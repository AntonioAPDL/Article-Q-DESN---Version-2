"""Finite PriceFM full-grid calendar preparation; never scientific authority.

Only stdlib scalar/manifest metadata is accepted. Complete constructive proofs
are independently checked; a failed bounded search is UNPROVEN. No command in
this module launches a worker, changes a price, or admits a scientific study.
"""
import argparse
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import time
import uuid

SCHEMA = 'r163_calendar_preparation_v1'
QUANTILES = [.1, .25, .45, .5, .55, .75, .9]
PHASES = ('D', 'S0', 'EXTRAS')
OPERATIONS = {'preparation', 'cache', 'metadata', 'transfer', 'parent', 'proof', 'publication', 'recovery'}
EVIDENCE = {'batch_overhead', 'calendar_tails', 'controller_grid', 'scientific_memory',
            'scientific_capacity', 'new_execution_authority'}
ACCEPTED_PRICES_SHA256 = '218e4003894082df820bc41850d791ac4a74cce92bf645b26ca329fe97079e3a'
ACCEPTED_INPUTS = {
    'FI': {'preparation': '1f5de78553253cf2df4727c12bff6ab0789ca018f13db32df3e6a7e79b60d96c',
           'config': 'f98356e648e83bbb88f64de8e188f2c301429911bf3ab79e44625528fe3a77bd'},
    'DK2': {'preparation': '5fa9bcefe7a04250b4fd144e67e5775493fb5d536936f9ba7f5a3782995a32d5',
            'config': 'c26e8ddfb90c0855fd91116851796cc34b51db077cfcaf532d6f560d4758d90e'}}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def finite(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def typed_equal(left, right):
    if type(left) is not type(right): return False
    if isinstance(left, dict): return set(left) == set(right) and all(typed_equal(left[k], right[k]) for k in left)
    if isinstance(left, list): return len(left) == len(right) and all(typed_equal(x, y) for x, y in zip(left, right))
    return left == right


def gates_equal(left, right):
    """Named gates are a typed set, independent of JSON object insertion order."""
    def index(rows):
        require(type(rows) is list, 'explicit gate list required')
        result = {}
        for row in rows:
            require(type(row) is dict and set(row) == {'name', 'passed'} and
                    type(row['name']) is str and type(row['passed']) is bool,
                    'exact named boolean gate required')
            require(row['name'] not in result, 'duplicate gate name')
            result[row['name']] = row['passed']
        return result
    return typed_equal(index(left), index(right))


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    value = json.loads(data, object_pairs_hook=pairs)
    def walk(item):
        if isinstance(item, float): require(math.isfinite(item), 'nonfinite JSON number')
        elif isinstance(item, dict):
            for child in item.values(): walk(child)
        elif isinstance(item, list):
            for child in item: walk(child)
    walk(value)
    return value


def pin_read(ref):
    require(isinstance(ref, dict) and set(ref) == {'path', 'sha256'}, 'exact metadata pin required')
    p = Path(ref['path'])
    require(p.is_absolute() and p.suffix == '.json' and not any(q.is_symlink() for q in (p, *p.parents)),
            'physical absolute JSON metadata required')
    with os.fdopen(os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_size <= 16 * 1024**2, 'bounded regular metadata required')
        data = stream.read(16 * 1024**2 + 1)
        after = os.fstat(stream.fileno())
    require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
            (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), 'metadata changed during read')
    require(hashlib.sha256(data).hexdigest() == ref['sha256'], 'changed metadata pin')
    require(len(data) <= 16 * 1024**2, 'bounded metadata required')
    return strict_json(data)


def input_refs_check(refs):
    require(set(refs) == {'schema', 'purpose', 'studies', 'prices', 'assumptions'}
            and refs['schema'] == 'r163_calendar_inputs_v1' and refs['purpose'] == 'PRICEFM_METADATA_CALENDAR_PREPARATION',
            'exact preparation input schema/purpose required')
    require(refs['prices']['sha256'] == ACCEPTED_PRICES_SHA256, 'accepted original prices required; no repricing')
    require(set(refs['studies']) == {'FI', 'DK2'}, 'both original studies required')
    for name, source in refs['studies'].items():
        require(set(source) == {'preparation', 'config'} and all(source[role]['sha256'] == expected
                for role, expected in ACCEPTED_INPUTS[name].items()), 'accepted original preparation/config pins required')
    return True


def adapt(prep, config, prices, study):
    """Reconstruct every original nomination/qualified branch without losses."""
    require(study in {'FI', 'DK2'}, 'original study required')
    packages = prep['packages']; by_id = {p['package_id']: p for p in packages}
    require(len(packages) == len(by_id) == {'FI': 20, 'DK2': 21}[study], 'complete package universe required')
    require(len({p['candidate_id'] for p in packages}) == {'FI': 19, 'DK2': 20}[study], 'complete geometry universe required')
    order = sorted(by_id, key=lambda p: (hashlib.sha256((config['audit_key'] + '|' + p).encode()).hexdigest(), p))
    require(order == prep['frozen_audit_permutation'], 'frozen audit order changed')
    control = prep['control']; require(control in by_id, 'control missing')
    lookup, tasks = {}, {}
    for task in prep['tasks']:
        key = task['package_id'], task['split'], task['mode'], task['seed_index']; name = task['name']
        require(type(task['split']) is int and task['split'] in (1, 2, 3) and type(task['seed_index']) is int
                and task['seed_index'] in (0, 1, 2), 'integer split/seed identity required')
        require(key not in lookup and name not in tasks, 'duplicate original task')
        require(task['clock_offsets_steps'] == [0, 24, 48, 72] and task['horizon_steps'] == 96
                and all(type(c) is int for c in task['clock_offsets_steps'])
                and task['quantiles'] == QUANTILES, 'original clocks/horizon/quantiles changed')
        require(name in prices['task_estimates'], 'unpriced task')
        est = prices['task_estimates'][name]
        require(integer(est['reserved_CPU']) and integer(est['reserved_wall'])
                and est['reserved_CPU'] <= est['reserved_wall'], 'integer original CPU/wall required')
        require(bool(est['imported']) == bool(task['reuse']), 'imported identity changed')
        require(not task['reuse'] or est['reserved_CPU'] == est['reserved_wall'] == 0, 'imported price changed')
        tasks[name] = dict(id=name, cpu=est['reserved_CPU'], wall=est['reserved_wall'], imported=bool(task['reuse']))
        lookup[key] = name
    expected = {(p, split, mode, seed) for p in by_id for split in (1, 2, 3)
                for mode, seed in [('D', 0), ('S', 0), ('S', 1), ('S', 2)]}
    require(set(lookup) == expected and set(tasks) == set(prices['task_estimates']), 'complete original D/S0/S1/S2 grid required')
    def names(ids, mode, seeds):
        return [lookup[(p, split, mode, seed)] for p in ids for seed in seeds for split in (1, 2, 3)]
    branches = []
    replacement_cpu = max(t['cpu'] for t in tasks.values()); replacement_wall = max(t['wall'] for t in tasks.values())
    for a in by_id:
        if a == control:
            continue
        excluded = {by_id[control]['candidate_id'], by_id[a]['candidate_id']}
        b = next(p for p in order if by_id[p]['candidate_id'] not in excluded)
        for qualified in ([], [a], [b], [a, b]):
            groups = {'D': names(list(by_id), 'D', [0]), 'S0': names([control, a, b], 'S', [0]),
                      'EXTRAS': names([control] + qualified, 'S', [1, 2]) if qualified else []}
            ids = sum(groups.values(), [])
            branches.append(dict(possible_A=a, prospective_B=b, possible_qualified_set=qualified,
                phase_names=groups, D_count=len(groups['D']), S0_count=9, atomic_extra_count=len(groups['EXTRAS']),
                replacement_count=1, reserved_science_CPU=sum(tasks[n]['cpu'] for n in ids) + replacement_cpu,
                serial_component_wall=sum(tasks[n]['wall'] for n in ids) + replacement_wall))
    require(len(branches) == len(prices['all_loss_blind_branches']), 'omitted branch')
    for branch, old in zip(branches, prices['all_loss_blind_branches']):
        require(all(old.get(k) == v for k, v in branch.items() if k != 'phase_names'), 'original branch/price changed')
    return dict(study=study, tasks=tasks, branches=branches, prices=prices)


def assumptions_check(a):
    require(set(a) == {'batch_overhead', 'calendar_tails', 'controller', 'remaining_outer_wall', 'evidence'},
            'complete explicit assumptions required')
    o = a['batch_overhead']; t = a['calendar_tails']; c = a['controller']
    require(set(o) == {'cpu', 'wall'} and all(integer(v) for v in o.values()) and o['cpu'] <= o['wall'] < 5400,
            'explicit nonnegative additional batch overhead required')
    require(set(t) == {'queue', 'drain', 'barrier', 'wave_open', 'assessment'}
            and all(integer(v) for v in t.values()) and t['queue'] >= 1 and t['drain'] >= 60
            and t['assessment'] == 1800, 'original queue/drain and separate assessment tail required')
    require(integer(a['remaining_outer_wall']), 'finite remaining outer wall required')
    require(set(a['evidence']) == EVIDENCE and all(type(v) is bool for v in a['evidence'].values()),
            'all evidence states explicit; unknown is false')
    require(set(c) == {'ceiling_CPU', 'existing_joint_charge_CPU', 'operations'} and c['ceiling_CPU'] == 1800
            and integer(c['existing_joint_charge_CPU']), 'original joint1800 controller pool required')
    rows = c['operations']; require(isinstance(rows, list) and len(rows) == len(OPERATIONS), 'complete operation grid required')
    require({x['name'] for x in rows} == OPERATIONS, 'every operation category exactly once required')
    for x in rows:
        require(set(x) == {'name', 'unit_CPU', 'base_count', 'per_study_count', 'per_job_count',
                          'per_wave_count', 'per_phase_count', 'measured'}, 'exact operation grid fields required')
        require(all(integer(x[k]) for k in ('unit_CPU', 'base_count', 'per_study_count', 'per_job_count',
                                           'per_wave_count', 'per_phase_count')) and type(x['measured']) is bool,
                'integer nonnegative operation counts/prices required')
        require(not any(x[k] for k in ('base_count', 'per_study_count', 'per_job_count', 'per_wave_count', 'per_phase_count'))
                or x['unit_CPU'] > 0, 'counted operations cannot be priced free')
    require(next(x for x in rows if x['name'] == 'parent')['per_job_count'] >= 1, 'every job parent must be counted')
    return True


def controller_cost(c, jobs, waves, phases, studies=2):
    rows = []
    for x in c['operations']:
        count = x['base_count'] + studies*x['per_study_count'] + jobs*x['per_job_count'] + waves*x['per_wave_count'] + phases*x['per_phase_count']
        rows.append(dict(name=x['name'], count=count, CPU=count*x['unit_CPU'], measured=x['measured']))
    total = c['existing_joint_charge_CPU'] + sum(x['CPU'] for x in rows)
    return dict(CPU=total, within_original1800=total <= c['ceiling_CPU'], operations=rows,
                all_measured=all(x['measured'] for x in rows), existing_joint_charge_CPU=c['existing_joint_charge_CPU'])


def partitions(ids, tasks, overhead, stage):
    """Deterministic balanced bin-count alternatives, not a minimum-bin claim."""
    payload = sorted((tasks[n] for n in ids if not tasks[n]['imported']), key=lambda t: (-t['wall'], -t['cpu'], t['id']))
    if not payload:
        return [[]]
    cap = {'cpu': 5400-overhead['cpu'], 'wall': 5400-overhead['wall']}
    if any(t[k] > cap[k] for t in payload for k in cap):
        return []
    low = max(math.ceil(sum(t[k] for t in payload)/cap[k]) for k in cap)
    options, seen = [], set()
    counts = sorted(set(range(low, min(len(payload), low+10)+1)) | {len(payload)})
    for count in counts:
        bins = [[] for _ in range(count)]; loads = [dict(cpu=0, wall=0) for _ in range(count)]
        for task in payload:
            fitting = [i for i in range(count) if all(loads[i][k]+task[k] <= cap[k] for k in cap)]
            if not fitting:
                break
            i = min(fitting, key=lambda n: (loads[n]['wall'], loads[n]['cpu'], n))
            bins[i].append(task['id'])
            for k in cap:
                loads[i][k] += task[k]
        else:
            members = tuple(sorted(tuple(sorted(b)) for b in bins if b))
            if members in seen:
                continue
            seen.add(members)
            options.append([dict(id=stage+'_'+str(i), tasks=list(b), cpu=sum(tasks[n]['cpu'] for n in b)+overhead['cpu'],
                                 wall=sum(tasks[n]['wall'] for n in b)+overhead['wall']) for i, b in enumerate(members)])
    return options


def constructive(phases, workers, tails, shortest=False):
    require(integer(workers, 1) and workers <= 4, 'one through four actual workers required')
    wave, start = 1, tails['wave_open']; available = [start]*workers; rows = []
    for phase, jobs in phases:
        pending = sorted(jobs, key=lambda j: ((j['wall'] if shortest else -j['wall']), j['id']))
        while pending:
            found = None
            for worker in sorted(range(workers), key=lambda n: (available[n], n)):
                for i, job in enumerate(pending):
                    finish = available[worker] + tails['queue'] + job['wall'] + tails['drain']
                    if job['cpu'] <= 5400 and job['wall'] <= 5400 and available[worker] < start+5400 and finish <= start+7200:
                        found = worker, i, finish; break
                if found:
                    break
            if found is None:
                wave += 1
                if wave > 3:
                    return None
                start = max(available) + tails['wave_open']; available = [start]*workers; continue
            worker, i, finish = found; job = pending.pop(i)
            rows.append(dict(phase=phase, batch=job['id'], cpu=job['cpu'], wall=job['wall'],
                             worker=worker, wave=wave, wave_start=start, dispatch=available[worker], finish=finish))
            available[worker] = finish
        end = max(available) + tails['barrier']; available = [end]*workers
    end = max(available)
    return dict(rows=rows, waves=wave, numerical_end=end,
                assessment_start=end+tails['queue'], assessment_end=end+tails['queue']+tails['assessment']+tails['drain'])


def verify_calendar(calendar, phases, workers, tails):
    require(calendar is not None, 'complete calendar required')
    require(integer(workers, 1) and workers <= 4, 'one through four actual workers required')
    expected = {j['id']: (phase, j) for phase, jobs in phases for j in jobs}
    require(len(expected) == sum(len(jobs) for _, jobs in phases), 'unique batch identities required')
    seen = set(); wave_starts = {}; intervals = {i: [] for i in range(workers)}
    order = [p for p, _ in phases]; phase_end = {}; last_phase = -1; last_wave = 1
    for row in calendar['rows']:
        require(row['batch'] in expected and row['batch'] not in seen, 'omitted/duplicate/unknown batch')
        phase, job = expected[row['batch']]
        require(all(row[k] == job[k] for k in ('cpu', 'wall')) and row['phase'] == phase, 'changed batch identity')
        require(all(integer(row[k]) for k in ('cpu', 'wall', 'worker', 'wave', 'wave_start', 'dispatch', 'finish')),
                'integer calendar coordinates required')
        position = order.index(phase)
        require(position >= last_phase and row['wave'] >= last_wave, 'phase/wave order changed')
        last_phase, last_wave = position, row['wave']
        if row['wave'] not in wave_starts:
            require(row['wave'] == len(wave_starts)+1, 'missing wave')
            previous = max((x['finish'] for x in calendar['rows'] if x['wave'] < row['wave']), default=0)
            require(row['wave_start'] >= previous+tails['wave_open'], 'overlapping wave lifetimes')
            wave_starts[row['wave']] = row['wave_start']
        require(wave_starts[row['wave']] == row['wave_start'], 'changed wave start')
        require(row['wave'] <= 3 and row['cpu'] <= 5400 and row['wall'] <= 5400 and row['dispatch'] >= row['wave_start']
                and row['dispatch'] < row['wave_start']+5400 and row['finish'] <= row['wave_start']+7200,
                'wave/dispatch/lease or batch cap violation')
        require(row['finish'] == row['dispatch']+tails['queue']+row['wall']+tails['drain'], 'duration changed')
        require(0 <= row['worker'] < workers, 'worker outside declared capacity')
        for earlier in order[:position]:
            require(row['dispatch'] >= phase_end.get(earlier, 0)+tails['barrier'], 'crossed root phase barrier')
        intervals[row['worker']].append((row['dispatch'], row['finish']))
        phase_end[phase] = max(phase_end.get(phase, 0), row['finish']); seen.add(row['batch'])
    require(seen == set(expected), 'omitted batch')
    for pairs in intervals.values():
        pairs.sort(); require(all(x[1] <= y[0] for x, y in zip(pairs, pairs[1:])), 'worker overlap')
    require(calendar['waves'] == max(1, len(wave_starts)) and 1 <= calendar['waves'] <= 3, 'wave count changed')
    end = tails['wave_open']
    for phase, jobs in phases:
        rows = [row for row in calendar['rows'] if row['phase'] == phase]
        require(all(row['dispatch'] >= end for row in rows), 'crossed root phase barrier')
        end = max((row['finish'] for row in rows), default=end)+tails['barrier']
    require(calendar['numerical_end'] == end and calendar['assessment_start'] == end+tails['queue']
            and calendar['assessment_end'] == end+tails['queue']+tails['assessment']+tails['drain'], 'assessment tail changed')
    return True


def scenario_phases(model, branch, scenario, overhead):
    """Check scientific membership/imports and reconstruct every batch price."""
    tasks = model['tasks']; phases = []; replacement = scenario['replacement_phase']
    require(replacement in PHASES and set(scenario['phase_jobs']) == set(PHASES), 'exact replacement/phase identities required')
    covered = branch['phase_names'][replacement]
    require(covered and scenario['covered_failed_tasks'] == covered, 'complete replacement coverage required')
    for stage in PHASES:
        ids = branch['phase_names'][stage]; jobs = scenario['phase_jobs'][stage]
        members = [n for job in jobs for n in job['tasks']]
        require(len(members) == len(set(members)) and set(members) == {n for n in ids if not tasks[n]['imported']},
                'complete phase task coverage required')
        for job in jobs:
            require(job['tasks'] and job['cpu'] == sum(tasks[n]['cpu'] for n in job['tasks'])+overhead['cpu']
                    and job['wall'] == sum(tasks[n]['wall'] for n in job['tasks'])+overhead['wall'], 'batch price changed')
        phases.append((stage, jobs))
        if stage == replacement:
            phases.append(('REPLACEMENT_'+stage, [dict(id='REPLACEMENT_'+stage, tasks=['ONE_RECONCILED_FAILURE'],
                cpu=max(tasks[n]['cpu'] for n in covered)+overhead['cpu'],
                wall=max(tasks[n]['wall'] for n in covered)+overhead['wall'])]))
    return phases


def verify_scenario(model, branch, scenario, assumptions):
    phases = scenario_phases(model, branch, scenario, assumptions['batch_overhead'])
    verify_calendar(scenario['calendar'], phases, scenario['workers'], assumptions['calendar_tails'])
    require(scenario['job_count'] == sum(len(j) for _, j in phases)+1, 'assessment/replacement job count changed')
    require(type(scenario['policy_workers']) is int and scenario['policy_workers'] in (1, 2, 4)
            and scenario['workers'] <= scenario['policy_workers'],
            'only1→2→4 scientific policy ladder;3actual workers requires4policy')
    expected_control = controller_cost(assumptions['controller'], scenario['job_count'],
                                      scenario['calendar']['waves'], len(phases), studies=1)
    require(typed_equal(scenario['controller_single_study_diagnostic'], expected_control)
            and scenario['phase_count'] == len(phases)
            and scenario['extra_batch_CPU'] == (scenario['job_count']-1)*assumptions['batch_overhead']['cpu'],
            'controller/phase/additional overhead accounting changed')
    require(type(scenario['within_remaining_outer_wall']) is bool and scenario['within_remaining_outer_wall'] ==
            (scenario['calendar']['assessment_end'] <= assumptions['remaining_outer_wall']), 'outer clock fit changed')
    return True


def analyze(model, a, max_combinations=64):
    assumptions_check(a); require(integer(max_combinations, 1) and max_combinations <= 2000, 'bounded search required')
    tasks = model['tasks']; cache = {}; results = []; counters = {str(w): {} for w in (1, 2, 3, 4)}
    for branch in model['branches']:
        options = []
        for stage in PHASES:
            key = stage, tuple(branch['phase_names'][stage])
            if key not in cache:
                cache[key] = partitions(list(key[1]), tasks, a['batch_overhead'], stage)
            options.append(cache[key])
        for replacement in (p for p in PHASES if branch['phase_names'][p]):
            covered = branch['phase_names'][replacement]
            volume = sum(tasks[n]['wall'] for ids in branch['phase_names'].values() for n in ids)+max(tasks[n]['wall'] for n in covered)
            for workers in (1, 2, 3, 4):
                result = dict(branch_A=branch['possible_A'], branch_B=branch['prospective_B'],
                    qualified=branch['possible_qualified_set'], atomic_extra_count=branch['atomic_extra_count'],
                    replacement_phase=replacement, workers=workers, policy_workers=4 if workers == 3 else workers,
                    policy_condition='SCIENTIFIC_POLICY_UNPROVED;3actual_requires4policy' if workers == 3 else 'SCIENTIFIC_POLICY_UNPROVED',
                    covered_failed_tasks=covered, reserved_volume=volume, status='UNPROVEN', scenario=None)
                if volume > workers*3*7200:
                    result['status'] = 'PROVED_RESERVED_VOLUME_INFEASIBLE'
                elif any(not o for o in options):
                    result['status'] = 'PROVED_SINGLE_COMPONENT_CAP_INFEASIBLE'
                else:
                    best = None; searched = 0
                    indices = sorted(itertools.product(*(range(len(o)) for o in options)),
                                     key=lambda i: (sum(i), max(i), i))
                    minimum_jobs = sum(min(len(j) for j in o) for o in options)+2
                    for indices_for_choice in indices[:max_combinations]:
                        selected = [o[i] for o, i in zip(options, indices_for_choice)]
                        trial = dict(result, phase_jobs={p: jobs for p, jobs in zip(PHASES, selected)})
                        phases = scenario_phases(model, branch, trial, a['batch_overhead'])
                        jobs = sum(len(j) for _, j in phases)+1
                        for shortest in (False, True):
                            searched += 1; calendar = constructive(phases, workers, a['calendar_tails'], shortest)
                            if calendar is None:
                                continue
                            control = controller_cost(a['controller'], jobs, calendar['waves'], len(phases), studies=1)
                            within_outer = calendar['assessment_end'] <= a['remaining_outer_wall']
                            score = (not within_outer, not control['within_original1800'], jobs, calendar['assessment_end'])
                            if best is None or score < best[0]:
                                proof = dict(trial, calendar=calendar, job_count=jobs, controller_single_study_diagnostic=control,
                                    phase_count=len(phases), extra_batch_CPU=(jobs-1)*a['batch_overhead']['cpu'],
                                    within_remaining_outer_wall=within_outer)
                                verify_scenario(model, branch, proof, a); best = score, proof
                        if best and best[1]['job_count'] == minimum_jobs and best[1]['within_remaining_outer_wall']:
                            break
                        # No unproved optimization assertion is made when the finite prefix is exhausted.
                    result['searched_calendars'] = searched
                    if best:
                        result.update(status='CONSTRUCTIVE', scenario=best[1])
                key = result['status']; counters[str(workers)][key] = counters[str(workers)].get(key, 0)+1
                results.append(result)
    return dict(study=model['study'], task_count=len(tasks), branch_count=len(model['branches']), scenarios=results,
                summary=counters, complete_scenarios=len(results),
                worst_reserved_CPU_fits=model['prices']['rounded_D_worst9S0_and_replacement_CPU'] <= model['prices']['available_science_CPU_share_adjusted'],
                original_available_science_CPU=model['prices']['available_science_CPU_share_adjusted'],
                original_mandatory_reserved_CPU=model['prices']['rounded_D_worst9S0_and_replacement_CPU'],
                optional_rule='Actual completed prefix charges govern whole12/18 extras; no retrospective all-extra deferral.',
                search_limit_per_scenario=max_combinations*2, no_minimum_job_count_claim=True)


def atomic_extra_check(model, branch, requested, completed_charges, remaining_CPU, scenario, a, other_study_controller_CPU):
    """Prospective all-or-none resource check; never a release authority."""
    assumptions_check(a); expected = branch['phase_names']['EXTRAS']; prefix = branch['phase_names']['D']+branch['phase_names']['S0']
    require(len(expected) in (12, 18) and len(requested) == len(set(requested)) and set(requested) == set(expected),
            'whole frozen12/18 extra set required; no partial extras')
    require(set(completed_charges) == set(prefix) and all(finite(v) for v in completed_charges.values()),
            'complete actual completed-prefix charges required')
    require(finite(remaining_CPU) and integer(other_study_controller_CPU), 'finite remaining resource budget required')
    verify_scenario(model, branch, scenario, a)
    reserve = max(t['cpu'] for t in model['tasks'].values())
    available = max(0., min(remaining_CPU, model['prices']['available_science_CPU_share_adjusted']-sum(completed_charges.values())-reserve))
    # Prefix work is already represented by actual completed charges. Only
    # future extra jobs and the retained replacement add batch overhead here.
    needed = sum(model['tasks'][n]['cpu'] for n in expected)+(len(scenario['phase_jobs']['EXTRAS'])+1)*a['batch_overhead']['cpu']
    controller = scenario['controller_single_study_diagnostic']['CPU']+other_study_controller_CPU
    reasons = []
    if needed > available: reasons.append('WHOLE_EXTRA_CPU_UNFUNDED')
    if scenario['calendar']['assessment_end'] > a['remaining_outer_wall']: reasons.append('COMPLETE_CALENDAR_DOES_NOT_FIT')
    if controller > 1800: reasons.append('JOINT_CONTROLLER_UNFUNDED')
    if not all(a['evidence'].values()) or not scenario['controller_single_study_diagnostic']['all_measured']:
        reasons.append('PROSPECTIVE_RESOURCE_EVIDENCE_UNPROVED')
    return dict(status='DEFERRED_WHOLE_EXTRA_RESOURCE_GATE' if reasons else 'ATOMIC_RESOURCE_FIT_NOT_AUTHORITY',
                admitted=False, required=requested, partial_extra_admitted=False, remaining_CPU=available,
                required_CPU=needed, joint_controller_CPU=controller, reasons=reasons)


def joint_summary(studies, a):
    worst = {}
    for name, result in studies.items():
        found = [x['scenario'] for x in result['scenarios'] if x['status'] == 'CONSTRUCTIVE' and x['workers'] == 4]
        worst[name] = dict(jobs=max((x['job_count'] for x in found), default=0),
                           waves=max((x['calendar']['waves'] for x in found), default=0),
                           phases=max((x['phase_count'] for x in found), default=0),
                           complete=bool(found) and all(x['status'] == 'CONSTRUCTIVE' for x in result['scenarios'] if x['workers'] == 4))
    joint = controller_cost(a['controller'], sum(x['jobs'] for x in worst.values()),
                            sum(x['waves'] for x in worst.values()), sum(x['phases'] for x in worst.values()))
    joint['worst_per_study'] = worst; joint['complete_calendars'] = all(x['complete'] for x in worst.values())
    gates = [{'name': name, 'passed': value} for name, value in sorted(a['evidence'].items())]
    gates += [dict(name='all_four_worker_scenarios_constructive', passed=joint['complete_calendars']),
              dict(name='joint_aggregate_capacity_calendar_certificate', passed=False),
              dict(name='joint_controller_funded_and_measured', passed=joint['within_original1800'] and joint['all_measured']),
              dict(name='all_current_prices_funded', passed=all(x['worst_reserved_CPU_fits'] for x in studies.values())),
              dict(name='all_complete_calendars_fit_original_outer_clock', passed=all(
                  x['status'] == 'CONSTRUCTIVE' and x['scenario']['within_remaining_outer_wall']
                  for s in studies.values() for x in s['scenarios'] if x['workers'] == 4))]
    return joint, gates


def prepare(models, a, max_combinations=64):
    require(set(models) == {'FI', 'DK2'}, 'both complete studies required for joint preparation')
    studies = {name: analyze(model, a, max_combinations) for name, model in models.items()}
    joint, gates = joint_summary(studies, a)
    return dict(schema=SCHEMA, purpose='PRICEFM_COMPLETE_GRID_CALENDAR_DIAGNOSTIC', status='PREPARED_NOT_ADMITTED',
                scientific_admission=False, studies=studies, joint_controller=joint, gates=gates,
                joint_calendar=dict(status='UNPROVEN_SHARED_FOUR_WORKER_CAPACITY', certificate=False,
                    independent_single_study_calendars_only=True, shared_worker_ceiling=4),
                assumptions=a, old_prices_changed=False, old_grants_renewed=False,
                limitations=['Declared optimistic overhead is not a measured price.',
                             'A lost batch with multiple uncertain children is not one reconciled replacement.',
                             'No failed search is an infeasibility proof; no constructive job count is claimed minimal.',
                             'Two independent four-worker study calendars are not a joint shared-four-worker calendar.',
                             'Assessment is separately funded after numerical waves and inside the outer deadline.'])


def verify_preparation(result, models, a):
    """Cheap independent witness verification; never rerun the search."""
    assumptions_check(a)
    require(result['schema'] == SCHEMA and result['purpose'] == 'PRICEFM_COMPLETE_GRID_CALENDAR_DIAGNOSTIC'
            and result['status'] == 'PREPARED_NOT_ADMITTED' and result['scientific_admission'] is False,
            'calendar preparation is not scientific authority')
    require(set(models) == set(result['studies']) == {'FI', 'DK2'} and typed_equal(result['assumptions'], a),
            'both complete models and exact assumptions required')
    require(result['old_prices_changed'] is False and result['old_grants_renewed'] is False, 'original history required')
    for name, model in models.items():
        study = result['studies'][name]; expected = {}
        for branch in model['branches']:
            for phase in (p for p in PHASES if branch['phase_names'][p]):
                for workers in (1, 2, 3, 4):
                    expected[(branch['possible_A'], branch['prospective_B'], tuple(branch['possible_qualified_set']), phase, workers)] = branch
        require(study['task_count'] == len(model['tasks']) and study['branch_count'] == len(model['branches'])
                and study['complete_scenarios'] == len(expected), 'complete original grid/counts required')
        seen = set(); counters = {str(w): {} for w in (1, 2, 3, 4)}
        for row in study['scenarios']:
            require(type(row['workers']) is int and row['workers'] in (1, 2, 3, 4)
                    and type(row['policy_workers']) is int and row['policy_workers'] == (4 if row['workers'] == 3 else row['workers'])
                    and type(row['atomic_extra_count']) is int, 'literal worker/policy/extra identity required')
            key = row['branch_A'], row['branch_B'], tuple(row['qualified']), row['replacement_phase'], row['workers']
            require(key in expected and key not in seen, 'duplicate/unknown scenario')
            seen.add(key); branch = expected[key]; covered = branch['phase_names'][row['replacement_phase']]
            volume = sum(model['tasks'][n]['wall'] for ids in branch['phase_names'].values() for n in ids)+max(model['tasks'][n]['wall'] for n in covered)
            require(row['atomic_extra_count'] == branch['atomic_extra_count'] and row['covered_failed_tasks'] == covered
                    and row['reserved_volume'] == volume, 'changed branch/replacement/volume identity')
            status = row['status']; require(status in {'CONSTRUCTIVE', 'UNPROVEN', 'PROVED_RESERVED_VOLUME_INFEASIBLE',
                                                       'PROVED_SINGLE_COMPONENT_CAP_INFEASIBLE'}, 'unknown proof status')
            if status == 'CONSTRUCTIVE':
                require(all(typed_equal(row[k], row['scenario'][k]) for k in
                    ('branch_A', 'branch_B', 'qualified', 'atomic_extra_count', 'replacement_phase', 'workers',
                     'policy_workers', 'covered_failed_tasks', 'reserved_volume')), 'outer/inner scenario identity changed')
                verify_scenario(model, branch, row['scenario'], a)
            else:
                require(row['scenario'] is None, 'failed search cannot carry an accepted proof')
                if status == 'PROVED_RESERVED_VOLUME_INFEASIBLE':
                    require(volume > row['workers']*3*7200, 'false volume infeasibility claim')
                elif status == 'PROVED_SINGLE_COMPONENT_CAP_INFEASIBLE':
                    require(any(model['tasks'][n][k]+a['batch_overhead'][k] > 5400
                        for ids in branch['phase_names'].values() for n in ids for k in ('cpu', 'wall')), 'false component infeasibility claim')
            counts = counters[str(row['workers'])]; counts[status] = counts.get(status, 0)+1
        require(seen == set(expected) and study['summary'] == counters, 'omitted scenario or false summary')
        price = model['prices']
        require(study['original_available_science_CPU'] == price['available_science_CPU_share_adjusted']
                and study['original_mandatory_reserved_CPU'] == price['rounded_D_worst9S0_and_replacement_CPU']
                and study['worst_reserved_CPU_fits'] == (price['rounded_D_worst9S0_and_replacement_CPU'] <= price['available_science_CPU_share_adjusted']),
                'original accepted prices/funding gate changed')
    joint, gates = joint_summary(result['studies'], a)
    require(typed_equal(result['joint_controller'], joint) and gates_equal(result['gates'], gates), 'joint accounting/gates changed')
    require(typed_equal(result['joint_calendar'], dict(status='UNPROVEN_SHARED_FOUR_WORKER_CAPACITY', certificate=False,
            independent_single_study_calendars_only=True, shared_worker_ceiling=4)), 'joint shared capacity remains unproved')
    return True


def verify_shared_capacity(scenarios, models, branches, a, policy_workers=4):
    """Verify one supplied two-study pair, never all branch combinations."""
    require(set(scenarios) == set(models) == set(branches) == {'FI', 'DK2'}
            and policy_workers in (1, 2, 4), 'both studies and legal shared policy required')
    anchors = {}; intervals = []
    for name, scenario in scenarios.items():
        require(models[name]['study'] == name and scenario['policy_workers'] <= policy_workers, 'study/policy identity changed')
        verify_scenario(models[name], branches[name], scenario, a)
        calendar = scenario['calendar']
        require(calendar['assessment_end'] <= a['remaining_outer_wall'], 'pair exceeds original outer clock')
        for row in calendar['rows']:
            if row['wave'] in anchors: require(anchors[row['wave']] == row['wave_start'], 'shared wave anchors differ')
            anchors[row['wave']] = row['wave_start']
            intervals.append((row['dispatch'], row['finish'], name, row['batch']))
        intervals.append((calendar['numerical_end'], calendar['assessment_end'], name, 'ASSESSMENT'))
    require(len(anchors) <= 3, 'more than three shared numerical waves')
    slots = [0]*policy_workers; assigned = []
    for start, end, name, batch in sorted(intervals):
        eligible = [i for i, free in enumerate(slots) if free <= start]
        require(eligible, 'aggregate shared capacity exceeded, including assessment/drain')
        worker = min(eligible); slots[worker] = end
        assigned.append(dict(study=name, batch=batch, shared_worker=worker, start=start, end=end))
    return dict(status='PROVIDED_PAIR_CAPACITY_VERIFIED_NOT_AUTHORITY', scientific_admission=False,
                all_branch_pairs_certified=False, shared_policy_workers=policy_workers,
                shared_wave_anchors=anchors, interval_assignment=assigned)


def publish_new(output, result):
    output = Path(output); require(output.is_absolute() and not any(q.is_symlink() for q in output.parents), 'physical absolute output required')
    temporary = output.parent/('.calendar-'+uuid.uuid4().hex+'.tmp')
    try:
        with temporary.open('x') as stream:
            json.dump(result, stream, sort_keys=True, separators=(',', ':'), allow_nan=False); stream.write('\n')
            stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, output)  # Atomic create-only publication; never replace a prior result.
    finally:
        if temporary.exists(): temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', required=True); parser.add_argument('--output', required=True)
    parser.add_argument('--inputs-sha256', required=True)
    parser.add_argument('--search-combinations', type=int, default=64)
    parser.add_argument('--maximum-cpu-seconds', type=int, default=20)
    args = parser.parse_args(); require(os.sched_getaffinity(0) == {31}, 'administrativeCPU31 required')
    require(integer(args.maximum_cpu_seconds, 1) and args.maximum_cpu_seconds <= 90, 'finiteCPU1..90 required')
    resource.setrlimit(resource.RLIMIT_CPU, (args.maximum_cpu_seconds, args.maximum_cpu_seconds)); signal.alarm(600)
    start = time.monotonic(); p = Path(args.inputs)
    refs = pin_read(dict(path=str(p), sha256=args.inputs_sha256))
    input_refs_check(refs)
    prices = pin_read(refs['prices']); models = {}
    for name, source in refs['studies'].items():
        require(set(source) == {'preparation', 'config'}, 'exact preparation/config pins required')
        prep = pin_read(source['preparation']); require(prep['config_sha256'] == source['config']['sha256'], 'preparation/config closure changed')
        models[name] = adapt(prep, pin_read(source['config']),
                             prices['studies'][name]['loss_blind_price_draft'], name)
    result = prepare(models, refs['assumptions'], args.search_combinations); result['input_pins'] = refs
    verify_preparation(result, models, refs['assumptions'])
    result['elapsed_wall'] = time.monotonic()-start; result['CPU_seconds'] = sum(resource.getrusage(resource.RUSAGE_SELF)[:2])
    publish_new(args.output, result)
    print(json.dumps(dict(status=result['status'], studies={n: {'tasks': s['task_count'], 'branches': s['branch_count'],
                              'scenarios': s['complete_scenarios']} for n, s in result['studies'].items()},
                         CPU_seconds=result['CPU_seconds'], wall_seconds=result['elapsed_wall'])))


if __name__ == '__main__':
    main()
