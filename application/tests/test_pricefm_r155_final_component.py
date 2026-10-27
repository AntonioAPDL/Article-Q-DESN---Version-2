"""Final-scope metadata/kernel tests; no model, campaign helper or forecasts."""
import importlib.util
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch,Mock
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_final_contract as c
import pricefm_r155_final_inventory as inventory
import pricefm_r155_metadata_waiter as waiter
for name in c.THREAD_ENV:os.environ[name]='1'


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


old=module('final_inherited_tests',Path(__file__).with_name('test_pricefm_r155_ee_completion.py'))
old.c=c;old.base.c=c
runner=module('final_test_entry',HERE/'528_run_pricefm_stage_r155_final_component.py')


class TestFinalAuthority(old.TestCompletionAuthority):
    def setUp(self):
        super().setUp();self.prep['remaining_component_names']=['onlyB3']
        scopes=[]
        for i,charge in enumerate((10961.212634375985,2692.2750262410004)):
            e=self.root/f'old_exit{i}.json';s=self.root/f'old_super{i}.json'
            c.immutable(e,dict(status='INCOMPLETE'))
            dead=dict(pid=987650+i,start_ticks=1,boot_id='fixture')
            c.immutable(s,dict(child_exit_code=1,all_inclusive_charged_CPU_seconds=charge,parent=dead,payload=dead))
            scopes.append(dict(exit=c.pin(e),supervisor_exit=c.pin(s),conservative_CPU_charge=charge))
        self.prep['previous_paid_scope']=dict(schema='r155_paid_scope_chain_v1',scopes=scopes,refund_authorized=False)
        role=self.root/'role.json';c.immutable(role,dict(schema='r155_legacy_490_metadata_role_v1',status='ADMITTED_EXACT_EXISTING_METADATA_ROLE'))
        self.prep['legacy_metadata_role']=c.pin(role)
        self.pp.write_text(json.dumps(self.prep))
        drain=self.root/'predecessor.json';c.immutable(drain,dict(status='PASS',exact_lifetimes_gone=True,same_global_flock_free=True))
        helper=c.pin(HERE/'pricefm_r155_metadata_waiter.py');review=self.root/'role_review.json'
        c.immutable(review,dict(status='PASS_PRIVATE_FIXTURE',helper=helper,role=c.pin(role)))
        self.a.update(schema='r155_final_authority_v1',max_new_tasks=1,preparation=c.pin(self.pp),
            previous_paid_scope=self.prep['previous_paid_scope'],predecessor_drain_proof=c.pin(drain),
            legacy_metadata_role=c.pin(role),legacy_metadata_role_helper=helper,legacy_metadata_role_review=c.pin(review),
            unit='pricefm-r155-ee-final-fresh.service',require_RemainAfterExit=True,
            output_dir=str(self.root/'pricefm_stage_r155_final_component_fresh'))
        runtime=self.root/'runtime_review.json'
        c.immutable(runtime,dict(status='PASS_PRIVATE_RUNTIME_FIXTURE',source=self.identity,numerical_runtime_review=True))
        self.a['source_review']=c.pin(runtime)

    def test_rejects_task_expansion_old_charge_credit_lock_replacement_and_no_LV_gate(self):
        for key,value in (('max_new_tasks',2),('previous_paid_scope',{}),('require_RemainAfterExit',False),
                ('original_global_lock_identity',{'device':2304,'inode':99}),('requires_completed_LV_drain',False)):
            a=dict(self.a);a[key]=value
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.validate(a)

    def test_admitted_metadata_role_and_review_are_mandatory(self):
        path=Path(self.a['legacy_metadata_role']['path']);role=c.read(path);role['status']='PROPOSED';path.write_text(json.dumps(role))
        a=dict(self.a,legacy_metadata_role=c.pin(path))
        with self.assertRaises(RuntimeError):self.validate(a)

    def test_preparation_only_or_other_source_review_cannot_admit_numerics(self):
        for source,numerical in ((self.identity,False),({'head':'other'},True)):
            path=self.root/'runtime_review.json';path.write_text(json.dumps(dict(status='PASS_CONDITIONAL_PREPARATION_ONLY',source=source,numerical_runtime_review=numerical)))
            with self.assertRaises(RuntimeError):self.validate(dict(self.a,source_review=c.pin(path)))


class TestOriginalPeerRules(old.base.TestPeerAndLifetime):
    test_foreign_argv_not_retained_in_conflict=None


class TestGuardian(old.base.TestDisposableGuardianPrivate):
    def script(self,root,mode):
        return super().script(root,mode).replace('import pricefm_r154_prediction_contract as c','import pricefm_r155_final_contract as c')


class TestFinalMetadata(unittest.TestCase):
    def test_frozen_whole_B3_and_retained_geometry_without_arrays(self):
        prep=c.read(inventory.OLD_PREP);task=next(t for t in prep['tasks'] if t['name']==inventory.MISSING[0])
        chunks=inventory.chunks(task)
        self.assertEqual(len(chunks),88);self.assertEqual(sum(len(d['origin_positions']) for d in chunks[:15]),120)
        self.assertEqual(sum(len(d['origin_positions']) for d in chunks[15:]),572)
        self.assertEqual(572+len(chunks[0]['origin_positions']),580)
        self.assertEqual(len(inventory.MISSING),1)

    def test_guardian_check_close_and_original_detection_are_unchanged(self):
        import ast
        def functions(path):return {n.name:ast.dump(n,include_attributes=False) for n in ast.walk(ast.parse(path.read_text())) if isinstance(n,ast.FunctionDef)}
        before=functions(HERE/'pricefm_r155_completion_contract.py');after=functions(HERE/'pricefm_r155_final_contract.py')
        for name in ('_start_guardian','check','close','observe','reserve','signal_unreaped_direct_child','peer_conflicts','admin_match'):
            self.assertEqual(before[name],after[name],name)

    def test_public_math_call_signatures_are_unchanged(self):
        import ast
        def calls(path,name):return [ast.dump(n,include_attributes=False) for n in ast.walk(ast.parse(path.read_text()))
            if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and isinstance(n.func.value,ast.Name)
            and n.func.value.id=='public' and n.func.attr==name]
        for name in ('predict','numerical_context','retained_arrays'):
            self.assertEqual(calls(HERE/'524_run_pricefm_stage_r155_ee_completion.py',name),calls(HERE/'528_run_pricefm_stage_r155_final_component.py',name))

    def test_only_positive_exact_role_filters_unknown_conflict_and_retains_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            lease=c.Lease.__new__(c.Lease);lease.out=Path(d);lease.a={'cpu':30,'physical_sibling_cpus':[30,62],
                'legacy_metadata_role_helper':{'path':'privatefixture','sha256':'a'*64}}
            lease.census={'allowed_intersecting_processes':[]};lease.admin_rules={'rules':[]}
            role=['python','-B','exact490','wait','--poll-seconds','300'];lease.metadata_role={'argv_exact':role}
            lease.metadata_role_pin={'path':'rolefixture','sha256':'b'*64};lease.metadata_role_cache={}
            lease.metadata_matcher=Mock();lease.metadata_matcher.observe_legacy_490.return_value={'observed':True}
            lease.metadata_matcher.match_legacy_490.return_value=True
            def row(pid,argv):return dict(pid=pid,start_ticks=pid,boot_id='fixture',cmdline_sha256=str(pid),
                state='S',comm='python',command=' '.join(argv),argv=argv,cpus=[30])
            permitted=row(1,role);unknown=row(2,['python','new_model.py'])
            with patch.object(c,'all_processes',return_value=[permitted,unknown]):
                with self.assertRaises(RuntimeError):lease.scan_peers('fixture',set())
            self.assertEqual(len(list((lease.out/'accepted_metadata_roles').glob('*.json'))),1)
            rejection=c.read(next((lease.out/'peer_rejections').glob('*.json')))
            self.assertEqual([r['pid'] for r in rejection['conflicts']],[2])
            self.assertTrue(rejection['new_reviewed_metadata_role_policy'])
            self.assertTrue(next(iter(lease.metadata_role_cache.values()))['positive_match'])
            with patch.object(c,'all_processes',return_value=[permitted]):lease.scan_peers('fixture',set())
            self.assertEqual(len(list((lease.out/'accepted_metadata_roles').glob('*.json'))),1)
            lease.metadata_matcher.match_legacy_490.return_value=False
            with patch.object(c,'all_processes',return_value=[permitted]),self.assertRaises(RuntimeError):lease.scan_peers('fixture',set())

    def test_stdlib_import_and_inspect_do_not_import_numerics(self):
        import subprocess
        code="import sys,importlib.util;sys.path.insert(0,sys.argv[1]);import pricefm_r155_final_contract,pricefm_r155_final_inventory;assert 'numpy' not in sys.modules"
        subprocess.run([sys.executable,'-B','-c',code,str(HERE)],check=True)


class TestCanonicalMetadataWaiterRole(unittest.TestCase):
    def fixture(self):
      rule=json.loads((inventory.R155/'review/legacy_490_waiter_audit_03/LEGACY_490_ROLE_PROPOSAL_01.json').read_text())
      process=dict(boot_id='boot',pid=123,start_ticks=456,cmdline_sha256='command',argv=rule['argv_exact'])
      current=dict(process,state='S',ppid=rule['parent']['pid'],uid=[rule['owner_uid']]*4,cwd=rule['cwd_exact'],
       executable=rule['resolved_executable'],threads=[dict(tid=123,cpus=rule['thread_mask_exact'])])
      parent={k:rule['parent'][k] for k in ('pid','start_ticks','boot_id','cmdline_sha256','executable')};parent['uid']=[rule['parent']['uid']]*4
      contract=rule['unit'];unit=dict(Id=contract['Id'],LoadState='loaded',ActiveState='active',SubState='running',
       MainPID='123',ExecMainPID='123',WorkingDirectory=contract['WorkingDirectory'],FragmentPath=contract['FragmentPath'],
       Restart=contract['Restart'],KillMode=contract['KillMode'],InvocationID='exact',
       ExecStart='{ path='+rule['interpreter']['path']+' ; argv[]='+' '.join(rule['argv_exact'])+' ; ignore_errors=no ; pid=123 ; status=0/0 }')
      pins=[rule['script'],rule['interpreter'],rule['parent']['executable_pin'],contract['fragment_pin'],*rule['configuration_pins']]
      observation=dict(observed=True,candidate_lifetime=list(waiter.lifetime(process)),current=current,closing_identity=dict(current),
       parent=parent,environment=rule['expected_thread_environment'].copy(),environment_absent={k:True for k in rule['environment_must_be_absent']},
       hashes={p['path']:p['sha256'] for p in pins},source=rule['source'].copy(),unit=unit,unit_by_PID=contract['Id'],unit_proof_epoch=1.)
      return process,rule,observation
    def test_exact_role_and_new_verified_lifetime_positive(self):
      process,rule,obs=self.fixture();self.assertTrue(waiter.match_legacy_490(process,rule,obs))
      process['pid']=124;obs['candidate_lifetime']=list(waiter.lifetime(process))
      for key in ('current','closing_identity'):obs[key]['pid']=124
      obs['current']['threads']=[dict(tid=124,cpus=rule['thread_mask_exact'])]
      obs['unit']['MainPID']=obs['unit']['ExecMainPID']='124'
      self.assertTrue(waiter.match_legacy_490(process,rule,obs))
    def test_all_narrow_role_negative_boundaries(self):
      mutations=[lambda p,r,o:o.update(observed=False),lambda p,r,o:o['source'].update(clean=False),
       lambda p,r,o:o['source'].update(head='other'),lambda p,r,o:o['hashes'].update({r['script']['path']:'other'}),
       lambda p,r,o:o['hashes'].update({r['configuration_pins'][0]['path']:'other'}),
       lambda p,r,o:o['hashes'].update({r['interpreter']['path']:'other'}),lambda p,r,o:o['current'].update(cwd='other'),
       lambda p,r,o:p.update(argv=[*p['argv'],'--extra']),lambda p,r,o:o['current'].update(argv=[*r['argv_exact'][:3],'controller']),
       lambda p,r,o:o['unit'].update(Id='other'),lambda p,r,o:o['unit'].update(MainPID='other'),
       lambda p,r,o:o['unit'].update(ExecMainPID='other'),lambda p,r,o:o['unit'].update(ExecStart=o['unit']['ExecStart'].replace(' 300',' 301')),
       lambda p,r,o:o['parent'].update(start_ticks=0),lambda p,r,o:o['parent'].update(boot_id='other'),
       lambda p,r,o:o['parent'].update(uid=[0]*4),lambda p,r,o:o['parent'].update(executable='other'),
       lambda p,r,o:o['current']['threads'].append(dict(tid=125,cpus=r['thread_mask_exact'])),
       lambda p,r,o:o['current']['threads'][0].update(cpus=[31]),lambda p,r,o:o['environment'].update(OMP_NUM_THREADS='2'),
       lambda p,r,o:o['environment_absent'].update(PYTHONPATH=False),lambda p,r,o:o.update(unit_by_PID='other'),
       lambda p,r,o:o['unit'].update(InvocationID=''),lambda p,r,o:r.update(expires_epoch=1),
       lambda p,r,o:o['closing_identity'].update(start_ticks=0)]
      for i,mutate in enumerate(mutations):
       with self.subTest(case=i):
        process,rule,obs=self.fixture();mutate(process,rule,obs);self.assertFalse(waiter.match_legacy_490(process,rule,obs))
    def test_missing_observation_fails_closed_and_irrelevant_peers_do_not_probe(self):
      process,rule,obs=self.fixture()
      with patch.object(waiter,'_static',side_effect=AssertionError('unrelated peer must not probe')):
       other=dict(process,argv=['python','unrelated.py']);self.assertFalse(waiter.observe_legacy_490(other,rule)['observed'])
      with patch.object(waiter,'_static',return_value={}),patch.object(waiter,'_identity',side_effect=FileNotFoundError()):
       failed=waiter.observe_legacy_490(process,rule);self.assertFalse(waiter.match_legacy_490(process,rule,failed))
    def test_cached_lifetime_still_rechecks_environment_and_new_pid_needs_unit(self):
      process,rule,obs=self.fixture();prior=copy.deepcopy(obs);prior['positive_match']=True
      current=copy.deepcopy(obs['current']);current['_environment']=rule['expected_thread_environment'].copy()
      static=dict(hashes=obs['hashes'],source=obs['source'])
      with patch.object(waiter,'_static',return_value=static),patch.object(waiter,'_identity',side_effect=[current,obs['parent'],obs['closing_identity']]),patch.object(waiter,'_command',side_effect=AssertionError('cached DBus must not run')):
       observed=waiter.observe_legacy_490(process,rule,prior)
      self.assertTrue(observed['cache_used']);self.assertTrue(waiter.match_legacy_490(process,rule,observed))
      current=copy.deepcopy(obs['current']);current['_environment']=dict(rule['expected_thread_environment'],OMP_NUM_THREADS='2')
      with patch.object(waiter,'_static',return_value=static),patch.object(waiter,'_identity',side_effect=[current,obs['parent'],obs['closing_identity']]):
       changed=waiter.observe_legacy_490(process,rule,prior)
      self.assertFalse(waiter.match_legacy_490(process,rule,changed))
      current=copy.deepcopy(obs['current']);current['_environment']=rule['expected_thread_environment'].copy()
      newer=dict(process,pid=124);current['pid']=124
      with patch.object(waiter,'_static',return_value=static),patch.object(waiter,'_identity',side_effect=[current,obs['parent']]),patch.object(waiter,'_command',side_effect=RuntimeError('new PID needs new unit attribution')):
       unverified=waiter.observe_legacy_490(newer,rule,prior)
      self.assertFalse(unverified['observed']);self.assertFalse(waiter.match_legacy_490(newer,rule,unverified))


if __name__=='__main__':unittest.main()
