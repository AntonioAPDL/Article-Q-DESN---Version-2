"""Causal-only R125 distribution pooling with position-stable chunk seeds."""
from __future__ import annotations

import numpy as np
from pricefm_r124_covariance import GaussianSampler
from pricefm_r125_cdf import pooled_quantiles
from pricefm_r126_contract import LEVELS, OPERATORS


def forecast(runtime, arrays, spec, normal, quantiles, positions, seed,
             observe=lambda value: None):
    positions = np.asarray(positions, dtype=int)
    if (len(positions) != len(arrays.response) or len(np.unique(positions)) != len(positions)
            or np.any(positions < 0) or sorted(quantiles) != list(LEVELS)):
        raise ValueError('unique original positions and seven fits required')
    engine = runtime.BASE; spec = runtime.normalize_spec(spec)
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    sampler = GaussianSampler(); seed_for = engine.deterministic_seed; paths = 500
    beta_n = sampler(normal['beta_mean'], normal['beta_cov'], paths, seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        normal['omega_shape'], 1 / normal['omega_rate'], size=paths)
    beta_q = {q: sampler(f['beta_mean'], f['beta_cov'], paths, seed_for(seed, 'quantile_beta', q))
              for q, f in quantiles.items()}
    out = {name: np.empty((len(positions), 96, 7)) for name in OPERATORS}
    for origin, position in enumerate(positions):
        states = [np.repeat(layer, paths, axis=0) for layer in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = np.empty((paths, 96))
        for h in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, generated[:, :h])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            innovation = np.random.default_rng(seed_for(seed, 'innovation', int(position), h)).standard_normal(paths)
            generated[:, h] = np.einsum('sp,sp->s', z, beta_n, optimize=True) + np.sqrt(omega) * innovation
            out['normal_driver'][origin, h] = np.quantile(generated[:, h], LEVELS)
            curves = np.column_stack([np.einsum('sp,sp->s', z, beta_q[q], optimize=True) for q in LEVELS])
            out['path_specific'][origin, h] = curves.mean(axis=0)
            out['rearranged_path_mean'][origin, h] = np.sort(curves, axis=1).mean(axis=0)
            out['mean_feature'][origin, h] = [np.mean(beta_q[q] @ z.mean(axis=0)) for q in LEVELS]
            for tails in ('clipped', 'linear'):
                out['cdf_pool_' + tails][origin, h] = pooled_quantiles(curves, tails)[0]
        observe(dict(origins_finished=origin + 1, origins_total=len(positions)))
    out['truth'] = np.asarray(arrays.response)
    return out, dict(sampler_audit=sampler.audit, paths=500,
        unknown_prices='generated_Normal_RHS_paths', oracle_inputs=False,
        teacher_forcing_between_origins=True, states_advance_each_step=True,
        conditional_quantile_coupling='independent_level_VB_draws',
        pooling='inverse_equal_weight_CDF_not_mean_conditional_quantiles',
        tails_identified_by_seven_levels=False, prior_changed=False)
