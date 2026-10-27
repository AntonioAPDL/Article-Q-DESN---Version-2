"""Synthetic/private contract tests; no fitted model or numerical campaign call."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import subprocess
import time
import types
import datetime as dt
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
import sys
sys.path.insert(0,str(HERE))
sys.dont_write_bytecode=True
import pricefm_r154_prediction_contract as c
for name in c.THREAD_ENV:os.environ[name]='1'


def module(name,filename):
    spec=importlib.util.spec_from_file_location(name,HERE/filename)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


prepmod=module('r154_test_preparation','520_prepare_pricefm_stage_r154_predictions.py')
runner=module('r154_test_execution','521_run_pricefm_stage_r154_predictions.py')
serial=module('r154_test_serial','522_run_pricefm_stage_r154_serial.py')


class TestImmutableAndStaging(unittest.TestCase):
    def test_immutable_rejects_different_content(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x.json';c.immutable(p,{'old':1});before=p.read_bytes()
            c.immutable(p,{'old':1})
            with self.assertRaises(RuntimeError):c.immutable(p,{'old':2})
            self.assertEqual(p.read_bytes(),before)

    def test_safe_byte_staging_and_alias_hash(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);src=root/'parent.bin';src.write_bytes(b'unchanged parent moment bytes')
            p=root/'preparation.json';c.immutable(p,{'study':'LV','input_files_sha256':{str(src):c.digest(src)}})
            archive=root/'stage.tar';prepmod.export_lv(p,archive)
            receipt=prepmod.import_lv(p,archive,root/'staged')
            aliases=c.read(receipt['path'])['read_aliases']
            self.assertEqual(c.resolve_pin(src,c.digest(src),aliases).read_bytes(),src.read_bytes())
            Path(aliases[str(src)]).write_bytes(b'bad')
            with self.assertRaises(RuntimeError):c.resolve_pin(src,c.digest(src),aliases)

    def test_staging_rejects_undeclared_archive_member_before_extract(self):
        import tarfile,io
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);src=root/'source';src.write_bytes(b'x')
            p=root/'preparation.json';c.immutable(p,{'study':'LV','input_files_sha256':{str(src):c.digest(src)}})
            archive=root/'stage.tar';prepmod.export_lv(p,archive)
            with tarfile.open(archive,'a') as tar:
                info=tarfile.TarInfo('../escape');info.size=1;tar.addfile(info,io.BytesIO(b'x'))
            with self.assertRaises(RuntimeError):prepmod.import_lv(p,archive,root/'staged')
            self.assertFalse((root/'staged').exists())


class TestAuthority(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.prep={'study':'EE','historical_prefix_floor_CPU':100,
            'historical_replacement_floor_CPU':10,'new_campaign_parent':str(self.root)}
        self.pp=self.root/'prep.json';c.immutable(self.pp,self.prep)
        self.identity={'branch':'work/pricefm-r154-test','head':'1'*40}
        self.evidence=self.root/'evidence.json';c.immutable(self.evidence,{'status':'PASS'})
        glob=self.root/'global.json';c.immutable(glob,{'schema':'r154_global_permits_v1','max_new_numerical':1,
            'created_epoch':900,'expires_epoch':2100,'nonrenewing':True,
            'lock_dir':str(self.root/'locks'),'permits':[{'id':'single','host':'muscat','cpu':30,'science':['EE','LV','CERTIFICATE_REFERENCE'],'sequential':True}]})
        self.a={'schema':'r154_prediction_authority_v1','status':'ADMITTED','study':'EE','scope_id':'fresh',
            'host':'muscat','cpu':30,'source':self.identity,'preparation':c.pin(self.pp),
            'start_epoch':1000,'expires_epoch':2000,'max_wall_seconds':1000,'max_execution_wall_seconds':1000,'nonrenewing':True,
            'full_prefix_CPU':100,'replacement_CPU':10,'admin_drain_CPU':20,'guardian_CPU_reserve':2,
            'total_CPU_cap':130,'min_delivered_share':.5,'own_RSS_soft_GiB':24,
            'prior_CPU_charged_seconds':0,
            'peer_census_cadence_seconds':5,
            'minimum_free_disk_GiB':80,'minimum_available_RAM_GiB':192,'new_output_soft_GiB':2,
            'drain_seconds':60,'maximum_atomic_wall_seconds':20,'max_new_tasks':64,
            'allow_extra_seeds':False,'new_fits':0,'official_origins':0,'hard_cgroup_isolation_claimed':False,
            'scheduler_policy':'SCHED_OTHER','nice':10,'io_class':3,
            'output_dir':str(self.root/'pricefm_stage_r154_ee_fresh'),'permit_id':'single',
            'global_contract':c.pin(glob)}
        for key in ('peer_census','resource_policy','pricing_evidence','process_classifier_proof','source_review','admin_rules'):
            self.a[key]=c.pin(self.evidence)
        policy=self.root/'resource_policy.json'
        c.immutable(policy,{'schema':'r154_resource_policy_v1','created_epoch':900,'expires_epoch':2100,'nonrenewing':True,
            'physical_CPU_allocation':{'host':'muscat','cpu':30,'project_numerical_reservation':True},
            'max_new_numerical_workers':1,'science':['EE','LV'],'sequential':True,
            'floors_GiB':{'RAM':192,'disk':80},
            'scheduling':{'policy':'SCHED_OTHER','nice':10,'io_class':3,'threads_per_payload':1}})
        self.a['resource_policy']=c.pin(policy)

    def tearDown(self):self.tmp.cleanup()
    def validate(self,a=None):return c.validate_authority(a or self.a,self.prep,self.pp,self.identity,1100,'muscat')
    def test_positive_whole_prefix(self):self.validate()
    def test_reject_partial_expired_wrong_source_SMT_and_clock_reset(self):
        for key,value in [('full_prefix_CPU',99),('expires_epoch',1001),('source',{'head':'wrong'}),
                          ('cpu',62),('max_wall_seconds',900),('max_new_tasks',65),
                          ('allow_extra_seeds',True),('new_fits',1),('official_origins',1),
                          ('guardian_CPU_reserve',21),('nonrenewing',False),('status','NOT_ADMITTED')]:
            a=copy.deepcopy(self.a);a[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.validate(a)
    def test_calendar_not_funded_by_CPU_alone(self):
        a=copy.deepcopy(self.a);a['min_delivered_share']=.1
        with self.assertRaises(RuntimeError):self.validate(a)
    def test_prior_charge_consumes_total_budget(self):
        a=copy.deepcopy(self.a);a['prior_CPU_charged_seconds']=1
        with self.assertRaises(RuntimeError):self.validate(a)
        a['total_CPU_cap']=131
        self.validate(a)
    def test_queued_absolute_and_active_clocks_are_both_finite(self):
        a=copy.deepcopy(self.a);a['max_execution_wall_seconds']=100
        with self.assertRaises(RuntimeError):self.validate(a)
        a['max_execution_wall_seconds']=1001
        with self.assertRaises(RuntimeError):self.validate(a)
    def test_global_pool_does_not_create_second_permit(self):
        g=self.root/'bad_global.json';glob=c.read(self.a['global_contract']['path'])
        glob['permits'].append(dict(glob['permits'][0],id='second'));c.immutable(g,glob)
        a=copy.deepcopy(self.a);a['global_contract']=c.pin(g)
        with self.assertRaises(RuntimeError):self.validate(a)
    def test_no_historical_output_namespace(self):
        a=copy.deepcopy(self.a);a['output_dir']=str(self.root/'pricefm_stage_r150_bounded_admission_20261023')
        with self.assertRaises(RuntimeError):self.validate(a)
    def test_global_expiry_or_policy_floor_cannot_be_weakened(self):
        for kind in ('expiry','floor','policy'):
            a=copy.deepcopy(self.a)
            if kind=='expiry':
                g=self.root/'expired.json';value=c.read(a['global_contract']['path']);value['expires_epoch']=1900;c.immutable(g,value);a['global_contract']=c.pin(g)
            elif kind=='floor':a['minimum_available_RAM_GiB']=191
            else:a['scheduler_policy']='SCHED_IDLE'
            with self.subTest(kind=kind),self.assertRaises(RuntimeError):self.validate(a)


class TestPeerAndLifetime(unittest.TestCase):
    def row(self,**kwargs):
        d={'pid':123,'start_ticks':999,'boot_id':'boot','state':'S','comm':'python',
           'command':'python new_unreviewed_model.py','argv':['python','new_unreviewed_model.py'],
           'cmdline_sha256':'abc','cpus':[30]};d.update(kwargs);return d
    def test_new_numerical_and_thread_union_conflict(self):
        census={'allowed_intersecting_processes':[]}
        self.assertEqual(len(c.peer_conflicts(30,census,set(),[self.row()])),1)
        self.assertEqual(c.peer_conflicts(30,census,set(),[self.row(cpus=[29])]),[])
        self.assertEqual(c.peer_conflicts(30,census,set(),[self.row(comm='rsync',command='rsync archive')]),[])
    def test_pid_reuse_or_argv_change_does_not_inherit_acceptance(self):
        row=self.row();census={'allowed_intersecting_processes':[row]}
        self.assertFalse(c.peer_conflicts(30,census,set(),[row]))
        for change in ({'start_ticks':1000},{'boot_id':'other'},{'cmdline_sha256':'changed'}):
            self.assertTrue(c.peer_conflicts(30,census,set(),[self.row(**change)]))
    def test_stopped_shell_resume_fails_even_with_same_pid(self):
        row=self.row(comm='bash',command='pipeline.sh',state='T')
        allowed=dict(row,allowed_states=['T'])
        census={'allowed_intersecting_processes':[allowed],'numerical_markers':['pipeline.sh']}
        self.assertFalse(c.peer_conflicts(30,census,set(),[row]))
        self.assertTrue(c.peer_conflicts(30,census,set(),[dict(row,state='S')]))
    def test_exact_source_hashed_controller_rule(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'480.py';path.write_text('frozen controller source')
            rule={'rules':[{'script':c.pin(path),'verb':'controller','cpu_flag':'--cpus','allowed_declared_cpus':list(range(30))}]}
            row=self.row(command=f'python {path} controller --cpus 15,16,17',argv=['python',str(path),'controller','--cpus','15,16,17'])
            census={'allowed_intersecting_processes':[]}
            self.assertFalse(c.peer_conflicts(30,census,set(),[row],rule))
            for args in (['python',str(path),'worker','--cpus','15,16'],
                         ['python',str(path),'controller','--cpus','30'],
                         ['python',str(path),'controller']):
                self.assertTrue(c.peer_conflicts(30,census,set(),[dict(row,argv=args)],rule))
            path.write_text('changed source')
            self.assertTrue(c.peer_conflicts(30,census,set(),[row],rule))
    def test_foreign_argv_not_retained_in_conflict(self):
        conflict=c.peer_conflicts(30,{'allowed_intersecting_processes':[]},set(),[self.row()])[0]
        self.assertNotIn('command',conflict);self.assertNotIn('argv',conflict)
    def test_horizon_callbacks_keep_checks_but_throttle_heartbeat(self):
        lease=c.Lease.__new__(c.Lease);lease.out=Path('/synthetic');lease.own={'pid':1}
        lease._heartbeat_at=0;lease.reserve_total=1
        lease.check=unittest.mock.Mock(return_value={});lease.note_written=unittest.mock.Mock()
        lease.a={'prior_CPU_charged_seconds':0}
        lease.observed_CPU=lambda:0
        with patch.object(c.time,'monotonic',return_value=100),patch.object(c,'update_owned') as write:
            for i in range(1000):lease.observe({'horizon_finished':i})
            self.assertEqual(lease.check.call_count,1000)
            self.assertEqual(write.call_count,1)
            lease.observe({'status':'chunk_sealed'})
            self.assertEqual(write.call_count,2)
        for call in lease.check.call_args_list:self.assertFalse(call.kwargs['fresh_peer'])
    def test_live_plus_reaped_guardian_CPU_no_double_count(self):
        lease=c.Lease.__new__(c.Lease);lease.guardian=456;lease.cpu0=10;lease.guardian_cpu0=0
        with patch.object(c,'cpu_seconds',return_value=15),patch.object(c,'process_identity',return_value={'state':'S','cpu_seconds':2}):
            self.assertEqual(lease.observed_CPU(),7)
        with patch.object(c,'cpu_seconds',return_value=17),patch.object(c,'process_identity',return_value=None):
            self.assertEqual(lease.observed_CPU(),7)
    def test_guardian_held_child_and_no_naked_parent_signal(self):
        source=Path(c.__file__).read_text()
        self.assertIn('signal_unreaped_direct_child(pid,child)',source)
        self.assertIn('os.WNOWAIT',source)
        self.assertIn('libc.prctl(1,signal.SIGKILL',source)
        self.assertNotIn("os.kill(parent",source)
        self.assertIn("single_threaded_only_waiter=True",source)


class TestScientificDescriptorsAndArithmetic(unittest.TestCase):
    def test_frozen_manifest_counts_without_model_execution(self):
        ee=prepmod.ee_preparation();lv=prepmod.lv_preparation()
        self.assertEqual(len(ee['remaining_D_names']),58)
        self.assertEqual(len(ee['retained_checkpoint_packets']),225)
        self.assertEqual(len(lv['call_manifest']),12)
        self.assertEqual({t['seed_index'] for t in ee['tasks']},{0})
        self.assertEqual(ee['max_new_tasks'],64)
    def test_chunk_identity_is_batch_and_clock_stable(self):
        task={'clock_offsets_steps':[0,24],'daily_origin_positions':list(range(10)),
              'origin_timestamps':{'0':[str(i) for i in range(10)],'24':[str(i) for i in range(10)]}}
        chunks=runner.ee_chunks(task)
        self.assertEqual(len(chunks),4)
        self.assertEqual(chunks[-1]['stable_rng_origin_keys'],[8*96+24,9*96+24])
    def test_vector_metrics_remain_seven_levels(self):
        self.assertEqual(runner.metric_mean([[1,2,3,4,5,6,7],[3,4,5,6,7,8,9]]),[2,3,4,5,6,7,8])
    def test_equivalence_rejects_RNG_and_value_drift(self):
        import numpy as np
        a={'ids':np.array([1,2],dtype='<i8'),'prediction':np.array([.1,.2])}
        self.assertEqual(runner.included_equivalence(a,a,1e-11,1e-10),{'prediction':0})
        for b in ({'ids':np.array([2,1]),'prediction':a['prediction']},
                  {'ids':a['ids'],'prediction':np.array([.1,.21])}):
            with self.assertRaises(RuntimeError):runner.included_equivalence(a,b,1e-11,1e-10)
    def test_physical_clock_subtracts_one_hour(self):
        import numpy as np
        def metric(y,q):return {}
        y=np.tile(np.arange(96),(12,1));q=np.zeros((12,96,7))
        anchors=['2024-01-01T00:00:00+00:00']*12
        values=runner.lv_time_diagnostics(y,q,anchors,metric)
        self.assertEqual(values['by_physical_hour']['23']['median_MAE'],1.5)
        self.assertEqual(values['by_physical_hour']['0']['median_MAE'],5.5)
    def test_real_frozen_H96_metric_and_short_subsets(self):
        import numpy as np
        dependency=Path('/data/jaguir26/local/src/Article-Q-DESN/.codex_work/pricefm_r127_closeout_20261008/application/scripts/pricefm')
        sys.path.insert(0,str(dependency))
        actual=module('r154_test_actual_r127_metric',str(dependency/'pricefm_r127_contract.py'))
        truth=np.linspace(-4,20,12*96).reshape(12,96)
        prediction=truth[...,None]+np.asarray([-3,-2,-1,0,1,2,3])
        frozen=actual.common_metrics(truth,prediction)
        result=runner.lv_metric(truth,prediction,actual.common_metrics)
        for key in frozen:self.assertTrue(np.allclose(result[key],frozen[key]))
        for horizon in (24,48):
            with self.assertRaises(ValueError):actual.common_metrics(truth[:,:horizon],prediction[:,:horizon])
            value=runner.lv_metric(truth[:,:horizon],prediction[:,:horizon],actual.common_metrics)
            self.assertEqual(value['median_MAE'],0)
            self.assertEqual(value['coverage_80'],1)
        runner.lv_time_diagnostics(truth,prediction,['2024-01-01T00:00:00+00:00']*12,actual.common_metrics)


class TestDisposableGuardianPrivate(unittest.TestCase):
    """Only disposable stdlib processes, inherited administration CPU31."""
    def script(self,root,mode):
        return """
import sys,os,time,fcntl
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import pricefm_r154_prediction_contract as c
out=Path(sys.argv[2]);out.mkdir()
lease=c.Lease.__new__(c.Lease)
lease.out=out;lease.own=c.process_identity(os.getpid());lease.guardian=None
lease.started=time.monotonic();lease.cpu0=c.cpu_seconds()
lease.a={'expires_epoch':time.time()+(0.4 if sys.argv[3]=='timeout' else 10),'max_wall_seconds':10,'guardian_CPU_reserve':2,'total_CPU_cap':10}
lease.lock=(out/'permit.lock').open('a+');fcntl.flock(lease.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
c.immutable(out/'claim.json',{'permanent_claim':True})
lease._start_guardian()
(out/'ready').write_text(str(lease.guardian))
if sys.argv[3]=='orphan':os._exit(0)
time.sleep(3)
raise RuntimeError('guardian failed to enforce its finite deadline')
"""
    def test_timeout_kills_only_held_direct_payload(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scope'
            child=subprocess.Popen([sys.executable,'-B','-c',self.script(out,'timeout'),str(HERE),str(out),'timeout'],
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            deadline=time.monotonic()+2
            while not (out/'ready').exists() and time.monotonic()<deadline:time.sleep(.01)
            self.assertTrue((out/'ready').exists())
            import fcntl
            with (out/'permit.lock').open('a+') as lock:
                with self.assertRaises(BlockingIOError):fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            _,err=child.communicate(timeout=6)
            self.assertEqual(child.returncode,137,err)
            record=c.read(out/'guardian_timeout.json')
            self.assertEqual(record['parent']['pid'],child.pid)
            self.assertNotEqual(record['payload']['pid'],child.pid)
            self.assertTrue(record['permit_not_released'])
            self.assertIn('held_unreaped_direct_child',record['action'])
            self.assertTrue((out/'claim.json').exists())
    def test_orphan_guardian_drains_and_permanent_claim_survives(self):
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scope'
            child=subprocess.Popen([sys.executable,'-B','-c',self.script(out,'orphan'),str(HERE),str(out),'orphan'],
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            _,err=child.communicate(timeout=6)
            self.assertEqual(child.returncode,0,err)
            end=time.monotonic()+2
            acquired=False
            with (out/'permit.lock').open('a+') as lock:
                while time.monotonic()<end:
                    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);acquired=True;break
                    except BlockingIOError:time.sleep(.05)
            self.assertTrue(acquired,'orphan retained shared permit beyond own parent drain')
            self.assertTrue((out/'claim.json').exists(),'OS lock release must not erase a permanent science claim')
            receipt=c.read(out/'supervisor_exit_receipt.json')
            self.assertGreater(receipt['exact_combined_reaped_CPU_seconds'],0)
    def test_supervisor_death_kernel_drains_payload_and_locks(self):
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scope'
            parent=subprocess.Popen([sys.executable,'-B','-c',self.script(out,'parentdeath'),str(HERE),str(out),'parentdeath'],
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            deadline=time.monotonic()+2
            while not (out/'ready').exists() and time.monotonic()<deadline:time.sleep(.01)
            self.assertTrue((out/'ready').exists())
            # Popen owns this unreaped direct test child; it cannot recycle.
            parent.kill();parent.communicate(timeout=4)
            self.assertEqual(parent.returncode,-9)
            end=time.monotonic()+2;acquired=False
            with (out/'permit.lock').open('a+') as lock:
                while time.monotonic()<end:
                    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);acquired=True;break
                    except BlockingIOError:time.sleep(.05)
            self.assertTrue(acquired,'kernel PDEATHSIG left numerical payload holding permit')
            self.assertTrue((out/'payload_identity.json').exists())


class TestLVFakeBackendEndToEnd(unittest.TestCase):
    def test_exact12_calls_six_operators_all_metrics_sealed(self):
        """I/O/DAG fixture only: no real model, sampler, fit or forecast helper."""
        import numpy as np
        prep=prepmod.lv_preparation()
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);out=root/'output';out.mkdir()
            fake_source=root/'core.py';fake_source.write_text('# synthetic backend fixture only\n')
            prep=dict(prep,source={'branch':'work/pricefm-r154-fixture','head':'fake'},
                input_files_sha256={str(fake_source):c.digest(fake_source)},
                public_core=c.pin(fake_source),bank=c.pin(fake_source),original_campaign=str(root/'old'))
            anchors=np.asarray([(dt.datetime(2022,2,4,tzinfo=dt.timezone.utc)+dt.timedelta(days=i)).isoformat() for i in range(940)])
            raw=types.SimpleNamespace(response=np.tile(np.linspace(-2,3,96),(940,1)),anchors=anchors)
            boundaries=[(506,631),(631,766),(766,940)]
            cells=[{'train':np.arange(a),'validation':np.arange(a,b)} for a,b in boundaries]
            scaler={'price_mean':0.,'price_scale':1.}
            groups=[]
            for group in prep['training_groups']:
                group=dict(group,scaler=scaler);groups.append(group)
                for name in group['parents']:
                    c.immutable(Path(prep['original_campaign'])/'tasks_done'/name/'result.json',{'certified':True})
            prep['training_groups']=groups
            runtime=types.SimpleNamespace(internal_splits=lambda n:cells,
                standardize_from_training_origins=lambda arrays,idx:(arrays,scaler),
                load_normal_fit=lambda path:{'fixture':True},load_quantile_fit=lambda path:{'fixture':True})
            core=types.SimpleNamespace(dependencies=lambda path:runtime,load_arrays=lambda runtime,path:raw)
            def shifted(arrays,idx,offset,validation):
                return types.SimpleNamespace(response=arrays.response[idx],anchors=np.asarray([
                    (dt.datetime.fromisoformat(str(arrays.anchors[i]))+dt.timedelta(minutes=15*offset)).isoformat() for i in idx]))
            calls=[]
            def forecast(runtime,arrays,spec,normal,quantiles,positions,seed,observe):
                calls.append((positions.tolist(),seed))
                prediction=arrays.response[...,None]+np.asarray([-3,-2,-1,0,1,2,3])
                values={name:prediction.copy() for name in runner.OPS}
                values['path_specific']=prediction[...,::-1].copy()
                return dict(values,truth=arrays.response),{'paths':500,'synthetic_fixture':True}
            dependency=Path('/data/jaguir26/local/src/Article-Q-DESN/.codex_work/pricefm_r127_closeout_20261008/application/scripts/pricefm')
            sys.path.insert(0,str(dependency))
            actual=module('r154_fixture_real_metric',str(dependency/'pricefm_r127_contract.py'))
            replay=types.ModuleType('pricefm_r126_replay');replay.forecast=forecast
            contract=types.ModuleType('pricefm_r127_contract');contract.shifted_windows=shifted
            contract.window_identity=lambda *args:None;contract.common_metrics=actual.common_metrics
            c.immutable(out/'authority.json',{'synthetic_private_test':True})
            class FakeLease:
                def __init__(self):
                    self.out=out;self.a={'scope_id':'fixture','permit_id':'fixture','LV_call_CPU':10,
                        'full_prefix_CPU':120,'maximum_atomic_wall_seconds':60,'read_aliases':None};self.reservations=[]
                def check(self,*args,**kwargs):pass
                def observe(self,event):pass
                def reserve(self,name,cpu):self.reservations.append((name,cpu))
                def note_written(self,path):pass
            lease=FakeLease()
            with patch.object(runner,'load_module',return_value=core),patch.object(runner,'numerical_pools',return_value=[{'num_threads':1}]),patch.dict(sys.modules,{'pricefm_r126_replay':replay,'pricefm_r127_contract':contract}):
                result=runner.run_lv(prep,lease)
            self.assertEqual(len(calls),12);self.assertEqual(len(lease.reservations),12)
            self.assertEqual(len(list((out/'tasks_done').iterdir())),12)
            self.assertEqual(result['origin_clock_pairs'],144)
            self.assertEqual(set(result['folds']),set(runner.OPS))
            self.assertEqual(len(result['equal_three_split_macro']['cdf_pool_clipped']['exceedance']),7)
            self.assertEqual(result['equal_three_split_macro']['path_specific']['crossing_rate'],1)
            self.assertFalse(result['promotion_authorized'])
            for (positions,seed),call in zip(calls,prep['call_manifest']):
                self.assertEqual(positions,call['original_origin_clock_positions']);self.assertEqual(seed,call['call_seed'])


class TestSerialOnceOnly(unittest.TestCase):
    def test_success_dispatches_EE_then_LV_once(self):
        grants=[({'study':'EE'},{},{}),({'study':'LV'},{},{})];seen=[]
        results=serial.run_chain(grants,lambda stage,a,p:seen.append(stage['study']) or stage['study'])
        self.assertEqual(seen,['EE','LV']);self.assertEqual(results,['EE','LV'])
    def test_failure_or_defer_never_dispatches_LV(self):
        for reason in ('INCOMPLETE','RESOURCE_DEFERRED','CERTIFICATE_FAILED'):
            seen=[]
            def fail(stage,a,p):seen.append(stage['study']);raise RuntimeError(reason)
            with self.assertRaises(RuntimeError):serial.run_chain([({'study':'EE'},{},{}),({'study':'LV'},{},{})],fail)
            self.assertEqual(seen,['EE'])
    def test_busy_shared_permit_not_reassigned(self):
        import fcntl
        with tempfile.TemporaryDirectory() as d:
            glob={'lock_dir':d}
            with (Path(d)/'same.lock').open('a+') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                self.assertFalse(serial.permit_free(glob,'same'))
            self.assertTrue(serial.permit_free(glob,'same'))
    def test_old_authority_clocks_and_physical_drain_are_enforced(self):
        source=Path(serial.__file__).read_text()
        self.assertIn('validate_authority(authority,prep',source)
        self.assertIn('complete_and_drained(name,authority,identity)',source)
        self.assertIn("not (out/'claim.json').exists()",source)
        self.assertIn('parent_death_arm(parent)',source)
        self.assertNotIn("authority['start_epoch']=",source)
    def test_exact_drain_and_assessment_seals_are_required(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d);identity={'head':'frozen','branch':'work/pricefm-r154-test'}
            authority={'output_dir':str(out),'scope_id':'scope'}
            c.immutable(out/'authority.json',authority)
            c.immutable(out/'assessment.json',{'status':'COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED'})
            execution={'source':identity,'scope_id':'scope','authority':c.pin(out/'authority.json')}
            c.immutable(out/'assessment_seal.json',{'assessment':c.pin(out/'assessment.json'),'execution':execution})
            child={'pid':123,'boot_id':'old','start_ticks':5}
            c.immutable(out/'supervisor_exit_receipt.json',{'child_exit_code':0,'parent':child,'payload':dict(child,pid=124)})
            with patch.object(serial,'process_identity',return_value=None):self.assertTrue(serial.complete_and_drained('EE',authority,identity)['physical_drain'])
            with patch.object(serial,'process_identity',return_value=child):
                with self.assertRaises(RuntimeError):serial.complete_and_drained('EE',authority,identity)
            (out/'assessment.json').write_text('{"status":"COMPLETE_INITIAL_PREFIX_TAMPERED"}')
            with patch.object(serial,'process_identity',return_value=None):
                with self.assertRaises(RuntimeError):serial.complete_and_drained('EE',authority,identity)
    def test_expired_queue_denies_before_any_child_or_claim(self):
        a={'schema':'r154_serial_queue_authority_v1','status':'ADMITTED','source':{},'host':'muscat','administrative_cpu':31,
            'new_fits':0,'new_forecasts':0,'automatic_retry':False,'nonrenewing':True,'start_epoch':1,'expires_epoch':2,'max_wall_seconds':1}
        with self.assertRaises(RuntimeError):serial.validate_queue(a,{},3,'muscat')


if __name__=='__main__':unittest.main()
