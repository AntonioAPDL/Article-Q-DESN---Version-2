"""Adversarial metadata checks; no scientific arrays, scoring or worker imports."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location('calendar_plan', Path(__file__).with_name('calendar_plan.py'))
p = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(p)


def fixture(study='DK2'):
    count = 20 if study == 'DK2' else 19
    packages = [dict(package_id='C0', candidate_id='g0')]+[
        dict(package_id='P'+str(i), candidate_id='g'+str(i)) for i in range(count)]
    by_id = {x['package_id']: x for x in packages}; config = dict(audit_key='frozen')
    order = sorted(by_id, key=lambda n: (hashlib.sha256(('frozen|'+n).encode()).hexdigest(), n))
    tasks, estimates = [], {}
    def name(pkg, split, mode, seed): return '|'.join(map(str, [pkg, split, mode, seed]))
    for pkg in by_id:
        for split in (1, 2, 3):
            for mode, seed in [('D', 0), ('S', 0), ('S', 1), ('S', 2)]:
                n = name(pkg, split, mode, seed)
                tasks.append(dict(package_id=pkg, split=split, mode=mode, seed_index=seed, name=n,
                    clock_offsets_steps=[0, 24, 48, 72], horizon_steps=96, quantiles=p.QUANTILES[:], reuse=None))
                estimates[n] = dict(reserved_CPU=3, reserved_wall=4, imported=None)
    branches = []
    for a in by_id:
        if a == 'C0': continue
        b = next(n for n in order if by_id[n]['candidate_id'] not in {'g0', by_id[a]['candidate_id']})
        for q in ([], [a], [b], [a, b]):
            extras = 6*(1+len(q)) if q else 0
            total = 3*len(by_id)+9+extras+1
            branches.append(dict(possible_A=a, prospective_B=b, possible_qualified_set=q,
                D_count=3*len(by_id), S0_count=9, atomic_extra_count=extras, replacement_count=1,
                reserved_science_CPU=3*total, serial_component_wall=4*total))
    prices = dict(task_estimates=estimates, all_loss_blind_branches=branches,
                  rounded_D_worst9S0_and_replacement_CPU=3*(3*len(by_id)+10), available_science_CPU_share_adjusted=100000)
    return dict(packages=packages, control='C0', tasks=tasks, frozen_audit_permutation=order), config, prices


def assumptions():
    rows = []
    for name in sorted(p.OPERATIONS):
        rows.append(dict(name=name, unit_CPU=2, base_count=int(name in {'preparation', 'publication', 'proof'}),
            per_study_count=int(name in {'cache', 'recovery'}), per_job_count=int(name in {'parent', 'metadata', 'transfer'}),
            per_wave_count=0, per_phase_count=0, measured=False))
    return dict(batch_overhead=dict(cpu=1, wall=2),
        calendar_tails=dict(queue=1, drain=60, barrier=7, wave_open=9, assessment=1800),
        controller=dict(ceiling_CPU=1800, existing_joint_charge_CPU=3, operations=rows),
        remaining_outer_wall=30000, evidence={name: False for name in p.EVIDENCE})


def scenario(model, branch, a, d_bins_index=0):
    v = dict(replacement_phase='D', covered_failed_tasks=branch['phase_names']['D'], workers=4, policy_workers=4,
        phase_jobs={stage: p.partitions(ids, model['tasks'], a['batch_overhead'], stage)[0]
                    for stage, ids in branch['phase_names'].items()})
    v['phase_jobs']['D'] = p.partitions(branch['phase_names']['D'], model['tasks'], a['batch_overhead'], 'D')[d_bins_index]
    phases = p.scenario_phases(model, branch, v, a['batch_overhead'])
    c = p.constructive(phases, 4, a['calendar_tails']); jobs = sum(len(j) for _, j in phases)+1
    v.update(calendar=c, job_count=jobs, phase_count=len(phases), extra_batch_CPU=(jobs-1)*a['batch_overhead']['cpu'],
        controller_single_study_diagnostic=p.controller_cost(a['controller'], jobs, c['waves'], len(phases), studies=1),
        within_remaining_outer_wall=c['assessment_end'] <= a['remaining_outer_wall'])
    return v


class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.model = p.adapt(*fixture(), 'DK2'); self.a = assumptions(); self.branch = self.model['branches'][1]
        self.s = scenario(self.model, self.branch, self.a)

    def test_both_complete_original_grids(self):
        self.assertEqual((len(self.model['tasks']), len(self.model['branches'])), (252, 80))
        fi = p.adapt(*fixture('FI'), 'FI'); self.assertEqual((len(fi['tasks']), len(fi['branches'])), (240, 76))
        self.assertEqual({b['atomic_extra_count'] for b in fi['branches']}, {0, 12, 18})

    def test_missing_task_and_branch_rejected(self):
        for kind in ('task', 'branch'):
            prep, config, price = fixture()
            (prep['tasks'] if kind == 'task' else price['all_loss_blind_branches']).pop()
            with self.assertRaises(ValueError): p.adapt(prep, config, price, 'DK2')

    def test_clock_and_seed_bool_rejected(self):
        for field, value in [('clock_offsets_steps', [False, 24, 48, 72]), ('seed_index', False), ('split', True)]:
            prep, config, price = fixture(); prep['tasks'][0][field] = value
            with self.assertRaises(ValueError): p.adapt(prep, config, price, 'DK2')

    def test_false_nominee_and_price_rejected(self):
        for field, value in [('prospective_B', 'C0'), ('atomic_extra_count', 6), ('reserved_science_CPU', 1)]:
            prep, config, price = fixture(); price['all_loss_blind_branches'][1][field] = value
            with self.assertRaises(ValueError): p.adapt(prep, config, price, 'DK2')

    def test_boolean_price_rejected(self):
        prep, config, price = fixture(); price['task_estimates'][prep['tasks'][0]['name']]['reserved_CPU'] = True
        with self.assertRaises(ValueError): p.adapt(prep, config, price, 'DK2')

    def test_balanced_options_preserve_all_tasks_and_capacity(self):
        ids = self.branch['phase_names']['D']; options = p.partitions(ids, self.model['tasks'], self.a['batch_overhead'], 'D')
        self.assertGreater(len(options), 1)
        for jobs in options:
            self.assertEqual(sorted(n for j in jobs for n in j['tasks']), sorted(ids))
            self.assertTrue(all(j['cpu'] <= 5400 and j['wall'] <= 5400 for j in jobs))

    def test_nonzero_overhead_and_barriers_verified(self):
        self.assertTrue(p.verify_scenario(self.model, self.branch, self.s, self.a))
        self.assertGreater(self.s['calendar']['assessment_end'], 1800)

    def test_empty_extra_phase_preserves_barrier(self):
        branch = self.model['branches'][0]; s = scenario(self.model, branch, self.a)
        self.assertTrue(p.verify_scenario(self.model, branch, s, self.a))

    def test_missing_batch_and_duplicate_task_rejected(self):
        for change in ('missing', 'duplicate'):
            s = copy.deepcopy(self.s)
            if change == 'missing': s['calendar']['rows'].pop()
            else: s['phase_jobs']['D'][0]['tasks'].append(s['phase_jobs']['D'][0]['tasks'][0])
            with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_crossed_phase_barrier_rejected(self):
        s = copy.deepcopy(self.s); row = next(r for r in s['calendar']['rows'] if r['phase'] == 'S0')
        row['dispatch'] = 9; row['finish'] = 9+self.a['calendar_tails']['queue']+row['wall']+60
        with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_wave_start_lease_and_worker_forgery_rejected(self):
        for field, value in [('wave_start', 999), ('worker', 4), ('wave', 4), ('dispatch', 9000)]:
            s = copy.deepcopy(self.s); s['calendar']['rows'][0][field] = value
            with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_assessment_tail_and_job_count_rejected(self):
        for change in ('assessment', 'count'):
            s = copy.deepcopy(self.s)
            if change == 'assessment': s['calendar']['assessment_end'] -= 1
            else: s['job_count'] -= 1
            with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_controller_forgery_rejected(self):
        s = copy.deepcopy(self.s); s['controller_single_study_diagnostic']['CPU'] = 0
        with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_replacement_membership_rejected(self):
        s = copy.deepcopy(self.s); s['covered_failed_tasks'] = s['covered_failed_tasks'][:-1]
        with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_three_actual_requires_four_policy(self):
        s = copy.deepcopy(self.s); s['workers'] = 3; s['policy_workers'] = 3
        with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_controller_joint_counts_and_old_debit(self):
        c = p.controller_cost(self.a['controller'], 20, 6, 10)
        self.assertEqual(c['CPU'], 3+sum(row['CPU'] for row in c['operations']))
        parent = next(x for x in c['operations'] if x['name'] == 'parent')
        self.assertEqual(parent['count'], 20); self.assertFalse(c['all_measured'])

    def test_missing_grid_free_operation_and_changed_cap_rejected(self):
        for change in ('missing', 'free', 'cap'):
            a = copy.deepcopy(self.a)
            if change == 'missing': a['controller']['operations'].pop()
            elif change == 'free': next(x for x in a['controller']['operations'] if x['name'] == 'parent')['unit_CPU'] = 0
            else: a['controller']['ceiling_CPU'] = 1801
            with self.assertRaises(ValueError): p.assumptions_check(a)

    def test_partial_extra_and_missing_actual_charge_rejected(self):
        expected = self.branch['phase_names']['EXTRAS']; prefix = self.branch['phase_names']['D']+self.branch['phase_names']['S0']
        charges = dict.fromkeys(prefix, .5)
        with self.assertRaises(ValueError): p.atomic_extra_check(self.model, self.branch, expected[:6], charges, 1000, self.s, self.a, 0)
        charges.pop(prefix[0])
        with self.assertRaises(ValueError): p.atomic_extra_check(self.model, self.branch, expected, charges, 1000, self.s, self.a, 0)

    def test_actual_charges_can_fund_optional_despite_worst_reservation(self):
        model = copy.deepcopy(self.model); model['prices']['available_science_CPU_share_adjusted'] = 220
        prefix = self.branch['phase_names']['D']+self.branch['phase_names']['S0']; expected = self.branch['phase_names']['EXTRAS']
        costly = p.atomic_extra_check(model, self.branch, expected, dict.fromkeys(prefix, 3), 1000, self.s, self.a, 0)
        cheap = p.atomic_extra_check(model, self.branch, expected, dict.fromkeys(prefix, .5), 1000, self.s, self.a, 0)
        self.assertIn('WHOLE_EXTRA_CPU_UNFUNDED', costly['reasons'])
        self.assertNotIn('WHOLE_EXTRA_CPU_UNFUNDED', cheap['reasons'])
        self.assertFalse(cheap['admitted']); self.assertIn('PROSPECTIVE_RESOURCE_EVIDENCE_UNPROVED', cheap['reasons'])

    def test_prefix_overhead_not_double_charged_at_extra_decision(self):
        prefix = self.branch['phase_names']['D']+self.branch['phase_names']['S0']; expected = self.branch['phase_names']['EXTRAS']
        result = p.atomic_extra_check(self.model, self.branch, expected, dict.fromkeys(prefix, 1), 10000, self.s, self.a, 0)
        self.assertEqual(result['required_CPU'], sum(self.model['tasks'][n]['cpu'] for n in expected)+2)

    def test_full_grid_finite_search_no_false_admission(self):
        result = p.analyze(self.model, self.a, max_combinations=1)
        self.assertEqual((result['task_count'], result['branch_count'], result['complete_scenarios']), (252, 80, 880))
        self.assertTrue(all(x['status'] in {'CONSTRUCTIVE', 'UNPROVEN', 'PROVED_RESERVED_VOLUME_INFEASIBLE',
                                          'PROVED_SINGLE_COMPONENT_CAP_INFEASIBLE'} for x in result['scenarios']))

    def test_oversize_component_and_failed_search_honesty(self):
        tasks = {'a': dict(id='a', cpu=100, wall=5400, imported=False)}
        self.assertEqual(p.partitions(['a'], tasks, dict(cpu=1, wall=1), 'D'), [])
        jobs = [dict(id=str(i), tasks=[str(i)], cpu=5000, wall=5400) for i in range(4)]
        self.assertIsNone(p.constructive([('D', jobs)], 1, self.a['calendar_tails']))

    def test_changed_pin_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            path = Path(tmp)/'input.json'; path.write_text('{}')
            with self.assertRaises(ValueError): p.pin_read(dict(path=str(path), sha256='0'*64))
            link = Path(tmp)/'link.json'; link.symlink_to(path)
            with self.assertRaises(ValueError): p.pin_read(dict(path=str(link), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))

    def test_atomic_create_only_result_preserved(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            path = Path(tmp)/'result.json'; p.publish_new(path, {'scientific_admission': False})
            original = path.read_bytes()
            with self.assertRaises(FileExistsError): p.publish_new(path, {'changed': True})
            self.assertEqual(path.read_bytes(), original); self.assertEqual(list(Path(tmp).glob('*.tmp')), [])

    def test_duplicate_and_nonfinite_json_rejected(self):
        for value in ('{"x":1,"x":2}', '{"x":NaN}', '[1e309]', '{"x":Infinity}'):
            with self.assertRaises(ValueError): p.strict_json(value)

    def test_resigned_modified_accepted_price_pin_rejected(self):
        refs = dict(schema='r163_calendar_inputs_v1', purpose='PRICEFM_METADATA_CALENDAR_PREPARATION',
            prices=dict(path='/unused/price.json', sha256='0'*64), assumptions=self.a,
            studies={n: {role: dict(path='/unused/'+role+'.json', sha256=digest)
                     for role, digest in pins.items()} for n, pins in p.ACCEPTED_INPUTS.items()})
        with self.assertRaisesRegex(ValueError, 'no repricing'): p.input_refs_check(refs)

    def test_cheap_complete_preparation_verifier_rejects_false_joint_claim(self):
        models = {'FI': p.adapt(*fixture('FI'), 'FI'), 'DK2': self.model}
        result = p.prepare(models, self.a, max_combinations=1)
        self.assertTrue(p.verify_preparation(result, models, self.a))
        result['joint_calendar']['certificate'] = True
        with self.assertRaises(ValueError): p.verify_preparation(result, models, self.a)

    def test_shared_capacity_pair_is_not_all_pairs_authority(self):
        fi = p.adapt(*fixture('FI'), 'FI'); branches = {'FI': fi['branches'][1], 'DK2': self.branch}
        models = {'FI': fi, 'DK2': self.model}
        scenarios = {name: scenario(model, branches[name], self.a) for name, model in models.items()}
        result = p.verify_shared_capacity(scenarios, models, branches, self.a)
        self.assertFalse(result['scientific_admission']); self.assertFalse(result['all_branch_pairs_certified'])

    def test_shared_four_worker_ceiling_rejects_eight_overlapping_workers(self):
        fi = p.adapt(*fixture('FI'), 'FI'); branches = {'FI': fi['branches'][1], 'DK2': self.branch}
        models = {'FI': fi, 'DK2': self.model}
        scenarios = {name: scenario(model, branches[name], self.a, d_bins_index=3) for name, model in models.items()}
        with self.assertRaisesRegex(ValueError, 'aggregate shared capacity'):
            p.verify_shared_capacity(scenarios, models, branches, self.a)

    def test_boolean_policy_and_resigned_controller_type_rejected(self):
        for mutation in ('policy', 'counter'):
            s = copy.deepcopy(self.s)
            if mutation == 'policy': s['policy_workers'] = True
            else: s['controller_single_study_diagnostic']['operations'][0]['count'] = True
            with self.assertRaises(ValueError): p.verify_scenario(self.model, self.branch, s, self.a)

    def test_outer_worker_and_replacement_labels_bound_to_witness(self):
        models = {'FI': p.adapt(*fixture('FI'), 'FI'), 'DK2': copy.deepcopy(self.model)}
        for model in models.values(): model['branches'] = [model['branches'][1]]
        result = p.prepare(models, self.a, max_combinations=1)
        self.assertTrue(p.verify_preparation(result, models, self.a))
        for field, value in [('workers', 4), ('replacement_phase', 'S0')]:
            changed = copy.deepcopy(result)
            row = next(x for x in changed['studies']['DK2']['scenarios']
                       if x['workers'] == 1 and x['replacement_phase'] == 'D')
            row['scenario'][field] = value
            with self.assertRaisesRegex(ValueError, 'outer/inner'): p.verify_preparation(changed, models, self.a)

    def test_json_roundtrip_and_gate_order_preserve_exact_named_proof(self):
        models = {'FI': p.adapt(*fixture('FI'), 'FI'), 'DK2': copy.deepcopy(self.model)}
        for model in models.values(): model['branches'] = [model['branches'][1]]
        result = json.loads(json.dumps(p.prepare(models, self.a, max_combinations=1), sort_keys=True))
        reordered = json.loads(json.dumps(self.a, sort_keys=True))
        result['gates'].reverse()
        self.assertTrue(p.verify_preparation(result, models, reordered))
        changed = copy.deepcopy(result); changed['gates'].append(copy.deepcopy(changed['gates'][0]))
        with self.assertRaisesRegex(ValueError, 'duplicate gate'): p.verify_preparation(changed, models, reordered)
        changed = copy.deepcopy(result); changed['gates'][0]['passed'] = 0
        with self.assertRaisesRegex(ValueError, 'boolean gate'): p.verify_preparation(changed, models, reordered)


if __name__ == '__main__':
    unittest.main()
