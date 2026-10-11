"""Held-out, same-fit controls and a read-only official-results report."""
from pathlib import Path

import numpy as np
import pandas as pd

CONTROLS = ('stochastic', 'parameter_only', 'mean_driver', 'oracle')
FORBIDDEN = ('new_fitting_authorized', 'new_screening_authorized',
             'test_reforecast_authorized', 'selection_uses_test',
             'automatic_model_selection_authorized', 'priors_from_initializers',
             'promotion_authorized', 'registry_mutation_authorized',
             'article_mutation_authorized', 'all_region_launch_authorized')


def validate_protocol(p):
    expected = dict(regions=['HR', 'DK_1'], folds=[1, 2, 3],
        quantiles=[.1, .25, .45, .5, .55, .75, .9], origins_per_clock=12,
        origin_offsets_steps=[0, 24, 48, 72], step_minutes=15,
        horizon_steps=96, paths=500, chunk_origins=3, maximum_workers=15,
        controls=list(CONTROLS), primary_operator='cdf_pool_clipped',
        validation_support='after_fitted_response_end_and_before_fold_test_start',
        minimum_free_memory_GiB=200, minimum_free_disk_GiB=200,
        maximum_campaign_output_GiB=.75, oracle_diagnostic_only=True)
    for key, value in expected.items():
        if p.get(key) != value:
            raise ValueError('frozen diagnostic protocol changed: ' + key)
    for key in FORBIDDEN:
        if p.get(key) is not False:
            raise ValueError('unauthorized expansion: ' + key)


def validation_grid(train_end, test_start, p):
    days = pd.date_range(train_end, test_start, inclusive='left', tz='UTC', freq='D')
    if len(days) < p['origins_per_clock'] + 1:
        raise ValueError('insufficient complete held-out days')
    selected = np.linspace(0, len(days) - 2, p['origins_per_clock'], dtype=int)
    rows = []
    for offset in p['origin_offsets_steps']:
        for day in selected:
            rows.append(dict(position=int(day * 96 + offset), offset=offset,
                anchor=(days[day] + pd.Timedelta(minutes=15 * offset)).isoformat()))
    check_support([r['anchor'] for r in rows], train_end, test_start)
    return rows


def check_support(anchors, train_end, test_start):
    origins = pd.DatetimeIndex(pd.to_datetime(anchors, utc=True))
    start, end = pd.Timestamp(train_end, tz='UTC'), pd.Timestamp(test_start, tz='UTC')
    if (not len(origins) or not origins.is_unique or np.any(origins < start)
            or np.any(origins + pd.Timedelta(days=1) > end)):
        raise ValueError('response overlaps fitted observations or official test')


def task_schedule(cells, p):
    tasks = []
    for cell in cells:
        for offset in p['origin_offsets_steps']:
            indices = [i for i, r in enumerate(cell['grid']) if r['offset'] == offset]
            pieces = [indices[:1]] + [indices[i:i + p['chunk_origins']]
                for i in range(1, len(indices), p['chunk_origins'])]
            for chunk, idx in enumerate(pieces):
                tasks.append(dict(name=f"{cell['region']}_f{cell['fold']}_h{offset:02d}_c{chunk:02d}",
                    region=cell['region'], fold=cell['fold'], offset=offset,
                    bank_indices=idx, positions=[cell['grid'][i]['position'] for i in idx],
                    smoke=chunk == 0))
    if len(tasks) != 120 or sum(t['smoke'] for t in tasks) != 24:
        raise ValueError('bounded 288-origin diagnostic schedule differs')
    return tasks


def complete_cell(packets, grid):
    values = {k: np.concatenate([z[k] for z in packets]) for k in packets[0]}
    order = np.argsort(values['bank_indices'])
    for key in values:
        values[key] = values[key][order]
    if not np.array_equal(values['bank_indices'], np.arange(len(grid))):
        raise ValueError('missing or duplicated diagnostic bank origin')
    expected = pd.DatetimeIndex(pd.to_datetime([r['anchor'] for r in grid], utc=True)).as_unit('ns').asi8
    if not np.array_equal(values['anchors_ns'], expected):
        raise ValueError('diagnostic origin identity differs')
    if not np.array_equal(values['positions'], [r['position'] for r in grid]):
        raise ValueError('diagnostic seed identity differs')
    return values


def summarize_cell(values, cell, common_metrics):
    rows = []
    truth = values['truth']
    for offset in (0, 24, 48, 72):
        idx = [i for i, r in enumerate(cell['grid']) if r['offset'] == offset]
        for mode in CONTROLS:
            rows.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=offset,
                operator=mode, **common_metrics(truth[idx], values[mode][idx])))
    lead_rows = []
    for offset in (0, 24, 48, 72):
        idx = [i for i, r in enumerate(cell['grid']) if r['offset'] == offset]
        for mode in CONTROLS:
            for h in range(96):
                error = truth[idx, h, None] - values[mode][idx, h]
                loss = np.maximum(np.array([.1,.25,.45,.5,.55,.75,.9]) * error,
                    (np.array([.1,.25,.45,.5,.55,.75,.9]) - 1) * error)
                lead_rows.append(dict(region=cell['region'], fold=cell['fold'], offset_steps=offset,
                    operator=mode, lead_step=h + 1, target_clock_step=(offset + h) % 96,
                    AQL=float(loss.mean())))
    return rows, lead_rows


def plot_report(path, official, validation, leads, controls, traces, official_curves=None):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages
    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False,
        'axes.spines.right': False, 'axes.grid': True, 'grid.alpha': .15,
        'pdf.fonttype': 42})
    colors = dict(stochastic='#087f8c', parameter_only='#d1495b',
        mean_driver='#6741a5', oracle='#228b22')
    with PdfPages(path) as pdf:
        fig, ax = plt.subplots(figsize=(11.7, 8.3)); ax.axis('off')
        fig.suptitle('PriceFM R130 | Same-fit forecast diagnosis', fontsize=18, y=.95)
        rows = []
        for region in ('DK_1', 'HR'):
            part = official[(official.region == region) & (official.operator == 'cdf_pool_clipped')]
            rows.append([region] + [f'{part[k].mean():.3f}' for k in
                ('AQL', 'qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')])
        table = ax.table(cellText=rows, colLabels=['Region', 'New recursive', 'Frozen R98',
            'Cached PriceFM', 'Local Phase I/II'], bbox=[.02,.66,.96,.19], cellLoc='center')
        table.auto_set_font_size(False); table.set_fontsize(11)
        ax.text(.02,.59,'Official scores are descriptive and unchanged. Lower AQL is better.', transform=ax.transAxes)
        text = ('Validation: saved fits, no refitting; 288 origins across six region/fold cells.\n'
                'Four origin clocks separate lead length from time-of-day difficulty.\n'
                'Oracle uses true future price prefixes only as a diagnostic control.\n'
                'All curves use the same frozen receiver draws and CDF-pooling convention.\n'
                'Equal permitted dates do not imply identical early training-response rows.\n'
                'Historical windows have been examined; no confirmatory superiority claim.\n'
                'No automatic model selection, article replacement or all-region rollout.')
        ax.text(.02,.49,text,va='top',linespacing=1.9,transform=ax.transAxes)
        pdf.savefig(fig); plt.close(fig)
        for region in ('DK_1','HR'):
            fig, axes = plt.subplots(2,2,figsize=(11.7,8.3),sharex=True,sharey=True)
            fig.suptitle(f'{region} | Held-out AQL by lead and origin clock',fontsize=16)
            for ax,offset in zip(axes.flat,(0,24,48,72)):
                for mode in CONTROLS:
                    part = leads[(leads.region==region)&(leads.offset_steps==offset)&(leads.operator==mode)]
                    curve = part.groupby('lead_step').AQL.mean()
                    ax.plot(curve.index/4,curve.values,label=mode.replace('_',' '),color=colors[mode],lw=1.7)
                ax.set_title(f'Origin {offset//4:02d}:00, fixed market clock')
                ax.set_xlabel('Hours ahead'); ax.set_ylabel('AQL (EUR/MWh)')
            axes[0,0].legend(fontsize=9); fig.tight_layout(rect=[0,0,1,.95]); pdf.savefig(fig); plt.close(fig)
            fig, axes = plt.subplots(1,2,figsize=(11.7,8.3))
            fig.suptitle(f'{region} | Calibration and driver effects',fontsize=16)
            summary = validation[validation.region==region].groupby('operator').mean(numeric_only=True).reindex(CONTROLS)
            axes[0].bar(np.arange(4),summary.AQL,color=[colors[k] for k in CONTROLS])
            axes[0].set_xticks(np.arange(4),['Stochastic','Parameter\nonly','Mean\ndriver','Oracle'])
            axes[0].set_ylabel('Equal-fold, equal-clock AQL')
            axes[1].bar(np.arange(4),summary.coverage_80*100,color=[colors[k] for k in CONTROLS])
            axes[1].axhline(80,color='black',ls='--',label='Nominal 80%')
            axes[1].set_xticks(np.arange(4),['Stochastic','Parameter\nonly','Mean\ndriver','Oracle'])
            axes[1].set_ylim(0,100); axes[1].set_ylabel('80% interval coverage (%)'); axes[1].legend()
            fig.tight_layout(rect=[0,.03,1,.95]); pdf.savefig(fig); plt.close(fig)
        for region in ('DK_1','HR'):
            fig, axes = plt.subplots(3,2,figsize=(11.7,8.3))
            fig.suptitle(f'{region} | Frozen public AL objective and scale traces',fontsize=16)
            for fold in (1,2,3):
                for q,frame in traces[region,fold]:
                    iteration=frame['iter' if 'iter' in frame else 'iteration']
                    axes[fold-1,0].plot(iteration,frame.elbo,label=f'{q:g}',lw=.9)
                    axes[fold-1,1].plot(iteration,frame.sigma,label=f'{q:g}',lw=.9)
                axes[fold-1,0].set_ylabel(f'Fold {fold}\nRaw ELBO'); axes[fold-1,1].set_ylabel('Scale')
            axes[0,0].legend(ncol=4,fontsize=8);axes[-1,0].set_xlabel('Iteration');axes[-1,1].set_xlabel('Iteration')
            fig.tight_layout(rect=[0,0,1,.95]);pdf.savefig(fig);plt.close(fig)
        for (region,fold),v in (official_curves or {}).items():
            i=len(v['truth'])//2;h=np.arange(1,97)/4
            fig,axes=plt.subplots(2,1,figsize=(11.7,8.3),sharex=True)
            fig.suptitle(f'{region} fold {fold} | Frozen official forecasts (not rerun)',fontsize=16)
            for ax,mode,title,color in zip(axes,('cdf_pool_clipped','normal_driver'),
                ('AL quantile receiver, pooled distribution','Normal RHS driver alone'),('#087f8c','#d1495b')):
                ax.plot(h,v['truth'][i],color='#222222',lw=1.8,label='Observed')
                ax.plot(h,v[mode][i,:,3],color=color,label='Median')
                ax.fill_between(h,v[mode][i,:,0],v[mode][i,:,-1],color=color,alpha=.20,label='80% interval')
                ax.set_title(title);ax.set_ylabel('EUR/MWh');ax.legend(ncol=3)
            axes[-1].set_xlabel('Hours ahead; prespecified calendar-middle origin')
            fig.tight_layout(rect=[0,0,1,.95]);pdf.savefig(fig);plt.close(fig)
        for (region,fold),v in controls.items():
            i=0
            fig, axes=plt.subplots(2,1,figsize=(11.7,8.3),sharex=True)
            fig.suptitle(f'{region} fold {fold} | Prespecified first validation origin',fontsize=16)
            h=np.arange(1,97)/4
            axes[0].plot(h,v['truth'][i],color='#222222',lw=1.7,label='Observed price')
            for mode in ('stochastic','oracle'):
                axes[0].plot(h,v[mode][i,:,3],color=colors[mode],label=mode.title())
                axes[0].fill_between(h,v[mode][i,:,0],v[mode][i,:,-1],color=colors[mode],alpha=.16)
            axes[0].set_ylabel('Price (EUR/MWh)');axes[0].legend(ncol=3)
            for mi,mode in enumerate(CONTROLS[:3]):
                axes[1].plot(h,v['driver_mean'][i,:,mi],color=colors[mode],label=mode.replace('_',' '))
            axes[1].plot(h,v['truth'][i],color='#222222',lw=1.5,label='Observed price')
            axes[1].set_xlabel('Hours ahead');axes[1].set_ylabel('Driver mean (EUR/MWh)');axes[1].legend(ncol=2)
            fig.tight_layout(rect=[0,0,1,.95]);pdf.savefig(fig);plt.close(fig)


def closeout(out, prep, verified, read, write, seal, common_metrics):
    path = out/'closeout'
    if path.exists():
        verified(path)
        return read(path/'interpretation.json')
    all_rows=[];all_leads=[];controls={};diagnostics=[];traces={};official_curves={};official_rows=[]
    for cell in prep['cells']:
        packets=[]
        for t in prep['tasks']:
            if (t['region'],t['fold']) != (cell['region'],cell['fold']):continue
            folder=out/'tasks_done'/t['name'];verified(folder)
            with np.load(folder/'predictions.npz',allow_pickle=False) as z:
                packets.append({k:z[k] for k in z.files})
        v=complete_cell(packets,cell['grid']); controls[cell['region'],cell['fold']]=v
        rows,leads=summarize_cell(v,cell,common_metrics);all_rows+=rows;all_leads+=leads
        for mi,mode in enumerate(CONTROLS[:3]):
            diagnostics.append(dict(region=cell['region'],fold=cell['fold'],operator=mode,
                driver_bias=float((v['driver_mean'][:,:,mi]-v['truth']).mean()),
                driver_rmse=float(np.sqrt(np.mean((v['driver_mean'][:,:,mi]-v['truth'])**2))),
                mean_driver_sd=float(v['driver_sd'][:,:,mi].mean()),
                state_oracle_rmse=float(v['state_oracle_rmse'][:,:,mi].mean()),
                saturation=float(v['saturated_fraction'][:,:,mi].mean()),
                near_linear=float(v['near_linear_fraction'][:,:,mi].mean())))
        traces[cell['region'],cell['fold']]=[]
        for q,folder in cell['quantile_dirs'].items():
            file=Path(folder)/'vb_trace.csv'
            if not file.exists():
                file=Path(cell['original_median'])/'vb_trace.csv'
            traces[cell['region'],cell['fold']].append((float(q),pd.read_csv(file)))
        packets=[]
        for t in prep['parent_tasks']:
            if t['kind']!='forecast' or (t['region'],t['fold'])!=(cell['region'],cell['fold']):continue
            folder=Path(prep['parent_out'])/'tasks_done'/t['name'];verified(folder)
            with np.load(folder/'predictions.npz',allow_pickle=False) as z:
                packets.append({k:z[k] for k in z.files})
        original={k:np.concatenate([z[k] for z in packets]) for k in packets[0]}
        order=np.argsort(original['positions']);original={k:v[order] for k,v in original.items()}
        count=prep['official_protocol']['test_origin_counts'][cell['fold']-1]
        if not np.array_equal(original['positions'],np.arange(count)):
            raise ValueError('frozen official cohort incomplete')
        expected=pd.date_range(prep['official_protocol']['test_intervals_market'][cell['fold']-1][0],
            periods=count,tz='UTC',freq='D').as_unit('ns').asi8
        if not np.array_equal(original['anchors_ns'],expected):
            raise ValueError('frozen official anchor identity differs')
        official_curves[cell['region'],cell['fold']]=original
        for mode in ('cdf_pool_clipped','normal_driver','mean_feature','path_specific'):
            full=common_metrics(original['truth'],original[mode])
            for a,b in ((0,24),(24,48),(48,72),(72,96)):
                error=original['truth'][:,a:b,None]-original[mode][:,a:b]
                cost=np.maximum(np.array([.1,.25,.45,.5,.55,.75,.9])*error,
                    (np.array([.1,.25,.45,.5,.55,.75,.9])-1)*error)
                official_rows.append(dict(region=cell['region'],fold=cell['fold'],operator=mode,
                    lead_start_hour=a/4,lead_end_hour=b/4,AQL=float(cost.mean()),
                    recomputed_full_AQL=full['AQL']))
    validation=pd.DataFrame(all_rows);leads=pd.DataFrame(all_leads)
    official=pd.read_csv(Path(prep['parent_out'])/'closeout/fold_comparison.csv')
    for row in official_rows:
        saved=official[(official.region==row['region'])&(official.fold==row['fold'])&(official.operator==row['operator'])]
        if len(saved)!=1 or abs(row['recomputed_full_AQL']-saved.iloc[0].AQL)>1e-10:
            raise ValueError('saved official AQL changed')
    path.mkdir()
    validation.to_csv(path/'validation_metrics.csv',index=False)
    leads.to_csv(path/'lead_clock_metrics.csv',index=False)
    pd.DataFrame(diagnostics).to_csv(path/'driver_state_diagnostics.csv',index=False)
    summary=validation.groupby(['region','operator']).mean(numeric_only=True).reset_index()
    summary.to_csv(path/'region_control_summary.csv',index=False)
    official.to_csv(path/'frozen_official_comparison.csv',index=False)
    pd.DataFrame(official_rows).to_csv(path/'frozen_official_horizon_metrics.csv',index=False)
    findings=[]
    for region in ('DK_1','HR'):
        r=summary[summary.region==region].set_index('operator')
        findings.append(dict(region=region,causal_AQL=float(r.loc['stochastic','AQL']),
            oracle_AQL=float(r.loc['oracle','AQL']),
            oracle_reduction_pct=float(100*(1-r.loc['oracle','AQL']/r.loc['stochastic','AQL'])),
            parameter_only_AQL=float(r.loc['parameter_only','AQL']),
            mean_driver_AQL=float(r.loc['mean_driver','AQL'])))
    interpretation=dict(source=prep['source'],new_fits=0,diagnostic_origins=288,
        official_reforecast=False,oracle_operational=False,findings=findings,
        automatic_model_selection=False,authority_replaced=False,
        confirmatory_claim=False,followup='review lead and target clock before prescribing a driver or representation correction')
    write(path/'interpretation.json',interpretation)
    plot_report(path/'pricefm_r130_forecast_error_attribution.pdf',official,validation,leads,controls,traces,official_curves)
    seal(path,dict(source=prep['source'],complete_origins=288))
    return interpretation
