"""Private stdlib fixtures only; no SSH, canonical registry or scientific calls."""
import ast
import atexit
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ORIGINAL_SOURCE = Path(__file__).with_name('pricefm_profile_caller.py')
# These fixture roots contain only dummy metadata/code. Actual tracker fsync
# latency is irrelevant to kernel/accounting semantics and exceeded an earlier
#30s synthetic batch timeout. Preserve that receipt; use private tmpfs here.
TEST_SPACE = tempfile.TemporaryDirectory(prefix='pricefm_r165_caller_',dir='/dev/shm')
atexit.register(TEST_SPACE.cleanup)
SOURCE = Path(TEST_SPACE.name) / 'caller_driver.py'
shutil.copyfile(ORIGINAL_SOURCE,SOURCE)
spec = importlib.util.spec_from_file_location('caller_driver', SOURCE)
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
TRACKERS = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers')
OLD_TRACKER = TRACKERS / 'pricefm_r164_execution_readiness_20261028_2336PDT'
CONSTRUCTOR = OLD_TRACKER / 'prospective_profile/job_bound_packets.py'
CONTROLLER_PACKAGE = ORIGINAL_SOURCE.parent / 'pricefm_hb'


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='caller_private_', dir=SOURCE.parent)
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def save(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(d.encoded(value))
        return d.pin(path)

    def config(self):
        parent=self.root
        self.root=parent/('configuration_'+os.urandom(6).hex())
        self.root.mkdir()
        try:return self._config()
        finally:self.root=parent

    def _config(self):
        scope_id = 'r164-profile-' + os.urandom(12).hex()
        package = self.root / 'package/pricefm_hb'; package.mkdir(parents=True)
        (package / '__init__.py').write_text('')
        (package / 'execution_profile.py').write_text('# no scientific code\n')
        (package / 'profile_supervisor.py').write_text('# fixture only\n')
        (package / 'profile_control.py').write_text(
            'import json,resource,signal,subprocess,sys\n'
            'def main(argv):\n'
            ' assert "--compute-session" not in argv and "--validate-return" not in argv\n'
            ' assert resource.getrlimit(resource.RLIMIT_CPU)==(2,40)\n'
            ' assert signal.getsignal(signal.SIGXCPU)==signal.SIG_DFL\n'
            ' assert signal.SIGXCPU not in signal.pthread_sigmask(signal.SIG_BLOCK,set())\n'
            ' if "collect" in argv: raise RuntimeError("owned synthetic failure")\n'
            ' code="import resource; resource.setrlimit(resource.RLIMIT_CPU,(40,40)); print(resource.getrlimit(resource.RLIMIT_CPU))"\n'
            ' x=subprocess.run([sys.executable,"-I","-B","-c",code],capture_output=True,text=True,check=True)\n'
            ' print(json.dumps({"argv":argv,"limits":[2,40],"helper":x.stdout.strip()}))\n')
        sources = {path.name: d.pin(path)['sha256'] for path in package.iterdir()}
        pub = self.save('publication.json', dict(status='VERIFIED_FEATURE_PUBLICATION',
            fresh_remote_hash_verified=True, feature_only=True, source_files=sources,auxiliary_sources={d.PUBLICATION_SOURCE_KEY:d.pin(SOURCE)['sha256']}))
        now = time.time(); expiry = now + 120
        request = dict(path='/nonexecuted/request.json', sha256='a' * 64)
        spec_value = dict(schema='r164_profile_controller_spec_v1', scope_id=scope_id,
            phase='QUALIFICATION_PAIR', controller_expires_epoch=expiry,
            controller_limits=dict(aggregate_reserved_CPU_seconds=450,operation_CPU_seconds=4), request=request,
            controller_sources=sources, feature_publication=pub)
        spec_pin = self.save('spec.json', spec_value)
        admin = self.save('admin.json', dict(admin_cpu=31,new_numerical_calls=0,
            issued_epoch=now-10,expires_epoch=expiry+1,write_scope=str(CONSTRUCTOR.parent)))
        funding = self.save('funding.json',dict(status='CPU_RESERVED_BEFORE_CALLER_START',
            scope_id=scope_id,phase='QUALIFICATION_PAIR',request=request,controller_sources=sources,
            caller_CPU_seconds=50,core_CPU_seconds=450,whole_phase_CPU_seconds=500,max_clients=16,
            all_reserved_costs_retained_on_failure=True,created_epoch=now-1,expires_epoch=expiry,
            driver=d.pin(SOURCE)))
        config = dict(schema=d.SCHEMA,scope_id=scope_id,phase='QUALIFICATION_PAIR',issued_epoch=now,
            expires_epoch=expiry,spec=spec_pin,package_root=str(package.parent),constructor=d.pin(CONSTRUCTOR),
            administrative_scope=admin,caller_funding=funding,caller_review={'path':'/pending','sha256':'0'*64})
        review = self.save('review.json',dict(status='PASS_REVIEWED_CALLER_ENVELOPE',
            config_contract_sha256=d.identity({k:v for k,v in config.items() if k!='caller_review'}),
            driver=d.pin(SOURCE),spec=spec_pin,ordinary_entrypoints_preserve_default_SIGXCPU=True))
        config['caller_review']=review
        return self.save('config.json',config), config

    def run_driver(self, config, commands):
        before=resource.getrusage(resource.RUSAGE_CHILDREN)
        result=subprocess.run([sys.executable,'-I','-B',str(SOURCE),'--config',config['path']],
            input=''.join(json.dumps(cmd)+'\n' for cmd in commands),text=True,capture_output=True,timeout=30)
        after=resource.getrusage(resource.RUSAGE_CHILDREN)
        return result, after.ru_utime+after.ru_stime-before.ru_utime-before.ru_stime

    def cleanup_run(self, config):
        import shutil
        path=SOURCE.parent/'runs'/config['scope_id']
        if path.exists(): shutil.rmtree(path)

    def test_typed_action_universe_forbids_compute_validation_and_raw_argv(self):
        for cmd in ({'action':'compute-session'},{'action':'validate-return'},
                    {'action':'stage','argv':['--compute-session']},{'action':True},[] ):
            with self.assertRaises(ValueError): d.command_argv(cmd,{'scope_id':'dummy'})

    def test_exact_aliases(self):
        self.assertEqual(d.command_argv({'action':'cancel'},{'scope_id':'x'}),['--scope','x','--action','cancel-owned'])
        self.assertEqual(d.command_argv({'action':'reconcile'},{'scope_id':'x'}),['--scope','x','--action','reconcile-failure'])

    def test_prepare_cannot_supply_a_different_spec(self):
        with self.assertRaises(ValueError): d.command_argv({'action':'prepare','spec':'/bad'}, {})

    def test_duplicate_and_nonfinite_json_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}'):
            with self.assertRaises(ValueError): d.decode(raw)

    def test_symlink_and_fifo_rejected_without_blocking(self):
        path=self.root/'normal';path.write_text('{}')
        link=self.root/'link';link.symlink_to(path)
        fifo=self.root/'fifo';os.mkfifo(fifo)
        for item in (link,fifo):
            with self.assertRaises(ValueError):d.raw(item)

    def test_bounded_source_read(self):
        p=self.root/'large';p.write_bytes(b'12345')
        with self.assertRaises(ValueError):d.raw(p,4)

    def test_expiry_alarm_rounds_down_and_rejects_subsecond_tail(self):
        with mock.patch.object(d.time,'time',return_value=100.2),mock.patch.object(d.signal,'signal'), \
             mock.patch.object(d.signal,'pthread_sigmask') as mask,mock.patch.object(d.signal,'alarm') as alarm:
            d.arm_expiry(102.9);alarm.assert_called_once_with(2)
            mask.assert_called_once_with(signal.SIG_UNBLOCK,{signal.SIGALRM})
            alarm.reset_mock()
            with self.assertRaises(ValueError):d.arm_expiry(100.9)
            alarm.assert_not_called()

    def test_create_only_preserves_first_record(self):
        p=self.root/'receipt.json';d.write_new(p,{'original':True})
        with self.assertRaises(FileExistsError):d.write_new(p,{'original':False})
        self.assertEqual(d.decode(p.read_bytes()),{'original':True})

    def test_config_validates_dynamic_publication_and_funding(self):
        ref,config=self.config()
        got,_,_=d.validate_config(ref['path'])
        self.assertEqual(got,config)

    def test_HB_publication_pin_resolves_exact_local_spec_copy(self):
        value={'status':'VERIFIED_FEATURE_PUBLICATION'};local=self.save('mapped_publication.json',value)
        hb={'path':'/unmounted/hb/scope/metadata/feature.json','sha256':local['sha256']}
        spec={'remote_root':'/unmounted/hb/scope','files':[dict(relative='metadata/feature.json',
              local=local['path'],sha256=local['sha256'],bytes=Path(local['path']).stat().st_size)]}
        self.assertEqual(d.local_metadata(spec,hb),value)
        spec['files'][0]['sha256']='0'*64
        with self.assertRaises(ValueError):d.local_metadata(spec,hb)

    def test_changed_dynamic_module_fails_closed(self):
        ref,config=self.config()
        (Path(config['package_root'])/'pricefm_hb/profile_control.py').write_text('raise RuntimeError()')
        with self.assertRaisesRegex(ValueError,'module changed'):d.validate_config(ref['path'])

    def test_changed_config_review_rejected(self):
        ref,config=self.config();config['expires_epoch']-=1
        Path(ref['path']).write_bytes(d.encoded(config))
        with self.assertRaisesRegex(ValueError,'reviewed caller'):d.validate_config(ref['path'])

    def test_wrong_core_budget_rejected(self):
        ref,config=self.config();sp=d.read_pin(config['spec']);sp['controller_limits']['aggregate_reserved_CPU_seconds']=400
        Path(config['spec']['path']).write_bytes(d.encoded(sp));config['spec']=d.pin(config['spec']['path'])
        Path(ref['path']).write_bytes(d.encoded(config))
        with self.assertRaisesRegex(ValueError,'450 CPU'):d.validate_config(ref['path'])

    def test_parent_and_client_actual_kernel_limits_with_funded_helper(self):
        ref,config=self.config()
        try:
            result,cpu=self.run_driver(ref,[{'action':'prepare'},{'action':'stop'}])
            self.assertEqual(result.returncode,0,result.stderr)
            root=SOURCE.parent/'runs'/config['scope_id'];slot=root/'client_01'
            terminal=d.decode((slot/'CLIENT_TERMINAL.json').read_bytes())
            self.assertEqual(terminal['returncode'],0,(slot/'stderr.raw').read_text())
            actual=d.decode((slot/'CLIENT_ACTUAL.json').read_bytes())
            self.assertEqual(actual['envelope']['soft_CPU_seconds'],2)
            self.assertTrue(actual['envelope']['SIGXCPU_default']);self.assertTrue(actual['envelope']['SIGXCPU_unblocked'])
            self.assertIn('(40, 40)',(slot/'stdout.raw').read_text())
            self.assertLess(cpu,4)
        finally:self.cleanup_run(config)

    def test_same_scope_cannot_restart_or_reset_budget(self):
        ref,config=self.config()
        try:
            first,_=self.run_driver(ref,[{'action':'stop'}]);self.assertEqual(first.returncode,0,first.stderr)
            second,_=self.run_driver(ref,[{'action':'stop'}]);self.assertNotEqual(second.returncode,0)
            self.assertIn('FileExistsError',second.stderr)
        finally:self.cleanup_run(config)

    def test_failed_startup_consumes_create_only_scope(self):
        ref,config=self.config()
        try:
            (Path(config['package_root'])/'pricefm_hb/profile_control.py').write_text('# changed source\n')
            first,_=self.run_driver(ref,[{'action':'stop'}]);self.assertNotEqual(first.returncode,0)
            root=SOURCE.parent/'runs'/config['scope_id']
            self.assertTrue((root/'DRIVER_INTENT.json').exists());self.assertFalse((root/'DRIVER_START.json').exists())
            second,_=self.run_driver(ref,[{'action':'stop'}]);self.assertNotEqual(second.returncode,0)
            self.assertIn('FileExistsError',second.stderr)
        finally:self.cleanup_run(config)

    def test_max16_clients_with_durable_intents(self):
        ref,config=self.config()
        try:
            result,_=self.run_driver(ref,[{'action':'observe'}]*17)
            self.assertNotEqual(result.returncode,0)
            root=SOURCE.parent/'runs'/config['scope_id']
            self.assertEqual(len(list(root.glob('client_*/CLIENT_INTENT.json'))),16)
            self.assertFalse((root/'client_17').exists())
            for actual in root.glob('client_*/CLIENT_ACTUAL.json'):
                self.assertEqual(d.decode(actual.read_bytes())['parent']['pid'],d.decode((root/'DRIVER_START.json').read_bytes())['process']['pid'])
        finally:self.cleanup_run(config)

    def test_invalid_command_cannot_spawn(self):
        ref,config=self.config()
        try:
            result,_=self.run_driver(ref,[{'action':'compute-session'}])
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(list((SOURCE.parent/'runs'/config['scope_id']).glob('client_*')))
        finally:self.cleanup_run(config)

    def test_external_client_intent_is_rejected(self):
        ref,config=self.config()
        command=self.save('external_command.json',{'action':'observe'})
        intent=self.save('external_intent.json',dict(config=ref,command=command,
            driver=d.pin(SOURCE),scope_id=config['scope_id'],parent=d.process()))
        p=subprocess.run([sys.executable,'-I','-B',str(SOURCE),'--client',ref['path'],command['path'],intent['path']],
            preexec_fn=lambda:d.set_envelope(2),capture_output=True,text=True,timeout=10)
        self.assertNotEqual(p.returncode,0)
        self.assertIn('canonical reserved caller slot paths required',p.stderr)
        self.assertFalse((self.root/'CLIENT_ACTUAL.json').exists())

    def test_replay_slot_has_no_new_execution(self):
        ref,config=self.config()
        try:
            p,_=self.run_driver(ref,[{'action':'observe'},{'action':'stop'}]);self.assertEqual(p.returncode,0,p.stderr)
            slot=SOURCE.parent/'runs'/config['scope_id']/'client_01'
            before=(slot/'CLIENT_ACTUAL.json').read_bytes()
            replay=subprocess.run([sys.executable,'-I','-B',str(SOURCE),'--client',ref['path'],
                str(slot/'COMMAND.json'),str(slot/'CLIENT_INTENT.json')],preexec_fn=lambda:d.set_envelope(2),
                capture_output=True,text=True,timeout=10)
            self.assertNotEqual(replay.returncode,0)
            self.assertEqual((slot/'CLIENT_ACTUAL.json').read_bytes(),before)
        finally:self.cleanup_run(config)

    def test_failed_slot_retained_and_only_explicit_failure_tail_allowed(self):
        ref,config=self.config()
        try:
            p,_=self.run_driver(ref,[{'action':'collect'},{'action':'cancel'},{'action':'reconcile'},{'action':'stop'}])
            self.assertEqual(p.returncode,0,p.stderr)
            root=SOURCE.parent/'runs'/config['scope_id']
            codes=[d.decode((root/('client_%02d'%i)/'CLIENT_TERMINAL.json').read_bytes())['returncode'] for i in (1,2,3)]
            self.assertNotEqual(codes[0],0);self.assertEqual(codes[1:],[0,0])
        finally:self.cleanup_run(config)

    def test_r165_fixed_funding_constants(self):
        self.assertEqual((d.CORE_CPU_SECONDS,d.CALLER_CPU_SECONDS,d.WHOLE_PHASE_CPU_SECONDS,d.PAIR_CONTROL_CPU_SECONDS,d.METADATA_CPU_SECONDS),(450,50,500,1000,4))
        self.assertEqual(d.CALLER_CPU_SECONDS,2+d.MAX_CLIENTS*3)
        self.assertEqual(d.SCHEMA,'r165_caller_envelope_v1')

    def test_legacy_schema_rejected_before_caller_start(self):
        ref,config=self.config();config['schema']='r164_caller_envelope_v1'
        Path(ref['path']).write_bytes(d.encoded(config))
        with self.assertRaisesRegex(ValueError,'configuration'):d.validate_config(ref['path'])

    def test_both_legacy_core_and_phase_funding_are_rejected(self):
        for core,whole in ((350,400),(400,450),(425,475),(450,400),(450,475)):
            ref,config=self.config();funding=d.read_pin(config['caller_funding'])
            funding.update(core_CPU_seconds=core,whole_phase_CPU_seconds=whole)
            Path(config['caller_funding']['path']).write_bytes(d.encoded(funding))
            config['caller_funding']=d.pin(config['caller_funding']['path'])
            Path(ref['path']).write_bytes(d.encoded(config))
            with self.assertRaisesRegex(ValueError,'450 core = 500'):d.validate_config(ref['path'])

    def test_only_four_CPU_metadata_is_the_reviewed_purpose(self):
        for cpu in (2,3,5):
            ref,config=self.config();value=d.read_pin(config['spec'])
            value['controller_limits']['operation_CPU_seconds']=cpu
            Path(config['spec']['path']).write_bytes(d.encoded(value));config['spec']=d.pin(config['spec']['path'])
            Path(ref['path']).write_bytes(d.encoded(config))
            with self.assertRaisesRegex(ValueError,'4 CPU metadata'):d.validate_config(ref['path'])

    def test_actual_caller_hash_must_be_published_auxiliary_source(self):
        for auxiliary in ({},{d.PUBLICATION_SOURCE_KEY:'0'*64}):
            ref,config=self.config();value=d.read_pin(config['spec']);pubref=value['feature_publication'];publication=d.read_pin(pubref)
            publication['auxiliary_sources']=auxiliary
            Path(pubref['path']).write_bytes(d.encoded(publication));value['feature_publication']=d.pin(pubref['path'])
            Path(config['spec']['path']).write_bytes(d.encoded(value));config['spec']=d.pin(config['spec']['path'])
            review=d.read_pin(config['caller_review']);review.update(spec=config['spec'],config_contract_sha256=d.identity({k:v for k,v in config.items() if k!='caller_review'}))
            Path(config['caller_review']['path']).write_bytes(d.encoded(review));config['caller_review']=d.pin(config['caller_review']['path'])
            Path(ref['path']).write_bytes(d.encoded(config))
            with self.assertRaisesRegex(ValueError,'feature publication'):d.validate_config(ref['path'])

    def test_limit_identity_and_action_functions_are_exact_prior_AST(self):
        prior=ast.parse((OLD_TRACKER/'caller_envelope_01/caller_driver.py').read_text())
        current=ast.parse(ORIGINAL_SOURCE.read_text())
        names={'set_envelope','envelope_status','arm_expiry','process','command_argv','invoke','client'}
        def surface(tree):
            return {n.name:ast.dump(n,include_attributes=False) for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names}
        self.assertEqual(set(surface(current)),names)
        self.assertEqual(surface(current),surface(prior))

    def test_actual26_source_bytes_and_full_spec_startup_under_parent_envelope(self):
        ref,config=self.config()
        package=Path(config['package_root'])/'pricefm_hb'
        publication=json.loads((OLD_TRACKER/'publication_slurm_08/FEATURE_PUBLICATION.json').read_text())
        sources={name:d.hashlib.sha256((CONTROLLER_PACKAGE/name).read_bytes()).hexdigest() for name in publication['source_files']}
        self.assertEqual(len(sources),26)
        total_source_bytes=0
        for name,expected in sources.items():
            data=(CONTROLLER_PACKAGE/name).read_bytes()
            self.assertEqual(d.hashlib.sha256(data).hexdigest(),expected)
            (package/name).write_bytes(data);total_source_bytes+=len(data)
        for name,expected in sources.items():
            self.assertEqual(d.hashlib.sha256((CONTROLLER_PACKAGE/name).read_bytes()).hexdigest(),expected)
        original_spec=json.loads((OLD_TRACKER/'prospective_profile/packet_resume_03_admitted/qualification_pair/SPEC_READY_FOR_ROOT_PREPARE.json').read_text())
        value=d.read_pin(config['spec'])
        full=dict(original_spec,**value);full['controller_sources']=sources
        publication_ref=value['feature_publication'];pub=d.read_pin(publication_ref)
        pub['source_files']=sources
        Path(publication_ref['path']).write_bytes(d.encoded(pub));full['feature_publication']=d.pin(publication_ref['path'])
        Path(config['spec']['path']).write_bytes(d.encoded(full));config['spec']=d.pin(config['spec']['path'])
        funding=d.read_pin(config['caller_funding']);funding['controller_sources']=sources
        Path(config['caller_funding']['path']).write_bytes(d.encoded(funding));config['caller_funding']=d.pin(config['caller_funding']['path'])
        review=d.read_pin(config['caller_review']);review.update(spec=config['spec'],config_contract_sha256=d.identity({k:v for k,v in config.items() if k!='caller_review'}))
        Path(config['caller_review']['path']).write_bytes(d.encoded(review));config['caller_review']=d.pin(config['caller_review']['path'])
        Path(ref['path']).write_bytes(d.encoded(config))
        try:
            result,cpu=self.run_driver(d.pin(ref['path']),[{'action':'stop'}])
            self.assertEqual(result.returncode,0,result.stderr)
            root=SOURCE.parent/'runs'/config['scope_id']
            self.assertTrue((root/'DRIVER_START.json').is_file())
            self.assertFalse(list(root.glob('client_*')))
            self.assertLess(cpu,1)
            print(json.dumps({'private_actual26_metadata_startup':'PASS','source_bytes':total_source_bytes,
                'full_original_spec_bytes':len(d.encoded(original_spec)),
                'declared_original_stage_bytes_not_all_read_by_caller':sum(x['bytes'] for x in original_spec['files']),
                'parent_SELF_CPU_seconds_no_client':cpu,'not_actual_admission':True}),flush=True)
        finally:self.cleanup_run(config)

    def test_constructor_import_is_nonmain_and_has_no_top_level_limit_reset(self):
        tree=ast.parse(CONSTRUCTOR.read_text())
        functions={n.name:n for n in tree.body if isinstance(n,ast.FunctionDef)}
        for name in ('prepare','finalize','scope_check'):
            calls=[ast.unparse(n.func) for n in ast.walk(functions[name]) if isinstance(n,ast.Call)]
            self.assertNotIn('resource.setrlimit',calls);self.assertNotIn('signal.signal',calls)
        self.assertIn("run_name='r164_reviewed_constructor_nonmain'",SOURCE.read_text())


if __name__=='__main__':unittest.main(verbosity=2)
