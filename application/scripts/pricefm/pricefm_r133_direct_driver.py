"""Direct multi-horizon correction for a frozen stochastic Normal driver."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

LEVELS = (.1, .25, .45, .5, .55, .75, .9)
FAMILIES = ('identity', 'compact_location', 'compact_location_scale',
            'known_exog_location', 'known_exog_location_scale')
FORBIDDEN = ('new_receiver_fitting_authorized', 'new_normal_fitting_authorized',
    'new_screening_authorized', 'official_test_reforecast_authorized',
    'selection_uses_r130_or_r131_or_r132_heldout', 'selection_uses_official_test',
    'oracle_used_for_fitting', 'priors_from_initializers', 'promotion_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized',
    'all_region_launch_authorized')


def validate_protocol(p):
    fixed = dict(regions=['HR', 'DK_1'], internal_splits=[1, 2, 3],
        forward_evaluation_splits=[2, 3], quantiles=list(LEVELS),
        candidate_families=list(FAMILIES), ridge_penalties=[.1, 1., 10., 100.],
        history_lags=[1, 4, 96, 192, 672], paths=500, horizon_steps=96,
        step_minutes=15, origins_per_clock=12, origin_offsets_steps=[0, 24, 48, 72],
        maximum_workers=30, minimum_free_memory_GiB=200,
        minimum_free_disk_GiB=200, maximum_campaign_output_GiB=2.,
        first_horizon_replay_tolerance_EUR_MWh=5e-8,
        scale_prior_count=192, scale_bounds=[.5, 2.5],
        minimum_internal_improvement_fraction=.01,
        maximum_split_regression_fraction=.005,
        selection_metric='forward_internal_direct_driver_AQL',
        receiver_operator='cdf_pool_clipped', direct_driver_fit_authorized=True)
    for key, value in fixed.items():
        if p.get(key) != value:
            raise ValueError('frozen R133 protocol changed: ' + key)
    for key in FORBIDDEN:
        if p.get(key) is not False:
            raise ValueError('unauthorized R133 expansion: ' + key)


def _check_packet(packet, require_prediction=True):
    required = ('truth', 'driver_mean', 'driver_sd', 'anchor_clock',
                'history_lags', 'exog_future')
    if require_prediction:
        required += ('prediction',)
    if any(key not in packet for key in required):
        raise ValueError('incomplete direct-driver packet')
    n = len(packet['truth'])
    expected = dict(truth=(n, 96), driver_mean=(n, 96), driver_sd=(n, 96),
        anchor_clock=(n,), history_lags=(n, 5))
    if require_prediction:
        expected['prediction'] = (n, 96, 7)
    for key, shape in expected.items():
        if np.asarray(packet[key]).shape != shape:
            raise ValueError(f'direct-driver packet geometry differs: {key}')
    if np.asarray(packet['exog_future']).shape[:2] != (n, 96):
        raise ValueError('direct-driver exogenous geometry differs')
    if not all(np.isfinite(np.asarray(packet[key])).all() for key in required):
        raise ValueError('nonfinite direct-driver packet')


def augment_packet(arrays, packet, history_lags=(1, 4, 96, 192, 672)):
    answer = {key: np.asarray(value) for key, value in packet.items()}
    n = len(answer['truth'])
    if len(arrays.response) != n or arrays.price_history.shape[1] < max(history_lags):
        raise ValueError('array support is incompatible with direct-driver features')
    answer['history_lags'] = np.column_stack(
        [arrays.price_history[:, -int(lag)] for lag in history_lags])
    answer['exog_future'] = np.asarray(arrays.exog_future)
    _check_packet(answer, require_prediction='prediction' in answer)
    return answer


def concatenate_packets(packets):
    if not packets:
        raise ValueError('at least one packet required')
    for packet in packets:
        _check_packet(packet)
    keys = packets[0].keys()
    if any(packet.keys() != keys for packet in packets):
        raise ValueError('packet keys differ')
    return {key: np.concatenate([packet[key] for packet in packets]) for key in keys}


def feature_matrix(packet, family):
    if family == 'identity' or family not in FAMILIES:
        raise ValueError('nonidentity declared family required')
    _check_packet(packet, require_prediction=False)
    mean = np.asarray(packet['driver_mean']); sd = np.maximum(packet['driver_sd'], 1e-8)
    n = len(mean); lead = np.arange(96)[None, :]
    clock = (np.asarray(packet['anchor_clock'])[:, None] + lead) % 96
    block = np.broadcast_to(lead // 24, (n, 96)).astype(int)
    blocks = np.eye(4)[block.reshape(-1)]
    mean_flat = mean.reshape(-1, 1); log_sd = np.log(sd).reshape(-1, 1)
    history = np.repeat(np.asarray(packet['history_lags'])[:, None, :], 96, axis=1).reshape(n * 96, 5)
    parts = [mean_flat, log_sd, history,
        np.sin(2 * np.pi * clock / 96).reshape(-1, 1),
        np.cos(2 * np.pi * clock / 96).reshape(-1, 1),
        np.broadcast_to(lead / 95, (n, 96)).reshape(-1, 1),
        np.broadcast_to((lead / 95) ** 2, (n, 96)).reshape(-1, 1),
        blocks[:, 1:]]
    parts.extend(mean_flat * blocks[:, [value]] for value in range(1, 4))
    parts.extend(log_sd * blocks[:, [value]] for value in range(1, 4))
    if family.startswith('known_exog'):
        parts.append(np.asarray(packet['exog_future']).reshape(n * 96, -1))
    result = np.column_stack(parts)
    if not np.isfinite(result).all():
        raise ValueError('nonfinite direct-driver feature matrix')
    return result


def fit_direct_map(packets, family, ridge_penalty, protocol, training_splits):
    if family == 'identity':
        return dict(family='identity', ridge_penalty=None, training_splits=list(training_splits),
            feature_dimension=0, scale=[1.] * 4, units='training_standardized')
    if family not in FAMILIES or ridge_penalty not in protocol['ridge_penalties']:
        raise ValueError('undeclared direct-driver candidate')
    for packet in packets:
        _check_packet(packet)
    x = np.vstack([feature_matrix(packet, family) for packet in packets])
    y = np.concatenate([np.asarray(packet['truth']).reshape(-1) for packet in packets])
    center = x.mean(axis=0); spread = x.std(axis=0); spread[spread < 1e-10] = 1.
    z = (x - center) / spread
    design = np.column_stack((np.ones(len(z)), z))
    penalty = np.eye(design.shape[1]) * float(ridge_penalty); penalty[0, 0] = 1e-10
    precision = design.T @ design + penalty
    try:
        beta = np.linalg.solve(precision, design.T @ y)
    except np.linalg.LinAlgError:
        beta = np.linalg.solve(precision + np.eye(len(precision)) * 1e-8, design.T @ y)
    scale = np.ones(4)
    if family.endswith('_scale'):
        residual = y - design @ beta
        base_sd = np.concatenate([packet['driver_sd'].reshape(-1) for packet in packets])
        lead_block = np.tile(np.arange(96) // 24, sum(len(packet['truth']) for packet in packets))
        for value in range(4):
            selected = lead_block == value
            raw = np.sqrt(np.mean(residual[selected] ** 2)) / max(
                np.sqrt(np.mean(base_sd[selected] ** 2)), 1e-8)
            weight = selected.sum() / (selected.sum() + protocol['scale_prior_count'])
            scale[value] = np.exp(weight * np.log(max(raw, 1e-8)))
        scale = np.clip(scale, *protocol['scale_bounds'])
    return dict(family=family, ridge_penalty=float(ridge_penalty),
        center=center.tolist(), spread=spread.tolist(), beta=beta.tolist(),
        scale=scale.tolist(), training_splits=list(training_splits),
        observations=int(len(y)), feature_dimension=int(x.shape[1]),
        units='training_standardized', direct_complete_path=True,
        baseline_generator_feedback=False)


def direct_location(packet, model):
    if model['family'] == 'identity':
        return np.asarray(packet['driver_mean']).copy()
    x = feature_matrix(packet, model['family'])
    center = np.asarray(model['center']); spread = np.asarray(model['spread'])
    beta = np.asarray(model['beta'])
    if x.shape[1] != len(center) or len(center) + 1 != len(beta):
        raise ValueError('direct map feature identity differs')
    return (np.column_stack((np.ones(len(x)), (x - center) / spread)) @ beta).reshape(
        np.asarray(packet['driver_mean']).shape)


def direct_quantiles(packet, model):
    _check_packet(packet)
    if model['family'] == 'identity':
        return np.asarray(packet['prediction']).copy()
    location = direct_location(packet, model)
    scale = np.asarray(model['scale'])[np.arange(96) // 24][None, :, None]
    result = location[..., None] + scale * (
        np.asarray(packet['prediction']) - np.asarray(packet['driver_mean'])[..., None])
    if not np.isfinite(result).all() or np.any(np.diff(result, axis=-1) < -1e-10):
        raise RuntimeError('invalid direct-driver quantiles')
    return result


def direct_paths(packet, baseline_paths, model):
    baseline_paths = np.asarray(baseline_paths)
    if baseline_paths.shape[:2] != np.asarray(packet['driver_mean']).shape:
        raise ValueError('baseline path geometry differs')
    if model['family'] == 'identity':
        return baseline_paths.copy()
    location = direct_location(packet, model)
    scale = np.asarray(model['scale'])[np.arange(96) // 24][None, :, None]
    result = location[..., None] + scale * (
        baseline_paths - np.asarray(packet['driver_mean'])[..., None])
    if not np.isfinite(result).all():
        raise RuntimeError('nonfinite direct-driver paths')
    return result


def average_quantile_loss(truth, prediction):
    error = np.asarray(truth)[..., None] - np.asarray(prediction)
    levels = np.asarray(LEVELS)
    return float(np.mean(np.maximum(levels * error, (levels - 1) * error)))


def select_candidate(rows, protocol):
    frame = pd.DataFrame(rows)
    baseline = frame[frame.candidate_id.eq('identity')].set_index('split').AQL
    if set(baseline.index) != set(protocol['forward_evaluation_splits']):
        raise ValueError('complete identity forward surface required')
    accepted = []
    for candidate, group in frame[~frame.candidate_id.eq('identity')].groupby('candidate_id'):
        score = group.set_index('split').AQL
        if set(score.index) != set(baseline.index) or len(group) != len(baseline):
            raise ValueError('complete unique forward candidate surface required')
        improvement = 1 - score.mean() / baseline.mean()
        no_bad_split = bool(np.all(score <= baseline *
            (1 + protocol['maximum_split_regression_fraction'])))
        if improvement >= protocol['minimum_internal_improvement_fraction'] and no_bad_split:
            first = group.iloc[0]
            accepted.append((float(score.mean()), int(first.feature_dimension),
                bool(first.scale_enabled), -float(first.ridge_penalty), candidate,
                float(improvement)))
    chosen = min(accepted)[4] if accepted else 'identity'
    ranking = frame.groupby('candidate_id', as_index=False).agg(
        mean_AQL=('AQL', 'mean'), family=('family', 'first'),
        ridge_penalty=('ridge_penalty', 'first'), feature_dimension=('feature_dimension', 'first'),
        scale_enabled=('scale_enabled', 'first')).sort_values(['mean_AQL', 'candidate_id'])
    records = ranking.to_dict('records')
    for record in records:
        if pd.isna(record['ridge_penalty']):
            record['ridge_penalty'] = None
    return dict(selected=chosen, accepted=[value[4] for value in sorted(accepted)],
        ranking=records, identity_mean_AQL=float(baseline.mean()),
        selection_uses_only_forward_internal_splits=True)


def replay_receiver(runtime, arrays, spec, quantiles, normal, positions, seed, model,
                    observe=lambda value: None):
    """Generate the baseline path, transform it once, then run frozen receivers."""
    from pricefm_r124_covariance import GaussianSampler
    from pricefm_r125_cdf import pooled_quantiles

    positions = np.asarray(positions, dtype=int); paths = 500
    if len(positions) != len(arrays.response) or sorted(quantiles) != list(LEVELS):
        raise ValueError('matching origins and seven quantile fits required')
    engine = runtime.BASE; spec = runtime.normalize_spec(spec); seed_for = engine.deterministic_seed
    sampler = GaussianSampler()
    bn = sampler(normal['beta_mean'], normal['beta_cov'], paths, seed_for(seed, 'normal_beta'))
    omega = 1 / np.random.default_rng(seed_for(seed, 'normal_sigma')).gamma(
        normal['omega_shape'], 1 / normal['omega_rate'], size=paths)
    bq = {q: sampler(fit['beta_mean'], fit['beta_cov'], paths,
          seed_for(seed, 'quantile_beta', q)) for q, fit in quantiles.items()}
    reservoir, config, _ = runtime.make_reservoir(spec,
        len(runtime.input_names(spec, arrays.exog_names)))
    baseline = np.empty((len(positions), 96, paths))
    for origin, position in enumerate(positions):
        states = [np.repeat(value, paths, axis=0) for value in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = baseline[origin].T
        for lead in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), lead,
                generated[:, :lead])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            noise = np.random.default_rng(seed_for(seed, 'innovation', int(position), lead)).standard_normal(paths)
            generated[:, lead] = np.einsum('sp,sp->s', z, bn, optimize=True) + np.sqrt(omega) * noise
            observe(dict(stage='baseline', origin=int(position), origins_total=len(positions),
                         horizon_finished=lead + 1))
    clocks = pd.DatetimeIndex(pd.to_datetime(arrays.anchors, utc=True))
    packet = augment_packet(arrays, dict(truth=np.asarray(arrays.response),
        driver_mean=baseline.mean(axis=2), driver_sd=baseline.std(axis=2),
        anchor_clock=np.asarray(clocks.hour * 4 + clocks.minute // 15, dtype=int)))
    corrected = direct_paths(packet, baseline, model)
    output = np.empty((len(positions), 96, 7))
    for origin, position in enumerate(positions):
        states = [np.repeat(value, paths, axis=0) for value in
                  engine.initialize_states(arrays, spec, reservoir, config, [origin])]
        generated = corrected[origin].T
        for lead in range(96):
            u = engine.explicit_input(arrays, spec, np.repeat(origin, paths), lead,
                generated[:, :lead])
            states = engine.reservoir_step(states, u, reservoir, config)
            z = engine.readout_rows(states, u, spec['readout'])
            curves = np.column_stack([np.einsum('sp,sp->s', z, bq[q], optimize=True)
                                      for q in LEVELS])
            output[origin, lead] = pooled_quantiles(curves, 'clipped')[0]
            observe(dict(stage='receiver', origin=int(position), origins_total=len(positions),
                         horizon_finished=lead + 1))
    return dict(direct=output, baseline_driver_mean=baseline.mean(axis=2),
        baseline_driver_sd=baseline.std(axis=2), direct_driver_mean=corrected.mean(axis=2),
        direct_driver_sd=corrected.std(axis=2)), dict(sampler=sampler.audit, paths=paths,
        future_target_access=False, teacher_forcing_between_origins=True,
        baseline_recursive_within_origin=True, direct_complete_path=True,
        baseline_generator_feedback=False, receiver_fit_changed=False,
        normal_fit_changed=False, direct_family=model['family'])


def plot_report(path, internal, heldout, driver, decisions):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False,
        'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .15,
        'pdf.fonttype': 42})
    colors = {'stochastic': '#087f8c', 'direct': '#d1495b'}
    with PdfPages(path) as pdf:
        fig, ax = plt.subplots(figsize=(11.7, 8.3)); ax.axis('off')
        fig.suptitle('PriceFM R133 | Decoupled direct multi-horizon driver', fontsize=17, y=.94)
        rows = []
        for region in ('DK_1', 'HR'):
            part = heldout[heldout.region.eq(region)].groupby('operator').AQL.mean()
            rows.append([region, decisions[region]['selected'],
                f"{part.get('stochastic', np.nan):.3f}", f"{part.get('direct', np.nan):.3f}"])
        table = ax.table(cellText=rows, colLabels=['Region', 'Internal choice',
            'Held-out stochastic', 'Held-out direct'], cellLoc='center', bbox=[.03, .67, .94, .18])
        table.auto_set_font_size(False); table.set_fontsize(10)
        ax.text(.03, .58, 'Map selection uses forward internal splits only; held-out receiver scores are descriptive.',
            transform=ax.transAxes)
        ax.text(.03, .49, 'The complete baseline stochastic path is generated first.\n'
            'The direct map then changes location/dispersion without feedback into that generator.\n'
            'Frozen independent AL-VB receivers consume the resulting path; S500 and H96.\n'
            'No DESN/Normal/quantile refit, official-test selection, promotion or broad rollout.',
            va='top', linespacing=1.8, transform=ax.transAxes)
        pdf.savefig(fig); plt.close(fig)
        for region in ('DK_1', 'HR'):
            fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
            part = internal[internal.region.eq(region)]
            best = part.groupby('candidate_id').AQL.mean().nsmallest(8).index
            shown = part[part.candidate_id.isin(best)]
            for candidate, values in shown.groupby('candidate_id'):
                axes[0].plot(values.split, values.AQL, marker='o', label=candidate)
            axes[0].set_xticks([2, 3]); axes[0].set_xlabel('Forward internal split')
            axes[0].set_ylabel('Driver AQL'); axes[0].legend(fontsize=6)
            part = heldout[heldout.region.eq(region)].groupby('operator').mean(numeric_only=True)
            axes[1].bar([0, 1], part.loc[['stochastic', 'direct'], 'AQL'],
                color=[colors['stochastic'], colors['direct']])
            axes[1].set_xticks([0, 1], ['Stochastic', 'Direct']); axes[1].set_ylabel('Held-out receiver AQL')
            fig.suptitle(f'{region} | Forward selection and held-out replay', fontsize=16)
            fig.tight_layout(rect=[0, 0, 1, .94]); pdf.savefig(fig); plt.close(fig)
            fig, ax = plt.subplots(figsize=(11.7, 8.3))
            part = driver[driver.region.eq(region)]
            for operator in ('stochastic', 'direct'):
                curve = part[part.operator.eq(operator)].groupby('lead_step').MAE.mean()
                ax.plot(curve.index / 4, curve, color=colors[operator], label=operator)
            ax.set_xlabel('Hours ahead'); ax.set_ylabel('Driver MAE (EUR/MWh)'); ax.legend()
            ax.set_title(f'{region} | Endogenous price-driver error by lead')
            fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
