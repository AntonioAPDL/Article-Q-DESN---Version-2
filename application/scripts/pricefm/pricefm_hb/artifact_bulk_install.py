"""Typed one-shot strong bulk install bridge; original recovery/26 stay frozen.

Standalone with the original controller package on PYTHONPATH. No subprocess,
SSH, numerical evaluation or acceptance API. Source tests use temporary trees.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import stat
import time

ROOT_SHA = '5ac75361eafe89aa7b6e933ca9546d0dbecc49c732866ccfbd14501736fe06e8'
RECOVERY_SHA = '778dcea741378b1f49163bff2ac6e75fddccb9009b4ee4b2e2303586da70f7e5'
ENDPOINT = 1793344299.7823877
SCOPE = 'r164-profile-feb3840ef66e59cda675336196e1a12d'
PROTOCOL = 'r173_original_memory_receive_strong_durable_bulk_materialization_v1'


def require(value, message):
    if not value:
        raise ValueError(message)


def frozen_recovery(value):
    path = Path(value['path'])
    require(value['sha256'] == RECOVERY_SHA and path.is_absolute()
            and not any(p.is_symlink() for p in (path, *path.parents)),
            'exact frozen recovery source required')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as f:
        before = os.fstat(f.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and before.st_size <= 16 * 1024**2, 'bounded owned frozen source required')
        raw = f.read(16 * 1024**2 + 1); after = os.fstat(f.fileno())
    fp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    require(fp(before) == fp(after) == fp(path.stat()) and len(raw) == before.st_size
            and hashlib.sha256(raw).hexdigest() == RECOVERY_SHA, 'exact frozen recovery bytes changed')
    spec = importlib.util.spec_from_file_location('_pricefm_r170_frozen_recovery', path)
    module = importlib.util.module_from_spec(spec)
    # Execute exactly the held-FD hash-verified bytes, never reread by a loader.
    exec(compile(raw, str(path), 'exec'), module.__dict__)
    require(module.pin(path) == value, 'frozen recovery changed during import')
    return module


def guard(r, value, expected, cpu, wall):
    r.operational_guard(value, expected, cpu, wall)


def source_map(r, values):
    require(type(values) is dict and {'artifact_bulk_materialize', 'artifact_bulk_install'} <= set(values),
            'both exact new source roles required')
    for value in values.values():
        r.pinned_bytes(value)


def load(config_path, r, c, *, now=None):
    now = time.time() if now is None else now
    cfg_pin = r.pin(config_path); cfg = r.read(cfg_pin)
    require(cfg['schema'] == 'r173_bulk_install_config_v1', 'exact typed bridge configuration required')
    root = r.read(cfg['root_scope'])
    require(cfg['root_scope']['sha256'] == ROOT_SHA and root['expires_epoch'] == ENDPOINT
            and now < ENDPOINT and root['eligible_scope'] == SCOPE
            and root['no_weaker_raw_durability_protocol'] is True, 'fresh strong-only finite root scope required')
    require(cfg['old_configuration'] == root['old_configuration']
            and cfg['recovery_source']['sha256'] == RECOVERY_SHA, 'old configuration/source immutable')
    ctx = r.load_context(cfg['old_configuration']['path'], c, now=now)
    require(ctx['config_pin'] == cfg['old_configuration'] and ctx['cfg']['scope_id'] == SCOPE,
            'exact existing D5 recovery context required')
    authority = r.read(cfg['authority'])
    require(authority['schema'] == 'r173_bulk_operation_authority_v1'
            and authority['status'] == 'ROOT_AUTHORIZED_STRONG_BULK_ARTIFACT_RECOVERY'
            and authority['root_scope'] == cfg['root_scope'] and authority['scope_id'] == SCOPE
            and authority['created_epoch'] <= now < authority['expires_epoch'] == ENDPOINT
            and authority['protocol'] == PROTOCOL and authority['strong_raw_durability'] is True
            and authority['no_guard_or_cap_changes'] is True
            and authority['one_real_attempt_only'] is True and authority['all_prior_fees_retained'] is True
            and authority['S_withheld'] is True
            and authority['cpu_seconds'] == 20 and authority['wall_seconds'] == 300
            and authority['install_CPU'] == 16 and authority['install_wall'] == 120
            and authority['original_validator_CPU'] == 40 and authority['original_validator_wall'] == 180,
            'explicit new strong bulk authority and unchanged caps required')
    for name in ('old_configuration', 'recovery_source', 'source_review', 'publication',
                 'old_prepare_guard'):
        require(authority[name] == cfg[name], 'new authority/config identity differs: ' + name)
    require(authority['synthetic_qualification'] == cfg['qualification'], 'same actual qualification required')
    require(authority['stable_anchor'] == str(Path(cfg['root_scope']['path']).parent.parent.parent),
            'this reviewed task uses the explicit T stable anchor')
    require(authority['source_receipt'] == cfg['spool_receipt'] and authority['source_role'] == 'REAL_COMPLETED_SPOOL'
            and authority['job_id'] == ctx['claim']['job_id'] and authority['wire_limit_bytes'] == 32600121
            and authority['memory_budget_bytes'] == 134217728, 'exact real spool role and bounded memory envelope required')
    require(authority['controller_sources'] == ctx['spec']['controller_sources']
            and authority['old_recovery_sources'] == ctx['auth']['recovery_sources'],
            'original26 and original four recovery sources must stay unchanged')
    source_map(r, authority['new_sources'])
    require(authority['new_sources']['artifact_bulk_install'] == r.pin(__file__), 'exact new bridge source required')
    review = r.read(cfg['source_review']); publication = r.read(cfg['publication'])
    require(review['status'] == 'PASS_REVIEWED_DURABLE_BULK_SOURCES'
            and review['bulk_sources'] == authority['new_sources']
            and review['old_recovery_sources'] == ctx['auth']['recovery_sources']
            and review['controller_sources'] == ctx['spec']['controller_sources']
            and publication['status'] == 'VERIFIED_FEATURE_PUBLICATION'
            and publication['bulk_sources'] == authority['new_sources']
            and publication['recovery_sources'] == ctx['auth']['recovery_sources']
            and publication['source_files'] == ctx['spec']['controller_sources']
            and publication['all_37_fetched_source_bytes_verified'] is True,
            'actual new exact source review/publication required')
    require(cfg['spool_guard'] == root['old_spool_guard'], 'completed original spool guardian identity required')
    spool = r.read(cfg['spool_receipt'])
    guard(r, cfg['spool_guard'], spool, 40, 120)
    require(spool['status'] == 'WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM'
            and spool['scope_id'] == SCOPE and spool['job_id'] == ctx['claim']['job_id'],
            'real completed original exact-job spool required')
    bulk_task = r.read(cfg['bulk_config'])
    require(bulk_task['schema'] == 'r173_bulk_materialize_task_v1'
            and bulk_task['authority'] == cfg['authority'], 'exact actual bulk task required')
    for key in ('source_role', 'scope_id', 'job_id', 'bindings', 'memory_root',
                'target_root', 'stable_anchor'):
        require(bulk_task[key] == authority[key], 'actual task must match direct authority field: ' + key)
    require(bulk_task['spool_receipt'] == authority['source_receipt'], 'actual spool source role must match authority')
    prepare = r.read(r.pin(ctx['root'] / 'prepare.done.json'))
    guard(r, cfg['old_prepare_guard'], prepare, 4, 20)
    failed = r.read(root['old_failed_decode_guard'])
    require(failed['returncode'] == 125 and failed['all_owned_descendants_reaped'] is True,
            'failed prior receive stays failed and fully reaped')
    return dict(cfg=cfg, config_pin=cfg_pin, root_scope=root, authority=authority, old=ctx, spool=spool)


def manifest_shape(value):
    names = [item['name'] for item in value['files']]
    require(names == sorted(set(names)), 'exact unique ordered wire members required')
    directories = set()
    for name in names:
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts, 'safe exact wire member required')
        directories.update(str(parent) for parent in path.parents if str(parent) != '.')
    return dict(files=len(names), payload_bytes=value['total_bytes'], directories=len(directories),
                max_depth=max((len(PurePosixPath(n).parts) for n in names), default=0),
                max_file_bytes=max((x['bytes'] for x in value['files']), default=0))


def qualification(r, bundle, actual_shape):
    cfg, auth = bundle['cfg'], bundle['authority']
    proof = r.read(cfg['qualification'])
    require(proof['status'] == 'PASS_QUALIFIED_STRONG_BULK_ALGORITHM'
            and proof['purpose'] == 'SYNTHETIC_AVAILABILITY_ONLY_NO_REAL_PAYLOAD'
            and proof['bulk_helper_source'] == auth['new_sources']['artifact_bulk_materialize']
            and proof['bulk_sources'] == auth['new_sources'] and proof['protocol'] == PROTOCOL
            and proof['source_review'] == cfg['source_review'] and proof['publication'] == cfg['publication'],
            'actual exact-source synthetic strong algorithm qualification required')
    for key, minimum in actual_shape.items():
        require(type(proof['fixture_shape'][key]) is int and proof['fixture_shape'][key] >= minimum,
                'synthetic qualification must cover actual shape: ' + key)
    result = r.read(proof['result'])
    guard(r, proof['guardian'], result, 20, 300)
    require(result['status'] == 'PASS_DURABLE_BULK_MATERIALIZATION'
            and result['source_role'] == 'SYNTHETIC_FIXTURE'
            and result['producer_source'] == auth['new_sources']['artifact_bulk_materialize']
            and manifest_shape(result['wire_manifest']) == {k: proof['fixture_shape'][k] for k in actual_shape},
            'synthetic qualification must use exact actual producer')


def verify_bulk(r, bundle, value):
    cfg, auth, ctx, spool = bundle['cfg'], bundle['authority'], bundle['old'], bundle['spool']
    require(value['schema'] == 'r173_bulk_materialization_result_v1'
            and value['status'] == 'PASS_DURABLE_BULK_MATERIALIZATION'
            and value['scope_id'] == SCOPE and value['job_id'] == ctx['claim']['job_id']
            and value['authority'] == cfg['authority'] and value['config'] == cfg['bulk_config']
            and value['producer_source'] == auth['new_sources']['artifact_bulk_materialize']
            and value['source_role'] == 'REAL_COMPLETED_SPOOL'
            and value['source_receipt'] == cfg['spool_receipt']
            and value['spool_receipt'] == cfg['spool_receipt'] and value['wire'] == spool['wire']
            and value['required_outer_guard'] == dict(cpu=20, wall=300)
            and value['no_canonical_install'] is True, 'genuine new typed bulk result required')
    require(value['memory_root'] == auth['memory_root'] and value['target_root'] == auth['target_root']
            and Path(cfg['bulk_receipt']['path']).parent == Path(auth['receipt_dir'])
            and Path(value['memory_decode']['path']).parent == Path(auth['receipt_dir'])
            and Path(value['durable_materialization']['path']).parent == Path(auth['receipt_dir']),
            'actual new phase targets and receipt roots must match reviewed authority')
    bindings = dict(spec=ctx['cfg']['original_spec'], request=ctx['spec']['request'],
        source_manifest=r.pin(ctx['canonical'] / 'release' / 'release_manifest.json'))
    require(value['bindings'] == spool['bindings'] == bindings, 'exact original spec/request/release roles required')
    guard(r, cfg['bulk_guard'], value, 20, 300)
    memory = r.read(value['memory_decode']); durable = r.read(value['durable_materialization'])
    require(memory == value['memory_decode_receipt'] and durable == value['durable_materialization_receipt']
            and memory['schema'] == 'r173_memory_decode_receipt_v1' and memory['status'] == 'PASS_MEMORY_DECODE'
            and durable['schema'] == 'r173_durable_materialization_receipt_v1'
            and durable['status'] == 'PASS_DURABLE_MATERIALIZATION' and durable['completed'] is True,
            'separate genuine complete memory parser and durable materialization receipts required')
    require(memory['authority'] == durable['authority'] == cfg['authority']
            and memory['producer_source'] == durable['producer_source'] == value['producer_source'],
            'both phase receipts must retain exact new authority/source')
    require(all(memory[k] == durable[k] == value[k] for k in
                ('config', 'scope_id', 'job_id', 'bindings', 'source_role', 'source_receipt', 'spool_receipt', 'wire')),
            'both typed phases must retain the complete actual task/source identity')
    require(memory['completed'] is True and memory['volatile'] is True
            and durable['all_writes_before_file_sync'] is True,
            'memory receipt must disclose volatility and durable phase must use reviewed bulk ordering')
    wire = value['wire_manifest']; raw = json.dumps(wire, sort_keys=True, separators=(',', ':')).encode()
    require(wire['schema'] == 'r164_exact_file_stream_v1' and wire['kind'] == 'directory'
            and hashlib.sha256(raw).hexdigest() == value['wire_manifest_sha256']
            == value['original_receive_receipt']['manifest_sha256'], 'original exact wire manifest binding required')
    require(memory['original_receive_receipt'] == value['original_receive_receipt']
            and value['original_receive_receipt']['files'] == len(wire['files'])
            and value['original_receive_receipt']['bytes'] == wire['total_bytes'], 'original parser result must stay target-free and exact')
    qualification(r, bundle, manifest_shape(wire))
    staging = r.physical(value['target_root']); memory_root = Path(value['memory_root'])
    require(staging.is_relative_to(ctx['root']) and staging.parent != ctx['root']
            and staging.name == 'decoded_raw' and staging != ctx['root'] / 'decoded_raw'
            and not staging.is_relative_to(ctx['canonical']), 'fresh nested persistent staging required; preserve failed508')
    require(memory_root.is_relative_to('/dev/shm') and memory_root != staging
            and memory['memory_root'] == durable['memory_root'] == str(memory_root)
            and durable['target_root'] == str(staging)
            and durable['memory_decode'] == value['memory_decode']
            and durable['target_manifest'] == value['target_manifest'], 'distinct actual memory and materialized targets required')
    ram = r.physical(memory_root).stat(); ram_id = memory['target_identity']
    require(ram.st_dev == ram_id['device'] == 22 and ram.st_ino == ram_id['inode']
            and ram.st_uid == ram_id['uid'] == os.getuid(), 'actual owned tmpfs memory target identity required')
    fresh = r.tree_manifest(staging); manifest = value['target_manifest']; identity = value['target_identity']
    require(manifest['root'] == str(staging) and manifest['device'] == fresh['device']
            == ctx['canonical'].stat().st_dev and manifest['inode'] == fresh['inode']
            and identity['device'] == fresh['device'] and identity['inode'] == fresh['inode']
            and identity['uid'] == os.getuid() and manifest['file_count'] == fresh['file_count']
            and manifest['total_bytes'] == fresh['total_bytes'], 'actual persistent target identity and totals required')
    expected = {x['name']: {k: x[k] for k in ('bytes', 'sha256', 'mode')} for x in wire['files']}
    ram_manifest = memory['memory_manifest']
    require(ram_manifest['root'] == str(memory_root) and ram_manifest['device'] == ram.st_dev
            and ram_manifest['inode'] == ram.st_ino and ram_manifest['file_count'] == len(expected)
            and ram_manifest['total_bytes'] == wire['total_bytes']
            and {name: {k: x[k] for k in ('bytes', 'sha256', 'mode')}
                 for name, x in ram_manifest['files'].items()} == expected,
            'genuine memory target manifest must equal original header bytes/modes')
    actual = {name: {k: x[k] for k in ('bytes', 'sha256', 'mode')} for name, x in fresh['files'].items()}
    require(expected == actual, 'every actual persistent file must equal the original received bytes/mode')
    require(set(manifest['files']) == set(fresh['files']), 'complete materialized file map required')
    for name, item in manifest['files'].items():
        require(all(item[k] == fresh['files'][name][k] for k in ('bytes', 'sha256', 'mode', 'device', 'inode'))
                and item['uid'] == os.getuid(), 'materialized per-file inode/hash/mode identity differs')
    require(type(durable['files_fsynced']) is list and sorted(durable['files_fsynced']) == sorted(fresh['files']),
            'every regular file must have completed its own fsync')
    anchor = Path(cfg['root_scope']['path']).parent.parent.parent
    required_dirs = {str(staging)}
    for name in expected:
        required_dirs.update(str(staging / parent) for parent in PurePosixPath(name).parents if str(parent) != '.')
    parent = staging.parent
    while True:
        require(parent == anchor or parent.is_relative_to(anchor), 'durable ancestry must reach declared stable anchor')
        required_dirs.add(str(parent))
        if parent == anchor:
            break
        parent = parent.parent
    require(type(durable['directories_fsynced']) is list
            and required_dirs <= set(durable['directories_fsynced'])
            and all(Path(p) == anchor or Path(p).is_relative_to(anchor) for p in durable['directories_fsynced']),
            'all owned directories and created ancestry must complete fsync through stable anchor')
    bank = durable['durable_wire_source']
    require(bank['wire_file_fsynced'] is True and bank['source_receipt_fsynced'] is True
            and bank['source_role'] == 'REAL_COMPLETED_SPOOL' and bank['source_receipt'] == cfg['spool_receipt']
            and bank['stable_anchor'] == str(anchor) and bank['wire_identity'] == spool['wire']['identity']
            and bank['wire_fingerprint'] == spool['wire']['fingerprint'], 'exact durable original wire/source receipt bank required')
    bank_dirs = set()
    parent = Path(spool['wire']['path']).parent
    while True:
        require(parent == anchor or parent.is_relative_to(anchor), 'owned wire bank ancestry required')
        bank_dirs.add(str(parent))
        if parent == anchor:
            break
        parent = parent.parent
    require(bank_dirs <= set(bank['directories_fsynced'])
            and all(Path(p) == anchor or Path(p).is_relative_to(anchor) for p in bank['directories_fsynced']),
            'wire bank created ancestry must be durably fsynced')
    return staging, fresh


def install(r, bundle, value, j):
    """Caller holds original canonical lock; all proof checks precede mutation."""
    ctx, cfg = bundle['old'], bundle['cfg']; root, canonical = ctx['root'], ctx['canonical']
    r.check_chain(ctx, j)
    require(r.read(r.pin(root / 'CONFIG_PIN.json')) == ctx['config_pin'], 'original CFG_PIN must stay unchanged')
    require(not (root / 'install.intent.json').exists() and not (root / 'install.done.json').exists(),
            'original install has not been attempted; no automatic retry')
    own = Path(cfg['root_scope']['path']).parent / 'bridge_runtime'
    own.mkdir()
    r.write_new(own / 'ATTEMPT_INTENT.json', dict(configuration=bundle['config_pin'], authority=cfg['authority'],
        producer=r.pin(__file__), one_shot=True))
    staging, fresh = verify_bulk(r, bundle, value)
    failed_path = root / 'decoded_raw'; failed = r.tree_manifest(failed_path)
    require(failed['file_count'] == 508, 'all508 failed prior decoded files must remain untouched')
    incoming = canonical / 'returned_raw'; old = r.tree_manifest(incoming)
    require(old['file_count'] == 195 and any('.profile-part' in n for n in old['files']), 'all195 original partial files required')
    archive = canonical / 'returned_raw_recovery06_preserved'
    require(not archive.exists(), 'old archive must be absent; no resume')
    r.write_new(own / 'CONFIG_PIN.json', bundle['config_pin'])
    r.write_new(own / 'FAILED508_MANIFEST.json', failed)
    r.write_new(root / 'OLD_PARTIAL_MANIFEST.json', old)
    r.write_new(root / 'NEW_TREE_MANIFEST.json', fresh)
    r.write_new(root / 'install.previous_guard.json', cfg['old_prepare_guard'])
    r.event(root, 'BULK_BRIDGE_INSTALL_INTENT', configuration=bundle['config_pin'],
            new_IO_authority=cfg['authority'], bridge_source=r.pin(__file__), bulk_receipt=cfg['bulk_receipt'])
    r.write_new(root / 'install.intent.json', dict(action='install', authority=ctx['cfg']['authority'],
        new_IO_authority=cfg['authority'], bridge_source=r.pin(__file__), bulk_receipt=cfg['bulk_receipt']))
    r.event(root, 'ARCHIVE_RENAME_INTENT', source=str(incoming), target=str(archive), manifest=r.pin(root / 'OLD_PARTIAL_MANIFEST.json'))
    r.no_replace_rename(incoming, archive); r.same_tree(old, r.tree_manifest(archive))
    r.event(root, 'ARCHIVE_RENAMED_CANONICAL_GAP', archive=str(archive))
    r.event(root, 'INSTALL_RENAME_INTENT', source=str(staging), target=str(incoming))
    r.no_replace_rename(staging, incoming); r.same_tree(fresh, r.tree_manifest(incoming))
    r.same_tree(failed, r.tree_manifest(failed_path))
    result = dict(status='RECOVERED_TREE_INSTALLED_PENDING_VALIDATION', protocol=PROTOCOL,
        new_IO_authority=cfg['authority'], bridge_source=r.pin(__file__), configuration=bundle['config_pin'],
        bulk_receipt=cfg['bulk_receipt'], memory_decode=value['memory_decode'],
        durable_materialization=value['durable_materialization'],
        new_tree_manifest=r.pin(root / 'NEW_TREE_MANIFEST.json'),
        old_partial_manifest=r.pin(root / 'OLD_PARTIAL_MANIFEST.json'),
        failed508_manifest=r.pin(own / 'FAILED508_MANIFEST.json'), preserved_archive=str(archive),
        operational_guards=dict(spool=cfg['spool_guard'], decode=cfg['bulk_guard']))
    j.put('RECOVERY_PROVENANCE', recovery_authority=ctx['cfg']['authority'],
          new_IO_authority=cfg['authority'], bridge_source=r.pin(__file__), bulk_receipt=cfg['bulk_receipt'],
          qualification=cfg['qualification'], failed508_manifest=result['failed508_manifest'])
    r.event(root, 'ACTION_COMPLETE', action='install', new_IO_authority=cfg['authority'])
    r.write_new(root / 'install.done.json', result)
    return result


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--config', required=True)
    p.add_argument('--recovery-source', required=True); args = p.parse_args(argv)
    r = frozen_recovery(dict(path=args.recovery_source, sha256=RECOVERY_SHA))
    from pricefm_hb import profile_control as c
    bundle = load(args.config, r, c)
    require(bundle['cfg']['recovery_source'] == r.pin(args.recovery_source), 'command exact frozen source must match configuration')
    j = c.Journal(SCOPE)
    try:
        result = install(r, bundle, r.read(bundle['cfg']['bulk_receipt']), j)
    finally:
        j.close()
    print(json.dumps(result, sort_keys=True, allow_nan=False))


if __name__ == '__main__':
    main()
