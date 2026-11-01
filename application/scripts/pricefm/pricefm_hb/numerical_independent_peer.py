"""Independent metadata-only numerical release peer, with two acyclic phases.

This source file creates no authority when prepared or imported. A separately
funded invocation may review one actual READY and write only the peer records
for its requested phase. It cannot submit, query a server, run R, read runtime
binaries or scientific arrays, or grant a root capability. Missing observations
fail closed. Current R parsing and the kernel ACK remain conditional compute
obligations, never facts claimed by this administrative program.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import shlex
import signal
import stat
import time

SCIENCE = {
    'application/R/pricefm_r129_al_fixedpoint_certificate.R': 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571',
    'application/R/524_toy_fullstate_consumer.R': '0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a',
    'application/R/525_project_fullstate_consumer.R': '57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2',
    'application/tests/r179_hb_toy.R': '662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190',
    'application/scripts/pricefm/r179_hb_bridge_or_pilot.R': '1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3',
}
MANIFESTS = {
    'base_manifest.json': '60eb4229602956510631bb6989de7d20ccd47cae7f6ab32bbfd6841d64af28e6',
    'addon01_manifest.json': 'daa479878c996684adb936cc4f50150bd4a7008831e4ba39eb41e6693bdc70a8',
    'addon02_manifest.json': 'bc0d9138e420bb508c4848d71fb990d7360e5aa36c405aebc66bec514545befd',
}
NATIVE_R = '9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
TRACER = '914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963'
BOUNDARY = 'bab70fe340dadb350228d37eaa0ac4521f2c1d100b2a5a8b5f8843cbecb8a6fe'
STOCK = '3637a96c29305a0e3f7df19ecf96f85b77f98f0dbb0e783773d217ba2be6dde6'
TARGET = 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
ORIGINAL_MANIFEST = 'aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8'
DELIVERY = {
    'contract/target.json': ('35c93150286b67c3d522b587d732536df64110498fe6c31c0aa9507e85556ec1', 2595),
    'fit/beta_cov.bin': ('0bb1b7fdebaa4a85ecbb371e30913f25479de175544c9050f76aaf55804d0fb9', 1391112),
    'fit/beta_mean.bin': ('e39e1145ced10241e2416f567d9966cc388990031e5fad684692f4a923cc8668', 3336),
    'fit/fixedpoint_certificate.json': ('d5b22a44864d3a82f3e448a5c11a688fe77f21e5fc2882e8fa415a75967d0680', 1860),
    'fit/terminal.json': ('f2875eaa7af4765769b9bec34eea249fe21e8a3f4b69f93a75d0e7e03d150901', 2661),
    'fit/vb_trace.csv': ('305d8ef67886d1617f0a10a20d09e82d91cb7cfd576f36c1920590393586ee3e', 35662),
    'design/terminal.json': ('735b18e40a305340a88f0953ff4fca914419b95ef69564cb1873afde0e4797c3', 454),
    'parent/terminal.json': ('a0528d7de54585a689628cb73b185eb20296758fa5f28267bfed8bea1e2c351f', 2694),
    'code/cran_adapter.R': ('679e6c929b09b710d412962b7ccaf965885065dfce08eacb5279834b3db9a554', 7389),
    'code/cran_manifest.json': ('30cd4a7eac5a59e32aa788427347962b2312aca744977e5a186e341a1a6ef4c8', 2927),
    'code/fixedpoint_helper.R': ('c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571', 7519),
    'design/X.bin': ('ac7835f74bfeb6b833d15c8738d391f6cf6461770d4bfa1d0962af4941907234', 162049536),
    'design/y.bin': ('50ec829d66f3dad98ffe41619c09b12475823a4d93546bace702da5678c66736', 388608),
    'design/design.json': ('e0a4ee224b54c7ef08250f13cce4335a1c6da2a4e4ba0b639ac1435103f95286', 24878),
    'design/scaler.json': ('c11fbbef36b504a489f364f36232b54c4d5d7403da09f67acbece2bfa8bf6da8', 260),
}
THREADS = ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
           'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS', 'BLIS_NUM_THREADS')
READS = {}
COMPUTE_NAMES = {'__init__.py', 'startup_helper.py', 'startup_batch_worker.py', 'profile_admission.py',
    'environment.py', 'runtime_archive.py', 'scientific_namespace_plan.py', 'scientific_namespace_contract.py',
    'scientific_allocation.py', 'scientific_code_install.py', 'scientific_metadata_owner.py',
    'scientific_namespace_fixture.R', 'scientific_boundary_fixture.R', 'scientific_batch.py',
    'scientific_batch_worker.py', 'numerical_batch.py', 'numerical_stage_owner.py', 'numerical_stage_contract.py',
    'numerical_physical_admission.py', 'numerical_stage_worker.py', 'numerical_stage_bootstrap.R'}
ADMIN_NAMES = {'numerical_stage_prepare.py', 'numerical_critical_driver.py', 'numerical_independent_peer.py'}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def strict_json(raw):
    def pairs(rows):
        out = {}
        for key, value in rows:
            require(key not in out, 'duplicate JSON key')
            out[key] = value
        return out
    def bad(value):
        raise ValueError('nonfinite JSON token: ' + value)
    def real(value):
        number = float(value)
        require(math.isfinite(number), 'nonfinite JSON exponent')
        return number
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad, parse_float=real)


def physical(path):
    p = Path(path)
    require(p.is_absolute() and '..' not in p.parts, 'absolute physical path')
    require(p.resolve(strict=True) == p, 'symlink or nonphysical input path')
    return p


def read_bytes(path, expected=None, *, code=False):
    p = physical(path)
    require(code or p.suffix in ('.json', '.stdout', '.stderr', '.lock'),
            'only explicit code or metadata may be opened')
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
                and before.st_uid in (0, os.getuid()) and before.st_size <= 32 * 1024**2,
                'bounded owned regular metadata/code')
        raw = stream.read(32 * 1024**2 + 1)
        after = os.fstat(stream.fileno())
    fingerprint = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    require(fingerprint(before) == fingerprint(after) == fingerprint(p.stat())
            and len(raw) == before.st_size, 'stable exact metadata/code read')
    sha = hashlib.sha256(raw).hexdigest()
    require(expected is None or sha == expected, 'pinned metadata/code hash changed')
    READS[str(p)] = dict(path=str(p), sha256=sha, bytes=len(raw))
    return raw


def pin(path, *, code=False):
    raw = read_bytes(path, code=code)
    return dict(path=str(path), sha256=hashlib.sha256(raw).hexdigest())


def check_pin(p):
    require(type(p) is dict and set(p) == {'path', 'sha256'}
            and type(p['path']) is str and p['path'].startswith('/')
            and '..' not in PurePosixPath(p['path']).parts
            and re.fullmatch('[a-f0-9]{64}', p['sha256']) is not None, 'strict absolute SHA pin')
    return p


def read(p):
    check_pin(p)
    return strict_json(read_bytes(p['path'], p['sha256']))


def local(path):
    return strict_json(read_bytes(path))


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()


def embedded(value, p):
    check_pin(p)
    require(hashlib.sha256(encoded(value)).hexdigest() == p['sha256'],
            'embedded compute metadata differs from actual file pin')


def write_new(path, value):
    require(path.parent.resolve(strict=True) == path.parent and not path.is_symlink(),
            'physical review output parent')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(encoded(value)); stream.flush(); os.fsync(stream.fileno())


def exact_int(value, expected):
    return type(value) is int and value == expected


def kernel_cpu_list(raw):
    require(type(raw) is str and 0 < len(raw) <= 4096, 'bounded actual kernel CPU list')
    values = set()
    for item in raw.strip().split(','):
        match = re.fullmatch(r'(\d+)(?:-(\d+))?', item)
        require(match is not None, 'standard kernel CPU range/list syntax')
        first = int(match[1]); last = int(match[2] or match[1])
        require(0 <= first <= last <= 65535 and last - first < 4096, 'bounded ordered CPU range')
        values.update(range(first, last + 1)); require(len(values) <= 4096, 'bounded online CPU set')
    return values


def role_limits(role, limits):
    require(exact_int(limits.get('production_fits'), 0)
            and limits.get('production_acceptance') is False, 'no production fits or promotion')
    if role == 'TOY_PARITY':
        require(limits.get('scientific_target_data') is False
                and all(exact_int(limits.get(k), v) for k, v in dict(
                    optimizer_invocations=8, combined_iterations=30, maximum_n=128, maximum_p=32).items()),
                'exact synthetic eight-call thirty-iteration toy')
    else:
        require(role == 'ZERO_UPDATE_BRIDGE' and limits.get('scientific_target_data') is True
                and limits.get('target_name') == TARGET
                and all(exact_int(limits.get(k), v) for k, v in dict(
                    optimizer_invocations=0, optimizer_updates=0, n=48576, p=417).items())
                and limits.get('tau') == .75 and limits.get('tau0') == .0022915214919211734
                and limits.get('both_RHS_starts') is True
                and limits.get('certificate_limits') == dict(beta_posterior_sd_rms=1e-4,
                    covariance_whitened_rms=1e-4, elbo_relative=1e-8, predictor_rms=1e-6,
                    rhs_joint_log_rates=1e-6, rhs_start_log_precision=1e-6, sigma_relative=1e-6),
                'exact NO3 zero-update bridge and original seven gates')


def guard(value, cpu, wall):
    flags = ('all_owned_descendants_reaped', 'independent_guardian', 'kernel_escape_filter',
             'orphan_subreaper', 'guardian_included_in_CPU', 'inherited_waited_history_included_once')
    require(exact_int(value.get('returncode'), 0) and exact_int(value.get('command_returncode'), 0)
            and value.get('cap_reason') is None and value.get('CPU_limit') == cpu
            and type(value.get('aggregate_CPU_seconds')) in (int, float)
            and math.isfinite(value['aggregate_CPU_seconds'])
            and type(value.get('complete_lifecycle_wall_seconds')) in (int, float)
            and math.isfinite(value['complete_lifecycle_wall_seconds'])
            and 0 <= value.get('aggregate_CPU_seconds', math.inf) < cpu
            and 0 <= value.get('complete_lifecycle_wall_seconds', math.inf) <= wall
            and value.get('guardian_forced_monitor_stop') is False
            and all(value.get(k) is True for k in flags), 'actual complete original native guard')


def prerequisites(config):
    bundle = read(config['prerequisite_bundle']); reuse = read(config['runtime_reuse'])
    require(bundle.get('status') == 'PREPARED_ACTUAL_ACCEPTED_BOUNDARY_EVIDENCE_NOT_EXECUTION_AUTHORITY',
            'actual accepted prerequisite metadata closure')
    aliases = {}
    for row in bundle['artifacts']:
        logical = check_pin(row['logical']); actual = check_pin(row.get('local') or row['staged'])
        require(logical['path'] not in aliases and logical['sha256'] == actual['sha256'],
                'unique logical proof alias preserving original bytes')
        raw = read_bytes(actual['path'], actual['sha256'])
        require(type(row['bytes']) is int and len(raw) == row['bytes'], 'exact logical proof length')
        value = strict_json(raw) if Path(logical['path']).suffix == '.json' else None
        aliases[logical['path']] = (logical['sha256'], len(raw), value)
    require(1 <= len(aliases) <= 128, 'closed bounded proof aliases')
    def resolve(p):
        check_pin(p); require(p['path'] in aliases and aliases[p['path']][0] == p['sha256'],
                              'proof referenced outside exact logical alias closure')
        return aliases[p['path']][2]
    accepted = bundle['accepted_boundary']
    require(accepted.get('status') == 'ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
            and accepted.get('role') == 'SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'
            and accepted.get('namespace_proved') is True and accepted.get('scientific_boundary_proved') is True,
            'outer accepted actual namespace and TSYNC prerequisite')
    g = resolve(accepted['actual_accept_action_guard']); guard(g, 5, 180)
    require(dict(strict_json(g['stdout']), status=accepted['status'],
                 actual_accept_action_guard=accepted['actual_accept_action_guard']) == accepted,
            'accepted record equals guarded candidate')
    manifest = resolve(accepted['full_return_manifest']); result = resolve(accepted['result'])
    account = resolve(accepted['accounting']); peer = resolve(accepted['independent_review'])
    require(account.get('terminal') is True and account.get('complete') is True
            and account.get('job_id') == accepted['job_id'] and account.get('primary_charge_counted_once') is True
            and account.get('canonical_primary_CPU_seconds') == accepted['canonical_primary_CPU_seconds'],
            'complete actual parent accounting with one primary charge')
    require(peer.get('status') == 'PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
            and peer.get('job_id') == accepted['job_id'] and peer.get('role') == accepted['role']
            and all(peer.get(k) == accepted[v] for k, v in dict(result='result', accounting='accounting',
                return_manifest='full_return_manifest').items()), 'actual independent accepted parent return')
    require(result.get('status') == 'PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER'
            and result.get('job_id') == accepted['job_id'] and result.get('node') == 'node-13', 'actual parent worker')
    outcome = result['outcome']; native = resolve(outcome['owned_guard'])
    require(outcome.get('status') == 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
            and outcome.get('original_guard_source_preserved') is True
            and native.get('schema') == 'r157_traced_bootstrap_guard_receipt_v1'
            and native.get('status') == 'EXITED' and native.get('returncode') == 0
            and all(native.get(k) is True for k in ('reaped', 'drained', 'CPU_accounting_complete',
                'all_newborns_kernel_traced_before_execution', 'tracer_death_kernel_EXITKILL_enabled',
                'postbootstrap_TSYNC_scientific_fork_denial', 'scientific_target_access_handshake'))
            and native.get('remaining_owned_lifetimes') == [] and native.get('unexpected_untraced_child_waits') == [],
            'actual kernel-owned drained TSYNC/ACK parent')
    att = native.get('scientific_filter_kernel_attestation') or {}
    require(att.get('operation') == 'SECCOMP_SET_MODE_FILTER' and att.get('flags') == 'TSYNC'
            and att.get('kernel_return') == 0, 'actual successful native TSYNC attestation')
    require(manifest.get('job_id') == accepted['job_id'] and manifest.get('scope_id') == accepted['scope_id'],
            'complete prerequisite return identity')
    seen = set()
    for row in manifest['files']:
        relative = PurePosixPath(row['relative'])
        require(not relative.is_absolute() and '..' not in relative.parts and str(relative) not in seen,
                'unique exact prerequisite return member')
        seen.add(str(relative)); logical = str(PurePosixPath(bundle['return_remote_root']) / relative)
        require(logical in aliases and aliases[logical][:2] == (row['sha256'], row['bytes']),
                'exact path/hash/length alias coverage; duplicate byte substitution forbidden')
    installation = result['installation']; inventory = resolve(bundle['inventory'])
    require(installation.get('status') == 'INSTALLED_CODE_BYTES_ONLY_NOT_NAMESPACE_OR_SCIENTIFIC_PROOF'
            and installation.get('files') == 2279 and installation.get('bytes') == 275498747
            and installation.get('job_id') == accepted['job_id'] and inventory.get('job_id') == accepted['job_id'],
            'actual accepted exact namespace code inventory')
    require(reuse.get('status') == 'PREPARED_ACCEPTED_NAMESPACE_RUNTIME_REUSE_NOT_EXECUTION_AUTHORITY'
            and reuse.get('accepted_boundary') == accepted and reuse.get('inventory') == inventory
            and reuse.get('native_R') == dict(path=installation['R_HOME'] + '/bin/exec/R', sha256=NATIVE_R)
            and set(reuse['manifest_inputs']) == set(MANIFESTS), 'qualified runtime context, no old execution grant')
    expected = []; total = 0; names = set(); runtime_root = str(Path(installation['R_HOME']).parent)
    for label, expected_sha in MANIFESTS.items():
        p = reuse['manifest_inputs'][label]; require(p['sha256'] == expected_sha, 'original runtime manifest SHA')
        for row in read(p)['files']:
            relative = PurePosixPath(row['relative'])
            require(not relative.is_absolute() and '..' not in relative.parts and str(relative) not in names,
                    'disjoint safe runtime code metadata')
            names.add(str(relative)); total += row['bytes']
            expected.append(dict(path=runtime_root + '/' + str(relative), sha256=row['sha256']))
    require(expected == reuse['runtime_files'] and len(names) == 2279 and total == 275498747,
            'exact 2279-member accepted runtime metadata; current compute still rehashes all')
    return bundle, reuse


def opaque_delivery(config, spec, packet, reuse):
    """Review only sealed delivery metadata; no target member is opened."""
    if config['role'] == 'TOY_PARITY':
        require(config['target_delivery'] == spec['target_delivery'] == [], 'synthetic toy has no real delivery')
        return {}
    original_pin = check_pin(config['original_manifest'])
    require(original_pin['sha256'] == ORIGINAL_MANIFEST, 'full unchanged original mathematical manifest')
    original = read(original_pin)
    selected = [row for row in original['targets'] if row['name'] == TARGET]
    require(len(selected) == 1, 'one exact original NO3 target')
    target = selected[0]; contract = target['contract']
    require(target['n'] == 48576 and target['p'] == 417 and target['tau'] == .75,
            'exact original target dimensions')
    rows = config['target_delivery']; remote_rows = spec['target_delivery']
    require(type(rows) is list and len(rows) == len(remote_rows) == 15,
            'closed fifteen-member original and actual remote delivery')
    by_relative = {}; logical = set(); expected_aliases = {}; expected = {}
    by_hash = {row['sha256']: row for row in target['bindings']}
    require(len(by_hash) == len(target['bindings']), 'unique original frozen target binding hashes')
    for row, remote in zip(rows, remote_rows):
        require(set(row) in ({'relative', 'bytes', 'source', 'logical_path'},
                            {'relative', 'bytes', 'source', 'logical_path', 'remote'}), 'closed original source row fields')
        relative = row['relative']; require(relative in DELIVERY and relative not in by_relative, 'closed unique target member')
        source = check_pin(row['source']); sha, length = DELIVERY[relative]
        require(source['sha256'] == sha and exact_int(row['bytes'], length)
                and 0 <= length <= 192 * 1024**2, 'exact frozen opaque member SHA and length')
        if 'remote' in row:
            require(check_pin(row['remote'])['sha256'] == sha, 'proposal alias preserves original opaque bytes')
        path = row['logical_path']
        require(type(path) is str and path.startswith('/') and '..' not in PurePosixPath(path).parts
                and path not in logical, 'unique exact original logical source alias')
        original_logical = by_hash[sha]['path'] if sha in by_hash else contract['design_dir'] + '/' + Path(relative).name
        require(path == original_logical, 'opaque logical alias derives from unchanged original target metadata')
        logical.add(path); by_relative[relative] = row
        expected_remote = dict(path=packet['remote_root'] + '/target/' + relative, sha256=sha)
        require({k: v for k, v in remote.items() if k != 'remote'} == {k: v for k, v in row.items() if k != 'remote'}
                and remote.get('remote') == expected_remote, 'actual generated target alias preserves all original source metadata')
        expected['target/' + relative] = (sha, length)
        expected_aliases[path] = expected_remote['path']
    require(set(by_relative) == set(DELIVERY) and sum(row['bytes'] for row in rows) == 163921491
            and sum(row['bytes'] for row in rows) <= 256 * 1024**2, 'exact complete frozen delivery bytes')
    authority = read(config['opaque_delivery_authority'])
    require(authority.get('status') == 'ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY'
            and authority.get('scope') == config['scope'] and authority.get('target_name') == TARGET
            and authority.get('files') == rows and authority.get('no_optimizer_or_science_execution') is True
            and authority.get('allow_opaque_transport') is True
            and exact_int(authority.get('maximum_files'), 15)
            and exact_int(authority.get('maximum_file_bytes'), 192 * 1024**2)
            and exact_int(authority.get('maximum_total_bytes'), 256 * 1024**2)
            and authority.get('original_manifest') == original_pin, 'separately funded explicit opaque transport only')
    for binding in target['bindings']:
        require(any(row['logical_path'] == binding['path'] and row['source']['sha256'] == binding['sha256'] for row in rows),
                'every original frozen target binding has an exact opaque alias')
    for key, folder in [('design_dir', 'design'), ('output_dir', 'fit'), ('parent_dir', 'parent')]:
        expected_aliases[contract[key]] = packet['remote_root'] + '/target/' + folder
    expected_aliases[contract['cran_library']] = str(Path(reuse['native_R']['path']).parents[2]) + '/library'
    execution = local(Path(config['registry']) / config['role'] / 'packet/execution_manifest.json')
    original_remote = dict(path=packet['remote_root'] + '/original_target_manifest.json', sha256=ORIGINAL_MANIFEST)
    require(execution == dict(schema='r182_exact_NO3_HB_alias_execution_manifest_v1',
        status='PREPARED_REMOTE_ALIASES_NOT_EXECUTION_AUTHORITY', original_manifest=original_remote,
        execution={TARGET: dict(aliases=expected_aliases, execution_host=config['node'], source_host='jerez.be.ucsc.edu')},
        original_mathematical_manifest_bytes_unchanged=True, optimizer_updates=0), 'exact metadata-only execution aliases, no new mathematical recipe')
    require(spec.get('execution_manifest') == dict(path=packet['remote_root'] + '/execution_manifest.json',
        sha256=pin(Path(config['registry']) / config['role'] / 'packet/execution_manifest.json')['sha256']),
        'actual bridge execution manifest pin')
    expected['original_target_manifest.json'] = (ORIGINAL_MANIFEST, READS[original_pin['path']]['bytes'])
    return expected


def packet_and_native_journals(config, root, packet, spec, ready, ready_guard_path, reuse):
    """One consolidated actual packet/action review, without new native work."""
    registry = root.parent; source_sha = spec['sources']['numerical_batch.py']['sha256']
    paths = sorted(registry.glob('control_*.started.json'))
    require(len(paths) == 4, 'exact fresh prepare/stage/submit/READY lifecycle journals')
    limits = {'prepare': dict(local_CPU=4, wall=120),
        'stage': dict(local_CPU=18, remote_unknown_fee=18, wall=300, maximum_calls=1),
        'submit': dict(local_CPU=4, remote_unknown_fee=4, wall=45, maximum_calls=1),
        'ready': dict(local_CPU=6, remote_unknown_fee=6, wall=330, maximum_calls=1)}
    results = {}
    for path, action in zip(paths, ['prepare', 'stage', 'submit', 'ready']):
        start = local(path); pending_path = path.with_name(path.name.replace('.started.json', '.pending.json'))
        pending = local(pending_path)
        require(start.get('status') == 'ACTION_STARTED_NOT_SUCCESS'
                and start.get('action') == action and start.get('role') == config['role']
                and start.get('source_sha256') == source_sha and start.get('limits') == limits[action]
                and type(start.get('command_pid')) is int and start['command_pid'] > 0
                and type(start.get('command_birth_ticks')) is int and start['command_birth_ticks'] > 0
                and pending.get('status') == 'INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
                and all(pending.get(k) == v for k, v in start.items() if k != 'status'),
                'actual action identity/source/native caps and completed internal result')
        if action == 'ready':
            guard_pin = pin(ready_guard_path)
            require(not path.with_name(path.name.replace('.started.json', '.validated.json')).exists(),
                    'READY remains pending until unchanged release finalizes its guard')
        else:
            validated = local(path.with_name(path.name.replace('.started.json', '.validated.json')))
            require(validated.get('status') == 'ACTUAL_ACTION_GUARD_PASSED'
                    and validated.get('started') == pin(path) and validated.get('pending') == pin(pending_path),
                    'actual exact validated prior native action pins')
            guard_pin = validated['guard']
        observed = read(guard_pin); guard(observed, limits[action]['local_CPU'], limits[action]['wall'])
        require(observed.get('session_id') == start['command_pid']
                and observed.get('leader_start_ticks') == start['command_birth_ticks']
                and strict_json(observed['stdout']) == pending['result'], 'whole native guard owns exact PID/birth/result')
        results[action] = pending['result']
    require(results['prepare'] == packet and results['submit'] == dict(job_id=ready['job_id'], scope_id=spec['scope_id'])
            and results['ready'] == ready, 'actual complete guarded packet, submit and READY outputs')
    previous = None; journal = []
    for path in sorted(root.glob('record_*.json')):
        row = local(path); require(row['previous'] == previous, 'exact role journal chain')
        journal.append(row); previous = pin(path)
    require([row['state'] for row in journal] == ['PREPARED', 'STAGING_INTENT', 'STAGED', 'SUBMISSION_INTENT',
        'SUBMISSION_REPLY_OBSERVED_NOT_ACCEPTED', 'SUBMITTED', 'READY_VALIDATED']
        and journal[0]['packet'] == pin(root / 'PACKET.json')
        and journal[-1]['ready'] == pin(root / 'READY.json'), 'single complete unfailed actual native lifecycle')
    expected = {}
    def add(relative, sha, size):
        require(relative not in expected and type(size) is int and size >= 0, 'unique bounded packet member')
        expected[relative] = (sha, size)
    for name, p in spec['sources'].items():
        require(p['path'] == packet['remote_root'] + '/package/pricefm_hb/' + name, 'exact remote compute code member')
        add('package/pricefm_hb/' + name, p['sha256'], READS[str(Path(config['source_dir']) / name)]['bytes'])
    for name, p in spec['science'].items():
        require(p['path'] == packet['remote_root'] + '/science/' + name, 'exact immutable science code alias')
        add('science/' + name, p['sha256'], READS[config['scientific_sources'][name]['path']]['bytes'])
    for key, suffix, sha in [('traced_guard', '.py', TRACER), ('boundary_library', '.so', BOUNDARY)]:
        original = check_pin(config[key]); require(original['sha256'] == sha, 'unchanged original native ownership machinery')
        relative = 'science/' + key + suffix
        require(spec['controls'][key] == dict(path=packet['remote_root'] + '/' + relative, sha256=sha), 'exact remote native ownership pin')
        add(relative, sha, physical(original['path']).stat().st_size)  # Metadata only; no native binary opened.
    bundle = read(config['prerequisite_bundle']); staged_bundle = local(root / 'packet/prerequisite_bundle.json')
    expected_bundle = dict(bundle); staged_rows = []
    for i, row in enumerate(bundle['artifacts']):
        relative = 'prerequisites/artifact_%04d' % i; actual = row.get('local') or row['staged']
        remote_pin = dict(path=packet['remote_root'] + '/' + relative, sha256=actual['sha256'])
        staged_rows.append(dict(row, staged=remote_pin)); add(relative, actual['sha256'], row['bytes'])
    expected_bundle['artifacts'] = staged_rows
    require(staged_bundle == expected_bundle, 'complete original logical proof aliases preserve exact staged metadata')
    staged_reuse = local(root / 'packet/runtime_reuse.json'); expected_reuse = dict(reuse); manifests = {}
    for i, (label, p) in enumerate(sorted(reuse['manifest_inputs'].items())):
        relative = 'runtime_manifest_%02d.json' % i
        manifests[label] = dict(path=packet['remote_root'] + '/' + relative, sha256=p['sha256'])
        add(relative, p['sha256'], READS[p['path']]['bytes'])
    expected_reuse['manifest_inputs'] = manifests
    require(staged_reuse == expected_reuse, 'exact qualified staged runtime manifest aliases')
    for relative, key in [('prerequisite_bundle.json', 'prerequisite_bundle'), ('runtime_reuse.json', 'runtime_reuse')]:
        p = pin(root / 'packet' / relative)
        require(spec['controls'][key] == dict(path=packet['remote_root'] + '/' + relative, sha256=p['sha256']), 'exact staged runtime/proof descriptor pin')
        add(relative, p['sha256'], READS[p['path']]['bytes'])
    require(set(spec['controls']) == {'traced_guard', 'boundary_library', 'prerequisite_bundle', 'runtime_reuse'}, 'closed native controls')
    scope_pin = config['scope']; add('Q_SCOPE.json', scope_pin['sha256'], READS[scope_pin['path']]['bytes'])
    require(spec['scope'] == dict(path=packet['remote_root'] + '/Q_SCOPE.json', sha256=scope_pin['sha256']), 'exact staged numerical scope')
    for relative, (sha, size) in opaque_delivery(config, spec, packet, reuse).items():
        add(relative, sha, size)
    for relative in ['SPEC.json'] + (['execution_manifest.json'] if config['role'] == 'ZERO_UPDATE_BRIDGE' else []):
        p = pin(root / 'packet' / relative); add(relative, p['sha256'], READS[p['path']]['bytes'])
    script = '#!/bin/bash\nset -euo pipefail\numask 077\nulimit -c 0\nulimit -t 600\nexport PATH=/usr/bin:/bin\nexport TZ=UTC\n'
    script += '\n'.join('export ' + k + '=1' for k in sorted(THREADS)) + '\n'
    script += 'exec ' + shlex.join([config['cached_python'], '-I', '-B', packet['remote_root'] + '/package/pricefm_hb/numerical_stage_worker.py',
        '--spec', packet['remote_root'] + '/SPEC.json', '--sha256', packet['spec_sha256']]) + '\n'
    raw_script = read_bytes(root / 'packet/job.sbatch', code=True)
    require(raw_script == script.encode(), 'same-PID direct SBATCH owner and exact whole600/single-thread launch')
    add('job.sbatch', hashlib.sha256(raw_script).hexdigest(), len(raw_script))
    uploads = packet['uploads']; require(type(uploads) is list and 1 <= len(uploads) <= 256, 'bounded closed packet upload list')
    actual = {}
    target_sources = {'target/' + row['relative']: row['source']['path'] for row in config['target_delivery']}
    for row in uploads:
        relative = row['relative']; require(relative in expected and relative not in actual, 'no extra or duplicate packet member')
        require(type(row['bytes']) is int and (row['sha256'], row['bytes']) == expected[relative], 'exact complete packet member SHA/length')
        if relative in target_sources:
            require(row['local'] == target_sources[relative], 'opaque target source path is exactly separately admitted source')
        actual[relative] = (row['sha256'], row['bytes'])
    require(actual == expected, 'no omitted packet member')
    staged = journal[2]; checksum_pin = staged['checksum']
    require(checksum_pin == pin(root / 'STAGE_CHECKSUM.json')
            and results['stage'] == dict(status='STAGED_NOT_SUBMITTED', scope_id=spec['scope_id'], checksum=checksum_pin),
            'actual complete stage guard pins original checksum observation')
    observation = read(checksum_pin); hashes = {packet['remote_root'] + '/' + rel: sha for rel, (sha, _) in expected.items()}
    hashes[config['cached_python']] = config['cached_python_sha256']
    require(observation.get('returncode') == 0 and observation.get('stderr') == ''
            and observation.get('argv') == ['sha256sum', *sorted(hashes)], 'actual complete remote stage checksum command/result')
    parsed = {}
    for line in observation['stdout'].splitlines():
        fields = line.split(None, 1)
        require(len(fields) == 2 and re.fullmatch('[0-9a-f]{64}', fields[0]) is not None
                and fields[1] not in parsed, 'strict complete unique original stage checksum rows')
        parsed[fields[1]] = fields[0]
    require(parsed == hashes, 'all remote packet bytes and cached Python actually matched; no peer array read')


def context(config_path, bundle_path, ready_guard_path, driver_authority_path):
    require(os.sched_getaffinity(0) == {31}, 'administrative CPU31 only')
    config = local(config_path); scope = read(config['scope']); now = time.time()
    authority = local(driver_authority_path)
    require(authority.get('status') == 'ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE'
            and authority.get('config') == pin(config_path) and authority.get('scope') == config['scope']
            and authority.get('peer_program') == pin(str(Path(__file__).absolute()), code=True)
            and authority.get('peer_program_independently_authored_and_reviewed') is True
            and authority.get('role') == config['role'] and authority.get('role_limits') == config['role_limits']
            and exact_int(authority.get('max_calls'), 1) and authority.get('automatic_retry') is False
            and exact_int(authority.get('peer_CPU_each'), 8)
            and authority.get('peer_phases') == ['source_physical', 'owner_release']
            and scope['issued_epoch'] <= authority['issued_epoch'] <= now < authority['expires_epoch'] <= scope['expires_epoch'],
            'new exact funded independent peer lifecycle authority')
    read_bytes(authority['driver_source']['path'], authority['driver_source']['sha256'], code=True)
    require(config.get('critical_driver') == authority['driver_source']
            and scope.get('status') == 'PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE'
            and scope.get('roles') == [config['role']] and exact_int(scope.get('maximum_jobs'), 1)
            and exact_int(scope.get('compute_CPU_reservation'), 600)
            and exact_int(scope.get('wall_seconds'), 1200) and exact_int(scope.get('memory_MiB'), 8192)
            and exact_int(scope.get('threads'), 1) and exact_int(scope.get('cpus_per_task'), 1)
            and scope.get('automatic_retry') is False and scope.get('requeue') is False,
            'fresh exact whole numerical purpose and funding')
    role_limits(config['role'], config['role_limits'])
    canonical = read(config['canonical_authority'])
    require(canonical.get('status') == 'ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'
            and canonical.get('binding') == {k: v for k, v in config.items() if k != 'canonical_authority'}
            and exact_int(canonical.get('maximum_jobs'), 1)
            and scope['issued_epoch'] <= canonical['issued_epoch'] <= now < canonical['expires_epoch'] <= scope['expires_epoch'],
            'exact canonical root configuration authority and bounded time')
    root = physical(str(Path(config['registry']) / config['role'])); out = physical(bundle_path)
    require(out == Path(scope['allowed_metadata_output_root']) / 'critical_driver/release'
            and root.parent == Path(config['registry']), 'exact private role and review output roots')
    packet = local(root / 'PACKET.json'); spec = local(root / 'packet/SPEC.json')
    ready = local(root / 'READY.json'); job = local(root / 'JOB.json')
    require(packet['spec_sha256'] == pin(root / 'packet/SPEC.json')['sha256']
            and packet['role'] == spec['role'] == ready['role'] == config['role']
            and ready.get('status') == 'READY_SOURCE_BOUND_COMPUTE_METADATA'
            and ready['scope_id'] == packet['scope_id'] == spec['scope_id']
            and ready['job_id'] == job['job_id'] and ready['node'] == spec['node'] == config['node'] == 'node-13'
            and ready['spec_sha256'] == packet['spec_sha256'] and ready['sources'] == packet['sources'] == spec['sources']
            and ready.get('models') == ready.get('optimizer_invocations') == 0
            and ready.get('physical_numerical_admission') is False
            and ready.get('cpus_per_task') == 1 and len(ready['affinity']) == 1,
            'exact current zero-work READY and job/source/spec binding')
    g = local(ready_guard_path); guard(g, 6, 330)
    require(strict_json(g['stdout']) == ready, 'actual ready action returned these exact READY bytes')
    publication = read(config['publication']); source_review = read(config['source_review'])
    require(publication.get('status') == 'PASS_FROZEN525_NUMERICAL_BATCH_SOURCE_PUBLICATION'
            and source_review.get('status') == 'PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_SOURCE'
            and publication['source_files'] == source_review['source_files']
            and set(publication['source_files']) == set(spec['sources']) == COMPUTE_NAMES
            and publication['commit'] == spec['source_commit'], 'frozen independently reviewed numerical source')
    for name, sha in publication['source_files'].items():
        require('/' not in name and name.endswith(('.py', '.R')), 'closed source file names')
        read_bytes(str(Path(config['source_dir']) / name), sha, code=True)
        require(spec['sources'][name]['sha256'] == sha, 'current compute source equals frozen source')
    require(publication.get('administrative_source_files') == source_review.get('administrative_source_files')
            and set(publication.get('administrative_source_files', {})) == ADMIN_NAMES,
            'closed independently reviewed administrative builder, critical driver and peer sources')
    for name, sha in publication['administrative_source_files'].items():
        read_bytes(str(Path(config['source_dir']) / name), sha, code=True)
    require(authority['driver_source']['sha256'] == publication['administrative_source_files']['numerical_critical_driver.py']
            and authority['peer_program']['sha256'] == publication['administrative_source_files']['numerical_independent_peer.py'],
            'root driver and independent peer are the exact frozen administrative programs')
    require(set(spec['science']) == set(config['scientific_sources']) == set(SCIENCE), 'exact five scientific code files')
    for name, sha in SCIENCE.items():
        require(config['scientific_sources'][name]['sha256'] == spec['science'][name]['sha256'] == sha,
                'unchanged mathematical source SHA')
        read_bytes(config['scientific_sources'][name]['path'], sha, code=True)
    require(spec['controls']['traced_guard']['sha256'] == TRACER
            and spec['controls']['boundary_library']['sha256'] == BOUNDARY,
            'unchanged native tracer and TSYNC boundary')
    prereq, reuse = prerequisites(config)
    known = read(config['known_jobs_registry'])
    terminal = {'COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL', 'PREEMPTED', 'BOOT_FAIL'}
    expected_known = [dict(job_id=row['job_id'], job_name=row['job_name'], terminal=row.get('state') in terminal) for row in known['jobs']]
    require(config['known_prior_jobs'] == expected_known and expected_known
            and all(row['terminal'] for row in expected_known)
            and any(row['job_id'] == prereq['accepted_boundary']['job_id']
                    and row['job_name'] == prereq['accepted_boundary']['scope_id'] for row in expected_known),
            'entire pinned known PriceFM registry and accepted parent terminal')
    require(ready['inventory']['job_id'] == ready['job_id']
            and all(ready['inventory'][k] == reuse['inventory'][k] for k in ('libc', 'python', 'python_version'))
            and spec['known_prior_jobs'] == config['known_prior_jobs'], 'qualified current runtime and complete known registry')
    packet_and_native_journals(config, root, packet, spec, ready, ready_guard_path, reuse)
    return config, scope, root, out, packet, spec, ready, authority, reuse


def physical_facts(config, spec, ready):
    snap = ready['physical_snapshot_value']; embedded(snap, ready['physical_snapshot'])
    now = time.time(); job = ready['job_id']; uid = snap['uid']; affinity = ready['affinity']; cpu = affinity[0]
    require(snap.get('status') == 'OBSERVED_NUMERICAL_CORE_METADATA_NOT_ADMISSION'
            and snap['job_id'] == job and snap['node'] == ready['node']
            and type(uid) is int and snap['affinity'] == affinity
            and now - 90 < snap['observed_epoch'] <= now and snap.get('physical_numerical_admission') is False,
            'fresh actual nonadmitting physical snapshot')
    filesystem = snap['filesystem']
    stat_fields = ('device', 'fragment_bytes', 'available_blocks', 'available_bytes', 'free_bytes', 'minimum_available_bytes')
    require(filesystem.get('status') == 'OBSERVED_NUMERICAL_FILESYSTEM_STAT_NOT_USER_QUOTA'
            and filesystem.get('path') == spec['remote_root']
            and all(type(filesystem.get(k)) is int and filesystem[k] >= 0 for k in stat_fields)
            and filesystem['fragment_bytes'] > 0
            and filesystem['available_bytes'] == filesystem['available_blocks'] * filesystem['fragment_bytes']
            and filesystem['free_bytes'] >= filesystem['available_bytes'] >= filesystem['minimum_available_bytes'] == 85899345920
            and filesystem.get('quota_status') == 'UNKNOWN'
            and type(filesystem.get('observed_epoch')) in (int, float) and math.isfinite(filesystem['observed_epoch'])
            and now - 150 <= filesystem['observed_epoch'] <= now,
            'fresh typed actual-root statvfs80GiB available floor; user quota explicitly UNKNOWN')
    topo = snap['topology']; siblings = snap['online_thread_siblings']; cpuset = snap['job_cpuset']
    online = kernel_cpu_list(snap['online_cpu_list_raw'])
    require(topo['cpu'] == cpu and cpu in topo['thread_siblings'] and cpu in siblings
            and all(type(value) is int and value >= 0 for value in topo['thread_siblings'])
            and siblings == sorted(set(topo['thread_siblings']) & online)
            and cpuset['version'] in (1, 2) and cpuset['effective_cpus'] == siblings
            and Path(cpuset['job_cgroup_path']).name == 'job_' + job
            and Path(cpuset['job_filesystem_path']).name == 'job_' + job
            and Path(cpuset['effective_file']).parent == Path(cpuset['job_filesystem_path'])
            and Path(cpuset['effective_file']).name in ('cpuset.cpus.effective', 'cpuset.effective_cpus', 'cpuset.cpus'),
            'observed job ancestor reserves exactly all online siblings of one physical core')
    policy = snap['Slurm_core_policy']; params = {token.upper() for token in policy.get('SelectTypeParameters', '').split(',')}
    require(policy.get('SelectType') == 'select/cons_tres'
            and (bool(params & {'CR_CORE', 'CR_CORE_MEMORY'})
                 or (bool(params & {'CR_CPU', 'CR_CPU_MEMORY'}) and topo['thread_siblings'] == affinity))
            and 'task/cgroup' in policy.get('TaskPlugin', '').split(',')
            and policy.get('ProctrackType') == 'proctrack/cgroup'
            and policy.get('PartitionOverSubscribe') in ('NO', 'EXCLUSIVE'),
            'actual CR_Core reservation, task/proctrack cgroups and no oversubscription')
    scheduler = snap['scheduler']; identity = ready['worker_identity']
    require(identity == snap['supervisor'] and identity['uid'] == uid and identity['affinity'] == affinity
            and identity['pid'] > 0 and identity['start_ticks'] > 0 and identity['boot_id']
            and scheduler['job_id'] == job and scheduler['node'] == ready['node'] and scheduler['uid'] == uid
            and scheduler['cpus'] == scheduler['tasks'] == scheduler['nodes'] == 1
            and scheduler['memory_MiB'] == 8192 and scheduler['requeue'] is False
            and 0 < scheduler['cgroup_memory_limit_bytes'] <= 8192 * 1024**2
            and 0 < scheduler['wall_seconds'] <= 1200 and scheduler['end_epoch'] > now + 300,
            'exact own live worker allocation and whole-stage resource window')
    for path in scheduler['cgroups']:
        parts = Path(path).parts
        require([p for p in parts if p.startswith('job_')] == ['job_' + job]
                and [p for p in parts if p.startswith('uid_')] in ([], ['uid_' + str(uid)]),
                'exact current job/UID cgroup and no foreign job')
    native = snap['native_observations_value']; embedded(native, snap['native_observations'])
    require(native.get('status') == 'ACTUAL_OWN_NATIVE_STARTUP_OBSERVATIONS_NOT_ADMISSION'
            and native.get('job_id') == job and native.get('node') == ready['node']
            and native.get('uid') == uid and native.get('own_startup_helpers_reaped') is True,
            'actual raw native scheduler observations with drained own helper tree')
    known = config['known_prior_jobs']; names = sorted(row['job_name'] for row in known)
    require(known and len(names) == len(set(names)) and all(row.get('terminal') is True for row in known),
            'complete exact known PriceFM registry must already be terminal')
    commands = [('/usr/bin/scontrol', 'show', 'config'),
                ('/usr/bin/scontrol', 'show', 'partition', '-o', '128x24'),
                ('/usr/bin/squeue', '--noheader', '--user', 'jaguir26', '--name', ','.join(names), '--format', '%i|%128j|%T'),
                ('/usr/bin/scontrol', 'show', 'job', '-o', job)]
    records = {tuple(row['argv']): row for row in native['records']}
    require(len(records) == len(native['records']) == 4 and set(records) == set(commands), 'closed exact four native observations')
    for row in records.values():
        child = row['identity']
        require(child['uid'] == uid and child['pid'] > 0 and child['pid'] != identity['pid']
                and child['start_ticks'] >= identity['start_ticks'] and row['exact_child_reaped'] is True
                and row['returncode'] == 0 and not row['stderr'], 'fresh own exact native child identity and wait/reap')
    config_raw = records[commands[0]]['stdout']; partition_raw = records[commands[1]]['stdout']
    parsed = dict(re.findall(r'^\s*(SelectType(?:Parameters)?|TaskPlugin|ProctrackType)\s*=\s*(\S+)', config_raw, re.M))
    partition = dict(re.findall(r'(\S+?)=(\S*)', partition_raw)); parsed['PartitionOverSubscribe'] = partition.get('OverSubscribe')
    require(parsed == policy and config_raw == snap['raw_scheduler_configuration']
            and partition.get('PartitionName') == '128x24' and records[commands[2]]['stdout'].strip() == '',
            'derive core policy and known-job drain from actual raw observations')
    job_fields = dict(re.findall(r'(\S+?)=(\S*)', records[commands[3]]['stdout']))
    require(job_fields.get('JobId') == job and job_fields.get('JobState') == 'RUNNING'
            and job_fields.get('NumCPUs') == job_fields.get('NumTasks') == job_fields.get('NumNodes') == '1'
            and job_fields.get('NodeList') == ready['node'] and job_fields.get('Requeue') == '0'
            and job_fields.get('Partition') == job_fields.get('Account') == '128x24'
            and job_fields.get('QOS') == 'normal'
            and re.fullmatch(r'jaguir26\(' + str(uid) + r'\)', job_fields.get('UserId', '')) is not None,
            'derive actual job identity and reservation from raw current-job observation')
    memory_match = re.fullmatch(r'([0-9]+)([MG]?)', job_fields.get('MinMemoryNode') or job_fields.get('MinMemoryCPU', ''))
    require(memory_match is not None, 'exact Slurm memory units')
    memory = int(memory_match[1]) * (1024 if memory_match[2] == 'G' else 1)
    wall_match = re.fullmatch(r'(?:(\d+)-)?(\d+):(\d+):(\d+)', job_fields.get('TimeLimit', ''))
    require(wall_match is not None, 'exact bounded Slurm wall time')
    wall = int(wall_match[1] or 0) * 86400 + int(wall_match[2]) * 3600 + int(wall_match[3]) * 60 + int(wall_match[4])
    end = datetime.datetime.strptime(job_fields.get('EndTime', ''), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=datetime.timezone.utc).timestamp()
    require(memory == scheduler['memory_MiB'] == 8192 and wall == scheduler['wall_seconds']
            and end == scheduler['end_epoch'], 'raw current Slurm resource and end-time facts match scheduler witness')
    witnesses = snap['witnesses']
    for key, value in witnesses.items():
        require(key in ('allocation_witness', 'peer_ownership_witness', 'priority_drain_witness'), 'closed witness kind')
        embedded(value, snap['witness_pins'][key])
        require(value['job_id'] == job and value['node'] == ready['node'] and value['uid'] == uid
                and snap['observed_epoch'] - 30 <= value['observed_epoch'] <= snap['observed_epoch'], 'fresh exact witness identity')
    require(set(witnesses) == {'allocation_witness', 'peer_ownership_witness', 'priority_drain_witness'}, 'all three actual witnesses')
    a = witnesses['allocation_witness']; p = witnesses['peer_ownership_witness']; d = witnesses['priority_drain_witness']
    require(a['scheduler'] == scheduler and a['topology'] == topo and a['Slurm_core_policy'] == policy
            and a['job_cpuset'] == cpuset and a['online_thread_siblings'] == siblings
            and p['supervisor'] == identity and p['cgroups'] == scheduler['cgroups']
            and p['pending_owned_children'] == [] and p['all_declared_native_helpers_reaped'] is True
            and p['unrelated_projects_censused'] is False and d['known_prior_jobs'] == known
            and d['observed_queue_rows'] == [] and d['all_known_PriceFM_jobs_absent'] is True
            and d['pending_owned_children'] == [] and d['no_production_processes_signalled'] is True,
            'independently bound whole-core ownership, own helper drain and exact PriceFM priority drain')
    return snap


def source_phase(ctx):
    config, scope, root, out, packet, spec, ready, authority, reuse = ctx
    snap = physical_facts(config, spec, ready)
    request = local(out / 'STAGE_SOURCE_REVIEW_REQUEST.json')
    expected_bindings = list(spec['science'].values()) + [spec['sources']['numerical_stage_bootstrap.R']]
    require(request.get('status') == 'REQUEST_NOT_PEER_PASS'
            and request.get('required_status') == 'PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'
            and all(request.get(k) == v for k, v in dict(role=config['role'], job_id=ready['job_id'],
                node=ready['node'], scope_id=spec['scope_id'], execution_adapter_source=spec['sources']['numerical_stage_owner.py'],
                source_bindings=expected_bindings, source_publication=config['publication'], role_limits=config['role_limits'],
                scientific_suffixes_byte_identical_required=True).items()), 'exact current source review request')
    physical_request = local(out / 'PHYSICAL_CORE_REVIEW_REQUEST.json')
    expected_physical = dict(job_id=ready['job_id'], node=ready['node'], topology=snap['topology'],
                             actual_snapshot=ready['physical_snapshot'], **snap['witness_pins'])
    require(physical_request.get('status') == 'REQUEST_NOT_PEER_PASS'
            and physical_request.get('required_status') == 'PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN'
            and all(physical_request.get(k) == v for k, v in expected_physical.items()), 'exact physical witness review request')
    request.pop('required_status'); request['status'] = 'PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'
    request.update(actual_R_parse_not_preclaimed=True, conditional_current_parse_and_kernel_ACK_required=True)
    physical_request.pop('required_status'); physical_request['status'] = 'PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN'
    physical_request['all_peer_and_drain_witnesses_bound'] = True
    recommendation = dict(status='PASS_REVIEWED_CONDITIONAL_ROOT_NUMERICAL_FIELDS', role=config['role'], job_id=ready['job_id'],
        actual_snapshot=ready['physical_snapshot'], recommended_root_fields=dict(all_SMT_siblings_reserved_to_this_job=True,
            unreviewed_numerical_peer_intersections=[], priority_drain_complete=True), no_root_grant_issued=True,
        actual_R_parse_not_preclaimed=True, raw_native_observations=snap['native_observations'])
    write_new(out / 'STAGE_SOURCE_REVIEW.json', request)
    write_new(out / 'PHYSICAL_CORE_REVIEW.json', physical_request)
    write_new(out / 'ROOT_FIELDS_RECOMMENDATION.json', recommendation)


def owner_phase(ctx, driver_authority_path):
    config, scope, root, out, packet, spec, ready, authority, reuse = ctx
    snap = physical_facts(config, spec, ready); remote = packet['remote_root'] + '/release/'
    def remote_pin(name):
        return dict(path=remote + name, sha256=pin(out / name)['sha256'])
    ospec = local(out / 'OWNER_SPEC.json'); auth = local(out / 'OWNER_AUTHORITY.json')
    grant = local(out / 'STAGE_GRANT.json'); bootstrap = local(out / 'BOOTSTRAP_SPEC.json')
    source = local(out / 'STAGE_SOURCE_REVIEW.json'); proof = local(out / 'PHYSICAL_CORE_PROOF.json')
    physical_review = local(out / 'PHYSICAL_CORE_REVIEW.json'); now = time.time()
    require(source.get('status') == 'PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'
            and source.get('conditional_current_parse_and_kernel_ACK_required') is True
            and grant.get('source_review') == remote_pin('STAGE_SOURCE_REVIEW.json')
            and grant.get('conditional_parse_and_current_kernel_ACK_required') is True
            and grant.get('driver_root_authority') == pin(driver_authority_path)
            and auth.get('driver_root_authority') == pin(driver_authority_path), 'closed conditional root grants after actual source/physical peer')
    for k, v in dict(role=config['role'], job_id=ready['job_id'], node=ready['node'], scope_id=spec['scope_id'],
        affinity=ready['affinity'], role_limits=config['role_limits'], nonce=spec['nonce'], source_commit=spec['source_commit'],
        scientific_sources=spec['science'], target_delivery=spec['target_delivery'], physical_snapshot=ready['physical_snapshot'],
        physical_core_proof=remote_pin('PHYSICAL_CORE_PROOF.json'), physical_core_review=remote_pin('PHYSICAL_CORE_REVIEW.json'),
        prerequisite_bundle=spec['controls']['prerequisite_bundle'], known_prior_jobs=spec['known_prior_jobs']).items():
        require(ospec.get(k) == v, 'exact owner field: ' + k)
    require(ospec.get('schema') == 'r182_frozen525_numerical_owner_spec_v1'
            and ospec.get('R_native') == reuse['native_R'] and ospec.get('accepted_boundary') == reuse['accepted_boundary']
            and ospec.get('boundary_qualification') == reuse['boundary_qualification']
            and ospec.get('traced_guard') == spec['controls']['traced_guard']
            and ospec.get('boundary_library') == spec['controls']['boundary_library']
            and ospec.get('bootstrap') == spec['sources']['numerical_stage_bootstrap.R']
            and ospec.get('bootstrap_spec') == remote_pin('BOOTSTRAP_SPEC.json')
            and ospec.get('stage_grant') == remote_pin('STAGE_GRANT.json'), 'exact current owner, native machine and bootstrap')
    owner_names = ('numerical_stage_owner.py', 'numerical_stage_contract.py', 'numerical_stage_bootstrap.R',
        'startup_helper.py', 'scientific_allocation.py', 'profile_admission.py', 'environment.py',
        'numerical_physical_admission.py', 'scientific_namespace_contract.py')
    owner_sources = {name: spec['sources'][name] for name in owner_names}
    require(auth.get('status') == 'ROOT_ADMITTED_R182_FROZEN525_NUMERICAL_STAGE'
            and auth.get('spec') == remote_pin('OWNER_SPEC.json') and auth.get('sources') == owner_sources
            and auth.get('role') == config['role'] and all(exact_int(auth.get(k), v) for k, v in dict(
                max_calls=1, memory_MiB=8192, whole_CPU_seconds=600, whole_wall_seconds=1200,
                owner_CPU_seconds=450, owner_wall_seconds=300, R_child_CPU_seconds=300).items())
            and auth['issued_epoch'] <= now < now + 300 < auth['expires_epoch'] <= scope['expires_epoch']
            and auth['expires_epoch'] - auth['issued_epoch'] <= 7200, 'fresh bounded owner450/child300/whole600 authority')
    grant_status = 'ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY' if config['role'] == 'TOY_PARITY' else 'ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY'
    require(grant.get('status') == grant_status and grant.get('schema') == 'pricefm_hb_scientific_stage_grant_v1'
            and all(grant.get(k) == ospec[k] for k in ('role', 'job_id', 'node', 'scope_id', 'affinity'))
            and grant.get('expected_stock_body_sha256') == STOCK
            and all(exact_int(grant.get(k), v) for k, v in dict(maximum_CPU_seconds=300,
                memory_MiB=8192, cores=1, max_new_numerical=1, attempt_index=1, new_attempt_index=1).items())
            and grant.get('old_claims_reused') is False and grant.get('old_costs_refunded') is False
            and grant.get('authorizes_production_acceptance') is False and grant.get('authorizes_production_fits') is False
            and grant.get('stage_deadline_epoch') == scope['expires_epoch']
            and grant.get('source', {}).get('head') == spec['source_commit']
            and grant.get('scientific_boundary_qualification') == reuse['boundary_qualification'], 'strict fresh numerical role grant')
    limits = dict(maximum_optimizer_invocations=8, maximum_total_optimizer_iterations=30, maximum_n=128, maximum_p=32)
    if config['role'] == 'ZERO_UPDATE_BRIDGE':
        limits = dict(maximum_optimizer_invocations=0, maximum_total_optimizer_iterations=0, maximum_n=48576, maximum_p=417)
        require(grant.get('mode') == 'bridge' and grant.get('target_name') == TARGET and exact_int(grant.get('max_iter'), 0)
                and grant.get('manifest_sha256') == spec['execution_manifest']['sha256']
                and ospec.get('execution_manifest') == spec['execution_manifest'], 'exact zero-update bridge, no pilot')
    require(all(exact_int(grant.get(k), v) for k, v in limits.items())
            and grant.get('authorizes_toy_optimizer') is (config['role'] == 'TOY_PARITY'), 'exact role optimizer and dimension bounds')
    bindings = list(spec['science'].values()) + [spec['sources']['numerical_stage_bootstrap.R']]
    entry_name = 'application/tests/r179_hb_toy.R' if config['role'] == 'TOY_PARITY' else 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R'
    entry = spec['science'][entry_name]
    require(grant.get('source_bindings') == ospec.get('scientific_source_bindings') == bindings
            and grant.get('execution_adapter_source') == ospec.get('execution_adapter_source') == spec['sources']['numerical_stage_owner.py']
            and grant.get('entrypoint') == ospec.get('entrypoint') == entry
            and all(source.get(k) == grant[k] for k in ('role', 'job_id', 'node', 'scope_id', 'source_bindings', 'execution_adapter_source')),
            'owner, peer, root and immutable scientific code agree')
    base = packet['remote_root']; rhome = str(Path(reuse['native_R']['path']).parents[2]); library = rhome + '/library'
    require(ospec.get('remote_namespace') == base and ospec.get('science_root') == base + '/science'
            and ospec.get('output') == base + '/result/numerical' and ospec.get('resource_lock') == base + '/numerical.lock',
            'exact private output, immutable science and single numerical lock')
    args = [base + '/science', remote_pin('STAGE_GRANT.json')['path'], remote_pin('STAGE_GRANT.json')['sha256'], base + '/result/numerical/toy']
    if config['role'] == 'ZERO_UPDATE_BRIDGE':
        args = ['bridge', base + '/science', spec['execution_manifest']['path'], remote_pin('STAGE_GRANT.json')['path'],
                remote_pin('STAGE_GRANT.json')['sha256'], base + '/result/numerical/bridge']
    require(bootstrap.get('schema') == 'r182_hb_numerical_bootstrap_v1'
            and all(bootstrap.get(k) == ospec[k] for k in ('role', 'job_id', 'node', 'nonce'))
            and bootstrap.get('library') == library and bootstrap.get('scientific_entrypoint') == entry
            and bootstrap.get('boundary_library') == ospec['boundary_library']
            and bootstrap.get('fixedpoint_helper') == spec['science']['application/R/pricefm_r129_al_fixedpoint_certificate.R']
            and bootstrap.get('source_parse_files') == list(spec['science'].values())
            and bootstrap.get('entrypoint_args') == args and bootstrap.get('expected_stock_body_sha256') == STOCK,
            'conditional current five-file parse before frozen entrypoint, with exact job/nonce and no pilot')
    env = dict(PATH='/usr/bin:/bin', LANG='C', LC_ALL='C', TZ='UTC', HOME=base, TMPDIR=base + '/tmp',
        R_HOME=rhome, R_ARCH='', R_DOC_DIR=rhome + '/doc', R_INCLUDE_DIR=rhome + '/include', R_SHARE_DIR=rhome + '/share',
        R_LIBS_USER=library, R_LIBS_SITE=library, LD_LIBRARY_PATH=rhome + '/lib:' + str(Path(rhome).parent / 'lib'),
        SLURM_JOB_ID=ready['job_id'], SLURMD_NODENAME=ready['node'], SLURM_CPUS_PER_TASK='1',
        R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED='1' if config['role'] == 'TOY_PARITY' else '0',
        R154_PROJECT_ROOT_ADMITTED='0' if config['role'] == 'TOY_PARITY' else '1',
        R154_PROJECT_MODE='toy' if config['role'] == 'TOY_PARITY' else 'bridge',
        R154_PROJECT_ADMISSION_PATH=remote_pin('STAGE_GRANT.json')['path'], R154_PROJECT_ADMISSION_SHA256=remote_pin('STAGE_GRANT.json')['sha256'],
        R154_PROJECT_RUNTIME_PATH=grant['actual_R_runtime_binding']['path'], R154_PROJECT_RUNTIME_SHA256=grant['actual_R_runtime_binding']['sha256'])
    env.update({key: '1' for key in THREADS}); require(ospec['environment'] == env, 'exact closed single-thread R environment')
    runtime = local(out / 'ACTUAL_RUNTIME_BINDING.json')
    require(grant['actual_R_runtime_binding'] == remote_pin('ACTUAL_RUNTIME_BINDING.json')
            and runtime.get('actual_executable') == reuse['native_R']['path'] and runtime.get('actual_executable_sha256') == NATIVE_R
            and runtime.get('R_home') == rhome and runtime.get('package_path') == library + '/exdqlm'
            and runtime.get('accepted_boundary') == reuse['accepted_boundary']
            and runtime.get('Rscript') == rhome + '/bin/Rscript'
            and runtime.get('Rscript_sha256') == {row['path']: row['sha256'] for row in reuse['runtime_files']}[rhome + '/bin/Rscript'],
            'exact accepted runtime binding, no administrative runtime read')
    allowed = {row['resolved_file']['path']: row['resolved_file']['sha256'] for row in ready['inventory']['helpers'].values()}
    allowed[reuse['native_R']['path']] = NATIVE_R
    require(ospec.get('bootstrap_exec_allowlist') == allowed, 'exact accepted bootstrap helpers plus one native R; no broader exec authority')
    require(proof.get('status') == 'ROOT_ADMITTED_EXACT_SLURM_NUMERICAL_PHYSICAL_CORE'
            and physical_review.get('status') == 'PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN'
            and proof.get('all_SMT_siblings_reserved_to_this_job') is True
            and proof.get('unreviewed_numerical_peer_intersections') == [] and proof.get('priority_drain_complete') is True
            and proof.get('old_processes_signalled_or_peer_allowlist_broadened') is False
            and proof.get('uid') == snap['uid'] and proof.get('affinity') == ready['affinity']
            and proof.get('Slurm_core_policy') == snap['Slurm_core_policy']
            and physical_review.get('all_peer_and_drain_witnesses_bound') is True
            and proof['issued_epoch'] <= now < proof['expires_epoch'] <= snap['scheduler']['end_epoch'], 'current root/peer physical admission agreement')
    for key in ('job_id', 'node', 'topology', 'actual_snapshot', 'allocation_witness', 'peer_ownership_witness', 'priority_drain_witness'):
        expected = ready['physical_snapshot'] if key == 'actual_snapshot' else snap['witness_pins'][key] if key.endswith('_witness') else snap[key]
        require(proof.get(key) == physical_review.get(key) == expected, 'exact physical root/peer field: ' + key)
    global_contract = local(out / 'GLOBAL_CONTRACT.json')
    require(grant.get('global_contract') == remote_pin('GLOBAL_CONTRACT.json')
            and global_contract == dict(schema='r179_hb_scientific_job_contract_v1', job_id=ready['job_id'], node=ready['node'],
                resource_lock=base + '/numerical.lock', max_new_numerical=1, expires_epoch=scope['expires_epoch']), 'exact global one-new-numerical contract')
    review = dict(status='PASS_REVIEWED_R182_FROZEN525_NUMERICAL_OWNER_AND_SPEC', role=config['role'],
        spec=remote_pin('OWNER_SPEC.json'), authority=remote_pin('OWNER_AUTHORITY.json'), sources=owner_sources,
        current_R_parse_not_preclaimed=True, conditional_current_parse_and_kernel_ACK_required=True)
    write_new(out / 'OWNER_REVIEW.json', review)
    labels = dict(owner_spec='OWNER_SPEC.json', owner_authority='OWNER_AUTHORITY.json', owner_review='OWNER_REVIEW.json',
        stage_grant='STAGE_GRANT.json', stage_source_review='STAGE_SOURCE_REVIEW.json', global_contract='GLOBAL_CONTRACT.json',
        bootstrap_spec='BOOTSTRAP_SPEC.json', physical_core_proof='PHYSICAL_CORE_PROOF.json', physical_core_review='PHYSICAL_CORE_REVIEW.json')
    write_new(out / 'PEER_RELEASE.json', dict(status='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE',
        role=config['role'], job_id=ready['job_id'], node=ready['node'], ready_sha256=pin(root / 'READY.json')['sha256'],
        spec_sha256=packet['spec_sha256'], sources=spec['sources'], stage_pins={key: remote_pin(name) for key, name in labels.items()},
        current_R_parse_not_preclaimed=True, conditional_current_parse_and_kernel_ACK_required=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('source_physical', 'owner_release'), required=True)
    parser.add_argument('--config', required=True); parser.add_argument('--bundle', required=True)
    parser.add_argument('--ready-guard', required=True); parser.add_argument('--driver-authority', required=True)
    args = parser.parse_args(); signal.signal(signal.SIGXCPU, signal.SIG_DFL); signal.alarm(30)
    resource.setrlimit(resource.RLIMIT_CPU, (6, 8)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    before = time.process_time(); started = time.monotonic()
    ctx = context(args.config, args.bundle, args.ready_guard, args.driver_authority)
    if args.phase == 'source_physical':
        source_phase(ctx)
    else:
        owner_phase(ctx, args.driver_authority)
    write_new(Path(args.bundle) / (args.phase.upper() + '_PEER_EXECUTION.json'), dict(
        status='COMPLETED_ACTUAL_METADATA_PEER_PHASE_NOT_NUMERICAL_ACCEPTANCE', phase=args.phase,
        program=pin(str(Path(__file__).absolute()), code=True), read_set=list(READS.values()),
        SELF_CPU_seconds=time.process_time() - before, wall_seconds=time.monotonic() - started,
        R_executions=0, scientific_arrays_opened=False, network_queries=0, root_grants_issued=0,
        current_R_parse_not_preclaimed=True))


if __name__ == '__main__':
    main()
