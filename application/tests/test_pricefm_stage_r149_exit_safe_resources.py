"""Resource-only successor preserves original R149 producer, packets and lease."""
import copy
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / 'application/scripts/pricefm/496_supervise_pricefm_stage_r149_exit_safe_resources.py'
SPEC = importlib.util.spec_from_file_location('r149_exit_safe_adapter_test', ENTRY)
A = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(A)
M = A.KERNEL


@pytest.fixture
def recovery(tmp_path, monkeypatch):
    c = M.read(A.CONFIG)
    c.update(data_root=str(tmp_path), runtime=str(tmp_path / 'launch_prep' / A.TAG / 'muscat_resources_exit_safe'),
        campaign_root=str(tmp_path / 'campaigns' / A.TAG), handoff_state=str(tmp_path / 'handoff_state.json'),
        handoff_waiting=str(tmp_path / 'handoff_waiting.json'))
    M.atomic(c['handoff_waiting'], dict(status='waiting_for_both_AT_terminal_receipts', worker_signals=0))
    lease = dict(lease_id='original-authorized-lease', boot_id='same-boot',
        started_epoch=M.time.time()-100, expires_epoch=M.time.time()+7100,
        started_monotonic=M.time.monotonic()-100, expires_monotonic=M.time.monotonic()+7100,
        initial_output_bytes=123456)
    artifacts = {}
    for key, value in (
        ('lease_import', lease),
        ('stopped_predecessor', dict(status='R149_IDLE_LEASE_STOPPED', cleanup_verified=True,
            baseline_worker_signals=0, source=dict(head=A.SCIENCE_HEAD), lease=lease)),
        ('completed_predecessor', dict(status='R148_IDLE_TASKS_COMPLETE_NOT_PROMOTED', cleanup_verified=True,
            baseline_worker_signals=0, source=dict(head=c['completed_predecessor']['source_head'])))):
        path = tmp_path / (key+'.json')
        M.atomic(path, value)
        artifacts[key] = path
        c[key].update(path=str(path), sha256=M.digest(path))
    artifact = tmp_path / 'unchanged_original_scientific_packet.json'
    M.atomic(artifact, dict(producer_head=A.SCIENCE_HEAD, certified=True))
    snapshot = dict(scientific_source=dict(head=A.SCIENCE_HEAD), original_lease_sha256=c['lease_import']['sha256'],
        task_descriptor_count=18, artifact_sha256={str(artifact): M.digest(artifact)})
    path = tmp_path / 'snapshot.json'; M.atomic(path, snapshot)
    c['supersession_snapshot'] = dict(path=str(path), sha256=M.digest(path))
    monkeypatch.setattr(M, 'available_memory', lambda: 300*M.GIB)
    monkeypatch.setattr(M, 'owned_rss', lambda config: 0)
    monkeypatch.setattr(M.shutil, 'disk_usage', lambda p: SimpleNamespace(free=500*M.GIB))
    monkeypatch.setattr(M, 'process', lambda pid: dict(boot_id='same-boot'))
    monkeypatch.setattr(M, 'unit_properties', lambda name: dict(MainPID='0', ActiveState='inactive', ControlGroup=''))
    monkeypatch.setattr(M, 'verify_release', lambda *args: None)
    return c, lease, artifacts, artifact


def reseal(c, key, value):
    M.atomic(c[key]['path'], value)
    c[key]['sha256'] = M.digest(c[key]['path'])


def test_science_executes_absolute_original_source_without_rebinding():
    assert M.SCIENCE == A.SCIENCE and A.SCIENCE.is_absolute()
    assert A.SCIENCE_ROOT != A.ROOT
    science = M.load_science()
    assert Path(science.__file__).resolve() == A.SCIENCE
    assert science.ROOT == A.SCIENCE_ROOT and science.ENTRY == A.SCIENCE
    assert science.source_identity()['head'] == A.SCIENCE_HEAD
    assert science.read_preparation()['source']['head'] == A.SCIENCE_HEAD


def test_resource_source_paths_do_not_relabel_external_scientific_files():
    assert A.SCIENCE not in M.source_paths()
    assert all(p.is_relative_to(A.ROOT) for p in M.source_paths())
    c = M.read(A.CONFIG)
    original = next(p for p in c['frozen_baseline_sources'] if p['root'] == str(A.SCIENCE_ROOT))
    assert original['head'] == A.SCIENCE_HEAD and len(original['sha256']) == 11
    assert 'application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py' in original['sha256']
    assert 'application/config/pricefm_stage_r149_ee_origin_coverage_20261023.json' in original['sha256']
    assert all(M.digest(A.SCIENCE_ROOT/relative) == sha for relative, sha in original['sha256'].items())


def test_original_lease_is_required_and_never_created_or_renewed(recovery):
    c, lease, _, _ = recovery
    runtime = Path(c['runtime']); runtime.mkdir(parents=True)
    with pytest.raises(RuntimeError, match='exact original lease bytes'):
        M.new_lease(c, runtime)
    assert not (runtime/'lease.json').exists()
    original_bytes = Path(c['lease_import']['path']).read_bytes()
    (runtime/'lease.json').write_bytes(original_bytes)
    assert M.new_lease(c, runtime) == lease
    assert (runtime/'lease.json').read_bytes() == original_bytes
    assert M.new_lease(c, runtime)['initial_output_bytes'] == 123456


@pytest.mark.parametrize('change', ['expiry', 'monotonic', 'boot', 'growth', 'whitespace'])
def test_imported_lease_cannot_be_altered_even_with_same_values_or_later_deadline(recovery, change):
    c, lease, _, _ = recovery
    runtime = Path(c['runtime']); runtime.mkdir(parents=True)
    altered = copy.deepcopy(lease)
    if change == 'expiry': altered['expires_epoch'] += 100
    elif change == 'monotonic': altered['expires_monotonic'] += 100
    elif change == 'boot': altered['boot_id'] = 'new-boot'
    elif change == 'growth': altered['initial_output_bytes'] = 0
    M.atomic(runtime/'lease.json', altered)
    if change == 'whitespace':
        (runtime/'lease.json').write_text((runtime/'lease.json').read_text()+'\n')
    with pytest.raises(RuntimeError, match='exact original lease bytes'):
        M.new_lease(c, runtime)


@pytest.mark.parametrize('key,value', [
    ('same_original_lease_required', False), ('new_explicit_R149_lease_authorized', True),
    ('scientific_head', 'resource-head'), ('scientific_entry', '/tmp/copied_science.py'),
    ('scientific_root', '/tmp/relabelled_root'), ('max_workers', 3),
    ('unit', 'pricefm-r149-muscat-ee-idle-development.service')])
def test_adapter_scope_cannot_change_scientific_producer_or_resource_budget(recovery, key, value):
    c, _, _, _ = recovery
    M.validate_config(c)
    c[key] = value
    with pytest.raises(RuntimeError): M.validate_config(c)


def test_successor_admission_reads_original_receipts_and_preserves_lease(recovery):
    c, lease, artifacts, artifact = recovery
    before = {p: p.read_bytes() for p in [*artifacts.values(), artifact]}
    M.guard(c, lease, check_sources=True, runtime=Path(c['runtime']))
    assert all(p.read_bytes() == value for p, value in before.items())


@pytest.mark.parametrize('field,value', [('cleanup_verified', False), ('baseline_worker_signals', 1),
    ('status', 'R149_RUNNING'), ('source', {'head': 'different-producer'})])
def test_resealed_stopped_receipt_still_requires_cleanup_and_original_producer(recovery, field, value):
    c, lease, _, _ = recovery
    previous = M.read(c['stopped_predecessor']['path']); previous[field] = value
    reseal(c, 'stopped_predecessor', previous)
    with pytest.raises(RuntimeError, match='stopped and cleanup verified'): M.guard(c, lease)


@pytest.mark.parametrize('properties', [dict(MainPID='123', ActiveState='inactive', ControlGroup=''),
    dict(MainPID='0', ActiveState='active', ControlGroup=''),
    dict(MainPID='0', ActiveState='inactive', ControlGroup='/old/private/workers')])
def test_old_unit_must_be_inactive_with_no_controller_or_cgroup(recovery, monkeypatch, properties):
    c, lease, _, _ = recovery
    monkeypatch.setattr(M, 'unit_properties', lambda name: properties)
    with pytest.raises(RuntimeError, match='fully drained'): M.guard(c, lease)


def test_tampered_original_sealed_artifact_blocks_resume_before_new_worker(recovery):
    c, lease, _, artifact = recovery
    artifact.write_text('changed')
    with pytest.raises(RuntimeError, match='existing sealed science changed'):
        M.guard(c, lease, check_sources=True, runtime=Path(c['runtime']))


def test_original_lease_object_mismatch_is_rejected_without_renewal(recovery):
    c, lease, _, _ = recovery
    altered = dict(lease, initial_output_bytes=0)
    with pytest.raises(RuntimeError, match='cannot change'): M.guard(c, altered)
