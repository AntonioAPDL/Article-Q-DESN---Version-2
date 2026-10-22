import copy
import importlib.util
import json
from types import SimpleNamespace
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / 'application/scripts/pricefm/489_run_pricefm_stage_r146_at_training_fallback.py'
spec = importlib.util.spec_from_file_location('pricefm_r146_runner_test', ENTRY)
R146 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R146)
CONFIG = json.loads((ROOT / 'application/config/pricefm_stage_r146_at_training_fallback_20261022.json').read_text())
IDENTITY = {'branch': 'work/pricefm-r146-at-training-fallback-test', 'head': 'r146-head'}


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def packet(folder, task, result, extra=None, source='r140'):
    write(folder / 'result.json', result)
    for name, value in (extra or {}).items():
        write(folder / name, value)
    artifacts = {str(f.relative_to(folder)): R146.sha256(f) for f in folder.rglob('*') if f.is_file()}
    metadata = {'certified': True, 'source_head': source, 'task_sha256': task}
    write(folder / 'completed_evidence.json', {'artifacts': artifacts, 'metadata': metadata})


def evidence_fixture(tmp_path, monkeypatch):
    config = copy.deepcopy(CONFIG)
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    monkeypatch.setattr(R146, 'assert_contract', lambda _: None)
    monkeypatch.setattr(R146, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(R146, 'git', lambda root, *args: 'test')
    monkeypatch.setattr(R146, 'host_health', lambda _: {'healthy': True})
    monkeypatch.setattr(R146, 'exhausted_evidence', lambda _: [{'task': 'failed'}])
    monkeypatch.setattr(R146, 'predecessor_state', lambda _: {'ready': False})
    candidate = config['fallback_candidate']
    previous = {'candidate_id': 'old-desn', 'tau0': 1, 'mean_AQL': 6, 'split_AQL': {}}
    row = {key: candidate[key] for key in ('candidate_id', 'tau0', 'mean_AQL', 'split_AQL')}
    source = R146.source_campaign(config)
    prep_path = R146.source_preparation(config)
    bank = source / 'training_banks/AT' / (candidate['spec']['feature_policy'] + '.npz')
    bank.parent.mkdir(parents=True); bank.write_bytes(b'frozen train-only bank')
    write(prep_path, {'regional': {'AT': {'candidates': [candidate]}},
                     'protocol': {'recovery_source': {'head': 'r140'}},
                     'bank_sha256': {str(bank): R146.sha256(bank)},
                     'input_sha256': {}, 'source_sha256': {}})
    write(source / 'rhs_closeout.json', {'AT': {'ranking': [previous] * 3 + [row],
                                               'finalists': [previous]}})
    imported = {}
    for name, record in config['prerequisites'].items():
        task = {'name': name, 'kind': record['kind'], 'candidate_id': candidate['candidate_id'],
                'region': 'AT', 'split': record['split']}
        result = {'certified': True}
        extra = {}
        if record['kind'] == 'stats':
            result['train_only'] = True
        else:
            task['tau0'] = candidate['tau0']
            extra['fit/terminal.json'] = {'full_variational_certified': True, 'test_opened': False,
                                          'prior_center_from_initializer': False, 'p': 577}
        path = source / 'tasks' / (name + '.json')
        write(path, task)
        record['task_sha256'] = R146.sha256(path)
        folder = source / 'tasks_done' / name
        packet(folder, record['task_sha256'], result, extra)
        record['completed_evidence_sha256'] = R146.sha256(folder / 'completed_evidence.json')
        record['source_head'] = 'r140'
        imported[name] = {key: record[key] for key in ('kind', 'task_sha256', 'completed_evidence_sha256')}
    write(source / 'recovery_import.json', {'status': 'R141_R140_PREREQUISITES_IMPORTED',
                                           'region': 'AT', 'source_head': 'r140', 'imported': imported})
    config['source_preparation_sha256'] = R146.sha256(prep_path)
    config['source_rhs_closeout_sha256'] = R146.sha256(source / 'rhs_closeout.json')
    config['source_recovery_import_sha256'] = R146.sha256(source / 'recovery_import.json')
    return config


def test_locked_contract_uses_one_distinct_candidate_eight_cores_and_no_prior_drift():
    assert CONFIG['fallback_rank'] == 4
    assert CONFIG['fallback_candidate']['candidate_id'] == 'r134_7a422c0c3473f81f'
    assert CONFIG['fallback_candidate']['tau0'] == 0.0016320908467640013
    assert 1 + sum(CONFIG['fallback_candidate']['spec']['units']) == 577
    assert CONFIG['cpus'] == list(range(8)) and CONFIG['maximum_workers'] == 8
    assert CONFIG['al_max_iter'] == 300
    assert {r['kind'] for r in CONFIG['prerequisites'].values()} == {'stats', 'rhs'}
    assert len(CONFIG['prerequisites']) == 6 and len(CONFIG['exhausted_rescues']) == 4
    for key in ('test_data_access_authorized', 'posterior_target_changes_authorized',
                'certificate_limit_changes_authorized', 'registry_mutation_authorized',
                'article_mutation_authorized', 'promotion_authorized'):
        assert CONFIG[key] is False
    changed = copy.deepcopy(CONFIG); changed['cpus'] = list(range(9))
    with pytest.raises(ValueError, match='bounded fallback'):
        R146.assert_contract(changed, require_host=False)


def test_exact_r140_import_lineage_is_accepted_without_relabelling(tmp_path, monkeypatch):
    config = evidence_fixture(tmp_path, monkeypatch)
    result = R146.fallback_audit(config, require_clean_source=False)
    assert result['status'] == 'R146_AUDIT_PASS'
    assert len(result['prerequisites']) == 6
    assert all(r['original_source_head'] == 'r140' for r in result['prerequisites'])
    assert result['official_test_opened'] is False
    with pytest.raises(RuntimeError, match='not finished draining'):
        R146.fallback_audit(config, require_idle=True)


def test_hash_valid_packet_with_false_origin_is_rejected(tmp_path, monkeypatch):
    config = evidence_fixture(tmp_path, monkeypatch)
    name = next(iter(config['prerequisites']))
    folder = R146.source_campaign(config) / 'tasks_done' / name
    seal = R146.read(folder / 'completed_evidence.json')
    seal['metadata']['source_head'] = config['source_head']
    write(folder / 'completed_evidence.json', seal)
    config['prerequisites'][name]['completed_evidence_sha256'] = R146.sha256(folder / 'completed_evidence.json')
    with pytest.raises(RuntimeError, match='R140 prerequisite provenance'):
        R146.fallback_audit(config, require_clean_source=False)


def test_changed_prerequisite_payload_is_rejected(tmp_path, monkeypatch):
    config = evidence_fixture(tmp_path, monkeypatch)
    name = next(iter(config['prerequisites']))
    write(R146.source_campaign(config) / 'tasks_done' / name / 'result.json', {'certified': False})
    with pytest.raises(RuntimeError, match='artifact hash differs'):
        R146.fallback_audit(config, require_clean_source=False)


def test_untried_distinct_training_rank_cannot_be_skipped(tmp_path, monkeypatch):
    config = evidence_fixture(tmp_path, monkeypatch)
    path = R146.source_campaign(config) / 'rhs_closeout.json'
    value = R146.read(path)
    value['AT']['ranking'][2] = dict(value['AT']['ranking'][3])
    write(path, value); config['source_rhs_closeout_sha256'] = R146.sha256(path)
    with pytest.raises(RuntimeError, match='first untried distinct'):
        R146.fallback_audit(config, require_clean_source=False)


def test_predecessor_requires_both_drained_lane_and_quarantine_receipts(tmp_path, monkeypatch):
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    config = copy.deepcopy(CONFIG)
    assert R146.predecessor_state(config)['ready'] is False
    runtime = tmp_path / 'launch_prep' / config['predecessor_tag'] / 'muscat'
    failure = {'region': 'AT', 'lane': 'at', 'error_type': 'RuntimeError',
               'reason': 'bounded rescue exhausted without certification: task',
               'test_opened': False, 'posterior_target_changed': False}
    write(runtime / 'quarantine/AT.json', failure)
    assert R146.predecessor_state(config)['ready'] is False
    write(runtime / 'at.terminal.json', {'status': config['predecessor_terminal_status'],
                                        'lane': 'at', 'completed': [], 'failures': [failure]})
    write(runtime / 'audit.json', {'source': {'branch': config['predecessor_branch'],
                                            'head': config['predecessor_head']}})
    assert R146.predecessor_state(config)['ready'] is True
    failure['reason'] = 'numerical crash'
    write(runtime / 'quarantine/AT.json', failure)
    with pytest.raises(RuntimeError, match='expected bounded rescue'):
        R146.predecessor_state(config)


def test_cpu_guard_checks_workers_children_and_owned_controllers(monkeypatch):
    monkeypatch.setattr(R146, 'command_lines', lambda: [
        (101, 'python pricefm.py controller --region AT --cpus 0,1,2,3,4,5,6,7'),
        (102, 'python pricefm.py controller --region IT_CSUD --cpus 15,16,17,18'),
        (103, 'R --file=fit_pricefm.R --args --config recovery.json'),
        (104, 'python pricefm.py worker --region DE_LU --cpu 8'),
        (105, 'unrelated R --file=other.R')])
    monkeypatch.setattr(R146.os, 'sched_getaffinity', lambda pid: {3} if pid == 103 else {8})
    assert {r['pid'] for r in R146.slot_a_conflicts(CONFIG)} == {101, 103}


def test_supervisor_waits_for_predecessor_then_worker_exit_without_launching(tmp_path, monkeypatch):
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    monkeypatch.setattr(R146, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(R146, 'release', lambda _: {})
    monkeypatch.setattr(R146, 'host_health', lambda _: {'healthy': True})
    states = iter([{'ready': False}, {'ready': True}, {'ready': True}])
    conflicts = iter([[{'pid': 42}], [{'pid': 42}], []])
    monkeypatch.setattr(R146, 'predecessor_state', lambda _: next(states))
    monkeypatch.setattr(R146, 'slot_a_conflicts', lambda _: next(conflicts))
    sleeps = []
    monkeypatch.setattr(R146.time, 'sleep', lambda _: sleeps.append(R146.read(
        tmp_path / 'launch_prep' / CONFIG['tag'] / 'muscat/progress.json')['status']))
    monkeypatch.setattr(R146, 'controller', lambda _: {'status': 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED',
                                                      'source': IDENTITY})
    assert R146.run(CONFIG)['status'] == 'R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED'
    assert sleeps == ['R146_WAITING_FOR_R145_AT_LANE_DRAIN', 'R146_WAITING_FOR_AT_SLOT_PROCESS_EXIT']


def test_failure_seals_runtime_quarantine_and_restart_cannot_retry(tmp_path, monkeypatch):
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    monkeypatch.setattr(R146, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(R146, 'release', lambda _: {})
    monkeypatch.setattr(R146, 'host_health', lambda _: {'healthy': True})
    monkeypatch.setattr(R146, 'predecessor_state', lambda _: {'ready': True})
    monkeypatch.setattr(R146, 'slot_a_conflicts', lambda _: [])
    calls = []
    def fail(_):
        calls.append(1)
        raise RuntimeError('uncertified AL fit')
    monkeypatch.setattr(R146, 'controller', fail)
    with pytest.raises(RuntimeError, match='uncertified'):
        R146.run(CONFIG)
    path = tmp_path / 'launch_prep' / CONFIG['tag'] / 'muscat/terminal.json'
    assert R146.read(path)['status'] == 'R146_AT_FALLBACK_QUARANTINED_NOT_PROMOTED'
    with pytest.raises(RuntimeError, match='automatic retries are forbidden'):
        R146.run(CONFIG)
    assert calls == [1]


def test_real_frozen_engine_is_bound_to_new_entry_and_builds_one_seven_quantile_ladder(monkeypatch):
    monkeypatch.setenv('PRICEFM_R141_REGION', 'AT')
    engine = R146.load_engine(CONFIG)
    assert engine.ENTRY == ENTRY and engine.REGION == 'AT'
    assert engine.OUT == R146.campaign(CONFIG)
    assert engine.source_identity is R146.source_identity
    candidate = copy.deepcopy(CONFIG['fallback_candidate']); candidate.pop('mean_AQL'); candidate.pop('split_AQL')
    candidate.pop('tau0'); candidate.pop('worst_split_AQL', None)
    rhs = [{'kind': 'rhs', 'name': 'rhs_' + str(split), 'region': 'AT', 'split': split,
            'candidate_id': candidate['candidate_id'], 'tau0': CONFIG['fallback_candidate']['tau0']}
           for split in (1, 2, 3)]
    monkeypatch.setattr(engine, 'outcome', lambda name: {'split': int(name.rsplit('_', 1)[1]), 'candidate_id': candidate['candidate_id'],
        'tau0': CONFIG['fallback_candidate']['tau0'], 'certified': True, 'AQL': 7.0})
    monkeypatch.setattr(engine, 'immutable', lambda *args: None, raising=False)
    tasks = engine.quantile_tasks({'protocol': {'regions': ['AT'], 'quantile_finalists': 1},
                                  'regional': {'AT': {'candidates': [candidate]}}}, rhs)
    assert len(tasks) == 27
    assert sum(t['kind'] == 'internal_al' for t in tasks) == 21
    assert {t['region'] for t in tasks} == {'AT'}
    assert {t['candidate_id'] for t in tasks} == {candidate['candidate_id']}
    for t in tasks:
        if t['kind'] == 'internal_al':
            assert t['parent_name'].startswith('rhs_') if t['tau'] == .5 else '_al' in t['parent_name']


def test_all_owned_source_paths_exist_before_background_preparation():
    assert all(path.is_file() for path in R146.owned_source_paths())
    assert any(path.name == '490_closeout_pricefm_stage_r146_all_region.py'
               for path in R146.owned_source_paths())


def test_changed_bank_cannot_become_new_truth_at_import(tmp_path, monkeypatch):
    config = evidence_fixture(tmp_path, monkeypatch)
    prep = R146.read(R146.source_preparation(config))
    bank = Path(next(iter(prep['bank_sha256'])))
    bank.write_bytes(b'different bank')
    with pytest.raises(RuntimeError, match='frozen source training bank differs'):
        R146.fallback_audit(config, require_clean_source=False)


def test_first_quantile_failure_never_builds_or_runs_full_fold_tasks(tmp_path, monkeypatch):
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    monkeypatch.setattr(R146, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(R146, 'complete', lambda _: False)
    monkeypatch.setattr(R146, 'fallback_audit', lambda *a, **k: {})
    monkeypatch.setattr(R146, 'prepare', lambda _: {})
    prepared = {'dependency': str(tmp_path)}
    write(R146.preparation_root(CONFIG) / 'preparation.json', prepared)
    output = R146.campaign(CONFIG)
    for name, record in CONFIG['prerequisites'].items():
        if record['kind'] == 'rhs':
            write(output / 'tasks' / (name + '.json'), {'name': name})
    write(output / 'rhs_closeout.json', {'AT': {'finalists': [CONFIG['fallback_candidate']]}})
    calls = []
    def reject_confirmation(*args):
        calls.append('AL_confirmation')
        raise RuntimeError('uncertified first AL batch')
    def forbidden(*args):
        calls.append('full')
        raise AssertionError('official full-fold work was reached')
    engine = SimpleNamespace(setup=lambda _: None, valid=lambda: prepared,
                             declared_cpus=lambda *a: list(range(8)),
                             quantile_tasks=lambda *a: [{'name': 'inner'}], batch=reject_confirmation,
                             frozen_choices=forbidden, full_tasks=forbidden)
    monkeypatch.setattr(R146, 'load_engine', lambda _: engine)
    with pytest.raises(RuntimeError, match='uncertified first AL'):
        R146.controller(CONFIG)
    assert calls == ['AL_confirmation']
    assert R146.read(output / 'blocked.json')['no_certificate_relaxation'] is True
    assert not (output / 'terminal.json').exists()


def test_release_runs_tests_before_sealing_and_rejects_failed_validation(tmp_path, monkeypatch):
    monkeypatch.setattr(R146, 'DATA', tmp_path)
    monkeypatch.setattr(R146, 'source_identity', lambda: IDENTITY)
    monkeypatch.setattr(R146, 'fallback_audit', lambda *a, **k: {'passed': True, 'source': IDENTITY})
    write(R146.source_preparation(CONFIG), {'dependency': '/frozen/r127/dependency'})
    observed_env = []
    def validation_failure(*args, **kwargs):
        observed_env.append(kwargs['env'])
        return SimpleNamespace(returncode=1, stdout='test failure')
    monkeypatch.setattr(R146.subprocess, 'run', validation_failure)
    with pytest.raises(RuntimeError, match='regression suite failed'):
        R146.release(CONFIG)
    receipt = R146.preparation_root(CONFIG) / 'release/muscat/validation.json'
    assert not receipt.exists()
    assert observed_env[0]['PRICEFM_R141_DEPENDENCY'] == '/frozen/r127/dependency'
    monkeypatch.setattr(R146.subprocess, 'run', lambda *a, **k: SimpleNamespace(returncode=0, stdout='passed'))
    result = R146.release(CONFIG)
    assert result['regression_validation']['passed'] is True
    assert len(result['regression_validation']['test_sha256']) == 5
    assert R146.release(CONFIG) == result
