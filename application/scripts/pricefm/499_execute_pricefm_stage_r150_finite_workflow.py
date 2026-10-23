#!/usr/bin/env python3
"""Execute only the four explicitly approved, finite R150 admissions.

This standard-library coordinator never renews a lease, raises priority, fits
models, launches AL, or starts a fourth numerical wave. Each wave gets its own
498 admission and lease. Healthy existing campaigns are read-only dependencies.
"""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
RESOURCE_ENTRY = ENTRY.with_name('498_supervise_pricefm_stage_r150_resources.py')
SCIENCE_ENTRY = ENTRY.with_name('497_run_pricefm_stage_r150_cached_continuation.py')
ADMISSIONS = ('benchmark', '1', '2', '3')


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj)
    if any(name in sys.modules for name in ('numpy', 'scipy', 'pandas')):
        raise RuntimeError('workflow scheduling must stay standard-library only')
    return obj


def next_step(completed, scientific_terminal):
    """The entire prospective admission set is fixed before the first score."""
    if scientific_terminal:
        return None
    if tuple(completed) != ADMISSIONS[:len(completed)]:
        raise RuntimeError('admission order or duplicate wave differs from frozen plan')
    return ADMISSIONS[len(completed)] if len(completed) < len(ADMISSIONS) else None


def acceptable_terminal(terminal, *, numerical_progress):
    if terminal.get('cleanup_verified') is not True:
        raise RuntimeError('prior wave lacks verified owned cleanup')
    if terminal.get('status') not in ('R150_WAVE_COMPLETE', 'R150_WAVE_DEFERRED'):
        raise RuntimeError('prior wave stopped at a guard; no automatic recovery')
    reason = terminal.get('original_stop_reason', '')
    if 'starvation' in reason or 'below.10' in reason or 'stop requested' in reason:
        raise RuntimeError('resource starvation or user/controller stop requires deferral')
    if terminal['wave'] != 'benchmark' and not numerical_progress:
        raise RuntimeError('a zero-progress wave cannot consume further automatic admissions')


def independent_drain(r, system, saved, folder, reason):
    errors = []; controller = None; workers = []
    try:
        controller = r.stop_and_drain(system, saved)
    except Exception as exc:
        errors.append(dict(unit=saved['unit'], error=repr(exc)))
    try:
        owned = r.discover_workers(folder)
    except Exception as exc:
        owned = []; errors.append(dict(operation='discover_workers', error=repr(exc)))
    for item in owned:
        try:
            workers.append(r.stop_and_drain(system, item))
        except Exception as exc:
            errors.append(dict(unit=item['unit'], error=repr(exc)))
    proof = dict(epoch=time.time(), reason=reason, controller=controller,
                 workers=workers, cleanup_verified=not errors, errors=errors)
    r.atomic(folder / ('workflow_drain_' + uuid.uuid4().hex + '.json'), proof)
    r.atomic(folder / 'workflow_independent_drain.json', proof)
    return proof


def wait_wave(r, c, launch):
    """Require a sealed terminal and actual controller/worker drain before return."""
    wave = launch['lease']['wave']; folder = Path(c['runtime']) / ('wave_' + wave)
    system = r.System()
    saved = r.read(folder / 'controller_launch.json')
    if (saved.get('unit') != launch['unit'] or saved.get('lease') != launch['lease']
            or saved.get('description') != 'R150 finite controller lease ' + launch['lease']['lease_id']):
        raise RuntimeError('controller ownership ledger differs from admitted launch')
    attested = bool(saved.get('attested'))
    # A lost/missing terminal is an error even if the manager reports success.
    deadline = launch['lease']['expires_epoch'] + 40
    while time.time() <= deadline:
        props = system.unit(launch['unit'])
        r.verify_owned(saved, props)
        if props.get('ActiveState') == 'active' and not attested:
            saved['attested'] = props; attested = True
            r.atomic(folder / 'workflow_controller_attestation.json', saved)
        terminal_path = folder / 'terminal.json'
        if props.get('ActiveState') in ('inactive', 'failed') or props.get('LoadState') == 'not-found':
            proof = independent_drain(r, system, saved, folder,
                                      'controller exited; validate all owned lifetimes before terminal')
            if not terminal_path.exists():
                raise RuntimeError('controller exited without a durable terminal: ' + wave)
            if not proof['cleanup_verified']:
                raise RuntimeError('independent owned cleanup failed: ' + json.dumps(proof['errors']))
            terminal = r.read(terminal_path)
            if (terminal.get('source', {}).get('head') != launch['lease']['source_head']
                    or terminal.get('lease') != launch['lease']):
                raise RuntimeError('terminal source/lease differs from admitted controller')
            return terminal
        time.sleep(5)
    raise RuntimeError('controller exceeded its finite lease plus drain allowance')


def execute(r, c, release_path):
    r.assert_parent_policy(c)
    release = r.read(release_path)
    if (release.get('status') != 'PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE'
            or not release.get('source', {}).get('remote_head')
            or release['source']['remote_head'] != release['source']['head']):
        raise RuntimeError('fresh clean remote-equal source release required')
    current = r.source_release()
    if current['head'] != release['source']['head']:
        raise RuntimeError('workflow HEAD differs from reviewed remote release')
    science = module('r150_workflow_science', SCIENCE_ENTRY)
    science.read_preparation()
    runtime = Path(c['runtime']); runtime.mkdir(parents=True, exist_ok=True)
    lock_path = runtime / 'workflow.lock'
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (runtime / 'workflow_terminal.json').exists():
            raise RuntimeError('terminal finite workflow cannot be automatically reopened')
        if any((runtime / ('wave_' + wave) / 'lease.json').exists() for wave in ADMISSIONS):
            raise RuntimeError('preexisting admissions require explicit audit; no implicit restart')
        plan = dict(stage='R150', source_head=current['head'], release_sha256=r.digest(release_path),
            admitted_order=list(ADMISSIONS), max_numerical_waves=3, benchmark_seconds=1200,
            wave_seconds=7200, no_renewals=True, new_fits=0, AL_admitted=False,
            source_entry_sha256=r.digest(ENTRY), started_epoch=time.time())
        r.atomic(runtime / 'workflow_plan.json', plan)
        completed = []; records = []; status = 'R150_FINITE_WORKFLOW_DEFERRED'; error = None
        cleanup_failures = []
        try:
            while True:
                state = science.advance()
                wave = next_step(completed, state['terminal'])
                if state['terminal']:
                    assessment = science.finalize()
                    status = 'R150_FINITE_WORKFLOW_SCIENTIFICALLY_COMPLETE'
                    break
                if wave is None:
                    status = 'R150_FINITE_WORKFLOW_BUDGET_EXHAUSTED'
                    break
                if not state['ready']:
                    status = 'R150_FINITE_WORKFLOW_BUDGET_DEFERRED_BEFORE_NEXT_ADMISSION'
                    break
                before = set(state['complete'])
                r.atomic(runtime / 'workflow_heartbeat.json', dict(epoch=time.time(), phase='admitting',
                    wave=wave, completed_admissions=completed, scientific_state=state))
                launch = r.launch(c, wave)
                try:
                    terminal = wait_wave(r, c, launch)
                except Exception as wave_error:
                    try:
                        folder = runtime / ('wave_' + wave)
                        saved = r.read(folder / 'controller_launch.json')
                        if (saved.get('unit') != launch['unit'] or saved.get('lease') != launch['lease']
                                or saved.get('description') != 'R150 finite controller lease ' + launch['lease']['lease_id']):
                            raise RuntimeError('controller ownership ledger differs from launch')
                        attestation = folder / 'workflow_controller_attestation.json'
                        if attestation.exists():
                            original = r.read(attestation)
                            if any(original.get(k) != saved[k] for k in ('unit', 'argv', 'description')):
                                raise RuntimeError('persisted controller attestation differs from launch intent')
                            saved = original
                        proof = independent_drain(r, r.System(), saved, folder,
                                                 'workflow observed wave error; preserve original failure')
                        cleanup_failures.extend(proof['errors'])
                    except Exception as cleanup_error:
                        cleanup_failures.append(dict(wave=wave, error=repr(cleanup_error)))
                    raise wave_error
                after = science.advance()
                progress = bool(set(after['complete']) - before)
                records.append(dict(wave=wave, launch=launch, terminal_status=terminal['status'],
                    new_complete_components=len(set(after['complete'])-before),
                    scientific_phase=after['phase'], strict_complete=len(after['complete']),
                    strict_required=after['total']))
                acceptable_terminal(terminal, numerical_progress=progress)
                completed.append(wave)
                r.atomic(runtime / 'workflow_progress.json', dict(plan=plan, records=records,
                    completed_admissions=completed, scientific_state=after))
        except Exception as exc:
            error = repr(exc)
            status = 'R150_FINITE_WORKFLOW_STOPPED_REVIEW_REQUIRED'
        state_error = None
        try:
            state = science.queue_state()
        except Exception as exc:
            state = dict(scientific_complete=False)
            state_error = repr(exc)
        result = dict(status=status, error=error, epoch=time.time(), plan=plan,
            completed_admissions=completed, records=records, scientific_state=state,
            scientific_assessment=(str(science.OUT / 'assessment.json') if state['scientific_complete'] else None),
            new_model_fits=0, baseline_worker_signals=0, no_promotion=True,
            no_lease_renewal=True, automatic_extra_waves=0, AL_launched=False,
            final_state_read_error=state_error, cleanup_failures=cleanup_failures)
        r.atomic(runtime / 'workflow_terminal.json', result)
        return result


def launch(r, c, release_path):
    r.assert_parent_policy(c)
    release = r.read(release_path)
    current = r.source_release()
    if (release.get('status') != 'PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE'
            or release.get('source', {}).get('remote_head') != current['head']
            or release['source']['head'] != current['head']):
        raise RuntimeError('fresh remote-equal reviewed source required before starting workflow')
    Path(c['runtime']).mkdir(parents=True, exist_ok=True)
    unit = 'pricefm-r150-workflow-' + uuid.uuid4().hex + '.service'
    command = [c['python_runtime'], '-B', str(ENTRY), 'run', '--release', str(release_path)]
    description = 'R150 approved finite benchmark and three-wave workflow'
    system = r.System()
    baseline = system.unit(c['baseline_units'][0])
    parent_cgroup = str(Path(baseline['ControlGroup']).parent)
    if not parent_cgroup.startswith('/user.slice/'):
        raise RuntimeError('unknown user-service cgroup hierarchy')
    # Four finite admissions total380min; another5min is metadata/drain overhead,
    # never an extra numerical lease or an extension of any worker RuntimeMaxSec.
    record = dict(unit=unit, argv=command, command=command, description=description,
        expected_cgroup=parent_cgroup + '/' + unit, source_head=current['head'],
        source_entry_sha256=r.digest(ENTRY), release_sha256=r.digest(release_path),
        admitted_order=list(ADMISSIONS), runtime_seconds=385*60, epoch=time.time())
    ledger = Path(c['runtime']) / 'workflow_launch.json'
    if ledger.exists():
        raise RuntimeError('existing workflow launch requires explicit audit; no duplicate launch')
    r.atomic(ledger, record)
    try:
        system.start(unit, description, command, cpus=c['cpus'], idle=False,
            runtime_seconds=385*60, stdout=Path(c['runtime']) / 'workflow.stdout')
        props = system.unit(unit); r.verify_owned(record, props)
        if props.get('ActiveState') != 'active' or not props.get('InvocationID'):
            raise RuntimeError('workflow failed before active unit attestation')
        record['attested'] = props
        r.atomic(ledger, record)
    except Exception as launch_error:
        proof = independent_drain(r, system, record, Path(c['runtime']),
                                  'workflow launch failed: ' + repr(launch_error))
        r.atomic(Path(c['runtime']) / 'workflow_launch_failure.json',
                 dict(error=repr(launch_error), cleanup=proof, epoch=time.time()))
        raise
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['launch', 'run'])
    parser.add_argument('--release', type=Path, required=True)
    args = parser.parse_args()
    r = module('r150_workflow_resources', RESOURCE_ENTRY)
    c = r.read(r.CONFIG); r.validate_config(c)
    result = launch(r, c, args.release) if args.action == 'launch' else execute(r, c, args.release)
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get('error') is None else 2


if __name__ == '__main__':
    raise SystemExit(main())
