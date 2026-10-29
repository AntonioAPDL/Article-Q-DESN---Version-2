"""One nonrenewable, journaled caller envelope for the reviewed PROFILE controller.

This auxiliary caller grants no scientific authority.

450 core CPU plus 50 caller CPU gives 500 per phase, 1000 across the paired
qualification/conditional measurement plan. This source does not grant funding. All actual operations still
pass the published controller's existing gates. No free-form Python/argv is run.
"""
import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import runpy
import signal
import stat
import subprocess
import sys
import time

SCHEMA = 'r165_caller_envelope_v1'
MAX_JSON = 16 * 1024 * 1024
MAX_LINE = 65536
MAX_CLIENTS = 16
CORE_CPU_SECONDS = 450
CALLER_CPU_SECONDS = 50
WHOLE_PHASE_CPU_SECONDS = CORE_CPU_SECONDS + CALLER_CPU_SECONDS
PAIR_CONTROL_CPU_SECONDS = 2 * WHOLE_PHASE_CPU_SECONDS
METADATA_CPU_SECONDS = 4
PUBLICATION_SOURCE_KEY = 'pricefm_profile_caller.py'
assert CALLER_CPU_SECONDS == 2 + MAX_CLIENTS * 3
CONSTRUCTOR_SHA = '1f975e38f84ccf11570b6d800b644e2da2c550db1d511bd64c4ab57d49e768d2'
HERE = Path(__file__).absolute().parent
ACTIONS = {'prepare', 'stage', 'submit', 'release-startup', 'observe-ready',
           'release-worker', 'observe', 'collect', 'cancel', 'reconcile',
           'constructor-notice', 'constructor-prepare', 'constructor-finalize'}
CONFIG_FIELDS = {'schema', 'scope_id', 'phase', 'issued_epoch', 'expires_epoch',
                 'spec', 'package_root', 'constructor', 'administrative_scope',
                 'caller_funding', 'caller_review'}


def need(value, message):
    if not value:
        raise ValueError(message)


def decode(raw):
    def pairs(items):
        out = {}
        for key, value in items:
            need(key not in out, 'duplicate JSON key')
            out[key] = value
        return out
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode()


def identity(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def physical(path):
    need(type(path) is str and path.startswith('/') and '..' not in Path(path).parts,
         'absolute physical path required')
    path = Path(path)
    need(not any(part.is_symlink() for part in (path, *path.parents)), 'symlink path rejected')
    return path


def fp(st):
    return (st.st_dev, st.st_ino, st.st_uid, st.st_mode, st.st_nlink,
            st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def raw(path, maximum=MAX_JSON):
    path = physical(str(path))
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as handle:
        before = os.fstat(handle.fileno())
        need(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
             and before.st_nlink == 1 and before.st_size <= maximum,
             'bounded owned singly linked regular file required')
        data = handle.read(maximum + 1)
        after = os.fstat(handle.fileno())
    need(len(data) == before.st_size and fp(before) == fp(after)
         == fp(physical(str(path)).stat()), 'file changed during bounded read')
    return data


def pin(path):
    data = raw(path)
    return {'path': str(physical(str(path))), 'sha256': hashlib.sha256(data).hexdigest()}


def read_pin(value):
    need(type(value) is dict and set(value) == {'path', 'sha256'}
         and type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}', value['sha256']),
         'exact physical SHA256 pin required')
    data = raw(value['path'])
    need(hashlib.sha256(data).hexdigest() == value['sha256'], 'pinned input changed')
    return decode(data)


def local_metadata(spec, value):
    """Resolve an HB metadata pin only through its exact immutable local copy."""
    path = Path(value['path']); remote = spec.get('remote_root')
    if remote is not None and path.is_relative_to(Path(remote)):
        relative = str(path.relative_to(Path(remote)))
        matches = [item for item in spec['files'] if item['relative'] == relative]
        need(len(matches) == 1 and matches[0]['sha256'] == value['sha256'],
             'exact local metadata copy of HB publication pin required')
        local = matches[0]
        data = raw(local['local'])
        need(len(data) == local['bytes'] and hashlib.sha256(data).hexdigest() == value['sha256'],
             'HB metadata local-copy bytes/SHA changed')
        return decode(data)
    return read_pin(value)


def write_new(path, value):
    path = physical(str(path))
    need(path.is_relative_to(HERE), 'owned tracker output required')
    data = encoded(value)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(data); handle.flush(); os.fsync(handle.fileno())
    dfd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)


def process(pid=None):
    pid = os.getpid() if pid is None else pid
    text = Path('/proc/%d/stat' % pid).read_text()
    fields = text[text.rindex(')') + 2:].split()
    status = Path('/proc/%d/status' % pid).read_text().splitlines()
    uid = int(next(line for line in status if line.startswith('Uid:')).split()[1])
    return {'pid': pid, 'ppid': int(fields[1]), 'start_ticks': int(fields[19]), 'uid': uid}


def arm_expiry(expiry):
    # Whole-second SIGALRM is rounded down, so the caller cannot claim a tail
    # beyond its funded expiry. A subsecond remainder admits no new call.
    seconds = int(expiry - time.time())
    need(seconds >= 1, 'caller window expired or insufficient final second')
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGALRM})
    signal.alarm(seconds)


def set_envelope(soft, expiry=None):
    need(soft in (1, 2) and type(soft) is int, 'fixed caller soft limit required')
    os.sched_setaffinity(0, {31})
    signal.signal(signal.SIGXCPU, signal.SIG_DFL)
    signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGXCPU})
    hard = resource.getrlimit(resource.RLIMIT_CPU)[1]
    need(hard == resource.RLIM_INFINITY or hard >= 40, 'ancestor hard limit must permit separately funded40CPU helper')
    resource.setrlimit(resource.RLIMIT_CPU, (soft, 40))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if expiry is not None:
        arm_expiry(expiry)


def envelope_status(soft):
    mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
    need(resource.getrlimit(resource.RLIMIT_CPU) == (soft, 40)
         and signal.getsignal(signal.SIGXCPU) == signal.SIG_DFL
         and signal.SIGXCPU not in mask and os.sched_getaffinity(0) == {31},
         'caller default unblocked soft CPU envelope changed')
    return {'soft_CPU_seconds': soft, 'hard_CPU_seconds': 40,
            'SIGXCPU_default': True, 'SIGXCPU_unblocked': True, 'CPU_affinity': [31]}


def validate_config(path, *, sources=True):
    config_pin = pin(path); config = read_pin(config_pin)
    need(type(config) is dict and set(config) == CONFIG_FIELDS and config['schema'] == SCHEMA,
         'exact caller configuration required')
    need(type(config['scope_id']) is str and re.fullmatch(r'r164-profile-[a-z0-9]{16,64}', config['scope_id']),
         'exact PROFILE scope ID required')
    need(config['phase'] in ('QUALIFICATION_PAIR', 'MEASUREMENT_PAIR'), 'PROFILE pair phase required')
    now = time.time()
    need(all(type(config[k]) in (int, float) and math.isfinite(config[k]) for k in ('issued_epoch', 'expires_epoch'))
         and config['issued_epoch'] <= now < config['expires_epoch'], 'finite current caller window required')
    spec = read_pin(config['spec'])
    need(spec['schema'] == 'r164_profile_controller_spec_v1'
         and spec['scope_id'] == config['scope_id'] and spec['phase'] == config['phase']
         and config['expires_epoch'] <= spec['controller_expires_epoch']
         and spec['controller_limits']['aggregate_reserved_CPU_seconds'] == CORE_CPU_SECONDS
         and spec['controller_limits']['operation_CPU_seconds'] == METADATA_CPU_SECONDS,
         'exact 450 CPU core and 4 CPU metadata spec/window required')
    scope = read_pin(config['administrative_scope'])
    need(scope.get('admin_cpu') == 31 and scope.get('new_numerical_calls') == 0
         and scope['issued_epoch'] <= now < config['expires_epoch'] <= scope['expires_epoch']
         and physical(config['constructor']['path']).parent.is_relative_to(physical(scope['write_scope'])),
         'current metadata-only constructor scope required')
    need(config['constructor']['sha256'] == CONSTRUCTOR_SHA, 'reviewed constructor source required')
    # Constructor is Python source, not JSON.
    need(pin(config['constructor']['path']) == config['constructor'], 'constructor source changed')
    funding = read_pin(config['caller_funding'])
    need(funding.get('status') == 'CPU_RESERVED_BEFORE_CALLER_START'
         and funding.get('scope_id') == config['scope_id'] and funding.get('phase') == config['phase']
         and funding.get('request') == spec['request']
         and funding.get('controller_sources') == spec['controller_sources']
         and funding.get('caller_CPU_seconds') == CALLER_CPU_SECONDS
         and funding.get('core_CPU_seconds') == CORE_CPU_SECONDS
         and funding.get('whole_phase_CPU_seconds') == WHOLE_PHASE_CPU_SECONDS
         and funding.get('max_clients') == MAX_CLIENTS
         and funding.get('all_reserved_costs_retained_on_failure') is True
         and funding.get('created_epoch', now + 1) <= config['issued_epoch']
         and funding.get('expires_epoch', 0) >= config['expires_epoch']
         and funding.get('driver') == pin(__file__),
         'new nonrefundable 50 caller + 450 core = 500 funding required')
    contract = identity({k: v for k, v in config.items() if k != 'caller_review'})
    review = read_pin(config['caller_review'])
    need(review.get('status') == 'PASS_REVIEWED_CALLER_ENVELOPE'
         and review.get('config_contract_sha256') == contract
         and review.get('driver') == pin(__file__)
         and review.get('spec') == config['spec']
         and review.get('ordinary_entrypoints_preserve_default_SIGXCPU') is True,
         'exact independently reviewed caller/config/source required')
    publication = local_metadata(spec, spec['feature_publication'])
    need(publication.get('status') == 'VERIFIED_FEATURE_PUBLICATION'
         and publication.get('fresh_remote_hash_verified') is True
         and publication.get('feature_only') is True
         and publication.get('source_files') == spec['controller_sources']
         and publication.get('auxiliary_sources', {}).get(PUBLICATION_SOURCE_KEY) == pin(__file__)['sha256'],
         'actual source-reviewed feature publication required')
    package = physical(config['package_root']) / 'pricefm_hb'
    names = spec['controller_sources']
    need(type(names) is dict and 4 <= len(names) <= 64 and
         {'profile_control.py', 'execution_profile.py', 'profile_supervisor.py', '__init__.py'} <= set(names),
         'complete reviewed controller source closure required')
    if sources:
        for name, expected in names.items():
            need(type(name) is str and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*\.py', name), 'module basename required')
            need(pin(package / name)['sha256'] == expected, 'published module changed: ' + name)
    return config, spec, config_pin


def command_argv(command, config, *, read_inputs=True):
    need(type(command) is dict and type(command.get('action')) is str
         and command['action'] in ACTIONS, 'ordinary caller action required; compute and validation forbidden')
    action = command['action']; required = {'action'}
    if action == 'observe-ready': required.add('notification')
    if action == 'release-worker': required |= {'authority', 'proof_staging'}
    if action == 'constructor-finalize': required.add('review')
    need(set(command) == required, 'exact action fields required; no raw argv or extra options')
    for key in required - {'action'}:
        value = command[key]
        need(type(value) is dict and set(value) == {'path', 'sha256'}
             and type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}', value['sha256']),
             'exact action input pin required')
        physical(value['path'])
        if read_inputs: read_pin(value)
    if action.startswith('constructor-'):
        return None
    if action == 'prepare':
        return ['--prepare', config['spec']['path']]
    alias = {'cancel': 'cancel-owned', 'reconcile': 'reconcile-failure'}.get(action, action)
    argv = ['--scope', config['scope_id'], '--action', alias]
    if action == 'observe-ready': argv += ['--notification', command['notification']['path']]
    if action == 'release-worker':
        argv += ['--authority', command['authority']['path'], '--proof-staging', command['proof_staging']['path']]
    return argv


def invoke(command, config):
    argv = command_argv(command, config)
    sys.path.insert(0, config['package_root'])
    if argv is not None:
        from pricefm_hb import profile_control
        profile_control.main(argv)
    else:
        funcs = runpy.run_path(config['constructor']['path'], run_name='r164_reviewed_constructor_nonmain')
        scope = Path(config['administrative_scope']['path'])
        if command['action'] == 'constructor-finalize':
            funcs['finalize'](config['scope_id'], scope, Path(command['review']['path']))
        else:
            funcs['prepare'](config['scope_id'], scope, command['action'] == 'constructor-notice')


def client(config_path, command_path, intent_path):
    # preexec has already armed2CPU before this interpreter starts.
    envelope_status(2)
    config, _, config_pin = validate_config(config_path)
    arm_expiry(config['expires_epoch'])
    command = read_pin(pin(command_path)); intent = read_pin(pin(intent_path))
    root = HERE / 'runs' / config['scope_id']
    slot = Path(intent_path).parent
    need(slot.parent == root and re.fullmatch(r'client_(0[1-9]|1[0-6])', slot.name)
         and Path(intent_path) == slot / 'CLIENT_INTENT.json'
         and Path(command_path) == slot / 'COMMAND.json', 'canonical reserved caller slot paths required')
    started = read_pin(pin(root / 'DRIVER_START.json'))
    need(intent['config'] == config_pin and intent['command'] == pin(command_path)
         and intent['driver'] == pin(__file__) and intent['scope_id'] == config['scope_id']
         and intent['driver_start'] == pin(root / 'DRIVER_START.json')
         and intent['slot'] == int(slot.name[-2:])
         and started['config'] == config_pin and started['driver'] == pin(__file__)
         and started['max_clients'] == MAX_CLIENTS,
         'client exact durable intent/source/config binding required')
    parent = process(os.getppid())
    need(parent == intent['parent'] == started['process'], 'actual caller PID/start/UID changed')
    parent_argv = Path('/proc/%d/cmdline' % parent['pid']).read_bytes().split(b'\0')[:-1]
    expected = [sys.executable, '-I', '-B', str(Path(__file__).absolute()), '--config', str(config_path)]
    need(parent_argv == [x.encode() for x in expected]
         and os.readlink('/proc/%d/exe' % parent['pid']) == os.path.realpath(sys.executable),
         'client must descend directly from exact pinned persistent driver command')
    command_argv(command, config)
    write_new(Path(intent_path).with_name('CLIENT_ACTUAL.json'),
              {'process': process(), 'parent': parent, 'config': config_pin,
               'intent': pin(intent_path), 'envelope': envelope_status(2), 'created_epoch': time.time()})
    invoke(command, config)
    envelope_status(2)


def driver(config_path):
    set_envelope(1)
    os.umask(0o077)
    # Reserve the one-shot scope BEFORE expensive source/authority validation.
    # A killed or rejected startup retains its reservation and cannot reset.
    config_pin = pin(config_path); preliminary = read_pin(config_pin)
    need(type(preliminary) is dict and type(preliminary.get('scope_id')) is str
         and re.fullmatch(r'r164-profile-[a-z0-9]{16,64}', preliminary['scope_id']), 'typed caller scope ID required')
    parent = process(); root = HERE / 'runs' / preliminary['scope_id']
    root.parent.mkdir(mode=0o700, exist_ok=True)
    root.mkdir(mode=0o700, exist_ok=False)  # A dead/finished driver can never reset the same scope.
    write_new(root / 'DRIVER_INTENT.json', {'schema': SCHEMA, 'config': config_pin,
              'driver': pin(__file__), 'process': parent, 'envelope': envelope_status(1),
              'caller_CPU_reservation_seconds': CALLER_CPU_SECONDS, 'max_clients': MAX_CLIENTS,
              'all_failed_costs_retained': True, 'created_epoch': time.time()})
    config, _, checked_pin = validate_config(config_path)
    need(checked_pin == config_pin, 'caller config changed during admission')
    arm_expiry(config['expires_epoch'])
    write_new(root / 'DRIVER_START.json', {'schema': SCHEMA, 'config': config_pin,
              'driver': pin(__file__), 'process': parent, 'envelope': envelope_status(1),
              'caller_CPU_reservation_seconds': CALLER_CPU_SECONDS, 'core_CPU_reservation_seconds': CORE_CPU_SECONDS,
              'whole_phase_CPU_reservation_seconds': WHOLE_PHASE_CPU_SECONDS,
              'pair_control_CPU_reservation_seconds': PAIR_CONTROL_CPU_SECONDS,
              'max_clients': MAX_CLIENTS, 'created_epoch': time.time()})
    print(json.dumps({'status': 'CALLER_DRIVER_READY', 'run_root': str(root), 'process': parent}), flush=True)
    slots = 0; failed = False
    while True:
        line = sys.stdin.buffer.readline(MAX_LINE + 1)
        if not line: break
        need(len(line) <= MAX_LINE and line.endswith(b'\n'), 'bounded complete JSON command line required')
        command = decode(line)
        if command == {'action': 'stop'}: break
        need(slots < MAX_CLIENTS, 'nonrenewable16-client caller reservation exhausted')
        need(pin(config_path) == config_pin and time.time() < config['expires_epoch'], 'caller config changed/window expired')
        command_argv(command, config, read_inputs=False)
        need(not failed or command['action'] in ('cancel', 'reconcile'),
             'after failure only explicit exact-owned cancel/reconcile tail is allowed')
        slots += 1
        slot = root / ('client_%02d' % slots); slot.mkdir(mode=0o700)
        command_path = slot / 'COMMAND.json'; intent_path = slot / 'CLIENT_INTENT.json'
        write_new(command_path, command)
        write_new(intent_path, {'scope_id': config['scope_id'], 'config': config_pin,
                  'driver': pin(__file__), 'command': pin(command_path), 'slot': slots,
                  'driver_start': pin(root / 'DRIVER_START.json'),
                  'parent': parent, 'created_epoch': time.time(), 'soft_CPU_seconds': 2,
                  'hard_CPU_seconds': 40, 'caller_conservative_CPU_charge_seconds': 3,
                  'automatic_retry': False, 'all_failed_costs_retained': True})
        with (slot / 'stdout.raw').open('xb') as stdout, (slot / 'stderr.raw').open('xb') as stderr:
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            proc = subprocess.Popen([sys.executable, '-I', '-B', str(Path(__file__).absolute()), '--client',
                                     str(config_path), str(command_path), str(intent_path)],
                                    stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                    preexec_fn=lambda: set_envelope(2, config['expires_epoch']))
            write_new(slot / 'CLIENT_STARTED.json', {'process': process(proc.pid), 'parent': parent,
                      'intent': pin(intent_path), 'started_epoch': time.time()})
            returncode = proc.wait()
            stdout.flush(); stderr.flush(); os.fsync(stdout.fileno()); os.fsync(stderr.fileno())
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        write_new(slot / 'CLIENT_TERMINAL.json', {'returncode': returncode, 'finished_epoch': time.time(),
                  'waited_subtree_CPU_seconds': after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                  'subtree_measurement_diagnostic_only': True,
                  'caller_conservative_CPU_charge_seconds': 3, 'core_helpers_charged_once_to_core': True,
                  'intent': pin(intent_path), 'stdout': pin(slot / 'stdout.raw'), 'stderr': pin(slot / 'stderr.raw')})
        print(json.dumps({'status': 'CLIENT_TERMINAL', 'slot': slots, 'returncode': returncode,
                          'receipt': str(slot / 'CLIENT_TERMINAL.json')}), flush=True)
        # Failed/unknown invocations are never retried. The same persistent
        # envelope retains its remaining explicitly requested failure-tail slots.
        if returncode != 0: failed = True
        envelope_status(1)
    write_new(root / 'DRIVER_TERMINAL.json', {'status': 'CLOSED_NO_RESUME', 'clients_started': slots,
              'caller_CPU_reservation_seconds': CALLER_CPU_SECONDS, 'all_reserved_costs_retained': True,
              'process': parent, 'finished_epoch': time.time(), 'envelope': envelope_status(1)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--config')
    group.add_argument('--client', nargs=3, metavar=('CONFIG', 'COMMAND', 'INTENT'))
    args = parser.parse_args()
    if args.client: client(*args.client)
    else: driver(args.config)


if __name__ == '__main__':
    main()
