"""UNBOUND template. Bind already-frozen CORE in a separate reviewed lane.

Each native operation retains original H, each peer has a separately paid SELF
cap, startup waits occur outside H, and no peer PASS is written by this driver.
"""
import argparse,hashlib,importlib,json,os,re,resource,signal,stat,subprocess,sys,time
from pathlib import Path

CORE_COMMIT = '54091b7c975d9bddacd0d45ab40b360e22447fff'
CORE_FILES = {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'profile_supervisor.py': '7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1', 'startup_batch.py': '0a7ea3b0637fb1e3d32ecd2414d75a42459f28c788d21925d14add13314a60a8', 'startup_batch_kernel.py': 'dd0852ca8b6a08a0a6b5e550ee63b651e486e1939727d0beeb9756ce39558f26', 'startup_batch_stop.py': '3274605193ee16f9ce737b4ee50bc7e8195440b0b0d530f79581550cb54fe886', 'startup_batch_stop_kernel.py': '09e7c7f767b73030e6f2ae0c006bf028fc08c15752b1172da087a8ee16047533', 'startup_batch_stop_worker.py': 'bf6e4f07b0d47012f418da95fbb15c2090f3f8c53e67c8330e2539dcaa8c09fd', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b', 'startup_helper_fixture.py': 'ca44d1b8d14ba9a83d41917dc9deab66915849305e3aa909f2dcb50ed711f277', 'startup_helper_kernel_tests.py': 'b6cabf52572051dd6ebeeb67a07e7e88b96b1bba328ffa23d9caa75815285666', 'startup_helper_metadata_fixture.R': 'f169f05839101de46bdd2282069a31ec08c0aab153e4fb4459b269c853997826', 'startup_stop_candidate.py': '0d2222f7f994b5887e62f9a85405288e4ccaaf41ec68a7c8edde9ad2a4e1443c', 'startup_stop_helper.py': 'd77132d53f4dbfb21aeb205691a1b4659376178549a926ccfb0df4976764b88a'}
EXTRA_ADMINISTRATIVE_SOURCE_FILES = {'node_startup_watch.py': 'aa483792be8eeeb26ed0c353a9b5f931ff4d4367b1f58fe6e0abd7c9a44d3802', 'unallocated_tail.py': 'fd510ff4d57a1f9d9b25dd5b02b73d8ae0b4e28b93b9677859bd861cd61cbab5'}
INDEPENDENT_SOURCE_FILES = {'independent_complete_return_peer.py': '29e96bd886b923e7c2f9a2773d6704aed56f7e6d382f881e4d7aa508be6e48eb', 'independent_foundation_release_peer.py': 'a2baf6959d04f36cf965e64cf1f9eee45660ea6ce2a471e85c60e0eca1aa3ba7', 'independent_scientific_ready_peer.py': '7edeebd74b54c3fb6683fc04e158558f3e9cc61a7b03d6adbcc714cc28f232cb', 'independent_unallocated_drain_review.py': 'e8e964d2e5519629bd8d784e9e293302e38eebcd9e91e7473e435a8b4776e6ab'}
CORE_SOURCE_MAPS = {'source_family_files': {'numerical': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1', 'numerical_batch.py': '482a0a896355d43c6a75ec8d0228680308368b2e266c01f4b9532c95ae1b19a1', 'numerical_physical_admission.py': '4f83dbc17fe4fdedc68d9bb0cfa218bbc8f5260f7e82b9606d97ce88ad288812', 'numerical_stage_bootstrap.R': '99266deda89983190a11b22ec6d9cda6dad5b5f4792749e34fec3aba905ad8a4', 'numerical_stage_contract.py': 'cda26aab2959120e66daf2c458beceaaf0f1740e2215e84132c2b8b829dd676b', 'numerical_stage_owner.py': '011237d183a110b13d76b983913c097b0fe82bf01c6060a351df35270dea5b3a', 'numerical_stage_worker.py': '1999792a4438c1e8fc23a468ca5ed897b8d5365e6fd8f49ee4e4291732cf91cd', 'profile_admission.py': '48514a178ff2415d4697b29168a3088ae10bdbd37294501029aa08ea7e37c57c', 'runtime_archive.py': '0a0f9416ad3b4df2e45fe511203737860d09ceb500ca372a47fadb7096054bcb', 'scientific_allocation.py': 'ddd707e3710f8485b8f2652505f123e22921674f29f12601a6685371dba61918', 'scientific_batch.py': 'b17b1753826ef8ac806eb56b17d9dd3efe2fbc5226b965d0d2866d247a78f7c7', 'scientific_batch_worker.py': '2b4c81eca2a5a29798f5cf2872c6c77ed94b428bde6f0780a7d63f61371171f6', 'scientific_boundary_fixture.R': '760dfba7326f457888ef699056b6f2f1d04edadd4772a603ff6897d11e554445', 'scientific_code_install.py': 'ab4222a320c8eccbcf0c4bcfb5966750cf576d1c2b1984c721e200eaddd14cf0', 'scientific_metadata_owner.py': '0061b128186511aa28294c52805c87850fd15ded61023ec5611ac05b3a09d910', 'scientific_namespace_contract.py': 'cda6ea625751e3a439d8068bca0cd3fcc4b9cc6ca2eb507fca55681c8b17f63b', 'scientific_namespace_fixture.R': 'b27a97cd7f37c31e1bd4171b57b572b7e7d500390d78fc00147a0a0aeefdda02', 'scientific_namespace_plan.py': 'd7669348722239694f5feb8b14774cb2e4305c7425519e8bb4e3a407f69f2b50', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'}, 'scientific': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1', 'profile_admission.py': '48514a178ff2415d4697b29168a3088ae10bdbd37294501029aa08ea7e37c57c', 'runtime_archive.py': '0a0f9416ad3b4df2e45fe511203737860d09ceb500ca372a47fadb7096054bcb', 'scientific_allocation.py': 'ddd707e3710f8485b8f2652505f123e22921674f29f12601a6685371dba61918', 'scientific_batch.py': 'b17b1753826ef8ac806eb56b17d9dd3efe2fbc5226b965d0d2866d247a78f7c7', 'scientific_batch_worker.py': '2b4c81eca2a5a29798f5cf2872c6c77ed94b428bde6f0780a7d63f61371171f6', 'scientific_boundary_fixture.R': '760dfba7326f457888ef699056b6f2f1d04edadd4772a603ff6897d11e554445', 'scientific_code_install.py': 'ab4222a320c8eccbcf0c4bcfb5966750cf576d1c2b1984c721e200eaddd14cf0', 'scientific_metadata_owner.py': '0061b128186511aa28294c52805c87850fd15ded61023ec5611ac05b3a09d910', 'scientific_namespace_contract.py': 'cda6ea625751e3a439d8068bca0cd3fcc4b9cc6ca2eb507fca55681c8b17f63b', 'scientific_namespace_fixture.R': 'b27a97cd7f37c31e1bd4171b57b572b7e7d500390d78fc00147a0a0aeefdda02', 'scientific_namespace_plan.py': 'd7669348722239694f5feb8b14774cb2e4305c7425519e8bb4e3a407f69f2b50', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'}, 'startup': {'__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f', 'profile_supervisor.py': '7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1', 'startup_batch.py': '0a7ea3b0637fb1e3d32ecd2414d75a42459f28c788d21925d14add13314a60a8', 'startup_batch_kernel.py': 'dd0852ca8b6a08a0a6b5e550ee63b651e486e1939727d0beeb9756ce39558f26', 'startup_batch_stop.py': '3274605193ee16f9ce737b4ee50bc7e8195440b0b0d530f79581550cb54fe886', 'startup_batch_stop_kernel.py': '09e7c7f767b73030e6f2ae0c006bf028fc08c15752b1172da087a8ee16047533', 'startup_batch_stop_worker.py': 'bf6e4f07b0d47012f418da95fbb15c2090f3f8c53e67c8330e2539dcaa8c09fd', 'startup_batch_worker.py': 'dfa7faf3563cb21e360421fc344156cb8746349b259931a44128cf214478a205', 'startup_helper.py': '8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b', 'startup_helper_fixture.py': 'ca44d1b8d14ba9a83d41917dc9deab66915849305e3aa909f2dcb50ed711f277', 'startup_helper_kernel_tests.py': 'b6cabf52572051dd6ebeeb67a07e7e88b96b1bba328ffa23d9caa75815285666', 'startup_helper_metadata_fixture.R': 'f169f05839101de46bdd2282069a31ec08c0aab153e4fb4459b269c853997826', 'startup_stop_candidate.py': '0d2222f7f994b5887e62f9a85405288e4ccaaf41ec68a7c8edde9ad2a4e1443c', 'startup_stop_helper.py': 'd77132d53f4dbfb21aeb205691a1b4659376178549a926ccfb0df4976764b88a'}}, 'administrative_source_files': {'numerical_critical_driver.py': 'ff3e2211927cb4c4731c66a0262192ab0933c3414b8ce04d3d2e93447a9ccea0', 'numerical_independent_peer.py': 'a9f139a325a2c46b1cb50c0a38568c2064f2cd1a42659dec3d1e88866f81ad94', 'numerical_stage_prepare.py': '895b5121182e88b8f173863efeade8050ff63104c4933ed8d313fcf4f6e9460b'}, 'scientific_source_files': {'application/R/524_toy_fullstate_consumer.R': '0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a', 'application/R/525_project_fullstate_consumer.R': '57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2', 'application/R/pricefm_r129_al_fixedpoint_certificate.R': 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571', 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R': '1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3', 'application/tests/r179_hb_toy.R': '662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190'}, 'extra_administrative_source_files': {'node_startup_watch.py': 'aa483792be8eeeb26ed0c353a9b5f931ff4d4367b1f58fe6e0abd7c9a44d3802', 'unallocated_tail.py': 'fd510ff4d57a1f9d9b25dd5b02b73d8ae0b4e28b93b9677859bd861cd61cbab5'}, 'independent_source_files': {'independent_complete_return_peer.py': '29e96bd886b923e7c2f9a2773d6704aed56f7e6d382f881e4d7aa508be6e48eb', 'independent_foundation_release_peer.py': 'a2baf6959d04f36cf965e64cf1f9eee45660ea6ce2a471e85c60e0eca1aa3ba7', 'independent_scientific_ready_peer.py': '7edeebd74b54c3fb6683fc04e158558f3e9cc61a7b03d6adbcc714cc28f232cb', 'independent_unallocated_drain_review.py': 'e8e964d2e5519629bd8d784e9e293302e38eebcd9e91e7473e435a8b4776e6ab'}}
H_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'

def bootstrap_core():
    """Check pinned local CORE using stdlib before importing package/helper."""
    source=Path(__file__).absolute().parent
    mappings=[*CORE_SOURCE_MAPS['source_family_files'].values(),CORE_SOURCE_MAPS['administrative_source_files'],
        CORE_SOURCE_MAPS['extra_administrative_source_files'],CORE_SOURCE_MAPS['independent_source_files']]
    wanted={}
    for mapping in mappings:
        for name,sha in mapping.items():
            assert '/' not in name and name.endswith(('.py','.R')) and re.fullmatch('[0-9a-f]{64}',sha),'closed bootstrap source pin'
            assert name not in wanted or wanted[name]==sha,'consistent overlapping CORE maps'
            wanted[name]=sha
    paths={source/name:sha for name,sha in wanted.items()}
    paths.update({source.parents[3]/name:sha for name,sha in CORE_SOURCE_MAPS['scientific_source_files'].items()})
    assert '__init__.py' in wanted and 'startup_helper.py' in wanted,'package/helper bootstrap closure'
    for path,sha in paths.items():
        assert path.is_absolute() and '..' not in path.parts and not any(p.is_symlink() for p in (path,*path.parents)),'physical bootstrap source'
        descriptor=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
        with os.fdopen(descriptor,'rb') as handle:
            before=os.fstat(handle.fileno())
            assert stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid in (0,os.getuid()) and before.st_size<=32*1024**2,'bounded owned bootstrap source'
            data=handle.read(32*1024**2+1);after=os.fstat(handle.fileno())
        key=lambda value:(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
        assert key(before)==key(after)==key(path.stat()) and len(data)==before.st_size and hashlib.sha256(data).hexdigest()==sha,'exact stable pre-import CORE bytes'
    return source

def run(config_path,authority_pin):
    assert len(CORE_COMMIT)==40 and CORE_FILES and EXTRA_ADMINISTRATIVE_SOURCE_FILES and INDEPENDENT_SOURCE_FILES and CORE_SOURCE_MAPS,'unbound template cannot execute'
    source=bootstrap_core();sys.path.insert(0,str(source.parent))
    from pricefm_hb import startup_helper as h
    h.require(set(CORE_SOURCE_MAPS)=={'source_family_files','administrative_source_files','scientific_source_files','extra_administrative_source_files','independent_source_files'}
        and set(CORE_SOURCE_MAPS['source_family_files'])=={'startup','scientific','numerical'}
        and [len(CORE_SOURCE_MAPS['source_family_files'][key]) for key in ['startup','scientific','numerical']]==[14,15,21]
        and [len(CORE_SOURCE_MAPS[key]) for key in ['administrative_source_files','scientific_source_files','extra_administrative_source_files','independent_source_files']]==[3,5,2,4]
        and CORE_SOURCE_MAPS['source_family_files']['startup']==CORE_FILES
        and CORE_SOURCE_MAPS['extra_administrative_source_files']==EXTRA_ADMINISTRATIVE_SOURCE_FILES
        and CORE_SOURCE_MAPS['independent_source_files']==INDEPENDENT_SOURCE_FILES,'complete closed frozen CORE map dimensions')
    c=h.read(h.pin(config_path));pub=h.read(c['publication']);review=h.read(c['source_review']);source=Path(c['source_dir'])
    h.require(pub['commit']==review['source_commit']==CORE_COMMIT and pub['source_files']==review['source_files']==CORE_FILES
        and pub['extra_administrative_source_files']==review['extra_administrative_source_files']==EXTRA_ADMINISTRATIVE_SOURCE_FILES
        and pub['independent_source_files']==review['independent_source_files']==INDEPENDENT_SOURCE_FILES,'closed already-frozen current CORE')
    for mapping in (CORE_FILES,EXTRA_ADMINISTRATIVE_SOURCE_FILES,INDEPENDENT_SOURCE_FILES):
        for name,sha in mapping.items():h.read_pin(dict(path=str(source/name),sha256=sha))
    b=importlib.import_module('pricefm_hb.startup_batch_stop');watch=importlib.import_module('pricefm_hb.node_startup_watch')
    h.require(Path(b.__file__).absolute()==source/'startup_batch_stop.py' and Path(watch.__file__).absolute()==source/'node_startup_watch.py','exact current imports')
    config,scope,site,hashes=b.load_config(config_path);a=h.read(authority_pin);now=time.time();role=a['role']
    dp=h.read(a['driver_publication']);dr=h.read(a['driver_source_review']);own=h.pin(Path(__file__).absolute())
    h.require(dp.get('status')=='PASS_NODE_QUALIFICATION_DRIVER_SOURCE_PUBLICATION'
        and dr.get('status')=='PASS_REVIEWED_NODE_QUALIFICATION_DRIVER_SOURCE'
        and type(dp.get('commit')) is str and re.fullmatch('[0-9a-f]{40}',dp['commit']) and dr.get('source_commit')==dp['commit']
        and dp.get('core_commit')==dr.get('core_commit')==CORE_COMMIT
        and dp.get('core_source_maps')==dr.get('core_source_maps')==CORE_SOURCE_MAPS
        and set(dp.get('source_files',{}))=={'foundation_driver.py','automated_release_driver.py'}
        and dp['source_files']==dr.get('source_files') and dp['source_files']['foundation_driver.py']==own['sha256'],
        'published independently reviewed exact two-driver closure bound to already frozen complete CORE')
    for name,sha in dp['source_files'].items():h.read_pin(dict(path=str(source/name),sha256=sha))
    h.require(os.sched_getaffinity(0)=={31} and a.get('status')=='ROOT_AUTHORIZED_NODE_FOUNDATION_LIFECYCLE'
        and a.get('config')==h.pin(config_path) and a.get('parent_scope')==c['scope']
        and a.get('driver_source')==h.pin(Path(__file__).absolute()) and a.get('role') in b.ROLES
        and a.get('maximum_calls')==1 and type(a['maximum_calls']) is int and a.get('automatic_retry') is False
        and a.get('driver_SELF_CPU_reservation')==10 and a.get('driver_SELF_soft_CPU')==8
        and a.get('peer_phase_CPU_caps')==dict(packet=2,plan=2,release=4)
        and a.get('may_issue_source_bound_root_release') is True
        and scope['issued_epoch']<=a['issued_epoch']<=now<a['expires_epoch']<=scope['expires_epoch'],'complete one-shot source-bound driver authority')
    h.require(a['original_supervisor']['sha256']==H_SHA and a['peer_program']['sha256']==INDEPENDENT_SOURCE_FILES['independent_foundation_release_peer.py'],'original H and independently authored current peer')
    h.read_pin(a['original_supervisor']);h.read_pin(a['peer_program'])
    root=Path(c['registry'])/role;out=Path(c['startup_watch_roots'][role])
    h.require(b.records(root)[-1]['state']=='STAGED' and not (root/'JOB.json').exists() and not out.exists(),'fresh staged role and private one-shot driver root')
    out.mkdir(mode=0o700);h.write_new(out/'INTENT.json',dict(status='STARTED_NODE_FOUNDATION_LIFECYCLE_NOT_SUCCESS',config=h.pin(config_path),authority=authority_pin,no_retry=True))
    python=str(Path(sys.executable).resolve(strict=True));source_parent=str(source.parent)
    command='import sys;sys.path.insert(0,'+repr(source_parent)+');from pricefm_hb import startup_batch_stop;startup_batch_stop.main()'
    def native(action,previous,bundle=None):
        limits=b.action_limits(action);stdout=out/(action+'.guard.json');stderr=out/(action+'.guard.stderr')
        argv=[python,'-I','-B',a['original_supervisor']['path'],'--cpu',str(limits['local_CPU']),'--wall',str(limits['wall']),'--output-cap','8388608','--',
            python,'-I','-B','-c',command,action,'--config',config_path,'--role',role,'--previous-guard',previous['path']]
        if bundle is not None:argv+=['--bundle',str(bundle)]
        with stdout.open('xb') as so,stderr.open('xb') as se:
            child=subprocess.Popen(argv,stdout=so,stderr=se,preexec_fn=lambda:None);code=child.wait()
            so.flush();os.fsync(so.fileno());se.flush();os.fsync(se.fileno())
        h.require(code==0,'native guardian failed; retain all raw receipts and exact failed-action drain path')
        g=h.read(h.pin(stdout));b.passing_guard(g,limits['local_CPU'],limits['wall'])
        return h.pin(stdout)
    def peer(phase,guard,bundle):
        cap=dict(packet=2,plan=2,release=4)[phase]
        def bounds():
            resource.setrlimit(resource.RLIMIT_CPU,(cap,cap));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(30)
        argv=[python,'-I','-B',a['peer_program']['path'],'--config',config_path,'--role',role,'--guard',guard['path'],
            '--scope',a['peer_scope']['path'],'--bundle',str(bundle),'--phase',phase,'--packet-review',a['packet_review']['path']]
        with (out/(phase+'.peer.stdout')).open('xb') as so,(out/(phase+'.peer.stderr')).open('xb') as se:
            code=subprocess.Popen(argv,stdout=so,stderr=se,preexec_fn=bounds).wait()
        h.require(code==0,'independent foundation peer rejected; no root success inferred from an exit alone')
    try:
        submit=native('submit',a['actual_stage_guard'])
        try:startup=watch.wait(config_path,role,'startup',a['startup_watch_authority'])
        except BaseException as error:
            cancel=None;cancel_error=None
            try:cancel=native('cancel',submit)
            except BaseException as err:cancel_error=type(err).__name__+': '+str(err)
            job=h.read(h.pin(root/'JOB.json'))
            h.write_new(out/'STARTUP_FAILED.json',dict(status='STARTUP_FAILED_NO_RELEASE' if cancel else 'FAILED_STARTUP_CANCEL_UNKNOWN_ROLE_QUARANTINED',
                job_id=job['job_id'],role=role,
                error=type(error).__name__+': '+str(error),cancel_guard=cancel,cancel_error=cancel_error,no_retry=True,no_release=True,all_reserved_fees_retained=True))
            h.write_new(root/'ROLE_FAILED_SPENT.json',dict(status='ROLE_FAILED_SPENT',job_id=job['job_id'],role=role,no_release=True,
                failed_startup=h.pin(out/'STARTUP_FAILED.json'),old_fees_retained=True));raise
        ready_guard=native('ready',submit);ready=h.read(h.pin(root/'READY.json'))
        h.require(h.pin(root/'READY.json')['sha256']==startup['ready']['sha256'] and 0<=time.time()-ready['observed_epoch']<180,'same physical READY and unchanged300 worker window')
        bundle=out/'release';b.prepare_foundation_release(config_path,bundle,role)
        if role==b.ROLES[1]:
            child=h.read(h.pin(bundle/'R_CHILD_SCOPE_TEMPLATE.json'));h.require(child.pop('required_issued_status')=='PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE','actual bounded R-child template')
            child.update(status='PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE',issued_epoch=time.time(),root_driver_authority=authority_pin)
            h.write_new(bundle/'R_CHILD_SCOPE.json',child);peer('plan',ready_guard,bundle)
            r=h.read(h.pin(bundle/'R_REVIEW.json'));h.require(r.get('status')=='PASS_REVIEWED_STARTUP_HELPER_SOURCE_AND_PLAN','actual independent R plan review')
            value=h.read(h.pin(bundle/'R_AUTHORITY_TEMPLATE.json'));value['status']=value.pop('required_status')
            remote=b.packet(root)['remote_root']+'/release/';value.update(issued_epoch=time.time(),root_scope=dict(path=remote+'R_CHILD_SCOPE.json',sha256=b.digest(bundle/'R_CHILD_SCOPE.json')),
                source_review=dict(path=remote+'R_REVIEW.json',sha256=b.digest(bundle/'R_REVIEW.json')),root_driver_authority=authority_pin)
            h.write_new(bundle/'R_AUTHORITY.json',value)
        peer('release',ready_guard,bundle);proposal=b.foundation_release_proposal(config_path,bundle,role)
        proposal['status']=proposal.pop('required_status');proposal.update(issued_epoch=time.time(),root_driver_authority=authority_pin)
        h.require(0<=time.time()-ready['observed_epoch']<180,'foundation source/reviewer chain consumed unchanged READY freshness')
        h.write_new(bundle/'RELEASE.json',proposal);release=native('release',ready_guard,bundle)
        result=dict(status='NATIVE_FOUNDATION_ROOT_RELEASE_ISSUED_AWAIT_COMPUTE_NOT_ACCEPTED',role=role,job=h.pin(root/'JOB.json'),
            startup_watch=h.pin(out/'STARTUP_WATCH.json'),submit_guard=submit,ready_guard=ready_guard,release_guard=release,
            root_release=h.pin(bundle/'RELEASE.json'),no_runtime_success_preclaimed=True,old_fees_retained=True)
        h.write_new(out/'RESULT.json',result);return result
    except BaseException as error:
        h.write_new(out/'FAILED.json',dict(status='FAILED_FOUNDATION_DRIVER_ROLE_AND_FEES_RETAINED_NO_RETRY',error=type(error).__name__+': '+str(error),authority=authority_pin));raise

def main():
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--authority',required=True);p.add_argument('--authority-sha256',required=True);a=p.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU,(8,136));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(1200)
    print(json.dumps(run(a.config,dict(path=a.authority,sha256=a.authority_sha256)),sort_keys=True))

if __name__=='__main__':main()
