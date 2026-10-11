"""Forward-only calibration of a frozen stochastic Normal price driver."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

LEVELS = (.1, .25, .45, .5, .55, .75, .9)
CANDIDATES = ('identity', 'location', 'scale', 'location_scale')
FORBIDDEN = ('new_receiver_fitting_authorized', 'new_normal_fitting_authorized',
    'new_screening_authorized', 'official_test_reforecast_authorized',
    'selection_uses_r130_or_r131', 'selection_uses_official_test',
    'oracle_used_for_calibration', 'priors_from_initializers',
    'promotion_authorized', 'registry_mutation_authorized',
    'article_mutation_authorized', 'all_region_launch_authorized')


def validate_protocol(p):
    fixed = dict(regions=['HR', 'DK_1'], internal_splits=[1, 2, 3],
        forward_evaluation_splits=[2, 3], quantiles=list(LEVELS),
        calibration_candidates=list(CANDIDATES), paths=500, horizon_steps=96,
        step_minutes=15, origins_per_clock=12,
        origin_offsets_steps=[0, 24, 48, 72], maximum_workers=30,
        minimum_free_memory_GiB=200, minimum_free_disk_GiB=200,
        maximum_campaign_output_GiB=1.5, scale_bounds=[.5, 2.5],
        minimum_internal_improvement_fraction=.01,
        maximum_split_regression_fraction=.005,
        selection_metric='forward_internal_Normal_driver_AQL',
        receiver_operator='cdf_pool_clipped')
    for key, value in fixed.items():
        if p.get(key) != value:
            raise ValueError('frozen R132 protocol changed: ' + key)
    for key in FORBIDDEN:
        if p.get(key) is not False:
            raise ValueError('unauthorized R132 expansion: ' + key)


def _group_effect(values, groups, levels, prior_count):
    answer = np.zeros(levels, dtype=float)
    for group in range(levels):
        selected = values[np.asarray(groups) == group]
        if len(selected):
            answer[group] = selected.mean() * len(selected) / (len(selected) + prior_count)
    return answer


def flatten_packets(packets):
    required = ('truth', 'driver_mean', 'driver_sd', 'anchor_clock')
    for packet in packets:
        if any(key not in packet for key in required):
            raise ValueError('incomplete internal driver packet')
        n = len(packet['truth'])
        if (packet['truth'].shape != (n, 96) or packet['driver_mean'].shape != (n, 96)
                or packet['driver_sd'].shape != (n, 96)
                or np.asarray(packet['anchor_clock']).shape != (n,)):
            raise ValueError('internal driver packet geometry differs')
    truth = np.concatenate([p['truth'] for p in packets]).reshape(-1)
    mean = np.concatenate([p['driver_mean'] for p in packets]).reshape(-1)
    sd = np.concatenate([p['driver_sd'] for p in packets]).reshape(-1)
    anchor_clocks = np.concatenate([np.asarray(p['anchor_clock'], dtype=float)
                                    for p in packets])
    if (not np.isfinite(anchor_clocks).all()
            or not np.equal(anchor_clocks, np.floor(anchor_clocks)).all()
            or np.any((anchor_clocks < 0) | (anchor_clocks > 95))):
        raise ValueError('anchor clocks must be integer quarter-hours in [0, 95]')
    clocks = np.concatenate([clock[:, None] + np.arange(96, dtype=int)[None, :]
                             for clock in np.split(anchor_clocks.astype(int),
                                                   np.cumsum([len(p['truth']) for p in packets])[:-1])]
                           ).reshape(-1) % 96
    leads = np.tile(np.arange(96), sum(len(p['truth']) for p in packets))
    if not all(np.isfinite(v).all() for v in (truth, mean, sd)):
        raise ValueError('nonfinite internal driver moments')
    return truth, mean, sd, clocks // 4, leads // 24


def fit_calibration(packets, mode, protocol, training_splits):
    if mode not in CANDIDATES:
        raise ValueError('unknown calibration mode')
    truth, mean, sd, hour, block = flatten_packets(packets)
    use_location = mode in ('location', 'location_scale')
    use_scale = mode in ('scale', 'location_scale')
    residual = truth - mean
    global_bias = float(residual.mean()) if use_location else 0.
    hour_effect = np.zeros(24); block_effect = np.zeros(4)
    if use_location:
        hour_effect = _group_effect(residual - global_bias, hour, 24,
            protocol['location_hour_prior_count'])
        remainder = residual - global_bias - hour_effect[hour]
        block_effect = _group_effect(remainder, block, 4,
            protocol['location_lead_prior_count'])
    bias = global_bias + hour_effect[hour] + block_effect[block]
    block_scale = np.ones(4)
    if use_scale:
        floor = max(float(np.median(sd)) * .05, 1e-6)
        for value in range(4):
            chosen = block == value
            raw = np.sqrt(np.mean(((residual[chosen] - bias[chosen]) /
                                   np.maximum(sd[chosen], floor)) ** 2))
            weight = chosen.sum() / (chosen.sum() + protocol['scale_prior_count'])
            block_scale[value] = np.exp(weight * np.log(max(raw, 1e-8)))
        block_scale = np.clip(block_scale, *protocol['scale_bounds'])
    return dict(mode=mode, global_bias=global_bias, hour_effect=hour_effect.tolist(),
        lead_block_effect=block_effect.tolist(), lead_block_scale=block_scale.tolist(),
        training_splits=list(training_splits), observations=int(len(truth)), units='EUR/MWh',
        estimated_from_internal_driver_residuals_only=True)


def calibration_terms(calibration, anchor_clock, lead):
    hour = ((int(anchor_clock) + int(lead)) % 96) // 4
    block = int(lead) // 24
    bias = (float(calibration['global_bias']) + float(calibration['hour_effect'][hour])
            + float(calibration['lead_block_effect'][block]))
    return bias, float(calibration['lead_block_scale'][block])


def apply_calibration(values, calibration, anchor_clock, lead, price_scale=1.):
    values = np.asarray(values, dtype=float)
    if calibration['mode'] == 'identity':
        return values.copy()
    bias, scale = calibration_terms(calibration, anchor_clock, lead)
    center = values.mean()
    return center + bias / float(price_scale) + scale * (values - center)


def normal_driver_paths(runtime, arrays, spec, fit, positions, seed, calibration,
                        price_scale=1., observe=lambda value: None):
    from pricefm_r124_covariance import GaussianSampler

    positions = np.asarray(positions, dtype=int)
    if len(positions) != len(arrays.response) or len(set(positions)) != len(positions):
        raise ValueError('unique internal origin identities required')
    engine = runtime.BASE; spec = runtime.normalize_spec(spec); paths = 500
    sampler = GaussianSampler(); seed_for = engine.deterministic_seed
    beta = sampler(fit['beta_mean'], fit['beta_cov'], paths, seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        fit['omega_shape'], 1 / fit['omega_rate'], size=paths)
    reservoir, config, _ = runtime.make_reservoir(spec,
        len(runtime.input_names(spec, arrays.exog_names)))
    prediction = np.empty((len(positions), 96, len(LEVELS)))
    driver_mean = np.empty((len(positions), 96)); driver_sd = np.empty_like(driver_mean)
    anchors = pd.DatetimeIndex(pd.to_datetime(arrays.anchors, utc=True))
    anchor_clock = np.asarray(anchors.hour * 4 + anchors.minute // 15, dtype=int)
    for origin, position in enumerate(positions):
        states = [np.repeat(value, paths, axis=0) for value in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = np.empty((paths, 96))
        for lead in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), lead,
                generated[:, :lead])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            noise = np.random.default_rng(seed_for(seed, 'innovation', int(position), lead)).standard_normal(paths)
            value = np.einsum('sp,sp->s', z, beta, optimize=True) + np.sqrt(omega) * noise
            generated[:, lead] = apply_calibration(value, calibration, anchor_clock[origin],
                lead, price_scale)
            prediction[origin, lead] = np.quantile(generated[:, lead], LEVELS)
            driver_mean[origin, lead] = generated[:, lead].mean()
            driver_sd[origin, lead] = generated[:, lead].std()
            observe(dict(origin=int(position), origins_total=len(positions), horizon_finished=lead + 1))
    if not all(np.isfinite(v).all() for v in (prediction, driver_mean, driver_sd)):
        raise RuntimeError('nonfinite calibrated Normal driver')
    return dict(prediction=prediction, driver_mean=driver_mean,
        driver_sd=driver_sd, truth=np.asarray(arrays.response), anchor_clock=anchor_clock), {
            'sampler': sampler.audit, 'paths': paths, 'future_target_access': False,
            'teacher_forcing_between_origins': True, 'recursive_within_origin': True,
            'parameters_fixed_within_path': True, 'calibration_mode': calibration['mode']}


def internal_packet(runtime, regional_core, arrays, spec, fit, split, per_clock,
                    seed, calibration, price_scale, observe=lambda value: None):
    from pricefm_r127_contract import shifted_windows

    idx = split['validation']
    selected = np.unique(np.linspace(0, len(idx) - 2, per_clock).round().astype(int))
    packets = []
    for offset in (0, 24, 48, 72):
        shifted = shifted_windows(arrays, idx[selected], offset, idx)
        packet, _ = normal_driver_paths(runtime, shifted, spec, fit, selected,
            runtime.BASE.deterministic_seed(seed, 'clock', offset), calibration,
            price_scale=price_scale, observe=observe)
        packets.append(packet)
    return {key: np.concatenate([packet[key] for packet in packets]) for key in packets[0]}


def select_candidate(rows, protocol):
    frame = pd.DataFrame(rows)
    if (set(frame['candidate']) != set(CANDIDATES)
            or set(frame['split']) != set(protocol['forward_evaluation_splits'])
            or frame.duplicated(['candidate', 'split']).any()):
        raise ValueError('complete unique forward candidate surface required')
    baseline = frame[frame.candidate == 'identity'].set_index('split').AQL
    accepted = []
    for candidate in CANDIDATES[1:]:
        score = frame[frame.candidate == candidate].set_index('split').AQL
        improvement = 1 - score.mean() / baseline.mean()
        no_bad_split = bool(np.all(score <= baseline *
            (1 + protocol['maximum_split_regression_fraction'])))
        if improvement >= protocol['minimum_internal_improvement_fraction'] and no_bad_split:
            accepted.append((float(score.mean()), candidate, float(improvement)))
    selected = min(accepted)[1] if accepted else 'identity'
    ranking = frame.groupby('candidate', as_index=False).AQL.mean().sort_values(['AQL', 'candidate'])
    return dict(selected=selected, accepted=[v[1] for v in sorted(accepted)],
        ranking=ranking.to_dict('records'), identity_mean_AQL=float(baseline.mean()),
        selection_uses_only_forward_internal_splits=True)


def calibrated_receiver_replay(runtime, arrays, spec, quantiles, normal, positions,
                               seed, calibration, price_scale,
                               observe=lambda value: None):
    from pricefm_r124_covariance import GaussianSampler
    from pricefm_r125_cdf import pooled_quantiles

    positions = np.asarray(positions, dtype=int); paths = 500
    if (len(positions) != len(arrays.response) or len(set(positions)) != len(positions)
            or sorted(quantiles) != list(LEVELS)):
        raise ValueError('matched origins and seven frozen quantile fits required')
    engine = runtime.BASE; spec = runtime.normalize_spec(spec); seed_for = engine.deterministic_seed
    sampler = GaussianSampler()
    bq = {q: sampler(fit['beta_mean'], fit['beta_cov'], paths,
          seed_for(seed, 'quantile_beta', q)) for q, fit in quantiles.items()}
    bn = sampler(normal['beta_mean'], normal['beta_cov'], paths, seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        normal['omega_shape'], 1 / normal['omega_rate'], size=paths)
    reservoir, config, _ = runtime.make_reservoir(spec,
        len(runtime.input_names(spec, arrays.exog_names)))
    output = np.empty((len(positions), 96, 7)); means = np.empty((len(positions), 96)); sds = np.empty_like(means)
    anchors = pd.DatetimeIndex(pd.to_datetime(arrays.anchors, utc=True))
    clocks = np.asarray(anchors.hour * 4 + anchors.minute // 15, dtype=int)
    for origin, position in enumerate(positions):
        states = [np.repeat(value, paths, axis=0) for value in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = np.empty((paths, 96))
        for lead in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), lead,
                generated[:, :lead])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            curves = np.column_stack([np.einsum('sp,sp->s', z, bq[q], optimize=True)
                                      for q in LEVELS])
            output[origin, lead] = pooled_quantiles(curves, 'clipped')[0]
            noise = np.random.default_rng(seed_for(seed, 'innovation', int(position), lead)).standard_normal(paths)
            value = np.einsum('sp,sp->s', z, bn, optimize=True) + np.sqrt(omega) * noise
            generated[:, lead] = apply_calibration(value, calibration, clocks[origin], lead, price_scale)
            means[origin, lead] = generated[:, lead].mean(); sds[origin, lead] = generated[:, lead].std()
            observe(dict(origin_position=int(position), origins_total=len(positions), horizon_finished=lead + 1))
    return dict(calibrated=output, driver_mean=means, driver_sd=sds), dict(
        sampler=sampler.audit, future_target_access=False, paths=paths,
        teacher_forcing_between_origins=True, recursive_within_origin=True,
        receiver_fit_changed=False, normal_fit_changed=False,
        calibration_mode=calibration['mode'])


def plot_report(path, internal, heldout, driver, decisions):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False,
        'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .15,
        'pdf.fonttype': 42})
    colors = {'identity': '#087f8c', 'location': '#d1495b', 'scale': '#6741a5',
              'location_scale': '#228b22', 'stochastic': '#087f8c', 'calibrated': '#d1495b'}
    with PdfPages(path) as pdf:
        fig, ax = plt.subplots(figsize=(11.7, 8.3)); ax.axis('off')
        fig.suptitle('PriceFM R132 | Forward-only stochastic-driver calibration', fontsize=17, y=.94)
        rows = [[region, decisions[region]['selected'],
                 f"{heldout[(heldout.region == region) & (heldout.operator == 'stochastic')].AQL.mean():.3f}",
                 f"{heldout[(heldout.region == region) & (heldout.operator == 'calibrated')].AQL.mean():.3f}"]
                for region in ('DK_1', 'HR')]
        table = ax.table(cellText=rows, colLabels=['Region', 'Internal choice',
            'Held-out stochastic', 'Held-out calibrated'], cellLoc='center', bbox=[.04, .66, .92, .19])
        table.auto_set_font_size(False); table.set_fontsize(10)
        ax.text(.04, .57, 'Selection uses forward R128 internal validation only; held-out R130 results are descriptive.',
            transform=ax.transAxes)
        ax.text(.04, .48, 'No Normal or quantile refitting. S500 recursive paths and frozen AL-VB receivers.\n'
            'Identity is retained unless the prespecified internal gate passes.\n'
            'No official test reforecast, article replacement, or all-region rollout.\n'
            'Lower AQL is better; 80% coverage is reported with interval width.',
            va='top', linespacing=1.8, transform=ax.transAxes)
        pdf.savefig(fig); plt.close(fig)
        for region in ('DK_1', 'HR'):
            fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
            part = internal[internal.region == region]
            for candidate in CANDIDATES:
                curve = part[part.candidate == candidate].sort_values('split')
                axes[0].plot(curve.split, curve.AQL, marker='o', label=candidate.replace('_', ' '),
                    color=colors[candidate])
            axes[0].set_xticks([2, 3]); axes[0].set_xlabel('Forward internal evaluation split')
            axes[0].set_ylabel('Normal-driver AQL'); axes[0].legend(fontsize=8)
            h = heldout[heldout.region == region].groupby('operator').mean(numeric_only=True)
            axes[1].bar([0, 1], [h.loc['stochastic', 'AQL'], h.loc['calibrated', 'AQL']],
                color=[colors['stochastic'], colors['calibrated']])
            axes[1].set_xticks([0, 1], ['Stochastic', 'Calibrated']); axes[1].set_ylabel('Held-out receiver AQL')
            fig.suptitle(f'{region} | Internal selection and held-out receiver replay', fontsize=16)
            fig.tight_layout(rect=[0, 0, 1, .94]); pdf.savefig(fig); plt.close(fig)
            fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
            d = driver[driver.region == region]
            for operator in ('stochastic', 'calibrated'):
                curve = d[d.operator == operator].groupby('lead_step').MAE.mean()
                axes[0].plot(curve.index / 4, curve, color=colors[operator], label=operator)
            axes[0].set_xlabel('Hours ahead'); axes[0].set_ylabel('Driver MAE (EUR/MWh)'); axes[0].legend()
            c = heldout[heldout.region == region].groupby('operator').mean(numeric_only=True)
            axes[1].bar([0, 1], 100 * c.loc[['stochastic', 'calibrated'], 'coverage_80'],
                color=[colors['stochastic'], colors['calibrated']])
            axes[1].axhline(80, color='black', ls='--'); axes[1].set_ylim(0, 100)
            axes[1].set_xticks([0, 1], ['Stochastic', 'Calibrated']); axes[1].set_ylabel('80% coverage (%)')
            fig.suptitle(f'{region} | Driver error and receiver calibration', fontsize=16)
            fig.tight_layout(rect=[0, 0, 1, .94]); pdf.savefig(fig); plt.close(fig)
