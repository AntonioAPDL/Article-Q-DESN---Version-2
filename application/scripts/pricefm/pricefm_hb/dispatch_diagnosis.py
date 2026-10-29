"""Diagnose saved PriceFM owner6 observations; never control or classify a peer.

Only bounded JSON metadata is read. This module deliberately has no process,
network, numerical, service, scheduling or authority-enrollment capability.
An observation may describe permitted dispatch; this diagnostic cannot permit it.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import time

SCHEMA = 'r163_dispatch_diagnosis_v1'
OBSERVER_SCHEMA = 'r155_baseline_owner6_readonly_health_v1'
SOURCE_HASHES = {
    '530_supervise_pricefm_stage_r155_baseline_continuation.py': '8cb57e7806253b6bb8ec9802eed9f5098b8fec5fbc1ea4e594c5eb487ee65e02',
    '531_prepare_pricefm_stage_r155_baseline_continuation.py': '5a63826f7b03cb3e6af37743fe8f9641fec686a27b66c7dd0880433c3f4277d1',
    '532_activate_pricefm_stage_r155_baseline_continuation.py': 'ce66f76c5c8706ac75461a273d67b6e06b7ab3f1f76bd5b358dfdd8810023f0d',
    '533_inspect_pricefm_stage_r155_baseline_continuation.py': '72648de5daa0912edd8df78eba304aabee246f14350137eaefdd178e09bb4924',
    '534_materialize_pricefm_stage_r155_baseline_owner6.py': '9cace53aacec69633e82e8f85c984fe89ee14cedb569b7a6182b58eee7b8f36e',
    'pricefm_r155_baseline_contract.py': 'a5a32ecd533f12b8433954fba3b8b1d07d8449d8f7b20765afe400571fcb35f4',
}
SOURCE_HEAD = 'be27be81617d187b5f96d13703ee03e85cdf5269'
SOURCE_BRANCH = 'work/pricefm-r155-baseline-owner6-20261027'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def physical(path):
    path = Path(path)
    require(path.is_absolute() and not any(p.is_symlink() for p in (path, *path.parents)),
            'absolute physical metadata path required')
    return path


def pinned_json(ref):
    require(type(ref) is dict and set(ref) == {'path', 'sha256'}, 'exact metadata pin required')
    path = physical(ref['path'])
    require(path.suffix == '.json', 'JSON metadata required')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        require(os.fstat(stream.fileno()).st_size <= 16 * 1024**2, 'bounded JSON metadata required')
        raw = stream.read(16 * 1024**2 + 1)
    require(len(raw) <= 16 * 1024**2, 'metadata grew beyond bound')
    require(hashlib.sha256(raw).hexdigest() == ref['sha256'], 'metadata pin changed')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def finite_tree(value):
        if isinstance(value, float): return math.isfinite(value)
        if isinstance(value, dict): return all(finite_tree(v) for v in value.values())
        if isinstance(value, list): return all(finite_tree(v) for v in value)
        return True
    value = json.loads(raw, object_pairs_hook=pairs,
                       parse_constant=lambda s: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    require(finite_tree(value), 'nonfinite JSON value')
    require(type(value) is dict, 'JSON object required')
    return value


def lifetime(record):
    anchor = record.get('stat', record.get('final_stat')) or {}
    pid, ticks, boot = record.get('pid'), anchor.get('start_ticks'), record.get('boot_id')
    if type(pid) is int and pid > 0 and type(ticks) is int and ticks >= 0 and isinstance(boot, str) and boot:
        return (boot, pid, ticks)
    return None


def validate_observation(value):
    require(value.get('schema') == OBSERVER_SCHEMA, 'source-specific owner6 observation required')
    require(number(value.get('epoch')), 'finite observation epoch required')
    require(value.get('host_context', {}).get('host') == 'muscat.be.ucsc.edu',
            'Muscat owner6 scope required')
    source = value.get('execution_source', {})
    require(source.get('head') == SOURCE_HEAD and source.get('branch') == SOURCE_BRANCH,
            'frozen owner6 source identity changed')
    hashes = source.get('runtime_sha256', {})
    expected = {'application/scripts/pricefm/' + name: sha for name, sha in SOURCE_HASHES.items()}
    require(hashes == expected, 'complete frozen owner6 runtime pins required')
    require(type(value.get('healthy_control')) is bool and
            type(value.get('dispatch_currently_permitted')) is bool, 'literal control flags required')
    census = value.get('census')
    require(type(census) is dict and type(census.get('complete')) is bool and
            type(census.get('unresolved')) is list, 'complete census evidence required')
    require(census.get('host') == 'muscat.be.ucsc.edu', 'census belongs to a different host')
    if value['dispatch_currently_permitted']:
        require(value['healthy_control'] and census['complete'] and not census['unresolved'] and
                census.get('full_host_view_verified') is True and value.get('recorded_phase') == 'running' and
                value.get('status') == 'CONTROL_RUNNING', 'inconsistent source dispatch flags')
    if census['complete']:
        require(not census['unresolved'] and census.get('full_host_view_verified') is True,
                'inconsistent complete census')
    require(type(value.get('numerical_worker_signals')) is int and value['numerical_worker_signals'] == 0 and
            type(value.get('runtime_writes')) is int and value['runtime_writes'] == 0,
            'read-only observer role required')
    return value


def diagnose(current, prior=None, *, now_epoch=None):
    """Interpret exact saved observations. No result is execution authority."""
    current = validate_observation(current)
    if prior is not None:
        prior = validate_observation(prior)
        require(prior['epoch'] <= current['epoch'], 'observation history reversed')
    now_epoch = time.time() if now_epoch is None else now_epoch
    require(number(now_epoch) and current['epoch'] <= now_epoch + 2, 'future observation rejected')
    census = current['census']
    before = {lifetime(r) for r in prior['census']['unresolved']} if prior else set()
    rows = []
    for record in census['unresolved']:
        key = lifetime(record)
        rows.append({
            'pid': record.get('pid'), 'lifetime': list(key) if key else None,
            'same_recorded_lifetime_as_prior': bool(key and key in before),
            'required_unavailable_fields': record.get('unavailable_fields', []),
            'error': record.get('error'), 'comm_descriptive_only': record.get('comm'),
            'role_classified': False, 'owner_inferred': False,
        })
    if not current['healthy_control']:
        status, action = 'CONTROL_NOT_HEALTHY_OR_UNVERIFIED', 'READ_SOURCE_BOUND_CONTROL_FAILURE'
    elif not census['complete']:
        status, action = 'BLOCKED_PROVENANCE_VISIBILITY', 'REQUIRE_COMPLETE_SOURCE_CENSUS'
    elif not current['dispatch_currently_permitted']:
        status, action = 'AWAIT_SOURCE_OWNER_RECONCILIATION', 'WAIT_FOR_ORIGINAL_OWNER_RECONCILIATION'
    else:
        status, action = 'SOURCE_SNAPSHOT_REPORTS_DISPATCH_PERMITTED', 'CONTINUE_ORIGINAL_OWNER_ONLY'
    return {
        'schema': SCHEMA, 'purpose': 'PRICEFM_READONLY_DISPATCH_DIAGNOSIS',
        'status': status, 'control_scope': 'MUSCAT_OWNER6_ONLY',
        'not_a_Jerez_R143_dispatch_observation': True,
        'observed_epoch': current['epoch'], 'observation_age_seconds': max(0, now_epoch - current['epoch']),
        'historical_snapshot_only': now_epoch - current['epoch'] > 60,
        'source_snapshot_healthy_control': current['healthy_control'],
        'source_snapshot_dispatch_permitted': current['dispatch_currently_permitted'],
        'recorded_phase': current.get('recorded_phase'), 'census_complete': census['complete'],
        'unresolved': rows, 'next_action': action,
        'dispatch_authorized_by_this_diagnostic': False, 'numerical_execution_authorized': False,
        'guard_exception_or_peer_classification_created': False,
        'live_process_mutations': 0, 'old_grants_renewed': False,
        'execution_source': current['execution_source'],
        'required_resolution': [
            'Retain exact source, authority, boot, PID and start-time anchors.',
            'Use accepted provenance visibility or legitimate natural recovery; never exempt a process by name.',
            'A vanished recorded PID alone is insufficient; require a later complete source-specific census.',
            'Require the original owner to reconcile and report dispatch permitted before its next release.',
            'Preserve existing fits, guards, queues, limits and failed charges; make no service or affinity change.',
        ],
    }


def compile_request(request):
    require(type(request) is dict and set(request) == {'schema', 'current', 'prior'}, 'exact diagnosis request required')
    require(request['schema'] == 'r163_dispatch_request_v1', 'diagnosis request schema changed')
    value = diagnose(pinned_json(request['current']),
                     pinned_json(request['prior']) if request['prior'] is not None else None)
    value['input_pins'] = request
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True)
    parser.add_argument('--request-sha256', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args(argv)
    require(os.sched_getaffinity(0) == {31}, 'administrative CPU31 required')
    resource.setrlimit(resource.RLIMIT_CPU, (5, 5))
    signal.alarm(30)
    path = physical(args.request)
    request = pinned_json({'path': str(path), 'sha256': args.request_sha256})
    result = compile_request(request)
    out = physical(args.output)
    require(out.suffix == '.json', 'new JSON result required')
    raw = (json.dumps(result, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()
    # Create only: no overwrite, replacement or authority/canonical publication.
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
    print(json.dumps({'status': result['status'], 'output': str(out),
                      'sha256': hashlib.sha256(raw).hexdigest(), 'dispatch_authorized': False}))


if __name__ == '__main__':
    main()
