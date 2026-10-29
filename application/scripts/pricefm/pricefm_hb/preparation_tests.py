"""Preparation boundary checks; synthetic saved metadata only."""
import copy
import tempfile
import unittest
from pathlib import Path
from . import preparation as p


def packets():
    dispatch = {'schema': 'r163_dispatch_diagnosis_v1', 'purpose': 'PRICEFM_READONLY_DISPATCH_DIAGNOSIS',
                'control_scope': 'MUSCAT_OWNER6_ONLY', 'not_a_Jerez_R143_dispatch_observation': True,
                'dispatch_authorized_by_this_diagnostic': False, 'numerical_execution_authorized': False,
                'status': 'BLOCKED_PROVENANCE_VISIBILITY', 'observed_epoch': 100., 'unresolved': []}
    pin = {'path': '/frozen/price.json', 'sha256': p.PRICE_SHA}
    profile = {'schema': 'r163_execution_profile_plan_v1',
               'purpose': 'PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION', 'status': 'PREPARED_NOT_ADMITTED',
               'numerical_execution_authorized': False, 'full_screening_admitted': False,
               'ready_for_numerical_execution': False, 'blockers': sorted(p.PROFILE_GATES),
               'studies': {}, 'input_pins': {'accepted_prices': pin, 'studies': {}}}
    calendar = {'schema': 'r163_calendar_preparation_v1', 'purpose': 'PRICEFM_COMPLETE_GRID_CALENDAR_DIAGNOSTIC',
                'status': 'PREPARED_NOT_ADMITTED', 'scientific_admission': False,
                'old_prices_changed': False, 'old_grants_renewed': False,
                'studies': {}, 'gates': [{'name': 'joint_capacity', 'passed': False}],
                'input_pins': {'prices': pin, 'studies': {}}}
    for study, (tasks, branches, scenarios) in p.COUNTS.items():
        profile['studies'][study] = {'task_count': tasks, 'tasks': [{'name': study+str(i)} for i in range(tasks)],
            'joint_geometry_coverage': {'uncovered_count': tasks}}
        calendar['studies'][study] = {'task_count': tasks, 'branch_count': branches,
            'complete_scenarios': scenarios, 'scenarios': [{} for _ in range(scenarios)],
            'summary': {}, 'original_mandatory_reserved_CPU': 100,
            'original_available_science_CPU': 99, 'worst_reserved_CPU_fits': False}
        refs = {'preparation': {'sha256': study+'prep'}, 'configuration': {'sha256': study+'cfg'}}
        profile['input_pins']['studies'][study] = refs
        calendar['input_pins']['studies'][study] = {'preparation': refs['preparation'], 'config': refs['configuration']}
    complete = ['r'+str(i) for i in range(29)]
    health = {'schema': 'r163_initial_health_v1', 'census_errors': [], 'complete': complete,
              'remaining': ['r'+str(i) for i in range(29, 38)], 'complete_regions': 29, 'remaining_regions': 9,
              'as_of_PDT': '1970-01-01T00:01:40+00:00',
              'active_stage_progress': {'x': {'completed': 3, 'active': 1, 'pending': 2, 'stage_total': 6}},
              'active_stage_active': 1, 'active_stage_queued': 2, 'active_stage_remaining': 3}
    output = {'schema': 'r163_completed_saved_scalar_review_29_v1', 'complete_regions': complete,
              'aggregate_29_regions': {'primary_operator': 'cdf_pool_clipped', 'regions': 29, 'folds': 87,
                  'AQL': 2.02, 'qdesn_AQL': 2., 'relative_percent_vs_current_authority': 1.}}
    return dict(dispatch=dispatch, profile=profile, calendar=calendar, health=health, output=output)


class PreparationTests(unittest.TestCase):
    def test_prepared_dossier_never_authorizes_numerics_or_clock_extension(self):
        r = p.join(**packets(), now_epoch=p.OUTER_END+1)
        self.assertFalse(r['numerical_execution_authorized'])
        self.assertFalse(r['full_screening_admitted'])
        self.assertTrue(r['original_HB_clock']['expired'])
        self.assertFalse(r['original_HB_clock']['renewed'])
        self.assertEqual(r['original_HB_clock']['remaining_seconds_at_join'], 0)
        self.assertIsNone(r['health_snapshot']['whole_campaign_remaining_runs'])

    def test_forged_dispatch_or_profile_execution_flags_rejected(self):
        for role, key in [('dispatch', 'dispatch_authorized_by_this_diagnostic'),
                          ('profile', 'numerical_execution_authorized'), ('profile', 'full_screening_admitted'),
                          ('calendar', 'scientific_admission'), ('calendar', 'old_grants_renewed')]:
            v = packets(); v[role][key] = True
            with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_missing_study_tasks_or_branches_rejected(self):
        v = packets(); v['profile']['studies'].pop('FI')
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)
        v = packets(); v['profile']['studies']['FI']['tasks'][-1] = {'name': 'FI0'}
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)
        v = packets(); v['calendar']['studies']['DK2']['complete_scenarios'] -= 1
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_cross_source_price_or_geometry_identity_rejected(self):
        v = packets(); v['calendar']['input_pins']['prices'] = {'sha256': 'other'}
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)
        v = packets(); v['calendar']['input_pins']['studies']['FI']['config'] = {'sha256': 'other'}
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_missing_scientific_gate_cannot_be_silently_omitted(self):
        v = packets(); v['profile']['blockers'].pop()
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_health_task_arithmetic_or_cohort_mismatch_rejected(self):
        for role, key, value in [('health', 'active_stage_queued', 1),
                                 ('health', 'remaining_regions', 8), ('output', 'complete_regions', ['other'])]:
            v = packets(); v[role][key] = value
            with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_changed_primary_ratio_or_partial_fold_cohort_rejected(self):
        for key, value in [('primary_operator', 'mean_feature'), ('folds', 86),
                           ('relative_percent_vs_current_authority', 2.)]:
            v = packets(); v['output']['aggregate_29_regions'][key] = value
            with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_muscat_cannot_be_relabelled_jerez_dispatch(self):
        v = packets(); v['dispatch']['control_scope'] = 'JEREZ_R143'
        with self.assertRaises(ValueError): p.join(**v, now_epoch=101)

    def test_request_cannot_add_job_or_authority_roles(self):
        with self.assertRaises(ValueError):
            p.compile_request({'schema': 'r163_preparation_request_v1', 'purpose': 'PRICEFM_PREPARATION_EVIDENCE_JOIN',
                               'numerical_execution_authorized': True, 'inputs': {}})

    def test_atomic_publication_cannot_overwrite_or_follow_output_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/'dossier.json'; p.write_new(out, {'x': 1})
            before = out.read_bytes()
            with self.assertRaises(FileExistsError): p.write_new(out, {'x': 2})
            self.assertEqual(out.read_bytes(), before)
            alias = Path(directory)/'alias.json'; alias.symlink_to(out)
            with self.assertRaises(ValueError): p.write_new(alias, {'x': 3})


if __name__ == '__main__':
    unittest.main()
