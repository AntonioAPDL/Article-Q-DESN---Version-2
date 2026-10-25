"""Resource/identity regression tests; no posterior fits or runtime services."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ENTRY = Path(__file__).resolve().parents[1] / 'scripts/pricefm/513_supervise_pricefm_stage_r153_baseline.py'
spec = importlib.util.spec_from_file_location('test_r153_explicit_owner', ENTRY)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
    return path


def file(path, text='fixture'):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def snapshot(pid, argv, cwd, cpus, parent=11, start=None, session=11):
    return dict(pid=pid, start_ticks=pid if start is None else start, boot_id='boot',
                argv=argv, cmdline_sha256=hashlib.sha256(b'\0'.join(a.encode() for a in argv) + b'\0').hexdigest(),
                cwd=str(cwd), cpus=list(cpus), session_id=session, state='R',
                uid=os.getuid(), uids=[os.getuid()] * 4, ppid=parent, age_seconds=10,
                cgroups=['/user.slice/user-' + str(os.getuid()) + '.slice/user@' + str(os.getuid()) + '.service/model.service'])


class FakeSystem:
    def __init__(self, processes):
        self.values = {p['pid']: copy.deepcopy(p) for p in processes}
        self.actions = []

    def process(self, pid):
        return copy.deepcopy(self.values.get(pid))

    def processes(self):
        return copy.deepcopy(list(self.values.values()))

    def cpu_seconds(self, pid, start):
        self.actions.append(('cpu', pid, start))
        return 2.


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='pricefm-r153-owner-probe-')
        self.root = Path(self.tmp.name)
        data = self.root / 'data'; data.mkdir()
        dep = self.root / 'dep'; science = self.root / 'science'
        self.normal = file(dep / 'application/scripts/pricefm' / m.NORMAL)
        self.al = file(science / 'application/scripts/pricefm' / m.AL)
        self.controller = file(science / 'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py')
        package = self.root / 'package'; self.package_file = file(package / 'R/fit.R')
        rscript = file(self.root / 'R/bin/Rscript')
        self.native = file(self.root / 'R/lib64/R/bin/exec/R')
        self.config = dict(data=str(data), dependency_worktree=str(dep), source_worktree=str(science),
                           source_controller=str(self.controller), python_runtime='/python', source_tag='probe',
                           source_head='a' * 40, source_branch='work/probe', source_sha256={})
        self.campaign = data / 'campaigns/probe__PROBE'
        self.name = 'rhs_PROBE_example'
        self.task = dict(name=self.name, region='PROBE', kind='rhs', tau0=.001)
        write(self.campaign / 'tasks' / (self.name + '.json'), self.task)
        self.contract_path = self.campaign / 'contracts' / (self.name + '.json')
        self.sources = {str(p):m.digest(p) for p in [self.normal, self.al, self.controller, self.package_file]}
        self.prep = dict(source={'head':'a'*40, 'branch':'work/probe'}, dependency=str(dep), source_sha256=self.sources,
                         control=dict(rscript=str(rscript), normal_runtime=str(package)),
                         template=dict(package_path=str(package)), protocol=dict(normal_max_iter=2000, al_max_iter=300))
        self.prep_path = write(data / 'launch_prep/probe__PROBE/preparation.json', self.prep)
        self.contract = dict(tag='probe__PROBE', output_dir=str(self.campaign / 'tasks_done' / self.name / 'fit'),
                             package_path=str(package), max_iter=2000, tau0=.001,
                             source_sha256={str(p):m.digest(p) for p in [self.normal, self.package_file]})
        write(self.contract_path, self.contract)
        self.parent = snapshot(11, ['/python','-B',str(self.controller),'controller','--region','PROBE'], self.root, [0,1], parent=1)
        self.worker = snapshot(12, ['/python','-B',str(self.controller),'worker','--region','PROBE','--name',self.name,'--cpu','0'], self.root, [0])
        self.child = snapshot(13, [str(self.native),'--no-echo','--no-restore','--file='+str(self.normal),'--args','--contract',str(self.contract_path)], self.root, [0], parent=12)
        self.job = dict(region='PROBE', process=self.parent, pid=11, cpus=[0,1], session_id=11,
                        observed_children=[copy.deepcopy(self.worker), copy.deepcopy(self.child)])
        self.system = FakeSystem([self.parent, self.worker, self.child])
        self.policy = m.ContractPolicy(self.config, self.system, private_namespace=self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def peers(self, child=None, worker=None):
        return {p['pid']:p for p in [self.parent, worker or self.worker, child or self.child]}

    def production_fixture(self, al=False):
        """A complete pinned producer contract, still without numerical work."""
        p=dict(normal_max_iter=2000,normal_min_iter=100,al_max_iter=300,al_tol=1e-5,
               al_n_samp=20,max_rhs_iter=20000,forecast_seed=7,
               certificate_limits={'beta_posterior_sd_rms':1e-4},
               regions=['PROBE'],tag='probe',maximum_workers_per_region=15)
        global_path=write(Path(self.config['source_worktree'])/'application/config/probe.json',p)
        self.config['source_sha256'][str(global_path)]=m.digest(global_path)
        self.prep['protocol']=dict(p,regions=['PROBE'],tag='probe__PROBE',maximum_workers=15)
        def prerequisite(name,relative):
            task=write(self.campaign/'tasks'/(name+'.json'),dict(name=name,region='PROBE',kind='fixture'))
            terminal=write(self.campaign/'tasks_done'/name/relative,dict(status='fixture'))
            write(self.campaign/'tasks_done'/name/'completed_evidence.json',dict(
                artifacts={relative:m.digest(terminal)},metadata=dict(
                    certified=True,source_head=self.config['source_head'],task_sha256=m.digest(task))))
        if al:
            name='PROBE_fold1_al0.75'
            task=dict(name=name,region='PROBE',kind='al',tau=.75,tau0=.001,fold=1,candidate_id='candidate',
                      design_name='PROBE_design',parent_name='PROBE_parent',parent_type='quantile')
            prerequisite(task['design_name'],'design/terminal.json')
            prerequisite(task['parent_name'],'fit/terminal.json')
            adapter=file(Path(self.config['dependency_worktree'])/'application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R')
            fixed=file(Path(self.config['source_worktree'])/'application/R/pricefm_r129_al_fixedpoint_certificate.R')
            manifest=file(self.root/'cran/manifest.json')
            self.prep['control'].update(cran_library=str(self.root/'cran'),cran_manifest=str(manifest))
            self.prep['source_sha256'].update({str(q):m.digest(q) for q in [adapter,fixed,manifest]})
            script=self.al
        else:
            name=self.name
            task=dict(self.task,candidate_id='candidate',split=1,stats_name='stats_PROBE_candidate')
            prerequisite(task['stats_name'],'stats/terminal.json')
            helper=file(Path(self.config['dependency_worktree'])/'application/R/pricefm_recursive_normal_fit.R')
            package=Path(self.contract['package_path'])
            priors=[file(package/'R'/name) for name in ['priors_beta.R','qdesn_rhs_ns_prior.R']]
            self.prep['source_sha256'].update({str(q):m.digest(q) for q in [helper,*priors]})
            self.prep['template'].update(tol=1e-5,stability_window=10,covariance_tol=1e-6,
                                         initial_fit_path=None,initial_fit_sha256=None)
            script=self.normal
        write(self.campaign/'tasks'/(name+'.json'),task)
        write(self.prep_path,self.prep)
        policy=m.ContractPolicy(self.config,self.system)
        prep=policy.preparation('PROBE')
        contract=policy.expected_contract(prep,task,self.job)
        path=write(self.campaign/'contracts'/(name+'.json'),contract)
        child=dict(self.child,argv=[str(self.native),'--no-echo','--no-restore','--file='+str(script),
                                    '--args','--config' if al else '--contract',str(path)])
        return policy,task,contract,path,child

    def seal_failure(self,task,contract_path,normal=False):
        if normal:
            terminal=dict(status='R123_SUCCESSOR_UNCERTIFIED',iterations=2000,termination_reason='iteration_cap',
                          full_variational_certified=False,test_opened=False,official_validation_opened=False,
                          initialization_only=True)
        else:
            terminal=dict(finite_core=True,iterations=300,computationally_certified=False,
                          termination='iteration_cap_uncertified',test_opened=False)
        terminal.update(contract_path=str(contract_path),contract_sha256=m.digest(contract_path))
        target=write(self.campaign/'tasks_done'/task['name']/'fit/terminal.json',terminal)
        task_path=self.campaign/'tasks'/(task['name']+'.json')
        write(target.parent.parent/'completed_evidence.json',dict(
            artifacts={'fit/terminal.json':m.digest(target)},metadata=dict(certified=False,
                source_head=self.config['source_head'],task_sha256=m.digest(task_path))))

    def test_exact_normal_package_transition_and_restoration_preserve_observation(self):
        moved = dict(self.child, cwd=self.contract['package_path'])
        before = copy.deepcopy(moved)
        self.assertTrue(self.policy.same_owned_child(moved, self.child, self.job, self.peers(moved)))
        self.assertEqual(moved, before)
        self.assertTrue(self.policy.same_owned_child(self.child, moved, self.job, self.peers()))
        self.assertEqual(len(self.policy.events), 2)
        self.assertEqual(self.policy.events[0]['actual_cwd'], self.contract['package_path'])

    def test_rscript_to_native_R_role_is_exact(self):
        initial = snapshot(13, [self.prep['control']['rscript'],str(self.normal),'--contract',str(self.contract_path)], self.root, [0], parent=12)
        self.assertTrue(self.policy.same_owned_child(self.child, initial, self.job, self.peers()))

    def test_different_directory_rejected(self):
        elsewhere = self.root / 'other'; elsewhere.mkdir()
        with self.assertRaisesRegex(RuntimeError, 'working directory'):
            self.policy.r_role(dict(self.child, cwd=str(elsewhere)), self.job)

    def test_native_R_cannot_add_another_file_or_eval_flag(self):
        for extra in [['--file=/other.R'], ['--eval','system("anything")'], ['--config',str(self.contract_path)]]:
            with self.subTest(extra=extra), self.assertRaises(RuntimeError):
                self.policy.r_role(dict(self.child, argv=self.child['argv'] + extra), self.job)

    def test_wrong_same_named_script_path_rejected(self):
        other = file(self.root / 'other' / m.NORMAL)
        bad = [str(self.native),'--no-echo','--no-restore','--file='+str(other),'--args','--contract',str(self.contract_path)]
        with self.assertRaisesRegex(RuntimeError, 'script path'):
            self.policy.r_role(dict(self.child, argv=bad), self.job)

    def test_contract_output_tag_parameter_and_cap_changes_rejected(self):
        for key,value in [('output_dir','/other'), ('tag','other'), ('tau0',.002), ('max_iter',2001), ('package_path',str(self.root))]:
            with self.subTest(key=key):
                write(self.contract_path, dict(self.contract, **{key:value}))
                with self.assertRaises(RuntimeError):self.policy.r_role(self.child, self.job)
        write(self.contract_path, self.contract)

    def test_preparation_literal_caps_cannot_be_mutually_raised(self):
        write(self.prep_path, dict(self.prep, protocol=dict(normal_max_iter=2001, al_max_iter=300)))
        write(self.contract_path, dict(self.contract, max_iter=2001))
        with self.assertRaisesRegex(RuntimeError, 'caps'):
            self.policy.r_role(self.child, self.job)

    def test_role_source_tamper_rejected(self):
        self.policy.r_role(self.child, self.job)
        self.package_file.write_text('changed')
        with self.assertRaises(RuntimeError):self.policy.r_role(self.child, self.job)

    def test_registered_contract_cannot_change_a_nonrole_field(self):
        self.policy.r_role(self.child, self.job)
        write(self.contract_path, dict(self.contract, unexpected=True))
        with self.assertRaisesRegex(RuntimeError, 'registered scientific contract changed'):
            self.policy.r_role(self.child, self.job)

    def test_symlinked_contract_rejected(self):
        self.contract_path.unlink(); target = write(self.root / 'elsewhere.json', self.contract)
        self.contract_path.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'noncanonical'):
            self.policy.r_role(self.child, self.job)

    def test_lifetime_changes_are_not_a_role_exception(self):
        for key,value in [('pid',14), ('start_ticks',14), ('boot_id','other')]:
            with self.subTest(key=key):self.assertFalse(self.policy.same_owned_child(dict(self.child,**{key:value}),self.child,self.job,self.peers()))

    def test_UID_session_cgroup_and_CPU_changes_fail_closed(self):
        cases=[('uid',os.getuid()+1), ('uids',[os.getuid()+1]*4), ('session_id',99), ('cgroups',['/elsewhere']), ('cpus',[2])]
        for key,value in cases:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                self.policy.same_owned_child(dict(self.child,**{key:value}),self.child,self.job,self.peers())

    def test_R_must_belong_to_exact_worker_task_and_CPU(self):
        with self.assertRaisesRegex(RuntimeError, 'worker parent'):
            self.policy.classify(dict(self.child,ppid=99),self.job,self.peers())
        with self.assertRaisesRegex(RuntimeError, 'exact worker CPU'):
            self.policy.classify(dict(self.child,cpus=[1]),self.job,self.peers())

    def test_worker_bootstrap_is_bounded_and_cannot_regress_after_pin(self):
        startup = dict(self.worker,cpus=[0,1],age_seconds=1)
        role = self.policy.classify(startup,self.job,self.peers(worker=startup))
        self.assertTrue(role['bootstrap'])
        self.assertFalse(self.policy.same_owned_child(startup,self.worker,self.job,self.peers(worker=startup)))
        with self.assertRaises(RuntimeError):self.policy.classify(dict(startup,age_seconds=121),self.job,self.peers(worker=startup))
        with self.assertRaisesRegex(RuntimeError,'before its worker CPU pin'):
            self.policy.classify(self.child,self.job,self.peers(worker=startup))

    def test_controller_identity_stays_exact(self):
        with self.assertRaisesRegex(RuntimeError,'controller lifetime'):
            self.policy.classify(dict(self.parent,cwd=self.contract['package_path']),self.job,self.peers())

    def test_unclassified_live_session_child_rejected(self):
        stranger=snapshot(14,['python','unreviewed.py'],self.root,[0],parent=11)
        self.system.values[14]=stranger
        with self.assertRaisesRegex(RuntimeError,'unclassified'):
            m.session_members(copy.deepcopy(self.job),self.system,self.policy)

    def test_new_valid_child_is_classified_before_retention(self):
        job=dict(self.job,observed_children=[])
        rows=m.session_members(job,self.system,self.policy)
        self.assertEqual({p['pid'] for p in rows},{11,12,13})
        self.assertEqual({p['pid'] for p in job['observed_children']},{12,13})

    def test_new_orphan_lifetime_cannot_be_adopted(self):
        self.system.values.pop(11)
        job=dict(self.job,observed_children=[])
        with self.assertRaisesRegex(RuntimeError,'unobserved orphan'):
            m.session_members(job,self.system,self.policy)

    def test_fresh_positive_exit_proof_overrides_earlier_same_cycle_census(self):
        census=self.system.processes()
        self.system.values.clear()
        self.assertEqual(m.session_members(copy.deepcopy(self.job),self.system,self.policy,census=census),[])

    def test_fresh_root_affinity_read_is_not_hidden_by_shared_census(self):
        census=self.system.processes()
        self.system.values[11]['cpus']=[0,1,2]
        with self.assertRaisesRegex(RuntimeError,'CPU differs'):
            m.session_members(copy.deepcopy(self.job),self.system,self.policy,census=census)

    def test_frozen_read_only_git_and_lscpu_roles(self):
        git=snapshot(14,['git','rev-parse','HEAD'],self.config['source_worktree'],[0],parent=12)
        self.assertEqual(self.policy.classify(git,self.job,self.peers())['kind'],'source_check_git')
        topology=snapshot(15,['lscpu','-p=CPU,CORE,SOCKET'],self.root,[0,1],parent=11)
        self.assertEqual(self.policy.classify(topology,self.job,self.peers())['kind'],'source_check_lscpu')
        with self.assertRaises(RuntimeError):self.policy.classify(dict(git,argv=['git','reset','--hard']),self.job,self.peers())

    def test_exact_AL_contract_is_strict_about_cwd(self):
        name='PROBE_fold1_al0.75'
        task=dict(name=name,region='PROBE',kind='al',tau=.75,tau0=.001,fold=1)
        write(self.campaign/'tasks'/(name+'.json'),task)
        adapter=file(Path(self.config['dependency_worktree'])/'adapter.R')
        fixed=file(Path(self.config['source_worktree'])/'fixedpoint.R')
        manifest=file(self.root/'cran/manifest.json')
        prep=copy.deepcopy(self.prep);prep['control'].update(cran_library=str(self.root/'cran'),cran_manifest=str(manifest))
        prep['source_sha256'].update({str(p):m.digest(p) for p in [adapter,fixed,manifest]})
        write(self.prep_path,prep)
        contract=dict(tag='probe__PROBE',output_dir=str(self.campaign/'tasks_done'/name/'fit'),
                      family='al',stage='R137',test_opened=False,max_iter=300,tau=.75,tau0=.001,fold=1,
                      cran_library=str(self.root/'cran'),cran_manifest=str(manifest),cran_manifest_sha256=m.digest(manifest),
                      cran_adapter=str(adapter),cran_adapter_sha256=m.digest(adapter),
                      fixedpoint_helper=str(fixed),fixedpoint_helper_sha256=m.digest(fixed))
        path=write(self.campaign/'contracts'/(name+'.json'),contract)
        process=dict(self.child,argv=[str(self.native),'--no-echo','--no-restore','--file='+str(self.al),'--args','--config',str(path)])
        self.assertEqual(self.policy.r_role(process,self.job)['kind'],'AL_R')
        with self.assertRaisesRegex(RuntimeError,'working directory'):
            self.policy.r_role(dict(process,cwd=self.contract['package_path']),self.job)

    def test_full_Normal_producer_contract_matches_without_importing_model(self):
        policy,task,contract,path,child=self.production_fixture()
        self.assertEqual(policy.r_role(child,self.job)['kind'],'normal_R')
        self.assertEqual(contract['min_iter'],100)

    def test_Normal_first_observation_rejects_limits_data_parent_and_target_changes(self):
        policy,task,contract,path,child=self.production_fixture()
        for key,value in [('tol',1.),('min_iter',1),('covariance_tol',1.),('initial_fit_path','/other'),
                          ('stats_dir',str(self.root)),('stats_terminal_sha256','0'*64),
                          ('posterior_target_sha256','other'),('unknown_new_key',True)]:
            with self.subTest(key=key):
                write(path,dict(contract,**{key:value}))
                fresh=m.ContractPolicy(self.config,self.system)
                with self.assertRaisesRegex(RuntimeError,'exact frozen producer'):
                    fresh.r_role(child,self.job)

    def test_AL_first_observation_rejects_limits_sampling_design_parent_and_target_changes(self):
        policy,task,contract,path,child=self.production_fixture(al=True)
        self.assertEqual(policy.r_role(child,self.job)['kind'],'AL_R')
        for key,value in [('certificate_limits',{'beta_posterior_sd_rms':1.}),('tol',1.),('n_samp',2),
                          ('n_samp_xi',2),('max_rhs_iter',30000),('design_dir',str(self.root)),
                          ('parent_dir',str(self.root)),('parent_type','other'),('seed',123),
                          ('parent_terminal_sha256','0'*64),('posterior_target_sha256','other')]:
            with self.subTest(key=key):
                write(path,dict(contract,**{key:value}))
                fresh=m.ContractPolicy(self.config,self.system)
                with self.assertRaisesRegex(RuntimeError,'exact frozen producer'):
                    fresh.r_role(child,self.job)

    def test_AL_target_uses_exact_frozen_17_digit_tau0_format(self):
        policy,task,contract,path,child=self.production_fixture(al=True)
        for tau0 in [.1,.2]:
            task['tau0']=tau0;write(self.campaign/'tasks'/(task['name']+'.json'),task)
            expected=policy.expected_contract(self.prep,task,self.job)
            self.assertTrue(expected['posterior_target_sha256'].endswith(':tau0='+format(tau0,'.17g')))
            self.assertNotEqual(format(tau0,'.17g'),str(tau0))
            write(path,dict(expected,posterior_target_sha256=expected['posterior_target_sha256'].rsplit(':tau0=',1)[0]+':tau0='+str(tau0)))
            with self.assertRaisesRegex(RuntimeError,'exact frozen producer'):
                m.ContractPolicy(self.config,self.system).r_role(child,self.job)

    def test_preparation_content_cache_is_rechecked_in_each_new_observation(self):
        m.session_members(copy.deepcopy(self.job),self.system,self.policy)
        write(self.prep_path,dict(self.prep,unexpected='changed'))
        with self.assertRaisesRegex(RuntimeError,'registered scientific preparation changed'):
            m.session_members(copy.deepcopy(self.job),self.system,self.policy)

    def test_typed_failure_collection_retains_RHS_exclusion_then_AL_blocker(self):
        _,rhs,_,rhs_path,_=self.production_fixture()
        self.seal_failure(rhs,rhs_path,normal=True)
        _,al,_,al_path,_=self.production_fixture(al=True)
        self.seal_failure(al,al_path)
        details={};result=m.failed_certificates(self.config,'PROBE',details)
        self.assertEqual([r['task'] for r in result],[al['name']])
        self.assertEqual([r['task'] for r in details['preserved_RHS_screening_exclusions']],[rhs['name']])

    def test_typed_failure_collection_rejects_nonfinite_AL_or_changed_source(self):
        _,task,_,path,_=self.production_fixture(al=True)
        self.seal_failure(task,path)
        terminal=self.campaign/'tasks_done'/task['name']/'fit/terminal.json'
        value=m.read(terminal);value['finite_core']=False;write(terminal,value)
        seal=terminal.parent.parent/'completed_evidence.json';s=m.read(seal);s['artifacts']['fit/terminal.json']=m.digest(terminal);write(seal,s)
        with self.assertRaisesRegex(RuntimeError,'finite original-cap'):
            m.failed_certificates(self.config,'PROBE')

    def test_private_constructor_cannot_relax_production_namespace(self):
        outside=tempfile.TemporaryDirectory()
        try:
            with self.assertRaisesRegex(RuntimeError,'declared root'):
                m.ContractPolicy(dict(self.config,data=outside.name),self.system,private_namespace=self.root)
        finally:outside.cleanup()

    def test_required_Normal_full_cap_failure_is_a_typed_blocker(self):
        policy,task,contract,path,child=self.production_fixture()
        task=dict(task,kind='normal_full',fold=1,design_name=task['stats_name'])
        write(self.campaign/'tasks'/(task['name']+'.json'),task)
        self.seal_failure(task,path,normal=True)
        result=m.failed_certificates(self.config,'PROBE')
        self.assertEqual([r['kind'] for r in result],['normal_full'])


class MetadataExitTests(unittest.TestCase):
    def sample(self,state='R',ppid=1):
        return dict(pid=10,start_ticks=20,state=state,ppid=ppid,session_id=10,process_group=10)

    def test_exit_between_base_snapshot_and_UID_read_has_positive_terminal_proof(self):
        system=m.System.__new__(m.System);system.boot_id='boot'
        value=dict(pid=10,start_ticks=20,session_id=10)
        with patch.object(m.adapter().RecoverySystem,'process',return_value=value), \
             patch.object(system,'stat_sample',side_effect=[self.sample(),self.sample('Z')]), \
             patch.object(Path,'read_text',side_effect=FileNotFoundError('exit')):
            self.assertIsNone(system.process(10))

    def test_live_protected_UID_read_is_not_omitted(self):
        system=m.System.__new__(m.System);system.boot_id='boot'
        value=dict(pid=10,start_ticks=20,session_id=10)
        with patch.object(m.adapter().RecoverySystem,'process',return_value=value), \
             patch.object(system,'stat_sample',return_value=self.sample()), \
             patch.object(Path,'read_text',side_effect=PermissionError('protected')) as call, \
             patch.object(m.time,'sleep'):
            with self.assertRaises(PermissionError):system.process(10)
            self.assertEqual(call.call_count,3)

    def test_live_parent_transition_is_reread_without_falsifying_parent(self):
        system=m.System.__new__(m.System);system.boot_id='boot'
        value=dict(pid=10,start_ticks=20,session_id=10)
        text='Uid:\t'+'\t'.join([str(os.getuid())]*4)+'\n'
        with patch.object(m.adapter().RecoverySystem,'process',return_value=value), \
             patch.object(system,'stat_sample',side_effect=[self.sample(ppid=3),self.sample(ppid=1),self.sample(ppid=1),self.sample(ppid=1)]), \
             patch.object(Path,'read_text',return_value=text),patch.object(m.time,'sleep'):
            self.assertEqual(system.process(10)['ppid'],1)


class ControlTests(unittest.TestCase):
    def authority(self,root):
        return dict(schema_version=1,authority_id='a'*32,runtime=str(root/'new'),legacy_baseline_runtime=str(root/'old'),
                    activation=dict(legacy_generations_spent=3,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=4),
                    grant=dict(starts_epoch=100,expires_epoch=604900,wall_seconds=604800,control_CPU_seconds=28800,prior_control_CPU_seconds=7),
                    frozen_cached_sha256={'a':'b'},frozen_legacy_sha256={'c':'d'},poll_seconds=20,source_verify_seconds=60,guardian_lease_seconds=180)

    def test_single_explicit_activation_and_old_spent_chain_are_literal(self):
        a=self.authority(Path('/tmp/example'))
        m.validate_authority_shape(a)
        for changed in [dict(a['activation'],activation_limit=2),dict(a['activation'],legacy_generations_spent=2),dict(a['activation'],cumulative_owner_count=3)]:
            with self.assertRaises(RuntimeError):m.validate_authority_shape(dict(a,activation=changed))
        with self.assertRaises(RuntimeError):m.validate_authority_shape(dict(a,runtime=a['legacy_baseline_runtime']))

    def test_control_CPU_excludes_numerical_cgroup_and_children(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);a=self.authority(root);runtime=Path(a['runtime']);runtime.mkdir()
            write(runtime/'guardian_heartbeat.json',dict(control_CPU_seconds=3))
            system=FakeSystem([]);state=dict(owner=dict(pid=1,start_ticks=2),heavy_source_checks=2)
            result=m.budget(a,state,system,now=101)
            self.assertEqual(result['cumulative_control_charged_CPU_seconds'],18.)
            self.assertEqual(system.actions,[('cpu',1,2)])
            self.assertFalse(result['numerical_CPU_included']);self.assertFalse(result['cgroup_CPU_used'])
            self.assertFalse(m.budget(a,state,system,now=604901)['within_wall'])

    def test_natural_B_return_records_only_in_new_runtime(self):
        config={'partition':{'baseline_A':list(range(15))}}
        with patch.object(m.core(),'cached_drained',return_value=True),patch.object(m.core(),'record_loan_return') as record:
            self.assertEqual(m.choose_cpus(config,'B','/new','/legacy',{},object()),list(range(15,30)))
            self.assertEqual(record.call_args.args[0],'/new')
        with patch.object(m.core(),'cached_drained',return_value=False):
            with self.assertRaises(RuntimeError):m.choose_cpus(config,'B','/new','/legacy',{},object())

    def test_systemd_runtime_parsing_is_finite(self):
        for value in ['1w','7d','604800s','604800000000']:
            self.assertEqual(m.runtime_seconds(value),604800)
        for value in ['infinity','','unlimited','1w garbage']:
            with self.assertRaises(RuntimeError):m.runtime_seconds(value)

    def test_guardian_loss_stops_dispatch_without_restart_or_model_signals(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);a=self.authority(root);a.update(guardian_unit='guard',launch_attestation_path=str(root/'attest.json'))
            runtime=Path(a['runtime']);runtime.mkdir();path=write(root/'authority.json',a)
            write(runtime/'state.json',dict(phase='running'))
            current=dict(pid=os.getpid(),start_ticks=1)
            system=FakeSystem([])
            def capsule(authority,attestation,mode,api):
                if mode=='guard':return current,{}
                raise RuntimeError('owner disappeared')
            with patch.object(m,'control_capsule',side_effect=capsule):
                result=m.guard_once(path,'guard',system,now=101,authority=a,attestation={'epoch':100})
            self.assertEqual(result,'blocked')
            receipt=m.read(runtime/'guardian_blocked.json')
            self.assertEqual(receipt['owner_restart_attempts'],0);self.assertEqual(receipt['numerical_worker_signals'],0)
            self.assertEqual(system.actions,[('cpu',os.getpid(),1)])

    def test_first_epoch_publication_gap_waits_only_with_bounded_positive_owner_proof(self):
        for phase,now,expected in [('adopted_ready',110,'wait'),('adopted_ready',131,'blocked'),('running',110,'blocked')]:
            with self.subTest(phase=phase,now=now),tempfile.TemporaryDirectory() as name:
                root=Path(name);a=self.authority(root);a.update(guardian_unit='guard',launch_attestation_path=str(root/'attest.json'))
                runtime=Path(a['runtime']);runtime.mkdir();path=write(root/'authority.json',a)
                owner=dict(pid=100,start_ticks=2,boot_id='b',cmdline_sha256='a',cwd='/root')
                guardian=dict(pid=os.getpid(),start_ticks=3)
                write(runtime/'state.json',dict(phase=phase,owner=owner,activation=a['activation'],authority_sha256=m.digest(path)))
                system=FakeSystem([])
                with patch.object(m,'control_capsule',side_effect=lambda aa,at,mode,ss: (guardian if mode=='guard' else owner,{})):
                    result=m.guard_once(path,'guard',system,now=now,authority=a,attestation={'epoch':100})
                self.assertEqual(result,expected)
                self.assertEqual((runtime/'guardian_blocked.json').exists(),expected=='blocked')

    def test_completed_tail_observation_does_not_require_an_active_finished_owner(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);a=self.authority(root);a.update(new_unit='owner',legacy_config_path='/config')
            runtime=Path(a['runtime']);runtime.mkdir();path=write(root/'authority.json',a)
            state=dict(phase='complete',completed={'A':['R'],'B':[]},quarantined={'A':[],'B':[]},active={})
            write(runtime/'state.json',state)
            write(runtime/'terminal.json',dict(status='R153_NINE_ORIGINAL_TAILS_DRAINED_NOT_GLOBAL_PROMOTION',
                activation=a['activation'],numerical_source_head='science',completed=state['completed'],quarantined=state['quarantined']))
            a['execution_source']={'head':'new'}
            system=FakeSystem([]);system.unit=lambda unit:dict(ActiveState='inactive',MainPID='0')
            with patch.object(m,'_validate',return_value=a),patch.object(m,'frozen_context'), \
                 patch.object(m.core(),'read_config',return_value=dict(source_head='science',queues={'A':['R'],'B':[]})), \
                 patch.object(m.core(),'complete_region',return_value=True):
                result=m.inspect_owner(path,system)
            self.assertTrue(result['healthy']);self.assertTrue(result['tail_finished']);self.assertFalse(result['owner_live'])


if __name__=='__main__':
    unittest.main()
