"""Join pinned PriceFM preparation evidence. This CLI cannot launch any work."""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import tempfile
import time
from .dispatch_diagnosis import physical, pinned_json, require

SCHEMA = 'r163_preparation_dossier_v1'
OUTER_END = 1793259235.5743458
PRICE_SHA = '218e4003894082df820bc41850d791ac4a74cce92bf645b26ca329fe97079e3a'
COUNTS = {'FI': (240, 76, 836), 'DK2': (252, 80, 880)}
PROFILE_GATES = {
    'distinct_finite_numerical_profile_authority_and_funding',
    'reviewed_instrumented_executor_source_and_private_accounting_tests',
    'fresh_source_input_runtime_native_library_and_RNG_attestation',
    'whole_component_numerical_output_parity',
    'complete_joint_geometry_mode_clock_seed_measurement_or_original_fallback',
    'worst_scientific_geometry_memory_and_aggregate_capacity',
    'complete_calendar_optional_branch_and_joint_controller_certificate',
    'fresh_resource_ownership_and_whole_execution_window',
    'separate_accepted_price_certificate_before_any_repricing',
}


def integer(v):
    return type(v) is int and v >= 0


def join(dispatch, profile, calendar, health, output, *, now_epoch=None):
    """Validate compatible preparation roles and retain every unproved gate."""
    now_epoch = time.time() if now_epoch is None else now_epoch
    require(type(now_epoch) in (int, float) and math.isfinite(now_epoch), 'finite current epoch required')
    require(dispatch.get('schema') == 'r163_dispatch_diagnosis_v1' and
            dispatch.get('purpose') == 'PRICEFM_READONLY_DISPATCH_DIAGNOSIS' and
            dispatch.get('control_scope') == 'MUSCAT_OWNER6_ONLY' and
            dispatch.get('not_a_Jerez_R143_dispatch_observation') is True and
            dispatch.get('dispatch_authorized_by_this_diagnostic') is False and
            dispatch.get('numerical_execution_authorized') is False,
            'read-only host-specific dispatch diagnosis required')
    require(profile.get('schema') == 'r163_execution_profile_plan_v1' and
            profile.get('purpose') == 'PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION' and
            profile.get('status') == 'PREPARED_NOT_ADMITTED' and
            profile.get('numerical_execution_authorized') is False and
            profile.get('full_screening_admitted') is False and
            profile.get('ready_for_numerical_execution') is False and
            set(profile.get('blockers', [])) == PROFILE_GATES,
            'complete non-admitting profile preparation required')
    require(calendar.get('schema') == 'r163_calendar_preparation_v1' and
            calendar.get('purpose') == 'PRICEFM_COMPLETE_GRID_CALENDAR_DIAGNOSTIC' and
            calendar.get('status') == 'PREPARED_NOT_ADMITTED' and calendar.get('scientific_admission') is False and
            calendar.get('old_prices_changed') is False and calendar.get('old_grants_renewed') is False,
            'non-admitting complete-grid calendar preparation required')
    require(set(profile.get('studies', {})) == set(calendar.get('studies', {})) == set(COUNTS),
            'both complete scientific study universes required')
    ppin = profile.get('input_pins', {}).get('accepted_prices', {})
    cpin = calendar.get('input_pins', {}).get('prices', {})
    require(ppin.get('sha256') == cpin.get('sha256') == PRICE_SHA, 'same original accepted prices required')
    studies = {}
    for study, (tasks, branches, scenarios) in COUNTS.items():
        p, c = profile['studies'][study], calendar['studies'][study]
        names = [t['name'] for t in p.get('tasks', [])]
        require(p.get('task_count') == c.get('task_count') == len(names) == len(set(names)) == tasks,
                'complete unique task coverage required: ' + study)
        require(c.get('branch_count') == branches and c.get('complete_scenarios') == scenarios and
                len(c.get('scenarios', [])) == scenarios, 'complete original branch/scenario coverage required')
        pp = profile['input_pins']['studies'][study]
        cp = calendar['input_pins']['studies'][study]
        require(pp['preparation']['sha256'] == cp['preparation']['sha256'] and
                pp['configuration']['sha256'] == cp['config']['sha256'], 'cross-packet scientific identity mismatch')
        studies[study] = {
            'tasks': tasks, 'branches': branches, 'calendar_scenarios': scenarios,
            'joint_geometry_uncovered': p['joint_geometry_coverage']['uncovered_count'],
            'calendar_summary': c['summary'],
            'original_mandatory_reserved_CPU': c['original_mandatory_reserved_CPU'],
            'original_available_science_CPU': c['original_available_science_CPU'],
            'original_mandatory_CPU_funded': c['worst_reserved_CPU_fits'],
        }
    require(health.get('schema') in {'r163_initial_health_v1', 'r163_final_health_v1'} and
            not health.get('census_errors'), 'source/seal-validated R163 health snapshot required')
    completed, remaining = health.get('complete'), health.get('remaining')
    require(type(completed) is list and type(remaining) is list and
            len(completed) == len(set(completed)) == health.get('complete_regions') and
            len(remaining) == len(set(remaining)) == health.get('remaining_regions') and
            not set(completed).intersection(remaining) and len(completed) + len(remaining) == 38,
            'complete disjoint 38-region census required')
    stages = health.get('active_stage_progress', {})
    for row in stages.values():
        require(all(integer(row.get(k)) for k in ('completed', 'active', 'pending', 'stage_total')) and
                row['completed'] + row['active'] + row['pending'] == row['stage_total'], 'stage arithmetic differs')
    active = sum(v['active'] for v in stages.values()); queued = sum(v['pending'] for v in stages.values())
    require(active == health['active_stage_active'] and queued == health['active_stage_queued'] and
            active + queued == health['active_stage_remaining'], 'health remaining arithmetic differs')
    require(output.get('schema') == 'r163_completed_saved_scalar_review_29_v1' and
            set(output.get('complete_regions', [])) == set(completed), 'output and health cohorts differ')
    aggregate = output.get('aggregate_29_regions', {})
    require(aggregate.get('primary_operator') == 'cdf_pool_clipped' and aggregate.get('regions') == len(completed) and
            aggregate.get('folds') == 3 * len(completed), 'fixed primary and full three-fold cohort required')
    require(aggregate.get('qdesn_AQL', 0) > 0 and aggregate.get('AQL', 0) > 0, 'positive saved aggregate losses required')
    gap = (aggregate['AQL'] / aggregate['qdesn_AQL'] - 1) * 100
    require(math.isclose(gap, aggregate['relative_percent_vs_current_authority'], rel_tol=0, abs_tol=1e-12),
            'ratio-of-means aggregate differs')
    gates = [{'gate': name, 'passed': False, 'role': 'prospective_numerical_profile'} for name in sorted(PROFILE_GATES)]
    for g in calendar.get('gates', []):
        require(type(g.get('passed')) is bool and isinstance(g.get('name'), str), 'explicit typed calendar gates required')
        gates.append({'gate': g['name'], 'passed': g['passed'], 'role': 'calendar_diagnostic_assumptions_only'})
    health_time = datetime.datetime.fromisoformat(health['as_of_PDT']).timestamp()
    require(health_time <= now_epoch + 2, 'future health snapshot rejected')
    return {
        'schema': SCHEMA, 'purpose': 'PRICEFM_PREPARATION_EVIDENCE_ONLY',
        'status': 'PREPARATION_IMPLEMENTED_SCIENTIFIC_EXECUTION_GATED',
        'numerical_execution_authorized': False, 'full_screening_admitted': False,
        'production_repair_admitted': False, 'old_authority_reused': False,
        'prepared_studies': studies, 'gates': gates,
        'health_snapshot': {'as_of_PDT': health['as_of_PDT'], 'age_seconds': max(0, now_epoch - health_time),
            'complete_regions': len(completed), 'remaining_regions': len(remaining),
            'active_records': active, 'queued_or_withheld_records': queued, 'current_remaining_records': active + queued,
            'whole_campaign_remaining_runs': None, 'future_graphs_and_repairs_additional': True},
        'dispatch_snapshot': {k: dispatch[k] for k in ('status', 'control_scope', 'observed_epoch', 'unresolved')},
        'saved_primary_output': {'regions': len(completed), 'folds': aggregate['folds'],
            'AQL': aggregate['AQL'], 'qdesn_AQL': aggregate['qdesn_AQL'], 'relative_percent': gap,
            'descriptive_completion_selected_subset': True, 'promotion_authorized': False},
        'original_HB_clock': {'expires_epoch': OUTER_END, 'remaining_seconds_at_join': max(0, OUTER_END - now_epoch),
            'expired': now_epoch >= OUTER_END, 'renewed': False, 'new_window_admitted': False},
        'next_actions': [
            {'host': 'Muscat', 'action': 'Resolve exact source-observed provenance gap; require complete census and original owner reconciliation.', 'priority': 1},
            {'host': 'Muscat/Jerez', 'action': 'Continue original admitted queues under each host-specific owner and certificate barriers.', 'priority': 2},
            {'host': 'Muscat CPU31', 'action': 'Use these pinned protocols to review a separate instrumented numerical executor and finite admission packet.', 'priority': 3},
            {'host': 'Hummingbird', 'action': 'Run actual-component profiling only after source, funding, ownership, parity/memory protocol and whole-window admission.', 'priority': 4},
            {'host': 'Hummingbird', 'action': 'Full predeclared screening requires complete feasible scientific prices, optional calendars and joint controller proof.', 'priority': 5},
        ],
        'limits': ['This dossier contains no numerical commands and cannot stage, submit, release, retry or alter jobs.',
                   'A prepared measurement contract is not measured scientific evidence.',
                   'Muscat owner6 visibility does not determine Jerez R143 dispatch.',
                   'All snapshots are dated; use fresh original observers before any later action.'],
    }


def compile_request(request):
    require(type(request) is dict and set(request) == {'schema', 'purpose', 'numerical_execution_authorized', 'inputs'},
            'exact evidence-join request required')
    require(request['schema'] == 'r163_preparation_request_v1' and
            request['purpose'] == 'PRICEFM_PREPARATION_EVIDENCE_JOIN' and
            request['numerical_execution_authorized'] is False, 'evidence join is not numerical authority')
    refs = request['inputs']
    require(type(refs) is dict and set(refs) == {'dispatch', 'profile', 'calendar', 'health', 'output'},
            'all five exact preparation roles required')
    evidence = {role: pinned_json(ref) for role, ref in refs.items()}
    validation = verify_source_grounded(evidence['profile'], evidence['calendar'])
    result = join(**evidence)
    result['source_grounded_validation'] = validation
    result['input_pins'] = refs
    return result


def verify_source_grounded(profile, calendar):
    """Rebuild metadata contracts and check witnesses, without searching or numerics.

    A resigned JSON file cannot become a passing witness merely by asserting
    counts, flags or old hash strings. Scientific source is read as text only.
    """
    from . import execution_profile_plan as profiles
    from . import calendar_plan as calendars
    compiler = Path(profiles.__file__).resolve()
    require(profile.get('compiler_source_pin') == {'path': str(compiler),
            'sha256': hashlib.sha256(profiles.bounded_bytes(compiler)).hexdigest()},
            'profile compiler differs from the reviewed current preparation source')
    request = pinned_json(profile['request_pin'])
    expected = profiles.compile_request(request)
    supplied = {k: v for k, v in profile.items() if k not in {'request_pin', 'compiler_accounting', 'compiler_source_pin'}}
    require(supplied == expected, 'profile preparation differs from complete source-grounded reconstruction')
    refs = calendar['input_pins']
    require(set(refs) == {'schema', 'purpose', 'studies', 'prices', 'assumptions'} and
            refs['schema'] == 'r163_calendar_inputs_v1' and
            refs['purpose'] == 'PRICEFM_METADATA_CALENDAR_PREPARATION', 'exact source-grounded calendar inputs required')
    require(refs['prices']['sha256'] == PRICE_SHA and set(refs['studies']) == set(COUNTS),
            'original common prices and joint study universe required')
    prices = pinned_json(refs['prices']); models = {}
    for study, pins in refs['studies'].items():
        require(set(pins) == {'preparation', 'config'}, 'exact original calendar metadata pins required')
        original = expected['input_pins']['studies'][study]
        require(pins['preparation']['sha256'] == original['preparation']['sha256'] and
                pins['config']['sha256'] == original['configuration']['sha256'], 'calendar scientific inputs differ')
        models[study] = calendars.adapt(pinned_json(pins['preparation']), pinned_json(pins['config']),
                                       prices['studies'][study]['loss_blind_price_draft'], study)
    calendars.verify_preparation(calendar, models, refs['assumptions'])
    require(calendar['joint_calendar']['certificate'] is False and
            calendar['joint_calendar']['independent_single_study_calendars_only'] is True,
            'independent study calendars are not a joint capacity certificate')
    return {'status': 'PASS_RECONSTRUCTED_PROFILE_AND_VERIFIED_CALENDAR_WITNESSES',
            'profile_recompiled_from_frozen_source_and_metadata': True,
            'calendar_search_repeated': False, 'complete_original_calendar_scenarios_verified': 1716,
            'joint_shared_worker_capacity_proven': False, 'scientific_admission': False}


def write_new(path, value):
    path = physical(path); require(path.suffix == '.json', 'JSON dossier required')
    raw = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()
    require(len(raw) <= 16 * 1024**2, 'bounded dossier required')
    fd, tmp = tempfile.mkstemp(prefix='.preparation_', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        physical(path.parent); os.link(tmp, path, follow_symlinks=False)
    finally:
        os.unlink(tmp)
    return hashlib.sha256(raw).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True); parser.add_argument('--request-sha256', required=True)
    parser.add_argument('--output', required=True); args = parser.parse_args(argv)
    require(os.sched_getaffinity(0) == {31}, 'administrative CPU31 required')
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10)); signal.alarm(60)
    result = compile_request(pinned_json({'path': args.request, 'sha256': args.request_sha256}))
    result['request_pin'] = {'path': args.request, 'sha256': args.request_sha256}
    sha = write_new(args.output, result)
    print(json.dumps({'status': result['status'], 'output': args.output, 'sha256': sha,
                      'numerical_execution_authorized': False}))


if __name__ == '__main__':
    main()
