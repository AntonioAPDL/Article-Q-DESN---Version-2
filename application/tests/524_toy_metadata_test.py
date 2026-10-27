#!/usr/bin/env python3
"""Source/authority/permit metadata tests; never invokes R or an optimizer."""
from contextlib import ExitStack,redirect_stdout
import datetime
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('toy_runner',ROOT/'scripts/pricefm/524_run_toy_validation.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c);ref=c.ref
CONFIG=ROOT/'config/pricefm/524_fullstate_toy_validation.json'


class Metadata(unittest.TestCase):
    def test_actual_authority_only_on_CPU31_no_optimizer(self):
        self.assertEqual(os.sched_getaffinity(0),{31})
        cfg=json.loads(CONFIG.read_text())
        template=c.AUDIT/'ROOT_TOY_GRANT_TEMPLATE_V2_NOT_ADMITTED.json'
        grant=json.loads(template.read_text());grant['status']='ROOT_ADMITTED_TOY_FULLSTATE_VALIDATION_ONLY'
        grant['config_sha256']=ref.sha256(CONFIG)
        grant['expires_UTC']=datetime.datetime.fromtimestamp(min(time.time()+120,cfg['stage_deadline_epoch']-1),datetime.timezone.utc).isoformat()
        grant['source_bindings']=[dict(path=x['path'],sha256=ref.sha256(x['path'])) for x in grant['source_bindings']]
        with tempfile.TemporaryDirectory(prefix='r524_metadata_') as d:
            gp=Path(d)/'grant';gp.write_text(json.dumps(grant))
            args=['control','--config',str(CONFIG),'--root-grant',str(gp),'--root-grant-sha256',ref.sha256(gp),'--check-authority']
            with mock.patch.object(sys,'argv',args),redirect_stdout(io.StringIO()) as output:c.main()
            self.assertIn('PASS toy authority only',output.getvalue());self.assertEqual(os.sched_getaffinity(0),{31})
            self.assertEqual(list(Path(d).iterdir()),[gp])

    def test_busy_pool_prevents_move_claim_or_optimizer(self):
        with tempfile.TemporaryDirectory(prefix='r524_busy_') as d,ExitStack() as s:
            holder=s.enter_context(open(Path(d)/'muscat_cpu30.lock','a+'));fcntl.flock(holder,fcntl.LOCK_EX|fcntl.LOCK_NB)
            s.enter_context(mock.patch.object(sys,'argv',['control','--config','x','--root-grant','x','--root-grant-sha256','0'*64]))
            s.enter_context(mock.patch.object(c.os,'sched_getaffinity',return_value={31}))
            s.enter_context(mock.patch.object(c,'authority',return_value=({},dict(global_contract={}))))
            s.enter_context(mock.patch.object(c.base,'global_permit',return_value={'lock_dir':d}))
            watched=[s.enter_context(mock.patch.object(owner,name)) for owner,name in [(c.os,'sched_setaffinity'),(c.os,'setpriority'),(c,'run_locked'),(c.ref,'immutable_json')]]
            with self.assertRaises(BlockingIOError):c.main()
            for boundary in watched:boundary.assert_not_called()

    def test_unknown_numerical_peer_on_SMT62_rejected(self):
        self.assertEqual(c.physical_siblings(),{30,62})
        with tempfile.TemporaryDirectory(prefix='r524_fakeproc_') as d,ExitStack() as s:
            root=Path(d);p=root/'100';p.mkdir();(p/'task/100').mkdir(parents=True)
            fields=['R']+['1']*19;fields[19]='12345'
            (p/'stat').write_text('100 (python) '+' '.join(fields));(p/'cmdline').write_bytes(b'python\0unreviewed.py\0');(p/'comm').write_text('python\n')
            (p/'exe').symlink_to('/usr/bin/python3')
            census=root/'census.json';census.write_text(json.dumps({'allowed_intersecting_processes':[]}))
            s.enter_context(mock.patch.object(c.base,'fresh_peer_guard',return_value={}))
            s.enter_context(mock.patch.object(c.base,'global_permit',return_value={'evidence':{'peer_census':{'path':str(census)}}}))
            s.enter_context(mock.patch.object(c.os,'sched_getaffinity',return_value={62}))
            # Keep only numeric proc entries in the synthetic proc root.
            with self.assertRaisesRegex(ValueError,'unknown numerical peer.*SMT62'):
                c.physical_peer_guard({},_proc_root=root)


if __name__=='__main__':
    started=time.process_time();result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Metadata))
    record={'status':'PASS' if result.wasSuccessful() else 'FAIL','tests':result.testsRun,
        'actual_toy_optimizer_invocations':0,'production_fit_invocations':0,'CPU_seconds':time.process_time()-started}
    if len(sys.argv)==2:ref.immutable_json(sys.argv[1],record)
    else:print(json.dumps(record))
    sys.exit(0 if result.wasSuccessful() else 1)
