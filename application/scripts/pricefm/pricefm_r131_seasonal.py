"""Causal seasonal price drivers for frozen pure-DESN quantile receivers."""
from pathlib import Path

import numpy as np
import pandas as pd

MODES = ('previous_day', 'previous_week')
PERIODS = (96, 672)
LEVELS = (.1, .25, .45, .5, .55, .75, .9)
CACHED = ('stochastic', 'parameter_only', 'mean_driver', 'oracle')
FORBIDDEN = ('new_fitting_authorized', 'new_screening_authorized',
    'test_reforecast_authorized', 'automatic_model_selection_authorized',
    'selection_uses_test', 'priors_from_initializers', 'promotion_authorized',
    'registry_mutation_authorized', 'article_mutation_authorized',
    'all_region_launch_authorized')


def validate_protocol(p):
    fixed = dict(regions=['HR', 'DK_1'], folds=[1, 2, 3], quantiles=list(LEVELS),
        controls=list(MODES), seasonal_periods_steps=list(PERIODS), paths=500,
        horizon_steps=96, step_minutes=15, maximum_workers=30,
        minimum_free_memory_GiB=200, minimum_free_disk_GiB=200,
        maximum_campaign_output_GiB=.5, primary_operator='cdf_pool_clipped',
        oracle_diagnostic_only=True,
        parent_head='cff723f900372bbeee22500e6c917fdd241e7557')
    for key, value in fixed.items():
        if p.get(key) != value:
            raise ValueError('frozen seasonal protocol changed: ' + key)
    for key in FORBIDDEN:
        if p.get(key) is not False:
            raise ValueError('unauthorized scientific expansion: ' + key)


def seasonal_path(history, period, horizon=96):
    history = np.asarray(history, dtype=float)
    if (history.ndim != 2 or period not in PERIODS or horizon != 96
            or history.shape[1] < period):
        raise ValueError('complete available quarter-hour seasonal history required')
    indices = history.shape[1] + np.arange(horizon) - period
    if np.any(indices < 0) or np.any(indices >= history.shape[1]):
        raise ValueError('seasonal source is not strictly before the origin')
    result = history[:, indices]
    if not np.isfinite(result).all():
        raise ValueError('nonfinite seasonal history')
    return result


def replay(runtime, arrays, spec, quantiles, positions, seed, observe=lambda value: None):
    from pricefm_r124_covariance import GaussianSampler
    from pricefm_r125_cdf import pooled_quantiles

    positions = np.asarray(positions, dtype=int)
    if (len(positions) != len(arrays.anchors) or len(set(positions)) != len(positions)
            or np.any(positions < 0) or sorted(quantiles) != list(LEVELS)):
        raise ValueError('unique matched origin identities and seven quantiles required')
    spec = runtime.normalize_spec(spec)
    if spec['calendar'] != 'none' or spec['readout'] != 'pure_all_layers':
        raise ValueError('unchanged pure all-layer no-calendar receiver required')
    engine = runtime.BASE
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    sampler = GaussianSampler()
    draws = {q: sampler(f['beta_mean'], f['beta_cov'], 500,
        engine.deterministic_seed(seed, 'quantile_beta', q)) for q, f in quantiles.items()}
    n = len(positions)
    result = {mode: np.empty((n, 96, 7)) for mode in MODES}
    drivers = np.stack([seasonal_path(arrays.price_history, period) for period in PERIODS], axis=-1)
    for origin, position in enumerate(positions):
        initial = engine.initialize_states(arrays, spec, reservoir, config, [origin])
        states = {mode: [z.copy() for z in initial] for mode in MODES}
        for h in range(96):
            for mi, mode in enumerate(MODES):
                generated = drivers[origin:origin + 1, :h, mi]
                u = engine.explicit_input(arrays, spec, [origin], h, generated)
                states[mode] = engine.reservoir_step(states[mode], u, reservoir, config)
                z = engine.readout_rows(states[mode], u, spec['readout'])[0]
                curves = np.column_stack([draws[q] @ z for q in LEVELS])
                result[mode][origin, h] = pooled_quantiles(curves, 'clipped')[0]
            observe(dict(origin_position=int(position), origin_number=origin + 1,
                origins_total=n, horizon_finished=h + 1))
    if not all(np.isfinite(v).all() for v in result.values()):
        raise RuntimeError('nonfinite causal seasonal forecasts')
    result['seasonal_driver'] = drivers
    return result, dict(sampler_audit=sampler.audit, paths=500, modes=list(MODES),
        fitting_performed=False, prior_changed=False, future_target_access=False,
        teacher_forcing_between_origins=True, recursive_within_origin=True,
        deterministic_driver=True, coefficient_uncertainty_retained=True,
        single_state_equivalent_to_500_duplicated_states=True,
        source_offsets_steps=[-96, -672], parameters_fixed_within_path=True,
        quantile_parameter_draws_common_with_r130=True)


def validate_cached(values, arrays, task, scaler):
    expected_truth = arrays.response * scaler['price_scale'] + scaler['price_mean']
    if not np.array_equal(values['bank_indices'], task['bank_indices']):
        raise ValueError('cached origin indices differ')
    if not np.array_equal(values['positions'], task['positions']):
        raise ValueError('cached seed identities differ')
    anchors = pd.DatetimeIndex(pd.to_datetime(arrays.anchors, utc=True)).as_unit('ns').asi8
    if not np.array_equal(values['anchors_ns'], anchors):
        raise ValueError('cached anchor timestamps differ')
    if not np.array_equal(values['truth'], expected_truth):
        raise ValueError('cached truth or inverse scaling differs')
    for key in CACHED:
        if values[key].shape != (*expected_truth.shape, 7) or not np.isfinite(values[key]).all():
            raise ValueError('incomplete cached control: ' + key)


def first_step_check(values):
    difference = max(float(np.max(abs(values[mode][:, 0] - values['stochastic'][:, 0])))
                     for mode in MODES)
    if difference > 1e-8:
        raise RuntimeError('common first-step seasonal/stochastic identity failed')
    return difference


def aggregate_packets(packets, grid):
    keys = ('bank_indices', 'positions', 'anchors_ns', 'truth', *MODES, *CACHED,
            'seasonal_driver', 'normal_driver_mean', 'normal_driver_sd')
    values = {k: np.concatenate([v[k] for v in packets]) for k in keys}
    order = np.argsort(values['bank_indices'])
    values = {k: v[order] for k, v in values.items()}
    if not np.array_equal(values['bank_indices'], np.arange(len(grid))):
        raise ValueError('missing or duplicate origins')
    if not np.array_equal(values['positions'], [v['position'] for v in grid]):
        raise ValueError('completed seed identities differ')
    anchors = pd.DatetimeIndex(pd.to_datetime([v['anchor'] for v in grid], utc=True)).as_unit('ns').asi8
    if not np.array_equal(values['anchors_ns'], anchors):
        raise ValueError('completed timestamps differ')
    return values


def metrics(values, cell, common_metrics):
    rows, leads, driver_rows = [], [], []
    modes = (*CACHED, *MODES)
    for clock in (0, 24, 48, 72):
        idx = [i for i, row in enumerate(cell['grid']) if row['offset'] == clock]
        truth = values['truth'][idx]
        for mode in modes:
            forecast = values[mode][idx]
            rows.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=clock,
                operator=mode, **common_metrics(truth, forecast)))
            error = truth[:, :, None] - forecast
            loss = np.maximum(np.array(LEVELS) * error, (np.array(LEVELS) - 1) * error)
            for h in range(96):
                leads.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=clock,
                    operator=mode, lead_step=h + 1, target_clock_step=(clock + h) % 96,
                    AQL=float(loss[:, h].mean())))
        for mi, mode in enumerate(('stochastic', *MODES)):
            mean = values['normal_driver_mean'][idx] if mi == 0 else values['seasonal_driver'][idx, :, mi - 1]
            error = mean - truth
            for h in range(96):
                driver_rows.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=clock,
                    operator=mode, lead_step=h + 1, target_clock_step=(clock + h) % 96,
                    bias=float(error[:, h].mean()), MAE=float(abs(error[:, h]).mean()),
                    RMSE=float(np.sqrt(np.mean(error[:, h]**2))),
                    driver_sd=float(values['normal_driver_sd'][idx, h].mean()) if mi == 0 else 0.))
    return rows, leads, driver_rows


def choose_physical_cpus(allowed, topology, utilization, count, reserve=2):
    if not 1 <= count <= 30:
        raise ValueError('physical worker cap is 30')
    groups = {}
    for cpu, group in topology.items():
        groups.setdefault(group, []).append(cpu)
    capacity = max(0, len(groups) - reserve)
    candidates = []
    for group, siblings in groups.items():
        permitted = sorted(set(siblings) & set(allowed))
        busy = max(utilization.get(cpu, 1.) for cpu in siblings)
        if permitted and busy < .35:
            candidates.append((busy, group, permitted[0]))
    chosen = [cpu for _, _, cpu in sorted(candidates)[:min(count, capacity)]]
    if not chosen:
        raise RuntimeError('no sufficiently idle physical core groups')
    return chosen


def plot_report(path, summary, leads, drivers, cells):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False,
        'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .15, 'pdf.fonttype': 42})
    colors = dict(stochastic='#087f8c', previous_day='#d1495b', previous_week='#6741a5', oracle='#228b22')
    selected = ('stochastic', *MODES, 'oracle')
    with PdfPages(path) as pdf:
        fig, ax = plt.subplots(figsize=(11.7, 8.3)); ax.axis('off')
        fig.suptitle('PriceFM R131 | Causal seasonal price-driver diagnosis', fontsize=17, y=.94)
        rows = [[r] + [f'{summary[(summary.region == r) & (summary.operator == m)].AQL.iloc[0]:.3f}'
            for m in selected] for r in ('DK_1', 'HR')]
        table = ax.table(cellText=rows, colLabels=['Region', 'Normal stochastic', 'Previous day',
            'Previous week', 'Oracle (diagnostic)'], cellLoc='center', bbox=[.02, .64, .96, .20])
        table.auto_set_font_size(False); table.set_fontsize(10)
        ax.text(.02, .55, 'Equal-fold/equal-clock held-out validation AQL; lower is better.', transform=ax.transAxes)
        ax.text(.02, .46, '288 matched origins; six frozen cells; no new fitting or test reforecast.\n'
            'H96 = 24 hours, at 15-minute resolution; S500 coefficient draws unchanged.\n'
            'Seasonal sources are observed strictly before the forecast origin.\n'
            'Seasonal drivers are deterministic controls, not calibrated predictive models.\n'
            'Future exogenous inputs remain retrospective realized covariates.\n'
            'Historical windows were examined; no confirmatory superiority claim.\n'
            'No automatic driver selection, article replacement or all-region rollout.',
            va='top', linespacing=1.8, transform=ax.transAxes)
        pdf.savefig(fig); plt.close(fig)
        for region in ('DK_1', 'HR'):
            fig, axes = plt.subplots(2, 2, figsize=(11.7, 8.3), sharex=True, sharey=True)
            fig.suptitle(f'{region} | Receiver AQL by lead and origin clock', fontsize=16)
            for ax, offset in zip(axes.flat, (0, 24, 48, 72)):
                for mode in selected:
                    part = leads[(leads.region == region) & (leads.operator == mode) & (leads.offset_steps == offset)]
                    curve = part.groupby('lead_step').AQL.mean()
                    ax.plot(curve.index / 4, curve.values, color=colors[mode], label=mode.replace('_', ' '))
                ax.set_title(f'Origin {offset // 4:02d}:00, fixed market clock')
                ax.set_xlabel('Hours ahead'); ax.set_ylabel('AQL (EUR/MWh)')
            axes[0, 0].legend(fontsize=8); fig.tight_layout(rect=[0, 0, 1, .95]); pdf.savefig(fig); plt.close(fig)
            fig, axes = plt.subplots(1, 2, figsize=(11.7, 8.3))
            fig.suptitle(f'{region} | Driver error and receiver coverage', fontsize=16)
            for mode in ('stochastic', *MODES):
                curve = drivers[(drivers.region == region) & (drivers.operator == mode)].groupby('lead_step').MAE.mean()
                axes[0].plot(curve.index / 4, curve, label=mode.replace('_', ' '), color=colors[mode])
            axes[0].set_xlabel('Hours ahead'); axes[0].set_ylabel('Driver MAE (EUR/MWh)'); axes[0].legend()
            part = summary[summary.region == region].set_index('operator').loc[list(selected)]
            axes[1].bar(range(4), part.coverage_80 * 100, color=[colors[m] for m in selected])
            axes[1].set_xticks(range(4), ['Normal', 'Previous\nday', 'Previous\nweek', 'Oracle'])
            axes[1].axhline(80, color='black', ls='--'); axes[1].set_ylim(0, 100)
            axes[1].set_ylabel('80% receiver interval coverage (%)')
            fig.tight_layout(rect=[0, 0, 1, .95]); pdf.savefig(fig); plt.close(fig)
        for (region, fold), values in cells.items():
            fig, axes = plt.subplots(3, 1, figsize=(11.7, 8.3), sharex=True)
            fig.suptitle(f'{region}, fold {fold} | Prespecified first validation origin', fontsize=16)
            x = np.arange(1, 97) / 4
            for ax, mode in zip(axes, ('stochastic', *MODES)):
                v = values[mode][0]
                ax.plot(x, values['truth'][0], color='#222222', lw=1.5, label='Observed')
                ax.plot(x, v[:, 3], color=colors[mode], label=mode.replace('_', ' '))
                ax.fill_between(x, v[:, 0], v[:, -1], color=colors[mode], alpha=.2, label='80% interval')
                ax.set_ylabel('EUR/MWh'); ax.legend(ncol=3, fontsize=9)
            axes[-1].set_xlabel('Hours ahead'); fig.tight_layout(rect=[0, 0, 1, .95]); pdf.savefig(fig); plt.close(fig)


def closeout(out, prep, verified, read, write, seal, common_metrics):
    path = Path(out) / 'closeout'
    if path.exists():
        verified(path)
        return read(path / 'interpretation.json')
    rows, leads, drivers, cells = [], [], [], {}
    for cell in prep['cells']:
        packets = []
        for task in prep['tasks']:
            if (task['region'], task['fold']) != (cell['region'], cell['fold']):
                continue
            folder = Path(out) / 'tasks_done' / task['name']; verified(folder)
            with np.load(folder / 'predictions.npz', allow_pickle=False) as data:
                packets.append({k: data[k] for k in data.files})
        values = aggregate_packets(packets, cell['grid'])
        cells[cell['region'], cell['fold']] = values
        a, b, c = metrics(values, cell, common_metrics)
        rows += a; leads += b; drivers += c
    frame, lead_frame, driver_frame = map(pd.DataFrame, (rows, leads, drivers))
    summary = frame.groupby(['region', 'operator']).mean(numeric_only=True).reset_index()
    findings = []
    for region in ('DK_1', 'HR'):
        region_scores = summary[summary.region == region].set_index('operator')
        baseline = float(region_scores.loc['stochastic', 'AQL'])
        for mode in MODES:
            score = float(region_scores.loc[mode, 'AQL'])
            deltas = []
            for fold in (1, 2, 3):
                part = frame[(frame.region == region) & (frame.fold == fold)].groupby('operator').AQL.mean()
                deltas.append(float(part[mode] - part['stochastic']))
            findings.append(dict(region=region, operator=mode, AQL=score,
                delta_AQL_vs_stochastic=score - baseline,
                improvement_pct=100 * (baseline - score) / baseline,
                fold_deltas=deltas, coverage_80=float(region_scores.loc[mode, 'coverage_80']),
                width_80=float(region_scores.loc[mode, 'width_80']), selected=False))
    result = dict(status='R131_COMPLETE_NOT_PROMOTED', source=prep['source'], new_fits=0,
        diagnostic_origins=288, official_test_reforecast=False, authority_unchanged=True,
        findings=findings, decision='No automatic selection or fitting. Inspect seasonal error and uncertainty before a separately frozen driver correction.',
        caveats=['Deterministic controls omit driver innovation uncertainty.',
            'Oracle is diagnostic only.', 'Future exogenous values are retrospective realized inputs.',
            'Historical windows were examined; selected regions are developmental.',
            'VB uncertainty and clipped seven-knot CDF completion remain limitations.'])
    path.mkdir()
    frame.to_csv(path / 'validation_metrics.csv', index=False)
    lead_frame.to_csv(path / 'lead_clock_metrics.csv', index=False)
    driver_frame.to_csv(path / 'driver_error_metrics.csv', index=False)
    summary.to_csv(path / 'region_control_summary.csv', index=False)
    plot_report(path / 'pricefm_r131_causal_seasonal_diagnosis.pdf', summary, lead_frame, driver_frame, cells)
    write(path / 'interpretation.json', result)
    seal(path, dict(source=prep['source'], diagnostic_origins=288, new_fits=0))
    return result
