"""R149 context/admission tests supplement all unchanged R148 kernel tests."""
import copy
import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('r149_resources', ROOT / 'application/scripts/pricefm/495_supervise_pricefm_stage_r149_ee_idle_resources.py')
A = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(A)
M = A.KERNEL


@pytest.fixture
def config(tmp_path):
    c = M.read(A.CONFIG)
    c['data_root'] = str(tmp_path)
    c['runtime'] = str(tmp_path / 'launch_prep' / A.TAG / 'muscat_resources')
    c['campaign_root'] = str(tmp_path / 'campaigns' / A.TAG)
    c['handoff_state'] = str(tmp_path / 'handoff.json')
    c['handoff_waiting'] = str(tmp_path / 'waiting.json')
    M.atomic(c['handoff_waiting'], {'status': 'waiting_for_both_AT_terminal_receipts', 'worker_signals': 0})
    predecessor = tmp_path / 'R148_terminal.json'
    M.atomic(predecessor, {'status': 'R148_IDLE_TASKS_COMPLETE_NOT_PROMOTED', 'cleanup_verified': True,
        'source': {'head': c['completed_predecessor']['source_head']}, 'baseline_worker_signals': 0})
    c['completed_predecessor']['path'] = str(predecessor)
    c['completed_predecessor']['sha256'] = M.digest(predecessor)
    return c


@pytest.fixture
def lease():
    return {'expires_epoch': M.time.time() + 7200, 'expires_monotonic': M.time.monotonic() + 7200,
            'boot_id': M.process(os.getpid())['boot_id'], 'initial_output_bytes': 0}


def healthy(monkeypatch):
    monkeypatch.setattr(M, 'available_memory', lambda: 300 * M.GIB)
    monkeypatch.setattr(M.shutil, 'disk_usage', lambda path: SimpleNamespace(free=500 * M.GIB))


def test_context_is_new_stage_and_frozen_default_is_unchanged():
    assert M.STAGE == 'R149'
    assert M.ENTRY == A.ENTRY and M.CONFIG == A.CONFIG and M.SCIENCE == A.SCIENCE
    assert M.REQUIRED_BRANCH == 'work/pricefm-r149-ee-origin-coverage-20261023'
    assert M.REQUIRED_UNIT == 'pricefm-r149-muscat-ee-idle-development.service'
    assert M.REQUIRE_ALL_TASKS_COMPLETE is True
    spec = importlib.util.spec_from_file_location('default_r148_context', A.KERNEL_PATH)
    default = importlib.util.module_from_spec(spec); spec.loader.exec_module(default)
    assert default.STAGE == 'R148'
    assert default.REQUIRED_BRANCH == 'work/pricefm-r148-ee-parallel-screening-20261023'
    assert default.REQUIRED_UNIT == 'pricefm-r148-muscat-ee-idle-development.service'
    assert default.ALLOWED_TASK_KINDS == ['cached_rhs_rescore']
    assert default.REQUIRE_ALL_TASKS_COMPLETE is False


def test_config_explicit_new_lease_and_separate_paths(config):
    M.validate_config(config)
    assert A.TAG in config['runtime'] and A.TAG in config['campaign_root']
    assert config['allowed_task_kinds'] == ['full_origin_replay', 'mc_panel_replay']


@pytest.mark.parametrize('field,value', [
    ('new_explicit_R149_lease_authorized', False), ('min_available_memory_gib', 191),
    ('max_workers', 3), ('lease_seconds', 7201), ('numerical_threads', 2),
    ('allowed_cpus', list(range(31))), ('allowed_task_kinds', ['cached_rhs_rescore']),
    ('unit', 'pricefm-r148-muscat-ee-idle-development.service'),
    ('runtime', '/tmp/R148/muscat_resources'), ('campaign_root', '/tmp/old_campaign'),
])
def test_context_cannot_expand_or_reuse_old_lane(config, field, value):
    config[field] = value
    with pytest.raises(RuntimeError):
        M.validate_config(config)


def test_predecessor_complete_guard_is_read_only(config, lease, monkeypatch):
    healthy(monkeypatch)
    path = Path(config['completed_predecessor']['path']); before = path.read_bytes()
    M.guard(config, lease)
    assert path.read_bytes() == before


def test_predecessor_tamper_blocks_admission(config, lease, monkeypatch):
    healthy(monkeypatch)
    Path(config['completed_predecessor']['path']).write_text('{}')
    with pytest.raises(RuntimeError, match='R148 terminal changed'):
        M.guard(config, lease)


def test_predecessor_undrained_blocks_even_if_hash_matches(config, lease, monkeypatch):
    healthy(monkeypatch)
    p = Path(config['completed_predecessor']['path']); v = M.read(p); v['cleanup_verified'] = False
    M.atomic(p, v); config['completed_predecessor']['sha256'] = M.digest(p)
    with pytest.raises(RuntimeError, match='complete and drained'):
        M.guard(config, lease)


def test_new_explicit_lease_has_its_own_deadline_and_never_renews(config, monkeypatch):
    monkeypatch.setattr(M.time, 'time', lambda: 1000)
    monkeypatch.setattr(M.time, 'monotonic', lambda: 500)
    first = M.new_lease(config, Path(config['runtime']))
    assert first['expires_epoch'] == 8200 and first['expires_monotonic'] == 7700
    monkeypatch.setattr(M.time, 'time', lambda: 9000)
    assert M.new_lease(config, Path(config['runtime'])) == first


def test_release_receipt_has_new_stage_identity(config, tmp_path, monkeypatch):
    monkeypatch.setattr(M, 'source_identity', lambda: {'head': 'new-r149', 'branch': M.REQUIRED_BRANCH})
    monkeypatch.setattr(M, 'freeze_baseline', lambda c: None)
    monkeypatch.setattr(M, 'SOURCE_PATHS', [A.ENTRY])
    value = M.release(config, tmp_path / 'release')
    assert value['status'] == 'R149_IDLE_RELEASE_FROZEN'
    assert value['source']['head'] == 'new-r149'


def test_git_uses_rebound_root_and_preserves_explicit_baseline_root(monkeypatch, tmp_path):
    roots = []
    monkeypatch.setattr(M.subprocess, 'check_output', lambda command, cwd, text: roots.append(cwd) or 'head\n')
    assert M.git('rev-parse', 'HEAD') == 'head'
    assert M.git('rev-parse', 'HEAD', root=tmp_path) == 'head'
    assert roots == [A.ROOT, tmp_path]


def test_original_R148_resource_file_remains_frozen():
    frozen = M.read(A.CONFIG)['frozen_baseline_sources'][-1]
    assert frozen['head'] == 'adce9120de82f2d3c60703957ce7e0823cd9cc7f'
    for relative, expected in frozen['sha256'].items():
        assert M.digest(Path(frozen['root']) / relative) == expected


def test_source_paths_cover_context_shared_kernel_and_all_new_stage_tests():
    paths = M.source_paths()
    assert A.ENTRY in paths and A.KERNEL_PATH in paths and A.CONFIG in paths and A.SCIENCE in paths
    assert all(path.is_file() for path in paths)


def test_actual_context_gate_inherits_idle_policy_before_payload(config, lease, monkeypatch):
    healthy(monkeypatch); monkeypatch.setattr(M, 'verify_release', lambda *a: None)
    before = M.cpu_times(); M.time.sleep(.1)
    config['allowed_cpus'] = sorted(set(range(30)) & os.sched_getaffinity(0))
    cpu = M.choose_cpu(config, before, M.cpu_times(), [])
    job = M.launch(config, Path(config['runtime']), lease, 'R149_actual_probe', cpu, payload='probe')
    try:
        assert job['process'].wait(timeout=15) == 0, Path(job['log_path']).read_text()
    finally:
        M.stop_owned([job], grace_seconds=0)


@pytest.mark.parametrize('science_complete', [False, None, True])
def test_ready_queue_empty_cannot_hide_incomplete_dependency_tasks(config, monkeypatch, science_complete):
    runtime = Path(config['runtime']); runtime.mkdir(parents=True)
    source = {'head': 'r149-frozen'}
    M.atomic(runtime / 'release.json', {'source': source})
    M.atomic(runtime / 'policy_probe.json', {'status': 'R149_IDLE_POLICY_PROBE_PASSED', 'source': source})
    for name in ('verify_release', 'verify_own_service', 'physical_cpu_check', 'guard'):
        monkeypatch.setattr(M, name, lambda *a, **kw: None)
    science = SimpleNamespace(preparation_complete=lambda: True, pending_task_names=lambda: [],
        write_closeout=lambda *a, **kw: {'status': 'partial' if not science_complete else 'complete'})
    if science_complete is not None:
        science.all_tasks_complete = lambda: science_complete
    monkeypatch.setattr(M, 'load_science', lambda: science)
    result = M.run(config, runtime)
    assert result['cleanup_verified'] is True
    if science_complete:
        assert result['status'] == 'R149_IDLE_TASKS_COMPLETE_NOT_PROMOTED'
    else:
        assert result['status'] == 'R149_IDLE_LEASE_STOPPED'
        assert 'tasks remain incomplete' in result['reason'] or 'verifier is required' in result['reason']
