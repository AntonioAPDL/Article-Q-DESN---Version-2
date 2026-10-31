"""Verify SI training boundaries and recursive source lineage from pinned JSON.

No numerical library is imported and no binary data, model, prediction or loss
is read or recomputed. This proves the declared source/sealed-metadata chain;
it explicitly does not re-prove the numerical contents of historical arrays.
"""
import argparse
import ast
from datetime import datetime, timedelta
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import time

SCHEMA = 'pricefm_SI_source_metadata_lineage_v1'
BOUNDARIES = ((506,631),(631,766),(766,940))
TAUS = (0.00024929739307713865,0.000024929739307713866)

def require(value, reason):
    if not value: raise ValueError(reason)

def pairs(items):
    value = {}
    for key,item in items:
        require(key not in value,'duplicate JSON key');value[key] = item
    return value

def loads(raw):
    value=json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda x: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    def finite(x):
        if isinstance(x,float):require(math.isfinite(x),'overflow JSON')
        if isinstance(x,dict):
            for y in x.values():finite(y)
        elif isinstance(x,list):
            for y in x:finite(y)
    finite(value);return value

def physical(path):
    path=Path(path)
    require(path.is_absolute() and not any(p.is_symlink() for p in (path,*path.parents)),'nonphysical path')
    return path

def pinned_bytes(item):
    path=physical(item['path']);before=path.stat()
    require(path.suffix in ('.json','.py') and stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid()
            and before.st_size<=16*1024**2,'unsafe metadata/source')
    raw=path.read_bytes();after=path.stat()
    require(all(getattr(before,k)==getattr(after,k) for k in ('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns')),'unstable metadata/source')
    require(hashlib.sha256(raw).hexdigest()==item['sha256'],'pinned input drift')
    return raw

def read(item):return loads(pinned_bytes(item))

def function(text,name):
    matches=[n for n in ast.parse(text).body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) and n.name==name]
    require(len(matches)==1,'missing/duplicate source function '+name)
    return matches[0]

def contains(node,expression):
    expected=ast.parse(expression).body[0]
    if isinstance(expected,ast.Expr):expected=expected.value
    return any(ast.dump(item,include_attributes=False)==ast.dump(expected,include_attributes=False) for item in ast.walk(node))

def source_contract(sources):
    trees={k:ast.parse(v) for k,v in sources.items()}
    require(contains(trees['r123'],'internal_splits = SUPPORT.internal_splits'),'runtime split alias changed')
    split=function(sources['r122'],'internal_splits')
    assignments=[n for n in ast.walk(split) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='boundaries' for t in n.targets)]
    require(len(assignments)==1 and ast.literal_eval(assignments[0].value)==BOUNDARIES,'inherited split boundaries changed')
    scaler=function(sources['r120'],'standardize_from_training_origins')
    for name in ('price_history','response','exog_history','exog_future'):
        require(contains(scaler,'arrays.'+name+'[idx]'),'scaler uses unbound origins: '+name)
    internal=function(sources['r141'],'scaled_internal')
    require(contains(internal,"cell = runtime.internal_splits(len(arrays.response))[split - 1]"),'split index changed')
    require(contains(internal,"runtime.standardize_from_training_origins(arrays, cell['train'])"),'scaler is not train-only')
    execute=function(sources['r141'],'execute')
    require(contains(execute,"scaled = core.slice_arrays(runtime, scaled, cell['train'])"),'design not sliced to training')
    require(contains(execute,"arrays.anchors[cell['validation'][0]]"),'boundary does not identify first validation origin')
    require(contains(function(sources['core'],'read_frame'),'15 * 60 * 10**9'),'quarter-hour source grid changed')
    regional=function(sources['core'],'regional_arrays')
    require(contains(regional,'y[p:p + 96]'),'response origin/horizon mapping changed')
    forced=function(sources['r120'],'teacher_forced_design')
    require(contains(forced,'response[start:stop] = arrays.response[:, horizon]'),'teacher-forced response rows misaligned')
    forecast=function(sources['replay'],'forecast')
    require(contains(forecast,'engine.explicit_input(arrays, spec, np.repeat(origin, paths), h, generated[:, :h])'),'recursive forecast uses unavailable target history')
    explicit=function(sources['r120'],'explicit_input')
    require(contains(explicit,'source = arrays.response[idx] if generated is None else np.asarray(generated, dtype=float)'),'generated target-lag branch changed')
    score=function(sources['core'],'quantile_internal_score')
    require(contains(score,"idx = split['validation']"),'internal score not bound to validation')
    require(contains(score,'shifted_windows(arrays, idx[positions], offset, idx)'),'shifted validation scope changed')
    shifted=function(sources['r127'],'shifted_windows')
    require(contains(shifted,'any(int(i) not in allowed or (offset and int(i + 1) not in allowed) for i in idx)'),
            'shifted response indices leave validation scope')
    identity=function(sources['r127'],'window_identity')
    require(contains(identity,'start < pd.Timestamp(training_end)') and
            contains(identity,'start + pd.Timedelta(days=1) > pd.Timestamp(validation_end)'),
            'shifted response window identity changed')
    return {'quarter_hour_minutes':15,'response_steps':96,'daily_origin_response_days':1,'fixed_common_origins':940,
            'training_stops':[x[0] for x in BOUNDARIES],'teacher_forced_training_and_recursive_validation_distinguished':True}

def validate_si(config):
    require(config['schema']==SCHEMA,'wrong lineage schema')
    preparation=read(config['preparation'])
    texts={}
    for role,item in config['sources'].items():
        require(preparation['source_sha256'].get(item['original_path'])==item['sha256'],'source not bound by captured preparation: '+role)
        texts[role]=pinned_bytes(item).decode()
    required={'r120','r122','r123','r141','core','replay','r127'}
    require(set(texts)==required,'source closure incomplete')
    contract=source_contract(texts)
    first=datetime.fromisoformat(preparation['official_protocol']['new_model_first_train_origin_market'])
    rows=[];seen=set();scalers_by_split={}
    for item in config['designs']:
        task,design,scaler,seal=(read(item[k]) for k in ('task','design','scaler','seal'))
        split=task['split'];tau=task['tau0'];identity=(split,tau)
        require(split in (1,2,3) and tau in TAUS and identity not in seen,'duplicate/unknown finalist split')
        seen.add(identity)
        require(task['kind']=='internal_design' and task['region']=='SI' and task['candidate_id']=='r134_996c377eeda607f0','wrong SI design identity')
        require(task['spec']['feature_policy']=='target_only' and task['spec']['region']=='SI','SI feature policy changed')
        require(task['spec']['units']==[192,192] and task['spec']['calendar']=='none','frozen SI geometry changed')
        require(seal['artifacts'].get('design/design.json')==item['design']['sha256'] and seal['artifacts'].get('design/scaler.json')==item['scaler']['sha256'],'design/scaler seal mismatch')
        require(seal['metadata']['task_sha256']==item['task']['sha256'],'sealed task mismatch')
        count=BOUNDARIES[split-1][0]
        require(type(scaler['training_origin_count']) is int and scaler['training_origin_count']==count,'scaler fit-count differs from inherited training block')
        require(design['region']=='SI' and design['split']==split and design['selection_stage']=='inner_training_only'
                and design['test_opened'] is False and design['source_specification_sha256']==task['specification_sha256'],'design training identity mismatch')
        require(design['n']==count*96 and design['p']==385,'teacher-forced row or readout dimension mismatch')
        cutoff=datetime.fromisoformat(design['response_end_exclusive'])
        expected=first+timedelta(days=count)
        require(cutoff==expected,'training response end is not first-validation origin')
        require(len(scaler['exog_mean'])==len(scaler['exog_scale'])==3 and all(x>0 for x in scaler['exog_scale']) and scaler['price_scale']>0,'SI own-exogenous scaler shape/scale mismatch')
        if split in scalers_by_split:require(scalers_by_split[split]==scaler,'paired tau scalers differ')
        scalers_by_split[split]=scaler
        rows.append({'split':split,'tau0':tau,'training_origins':count,'design_rows':design['n'],
                     'first_training_origin':first.isoformat(),'last_training_origin':(expected-timedelta(days=1)).isoformat(),
                     'last_training_response_end_exclusive':expected.isoformat(),'first_validation_origin':cutoff.isoformat(),
                     'sealed_scaler':item['scaler'],'design':item['design'],'metadata_boundary_match':True})
    require(seen=={(split,tau) for split in (1,2,3) for tau in TAUS},'missing finalist split lineage')
    return {'status':'PASS_PINNED_SOURCE_AND_SEALED_SI_METADATA_LINEAGE','schema':SCHEMA,'source_contract':contract,
            'designs':rows,'array_values_or_binary_bank_integrity_recomputed':False,
            'fresh_remote_execution_or_library_bytes_reaudited':False,'source_imported_or_executed':False,
            'limits':['Recorded source and sealed metadata establish declared fitting boundaries and recursive target-use semantics',
                      'Historical binary array values and live remote source/library state are not re-evaluated',
                      'This is provenance evidence, not a new score, fit, formal-convergence claim or screening authority']}

def main():
    resource.setrlimit(resource.RLIMIT_CPU,(8,8));signal.alarm(90)
    require(os.sched_getaffinity(0)=={31},'CPU31 metadata lane required')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',required=True);parser.add_argument('--config-sha256',required=True);parser.add_argument('--output',required=True)
    args=parser.parse_args()
    cfg=read({'path':args.config,'sha256':args.config_sha256});auth=read(cfg['authority'])
    require(auth['status']=='PROSPECTIVE_TRAINING_EVIDENCE_REPAIR_IMPLEMENTATION' and time.time()<auth['expires_epoch'],'fresh evidence scope required')
    out=physical(args.output);require(out.parent==Path(cfg['authority']['path']).parent,'output outside evidence scope')
    result=validate_si(cfg);result.update(created_epoch=time.time(),config={'path':args.config,'sha256':args.config_sha256},
                                        source={'path':str(Path(__file__).absolute()),'sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    with out.open('x') as f:json.dump(result,f,indent=2,sort_keys=True,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())
    print(json.dumps({'status':result['status'],'output':{'path':str(out),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()},'SELF_CPU':sum(resource.getrusage(resource.RUSAGE_SELF)[:2])}))

if __name__=='__main__':main()
