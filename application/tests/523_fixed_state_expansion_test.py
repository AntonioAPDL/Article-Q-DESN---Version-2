#!/usr/bin/env python3
"""Metadata/guard tests only. Opens no real target numerical arrays."""
from contextlib import ExitStack,redirect_stdout
import datetime
import importlib.util
import io
import json
import os
from pathlib import Path
import resource
import sys
import tempfile
import time
import unittest
from unittest import mock
import fcntl

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('expansion',ROOT/'scripts/pricefm/523_fixed_state_control.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c);ref=c.ref
MANIFEST=ROOT/'config/pricefm/523_fixed_state_expansion.json'


class Guards(unittest.TestCase):
    def test_original_seven_target_set_and_scope_are_exact(self):
        manifest=c.load_manifest(MANIFEST)
        self.assertEqual(len(manifest['targets']),7)
        self.assertEqual(set(manifest['execution']),{c.NO3,c.AT})
        with tempfile.TemporaryDirectory(prefix='r523_scope_') as d:
            path=Path(d)/'manifest'
            for mutate in ['units','prior','targets','budget']:
                altered=json.loads(MANIFEST.read_text())
                if mutate=='units':altered['scope']['units']='standardized'
                elif mutate=='prior':altered['scope']['prior']['center']='initializer'
                elif mutate=='targets':altered['targets'][0]['tau0']*=2
                else:altered['budget']['prior_charged_CPU_seconds']=0
                path.write_text(json.dumps(altered))
                with self.assertRaises(ValueError):c.load_manifest(path)

    def test_synthetic_alias_hash_host_and_dimensions(self):
        with tempfile.TemporaryDirectory(prefix='r523_alias_') as d:
            root=Path(d);design=root/'design';fit=root/'fit';design.mkdir();fit.mkdir()
            (design/'X.bin').write_bytes(b'12345678');(design/'y.bin').write_bytes(b'abcdefgh')
            (design/'design.json').write_text(json.dumps({'n':1,'p':1,'feature_names':['intercept']}))
            dt={'status':'completed_r137_quantile_design','test_opened':False,'files':{name:ref.sha256(design/name) for name in ['X.bin','y.bin','design.json']}}
            (design/'terminal.json').write_text(json.dumps(dt));terminal={'computationally_certified':False}
            (fit/'terminal.json').write_text(json.dumps(terminal))
            contract={'design_dir':'/original/design','output_dir':'/original/fit'}
            cp=root/'contract';cp.write_text(json.dumps(contract))
            aliases={'/original/contract':str(cp),'/original/design':str(design),'/original/fit':str(fit)}
            ap=root/'alias.json';alias={'target':c.NO3,'aliases':aliases,'source_host':'jerez','execution_host':'muscat'};ap.write_text(json.dumps(alias))
            target={'name':c.NO3,'host':'jerez','n':1,'p':1,'contract':contract,'stored_terminal':terminal,
                'bindings':[{'path':'/original/contract','sha256':ref.sha256(cp)}]}
            manifest={'targets':[target],'execution':{c.NO3:{'source_host':'jerez','execution_host':'muscat','aliases':aliases,'alias_manifest':{'path':str(ap),'sha256':ref.sha256(ap)}}}}
            self.assertEqual(c.verify_execution_target(manifest,c.NO3)['name'],c.NO3)
            (design/'X.bin').write_bytes(b'wrong___')
            with self.assertRaises(ValueError):c.verify_execution_target(manifest,c.NO3)
            manifest['execution'][c.NO3]['execution_host']='jerez'
            with self.assertRaises(ValueError):c.verify_execution_target(manifest,c.NO3)

    def test_remaining_budget_and_missing_reap_receipt_fail_closed(self):
        manifest=c.load_manifest(MANIFEST)
        with tempfile.TemporaryDirectory(prefix='r523_ledger_') as d,mock.patch.object(c,'AUDIT',Path(d)):
            spent,receipts=c.ledger(manifest);self.assertAlmostEqual(spent,1395.588691);self.assertEqual(receipts,[])
            consume=Path(d)/'target_consumption';consume.mkdir();claim=consume/(ref.canonical_hash(c.NO3)+'.json');claim.write_text('{}')
            with self.assertRaises(ValueError):c.ledger(manifest)
            out=Path(d)/manifest['execution'][c.NO3]['output_name'];out.mkdir();rp=out/'resource_receipt.json'
            receipt={'target':c.NO3,'scope':'r154_two_target_fixed_state_expansion_v1','child_CPU_seconds':95.0};rp.write_text(json.dumps(receipt))
            self.assertAlmostEqual(c.ledger(manifest)[0],1490.588691)
            receipt['child_CPU_seconds']=-95;rp.write_text(json.dumps(receipt))
            with self.assertRaises(ValueError):c.ledger(manifest)

    def test_busy_shared_flock_means_no_move_or_target_or_claim(self):
        with tempfile.TemporaryDirectory(prefix='r523_busy_') as d,ExitStack() as s:
            path=Path(d)/'muscat_cpu30.lock';holder=s.enter_context(open(path,'a+'));fcntl.flock(holder,fcntl.LOCK_EX|fcntl.LOCK_NB)
            s.enter_context(mock.patch.object(sys,'argv',['control','--manifest','x','--root-grant','x','--root-grant-sha256','0'*64,'--target',c.NO3]))
            s.enter_context(mock.patch.object(c.os,'sched_getaffinity',return_value={31}))
            s.enter_context(mock.patch.object(c,'authority',return_value=({},dict(global_contract={}))))
            s.enter_context(mock.patch.object(c.base,'global_permit',return_value={'lock_dir':d}))
            observed=[s.enter_context(mock.patch.object(owner,name)) for owner,name in [(c.os,'sched_setaffinity'),(c.os,'setpriority'),(c.os,'sched_setscheduler'),(c,'run_owned'),(c,'verify_execution_target'),(c.ref,'immutable_json')]]
            with self.assertRaises(BlockingIOError):c.main()
            for boundary in observed:boundary.assert_not_called()

    def test_actual_authority_metadata_CPU31_for_both_targets_no_claim(self):
        self.assertEqual(os.sched_getaffinity(0),{31})
        manifest=c.load_manifest(MANIFEST);global_contract=json.loads(Path(manifest['global_contract']['path']).read_text())
        source=[c.HERE/'523_fixed_state_control.py',c.HERE/'523_fixed_state_diagnosis.R',c.HERE/'522_fixed_state_control.py',c.HERE/'522_certificate_reference.py',c.ROOT/'application/R/522_certificate_reference.R']
        for target,cap in c.CAPS.items():
            grant={'status':'ROOT_ADMITTED_FIXED_STATE_EXPANSION_ONLY','manifest_sha256':ref.sha256(MANIFEST),'target':target,
                'authorizes_fixed_state_reconstruction':True,'authorizes_posterior_fits':False,'authorizes_production_acceptance':False,
                'expires_UTC':datetime.datetime.fromtimestamp(min(time.time()+300,global_contract['expires_epoch']-1),datetime.timezone.utc).isoformat(),
                'host':'muscat','maximum_CPU_seconds':cap,'maximum_wall_seconds':7200,'maximum_total_diagnostic_CPU_seconds':2700,
                'prior_charged_CPU_seconds':995.588691,'reserved_source_preparation_CPU_seconds':300,'reserved_fixed_reference_CPU_seconds':100,
                'cores':1,'affinity':[30],'memory_GiB':8,'disk_GiB':2,'permit_id':'muscat_cpu30','global_contract':manifest['global_contract'],
                'source_bindings':[{'path':str(p),'sha256':ref.sha256(p)} for p in source],
                'actual_R_runtime_binding':manifest['actual_Muscat_R_runtime'],'prior_completed_receipts':[],'test_fixture_only':True}
            with tempfile.TemporaryDirectory(prefix='r523_valid_metadata_') as d:
                gp=Path(d)/'grant';gp.write_text(json.dumps(grant))
                argv=['control','--manifest',str(MANIFEST),'--root-grant',str(gp),'--root-grant-sha256',ref.sha256(gp),'--target',target,'--check-authority']
                with mock.patch.object(sys,'argv',argv),redirect_stdout(io.StringIO()) as output:c.main()
                self.assertIn('PASS expansion authority only',output.getvalue());self.assertEqual(os.sched_getaffinity(0),{31})
                self.assertEqual(list(Path(d).iterdir()),[gp])


if __name__=='__main__':
    started=time.monotonic();result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Guards))
    record={'status':'PASS' if result.wasSuccessful() else 'FAIL','tests':result.testsRun,'metadata_or_synthetic_file_cases_only':True,
        'target_numeric_calls':0,'posterior_fits':0,'wall_seconds':time.monotonic()-started,'process_CPU_seconds_total':time.process_time(),
        'max_RSS_KiB':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
    if len(sys.argv)==2:ref.immutable_json(sys.argv[1],record)
    else:print(json.dumps(record))
    sys.exit(0 if result.wasSuccessful() else 1)
