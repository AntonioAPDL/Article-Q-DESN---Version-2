"""Corruption, scope and non-dispatch tests for the frozen science verifier."""
from pathlib import Path
from copy import deepcopy
from contextlib import redirect_stderr, redirect_stdout
import ast
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from unittest.mock import patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/517_verify_pricefm_stage_r153_science_preparation.py'
spec=importlib.util.spec_from_file_location('r153_science_verifier_test',ENTRY)
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
REAL_BUNDLE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r153_control_and_diagnostics_20261025/science')


def payload_fixture():
    limits=deepcopy(v.LIMITS);raw_regions={'AT':{'targets':[]},'LT':{'targets':[]}};no3=[];rows=[]
    for region,count in [('AT',4),('LT',1),('NO_3',2)]:
        for i in range(count):
            name=f'{region}_{i}';task=dict(name=name,region=region,kind='al' if region=='LT' else 'internal_al')
            measures=dict(limits);measures['beta_posterior_sd_rms']*=2
            checks={key:measures[key]<=limit for key,limit in limits.items()}
            terminal=dict(iterations=300,computationally_certified=False,full_fit_object_retained=False,
                exact_optimizer_resumption_supported=False,posterior_target_sha256=name,n=10,p=3,tau=.75,tau0=.01)
            contract=dict(max_iter=300,prior_center_from_initializer=False,posterior_target_sha256=name,
                certificate_limits=deepcopy(limits),seed=7)
            target=dict(name=name,task=task,contract=contract,terminal=terminal,contract_sha256='c'*64,
                certificate=dict(certified=False,measures=measures,limits=deepcopy(limits),checks=checks),
                retained_files={'fixedpoint_certificate.json':{'sha256':'e'*64}})
            (no3 if region=='NO_3' else raw_regions[region]['targets']).append(target)
            rows.append(dict(name=name,region=region,task=deepcopy(task),contract_sha256='c'*64,
                certificate_sha256='e'*64,parent_certified=True,iteration_cap=300,resume_supported=False,
                fit_admitted=False,initialization_changes_prior=False,posterior_target_sha256=name,
                n=10,p=3,tau=.75,tau0=.01,seed=7,failed_checks=['beta_posterior_sd_rms'],
                all_limit_ratios={key:measures[key]/limit for key,limit in limits.items()}))
    status=dict(blocking_AL_targets=7,target_counts={'AT':4,'LT':1,'NO_3':2})
    dossier=dict(status='PREPARED_VERIFIED_NO_REPAIR_FIT_ADMITTED',numerical_caps={'AL':300,'Normal':2000},
        historical_600_cap_proposals_selected=False,target_counts=deepcopy(status['target_counts']),
        failed_returned_targets=rows,blocked_unsealed_dependants={'AT':15,'LT':10,'NO_3':4},
        failed_targets_added_to_unsealed_count=False)
    choice=dict(candidate_id='r134_fixture',tau0=.01,specification_sha256='f'*64)
    remote=dict(protocol=dict(paths=500,al_max_iter=300,normal_max_iter=2000,quantiles=v.LEVELS,
        clock_offsets_steps=[0,24,48,72],forecast_seed=11),frozen_choice=choice,
        bank_expected_sha256={'/bank.npz':'b'*64},preparation_sha256='a'*64,
        packet_evidence=[{} for _ in range(32)],folds=[dict(origins=n) for n in [120,123,122]])
    groups=[];calls=[]
    for split in [1,2,3]:
        al_names={str(q):f'iq_LV_s{split}_al{q:.2f}' for q in v.LEVELS}
        task=dict(name=f'iq_LV_s{split}_score',kind='internal_score',region='LV',candidate_id=choice['candidate_id'],
            tau0=.01,split=split,rhs_name=f'rhs_s{split}',al_names=al_names)
        parents={name:{'seal_sha256':'p'*64} for name in [task['rhs_name'],*al_names.values()]}
        group=dict(task=task,task_sha256='t'*64,parents=parents,design_terminal_sha256='d'*64,scaler_sha256='s'*64)
        groups.append(group)
        lo,hi=[(506,631),(631,766),(766,940)][split-1]
        origins=[lo+round(i*(hi-lo-2)/11) for i in range(12)]
        base=v.stable_seed(11,'LV',choice['candidate_id'],.01,split)
        for clock in [0,24,48,72]:
            calls.append(dict(id=f's{split}_c{clock}',split=split,clock_offset_steps=clock,
                source_score_task=task['name'],source_score_task_sha256='t'*64,
                origin_indices=list(origins),original_origin_clock_positions=[i*96+clock for i in origins],
                call_seed=v.stable_seed(base,'quantile_clock',clock),parent_seals=deepcopy(parents),
                design_terminal_sha256='d'*64,scaler_sha256='s'*64))
    remote['prospective_training_groups']=groups
    training=dict(status='FROZEN_PROPOSAL_NOT_ADMITTED',dispatch_authorized=False,admission=None,
        candidate_nomination_authorized=False,promotion_authorized=False,new_fits=0,
        official_origins_used=0,official_scores_mutated=0,max_forecast_calls=12,origin_clock_pairs=144,
        horizon_steps=96,posterior_paths=500,quantiles=v.LEVELS,
        pricing_gate=dict(status='NOT_PRICED_NOT_FUNDED',CPU_allowance=None,wall_allowance=None),
        region='LV',**choice,expected_training_bank_sha256=remote['bank_expected_sha256'],
        preparation_sha256=remote['preparation_sha256'],operators_generated_by_same_call=[
            'mean_feature','path_specific','normal_driver','rearranged_path_mean','cdf_pool_clipped','cdf_pool_linear'],
        call_manifest=calls)
    saved=dict(model_fit_calls=0,forecast_calls=0,official_outputs_changed=0,packet_payloads_verified=32,official_origins_verified=365)
    return {'SCIENCE_PREPARATION_STATUS.json':status,'CERTIFICATE_REPAIR_DOSSIER.json':dossier,
        'LOCAL_TARGET_INPUTS.json':dict(regions=raw_regions),
        'JEREZ_SAVED_EVIDENCE.json':dict(NO3=dict(targets=no3),LV=remote),
        'LV_TRAINING_DIAGNOSTIC_MANIFEST.json':training,'LV_CALIBRATION_DOSSIER.json':saved}


def cache_fixture():
    packets=[dict(path=f'/checkpoint/{i}',sha256=hashlib.sha256(str(i).encode()).hexdigest()) for i in range(225)]
    units=[f'u{i}' for i in range(8)]
    drain=dict(cleanup_verified=True,owned_pids=[],owned_units=units,
        cleanup=[dict(unit=u,drained=True,pids=[]) for u in units])
    cache=dict(status='PASS_CLOSED_CACHED_SCOPE_PRESERVED',errors=[],read_only=True,
        closed_scope=dict(manifest_files=75,current_manifest={str(i):'f'*64 for i in range(75)},
            manifest_mismatches=[],EE_C1_spent=True,EE_C2_exists=False,cached_restart_authorized=False,actual_drain=drain),
        master=dict(scope_id=v.SCOPE_ID,sha256=v.MASTER_SHA256,start_epoch=v.T0,expires_epoch=v.EXPIRY,duration_seconds=43200),
        checkpoints=dict(retained_and_validated=225,seal_sha256={r['path']:r['sha256'] for r in packets},strict_new_full_components=0),
        attempts=[dict(validated_checkpoint_packets=packets[i::6]) for i in range(6)],
        charges=dict(EE_cumulative_scientific_CPU_seconds=v.EE_SCIENCE,cached_control_final_CPU_seconds=v.CACHED_CONTROL))
    proposal=dict(status='EE_REUSE_PROPOSAL_PREPARED_NOT_ADMITTED',closed_scope_restart_authorized=False,
        new_allocation=None,new_fits=0,new_forecasts=0,new_admissions=0,old_C1='spent',old_C2='unclaimed_but_closed',
        checkpoint_packets=225,imported_strict_D=20,remaining_D=58,new_S0_max=6,
        new_full_components_initial_max=64,new_full_components_all_max=82,original_scope_id=v.SCOPE_ID,
        original_expiry_epoch=v.EXPIRY,full_cache_verification=cache,
        carried_ledger=dict(EE_science_reserved_CPU_seconds=v.EE_SCIENCE,
            cached_control_closed_CPU_seconds=v.CACHED_CONTROL,all_failed_probe_and_attempt_debits_retained=True,
            later_baseline_control_ledger_kept_separate=True))
    return {'EE_CARRY_FORWARD_READINESS.json':proposal}


class ArtifactBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.manifest=dict(status='SEALED_SCIENCE_AUDIT_AND_PROTOCOL_PREPARATION',file_count=19,files={})
        for name in v.EXPECTED_FILES:
            data=('fixture:'+name).encode();(self.root/name).write_bytes(data)
            self.manifest['files'][name]=dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
    def test_complete_regular_inventory_passes(self):v._verify_artifacts(self.root,self.manifest)
    def test_unpinned_manifest_rejected(self):
        (self.root/'artifact_manifest.json').write_text('{}')
        with self.assertRaisesRegex(RuntimeError,'committed pinned identity'):v.verify_bundle(self.root)
    def test_mutated_file_rejected(self):
        path=self.root/'CERTIFICATE_REPAIR_DOSSIER.json';data=path.read_bytes();path.write_bytes(b'X'+data[1:])
        with self.assertRaisesRegex(RuntimeError,'hash differs'):v._verify_artifacts(self.root,self.manifest)
    def test_extra_unsealed_payload_rejected(self):
        (self.root/'run_forecast.py').write_text('raise SystemExit')
        with self.assertRaisesRegex(RuntimeError,'unsealed or missing'):v._verify_artifacts(self.root,self.manifest)
    def test_missing_file_rejected(self):
        (self.root/'VALIDATION_RECEIPT.json').unlink()
        with self.assertRaises(RuntimeError):v._verify_artifacts(self.root,self.manifest)
    def test_symlink_payload_rejected(self):
        name='LOCAL_TARGET_INPUTS.json';(self.root/name).unlink();(self.root/name).symlink_to(self.root/'JEREZ_SAVED_EVIDENCE.json')
        with self.assertRaisesRegex(RuntimeError,'symlink'):v._verify_artifacts(self.root,self.manifest)
    def test_unsafe_paths_rejected(self):
        for name in ['','.', '..','../escape','/absolute','a/../b','a//b','a\\b']:
            with self.subTest(name=name),self.assertRaises(RuntimeError):v._safe_relative(name)
    def test_relative_bundle_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'absolute'):v.verify_bundle(Path('relative'))
    def test_no_dispatch_cli(self):
        with patch('sys.argv',['verify','--bundle',str(self.root),'--run']),redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as e:v.main()
        self.assertEqual(e.exception.code,2)


class ScientificScopeTests(unittest.TestCase):
    def setUp(self):self.p=payload_fixture()
    def test_seven_frozen_blockers_validate(self):v._validate_blockers(self.p)
    def test_larger_cap_rejected(self):
        self.p['CERTIFICATE_REPAIR_DOSSIER.json']['numerical_caps']['AL']=600
        with self.assertRaisesRegex(RuntimeError,'caps differ'):v._validate_blockers(self.p)
    def test_certified_string_cannot_override_failed_boolean(self):
        raw=self.p['LOCAL_TARGET_INPUTS.json']['regions']['AT']['targets'][0]
        raw['terminal']['status']='completed_r137_certified_al_fit';raw['terminal']['computationally_certified']=True
        with self.assertRaisesRegex(RuntimeError,'relabelled'):v._validate_blockers(self.p)
    def test_resume_claim_rejected(self):
        self.p['CERTIFICATE_REPAIR_DOSSIER.json']['failed_returned_targets'][0]['resume_supported']=True
        with self.assertRaisesRegex(RuntimeError,'resumption'):v._validate_blockers(self.p)
    def test_prior_change_rejected(self):
        self.p['LOCAL_TARGET_INPUTS.json']['regions']['AT']['targets'][0]['contract']['prior_center_from_initializer']=True
        with self.assertRaisesRegex(RuntimeError,'prior'):v._validate_blockers(self.p)
    def test_misreported_ratio_rejected(self):
        self.p['CERTIFICATE_REPAIR_DOSSIER.json']['failed_returned_targets'][0]['all_limit_ratios']['beta_posterior_sd_rms']=.5
        with self.assertRaisesRegex(RuntimeError,'ratio'):v._validate_blockers(self.p)
    def test_screening_exclusion_is_not_a_repair_target(self):
        self.p['LOCAL_TARGET_INPUTS.json']['regions']['AT']['targets'][0]['task']['kind']='rhs'
        with self.assertRaises(RuntimeError):v._validate_blockers(self.p)
    def test_incomplete_target_census_rejected(self):
        self.p['CERTIFICATE_REPAIR_DOSSIER.json']['failed_returned_targets'].pop()
        with self.assertRaisesRegex(RuntimeError,'identity list'):v._validate_blockers(self.p)
    def test_unadmitted_inner_training_protocol_validates(self):v._validate_training(self.p)
    def test_implicit_dispatch_rejected(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['dispatch_authorized']=True
        with self.assertRaisesRegex(RuntimeError,'unadmitted'):v._validate_training(self.p)
    def test_unpriced_CPU_grant_rejected(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['pricing_gate']['CPU_allowance']=3600
        with self.assertRaisesRegex(RuntimeError,'resource allocation'):v._validate_training(self.p)
    def test_extra_call_rejected(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['call_manifest'].append(deepcopy(self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['call_manifest'][0]))
        with self.assertRaisesRegex(RuntimeError,'calls duplicated'):v._validate_training(self.p)
    def test_official_cohort_rejected(self):
        self.p['JEREZ_SAVED_EVIDENCE.json']['LV']['prospective_training_groups'][0]['task']['name']='LV_fold1_score'
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['call_manifest'][0]['source_score_task']='LV_fold1_score'
        with self.assertRaisesRegex(RuntimeError,'official or wrong'):v._validate_training(self.p)
    def test_origin_replacement_rejected(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['call_manifest'][0]['origin_indices'][0]=0
        with self.assertRaisesRegex(RuntimeError,'cohort differs'):v._validate_training(self.p)
    def test_seed_replacement_rejected(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['call_manifest'][0]['call_seed']+=1
        with self.assertRaisesRegex(RuntimeError,'RNG'):v._validate_training(self.p)
    def test_parent_omission_rejected(self):
        self.p['JEREZ_SAVED_EVIDENCE.json']['LV']['prospective_training_groups'][0]['parents'].pop('rhs_s1')
        with self.assertRaisesRegex(RuntimeError,'parent set'):v._validate_training(self.p)
    def test_cached_path_count_not_inherited_into_baseline(self):
        self.p['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']['posterior_paths']=100
        with self.assertRaisesRegex(RuntimeError,'geometry'):v._validate_training(self.p)


class ClosedCacheTests(unittest.TestCase):
    def setUp(self):self.p=cache_fixture();self.c=self.p['EE_CARRY_FORWARD_READINESS.json']
    def test_closed_carry_forward_validates(self):v._validate_cache(self.p)
    def test_closed_C2_cannot_reopen(self):
        self.c['full_cache_verification']['closed_scope']['EE_C2_exists']=True
        with self.assertRaisesRegex(RuntimeError,'closed cache proof'):v._validate_cache(self.p)
    def test_new_allocation_cannot_be_implicit(self):
        self.c['new_allocation']={'cores':6}
        with self.assertRaisesRegex(RuntimeError,'reopened'):v._validate_cache(self.p)
    def test_original_clock_cannot_reset(self):
        self.c['full_cache_verification']['master']['start_epoch']+=1
        with self.assertRaisesRegex(RuntimeError,'master/clock'):v._validate_cache(self.p)
    def test_checkpoint_cannot_duplicate(self):
        rows=self.c['full_cache_verification']['attempts'][0]['validated_checkpoint_packets'];rows[-1]=deepcopy(rows[0])
        with self.assertRaisesRegex(RuntimeError,'duplicated'):v._validate_cache(self.p)
    def test_checkpoint_is_not_a_complete_component(self):
        self.c['full_cache_verification']['checkpoints']['strict_new_full_components']=1
        with self.assertRaisesRegex(RuntimeError,'checkpoint census'):v._validate_cache(self.p)
    def test_failed_unit_cannot_be_ignored(self):
        self.c['full_cache_verification']['closed_scope']['actual_drain']['cleanup'][0]['drained']=False
        with self.assertRaisesRegex(RuntimeError,'drain'):v._validate_cache(self.p)
    def test_historical_charge_cannot_be_refunded(self):
        self.c['carried_ledger']['EE_science_reserved_CPU_seconds']-=1
        with self.assertRaisesRegex(RuntimeError,'ledger'):v._validate_cache(self.p)


class SourceAndReadOnlyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);root=Path(self.tmp.name)
        sources={}
        for i in range(10):
            p=root/f'source{i}.py';p.write_text(f'# source {i}\n');sources[str(p)]=v.sha256(p)
        self.p={'SCIENCE_PREPARATION_STATUS.json':dict(source_sha256=sources),
            'READONLY_SOURCE_ALIAS_PROOF.json':dict(source_sha256=deepcopy(sources),remote_to_local_path={},matched_remote_preparation_pins=True)}
        for n in ['CERTIFICATE_REPAIR_DOSSIER.json','LV_CALIBRATION_DOSSIER.json','LV_TRAINING_DIAGNOSTIC_MANIFEST.json']:
            self.p[n]=dict(source_sha256=deepcopy(sources))
    def test_scientific_sources_are_read_and_hashed(self):self.assertEqual(v._verify_sources(self.p),(10,0))
    def test_source_change_rejected(self):
        Path(next(iter(self.p['SCIENCE_PREPARATION_STATUS.json']['source_sha256']))).write_text('# changed')
        with self.assertRaisesRegex(RuntimeError,'source bytes'):v._verify_sources(self.p)
    def test_unknown_alias_rejected(self):
        self.p['READONLY_SOURCE_ALIAS_PROOF.json']['remote_to_local_path']['/untracked.py']=str(ENTRY)
        with self.assertRaisesRegex(RuntimeError,'unknown'):v._verify_sources(self.p)
    def test_cross_dossier_source_map_rejected(self):
        self.p['LV_CALIBRATION_DOSSIER.json']['source_sha256']={}
        with self.assertRaisesRegex(RuntimeError,'cross-artifact'):v._verify_sources(self.p)
    def test_verifier_has_only_readonly_imports_and_no_executor(self):
        tree=ast.parse(ENTRY.read_text());imports=set();forbidden={'exec','eval','compile','__import__','open'}
        for n in ast.walk(tree):
            if isinstance(n,ast.Import):imports.update(x.name for x in n.names)
            if isinstance(n,ast.ImportFrom):imports.add(n.module)
            if isinstance(n,ast.Call) and isinstance(n.func,ast.Name):self.assertNotIn(n.func.id,forbidden)
            if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute):
                self.assertNotIn(n.func.attr,{'write_text','write_bytes','unlink','rename','replace','mkdir','Popen','run','system','fork','execv'})
        self.assertTrue(imports <= {'__future__','argparse','hashlib','json','math','pathlib','sys'})
    @unittest.skipUnless(REAL_BUNDLE.is_dir(),'external pinned science bundle not installed')
    def test_actual_pinned_bundle_integration(self):
        result=v.verify_bundle(REAL_BUNDLE)
        self.assertEqual(result['sealed_files'],19);self.assertEqual(result['EE_retained_checkpoints'],225)
        self.assertFalse(result['dispatch_authorized']);self.assertEqual(result['source_or_runtime_writes'],0)


if __name__=='__main__':unittest.main()
