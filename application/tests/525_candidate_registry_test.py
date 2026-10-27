#!/usr/bin/env python3
"""Synthetic metadata/file tests only: no target arrays or optimizer is loaded."""
from copy import deepcopy
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('registry', ROOT / 'scripts/pricefm/525_candidate_registry.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
REAL_LOADER = r.load_original_manifest


class Fixture:
    """A closed synthetic seven-target manifest substitutes only the loader.

    Validation/sealing/acceptance/resolution code is never mocked. Byte files
    are tiny fixtures rather than real X/y, covariance, RDS or posterior data.
    """
    def __init__(self, root):
        self.root = Path(root); self.count = 0
        self.source = dict(branch='work/pricefm-r154-fullstate-pilot-adapter-test',
                           head='a' * 40, kind=r.SOURCE_KIND)
        self.manifest = deepcopy(REAL_LOADER())
        for target in self.manifest['targets']:
            target['n'] = 2; target['p'] = 2
            design = self.root / 'original_designs' / target['name']; design.mkdir(parents=True)
            (design / 'X.bin').write_bytes(b'X' * 32); (design / 'y.bin').write_bytes(b'y' * 16)
            d = {'status': 'completed_r137_quantile_design', 'test_opened': False,
                 'files': {'X.bin': r.digest(design / 'X.bin'), 'y.bin': r.digest(design / 'y.bin')}}
            r.immutable_json(design / 'terminal.json', d)
            sha = r.digest(design / 'terminal.json')
            target['contract']['design_terminal_sha256'] = sha
            target['contract']['design_dir'] = str(design)
            target['posterior_target_sha256'] = sha + ':fixture:' + target['name']
            target['contract']['posterior_target_sha256'] = target['posterior_target_sha256']
            target['fixture_design'] = str(design)

    def write(self, path, data):
        path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
        r.immutable_json(path, data); return r.pin(path)

    def packet(self, name=r.NO3, *, formal=False, independent=True, finite=True):
        self.count += 1; number = self.count
        target = r.target_record(self.manifest, name)
        root = self.root / ('candidate_%02d' % number); root.mkdir()
        evidence = self.root / ('external_%02d' % number); evidence.mkdir()
        design = Path(target['fixture_design'])
        refs = {'X': r.pin(design / 'X.bin'), 'y': r.pin(design / 'y.bin')}
        factor = evidence / 'full_state.rds'; factor.write_bytes(b'fixture-factor-state')
        bridge = dict(schema='r154_conditional_state_bridge_v1', target_name=name,
            posterior_target_sha256=target['posterior_target_sha256'], source=self.source,
            units=r.UNITS, prior=r.PRIOR, optimizer_updates=0,
            full_state_factors_verified=True, explicit_factor_elbo_verified=True,
            original_seven_certificate_computed=True, rhs_unit_and_dispersed_verified=True,
            source_recipe_reproduced=True, factor_state=r.pin(factor), data_references=refs)
        bridge_pin = self.write(evidence / 'bridge_validation.json', bridge)
        values = {key: limit / 2 for key, limit in r.LIMITS.items()}
        if not independent:
            values['beta_posterior_sd_rms'] = r.LIMITS['beta_posterior_sd_rms'] * 2
        certificate = dict(certified=independent, measures=values, limits=r.LIMITS,
            rhs_reconstruction=dict(unit_converged=True, dispersed_converged=True))
        checkpoints = []
        for sweep in (1, 2):
            state = root / 'checkpoints' / ('sweep_%03d.rds' % sweep)
            state.parent.mkdir(exist_ok=True); state.write_bytes(('state%d' % sweep).encode())
            checkpoints.append(dict(completed_sweep=sweep, state_pin=r.pin(state),
                                    contains_all_factors_and_schedules=True))
        index_pin = self.write(root / 'checkpoints/index.json', dict(
            schema='r154_fullstate_checkpoint_index_v1', target_name=name,
            posterior_target_sha256=target['posterior_target_sha256'], source=self.source,
            data_references=refs, checkpoints=checkpoints))
        admission_pin = self.write(evidence / 'admission.json', dict(
            status='ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY', target_name=name,
            source=self.source, max_iter=300, new_attempt_index=1))
        actual_runtime = self.write(evidence / 'actual_runtime.json', {'fixture': 'no process execution'})
        runtime_pin = self.write(evidence / 'runtime.json', dict(status='VERIFIED_EXECUTION_RUNTIME',
            host='muscat', package_repository='CRAN', package_version='1.1.1', source=self.source,
            actual_R_runtime_binding=actual_runtime))
        guard_pin = self.write(evidence / 'owned_guard_receipt.json', dict(
            schema='r154_owned_stage_guard_receipt_v1', status='EXITED', returncode=0,
            source=self.source, target_name=name, child_CPU_seconds=2.0,
            reaped=True, drained=True, CPU_accounting_complete=True,
            preexec_kernel_boundary_proved=True, subprocess_creation_kernel_denied=True))
        funding_pin = self.write(evidence / 'funding.json', dict(reserved_parent_and_finalize_CPU_seconds=300.0))
        ledger_pin = self.write(evidence / 'ledger.json', dict(status='PILOT_REAPED', returncode=0,
            target_name=name, source=self.source, child_CPU_seconds=2.0,
            reaped=True, drained=True, CPU_accounting_complete=True,
            preexec_kernel_boundary_proved=True, subprocess_creation_kernel_denied=True,
            owned_guard_receipt_pin=guard_pin,
            funding_pin=funding_pin, actual_whole_stage_CPU_seconds_at_ledger=12.0,
            administrative_CPU_seconds_including_startup_and_reaped_helpers=10.0,
            reserved_finalization_tail_CPU_seconds=30.0, whole_stage_debit_CPU_seconds=302.0,
            all_parent_lineage_costs_paid=True, original_failed_costs_refunded=False))
        terminal = dict(schema='r154_project_consumer_candidate_v1',
            record_kind='pilot_candidate_no_automatic_release',
            origin='sealed_real_target_project_consumer', target_name=name,
            posterior_target_sha256=target['posterior_target_sha256'],
            n=target['n'], p=target['p'], tau=target['tau'], tau0=target['tau0'], seed=target['seed'],
            source=self.source, original_failed=target['bindings'],
            original_manifest_sha256=r.MANIFEST_SHA256, units=r.UNITS, prior=r.PRIOR,
            test_opened=False, prior_center_from_initializer=False,
            initializer=dict(kind='conditional_reconstruction_new_initialization', bridge=bridge_pin,
                exact_optimizer_resume=False, prior_center_from_initializer=False),
            max_iter=300, new_attempt_index=1, maximum_new_attempts=1,
            prior_attempt_iterations=300, completed_sweeps=2,
            old_completed_artifacts_modified=False, automatic_dependant_release=False,
            finite_core=finite, formal_converged=formal, independent_certificate=certificate,
            all_seven_certificate_computed=True, computationally_certified=finite and (formal or independent),
            acceptance_logic=r.ACCEPTANCE, checkpoint_index=index_pin,
            admission_pin=admission_pin, runtime_pin=runtime_pin, ledger_pin=ledger_pin)
        (root / 'beta_mean.bin').write_bytes(b'b' * 16)
        (root / 'beta_cov.bin').write_bytes(b'V' * 32)
        (root / 'vb_trace.csv').write_text('iteration,fixture\n1,0\n2,0\n')
        (root / 'final_state.rds').write_bytes(b'fixture-final-factors-no-real-model')
        core = dict(terminal); core.pop('ledger_pin')
        self.write(root / 'terminal_core.json', core)
        self.write(root / 'terminal.json', terminal)
        return root

    def edit_terminal(self, root, transform):
        path = Path(root) / 'terminal.json'; data = r.read(path); transform(data)
        path.write_text(json.dumps(data, sort_keys=True))
        core = dict(data); core.pop('ledger_pin')
        (Path(root) / 'terminal_core.json').write_text(json.dumps(core, sort_keys=True))

    def registered(self, **kwargs):
        packet = self.packet(**kwargs)
        seal = r.seal_candidate_packet(packet, self.manifest, self.source)
        self.finalization_accounting(packet)
        registration = r.register_candidate(self.root / 'registry', seal, self.manifest, self.source)
        return packet, seal, registration

    def finalization_accounting(self, packet):
        terminal = r.read(Path(packet) / 'terminal.json')
        return self.write(Path(packet) / 'finalization_accounting.json', dict(
            status='WITHIN_RESERVED_PARENT_AND_FINALIZATION', source=self.source,
            target_name=terminal['target_name'], actual_whole_stage_CPU_seconds=22.0,
            administrative_CPU_seconds_including_startup_and_reaped_helpers=20.0,
            reserved_parent_and_finalize_CPU_seconds=300.0, whole_stage_debit_CPU_seconds=302.0,
            candidate_registration_not_yet_started=True))

    def resolution(self, registration):
        record = r.read(registration['path'])
        self.count += 1
        return self.write(self.root / ('resolution_%02d.json' % self.count), dict(
            schema='r154_explicit_candidate_resolution_v1', status='ROOT_APPROVED_EFFECTIVE_TASK_ONLY',
            authorizes_effective_task_resolution=True, authorizes_automatic_dependant_release=False,
            target_name=record['target_name'], source=self.source, registration_pin=registration,
            candidate_seal_pin=record['candidate_seal_pin']))


class Registry(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='r525_registry_fixture_')
        self.f = Fixture(self.tmp.name)
        self.loader = mock.patch.object(r, 'load_original_manifest', return_value=self.f.manifest)
        self.loader.start()

    def tearDown(self):
        self.loader.stop(); self.tmp.cleanup()

    def test_original_manifest_raw_pin_and_contract(self):
        original = REAL_LOADER(); self.assertEqual(len(original['targets']), 7)
        with self.assertRaises(ValueError): REAL_LOADER(expected_sha='0' * 64)

    def test_candidate_only_registration_does_not_activate(self):
        packet, seal, registered = self.f.registered()
        result = r.resolve_effective_task(r.NO3, '/original/failure', self.f.manifest,
            self.f.source, registration_pin=registered)
        self.assertEqual(result['packet'], '/original/failure'); self.assertFalse(result['candidate_activated'])
        self.assertTrue(r.read(registered['path'])['accepted'])
        with self.assertRaises(FileExistsError): r.register_candidate(self.f.root / 'registry', seal, self.f.manifest, self.f.source)
        with self.assertRaises(FileExistsError): r.seal_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_finalization_funding_and_registration_proof_required(self):
        for change in (dict(administrative_CPU_seconds_including_startup_and_reaped_helpers=301.0,
                            actual_whole_stage_CPU_seconds_at_ledger=303.0, whole_stage_debit_CPU_seconds=303.0),
                       dict(actual_whole_stage_CPU_seconds_at_ledger=11.0),
                       dict(whole_stage_debit_CPU_seconds=2.0),
                       dict(reserved_finalization_tail_CPU_seconds=400.0)):
            packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
            ledger_path = Path(terminal['ledger_pin']['path']); ledger = r.read(ledger_path)
            ledger.update(change); ledger_path.write_text(json.dumps(ledger))
            self.f.edit_terminal(packet, lambda data: data.__setitem__('ledger_pin', r.pin(ledger_path)))
            with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)
        packet = self.f.packet(); seal = r.seal_candidate_packet(packet, self.f.manifest, self.f.source)
        with self.assertRaises(FileNotFoundError):
            r.register_candidate(self.f.root / 'registry', seal, self.f.manifest, self.f.source)
        self.f.finalization_accounting(packet)
        path = packet / 'finalization_accounting.json'; original = r.read(path)
        for change in (dict(status='PARENT_RESERVATION_OVERRUN_STOP'),
                       dict(source=dict(self.f.source, head='0' * 40)), dict(target_name=r.AT),
                       dict(administrative_CPU_seconds_including_startup_and_reaped_helpers=301.0,
                            actual_whole_stage_CPU_seconds=303.0, whole_stage_debit_CPU_seconds=303.0),
                       dict(whole_stage_debit_CPU_seconds=2.0), dict(actual_whole_stage_CPU_seconds=1.0)):
            path.write_text(json.dumps(dict(original, **change)))
            with self.assertRaises(ValueError):
                r.register_candidate(self.f.root / 'registry', seal, self.f.manifest, self.f.source)
        path.write_text(json.dumps(original))
        registered = r.register_candidate(self.f.root / 'registry', seal, self.f.manifest, self.f.source)
        self.assertEqual(r.read(registered['path'])['finalization_accounting_pin'], r.pin(path))
        path.write_text('{}')
        with self.assertRaises(ValueError): r.validate_registration(registered, self.f.manifest, self.f.source)

    def test_original_OR_acceptance_and_always_seven_gates(self):
        for formal, independent, finite, expected in [(False, True, True, True),
                (True, False, True, True), (False, False, True, False), (True, True, False, False)]:
            packet = self.f.packet(formal=formal, independent=independent, finite=finite)
            self.assertIs(r.validate_candidate_packet(packet, self.f.manifest, self.f.source)['accepted'], expected)
        packet = self.f.packet(formal=True, independent=False)
        self.f.edit_terminal(packet, lambda d: d['independent_certificate']['measures'].__setitem__('beta_posterior_sd_rms', None))
        self.assertTrue(r.validate_candidate_packet(packet, self.f.manifest, self.f.source)['accepted'])
        self.f.edit_terminal(packet, lambda d: d.__setitem__('all_seven_certificate_computed', False))
        with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_changed_target_source_units_prior_cap_resume_or_flags_rejected(self):
        mutations = [lambda d: d.__setitem__('origin', 'synthetic_toy'),
            lambda d: d.__setitem__('record_kind', 'diagnostic_only'),
            lambda d: d.__setitem__('units', 'standardized'),
            lambda d: d.__setitem__('prior', dict(r.PRIOR, center='initializer')),
            lambda d: d.__setitem__('tau0', d['tau0'] * 2),
            lambda d: d.__setitem__('source', dict(self.f.source, kind='unmodified_public_CRAN_fit')),
            lambda d: d.__setitem__('max_iter', 600),
            lambda d: d.__setitem__('prior_attempt_iterations', 0),
            lambda d: d['initializer'].__setitem__('exact_optimizer_resume', True),
            lambda d: d.__setitem__('automatic_dependant_release', True),
            lambda d: d['independent_certificate']['limits'].__setitem__('elbo_relative', 1e-6)]
        for change in mutations:
            packet = self.f.packet(); self.f.edit_terminal(packet, change)
            with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_hash_state_runtime_ledger_and_checkpoint_fail_closed(self):
        packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
        bridge = r.read(terminal['initializer']['bridge']['path'])
        Path(bridge['factor_state']['path']).write_bytes(b'changed')
        with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)
        packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
        index = r.read(terminal['checkpoint_index']['path']); index['checkpoints'].pop()
        Path(terminal['checkpoint_index']['path']).write_text(json.dumps(index))
        terminal['checkpoint_index'] = r.pin(terminal['checkpoint_index']['path'])
        (packet / 'terminal.json').write_text(json.dumps(terminal))
        core = dict(terminal); core.pop('ledger_pin'); (packet / 'terminal_core.json').write_text(json.dumps(core))
        with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)
        packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
        ledger = r.read(terminal['ledger_pin']['path']); ledger['original_failed_costs_refunded'] = True
        Path(terminal['ledger_pin']['path']).write_text(json.dumps(ledger)); terminal['ledger_pin'] = r.pin(terminal['ledger_pin']['path'])
        (packet / 'terminal.json').write_text(json.dumps(terminal))
        core = dict(terminal); core.pop('ledger_pin'); (packet / 'terminal_core.json').write_text(json.dumps(core))
        with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_candidate_seal_detects_tamper_and_symlink(self):
        packet, seal, registered = self.f.registered()
        (packet / 'beta_mean.bin').write_bytes(b'changed')
        with self.assertRaises(ValueError): r.validate_candidate_seal(seal, self.f.manifest, self.f.source)
        packet = self.f.packet(); (packet / 'forged-link').symlink_to(packet / 'final_state.rds')
        with self.assertRaises(ValueError): r.seal_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_two_phase_finalization_only_adds_actual_ledger(self):
        packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
        (packet / 'terminal.json').unlink()  # Synthetic fixture producer boundary.
        before = (packet / 'terminal_core.json').read_bytes()
        validated = r.finalize_terminal_core(packet, terminal['ledger_pin'], self.f.manifest, self.f.source)
        self.assertTrue(validated['accepted'])
        self.assertEqual((packet / 'terminal_core.json').read_bytes(), before)
        with self.assertRaises(FileExistsError): r.finalize_terminal_core(packet, terminal['ledger_pin'], self.f.manifest, self.f.source)

    def test_aborted_unproved_undrained_or_foreign_guard_cannot_finalize(self):
        for layer in ('ledger', 'guard'):
            changes = [(flag, False) for flag in ('reaped', 'drained', 'CPU_accounting_complete',
                'preexec_kernel_boundary_proved', 'subprocess_creation_kernel_denied')]
            changes += [('returncode', -9), ('child_CPU_seconds', 3.0)]
            if layer == 'guard':
                changes += [('status', 'ABORTED'), ('target_name', r.AT),
                            ('source', dict(self.f.source, head='0' * 40))]
            for key, changed in changes:
                with self.subTest(layer=layer, field=key):
                    packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
                    ledger = r.pinned_json(terminal['ledger_pin'])
                    path = Path(terminal['ledger_pin']['path'])
                    if layer == 'guard':
                        guard = r.pinned_json(ledger['owned_guard_receipt_pin'])
                        guard[key] = changed
                        guard_path = Path(ledger['owned_guard_receipt_pin']['path'])
                        guard_path.write_text(json.dumps(guard))
                        ledger['owned_guard_receipt_pin'] = r.pin(guard_path)
                    else:
                        ledger[key] = changed
                    path.write_text(json.dumps(ledger)); ledger_pin = r.pin(path)
                    (packet / 'terminal.json').unlink()
                    with self.assertRaises(ValueError):
                        r.finalize_terminal_core(packet, ledger_pin, self.f.manifest, self.f.source)
                    self.assertFalse((packet / 'terminal.json').exists())
        packet = self.f.packet(); terminal = r.read(packet / 'terminal.json')
        ledger = r.pinned_json(terminal['ledger_pin'])
        Path(ledger['owned_guard_receipt_pin']['path']).write_text('{}')
        with self.assertRaises(ValueError): r.validate_candidate_packet(packet, self.f.manifest, self.f.source)
        final = r.read(packet / 'terminal.json'); final['formal_converged'] = True
        (packet / 'terminal.json').write_text(json.dumps(final))
        with self.assertRaisesRegex(ValueError, 'finalizer changed core'):
            r.validate_candidate_packet(packet, self.f.manifest, self.f.source)

    def test_writes_reject_original_campaign_and_changed_manifest(self):
        original_fit = self.f.manifest['targets'][0]['contract']['output_dir']
        with self.assertRaisesRegex(ValueError, 'original campaign'):
            r._guard_new_output_root(original_fit, self.f.manifest)
        changed = deepcopy(self.f.manifest); changed['targets'][0]['tau0'] *= 2
        with self.assertRaisesRegex(ValueError, 'exact original seven'):
            r._guard_new_output_root(self.f.root / 'not-created', changed)
        self.assertFalse((self.f.root / 'not-created').exists())

    def test_NO3_failure_stops_AT_and_no_other_five_target(self):
        _, _, failed = self.f.registered(independent=False)
        with self.assertRaises(ValueError): r.branch_predecessor(r.AT, failed, self.f.manifest, self.f.source)
        with self.assertRaises(ValueError): r.branch_predecessor(r.AT, None, self.f.manifest, self.f.source)
        _, _, accepted = self.f.registered()
        self.assertTrue(r.branch_predecessor(r.AT, accepted, self.f.manifest, self.f.source)['candidate']['accepted'])
        other = next(t['name'] for t in self.f.manifest['targets'] if t['name'] not in r.ALLOWED_TARGETS)
        with self.assertRaises(ValueError): r.branch_predecessor(other, accepted, self.f.manifest, self.f.source)

    def test_explicit_effective_resolution_requires_fresh_exact_approval(self):
        packet, _, registered = self.f.registered(); approved = self.f.resolution(registered)
        result = r.resolve_effective_task(r.NO3, '/original', self.f.manifest, self.f.source, registered, approved)
        self.assertTrue(result['candidate_activated']); self.assertEqual(result['packet'], str(packet))
        d = r.read(approved['path']); d['candidate_seal_pin'] = dict(d['candidate_seal_pin'], sha256='0' * 64)
        Path(approved['path']).write_text(json.dumps(d)); stale = r.pin(approved['path'])
        with self.assertRaises(ValueError): r.resolve_effective_task(r.NO3, '/original', self.f.manifest, self.f.source, registered, stale)
        _, _, failed = self.f.registered(independent=False); failed_approval = self.f.resolution(failed)
        with self.assertRaises(ValueError): r.resolve_effective_task(r.NO3, '/original', self.f.manifest, self.f.source, failed, failed_approval)

    def region_fixture(self, names=None):
        packet, seal, registered = self.f.registered(); resolution = self.f.resolution(registered)
        names = names or [r.NO3]
        tasks = [dict(name=r.NO3, original_packet='/original/NO3', registration_pin=registered,
                      resolution_approval_pin=resolution, evidence_pin=seal)]
        for name in names:
            if name == r.NO3: continue
            # Even a new truthy original seal cannot overwrite a recorded failure.
            artifact = self.f.root / ('task-' + name); artifact.mkdir()
            (artifact / 'result.json').write_text('{}')
            evidence = self.f.write(artifact / 'completed_evidence.json', dict(metadata={'certified': True}, artifacts={'result.json': r.digest(artifact / 'result.json')}))
            tasks.append(dict(name=name, evidence_pin=evidence))
        inventory = self.f.write(self.f.root / ('inventory%d.json' % self.f.count), dict(
            schema='r154_source_qualified_region_task_inventory_v1', region='NO_3', source=self.f.source, tasks=tasks))
        region = self.f.root / ('region%d' % self.f.count); (region / 'closeout').mkdir(parents=True)
        labels = {'exposure': 'development_nonconfirmatory'}
        terminal = dict(schema='r154_project_consumer_region_v1', status='R154_PROJECT_CONSUMER_REGION_COMPLETE_NOT_PROMOTED',
            region='NO_3', source=self.f.source, complete_folds=3, complete_regions=1,
            test_used_for_selection=False, same_target_relative_to_selected_model=True,
            selection_labels=labels, task_inventory_pin=inventory)
        self.f.write(region / 'terminal.json', terminal)
        table = region / 'closeout/fold_comparison.csv'
        with table.open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=['region', 'fold', 'operator', *r.SCORES]); writer.writeheader()
            for fold in (1, 2, 3):
                for operator in sorted(r.OPERATORS): writer.writerow(dict(region='NO_3', fold=fold, operator=operator, **{k: 1 for k in r.SCORES}))
        self.f.write(region / 'closeout/completed_evidence.json', dict(schema='r154_project_region_seal_v1',
            source=self.f.source, task_inventory_pin=inventory, artifacts={'fold_comparison.csv': r.digest(table)}))
        approval = self.f.write(self.f.root / ('region_approval%d.json' % self.f.count), dict(
            schema='r154_full_region_collection_approval_v1', status='ROOT_APPROVED_FULL_REGION_COLLECTION_ONLY',
            region='NO_3', source=self.f.source, selection_labels=labels, task_inventory_pin=inventory,
            required_task_names=names))
        return region, approval

    def test_one_pilot_cannot_close_real_shaped_region_or_hide_smaller_tau(self):
        region, approval = self.region_fixture()
        with self.assertRaisesRegex(ValueError, 'other original regional failures'):
            r.validate_full_region_packet(region, approval, self.f.manifest, self.f.source)
        small = next(t['name'] for t in self.f.manifest['targets'] if t['region'] == 'NO_3' and t['name'] != r.NO3)
        region, approval = self.region_fixture([r.NO3, small])
        with self.assertRaisesRegex(ValueError, 'original failed task'):
            r.validate_full_region_packet(region, approval, self.f.manifest, self.f.source)

    def test_full_regional_schema_surface_under_future_closed_fixture(self):
        # Isolate the generic collector anatomy in a future synthetic closed
        # inventory. This is not a claim that today's NO3 region can close.
        for t in self.f.manifest['targets']:
            if t['region'] == 'NO_3' and t['name'] != r.NO3: t['region'] = 'OTHER_FIXTURE'
        region, approval = self.region_fixture()
        result = r.validate_full_region_packet(region, approval, self.f.manifest, self.f.source)
        self.assertEqual(result['source_class'], 'R154_project_fullstate_pilot_region')
        self.assertEqual(len(result['rows']), 12); self.assertFalse(result['promotion_authority'])
        terminal = r.read(region / 'terminal.json'); terminal['source'] = dict(self.f.source, kind='R141')
        (region / 'terminal.json').write_text(json.dumps(terminal))
        with self.assertRaises(ValueError): r.validate_full_region_packet(region, approval, self.f.manifest, self.f.source)
        terminal['source'] = self.f.source; (region / 'terminal.json').write_text(json.dumps(terminal))
        table = region / 'closeout/fold_comparison.csv'; lines = table.read_text().splitlines(); table.write_text('\n'.join(lines[:-1]) + '\n')
        seal = r.read(region / 'closeout/completed_evidence.json'); seal['artifacts']['fold_comparison.csv'] = r.digest(table)
        (region / 'closeout/completed_evidence.json').write_text(json.dumps(seal))
        with self.assertRaisesRegex(ValueError, 'twelve'):
            r.validate_full_region_packet(region, approval, self.f.manifest, self.f.source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
