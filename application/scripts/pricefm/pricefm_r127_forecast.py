"""Same-fit oracle and Normal-driver controls; no posterior target or fit changes."""
import numpy as np

from pricefm_r124_covariance import GaussianSampler, covariance_factor
from pricefm_r125_cdf import pooled_quantiles
from pricefm_r126_contract import LEVELS
from pricefm_r127_contract import variance_terms

MODES = ('stochastic', 'parameter_only', 'mean_driver')


def replay(runtime, arrays, spec, quantiles, positions, seed, normal=None,
           oracle_only=False, observe=lambda value: None, cached=None):
    positions = np.asarray(positions, dtype=int)
    if (len(positions) != len(arrays.response) or len(set(positions)) != len(positions)
            or np.any(positions < 0) or sorted(quantiles) != list(LEVELS)):
        raise ValueError('unique positions and seven quantile fits required')
    engine = runtime.BASE; spec = runtime.normalize_spec(spec)
    if spec['calendar'] != 'none' or spec['readout'] != 'pure_all_layers':
        raise ValueError('frozen pure all-layer no-calendar receiver required')
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    sampler = GaussianSampler(); seed_for = engine.deterministic_seed; paths = 500
    bq = {q: sampler(f['beta_mean'], f['beta_cov'], paths, seed_for(seed, 'quantile_beta', q))
          for q, f in quantiles.items()}
    if not oracle_only:
        if normal is None: raise ValueError('Normal fit required for causal controls')
        bn = sampler(normal['beta_mean'], normal['beta_cov'], paths, seed_for(seed, 'normal_beta'))
        omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
            normal['omega_shape'], 1 / normal['omega_rate'], size=paths)
    modes = () if oracle_only else MODES
    median_factor = None if oracle_only else covariance_factor(quantiles[.5]['beta_cov'])[0]
    out = {name: np.empty((len(positions), 96, 7)) for name in (*modes, 'oracle')}
    cached = {} if cached is None else cached
    for key, value in cached.items():
        if key not in ('oracle', 'stochastic') or np.asarray(value).shape != out[key].shape or not np.isfinite(value).all():
            raise ValueError('matching finite frozen oracle/causal forecasts required')
    # Compact moment summaries, never the S x H x P reservoir bank.
    stats = {name: np.empty((len(positions), 96, len(modes)))
             for name in ('driver_mean', 'driver_sd')}
    layer_stats = {name: np.empty((len(positions), 96, len(modes), spec['depth']))
        for name in ('state_mean', 'state_variance', 'state_oracle_rmse', 'saturated_fraction', 'near_linear_fraction')}
    var = np.zeros((len(positions), 96, len(modes), 3))
    var_mask = np.zeros(96, dtype=bool); var_mask[[0, 23, 47, 71, 95]] = True
    sensitivity = np.empty((len(positions), 96, len(arrays.exog_names), spec['depth']))
    origin_zero_differences = []
    for origin, position in enumerate(positions):
        initial = engine.initialize_states(arrays, spec, reservoir, config, [origin])
        oracle_states = [x.copy() for x in initial]
        banks = {mode: [np.repeat(x, paths if mode != 'mean_driver' else 1, axis=0)
                        for x in initial] for mode in modes}
        generated = {mode: np.empty((paths if mode != 'mean_driver' else 1, 96)) for mode in modes}
        for h in range(96):
            uo = engine.explicit_input(arrays, spec, [origin], h, arrays.response[origin:origin + 1, :h])
            before = oracle_states
            oracle_states = engine.reservoir_step(before, uo, reservoir, config)
            zo = engine.readout_rows(oracle_states, uo, spec['readout'])[0]
            oracle_curves = np.column_stack([bq[q] @ zo for q in LEVELS])
            if 'oracle' not in cached or h == 0:
                out['oracle'][origin, h] = pooled_quantiles(oracle_curves, 'clipped')[0]
                if 'oracle' in cached and not np.allclose(out['oracle'][origin, h], cached['oracle'][origin, h], rtol=2e-12, atol=1e-9):
                    raise RuntimeError('frozen oracle control differs')
            else: out['oracle'][origin, h] = cached['oracle'][origin, h]
            if not oracle_only:
                for channel in range(len(arrays.exog_names)):
                    changed = uo.copy(); changed[0, spec['m_y'] + channel] += 1
                    perturbed = engine.reservoir_step(before, changed, reservoir, config)
                    sensitivity[origin, h, channel] = [float(np.sqrt(np.mean((a - b)**2)))
                        for a, b in zip(perturbed, oracle_states)]
            for mi, mode in enumerate(modes):
                count = generated[mode].shape[0]
                u = engine.explicit_input(arrays, spec, np.repeat(origin, count), h, generated[mode][:, :h])
                banks[mode] = engine.reservoir_step(banks[mode], u, reservoir, config)
                z = engine.readout_rows(banks[mode], u, spec['readout'])
                if mode == 'mean_driver':
                    generated[mode][:, h] = z @ normal['beta_mean']
                    curves = np.column_stack([bq[q] @ z[0] for q in LEVELS])
                else:
                    value = np.einsum('sp,sp->s', z, bn, optimize=True)
                    if mode == 'stochastic':
                        eps = np.random.default_rng(seed_for(seed, 'innovation', int(position), h)).standard_normal(paths)
                        value += np.sqrt(omega) * eps
                    generated[mode][:, h] = value
                    curves = np.column_stack([np.einsum('sp,sp->s', z, bq[q], optimize=True) for q in LEVELS])
                if mode not in cached or h == 0:
                    out[mode][origin, h] = pooled_quantiles(curves, 'clipped')[0]
                    if mode in cached and not np.allclose(out[mode][origin, h], cached[mode][origin, h], rtol=2e-12, atol=1e-9):
                        raise RuntimeError('frozen stochastic control differs')
                else: out[mode][origin, h] = cached[mode][origin, h]
                stats['driver_mean'][origin, h, mi] = generated[mode][:, h].mean()
                stats['driver_sd'][origin, h, mi] = generated[mode][:, h].std()
                for li, (state, target) in enumerate(zip(banks[mode], oracle_states)):
                    layer_stats['state_mean'][origin, h, mi, li] = state.mean()
                    layer_stats['state_variance'][origin, h, mi, li] = state.var(axis=0).mean()
                    layer_stats['state_oracle_rmse'][origin, h, mi, li] = np.sqrt(np.mean((state.mean(axis=0) - target[0])**2))
                    layer_stats['saturated_fraction'][origin, h, mi, li] = np.mean(abs(state) > .95)
                    layer_stats['near_linear_fraction'][origin, h, mi, li] = np.mean(abs(state) < .1)
                if var_mask[h]:
                    var[origin, h, mi] = variance_terms(z, quantiles[.5]['beta_mean'], quantiles[.5]['beta_cov'], median_factor)
                if h == 0:
                    delta = float(np.max(abs(out[mode][origin, h] - out['oracle'][origin, h])))
                    origin_zero_differences.append(delta)
                    if delta > 1e-8: raise RuntimeError('first-step common-readout identity failed')
            observe(dict(origin_position=int(position), origin_number=origin + 1,
                         origins_total=len(positions), horizon_finished=h + 1))
    if not all(np.isfinite(v).all() for v in out.values()): raise RuntimeError('nonfinite diagnostic forecasts')
    out['truth'] = np.asarray(arrays.response)
    if not oracle_only:
        out.update(stats, **layer_stats, median_variance_terms=var,
                   variance_lead_mask=var_mask, oracle_current_exog_sensitivity=sensitivity)
    return out, dict(sampler_audit=sampler.audit, modes=list(modes), paths=paths,
        oracle_diagnostic_only=True, oracle_price_lags='exact observed prefix strictly before each horizon',
        prior_changed=False, fitting_performed=False, quantile_parameter_draws_common_across_controls=True,
        fixed_normal_beta_and_omega_per_path=True, teacher_forcing_between_origins=True,
        mean_driver='recursive Normal beta mean with zero innovations, not mean stochastic readout',
        current_exog_sensitivity='one inner-standardized unit local perturbation with past oracle states held fixed',
        variance_terms='median raw receiver location, independent empirical state distribution; not pooled price CDF variance',
        variance_leads=[1, 24, 48, 72, 96], max_h0_difference=max(origin_zero_differences, default=0.))
