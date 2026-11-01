"""Source and scalar-metadata fixtures only; no R, arrays, jobs or grants."""
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import unittest
from . import numerical_stage_contract as c

STATUS='R188_BRIDGE_SCALARS_AFTER_ACK_FAILED_NOT_ACCEPTANCE'
RHS_NUMBERS=['unit_iterations','dispersed_iterations','unit_residual','dispersed_residual']
RHS_BOOLEANS=['unit_converged','dispersed_converged']


def require(value):
    if not value:raise ValueError('invalid diagnostic metadata')


def scalar(value,boolean=False):
    require(type(value) is dict and type(value.get('available')) is bool)
    if not value['available']:
        require(set(value)=={'available','label'} and value['label'] in {'UNAVAILABLE','REDACTED_NONSCALAR','REDACTED_TYPE'});return
    if value.get('kind')=='nonfinite':
        require(set(value)=={'available','kind','label'} and value['label'] in ({'NA'} if boolean else {'NaN','Inf','-Inf','NA'}));return
    require(set(value)=={'available','kind','value'})
    if boolean:require(value['kind']=='boolean' and type(value['value']) is bool)
    else:require(value['kind']=='number' and type(value['value']) in (int,float) and math.isfinite(value['value']))


def parse_scalar_frame(raw,context):
    """Test-only consumer: not imported by any worker/owner/acceptance path."""
    require(len(raw)<=16384)
    def pairs(items):
        out={}
        for key,value in items:require(key not in out);out[key]=value
        return out
    def reject(value):raise ValueError('non-JSON numeric literal')
    frame=json.loads(raw,object_pairs_hook=pairs,parse_constant=reject)
    require(set(frame)==set(context)|{'schema','status','diagnostic_available','logging','original_limits','current_cert','old_cert','terminal_sigma','R_exit_status','numerical_acceptance'})
    require(frame['schema']=='r188_post_ACK_bridge_scalar_diagnostic_v1' and frame['status']==STATUS and frame['R_exit_status']==1
            and type(frame['R_exit_status']) is int and frame['numerical_acceptance'] is False)
    require(all(frame[key]==value for key,value in context.items()) and frame['context_complete'] is True)
    require(frame['original_limits']==c.LIMITS and all(type(x) in (int,float) for x in frame['original_limits'].values()))
    require(type(frame['diagnostic_available']) is bool and frame['logging'] in {'SCALAR_WHITELIST_ONLY','UNAVAILABLE'})
    if not frame['diagnostic_available']:require(frame['logging']=='UNAVAILABLE')
    for key in ['current_cert','old_cert']:
        cert=frame[key];require(type(cert) is dict and type(cert.get('available')) is bool)
        if set(cert)=={'available'}:require(cert['available'] is False);continue
        require(set(cert)=={'available','measures','limits','certified','raw_reconstructed_elbo','raw_next_elbo','rhs_reconstruction'})
        for field in ['measures','limits']:
            require(set(cert[field])==set(c.LIMITS))
            for value in cert[field].values():scalar(value)
        scalar(cert['certified'],True);scalar(cert['raw_reconstructed_elbo']);scalar(cert['raw_next_elbo'])
        require(set(cert['rhs_reconstruction'])==set(RHS_NUMBERS+RHS_BOOLEANS))
        for name,value in cert['rhs_reconstruction'].items():scalar(value,name in RHS_BOOLEANS)
    scalar(frame['terminal_sigma']);return frame


class ScalarMetadataTests(unittest.TestCase):
    def fixture(self):
        number=lambda x:dict(available=True,kind='number',value=x)
        boolean=lambda x:dict(available=True,kind='boolean',value=x)
        pins=[dict(path='/UNIT/'+name,sha256=sha) for name,sha in sorted(c.SCIENCE_HASHES.items())]
        context=dict(role='ZERO_UPDATE_BRIDGE',job_id='123',node='node-13',nonce='0'*32,source_files=pins,
            entrypoint=pins[3],bootstrap_spec=dict(path='/UNIT/SPEC.json',sha256='a'*64),context_complete=True)
        cert=dict(available=True,measures={key:number(.5) for key in c.LIMITS},limits={key:number(x) for key,x in c.LIMITS.items()},
            certified=boolean(False),raw_reconstructed_elbo=number(1.),raw_next_elbo=number(2.),
            rhs_reconstruction={**{key:number(1.) for key in RHS_NUMBERS},**{key:boolean(True) for key in RHS_BOOLEANS}})
        return dict(context,schema='r188_post_ACK_bridge_scalar_diagnostic_v1',status=STATUS,diagnostic_available=True,logging='SCALAR_WHITELIST_ONLY',
            original_limits=c.LIMITS,current_cert=cert,old_cert=copy.deepcopy(cert),terminal_sigma=number(1.),R_exit_status=1,numerical_acceptance=False),context
    def test_finite_and_explicit_nonfinite_scalars(self):
        frame,context=self.fixture();parse_scalar_frame(json.dumps(frame).encode(),context)
        for label in ['NaN','Inf','-Inf','NA']:
            item=copy.deepcopy(frame);item['terminal_sigma']=dict(available=True,kind='nonfinite',label=label)
            parse_scalar_frame(json.dumps(item).encode(),context)
    def test_unavailable_logging_fallback_is_failure(self):
        frame,context=self.fixture();frame.update(diagnostic_available=False,logging='UNAVAILABLE',current_cert=dict(available=False),old_cert=dict(available=False),terminal_sigma=dict(available=False,label='UNAVAILABLE'))
        self.assertFalse(parse_scalar_frame(json.dumps(frame).encode(),context)['numerical_acceptance'])
    def test_arrays_wrong_types_foreign_context_and_success_reject(self):
        for mutation in ['extra_state','vector','raw_nan','raw_inf','boolean_number','wrong_status','exit0','acceptance','foreign_job','missing_measure','rhs_type']:
            frame,context=self.fixture()
            if mutation=='extra_state':frame['current_cert']['qbeta']={'m':[1,2]}
            elif mutation=='vector':frame['terminal_sigma']['value']=[1,2]
            elif mutation=='raw_nan':frame['terminal_sigma']['value']=float('nan')
            elif mutation=='raw_inf':frame['terminal_sigma']['value']=float('inf')
            elif mutation=='boolean_number':frame['terminal_sigma']['value']=True
            elif mutation=='wrong_status':frame['status']='PASS'
            elif mutation=='exit0':frame['R_exit_status']=0
            elif mutation=='acceptance':frame['numerical_acceptance']=True
            elif mutation=='foreign_job':frame['job_id']='999'
            elif mutation=='missing_measure':frame['old_cert']['measures'].pop(next(iter(c.LIMITS)))
            else:frame['current_cert']['rhs_reconstruction']['unit_converged']=dict(available=True,kind='number',value=1)
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):parse_scalar_frame(json.dumps(frame).encode(),context)
    def test_oversize_duplicates_and_bad_labels_reject(self):
        frame,context=self.fixture()
        with self.assertRaises(ValueError):parse_scalar_frame(b' '*16385,context)
        raw=json.dumps(frame).replace('"R_exit_status": 1','"R_exit_status": 1,"R_exit_status": 1').encode()
        with self.assertRaises(ValueError):parse_scalar_frame(raw,context)
        frame['terminal_sigma']=dict(available=True,kind='nonfinite',label='other')
        with self.assertRaises(ValueError):parse_scalar_frame(json.dumps(frame).encode(),context)


class BootstrapSourceTests(unittest.TestCase):
    def fixture(self):
        path=Path(__file__).with_name('numerical_stage_bootstrap.R');root=path.parents[4]
        old=subprocess.check_output(['git','show','c0e8477ef044cceb9309e30b62dc58c9da622002:application/scripts/pricefm/pricefm_hb/numerical_stage_bootstrap.R'],cwd=root,text=True)
        new=path.read_text();entry="source(spec$scientific_entrypoint$path)\n"
        return new,old,new[len(old)-len(entry):-len(entry)],root
    def test_preACK_prefix_and_TOY_call_unchanged(self):
        new,old,block,_=self.fixture();entry="source(spec$scientific_entrypoint$path)\n"
        self.assertTrue(new.startswith(old[:-len(entry)]));self.assertTrue(new.endswith(entry))
        self.assertTrue(block.startswith("if (identical(spec$role,'ZERO_UPDATE_BRIDGE'))"));self.assertNotIn('TOY_PARITY',block)
        self.assertLess(new.index(".Call('r157_scientific_boundary'"),new.index('base::options(error='))
        self.assertLess(new.index("Sys.setenv(R179_CURRENT_TSYNC_ACK_REQUIRED='1')"),new.index('base::options(error='))
    def test_whitelist_scalar_guards_and_unconditional_quit(self):
        _,_,block,_=self.fixture()
        for key in list(c.LIMITS)+RHS_NUMBERS+RHS_BOOLEANS:self.assertIn("'"+key+"'",block)
        for text in ["base::length(value)!=1L","base::dim(value)","base::is.object(value)","base::bindingIsActive(name,.GlobalEnv)","base::get(name,envir=.GlobalEnv,inherits=FALSE)","16384L","base::tryCatch","base::quit(status=1L,save='no',runLast=FALSE)"]:self.assertIn(text,block)
        self.assertEqual(block.count('base::cat('),1);self.assertEqual(block.count('base::quit('),1)
        self.assertLess(block.rindex('error=function(error) base::invisible(NULL)'),block.index('base::quit('))
        for text in ['readRDS','saveRDS','readBin','writeBin','r129_certificate(','r525_','geterrmessage','conditionMessage','encode(object(']:self.assertNotIn(text,block)
    def test_math_files_and_original_assertion_unchanged(self):
        _,_,_,root=self.fixture()
        for name,sha in c.SCIENCE_HASHES.items():self.assertEqual(hashlib.sha256((root/name).read_bytes()).hexdigest(),sha)
        self.assertIn('identical(as.numeric(cert$measures[[k]]), as.numeric(old_cert$measures[[k]]))',(root/'application/scripts/pricefm/r179_hb_bridge_or_pilot.R').read_text())


if __name__=='__main__':unittest.main()
