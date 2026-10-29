"""Prepare training-contained calibration diagnostics from saved scalar evidence.

No prediction arrays, new losses, parameter selection, forecasting or fitting.
The recipe preserves the fixed operator and separates already exposed training
evidence from prospective chronological development assessment.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal

from . import profile_admission as admission
from .execution_profile_plan import write_new

SCHEMA = 'r164_calibration_diagnostic_request_v1'


def compile_protocol(request):
    admission.require(set(request) == {'schema', 'purpose', 'EE_initial_readout', 'EE_saved_analysis', 'LV_complete_readout'}
                      and request['schema'] == SCHEMA
                      and request['purpose'] == 'TRAINING_CONTAINED_CALIBRATION_PREPARATION',
                      'exact training-contained diagnostic request required')
    ee = admission.read_pin(request['EE_initial_readout'])
    admission.require(request['EE_saved_analysis']['sha256'] == ee['analysis']['sha256'],
                      'exact sealed original EE analysis required')
    ee_analysis = admission.read_pin(request['EE_saved_analysis'])
    lv = admission.read_pin(request['LV_complete_readout'])
    admission.require(ee.get('schema') == 'r155_complete_ee_interpretation_v1'
                      and ee.get('status') == 'COMPLETE_INITIAL_SCREEN_ONE_QUALIFIER'
                      and ee.get('official_selection') is False and ee.get('promotion') is False
                      and ee.get('arrays_opened') is False and ee.get('new_forecasts') == 0,
                      'complete exposed EE initial training interpretation required')
    admission.require(lv.get('status') == 'PASS_COMPLETE12_CALL_SAVED_ARRAY_ARITHMETIC'
                      and lv.get('training_diagnostic_exposed') is True
                      and lv.get('new_fits') == 0 and lv.get('new_forecasts') == 0
                      and lv.get('operator_selection_authorized') is False
                      and lv.get('promotion_authorized') is False and lv.get('confirmatory_claim') is False,
                      'complete exposed LV training comparison required')
    admission.require(type(lv.get('calls')) is int and lv['calls'] == 12 and lv.get('origin_clock_pairs') == 144,
                      'all original twelve LV calls and cohort support required')
    rows = ee.get('calibration_by_split', [])
    expected_packages = {'C0', ee['fixed_A'], ee['fixed_geometry_audit_B']}
    admission.require(len(expected_packages) == 3, 'C0, fixed A and fixed B must remain distinct')
    admission.require(len(rows) == 9 and {(r['package'], r['split']) for r in rows}
                      == {(p, s) for p in expected_packages for s in (1, 2, 3)},
                      'complete fixed C0/A/B by three-split diagnostic surface required')
    mode_rows = ee_analysis.get('selected_calibration_by_split', [])
    admission.require(len(mode_rows) == 18
                      and {(r['mode'], r['package'], r['split']) for r in mode_rows}
                      == {(m, p, s) for m in ('D', 'S') for p in expected_packages for s in (1, 2, 3)},
                      'all eighteen original mode/package/split rows required')
    primary = lv['comparison']['cdf_pool_clipped']
    return {
        'schema': 'r164_training_calibration_protocol_v1',
        'status': 'PREPARED_TRAINING_DIAGNOSTICS_ONLY_NOT_NUMERICALLY_ADMITTED',
        'input_pins': {'EE_initial_readout': request['EE_initial_readout'], 'EE_saved_analysis': request['EE_saved_analysis'],
                       'LV_complete_readout': request['LV_complete_readout']},
        'regions': ['EE', 'LV'], 'fixed_primary': 'cdf_pool_clipped',
        'horizon': 96, 'quantiles': [.10, .25, .45, .50, .55, .75, .90],
        'new_predictions': 0, 'new_fits': 0, 'new_losses': 0,
        'official_test_tuning_authorized': False, 'operator_selection_authorized': False,
        'production_change_authorized': False, 'numerical_execution_authorized': False,
        'EE_evidence_scope': 'Initial deterministic and matched seed0 training diagnostics; not a replacement for final three-seed disposition',
        'saved_scalar_evidence': {
            'EE_fixed_A': ee['fixed_A'], 'EE_fixed_geometry_audit_B': ee['fixed_geometry_audit_B'],
            'EE_mode_specific_comparisons': ee['comparison'],
            'EE_initial_interpretation_nine_rows_are_S_seed0_only': rows,
            'EE_all_eighteen_D_and_S_seed0_split_rows': mode_rows,
            'scalar_units': {'AQL': 'EUR/MWh', 'median_MAE': 'EUR/MWh', 'width_80': 'EUR/MWh',
                             'coverage_and_tail_rates': 'probabilities; original saved units unchanged'},
            'LV_primary': primary, 'LV_equal_split_rows': lv['equal_three_split_fold_metrics'],
            'LV_all_original_mechanism_comparisons': lv['comparison'],
        },
        'questions_before_any_calibration_fit': [
            'Compare exact parent, scaler, bank, source, origin, timestamp and UTC-hour support before attributing errors to a distribution shift.',
            'Tabulate both tails and median separately by original inner split, UTC physical hour, mode and the four fixed24-step horizon quarters.',
            'Retain sample support and overlapping-origin/window counts; forecast paths and algorithmic seeds are not independent datasets.',
            'Keep deterministic and stochastic EE calibration diagnoses separate; do not replace frozen A/B nomination or seed qualification with coverage flags.',
            'Use the LV split-level direction reversals to test whether a conditional location mechanism is supported; near80% pooled coverage alone is insufficient.',
        ],
        'prospective_chronological_contract': {
            'fit_data': 'Previously available residuals wholly inside the original training partition only',
            'assessment_data': 'Later predeclared training-contained origins; previously exposed readouts remain development evidence',
            'leakage_barrier': 'Every calibration-training target timestamp must precede every assessment forecast origin; embargo complete overlapping96-step horizons.',
            'required_identity_freeze': ['source', 'parent', 'scaler', 'bank', 'origins', 'physical_UTC_hour', 'quantiles', 'RNG', 'operator', 'hypothesis', 'cohort_boundaries'],
            'objective': 'Unchanged equal-three-split AQL; report both-tail, coverage, median and width diagnostics separately.',
            'new_hypothesis_or_threshold_selection': 'Requires a prospective reviewed training protocol before evaluating additional candidate losses.',
            'numerical_gate': 'Separate finite source/resource/funding/whole-calendar authority; no official-test parameter selection or automatic promotion.',
        },
        'interpretation': {
            'LV_uniform_inflation_supported': False,
            'LV_pooled_coverage_implies_split_calibration': False,
            'EE_AQL_gain_implies_calibration_gain': False,
            'causal_shift_or_speedup_established': False,
            'whole_surface_objective_unchanged': True,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True)
    parser.add_argument('--request-sha256', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    admission.require(os.sched_getaffinity(0) == {31}, 'administrative CPU31 required')
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10)); signal.alarm(120)
    request = admission.read_pin({'path': args.request, 'sha256': args.request_sha256})
    result = compile_protocol(request)
    result['request_pin'] = {'path': args.request, 'sha256': args.request_sha256}
    result['compiler_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    write_new(Path(args.output), result)
    print(json.dumps({'status': result['status'], 'output': args.output}))


if __name__ == '__main__':
    main()
