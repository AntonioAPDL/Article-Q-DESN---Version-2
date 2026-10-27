#!/usr/bin/env python3
"""Small fixed-state tests only; no target data are opened."""
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import sys
import tempfile
import time
import unittest
from unittest import mock
from contextlib import ExitStack, redirect_stdout
import io
import datetime
import fcntl

ROOT=Path(__file__).resolve().parents[1]
def module(name):
    p=ROOT/'scripts'/'pricefm'/(name+'.py')
    spec=importlib.util.spec_from_file_location(name,p); x=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(x); return x
ref=module('522_certificate_reference'); oracle=module('522_decimal_oracle')
control=module('522_fixed_state_control')
np=ref.np
CASE_COUNT=32


class References(unittest.TestCase):
    def test_bounded_decimal_fixed_states(self):
        self.assertLessEqual(CASE_COUNT,64)
        errors=[]; backward=[]; floors=0
        for case in range(CASE_COUNT):
            n=1+case%8; p=1+case%4
            scales=np.logspace(-3,3,p)
            C=np.full((p,p),.125); np.fill_diagonal(C,1.0)
            P=(C*scales[:,None])*scales[None,:]
            P=np.tril(P)+np.tril(P,-1).T
            b=np.arange(1,p+1,dtype=float)*scales
            g=ref.gaussian_reference(P,b)
            exact,V=oracle.solve(P.tolist(),b.tolist())
            exact=np.array(list(map(float,exact))); V=np.array([[float(x) for x in row] for row in V])
            self.assertLess(np.max(np.abs(g['beta']-exact)/np.maximum(1,np.abs(exact))),1e-12)
            self.assertLess(np.max(np.abs(g['covariance']-V)/np.maximum(1,np.abs(V))),1e-12)
            self.assertEqual(g['jitter_added'],0)
            backward.append(g['componentwise_backward_error'])
            r=np.linspace(-.3,.5,n); second=r*r+np.linspace(.01,.2,n)
            sigma=.2+case/7; tau=[.1,.45,.5,.9][case%4]
            if case%8==0: second[0]=1e-30
            if case%8==1: sigma=1e20
            logdet=-.3*p; prior=-2.25
            obj=ref.objective_reference(r,second,sigma,tau,p,logdet,prior)
            high=float(oracle.objective(r.tolist(),second.tolist(),sigma,tau,p,logdet,prior))
            error=abs(obj['objective']-high)/max(1,abs(high)); errors.append(error)
            self.assertLess(error,2e-13)
            expanded=ref.objective_expanded_reference(r,second,sigma,tau,p,logdet,prior)
            self.assertLess(abs(expanded-high)/max(1,abs(high)),2e-12)
            floors+=obj['chi_floor_count']+int(obj['psi_floor_active'])
        self.assertGreater(floors,0)
        global NUMERIC_SUMMARY
        NUMERIC_SUMMARY=dict(tiny_fixed_state_cases=CASE_COUNT,decimal_precision=oracle.PRECISION,
            max_relative_objective_error=max(errors), max_componentwise_backward_error=max(backward),
            floor_events=floors, target_numeric_diagnoses=0, posterior_fits=0,
            original_prior_scalar_independently_oracled=False)

    def test_original_unit_covariance_and_prior(self):
        P=np.array([[4.,1.],[1.,9.]]); b=np.array([2.,3.])
        g=ref.gaussian_reference(P,b)
        self.assertTrue(np.allclose(P@g['beta'],b,atol=1e-14,rtol=1e-14))
        self.assertTrue(np.allclose(P@g['covariance'],np.eye(2),atol=1e-14,rtol=1e-14))
        self.assertFalse(np.allclose(g['beta'],g['beta']/g['diagonal_scale']))
        args=([.2,.3],[.05,.2],.7,.9,2,-1.,-7.)
        a=ref.objective_reference(*args)['objective']
        z=list(args); z[-1]+=1
        self.assertAlmostEqual(ref.objective_reference(*z)['objective']-a,1.,places=12)

    def test_reject_changed_hash_units_prior_state_and_gates(self):
        scope=dict(units=ref.UNITS,prior=ref.PRIOR,state_kind=ref.STATE_KIND,
            exact_optimizer_resume=False,limits=ref.LIMITS,caps={'Normal':2000,'AL':300},
            acceptance='finite AND (formal OR independent)')
        ref.validate_scope(scope)
        for key,value in [('units','standardized'),('prior',dict(ref.PRIOR,center='initializer')),
            ('state_kind','exact_resume'),('exact_optimizer_resume',True),
            ('caps',{'Normal':2000,'AL':600}),('limits',dict(ref.LIMITS,elbo_relative=1e-7)),
            ('acceptance','finite AND formal AND independent')]:
            with self.assertRaises(ValueError): ref.validate_scope(dict(scope,**{key:value}))
        with tempfile.TemporaryDirectory(prefix='r522_synthetic_') as d:
            p=Path(d)/'state'; p.write_bytes(b'fixed')
            ref.verify_files([dict(path=str(p),sha256=ref.sha256(p))])
            with self.assertRaises(ValueError): ref.verify_files([dict(path=str(p),sha256='0'*64)])
            with self.assertRaises(FileNotFoundError): ref.verify_files([dict(path=str(p)+'missing',sha256='0'*64)])
            out=Path(d)/'diagnostic.json'; ref.immutable_json(out,{'value':1})
            with self.assertRaises(FileExistsError): ref.immutable_json(out,{'value':2})
            self.assertNotIn('certified',json.loads(out.read_text()))
        for P in [[[1.,2.],[2.,1.]],[[1.,1.],[0.,1.]]]:
            with self.assertRaises((ValueError,np.linalg.LinAlgError)):ref.gaussian_reference(P,[1.,2.])

    def test_oracle_cannot_accept_production_dimensions(self):
        with self.assertRaises(ValueError):oracle.solve(np.eye(5).tolist(),[1]*5)
        with self.assertRaises(ValueError):oracle.objective([0]*9,[1]*9,1,.5,1,0,0)
        with self.assertRaises(ValueError):oracle.gamma_pair('1.1')

    def test_target_authority_rejects_unfunded_changed_or_expired_scope(self):
        # No target paths or arrays are read in this test.
        manifest=json.loads((ROOT/'config/pricefm/522_fixed_state_targets.json').read_text())
        with tempfile.TemporaryDirectory(prefix='r522_authority_negative_') as d:
            mp=Path(d)/'manifest.json';mp.write_text(json.dumps(manifest))
            gp=Path(d)/'grant.json'
            base=dict(status='NOT_ADMITTED',manifest_sha256=ref.sha256(mp),
                authorizes_posterior_fits=False,authorizes_production_acceptance=False,
                authorizes_fixed_state_reconstruction=True,target='LT_fold1_al0.90',
                expires_UTC='2099-01-01T00:00:00+00:00',host=os.uname().nodename,
                maximum_CPU_seconds=1800,maximum_wall_seconds=7200,cores=1,
                maximum_total_diagnostic_CPU_seconds=2700,reserved_source_preparation_CPU_seconds=300,
                reserved_fixed_reference_CPU_seconds=600,
                affinity=[min(os.sched_getaffinity(0))],memory_GiB=8,disk_GiB=2,
                source_bindings=[])
            variants=[{},dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY',authorizes_posterior_fits=True),
                dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY',expires_UTC='2000-01-01T00:00:00+00:00'),
                dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY',maximum_CPU_seconds=2701),
                dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY',target='another_target'),
                dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY',manifest_sha256='0'*64),
                dict(status='ROOT_ADMITTED_FIXED_STATE_DIAGNOSTIC_ONLY')]
            for changed in variants:
                gp.write_text(json.dumps(dict(base,**changed)))
                with self.assertRaises(ValueError):control.authority(mp,gp,ref.sha256(gp),'LT_fold1_al0.90')
            with self.assertRaises(ValueError):control.authority(mp,gp,'0'*64,'LT_fold1_al0.90')

    def test_shared_permit_lock_is_exclusive(self):
        with tempfile.TemporaryDirectory(prefix='r522_flock_synthetic_') as d:
            path=Path(d)/'muscat_cpu30.lock'
            with open(path,'a+') as first,open(path,'a+') as second:
                fcntl.flock(first,fcntl.LOCK_EX|fcntl.LOCK_NB)
                with self.assertRaises(BlockingIOError):fcntl.flock(second,fcntl.LOCK_EX|fcntl.LOCK_NB)
                first.close()
                fcntl.flock(second,fcntl.LOCK_EX|fcntl.LOCK_NB)

    def test_busy_shared_pool_cannot_move_or_open_target_or_claim(self):
        # Exercise main() and a real busy flock inode. Authority hashing is
        # stubbed because it is administrative; every scientific/claim/move
        # boundary is observed and must remain untouched.
        with tempfile.TemporaryDirectory(prefix='r522_busy_pool_negative_') as d:
            path=Path(d)/'muscat_cpu30.lock'
            grant=dict(permit_id='muscat_cpu30',global_contract={'path':'unused','sha256':'0'*64})
            with open(path,'a+') as holder,ExitStack() as stack:
                fcntl.flock(holder,fcntl.LOCK_EX|fcntl.LOCK_NB)
                stack.enter_context(mock.patch.object(sys,'argv',['control','--manifest','unused',
                    '--root-grant','unused','--root-grant-sha256','0'*64,'--output-dir',str(Path(d)/'must_not_exist')]))
                stack.enter_context(mock.patch.object(control,'authority',return_value=({},grant)))
                stack.enter_context(mock.patch.object(control,'global_permit',return_value={'lock_dir':d}))
                stack.enter_context(mock.patch.object(control.os,'sched_getaffinity',return_value={31}))
                observed=[stack.enter_context(mock.patch.object(owner,name)) for owner,name in [
                    (control.os,'sched_setaffinity'),(control.os,'sched_setscheduler'),
                    (control.os,'setpriority'),(control.subprocess,'run'),
                    (control,'run_under_lock'),(control.ref,'verify_target'),
                    (control.ref,'immutable_json'),(control.ref,'verify_files')]]
                with self.assertRaises(BlockingIOError):control.main()
                for boundary in observed:boundary.assert_not_called()
                self.assertFalse((Path(d)/'must_not_exist').exists())

    def test_check_authority_stays_on_caller_CPU31_without_pool_claim(self):
        with ExitStack() as stack:
            stack.enter_context(mock.patch.object(sys,'argv',['control','--manifest','unused',
                '--root-grant','unused','--root-grant-sha256','0'*64,'--check-authority']))
            stack.enter_context(mock.patch.object(control,'authority',return_value=({},{})))
            stack.enter_context(mock.patch.object(control.os,'sched_getaffinity',return_value={31}))
            observed=[stack.enter_context(mock.patch.object(owner,name)) for owner,name in [
                (control.os,'sched_setaffinity'),(control.os,'sched_setscheduler'),
                (control.os,'setpriority'),(control.subprocess,'run'),
                (control,'global_permit'),(control,'run_under_lock'),
                (control.ref,'verify_target'),(control.ref,'immutable_json')]]
            with redirect_stdout(io.StringIO()):control.main()
            for boundary in observed:boundary.assert_not_called()


if __name__=='__main__':
    started=time.monotonic(); cpu=time.process_time()
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(References)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    summary=dict(globals().get('NUMERIC_SUMMARY',{}),passed=result.wasSuccessful(),tests=result.testsRun,
        wall_seconds=time.monotonic()-started, process_CPU_seconds=time.process_time()-cpu,
        process_CPU_seconds_total_including_startup=time.process_time(),
        max_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        environment=ref.environment_binding())
    if len(sys.argv)==2:ref.immutable_json(sys.argv[1],summary)
    else:print(json.dumps(summary,sort_keys=True))
    sys.exit(0 if result.wasSuccessful() else 1)
