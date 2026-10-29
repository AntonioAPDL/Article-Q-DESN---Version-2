"""Prospective actual-component profile preparation; metadata only, never authority.

The compiler reads pinned JSON and Python text. It cannot submit or execute a
profile, inspect model arrays, revise prices, or override a scientific gate.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import sys
import tempfile
import time

SCHEMA = 'r163_execution_profile_plan_v1'
REQUEST_SCHEMA = 'r163_execution_profile_request_v1'
PURPOSE = 'PROSPECTIVE_ACTUAL_COMPONENT_PROFILE_PREPARATION'
ACCEPTED_PRICES_SHA256 = '218e4003894082df820bc41850d791ac4a74cce92bf645b26ca329fe97079e3a'
CLOCKS = [0, 24, 48, 72]
QUANTILES = [.1, .25, .45, .5, .55, .75, .9]
DIMENSIONS = ('m_y', 'm_x', 'depth', 'input_fan_in', 'recurrent_sparsity')
COUNTS = {'FI': (20, 19, 240), 'DK2': (21, 20, 252)}
CANONICAL = {
    'FI': {'region': 'FI', 'preparation': '1f5de78553253cf2df4727c12bff6ab0789ca018f13db32df3e6a7e79b60d96c',
           'configuration': 'f98356e648e83bbb88f64de8e188f2c301429911bf3ab79e44625528fe3a77bd',
           'head': 'cba0b6c861f20ebdffcd970d59b0fa38afd80a42',
           'cost_plan': '86f3c2264669329e2c24c267c21a462c00072c3f8699aec7a80824b5ce6aca71',
           'timings': 'e6b6053a33a80c0919e283a9563eed5c1dc544473087fddc41c31678edd44839'},
    'DK2': {'region': 'DK_2', 'preparation': '5fa9bcefe7a04250b4fd144e67e5775493fb5d536936f9ba7f5a3782995a32d5',
            'configuration': 'c26e8ddfb90c0855fd91116851796cc34b51db077cfcaf532d6f560d4758d90e',
            'head': '57f9bc8931b67fbafd68c894599ac7c0ca519fab',
            'cost_plan': 'ccb12d26611f8be87b4efc1b29bc5022d6e8c78f69696c6b760a520b14bc0132',
            'timings': '1ed5581f962cdebe5a3401452b538a10e8f29b351677726c16454891fa53d95c'},
}
SOURCE_HASHES = {
    'prefix': 'db374dffc5cbfbdbeb801281a72d4d93f462b250763220b0865c56e4aa8cabd9',
    'benchmark': '43220d303106148d86031962a9694f0be90cdaed1722e85bbaf8d1ef5f5844c2',
    'science': '3db567ec7f98b70449740a285f34f1a5b733ab51f7b7691f2644e8e7a5dba319',
    'environment': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1',
}
BLOCKERS = [
    'distinct_finite_numerical_profile_authority_and_funding',
    'reviewed_instrumented_executor_source_and_private_accounting_tests',
    'fresh_source_input_runtime_native_library_and_RNG_attestation',
    'whole_component_numerical_output_parity',
    'complete_joint_geometry_mode_clock_seed_measurement_or_original_fallback',
    'worst_scientific_geometry_memory_and_aggregate_capacity',
    'complete_calendar_optional_branch_and_joint_controller_certificate',
    'fresh_resource_ownership_and_whole_execution_window',
    'separate_accepted_price_certificate_before_any_repricing',
]
INSTRUMENTS = (
    ('startup_and_authority', 'prefix', 'run_component', 'allocation=require_compute()', True),
    ('input_verification', 'prefix', 'run_component', 'prep,config,resolver=b.load_staged', True),
    ('runtime_and_adapter_setup', 'prefix', 'run_component', 'adapter=b.frozen_adapter', True),
    ('parent_context_load', 'science', '_context', 'def _context(', True),
    ('all_parent_preflight_comparison', 'benchmark', 'timing_panel', 'preflight = adapter.preflight', False),
    ('arithmetic', 'prefix', 'component_loop', 'prediction,truth,audit=adapter.predict', True),
    ('retained_array_conversion', 'prefix', 'component_loop', 'arrays=adapter.retained_arrays', True),
    ('chunk_validation', 'prefix', 'component_loop', 'validator(task,arrays', True),
    ('chunk_serialization', 'prefix', 'component_loop', 'serializer(folder/', True),
    ('concatenation_full_validation_metrics', 'prefix', 'component_loop', 'arrays=concatenate(parts)', True),
    ('full_serialization', 'prefix', 'component_loop', 'serializer(output/', True),
    ('sealing_and_final_accounting', 'prefix', 'run_component', "seal_directory(output,\"completed_evidence.json\"", True),
    ('cleanup', 'prefix', 'component_loop', 'adapter.cleanup(context)', True),
)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def integer(value, positive=False):
    return type(value) is int and value >= (1 if positive else 0)


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def sha(value):
    return hashlib.sha256(value).hexdigest()


def identity(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode())


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def decode_json(data):
    def finite_float(token):
        value = float(token)
        require(math.isfinite(value), 'nonfinite JSON float')
        return value
    return json.loads(data, object_pairs_hook=unique_object, parse_float=finite_float,
                      parse_constant=lambda v: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def physical(path):
    p = Path(path)
    require(p.is_absolute() and '..' not in p.parts, 'absolute physical path required')
    require(not any(q.is_symlink() for q in (p, *p.parents)), 'symlink path prohibited')
    return p


def bounded_bytes(path):
    p = physical(path)
    before = p.stat()
    require(stat.S_ISREG(before.st_mode) and before.st_size <= 16 * 1024**2, 'bounded regular metadata required')
    fields = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        require(fields(os.fstat(fd)) == fields(before), 'metadata changed before open')
        with os.fdopen(fd, 'rb', closefd=False) as handle:
            data = handle.read(16 * 1024**2 + 1)
        require(fields(os.fstat(fd)) == fields(before), 'metadata changed during read')
    finally:
        os.close(fd)
    require(len(data) == before.st_size and fields(p.stat()) == fields(before), 'metadata changed after read')
    physical(p)
    return data


def read_pin(ref, source=False):
    require(type(ref) is dict and set(ref) == {'path', 'sha256'}, 'exact metadata pin required')
    require(type(ref['path']) is str and type(ref['sha256']) is str
            and re.fullmatch('[0-9a-f]{64}', ref['sha256']), 'valid path/hash pin required')
    require(Path(ref['path']).suffix == ('.py' if source else '.json'), 'JSON/source text only; numerical payloads prohibited')
    data = bounded_bytes(ref['path'])
    require(sha(data) == ref['sha256'], 'changed metadata/source pin')
    return data.decode() if source else decode_json(data)


def pin_only(ref):
    return {k: ref[k] for k in ('path', 'sha256')}


def instrumentation(sources, pins):
    result = []
    for phase, role, entry, anchor, component in INSTRUMENTS:
        nodes = [n for n in ast.parse(sources[role]).body if isinstance(n, ast.FunctionDef) and n.name == entry]
        require(len(nodes) == 1, 'missing unique lifecycle entry: ' + entry)
        node = nodes[0]
        lines = sources[role].splitlines()
        matches = [i + 1 for i in range(node.lineno - 1, node.end_lineno) if anchor in lines[i]]
        require(bool(matches), 'lifecycle instrumentation anchor missing: ' + phase)
        result.append(dict(phase=phase, source=pin_only(pins[role]), entry=entry,
                           function_ast_sha256=sha(ast.dump(node, include_attributes=False).encode()),
                           first_line=node.lineno, last_line=node.end_lineno, anchor_lines=matches,
                           in_actual_component=component, measure_CPU_wall_IO_RSS=True))
    return result


def environment_from_source(text):
    values = {}
    for n in ast.parse(text).body:
        if isinstance(n, ast.Assign):
            for target in n.targets:
                if isinstance(target, ast.Name) and target.id in {'THREAD_ENV', 'REFERENCE_NUMERICAL_ENV'}:
                    values[target.id] = ast.literal_eval(n.value)
    require(set(values) == {'THREAD_ENV', 'REFERENCE_NUMERICAL_ENV'}, 'frozen numerical environment missing')
    require(all(v == '1' for v in values['THREAD_ENV'].values()), 'one-thread environment required')
    return {**values['THREAD_ENV'], **values['REFERENCE_NUMERICAL_ENV']}


def build_study(study, prep, config, timing, prices):
    """Pure metadata construction. Caller supplies already verified frozen bytes."""
    require(study in COUNTS, 'only original FI/DK2 studies supported')
    packages_n, geometries_n, tasks_n = COUNTS[study]
    region = CANONICAL[study]['region']
    packages = prep['packages']; by = {p['package_id']: p for p in packages}
    require(len(packages) == len(by) == packages_n and 'C0' in by, 'complete original packages required')
    require(len({p['candidate_id'] for p in packages}) == geometries_n, 'complete original geometry universe required')
    require(prep['region'] == config['region'] == region and prep['control'] == config['control'] == 'C0', 'region/control changed')
    require(prep['source']['head'] == CANONICAL[study]['head'], 'original source head changed')
    require(prep['new_model_fits'] == 0 and type(prep['new_model_fits']) is int
            and prep['posterior_updated'] is False and prep['test_opened'] is False, 'training-only frozen Normal preparation required')
    require(config['clock_offsets_steps'] == CLOCKS and all(type(x) is int for x in config['clock_offsets_steps'])
            and config['horizon_steps'] == 96 and type(config['horizon_steps']) is int
            and config['paths'] == 100 and type(config['paths']) is int
            and config['quantiles'] == QUANTILES, 'original clocks/H96/paths/quantiles changed')
    require(all(config[k] is False for k in ('AL_authorized', 'official_evaluation_authorized', 'promotion_authorized', 'test_used_for_selection')),
            'preparation cannot authorize expansion')
    require(timing['status'] == 'COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION'
            and timing['arithmetic_calls'] == 18 and len(timing['rows']) == 16
            and timing['full_prefix_admitted'] is False and timing['no_scientific_selection'] is True,
            'complete original non-admitting timing panel required')
    profile = timing['actual_reference_numerical_profile']
    require(profile['enabled'] is True and type(profile['native_library_sha256']) is dict
            and bool(profile['native_library_sha256']) and all(re.fullmatch('[0-9a-f]{64}', v)
                for v in profile['native_library_sha256'].values()), 'accepted native numerical profile required')
    estimates = prices['task_estimates']; tasks = prep['tasks']
    names = [t['name'] for t in tasks]
    keys = [(t['package_id'], t['split'], t['mode'], t['seed_index']) for t in tasks]
    expected = {(p, split, mode, seed) for p in by for split in (1, 2, 3)
                for mode, seed in [('D', 0), ('S', 0), ('S', 1), ('S', 2)]}
    require(len(tasks) == len(set(names)) == len(set(keys)) == tasks_n and set(keys) == expected
            and set(names) == set(estimates), 'complete unique original D/S0/S1/S2 task grid required')
    out = []; gaps = []; clock_gaps = []; mode_seed_gaps = []; imported = 0
    for task in tasks:
        spec = task['spec']; package = by[task['package_id']]
        require(task['region'] == region and task['candidate_id'] == package['candidate_id']
                and task['p'] == package['p'] and spec == package['spec'], 'task/package geometry changed')
        require(integer(task['p'], True) and all(number(spec[k]) for k in DIMENSIONS), 'finite nonboolean joint dimensions required')
        require(task['clock_offsets_steps'] == CLOCKS and all(type(x) is int for x in task['clock_offsets_steps'])
                and task['quantiles'] == QUANTILES and task['horizon_steps'] == 96
                and type(task['horizon_steps']) is int and task['paths'] == 100 and type(task['paths']) is int,
                'complete task clock/quantile/path surface required')
        require(integer(task['split'], True) and integer(task['seed_index'])
                and type(task['forecast_seed']) is int and task['test_opened'] is False
                and task['posterior_updated'] is False and type(task['new_model_fits']) is int
                and task['new_model_fits'] == 0, 'task RNG/scientific role changed')
        origins = task['daily_origin_positions']; timestamps = task['origin_timestamps']
        require(type(origins) is list and bool(origins) and all(integer(v) for v in origins)
                and len(origins) == len(set(origins)) and origins == sorted(origins), 'complete ordered origins required')
        require(set(timestamps) == {str(c) for c in CLOCKS}
                and all(type(timestamps[str(c)]) is list and len(timestamps[str(c)]) == len(origins) for c in CLOCKS),
                'complete four-clock origin timestamps required')
        price = estimates[task['name']]
        require(integer(price['reserved_CPU']) and integer(price['reserved_wall'])
                and price['reserved_CPU'] <= price['reserved_wall']
                and (task['reuse'] is None or type(task['reuse']) is dict)
                and type(price['imported']) is type(task['reuse']) and price['imported'] == task['reuse'],
                'original reservation/import identity changed')
        if task['reuse']:
            require(price['reserved_CPU'] == price['reserved_wall'] == 0, 'imported task cannot acquire new charges')
            imported += 1
        candidates = [(i, row) for i, row in enumerate(timing['rows']) if row['mode'] == task['mode']]
        require(bool(candidates), 'both original modes must be represented')
        for _, row in candidates:
            require(integer(row['p'], True) and all(number(row['spec'][k]) for k in DIMENSIONS), 'invalid timing joint geometry')
        dominating = [i for i, row in candidates if row['p'] >= task['p']
                      and row['spec']['feature_policy'] == spec['feature_policy']
                      and all(row['spec'][k] >= spec[k] for k in DIMENSIONS)]
        clocks = sorted({row['clock_offset_steps'] for _, row in candidates})
        if not dominating:
            gaps.append(task['name'])
        if set(CLOCKS) - set(clocks):
            clock_gaps.append(task['name'])
        if task['seed_index'] != 0 or task['split'] != 3:
            mode_seed_gaps.append(task['name'])
        out.append(dict(name=task['name'], package=task['package_id'], candidate_id=task['candidate_id'],
            split=task['split'], mode=task['mode'], seed_index=task['seed_index'],
            task_sha256=identity(task), scientific_identity_sha256=task['scientific_identity_sha256'],
            geometry={'p': task['p'], 'feature_policy': spec['feature_policy'], **{k: spec[k] for k in DIMENSIONS}},
            RNG_identity_sha256=identity({k: task[k] for k in ('forecast_seed', 'seed_index', 'spec', 'daily_origin_positions', 'origin_timestamps')}),
            complete_origin_clock_identity_sha256=identity({'origins': origins, 'timestamps': timestamps}),
            parent_scaler_bank_identity_sha256=identity({k: task[k] for k in ('parent_fit', 'parent_seal_sha256', 'parent_input_sha256', 'scaler_path', 'scaler_sha256', 'bank')}),
            origin_clock_windows=4 * len(origins), clocks=CLOCKS, original_reserved_CPU=price['reserved_CPU'],
            original_reserved_wall=price['reserved_wall'], imported=bool(task['reuse']),
            measurement_role='REFERENCE_ONLY_RETAINED_REUSE' if task['reuse'] else 'PROSPECTIVE_WHOLE_COMPONENT_COVERAGE',
            original_joint_dominators=dominating, original_mode_clock_coverage=clocks))
    return dict(region=region, task_count=tasks_n, package_count=packages_n, geometry_count=geometries_n,
        imported_reference_count=imported, tasks=out,
        joint_geometry_coverage={'uncovered_tasks': gaps, 'uncovered_count': len(gaps),
            'reason': 'no joint p/m_y/m_x/depth/input_fan_in/recurrent_sparsity dominator within mode and feature policy',
            'original_fallback_preserved': True, 'old_panel_missing_clock_coverage_tasks': clock_gaps,
            'old_panel_no_exact_seed_split_measurement_tasks': mode_seed_gaps,
            'prospective_coverage_rule': 'Every original task is explicit; future measured rows may cover joint-dominated tasks only under the unchanged reviewed rule. No task or clock is dropped.'},
        original_price_certificate=prices, original_prices_revised=False,
        numerical_environment_evidence=profile,
        source_ledger_sha256=identity(prep['source_sha256']), input_ledger_sha256=identity(prep['input_sha256']),
        input_payloads_rehashed=False, future_compute_must_rehash_complete_ledgers=True)


def compile_request(request):
    require(type(request) is dict and set(request) == {'schema', 'purpose', 'numerical_execution_authorized',
            'full_screening_admitted', 'studies', 'accepted_prices', 'source_pins'}, 'exact preparation request schema required')
    require(request['schema'] == REQUEST_SCHEMA and request['purpose'] == 'METADATA_ONLY_PROSPECTIVE_EXECUTION_PROFILE'
            and request['numerical_execution_authorized'] is False and request['full_screening_admitted'] is False,
            'metadata preparation is not numerical authority')
    require(set(request['studies']) == set(COUNTS) and set(request['source_pins']) == set(SOURCE_HASHES),
            'complete joint studies and source closure required')
    sources = {}
    for role, ref in request['source_pins'].items():
        require(ref.get('sha256') == SOURCE_HASHES[role], 'accepted scientific source changed: ' + role)
        sources[role] = read_pin(ref, source=True)
    require(request['accepted_prices'].get('sha256') == ACCEPTED_PRICES_SHA256, 'original accepted price certificate changed')
    prices = read_pin(request['accepted_prices'])
    require(prices['original_caps'] == {'assessment_CPU_each': 1800, 'joint_controller_CPU': 1800, 'study_CPU_each': 32400}
            and prices['full_screening_admitted'] is False, 'original ceilings/non-admission changed')
    result = {}; pins = {'accepted_prices': request['accepted_prices'], 'studies': {}}
    for study, refs in request['studies'].items():
        require(type(refs) is dict and set(refs) == {'cost_plan', 'timings'}, 'exact original study evidence refs required')
        require(all(refs[k].get('sha256') == CANONICAL[study][k] for k in refs), 'accepted cost-plan/timing evidence changed')
        plan = read_pin(refs['cost_plan']); timing = read_pin(refs['timings'])
        require(plan['study'] == study, 'study/cost evidence role changed')
        prep_ref = pin_only(plan['canonical_preparation']); cfg_ref = plan['canonical_config']
        require(prep_ref['sha256'] == CANONICAL[study]['preparation']
                and cfg_ref['sha256'] == CANONICAL[study]['configuration'], 'canonical frozen preparation/configuration changed')
        prep = read_pin(prep_ref); config = read_pin(cfg_ref)
        require(prep['config_sha256'] == cfg_ref['sha256'], 'preparation/configuration pin mismatch')
        result[study] = build_study(study, prep, config, timing, prices['studies'][study]['loss_blind_price_draft'])
        pins['studies'][study] = {**refs, 'preparation': prep_ref, 'configuration': cfg_ref}
    environment = environment_from_source(sources['environment'])
    require(all(all(v == environment[k] for k, v in s['numerical_environment_evidence']['environment'].items())
                for s in result.values()), 'accepted numerical environment differs')
    return dict(schema=SCHEMA, purpose=PURPOSE, status='PREPARED_NOT_ADMITTED',
        numerical_execution_authorized=False, full_screening_admitted=False, ready_for_numerical_execution=False,
        new_model_fits=0, new_forecasts=0, old_scope_reused=False, old_charges_refunded=False,
        source_pins=request['source_pins'], input_pins=pins, studies=result,
        instrumentation_map=instrumentation(sources, request['source_pins']),
        lifecycle_measurement_contract={'measure': ['whole process wall/CPU', 'aggregate parent and fresh numerical child CPU',
            'disjoint phase CPU/wall', 'proc IO counters', 'rusage/max RSS', 'affinity/cgroup/physical core', 'all seals and failures'],
            'startup_wall_included': True, 'all_parent_preflight_is_separate_panel_comparison_only': True,
            'no_all_parent_preflight_added_to_ordinary_component': True,
            'parent_plus_child_accounting': 'Charge each Slurm primary allocation once. Steps and child counters attribute that charge, never add duplicate totals. Retain failed/uncollected/reserved charges; no refund.',
            'phase_accounting': 'Explicit nonoverlapping intervals plus whole-lifecycle total; retain residual unattributed time. Never call residual I/O or subtract it from frozen evidence.'},
        storage_comparisons=[{'name': 'DIRECT_RETAINED_SOURCE', 'new_scratch_copy': False, 'cache_state': 'UNKNOWN'},
            {'name': 'AMORTIZED_OWNED_PRIVATE_SCRATCH', 'new_scratch_copy': True, 'cache_state': 'UNKNOWN',
             'copy_hash_cleanup_CPU_wall_included': True, 'source_immutable': True,
             'reuse_count_prospectively_fixed': True, 'single_pass_speedup_assumed': False,
             'cleanup': 'Only fresh owned tree with exact marker/inode proof; retained source never removed.'}],
        parity_requirements={'arithmetic_RNG_origin_clock_order_unchanged': True, 'fresh_component_children': True,
            'required_environment': environment, 'native_libraries': 'Exact accepted per-study native-library hash maps; fresh runtime attestation required',
            'full_arrays': 'Same keys, dtype, shape and ordered element bytes; compare all four clocks and canonical RNG keys, not just aggregate loss.',
            'packet_bytes': 'Retain both full raw packet hashes and report equality; if a container has nondeterministic metadata, canonical array-byte equality and preserved scientific scalars remain mandatory, with reviewed serialization explanation.',
            'scalars': 'Unchanged original validation/metrics/weights; no new tolerance or selection from profile outcomes',
            'source_instrumentation': 'A separately reviewed immutable executor must implement these hooks before compute admission'},
        preserved_constraints={'study_CPU_each': 32400, 'assessment_CPU_each': 1800, 'joint_controller_CPU': 1800,
            'Normal_iterations': 2000, 'AL_iterations': 300, 'training_paths': 100, 'official_paths': 500,
            'horizon_steps': 96, 'quantiles': QUANTILES, 'clock_offsets_steps': CLOCKS,
            'automatic_retry': False, 'promotion_authorized': False, 'price_change_authorized': False},
        blockers=BLOCKERS, preparation_only=True,
        next_action='Review and implement instrumentation in a distinct executor; obtain prospective finite numerical scope and every listed proof. This file is never accepted as execution authority.')


def write_new(path, value):
    p = physical(path); physical(p.parent)
    data = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()
    require(len(data) <= 16 * 1024**2, 'bounded plan output required')
    fd, temporary = tempfile.mkstemp(prefix='.execution_profile_', dir=p.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data); handle.flush(); os.fsync(fd)
        physical(p.parent)
        os.link(temporary, p, follow_symlinks=False)
    finally:
        os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args(argv)
    require(os.sched_getaffinity(0) == {31} and sys.dont_write_bytecode, 'administrative CPU31/-B required')
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError('120wall metadata compiler limit')))
    signal.alarm(120); start = time.monotonic()
    request_path = physical(args.request)
    require(request_path.suffix == '.json', 'JSON preparation request required')
    data = bounded_bytes(request_path)
    request = decode_json(data)
    result = compile_request(request)
    result['request_pin'] = {'path': str(request_path), 'sha256': sha(data)}
    result['compiler_source_pin'] = {'path': str(Path(__file__).resolve()), 'sha256': sha(bounded_bytes(Path(__file__).resolve()))}
    result['compiler_accounting'] = {'CPU_seconds': sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
        'wall_seconds': time.monotonic() - start, 'CPU_cap': 10, 'wall_cap': 120,
        'numerical_imports': 0, 'array_reads': 0, 'network_calls': 0, 'jobs_submitted': 0}
    write_new(args.output, result)
    print(json.dumps({'status': result['status'], 'tasks': sum(s['task_count'] for s in result['studies'].values()),
                      'output': str(args.output), 'sha256': sha(bounded_bytes(args.output))}))


if __name__ == '__main__':
    main()
