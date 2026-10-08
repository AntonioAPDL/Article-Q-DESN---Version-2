"""Automatic complete-cohort diagnostic closeout, not authority selection."""
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_r126_contract import read, write, immutable, digest, verified, seal, loss
from pricefm_r127_contract import common_metrics
from pricefm_r127_forecast import MODES


def complete_positions(blocks, expected):
    values = np.concatenate([b['positions'] for b in blocks]); order = np.argsort(values)
    if not np.array_equal(values[order], np.asarray(expected)):
        raise ValueError('duplicate, missing or unexpected diagnostic origins')
    return order


def closeout(out, prep):
    out = Path(out); report = out / 'report'
    if verified(report): return read(report / 'decision.json')
    official = []; internal = []; leads = []; variances = []; repeats = []; groups = {}; sensitivity = []; mc_deltas = []
    seals = {}
    for path in sorted((out / 'tasks').glob('*.json')):
        task = read(path); folder = out / 'tasks_done' / task['name']; verified(folder)
        seals[str(folder / 'completed_evidence.json')] = digest(folder / 'completed_evidence.json')
        with np.load(folder / 'predictions.npz', allow_pickle=False) as packet:
            block = {key: packet[key] for key in packet.files}
        key = (task['kind'], task.get('fold'), task.get('split'), task.get('offset'), task.get('seed'))
        groups.setdefault(key, []).append(block)
    expected_groups = {('official', f, None, None, None) for f in (1,2,3)}
    expected_groups.update(('internal',None,j['split'],o,j['seed'])
        for j in prep['jobs'] for o in prep['protocol']['internal_offsets_steps'])
    expected_groups.update(('mc',None,prep['protocol']['mc_repeat_split'],0,s)
        for s in prep['protocol']['mc_repeat_seeds'])
    if set(groups) != expected_groups: raise ValueError('complete diagnostic cell support required')
    for fold, count in enumerate(prep['official_protocol']['test_origin_counts'], 1):
        blocks = groups[('official', fold, None, None, None)]; order = complete_positions(blocks, range(count))
        oracle = np.concatenate([b['oracle'] for b in blocks])[order]
        truth = np.concatenate([b['truth'] for b in blocks])[order]
        anchors = np.concatenate([b['anchors_ns'] for b in blocks])[order]
        parent = Path(prep['parent']) / f'official/fold={fold}'; verified(parent)
        with np.load(parent / 'predictions.npz', allow_pickle=False) as old:
            np.testing.assert_array_equal(truth, old['truth'])
            np.testing.assert_array_equal(anchors, old['anchors_ns'])
            causal = old['cdf_pool_clipped']
            official.extend([dict(fold=fold, method='R126_recursive', origins=count,
                **common_metrics(truth, causal)), dict(fold=fold, method='R127_oracle_DIAGNOSTIC_ONLY', origins=count,
                **common_metrics(truth, oracle))])
            official[-1]['paired_AQL_change'] = float(np.mean(loss(truth, oracle)-loss(truth, causal)))
    for key, blocks in groups.items():
        kind, _, split, offset, seed = key
        if kind == 'official': continue
        task_positions = sorted(v for b in blocks for v in b['positions'])
        if kind == 'mc': expected = prep['protocol']['mc_repeat_positions']
        elif not offset: expected = next(j['origin_positions'] for j in prep['jobs'] if j['split'] == split)
        else:
            from pricefm_r125_cdf import origin_positions
            n = next(j['complete_origin_count'] for j in prep['jobs'] if j['split'] == split)
            expected = origin_positions(n - 1, 12)
        order = complete_positions(blocks, expected)
        arrays = {k: np.concatenate([b[k] for b in blocks])[order]
            for k in blocks[0] if k != 'variance_lead_mask'}
        truth = arrays['truth']
        if kind == 'internal' and 'oracle_current_exog_sensitivity' in arrays:
            values = arrays['oracle_current_exog_sensitivity'].mean(axis=0)
            for h in range(96):
                for ch, channel in enumerate(('load','solar','wind')):
                    for layer in range(values.shape[-1]):
                        sensitivity.append(dict(split=split,offset_hour=offset/4,lead_step=h+1,
                            channel=channel,layer=layer+1,local_one_unit_RMS=float(values[h,ch,layer])))
        if kind == 'mc':
            baseline_seed=next(j['seed'] for j in prep['jobs'] if j['split']==split)
            base=groups[('internal',None,split,0,baseline_seed)]
            pos=np.concatenate([b['positions'] for b in base])
            indexes=[list(pos).index(int(p)) for p in expected]
            for mode in (*MODES,'oracle'):
                control=np.concatenate([b[mode] for b in base])[indexes]
                np.testing.assert_array_equal(truth,np.concatenate([b['truth'] for b in base])[indexes])
                mc_deltas.append(dict(split=split,seed=seed,method=mode,
                    mean_absolute_quantile_delta=float(np.mean(abs(arrays[mode]-control))),
                    AQL_change=float(np.mean(loss(truth,arrays[mode])-loss(truth,control)))))
        for mode in (*MODES, 'oracle'):
            row = dict(split=split, offset_hour=offset / 4, seed=seed, method=mode,
                origins=len(task_positions), units='outer fold-1 scaled price', **common_metrics(truth, arrays[mode]))
            if mode != 'oracle':
                mi = MODES.index(mode); driver = arrays['driver_mean'][:, :, mi]
                row.update(driver_bias=float(np.mean(driver-truth)), driver_MAE=float(np.mean(abs(driver-truth))),
                    driver_sd=float(arrays['driver_sd'][:,:,mi].mean()),
                    state_oracle_rmse=float(arrays['state_oracle_rmse'][:,:,mi].mean()),
                    state_variance=float(arrays['state_variance'][:,:,mi].mean()),
                    near_linear_fraction=float(arrays['near_linear_fraction'][:,:,mi].mean()),
                    saturated_fraction=float(arrays['saturated_fraction'][:,:,mi].mean()))
            (repeats if kind == 'mc' else internal).append(row)
            if kind == 'mc': continue
            costs = loss(truth, arrays[mode])
            for h in range(96):
                lead = dict(split=split, offset_hour=offset/4, method=mode, lead_step=h+1,
                    target_hour=(offset/4+h/4)%24, AQL=float(costs[:,h].mean()),
                    coverage_80=float(np.mean((truth[:,h]>=arrays[mode][:,h,0]) & (truth[:,h]<=arrays[mode][:,h,-1]))),
                    width_80=float(np.mean(arrays[mode][:,h,-1]-arrays[mode][:,h,0])))
                if mode != 'oracle':
                    mi=MODES.index(mode)
                    for metric in ('driver_mean','driver_sd','state_oracle_rmse','state_variance','saturated_fraction','near_linear_fraction'):
                        lead[metric] = float(arrays[metric][:,h,mi].mean())
                    lead['driver_bias'] = float(np.mean(arrays['driver_mean'][:,h,mi]-truth[:,h]))
                    if blocks[0]['variance_lead_mask'][h]:
                        terms=arrays['median_variance_terms'][:,h,mi].mean(axis=0)
                        variances.append(dict(split=split,offset_hour=offset/4,method=mode,lead_step=h+1,
                            coefficient_variance=float(terms[0]),state_variance=float(terms[1]),total=float(terms[2])))
                leads.append(lead)
    reference = pd.read_csv(prep['reference'])
    official_frame = pd.DataFrame(official)
    for fold in (1,2,3):
        observed=official_frame.query('fold == @fold and method == "R126_recursive"').iloc[0].AQL
        expected=reference.query('fold == @fold and method == "new_recursive_QDESN"').iloc[0].AQL
        if abs(observed-expected)>1e-10: raise RuntimeError('frozen comparison metric differs')
    for row in reference.to_dict('records'):
        if row['method'] in ('current_R98_QDESN','cached_PriceFM_PhaseI','local_PriceFM_PhaseI_II'):
            official.append({k:v for k,v in row.items() if not isinstance(v,float) or np.isfinite(v)})
    frame=pd.DataFrame(internal)
    averages=frame.groupby('method').AQL.mean().to_dict()
    driver_gap=(averages['stochastic']-averages['oracle'])/averages['stochastic']
    decision=dict(status='R127_DIAGNOSTIC_COMPLETE', official_origins=365, internal_origins=144,
        mc_repeat_origins=6, new_fits=0, model_family='independent AL VB with Normal RHS VB driver',
        internal_equal_split_offset_AQL=averages, internal_oracle_relative_reduction=driver_gap,
        official_oracle_is_diagnostic_not_deployable=True, priors_unchanged=True,
        authority_unchanged=True, promotion_authorized=False, automatic_corrective_refit=False,
        interpretation='Oracle benefit identifies input/state sensitivity; it does not prove an optimal feasible driver.',
        recommended_next_step='Review driver errors, calibration and local exogenous sensitivity together; '
            'approve only a targeted training-internal corrective experiment. No test-driven retuning.',
        limitations=['BG only; not evidence for all-region promotion', 'VB only; no MCMC comparison',
            'released realized exogenous covariates give a retrospective conditional forecast',
            'previously exposed official outcomes are development diagnostics, not a new untouched test',
            'cached PriceFM training exposure unresolved; local Phase-I/II is not the full authors search',
            'internal outer affine quantization retained; no new complete latent-factor stationarity certificate'],
        deferred=prep['protocol']['deferred'], source=prep['source'], parent_head=prep['protocol']['parent_head'])
    report.mkdir()
    pd.DataFrame(official).to_csv(report/'official_fold_metrics.csv',index=False)
    frame.to_csv(report/'internal_control_metrics.csv',index=False)
    pd.DataFrame(leads).to_csv(report/'internal_lead_metrics.csv',index=False)
    pd.DataFrame(variances).to_csv(report/'median_raw_location_variance.csv',index=False)
    pd.DataFrame(repeats).to_csv(report/'mc_repeat_metrics.csv',index=False)
    pd.DataFrame(mc_deltas).to_csv(report/'mc_control_differences.csv',index=False)
    pd.DataFrame(sensitivity).to_csv(report/'local_exogenous_sensitivity.csv',index=False)
    write(report/'decision.json',decision)
    render(report,decision)
    seal(report,dict(source=prep['source'],task_seals=seals,reference_sha256=digest(prep['reference']),
        official_origins=365,internal_origins=144,oracle_diagnostic_only=True))
    immutable(out/'terminal.json',dict(status='R127_COMPLETE',new_fits=0,failed=0,tasks=len(seals),
        source=prep['source'],task_seals=seals,report_seal_sha256=digest(report/'completed_evidence.json'),
        authority_mutated=False,article_mutated=False))
    return decision


def render(report,decision):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages
    plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    colors={'stochastic':'#136f63','parameter_only':'#b54a34','mean_driver':'#3559a0','oracle':'#713a84'}
    internal=pd.read_csv(report/'internal_control_metrics.csv')
    lead=pd.read_csv(report/'internal_lead_metrics.csv')
    official=pd.read_csv(report/'official_fold_metrics.csv')
    with PdfPages(report/'pricefm_r127_driver_diagnosis.pdf') as pdf:
        fig,ax=plt.subplots(figsize=(11.7,8.3)); ax.axis('off')
        ax.set_title('BG: frozen-fit forecast diagnosis\nOfficial folds, AQL in EUR/MWh (lower is better)',loc='left',pad=24)
        pivot=official.pivot(index='method',columns='fold',values='AQL'); pivot['Equal-fold mean']=pivot.mean(axis=1)
        labels={'R127_oracle_DIAGNOSTIC_ONLY':'Oracle price lags (NOT deployable)','R126_recursive':'R126 recursive',
            'current_R98_QDESN':'Current R98 authority','cached_PriceFM_PhaseI':'Cached PriceFM Phase I',
            'local_PriceFM_PhaseI_II':'Local PriceFM Phase I/II'}
        table=ax.table(cellText=[[f'{v:.4f}' for v in r] for r in pivot.values],
            rowLabels=[labels.get(n,n) for n in pivot.index],colLabels=['Fold 1','Fold 2','Fold 3','Equal-fold mean'],
            bbox=[.30,.38,.68,.45]); table.auto_set_font_size(False); table.set_fontsize(10)
        ax.text(0,.23,'Same frozen BG fits, seven quantiles and 500 receiver draws. No refitting or selection on these outcomes.\n'
            'Oracle uses true price lags strictly before each step; this is explanatory, not a usable forecast.\n'
            '96 quarter-hours = 24 hours. All 365 daily origins retained; the article authority is unchanged.',transform=ax.transAxes)
        ax.text(0,.06,'PriceFM references retain the provenance limitations of the frozen R126 comparison.\n'
            'This diagnostic is VB only. Official outcomes were already inspected during development.',transform=ax.transAxes,color='#555555')
        fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
        sensitivity_path=report/'local_exogenous_sensitivity.csv'
        if sensitivity_path.stat().st_size>2:
            sensitivity=pd.read_csv(sensitivity_path)
            fig,axes=plt.subplots(2,2,figsize=(11.7,8.3))
            for mode,color in colors.items():
                if mode=='oracle': continue
                rows=lead[lead.method.eq(mode)].groupby('lead_step').mean(numeric_only=True)
                axes[0,0].plot(rows.index/4,rows.driver_sd,color=color,label=mode.replace('_',' '))
                axes[0,1].plot(rows.index/4,rows.state_variance,color=color)
                axes[1,0].plot(rows.index/4,rows.near_linear_fraction,color=color)
            for (channel,layer),rows in sensitivity.groupby(['channel','layer']):
                values=rows.groupby('lead_step').local_one_unit_RMS.mean()
                axes[1,1].plot(values.index/4,values,label=f'{channel}, layer {layer}')
            axes[0,0].set_ylabel('Normal driver SD (scaled price)'); axes[0,0].legend()
            axes[0,1].set_ylabel('Mean within-path state variance')
            axes[1,0].set_ylabel('Fraction |state| < 0.1')
            axes[1,1].set_ylabel('Local exogenous response (RMS)'); axes[1,1].legend(fontsize=8,ncol=2)
            fig.suptitle('State uncertainty and local current-exogenous sensitivity (not feature importance)')
            for ax in axes.flat: ax.set_xlabel('Lead (hours)'); ax.grid(alpha=.2)
            fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
        fig,axes=plt.subplots(3,1,figsize=(11.7,8.3),sharex=True)
        for split,ax in enumerate(axes,1):
            data=internal[internal.split.eq(split)]
            for mode,color in colors.items():
                rows=data[data.method.eq(mode)].sort_values('offset_hour')
                ax.plot(rows.offset_hour,rows.AQL,'o-',color=color,label=mode.replace('_',' '))
            ax.set_ylabel(f'Split {split}\nAQL (scaled price)'); ax.grid(alpha=.2)
        axes[0].set_title('Training-internal controls: 12 calendar-selected origins per clock offset',loc='left')
        axes[0].legend(ncol=4); axes[-1].set_xticks([0,6,12,18]); axes[-1].set_xlabel('Origin market hour (fixed UTC + 1, no DST)')
        fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
        fig,axes=plt.subplots(2,2,figsize=(11.7,8.3))
        for mode,color in colors.items():
            rows=lead[lead.method.eq(mode)].groupby('lead_step').mean(numeric_only=True)
            axes[0,0].plot(rows.index/4,rows.AQL,color=color,label=mode.replace('_',' '))
            axes[0,1].plot(rows.index/4,rows.coverage_80,color=color)
            if mode!='oracle':
                axes[1,0].plot(rows.index/4,rows.driver_bias,color=color)
                axes[1,1].plot(rows.index/4,rows.state_oracle_rmse,color=color)
        axes[0,0].set_ylabel('AQL (scaled price)'); axes[0,1].set_ylabel('80% interval coverage'); axes[0,1].axhline(.8,color='#555555',ls=':')
        axes[1,0].set_ylabel('Normal driver bias (scaled price)'); axes[1,0].axhline(0,color='#555555',ls=':')
        axes[1,1].set_ylabel('Mean-state RMSE vs oracle')
        axes[0,0].legend(); fig.suptitle('Internal splits and origin offsets averaged equally')
        for ax in axes.flat: ax.set_xlabel('Lead (hours)'); ax.grid(alpha=.2)
        fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
        fig,ax=plt.subplots(figsize=(11.7,8.3)); ax.axis('off')
        ax.set_title('Interpretation and next decision',loc='left',pad=20)
        import textwrap
        lines=['Internal equal-split/offset AQL:']+[f'  {k}: {v:.6f}' for k,v in decision['internal_equal_split_offset_AQL'].items()]
        lines+=['',f'Oracle relative reduction: {100*decision["internal_oracle_relative_reduction"]:.1f}%', '',
            *textwrap.wrap(decision['interpretation'],105),'',*textwrap.wrap(decision['recommended_next_step'],105),'','Limits:']
        for item in decision['limitations']: lines.extend(textwrap.wrap('- '+item,105))
        ax.text(0,.98,'\n'.join(lines),va='top',transform=ax.transAxes,linespacing=1.5)
        fig.tight_layout(); pdf.savefig(fig); plt.close(fig)
