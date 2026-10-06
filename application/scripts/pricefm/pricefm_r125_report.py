"""Readable internal diagnosis, with historical references kept separate."""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

NAMES = {'r123_3e15bdc342f556c1': 'B', 'r123_6d32d129873c7930': 'A', 'r123_8680f8aaeaeae8ce': 'C'}
COLORS = {'mean_feature': '#713E8A', 'normal_driver': '#697C85', 'cdf_pool_clipped': '#167D9A',
          'cdf_pool_linear': '#165C38', 'oracle_mean_feature': '#B57917'}


def report(output, jobs, frame, origins, traces, reference, requirements):
    output = Path(output)
    means = frame.groupby(['candidate_id', 'operator'], as_index=False).agg(
        mean_AQL=('AQL', 'mean'), mean_late_AQL=('late_AQL', 'mean'),
        mean_coverage=('interval_80_coverage', 'mean'), mean_width=('interval_80_width', 'mean'),
        mean_crossing=('crossing_rate', 'mean'))
    means.to_csv(output / 'operator_internal_means.csv', index=False)
    paired = origins.pivot(index=['candidate_id', 'split', 'origin_index', 'anchor'], columns='operator', values='AQL')
    paired['cdf_linear_minus_raw_mean'] = paired.cdf_pool_linear - paired.mean_feature
    paired['CDF_pool_minus_sorted_mean'] = paired.cdf_pool_linear - paired.rearranged_path_mean
    paired['generated_minus_oracle_mean'] = paired.mean_feature - paired.oracle_mean_feature
    paired.to_csv(output / 'paired_AQL_differences.csv')
    lines = ['# R125 frozen-fit forecast diagnosis', '',
        'BG, outer-Fold-1 training-internal validation: 12 predetermined origins per split/candidate.',
        '108 origin/candidate evaluations, 500 paths, 96 quarter-hour steps = 24 hours.',
        'AQL units: outer-Fold-1 training-scaled price. Zero refits; priors/specifications unchanged.', '',
        '## Internal results, not an official comparison', '',
        '| Candidate | Operator | Mean AQL | Late AQL | Coverage 80% | Width |',
        '|---|---|---:|---:|---:|---:|']
    for row in means.itertuples():
        lines.append(f'| {NAMES[row.candidate_id]} | {row.operator} | {row.mean_AQL:.7f} | {row.mean_late_AQL:.7f} | {row.mean_coverage:.1%} | {row.mean_width:.5f} |')
    lines += ['', '## What can and cannot be concluded', '',
        'The paired controls must reproduce the matched R124 forecasts; changing origin positions must not change innovation seeds.',
        'CDF pooling integrates explicit conditional distributions and then inverts the average CDF. It is not an average of quantile functions.',
        'Seven levels do not identify the whole conditional distribution. Clipped tails add endpoint masses; linear tails extend quantile slopes to probabilities 0 and 1.',
        'Each path sorts the seven knots with an explicitly unweighted convention. This is a changed diagnostic reconstruction, not a correction to the original fit.',
        'The sorted-path mean control separates effects of crossing repair from effects of CDF pooling. Both tail conventions must be reported, not cherry-picked.',
        'Independent quantile-level VB draws are a declared modular coupling, not an identified joint posterior.',
        'No AL likelihood-scale posterior is fabricated from the saved sigma mean. No composite joint density is treated as normalized.',
        'Oracle readouts deliberately consume future target lags. They help diagnose the mechanism but are invalid forecasts and cannot be selected or published.',
        'Saved ELBO and state/scale deltas cannot certify unexported covariance, RHS or latent-state stationarity. No exact optimizer resumption is available from these compact AL files.', '',
        '## Current article context: DIFFERENT windows and units', '',
        '| Official fold | Current R98 QDESN test AQL (EUR/MWh) | Cached PriceFM test AQL (EUR/MWh) |',
        '|---|---:|---:|']
    for row in reference.sort_values('fold').itertuples():
        lines.append(f'| {row.fold} | {row.qdesn_AQL:.6f} | {row.pricefm_AQL:.6f} |')
    lines += [f'| Three-fold mean | {reference.qdesn_AQL.mean():.6f} | {reference.pricefm_AQL.mean():.6f} |', '',
        'These reference numbers come from the freshly fetched main article registry. They cannot be subtracted from internal scaled R125 AQL.',
        'The new specification is NOT YET demonstrably better or worse than either comparator on matched official folds.',
        'Promotion and an all-region rollout are not justified by this internal diagnostic alone.', '',
        '## Efficient route to that decision', '',
        '1. Use the fixed internal diagnostics to decide which forecast quantity is scientifically intended; do not choose a tail rule from test performance.',
        '2. Resolve/document B stationarity. A/C provide formally converged controls; no blanket increased iteration budget is inferred from band coverage.',
        '3. Freeze a deployable operator and fit one region specification on all three full training windows (3 Normal + 21 AL fits). Internal partial-window fits are not full-fold fits.',
        '4. Score actual matching authority/PriceFM origins, EUR/MWh units and seven levels using the strict matched_comparison validator.',
        '5. Compare mean AQL over all prespecified folds/regions; never require each case to beat both or cherry-pick test winners.',
        '6. Historical tests have already been inspected in earlier stages; label this retrospective. A fresh prospective confirmation needs new future data.',
        '7. Only complete matched whole-cohort evidence can support a promotion handoff to the coordinator. No registry, manuscript, main or Overleaf changes here.', '',
        'NOT_READY_FOR_INTEGRATION', '']
    (output / 'diagnosis_report.md').write_text('\n'.join(lines))
    os.environ['MPLCONFIGDIR'] = str(output / 'plot_cache')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages
    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False,
                         'axes.grid': True, 'grid.alpha': .18, 'pdf.fonttype': 42})
    selected_ops = ('mean_feature', 'normal_driver', 'rearranged_path_mean', 'cdf_pool_clipped', 'cdf_pool_linear', 'oracle_mean_feature')
    with PdfPages(output / 'forecast_estimand_diagnostics.pdf') as pdf:
        fig = plt.figure(figsize=(11.7, 8.3))
        fig.text(.06, .92, 'R125 | What is the forecast band estimating?', fontsize=20, weight='bold')
        fig.text(.06, .86, 'BG / training-internal diagnosis only / frozen fits / no official evaluation', fontsize=12)
        group = means[(means.candidate_id == 'r123_3e15bdc342f556c1') & means.operator.isin(selected_ops)]
        rows = [[r.operator.replace('_', ' '), f'{r.mean_AQL:.6f}', f'{r.mean_coverage:.1%}', f'{r.mean_width:.4f}'] for r in group.itertuples()]
        ax = fig.add_axes([.06, .50, .88, .28]); ax.axis('off')
        table = ax.table(cellText=rows, colLabels=['Candidate B operator', 'Internal AQL', '80% coverage', 'Band width'], cellLoc='left', loc='center')
        table.auto_set_font_size(False); table.set_fontsize(10); table.scale(1, 1.6)
        fig.text(.06, .19, 'Predictive mixtures and averaged conditional quantiles are different quantities.\n'
            'Both tail rules and crossing controls are explicit diagnostic conventions.\n'
            'Oracle inputs are intentionally unavailable future prices: diagnostic only.\n'
            'No new matched official-fold score exists against PriceFM or article authority.\n'
            'Current results do not authorize promotion or an all-region launch.', linespacing=1.8)
        pdf.savefig(fig); plt.close(fig)
        fig, axes = plt.subplots(1, 3, figsize=(11.7, 6.5), sharey=True)
        for ax, candidate in zip(axes, NAMES):
            for operator in COLORS:
                rows = frame[(frame.candidate_id == candidate) & (frame.operator == operator)].sort_values('split')
                ax.plot(rows.split, rows.AQL, 'o-', color=COLORS[operator], label=operator.replace('_', ' '))
            ax.set(title='Candidate ' + NAMES[candidate], xlabel='Internal split', xticks=[1, 2, 3])
        axes[0].set_ylabel('Matched-subset AQL (training-scaled price)')
        axes[-1].legend(fontsize=8)
        fig.suptitle('Paired diagnostic operators on predetermined origins', fontsize=15)
        fig.tight_layout(rect=[0, .03, 1, .93]); pdf.savefig(fig); plt.close(fig)
        for job in [j for j in jobs if j['candidate_id'] == 'r123_3e15bdc342f556c1']:
            with np.load(Path(job['output_dir']) / 'predictions.npz', allow_pickle=False) as arrays:
                fig, axes = plt.subplots(3, 1, figsize=(11.7, 8.3), sharex=True)
                x = np.arange(1, 97) / 4
                for ax, origin in zip(axes, (0, 6, 11)):
                    ax.plot(x, arrays['truth'][origin], color='#252A2D', label='Observed price')
                    for name in ('mean_feature', 'normal_driver', 'cdf_pool_clipped', 'cdf_pool_linear'):
                        curve = arrays[name][origin]
                        ax.plot(x, curve[:, 3], color=COLORS[name], label=name.replace('_', ' '), linewidth=1)
                        ax.fill_between(x, curve[:, 0], curve[:, -1], color=COLORS[name], alpha=.10)
                    ax.set_title(str(arrays['origin_utc'][origin]), fontsize=10); ax.set_ylabel('Scaled price')
                axes[0].legend(ncol=4, fontsize=8); axes[-1].set_xlabel('Hours ahead')
                fig.suptitle(f'B / internal split {job["split"]}: causal forecasts only', fontsize=15)
                fig.tight_layout(rect=[0, .03, 1, .93]); pdf.savefig(fig); plt.close(fig)
        for job in [j for j in jobs if j['candidate_id'] == 'r123_3e15bdc342f556c1']:
            fig, axes = plt.subplots(4, 2, figsize=(11.7, 8.3))
            for ax, (level, folder) in zip(axes.flat, sorted(job['quantile_dirs'].items(), key=lambda item: float(item[0]))):
                trace = pd.read_csv(Path(folder) / 'vb_trace.csv')
                ax.plot(np.arange(1, len(trace) + 1), trace.elbo, color='#165C38', linewidth=1)
                ax.set_title('AL level ' + str(level), fontsize=10)
                ax.set(xlabel='Saved iteration', ylabel='Raw total ELBO')
            axes.flat[-1].axis('off')
            axes.flat[-1].text(0, .8, 'All B fits reached the 1000-iteration cap.\n'
                'A flat ELBO alone is not a full-state certificate.\n'
                'RHS/latent/covariance traces were not exported.\n'
                'These compact fits cannot be resumed exactly.', va='top', fontsize=10, linespacing=1.6)
            fig.suptitle(f'B / internal split {job["split"]}: complete saved raw ELBO traces', fontsize=14)
            fig.tight_layout(rect=[0, .02, 1, .94]); pdf.savefig(fig); plt.close(fig)
        fig = plt.figure(figsize=(11.7, 8.3))
        fig.text(.06, .91, 'Promotion question: not yet an aligned comparison', fontsize=18, weight='bold')
        rows = [[str(r.fold), f'{r.qdesn_AQL:.4f}', f'{r.pricefm_AQL:.4f}', 'Not fitted/scored'] for r in reference.sort_values('fold').itertuples()]
        ax = fig.add_axes([.06, .55, .88, .22]); ax.axis('off')
        table = ax.table(cellText=rows, colLabels=['Official fold', 'Article QDESN AQL', 'Cached PriceFM AQL', 'New specification'], cellLoc='center', loc='center')
        table.auto_set_font_size(False); table.set_fontsize(11); table.scale(1, 1.8)
        fig.text(.06, .19, 'Reference scores are official TEST AQL in EUR/MWh, not internal scaled-price AQL.\n'
            'No invalid numerical ranking across these two questions is made.\n'
            'Next: freeze the operator, address convergence evidence, fit full training windows,\n'
            'then compare identical origins and report the prespecified average across folds.\n'
            'No per-fold dual-comparator gate. No future-target oracle promotion.\n'
            'An all-region decision requires complete matched whole-cohort evidence.', linespacing=1.8)
        pdf.savefig(fig); plt.close(fig)
