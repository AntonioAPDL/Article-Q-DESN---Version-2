#!/usr/bin/env python3
"""Source-gated, fit-free held-out validation diagnosis for HR and DK_1."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS',
            'BLIS_NUM_THREADS','NUMEXPR_NUM_THREADS','R_DATATABLE_NUM_THREADS'):
    os.environ[key]='1'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
sys.dont_write_bytecode=True

import numpy as np
import pandas as pd
from pricefm_r130_attribution import validate_protocol, validation_grid, task_schedule, closeout

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
ENTRY=Path(__file__).resolve()
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
TAG='pricefm_stage_r130_forecast_error_attribution_20261010'
OUT=DATA/'campaigns'/TAG
PREP=DATA/'launch_prep'/TAG
PROTOCOL=ROOT/'application/config'/(TAG+'.json')
PLAN=ROOT/'local_trackers/pricefm_stage_r130_master_diagnosis_plan_20261010.md'


def git(path,*args):
    return subprocess.check_output(['git','-C',str(path),*args],text=True).strip()


def identity():
    branch=git(ROOT,'branch','--show-current')
    if not branch.startswith('work/pricefm-r130-') or git(ROOT,'status','--porcelain'):
        raise RuntimeError('committed clean dedicated R130 source required')
    return dict(branch=branch,head=git(ROOT,'rev-parse','HEAD'))


def setup(dependency,r128):
    global runtime,core,read,write,immutable,digest,seal,verified,verify_hashes,replay
    sys.path.insert(0,str(Path(dependency)/'application/scripts/pricefm'))
    from pricefm_r126_contract import read,write,immutable,digest,seal,verified,verify_hashes
    from pricefm_r127_forecast import replay
    import pricefm_r123_runtime as runtime
    path=Path(r128)/'application/scripts/pricefm/pricefm_r128_core.py'
    spec=importlib.util.spec_from_file_location('r130_frozen_regional_core',path)
    core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)


def release(dependency,r128):
    source=identity();setup(dependency,r128)
    path=DATA/'runtime_audits'/TAG/('release_'+os.uname().nodename+'_'+source['head'][:12])
    path.mkdir(parents=True,exist_ok=False)
    junit=path/'pytest.xml'
    env=dict(os.environ,PRICEFM_R130_DEPENDENCY=str(dependency),PRICEFM_R130_R128=str(r128))
    with (path/'pytest.log').open('w') as log:
        result=subprocess.run([sys.executable,'-B','-m','pytest','-q',
            str(ROOT/'application/tests/test_pricefm_stage_r130_attribution.py'),
            str(Path(dependency)/'application/tests/test_pricefm_stage_r127_driver_diagnosis.py'),
            '-p','no:cacheprovider','--junitxml='+str(junit)],env=env,cwd=ROOT,
            stdout=log,stderr=subprocess.STDOUT)
    suites=ET.parse(junit).getroot().findall('testsuite')
    totals={k:sum(int(s.get(k,'0')) for s in suites) for k in ('tests','failures','errors','skipped')}
    value=dict(source=source,**totals,passed=result.returncode==0 and totals['tests']>=50
        and sum(totals[k] for k in ('failures','errors','skipped'))==0)
    write(path/'validation.json',value)
    if not value['passed']:raise RuntimeError('release failed; inspect '+str(path))
    return dict(path=str(path/'validation.json'),**value)


def preparation(parent,r128,dependency,receipt):
    p=read(PROTOCOL);validate_protocol(p);source=identity()
    for label,path,key in [('R129B',parent,'parent_head'),('R128',r128,'r128_head'),
                           ('R127',dependency,'dependency_head')]:
        if git(path,'rev-parse','HEAD')!=p[key] or git(path,'status','--porcelain'):
            raise RuntimeError(label+' frozen source differs')
    release=read(receipt)
    if release['source']!=source or not release['passed']:raise RuntimeError('source-matched release required')
    parent_out=DATA/'campaigns'/p['parent_tag']
    parent_prep_path=DATA/'launch_prep'/p['parent_tag']/'preparation.json'
    previous=read(parent_prep_path)
    if previous['source']['head']!=p['parent_head'] or read(parent_out/'terminal.json')['status']!='R129B_COMPLETE_NOT_PROMOTED':
        raise RuntimeError('completed frozen parent required')
    verify_hashes(previous['source_sha256']);verify_hashes(previous['inherited_source_sha256'])
    verify_hashes(previous['input_sha256']);verified(parent_out/'closeout')
    if digest(DATA/'raw/FINAL.csv')!=previous['raw_identity']['sha256']:
        raise RuntimeError('raw source changed')
    for f in Path('/proc').glob('[0-9]*/cmdline'):
        try:parts=f.read_bytes().split(b'\0')
        except OSError:continue
        if any(str(Path(parent)/'application/scripts/pricefm/459_run_pricefm_stage_r129_recovery.py').encode()==v for v in parts):
            raise RuntimeError('parent campaign still active')
    own_files=[ENTRY,HERE/'pricefm_r130_attribution.py',PROTOCOL,
        ROOT/'application/tests/test_pricefm_stage_r130_attribution.py',
        ROOT/'application/notes/pricefm_stage_r130_forecast_error_attribution_20261010.md']
    sources={str(f):digest(f) for f in own_files}
    sources.update(previous['source_sha256']);sources.update(previous['inherited_source_sha256'])
    inputs={str(f):digest(f) for f in (parent_prep_path,parent_out/'terminal.json',
        parent_out/'closeout/completed_evidence.json',Path(receipt),PLAN)}
    # Seal provenance includes all official predictions; their scores are descriptive only.
    inputs.update({str(parent_out/'closeout'/k):h for k,h in
        read(parent_out/'closeout/completed_evidence.json')['artifacts'].items()})
    for task in previous['tasks']:
        folder=parent_out/'tasks_done'/task['name'];verified(folder)
        inputs[str(folder/'completed_evidence.json')]=digest(folder/'completed_evidence.json')
        inputs.update({str(folder/k):h for k,h in read(folder/'completed_evidence.json')['artifacts'].items()})
    cells=[];official=previous['official_protocol'];old=Path(previous['parent_out'])
    for region in p['regions']:
        choice=previous['choices'][region]
        if not choice['selected_before_test']:raise RuntimeError('unfrozen regional choice')
        for fold in p['folds']:
            prefix=f'{region}_fold{fold}'
            design=old/'tasks_done'/(prefix+'_design')/'design'
            normal=old/'tasks_done'/(prefix+'_normal')/'fit'
            info=read(design/'design.json');scaler=read(design/'scaler.json')
            driver=read(normal/'terminal.json')
            train_end=official['train_end_market'][fold-1]
            test_start=official['test_intervals_market'][fold-1][0]
            if info['response_end_exclusive']!=train_end or info['test_opened'] or info['source_specification_sha256']!=choice['specification_sha256']:
                raise RuntimeError('fitted response cutoff or architecture differs')
            if (not driver['full_variational_certified'] or driver['prior_type']!='rhs_ns'
                    or driver['tau0']!=choice['tau0'] or driver['p']!=info['p']
                    or driver['test_opened'] or driver['prior_center_from_initializer']):
                raise RuntimeError('Normal driver target or certification differs')
            verified(design.parent);verified(normal.parent)
            inputs.update({str(folder/k):h for folder in (design.parent,normal.parent)
                for k,h in read(folder/'completed_evidence.json')['artifacts'].items()})
            quantile_dirs={}
            for q in p['quantiles']:
                folder=parent_out/'tasks_done'/(prefix+f'_al{q:.2f}')/'fit';terminal=read(folder/'terminal.json')
                if not terminal['independent_fixedpoint_certified'] or terminal['tau0']!=choice['tau0']:
                    raise RuntimeError('uncertified or changed receiver prior')
                quantile_dirs[str(q)]=str(folder)
            grid=validation_grid(train_end,test_start,p)
            frame=core.read_frame(DATA/'raw/FINAL.csv',runtime.active_regions(choice['spec']),test_start)
            origins=pd.DatetimeIndex(pd.to_datetime([r['anchor'] for r in grid],utc=True))
            arrays=core.regional_arrays(runtime,frame,origins,choice['spec'])
            from pricefm_r126_contract import transform
            scaled=transform(arrays,scaler,runtime.ExplicitArrays)
            bank=OUT/'validation_banks'/f'{prefix}.npz';bank.parent.mkdir(parents=True,exist_ok=True)
            if bank.exists():raise RuntimeError('preparation must not overwrite a prior bank')
            core.save_arrays(bank,scaled);inputs[str(bank)]=digest(bank)
            cells.append(dict(region=region,fold=fold,spec=choice['spec'],tau0=choice['tau0'],
                train_end=train_end,test_start=test_start,grid=grid,bank=str(bank),
                scaler=scaler,normal_dir=str(normal),quantile_dirs=quantile_dirs,
                original_median=str(old/'tasks_done'/(prefix+'_al0.50')/'fit')))
            median_trace=Path(cells[-1]['original_median'])/'vb_trace.csv'
            inputs[str(median_trace)]=digest(median_trace)
    tasks=task_schedule(cells,p)
    value=dict(source=source,protocol=p,parent_source=str(parent),r128_source=str(r128),
        dependency=str(dependency),parent_out=str(parent_out),source_sha256=sources,
        input_sha256=inputs,raw_sha256=previous['raw_identity']['sha256'],release=str(receipt),
        cells=cells,tasks=tasks,parent_tasks=previous['tasks'],official_protocol=official,
        new_fits=0,diagnostic_origins=288,official_test_reforecast=False)
    immutable(PREP/'preparation.json',value)
    for task in tasks:immutable(OUT/'tasks'/(task['name']+'.json'),task)
    return dict(status='R130_PREPARED',tasks=len(tasks),smoke_tasks=24,new_fits=0,origins=288)


def valid(prep,full=False):
    if identity()!=prep['source'] or read(PROTOCOL)!=prep['protocol']:
        raise RuntimeError('executed source/protocol changed')
    verify_hashes(prep['source_sha256'])
    if full:verify_hashes(prep['input_sha256'])
    for path,key in ((prep['parent_source'],'parent_head'),(prep['r128_source'],'r128_head'),
                     (prep['dependency'],'dependency_head')):
        if git(path,'rev-parse','HEAD')!=prep['protocol'][key]:raise RuntimeError('frozen dependency head changed')
    for task in prep['tasks']:
        if read(OUT/'tasks'/(task['name']+'.json'))!=task:raise RuntimeError('task schedule changed')


def worker(name,cpu):
    prep=json.loads((PREP/'preparation.json').read_text());setup(prep['dependency'],prep['r128_source']);valid(prep)
    os.sched_setaffinity(0,{cpu});task=read(OUT/'tasks'/(name+'.json'))
    if (OUT/'tasks_done'/name).exists():
        verified(OUT/'tasks_done'/name);return
    cell=next(c for c in prep['cells'] if (c['region'],c['fold'])==(task['region'],task['fold']))
    verify_hashes({cell['bank']:prep['input_sha256'][cell['bank']]})
    arrays=runtime.subset_arrays(core.load_arrays(runtime,Path(cell['bank'])),task['bank_indices'])
    from pricefm_r130_attribution import check_support
    check_support(arrays.anchors,cell['train_end'],cell['test_start'])
    normal=runtime.load_normal_fit(Path(cell['normal_dir']))
    quantiles={float(q):runtime.load_quantile_fit(Path(folder)) for q,folder in cell['quantile_dirs'].items()}
    beat=lambda v:write(OUT/'heartbeats'/(name+'.json'),dict(v,epoch=time.time(),cpu=cpu))
    start=time.time()
    values,audit=replay(runtime,arrays,cell['spec'],quantiles,task['positions'],
        runtime.BASE.deterministic_seed(2026101001,task['region'],task['fold'],'validation'),normal,observe=beat)
    scaler=cell['scaler']
    for key in ('truth','stochastic','parameter_only','mean_driver','oracle','driver_mean'):
        values[key]=values[key]*scaler['price_scale']+scaler['price_mean']
    values['driver_sd']*=scaler['price_scale']
    values['median_variance_terms']*=scaler['price_scale']**2
    # Fixed per-lead mask is not origin-indexed; store only its selected slice.
    values['median_variance_terms']=values['median_variance_terms'][:,values.pop('variance_lead_mask')]
    values.update(bank_indices=np.asarray(task['bank_indices']),positions=np.asarray(task['positions']),
        anchors_ns=pd.DatetimeIndex(pd.to_datetime(arrays.anchors,utc=True)).as_unit('ns').asi8)
    if not all(np.isfinite(v).all() for v in values.values()):raise RuntimeError('nonfinite saved diagnostic')
    audit.update(region=task['region'],fold=task['fold'],offset_steps=task['offset'],
        response_end_exclusive=cell['test_start'],fitted_response_end=cell['train_end'],
        test_opened=False,units='EUR/MWh',seed_identity='original day*96+clock offset')
    (OUT/'staging').mkdir(exist_ok=True)
    tmp=Path(tempfile.mkdtemp(prefix=name+'.',dir=OUT/'staging'))
    np.savez_compressed(tmp/'predictions.npz',**values);write(tmp/'audit.json',audit)
    seal(tmp,dict(task=task,source=prep['source'],elapsed_seconds=time.time()-start,
        certified=True,first_horizon_difference=audit['max_h0_difference']))
    dest=OUT/'tasks_done'/name;dest.parent.mkdir(exist_ok=True)
    if dest.exists():raise RuntimeError('duplicate task writer')
    tmp.rename(dest)


def resources(p):
    mem={s.split(':')[0]:int(s.split()[1])*1024 for s in Path('/proc/meminfo').read_text().splitlines()}
    free=shutil.disk_usage(DATA).free/2**30
    used=sum(f.stat().st_size for f in OUT.rglob('*') if f.is_file())/2**30
    if mem['MemAvailable']/2**30<p['minimum_free_memory_GiB'] or free<p['minimum_free_disk_GiB']+.03 or used>.70:
        raise RuntimeError('resource reserve reached; drain own workers, retain pending')
    return dict(available_memory_GiB=mem['MemAvailable']/2**30,free_disk_GiB=free,campaign_GiB=used)


def batch(tasks,cpus,prep,stage):
    waiting=[t for t in tasks if not (OUT/'tasks_done'/t['name']/'completed_evidence.json').exists()]
    for task in tasks:
        folder=OUT/'tasks_done'/task['name']
        if folder.exists():verified(folder)
    running={};free=list(cpus);failed=[];resource_error=None
    while waiting or running:
        try:res=resources(prep['protocol'])
        except RuntimeError as error:resource_error=str(error);res={}
        while waiting and free and not failed and not resource_error:
            task=waiting.pop(0);cpu=free.pop(0)
            log=(OUT/'worker_logs'/(task['name']+'.log')).open('a')
            process=subprocess.Popen([sys.executable,'-B',str(ENTRY),'worker','--name',task['name'],'--cpu',str(cpu)],
                stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            running[task['name']]=(process,cpu,log)
        for name,(process,cpu,log) in list(running.items()):
            code=process.poll()
            if code is None:continue
            log.close();free.append(cpu);del running[name]
            if code:failed.append(dict(task=name,exit_code=code))
            else:
                try:
                    metadata=verified(OUT/'tasks_done'/name)
                    if metadata['source']!=prep['source'] or metadata['first_horizon_difference']>1e-8:
                        raise RuntimeError('source/first-step gate failed')
                except Exception as error:failed.append(dict(task=name,error=str(error)))
        write(OUT/'progress.json',dict(stage=stage,active=len(running),pending=len(waiting),
            completed=sum((OUT/'tasks_done'/t['name']/'completed_evidence.json').exists() for t in prep['tasks']),
            total=len(prep['tasks']),failures=failed,resource_error=resource_error,resources=res,epoch=time.time()))
        if not running and (failed or resource_error):raise RuntimeError(str(failed or resource_error))
        if waiting or running:time.sleep(5)


def controller(workers):
    prep=json.loads((PREP/'preparation.json').read_text());setup(prep['dependency'],prep['r128_source'])
    valid(prep,full=True)
    if not 1<=workers<=15:raise ValueError('physical worker cap is 15')
    for f in Path('/proc').glob('[0-9]*/cmdline'):
        try:parts=f.read_bytes().split(b'\0')
        except OSError:continue
        if str(ENTRY).encode() in parts and b'worker' in parts:raise RuntimeError('live own worker; do not duplicate')
    with (OUT/'controller.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if (OUT/'terminal.json').exists():
            verified(OUT/'closeout');return
        if (OUT/'staging').exists() and list((OUT/'staging').iterdir()):
            raise RuntimeError('unsealed partial task requires inspection; no automatic cleanup')
        prior=core.module('r130_frozen_scheduler',Path(prep['dependency'])/'application/scripts/pricefm/450_run_pricefm_stage_r127_driver_diagnosis.py')
        cpus=prior.cpu_pool(workers);resources(prep['protocol'])
        (OUT/'worker_logs').mkdir(exist_ok=True)
        write(OUT/'controller_identity.json',dict(pid=os.getpid(),cpus=cpus,source=prep['source'],epoch=time.time()))
        try:
            batch([t for t in prep['tasks'] if t['smoke']],cpus,prep,'first_origin_smoke_gate')
            immutable(OUT/'smoke_gate.json',dict(passed=True,tasks=24,source=prep['source']))
            batch([t for t in prep['tasks'] if not t['smoke']],cpus,prep,'heldout_paired_controls')
            valid(prep,full=True)
            if digest(DATA/'raw/FINAL.csv')!=prep['raw_sha256']:raise RuntimeError('raw content changed')
            from pricefm_r127_contract import common_metrics
            closeout(OUT,prep,verified,read,write,seal,common_metrics)
            write(OUT/'terminal.json',dict(status='R130_COMPLETE_NOT_PROMOTED',source=prep['source'],
                tasks=120,diagnostic_origins=288,new_fits=0))
        except Exception as error:
            write(OUT/'blocked.json',dict(error=str(error),source=prep['source'],epoch=time.time(),
                parent_untouched=True,automatic_correction=False));raise


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('release','prepare','controller','worker'))
    for name in ('parent','r128','dependency','release'):parser.add_argument('--'+name,type=Path)
    parser.add_argument('--workers',type=int,default=15);parser.add_argument('--name');parser.add_argument('--cpu',type=int)
    a=parser.parse_args()
    if a.action=='release':print(release(a.dependency,a.r128),flush=True)
    elif a.action=='prepare':
        setup(a.dependency,a.r128);print(preparation(a.parent,a.r128,a.dependency,a.release),flush=True)
    elif a.action=='controller':controller(a.workers)
    else:worker(a.name,a.cpu)
