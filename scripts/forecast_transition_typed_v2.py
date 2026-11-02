#!/usr/bin/python3.11
"""Generated-only v2 central acceptance adapter; canonical v1 ledger unchanged."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess

class GateError(ValueError):
    pass

def require(ok, why):
    if not ok:
        raise GateError(why)

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024**2),b''):h.update(block)
    return h.hexdigest()

def read_json(path, cap=4*1024**2):
    path=Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size<=cap,'bounded nonsymlink JSON required')
    def pairs(items):
        result={}
        for k,v in items:
            require(k not in result,'duplicate JSON key');result[k]=v
        return result
    def invalid(x):raise GateError('nonfinite JSON '+x)
    return json.loads(path.read_text(),object_pairs_hook=pairs,parse_constant=invalid)

def number(value):
    require(type(value) in (int,float) and math.isfinite(value),'finite typed number required')
    return value

def sequence(value):
    return value if isinstance(value,list) else [value]

def validate_wire(wire,request):
    require(request.get('schema_version')=='mq_generated_workflow_request_v2' and
        request.get('execution_scope')=='generated_fixture_only' and request.get('production_authorized') is False,
        'production v2 dispatch is not admitted')
    require(wire.get('schema_version')=='mq_typed_numerical_wire_v2' and wire.get('execution_scope')=='generated_fixture_only'
        and wire.get('production_authorized') is False,'unsupported wire/scope')
    identity=request['identity'];require(wire['identity']==identity,'request/wire identity differs')
    for key,size in dict(source_commit=40,source_tree=40,source_manifest_sha256=64,posterior_target_sha256=64,
                        input_manifest_sha256=64,task_manifest_sha256=64).items():
        require(type(identity.get(key)) is str and re.fullmatch('[a-f0-9]{%d}'%size,identity[key]),'invalid identity '+key)
    require(identity.get('outer_conditioning')=='parameters_and_observed_origin_reservoir_state','changed conditioning')
    for key in ('task_id','rng_namespace'):
        require(type(identity.get(key)) is str and bool(identity[key]),'missing producer identity '+key)
    expected=sequence(request['expected_member_keys']);keys=sequence(wire['expected_member_keys'])
    require(expected and all(type(x) is str and bool(x) for x in expected) and
        len(set(expected))==len(expected) and keys==expected,'incomplete/relabelled expected members')
    expected_p=sequence(request.get('probabilities'));expected_h=sequence(request.get('horizons'))
    require(type(request.get('model_id')) is str and bool(request['model_id']),'explicit model required')
    require(len(expected_p)>=2 and all(0<number(x)<1 for x in expected_p) and
        all(a<b for a,b in zip(expected_p,expected_p[1:])),'explicit probability grid required')
    require(expected_h==list(range(1,len(expected_h)+1)) and len(expected_h)<=30 and
        all(type(x) is int for x in expected_h),'explicit horizon grid required')
    members=wire['members'];require(isinstance(members,list) and len(members)==len(keys),'member count differs')
    checked=[]
    for member,key in zip(members,keys):
        require(member['member_key']==key,'member key changed')
        require(member.get('model_id')==request['model_id'],'predeclared model changed')
        q=member['quantiles'];r=member['receipt'];c=r['stream_contract']
        require(r.get('schema_version')=='integrated_quantile_compact_receipt_v2' and
            r.get('method')=='mq_heldout_conditional_cdf_streaming_v1' and r['identity']==identity,'typed receipt/identity changed')
        for name in ('draw_id','origin_id'):
            require(type(member[name]) is str and member[name] and r[name]==member[name] and c[name]==member[name],
                'draw/origin/coupling identity changed')
        require(r['rng_namespace']==identity['rng_namespace']==c['rng_namespace'],'scientific stream namespace differs')
        require(c.get('schema_version')=='mq_streaming_cdf_certificate_contract_v1' and
            c.get('method')=='heldout_conditional_CDF_empirical_Bernstein_alpha_spending' and
            c.get('conditioning')=='one_fixed_original_parameter_draw_and_observed_origin' and
            c.get('validation_values')=='iid_future_path_conditional_CDF_not_particle_filter' and
            c.get('candidates_from_training_paths_only') is True,'wrong numerical method/conditioning')
        for flag in ('source_identity_authenticated','independent_stream_generation_authenticated',
                     'particle_filter_accuracy_certified','origin_filter_accuracy_certified','production_authorized'):
            require(c.get(flag,False) is False,'numeric receipt cannot authenticate '+flag)
        for name,value in dict(training_path_range=[1,65536],validation_path_range=[65537,327680],
            look_sizes=[65536,131072,262144],total_alpha=.05,absolute_quantile_tolerance=.01,
            relative_quantile_tolerance=.01).items():
            for x in sequence(c.get(name)):number(x)
            require(c.get(name)==value,'fixed precision policy changed: '+name)
        alpha=c['alpha_per_look'];require(len(alpha)==3 and all(abs(number(x)-.05/3)<=1e-16 for x in alpha)
            and sum(alpha)<=.05+1e-16,'alpha allocation changed')
        look=number(r['look_index']);require(look in (1,2,3),'unlisted optional look')
        n=number(r['validation_count']);require(n==c['look_sizes'][int(look)-1] and
            r['validation_first_path_id']==65537 and r['validation_last_path_id']==65536+n,'invalid validation prefix')
        require(type(r['validation_chain_sha256']) is str and re.fullmatch('[a-f0-9]{64}',r['validation_chain_sha256']),
            'validation replay identity missing')
        require(isinstance(q,list) and q,'empty quantile geometry')
        horizons=sorted({number(x['horizon']) for x in q});p=sorted({number(x['probability']) for x in q})
        require(horizons==list(range(1,len(horizons)+1)) and len(horizons)<=30 and len(p)>=2 and
            0<p[0]<p[-1]<1 and [(x['horizon'],x['probability']) for x in q]==[(h,a) for h in horizons for a in p],
            'changed/duplicate/incomplete probability-horizon grid')
        require(horizons==expected_h and p==expected_p,'predeclared probability/horizon grid changed')
        ends=[]
        for h in horizons:
            values=[number(x['quantile']) for x in q if x['horizon']==h]
            require(all(a<=b for a,b in zip(values,values[1:])),'crossed integrated candidates')
            for value in values:
                delta=max(.01,.01*abs(value));lower=number(value-delta);upper=number(value+delta)
                require(lower<upper,'unresolved candidate endpoints');ends.extend((lower,upper))
        means=r['cdf_mean'];M2=r['cdf_M2'];M=len(ends)
        require(len(means)==len(M2)==M,'CDF endpoint moment count differs')
        for mean,m2 in zip(means,M2):
            require(0<=number(mean)<=1 and 0<=number(m2)<=n*mean*(1-mean)+1e-8,'invalid bounded CDF moments')
        for h in horizons:
            indices=list(range((h-1)*2*len(p),h*2*len(p)));indices.sort(key=lambda j:ends[j])
            for a,b in zip(indices,indices[1:]):
                require(means[a]<=means[b]+1e-12,'nonmonotone endpoint CDF')
                if ends[a]==ends[b]:require(means[a]==means[b] and M2[a]==M2[b],'equal endpoints differ')
        split=c['training_split_diagnostic'];require(len(split)==len(q),'split count differs')
        for a,b in zip(split,q):
            require(a['horizon']==b['horizon'] and a['probability']==b['probability'],'split keys differ')
            absolute=number(a['split_stream_absolute_difference']);relative=number(a['split_stream_relative_difference'])
            require(absolute>=0 and relative>=0 and (absolute<=.005 or relative<=.005),'split REVIEW cannot be accepted')
        radii=[math.sqrt(2*(m2/(n-1))*math.log(4*M/alpha[int(look)-1])/n)+
               7*math.log(4*M/alpha[int(look)-1])/(3*(n-1)) for m2 in M2]
        for i,row in enumerate(q):
            require(min(1,means[2*i]+radii[2*i])<row['probability'] and
                max(0,means[2*i+1]-radii[2*i+1])>=row['probability'],'independent CDF bound REVIEW')
        checked.append(dict(member_key=key,validation_count=n,look_index=look,endpoint_count=M,maximum_radius=max(radii)))
    return checked

def accept_generated(packet,request,root=None):
    root=Path(root) if root else Path(__file__).resolve().parents[1]
    packet=Path(packet).resolve(strict=True)
    wire=read_json(packet/'numerical_wire.json');checked=validate_wire(wire,request)
    block=packet/'typed_block.rds'
    require(block.is_file() and not block.is_symlink() and block.stat().st_size<8*1024**2 and
        digest(block)==wire['block_file_sha256'],'compact block bytes changed')
    # Independent R decoding binds the JSON numerical values to the real block;
    # a forged passing sidecar cannot hide failing RDS sufficient statistics.
    env=dict(os.environ,LC_ALL='C',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1',
             R_LIBS_USER='/dev/null',R_LIBS_SITE='/dev/null')
    run=subprocess.run(['/data/jaguir26/local/opt/R/4.6.0/bin/Rscript','--vanilla',
        str(root/'scripts/validate_mq_typed_packet_v2.R'),'--generated-packet',str(packet)],
        cwd=root,env=env,capture_output=True,text=True,timeout=60)
    require(run.returncode==0,'independent block/sidecar decoding failed: '+run.stderr[-1000:])
    proof=json.loads(run.stdout)
    require(proof['block_file_sha256']==wire['block_file_sha256'] and proof['production_authorized'] is False,
        'independent validator returned wrong binding')
    return dict(schema_version='mq_generated_central_acceptance_v2',
        status='GENERATED_TYPED_V2_ACCEPTED_NOT_PRODUCTION',identity=request['identity'],
        expected_member_keys=sequence(request['expected_member_keys']),members=checked,
        model_id=request['model_id'],probabilities=sequence(request['probabilities']),horizons=sequence(request['horizons']),
        block_file_sha256=wire['block_file_sha256'],wire_sha256=digest(packet/'numerical_wire.json'),
        independent_numeric_recomputation=True,independent_block_decoding=True,
        canonical_ledger_mutations=0,production_authorized=False,
        confidence_scope='one_fixed_draw_origin_not_campaign_familywise')

def main(argv=None):
    p=argparse.ArgumentParser();p.add_argument('--generated-packet');p.add_argument('--request');p.add_argument('--receipt')
    a=p.parse_args(argv)
    if not a.generated_packet:
        print('MQ_PRODUCTION_NOT_ADMITTED');return
    require(a.request and a.receipt,'generated request and fresh acceptance receipt required')
    result=accept_generated(a.generated_packet,read_json(a.request))
    with Path(a.receipt).open('x') as stream:json.dump(result,stream,sort_keys=True,indent=2,allow_nan=False);stream.write('\n')

if __name__=='__main__':main()
