#!/usr/bin/python3.11
"""Bounded stop-post and separate inactive-unit proof; never launches a job."""
import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import pathlib
import re
import shlex
import subprocess

FIELDS = ('Id', 'LoadState', 'FragmentPath', 'ActiveState', 'SubState', 'Result',
          'ExecMainCode', 'ExecMainStatus', 'MainPID', 'ControlGroup', 'DropInPaths', 'NeedDaemonReload',
          'ExecStart', 'ExecStopPost', 'WorkingDirectory', 'CPUAffinity', 'LimitCPU', 'LimitAS',
          'LimitFSIZE', 'KillMode', 'Restart', 'Environment')

def need(ok, why):
    if not ok:
        raise ValueError('MQ_NATIVE_TERMINAL: ' + why)

def sha(path):
    h = hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for part in iter(lambda: stream.read(1024**2), b''):
            h.update(part)
    return h.hexdigest()

def pin_check(pin):
    p = pathlib.Path(pin['path'])
    need(set(pin) == {'path', 'size_bytes', 'sha256'} and p.is_absolute() and
         p.resolve(strict=True) == p and p.is_file() and not p.is_symlink() and
         p.stat().st_size == pin['size_bytes'] and sha(p) == pin['sha256'], 'pinned file changed')
    return p

def native_time(text):
    values = {}
    for name in ('Exit status', 'User time (seconds)', 'System time (seconds)', 'Maximum resident set size (kbytes)'):
        match = re.findall(r'^\s*' + re.escape(name) + r':\s*([0-9]+(?:\.[0-9]+)?)\s*$', text, re.M)
        need(len(match) == 1, 'missing/duplicate native time value')
        values[name] = float(match[0])
        need(math.isfinite(values[name]) and values[name] >= 0, 'invalid native time number')
    elapsed = re.findall(r'^\s*Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*([0-9:.]+)\s*$', text, re.M)
    need(len(elapsed) == 1, 'missing/duplicate native wall time')
    parts = elapsed[0].split(':')
    need(len(parts) in (2, 3) and all(re.fullmatch('[0-9]+', p) for p in parts[:-1]) and
         re.fullmatch('[0-9]+(?:\.[0-9]+)?', parts[-1]) is not None and float(parts[-1]) < 60 and
         (len(parts) == 2 or int(parts[-2]) < 60), 'malformed native wall time')
    wall = sum(float(x) * 60**i for i, x in enumerate(reversed(parts)))
    need(math.isfinite(wall), 'nonfinite native wall time')
    for name in ('Exit status', 'Maximum resident set size (kbytes)'):
        need(values[name].is_integer(), 'noninteger native count')
    return dict(exit_code=int(values['Exit status']), user_cpu_seconds=values['User time (seconds)'],
                system_cpu_seconds=values['System time (seconds)'], wall_seconds=wall,
                peak_rss_kib=int(values['Maximum resident set size (kbytes)']))

def unit_state(unit):
    args = ['/usr/bin/systemctl', '--user', 'show', unit]
    for key in FIELDS:
        args.extend(('-p', key))
    result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=False)
    need(result.returncode == 0, 'unit readback failed')
    pairs = [line.split('=', 1) for line in result.stdout.splitlines()]
    need(len(pairs) == len(FIELDS) and all(len(p) == 2 for p in pairs) and
         len({p[0] for p in pairs}) == len(FIELDS), 'malformed unit fields')
    out = dict(pairs)
    need(set(out) == set(FIELDS), 'incomplete unit fields')
    return out

def check_unit(value, unit, fragment, final=False, successful_hook=None):
    need(value['Id'] == unit and value['LoadState'] == 'loaded' and value['FragmentPath'] == fragment and
         value['MainPID'] == '0' and value['Result'] == 'success' and value['ExecMainStatus'] == '0',
         'wrong issued unit or unsuccessful/live worker')
    if not final:
        need((value['ActiveState'], value['SubState']) == ('deactivating', 'stop-post') and
             value['ExecMainCode'] == '1' and value['ControlGroup'].startswith('/user.slice/') and
             value['ControlGroup'].endswith('/' + unit), 'actual exited stop-post proof required')
    else:
        need(successful_hook is not None and successful_hook.get('successful_actual_stop_post_proof') is True,
             'final inactive state cannot replace successful actual stop-post proof')
        need((value['ActiveState'], value['SubState']) == ('inactive', 'dead'), 'unit not independently inactive/dead')
        retained = value['ExecMainCode'] == '1' and value['ControlGroup'] == successful_hook['unit_state']['ControlGroup']
        collected = value['ExecMainCode'] == '0' and value['ControlGroup'] == ''
        need(retained or collected, 'final unit state not linked to actual execution')

def output_inventory(root):
    root = pathlib.Path(root)
    need(root.is_absolute() and root.resolve(strict=True) == root and root.is_dir() and not root.is_symlink(), 'canonical output required')
    rows = []
    for path in sorted(root.iterdir()):
        need(path.is_file() and not path.is_symlink(), 'nonregular generated output')
        rows.append(dict(relative_path=path.name, size_bytes=path.stat().st_size, sha256=sha(path)))
    return rows

def check_manifest(output, rows, actor):
    if actor == 'mq-native-build':
        # Build receipt binds each DLL/C/log; all retained build files are also
        # sealed by external stop-post and independently rehashed at final.
        return
    with (output / 'artifact_manifest.csv').open(newline='') as stream:
        expected = list(csv.DictReader(stream))
    actual = {r['relative_path']: r for r in rows if r['relative_path'] != 'artifact_manifest.csv'}
    need(len(expected) == len(actual) and len({r['relative_path'] for r in expected}) == len(expected), 'manifest membership differs')
    for row in expected:
        need(row['relative_path'] in actual and int(row['size_bytes']) == actual[row['relative_path']]['size_bytes'] and
             row['sha256'] == actual[row['relative_path']]['sha256'], 'manifest bytes differ')

def check_packet(receipt, spec, purpose_sha, actor):
    need(receipt['source_commit'] == spec['source_commit'] and receipt['source_tree'] == spec['source_tree'], 'receipt source mismatch')
    name = 'purpose_sha256' if actor == 'mq-native-build' else 'purpose_contract_sha256'
    need(receipt[name] == purpose_sha and receipt['production_authorized'] is False and
         receipt.get('C_ABI_qualified', False) is False, 'receipt scope or purpose mismatch')
    if actor == 'mq-native-build':
        need(receipt['status'] == 'RETAINED_NATIVE_BUILD_COMPLETE_NOT_NUMERICAL_QUALIFICATION' and
             receipt['numeric_replay_executed'] is False and set(receipt['dlls']) == {'key', 'isotonic', 'inverse'}, 'invalid retained-build closure')
        for dll in receipt['dlls'].values():
            pin_check({k: dll[k] for k in ('path', 'size_bytes', 'sha256')})
        for log in receipt['compile_logs']:
            pin_check(log)
    else:
        need(actor == 'mq-native-replay' and receipt.get('training_paths') == 65536 and
             receipt.get('parameter_refits') == 0 and receipt.get('score_evaluations') == 0 and
             receipt.get('observational_future_truth_used') is False and
             receipt.get('article_promotion_authorized') is False and
             receipt.get('production_consumer_qualified') is False, 'numerical replay scope changed')

def service_definition(spec, grant, private):
    """Single prospective definition used for issuance and independent readback."""
    private = pathlib.Path(private)
    actor = grant['actor']; limits = spec['limits']; root = grant['source_root']
    need(actor in ('mq-native-build', 'mq-native-replay'), 'unknown bounded actor')
    for path in (str(private), root, grant['helper']['path']):
        need(re.fullmatch('/[A-Za-z0-9_./+-]+', path) is not None and '..' not in pathlib.PurePath(path).parts,
             'simple canonical service paths required')
    unit = grant['unit']; cpu = limits['logical_cpu']
    need(re.fullmatch('qdesn-native-(build|replay)-[0-9]{8}-[a-z0-9]{8,64}\\.service', unit) is not None,
         'dedicated fresh native unit name required')
    purpose = str(private / 'purpose.json'); purpose_sha = grant['purpose_sha256']
    base = ['/usr/bin/taskset', '-c', str(cpu), '/usr/bin/time', '-v', '-o', str(private / 'payload.time.txt'),
            '/usr/bin/timeout', '--signal=TERM', '--kill-after=1s', str(limits['wall_term_seconds']) + 's',
            '/usr/bin/prlimit', '--cpu={0}:{0}'.format(limits['cpu_seconds']),
            '--as={0}:{0}'.format(limits['address_space_bytes']), '--fsize={0}:{0}'.format(limits['output_bytes'])]
    if actor == 'mq-native-build':
        need(root == spec['source_root'] and unit.startswith('qdesn-native-build-'), 'build source/unit mismatch')
        base += ['/usr/bin/python3.11', '-I', '-S', '-B', 'scripts/build_mq_native_replay.py']
    else:
        need(unit == spec['administrative_unit_name'] and unit.startswith('qdesn-native-replay-'), 'replay unit mismatch')
        base += ['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript', '--vanilla', 'scripts/qualify_mq_native_composed.R']
    base += ['--contract', purpose, '--sha256', purpose_sha, '--execute']
    hook = ['/usr/bin/taskset', '-c', str(cpu), '/usr/bin/time', '-v', '-o', str(private / 'hook.time.txt'),
            '/usr/bin/timeout', '--signal=TERM', '--kill-after=1s', '19s', '/usr/bin/prlimit',
            '--cpu=20:20', '--as=536870912:536870912', '--fsize=4194304:4194304',
            '/usr/bin/python3.11', '-I', '-S', '-B', grant['helper']['path'], '--phase', 'stop-post', '--private', str(private)]
    fields = {'Type': 'simple', 'WorkingDirectory': root, 'CPUAffinity': str(cpu),
              'LimitCPU': str(limits['cpu_seconds']), 'LimitAS': str(limits['address_space_bytes']),
              'LimitFSIZE': str(limits['output_bytes']), 'RuntimeMaxSec': str(limits['cpu_seconds'] + 10),
              'TimeoutStopSec': '25', 'KillMode': 'control-group', 'Restart': 'no',
              'StandardOutput': 'file:' + str(private / 'worker.log'), 'StandardError': 'inherit',
              'ExecStart': ' '.join(base), 'ExecStopPost': ' '.join(hook)}
    environment = {'OMP_NUM_THREADS': '1', 'OPENBLAS_NUM_THREADS': '1', 'MKL_NUM_THREADS': '1',
                   'R_LIBS': '', 'R_LIBS_USER': '/dev/null', 'R_LIBS_SITE': '/dev/null',
                   'LD_PRELOAD': '', 'LD_AUDIT': '', 'LD_LIBRARY_PATH': '', 'LANG': 'C', 'LC_ALL': 'C',
                   'TZ': 'UTC', 'PATH': '/usr/bin:/bin', 'GIT_TERMINAL_PROMPT': '0'}
    if grant.get('ssh_socket'):
        environment['SSH_AUTH_SOCK'] = grant['ssh_socket']
    if actor == 'mq-native-replay':
        environment.update(QDESN_MQ_NATIVE_EXECUTION_GATE_SHA256=spec['external_execution_gate']['sha256'],
                           QDESN_MQ_NATIVE_PURPOSE_SHA256=purpose_sha,
                           QDESN_MQ_NATIVE_UNIT_NAME=unit)
    return fields, environment

def validate_unit_text(text, spec, grant, private):
    fields, environment = service_definition(spec, grant, private)
    seen = {}; actual_env = {}; section = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('['):
            need(line in ('[Unit]', '[Service]'), 'unexpected unit section')
            section = line
            continue
        need('=' in line, 'malformed unit line')
        key, value = line.split('=', 1)
        if section == '[Unit]':
            need(key == 'Description', 'unapproved unit directive')
        else:
            need(section == '[Service]', 'service section missing')
            if key == 'Environment':
                for word in shlex.split(value):
                    need('=' in word, 'malformed unit environment')
                    name, item = word.split('=', 1)
                    need(name not in actual_env, 'duplicate unit environment')
                    actual_env[name] = item
            else:
                need(key not in seen, 'duplicate service directive')
                seen[key] = value
    need(seen == fields and actual_env == environment, 'actual unit commands/environment/caps differ from prospective definition')

def validate_effective_unit(value, spec, grant, private):
    fields, environment = service_definition(spec, grant, private)
    need(value['DropInPaths'] == '' and value['NeedDaemonReload'] == 'no',
         'unit drop-ins or stale cached configuration forbidden')
    for key in ('WorkingDirectory', 'CPUAffinity', 'LimitCPU', 'LimitAS', 'LimitFSIZE', 'KillMode', 'Restart'):
        need(value[key] == fields[key], 'effective service resource/path policy differs')
    for key in ('ExecStart', 'ExecStopPost'):
        text = value[key]
        match = re.fullmatch(r'\{ path=/usr/bin/taskset ; argv\[\]=(.*?) ; ignore_errors=no ; .* \}', text)
        need(match is not None and match[1] == fields[key] and text.count('{ path=') == 1,
             'effective service command differs from prospective command')
    pairs = [word.split('=', 1) for word in shlex.split(value['Environment'])]
    need(all(len(pair) == 2 for pair in pairs) and len({p[0] for p in pairs}) == len(pairs) and
         dict(pairs) == environment, 'effective service environment differs')

def verify(private, phase):
    private = pathlib.Path(private).resolve(strict=True)
    need(private.is_dir() and private.stat().st_uid == os.getuid(), 'owned private administration required')
    spec = json.loads((private / 'purpose.json').read_text())
    grant = json.loads((private / 'resource_admission.json').read_text())
    purpose_sha = sha(private / 'purpose.json')
    unit = grant['unit']; actor = grant['actor']; output = pathlib.Path(spec['output_root'])
    need(actor in ('mq-native-build', 'mq-native-replay') and grant['purpose_sha256'] == purpose_sha and
         grant['source_commit'] == spec['source_commit'] and grant['source_tree'] == spec['source_tree'], 'administrative identity mismatch')
    need(grant['auto_restart'] is False and grant['allow_production'] is False and grant['allow_article'] is False and
         grant['hook_limits'] == {'cpu_seconds': 20, 'wall_seconds': 20, 'address_space_bytes': 536870912}, 'administrative permission/cost scope changed')
    helper = pin_check(grant['helper']); fragment = pin_check(grant['unit_file'])
    need(helper == pathlib.Path(__file__).resolve() and fragment.name == unit, 'wrong issued helper/fragment')
    need(grant['payload_limits'] == spec['limits'], 'payload limit binding changed')
    validate_unit_text(fragment.read_text(), spec, grant, private)
    failures = []; state = metrics = receipt = hook = hook_cost = None; rows = []
    try:
        state = unit_state(unit)
        validate_effective_unit(state, spec, grant, private)
        metrics = native_time((private / 'payload.time.txt').read_text())
        need(metrics['exit_code'] == 0 and metrics['user_cpu_seconds'] + metrics['system_cpu_seconds'] <= spec['limits']['cpu_seconds'] and
             metrics['wall_seconds'] <= spec['limits']['wall_term_seconds'] + 1 and
             metrics['peak_rss_kib'] * 1024 <= spec['limits']['address_space_bytes'], 'native payload cost/exit invalid')
        rows = output_inventory(output)
        check_manifest(output, rows, actor)
        name = 'BUILD_RECEIPT.json' if actor == 'mq-native-build' else 'qualification.json'
        receipt = json.loads((output / name).read_text())
        check_packet(receipt, spec, purpose_sha, actor)
        private_rows = list(private.iterdir())
        need(all(p.is_file() and not p.is_symlink() for p in private_rows), 'nonregular private artifacts')
        admin = sum(p.stat().st_size for p in private_rows) + 65536
        prepared = sum(spec.get(k, {}).get('size_bytes', 0) for k in ('prepared_payload', 'prepared_derivation', 'prepared_manifest'))
        need(admin < 4 * 1024**2 and sum(r['size_bytes'] for r in rows) + admin + prepared <= spec['limits']['output_bytes'], 'whole-packet output budget exceeded')
        if phase == 'stop-post':
            need({k: os.getenv(k) for k in ('SERVICE_RESULT', 'EXIT_CODE', 'EXIT_STATUS')} ==
                 {'SERVICE_RESULT': 'success', 'EXIT_CODE': 'exited', 'EXIT_STATUS': '0'}, 'actual successful service exit environment required')
            check_unit(state, unit, str(fragment))
        else:
            hook = json.loads((private / 'STOP_POST_RECEIPT.json').read_text())
            need(hook['status'] == 'EXECUTION_PENDING_FINAL_INACTIVE_READBACK' and hook['failures'] == [] and
                 hook['purpose_sha256'] == purpose_sha and hook['grant_sha256'] == sha(private / 'resource_admission.json') and
                 hook['unit'] == unit and hook['outputs'] == rows and hook['payload_native_time'] == metrics,
                 'successful hook identities/outputs/time changed')
            hook_cost = native_time((private / 'hook.time.txt').read_text())
            need(hook_cost['exit_code'] == 0 and hook_cost['user_cpu_seconds'] + hook_cost['system_cpu_seconds'] <= 20 and
                 hook_cost['wall_seconds'] <= 20 and hook_cost['peak_rss_kib'] * 1024 <= 536870912, 'hook cost/exit unclosed')
            check_unit(state, unit, str(fragment), final=True, successful_hook=hook)
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        failures.append(str(error))
    result = dict(schema_version='mq_native_external_terminal_receipt_v1', actor=actor, phase=phase,
                  utc=dt.datetime.now(dt.timezone.utc).isoformat(), source_commit=spec['source_commit'], source_tree=spec['source_tree'],
                  purpose_sha256=purpose_sha, grant_sha256=sha(private / 'resource_admission.json'),
                  unit=unit, unit_state=state, payload_native_time=metrics, outputs=rows, failures=failures,
                  successful_actual_stop_post_proof=phase == 'stop-post' and not failures,
                  hook_native_time=hook_cost, numerical_status=None if receipt is None else receipt.get('numerical_status'),
                  independently_linked_successful_stop_post=phase == 'final' and not failures,
                  stop_post_receipt_sha256=sha(private / 'STOP_POST_RECEIPT.json') if phase == 'final' and hook is not None else None,
                  production_authorized=False, article_promotion_authorized=False,
                  own_administrative_cost_requires_independent_closure=True)
    result['status'] = 'EXECUTION_NOT_ACCEPTED' if failures else (
        'EXECUTION_PENDING_FINAL_INACTIVE_READBACK' if phase == 'stop-post' else 'EXECUTION_COMPLETE_NOT_PRODUCTION')
    target = private / ('STOP_POST_RECEIPT.json' if phase == 'stop-post' else 'FINAL_SUPERVISOR_READBACK.json')
    with target.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False); stream.write('\n')
    return 1 if failures else 0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('stop-post', 'final'), required=True)
    parser.add_argument('--private', required=True)
    args = parser.parse_args()
    return verify(args.private, args.phase)

if __name__ == '__main__':
    raise SystemExit(main())
