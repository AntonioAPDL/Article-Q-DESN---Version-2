"""Separately authorized recovery of already COMPLETE H artifacts; no network/job API.

Run this standalone file with the ORIGINAL frozen package on PYTHONPATH.  New
modules are auxiliary sources, outside its explicit 26-file closure.  Each action
is one shot; a failed action or the archive/install gap requires manual diagnosis.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import time

D5 = 'r164-profile-feb3840ef66e59cda675336196e1a12d'
S5 = 'r164-profile-d36a80cdd89152e6ad4690168cfa21ed'
POLICY = 'r165_complete_typed_native_inventory_multiset_v1'
ENDPOINT = 1793344299.7823877
ROOT_SHA = '1eb6bb0cc80630dddf274c5b8863e9de610ac2405f5f376c2a7bbe318ee7b6ab'
D_TERMINAL_SHA = 'c2ef4d3be06945d171eaddedc60d45537d174377d8b0e70f10964c921cd2513a'
D_FAILURE_SHA = '99c2e6bad7ef179227436489db8a0a86efa13faaad67fcf3c0a9d4be3b8d7b05'
MAX_BYTES = 8589934592
VALIDATOR_CPU, VALIDATOR_WALL = 40, 180
ACTIONS = ('prepare', 'install', 'validation-plan', 'validate', 'draft-accounting', 'accept')


def require(value, message):
    if not value:
        raise ValueError(message)


def physical(path, *, missing=False):
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts, 'absolute physical owned path required')
    for part in (path, *path.parents):
        if not part.exists():
            require(missing, 'missing physical path')
            continue
        s = part.lstat()
        require(not stat.S_ISLNK(s.st_mode), 'symlink forbidden')
    if path.exists():
        require(path.stat().st_uid == os.getuid(), 'owned path required')
    return path


def digest(path):
    path = physical(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        s = os.fstat(f.fileno())
        require(stat.S_ISREG(s.st_mode) and s.st_nlink == 1, 'regular single-link file required')
        h = hashlib.sha256()
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
        end = os.fstat(f.fileno())
    require((s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns) ==
            (end.st_dev, end.st_ino, end.st_size, end.st_mtime_ns, end.st_ctime_ns) ==
            (path.stat().st_dev, path.stat().st_ino, path.stat().st_size,
             path.stat().st_mtime_ns, path.stat().st_ctime_ns), 'file changed while hashing')
    return h.hexdigest()


def pin(path):
    return dict(path=str(physical(path)), sha256=digest(path))


def pinned_bytes(value):
    require(type(value) is dict and set(value) == {'path', 'sha256'}, 'exact file pin required')
    path = physical(value['path'])
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        before = os.fstat(f.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
                and before.st_size <= 16 * 1024**2, 'bounded single-link JSON metadata required')
        raw = f.read(16 * 1024**2 + 1); after = os.fstat(f.fileno())
    fp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    require(fp(before) == fp(after) == fp(path.stat()) and len(raw) == before.st_size
            and hashlib.sha256(raw).hexdigest() == value['sha256'], 'pinned file changed while reading')
    return raw


def read(value):
    raw = pinned_bytes(value)
    def pairs(items):
        out = {}
        for key, item in items:
            require(key not in out, 'duplicate JSON key')
            out[key] = item
        return out
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))


def write_new(path, value):
    path = physical(path, missing=True)
    raw = (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    sync_dir(path.parent)
    return pin(path)


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def tree_manifest(root):
    root = physical(root)
    require(root.is_dir(), 'physical return directory required')
    members = {}; total = 0
    for path in sorted(root.rglob('*')):
        physical(path); s = path.lstat()
        require(s.st_uid == os.getuid(), 'foreign return member')
        require(stat.S_ISREG(s.st_mode) or stat.S_ISDIR(s.st_mode), 'regular tree only')
        if path.is_file():
            total += s.st_size
            require(total <= MAX_BYTES and len(members) < 5000, 'bounded return inventory required')
            members[str(path.relative_to(root))] = dict(bytes=s.st_size, sha256=digest(path),
                device=s.st_dev, inode=s.st_ino, mode=stat.S_IMODE(s.st_mode), mtime_ns=s.st_mtime_ns)
    s = root.stat()
    return dict(root=str(root), device=s.st_dev, inode=s.st_ino, files=members,
                file_count=len(members), total_bytes=total)


def same_tree(before, after):
    require(all(before[k] == after[k] for k in ('device', 'inode', 'files', 'file_count', 'total_bytes')),
            'rename must preserve every byte, inode and member')


def event(root, state, **values):
    paths = sorted(root.glob('event_*.json')); previous = None
    for index, path in enumerate(paths):
        require(path.name == 'event_%04d.json' % index, 'recovery journal gap')
        item = read(pin(path)); require(item['previous_sha256'] == previous, 'recovery journal changed')
        previous = digest(path)
    return write_new(root / ('event_%04d.json' % len(paths)),
                     dict(state=state, created_epoch=time.time(), previous_sha256=previous, **values))


def original_publication(spec, grant, c):
    require(spec['feature_publication'] == dict(
        path=spec['remote_root'] + '/metadata/feature_publication.json',
        sha256=grant['source_publication']['sha256'])
        and c.spec_read(spec, spec['feature_publication']) == read(grant['source_publication']),
        'original H publication must retain exact remote role, SHA and staged bytes')


def load_context(config_path, c, *, now=None):
    """All authority is externally authored; this function issues none."""
    now = time.time() if now is None else now
    config_pin = pin(config_path); cfg = read(config_pin)
    require(cfg['schema'] == 'r170_completed_artifact_recovery_config_v1', 'exact recovery config schema')
    scope = cfg['scope_id']; require(scope in (D5, S5), 'only H D5/S5 eligible')
    grant = read(cfg['root_scope'])
    require(cfg['root_scope']['sha256'] == ROOT_SHA and grant['expires_epoch'] == ENDPOINT
            and now < ENDPOINT and grant['eligible_scopes'] == [D5, S5], 'new finite recovery scope required')
    auth = read(cfg['authority'])
    require(auth['status'] == 'ROOT_AUTHORIZED_COMPLETED_ARTIFACT_RECOVERY'
            and auth['root_scope'] == cfg['root_scope'] and auth['scope_id'] == scope
            and auth['created_epoch'] <= now < auth['expires_epoch'] == ENDPOINT
            and auth['actions'] == list(ACTIONS)
            and auth['no_numerical_rerun'] is True and auth['old_fees_retained'] is True
            and auth['native_inventory_comparison_policy'] == POLICY,
            'explicit new root authority required; old controller grant is not reusable')
    require(auth['allocations'] == dict(transport_local_CPU=40, transport_remote_CPU=40,
            offline_receive_CPU=20, offline_receive_wall=300, validator_CPU=40, validator_wall=180,
            proof_tail_CPU=26, ordinary_metadata_CPU=4, ordinary_metadata_wall=20, proof_CPU=5, proof_wall=30),
            'separate fixed recovery reservations required')
    for name in ('terminal_claim', 'old_tip', 'old_caller_terminal', 'original_spec', 'recovery_root',
                 'source_review', 'publication', 'original_package'):
        require(cfg[name] == auth[name], 'authority/config identity differs: ' + name)
    source_review = read(cfg['source_review']); publication = read(cfg['publication'])
    sources = dict(artifact_recovery=pin(__file__))
    require(source_review['status'] == 'PASS_REVIEWED_COMPLETED_ARTIFACT_RECOVERY_SOURCE'
            and source_review['recovery_sources'] == auth['recovery_sources']
            and publication['status'] == 'VERIFIED_FEATURE_PUBLICATION'
            and publication['recovery_sources'] == auth['recovery_sources']
            and sources['artifact_recovery'] == auth['recovery_sources']['artifact_recovery'],
            'actual reviewed and published auxiliary source pins required')
    for value in auth['recovery_sources'].values():
        require(digest(value['path']) == value['sha256'], 'auxiliary source changed')
    c.owner()
    canonical = physical(c.CENTRAL / scope)
    require(canonical.is_dir(), 'existing canonical claim required; no new admission')
    require(cfg['original_spec'] == pin(canonical / 'controller_spec.json'), 'exact original canonical spec required')
    spec = read(cfg['original_spec']); c.validate_spec(spec, now=now, admit_new_work=False)
    require(spec['scope_id'] == scope and spec['controller_expires_epoch'] == ENDPOINT
            and spec['controller_sources'] == auth['controller_sources'] == c.controller_sources()
            and spec['worker_sources'] == auth['worker_sources'] == c.e.source_closure()
            and len(spec['controller_sources']) == 26 and len(spec['worker_sources']) == 22
            and source_review['controller_sources'] == publication['source_files'] == spec['controller_sources'],
            'original26/22/endpoint must remain exact')
    require(Path(c.__file__).resolve().parent == physical(cfg['original_package']) / 'pricefm_hb',
            'validator must import original pinned package, not new controller copy')
    for name, sha in spec['controller_sources'].items():
        require(digest(Path(c.__file__).parent / name) == sha, 'original module changed')
    claim = read(cfg['terminal_claim']); old = read(cfg['old_tip']); caller = read(cfg['old_caller_terminal'])
    expected_caller = Path(cfg['root_scope']['path']).parent.parent / 'caller_runtime' / 'runs' / scope / 'DRIVER_TERMINAL.json'
    require(Path(cfg['old_caller_terminal']['path']) == expected_caller, 'original H caller required')
    original_publication(spec, grant, c)
    require(claim['state'] == 'TERMINAL_OBSERVED' and claim['job_id'].isdigit()
            and caller['status'] == 'CLOSED_NO_RESUME' and caller['all_reserved_costs_retained'] is True,
            'real complete terminal claim and closed original caller required')
    require(Path(cfg['terminal_claim']['path']).parent == canonical
            and Path(cfg['old_tip']['path']).parent == canonical, 'canonical immutable history required')
    if scope == D5:
        require(cfg['terminal_claim']['sha256'] == D_TERMINAL_SHA and cfg['old_tip']['sha256'] == D_FAILURE_SHA
                and old['state'] == 'AMBIGUOUS_SPENT' and old['operation'] == 'retrieve_all_useful_raw_outputs'
                and 'truncated stream' in old['diagnostic'] and claim['job_id'] == '873499',
                'only genuine D5 truncated completed bulk return eligible')
    else:
        require(cfg['old_tip'] == cfg['terminal_claim'] and old['state'] == 'TERMINAL_OBSERVED',
                'S recovery begins before original collect; no fabricated failed transfer')
    accounting = read(claim['accounting'])
    reparsed = c.parse_accounting(accounting['sacct'], claim['job_id'], spec)
    require(all(accounting.get(k) == v for k, v in reparsed.items()) and accounting['complete'] is True
            and accounting['terminal'] is True and accounting['job_still_queued'] is False
            and accounting['squeue'] == '' and accounting['status'] == 'ACCEPTED_COMPLETE_JOB_ACCOUNTING',
            'original complete accounting must reparse exactly; primary charge once')
    ready = read(claim['attestation']); authority = read(claim['authority'])
    request = c.spec_read(spec, spec['request'])
    require(authority['scope_id'] == scope and authority['request_sha256'] == spec['request']['sha256']
            and authority['attestation_sha256'] == claim['attestation']['sha256']
            and authority['source_files'] == spec['worker_sources'], 'original job authority identity differs')
    c.ready_input_binding(spec, ready, now=ready['observed_epoch'])
    old_policy = read(grant['original_H_policy'])
    # Job-bound proofs were staged after the immutable release manifest. Resolve
    # this one role from the archived terminal claim, never a generic fallback.
    review_relative = 'metadata/job_bound/source_review.json'
    reviews = [x for x in claim['staged_files'] if x['relative'] == review_relative]
    require(len(reviews) == 1 and authority['review'] == dict(
        path=spec['remote_root'] + '/' + review_relative, sha256=reviews[0]['sha256']),
        'exact archived job-bound source review role required')
    job_review = read(dict(path=reviews[0]['local'], sha256=reviews[0]['sha256']))
    require(job_review['native_inventory_comparison_policy'] == POLICY
            and authority['policy'] == request['policy']
            and old_policy['native_inventory_comparison_policy'] == POLICY
            and old_policy['model_policy_expiry_epoch'] == spec['expires_epoch']
            and old_policy['controller_endpoint_epoch'] == ENDPOINT, 'original H scientific policy required')
    root = physical(cfg['recovery_root'], missing=True)
    require(root == physical(Path(cfg['root_scope']['path']).parent) / 'operations' / scope,
            'new exact recovery root required')
    return dict(cfg=cfg, config_pin=config_pin, auth=auth, canonical=canonical, spec=spec,
                claim=claim, accounting=accounting, root=root)


def check_chain(ctx, j):
    records = j.records(); cfg = ctx['cfg']
    terminal = Path(cfg['terminal_claim']['path']).name
    tip = Path(cfg['old_tip']['path']).name
    require(pin(j.root / terminal) == cfg['terminal_claim'] and pin(j.root / tip) == cfg['old_tip'],
            'old canonical history changed')
    index = int(tip[7:11]); require(index < len(records), 'old canonical tip absent')
    require(all(x['state'] == 'RECOVERY_PROVENANCE' and x['recovery_authority'] == cfg['authority']
                for x in records[index + 1:]), 'unrelated lifecycle action or acceptance intervened')
    if cfg['scope_id'] == S5:
        require(not any(x['state'] in ('COLLECTION_INTENT', 'AMBIGUOUS_SPENT') for x in records),
                'S original collection must never have begun')


def no_replace_rename(source, target):
    """Linux renameat2 NOREPLACE: never replace even an empty raced-in target."""
    import ctypes
    physical(source); physical(target, missing=True)
    libc = ctypes.CDLL(None, use_errno=True)
    require(hasattr(libc, 'renameat2'), 'atomic no-replace rename kernel API required')
    result = libc.renameat2(-100, os.fsencode(source), -100, os.fsencode(target), 1)
    if result:
        error = ctypes.get_errno(); raise OSError(error, os.strerror(error))
    sync_dir(Path(source).parent); sync_dir(Path(target).parent)


def operational_guard(value, expected, cpu, wall):
    proof = read(value)
    require(proof['returncode'] == proof['command_returncode'] == 0
            and proof['all_owned_descendants_reaped'] is True and proof['kernel_escape_filter'] is True
            and proof['independent_guardian'] is True and proof['CPU_limit'] == cpu
            and proof['aggregate_CPU_seconds'] < cpu and proof['complete_lifecycle_wall_seconds'] <= wall
            and json.loads(proof['stdout']) == expected, 'actual operational outer guardian must pass with exact receipt')


def install_tree(ctx, decoded):
    root, canonical = ctx['root'], ctx['canonical']; cfg = ctx['cfg']
    bindings = dict(spec=cfg['original_spec'], request=ctx['spec']['request'],
                    source_manifest=pin(canonical / 'release' / 'release_manifest.json'))
    require(decoded['schema'] == 'r165_artifact_spool_decode_receipt_v1'
            and decoded['status'] == 'PASS_OFFLINE_DECODE' and decoded['scope_id'] == cfg['scope_id']
            and decoded['job_id'] == ctx['claim']['job_id'] and decoded['all_frames_verified'] is True
            and decoded['canonical_install_performed'] is False and decoded['bindings'] == bindings,
            'actual full original receiver receipt required')
    spool = read(decoded['spool_receipt'])
    require(spool['status'] == 'WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM'
            and spool['scope_id'] == cfg['scope_id'] and spool['job_id'] == ctx['claim']['job_id']
            and spool['bindings'] == bindings and spool['wire'] == decoded['wire'], 'exact completed spool receipt required')
    operational_guard(ctx['operational_guards']['spool'], spool, 40, 120)
    operational_guard(ctx['operational_guards']['decode'], decoded, 20, 300)
    incoming = canonical / 'returned_raw'; staging = physical(decoded['target_root'])
    require(staging != incoming and not staging.is_relative_to(canonical)
            and staging.is_relative_to(root) and staging.name == 'decoded_raw', 'fresh owned recovery staging required')
    fresh = tree_manifest(staging)
    identity = decoded['target_identity']; received = decoded['original_receive_receipt']
    require(identity['device'] == fresh['device'] == canonical.stat().st_dev
            and identity['inode'] == fresh['inode'] and identity['uid'] == os.getuid()
            and received['files'] == fresh['file_count'] and received['bytes'] == fresh['total_bytes']
            and decoded['payload_bytes'] == fresh['total_bytes'],
            'same-filesystem decoded byte/inode manifest must match original receive totals')
    wire_manifest = decoded['wire_manifest']
    header = json.dumps(wire_manifest, sort_keys=True, separators=(',', ':')).encode()
    require(hashlib.sha256(header).hexdigest() == received['manifest_sha256']
            == decoded['wire_manifest_sha256'] and wire_manifest['kind'] == 'directory'
            and wire_manifest['schema'] == 'r164_exact_file_stream_v1', 'exact original received wire manifest required')
    expected = {x['name']: {k: x[k] for k in ('bytes', 'sha256', 'mode')} for x in wire_manifest['files']}
    observed = {name: {k: x[k] for k in ('bytes', 'sha256', 'mode')} for name, x in fresh['files'].items()}
    require(expected == observed and len(expected) == len(wire_manifest['files'])
            and wire_manifest['total_bytes'] == fresh['total_bytes'], 'every received raw file must retain original hash/mode')
    write_new(root / 'NEW_TREE_MANIFEST.json', fresh)
    if cfg['scope_id'] == D5:
        old = tree_manifest(incoming)
        require(old['file_count'] == 195 and any('.profile-part' in name for name in old['files']),
                'all195 old partial files including failed frame must be preserved')
        archive = canonical / 'returned_raw_recovery06_preserved'
        require(not archive.exists(), 'archive must be absent; no automatic resume')
        write_new(root / 'OLD_PARTIAL_MANIFEST.json', old)
        event(root, 'ARCHIVE_RENAME_INTENT', source=str(incoming), target=str(archive), manifest=pin(root / 'OLD_PARTIAL_MANIFEST.json'))
        no_replace_rename(incoming, archive)
        same_tree(old, tree_manifest(archive))
        event(root, 'ARCHIVE_RENAMED_CANONICAL_GAP', archive=str(archive))
    else:
        require(not incoming.exists(), 'S canonical return must be absent')
    event(root, 'INSTALL_RENAME_INTENT', source=str(staging), target=str(incoming))
    no_replace_rename(staging, incoming)
    same_tree(fresh, tree_manifest(incoming))
    event(root, 'CANONICAL_TREE_INSTALLED', tree=pin(root / 'NEW_TREE_MANIFEST.json'))


def validation_plan(ctx, c):
    canonical, cfg = ctx['canonical'], ctx['cfg']
    require(time.time() + VALIDATOR_WALL < ENDPOINT, 'complete original validator must fit original endpoint')
    require(not any((canonical / name).exists() for name in
                    ('validation_claim.json', 'return_validation.json', 'returned_raw_manifest.json')),
            'original validation is one-shot and create-only')
    raw = pinned_bytes(cfg['terminal_claim'])
    path = canonical / 'validation_claim.json'
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    sync_dir(canonical)
    require(digest(path) == cfg['terminal_claim']['sha256'], 'terminal claim byte copy differs')
    command = [sys.executable, '-B', '-m', 'pricefm_hb.profile_control',
        '--validate-return', str(canonical / 'returned_raw'),
        '--spec', str(canonical / 'controller_spec.json'), '--claim', str(path),
        '--receipt', str(canonical / 'return_validation.json')]
    return dict(status='PLAN_ONLY_NOT_EXECUTED', recovery_authority=cfg['authority'],
        config=ctx['config_pin'], command=command, original_package=cfg['original_package'],
        supervisor=pin(Path(c.__file__).with_name('profile_supervisor.py')),
        CPU=40, wall=180, output_cap=1048576, terminal_claim=cfg['terminal_claim'],
        validation_claim=pin(path), original_controller_sources=ctx['spec']['controller_sources'],
        instruction='Root executes original guardian directly, no smaller ancestor cap; no coordinator child launch.')


def validator(ctx, execution_pin):
    cfg, canonical = ctx['cfg'], ctx['canonical']
    execution = read(execution_pin)
    require(execution['status'] == 'EXECUTED_ORIGINAL_FULL_RAW_VALIDATOR'
            and execution['recovery_authority'] == cfg['authority']
            and execution['validation_plan'] == pin(ctx['root'] / 'VALIDATION_PLAN.json')
            and execution['CPU'] == 40 and execution['wall'] == 180
            and execution['new_recovery_fees_only'] is True,
            'actual separately funded original validator execution receipt required')
    proof = read(execution['guardian'])
    require(proof['command_returncode'] == proof['returncode'] == 0 and proof['all_owned_descendants_reaped'] is True
            and proof['kernel_escape_filter'] is True and proof['aggregate_CPU_seconds'] < 40
            and proof['CPU_limit'] == 40 and proof['independent_guardian'] is True
            and proof['complete_lifecycle_wall_seconds'] <= 180,
            'original full-validator owned40CPU/180wall guard failed')
    verified = read(pin(canonical / 'return_validation.json'))
    require(verified['status'] == 'PASS_FULL_RAW_RETURN_VALIDATION'
            and verified['scope_id'] == cfg['scope_id'] and verified['job_id'] == ctx['claim']['job_id']
            and verified['exact_whole_component_parity'] is True
            and verified['full_raw_manifest'] == pin(canonical / 'returned_raw_manifest.json'),
            'original validator did not pass at exact canonical paths')
    require(json.loads(proof['stdout']) == verified, 'guardian stdout must be the actual original validator result')
    manifest = read(verified['full_raw_manifest'])
    require(manifest['schema'] == 'r164_complete_return_manifest_v1'
            and manifest['scope_id'] == cfg['scope_id'] and manifest['job_id'] == ctx['claim']['job_id']
            and manifest['root'] == str(canonical / 'returned_raw'), 'canonical full manifest binding differs')
    return dict(validation=pin(canonical / 'return_validation.json'), execution=execution_pin)


def accepted_accounting(ctx, verified):
    claim, spec = ctx['claim'], ctx['spec']
    return dict(ctx['accounting'], source_files=spec['worker_sources'], all_raw_outputs_returned_and_verified=True,
        scope_id=spec['scope_id'], phase=spec['phase'], request_sha256=spec['request']['sha256'],
        original_accounting_sha256=claim['accounting']['sha256'],
        raw_validation_sha256=pin(ctx['canonical'] / 'return_validation.json')['sha256'],
        full_raw_manifest_sha256=verified['full_raw_manifest']['sha256'],
        component_pair_result_sha256=verified['component_pair_result']['sha256'])


def acceptance(ctx, c, review_pin, tail_pin):
    cfg, spec, claim, canonical = ctx['cfg'], ctx['spec'], ctx['claim'], ctx['canonical']
    verified = read(pin(canonical / 'return_validation.json'))
    if cfg['scope_id'] == D5:
        same_tree(read(pin(ctx['root'] / 'OLD_PARTIAL_MANIFEST.json')),
                  tree_manifest(canonical / 'returned_raw_recovery06_preserved'))
    draft_pin = pin(ctx['root'] / 'accepted_job_accounting.draft.json')
    accounting_pin = dict(path=str(canonical / 'accepted_job_accounting.json'), sha256=draft_pin['sha256'])
    require(read(draft_pin) == accepted_accounting(ctx, verified), 'standard postvalidation accounting differs')
    review = read(review_pin)
    expected = dict(recovery_authority=cfg['authority'], source_files=spec['controller_sources'],
        worker_sources=spec['worker_sources'], terminal_claim=cfg['terminal_claim'],
        original_authority=claim['authority'], original_accounting=claim['accounting'],
        validation=pin(canonical / 'return_validation.json'), full_raw_manifest=verified['full_raw_manifest'],
        accepted_accounting=draft_pin, native_inventory_comparison_policy=POLICY,
        validator_execution=read(pin(ctx['root'] / 'validate.done.json'))['execution'],
        recovery_sources=ctx['auth']['recovery_sources'], configuration=ctx['config_pin'],
        old_tip=cfg['old_tip'], old_caller_terminal=cfg['old_caller_terminal'],
        installation=pin(ctx['root'] / 'install.done.json'),
        operational_guards=read(pin(ctx['root'] / 'install.done.json'))['operational_guards'],
        action_guards={prior: read(pin(ctx['root'] / (following + '.previous_guard.json')))
                       for prior, following in zip(ACTIONS[:-1], ACTIONS[1:])})
    require(review['status'] == 'PASS_REVIEWED_COMPLETE_RECOVERED_ARTIFACTS_AND_ACCOUNTING'
            and all(review.get(k) == v for k, v in expected.items()), 'actual independent full-artifact review required')
    tail = read(tail_pin); remote_path = spec['remote_root'] + '/accepted_job_accounting.json'
    require(tail['status'] == 'PASS_RECOVERY_POSTVALIDATION_ACCOUNTING_PUBLICATION'
            and tail['recovery_authority'] == cfg['authority'] and tail['scope_id'] == spec['scope_id']
            and tail['job_id'] == claim['job_id'] and tail['local_accounting'] == draft_pin
            and tail['remote_accounting'] == dict(path=remote_path, sha256=accounting_pin['sha256'])
            and tail['operations'] == ['accepted_accounting_path_must_be_absent',
                'publish_postvalidation_accepted_accounting', 'verify_published_accepted_accounting']
            and tail['all_operations_passed'] is True and tail['new_recovery_fees_only'] is True
            and tail['independent_review'] == review_pin,
            'actual separately funded three-operation remote publication required')
    require(len(tail['operation_receipts']) == 3, 'all three actual operation receipts required')
    operation_results = [read(value) for value in tail['operation_receipts']]
    require(all(x['returncode'] == 0 and x['all_owned_descendants_reaped'] is True
                and x['kernel_escape_filter'] is True for x in operation_results)
            and operation_results[-1]['stdout'].split()[0] == accounting_pin['sha256'],
            'actual bounded successful three-operation receipts and exact SHA readback required')
    total = sum(item['bytes'] for item in read(verified['full_raw_manifest'])['members'].values())
    return dict(status='ACCEPTED_COMPLETE_PAIRED_COMPONENT_QUALIFICATION' if spec['phase'] == 'QUALIFICATION_PAIR'
        else 'ACCEPTED_COMPLETE_PAIRED_COMPONENT_MEASUREMENT', scope_id=spec['scope_id'], source_files=spec['worker_sources'],
        whole_accounting_accepted=True, all_canonical_array_bytes_equal=True, request=spec['request'],
        parity_runtime=read(claim['attestation'])['runtime'],
        whole_accounting=dict(path=remote_path, sha256=accounting_pin['sha256']),
        component_pair_result=dict(path=spec['output_root'] + '/profile_result.json',
            sha256=verified['component_pair_result']['sha256']), local_whole_accounting=accounting_pin,
        original_slurm_accounting=claim['accounting'], local_component_pair_result=verified['component_pair_result'],
        full_raw_manifest=verified['full_raw_manifest'], raw_return=str(canonical / 'returned_raw'),
        total_return_bytes=total, screening_admitted=False, prices_revised=False)


def run(config_path, action, *, decode_receipt=None, spool_guard=None, decode_guard=None,
        validator_execution=None, previous_guard=None, review=None, tail=None):
    from pricefm_hb import profile_control as c
    require(action in ACTIONS, 'fixed recovery action required')
    ctx = load_context(config_path, c); root = ctx['root']; cfg = ctx['cfg']
    j = c.Journal(cfg['scope_id'])
    try:
        check_chain(ctx, j)
        if action == 'prepare':
            root.parent.mkdir(exist_ok=True); root.mkdir()
            write_new(root / 'CONFIG_PIN.json', ctx['config_pin'])
            result = dict(status='RECOVERY_PREPARED_NO_ACCEPTANCE', terminal_claim=cfg['terminal_claim'])
        else:
            require(read(pin(root / 'CONFIG_PIN.json')) == ctx['config_pin'], 'same immutable recovery configuration required')
            preceding = ACTIONS[ACTIONS.index(action) - 1]
            require((root / (preceding + '.done.json')).is_file(), 'prior one-shot action must succeed')
            require(previous_guard, 'actual previous-action successful outer guardian receipt required')
            proof = read(previous_guard)
            require(proof['returncode'] == proof['command_returncode'] == 0
                    and proof['all_owned_descendants_reaped'] is True and proof['kernel_escape_filter'] is True
                    and proof['independent_guardian'] is True
                    and json.loads(proof['stdout']) == read(pin(root / (preceding + '.done.json'))),
                    'previous action must have completed its actual outer guard successfully')
            write_new(root / (action + '.previous_guard.json'), previous_guard)
        require(not (root / (action + '.intent.json')).exists(), 'action already attempted; no retry or clock reset')
        event(root, 'ACTION_INTENT', action=action, recovery_authority=cfg['authority'])
        write_new(root / (action + '.intent.json'), dict(action=action, authority=cfg['authority']))
        if action == 'install':
            require(decode_receipt and spool_guard and decode_guard, 'actual decode receipt and both outer guardian pins required')
            ctx['operational_guards'] = dict(spool=spool_guard, decode=decode_guard)
            install_tree(ctx, read(decode_receipt)); result = dict(status='RECOVERED_TREE_INSTALLED_PENDING_VALIDATION',
                decode_receipt=decode_receipt, new_tree_manifest=pin(root / 'NEW_TREE_MANIFEST.json'),
                operational_guards=ctx['operational_guards'],
                old_partial_manifest=pin(root / 'OLD_PARTIAL_MANIFEST.json') if cfg['scope_id'] == D5 else None,
                preserved_archive=str(ctx['canonical'] / 'returned_raw_recovery06_preserved') if cfg['scope_id'] == D5 else None)
        elif action == 'validation-plan':
            result = validation_plan(ctx, c)
            write_new(root / 'VALIDATION_PLAN.json', result)
        elif action == 'validate':
            require(validator_execution, 'actual validator execution pin required')
            result = validator(ctx, validator_execution)
        elif action == 'draft-accounting':
            require(pin(ctx['canonical'] / 'return_validation.json') == read(pin(root / 'validate.done.json'))['validation'],
                    'current validation must equal actual guarded validated pin')
            verified = read(pin(ctx['canonical'] / 'return_validation.json'))
            result = write_new(root / 'accepted_job_accounting.draft.json', accepted_accounting(ctx, verified))
        elif action == 'accept':
            require(review and tail, 'actual independent review and remote tail pins required')
            result = acceptance(ctx, c, review, tail)
            write_new(ctx['canonical'] / 'accepted_job_accounting.json', read(pin(root / 'accepted_job_accounting.draft.json')))
            accepted_pin = write_new(ctx['canonical'] / 'accepted.json', result)
            j.put('RECOVERY_PROVENANCE', recovery_authority=cfg['authority'], independent_review=review,
                  remote_tail=tail, recovery_journal_root=str(root), original_failure=cfg['old_tip'])
            j.put('ACCEPTED', job_id=ctx['claim']['job_id'], acceptance=accepted_pin,
                  canonical_charged_CPU_seconds=ctx['accounting']['canonical_primary_CPU_seconds'], reservation_retained=True)
        event(root, 'ACTION_COMPLETE', action=action)
        write_new(root / (action + '.done.json'), result)
        return result
    finally:
        j.close()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True); p.add_argument('--action', required=True, choices=ACTIONS)
    p.add_argument('--decode-receipt'); p.add_argument('--validator-execution'); p.add_argument('--previous-guard')
    p.add_argument('--spool-guard'); p.add_argument('--decode-guard')
    p.add_argument('--review'); p.add_argument('--tail')
    args = p.parse_args(argv)
    print(json.dumps(run(args.config, args.action,
        decode_receipt=pin(args.decode_receipt) if args.decode_receipt else None,
        spool_guard=pin(args.spool_guard) if args.spool_guard else None,
        decode_guard=pin(args.decode_guard) if args.decode_guard else None,
        validator_execution=pin(args.validator_execution) if args.validator_execution else None,
        previous_guard=pin(args.previous_guard) if args.previous_guard else None,
        review=pin(args.review) if args.review else None, tail=pin(args.tail) if args.tail else None), sort_keys=True))


if __name__ == '__main__':
    main()
