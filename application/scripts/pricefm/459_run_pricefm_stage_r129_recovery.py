#!/usr/bin/env python3
"""Bounded certificates -> untouched outward AL fits -> matched pilot forecasts."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

for key in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
            'BLIS_NUM_THREADS', 'NUMEXPR_NUM_THREADS', 'R_DATATABLE_NUM_THREADS'):
    os.environ[key] = '1'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
HERE = ENTRY.parent
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG = 'pricefm_stage_r129_al_fixedpoint_recovery_20261008'
OUT = DATA / 'campaigns' / TAG
PREP = DATA / 'launch_prep' / TAG
HELPER = ROOT / 'application/R/pricefm_r129_al_fixedpoint_certificate.R'
PROTOCOL = ROOT / 'application/config' / (TAG + '.json')


def git(path, *args):
    return subprocess.check_output(['git', *args], cwd=path, text=True).strip()


def source_identity():
    branch = git(ROOT, 'branch', '--show-current')
    if not branch.startswith('work/pricefm-r129-') or git(ROOT, 'status', '--porcelain'):
        raise RuntimeError('clean committed R129 source required')
    return dict(branch=branch, head=git(ROOT, 'rev-parse', 'HEAD'))


def setup(parent, dependency):
    global base, runtime, read, write, immutable, digest, seal, verified, verify_hashes
    path = Path(parent) / 'application/scripts/pricefm/456_run_pricefm_stage_r128_stochastic_pilots.py'
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location('r129_frozen_r128', path)
    base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
    runtime = base.setup(Path(dependency))
    from pricefm_r126_contract import read, write, immutable, digest, seal, verified, verify_hashes
    base.OUT = OUT; base.ENTRY = ENTRY; base._OUTCOMES = {}
    return runtime


def validate_protocol(p):
    if (p['tag'] != TAG or p['regions'] != ['HR', 'DK_1'] or p['maximum_workers'] != 15 or
            p['quantiles'] != [.1, .25, .45, .5, .55, .75, .9] or p['al_max_iter'] != 1000):
        raise ValueError('fixed recovery geometry changed')
    for key in ('package_mutation_authorized', 'screening_authorized', 'mcmc_authorized',
                'joint_authorized', 'exal_authorized', 'promotion_authorized',
                'registry_mutation_authorized', 'article_mutation_authorized',
                'priors_from_initializers', 'test_used_for_selection', 'all_region_launch_authorized'):
        if p[key] is not False: raise ValueError('unauthorized expansion: ' + key)


def release(parent, dependency):
    identity = source_identity()
    path = DATA / 'runtime_audits' / TAG / ('release_' + os.uname().nodename + '_' + identity['head'][:12])
    path.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PRICEFM_R129_PARENT=str(parent), PRICEFM_R129_DEPENDENCY=str(dependency))
    log = path / 'pytest.log'; junit = path / 'pytest.xml'
    with log.open('w') as stream:
        result = subprocess.run([sys.executable, '-B', '-m', 'pytest', '-q',
            str(ROOT / 'application/tests/test_pricefm_stage_r129_recovery.py'), '-p', 'no:cacheprovider',
            '--junitxml=' + str(junit)], cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
    suites = ET.parse(junit).getroot().findall('testsuite')
    totals = {k: sum(int(s.get(k, '0')) for s in suites) for k in ('tests', 'failures', 'errors', 'skipped')}
    receipt = dict(source=identity, passed=result.returncode == 0 and totals['tests'] >= 19 and
        sum(totals[k] for k in ('failures', 'errors', 'skipped')) == 0, **totals,
        public_cran_AL_numerical_smoke=True, posterior_target_separation_test=True)
    write(path / 'validation.json', receipt)
    if not receipt['passed']: raise RuntimeError('release tests failed: ' + str(path))
    return dict(path=str(path / 'validation.json'), **receipt)


def build_tasks(parent_prep, choices):
    original = base.full_tasks(parent_prep, choices)
    median = [dict(t, kind='median_certificate', depends=[]) for t in original
              if t['kind'] == 'al' and t['tau'] == .5]
    remaining = [t for t in original if (t['kind'] == 'al' and t['tau'] != .5) or t['kind'] == 'forecast']
    return median, remaining


def prepare(parent, release):
    p = read(PROTOCOL); validate_protocol(p)
    parent_out = DATA / 'campaigns' / p['parent_tag']
    parent_prep_path = DATA / 'launch_prep' / p['parent_tag'] / 'preparation.json'
    old = read(parent_prep_path)
    setup(parent, old['dependency'])
    identity = source_identity(); receipt = read(release)
    if receipt['source'] != identity or not receipt['passed']: raise RuntimeError('source-matched release required')
    if git(parent, 'rev-parse', 'HEAD') != p['parent_head'] or git(parent, 'status', '--porcelain'):
        raise RuntimeError('frozen R128 source differs')
    if git(old['dependency'], 'rev-parse', 'HEAD') != p['dependency_head']:
        raise RuntimeError('frozen R127 dependency differs')
    # R128 must have stopped without a live controller or worker before recovery.
    for command in Path('/proc').glob('[0-9]*/cmdline'):
        try: raw = command.read_bytes()
        except OSError: continue
        if str(Path(parent) / 'application/scripts/pricefm/456_run_pricefm_stage_r128_stochastic_pilots.py').encode() in raw:
            raise RuntimeError('R128 still active; do not create duplicate work')
    verify_hashes(old['source_sha256'])
    choices = read(parent_out / 'frozen_choices.json')
    median, remaining = build_tasks(old, choices)
    inputs = {str(parent_prep_path): digest(parent_prep_path),
        str(parent_out / 'frozen_choices.json'): digest(parent_out / 'frozen_choices.json'),
        str(parent_out / 'blocked.json'): digest(parent_out / 'blocked.json')}
    for region in p['regions']:
        for fold in (1, 2, 3):
            for suffix in ('design', 'normal', 'al0.50'):
                folder = parent_out / 'tasks_done' / f'{region}_fold{fold}_{suffix}'
                metadata = verified(folder)
                if metadata['source_head'] != p['parent_head']: raise RuntimeError('reused task source mismatch')
                if suffix == 'normal' and not metadata['certified']: raise RuntimeError('uncertified Normal driver')
                for file in folder.rglob('*'):
                    if file.is_file(): inputs[str(file)] = digest(file)
    source_paths = [ENTRY, HELPER, PROTOCOL, HERE / '457_audit_pricefm_stage_r129_al_fixedpoint.R',
        HERE / '458_fit_pricefm_stage_r129_certified_al.R',
        ROOT / 'application/tests/test_pricefm_stage_r129_al_fixedpoint.R',
        ROOT / 'application/tests/test_pricefm_stage_r129_recovery.py']
    prep = dict(source=identity, parent_source=str(parent), parent_out=str(parent_out), dependency=old['dependency'],
        source_sha256={str(f): digest(f) for f in source_paths}, inherited_source_sha256=old['source_sha256'],
        input_sha256=inputs, release_path=str(release), release_sha256=digest(release), protocol=p,
        control=old['control'], official_protocol=old['official_protocol'], references=old['references'],
        choices=choices, tasks=[*median, *remaining], median_tasks=median, remaining_tasks=remaining,
        raw_identity=old['raw_identity'], parent_preparation_sha256=digest(parent_prep_path),
        new_screening=False, new_Normal_fits=0, new_median_fits=0, reused_median_certificates=6,
        new_outward_AL_fits=36, official_origin_region_pairs=730)
    immutable(PREP / 'preparation.json', prep)
    return dict(status='R129_PREPARED', median_certificates=6, new_AL_fits=36, forecasts=64)


def valid():
    prep = read(PREP / 'preparation.json')
    if source_identity() != prep['source']: raise RuntimeError('executed R129 source changed')
    if git(prep['parent_source'], 'rev-parse', 'HEAD') != prep['protocol']['parent_head']:
        raise RuntimeError('frozen R128 source changed')
    if git(prep['dependency'], 'rev-parse', 'HEAD') != prep['protocol']['dependency_head']:
        raise RuntimeError('frozen R127 source changed')
    verify_hashes(prep['source_sha256'])
    if digest(prep['release_path']) != prep['release_sha256']: raise RuntimeError('release changed')
    stat = (DATA / 'raw/FINAL.csv').stat()
    if (stat.st_size, stat.st_mtime_ns) != (prep['raw_identity']['bytes'], prep['raw_identity']['mtime_ns']):
        raise RuntimeError('raw input metadata changed')
    return prep


def contract(prep, task, output):
    p = prep['protocol']; old = Path(prep['parent_out']); prefix = f"{task['region']}_fold{task['fold']}"
    design = old / 'tasks_done' / (prefix + '_design') / 'design'
    parent = (old if task['kind'] == 'median_certificate' else OUT) / 'tasks_done' / task['parent_name'] / 'fit'
    if task['kind'] == 'median_certificate': parent = old / 'tasks_done' / task['name'] / 'fit'
    adapter = Path(prep['dependency']) / 'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R'
    protected = [HELPER, adapter, design / 'terminal.json', design / 'design.json',
        parent / 'terminal.json', parent / 'beta_mean.bin', parent / 'beta_cov.bin']
    if task['kind'] == 'al': protected.append(parent / 'certificate.json')
    target = digest(design / 'terminal.json') + f":tau={task['tau']}:tau0={task['tau0']:.17g}"
    return dict(stage='R129', action='saved_median_certificate' if task['kind'] == 'median_certificate' else 'public_AL_fit',
        helper=str(HELPER), helper_sha256=digest(HELPER), cran_adapter=str(adapter),
        cran_library=prep['control']['cran_library'], design_dir=str(design), parent_dir=str(parent),
        output_dir=str(output / ('audit' if task['kind'] == 'median_certificate' else 'fit')),
        input_sha256={str(f): digest(f) for f in protected}, posterior_target_sha256=target,
        fold=task['fold'], tau=task['tau'], tau0=task['tau0'], max_iter=p['al_max_iter'],
        tol=p['al_computational_stop_tol'], n_samp=p['al_n_samp'], max_rhs_iter=p['max_rhs_iter'],
        limits=p['certificate_limits'], test_opened=False,
        seed=runtime.BASE.deterministic_seed(2026100801, task['region'], task['fold'], task['tau']) % (2**31 - 1))


def forecast(prep, task, output, beat):
    from pricefm_r126_contract import official_origins, market_ns, transform
    from pricefm_r126_replay import forecast as run_forecast
    from pricefm_r127_contract import common_metrics
    old = Path(prep['parent_out']); prefix = f"{task['region']}_fold{task['fold']}"
    design = old / 'tasks_done' / (prefix + '_design') / 'design'
    scaler = read(design / 'scaler.json'); official = prep['official_protocol']; fold = task['fold']
    origins = official_origins(official, fold)[task['positions']]
    frame = base.core.read_frame(DATA / 'raw/FINAL.csv', runtime.active_regions(task['spec']),
        official['test_intervals_market'][fold - 1][1])
    arrays = base.core.regional_arrays(runtime, frame, origins, task['spec'])
    scaled = transform(arrays, scaler, runtime.ExplicitArrays)
    normal = runtime.load_normal_fit(old / 'tasks_done' / (prefix + '_normal') / 'fit')
    quantiles = {float(q): runtime.load_quantile_fit(OUT / 'tasks_done' / name / 'fit') for q, name in task['al_names'].items()}
    for fit in quantiles.values():
        if not fit['terminal']['independent_fixedpoint_certified']: raise RuntimeError('uncertified receiving quantile')
    values, audit = run_forecast(runtime, scaled, task['spec'], normal, quantiles, task['positions'],
        runtime.BASE.deterministic_seed(2026100801, task['region'], fold, 'official'), observe=beat)
    for key in values: values[key] = values[key] * scaler['price_scale'] + scaler['price_mean']
    values['truth'] = arrays.response
    np.savez_compressed(output / 'predictions.npz', **values, anchors_ns=market_ns(origins), positions=np.asarray(task['positions']))
    return dict(certified=True, metrics={key: common_metrics(values['truth'], v) for key, v in values.items() if key != 'truth'},
        audit=audit, origins=len(origins), reused_Normal_fit=True)


def worker(name, cpu):
    prep = read(PREP / 'preparation.json'); setup(prep['parent_source'], prep['dependency']); valid()
    os.sched_setaffinity(0, {cpu})
    task = read(OUT / 'tasks' / (name + '.json')); output = OUT / 'tasks_done' / name
    if (output / 'completed_evidence.json').exists(): verified(output); return
    output.mkdir(parents=True)
    beat = lambda value: write(OUT / 'heartbeats' / (name + '.json'), dict(value, epoch=time.time()))
    start = time.time(); beat(dict(kind=task['kind'], status='running'))
    if task['kind'] == 'forecast': result = forecast(prep, task, output, beat)
    else:
        from pricefm_r126_fullfold import run_r
        c = contract(prep, task, output); path = OUT / 'contracts' / (name + '.json'); immutable(path, c)
        entry = HERE / ('457_audit_pricefm_stage_r129_al_fixedpoint.R' if task['kind'] == 'median_certificate'
                        else '458_fit_pricefm_stage_r129_certified_al.R')
        run_r(entry, '--config', path, OUT / 'fit_logs' / (name + '.log'))
        if task['kind'] == 'median_certificate':
            audit = read(output / 'audit/certificate.json'); fit_dir = output / 'fit'; fit_dir.mkdir()
            parent = Path(c['parent_dir']); old_term = read(parent / 'terminal.json')
            for file in ('beta_mean.bin', 'beta_cov.bin'): shutil.copyfile(parent / file, fit_dir / file)
            shutil.copyfile(output / 'audit/certificate.json', fit_dir / 'certificate.json')
            terminal = dict(old_term, status='r129_derived_AL_fixedpoint_from_frozen_median',
                independent_fixedpoint_certified=audit['certified'], original_terminal_sha256=digest(parent / 'terminal.json'),
                certification=audit['certification'], no_new_AL_fit=True, exact_optimizer_resumption_supported=False)
            # The original formal flag remains false, even when the independent certificate passes.
            write(fit_dir / 'terminal.json', terminal)
        else: terminal = read(output / 'fit/terminal.json')
        result = dict(certified=terminal['independent_fixedpoint_certified'],
            original_or_public_formal_converged=terminal['formal_converged'], fold=task['fold'], tau=task['tau'])
    write(output / 'result.json', result)
    seal(output, dict(task_sha256=digest(OUT / 'tasks' / (name + '.json')), source_head=prep['source']['head'],
        elapsed_seconds=time.time() - start, certified=result['certified']))


def closeout(prep):
    from pricefm_r127_contract import common_metrics
    rows = []
    for region in prep['protocol']['regions']:
        for fold in (1, 2, 3):
            selected = sorted((t for t in prep['remaining_tasks'] if t['kind'] == 'forecast' and t['region'] == region and t['fold'] == fold),
                key=lambda t: t['positions'][0])
            packets = []
            for t in selected:
                verified(OUT / 'tasks_done' / t['name'])
                with np.load(OUT / 'tasks_done' / t['name'] / 'predictions.npz', allow_pickle=False) as z:
                    packets.append({k: z[k] for k in z.files})
            values = {k: np.concatenate([z[k] for z in packets]) for k in packets[0]}
            if not np.array_equal(values['positions'], np.arange(prep['official_protocol']['test_origin_counts'][fold - 1])):
                raise RuntimeError('incomplete comparison cohort')
            ref = next(r for r in prep['references'] if r['region'] == region and r['fold'] == fold)
            for operator in ('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'):
                rows.append(dict(region=region, fold=fold, operator=operator, **common_metrics(values['truth'], values[operator]),
                    **{k: ref[k] for k in ('qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')}))
    path = OUT / 'closeout'; path.mkdir()
    table = pd.DataFrame(rows); table.to_csv(path / 'fold_comparison.csv', index=False)
    table.groupby(['region', 'operator'], as_index=False).mean(numeric_only=True).to_csv(path / 'region_comparison.csv', index=False)
    write(path / 'interpretation.json', dict(primary_operator='cdf_pool_clipped', authority_replaced=False,
        all_region_rollout_authorized=False, inference='independent_AL_VB_with_stochastic_Normal_RHS_VB_driver',
        convergence_policy='independent_full_fixedpoint_not_original_raw_beta_tolerance',
        test_seen_previously=True, confirmatory_claim=False))
    seal(path, dict(source=prep['source'], regions=2, folds=6))
    write(OUT / 'terminal.json', dict(status='R129_COMPLETE_NOT_PROMOTED', source=prep['source'],
        reused_medians=6, new_AL_fits=36, official_origin_region_pairs=730))


def controller(workers):
    prep = read(PREP / 'preparation.json'); setup(prep['parent_source'], prep['dependency']); valid()
    if not 1 <= workers <= 15: raise ValueError('shared physical worker cap15')
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'controller.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for f in Path('/proc').glob('[0-9]*/cmdline'):
            try: parts = f.read_bytes().split(b'\0')
            except OSError: continue
            if str(ENTRY).encode() in parts and b'worker' in parts: raise RuntimeError('live own worker; do not duplicate')
        verify_hashes(prep['input_sha256']); verify_hashes(prep['inherited_source_sha256'])
        cpus = base.core.physical_cpus(workers)
        if not cpus: raise RuntimeError('no idle physical cores')
        base.resources(prep['protocol'], len(cpus) * .06)
        write(OUT / 'controller_identity.json', dict(pid=os.getpid(), cpus=cpus, source=prep['source'], epoch=time.time()))
        try:
            base.batch(prep['median_tasks'], cpus, prep, 'saved_median_full_fixedpoint_audit')
            outcomes = {t['name']: base.outcome(t['name']) for t in prep['median_tasks']}
            if not all(v['certified'] for v in outcomes.values()):
                raise RuntimeError('median full-fixedpoint gate failed; no outward fit authorized')
            immutable(OUT / 'median_gate.json', dict(passed=True, outcomes=outcomes, original_formal_flags_preserved=True))
            base.batch(prep['remaining_tasks'], cpus, prep, 'nested_public_AL_and_recursive_forecasts')
            if any(not base.outcome(t['name'])['certified'] for t in prep['tasks']): raise RuntimeError('uncertified task at closeout')
            valid(); verify_hashes(prep['input_sha256'])
            if digest(DATA / 'raw/FINAL.csv') != prep['raw_identity']['sha256']:
                raise RuntimeError('raw content changed before comparison closeout')
            closeout(prep)
        except Exception as error:
            write(OUT / 'blocked.json', dict(error=str(error), epoch=time.time(), source=prep['source'],
                original_R128_unchanged=True, no_automatic_budget_change=True))
            raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('release', 'prepare', 'controller', 'worker'))
    parser.add_argument('--parent', type=Path); parser.add_argument('--release', type=Path)
    parser.add_argument('--dependency', type=Path)
    parser.add_argument('--workers', type=int, default=15); parser.add_argument('--name'); parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    if args.action == 'release':
        setup(args.parent, args.dependency); print(release(args.parent, args.dependency), flush=True)
    elif args.action == 'prepare':
        old = json.loads((DATA / 'launch_prep/pricefm_stage_r128_stochastic_regional_pilots_20261008/preparation.json').read_text())
        setup(args.parent, old['dependency']); print(prepare(args.parent, args.release), flush=True)
    else:
        prep = json.loads((PREP / 'preparation.json').read_text()); setup(prep['parent_source'], prep['dependency'])
        if args.action == 'worker': worker(args.name, args.cpu)
        else: controller(args.workers)
