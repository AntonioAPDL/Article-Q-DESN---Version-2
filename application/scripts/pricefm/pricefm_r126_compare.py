"""Matched raw-price scoring and an explicitly retrospective BG pilot report."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess

import joblib
import numpy as np
import pandas as pd
import yaml

from pricefm_r126_contract import (LEVELS, digest, read, write, seal, verified,
    loss, market_ns, official_origins, training_valid)
from pricefm_r126_fullfold import raw_frame


def long_prediction(frame, count, value):
    if frame.duplicated(['origin_id', 'horizon', 'tau']).any():
        raise ValueError('duplicate reference prediction rows')
    index = pd.MultiIndex.from_product([range(count), range(1, 97), LEVELS],
                                      names=['origin_id', 'horizon', 'tau'])
    packet = frame.set_index(['origin_id', 'horizon', 'tau'])
    if len(packet) != len(index) or set(packet.index) != set(index):
        raise ValueError('reference forecast support differs')
    return packet.loc[index, value].to_numpy().reshape(count, 96, 7)


def cached_phase1(data, code, output, fold):
    output = Path(output)
    original = Path(data) / 'authoritative/pricefm_phase1_stage_b_apples_to_apples_20260616' / 'region=BG' / f'fold={fold}'
    old = read(original / 'summary.json')
    model = Path(old['model_path']); upstream = Path(old['pricefm_repo'])
    if digest(model) != old['model_sha256']:
        raise RuntimeError('released checkpoint hash differs')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=upstream, text=True).strip()
    if revision != old['pricefm_repo_commit']: raise RuntimeError('public PriceFM source revision differs')
    if verified(output): return pd.read_csv(output / 'pricefm_phase1_predictions_original.csv')
    if output.exists(): raise RuntimeError('partial reference replay must be audited, not overwritten')
    config = yaml.safe_load((Path(code) / 'application/config/pricefm_data_pipeline.yaml').read_text())
    config['pricefm']['processed_dir'] = str(Path(data) / 'processed')
    for key in ('raw_dir', 'interim_dir', 'external_repo_dir', 'log_dir'):
        config['pricefm'][key] = str(Path(data) / ('external/PriceFM' if key == 'external_repo_dir' else key.removesuffix('_dir')))
    config_path = output.parent / f'fold={fold}_phase1_config.yaml'
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(yaml.safe_dump(config))
    command = [str(Path(data) / 'venv_pricefm_tf/bin/python'), '-B',
        str(Path(code) / 'application/scripts/pricefm/17_run_pricefm_phase1_predictions.py'),
        '--config', str(config_path), '--model-path', str(model), '--pricefm-repo', str(upstream),
        '--output-dir', str(output), '--region', 'BG', '--fold', str(fold),
        '--splits', 'test', '--window-mode', old['window_mode']]
    import os
    env = dict(os.environ, TF_NUM_INTRAOP_THREADS='1', TF_NUM_INTEROP_THREADS='1', CUDA_VISIBLE_DEVICES='-1')
    with (output.parent / f'fold={fold}_phase1.log').open('x') as stream:
        subprocess.run(command, cwd=code, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
    metrics = pd.read_csv(output / 'pricefm_phase1_metrics.csv')
    archived = pd.read_csv(original / 'pricefm_phase1_metrics.csv')
    observed = metrics[metrics.unit.eq('original') & metrics.split.eq('test')].iloc[0].AQL
    expected = archived[archived.unit.eq('original') & archived.split.eq('test')].iloc[0].AQL
    if abs(observed - expected) > 1e-4:
        raise RuntimeError('cached Phase-I reproduction differs from its ledger')
    seal(output, dict(inference_only=True, checkpoint_sha256=digest(model),
        source_revision=revision, training_exposure='unresolved', ledger_AQL=float(expected)))
    return pd.read_csv(output / 'pricefm_phase1_predictions_original.csv')


def compare(data, code, mirror, output, protocol):
    data, code, mirror, output = map(Path, (data, code, mirror, output))
    if verified(output): return read(output / 'decision.json')
    if output.exists(): raise RuntimeError('partial comparison evidence must not be overwritten')
    terminal = read(mirror / 'terminal.json')
    if terminal['full_fits'] != 24: raise RuntimeError('all full-fold fits required')
    choice = read(mirror / 'frozen_choice.json')
    if choice['selection_uses_test'] is not False: raise ValueError('test-selected candidate forbidden')
    raw = raw_frame(data)
    r98 = data / 'campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908'
    local = data / 'benchmarks/pricefm_operational_public_architecture_fullshot_20260812'
    registry = pd.read_csv(code / 'tables/pricefm_r98_authoritative_registry.csv')
    bg = registry[registry.region.eq('BG')].set_index('fold')
    winners = pd.read_csv(local / 'selection/cell_specific_winners.csv')
    task_map = pd.read_csv(local / 'test/selector_task_map.csv')
    freeze_path = local / 'selection/winner_freeze.json'
    if digest(freeze_path) != '11e5b6a6bffdb264f3ffb593c53b581a18cd38ad5e8b350f05cf5999787b9aec':
        raise ValueError('local PriceFM winner freeze changed')
    if digest(local / 'selection/cell_specific_winners.csv') != '466f14c01a26510ccfea6b2fd0cfb12b7449aa8024f19712b704007d528ea18f':
        raise ValueError('local PriceFM winner manifest changed')
    results = []; paired = []; evidence = {}; panels = []; by_quantile = []; by_horizon = []; train_scores = []
    for fold in (1, 2, 3):
        origins = official_origins(protocol, fold); count = len(origins)
        training_valid(read(mirror / 'full' / f'fold={fold}/design/training.json'), protocol, fold)
        scale = read(mirror / 'full' / f'fold={fold}/design/scalers.json')
        train_scores.append(dict(fold=fold, method='new_recursive_QDESN',
            teacher_forced_training_AQL=float(np.mean([read(mirror / 'full' / f'fold={fold}/al/tau={q:.2f}/terminal.json')
                ['training_pinball_inner_units'] for q in LEVELS])) * scale['inner']['price_scale'] * scale['outer']['y_scale'],
            not_a_forecast_score=True, units='EUR/MWh'))
        with np.load(mirror / 'official' / f'fold={fold}/predictions.npz', allow_pickle=False) as z:
            if not np.array_equal(z['anchors_ns'], origins.as_unit('ns').asi8):
                raise ValueError('new model official origins differ')
            new = z[choice['operator']]; controls = {k: z[k] for k in protocol['secondary_operators']}
        pos = raw.index.get_indexer(origins)
        truth = np.stack([raw['BG-price'].iloc[p:p + 96].to_numpy() for p in pos])
        base = r98 / f'global_scoring/runs/region=BG/fold={fold}'
        rows_path = base / 'adapter/rows_test.csv'; pred_path = base / 'score/test_predictions_scaled.csv'
        rows = pd.read_csv(rows_path).sort_values(['origin_id', 'horizon'])
        if len(rows) != count * 96 or rows.duplicated(['origin_id', 'horizon']).any():
            raise ValueError('R98 reference rows differ')
        if not np.array_equal(market_ns(rows.origin_market_time.iloc[::96]), origins.as_unit('ns').asi8):
            raise ValueError('R98 reference origin clock differs')
        expected_times = origins.as_unit('ns').asi8[:, None] + np.arange(96)[None, :] * 15 * 60 * 10**9
        if not np.array_equal(market_ns(rows.response_market_time), expected_times.reshape(-1)):
            raise ValueError('R98 reference response clock differs')
        scaler_path = r98 / f'processed_validation/scalers/fold_{fold}/per_region_separate_xy_scalers.joblib'
        sy = joblib.load(scaler_path)['BG']['y_scaler']
        old_truth = rows.y_scaled.to_numpy().reshape(count, 96) * sy.scale_[0] + sy.center_[0]
        old = long_prediction(pd.read_csv(pred_path), count, 'pred_scaled') * sy.scale_[0] + sy.center_[0]
        if np.max(np.abs(old_truth - truth)) > 6e-5: raise ValueError('R98 truth differs beyond measured float32 rounding')
        old_ledger = float(loss(old_truth, old).mean())
        if abs(old_ledger - bg.loc[fold, 'qdesn_AQL']) > 1e-6: raise ValueError('R98 ledger AQL differs')
        # The selector is frozen in August; it must not be selected after test scoring.
        selected = task_map[(task_map.selector == 'cell_specific') & (task_map.region == 'BG') & (task_map.fold == fold)]
        if len(selected) != 1: raise ValueError('one frozen local PriceFM task per BG fold required')
        task_id = str(selected.iloc[0].task_id)
        winner = winners[(winners.region == 'BG') & (winners.fold == fold)]
        if (len(winner) != 1 or winner.iloc[0].selected_on_split != 'validation'
                or str(winner.iloc[0].selection_reads_test).lower() != 'false'
                or digest(Path(winner.iloc[0].checkpoint)) != winner.iloc[0].checkpoint_sha256):
            raise ValueError('local PriceFM selected-checkpoint provenance differs')
        local_path = local / 'test/tasks' / task_id / 'predictions.npz'
        expected_prediction_hashes = (
            '1847b5ec7beeed3ad6e5e9750e54befa261d280ccecc7a0e3ec96f75ff98840d',
            '4515236ba4b0ff145215a43a82c253d6bce2d9891d2f2c5cf2757ba709b6c1a4',
            '8c12751fb8bcf1bc8f14be1de0e378218583a917d13c251d89d588622cfb49df')
        if digest(local_path) != expected_prediction_hashes[fold - 1]:
            raise ValueError('retained local PriceFM prediction hash differs')
        with np.load(local_path, allow_pickle=False) as z:
            if not np.array_equal(z['anchors_ns'], origins.as_unit('ns').asi8): raise ValueError('local PriceFM origins differ')
            local_pred, local_truth = z['y_pred'], z['y_true']
        if np.max(np.abs(local_truth - truth)) > 6e-5: raise ValueError('local PriceFM truth differs')
        cached = cached_phase1(data, code, mirror.parent / 'reference_replay' / f'fold={fold}', fold)
        if not np.array_equal(market_ns(cached.drop_duplicates('origin_id').sort_values('origin_id').origin_market_time),
                              origins.as_unit('ns').asi8): raise ValueError('cached PriceFM origins differ')
        phase1 = long_prediction(cached, count, 'pred_original')
        cached_truth = cached.drop_duplicates(['origin_id', 'horizon']).sort_values(['origin_id', 'horizon']).y_original.to_numpy().reshape(count, 96)
        if np.max(np.abs(cached_truth - truth)) > 6e-5: raise ValueError('cached PriceFM truth differs')
        models = dict(new_recursive_QDESN=new, current_R98_QDESN=old,
                      cached_PriceFM_PhaseI=phase1, local_PriceFM_PhaseI_II=local_pred)
        for name, prediction in models.items():
            values = loss(truth, prediction); daily = values.mean(axis=(1, 2))
            results.append(dict(fold=fold, method=name, AQL=float(values.mean()),
                early_AQL=float(values[:, :24].mean()), late_AQL=float(values[:, 72:].mean()),
                coverage_80=float(np.mean((truth >= prediction[:, :, 0]) & (truth <= prediction[:, :, -1]))),
                width_80=float(np.mean(prediction[:, :, -1] - prediction[:, :, 0])),
                crossing_rate=float(np.mean(np.any(np.diff(prediction, axis=2) < 0, axis=2))),
                median_MAE=float(np.mean(np.abs(truth - prediction[:, :, 3])))))
            paired.extend(dict(fold=fold, method=name, origin_market_time=origin.isoformat(), AQL=float(v))
                          for origin, v in zip(origins, daily))
            by_quantile.extend(dict(fold=fold, method=name, tau=float(q), AQL=float(values[:, :, i].mean()))
                               for i, q in enumerate(LEVELS))
            by_horizon.extend(dict(fold=fold, method=name, horizon=h + 1, AQL=float(values[:, h].mean()))
                              for h in range(96))
        for name, prediction in controls.items():
            results.append(dict(fold=fold, method='secondary_' + name, AQL=float(loss(truth, prediction).mean())))
        panels.append((fold, origins, truth, models))
        for p in (rows_path, pred_path, scaler_path, local_path, freeze_path,
                  Path(winner.iloc[0].checkpoint), local / 'selection/cell_specific_winners.csv'):
            evidence[str(p)] = digest(p)
    output.mkdir(parents=True)
    frame = pd.DataFrame(results); frame.to_csv(output / 'fold_metrics.csv', index=False)
    pd.DataFrame(paired).to_csv(output / 'paired_daily_losses.csv', index=False)
    pd.DataFrame(by_quantile).to_csv(output / 'quantile_losses.csv', index=False)
    pd.DataFrame(by_horizon).to_csv(output / 'horizon_losses.csv', index=False)
    pd.DataFrame(train_scores).to_csv(output / 'training_fit_diagnostics.csv', index=False)
    means = frame.groupby('method').AQL.mean().to_dict(); candidate = means['new_recursive_QDESN']
    decision = dict(mean_AQL=means,
        better_than_R98=candidate < means['current_R98_QDESN'],
        better_than_cached_PriceFM=candidate < means['cached_PriceFM_PhaseI'],
        better_than_local_PriceFM=candidate < means['local_PriceFM_PhaseI_II'],
        scope='BG_three_fold_retrospective_pilot_not_all_regions',
        next_decision='consider_prespecified_broader_cohort' if candidate < means['current_R98_QDESN'] else 'diagnose_BG_before_expansion',
        operator=choice['operator'], candidate_id=choice['candidate_id'],
        cached_checkpoint_training_exposure='unresolved', same_target_fitting_rows=False,
        future_covariates='shared_realized_retrospective',
        promotion_authorized=False, all_region_launch_authorized=False,
        integration_status='NOT_READY_FOR_INTEGRATION')
    write(output / 'decision.json', decision); write(output / 'reference_hashes.json', evidence)
    report(output, frame, panels, choice, decision, mirror)
    seal(output, dict(status='R126_MATCHED_BG_COMPARISON_COMPLETE', decision=decision))
    return decision


def report(output, frame, panels, choice, decision, mirror):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages
    colors = ['#218380', '#564787', '#c05252', '#536874']
    with PdfPages(output / 'pricefm_r126_matched_BG_comparison.pdf') as pdf:
        fig, ax = plt.subplots(figsize=(11.7, 8.3)); ax.axis('off')
        ax.text(.03, .95, 'BG: Frozen Recursive Q-DESN Comparison', fontsize=19, va='top')
        text = '\n'.join(f'{name}: mean AQL {value:.6f} EUR/MWh' for name, value in decision['mean_AQL'].items()
                         if not name.startswith('secondary_'))
        ax.text(.03, .79, text, fontsize=12, va='top', linespacing=1.8)
        ax.text(.03, .49, f"Winner: {choice['candidate_id']}\nOperator: {choice['operator']}\n"
            'Three complete official folds; one frozen specification; train-only parameter fits.\n'
            'Same forecast dates and raw observed prices, not identical model fitting rows.\n'
            'Retrospective conditional evaluation with realized future exogenous covariates.\n'
            'Cached Phase-I checkpoint training exposure remains unresolved.\n'
            'A BG pilot cannot justify whole-cohort promotion on its own.', fontsize=11, va='top', linespacing=1.8)
        pdf.savefig(fig); plt.close(fig)
        for fold, origins, truth, models in panels:
            fig, axes = plt.subplots(4, 1, figsize=(11.7, 8.3), sharex=True)
            for ax, (name, pred), color in zip(axes, models.items(), colors):
                # First seven days are chosen by calendar, not by visual fit quality.
                y = truth[:7].reshape(-1); p = pred[:7].reshape(-1, 7); x = np.arange(len(y)) / 96
                ax.fill_between(x, p[:, 0], p[:, -1], color=color, alpha=.20)
                ax.plot(x, p[:, 3], color=color, lw=.9); ax.plot(x, y, color='#252525', lw=.65)
                score = frame[(frame.fold == fold) & (frame.method == name)].iloc[0].AQL
                ax.set_title(f'{name} | full-fold AQL {score:.4f}', fontsize=10, loc='left')
                ax.set_ylabel('EUR/MWh', fontsize=9); ax.grid(alpha=.15)
            axes[-1].set_xlabel('Days from first official forecast origin')
            fig.suptitle(f'Fold {fold}: identical first-week forecast dates, median and 10%-90% bands', fontsize=13)
            fig.tight_layout(rect=[0, 0, 1, .96]); pdf.savefig(fig); plt.close(fig)
            fig, axes = plt.subplots(4, 2, figsize=(11.7, 8.3))
            root = mirror / 'full' / f'fold={fold}'
            for ax, q in zip(axes.flat, ['normal', *LEVELS]):
                folder = root / 'normal' if q == 'normal' else root / f'al/tau={q:.2f}'
                trace = pd.read_csv(folder / ('convergence_trace.csv' if q == 'normal' else 'vb_trace.csv'))
                column = 'total_objective' if q == 'normal' else 'elbo'
                ax.plot(np.arange(1, len(trace) + 1), trace[column], color=colors[0], lw=1)
                ax.set_title('Normal RHS: total objective' if q == 'normal' else f'AL {q:.2f}: raw total ELBO',
                             loc='left', fontsize=9)
                ax.set_xlabel('VB iteration', fontsize=8); ax.grid(alpha=.15)
            fig.suptitle(f'Fold {fold}: raw fit-objective traces (not comparable in absolute level)', fontsize=12)
            fig.tight_layout(rect=[0, 0, 1, .96]); pdf.savefig(fig); plt.close(fig)
    write(output / 'report_metadata.json', dict(pages=7, plotted_origins='first_seven_by_calendar',
        primary_metric='complete_fold_mean_pinball_loss', mean_feature_and_linear_secondary_only=True))
