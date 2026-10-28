"""Canonical ledger tests with real files and explicit external proof boundaries.

No network, Slurm, numerical package imports, arrays, or real registry writes.
Scientific arithmetic and complete-set rules are tested in prefix_tests.py.
"""
import copy
import math
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from . import prefix as p, prefix_control as c, registry as r
from .prefix_tests import fixture


class LedgerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cost,cls.prep,cls.config,timing=fixture()
        cls.price=p.price_prefix(cost,timing)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.central=self.root/'registry'
        self.packet={'scope_id':'fixed-policy','created_epoch':900.,'expires_epoch':15000.,'HB_max_workers':1,
            'scale_amendments':[],'legacy_contract':{},'legacy_resource_policy':{},'local_permit':{'CPU':1},'execution_sources':{}}
        self.policy_path=self.write('policy.json',self.packet)
        self.plan={'study':'FI','pricing':copy.deepcopy(self.price),'cost_publication':'/test/cost',
            'cost_plan':{'claim':{'scientific_exclusion_key':'fixed-parent'}},
            'scientific_manifest':{key:self.prep[key] for key in ('source','region','control','packages','tasks','frozen_audit_permutation')}}
        self.resource_plan_path=self.write('cost-plan.json',self.plan['cost_plan'])
        self.plan['original_cost_plan']=c.pin(self.resource_plan_path)
        self.plan_path=self.write('plan.json',self.plan)
        self.sources={'prefix.py':'a'*64}
        for obj,name,value in [(c,'CENTRAL',self.central),(c,'owner',lambda:None),
            (c.time,'time',lambda:1000.),(p,'executed_sources',lambda:self.sources),
            (p,'validate_plan',lambda *args,**kwargs:(self.prep,self.config)),
            (p,'metadata',lambda value:(self.prep,self.config)),
            (p,'price_prefix',lambda *args,**kwargs:copy.deepcopy(self.price)),
            (c,'cost_basis',lambda path:(self.plan['cost_plan'],{},None,None)),
            (c.policy,'validate_policy',lambda value,**kwargs:value)]:
            patcher=patch.object(obj,name,value);patcher.start();self.addCleanup(patcher.stop)
        proofs=[]
        for name in ('COMPONENT_LIFECYCLE_FI','COMPONENT_LIFECYCLE_DK2','ASSESSMENT_LIFECYCLE_FI',
                'ASSESSMENT_LIFECYCLE_DK2','JOINT_PREPARATION_CACHE_FINALIZATION'):
            path=self.write('measurement-'+name+'.json',{'operation':name,'status':'ROOT_REVIEWED_MEASURED_CONTROLLER_OPERATION',
                'controller':p.OWNER,'executed_sources':self.sources,'complete_operation_measured':True,
                'no_candidate_losses_used':True,'numerical_calls':0,'aggregate_CPU_seconds':.1})
            proofs.append(c.pin(path))
        self.controller_price_path=self.write('controller-price.json',{'schema':'r157_hb_prefix_controller_price_v1',
            'controller':p.OWNER,'policy_scope_id':'fixed-policy','pool_id':'r157-prefix-controller-fixed-policy',
            'ceiling_CPU_seconds':1800,'old_pool_reset':False,'no_candidate_losses_used':True,'measurements':proofs})
        draft=c.draft_master(self.plan_path,c.pin(self.policy_path),expires_epoch=14000.,controller_price_pin=c.pin(self.controller_price_path))
        authorization={'status':'ROOT_REVIEWED_CACHED_NORMAL_PREFIX_AUTHORIZATION','controller':p.OWNER,
            'master_draft_sha256':r.identity(draft),'actual_cost_publication_accepted':True,
            'user_requested_implementation':True,'all_original_scientific_bounds_preserved':True}
        self.auth_path=self.write('authorization.json',authorization)
        self.master=c.adopt_master(draft,c.pin(self.auth_path),self.plan)
        self.master_path=self.write('master.json',self.master)
        self.ledger=c.Ledger();self.ledger.admit(self.plan_path,self.master_path)
        self.wave_path=self.wave('wave1');self.ledger.open_wave('FI',self.wave_path)
        self.task=next(t for t in self.prep['tasks'] if t['name'] in self.ledger.queue('FI')['ready'])

    def write(self,name,value):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value);return path

    def wave(self,name):
        return self.write(name+'.json',{'schema':c.WAVE_SCHEMA,'status':'ROOT_ADMITTED_FINITE_PREFIX_WAVE',
            'controller':p.OWNER,'study':'FI','master':c.pin(self.master_path),'wave_id':name,
            'started_epoch':1000.,'expires_epoch':8200.,'dispatch_expires_epoch':6400.,'automatic_retry':False})

    def change(self,fn):
        value=self.ledger.snapshot();fn(value);r.write(self.ledger.path,value);return value

    def release(self,key='op1',replacement=None,task=None):
        task=task or self.task;cpu=self.price['rounded_task_CPU_reservations'][task['name']]
        release={'purpose':'CACHED_NORMAL_COMPONENT','study':'FI','task_key':key,
            'plan_sha256':r.digest(self.plan_path),'policy_pin':c.pin(self.policy_path),
            'resources':{'cpus':1,'memory_MiB':4096,'cpu_seconds':cpu,
                'wall_seconds':math.ceil(self.price['task_estimates'][task['name']]['estimated_wall_seconds'])},
            'backend':{'plan_path':str(self.plan_path),'master':c.pin(self.master_path),'study_key':self.master['scope_id'],
                'wave_key':'wave1','wave':c.pin(self.wave_path),'component_name':task['name'],
                'task_sha256':r.identity(task),'replacement_of':replacement,
                'controller_CPU_pool':self.master['controller_pricing']['pool_id'],'controller_CPU_ceiling':1800,
                'controller_price':self.master['controller_price'],'controller_CPU_reservation':1,
                'controller_whole_grid_CPU_seconds':182}}
        path=self.root/key;path.mkdir();r.write(path/'release.json',release);return release,path

    def reserve(self,key='op1',replacement=None,task=None):
        release,path=self.release(key,replacement,task);return c.lifecycle_reserve(release,path,{})

    def fail(self,key='op1'):
        return c.lifecycle_complete(key,{'application_passed':False},'/quarantine',{'terminal':True,'squeue':''})

    def test_admin_import_has_no_numerical_runtime(self):
        self.assertNotIn('numpy',sys.modules);self.assertNotIn('scipy',sys.modules)

    def test_master_requires_full_original_price(self):
        plan=copy.deepcopy(self.plan);plan['pricing']['prefix_admitted']=False
        path=self.write('deferred.json',plan)
        with self.assertRaisesRegex(p.PrefixError,'full D'):c.draft_master(path,c.pin(self.policy_path),expires_epoch=12000.)

    def test_master_needs_independent_exact_review(self):
        auth=r.read(self.auth_path);auth['all_original_scientific_bounds_preserved']=False
        path=self.write('bad-review.json',auth);draft=dict(self.master,status='DRAFT_NOT_ADMITTED',authorization=None)
        with self.assertRaisesRegex(p.PrefixError,'independently reviewed'):c.adopt_master(draft,c.pin(path),self.plan)

    def test_master_clock_cannot_renew(self):
        with self.assertRaisesRegex(p.PrefixError,'finite new master'):
            c.draft_master(self.plan_path,c.pin(self.policy_path),expires_epoch=15001.)

    def test_unmeasured_controller_price_cannot_admit_master(self):
        with self.assertRaisesRegex(p.PrefixError,'explicit measured'):
            c.draft_master(self.plan_path,c.pin(self.policy_path),expires_epoch=14000.)

    def test_joint_controller_grid_fits_one_shared_pool_with_replacements(self):
        price=c.controller_price(c.pin(self.controller_price_path),self.packet)
        self.assertEqual(price['whole_joint_grid_projected_CPU_seconds'],182)
        self.assertEqual(price['counts']['COMPONENT_LIFECYCLE_FI'],88)
        self.assertEqual(price['counts']['COMPONENT_LIFECYCLE_DK2'],91)
        self.assertEqual(price['ceiling_CPU_seconds'],1800)

    def test_full_controller_price_defers_instead_of_silently_doubling_pool(self):
        value=r.read(self.controller_price_path)
        for record in value['measurements']:
            proof=r.read(record['path']);proof['aggregate_CPU_seconds']=20.
            path=self.write('expensive-'+proof['operation']+'.json',proof);record.update(c.pin(path))
        path=self.write('expensive-price.json',value)
        with self.assertRaisesRegex(p.PrefixError,'joint controller grid exceeds'):
            c.draft_master(self.plan_path,c.pin(self.policy_path),expires_epoch=14000.,controller_price_pin=c.pin(path))

    def test_study_cannot_be_reset_after_admission(self):
        with self.assertRaisesRegex(p.PrefixError,'no reset'):self.ledger.admit(self.plan_path,self.master_path)

    def test_changed_cost_lineage_cannot_be_admitted(self):
        self.change(lambda state:state['studies'].clear())
        with patch.object(c,'cost_basis',return_value=({'other':True},{},None,None)):
            with self.assertRaisesRegex(p.PrefixError,'cost lineage'):self.ledger.admit(self.plan_path,self.master_path)

    def test_source_changed_master_is_rejected(self):
        with patch.object(p,'executed_sources',return_value={'prefix.py':'b'*64}):
            with self.assertRaisesRegex(p.PrefixError,'source-bound'):self.ledger.current('FI')

    def test_calendar_observation_retains_original_wave_and_cost_bytes(self):
        path=self.root/'calendar.json';value=c.calendar_observation('FI',path)
        self.assertEqual(value['expires_epoch'],8200.);self.assertFalse(value['expires_reset'])
        self.assertEqual(value['resource_plan_sha256'],r.digest(self.resource_plan_path))
        self.assertEqual(c.validate_calendar_observation(value,c.pin(self.plan_path),c.pin(self.resource_plan_path)),value)
        with self.assertRaises(FileExistsError):c.calendar_observation('FI',path)

    def test_calendar_observation_cannot_renew_original_expiry(self):
        value=c.calendar_observation('FI',self.root/'calendar.json');value['expires_epoch']+=1
        with self.assertRaisesRegex(p.PrefixError,'cannot renew'):
            c.validate_calendar_observation(value,c.pin(self.plan_path),c.pin(self.resource_plan_path))

    def test_old_observation_requires_activation_mode_and_does_not_extend_dispatch(self):
        value=c.calendar_observation('FI',self.root/'calendar.json')
        with patch.object(c.time,'time',return_value=1401.):
            with self.assertRaisesRegex(p.PrefixError,'fresh observation'):
                c.validate_calendar_observation(value,c.pin(self.plan_path),c.pin(self.resource_plan_path))
            c.validate_calendar_observation(value,c.pin(self.plan_path),c.pin(self.resource_plan_path),allow_stale=True)
        with patch.object(c.time,'time',return_value=8201.):
            with self.assertRaisesRegex(p.PrefixError,'cannot renew'):
                c.validate_calendar_observation(value,c.pin(self.plan_path),c.pin(self.resource_plan_path),allow_stale=True)

    def test_three_wave_ceiling_is_cumulative(self):
        for name in ('wave2','wave3'):self.ledger.open_wave('FI',self.wave(name))
        with self.assertRaisesRegex(p.PrefixError,'three-wave'):self.ledger.open_wave('FI',self.wave('wave4'))

    def test_unresolved_attempt_blocks_next_wave(self):
        self.reserve()
        with self.assertRaisesRegex(p.PrefixError,'unresolved'):self.ledger.open_wave('FI',self.wave('wave2'))

    def test_no_new_dispatch_after_original_wave_clock(self):
        release,path=self.release()
        with patch.object(c.time,'time',return_value=6401.):
            with self.assertRaisesRegex(p.PrefixError,'dispatch closed'):c.lifecycle_reserve(release,path,{})

    def test_reservation_is_exact_integer_prepriced_amount(self):
        claim=self.reserve();expected=self.price['rounded_task_CPU_reservations'][self.task['name']]
        self.assertEqual(claim['reserved_CPU_seconds'],expected)
        self.assertEqual(c.budget_view(self.ledger.snapshot()['studies']['FI'])['active_reservations_CPU_seconds'],expected)

    def test_fractional_or_smaller_claim_cannot_erase_reservation(self):
        release,path=self.release();release['resources']['cpu_seconds']-=.5;r.write(path/'release.json',release)
        with self.assertRaisesRegex(p.PrefixError,'prepriced integer'):c.lifecycle_reserve(release,path,{})

    def test_study_master_policy_and_plan_are_bound(self):
        for field,value in [('plan_sha256','b'*64),('policy_pin',None)]:
            release,path=self.release('bad-'+field);release[field]=value;r.write(path/'release.json',release)
            with self.assertRaisesRegex(p.PrefixError,'immutable study'):c.lifecycle_reserve(release,path,{})

    def test_current_stage_forbids_seed0_before_complete_D(self):
        task=next(t for t in self.prep['tasks'] if t['mode']=='S')
        with self.assertRaisesRegex(p.PrefixError,'fixed scientific stage'):self.reserve(task=task)

    def test_duplicate_global_key_never_adds_a_scientific_attempt(self):
        self.reserve();release=r.read(self.root/'op1/release.json')
        with self.assertRaisesRegex(p.PrefixError,'already spent'):c.lifecycle_reserve(release,self.root/'op1',{})

    def test_aggregate_concurrency_counts_other_study_and_assessment(self):
        def occupy(state):state['studies']['DK2']={'claims':{},'assessment':{'state':'RESERVED'}}
        self.change(occupy)
        with self.assertRaisesRegex(p.PrefixError,'concurrency'):self.reserve()

    def test_unknown_replacement_lineage_is_rejected(self):
        with self.assertRaisesRegex(p.PrefixError,'unknown replacement'):self.reserve(replacement='unseen')

    def test_failure_spends_full_amount_and_never_credits_partial_CPU(self):
        claim=self.reserve();completed=self.fail()
        self.assertEqual(completed['charged_CPU_seconds'],claim['reserved_CPU_seconds'])
        view=c.budget_view(self.ledger.snapshot()['studies']['FI'])
        self.assertEqual(view['failed_spent_CPU_seconds'],claim['reserved_CPU_seconds']);self.assertFalse(view['failed_attempts_refunded'])

    def test_unresolved_failure_never_becomes_replacement_eligible(self):
        self.reserve()
        with self.assertRaisesRegex(p.PrefixError,'unresolved execution'):
            c.lifecycle_complete('op1',{'application_passed':False},'/quarantine',{'terminal':False,'squeue':''})
        self.assertEqual(self.ledger.snapshot()['studies']['FI']['claims']['op1']['state'],'RESERVED')

    def test_failed_task_requires_explicit_replacement_and_only_one(self):
        self.reserve();self.fail();queue=self.ledger.queue('FI')
        self.assertNotIn(self.task['name'],queue['ready']);self.assertEqual(queue['explicit_replacement_candidates'],['op1'])
        with self.assertRaisesRegex(p.PrefixError,'duplicate task'):self.reserve('implicit')
        replacement=self.reserve('replacement',replacement='op1');self.fail('replacement')
        self.assertEqual(replacement['replacement_of'],'op1')
        with self.assertRaisesRegex(p.PrefixError,'duplicate task'):self.reserve('third',replacement='replacement')
        self.assertEqual(self.ledger.snapshot()['studies']['FI']['replacements_used'],1)

    def test_collection_after_master_expiry_cannot_reopen_dispatch(self):
        self.reserve()
        with patch.object(c.time,'time',return_value=15001.):
            self.fail()
            with self.assertRaisesRegex(p.PrefixError,'expired'):self.ledger.current('FI')
        self.assertEqual(self.ledger.snapshot()['studies']['FI']['claims']['op1']['state'],'FAILED_COMPONENT_RECONCILED')

    def test_protected_replacement_reserve_cannot_be_spent_by_normal_component(self):
        cpu=self.price['rounded_task_CPU_reservations'][self.task['name']]
        reserve=self.price['rounded_replacement_CPU_reservation']
        def spend(state):state['studies']['FI']['claims']['old']={'task':'other','state':'FAILED_COMPONENT_RECONCILED',
            'reserved_CPU_seconds':32400-cpu-reserve+.5,'charged_CPU_seconds':32400-cpu-reserve+.5}
        self.change(spend)
        with self.assertRaisesRegex(p.PrefixError,'protected'):self.reserve()

    def test_failure_cannot_be_reconciled_twice(self):
        self.reserve();self.fail()
        with self.assertRaisesRegex(p.PrefixError,'already reconciled'):self.fail()

    def successful_publication(self,claim):
        publication=self.root/'publication';output=publication/'outputs/PREFIX_TRAINING/FI'/self.task['name'];output.mkdir(parents=True)
        r.write(publication/'authority.json',{'authority':'sealed'});r.write(publication/'activation.json',{'activation':'sealed'})
        execution={'plan_sha256':r.digest(self.plan_path),'allocation':{'job_id':'123'},
            'authority_sha256':r.digest(publication/'authority.json'),'activation_sha256':r.digest(publication/'activation.json')}
        r.write(output/'execution_identity.json',execution)
        component={'schema':p.RESULT_SCHEMA,'name':self.task['name'],'source':self.prep['source'],'mode':self.task['mode'],
            'scientific_identity_sha256':self.task['scientific_identity_sha256'],'task_sha256':r.identity(self.task),
            'metrics':{'AQL':10.},'origin_clock_windows':4*len(self.task['daily_origin_positions']),
            'chunk_count':len(p.original('chunks')(self.task)),'new_model_fits':0,'posterior_updated':False,
            'test_opened':False,'promotion_authorized':False}
        r.write(output/'result.json',component);r.write(output/'completed_evidence.json',{})
        sacct='\n'.join(f'{name}|COMPLETED|0:0|1|1|00:00:00.250|500K|node-07' for name in ('123','123.batch','123.0'))
        accounting={'task_key':claim['task_key'],'release_sha256':claim['release_sha256'],'job_id':'123',
            'terminal':True,'squeue':'','sacct':sacct}
        return publication,component,accounting

    def test_success_counts_parent_TotalCPU_once_and_preserves_all_reservations(self):
        claim=self.reserve();publication,component,accounting=self.successful_publication(claim)
        with patch.object(c,'verify_component',return_value=component):
            saved=c.lifecycle_complete('op1',{'application_passed':True},publication,accounting)
        self.assertEqual(saved['charged_CPU_seconds'],.25)
        view=c.budget_view(self.ledger.snapshot()['studies']['FI'])
        self.assertEqual(view['completed_charged_CPU_seconds'],.25)
        self.assertEqual(view['all_reservations_ever_CPU_seconds'],claim['reserved_CPU_seconds'])

    def test_success_from_other_execution_cannot_receive_CPU_credit(self):
        claim=self.reserve();publication,component,accounting=self.successful_publication(claim)
        accounting['task_key']='another-task'
        with patch.object(c,'verify_component',return_value=component):
            with self.assertRaisesRegex(p.PrefixError,'job/source'):
                c.lifecycle_complete('op1',{'application_passed':True},publication,accounting)
        self.assertEqual(self.ledger.snapshot()['studies']['FI']['claims']['op1']['state'],'RESERVED')

    def test_CPU_scope_violation_cannot_receive_successful_credit(self):
        claim=self.reserve();publication,component,accounting=self.successful_publication(claim)
        seconds=claim['resources']['cpu_seconds']+1
        duration=f'{seconds//3600:02d}:{seconds%3600//60:02d}:{seconds%60:02d}'
        accounting['sacct']=accounting['sacct'].replace('00:00:00.250',duration)
        with patch.object(c,'verify_component',return_value=component):
            with self.assertRaisesRegex(p.PrefixError,'CPU/wall'):
                c.lifecycle_complete('op1',{'application_passed':True},publication,accounting)

    def test_policy_scaling_cannot_change_local_assignment_or_clocks(self):
        for field,value in [('expires_epoch',16000.),('local_permit',{'CPU':2}),('scope_id','renewed')]:
            new=dict(self.packet,HB_max_workers=2);new[field]=value;path=self.write('policy-'+field+'.json',new)
            with self.assertRaisesRegex(p.PrefixError,'cannot renew'):self.ledger.set_policy(c.pin(path))

    def test_assessment_uses_separate1800_budget_and_once_only(self):
        release,path=self.release('assessment');release['purpose']='PREFIX_ASSESSMENT'
        release['resources'].update(cpu_seconds=1800,wall_seconds=1800)
        snapshot=self.write('assessment/assessment_snapshot.json',{})
        release['backend'].update(kind='assessment',assessment_snapshot_sha256=r.digest(snapshot))
        r.write(path/'release.json',release)
        with patch.object(p,'manifest_state',return_value={'assessment_ready':True}):
            claim=c.lifecycle_reserve(release,path,{})
            with self.assertRaisesRegex(p.PrefixError,'already spent'):c.lifecycle_reserve(release,path,{})
        state=self.ledger.snapshot();self.assertEqual(claim['reserved_CPU_seconds'],1800)
        self.assertEqual(c.budget_view(state['studies']['FI'])['remaining_numerical_CPU_seconds'],32400)
        self.assertEqual(c.active_count(state),1)

    def test_partial_scientific_set_cannot_start_assessment(self):
        release,path=self.release('assessment');release['purpose']='PREFIX_ASSESSMENT'
        release['resources'].update(cpu_seconds=1800,wall_seconds=1800)
        snapshot=self.write('assessment/assessment_snapshot.json',{})
        release['backend'].update(kind='assessment',assessment_snapshot_sha256=r.digest(snapshot));r.write(path/'release.json',release)
        with self.assertRaisesRegex(p.PrefixError,'partial scientific set'):c.lifecycle_reserve(release,path,{})

    def test_validated_cache_is_exact_plan_config_and_physical_root(self):
        config={'remote_root':'/mnt/beegfs/home/jaguir26/r157'};manifest=self.write('cache_manifest.json',{'files':{}})
        receipt={'schema':'r157_hb_shared_prefix_cache_v1','status':'VERIFIED_SHARED_PREFIX_CACHE',
            'plan':c.pin(self.plan_path),'config_sha256':r.identity(config),'cache_manifest':c.pin(manifest),
            'remote_root':config['remote_root']+'/prefix-cache-'+r.digest(self.plan_path)[:32],
            'remote_manifest_sha256':r.digest(manifest)}
        path=self.write('receipt.json',receipt);self.assertEqual(c.validate_cache_receipt(path,self.plan_path,config),receipt)
        for field,value in [('remote_root','/tmp/other'),('config_sha256','b'*64),('remote_manifest_sha256','b'*64)]:
            bad=dict(receipt);bad[field]=value;path=self.write('receipt-'+field+'.json',bad)
            with self.assertRaisesRegex(p.PrefixError,'content-bound'):c.validate_cache_receipt(path,self.plan_path,config)

    def test_real_component_release_seal_and_scientific_reservation_are_wired(self):
        from . import lifecycle
        request={'purpose':'CACHED_NORMAL_COMPONENT','execution_plan_sha256':r.digest(self.plan_path),
            'scientific_exclusion_key':'fixed-parent|'+self.task['name'],'policy_pin':c.pin(self.policy_path),
            'runtime_python':'/mnt/beegfs/home/jaguir26/runtime/bin/python','environment_bundle':{'prepared':'qualified'}}
        request_path=self.write('request.json',request);destination=self.root/'prepared-release'
        config={'remote_root':'/mnt/beegfs/home/jaguir26/r157'}
        gate={'site':{'node':'node-12','memory_mib':4096}}
        def static_inputs(plan,root):(Path(root)/'stage').mkdir()
        with patch.object(c.ctl,'config',return_value=config),patch.object(c,'stage_original_inputs',side_effect=static_inputs),\
                patch.object(lifecycle,'validate_request',return_value=gate),patch.object(lifecycle,'owner',return_value=None),\
                patch.object(lifecycle,'policy_document',return_value=self.packet):
            release=c.prepare_component_release(self.plan_path,self.master_path,self.wave_path,self.task['name'],
                request_path,self.root/'config.json',destination)
            verified=lifecycle.verify_release(destination)
        self.assertEqual(verified,release);self.assertEqual(release['purpose'],'CACHED_NORMAL_COMPONENT')
        self.assertEqual(release['source_hashes'],lifecycle.a.executed_sources('CACHED_NORMAL_COMPONENT'))
        self.assertTrue((destination/'job.sh').is_file());self.assertIn('srun',(destination/'job.sh').read_text())
        claim=c.lifecycle_reserve(release,destination,config)
        self.assertEqual(claim['task'],self.task['name'])
        self.assertEqual(claim['reserved_CPU_seconds'],release['resources']['cpu_seconds'])

    def test_changed_cache_manifest_is_rejected(self):
        config={'remote_root':'/mnt/beegfs/home/jaguir26/r157'};manifest=self.write('manifest.json',{})
        receipt={'schema':'r157_hb_shared_prefix_cache_v1','status':'VERIFIED_SHARED_PREFIX_CACHE',
            'plan':c.pin(self.plan_path),'config_sha256':r.identity(config),'cache_manifest':c.pin(manifest),
            'remote_root':config['remote_root']+'/prefix-cache-'+r.digest(self.plan_path)[:32],
            'remote_manifest_sha256':r.digest(manifest)}
        path=self.write('receipt.json',receipt);r.write(manifest,{'changed':True})
        with self.assertRaises(ValueError):c.validate_cache_receipt(path,self.plan_path,config)


if __name__=='__main__':unittest.main()
