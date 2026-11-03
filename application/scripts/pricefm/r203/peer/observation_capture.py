"""Exact native metadata transport for one separately funded r203 operation.

This module does not submit jobs, run remote interpreters, build, load ELF,
renew an owner or poll. Archives contain explicitly granted metadata only.
Every partial operation and native reply is retained; create-only installs
commit RELEASE.ready last, after exact native byte verification.
"""
import hashlib,importlib.util,io,json,os,re,resource,select,shlex,signal,stat,subprocess,sys,tarfile,time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
p=ROOT/'common/metadata.py';raw=p.read_bytes()
if hashlib.sha256(raw).hexdigest()!='6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':
    raise ValueError('immutable basic metadata primitives')
sp=importlib.util.spec_from_file_location('_r203_transport_metadata',p)
m=importlib.util.module_from_spec(sp);exec(compile(raw,str(p),'exec'),m.__dict__)
LEGACY=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r165_headroom_execution_20261029_1526PDT/legacy_node13_execution_20261101_1250PST/scheduler/legacy_scheduler.py')
LEGACY_SHA='4b5210befbbd4193c528d591b9bd30f904ecd16552a0cb7ef2692f3288738e6c'
SITE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_hb_scientific_preparation_20261027/site.canonical.json')
SITE_SHA='09164aefd8b52d135e88d2e1e6c83f8a5135b252d979344decb7040f4ba4ad38'
HOME_PARENT=Path('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa')
MAX_FILE=16*1024**2;MAX_TOTAL=64*1024**2
CLOCK=['env','TZ=UTC','date','--utc','+%Y-%m-%dT%H:%M:%SZ|%s|%z|%Z']
def before_records():
    m.require(os.sched_getaffinity(0)=={31} and resource.getrlimit(resource.RLIMIT_CPU)==(8,8)
      and os.getpid()==os.getsid(0)==os.getpgrp(),'actual original H8 before capture inputs')
    s=dict(v.split(':',1) for v in Path('/proc/self/status').read_text().splitlines() if ':' in v)
    m.require(s.get('NoNewPrivs','').strip()=='1' and s.get('Seccomp','').strip()=='2','actual H kernel boundary')
def birth():
    return int(Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19])
def _metadata_pin(pin):
    m.descriptor(pin);p=m.absolute(pin['path'])
    m.require(p.suffix in {'.json','.stdout','.stderr','.txt','.md','.sh'} and 'target_cache' not in p.parts
      and not any(v in p.parts for v in ('target_data','runtime_envs','.ssh')),'explicit metadata only; no credentials/binaries/data')
    base=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers')
    local=p.is_relative_to(base) and (p.relative_to(base).parts[0].startswith('pricefm_') or (len(p.relative_to(base).parts)>1 and p.relative_to(base).parts[0]=='worktrees' and p.relative_to(base).parts[1].startswith('pricefm_')))
    m.require(local or p.is_relative_to(Path('/home/jaguir26/.local/state/pricefm')),'PriceFM canonical metadata only')
    return p
def _proof_pin(path):
    raw=m.read_regular(path,limit=MAX_TOTAL//2,expected_uid=os.getuid())
    return dict(path=str(path),sha256=hashlib.sha256(raw).hexdigest())

def _load_transport():
    raw=m.read_regular(LEGACY,limit=256*1024,expected_sha=LEGACY_SHA)
    sp=importlib.util.spec_from_file_location('_r203_fixed_legacy_ssh',LEGACY)
    x=importlib.util.module_from_spec(sp);exec(compile(raw,str(LEGACY),'exec'),x.__dict__)
    site=m.strict_json(m.read_regular(SITE,limit=64*1024,expected_sha=SITE_SHA))
    m.require(site['host']=='hb.ucsc.edu' and site['user']=='jaguir26','approved exact native endpoint')
    return ['/usr/bin/ssh','-T',*x.ssh_options(site),site['user']+'@'+site['host']]
def _native(ssh,argv,root,index,deadline,stdin=b'',limit=1024**2,binary=False):
    m.require(type(limit) is int and 0<limit<=MAX_FILE-65536,'reserve one complete native read chunk inside retained leaf cap')
    m.require(type(argv) is list and argv and all(type(v) is str and '\0' not in v and '\n' not in v for v in argv),'closed native argv')
    m.require(0<len(stdin)<=MAX_TOTAL if stdin else True,'bounded native input')
    rawout=bytearray();rawerr=bytearray();sent=0
    command=subprocess.Popen([*ssh,'TZ=UTC SLURM_TIME_FORMAT='+shlex.quote('%Y-%m-%dT%H:%M:%S%z')+' '+shlex.join(argv)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,close_fds=True,env=dict(PATH='/usr/bin:/bin',TZ='UTC',LANG='C',LC_ALL='C'))
    for pipe in (command.stdin,command.stdout,command.stderr):os.set_blocking(pipe.fileno(),False)
    reads={command.stdout.fileno():rawout,command.stderr.fileno():rawerr}
    inputfd=command.stdin.fileno();writing=True
    try:
        while reads or writing:
            m.require(time.time()<deadline,'original fixed capture deadline; no retries')
            ready,writes,_=select.select(list(reads),[inputfd] if writing else [],[],min(.1,max(0,deadline-time.time())))
            if inputfd in writes:
                if sent<len(stdin):sent+=os.write(inputfd,stdin[sent:sent+65536])
                if sent==len(stdin):command.stdin.close();writing=False
            for fd in ready:
                chunk=os.read(fd,65536)
                if chunk:reads[fd].extend(chunk)
                else:reads.pop(fd)
            m.require(len(rawout)<=limit and len(rawerr)<=1024**2,'bounded complete native reply')
        rc=command.wait(timeout=max(.001,deadline-time.time()))
    except BaseException:
        if command.poll() is None:command.kill()
        command.wait()
        (root/f'native_{index:03d}.partial.stdout').write_bytes(rawout)
        (root/f'native_{index:03d}.partial.stderr').write_bytes(rawerr)
        raise
    out=root/f'native_{index:03d}.stdout';err=root/f'native_{index:03d}.stderr'
    for path,value in ((out,rawout),(err,rawerr)):
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as f:f.write(value);f.flush();os.fsync(f.fileno())
    reply=dict(argv=argv,returncode=rc,stdout='' if binary else bytes(rawout).decode('utf-8','strict'),
      stderr=bytes(rawerr).decode('utf-8','strict'))
    m.write_new(root/f'native_{index:03d}.json',dict(reply,stdout_capture=_proof_pin(out),stderr_capture=_proof_pin(err),binary_metadata_envelope=binary))
    return reply,bytes(rawout)
def _funded(r):
    b=r['binding'];m.require(b['parameters_sha256']==m.digest(b['parameters']) and b['physical_profile']==b['parameters']['common']['physical_profile'],'exact prospective capture parameters/profile')
    s=m.linked(b['scope']);l=m.linked(b['ledger']);q=m.linked(b['quote'])
    qr=m.linked(q['independent_review']);qc=dict(q);qc.pop('independent_review')
    m.require(qr.get('status')=='PASS_REVIEWED_R203_CONTROL_STAGE_QUOTE' and qr.get('quote_core_sha256')==m.digest(qc),'independent complete quote')
    m.require(s.get('status')=='ROOT_FUNDED_R203_CONTROL_STAGE_NO_TARGETS'
      and type(s.get('compute_CPU_reservation')) is int and s['compute_CPU_reservation']>0
      and s.get('optimizer_invocations')==s.get('new_posterior_fits')==0,'new positive separately funded role, source448 denied')
    m.require(s.get('remote_namespace')==b['output_root'],'exact funded native namespace')
    m.require(s.get('quote')==b['quote'] and l.get('scopes',[])[-1].get('scope')==b['scope'],'append-only funded capture scope')
    for key in ('purpose','nonce','stage','control_publication','control_map_sha256','runtime_publication','runtime_map_sha256','parameters_sha256'):
        m.require(s.get(key)==b[key],'capture funding binding '+key)
    m.require(s['issued_epoch']<=time.time()<r['expires_epoch']<=s['expires_epoch']
      and r['issued_epoch']<=time.time() and r['remote_unknown_CPU_reservation']==8
      and q['remote_unknown_CPU_reservation']>=8 and q['administrative_CPU_reservation']>=8,'fixed one H8 plus remote8 reservation')
    pub=m.linked(b['control_publication']);m.require(pub['files']['peer/observation_capture.py']==m.pin_file(__file__)['sha256'],'published transport code')
    baseline=m.linked(b['expected_startup_baseline']);m.require(baseline['parameters_sha256']==b['parameters_sha256'],'expected baseline exact parameters')
    facility=m.linked(baseline['facility_policy'])
    t=dict(node=b['node'],parameters=b['parameters'],issued_epoch=s['issued_epoch'],expires_epoch=s['expires_epoch'],control_sources={k:dict(path=str(ROOT/k),sha256=v) for k,v in pub['files'].items()})
    peer=_independent();peer.clean_launch_contract(facility['native_clean_launch_contract'],t)
    profile=m.linked(b['physical_profile']);m.require(profile['memory_MiB']==q['memory_MiB'] and profile['node']==b['node'],'literal profile equals funded resource quote')
    peer.profile_values(profile,q['owner_wall_seconds'],b['parameters']['common']['canonical_metadata_root'],b['nonce'])
    return b
def _archive(ssh,pins,root,deadline,index):
    m.require(type(pins) is list and len(pins)<=256,'fixed explicit proof closure')
    paths=[str(_metadata_pin(dict(path=p['path'],sha256=p['sha256'] or '0'*64))) for p in pins];m.require(len(set(paths))==len(paths),'unique proof paths')
    if not pins:return [],index
    real,_=_native(ssh,['realpath','--',*paths],root,index,deadline);index+=1
    m.require(real['returncode']==0 and real['stderr']=='' and real['stdout'].splitlines()==paths,'actual canonical paths; no shared-filesystem or parent-symlink assumption')
    args=['tar','--absolute-names','--create','--file=-','--no-recursion','--verbatim-files-from','--null','--files-from=-']
    reply,data=_native(ssh,args,root,index,deadline,stdin=b''.join(p.encode()+b'\0' for p in paths),limit=MAX_FILE-65536,binary=True)
    m.require(reply['returncode']==0 and reply['stderr']=='','exact metadata archive native success')
    expected={str(p):pin for p,pin in zip(paths,pins)};records=[];total=0
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:') as archive:
        members=archive.getmembers();m.require(len(members)==len(expected),'exact metadata archive members')
        seen=set()
        for member in members:
            m.require(member.name in expected and member.name not in seen and member.isfile()
              and not member.issym() and not member.islnk() and 0<=member.size<=MAX_FILE,'regular bounded granted metadata only')
            seen.add(member.name);pin=expected[member.name];stream=archive.extractfile(member)
            raw=stream.read(MAX_FILE+1);total+=len(raw)
            m.require(len(raw)==member.size and total<=MAX_TOTAL and (pin['sha256'] is None or hashlib.sha256(raw).hexdigest()==pin['sha256']),'exact native metadata bytes')
            path=root/f'copy_{len(records):03d}{Path(pin["path"]).suffix}'
            fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
            records.append(dict(remote_path=pin['path'],sha256=hashlib.sha256(raw).hexdigest(),local_copy=_proof_pin(path)))
    return records,index+1
def _independent():
    path=ROOT/'peer/independent_peer.py'
    raw=m.read_regular(path,limit=512*1024,expected_sha='b2f124fd3d10d4cd28a255b32fa4ba0ddfe57204a0cf8d673892083dec3dccd7')
    sp=importlib.util.spec_from_file_location('_r203_native_admission_peer',path)
    x=importlib.util.module_from_spec(sp);exec(compile(raw,str(path),'exec'),x.__dict__)
    return x

def _admin():
    path=ROOT/'peer/admin_context.py'
    raw=m.read_regular(path,limit=128*1024,expected_sha='a877ebc7ae8a183b17eddaf1a7f28e4ea07df79c6c7e3f932251af612fc3a6ea')
    sp=importlib.util.spec_from_file_location('_r203_transport_admin',path)
    x=importlib.util.module_from_spec(sp);exec(compile(raw,str(path),'exec'),x.__dict__)
    return x

def run(pin):
    before_records();r=m.linked(pin)
    m.closed(r,{'schema','status','administrative_grant','mode','binding','job_id','template','request','canonical_inputs','create_inputs',
      'existing_inputs','discover_names','release_marker','output_directory','issued_epoch','expires_epoch','remote_unknown_CPU_reservation'},'one native metadata operation')
    m.require(r['schema']=='r203_single_native_metadata_operation_v1'
      and r['status']=='ROOT_AUTHORIZED_R203_ONE_NATIVE_METADATA_OPERATION'
      and r['mode'] in {'ADMISSION','SOURCE_PHYSICAL','OWNER_READY','TERMINAL','INSTALL','SUBMIT'},'closed operation')
    b=_funded(r)
    operation=('READY_DISCOVERY' if r['mode']=='SOURCE_PHYSICAL' and r['request'] is None else
      ('INSTALL_BOOTSTRAP' if r['job_id'] is None else 'INSTALL_RELEASE') if r['mode']=='INSTALL' else r['mode'])
    g,root=_admin().grant(r['administrative_grant'],'CAPTURE_'+operation,m.pin_file(__file__),8,8)
    m.require(g['scope']==b['scope'] and g['ledger']==b['ledger'] and g['source_publication']==b['control_publication']
      and r['output_directory']==str(root),'same finite stage/action delegation')
    m.require(root.parent==HOME_PARENT and re.fullmatch('R203_[A-Za-z0-9_]{1,120}',root.name),'new approved private capture root')
    root.mkdir(mode=0o700);m.write_new(root/'INTENT.json',dict(operation=pin,started_epoch=time.time(),no_retries=True))
    ssh=_load_transport();deadline=min(r['expires_epoch'],time.time()+165);raw=[];index=0
    def call(argv,stdin=b''):
        nonlocal index
        value,_=_native(ssh,argv,root,index,deadline,stdin=stdin);index+=1;raw.append(value)
        m.require(value['returncode']==0,'native operation failed; preserve whole fee and stop')
        return value
    started=time.time();call(CLOCK)
    mode=r['mode']
    if mode=='ADMISSION':
        m.require(r['job_id'] is None and r['template'] is None and r['request'] is None,'no invented prejob identity')
        profile=m.linked(b['physical_profile']);m.require(profile['node']==b['node'],'selected profile')
        pc=dict(profile);pc.pop('independent_review');pr=m.linked(profile['independent_review'])
        m.require(pr.get('status')=='PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE' and pr.get('profile_core_sha256')==m.digest(pc),'reviewed exact profile')
        node=call(['scontrol','show','node',b['node'],'--oneliner'])
        fields=dict(re.findall(r'(RealMemory|AllocMem|CPUTot|CPUAlloc)=([^\s]+)',node['stdout']))
        m.require(all(fields.get(k,'').isdigit() for k in ('RealMemory','AllocMem','CPUTot','CPUAlloc')) and int(fields['RealMemory'])-int(fields['AllocMem'])>=m.linked(b['quote'])['memory_MiB'] and int(fields['CPUTot'])-int(fields['CPUAlloc'])>=profile['requested_CPUs'],'HOLD insufficient native scheduler resources; no forecast/job or retry')
        argv=profile['rendered_sbatch_argv'];m.require(Path(argv[0]).name=='sbatch' and argv[-1]==profile['job_script']['path'] and not any('--wrap' in a or '--array' in a or a=='--requeue' for a in argv),'reviewed exact direct command')
        call(argv[:-1]+['--test-only',argv[-1]])
    elif mode=='SUBMIT':
        m.require(r['job_id'] is None and r['request'] is None and r['canonical_inputs']==[] and r['discover_names']==[],'one initial native submission without invented job or payload transport')
        t,q=_independent().template(r['template']);profile=m.linked(t['parameters']['common']['physical_profile'])
        m.require(t['scope']==b['scope'] and t['parameters']==b['parameters'] and time.time()<=profile['latest_first_submit_epoch'],'same fixed admitted first-submit window')
        reply=call(profile['rendered_sbatch_argv'])
        match=re.fullmatch(r'(?:Submitted batch job )?([1-9][0-9]*)(?:;[A-Za-z0-9_.-]+)?\s*',reply['stdout'])
        m.require(match is not None,'one actual native Slurm allocation ID; uncertain submission never retries')
        submitted_job_id=match[1]
    elif mode in {'SOURCE_PHYSICAL','OWNER_READY','TERMINAL'}:
        m.require(re.fullmatch('[1-9][0-9]*',r['job_id']) is not None,'actual explicit owned job')
        t=m.linked(r['template']);m.require(t['output_root']==b['output_root'] and t['scope']==b['scope'] and t['parameters']==b['parameters'],'same actual funded template')
        if r['request'] is None:m.require(mode=='SOURCE_PHYSICAL','only initial actual READY discovery has no request')
        else:
            request=m.linked(r['request']);m.require(request['job_id']==r['job_id'] and request['template']==r['template'],'same actual request')
        if mode=='TERMINAL':
            call(['env','TZ=UTC','SLURM_TIME_FORMAT=%Y-%m-%dT%H:%M:%S%z','sacct','--noheader','--parsable2','--allocations','--jobs='+r['job_id'],
              '--format=JobIDRaw,JobName%96,State%48,User,UID,AllocCPUS,ElapsedRaw,CPUTimeRAW,MaxRSS,NodeList,Start,End,ExitCode,TotalCPU'])
            call(['find',t['output_root'],'-mindepth','1','-maxdepth','1','-printf',r'%f|%y|%s|%D|%i|%U|%n\n'])
        else:call(['scontrol','show','job',r['job_id'],'--oneliner'])
    else:
        m.require(r['canonical_inputs']==[] and len(r['create_inputs'])+len(r['existing_inputs'])<=256,'explicit install list only')
        seen=set()
        for row in r['existing_inputs']:
            path=str(_metadata_pin(row));canonical=call(['realpath','--',path]);m.require(canonical['stdout'].splitlines()==[path] and canonical['stderr']=='','actual existing canonical file')
            m.require(path not in seen,'unique installed proof');seen.add(path)
            v=call(['sha256sum','--',path]);m.require(v['stdout'].split()[0]==row['sha256'],'already existing immutable exact bytes')
        for row in r['create_inputs']:
            m.closed(row,{'destination','source'},'exact create-only canonical metadata row')
            destination=str(_metadata_pin(dict(path=row['destination'],sha256=row['source']['sha256'])))
            m.require(destination not in seen,'unique create-only canonical path');seen.add(destination)
            parent=call(['realpath','--',str(Path(destination).parent)]);m.require(parent['stdout'].splitlines()==[str(Path(destination).parent)] and parent['stderr']=='','actual canonical preprovisioned install parent')
            local=_metadata_pin(row['source']);data=m.read_regular(local,limit=MAX_FILE,expected_sha=row['source']['sha256'],expected_uid=os.getuid())
            call(['dd','of='+destination,'bs=65536','conv=excl,fsync','oflag=nofollow','status=none'],data)
            call(['sync','--',str(Path(destination).parent)])
            v=call(['sha256sum','--',destination]);m.require(v['stdout'].split()[0]==row['source']['sha256'],'native exact installed byte verification')
        if r['release_marker'] is not None:
            marker=m.absolute(r['release_marker']);m.require(marker.name=='RELEASE.ready' and str(marker.parent)==b['output_root'],'only fixed final commit marker')
            parent=call(['realpath','--',str(marker.parent)]);m.require(parent['stdout'].splitlines()==[str(marker.parent)] and parent['stderr']=='','actual canonical commit-marker parent')
            call(['dd','of='+str(marker),'bs=1','conv=excl,fsync','oflag=nofollow','status=none'])
            call(['sync','--',str(marker.parent)])
    pins=list(r['canonical_inputs']);names=list(r['discover_names'])
    if mode in {'SOURCE_PHYSICAL','OWNER_READY','TERMINAL'}:
        required=['reservation.json','startup_claim.json','source_capture.json','physical_witness.json','ready.json']
        if mode=='TERMINAL':
            required+=['stage_claim.json','raw_stage_result.json','proof_inventory.json','owner_usage.json']
            if t['stage']=='NATIVE_ABI_SUITE':
                required+=['abi_founder_observation.json']
                for ordinal,case in enumerate(('pre_ack_live','wrong_lifetime','wrong_permit','late_transition','repeat_transition','real_ACK','live_rechecks','noreplace_collision','bounded_storage'),1):
                    required+=['abi_descriptor_%02d.json'%ordinal,'abi_'+case+'.stdout','abi_'+case+'.stderr','abi_'+case+'.guard.json']
            else:
                prefix='build' if t['stage']=='OWNED_NATIVE_BUILD' else 'observer'
                required+=[prefix+'.stdout',prefix+'.stderr',prefix+'.guard.json']
        names=list(dict.fromkeys(names+required))
    m.require(type(names) is list and len(names)<=256 and len(set(names))==len(names),'closed unique discovery list')
    if names:
        m.require(mode in {'SOURCE_PHYSICAL','OWNER_READY','TERMINAL'},'no prejob/installer arbitrary discovery')
        allowed={v['name'] for v in t['parameters']['common']['storage_policy']['slots']}
        m.require(all(name in allowed and Path(name).suffix in {'.json','.stdout','.stderr','.txt'} for name in names),'only explicitly declared metadata/proof slots')
        existing={p['path'] for p in pins}
        pins += [dict(path=str(Path(t['output_root'])/name),sha256=None) for name in names if str(Path(t['output_root'])/name) not in existing]
    if mode=='TERMINAL':
        meta=Path(t['parameters']['common']['canonical_metadata_root'])
        pins += [dict(path=str(meta/('slurm_'+t['nonce']+suffix)),sha256=None) for suffix in ('.stdout','.stderr')]
    records,index=_archive(ssh,pins,root,deadline,index)
    call(CLOCK);completed=time.time()
    out=dict(schema='r203_owned_stage_metadata_capture_v1',status='CAPTURED_R203_ACTUAL_NATIVE_STAGE_METADATA_NOT_ADMISSION',
      mode=mode,purpose=b['purpose'],nonce=b['nonce'],stage=b['stage'],node=b['node'],job_id=r['job_id'],template=r['template'],request=r['request'],
      scope=b['scope'],ledger=b['ledger'],quote=b['quote'],parameters_sha256=b['parameters_sha256'],
      control_publication=b['control_publication'],control_map_sha256=b['control_map_sha256'],
      runtime_publication=b['runtime_publication'],runtime_map_sha256=b['runtime_map_sha256'],raw=raw,records=records,
      observed_epoch=started,completed_epoch=completed,command_pid=os.getpid(),command_birth_ticks=birth(),controller_source=m.pin_file(__file__))
    m.require(sum(p.stat().st_size for p in root.iterdir() if p.is_file())+len(m.canonical(out))<=MAX_TOTAL,'whole retained transport envelope/copies/replies64MiB')
    if mode=='SUBMIT':
        out.update(schema='r203_actual_single_native_submission_v1',status='SUBMITTED_ONE_R203_STAGE_NOT_RUNTIME_QUALIFIED',job_id=submitted_job_id)
    m.write_new(root/'RESULT.json',out);return out
if __name__=='__main__':
    before_records();m.require(len(sys.argv)==3,'exact operation path and SHA')
    print(json.dumps(run(dict(path=sys.argv[1],sha256=sys.argv[2])),sort_keys=True,allow_nan=False))
