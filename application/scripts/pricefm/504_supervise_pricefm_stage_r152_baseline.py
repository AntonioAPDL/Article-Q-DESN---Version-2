#!/usr/bin/env python3
"""Resource-only Muscat successor for the audited, drained AT+LT boundary.

The numerical producer is the immutable R141 controller. This parent never
signals numerical workers, resumes R145, changes a certificate, or repairs a
fit. Its new source owns only explicit resource/lifecycle provenance.
"""
from __future__ import annotations

import argparse
import contextlib
import csv
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import uuid
import re

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT/'application/config/pricefm_stage_r152_baseline_20261024.json'
DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
SHARED = DATA/'launch_prep/pricefm_stage_r152_parallel_20261024'
A_QUEUE = ['IT_CALA','IT_SICI','NL','NO_4','RO','SE_4']
B_QUEUE = ['NO_2','PL','SE_2']
PROPERTIES = ['Id','LoadState','MainPID','ActiveState','SubState','Result','InvocationID',
    'ControlGroup','KillMode','Restart','WorkingDirectory','ExecStart','NRestarts']
TERMINAL_PHASES = {'complete','blocked','precommit_aborted'}
THREAD_ENV = ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS',
    'NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS','BLIS_NUM_THREADS')


def guardian_name(attempt,owner_pid=None):
    return 'pricefm-r152-baseline-guardian-'+attempt[:16]+'-'+str(os.getpid() if owner_pid is None else owner_pid)+'.service'


def read(path): return json.loads(Path(path).read_text())


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''): h.update(block)
    return h.hexdigest()


def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with temporary.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary,path)


def immutable(path, value):
    path = Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    encoded = (json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
    if path.exists():
        if path.read_bytes()!=encoded: raise RuntimeError('immutable receipt differs: '+str(path))
        return
    temporary = path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with temporary.open('xb') as stream:
        stream.write(encoded); stream.flush(); os.fsync(stream.fileno())
    try: os.link(temporary,path)
    finally: temporary.unlink(missing_ok=True)


def read_config(path=CONFIG):
    value=read(path); validate_config(value); return value


def validate_config(config):
    expected = (config['queues']=={'A':A_QUEUE,'B':B_QUEUE}
        and config['partition']=={'baseline_A':list(range(15)),
            'baseline_B':list(range(15,24)),'development_base':list(range(24,30)),
            'optional':[22,23]}
        and config['scope_seconds']==43200 and config['quarantined_regions']==['AT','LT']
        and config['source_head']=='4cd92ac3654f16a84a67c8db6cfc7f381113aeb9'
        and config['old_attempt']=='e6226e1ddefd4c36ae17324684d40d22'
        and config['fit_max_iter']==300 and not config['repair_fits_authorized']
        and not config['signal_numerical_workers'] and not config['resume_old_R145'])
    if not expected: raise RuntimeError('configuration differs from bounded R152 recovery')
    sets=[set(config['partition'][key]) for key in ('baseline_A','baseline_B','development_base')]
    if sum(map(len,sets))!=30 or len(set.union(*sets))!=30:
        raise RuntimeError('mandatory partitions overlap or lose physical slots')
    if not 1<=config['max_owner_generations']<=3:
        raise RuntimeError('unbounded owner recovery is forbidden')
    if not re.fullmatch(r'pricefm-r152-muscat-baseline(?:-[a-f0-9]{12,32})?\.service',config['new_unit']):
        raise RuntimeError('unexpected successor unit')


def source_identity(config):
    def git(*args): return subprocess.check_output(['git','-C',str(ROOT),*args],text=True).strip()
    value={'root':str(ROOT),'head':git('rev-parse','HEAD'),'branch':git('branch','--show-current')}
    if value['branch']!=config['required_branch'] or git('status','--porcelain'):
        raise RuntimeError('clean committed R152 resource source required')
    return value


def verify_pins(pins):
    for name,expected in pins.items():
        if sha(name)!=expected: raise RuntimeError('frozen source/evidence changed: '+name)


class System:
    """Small actual-host interface, replaceable in focused fault tests."""
    def __init__(self): self.boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    def host(self): return socket.gethostname().split('.')[0].lower()
    def process(self,pid):
        if not int(pid): return None
        path=Path('/proc')/str(pid)
        try:
            raw=(path/'cmdline').read_bytes(); stat=(path/'stat').read_text()
            fields=stat[stat.rfind(')')+2:].split()
            if fields[0]=='Z': return None
            return dict(pid=int(pid),start_ticks=int(fields[19]),boot_id=self.boot_id,
                cmdline_sha256=hashlib.sha256(raw).hexdigest(),
                argv=[x.decode(errors='replace') for x in raw.split(b'\0') if x],
                cwd=os.readlink(path/'cwd'),state=fields[0],session_id=int(fields[3]),
                cpus=sorted(os.sched_getaffinity(int(pid))),
                cgroups=[line.split(':',2)[2] for line in (path/'cgroup').read_text().splitlines()])
        except (FileNotFoundError,ProcessLookupError): return None
    def processes(self):
        result=[]
        for path in Path('/proc').iterdir():
            if not path.name.isdigit(): continue
            try:
                if path.stat().st_uid!=os.getuid(): continue
                process=self.process(int(path.name))
                if process: result.append(process)
            except (FileNotFoundError,ProcessLookupError): continue
        return result
    def unit(self,name):
        result=subprocess.run(['systemctl','--user','show',name,'--property='+','.join(PROPERTIES)],
            text=True,capture_output=True,timeout=30)
        props=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
        if result.returncode and props.get('LoadState')!='not-found':
            raise RuntimeError('cannot inspect unit '+name+': '+result.stderr.strip())
        return props
    def units(self):
        output=subprocess.check_output(['systemctl','--user','list-units','--all','--plain',
            '--no-legend','--type=service'],text=True,timeout=30)
        return [line.split()[0] for line in output.splitlines() if line.split()]
    def members(self,cgroup):
        if not cgroup: return []
        root=Path('/sys/fs/cgroup')/cgroup.lstrip('/')
        if not root.exists(): return []
        return sorted({int(pid) for path in root.rglob('cgroup.procs') for pid in path.read_text().split()})
    def stop(self,name): subprocess.run(['systemctl','--user','stop',name],check=True,timeout=45)
    def start(self,name): subprocess.run(['systemctl','--user','start',name],check=True,timeout=30)
    def guardian(self,config_path,runtime,shared_runtime,attempt,owner_unit=None):
        name=guardian_name(attempt)
        current=self.unit(name)
        if current.get('ActiveState') not in {'active','activating'}:
            subprocess.run(['systemd-run','--user','--quiet','--collect','--unit='+name,
                '--property=Restart=no','--property=KillMode=process',
                '--property=WorkingDirectory='+str(ROOT),
                str(read_config(config_path)['python_runtime']),'-B',str(ENTRY),'guard',
                '--config',str(config_path),'--runtime',str(runtime),
                '--shared-runtime',str(shared_runtime),'--attempt',attempt,
                '--unit',owner_unit or read_config(config_path)['new_unit']],check=True,timeout=30)
        props=self.unit(name); process=self.process(int(props.get('MainPID',0)))
        if (not process or not entry_matches(process,ENTRY) or 'guard' not in process['argv']
                or str(runtime) not in process['argv'] or attempt not in process['argv']
                or props.get('ControlGroup')==self.unit(owner_unit or read_config(config_path)['new_unit']).get('ControlGroup')):
            raise RuntimeError('independent successor guardian failed attestation')
        return name
    def launch(self,argv,env,log,cpus):
        stream=Path(log).open('a')
        try:
            process=subprocess.Popen(argv,env=env,stdout=stream,stderr=subprocess.STDOUT,
                cwd=str(ROOT),start_new_session=True,
                preexec_fn=lambda:os.sched_setaffinity(0,set(cpus)))
        finally: stream.close()
        return process
    def sleep(self,seconds): time.sleep(seconds)


def same_process(current,expected):
    return bool(current) and all(current.get(k)==expected.get(k)
        for k in ('pid','start_ticks','boot_id','cmdline_sha256','cwd'))


def same_owned_child(current,expected):
    if same_process(current,expected): return True
    if not current or not all(current.get(key)==expected.get(key) for key in ('pid','start_ticks','boot_id','cwd')):
        return False
    # Rscript execs the native R binary without changing its lifetime. Permit
    # only an identical script + contract/config role, never an arbitrary exec.
    def role(process):
        argv=process.get('argv',[])
        scripts=[arg.split('=',1)[1] if arg.startswith('--file=') else arg for arg in argv
            if (arg.endswith('/470_fit_pricefm_stage_r137_certified_al_300.R')
                or arg.endswith('/442_fit_pricefm_stage_r123_certified_normal.R'))]
        contracts=[argv[index+1] for index,arg in enumerate(argv[:-1]) if arg in {'--config','--contract'}]
        return (scripts[0],contracts[0]) if len(scripts)==len(contracts)==1 else None
    expected_role=role(expected)
    return expected_role is not None and role(current)==expected_role


def entry_matches(process,entry):
    return any(arg==str(entry) for arg in process.get('argv',[]))


def numerical_process(process,config):
    argv=process.get('argv',[])
    names={Path(arg).name for arg in argv if arg and '\n' not in arg and len(arg)<4096}
    return bool(names.intersection(config['numerical_entries']))


def verify_packet(path):
    path=Path(path); seal=read(path/'completed_evidence.json')
    if not isinstance(seal.get('artifacts'),dict) or not seal['artifacts']:
        raise RuntimeError('incomplete artifact seal: '+str(path))
    for name,expected in seal['artifacts'].items():
        target=(path/name).resolve()
        if not target.is_relative_to(path.resolve()) or sha(target)!=expected:
            raise RuntimeError('unsafe or changed sealed artifact: '+str(target))
    return seal


def campaign(config,region): return Path(config['data'])/'campaigns'/(config['source_tag']+'__'+region)


def complete_region(config,region):
    folder=campaign(config,region)
    if not (folder/'terminal.json').is_file(): return False
    terminal=read(folder/'terminal.json')
    expected={'head':config['source_head'],'branch':config['source_branch']}
    if terminal.get('status')!='R141_REGION_COMPLETE_NOT_PROMOTED' or terminal.get('source')!=expected:
        raise RuntimeError('regional terminal/source differs: '+region)
    seal=verify_packet(folder/'closeout')
    if seal.get('metadata',{}).get('source')!=expected:
        raise RuntimeError('regional closeout source differs: '+region)
    with (folder/'closeout/fold_comparison.csv').open() as stream: rows=list(csv.DictReader(stream))
    operators={'cdf_pool_clipped','mean_feature','path_specific','normal_driver'}
    if (len(rows)!=12 or {(int(row['fold']),row['operator']) for row in rows}
            !={(fold,operator) for fold in (1,2,3) for operator in operators}
            or any(row['region']!=region or not math.isfinite(float(row['AQL'])) or float(row['AQL'])<0 for row in rows)):
        raise RuntimeError('regional fold/operator surface differs: '+region)
    return True


def validate_block(block,config):
    failures=block.get('failures',[])
    expected={('slot_a','AT'),('slot_b','LT')}
    if (block.get('status')!='blocked' or block.get('host')!='muscat'
            or block.get('source',{}).get('head')!=config['source_head']
            or block.get('active')!={} or len(failures)!=2
            or {(row.get('slot'),row.get('region')) for row in failures}!=expected):
        raise RuntimeError('scheduler block is not the exact drained AT+LT boundary')


def verify_static(config):
    validate_config(config); verify_pins(config['source_sha256']); verify_pins(config['evidence_sha256'])
    root=Path(config['source_worktree'])
    head=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
    dirty=subprocess.check_output(['git','-C',str(root),'status','--porcelain'],text=True).strip()
    if head!=config['source_head'] or dirty: raise RuntimeError('immutable R141 source changed')
    release=read(config['release_receipt'])
    if not release.get('passed') or release.get('source')!={'head':config['source_head'],'branch':config['source_branch']}:
        raise RuntimeError('R141 source release receipt differs')
    validate_block(read(config['scheduler_blocked']),config)
    state=read(Path(config['old_runtime'])/'state.json')
    if state.get('attempt')!=config['old_attempt'] or state.get('phase')!='draining':
        raise RuntimeError('old committed ownership boundary differs')
    if read(config['AT_terminal']).get('status')!='R146_AT_FALLBACK_QUARANTINED_NOT_PROMOTED':
        raise RuntimeError('AT must remain explicitly quarantined')
    if complete_region(config,'LT'): raise RuntimeError('LT unexpectedly closed; re-audit required')
    for region in config['closed_imports']:
        if not complete_region(config,region): raise RuntimeError('previous closeout missing: '+region)


def audit(config,system=None):
    system=system or System()
    if system.host()!='muscat': raise RuntimeError('baseline successor is Muscat-only')
    verify_static(config)
    numerical=[row for row in system.processes() if numerical_process(row,config)]
    state=read(Path(config['old_runtime'])/'state.json')
    units={name:system.unit(name) for name in config['legacy_units']}
    for name in config['retired_units']:
        unit=units[name]
        if int(unit.get('MainPID',0)) or system.members(unit.get('ControlGroup','')):
            raise RuntimeError('retired legacy unit has owned processes: '+name)
    locks=[]
    for name in config['legacy_locks']:
        path=Path(name)
        if path.is_symlink() or not path.is_file(): raise RuntimeError('legacy lock path differs: '+name)
        info=path.stat(); locks.append(dict(path=name,device=info.st_dev,inode=info.st_ino))
    return dict(schema_version=1,status='R152_BASELINE_READ_ONLY_AUDIT',epoch=time.time(),
        host=system.host(),boot_id=system.boot_id,old_attempt=state['attempt'],old_phase=state['phase'],
        old_state_sha256=sha(Path(config['old_runtime'])/'state.json'),
        units=units,numerical_processes=numerical,worker_free=not numerical,locks=locks,
        source=source_identity(config),source_sha256=config['source_sha256'],
        evidence_sha256=config['evidence_sha256'],numerical_worker_signals=0)


@contextlib.contextmanager
def fences(runtime,config,expected_locks=None):
    """Acquire all or none, checking stable lock inodes; never block holding a subset."""
    paths=[Path(runtime)/'supervisor.lock',*[Path(name) for name in config['legacy_locks']]]
    opened=[]
    try:
        for index,path in enumerate(paths):
            if path.is_symlink(): raise RuntimeError('symlinked dispatch lock')
            if index==0: path.parent.mkdir(parents=True,exist_ok=True)
            elif not path.is_file(): raise RuntimeError('missing legacy lock')
            stream=path.open('a+')
            try: fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BaseException: stream.close(); raise
            opened.append(stream)
            st=path.stat(); fd=os.fstat(stream.fileno())
            if (st.st_dev,st.st_ino)!=(fd.st_dev,fd.st_ino): raise RuntimeError('lock inode changed')
            if index and expected_locks:
                expected=next(row for row in expected_locks if row['path']==str(path))
                if (fd.st_dev,fd.st_ino)!=(expected['device'],expected['inode']):
                    raise RuntimeError('legacy lock identity changed')
        yield
    finally:
        for stream in reversed(opened): stream.close()


def legacy_guardians(config,system):
    result=[]
    for name in system.units():
        if not name.startswith(config['legacy_guardian_prefix']): continue
        unit=system.unit(name); pid=int(unit.get('MainPID',0))
        if unit.get('ActiveState') not in {'active','activating'} and not pid: continue
        process=system.process(pid)
        if process is None:
            after=system.unit(name)
            if (not int(after.get('MainPID',0)) and after.get('ActiveState') not in {'active','activating'}
                    and not system.members(unit.get('ControlGroup',''))):
                continue
            raise RuntimeError('legacy guardian vanished without verified unit/cgroup drain: '+name)
        argv=process.get('argv',[]) if process else []
        def option(key):
            return argv[argv.index(key)+1] if key in argv and argv.index(key)+1<len(argv) else None
        if (not process or not entry_matches(process,config['legacy_entry']) or 'guard' not in argv
                or option('--attempt')!=config['old_attempt']
                or option('--runtime')!=config['old_runtime']
                or option('--config')!=config['legacy_config']
                or process['cwd']!=config['legacy_worktree']
                or unit.get('WorkingDirectory')!=config['legacy_worktree']
                or unit.get('ControlGroup','') not in process.get('cgroups',[])):
            raise RuntimeError('ambiguous legacy guardian; no signal sent: '+name)
        result.append(dict(unit=name,properties=unit,process=process))
    return result


def quiesce_legacy(config,system,receipt):
    if not receipt.get('worker_free'): raise RuntimeError('cutover is not worker-free')
    if any(numerical_process(row,config) for row in system.processes()):
        raise RuntimeError('numerical child appeared before control cutover')
    name=config['legacy_handoff_unit']; unit=system.unit(name)
    if (unit.get('WorkingDirectory')!=config['legacy_worktree']
            or config['legacy_entry'] not in unit.get('ExecStart','')
            or config['old_runtime'] not in unit.get('ExecStart','')
            or unit.get('KillMode')!='process' or unit.get('Restart')!='on-failure'):
        raise RuntimeError('old handoff unit identity differs; no signal sent')
    guardians=legacy_guardians(config,system)
    # Fences are held by run(). Their old run paths cannot reach numerical dispatch.
    system.stop(name)
    for row in guardians:
        current=system.unit(row['unit'])
        if current.get('InvocationID')!=row['properties'].get('InvocationID'):
            raise RuntimeError('legacy guardian lifetime changed before stop')
        current_process=system.process(row['process']['pid'])
        if not same_process(current_process,row['process']):
            if current_process is not None: raise RuntimeError('legacy guardian PID was reused')
            continue
        system.stop(row['unit'])
    for _ in range(2):
        unit=system.unit(name)
        if int(unit.get('MainPID',0)) or system.members(unit.get('ControlGroup','')):
            raise RuntimeError('old handoff did not drain')
        if legacy_guardians(config,system): raise RuntimeError('legacy guardian remains or restarted')
        if any(numerical_process(row,config) for row in system.processes()):
            raise RuntimeError('numerical child appeared during quiescence')
        system.sleep(.2)
    return dict(status='R152_EXACT_LEGACY_CONTROLS_QUIESCED',epoch=time.time(),
        handoff_unit=name,guardians=[row['unit'] for row in guardians],
        old_attempt=config['old_attempt'],old_R145_resumed=False,numerical_worker_signals=0,
        protected_slot_B_disposition='LT_QUARANTINED_TAIL_UNCLOSED_EXPLICIT_NEW_RESOURCE_ALLOCATION')


def require_own_service(config,system):
    unit=system.unit(config['new_unit'])
    if (int(unit.get('MainPID',0))!=os.getpid() or unit.get('KillMode')!='process'
            or unit.get('Restart')!='on-failure' or unit.get('WorkingDirectory')!=str(ROOT)
            or str(ENTRY) not in unit.get('ExecStart','')):
        raise RuntimeError('successor requires exact own service, process kill mode and bounded restart')
    return unit


def publish_owner(runtime,state,system,master=None):
    path=Path(runtime); owner=system.process(os.getpid())
    if owner is None: raise RuntimeError('own lifetime vanished')
    old=read(path/'resource_ownership_epoch.json') if (path/'resource_ownership_epoch.json').exists() else None
    generation=(old['generation']+1) if old and not same_process(owner,old['owner']) else (old['generation'] if old else 1)
    if generation>state['max_owner_generations']: raise RuntimeError('bounded owner generations exhausted')
    predecessor=(sha(path/'owner_epochs'/f"{old['generation']:03d}.json")
        if old and generation!=old['generation'] and master else (old or {}).get('predecessor_sha256'))
    value=dict(schema_version=1,scope_id=state['scope_id'],attempt=state['attempt'],
        source=state['source'],generation=generation,owner=owner,
        guardian_unit=state['guardian_unit'],heartbeat=time.time(),phase=state['phase'],
        expires_epoch=master['expires_epoch'] if master else None,
        predecessor_sha256=predecessor)
    sealed=path/'owner_epochs'/f'{generation:03d}.json'
    if master and not sealed.exists():
        immutable(sealed,value)
    atomic(path/'resource_ownership_epoch.json',value)
    return value


def default_commit_master(pending,shared_runtime,partition_release_fields):
    entry=ROOT/'application/scripts/pricefm/505_run_pricefm_stage_r152_shared_pool.py'
    spec=importlib.util.spec_from_file_location('r152_commit_pool',entry)
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.commit_master(pending,shared_runtime,partition_release_fields=partition_release_fields)


def partition_receipt(config,runtime,shared_runtime,master,source):
    start=master.get('started_epoch',master.get('start_epoch'))
    return dict(schema_version=1,scope_id=master['scope_id'],
        master_sha256=sha(Path(shared_runtime)/'master.json'),
        started_epoch=start,start_epoch=start,expires_epoch=master['expires_epoch'],
        partition=config['partition'],source=source,baseline_owner=master['baseline_owner'],
        guardian_unit=master['baseline_guardian_unit'],baseline_runtime=str(Path(runtime).resolve()),
        allowed_transitions=['same_source_owner_adoption','region_complete','scientific_quarantine',
            'development_drained_then_B_next_region_restoration'],numerical_worker_signals=0)


def commit_scope(config,runtime,shared_runtime,state,pending,system,commit_callback=None):
    """Only real owner publishes the common T0; the callback writes one master authority."""
    if state['phase']!='armed': raise RuntimeError('scope can commit only from armed')
    if pending.get('scope_id')!=state['scope_id']:
        raise RuntimeError('pending master scope differs')
    pending_gate(pending,system)
    fields=dict(baseline_owner=system.process(os.getpid()),baseline_runtime=str(Path(runtime).resolve()),
        baseline_guardian_unit=state['guardian_unit'],
        loan_owner_epoch=dict(attempt=state['attempt'],generation=1,
            heartbeat_path=str(Path(runtime)/'resource_ownership_epoch.json')),
        host=system.host(),boot_id=system.boot_id,partition=config['partition'])
    if not fields['baseline_owner']: raise RuntimeError('owner lifetime unavailable before commit')
    callback=commit_callback or default_commit_master
    master=callback(pending,Path(shared_runtime),partition_release_fields=fields)
    if master is None: master=read(Path(shared_runtime)/'master.json')
    start=master.get('started_epoch',master.get('start_epoch'))
    if (master['scope_id']!=state['scope_id'] or master['expires_epoch']!=start+config['scope_seconds']
            or master.get('partition')!=config['partition']):
        raise RuntimeError('master does not match the single partition-loan clock')
    immutable(Path(runtime)/'partition_release.json',partition_receipt(config,runtime,shared_runtime,master,state['source']))
    state.update(phase='running',master_sha256=sha(Path(shared_runtime)/'master.json'))
    atomic(Path(runtime)/'state.json',state); publish_owner(runtime,state,system,master)
    return master


def recover_committed_scope(config,runtime,shared_runtime,state,pending,system):
    """Finish publication after a crash; never manufacture another T0 or scope."""
    master=read(Path(shared_runtime)/'master.json'); current_hash=sha(Path(shared_runtime)/'master.json')
    start=master.get('started_epoch',master.get('start_epoch'))
    if (master.get('scope_id')!=state['scope_id'] or pending.get('scope_id')!=state['scope_id']
            or master.get('source',{}).get('head')!=state['source']['head']
            or master.get('partition')!=config['partition']
            or master.get('baseline_runtime')!=str(Path(runtime).resolve())
            or master.get('expires_epoch')!=start+43200
            or start>=pending.get('precommit_expires_epoch',0)):
        raise RuntimeError('committed scope/clock/source cannot be adopted')
    if state.get('master_sha256'):
        if state['master_sha256']!=current_hash: raise RuntimeError('committed master bytes changed')
    else:
        epoch=read(Path(runtime)/'resource_ownership_epoch.json')
        if (state['phase']!='armed' or master.get('baseline_guardian_unit')!=state['guardian_unit']
                or not same_process(epoch['owner'],master['baseline_owner'])):
            raise RuntimeError('partial commitment lacks exact original owner proof')
        # The master is the authoritative commit event. Recover the first
        # owner seal from its exact precommit observation without inventing a
        # fresh clock, live owner or heartbeat.
        first=Path(runtime)/'owner_epochs/001.json'
        if not first.exists():
            original=dict(epoch,expires_epoch=master['expires_epoch'],
                phase='committed_original_owner_reconstructed',
                publication_recovered_from_master_sha256=current_hash)
            immutable(first,original)
    immutable(Path(runtime)/'partition_release.json',partition_receipt(config,runtime,shared_runtime,master,state['source']))
    state.update(master_sha256=current_hash,phase='running')
    return master


def baseline_ownership(runtime,master,system=None,allow_expired=False):
    system=system or System(); runtime=Path(runtime)
    state=read(runtime/'state.json'); config=read_config(state.get('config_path',CONFIG))
    config=dict(config,new_unit=state.get('new_unit',config['new_unit'])); validate_config(config)
    if state.get('config_sha256')!=sha(state.get('config_path',CONFIG)):
        raise RuntimeError('baseline source configuration bytes changed')
    epoch=read(runtime/'resource_ownership_epoch.json')
    shared=runtime.parent; release=read(runtime/'partition_release.json')
    if (release['master_sha256']!=sha(shared/'master.json')
            or release['scope_id']!=master['scope_id'] or epoch['scope_id']!=master['scope_id']
            or state['scope_id']!=master['scope_id'] or release['expires_epoch']!=master['expires_epoch']
            or epoch['expires_epoch']!=master['expires_epoch']
            or epoch['source']!=state['source'] or epoch['source']['head']!=master.get('source_head',master.get('source',{}).get('head'))
            or epoch['phase'] not in {'running','complete'}
            or time.time()-epoch['heartbeat']>config['guardian_lease_seconds']):
        raise RuntimeError('baseline ownership epoch/master/heartbeat differs')
    if not allow_expired and time.time()>=master['expires_epoch']:
        raise RuntimeError('baseline six-core loan has expired')
    if not allow_expired and early_closed(shared,master,system):
        raise RuntimeError('baseline six-core loan was cleanly released early')
    unit=system.unit(config['new_unit'])
    if (int(unit.get('MainPID',0))!=epoch['owner']['pid']
            or not same_process(system.process(epoch['owner']['pid']),epoch['owner'])
            or unit.get('KillMode')!='process' or unit.get('WorkingDirectory')!=str(ROOT)
            or str(ENTRY) not in unit.get('ExecStart','')):
        raise RuntimeError('new baseline owner lifetime differs')
    guardian=system.unit(epoch['guardian_unit'])
    guardian_process=system.process(int(guardian.get('MainPID',0)))
    argv=guardian_process.get('argv',[]) if guardian_process else []
    if (not guardian_process or not entry_matches(guardian_process,ENTRY) or 'guard' not in argv
            or str(runtime) not in argv or state['attempt'] not in argv
            or config['new_unit'] not in argv or guardian.get('WorkingDirectory')!=str(ROOT)
            or guardian.get('KillMode')!='process' or guardian.get('Restart')!='no'
            or guardian.get('ControlGroup') not in guardian_process.get('cgroups',[])):
        raise RuntimeError('baseline guardian is not the expected live source')
    for generation in range(1,epoch['generation']+1):
        receipt=read(runtime/'owner_epochs'/f'{generation:03d}.json')
        if (receipt['generation']!=generation or receipt['scope_id']!=master['scope_id']
                or receipt['source']!=state['source'] or receipt['expires_epoch']!=master['expires_epoch']):
            raise RuntimeError('baseline owner adoption chain differs')
        if generation==epoch['generation'] and not same_process(receipt['owner'],epoch['owner']):
            raise RuntimeError('latest sealed owner generation differs')
        if generation>1 and receipt.get('predecessor_sha256')!=sha(runtime/'owner_epochs'/f'{generation-1:03d}.json'):
            raise RuntimeError('baseline owner adoption predecessor differs')
    for lane,job in state.get('active',{}).items():
        for process in session_members(job,system):
            if not set(process['cpus']).issubset(job['cpus']):
                raise RuntimeError('baseline child escaped its declared CPU partition')
    return dict(scope_id=master['scope_id'],master_sha256=release['master_sha256'],
        expires_epoch=master['expires_epoch'],owner=epoch['owner'],guardian=guardian_process,
        generation=epoch['generation'],phase=epoch['phase'],heartbeat=epoch['heartbeat'])


def session_members(job,system):
    expected=job.get('process')
    if expected:
        current=system.process(expected['pid'])
        if current and not same_process(current,expected): raise RuntimeError('baseline child PID reused')
    members=[row for row in system.processes() if row.get('session_id')==job['session_id']]
    if members and not expected: raise RuntimeError('unrecorded session root; cannot adopt unknown children')
    observed={row['pid']:row for row in job.get('observed_children',[])}
    for row in members:
        if not set(row['cpus']).issubset(job['cpus']): raise RuntimeError('owned baseline session escaped CPU partition')
        if expected and row['start_ticks']<expected['start_ticks']:
            raise RuntimeError('session contains a process older than its recorded root')
        if expected and current is None and not same_owned_child(row,observed.get(row['pid'],{})):
            raise RuntimeError('unobserved or changed orphan lifetime; adoption requires fresh proof')
    if expected and current is not None:
        job['observed_children']=[row for row in members if row['pid']!=expected['pid']]
    return members


def cached_drained(shared_runtime,master,system):
    shared_runtime=Path(shared_runtime)
    path=shared_runtime/'development/final_drained.json'
    if not path.is_file(): path=shared_runtime/'development/drained.json'
    if not path.is_file(): return False
    value=read(path)
    if (not value.get('cleanup_verified') or value.get('owned_pids')!=[]
            or value.get('scope_id')!=master['scope_id']
            or value.get('master_sha256')!=sha(Path(shared_runtime)/'master.json')
            or value.get('source_head')!=master.get('source_head',master.get('source',{}).get('head'))):
        return False
    cleanup=value.get('cleanup',[])
    if set(value.get('owned_units',[]))!={row['unit'] for row in cleanup}: return False
    for row in cleanup:
        if not row.get('drained') or row.get('pids') or system.members(row.get('expected_cgroup','')):
            return False
        unit=system.unit(row['unit'])
        if (int(unit.get('MainPID',0)) or unit.get('ActiveState') in {'active','activating'}
                or system.members(unit.get('ControlGroup',''))): return False
    # The broker can seal its worker-drain receipt before its own final exit.
    # Independently fence every registered cached control lifetime too.
    attempts=sorted((shared_runtime/'development/attempts').glob('*/*/ownership.json'))
    covered=set(value.get('owned_units',[]))
    if any(read(path).get('unit') not in covered for path in attempts): return False
    control_paths=attempts+[shared_runtime/'development'/name for name in ('controller.json','guardian.json')]
    control_paths.append(shared_runtime/'orchestrator.json')
    for path in control_paths:
        if not path.is_file(): continue
        saved=read(path); saved=saved.get('capsule',saved)
        unit=system.unit(saved['unit'])
        group=saved.get('expected_cgroup') or saved.get('attested',{}).get('ControlGroup','')
        expected=saved.get('process'); current=system.process(expected['pid']) if expected else None
        same=(current is not None and all(current.get(key)==expected.get(key) for key in ('pid','start_ticks','boot_id')))
        if (int(unit.get('MainPID',0)) or unit.get('ActiveState') in {'active','activating'}
                or system.members(group) or system.members(unit.get('ControlGroup','')) or same):
            return False
    for row in system.processes():
        argv=row.get('argv',[])
        if any(str(Path(shared_runtime)/'development') in arg for arg in argv) and any(
                arg in {'worker','payload','bootstrap'} or '500_run_pricefm' in arg for arg in argv):
            return False
    return True


def early_closed(shared_runtime,master,system):
    path=Path(shared_runtime)/'development_closed.json'
    if not path.is_file(): return False
    value=read(path)
    if (value.get('scope_id')!=master['scope_id']
            or value.get('master_sha256')!=sha(Path(shared_runtime)/'master.json')
            or value.get('source_head')!=master.get('source_head',master.get('source',{}).get('head'))
            or value.get('future_admissions_closed') is not True
            or value.get('cleanup_verified') is not True): return False
    terminal=Path(value.get('terminal_path',Path(shared_runtime)/'development/terminal.json'))
    if not terminal.resolve().is_relative_to((Path(shared_runtime)/'development').resolve()): return False
    if not terminal.is_file() or value.get('terminal_sha256')!=sha(terminal): return False
    final=Path(shared_runtime)/'development/final_drained.json'
    if not final.is_file() or value.get('final_drained_sha256')!=sha(final): return False
    return cached_drained(shared_runtime,master,system)


def record_loan_return(runtime,shared_runtime,master):
    path=Path(runtime)/'loan_return_verified.json'
    if path.exists():
        value=read(path)
        if value.get('scope_id')!=master['scope_id'] or value.get('master_sha256')!=sha(Path(shared_runtime)/'master.json'):
            raise RuntimeError('loan-return receipt belongs to another master')
        return value
    records={}
    for name in ('development_closed.json','development/final_drained.json','development/drained.json',
            'development/controller.json','development/guardian.json','orchestrator.json'):
        target=Path(shared_runtime)/name
        if target.is_file(): records[name]=sha(target)
    value=dict(schema_version=1,scope_id=master['scope_id'],master_sha256=sha(Path(shared_runtime)/'master.json'),
        source_head=master.get('source_head',master.get('source',{}).get('head')),epoch=time.time(),
        all_registered_cached_workers_and_controls_drained=True,publisher_actual_drain_checked=True,
        returned_CPUs=list(range(24,30)),receipt_sha256=records,numerical_worker_signals=0,
        restore_only_at_region_boundary=True)
    immutable(path,value);return value


def choose_cpus(config,lane,shared_runtime,master,system):
    if lane=='A': return config['partition']['baseline_A']
    if ((time.time()>=master['expires_epoch'] and cached_drained(shared_runtime,master,system))
            or early_closed(shared_runtime,master,system)):
        record_loan_return(Path(shared_runtime)/'baseline',shared_runtime,master)
        return list(range(15,30))
    return config['partition']['baseline_B']


def failed_certificates(config,region):
    folder=campaign(config,region); result=[]
    for path in sorted((folder/'tasks_done').glob('*')):
        if not (path/'completed_evidence.json').is_file(): continue
        seal=read(path/'completed_evidence.json')
        if seal.get('metadata',{}).get('certified') is not False: continue
        seal=verify_packet(path); terminal_path=path/'fit/terminal.json'
        task=read(folder/'tasks'/(path.name+'.json'))
        if (seal['metadata'].get('source_head')!=config['source_head']
                or task.get('kind') not in {'al','internal_al'} or not terminal_path.exists()):
            raise RuntimeError('unclassified failed numerical packet: '+path.name)
        terminal=read(terminal_path)
        if (terminal.get('finite_core') is not True or terminal.get('iterations')!=300
                or terminal.get('termination')!='iteration_cap_uncertified'
                or terminal.get('test_opened') is not False):
            raise RuntimeError('failed packet is not finite original-cap AL evidence: '+path.name)
        result.append(dict(task=path.name,completed_evidence_sha256=sha(path/'completed_evidence.json'),
            terminal_sha256=sha(terminal_path),task_sha256=sha(folder/'tasks'/(path.name+'.json'))))
    return result


def command(config,region,phase,cpus):
    if region not in A_QUEUE+B_QUEUE: raise RuntimeError('region is outside the nine healthy tails')
    base=[config['python_runtime'],'-B',config['source_controller']]
    if phase=='prepare':
        return base+['prepare','--dependency',config['dependency_worktree'],'--release',config['release_receipt']]
    if phase!='controller' or len(cpus) not in {9,15}: raise RuntimeError('invalid baseline dispatch phase/CPU count')
    return base+['controller','--region',region,'--workers',str(len(cpus)),
        '--cpus',','.join(map(str,cpus))]


def launch_region(config,runtime,lane,region,phase,cpus,system):
    argv=command(config,region,phase,cpus)
    env=dict(os.environ,PRICEFM_R141_REGION=region,**{key:'1' for key in THREAD_ENV})
    log=Path(runtime)/'logs'/f'{lane}.{region}.{phase}.log'; log.parent.mkdir(parents=True,exist_ok=True)
    process=system.launch(argv,env,log,cpus)
    observed=system.process(process.pid)
    if observed and (observed.get('argv')!=argv or observed.get('session_id')!=process.pid):
        raise RuntimeError('launched baseline root identity/session differs')
    return dict(region=region,phase=phase,cpus=list(cpus),argv=argv,pid=process.pid,
        session_id=process.pid,process=observed,observed_children=[],started_epoch=time.time(),log=str(log))


def host_health(config):
    memory={line.split(':')[0]:int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    disk=os.statvfs(config['data'])
    value=dict(available_memory_GiB=memory['MemAvailable']/2**20,
        free_disk_GiB=disk.f_bavail*disk.f_frsize/2**30)
    value['healthy']=value['available_memory_GiB']>=192 and value['free_disk_GiB']>=80
    return value


def pending_gate(pending,system,minimum_remaining=0):
    if time.time()+minimum_remaining>=pending.get('precommit_expires_epoch',0):
        raise RuntimeError('orchestrator precommit allowance expired or insufficient')
    capsule=pending.get('orchestrator',{}); unit=system.unit(capsule.get('unit',''))
    process=capsule.get('process',{})
    if (not process or not same_process(system.process(process.get('pid',0)),process)
            or int(unit.get('MainPID',0))!=process['pid']
            or unit.get('InvocationID')!=capsule.get('invocation_id')):
        raise RuntimeError('precommit orchestrator lifetime disappeared or changed')


def step_lanes(config,runtime,shared_runtime,state,master,system):
    """Advance only after exact owned-session drain; never repair a failed fit."""
    for lane,queue in config['queues'].items():
        job=state['active'].get(lane)
        if job:
            if session_members(job,system): continue
            region=job['region']
            if job['phase']=='prepare':
                prep=Path(config['data'])/'launch_prep'/(config['source_tag']+'__'+region)/'preparation.json'
                if not prep.is_file(): raise RuntimeError('preparation exited without immutable preparation: '+region)
                prepared=read(prep)
                if prepared.get('source',{}).get('head')!=config['source_head']:
                    raise RuntimeError('preparation source changed: '+region)
                state['active'][lane]=launch_region(config,runtime,lane,region,'controller',job['cpus'],system)
            elif complete_region(config,region):
                state['completed'][lane].append(region); del state['active'][lane]
                immutable(Path(runtime)/'regions'/f'{region}.complete.json',dict(region=region,
                    status='R152_BASELINE_NUMERICAL_SOURCE_PRESERVED',source_head=config['source_head'],
                    terminal_sha256=sha(campaign(config,region)/'terminal.json'),epoch=time.time()))
            else:
                failed=failed_certificates(config,region)
                if not failed: raise RuntimeError('controller exited without closeout or finite certificate failure: '+region)
                receipt=dict(region=region,lane=lane,status='R152_ORIGINAL_CAP_CERTIFICATE_QUARANTINE',
                    failed=failed,epoch=time.time(),source_head=config['source_head'],
                    fit_retry_admitted=False,certificate_limits_changed=False,old_evidence_preserved=True)
                immutable(Path(runtime)/'quarantine'/(region+'.json'),receipt)
                state['quarantined'][lane].append(region); del state['active'][lane]
            continue
        pending=[region for region in queue if region not in state['completed'][lane]
            and region not in state['quarantined'][lane]]
        if not pending: continue
        region=pending[0]
        if complete_region(config,region):
            state['completed'][lane].append(region); continue
        prep=Path(config['data'])/'launch_prep'/(config['source_tag']+'__'+region)/'preparation.json'
        phase='controller' if prep.is_file() else 'prepare'
        cpus=choose_cpus(config,lane,shared_runtime,master,system)
        state['active'][lane]=launch_region(config,runtime,lane,region,phase,cpus,system)
    return state


def seal_terminal(runtime,state,source):
    path=Path(runtime)/'terminal.json'
    fields=dict(status='R152_BASELINE_TAILS_DRAINED_NOT_GLOBAL_CLOSEOUT',
        scope_id=state['scope_id'],master_sha256=state['master_sha256'],
        completed=state['completed'],quarantined=state['quarantined'],
        excluded_quarantines=['AT','LT'],source=source,
        scientific_targets_changed=False,certificates_changed=False)
    if path.exists():
        current=read(path)
        if any(current.get(key)!=value for key,value in fields.items()):
            raise RuntimeError('existing baseline terminal differs on owner adoption')
        return current
    value=dict(fields,epoch=time.time()); immutable(path,value); return value


def run(config,runtime,shared_runtime,pending_path,config_path=CONFIG,system=None,commit_callback=None):
    system=system or System(); runtime=Path(runtime); shared_runtime=Path(shared_runtime)
    runtime.mkdir(parents=True,exist_ok=True)
    source=source_identity(config); pending=read(pending_path)
    if pending.get('source',{}).get('head',pending.get('source_head'))!=source['head']:
        raise RuntimeError('pending master does not attest current resource source')
    require_own_service(config,system)
    # A busy old lock releases the whole acquired set; the service does not spin forever.
    deadline=time.time()+config['fence_wait_seconds']
    while True:
        try:
            current_audit=audit(config,system)
            with fences(runtime,config,current_audit['locks']):
                state_path=runtime/'state.json'
                if state_path.exists():
                    state=read(state_path)
                    if state['scope_id']!=pending['scope_id'] or state['source']!=source:
                        raise RuntimeError('existing successor scope/source differs')
                    if state['phase']=='blocked': return state
                    if state['phase']=='complete' and (shared_runtime/'master.json').exists():
                        old_master=read(shared_runtime/'master.json')
                        if time.time()>=old_master['expires_epoch'] or early_closed(shared_runtime,old_master,system): return state
                else:
                    if not current_audit['worker_free']: raise RuntimeError('initial cutover requires worker-free baseline')
                    state=dict(schema_version=1,scope_id=pending['scope_id'],attempt=uuid.uuid4().hex,
                        phase='pending',source=source,config_sha256=sha(config_path),
                        config_path=str(Path(config_path).resolve()),new_unit=config['new_unit'],
                        master_pending_sha256=sha(pending_path),
                        active={},completed={'A':[],'B':[]},quarantined={'A':[],'B':[]},
                        excluded_quarantines=['AT','LT'],max_owner_generations=config['max_owner_generations'])
                    immutable(runtime/'initial_audit.json',current_audit)
                try:
                    if not (shared_runtime/'master.json').exists():
                        pending_gate(pending,system,config['cutover_reserve_seconds'])
                        quiesced=quiesce_legacy(config,system,current_audit)
                        if (runtime/'legacy_supersession.json').exists():
                            old_quiesced=read(runtime/'legacy_supersession.json')
                            if (old_quiesced.get('old_attempt')!=config['old_attempt']
                                    or old_quiesced.get('numerical_worker_signals')!=0):
                                raise RuntimeError('prior exact quiescence receipt differs')
                            immutable(runtime/'quiescence_rechecks'/f'{os.getpid()}.json',quiesced)
                        else: immutable(runtime/'legacy_supersession.json',quiesced)
                        state['phase']='armed'
                        state['guardian_unit']=guardian_name(state['attempt'])
                        atomic(state_path,state)
                        state['guardian_unit']=system.guardian(config_path,runtime,shared_runtime,state['attempt'],config['new_unit'])
                        atomic(state_path,state); publish_owner(runtime,state,system)
                        master=commit_scope(config,runtime,shared_runtime,state,pending,system,commit_callback)
                    else:
                        if state.get('master_pending_sha256')!=sha(pending_path):
                            raise RuntimeError('original pending master changed after commitment')
                        master=recover_committed_scope(config,runtime,shared_runtime,state,pending,system)
                        state['guardian_unit']=guardian_name(state['attempt'])
                        atomic(state_path,state)
                        state['guardian_unit']=system.guardian(config_path,runtime,shared_runtime,state['attempt'],config['new_unit'])
                        state['phase']='running'; atomic(state_path,state); publish_owner(runtime,state,system,master)
                    while True:
                        verify_pins(config['source_sha256'])
                        health=host_health(config)
                        if not health['healthy']: raise RuntimeError('baseline host resource floor crossed')
                        state=step_lanes(config,runtime,shared_runtime,state,master,system)
                        state.update(epoch=time.time(),health=health)
                        done=all(len(state['completed'][lane])+len(state['quarantined'][lane])==len(queue)
                            for lane,queue in config['queues'].items())
                        if done: state['phase']='complete'
                        atomic(state_path,state); publish_owner(runtime,state,system,master)
                        atomic(runtime/'progress.json',state)
                        if done:
                            seal_terminal(runtime,state,source)
                            # Remain a live, heartbeating resource owner until the loan closes.
                            while time.time()<master['expires_epoch'] and not early_closed(shared_runtime,master,system):
                                publish_owner(runtime,state,system,master); system.sleep(config['poll_seconds'])
                            return state
                        system.sleep(config['poll_seconds'])
                except BaseException as error:
                    state.update(phase='blocked',error=repr(error),epoch=time.time())
                    atomic(state_path,state)
                    atomic(runtime/'blocked.json',dict(state,baseline_children_signalled=False,
                        old_R145_resumed=False,cached_guard_must_defer=True))
                    if state.get('guardian_unit'): publish_owner(runtime,state,system,
                        read(shared_runtime/'master.json') if (shared_runtime/'master.json').exists() else None)
                    raise
        except BlockingIOError:
            if time.time()>=deadline: raise RuntimeError('bounded legacy/new dispatch fence wait exhausted')
            system.sleep(.25)


def guard_once(config,runtime,shared_runtime,attempt,system=None,now=None):
    system=system or System(); runtime=Path(runtime); now=time.time() if now is None else now
    state=read(runtime/'state.json')
    if state['attempt']!=attempt: raise RuntimeError('guardian belongs to a different attempt')
    observer=system.process(os.getpid())
    if observer and 'guard' in observer.get('argv',[]) and state.get('guardian_unit'):
        current=system.unit(state['guardian_unit'])
        pid=int(current.get('MainPID',0))
        if pid and pid!=os.getpid(): return 'complete'
    if state['phase'] in TERMINAL_PHASES:
        if state['phase']!='complete': return 'complete'
        master_path=Path(shared_runtime)/'master.json'
        if not master_path.exists(): return 'complete'
        master=read(master_path)
        if now>=master['expires_epoch'] or early_closed(shared_runtime,master,system): return 'complete'
    epoch_path=runtime/'resource_ownership_epoch.json'
    if not epoch_path.exists(): return 'wait'
    epoch=read(epoch_path); owner=system.process(epoch['owner']['pid'])
    if same_process(owner,epoch['owner']):
        if now-epoch['heartbeat']>config['guardian_lease_seconds']:
            atomic(runtime/'guardian_blocked.json',dict(reason='live_owner_heartbeat_stale',epoch=now,
                numerical_worker_signals=0,old_R145_resumed=False)); return 'blocked'
        return 'wait'
    if state['phase']=='armed':
        atomic(runtime/'guardian_blocked.json',dict(reason='owner_lost_before_master_commit',
            epoch=now,old_R145_resumed=False,numerical_worker_signals=0)); return 'blocked'
    if epoch['generation']>=config['max_owner_generations']:
        atomic(runtime/'guardian_blocked.json',dict(reason='bounded_owner_adoption_exhausted',epoch=now,
            numerical_worker_signals=0,old_R145_resumed=False)); return 'blocked'
    unit=system.unit(config['new_unit'])
    if (unit.get('KillMode')!='process' or unit.get('Restart')!='on-failure'
            or str(ENTRY) not in unit.get('ExecStart','')):
        raise RuntimeError('guardian successor source/service policy changed')
    if unit.get('ActiveState') not in {'active','activating'}: system.start(config['new_unit'])
    return 'wait'


def guard(config,runtime,shared_runtime,attempt,system=None):
    system=system or System()
    while guard_once(config,runtime,shared_runtime,attempt,system)=='wait': system.sleep(3)


def probe_authority(path,system):
    path=Path(path).resolve()
    if (path.parent!=Path('/tmp') or not path.name.startswith('pricefm-r152-baseline-probe-')
            or path.stat().st_uid!=os.getuid() or path.stat().st_mode & 0o077):
        raise RuntimeError('disposable baseline probe requires its private UUID /tmp namespace')
    authority=read(path/'authority.json')
    if authority['source']!=source_identity(read_config()): raise RuntimeError('probe source changed')
    if not same_process(system.process(authority['owner']['pid']),authority['owner']):
        raise RuntimeError('probe owner lifetime changed')
    return authority


def probe_contend(path):
    system=System(); probe_authority(path,system)
    config={'legacy_locks':[str(Path(path)/'legacy0.lock'),str(Path(path)/'legacy1.lock')]}
    try:
        with fences(path,config): pass
    except BlockingIOError:
        print('cross-process dispatch fence held',flush=True); return
    raise RuntimeError('second process incorrectly obtained held dispatch fences')


def probe_orphan(path):
    system=System(); probe_authority(path,system)
    child=subprocess.Popen([read_config()['python_runtime'],'-B','-c','import time; time.sleep(20)'],
        stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    expected=None
    for _ in range(50):
        expected=system.process(child.pid)
        if expected: break
        time.sleep(.01)
    if not expected: raise RuntimeError('disposable orphan child never became observable')
    owner=system.process(os.getpid())
    immutable(Path(path)/'orphan_job.json',dict(process=owner,session_id=owner['session_id'],
        cpus=owner['cpus'],child=expected,observed_children=[expected],disposable=True))


def capability_probe(output):
    """Actual source primitives on private locks/lifetimes; no real unit controls."""
    config=read_config(); source=source_identity(config); system=System()
    if system.host()!='muscat': raise RuntimeError('actual baseline probe is Muscat-only')
    temporary=Path(tempfile.mkdtemp(prefix='pricefm-r152-baseline-probe-'))
    owner=system.process(os.getpid()); scope=uuid.uuid4().hex
    immutable(temporary/'authority.json',dict(source=source,owner=owner,scope_id=scope))
    for name in ('legacy0.lock','legacy1.lock'): (temporary/name).touch()
    lock_config={'legacy_locks':[str(temporary/'legacy0.lock'),str(temporary/'legacy1.lock')]}
    command_base=[config['python_runtime'],'-B',str(ENTRY)]
    with fences(temporary,lock_config):
        result=subprocess.run(command_base+['probe-contend','--probe-runtime',str(temporary)],
            text=True,capture_output=True,timeout=10)
        if result.returncode: raise RuntimeError('actual fence contender failed: '+result.stderr)
    live=temporary/'guardian'; live.mkdir()
    atomic(live/'state.json',dict(attempt=scope,phase='running'))
    atomic(live/'resource_ownership_epoch.json',dict(owner=owner,generation=1,heartbeat=time.time()))
    if guard_once(config,live,temporary,scope,system)!='wait':
        raise RuntimeError('actual healthy-owner guardian observation failed')
    process=subprocess.Popen(command_base+['probe-orphan','--probe-runtime',str(temporary)],
        start_new_session=True,preexec_fn=lambda:os.sched_setaffinity(0,{29}),
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    stdout,stderr=process.communicate(timeout=10)
    if process.returncode: raise RuntimeError('actual orphan publisher failed: '+stderr)
    job=read(temporary/'orphan_job.json')
    adopted=session_members(job,system)
    if (system.process(job['process']['pid']) is not None
            or not any(same_process(row,job['child']) for row in adopted)):
        raise RuntimeError('exact orphan-session adoption failed')
    target=system.process(job['child']['pid'])
    if not same_process(target,job['child']): raise RuntimeError('disposable child identity changed before cleanup')
    os.kill(target['pid'],signal.SIGTERM)
    deadline=time.time()+5
    while system.process(target['pid']) is not None and time.time()<deadline: time.sleep(.05)
    if system.process(target['pid']) is not None:
        if not same_process(system.process(target['pid']),target): raise RuntimeError('probe PID reused during cleanup')
        os.kill(target['pid'],signal.SIGKILL)
    if session_members(job,system): raise RuntimeError('disposable adopted session did not drain')
    result=dict(schema_version=1,status='PASS_ACTUAL_SOURCE_BASELINE_PRIMITIVE_PROBE',
        source=source,entry_sha256=sha(ENTRY),probe_namespace=str(temporary),epoch=time.time(),
        cross_process_fences=True,healthy_owner_guardian_observation=True,
        exact_orphan_session_adoption=True,exact_disposable_cleanup=True,
        production_guardian_restart_proved=False,real_legacy_controls_changed=False,
        baseline_workers_launched=0,scientific_workers_signalled=0,
        disposable_child_signals=['SIGTERM'],source_bound=True)
    immutable(output,result); return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('audit','run','guard','status','probe','probe-orphan','probe-contend'))
    parser.add_argument('--config',type=Path,default=CONFIG)
    parser.add_argument('--runtime',type=Path)
    parser.add_argument('--shared-runtime',type=Path,default=SHARED)
    parser.add_argument('--pending',type=Path)
    parser.add_argument('--attempt')
    parser.add_argument('--unit')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--probe-runtime',type=Path)
    args=parser.parse_args()
    if args.action in {'probe-orphan','probe-contend'}:
        if not args.probe_runtime: parser.error('--probe-runtime required')
        return probe_orphan(args.probe_runtime) if args.action=='probe-orphan' else probe_contend(args.probe_runtime)
    config=read_config(args.config)
    if args.unit: config=dict(config,new_unit=args.unit); validate_config(config)
    runtime=args.runtime or args.shared_runtime/'baseline'
    if args.action=='audit': result=audit(config)
    elif args.action=='run':
        result=run(config,runtime,args.shared_runtime,args.pending or args.shared_runtime/'master_pending.json',args.config)
    elif args.action=='guard':
        if not args.attempt: parser.error('--attempt required')
        result=guard(config,runtime,args.shared_runtime,args.attempt)
    elif args.action=='probe':
        if not args.output: parser.error('--output required')
        result=capability_probe(args.output)
    else: result=read(runtime/'state.json') if (runtime/'state.json').exists() else {'status':'NOT_STARTED'}
    if result is not None: print(json.dumps(result,sort_keys=True,indent=2))


if __name__=='__main__': main()
