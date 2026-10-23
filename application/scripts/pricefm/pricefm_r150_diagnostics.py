#!/usr/bin/env python3
"""R150 read-only retained-forecast diagnosis. No numerical model entry point.

Collect/verify the five original producers before analyzing EUR/MWh arrays.
The remote collector streams one bounded tar on stdout and writes nothing there.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import time

for _name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
              'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS'):
    os.environ[_name] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'

DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
LEVELS = (.1, .25, .45, .5, .55, .75, .9)
OPERATORS = ('cdf_pool_clipped', 'cdf_pool_linear', 'mean_feature', 'path_specific',
             'normal_driver', 'rearranged_path_mean')
PRIMARY = 'cdf_pool_clipped'
DAY_NS = 86400 * 10**9
HOUR_NS = 3600 * 10**9
CAMPAIGNS = {
    'EE': 'pricefm_stage_r137_four_region_pilot_20261015__EE',
    'DE_LU': 'pricefm_stage_r141_recovery_rollout_20261019__DE_LU',
    'DK_2': 'pricefm_stage_r141_recovery_rollout_20261019__DK_2',
    'DK_1': 'pricefm_stage_r141_recovery_rollout_20261019__DK_1',
    'DK_1_R138': 'pricefm_stage_r138_dk1_diverse_driver_20261016',
}


class EvidenceError(RuntimeError):
    pass


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def verify_seal(folder):
    folder = Path(folder)
    seal = read(folder / 'completed_evidence.json')
    for name, expected in seal['artifacts'].items():
        path = (folder / name).resolve()
        require(path.is_relative_to(folder.resolve()), 'unsafe sealed artifact: ' + name)
        require(digest(path) == expected, 'sealed artifact changed: ' + str(path))
    return seal


def collect_campaign(label, checked):
    """Hash original sources, inputs, bank, raw identity and all official packets."""
    campaign = DATA / 'campaigns' / CAMPAIGNS[label]
    prep_path = DATA / 'launch_prep' / CAMPAIGNS[label] / 'preparation.json'
    prep = read(prep_path)
    source_checks = {}
    for category in ('source_sha256', 'input_sha256', 'bank_sha256'):
        for filename, expected in prep[category].items():
            key = (filename, expected)
            if key not in checked:
                checked[key] = digest(filename)
            require(checked[key] == expected, category + ' mismatch: ' + filename)
            source_checks[filename] = expected
    release = Path(prep['release_path'])
    require(digest(release) == prep['release_sha256'], 'release pin changed')
    raw = DATA / 'raw/FINAL.csv'
    raw_key = (str(raw), prep['raw_identity']['sha256'])
    if raw_key not in checked:
        checked[raw_key] = digest(raw)
    require(checked[raw_key] == raw_key[1], 'raw identity changed')
    protocol = prep['official_protocol']
    require(protocol['market_clock'] == 'physical_UTC_plus_fixed_one_hour_no_DST',
            'unsupported official clock')
    require(protocol['quantiles'] == list(LEVELS) and protocol['horizon_steps'] == 96,
            'official scoring geometry changed')
    packets, files = [], []
    region = label.replace('_R138', '')
    for task_path in sorted((campaign / 'tasks').glob(region + '_fold*_forecast*.json')):
        task = read(task_path)
        require(task['kind'] == 'forecast' and task['region'] == region, 'wrong task role')
        folder = campaign / 'tasks_done' / task['name']
        seal = verify_seal(folder)
        meta = seal['metadata']
        require(meta['certified'] is True, 'uncertified official packet')
        require(meta['source_head'] == prep['source']['head'], 'producer source drift')
        require(meta['task_sha256'] == digest(task_path), 'task descriptor changed')
        packets.append(dict(task=task, task_sha256=digest(task_path),
                            seal_sha256=digest(folder / 'completed_evidence.json'),
                            artifacts=seal['artifacts'], folder=str(folder)))
        for filename in ('predictions.npz', 'completed_evidence.json', 'result.json'):
            files.append((folder / filename, label + '/tasks_done/' + task['name'] + '/' + filename))
        files.append((task_path, label + '/tasks/' + task_path.name))
    require(len(packets) == 32, 'exactly 32 sealed official packets required: ' + label)
    closeout = verify_seal(campaign / 'closeout')
    for filename in closeout['artifacts']:
        files.append((campaign / 'closeout' / filename, label + '/closeout/' + filename))
    files.append((campaign / 'closeout/completed_evidence.json', label + '/closeout/completed_evidence.json'))
    for filename in ('terminal.json', 'frozen_choice.json', 'frozen_choices.json', 'wave1_gate.json'):
        if (campaign / filename).exists():
            files.append((campaign / filename, label + '/' + filename))
    # Full prep contains enormous unrelated historical inventories. Preserve only exact
    # identities used in this reader; source/input maps are complete, not summarized.
    reduced = {k: prep[k] for k in ('source', 'source_sha256', 'input_sha256', 'bank_sha256',
                'raw_identity', 'official_protocol', 'release_path', 'release_sha256',
                'official_development_test_seen_previously', 'test_used_for_selection') if k in prep}
    manifest = dict(label=label, campaign=str(campaign), preparation=str(prep_path),
                    preparation_sha256=digest(prep_path), checked_source_input_bank_count=len(source_checks),
                    checked_source_input_bank_sha256=source_checks, release_sha256=prep['release_sha256'],
                    raw_sha256=raw_key[1], source=prep['source'], packets=packets,
                    closeout_seal_sha256=digest(campaign / 'closeout/completed_evidence.json'))
    return manifest, reduced, files


def remote_collect():
    checked, all_files, manifests, preparations = {}, [], {}, {}
    for label in ('DK_1', 'DK_1_R138'):
        manifest, prep, files = collect_campaign(label, checked)
        manifests[label], preparations[label] = manifest, prep
        all_files.extend(files)
    with tarfile.open(fileobj=sys.stdout.buffer, mode='w|') as archive:
        for path, name in all_files:
            archive.add(str(path), arcname=name, recursive=False)
        for name, value in [('remote_manifest.json', manifests), ('remote_preparations.json', preparations)]:
            content = json.dumps(value, sort_keys=True).encode()
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))


def extract_safe(archive_path, destination):
    """Accept only ordinary files inside the predeclared two diagnostic labels."""
    destination = Path(destination)
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        names = [m.name for m in members]
        require(len(names) == len(set(names)), 'duplicate archive entry')
        for member in members:
            target = (destination / member.name).resolve()
            require(member.isfile() and target.is_relative_to(destination.resolve()), 'unsafe archive entry')
            require(member.name.split('/')[0] in ('DK_1', 'DK_1_R138', 'remote_manifest.json',
                                                'remote_preparations.json'), 'unexpected archive namespace')
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, target.open('wb') as output:
                output.write(source.read())


def market_to_physical_ns(market_ns):
    """Market labels are physical UTC + fixed one hour, with no DST."""
    import numpy as np
    return np.asarray(market_ns, dtype=np.int64) - HOUR_NS


def euros(standardized, mean, scale):
    import numpy as np
    require(scale > 0 and np.isfinite([mean, scale]).all(), 'invalid scaler')
    return np.asarray(standardized) * scale + mean


def pinball(truth, prediction):
    import numpy as np
    truth, prediction = np.asarray(truth), np.asarray(prediction)
    require(prediction.shape == truth.shape + (7,), 'quantile shape differs')
    require(np.isfinite(truth).all() and np.isfinite(prediction).all(), 'nonfinite retained arrays')
    error = truth[..., None] - prediction
    return np.maximum(np.asarray(LEVELS) * error, (np.asarray(LEVELS) - 1) * error)


def summarize(truth, prediction):
    import numpy as np
    losses = pinball(truth, prediction)
    below = np.mean(truth[..., None] < prediction, axis=(0, 1))
    at_below = np.mean(truth[..., None] <= prediction, axis=(0, 1))
    out = dict(AQL=float(losses.mean()), median_MAE=float(np.abs(truth-prediction[..., 3]).mean()),
               median_bias_prediction_minus_truth=float((prediction[..., 3]-truth).mean()),
               crossing_rate=float(np.mean(prediction[..., :-1] > prediction[..., 1:])),
               lower_tail_miss=float(np.mean(truth < prediction[..., 0])),
               upper_tail_miss=float(np.mean(truth > prediction[..., 6])),
               n_origins=len(truth), n_response_values=int(truth.size),
               quantile_loss=losses.mean(axis=(0, 1)).tolist(),
               below_strict=below.tolist(), below_inclusive=at_below.tolist(),
               tie_frequency=(at_below-below).tolist())
    for pct, lo, hi in ((80, 0, 6), (50, 1, 5), (10, 2, 4)):
        out['coverage_' + str(pct)] = float(np.mean((truth >= prediction[..., lo]) & (truth <= prediction[..., hi])))
        out['width_' + str(pct)] = float(np.mean(prediction[..., hi]-prediction[..., lo]))
    return out


def contribution(values, group, weights):
    """Original-target weighted contributions; groups sum to the primary contrast."""
    import numpy as np
    values, weights = np.asarray(values), np.asarray(weights)
    require(values.shape == weights.shape and np.isclose(weights.sum(), 1), 'invalid target weights')
    return {str(label): float(np.sum(values[np.asarray(group) == label] * weights[np.asarray(group) == label]))
            for label in np.unique(group)}


def csv_write(path, rows):
    keys = list(dict.fromkeys(key for row in rows for key in row))
    with Path(path).open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)


def training_bank_evidence(manifests):
    """Inspect only training-bank metadata/anchors, never raw official values."""
    import numpy as np
    import zipfile
    inspected={}
    for label in ('EE','DE_LU','DK_2'):
        bank=next(Path(path) for path in manifests[label]['checked_source_input_bank_sha256']
                  if path.endswith('/target_only.npz'))
        schema={}
        with zipfile.ZipFile(bank) as archive:
            for name in archive.namelist():
                with archive.open(name) as handle:
                    version=np.lib.format.read_magic(handle)
                    shape,order,dtype=np.lib.format._read_array_header(handle,version)
                    schema[name]=dict(shape=list(shape),fortran_order=order,dtype=str(dtype))
        with np.load(bank,allow_pickle=False) as values:
            anchors=values['anchors']
            first,last=str(anchors[0]),str(anchors[-1])
        inspected[label]=dict(path=str(bank),sha256=digest(bank),schema=schema,
            first_training_anchor_market=first,last_training_anchor_market=last,
            complete_official_2025_lag_history_available=False,
            reason='Training bank ends2024-08-31; official daily anchors span2025. Saved official NPZ has truth/predictions/positions/anchors only. Official design X/y/scaler is not a saved raw lag-history cohort.')
    return dict(status='FULL_OFFICIAL_LAG_REGIMES_UNAVAILABLE_WITHIN_RETAINED_INPUTS',
        local_banks=inspected,remote_banks='Rehashed in Jerez collection; bank arrays were not transferred or claimed inspected.',
        no_substitution='No response-derived contemporaneous volatility or dropped-origin regime analysis is substituted.')


def load_packets(label, manifest, prep, remote_root=None):
    import numpy as np
    import pandas as pd
    by_fold = {}
    for fold in (1, 2, 3):
        packets = sorted((p for p in manifest['packets'] if p['task']['fold'] == fold),
                         key=lambda p: p['task']['positions'][0])
        values = []
        for record in packets:
            folder = Path(record['folder']) if remote_root is None else remote_root / label / 'tasks_done' / record['task']['name']
            require(digest(folder / 'completed_evidence.json') == record['seal_sha256'], 'seal moved after collection')
            verify_seal(folder)
            with np.load(folder / 'predictions.npz', allow_pickle=False) as packet:
                require(set(packet.files) == set(OPERATORS) | {'truth', 'positions', 'anchors_ns'}, 'retained array schema changed')
                value = {key: packet[key] for key in packet.files}
            require(value['positions'].tolist() == record['task']['positions'], 'task positions mismatch')
            losses = {operator: summarize(value['truth'], value[operator]) for operator in OPERATORS}
            sealed_result = read(folder / 'result.json')
            for operator in OPERATORS:
                for key in ('AQL', 'median_MAE', 'coverage_80', 'width_80'):
                    require(np.isclose(losses[operator][key], sealed_result['metrics'][operator][key], atol=1e-11, rtol=1e-12),
                            'sealed metric does not replay: ' + label + '/' + key)
                require(np.allclose(1-np.asarray(losses[operator]['below_inclusive']),
                                    sealed_result['metrics'][operator]['exceedance'], atol=1e-12, rtol=0),
                        'sealed exceedance tie convention differs')
            values.append(value)
        combined = {key: np.concatenate([p[key] for p in values]) for key in values[0]}
        count = prep['official_protocol']['test_origin_counts'][fold - 1]
        require(combined['truth'].shape == (count, 96), 'incomplete H96 cohort')
        require(np.array_equal(combined['positions'], np.arange(count)), 'duplicate/missing origin')
        start, end = prep['official_protocol']['test_intervals_market'][fold-1]
        expected = pd.date_range(start, end, inclusive='left', freq='D', tz='UTC').as_unit('ns').asi8
        require(np.array_equal(combined['anchors_ns'], expected), 'market timestamp identity changed')
        require(np.all(np.diff(market_to_physical_ns(combined['anchors_ns'])) == DAY_NS), 'official daily clock changed')
        by_fold[fold] = combined
    return by_fold


def analyze(label, folds, output):
    import numpy as np
    import pandas as pd
    metrics, quantiles, horizons, origins, operators = [], [], [], [], []
    macro = {}
    for operator in OPERATORS:
        fold_summaries = []
        for fold, values in folds.items():
            truth, prediction = values['truth'], values[operator]
            summary = summarize(truth, prediction)
            fold_summaries.append(summary)
            metrics.append(dict(label=label, fold=fold, operator=operator,
                                **{k:v for k,v in summary.items() if not isinstance(v, list)}))
            for qi, q in enumerate(LEVELS):
                quantiles.append(dict(label=label, fold=fold, operator=operator, quantile=q,
                    AQL_quantile=summary['quantile_loss'][qi], primary_AQL_contribution=summary['quantile_loss'][qi]/21,
                    below_strict=summary['below_strict'][qi], below_inclusive=summary['below_inclusive'][qi],
                    tie_frequency=summary['tie_frequency'][qi], nominal=q))
            losses = pinball(truth, prediction)
            primary_losses = pinball(truth, values[PRIMARY])
            for block in range(4):
                section = slice(block*24, (block+1)*24)
                small = summarize(truth[:, section], prediction[:, section])
                horizons.append(dict(label=label, fold=fold, operator=operator, first_step=block*24+1,
                    last_step=(block+1)*24, hours_from_origin_start=block*6,
                    AQL=small['AQL'], primary_AQL_contribution=small['AQL']/12,
                    coverage_80=small['coverage_80'], lower_tail_miss=small['lower_tail_miss'],
                    upper_tail_miss=small['upper_tail_miss'], width_80=small['width_80'],
                    n_response_values=small['n_response_values']))
            delta = losses.mean(axis=(1,2)) - primary_losses.mean(axis=(1,2))
            for i, anchor in enumerate(values['anchors_ns']):
                origins.append(dict(label=label, fold=fold, operator=operator, origin_position=i,
                    anchor_market=pd.Timestamp(anchor, tz='UTC').isoformat(),
                    anchor_physical_UTC=pd.Timestamp(market_to_physical_ns(anchor), tz='UTC').isoformat(),
                    month_market=pd.Timestamp(anchor, tz='UTC').strftime('%Y-%m'),
                    weekday_market=pd.Timestamp(anchor, tz='UTC').dayofweek,
                    AQL=float(losses[i].mean()), AQL_contribution=float(losses[i].mean()/(3*len(truth))),
                    delta_AQL_vs_primary=float(delta[i]), delta_contribution=float(delta[i]/(3*len(truth))),
                    median_absolute_error=float(np.abs(truth[i]-prediction[i,:,3]).mean()),
                    lower_tail_miss=float(np.mean(truth[i]<prediction[i,:,0])),
                    upper_tail_miss=float(np.mean(truth[i]>prediction[i,:,6]))))
            operators.append(dict(label=label, fold=fold, operator=operator,
                delta_AQL_vs_primary=float(delta.mean()), primary_delta_contribution=float(delta.mean()/3),
                fraction_origins_lower_loss=float(np.mean(delta<0)),
                delta_coverage_80=summary['coverage_80']-summarize(truth, values[PRIMARY])['coverage_80']))
        scalar = [k for k,v in fold_summaries[0].items() if not isinstance(v,list) and not k.startswith('n_')]
        macro[operator] = {key:float(np.mean([row[key] for row in fold_summaries])) for key in scalar}
        for key in ('quantile_loss','below_strict','below_inclusive','tie_frequency'):
            macro[operator][key] = np.mean([row[key] for row in fold_summaries],axis=0).tolist()
        pooled_truth=np.concatenate([values['truth'] for values in folds.values()])
        pooled_prediction=np.concatenate([values[operator] for values in folds.values()])
        macro[operator]['secondary_pooled_AQL']=summarize(pooled_truth,pooled_prediction)['AQL']
        require(np.isclose(sum(r['primary_AQL_contribution'] for r in quantiles if r['operator']==operator),macro[operator]['AQL']), 'quantile contribution sum mismatch')
        require(np.isclose(sum(r['primary_AQL_contribution'] for r in horizons if r['operator']==operator),macro[operator]['AQL']), 'horizon contribution sum mismatch')
        require(np.isclose(sum(r['AQL_contribution'] for r in origins if r['operator']==operator),macro[operator]['AQL']), 'origin contribution sum mismatch')
    calendar=[]
    for operator in OPERATORS:
        selected=[row for row in origins if row['operator']==operator]
        for key in ('month_market','weekday_market'):
            for group in sorted(set(row[key] for row in selected)):
                group_rows=[row for row in selected if row[key]==group]
                weight=sum(1/(3*len(folds[row['fold']]['truth'])) for row in group_rows)
                total=sum(row['AQL_contribution'] for row in group_rows)
                calendar.append(dict(label=label,operator=operator,grouping=key,group=group,
                    n_origins=len(group_rows),primary_weight=weight,AQL_contribution=total,
                    weighted_group_AQL=total/weight,
                    delta_AQL_vs_primary_contribution=sum(row['delta_contribution'] for row in group_rows)))
    for filename, rows in [('fold_metrics.csv',metrics),('quantile_reliability.csv',quantiles),
                            ('horizon_blocks.csv',horizons),('origin_influence.csv',origins),
                            ('paired_operators.csv',operators),('calendar_groups.csv',calendar)]:
        csv_write(output/(label+'_'+filename),rows)
    return macro


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect-remote',action='store_true')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--fetch-remote',action='store_true')
    parser.add_argument('--attested-analysis',action='store_true')
    args=parser.parse_args()
    if args.collect_remote:
        remote_collect(); return
    require(args.output is not None, '--output required')
    execution=dict(pid=os.getpid(),ppid=os.getppid(),affinity=sorted(os.sched_getaffinity(0)),
                   scheduler=os.sched_getscheduler(0),numerical_thread_environment={name:os.environ[name]
                     for name in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS',
                                  'BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS')},
                   initial_analysis_record_gap='Initial analysis-only diagnostic pass inherited affinity/scheduler and did not record them; no confinement claim applies retrospectively.')
    if args.attested_analysis:
        require(execution['affinity']==[29] and execution['scheduler']==os.SCHED_IDLE,
                'attested analysis requires CPU29 and SCHED_IDLE before numerical imports')
        execution['ionice']=subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).strip()
        require(execution['ionice']=='idle','attested analysis requires idle I/O')
    output=args.output.resolve(); output.mkdir(parents=True,exist_ok=True)
    start=time.time(); checked={}; manifests={}; preparations={}
    for label in ('EE','DE_LU','DK_2'):
        manifests[label],preparations[label],_=collect_campaign(label,checked)
    remote=output/'remote_inputs'; archive=output/'jerez_retained_inputs.tar'
    if args.fetch_remote:
        require(not archive.exists(), 'remote archive already exists; explicit reuse instead of overwrite')
        python=str(DATA/'runtime_envs/r137_py311/bin/python')
        command=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=15','jerez',python,'-B','-','--collect-remote']
        with archive.open('wb') as stdout:
            result=subprocess.run(command,input=Path(__file__).read_bytes(),stdout=stdout,stderr=subprocess.PIPE,timeout=180)
        require(result.returncode==0, 'bounded remote collection failed: '+result.stderr.decode(errors='replace'))
        write(output/'remote_transport.json',dict(command=command,returncode=result.returncode,
              archive_bytes=archive.stat().st_size,archive_sha256=digest(archive),stderr=result.stderr.decode()))
    require(archive.exists(), 'remote retained archive required')
    require(digest(archive)==read(output/'remote_transport.json')['archive_sha256'],
            'remote archive changed after verified transport')
    extract_safe(archive,remote)
    manifests.update(read(remote/'remote_manifest.json'))
    preparations.update(read(remote/'remote_preparations.json'))
    # All five verification receipts exist before any array metrics are opened.
    write(output/'input_verification.json',dict(status='ALL_FIVE_PRODUCERS_REHASHED_BEFORE_ANALYSIS',
          manifests=manifests,source_file_sha256=digest(__file__),remote_transport=read(output/'remote_transport.json')))
    import numpy as np
    from threadpoolctl import threadpool_info
    execution['threadpools_after_numerical_import']=threadpool_info()
    require(all(pool['num_threads']==1 for pool in execution['threadpools_after_numerical_import']),
            'analysis numerical threadpool differs from1')
    execution['attested_analysis']=args.attested_analysis
    write(output/'analysis_execution.json',execution)
    regimes=training_bank_evidence(manifests)
    write(output/'training_regime_evidence.json',regimes)
    results={}; folds_all={}
    for label in CAMPAIGNS:
        folds=load_packets(label,manifests[label],preparations[label],remote if label in ('DK_1','DK_1_R138') else None)
        folds_all[label]=folds
        results[label]=analyze(label,folds,output)
    pairs=[]
    for fold in (1,2,3):
        control,alternate=folds_all['DK_1'][fold],folds_all['DK_1_R138'][fold]
        require(np.array_equal(control['truth'],alternate['truth']) and np.array_equal(control['anchors_ns'],alternate['anchors_ns']), 'R138 matched cohort changed')
        d=pinball(control['truth'],alternate[PRIMARY]).mean(axis=(1,2))-pinball(control['truth'],control[PRIMARY]).mean(axis=(1,2))
        for i,value in enumerate(d):
            pairs.append(dict(fold=fold,origin_position=i,delta_R138_minus_R141=float(value),
                              primary_delta_contribution=float(value/(3*len(d)))))
    csv_write(output/'DK_1_R138_vs_R141_paired_origins.csv',pairs)
    write(output/'diagnostic_summary.json',dict(status='RETAINED_DIAGNOSIS_COMPLETE_NO_MODEL_EXECUTION',
        elapsed_seconds=time.time()-start,official_primary_weighting='equal_three_fold_mean; equal_origins_within_fold; H96; seven_quantiles',
        market_clock='physical_UTC_plus_fixed_one_hour_no_DST', official_daily_origins_per_producer=365,
        total_forecast_packets=160,operators=list(OPERATORS), results=results,
        R138_minus_R141_primary_AQL=sum(p['primary_delta_contribution'] for p in pairs),
        exante_training_lag_regimes=dict(status='MISSING_FULL_OFFICIAL_COHORT',evidence='training_regime_evidence.json',
            reason='Verified local training banks end2024-08-31; no complete2025 official-origin lag-history cohort or frozen threshold/feature identity is retained. No retrospective outcome-derived regime is substituted.'),
        limitations=['Previously exposed official development outcomes; never used here for candidate/operator selection.',
                    'No full PIT, unidentified outer tails, comparator calibration, pathwise variance decomposition or scenario causality.',
                    'Normal inner four-clock support and official AL daily support are separate. No forecasts/fits/raw-value analysis or campaign mutation.']))
    print(json.dumps(dict(status='PASS',producers=5,packets=160,origins=1825,elapsed_seconds=time.time()-start)))


if __name__=='__main__':
    main()
