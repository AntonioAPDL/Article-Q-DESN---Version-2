"""Actual initial qualification boundary; never a production data capability."""
import datetime, hashlib, importlib.util, os, re, time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
_CP=ROOT/'qualification/qualification_contract.py'
# Before supplied data, this fixed sibling is source only; actual closure is verified below.
_raw=_CP.read_bytes()
if any(v.is_symlink() for v in (_CP,*_CP.parents)) or hashlib.sha256(_raw).hexdigest()!='39a53e52b4c1ebafe076d59b8e509e94f1b5a02706ef1710637654aa0a74ec75':
    raise ValueError('fixed authenticated qualification contract before interpretation')
_sp=importlib.util.spec_from_file_location('_r201_qualification_contract',_CP)
c=importlib.util.module_from_spec(_sp);exec(compile(_raw,str(_CP),'exec'),c.__dict__)
m=c.m
_SEAL=object()
def load_fixed(review,name):
    pin=review['source_pins'].get(name)
    m.require(pin is not None and pin['path']==str(ROOT/name),'fixed source member '+name)
    raw=m.source_bytes(pin);sp=importlib.util.spec_from_file_location('_r201_fixed_'+name.replace('/','_'),pin['path'])
    mod=importlib.util.module_from_spec(sp)
    import sys
    sys.modules[sp.name]=mod;exec(compile(raw,pin['path'],'exec'),mod.__dict__)
    return mod
def job_before_records():
    job=os.environ.get('SLURM_JOB_ID','');node=os.uname().nodename.split('.')[0]
    m.require(re.fullmatch('[1-9][0-9]{0,11}',job or '') and os.environ.get('SLURMD_NODENAME')==node
      and re.fullmatch('node-[0-9]{2}',node),'actual Slurm compute job before supplied records')
    m.require(re.search(r'(?:^|/)job_'+re.escape(job)+r'(?:/|$)',Path('/proc/self/cgroup').read_text(),re.M),
      'actual kernel Slurm job cgroup')
    m.require(os.environ.get('SLURM_CPUS_PER_TASK')=='1' and os.environ.get('TZ')=='UTC'
      and all(os.environ.get(k)=='1' for k in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS',
      'VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS','BLIS_NUM_THREADS')),'one-thread actual job')
    return job,node
def peer_program_metadata(main_program_pin,installed_program_pin):
    """Identical reviewed peer bytes may have different Main/compute host paths."""
    m.descriptor(main_program_pin);m.descriptor(installed_program_pin)
    m.require(main_program_pin['sha256']==installed_program_pin['sha256'],
      'exact approved independently reviewed peer source identity across hosts')
    return dict(status='CONSISTENT_PEER_PROGRAM_METADATA_ONLY',runtime_admitted=False,
                main_program=main_program_pin,installed_program=installed_program_pin)
def source_review(spec,spec_pin,review_pin):
    r=m.linked(review_pin);c.same(r,spec)
    peer_program_metadata(r.get('independent_program'),spec['source_pins']['qualification/qualification_peer.py'])
    m.require(r.get('schema')=='r201_qualification_source_review_v1'
      and r.get('status')=='PASS_REVIEWED_R201_QUALIFICATION_SOURCE_PHYSICAL'
      and r.get('spec')==spec_pin and r.get('source_pins')==spec['source_pins']
      and r.get('source_map_sha256')==spec['source_map_sha256']
      and r.get('source_publication')==spec['source_publication']
      and r.get('controller_source')==spec['source_publication']
      and r.get('runtime_admitted') is False,
      'actual independent source phase, not Root release')
    for name,pin in spec['source_pins'].items():
        m.require(pin['path']==str(ROOT/name),'same installed source root')
        m.source_bytes(pin)
    return r
def verify_readonly_runtime(spec,launch):
    paths=[p['path'] for p in spec['source_pins'].values()]+[p['path'] for p in launch['baseline_files']]
    paths += [launch[k]['path'] for k in ('bootstrap','native_executable','native_library','traced_guard','native_abi')]
    if spec['role']=='LT_NO4_REFERENCE':paths += [p['path'] for p in spec['scientific_sources'].values()]
    mounts=[]
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        fields=line.split();sep=fields.index('-')
        point=Path(fields[4].replace('\\040',' ').replace('\\134','\\'))
        mounts.append((point,set(fields[5].split(',')),set(fields[sep+3].split(','))))
    for text in paths:
        path=m.physical(text);cover=[r for r in mounts if path==r[0] or path.is_relative_to(r[0])]
        m.require(cover,'runtime has actual mount')
        point,options,superopts=max(cover,key=lambda r:len(r[0].parts))
        m.require('ro' in options and 'ro' in superopts,'read-only backing superblock, no writable alias bind')
def _base(review):return load_fixed(review,'owner/compute_boundary.py')
def _authority(spec,spec_pin,authority_pin,review_pin):
    a=m.linked(authority_pin);m.closed(a,c.AUTHORITY_KEYS,'initial Root authority');c.same(a,spec)
    m.require(a['schema']=='r201_qualification_authority_v1'
      and a['status']=='ROOT_ADMITTED_R201_INITIAL_NATIVE_REFERENCE_QUALIFICATION'
      and a['spec']==spec_pin and a['source_review']==review_pin,'separate actual initial authority')
    for k in ('case_sha256','source_map_sha256','source_publication','scope','ledger','quote','build_acceptance','deployment_acceptance'):
        m.require(a[k]==spec[k],'same authority '+k)
    for k,v in [('maximum_calls',1),('optimizer_invocations',0),('new_posterior_fits',0)]:
        m.require(type(a[k]) is int and a[k]==v,'initial-only '+k)
    for record in (spec,a):
        for k in ('issued_epoch','expires_epoch'):m.finite(record[k],k)
    now=time.time()
    m.require(spec['issued_epoch']<=a['issued_epoch']<=now<a['expires_epoch']<=spec['expires_epoch'],
      'current finite actual qualification authority')
    return a
def ready_clock_metadata(ready,peer,source,authority,*,launched_at=None,now=None):
    """Check a launch lease or its historical earned entry; never grants execution."""
    now=time.time() if now is None else now
    m.finite(now,'current metadata clock')
    for v in (ready,peer,source,authority):
        for k in (('created_epoch','expires_epoch') if v is ready else ('issued_epoch','expires_epoch')):
            m.finite(v.get(k),k)
    m.require(ready['created_epoch']<ready['expires_epoch']<=ready['created_epoch']+120,
      'one original READY120 interval')
    t=now if launched_at is None else launched_at
    m.finite(t,'actual launch or historical ACK clock')
    m.require(source['issued_epoch']<=peer['issued_epoch']<=authority['issued_epoch']<=t
      and t<source['expires_epoch'] and t<peer['expires_epoch']
      and ready['created_epoch']<=t<ready['expires_epoch'] and t<=now<authority['expires_epoch'],
      'entry was inside all original leases and full runtime authority remains current')
    return dict(status='CONSISTENT_LAUNCH_CLOCK_METADATA_ONLY',runtime_admitted=False,lease_renewed=False)

def _ready(spec,authority,review_pin,base,launched_at=None):
    peer=m.linked(authority['owner_review']);c.same(peer,spec)
    m.require(peer.get('status')=='PASS_REVIEWED_R201_QUALIFICATION_OWNER_RELEASE'
      and peer.get('spec')==spec['_spec_pin'] and peer.get('source_review')==review_pin
      and peer.get('source_map_sha256')==spec['source_map_sha256']
      and peer.get('independent_program')==m.linked(review_pin).get('independent_program'),
      'actual distinct independent owner release from same reviewed Main peer')
    ready=m.linked(peer['owner_ready'])
    m.require(ready.get('schema')=='r201_qualification_ready_v1'
      and ready.get('status')=='READY_R201_INITIAL_QUALIFICATION_AWAIT_ROOT_NO_PAYLOAD'
      and ready.get('owner')==spec['owner'] and ready.get('job_id')==spec['job_id']
      and ready.get('node')==spec['node'] and ready.get('resource_lock_fd')==spec['resource_lock_fd']
      and ready.get('resource_lock_path')==spec['resource_lock_path']
      and ready.get('physical_admission')==peer.get('physical_admission'),'actual same READY lifetime')
    m.finite(ready.get('created_epoch'),'READY clock');m.finite(ready.get('expires_epoch'),'READY expiry')
    ready_clock_metadata(ready,peer,m.linked(review_pin),authority,launched_at=launched_at)
    for k in ('scope','ledger','quote','build_acceptance','deployment_acceptance','source_publication'):
        m.require(ready.get(k)==spec[k],'READY binds '+k)
    return ready
def validate_prelaunch(spec_pin,authority_pin,review_pin):
    job,node=job_before_records()
    raw=m.linked(spec_pin);c.inspect_spec_metadata(raw);spec=dict(raw,_spec_pin=spec_pin)
    m.require((spec['job_id'],spec['node'],spec['uid'])==(job,node,os.getuid())
      and os.sched_getaffinity(0)==set(spec['affinity']),'actual same job/core/UID')
    review=source_review(spec,spec_pin,review_pin);base=_base(review)
    parent=base._proc(os.getpid())
    m.require(spec['owner']==dict(pid=os.getpid(),start_ticks=parent['start_ticks'],
      boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip()) and parent['TracerPid']==0,
      'direct Slurm same-PID READY owner, outside admin H')
    authority=_authority(spec,spec_pin,authority_pin,review_pin)
    quote=c.quote_and_funding(spec);base._whole_ledger_provenance(spec)
    _ready(spec,authority,review_pin,base)
    launch=m.linked(spec['owner_launch']);c.validate_native_prerequisites(spec,launch,review)
    m.require(launch['bootstrap']==review['source_pins']['native_python/python_bootstrap.py']
      and launch['traced_guard']['sha256']=='914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963',
      'fixed new bootstrap and unchanged original tracer')
    m.require(launch['native_executable'] in launch['baseline_files']
      and launch['native_library'] in launch['baseline_files']
      and launch['traced_guard'] in launch['baseline_files']
      and launch['native_executable']['path']==str(Path('/proc/self/exe').resolve(strict=True)),
      'current exact Python and complete immutable native baseline')
    for pin in launch['baseline_files']:
        m.descriptor(pin);m.read_regular(pin['path'],limit=64*1024**2,expected_sha=pin['sha256'],expected_uid=os.getuid())
    for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS','BLIS_NUM_THREADS'):
        m.require(launch['environment'].get(key)=='1','one-thread child '+key)
    m.require(launch['environment'].get('SLURM_JOB_ID')==job
      and launch['environment'].get('SLURMD_NODENAME')==node and launch['environment'].get('TZ')=='UTC'
      and 'LD_PRELOAD' not in launch['environment'] and 'PYTHONPATH' not in launch['environment'],'closed child environment')
    m.require(time.time()+quote['whole_wall_seconds']<authority['expires_epoch'],'whole prospective interval fits')
    verify_readonly_runtime(spec,launch)
    oldowner=load_fixed(review,'owner/pilot_compute_owner.py')
    physical=oldowner._kernel_physical(spec,quote,initial_reservation=True)
    # Existing held permit; do not acquire a substitute lock.
    fd=spec['resource_lock_fd'];a=os.fstat(fd);b=m.physical(spec['resource_lock_path']).stat()
    m.require(a.st_uid==os.getuid() and (a.st_dev,a.st_ino)==(b.st_dev,b.st_ino)
      and 'FLOCK' in Path('/proc/self/fdinfo/'+str(fd)).read_text()
      and 'WRITE' in Path('/proc/self/fdinfo/'+str(fd)).read_text(),'actual inherited owner permit')
    return spec,authority,review,quote,launch,physical
class QualificationContext:
    __slots__=('_spec','_authority','_review','_native','_pins','_seal')
    def __init__(self,s,a,r,native,pins,seal):
        m.require(seal is _SEAL,'private actual qualification context')
        self._spec,self._authority,self._review,self._native,self._pins,self._seal=s,a,r,native,pins,seal
    def verify_live(self):
        m.require(self._seal is _SEAL,'real initial context')
        job_before_records();s=self._spec;a=self._authority
        m.require(a['issued_epoch']<=time.time()<a['expires_epoch']<=s['expires_epoch'],'live qualification only')
        for pin in self._pins:m.require(m.pin_file(pin['path'])==pin,'unchanged actual qualification proof')
        self._native.verify_live()
        return dict(role=c.ROLE,job_id=s['job_id'],node=s['node'],optimizer_invocations=0,production_admission=False)
def acquire(spec_pin,authority_pin,review_pin,ack_pin):
    job,node=job_before_records()
    raw=m.linked(spec_pin);c.inspect_spec_metadata(raw);spec=dict(raw,_spec_pin=spec_pin)
    authority=_authority(spec,spec_pin,authority_pin,review_pin);review=source_review(spec,spec_pin,review_pin)
    base=_base(review);ack=m.linked(ack_pin)
    m.require(ack_pin['path']==spec['acknowledgement_path'],'fixed actual preACK gate path')
    m.closed(ack,base.ACK_KEYS,'actual parent parse gate');c.same(ack,spec)
    m.require(ack['schema']=='r200_parent_parse_gate_v1'
      and ack['status']=='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK' and ack['spec']==spec_pin
      and ack['authority']==authority_pin and ack['source_review']==review_pin
      and ack['uid']==spec['uid'] and ack['kernel_ACK_requires_real_boundary_call'] is True,'parent gate is not kernel ACK')
    frame=m.closed(ack['frame'],base.FRAME_KEYS,'fixed parse frame');c.same(frame,spec)
    m.require(frame['status']=='R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT'
      and frame['source_pins']==ack['source_pins']==spec['source_pins']
      and type(frame['optimizer_invocations']) is int and frame['optimizer_invocations']==0
      and frame['scientific_target_data_read'] is False,'source-only parse phase')
    base._identity(spec,ack)
    claim_pin=m.pin_file(spec['attempt_claim_path']);claim=m.linked(claim_pin);c.same(claim,spec)
    m.require(claim.get('schema')=='r200_compute_attempt_claim_v1'
      and claim.get('status')=='SPENT_CURRENT_OWNER_ATTEMPT_NO_RETRY'
      and claim.get('spec')==spec_pin and claim.get('authority')==authority_pin
      and claim.get('owner')==spec['owner'],'spent actual initial-only owner attempt')
    c.quote_and_funding(spec);base._whole_ledger_provenance(spec);_ready(spec,authority,review_pin,base,launched_at=ack['created_epoch'])
    launch=m.linked(spec['owner_launch']);c.validate_native_prerequisites(spec,launch,review);verify_readonly_runtime(spec,launch)
    native=load_fixed(review,'native_python/native_contract.py').reacquire(spec_pin,review_pin)
    native.verify_live()
    proofs=[spec_pin,authority_pin,review_pin,ack_pin,claim_pin]+[spec[k] for k in ('quote','scope','ledger','build_acceptance','deployment_acceptance','source_publication','owner_launch')]
    ctx=QualificationContext(spec,authority,review,native,proofs,_SEAL)
    ctx.verify_live();return ctx
