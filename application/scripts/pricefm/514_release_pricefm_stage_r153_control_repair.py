#!/usr/bin/env python3
"""Release one explicitly additional baseline control owner, preserving R152.

No legacy generation is replenished. Cached work remains closed. This release
records a separate, finite baseline-only activation and attests its actual
source, process and service before the controller can dispatch anything.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
OWNER = ENTRY.with_name('513_supervise_pricefm_stage_r153_baseline.py')
BRANCH = 'work/pricefm-r153-control-lifecycle-20261025'
OLD_ROOT = ROOT.parent/'pricefm_r152_parent_recovery_20261024'
CORE_ROOT = ROOT.parent/'pricefm_r152_parallel_20261024'
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
LEGACY = DATA/'launch_prep/pricefm_stage_r152_parallel_20261024'
SHARED = DATA/'launch_prep/pricefm_stage_r153_control_lifecycle_20261025'
RUNTIME = SHARED/'baseline'
POINTER = LEGACY/'baseline/explicit_successor.json'
AUTHORITY = RUNTIME/'authority.json'
PYTHON = DATA/'runtime_envs/r137_py311/bin/python'
WALL_SECONDS = 7*86400
CONTROL_CPU_SECONDS = 28800.
BUILD_PROOF = ROOT.parents[1]/'pricefm_chat_continuation_20261021/r153_control_and_diagnostics_20261025/validation/NORMAL_PACKAGE_BUILD_PREFLIGHT.json'
THREAD_ENV = ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS',
              'NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS','BLIS_NUM_THREADS')
_MODULES = {}


def module(name, path):
    if name not in _MODULES:
        spec = importlib.util.spec_from_file_location(name, path)
        value = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(value)
        _MODULES[name] = value
        if any(key in sys.modules for key in ('numpy','scipy','pandas')):
            raise RuntimeError('control release imported numerical libraries')
    return _MODULES[name]


def legacy():
    return module('r153_release_frozen_r152', OLD_ROOT/'application/scripts/pricefm/512_release_pricefm_stage_r152_baseline_owner.py')


def owner():
    return module('r153_explicit_owner', OWNER)


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def immutable_bytes(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise RuntimeError('symlinked immutable destination')
    if path.exists():
        if path.read_bytes() != data:
            raise RuntimeError('immutable bytes differ: '+str(path))
        return
    temporary = path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('xb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
        fd = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        temporary.unlink(missing_ok=True)


def immutable(path, value):
    immutable_bytes(path, (json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+'\n').encode())
    return value


@contextlib.contextmanager
def locked(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise RuntimeError('symlinked release lock')
    with path.open('a+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX|fcntl.LOCK_NB)
        st, fd = path.stat(), os.fstat(stream.fileno())
        if (st.st_dev,st.st_ino) != (fd.st_dev,fd.st_ino):
            raise RuntimeError('release lock inode changed')
        yield


def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args], text=True).strip()


def runtime_entries():
    names = ('513_supervise_pricefm_stage_r153_baseline.py',
             '514_release_pricefm_stage_r153_control_repair.py',
             '515_resolve_pricefm_stage_r153_cz_gate.py',
             '516_release_pricefm_stage_r153_cz_gate.py')
    return [ENTRY.with_name(name) for name in names]


def source_identity(remote=False):
    value = dict(root=str(ROOT), head=git('rev-parse','HEAD'), branch=git('branch','--show-current'),
                 runtime_sha256={str(path.relative_to(ROOT)):digest(path) for path in runtime_entries()})
    verify_source(value, remote=remote)
    return value


def verify_source(source, remote=False):
    if (source.get('root') != str(ROOT) or source.get('branch') != BRANCH
            or git('branch','--show-current') != BRANCH or git('rev-parse','HEAD') != source.get('head')
            or git('status','--porcelain')):
        raise RuntimeError('clean committed R153 source required')
    required = {str(path.relative_to(ROOT)) for path in runtime_entries()}
    if set(source.get('runtime_sha256',{})) != required:
        raise RuntimeError('R153 executable pin coverage differs')
    for relative, expected in source['runtime_sha256'].items():
        path = ROOT/relative
        if not path.resolve().is_relative_to(ROOT.resolve()) or digest(path) != expected:
            raise RuntimeError('R153 executable source differs: '+relative)
    if remote:
        line = git('ls-remote','origin','refs/heads/'+BRANCH)
        if not line or line.split()[0] != source['head']:
            raise RuntimeError('fresh published R153 head differs')
    return source


def check_pins(pins):
    for name, expected in pins.items():
        if digest(name) != expected:
            raise RuntimeError('frozen predecessor/evidence differs: '+name)


def build_paths(package):
    """Mirror the captured pkgbuild source/header predicate for this package."""
    package=Path(package)
    description=(package/'DESCRIPTION').read_text()
    if re.search(r'^Config/build/extra-sources\s*:',description,re.M):
        raise RuntimeError('unreviewed extra-source discovery in Normal package')
    sources=[];headers=[]
    if (package/'src').is_symlink() or (package/'inst/include').is_symlink():
        raise RuntimeError('symlinked Normal build discovery directory')
    for path in (package/'src').rglob('*'):
        if path.is_symlink():raise RuntimeError('symlinked Normal build discovery input')
        if any(part.startswith('.') for part in path.relative_to(package/'src').parts):continue
        if not path.is_file():continue
        if re.search(r'\.(c.*|f|rs)$',path.name) or path.name=='Cargo.toml':sources.append(str(path))
        if re.search(r'^Makevars.*$',path.name) or re.search(r'\.h.*$',path.name):headers.append(str(path))
    for path in (package/'inst/include').rglob('*'):
        if path.is_symlink():raise RuntimeError('symlinked Normal header discovery input')
        if any(part.startswith('.') for part in path.relative_to(package/'inst/include').parts):continue
        if path.is_file() and re.search(r'\.h.*$',path.name):headers.append(str(path))
    return sorted(set(sources+headers))


def build_record(path):
    path=Path(path)
    if not path.is_absolute() or path.is_symlink() or path.resolve()!=path:
        raise RuntimeError('noncanonical Normal build input')
    before=path.stat();sha=digest(path);after=path.stat()
    fields=('st_size','st_mtime_ns','st_ctime_ns','st_ino','st_dev','st_mode','st_uid','st_gid')
    if any(getattr(before,key)!=getattr(after,key) for key in fields):
        raise RuntimeError('Normal build input changed during attestation')
    return dict(path=str(path),sha256=sha,bytes=after.st_size,mtime_ns=after.st_mtime_ns,
        ctime_ns=after.st_ctime_ns,inode=after.st_ino,dev=after.st_dev,mode=after.st_mode,uid=after.st_uid,gid=after.st_gid)


def normal_build_context(path=BUILD_PROOF):
    path=Path(path);proof=read(path)
    if (proof.get('status')!='PASS_PINNED_NORMAL_PACKAGE_ALREADY_BUILT' or proof.get('needs_compile') is not False
            or proof.get('nanosecond_predicate_false') is not True or proof.get('compile_called') is not False
            or proof.get('load_all_called') is not False or proof.get('posterior_fits')!=0
            or proof.get('canonical_runtime_writes')!=0):
        raise RuntimeError('actual read-only Normal no-compilation proof required')
    package=Path(proof['package_path'])
    records=copy.deepcopy(proof['predicate_input_records'])
    records[str(package/'DESCRIPTION')]=proof['DESCRIPTION'];records[proof['dll']['path']]=proof['dll']
    libraries={}
    namespace_path=path.with_name('NORMAL_PACKAGE_BUILD_NAMESPACE_PINS.json')
    namespace=read(namespace_path)
    if (namespace.get('status')!='PASS_INSTALLED_BUILD_PREDICATE_NAMESPACE_PINS'
            or namespace.get('build_preflight_sha256')!=digest(path)):
        raise RuntimeError('installed build-predicate namespace proof differs')
    expected_namespace_paths=set()
    for key in ('pkgbuild_namespace','pkgload_namespace'):
        folder=Path(proof[key]);paths=[folder/'DESCRIPTION',folder/'NAMESPACE',*sorted((folder/'R').glob('*'))]
        expected_namespace_paths.update(str(item) for item in paths if item.is_file())
    if expected_namespace_paths!=set(namespace['namespace_code_records']):
        raise RuntimeError('installed build/loader namespace file inventory changed')
    for name,expected in namespace['namespace_code_records'].items():
        actual=build_record(name)
        if any(actual[key]!=value for key,value in expected.items()):
            raise RuntimeError('installed build/loader namespace source differs')
        libraries[name]=actual
    value=dict(schema_version=1,proof_path=str(path.resolve()),proof_sha256=digest(path),
        namespace_proof_path=str(namespace_path.resolve()),namespace_proof_sha256=digest(namespace_path),
        package_path=str(package),predicate_input_paths=sorted(proof['predicate_input_paths']),
        dll_path=proof['dll']['path'],records=records,namespace_records=libraries,
        no_compilation_permitted=True,no_build_helper_role_authorized=True)
    verify_normal_build_context(value)
    return value


def verify_normal_build_context(context, metadata_only=False):
    if (context.get('schema_version')!=1 or context.get('no_compilation_permitted') is not True
            or context.get('no_build_helper_role_authorized') is not True
            or digest(context['proof_path'])!=context['proof_sha256']
            or digest(context['namespace_proof_path'])!=context['namespace_proof_sha256']
            or build_paths(context['package_path'])!=context['predicate_input_paths']):
        raise RuntimeError('Normal no-compilation context or discovery inventory changed')
    records=dict(context['records'],**context['namespace_records'])
    for name,record in records.items():
        path=Path(name)
        if path.is_symlink() or path.resolve()!=path:
            raise RuntimeError('Normal build input path substituted')
        if metadata_only:
            st=path.stat()
            actual=dict(path=str(path),bytes=st.st_size,mtime_ns=st.st_mtime_ns,ctime_ns=st.st_ctime_ns,
                inode=st.st_ino,dev=st.st_dev,mode=st.st_mode,uid=st.st_uid,gid=st.st_gid)
            expected={key:record[key] for key in actual}
        else:
            actual=build_record(path);expected=record
        if actual!=expected:
            raise RuntimeError('Normal build input bytes or metadata changed: '+name)
    newest=max(context['records'][name]['mtime_ns'] for name in context['predicate_input_paths'])
    if newest>context['records'][context['dll_path']]['mtime_ns']:
        raise RuntimeError('Normal package would require unadmitted compilation')
    return True


def predecessor(system=None):
    system = system or owner().System()
    master, master_identity = legacy().master_context(allow_expired=True)
    state = read(LEGACY/'baseline/state.json')
    epoch = read(LEGACY/'baseline/resource_ownership_epoch.json')
    config = legacy().core().read_config(state['config_path'])
    if (state.get('phase') != 'blocked' or epoch.get('phase') != 'blocked'
            or epoch.get('generation') != 3 or config.get('max_owner_generations') != 3
            or state.get('scope_id') != master['scope_id'] or state.get('master_sha256') != master_identity['sha256']):
        raise RuntimeError('not the exact exhausted, blocked R152 predecessor')
    current = system.process(epoch['owner']['pid'])
    props = system.unit(state['new_unit'])
    if (legacy().core().same_process(current, epoch['owner']) or int(props.get('MainPID',0))
            or props.get('ActiveState') in {'active','activating'}):
        raise RuntimeError('legacy owner is still live')
    guardian = system.unit(epoch['guardian_unit'])
    if int(guardian.get('MainPID',0)) or guardian.get('ActiveState') in {'active','activating'}:
        raise RuntimeError('legacy guardian is still live')
    owner_groups = {group for group in epoch['owner'].get('cgroups',[]) if group.endswith('/'+state['new_unit'])}
    if len(owner_groups) != 1 or system.members(next(iter(owner_groups))):
        raise RuntimeError('failed generation-three control group is not drained')
    # This deliberately does not stop or require drainage of the original
    # generation-one unit: it still contains the scientific sessions.
    closed = legacy().closed_cached_scope(master, system)
    if len(closed['immutable_sha256']) != 75:
        raise RuntimeError('closed cached inventory differs')
    if POINTER.exists():
        raise RuntimeError('an explicit baseline successor has already been registered')
    return dict(master=master, master_identity=master_identity, state=state, epoch=epoch, config=config,
                old_owner_properties=props, old_guardian_properties=guardian, closed=closed)


def freeze(output, system=None):
    output = Path(output).resolve()
    if output.is_relative_to(LEGACY) or output.is_relative_to(SHARED):
        raise RuntimeError('source release must be outside canonical runtime')
    source = source_identity(remote=True)
    proof = predecessor(system)
    frozen = {str(path):digest(path) for path in sorted(LEGACY.rglob('*.json'))}
    # Existing immutable science/evidence pins remain part of the release.
    check_pins(proof['config']['source_sha256'])
    check_pins(proof['config']['evidence_sha256'])
    build=normal_build_context()
    preparation=read(DATA/'launch_prep'/(proof['config']['source_tag']+'__IT_CALA')/'preparation.json')
    if build['package_path']!=preparation['control']['normal_runtime'] or build['package_path']!=preparation['template']['package_path']:
        raise RuntimeError('no-compilation proof is for a different Normal runtime')
    return immutable(output, dict(schema_version=1, status='R153_BASELINE_ONLY_SOURCE_RELEASE',
        execution_source=source, legacy_master=proof['master_identity'], frozen_legacy_sha256=frozen,
        frozen_cached_sha256=proof['closed']['immutable_sha256'], legacy_generations_spent=3,
        explicit_additional_activation_limit=1, cumulative_owner_limit=4,
        normal_build_context=build,cached_restart_authorized=False, scientific_parameters_changed=False, created_epoch=time.time()))


def validate_probes(paths, source):
    if not paths:
        raise RuntimeError('committed-source private R lifecycle proof required')
    rows = []
    for index,path in enumerate(paths):
        path = Path(path).resolve()
        value = read(path)
        charge = value.get('control_charged_CPU_seconds')
        recorded=value.get('execution_source',{})
        if (not isinstance(charge,(int,float))
                or isinstance(charge,bool) or not math.isfinite(charge) or charge <= 0
                or value.get('new_fits') != 0 or value.get('production_service_actions') != 0
                or value.get('cleanup_verified') is not True or value.get('cleanup_errors')):
            raise RuntimeError('private R probe identity, charge or cleanup differs')
        if index==len(paths)-1:
            if recorded!=source:
                raise RuntimeError('latest successful private proof must match current execution source')
        elif recorded!=source:
            # A corrected source does not erase or refund a failed earlier
            # proof. Validate its exact committed ancestor bytes instead.
            if (recorded.get('root')!=str(ROOT) or recorded.get('branch')!=BRANCH
                    or not re.fullmatch('[a-f0-9]{40}',recorded.get('head',''))
                    or set(recorded.get('runtime_sha256',{}))!={str(p.relative_to(ROOT)) for p in runtime_entries()}):
                raise RuntimeError('historical private proof source identity differs')
            subprocess.run(['git','-C',str(ROOT),'merge-base','--is-ancestor',recorded['head'],source['head']],check=True,timeout=20)
            for relative,expected in recorded['runtime_sha256'].items():
                data=subprocess.check_output(['git','-C',str(ROOT),'show',recorded['head']+':'+relative],timeout=20)
                if hashlib.sha256(data).hexdigest()!=expected:
                    raise RuntimeError('historical private proof executable hash differs')
        rows.append(dict(path=str(path), sha256=digest(path), status=value['status'], control_CPU_seconds=charge))
    latest = read(rows[-1]['path'])
    if (latest.get('status') != 'PASS_R153_PRIVATE_R_LIFECYCLE_PROBE'
            or latest.get('package_cwd_observed') is not True or latest.get('launch_cwd_restored') is not True
            or latest.get('unapproved_cwd_rejected') is not True or latest.get('actual_process_checks',0) < 3
            or latest.get('private_control_unit',{}).get('status')!='PASS_R153_PRIVATE_CONTROL_UNIT_PROBE'):
        raise RuntimeError('non-vacuous successful actual R package/negative proof required')
    if len({row['path'] for row in rows}) != len(rows):
        raise RuntimeError('duplicate private probe receipt')
    return rows


def intent(unit, mode, authority_path):
    return dict(unit=unit, mode=mode,
        argv=[str(PYTHON),'-B',str(OWNER),mode,'--authority',str(authority_path),'--unit',unit],
        working_directory=str(ROOT), source_entry_path=str(OWNER), source_entry_sha256=digest(OWNER),
        Restart='no', KillMode='process', RuntimeMaxSec=WALL_SECONDS)


def prepare(release_path, probe_paths, system=None):
    system = system or owner().System()
    release_path = Path(release_path).resolve()
    release = read(release_path)
    source = source_identity(remote=True)
    if (release.get('status') != 'R153_BASELINE_ONLY_SOURCE_RELEASE' or release.get('execution_source') != source
            or release.get('explicit_additional_activation_limit') != 1 or release.get('cached_restart_authorized') is not False):
        raise RuntimeError('baseline-only source release differs')
    check_pins(release['frozen_legacy_sha256'])
    probes = validate_probes(probe_paths, source)
    proof = predecessor(system)
    if proof['closed']['immutable_sha256'] != release['frozen_cached_sha256']:
        raise RuntimeError('closed cached scope changed after release')
    verify_normal_build_context(release['normal_build_context'])
    with locked(SHARED/'baseline_release.lock'):
        if AUTHORITY.exists() or (RUNTIME/'activation_claim.json').exists():
            raise RuntimeError('the single explicit additional authority is already prepared or spent')
        authority_id = uuid.uuid4().hex
        start = time.time()
        prior = sum(row['control_CPU_seconds'] for row in probes)
        if prior > 600:
            raise RuntimeError('private proof consumed the proposed finite control allowance')
        original = RUNTIME/'original'
        for name in ('state','resource_ownership_epoch','blocked'):
            immutable_bytes(original/(name+'.json'), (LEGACY/'baseline'/(name+'.json')).read_bytes())
        immutable_bytes(original/'config.json', Path(proof['state']['config_path']).read_bytes())
        unit = 'pricefm-r153-muscat-owner-'+authority_id+'.service'
        guardian = 'pricefm-r153-muscat-guardian-'+authority_id+'.service'
        value = dict(schema_version=1, kind='R153_EXPLICIT_ADDITIONAL_BASELINE_OWNER', authority_id=authority_id,
            runtime=str(RUNTIME), legacy_shared_runtime=str(LEGACY), legacy_baseline_runtime=str(LEGACY/'baseline'),
            legacy_config_path=str(original/'config.json'), legacy_config_sha256=digest(original/'config.json'),
            legacy_master=dict(path=str(LEGACY/'master.json'), sha256=proof['master_identity']['sha256'],
                scope_id=proof['master']['scope_id'], start_epoch=proof['master']['start_epoch'], expires_epoch=proof['master']['expires_epoch']),
            legacy_state_archive_path=str(original/'state.json'), legacy_state_archive_sha256=digest(original/'state.json'),
            legacy_epoch_archive_path=str(original/'resource_ownership_epoch.json'),
            legacy_epoch_archive_sha256=digest(original/'resource_ownership_epoch.json'),
            execution_source=source, new_unit=unit, guardian_unit=guardian,
            activation=dict(legacy_generations_spent=3,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=4),
            grant=dict(starts_epoch=start,expires_epoch=start+WALL_SECONDS,wall_seconds=WALL_SECONDS,
                control_CPU_seconds=CONTROL_CPU_SECONDS,prior_control_CPU_seconds=prior,
                administrative_source_check_CPU_reservation=.5),
            frozen_legacy_sha256=release['frozen_legacy_sha256'], frozen_cached_sha256=release['frozen_cached_sha256'],
            normal_build_context=release['normal_build_context'],
            poll_seconds=20, source_verify_seconds=60, guardian_lease_seconds=180,
            source_release_path=str(release_path),source_release_sha256=digest(release_path),probe_receipts=probes,
            launch_attestation_path=str(RUNTIME/'launch_attestation.json'),
            control_intent=intent(unit,'run',AUTHORITY), guardian_intent=intent(guardian,'guard',AUTHORITY),
            scientific_scope='UNCHANGED_NINE_R141_TAIL_REGIONS_NO_REPAIR_FITS', cached_restart_authorized=False,
            original_cached_clock_reset=False, new_cached_allocation=False)
        owner().validate_authority_shape(value)
        # Validate current sessions under the new exact role/cwd policy before
        # publishing even a staged authority. No model or dispatch is changed.
        sessions = owner().inspect_sessions(value, system=system)
        immutable(RUNTIME/'preparation_sessions.json', sessions)
        immutable(AUTHORITY, value)
        return value


def validate_authority(path, system=None, require_unclaimed=False):
    path = Path(path).resolve()
    if path != AUTHORITY or path.is_symlink():
        raise RuntimeError('unreviewed R153 baseline authority namespace')
    value = read(path)
    owner().validate_authority_shape(value)
    authority_id=value.get('authority_id','')
    if (value.get('kind')!='R153_EXPLICIT_ADDITIONAL_BASELINE_OWNER'
            or value.get('runtime')!=str(RUNTIME)
            or value.get('legacy_shared_runtime')!=str(LEGACY)
            or value.get('legacy_baseline_runtime')!=str(LEGACY/'baseline')
            or value.get('new_unit')!='pricefm-r153-muscat-owner-'+authority_id+'.service'
            or value.get('guardian_unit')!='pricefm-r153-muscat-guardian-'+authority_id+'.service'
            or value.get('legacy_config_path')!=str(RUNTIME/'original/config.json')
            or value.get('legacy_state_archive_path')!=str(RUNTIME/'original/state.json')
            or value.get('legacy_epoch_archive_path')!=str(RUNTIME/'original/resource_ownership_epoch.json')
            or value.get('launch_attestation_path')!=str(RUNTIME/'launch_attestation.json')
            or value.get('cached_restart_authorized') is not False
            or value.get('original_cached_clock_reset') is not False
            or value.get('new_cached_allocation') is not False):
        raise RuntimeError('explicit baseline authority namespace/unit/scope differs')
    verify_source(value['execution_source'])
    check_pins(value['frozen_legacy_sha256'])
    check_pins(value['frozen_cached_sha256'])
    if digest(value['source_release_path']) != value['source_release_sha256']:
        raise RuntimeError('source release receipt changed')
    released=read(value['source_release_path'])
    if (released.get('status')!='R153_BASELINE_ONLY_SOURCE_RELEASE'
            or released.get('execution_source')!=value['execution_source']
            or released.get('frozen_legacy_sha256')!=value['frozen_legacy_sha256']
            or released.get('frozen_cached_sha256')!=value['frozen_cached_sha256']
            or released.get('normal_build_context')!=value.get('normal_build_context')
            or released.get('explicit_additional_activation_limit')!=1
            or released.get('cumulative_owner_limit')!=4):
        raise RuntimeError('authority does not match its finite source release')
    verify_normal_build_context(value['normal_build_context'],metadata_only=True)
    probes = validate_probes([row['path'] for row in value['probe_receipts']],value['execution_source'])
    if probes != value['probe_receipts']:
        raise RuntimeError('source-bound private proof history changed')
    prior=sum(row['control_CPU_seconds'] for row in probes)
    grant=value['grant']
    if (grant.get('prior_control_CPU_seconds')!=prior or prior>600
            or not all(isinstance(grant.get(key),(int,float)) and not isinstance(grant.get(key),bool)
                       and math.isfinite(grant[key]) for key in ('starts_epoch','expires_epoch'))
            or grant['starts_epoch']<released['created_epoch']
            or grant.get('administrative_source_check_CPU_reservation')!=.5):
        raise RuntimeError('private proof charges or finite control clock differ')
    master=read(LEGACY/'master.json')
    expected_master=dict(path=str(LEGACY/'master.json'),sha256=digest(LEGACY/'master.json'),
        scope_id=master['scope_id'],start_epoch=master['start_epoch'],expires_epoch=master['expires_epoch'])
    if value.get('legacy_master')!=expected_master:
        raise RuntimeError('original master identity/clock was reset')
    for key in ('legacy_state_archive','legacy_config','legacy_epoch_archive'):
        if digest(value[key+'_path']) != value[key+'_sha256']:
            raise RuntimeError('archived predecessor changed: '+key)
    if value.get('control_intent') != intent(value['new_unit'],'run',path) or value.get('guardian_intent') != intent(value['guardian_unit'],'guard',path):
        raise RuntimeError('declared actual unit/entry intent differs')
    claim = RUNTIME/'activation_claim.json'
    if require_unclaimed and claim.exists():
        raise RuntimeError('single R153 baseline activation already consumed')
    return value


def start_control(record, log, system=None):
    command = ['systemd-run','--user','--quiet','--unit='+record['unit'],
        '--description=R153 explicit baseline-only '+record['mode'],
        '--property=Restart=no','--property=KillMode=process','--property=TimeoutStopSec=20s',
        '--property=RuntimeMaxSec='+str(WALL_SECONDS)+'s','--property=WorkingDirectory='+str(ROOT),
        '--property=CPUAffinity=0-29','--property=CPUSchedulingPolicy=other','--property=IOSchedulingClass=idle',
        '--property=CPUAccounting=yes','--property=MemoryAccounting=yes',
        '--property=StandardOutput=file:'+str(log),'--property=StandardError=file:'+str(log)+'.stderr']
    command += ['--setenv='+key+'=1' for key in THREAD_ENV]
    command += ['--setenv=PYTHONDONTWRITEBYTECODE=1',*record['argv']]
    subprocess.run(command,check=True,timeout=30)


def attest(record, system, timeout=20):
    deadline=time.monotonic()+timeout
    last=None
    while time.monotonic()<deadline:
        props=system.unit(record['unit']);pid=int(props.get('MainPID',0));process=system.process(pid) if pid else None
        if process and props.get('ActiveState')=='active':
            if (process.get('argv')!=record['argv'] or process.get('cwd')!=str(ROOT)
                    or process.get('cpus')!=list(range(30))
                    or props.get('Restart')!='no' or props.get('KillMode')!='process'
                    or props.get('WorkingDirectory')!=str(ROOT) or not props.get('InvocationID')
                    or str(OWNER) not in props.get('ExecStart','')):
                raise RuntimeError('actual launched control service differs from declared intent')
            raw=props.get('RuntimeMaxUSec','')
            if raw not in {'1w','7d','604800000000','604800s','7d 0h 0min 0s'}:
                raise RuntimeError('actual control runtime bound differs: '+raw)
            return dict(intent=record,process=process,unit_properties=props,attested_epoch=time.time())
        last=dict(properties=props,process=process)
        time.sleep(.1)
    raise RuntimeError('bounded control attestation timed out: '+repr(last))


def launch(path, system=None):
    system=system or owner().System()
    with locked(SHARED/'baseline_release.lock'):
        value=validate_authority(path,system=system,require_unclaimed=True)
        verify_source(value['execution_source'],remote=True)
        predecessor(system)
        if time.time()-value['grant']['starts_epoch']>300:
            raise RuntimeError('prepared handoff is too old; no activation consumed')
        owner().inspect_sessions(value,system=system)
        claim=dict(schema_version=1,authority_path=str(AUTHORITY),authority_sha256=digest(AUTHORITY),
            activation=value['activation'],execution_source=value['execution_source'],claimed_epoch=time.time(),
            new_unit=value['new_unit'],guardian_unit=value['guardian_unit'],model_signals=0)
        immutable(RUNTIME/'activation_claim.json',claim)
        started=[]
        try:
            for label,key in [('owner','control_intent'),('guardian','guardian_intent')]:
                start_control(value[key],RUNTIME/(label+'.log'),system=system)
                started.append(value[key])
            owner_capsule=attest(value['control_intent'],system)
            guardian_capsule=attest(value['guardian_intent'],system)
            immutable(RUNTIME/'launch_attestation.json',dict(schema_version=1,authority_sha256=digest(AUTHORITY),
                owner=owner_capsule,guardian=guardian_capsule,source=value['execution_source'],epoch=time.time()))
            deadline=time.monotonic()+60
            last=None
            while time.monotonic()<deadline:
                try:
                    last=owner().inspect_owner(AUTHORITY,system=system)
                    if last.get('healthy') is True:
                        pointer=dict(schema_version=1,kind='EXPLICIT_R153_BASELINE_ONLY_SUCCESSOR',
                            authority_path=str(AUTHORITY),authority_sha256=digest(AUTHORITY),runtime=str(RUNTIME),
                            source=value['execution_source'],legacy_generations_spent=3,explicit_additional_activation=1,
                            cumulative_owner_count=4,cached_restart_authorized=False,registered_epoch=time.time())
                        immutable(POINTER,pointer)
                        immutable(RUNTIME/'activation_verified.json',dict(proof=last,canonical_pointer=str(POINTER),
                            canonical_pointer_sha256=digest(POINTER),model_signals=0,epoch=time.time()))
                        return last
                except (RuntimeError,FileNotFoundError) as error:
                    last=repr(error)
                time.sleep(.2)
            raise RuntimeError('new baseline owner did not become healthy: '+repr(last))
        except BaseException as error:
            # Only the exact newly declared control services may be stopped.
            # Their KillMode=process is attested before any stop. Never stop
            # the old fit-containing unit or a numerical child.
            cleanup=[]
            for record in reversed(started):
                props=system.unit(record['unit'])
                if props.get('KillMode')=='process' and str(OWNER) in props.get('ExecStart',''):
                    result=subprocess.run(['systemctl','--user','stop',record['unit']],capture_output=True,text=True,timeout=30)
                    cleanup.append(dict(unit=record['unit'],returncode=result.returncode))
                else:
                    cleanup.append(dict(unit=record['unit'],stopped=False,reason='control policy not safely attested'))
            immutable(RUNTIME/'activation_failed.json',dict(error=repr(error),control_cleanup=cleanup,
                activation_spent=True,numerical_worker_signals=0,epoch=time.time()))
            raise


def private_r_probe(output, system=None):
    """Observe real installed-pkgload cwd transitions without any model fit.

    The tiny private package only writes witnesses and waits for handshakes.
    The exact production role/contract predicate is exercised against the
    actual R process via its strictly private fixture policy.
    """
    output=Path(output).resolve()
    if output.is_relative_to(LEGACY) or output.is_relative_to(SHARED) or output.exists():
        raise RuntimeError('new private proof output must be outside canonical runtime')
    source=source_identity(remote=True)
    system=system or owner().System()
    started_cpu=time.process_time()
    child_cpu_before=os.times().children_user+os.times().children_system
    namespace=Path(tempfile.mkdtemp(prefix='pricefm-r153-owner-probe-',dir='/tmp'))
    os.chmod(namespace,0o700)
    value=dict(schema_version=1,status='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE',execution_source=source,
        namespace=str(namespace),started_epoch=time.time(),new_fits=0,production_service_actions=0,
        package_cwd_observed=False,launch_cwd_restored=False,unapproved_cwd_rejected=False,
        actual_process_checks=0,cleanup_verified=False,cleanup_errors=[],errors=[],signals=[])
    process=None;identity=None
    try:
        data=namespace/'data';science=namespace/'science';dependency=namespace/'dependency'
        launch_cwd=namespace/'launch';package=namespace/'package';unapproved=namespace/'unapproved'
        for folder in (data,science,dependency,launch_cwd,package/'R',unapproved):
            folder.mkdir(parents=True,exist_ok=True)
        (package/'DESCRIPTION').write_text('Package: r153cwdprobe\nVersion: 0.0.1\nTitle: Private Resource Lifecycle Witness\nDescription: Writes directory witnesses without numerical fitting.\nAuthors@R: person("Private", "Probe", email="probe@example.invalid", role=c("aut","cre"))\nLicense: MIT\nEncoding: UTF-8\n')
        (package/'NAMESPACE').write_text('')
        script=dependency/'application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R'
        script.parent.mkdir(parents=True)
        witness=package/'R/witness.R'
        def rstring(path):
            return json.dumps(str(path))
        witness.write_text('writeLines(getwd(), '+rstring(namespace/'inside.txt')+')\n'
            'while (!file.exists('+rstring(namespace/'restore.request')+')) Sys.sleep(0.01)\n')
        script.write_text('initial <- getwd()\nwriteLines(initial, '+rstring(namespace/'before.txt')+')\n'
            'while (!file.exists('+rstring(namespace/'load.request')+')) Sys.sleep(0.01)\n'
            'pkgload::load_all('+rstring(package)+', quiet=TRUE, export_all=TRUE, compile=FALSE)\n'
            'stopifnot(identical(getwd(), initial))\nwriteLines(getwd(), '+rstring(namespace/'restored.txt')+')\n'
            'while (!file.exists('+rstring(namespace/'negative.request')+')) Sys.sleep(0.01)\n'
            'setwd('+rstring(unapproved)+')\nwriteLines(getwd(), '+rstring(namespace/'negative.txt')+')\n'
            'while (!file.exists('+rstring(namespace/'exit.request')+')) Sys.sleep(0.01)\n'
            'setwd(initial)\n')
        rscript=Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
        if not rscript.is_file():
            raise RuntimeError('pinned R 4.6 runtime unavailable')
        tag='pricefm_stage_r153_private_lifecycle';region='PROBE';task_name='rhs_PROBE_private'
        campaign=data/'campaigns'/(tag+'__'+region)
        (campaign/'tasks').mkdir(parents=True);(campaign/'contracts').mkdir()
        preparation=data/'launch_prep'/(tag+'__'+region)/'preparation.json'
        preparation.parent.mkdir(parents=True)
        pins={str(script):digest(script),str(witness):digest(witness),str(package/'DESCRIPTION'):digest(package/'DESCRIPTION')}
        config=dict(data=str(data),source_worktree=str(science),dependency_worktree=str(dependency),source_tag=tag,
            source_head=source['head'],source_branch=source['branch'],python_runtime=str(PYTHON),
            source_controller=str(science/'480_private_controller.py'),source_sha256=pins,evidence_sha256={})
        immutable(preparation,dict(source=dict(head=source['head'],branch=source['branch']),dependency=str(dependency),
            source_sha256=pins,template=dict(package_path=str(package)),
            control=dict(normal_runtime=str(package),rscript=str(rscript)),
            protocol=dict(normal_max_iter=2000,al_max_iter=300)))
        immutable(campaign/'tasks'/(task_name+'.json'),dict(name=task_name,region=region,kind='rhs',tau0=1e-3))
        contract=campaign/'contracts'/(task_name+'.json')
        immutable(contract,dict(output_dir=str(campaign/'tasks_done'/task_name/'fit'),tag=tag+'__'+region,
            package_path=str(package),max_iter=2000,tau0=1e-3,source_sha256=pins))
        immutable(namespace/'policy.json',dict(schema_version=1,namespace=str(namespace),execution_source=source,
            owner=system.process(os.getpid()),config=config))
        policy=owner().private_probe_policy(namespace,sourceproof=source,system=system)
        env=dict(os.environ,**{key:'1' for key in THREAD_ENV})
        def private_idle():
            os.sched_setaffinity(0,{29})
            os.sched_setscheduler(0,os.SCHED_IDLE,os.sched_param(0))
        stdout=(namespace/'R.stdout').open('wb');stderr=(namespace/'R.stderr').open('wb')
        try:
            process=subprocess.Popen([str(rscript),str(script),'--contract',str(contract)],cwd=str(launch_cwd),
                env=env,stdout=stdout,stderr=stderr,start_new_session=True,preexec_fn=private_idle)
        finally:
            stdout.close();stderr.close()
        def await_witness(name):
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                if (namespace/name).is_file():
                    return (namespace/name).read_text().strip()
                if process.poll() is not None:
                    raise RuntimeError('private R exited before '+name+': '+(namespace/'R.stderr').read_text())
                time.sleep(.02)
            raise RuntimeError('bounded private R witness timeout: '+name)
        before_cwd=await_witness('before.txt')
        identity=system.process(process.pid)
        if identity is None or identity['cwd']!=str(launch_cwd) or before_cwd!=str(launch_cwd):
            raise RuntimeError('private R initial observed directory differs')
        job=dict(region=region,process=dict(identity,cwd=str(launch_cwd)),cpus=[29],session_id=process.pid)
        observations=[]
        def observe(expected_cwd,accepted=True):
            current=system.process(process.pid)
            if (current is None or any(current[k]!=identity[k] for k in ('pid','start_ticks','boot_id','cmdline_sha256','argv','session_id'))
                    or current['cwd']!=str(expected_cwd) or current['cpus']!=[29]):
                raise RuntimeError('private R lifetime/command/session/affinity changed')
            value['actual_process_checks']+=1
            try:
                role=policy.r_role(current,job)
            except RuntimeError as error:
                if accepted:raise
                observations.append(dict(actual=current,accepted=False,error=repr(error)))
                return
            if not accepted:
                raise RuntimeError('unapproved actual R cwd was accepted')
            observations.append(dict(actual=current,accepted=True,role=role))
        observe(launch_cwd)
        (namespace/'load.request').touch()
        if await_witness('inside.txt')!=str(package):
            raise RuntimeError('installed pkgload did not enter the private package directory')
        observe(package);value['package_cwd_observed']=True
        (namespace/'restore.request').touch()
        if await_witness('restored.txt')!=str(launch_cwd):
            raise RuntimeError('installed pkgload failed to restore launch cwd')
        observe(launch_cwd);value['launch_cwd_restored']=True
        (namespace/'negative.request').touch()
        if await_witness('negative.txt')!=str(unapproved):
            raise RuntimeError('negative private R witness differs')
        observe(unapproved,accepted=False);value['unapproved_cwd_rejected']=True
        (namespace/'exit.request').touch()
        if process.wait(timeout=10)!=0:
            raise RuntimeError('private R lifecycle exited unsuccessfully')
        value.update(status='PASS_R153_PRIVATE_R_LIFECYCLE_PROBE',observations=observations,
            Rscript_path=str(rscript),Rscript_sha256=digest(rscript),private_process=identity,
            namespace_files_sha256={str(path.relative_to(namespace)):digest(path) for path in namespace.rglob('*') if path.is_file()})
        value['private_control_unit']=private_control_unit_probe(namespace,source,system)
    except BaseException as error:
        value['status']='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE'
        value['errors'].append(repr(error))
    finally:
        for name in ('load.request','restore.request','negative.request','exit.request'):
            (namespace/name).touch(exist_ok=True)
        if process is not None and process.poll() is None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                current=system.process(process.pid)
                if current is not None and identity is not None and all(current[k]==identity[k] for k in ('pid','start_ticks','boot_id')):
                    process.terminate();value['signals'].append(dict(pid=process.pid,signal='SIGTERM',private_only=True))
                    try:process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        after=system.process(process.pid)
                        if after is not None and all(after[k]==identity[k] for k in ('pid','start_ticks','boot_id')):
                            process.kill();value['signals'].append(dict(pid=process.pid,signal='SIGKILL',private_only=True));process.wait(timeout=5)
                else:
                    value['cleanup_errors'].append('private process identity unavailable; no blind signal sent')
        if process is not None:
            try:
                remaining=[row for row in system.processes() if row.get('session_id')==process.pid]
                value['remaining_private_session']=remaining
                value['cleanup_verified']=not remaining and process.poll() is not None
            except BaseException as error:
                value['cleanup_errors'].append(repr(error))
        else:
            value['cleanup_verified']=True
        if (namespace/'private_unit_intent.json').exists():
            cleanup_path=namespace/'private_unit_cleanup.json'
            if not cleanup_path.is_file() or read(cleanup_path).get('cleanup_verified') is not True:
                value['cleanup_errors'].append('private control unit cleanup is not positively verified')
                value['cleanup_verified']=False
        value['namespace_files_sha256']={str(path.relative_to(namespace)):digest(path)
            for path in namespace.rglob('*') if path.is_file()}
        # A transient private unit is not this driver's child. Reserve its
        # complete 30-second CPU lifetime rather than dropping its cost.
        private_unit_charge=30. if value.get('private_control_unit_started') or (namespace/'private_unit_intent.json').exists() else 0.
        value['private_control_unit_CPU_reservation']=private_unit_charge
        value['control_charged_CPU_seconds']=max(.001,time.process_time()-started_cpu)+(os.times().children_user+os.times().children_system-child_cpu_before)+5.+private_unit_charge
        value['finished_epoch']=time.time()
        if not value['cleanup_verified'] or value['cleanup_errors']:
            value['status']='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE'
        immutable(output,value)
    return value


def private_control_unit_run(namespace, unit):
    namespace=Path(namespace).resolve();system=owner().System()
    owner().private_probe_policy(namespace,system=system)
    intended=read(namespace/'private_unit_intent.json')
    process=system.process(os.getpid());props=system.unit(unit)
    if (intended['unit']!=unit or intended['argv']!=process.get('argv')
            or int(props.get('MainPID',0))!=os.getpid() or props.get('Restart')!='no'
            or props.get('KillMode')!='process' or props.get('WorkingDirectory')!=str(ROOT)
            or process.get('cpus')!=list(range(30)) or str(ENTRY) not in props.get('ExecStart','')
            or owner().runtime_seconds(props.get('RuntimeMaxUSec',''))!=WALL_SECONDS):
        raise RuntimeError('private actual control unit differs from declared policy')
    started=time.process_time()
    immutable(namespace/'private_unit_ready.json',dict(process=process,unit_properties=props,source_sha256=digest(ENTRY)))
    deadline=time.monotonic()+30
    parent=read(namespace/'policy.json')['owner']
    while not (namespace/'private_unit_exit.request').exists():
        if time.monotonic()>=deadline or not legacy().core().same_process(system.process(parent['pid']),parent):
            break
        time.sleep(.05)
    immutable(namespace/'private_unit_terminal.json',dict(status='PRIVATE_CONTROL_EXITED',
        own_CPU_seconds=time.process_time()-started,production_dispatches=0,model_signals=0))


def private_control_unit_probe(namespace, source, system):
    """Prove actual transient-unit policy and drainage before the real claim."""
    namespace=Path(namespace);unit='pricefm-r153-muscat-probe-'+uuid.uuid4().hex+'.service'
    record=dict(unit=unit,mode='private-control-probe',argv=[str(PYTHON),'-B',str(ENTRY),'private-control-probe',
        '--namespace',str(namespace),'--unit',unit],working_directory=str(ROOT))
    immutable(namespace/'private_unit_intent.json',record)
    started=False;capsule=None
    try:
        start_control(record,namespace/'private_unit.log',system=system);started=True
        deadline=time.monotonic()+20
        ready=namespace/'private_unit_ready.json'
        while not ready.is_file() and time.monotonic()<deadline:
            props=system.unit(unit)
            if props.get('ActiveState')=='failed':
                raise RuntimeError('private control unit failed: '+(namespace/'private_unit.log.stderr').read_text())
            time.sleep(.05)
        if not ready.is_file():
            raise RuntimeError('private control unit attestation timed out')
        capsule=read(ready);actual=system.process(capsule['process']['pid']);props=system.unit(unit)
        if (not legacy().core().same_process(actual,capsule['process']) or actual['argv']!=record['argv']
                or props.get('InvocationID')!=capsule['unit_properties'].get('InvocationID')
                or props.get('ActiveState')!='active'):
            raise RuntimeError('private control capsule/InvocationID differs')
        (namespace/'private_unit_exit.request').touch()
        while time.monotonic()<deadline:
            after=system.unit(unit)
            if (not int(after.get('MainPID',0)) and after.get('ActiveState') not in {'active','activating'}
                    and not system.members(props.get('ControlGroup',''))):
                terminal=read(namespace/'private_unit_terminal.json')
                if terminal.get('production_dispatches')!=0 or terminal.get('model_signals')!=0:
                    raise RuntimeError('private unit performed an unexpected action')
                return dict(status='PASS_R153_PRIVATE_CONTROL_UNIT_PROBE',declared=record,attested=capsule,
                    final_unit=after,terminal=terminal,exact_drain=True,production_service_actions=0,
                    private_service_starts=1,control_CPU_reservation=30.)
            time.sleep(.05)
        raise RuntimeError('private control unit did not drain within its bound')
    finally:
        (namespace/'private_unit_exit.request').touch()
        cleanup=dict(unit=unit,started=started,cleanup_verified=False,model_signals=0)
        try:
            props=system.unit(unit)
            if int(props.get('MainPID',0)) or props.get('ActiveState') in {'active','activating'}:
                if props.get('KillMode')!='process' or str(ENTRY) not in props.get('ExecStart',''):
                    raise RuntimeError('refusing unsafe private-control cleanup')
                subprocess.run(['systemctl','--user','stop',unit],check=True,timeout=20)
            after=system.unit(unit)
            group=(capsule or {}).get('unit_properties',{}).get('ControlGroup',props.get('ControlGroup',''))
            cleanup.update(final_unit=after,remaining_cgroup_members=system.members(group))
            cleanup['cleanup_verified']=(not int(after.get('MainPID',0))
                and after.get('ActiveState') not in {'active','activating'} and not cleanup['remaining_cgroup_members'])
        except BaseException as error:
            cleanup['error']=repr(error)
            raise
        finally:
            immutable(namespace/'private_unit_cleanup.json',cleanup)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='action',required=True)
    p=commands.add_parser('freeze');p.add_argument('--output',required=True)
    p=commands.add_parser('probe');p.add_argument('--output',required=True)
    p=commands.add_parser('prepare');p.add_argument('--release',required=True);p.add_argument('--probe',action='append',required=True)
    p=commands.add_parser('launch');p.add_argument('--authority',default=str(AUTHORITY))
    p=commands.add_parser('inspect');p.add_argument('--authority',default=str(AUTHORITY))
    p=commands.add_parser('private-control-probe');p.add_argument('--namespace',required=True);p.add_argument('--unit',required=True)
    args=parser.parse_args()
    if args.action=='freeze':result=freeze(args.output)
    elif args.action=='probe':result=private_r_probe(args.output)
    elif args.action=='prepare':result=prepare(args.release,args.probe)
    elif args.action=='launch':result=launch(args.authority)
    elif args.action=='private-control-probe':
        private_control_unit_run(args.namespace,args.unit);result=dict(status='PRIVATE_CONTROL_EXITED')
    else:result=owner().inspect_owner(args.authority)
    print(json.dumps(result,indent=2,sort_keys=True,allow_nan=False))


if __name__=='__main__':
    main()
