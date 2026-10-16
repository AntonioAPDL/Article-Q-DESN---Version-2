"""Scale-safe recursive forecasts with distinct Normal driver and AL receiver DESNs."""
from __future__ import annotations

import numpy as np


def _driver_to_receiver(values, driver_scaler, receiver_scaler):
    raw = values * float(driver_scaler['price_scale']) + float(driver_scaler['price_mean'])
    return (raw - float(receiver_scaler['price_mean'])) / float(receiver_scaler['price_scale'])


def forecast(runtime, receiver_arrays, receiver_spec, receiver_scaler,
             driver_arrays, driver_spec, driver_scaler, normal, quantiles,
             positions, seed, observe=lambda value: None, paths=500):
    """Advance driver and receiver states on one shared recursively generated price path.

    The Normal RHS driver emits standardized prices on its own training scale. Each
    draw is mapped through EUR/MWh into the receiver scale before entering the
    receiver target-lag vector. This makes cross-architecture driver comparisons
    valid even when their feature sets or training scalers differ.
    """
    from pricefm_r124_covariance import GaussianSampler
    from pricefm_r125_cdf import pooled_quantiles
    from pricefm_r126_contract import LEVELS, OPERATORS

    positions = np.asarray(positions, dtype=int)
    receiver_spec = runtime.normalize_spec(receiver_spec)
    driver_spec = runtime.normalize_spec(driver_spec)
    if (len(positions) != len(receiver_arrays.response)
            or len(positions) != len(driver_arrays.response)
            or len(np.unique(positions)) != len(positions)
            or np.any(positions < 0) or sorted(quantiles) != list(LEVELS)
            or int(paths) != 500):
        raise ValueError('aligned unique positions, seven fits, and 500 paths required')
    if not np.array_equal(receiver_arrays.anchors, driver_arrays.anchors):
        raise ValueError('driver and receiver origins differ')

    engine = runtime.BASE
    receiver_reservoir, receiver_config, _ = runtime.make_reservoir(
        receiver_spec, len(runtime.input_names(receiver_spec, receiver_arrays.exog_names)))
    driver_reservoir, driver_config, _ = runtime.make_reservoir(
        driver_spec, len(runtime.input_names(driver_spec, driver_arrays.exog_names)))
    sampler = GaussianSampler(); seed_for = engine.deterministic_seed
    beta_n = sampler(normal['beta_mean'], normal['beta_cov'], paths,
                     seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        normal['omega_shape'], 1 / normal['omega_rate'], size=paths)
    beta_q = {q: sampler(fit['beta_mean'], fit['beta_cov'], paths,
                         seed_for(seed, 'quantile_beta', q))
              for q, fit in quantiles.items()}
    output = {name: np.empty((len(positions), 96, len(LEVELS))) for name in OPERATORS}

    for origin, position in enumerate(positions):
        driver_states = [np.repeat(layer, paths, axis=0) for layer in
                         engine.initialize_states(driver_arrays, driver_spec,
                                                  driver_reservoir, driver_config, [origin])]
        receiver_states = [np.repeat(layer, paths, axis=0) for layer in
                           engine.initialize_states(receiver_arrays, receiver_spec,
                                                    receiver_reservoir, receiver_config, [origin])]
        generated_driver = np.empty((paths, 96))
        generated_receiver = np.empty((paths, 96))
        repeated = np.repeat(origin, paths)
        for horizon in range(96):
            driver_input = engine.explicit_input(
                driver_arrays, driver_spec, repeated, horizon, generated_driver[:, :horizon])
            driver_states = engine.reservoir_step(
                driver_states, driver_input, driver_reservoir, driver_config)
            driver_readout = engine.readout_rows(
                driver_states, driver_input, driver_spec['readout'])
            innovation = np.random.default_rng(
                seed_for(seed, 'innovation', int(position), horizon)).standard_normal(paths)
            generated_driver[:, horizon] = (
                np.einsum('sp,sp->s', driver_readout, beta_n, optimize=True)
                + np.sqrt(omega) * innovation)
            generated_receiver[:, horizon] = _driver_to_receiver(
                generated_driver[:, horizon], driver_scaler, receiver_scaler)

            receiver_input = engine.explicit_input(
                receiver_arrays, receiver_spec, repeated, horizon,
                generated_receiver[:, :horizon])
            receiver_states = engine.reservoir_step(
                receiver_states, receiver_input, receiver_reservoir, receiver_config)
            receiver_readout = engine.readout_rows(
                receiver_states, receiver_input, receiver_spec['readout'])
            output['normal_driver'][origin, horizon] = np.quantile(
                generated_receiver[:, horizon], LEVELS)
            curves = np.column_stack([
                np.einsum('sp,sp->s', receiver_readout, beta_q[q], optimize=True)
                for q in LEVELS])
            output['path_specific'][origin, horizon] = curves.mean(axis=0)
            output['rearranged_path_mean'][origin, horizon] = np.sort(curves, axis=1).mean(axis=0)
            output['mean_feature'][origin, horizon] = [
                np.mean(beta_q[q] @ receiver_readout.mean(axis=0)) for q in LEVELS]
            for tails in ('clipped', 'linear'):
                output['cdf_pool_' + tails][origin, horizon] = pooled_quantiles(curves, tails)[0]
        observe(dict(origins_finished=origin + 1, origins_total=len(positions)))

    output['truth'] = np.asarray(receiver_arrays.response)
    return output, dict(
        sampler_audit=sampler.audit,
        paths=paths,
        unknown_prices='generated_distinct_Normal_RHS_paths',
        driver_specification_distinct=driver_spec != receiver_spec,
        scale_transfer='driver_standardized_to_EUR_MWh_to_receiver_standardized',
        oracle_inputs=False,
        teacher_forcing_between_origins=True,
        states_advance_each_step=True,
        conditional_quantile_coupling='independent_level_VB_draws',
        pooling='inverse_equal_weight_CDF_not_mean_conditional_quantiles',
        tails_identified_by_seven_levels=False,
        prior_changed=False,
    )
