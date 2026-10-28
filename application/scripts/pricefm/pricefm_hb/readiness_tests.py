"""Readiness helper tests: only metadata fixtures and mocked host observations."""
from __future__ import annotations
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest import mock
from . import readiness as q
from . import cost_control_tests as wire


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.w=wire.CostControlTests(methodName='runTest');self.w.setUp();self.addCleanup(self.w.doCleanups)
        self.root=self.w.root;self.plan=self.w.plan;self.output=self.root/'refresh'
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(q.os,'sched_getaffinity',return_value={31}).start()
        self.limit=mock.patch.object(q.resource,'setrlimit').start()
        mock.patch.object(q.Budget,'used_cpu',return_value=.2).start()
        mock.patch.object(q.cost,'load_plan',return_value=self.plan).start()
        parity=self.root/'parity-publication/outputs';(parity/'TEST/parity').mkdir(parents=True)
        for pin,target in ((self.w.request['parity_seal'],parity/'TEST/parity/completed_evidence.json'),
                           (self.w.request['parity_runtime_result'],parity/'environment-runtime.json')):
            shutil.copyfile(pin['path'],target)
        self.assessment=q.cost.pinned(self.w.ee['scientific_assessment'])
        seal_pin=self.w.write('EE-assessment-seal.json',{'assessment':self.w.ee['scientific_assessment']})
        self.ee={'complete_components':12,'required_components':12,'remaining_components':0,
                 'scientifically_complete_and_physically_drained':True,'same_original_flock_free':True,
                 'phase':'COMPLETED_RETAINED_UNIT_FULL_MATCHED_SET_DRAINED','epoch':wire.NOW,
                 'actual_unit':{'MainPID':'0','ActiveState':'active','SubState':'exited','Result':'success'},
                 'processes':[{'role':'guardian.json','live_exact_lifetime':False},{'role':'payload_identity.json','live_exact_lifetime':False}],
                 'records':{'assessment.json':{'pin':self.w.ee['scientific_assessment'],'value':self.assessment},
                            'assessment_seal.json':{'pin':seal_pin,'value':q.cost.pinned(seal_pin)}}}
        sizing=self.w.write('sizing.json',dict(study='FI',plan_sha256=self.w.plan_pin['sha256'],memory_mib=4096,
                                               minimum_required_memory_mib=1024,maximum_parent_p=2))
        calendar=self.w.write('calendar.json',dict(study='FI',plan_sha256=self.w.plan_pin['sha256'],created_epoch=wire.NOW,
            expires_epoch=wire.NOW+7200,status='PROPOSED_FINITE_COST_WINDOW_NOT_AUTHORITY',authority_issued=False,claim_created=False))
        self.config={'schema':q.SCHEMA,'site_config':str(self.w.config_path),'runtime_publication':str(self.root/'runtime'),
            'parity_publication':str(parity.parent),'adapter_reviews':{'FI':self.w.request['adapter_review']},
            'delivered_EE_report':self.w.ee['delivered_report'],'sizing_evidence':{'FI':sizing},'calendar_evidence':{'FI':calendar},
            'legacy_registries':[{'host':q.cost.OWNER,'path':'/known/closed.json'},
                                 {'host':'jerez.be.ucsc.edu','path':'/known/closed.json'}],
            'legacy_outputs':{'FI':'/known/FI-descriptors'}}
        self.config_path=self.root/'operator.json';q.r.write(self.config_path,self.config)
        def qualification(path,prefix):
            return {key:self.w.request[key] for key in (prefix+'_result',prefix+'_qualification_seal',prefix+'_accounting')}
        mock.patch.object(q,'qualification',side_effect=qualification).start()
        self.run=mock.patch.object(q,'run',side_effect=lambda *a,**k:json.dumps(self.ee)).start()
        self.snapshots={}
        for host in (q.cost.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'):
            self.snapshots[host]={'host':host,'observed_epoch':wire.NOW,'matching_processes':[],
                'unreadable_own_processes':[],'registries':([] if host=='hb.ucsc.edu' else [
                    {'path':'/known/closed.json','present':True,'value':{'status':'CLOSED','active':[]}}])}
        self.snapshots[q.cost.OWNER]['registries'].append({'path':str(q.cost.CENTRAL/'cost_only_registry.json'),'present':False})
        self.snapshots['hb.ucsc.edu'].update(free_disk_bytes=3*1024**3,slurm={'queue':'',
            'node':'NodeName=node-07 RealMemory=120000 AllocMem=1000 FreeMem=90000 CPUTot=24 CPUEfctv=24 CPUAlloc=2 State=MIXED Partitions=128x24',
            'partition':'PartitionName=128x24 State=UP MaxTime=7-00:00:00'})
        self.real_observe=q.observe
        self.observe=mock.patch.object(q,'observe',side_effect=lambda host,*a:self.snapshots[host]).start()

    def refresh(self):return q.refresh(self.w.plan_pin['path'],self.config_path,self.output)

    def test_positive_refresh_emits_valid_request_without_claim_authority_or_network_mutation(self):
        result=self.refresh();self.assertEqual(result['status'],'READY_FOR_PREPARE_ONLY_NOT_ADMITTED',result)
        request=q.cost.pinned(result['request']);q.cost.validate_gates(request,self.plan,self.w.plan_pin['sha256'],wire.NOW)
        self.assertEqual(result['claims_created'],0);self.assertEqual(result['jobs_submitted'],0)
        self.assertFalse((q.cost.CENTRAL/'cost_only_registry.json').exists())
        self.assertEqual(self.run.call_args.args[0],q.EE_COMMAND);self.assertIn('--inspect',self.run.call_args.args[0])
        self.w.external.assert_not_called();self.w.remote.assert_not_called();self.w.transfer.assert_not_called()

    def test_partial_EE_is_blocked_without_launch_request(self):
        self.ee.update(complete_components=11,remaining_components=1,scientifically_complete_and_physically_drained=False)
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertFalse((self.output/'launch-request.json').exists())
        self.observe.assert_not_called()

    def test_operational_EE_disposition_never_normalizes_to_cost_readiness(self):
        self.assessment['disposition']='STOP_OPERATIONAL_FAILURE'
        path=Path(self.w.ee['scientific_assessment']['path']);q.r.write(path,self.assessment)
        self.ee['records']['assessment.json']['pin']=q.cost.pin(path)
        self.ee['records']['assessment_seal.json']['value']['assessment']=q.cost.pin(path)
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED')

    def test_unknown_or_matching_processes_block_but_unrelated_baseline_is_not_rejected(self):
        self.snapshots['jerez.be.ucsc.edu']['matching_processes']=[{'pid':123,'argv':['python','FI-worker']}]
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('pid123',result['reason'])

    def test_unreadable_own_process_blocks_honestly(self):
        self.snapshots[q.cost.OWNER]['unreadable_own_processes']=[{'pid':456,'error':'PermissionError'}]
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('unreadable_pid456',result['reason'])

    def test_active_cost_registry_and_unknown_legacy_registry_block(self):
        self.snapshots[q.cost.OWNER]['registries'][0]={'path':'/known/closed.json','present':True,'value':{'claims':{'x':{'state':'SUBMITTED'}}}}
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED')

    def test_missing_legacy_path_is_never_called_closed(self):
        self.snapshots[q.cost.OWNER]['registries'][0]={'path':'/known/closed.json','present':False}
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('UNKNOWN_MISSING',result['reason'])

    def test_unknown_document_shape_is_blocked(self):
        self.snapshots[q.cost.OWNER]['registries'][0]['value']={'expires_epoch':wire.NOW-100}
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('terminal state',result['reason'])

    def test_busy_queue_or_drain_node_or_low_resources_cannot_emit_positive_request(self):
        self.snapshots['hb.ucsc.edu']['slurm']['queue']='123|other-job|RUNNING|node-07\n'
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED')

    def test_insufficient_measured_memory_is_rejected_by_final_gate(self):
        self.snapshots['hb.ucsc.edu']['slurm']['node']=self.snapshots['hb.ucsc.edu']['slurm']['node'].replace('FreeMem=90000','FreeMem=100')
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED')

    def test_stale_calendar_or_tampered_review_never_emit_request(self):
        proof=q.cost.pinned(self.config['calendar_evidence']['FI']);proof['created_epoch']=wire.NOW-301
        self.config['calendar_evidence']['FI']=self.w.write('stale-calendar.json',proof);q.r.write(self.config_path,self.config)
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('calendar',result['reason'])

    def test_observer_failure_retains_blocked_evidence_and_no_retry(self):
        self.run.side_effect=subprocess.TimeoutExpired('source529 --inspect',8)
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertEqual(self.run.call_count,1)
        self.assertTrue((self.output/'readiness-result.json').exists());self.assertFalse((self.output/'launch-request.json').exists())

    def test_refresh_and_window_publications_are_create_only(self):
        self.output.mkdir()
        with self.assertRaises(FileExistsError):self.refresh()
        self.run.assert_not_called()

    def test_new_window_preserves_old_files_and_issues_only_a_unique_proposal(self):
        before=self.config_path.read_bytes();proposal=self.root/'new-window.json';config=self.root/'new-operator.json'
        result=q.new_window(self.w.plan_pin['path'],self.config_path,proposal,config)
        value=q.cost.pinned(result['proposal']);self.assertEqual(value['expires_epoch']-value['created_epoch'],7200)
        self.assertFalse(value['authority_issued']);self.assertFalse(value['claim_created']);self.assertTrue(value['proposal_id'])
        self.assertEqual(self.config_path.read_bytes(),before);self.assertFalse((q.cost.CENTRAL/'cost_only_registry.json').exists())
        self.assertEqual(q.metadata(config)['calendar_evidence']['FI'],result['proposal'])
        with self.assertRaises(FileExistsError):q.new_window(self.w.plan_pin['path'],self.config_path,proposal,config)
        self.run.assert_not_called();self.observe.assert_not_called()

    def test_new_window_cannot_reset_spent_or_active_cost_scope(self):
        registry=q.cost.CENTRAL/'cost_only_registry.json'
        for state in ({'schema':q.cost.SCHEMA,'owner':q.cost.OWNER,'spent_regions':{'FI':'old'},'claims':{}},
                      {'schema':q.cost.SCHEMA,'owner':q.cost.OWNER,'spent_regions':{},'claims':{'x':{'state':'AMBIGUOUS'}}}):
            q.r.write(registry,state)
            with self.assertRaises(q.Blocked):q.new_window(self.w.plan_pin['path'],self.config_path,self.root/'proposal.json',self.root/'new-config.json')
            self.assertEqual(q.metadata(registry),state)
        self.assertFalse((self.root/'proposal.json').exists())

    def test_new_window_rejects_oversized_or_incomplete_calendar(self):
        for seconds in (0,1259,7201,True):
            with self.subTest(seconds=seconds),self.assertRaises(q.Blocked):
                q.new_window(self.w.plan_pin['path'],self.config_path,self.root/'proposal.json',self.root/'new-config.json',seconds)

    def test_slurm_parser_and_budget_fail_closed(self):
        self.assertEqual(q.duration('1-01:02:03'),90123)
        self.assertEqual(q.fields('NodeName=node-07 FreeMem=100')['FreeMem'],'100')
        budget=q.Budget()
        with mock.patch.object(budget,'used_cpu',return_value=10):
            with self.assertRaises(q.Blocked):budget.check()

    def test_exact_legacy_closure_requires_the_recorded_publisher_lifetime_gone(self):
        value={'path':'/known/development_closed.json','present':True,'value':{
            'future_admissions_closed':True,'cleanup_verified':True,'scope_id':'old-r152',
            'master_sha256':'a'*64,'terminal_sha256':'b'*64},
            'recorded_lifetimes':[{'pid':123,'same_exact_lifetime':False}]}
        self.assertEqual(q.registry_overlaps(value,'FI:key'),[])
        value['recorded_lifetimes'][0]['same_exact_lifetime']=True
        self.assertTrue(q.registry_overlaps(value,'FI:key'))

    def test_foreign_canonical_registry_identity_never_normalizes_to_no_overlap(self):
        self.snapshots[q.cost.OWNER]['registries'][1].update(present=True,value={'schema':'foreign','owner':'other','claims':{}})
        result=self.refresh();self.assertEqual(result['status'],'BLOCKED');self.assertIn('canonical cost registry',result['reason'])

    def test_remote_observer_uses_strict_key_and_read_only_bounded_stdin_script(self):
        snapshot=dict(self.snapshots['hb.ucsc.edu'],host='rit-prd-clusterlogin-2.ucsc.edu',CPU_seconds=.02)
        self.run.side_effect=lambda *a,**k:json.dumps(snapshot)
        observed=self.real_observe('hb.ucsc.edu',{'exclusion_key':'FI:key','slurm':True,'disk_path':'/mnt/beegfs/home/jaguir26/test'},self.w.config,q.Budget())
        self.assertEqual(observed['host'],'rit-prd-clusterlogin-2.ucsc.edu')
        argv=self.run.call_args.args[0];self.assertIn('BatchMode=yes',argv);self.assertIn('PasswordAuthentication=no',argv)
        self.assertIn('timeout 38s /usr/bin/python3 -B -',argv[-1])
        script=self.run.call_args.kwargs['stdin']
        self.assertNotIn('sbatch',script);self.assertNotIn('rsync',script);self.assertNotIn('mkdir',script)

    def test_finite_refresh_timer_is_disarmed_before_return(self):
        self.assertEqual(self.refresh()['status'],'READY_FOR_PREPARE_ONLY_NOT_ADMITTED')
        self.assertEqual(q.signal.getitimer(q.signal.ITIMER_REAL),(0.0,0.0))

    def test_guard_stopped_legacy_scope_is_closed_ownership_not_scientific_success(self):
        value={'path':'/known/terminal.json','present':True,'value':{'status':'R152_GUARD_STOPPED',
            'cleanup_verified':True,'fanout_stop':True,'cleanup_errors':[],'owned_pids':[],
            'scope_id':'old-r152','master_sha256':'a'*64,'final_control_charge_sha256':'b'*64}}
        self.assertEqual(q.registry_overlaps(value,'FI:key'),[])
        value['value']['cleanup_errors']=['unreaped child']
        with self.assertRaises(q.Blocked):q.registry_overlaps(value,'FI:key')

    def never_admitted_fixture(self):
        config=self.w.write('legacy-config.json',{'tag':'canonical-fi-fixture'})
        plan=dict(self.plan,canonical_config=config)
        path=q.cost.p.DATA/'campaigns/canonical-fi-fixture'
        audit={'status':'PASS_CLOSED_CACHED_SCOPE_PRESERVED','errors':[],
               'master':{'sha256':'a'*64,'scope_id':'old-scope'},'attempts':[{'task':'EE_only'}],
               'closed_scope':{'baseline_only':True,'cached_restart_authorized':False,'manifest_mismatches':[],
                   'actual_drain':{'master_sha256':'a'*64,'scope_id':'old-scope','cleanup_verified':True,'owned_pids':[],
                                   'cleanup':[{'drained':True,'pids':[]} for _ in range(8)]}}}
        terminal={'path':'/known/terminal.json','sha256':'b'*64,'value':{'status':'R152_GUARD_STOPPED',
            'study_dispositions':{'FI':None,'DK2':None},'cleanup_verified':True,'fanout_stop':True,
            'cleanup_errors':[],'owned_pids':[],'master_sha256':'a'*64,'scope_id':'old-scope'}}
        snapshots={q.cost.OWNER:{'registries':[terminal]}}
        return plan,path,audit,snapshots,{'/known/terminal.json':'b'*64}

    def test_missing_exact_descriptor_needs_pinned_never_admitted_terminal_and_all_eight_drains(self):
        plan,path,audit,snapshots,hashes=self.never_admitted_fixture()
        proof=q.never_admitted_absence('FI',str(path),plan,snapshots,audit,hashes)
        self.assertEqual(proof['status'],'ABSENT_CANONICAL_DESCRIPTOR_STUDY_NEVER_ADMITTED')
        self.assertEqual(proof['terminal']['sha256'],'b'*64)
        for changed in (str(path)+'-arbitrary', '/tmp/missing'):
            with self.subTest(path=changed),self.assertRaises(q.Blocked):
                q.never_admitted_absence('FI',changed,plan,snapshots,audit,hashes)

    def test_missing_descriptor_never_passes_with_prior_FI_admission_or_partial_drain(self):
        plan,path,audit,snapshots,hashes=self.never_admitted_fixture()
        for mode in ('admitted','task','partial','hash'):
            aa=copy.deepcopy(audit);ss=copy.deepcopy(snapshots);hh=dict(hashes)
            if mode=='admitted':ss[q.cost.OWNER]['registries'][0]['value']['study_dispositions']['FI']={'admitted':True}
            if mode=='task':aa['attempts']=[{'task':'FI_previous_science'}]
            if mode=='partial':aa['closed_scope']['actual_drain']['cleanup'].pop()
            if mode=='hash':hh['/known/terminal.json']='c'*64
            with self.subTest(mode=mode),self.assertRaises(q.Blocked):
                q.never_admitted_absence('FI',str(path),plan,ss,aa,hh)


if __name__=='__main__':unittest.main()
