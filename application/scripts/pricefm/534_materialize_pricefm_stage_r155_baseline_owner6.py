#!/usr/bin/env python3
"""Materialize four live authority slots and activate owner6 once, when admitted.

Only stdlib is imported before exact source/interpreter/template/review pins.
Preparation clocks are historical receipts. Actual execution uses its prepaid30
CPU reserve inside the original baseline ceiling and original absolute expiry.
"""
import argparse,copy,hashlib,importlib,importlib.util,json,math,os,resource,signal,subprocess,sys,time
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3]
AUDIT=ROOT.parents[1]/'pricefm_chat_continuation_20261021/r155_screening_recovery_20261027/baseline_control_owner6'
ORIGINAL_EXPIRY=1793575052.3571737
ORIGINAL_START=1792970252.3571737
CPU_RESERVE=30.
PY='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
PY_SHA='695bf83254bba94ab3b2a9d00c94b9316e483965b006936b076916f0a85a9ae5'
LIVE_KEYS={'status','source_review','activation_epoch','unit_runtime_max_seconds'}


def require(value,message):
    if not value:raise RuntimeError(message)


def pin(path):
    path=Path(path);h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return dict(path=str(path),sha256=h.hexdigest())


def read_pin(value):
    path=Path(value['path']);require(path.is_absolute() and not path.is_symlink() and path.resolve()==path,'noncanonical pin')
    require(pin(path)==value,'pinned input changed: '+str(path));return json.loads(path.read_text())


def usage():
    own=resource.getrusage(resource.RUSAGE_SELF);child=resource.getrusage(resource.RUSAGE_CHILDREN)
    return dict(own_CPU=own.ru_utime+own.ru_stime,reaped_administrative_CPU=child.ru_utime+child.ru_stime,
        whole_invocation_own_plus_reaped_CPU=own.ru_utime+own.ru_stime+child.ru_utime+child.ru_stime)


def checkpoint():
    value=usage();require(value['whole_invocation_own_plus_reaped_CPU']+2<CPU_RESERVE,'prepaid30CPU reserve lacks drain headroom')
    cap=math.floor(CPU_RESERVE-value['reaped_administrative_CPU']);old=resource.getrlimit(resource.RLIMIT_CPU)[1]
    if old!=resource.RLIM_INFINITY:cap=min(cap,old)
    require(value['own_CPU']+2<cap,'remaining absolute materializer CPU cap insufficient')
    resource.setrlimit(resource.RLIMIT_CPU,(cap,cap));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    require(time.time()+300<ORIGINAL_EXPIRY,'original baseline absolute expiry has no activation margin');return value


def lifetime():
    raw=Path('/proc/self/stat').read_text();parts=raw[raw.rfind(')')+2:].split();cmd=Path('/proc/self/cmdline').read_bytes()
    return dict(pid=os.getpid(),start_ticks=int(parts[19]),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        cmdline_sha256=hashlib.sha256(cmd).hexdigest(),argv=[v.decode(errors='replace') for v in cmd.split(b'\0') if v],
        executable=os.readlink('/proc/self/exe'),cwd=os.readlink('/proc/self/cwd'),uid=os.getuid(),cpus=sorted(os.sched_getaffinity(0)))


def atomic_create(path,value):
    path=Path(path);require(path.is_absolute() and not path.is_symlink() and path.resolve()==path and not path.exists(),'create-only canonical output already used')
    raw=(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
    temporary=path.with_name('.'+path.name+'.'+str(os.getpid())+'.'+os.urandom(8).hex()+'.tmp')
    try:
        fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
        os.link(temporary,path);fd=os.open(path.parent,os.O_RDONLY)
        try:os.fsync(fd)
        finally:os.close(fd)
    finally:temporary.unlink(missing_ok=True)


def changed_keys(before,after):return {key for key in set(before)|set(after) if before.get(key)!=after.get(key)}


def materialized(template,review,epoch):
    require(template['status']=='PROPOSED' and template['grant']['starts_epoch']==ORIGINAL_START
        and template['grant']['expires_epoch']==ORIGINAL_EXPIRY and template['grant']['control_CPU_seconds']==28800
        and template['grant']['prior_control_CPU_seconds']==5621.924971277
        and template['guardian_CPU_reserve']==600 and template['preparation_CPU_debit']==200
        and template['activation_wrapper_CPU_reserve']==30,'reviewed owner6 funding/clock template differs')
    result=copy.deepcopy(template);result.update(status='ADMITTED',source_review=review,activation_epoch=epoch,
        unit_runtime_max_seconds=math.floor(ORIGINAL_EXPIRY-epoch-300))
    require(result['unit_runtime_max_seconds']>0 and changed_keys(template,result).issubset(LIVE_KEYS),'authority changed outside four live slots')
    return result


def verify_code(plan):
    source=plan['execution_source'];require(Path(source['root'])==ROOT
        and source['branch']=='work/pricefm-r155-baseline-owner6-20261027','wrong owner6 checkout/branch')
    for relative,sha in source['runtime_sha256'].items():
        path=ROOT/relative;require(path.resolve()==path and path.is_relative_to(ROOT) and pin(path)['sha256']==sha,'owner6 executable changed')
    for path,sha in plan['dependency_sha256'].items():require(pin(path)['sha256']==sha,'frozen dependency changed')
    def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,timeout=20).strip()
    require(git('rev-parse','HEAD')==source['head'] and git('branch','--show-current')==source['branch']
        and not git('status','--porcelain'),'owner6 checkout is not the exact clean reviewed head')


def execute(path,sha):
    now=time.time();duration=min(600.,ORIGINAL_EXPIRY-now-1);require(duration>0,'original deadline expired')
    def expired(signum,frame):raise TimeoutError('owner6 self-only materializer wall timer expired')
    signal.signal(signal.SIGALRM,expired);signal.setitimer(signal.ITIMER_REAL,duration)
    wall=dict(maximum_wall_seconds=duration,absolute_wall_deadline=now+duration,self_process_only=True)
    checkpoint();require(os.sched_getaffinity(0)=={31} and sys.flags.dont_write_bytecode,'pinned-B administrative31 required')
    plan=read_pin(dict(path=str(Path(path).resolve()),sha256=sha))
    require(plan.get('schema')=='r155_baseline_owner6_materialize_plan_v1' and plan.get('status')=='ROOT_ADMITTED_ONCE'
        and plan.get('maximum_actual_invocations')==1 and plan.get('automatic_retry') is False,'root once-only owner6 plan absent')
    require(plan['actual_activation_CPU_reserve']==30 and plan['actual_activation_expiry']==ORIGINAL_EXPIRY,'actual execution funding/clock differs')
    require(pin(Path(__file__).resolve())==plan['materializer'] and plan['interpreter']==dict(path=PY,sha256=PY_SHA)
        and pin(PY)['sha256']==PY_SHA and Path(sys.executable).resolve()==Path(PY).resolve(),'materializer/interpreter pin differs')
    require(os.getuid()==269188 and os.readlink('/proc/self/ns/pid')=='pid:[4026531836]'
        and Path('/proc/sys/kernel/random/boot_id').read_text().strip()=='37b80e3b-9596-4c75-85e1-aca85af8fa7f'
        and sum(p.name.isdigit() for p in Path('/proc').iterdir())>=100,'actual host view/boot/UID not established')
    template=read_pin(plan['authority_template']);prep=read_pin(template['preparation'])
    allowance=read_pin(plan['metadata_preparation_allowance']);closeout=read_pin(plan['metadata_preparation_closeout'])
    require(allowance['total_CPU_allowance']==200 and closeout['preparation_complete'] is True
        and closeout['conservative_preparation_CPU']<=200 and closeout['completed_epoch']<=allowance['expires_epoch'],
        'owner6 preparation not completed in its funded clock')
    require(prep['source_preparation_allowance']==plan['metadata_preparation_allowance']
        and closeout['allowance']==plan['metadata_preparation_allowance'],'preparation allowance/closeout provenance differs')
    require(template['execution_source']==plan['execution_source'] and prep['execution_source']==plan['execution_source']
        and plan['dependency_sha256']==prep['dependency_sha256'],'transitive source/preparation coverage differs')
    review=read_pin(plan['runtime_source_review'])
    require(str(review.get('status','')).startswith('PASS') and review.get('administrative_runtime_review') is True
        and review['execution_source']==plan['execution_source'] and review['materializer']==plan['materializer']
        and review['authority_template']==plan['authority_template'] and review['paid_scope_ledger']==template['paid_scope_ledger'],
        'distinct complete owner6 runtime/materializer/template/funding review absent')
    target=Path(plan['target_authority']);require(target==AUDIT/'ROOT_BASELINE_OWNER6_AUTHORITY_ADMITTED_01.json'
        and target==Path(template['control_intent']['argv'][5])==Path(template['guardian_intent']['argv'][5])
        and not target.exists(),'fixed fresh owner6 authority target differs or exists')
    verify_code(plan);checkpoint();marker=Path(plan['execution_claim']);result_path=Path(plan['execution_receipt'])
    require(marker==AUDIT/'OWNER6_MATERIALIZER_CLAIM_01.json' and result_path==AUDIT/'OWNER6_MATERIALIZER_RECEIPT_01.json'
        and not marker.exists() and not result_path.exists(),'owner6 materializer attempt already spent; no retry')
    atomic_create(marker,dict(schema='r155_owner6_materializer_claim_v1',plan=dict(path=str(path),sha256=sha),source=plan['materializer'],
        process=lifetime(),wall_timer=wall,CPU_reserve=30,automatic_retry=False,epoch=time.time()))
    try:
        sys.path.insert(0,str(ROOT/'application/scripts/pricefm'));c=importlib.import_module('pricefm_r155_baseline_contract')
        spec=importlib.util.spec_from_file_location('r155_actual_owner6_activation',ROOT/'application/scripts/pricefm/532_activate_pricefm_stage_r155_baseline_continuation.py')
        api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
        require(Path(c.__spec__.origin)==ROOT/'application/scripts/pricefm/pricefm_r155_baseline_contract.py'
            and Path(api.__spec__.origin)==ROOT/'application/scripts/pricefm/532_activate_pricefm_stage_r155_baseline_continuation.py'
            and api.c is c and not any(k in sys.modules for k in ('numpy','scipy','pandas')),'actual module origin/numerical import differs')
        verify_code(plan);c.verify_source(plan['execution_source'],remote=True)
        c.check_pins(prep['dependency_sha256']);c.check_pins(prep['predecessor_runtime_sha256']);c.check_pins(prep['spent_owner5_runtime_sha256'])
        system=c.System(template['expected_host_pid_namespace']);prior=c.verify_predecessor(template,system,require_full_census=True)
        c.verify_original_locks(template,require_free=True);config=c.core().read_config(prior['authority']['legacy_config_path'])
        policy=c.old.ContractPolicy(config,system)
        for job in prior['state']['active'].values():c.old.session_members(copy.deepcopy(job),system,policy,census=prior['census'])
        policy.verify_sources();require(c.core().host_health(config)['healthy'],'original host resource floor failed')
        require(not (Path(template['runtime'])/'activation_claim.json').exists(),'owner6 service activation already spent')
        checkpoint();epoch=time.time();authority=materialized(template,plan['runtime_source_review'],epoch)
        atomic_create(target,authority);authority_pin=pin(target);checkpoint()
        require(c.validate_authority(target,authority_pin['sha256'],unclaimed=True)==authority,'fresh admitted authority bytes differ')
        activation=api.activate(target,authority_pin['sha256'])
        receipt=dict(schema='r155_owner6_materializer_receipt_v1',status='MATERIALIZED_'+activation['status'],authority=authority_pin,
            activation_result=activation,immediate_533_proof=activation.get('immediate_proof'),changed_live_keys=sorted(changed_keys(template,authority)),
            actual_activation_epoch=epoch,whole_invocation_usage=usage(),materializer_process=lifetime(),wall_timer=wall,
            healthy_control=activation.get('healthy_control'),dispatch_currently_permitted=activation.get('dispatch_currently_permitted') is True,
            preparation_clocks_historical_not_renewed=True,foreign_process_signals=0,automatic_retry=False,epoch=time.time())
        atomic_create(result_path,receipt);return receipt
    except BaseException as error:
        receipt=dict(schema='r155_owner6_materializer_receipt_v1',status='FAILED_ONCE_NO_RETRY',error=repr(error),
            actual_authority=pin(target) if target.exists() else None,materializer_process=lifetime(),wall_timer=wall,
            whole_invocation_usage=usage(),foreign_process_signals=0,automatic_retry=False,epoch=time.time())
        if hasattr(error,'observation'):receipt['observation']=error.observation
        if not result_path.exists():atomic_create(result_path,receipt)
        raise


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--plan',required=True);p.add_argument('--plan-sha256',required=True);a=p.parse_args()
    try:
        result=execute(a.plan,a.plan_sha256);print(json.dumps(result,indent=2,sort_keys=True,allow_nan=False))
    except BaseException as error:
        print(json.dumps(dict(status='OWNER6_MATERIALIZER_REFUSED_OR_FAILED_NO_RETRY',error=repr(error),whole_invocation_usage=usage()),sort_keys=True),file=sys.stderr);raise
    finally:signal.setitimer(signal.ITIMER_REAL,0.)
