"""One-shot local metadata orchestration; never a compute or scientific owner.

Each native action remains below the original H. Finite separately funded startup probes precede the unchanged post-READY chain. No retry, extra
stopping wrapper, R, array library or login-node payload is introduced.
"""
import argparse
import hashlib
import importlib
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import subprocess
import sys
import time

CORE_COMMIT = '54091b7c975d9bddacd0d45ab40b360e22447fff'
CORE_FILES = {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1', 'profile_admission.py': '48514a178ff2415d4697b29168a3088ae10bdbd37294501029aa08ea7e37c57c', 'runtime_archive.py': '0a0f9416ad3b4df2e45fe511203737860d09ceb500ca372a47fadb7096054bcb', 'scientific_allocation.py': 'ddd707e3710f8485b8f2652505f123e22921674f29f12601a6685371dba61918', 'scientific_batch.py': 'b17b1753826ef8ac806eb56b17d9dd3efe2fbc5226b965d0d2866d247a78f7c7', 'scientific_batch_worker.py': '2b4c81eca2a5a29798f5cf2872c6c77ed94b428bde6f0780a7d63f61371171f6', 'scientific_boundary_fixture.R': '760dfba7326f457888ef699056b6f2f1d04edadd4772a603ff6897d11e554445', 'scientific_code_install.py': 'ab4222a320c8eccbcf0c4bcfb5966750cf576d1c2b1984c721e200eaddd14cf0', 'scientific_metadata_owner.py': '0061b128186511aa28294c52805c87850fd15ded61023ec5611ac05b3a09d910', 'scientific_namespace_contract.py': 'cda6ea625751e3a439d8068bca0cd3fcc4b9cc6ca2eb507fca55681c8b17f63b', 'scientific_namespace_fixture.R': 'b27a97cd7f37c31e1bd4171b57b572b7e7d500390d78fc00147a0a0aeefdda02', 'scientific_namespace_plan.py': 'd7669348722239694f5feb8b14774cb2e4305c7425519e8bb4e3a407f69f2b50', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'}
EXTRA_ADMINISTRATIVE_SOURCE_FILES = {'node_startup_watch.py': 'aa483792be8eeeb26ed0c353a9b5f931ff4d4367b1f58fe6e0abd7c9a44d3802', 'unallocated_tail.py': 'fd510ff4d57a1f9d9b25dd5b02b73d8ae0b4e28b93b9677859bd861cd61cbab5'}
INDEPENDENT_SOURCE_FILES = {'independent_complete_return_peer.py': '29e96bd886b923e7c2f9a2773d6704aed56f7e6d382f881e4d7aa508be6e48eb', 'independent_foundation_release_peer.py': 'a2baf6959d04f36cf965e64cf1f9eee45660ea6ce2a471e85c60e0eca1aa3ba7', 'independent_scientific_ready_peer.py': '7edeebd74b54c3fb6683fc04e158558f3e9cc61a7b03d6adbcc714cc28f232cb', 'independent_unallocated_drain_review.py': 'e8e964d2e5519629bd8d784e9e293302e38eebcd9e91e7473e435a8b4776e6ab'}
CORE_SOURCE_MAPS = {'source_family_files': {'numerical': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1', 'numerical_batch.py': '482a0a896355d43c6a75ec8d0228680308368b2e266c01f4b9532c95ae1b19a1', 'numerical_physical_admission.py': '4f83dbc17fe4fdedc68d9bb0cfa218bbc8f5260f7e82b9606d97ce88ad288812', 'numerical_stage_bootstrap.R': '99266deda89983190a11b22ec6d9cda6dad5b5f4792749e34fec3aba905ad8a4', 'numerical_stage_contract.py': 'cda26aab2959120e66daf2c458beceaaf0f1740e2215e84132c2b8b829dd676b', 'numerical_stage_owner.py': '011237d183a110b13d76b983913c097b0fe82bf01c6060a351df35270dea5b3a', 'numerical_stage_worker.py': '1999792a4438c1e8fc23a468ca5ed897b8d5365e6fd8f49ee4e4291732cf91cd', 'profile_admission.py': '48514a178ff2415d4697b29168a3088ae10bdbd37294501029aa08ea7e37c57c', 'runtime_archive.py': '0a0f9416ad3b4df2e45fe511203737860d09ceb500ca372a47fadb7096054bcb', 'scientific_allocation.py': 'ddd707e3710f8485b8f2652505f123e22921674f29f12601a6685371dba61918', 'scientific_batch.py': 'b17b1753826ef8ac806eb56b17d9dd3efe2fbc5226b965d0d2866d247a78f7c7', 'scientific_batch_worker.py': '2b4c81eca2a5a29798f5cf2872c6c77ed94b428bde6f0780a7d63f61371171f6', 'scientific_boundary_fixture.R': '760dfba7326f457888ef699056b6f2f1d04edadd4772a603ff6897d11e554445', 'scientific_code_install.py': 'ab4222a320c8eccbcf0c4bcfb5966750cf576d1c2b1984c721e200eaddd14cf0', 'scientific_metadata_owner.py': '0061b128186511aa28294c52805c87850fd15ded61023ec5611ac05b3a09d910', 'scientific_namespace_contract.py': 'cda6ea625751e3a439d8068bca0cd3fcc4b9cc6ca2eb507fca55681c8b17f63b', 'scientific_namespace_fixture.R': 'b27a97cd7f37c31e1bd4171b57b572b7e7d500390d78fc00147a0a0aeefdda02', 'scientific_namespace_plan.py': 'd7669348722239694f5feb8b14774cb2e4305c7425519e8bb4e3a407f69f2b50', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'}, 'scientific': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1', 'profile_admission.py': '48514a178ff2415d4697b29168a3088ae10bdbd37294501029aa08ea7e37c57c', 'runtime_archive.py': '0a0f9416ad3b4df2e45fe511203737860d09ceb500ca372a47fadb7096054bcb', 'scientific_allocation.py': 'ddd707e3710f8485b8f2652505f123e22921674f29f12601a6685371dba61918', 'scientific_batch.py': 'b17b1753826ef8ac806eb56b17d9dd3efe2fbc5226b965d0d2866d247a78f7c7', 'scientific_batch_worker.py': '2b4c81eca2a5a29798f5cf2872c6c77ed94b428bde6f0780a7d63f61371171f6', 'scientific_boundary_fixture.R': '760dfba7326f457888ef699056b6f2f1d04edadd4772a603ff6897d11e554445', 'scientific_code_install.py': 'ab4222a320c8eccbcf0c4bcfb5966750cf576d1c2b1984c721e200eaddd14cf0', 'scientific_metadata_owner.py': '0061b128186511aa28294c52805c87850fd15ded61023ec5611ac05b3a09d910', 'scientific_namespace_contract.py': 'cda6ea625751e3a439d8068bca0cd3fcc4b9cc6ca2eb507fca55681c8b17f63b', 'scientific_namespace_fixture.R': 'b27a97cd7f37c31e1bd4171b57b572b7e7d500390d78fc00147a0a0aeefdda02', 'scientific_namespace_plan.py': 'd7669348722239694f5feb8b14774cb2e4305c7425519e8bb4e3a407f69f2b50', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'}, 'startup': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'profile_supervisor.py': '7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1', 'startup_batch.py': '0a7ea3b0637fb1e3d32ecd2414d75a42459f28c788d21925d14add13314a60a8', 'startup_batch_kernel.py': 'dd0852ca8b6a08a0a6b5e550ee63b651e486e1939727d0beeb9756ce39558f26', 'startup_batch_stop.py': '3274605193ee16f9ce737b4ee50bc7e8195440b0b0d530f79581550cb54fe886', 'startup_batch_stop_kernel.py': '09e7c7f767b73030e6f2ae0c006bf028fc08c15752b1172da087a8ee16047533', 'startup_batch_stop_worker.py': 'bf6e4f07b0d47012f418da95fbb15c2090f3f8c53e67c8330e2539dcaa8c09fd', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b', 'startup_helper_fixture.py': 'ca44d1b8d14ba9a83d41917dc9deab66915849305e3aa909f2dcb50ed711f277', 'startup_helper_kernel_tests.py': 'b6cabf52572051dd6ebeeb67a07e7e88b96b1bba328ffa23d9caa75815285666', 'startup_helper_metadata_fixture.R': 'f169f05839101de46bdd2282069a31ec08c0aab153e4fb4459b269c853997826', 'startup_stop_candidate.py': '0d2222f7f994b5887e62f9a85405288e4ccaaf41ec68a7c8edde9ad2a4e1443c', 'startup_stop_helper.py': 'd77132d53f4dbfb21aeb205691a1b4659376178549a926ccfb0df4976764b88a'}}, 'administrative_source_files': {'numerical_critical_driver.py': 'ff3e2211927cb4c4731c66a0262192ab0933c3414b8ce04d3d2e93447a9ccea0', 'numerical_independent_peer.py': 'a9f139a325a2c46b1cb50c0a38568c2064f2cd1a42659dec3d1e88866f81ad94', 'numerical_stage_prepare.py': '895b5121182e88b8f173863efeade8050ff63104c4933ed8d313fcf4f6e9460b'}, 'scientific_source_files': {'application/R/524_toy_fullstate_consumer.R': '0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a', 'application/R/525_project_fullstate_consumer.R': '57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2', 'application/R/pricefm_r129_al_fixedpoint_certificate.R': 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571', 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R': '1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3', 'application/tests/r179_hb_toy.R': '662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190'}, 'extra_administrative_source_files': {'node_startup_watch.py': 'aa483792be8eeeb26ed0c353a9b5f931ff4d4367b1f58fe6e0abd7c9a44d3802', 'unallocated_tail.py': 'fd510ff4d57a1f9d9b25dd5b02b73d8ae0b4e28b93b9677859bd861cd61cbab5'}, 'independent_source_files': {'independent_complete_return_peer.py': '29e96bd886b923e7c2f9a2773d6704aed56f7e6d382f881e4d7aa508be6e48eb', 'independent_foundation_release_peer.py': 'a2baf6959d04f36cf965e64cf1f9eee45660ea6ce2a471e85c60e0eca1aa3ba7', 'independent_scientific_ready_peer.py': '7edeebd74b54c3fb6683fc04e158558f3e9cc61a7b03d6adbcc714cc28f232cb', 'independent_unallocated_drain_review.py': 'e8e964d2e5519629bd8d784e9e293302e38eebcd9e91e7473e435a8b4776e6ab'}}
H_SHA = "7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1"
MAX_CHAIN_SECONDS = 80
MAX_JSON = 16*1024**2
ACTION_LIMITS = {"stage":(18,300),"submit":(4,45),"ready":(6,330),"release":(4,180),"cancel":(4,45)}
REVIEW_OUTPUTS = ("install_review.json","owner_review.json","PEER_RELEASE.json")
RELEASE_FILES = ("install_spec.json","install_authority.json","install_review.json","namespace_spec.json","owner_spec.json","owner_authority.json","owner_review.json","PEER_RELEASE.json")


class DriverError(ValueError):pass


def require(ok,message):
    if not ok:raise DriverError(message)


def approved_metadata_role(role, supported_roles):
    """Each approval covers exactly one known zero-target metadata role."""
    allowed = {"SCIENTIFIC_NAMESPACE_NO_OPTIMIZER", "SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER"}
    require(type(role) is str and role in allowed, "only an exact metadata role is supported")
    require(type(supported_roles) is list and supported_roles == [role],
            "the independent reviewer must be approved for this one exact role")
    return True


def physical(path):
    p=Path(path)
    require(p.is_absolute() and '..' not in p.parts and not any(q.is_symlink() for q in (p,*p.parents)), 'absolute physical metadata path required')
    return p


def raw(path,limit=MAX_JSON):
    p=physical(path)
    with p.open('rb') as f:
        before=os.fstat(f.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid in (0,os.getuid()) and before.st_nlink==1 and before.st_size<=limit,'bounded owned/system regular input required')
        value=f.read(limit+1);after=os.fstat(f.fileno())
    key=lambda v:(v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns)
    require(key(before)==key(after)==key(p.stat()) and len(value)==before.st_size,'input changed during read')
    return value


def pin(path):
    return dict(path=str(path),sha256=hashlib.sha256(raw(path)).hexdigest())


def exact(value):
    require(type(value) is dict and set(value)=={'path','sha256'} and re.fullmatch('[0-9a-f]{64}',value['sha256']),'strict pin required')
    data=raw(value['path']);require(hashlib.sha256(data).hexdigest()==value['sha256'],'pinned source/config/reviewer drift')
    return data


def parse(data):
    def pairs(rows):
        out={}
        for k,v in rows:require(k not in out,'duplicate JSON key');out[k]=v
        return out
    def floating(s):
        v=float(s);require(math.isfinite(v),'nonfinite JSON');return v
    return json.loads(data,object_pairs_hook=pairs,parse_float=floating,parse_constant=lambda _:(_ for _ in ()).throw(DriverError('nonfinite JSON')))


def read(path):return parse(raw(path))
def linked(value):return parse(exact(value))


def write_new(path,value):
    path=physical(path);fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as f:
        json.dump(value,f,indent=2,sort_keys=True,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())
    fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(fd)
    finally:os.close(fd)


def executable(value):
    # The approved LOCAL virtualenv Python is a symlink. Pin its regular final
    #ELF bytes, not the unrelated remote HB cached-Python6059 path.
    require(type(value) is dict and set(value)=={'path','sha256'},'exact executable pin required')
    resolved=Path(value['path']).resolve(strict=True)
    require(pin(resolved)['sha256']==value['sha256'],'local executable bytes drifted')
    return resolved


def fresh_unsubmitted(root,output):
    require(not Path(output).exists(),'existing driver invocation cannot be resumed or retried')
    require(all(not (Path(root)/n).exists() for n in ['JOB.json','RECONCILED_JOB.json','ROLE_FAILED_SPENT.json','submit.intent.json','READY.json','release.intent.json']),
            'only an unsubmitted successful stage can start; no retry or late attachment')


def process_identity(pid):
    root=Path('/proc')/str(pid);fields=(root/'stat').read_text().rsplit(')',1)[1].split()
    uid=int(next(line for line in (root/'status').read_text().splitlines() if line.startswith('Uid:')).split()[1])
    return dict(pid=pid,start_ticks=int(fields[19]),uid=uid,boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip())


def verify_action(c,action,guard_path):
    g=read(guard_path);CPU,wall=ACTION_LIMITS[action]
    require(type(g.get('returncode')) is int and type(g.get('command_returncode')) is int and g['returncode']==g['command_returncode']==0
            and g.get('CPU_limit')==CPU and g.get('cap_reason') is None
            and type(g.get('aggregate_CPU_seconds')) in (int,float) and math.isfinite(g['aggregate_CPU_seconds']) and 0<=g['aggregate_CPU_seconds']<CPU
            and type(g.get('complete_lifecycle_wall_seconds')) in (int,float) and math.isfinite(g['complete_lifecycle_wall_seconds'])
            and 0<=g['complete_lifecycle_wall_seconds']<=wall and g.get('guardian_forced_monitor_stop') is False
            and all(g.get(k) is True for k in ['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']),
            'actual original native guardian failed; no successor release')
    starts=[]
    for path in Path(c['registry']).glob('control_*.started.json'):
        start=read(path)
        if start['action']==action:starts.append((path,start))
    require(len(starts)==1,'one actual native action start required')
    path,start=starts[0];pending=read(path.with_name(path.name.replace('.started.','.pending.')))
    limits=dict(local_CPU=CPU,wall=wall)
    if action!='stage':limits.update(remote_unknown_fee=CPU,maximum_calls=1)
    else:limits.update(remote_unknown_fee=18,maximum_calls=1)
    require(start['role']==c['role'] and start['source_sha256']==CORE_FILES['scientific_batch.py']
            and start['limits']==limits and g['session_id']==start['command_pid'] and g['leader_start_ticks']==start['command_birth_ticks']
            and all(pending[k]==v for k,v in start.items() if k!='status') and pending['result']==parse(g['stdout']),
            'guardian/core source/lifetime/result context differs')
    return pending['result']


def preflight(config_path,stage_guard,packet_review,startup_watch_authority):
    require(len(CORE_COMMIT)==40 and CORE_FILES and EXTRA_ADMINISTRATIVE_SOURCE_FILES and INDEPENDENT_SOURCE_FILES and CORE_SOURCE_MAPS,"unbound template cannot execute")
    require(set(CORE_SOURCE_MAPS)=={'source_family_files','administrative_source_files','scientific_source_files','extra_administrative_source_files','independent_source_files'}
            and set(CORE_SOURCE_MAPS['source_family_files'])=={'startup','scientific','numerical'}
            and [len(CORE_SOURCE_MAPS['source_family_files'][key]) for key in ['startup','scientific','numerical']]==[14,15,21]
            and [len(CORE_SOURCE_MAPS[key]) for key in ['administrative_source_files','scientific_source_files','extra_administrative_source_files','independent_source_files']]==[3,5,2,4]
            and CORE_SOURCE_MAPS['source_family_files']['scientific']==CORE_FILES
            and CORE_SOURCE_MAPS['extra_administrative_source_files']==EXTRA_ADMINISTRATIVE_SOURCE_FILES
            and CORE_SOURCE_MAPS['independent_source_files']==INDEPENDENT_SOURCE_FILES,'complete frozen CORE map dimensions')
    cfg_pin=pin(config_path);c=linked(cfg_pin);d=c['release_orchestration'];now=time.time()
    require(d.get('schema')=='pricefm_submit_ready_release_driver_binding_v1','actual reviewed driver binding required')
    require(d['source']==pin(Path(__file__).absolute()),'exact executing driver source required')
    overall=linked(d['overall_driver_publication']);overall_review=linked(d['overall_driver_source_review'])
    require(overall.get('status')=='PASS_NODE_QUALIFICATION_DRIVER_SOURCE_PUBLICATION'
            and overall_review.get('status')=='PASS_REVIEWED_NODE_QUALIFICATION_DRIVER_SOURCE'
            and re.fullmatch('[0-9a-f]{40}',overall.get('commit',''))
            and overall_review.get('source_commit')==overall['commit']
            and overall.get('core_commit')==overall_review.get('core_commit')==CORE_COMMIT
            and overall.get('core_source_maps')==overall_review.get('core_source_maps')==CORE_SOURCE_MAPS
            and set(overall.get('source_files',{}))=={'foundation_driver.py','automated_release_driver.py'}
            and overall['source_files']==overall_review.get('source_files')
            and overall['source_files']['automated_release_driver.py']==d['source']['sha256'],
            'published reviewed exact two-driver closure with complete already-frozen CORE maps')
    for name,sha in overall['source_files'].items():exact(dict(path=str(Path(c['source_dir'])/name),sha256=sha))
    publication=linked(d['publication']);review=linked(d['source_review'])
    require(publication.get('status')=='PASS_AUTOMATED_RELEASE_DRIVER_SOURCE_PUBLICATION'
            and publication.get('source')==d['source'] and re.fullmatch('[0-9a-f]{40}',publication['commit'])
            and review.get('status')=='PASS_REVIEWED_AUTOMATED_RELEASE_DRIVER_SOURCE'
            and review.get('source')==d['source'] and review.get('source_commit')==publication['commit']
            and review.get('core_source_commit')==CORE_COMMIT,'published and independently reviewed exact driver required')
    approval=linked(d['reviewer_source_approval'])
    require(approval.get('status')=='PASS_REVIEWED_INDEPENDENT_READY_REVIEWER_SOURCE'
            and approval.get('reviewer')==approval.get('source')==d['reviewer']
            and approval.get('local_python')==d['local_python'] and approval.get('CPU_limit')==12
            and approval.get('output_files')==list(REVIEW_OUTPUTS)
            and approval.get('required_cli_options')==['--config','--bundle','--scope','--stage-guard','--submit-guard','--ready-guard','--packet-review']
            and approved_metadata_role(c['role'], approval.get('supported_roles'))
            and approval['issued_epoch']<=now<approval['expires_epoch']
            and review.get('reviewer_source_approval')==d['reviewer_source_approval'],
            'independently authored pinned namespace READY12 reviewer required')
    exact(d['reviewer']);executable(d['local_python'])
    require(Path(sys.executable).resolve(strict=True)==Path(d['local_python']['path']).resolve(strict=True),'driver must use pinned LOCAL Python')
    require(d['supervisor']['sha256']==H_SHA,'unchanged original H required');exact(d['supervisor'])
    corepub=linked(c['publication']);corereview=linked(c['source_review'])
    require(corepub.get('commit')==corereview.get('source_commit')==CORE_COMMIT
            and corepub.get('source_files')==corereview.get('source_files')==CORE_FILES
            and corepub.get('extra_administrative_source_files')==corereview.get('extra_administrative_source_files')==EXTRA_ADMINISTRATIVE_SOURCE_FILES
            and corepub.get('independent_source_files')==corereview.get('independent_source_files')==INDEPENDENT_SOURCE_FILES,'core15/R183 publication identity must remain exact')
    core_pins=[dict(path=str(Path(c['source_dir'])/name),sha256=sha) for mapping in (CORE_FILES,EXTRA_ADMINISTRATIVE_SOURCE_FILES,INDEPENDENT_SOURCE_FILES) for name,sha in mapping.items()]
    for row in core_pins:exact(row)
    sys.path.insert(0,str(Path(c['source_dir']).parent))
    core=importlib.import_module('pricefm_hb.scientific_batch')
    require(Path(core.__file__).absolute()==Path(c['source_dir'])/'scientific_batch.py','exact pinned core module path required')
    checked,s,_,_=core.load_config(config_path);require(checked==c,'actual canonical core config differs')
    scope=linked(d['invocation_scope']);ps=linked(d['peer_scope']);out=physical(d['invocation_root'])
    require(scope.get('status')=='PROSPECTIVE_AUTOMATED_RELEASE_DRIVER_INVOCATION' and scope.get('parent')==c['scope']
            and scope.get('role')==c['role'] and scope.get('max_invocations')==1 and scope.get('automatic_retry') is False
            and scope.get('parent_SELF_CPU_seconds')==4 and scope.get('parent_CPU_hard_ceiling')==16
            and scope.get('root_CPU_reservation')==12 and scope.get('native_CPU_reservation')==136 and scope.get('peer_CPU_reservation')==12
            and type(scope.get('startup_watch_CPU_reservation')) is int and scope['startup_watch_CPU_reservation']==60
            and scope.get('startup_watch_budget')==c['startup_watch_budget']
            and scope.get('may_issue_prospective_stage_authorities') is True and scope.get('may_publish_source_bound_outer_release') is True
            and scope.get('allowed_output_root')==str(out) and scope.get('allowed_bundle_root')==str(out/'bundle')
            and scope['issued_epoch']<=now<scope['expires_epoch']<=s['expires_epoch'],'fresh exact one-invocation complete root/native/peer funding required')
    require(out.is_relative_to(physical(s['allowed_metadata_output_root'])) and out!=Path(s['allowed_metadata_output_root']) and not out.exists(),
            'new private home invocation root required; an old invocation cannot be resumed')
    require(ps.get('parent')==c['scope'] and ps.get('allocations',{}).get('actual_READY_prospective_installer_owner_and_outer_release')==12
            and ps.get('allowed_release_review_output_root')==str(out/'bundle')
            and ps['issued_epoch']<=now<ps['expires_epoch']<=s['expires_epoch'],'new independent actual READY12 scope required')
    require(type(d.get('settle_seconds')) is int and 1<=d['settle_seconds']<=15,'one short prepriced settle outside H required')
    root=Path(c['registry'])/c['role']
    fresh_unsubmitted(root,out)
    staged=verify_action(c,'stage',stage_guard);require(staged.get('status')=='STAGED_NOT_SUBMITTED','actual successful stage required')
    packet=read(root/'PACKET.json');peer=read(packet_review)
    require(peer.get('status')=='PASS_REVIEWED_SCIENTIFIC_BATCH_PACKET' and peer.get('config')==cfg_pin
            and peer.get('packet')==pin(root/'PACKET.json'),'actual config-bound independent packet review required')
    require(staged.get('scope_id')==packet['scope_id'],'stage and packet differ')
    fixed=[startup_watch_authority,d['overall_driver_publication'],d['overall_driver_source_review'],cfg_pin,d['source'],d['publication'],d['source_review'],d['supervisor'],d['reviewer'],d['reviewer_source_approval'],
           d['invocation_scope'],d['peer_scope'],c['scope'],c['publication'],c['source_review'],pin(stage_guard),pin(packet_review),*core_pins]
    return dict(startup_watch_authority=startup_watch_authority,config=c,config_path=str(config_path),config_pin=cfg_pin,settings=d,scope=s,invocation_scope=scope,
                output=out,root=root,packet=packet,stage_guard=str(stage_guard),packet_review=str(packet_review),core=core,fixed_pins=fixed)


class Driver:
    def __init__(self,context,*,clock=time.monotonic,sleeper=time.sleep):
        self.x=context;self.clock=clock;self.sleeper=sleeper;self.started=None;self.phase='PREFLIGHT';self.events=[];self.active_child=None;self.payload_may_have_started=False

    def check(self):
        for value in self.x['fixed_pins']:exact(value)
        executable(self.x['settings']['local_python'])
        require(time.time()<self.x['invocation_scope']['expires_epoch'],'driver scope expired')
        if self.started is not None:require(0<=self.clock()-self.started<MAX_CHAIN_SECONDS,'causal pre-submit elapsed ceiling exceeded; no further release')

    def record(self,state,**fields):
        self.phase=state
        value=dict(state=state,epoch=time.time(),elapsed=None if self.started is None else self.clock()-self.started,
                   previous=pin(self.events[-1]) if self.events else None,**fields)
        path=self.x['output']/('phase_%02d.json'%len(self.events));write_new(path,value);self.events.append(path)

    def subprocess(self,argv,stdout,stderr):
        # No timeout, signal, process-group stopper or second guardian is added.
        #Original H owns its own drain; the reviewer has its separate SELF12.
        with Path(stdout).open('xb') as out,Path(stderr).open('xb') as err:
            child=subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=out,stderr=err,close_fds=True,preexec_fn=lambda:None)
            self.active_child=dict(pid=child.pid,argv=argv,stdout=str(stdout),stderr=str(stderr),identity_not_yet_observed=True)
            self.active_child.update(process_identity(child.pid));self.active_child['identity_not_yet_observed']=False
            code=child.wait();out.flush();os.fsync(out.fileno());err.flush();os.fsync(err.fileno())
        self.active_child=None;return code

    def guarded(self,action,previous_guard,*,bundle=None):
        self.check();self.record(action.upper()+'_INTENT')
        x=self.x;d=x['settings'];CPU,wall=ACTION_LIMITS[action];path=x['output']/(action+'.guard.json')
        code="import sys;sys.path.insert(0,"+repr(str(Path(x['config']['source_dir']).parent))+");from pricefm_hb import scientific_batch;b=scientific_batch;b.main()"
        argv=[d['local_python']['path'],'-I','-B',d['supervisor']['path'],'--cpu',str(CPU),'--wall',str(wall),'--output-cap','8388608','--',
              d['local_python']['path'],'-I','-B','-c',code,action,'--config',x['config_path'],'--role',x['config']['role'],'--previous-guard',str(previous_guard)]
        if bundle is not None:argv+=['--bundle',str(bundle)]
        rc=self.subprocess(argv,path,x['output']/(action+'.guard.stderr'))
        require(rc==0,'original '+action+' guardian failed; retain receipt and stop')
        result=verify_action(x['config'],action,path)
        self.record(action.upper()+'_GUARD_PASSED',guard=pin(path));self.check();return path,result

    def authorities(self,bundle):
        self.check();now=time.time()
        for prefix,status in [('install','ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY'),('owner','ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY')]:
            value=read(bundle/(prefix+'_authority_TEMPLATE.json'))
            require(value.get('status')=='PROPOSED_UNISSUED' and value.pop('required_status')==status,'frozen core unissued authority template required')
            value.update(status=status,issued_epoch=now,expires_epoch=min(value['expires_epoch'],now+3600,self.x['scope']['expires_epoch']),
                         root_driver_source=self.x['settings']['source'],root_driver_scope=self.x['settings']['invocation_scope'],root_config=self.x['config_pin'])
            require(now+900<value['expires_epoch'],'complete stage window cannot fit root authority')
            write_new(bundle/(prefix+'_authority.json'),value)
        self.record('PROSPECTIVE_ROOT_AUTHORITIES_ISSUED')

    def peer(self,bundle,submit_guard,ready_guard):
        self.check();self.record('INDEPENDENT_READY_REVIEW_INTENT')
        x=self.x;d=x['settings'];argv=[d['local_python']['path'],'-I','-B',d['reviewer']['path'],
            '--config',x['config_path'],'--bundle',str(bundle),'--scope',d['peer_scope']['path'],
            '--stage-guard',x['stage_guard'],'--submit-guard',str(submit_guard),'--ready-guard',str(ready_guard),'--packet-review',x['packet_review']]
        rc=self.subprocess(argv,x['output']/'peer.stdout',x['output']/'peer.stderr')
        require(rc==0,'independent READY review failed; no RELEASE is created')
        self.check();self.record('INDEPENDENT_REVIEW_PROCESS_EXITED_NOT_YET_VALIDATED')

    def release_document(self,bundle):
        self.check();x=self.x;p=x['packet'];ready=read(x['root']/'READY.json');job=read(x['root']/'JOB.json');folder=p['remote_root']+'/release'
        def remote(name):return dict(path=folder+'/'+name,sha256=pin(bundle/name)['sha256'])
        stdout=parse(raw(x['output']/'peer.stdout'));peer=read(bundle/'PEER_RELEASE.json')
        stages=dict(install_spec=remote('install_spec.json'),install_authority=remote('install_authority.json'),install_review=remote('install_review.json'),
                    namespace_spec=remote('namespace_spec.json'),owner_spec=remote('owner_spec.json'),owner_authority=remote('owner_authority.json'),owner_review=remote('owner_review.json'))
        require(stdout.get('status')=='PASS_REVIEWED_STARTUP_BATCH_RELEASE' and stdout.get('phase')=='release'
                and type(stdout.get('SELF_CPU')) in (int,float) and math.isfinite(stdout['SELF_CPU']) and 0<=stdout['SELF_CPU']<12,
                'actual pinned independent reviewer output required')
        require(peer.get('status')=='PASS_REVIEWED_STARTUP_BATCH_RELEASE' and peer.get('purpose')=='SCIENTIFIC_METADATA_ONLY'
                and peer.get('role')==x['config']['role'] and peer.get('scope_id')==p['scope_id'] and peer.get('job_id')==job['job_id']
                and peer.get('node')==x['config']['node'] and peer.get('qualification_route_id')==x['scope']['qualification_route_id'] and peer.get('ready_sha256')==pin(x['root']/'READY.json')['sha256']
                and peer.get('spec_sha256')==p['spec_sha256'] and peer.get('sources')==p['sources'] and peer.get('stage_pins')==stages
                and peer.get('review_source')==x['settings']['reviewer'] and peer.get('actual_peer_scope')==x['settings']['peer_scope']
                and peer.get('config')==x['config_pin'],'actual independent READY/source/job/root-contract review differs')
        for prefix,status in [('install','PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC'),('owner','PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC')]:
            proof=read(bundle/(prefix+'_review.json'))
            require(proof.get('status')==status and proof.get('spec')==stages[prefix+'_spec'] and proof.get('authority')==stages[prefix+'_authority']
                    and proof.get('actual_peer_scope')==x['settings']['peer_scope'] and proof.get('config')==x['config_pin'],'actual independent stage review differs')
        now=time.time();expiry=min(peer['expires_epoch'],x['scope']['expires_epoch'])
        require(now+900<expiry,'complete root release stage window exhausted')
        value=dict(status='ROOT_RELEASED_STARTUP_BATCH_ROLE',role=x['config']['role'],scope_id=p['scope_id'],job_id=job['job_id'],node=x['config']['node'],qualification_route_id=x['scope']['qualification_route_id'],
            ready_sha256=pin(x['root']/'READY.json')['sha256'],spec_sha256=p['spec_sha256'],sources=p['sources'],scope_sha256=x['config']['scope']['sha256'],
            issued_epoch=now,expires_epoch=expiry,files=[dict(relative=n,sha256=pin(bundle/n)['sha256']) for n in RELEASE_FILES],
            independent_review=remote('PEER_RELEASE.json'),root_driver_source=x['settings']['source'],root_driver_scope=x['settings']['invocation_scope'],**stages)
        # Nothing named RELEASE exists until all actual independent records pass.
        self.check();write_new(bundle/'RELEASE.json',value);self.record('SOURCE_BOUND_ROOT_RELEASE_DOCUMENT_CREATED',release=pin(bundle/'RELEASE.json'))
        return value

    def execute(self):
        x=self.x;self.check();fresh_unsubmitted(x['root'],x['output']);x['output'].mkdir(mode=0o700)
        write_new(x['output']/'INTENT.json',dict(status='DRIVER_INVOCATION_STARTED_NOT_SUCCESS',config=x['config_pin'],
            driver=x['settings']['source'],stage_guard=pin(x['stage_guard']),packet_review=pin(x['packet_review']),no_automatic_retry=True))
        try:
            self.record('SUBMISSION_STARTED_BEFORE_SEPARATE_STARTUP_WATCH')
            sg,_=self.guarded('submit',x['stage_guard'])
            self.check();self.record('PAID_STARTUP_WATCH_INTENT')
            watch=importlib.import_module('pricefm_hb.node_startup_watch')
            try:startup=watch.wait(x['config_path'],x['config']['role'],'scientific',x['startup_watch_authority'])
            except BaseException as startup_error:
                cancel=None;cancel_error=None
                try:cancel,_=self.guarded('cancel',sg)
                except BaseException as err:cancel_error=type(err).__name__+': '+str(err)
                job=read(x['root']/'JOB.json')
                write_new(x['output']/'STARTUP_FAILED.json',dict(status='STARTUP_FAILED_NO_RELEASE' if cancel else 'FAILED_STARTUP_CANCEL_UNKNOWN_ROLE_QUARANTINED',
                    job_id=job['job_id'],role=x['config']['role'],error=type(startup_error).__name__+': '+str(startup_error),
                    cancel_guard=pin(cancel) if cancel else None,cancel_error=cancel_error,no_retry=True,no_release=True,all_reserved_fees_retained=True))
                write_new(x['root']/'ROLE_FAILED_SPENT.json',dict(status='ROLE_FAILED_SPENT',job_id=job['job_id'],role=x['config']['role'],no_release=True,
                    failed_startup=pin(x['output']/'STARTUP_FAILED.json'),old_fees_retained=True));raise
            rg,_=self.guarded('ready',sg)
            ready=read(x['root']/'READY.json')
            require(pin(x['root']/'READY.json')['sha256']==startup['ready']['sha256'] and type(ready['observed_epoch']) in (int,float)
                and math.isfinite(ready['observed_epoch']) and 0<=time.time()-ready['observed_epoch']<80,'same fresh actual READY begins unchanged80chain')
            self.started=self.clock()-(time.time()-ready['observed_epoch']);self.check()
            bundle=x['output']/'bundle';x['core'].prepare_release(x['config_path'],bundle);self.record('ACTUAL_READY_BOUND_SPECS_PREPARED')
            self.authorities(bundle);self.peer(bundle,sg,rg);self.release_document(bundle)
            self.check();self.payload_may_have_started=True
            release_guard,result=self.guarded('release',rg,bundle=bundle)
            value=dict(status='PASS_GUARDED_SUBMIT_READY_RELEASE_NOT_RUNTIME_PROOF',job=pin(x['root']/'JOB.json'),release_guard=pin(release_guard),
                       result=result,driver_source=x['settings']['source'],elapsed_seconds=self.clock()-self.started,
                       pending_core_release_guard_must_be_supplied_to_next_action=True,namespace_ABI_TSYNC_or_numerical_acceptance=False,
                       primary_and_child_CPU_not_double_counted=True)
            write_new(x['output']/'RESULT.json',value);return value
        except BaseException as error:
            own=resource.getrusage(resource.RUSAGE_SELF)
            value=dict(status='FAILED_DRIVER_INVOCATION_RETAINED_NO_RETRY',error=type(error).__name__+': '+str(error),phase=self.phase,
                active_child=self.active_child,remote_payload_may_have_started=self.payload_may_have_started,
                local_H_child_drains_not_claimed_by_driver=True,parent_SELF_CPU_seconds=own.ru_utime+own.ru_stime,
                elapsed_seconds=None if self.started is None else self.clock()-self.started,old_fees_retained=True)
            write_new(x['output']/'FAILED.json',value);raise


def main():
    require(os.sched_getaffinity(0)=={31},'administrative CPU31 required')
    old=resource.getrlimit(resource.RLIMIT_CPU);require(old[1]==resource.RLIM_INFINITY or old[1]>=16,'parent must permit original H/reviewer child hard caps')
    resource.setrlimit(resource.RLIMIT_CPU,(4,16));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    signal.signal(signal.SIGXCPU,lambda *_:(_ for _ in ()).throw(DriverError('parent SELF4 exhausted; no successor payload')))
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['config','stage-guard','packet-review','startup-watch-authority','startup-watch-authority-sha256']:p.add_argument('--'+name,required=True)
    args=p.parse_args();context=preflight(args.config,args.stage_guard,args.packet_review,dict(path=args.startup_watch_authority,sha256=args.startup_watch_authority_sha256));result=Driver(context).execute();print(json.dumps(result,sort_keys=True))


if __name__=='__main__':main()
