from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))
import pricefm_r123_recovery as REC


def load(name, filename):
    loader = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(loader); loader.loader.exec_module(module)
    return module


RUN = load("r123_recovery_test_original", "433_run_pricefm_stage_r123_connectivity.py")
DRIVER = load("r123_recovery_test_driver", "434_resume_pricefm_stage_r123_resources.py")


def csv_file(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["fit_id", "fit_sha256"])
        writer.writeheader(); writer.writerows(records)


@pytest.fixture
def screening(tmp_path):
    prep, campaign = tmp_path / "prep", tmp_path / "campaign"
    csv_file(prep / "execution_manifest.csv", [{"fit_id": "a", "fit_sha256": "A"},
                                               {"fit_id": "b", "fit_sha256": "B"}])
    csv_file(campaign / "seed3/manifest.csv", [{"fit_id": "c", "fit_sha256": "C"}])
    for fit, identity in (("a", "A"), ("c", "C")):
        root = campaign / "ridge/fits" / fit; root.mkdir(parents=True)
        artifacts = {}
        for name in ("contract.json", "training_statistics.npz", "validation_metrics.csv"):
            (root / name).write_bytes(b"frozen evidence"); artifacts[name] = REC.digest(root / name)
        REC.write(root / "terminal.json", {"status": "completed_r123_ridge_cell", "fit_sha256": identity,
                  "test_opened": False, "output_sha256": artifacts})
    REC.write(campaign / "ridge/fits/b/rejected_washout.json", {"passed": False})
    return prep, campaign


def test_complete_screening_is_reused_and_hashes_preserved(screening):
    prep, campaign = screening
    ledger = REC.audit_ridge(prep, campaign, 3)
    assert (ledger["fitted"], ledger["washout_excluded"]) == (2, 1)
    assert len(ledger["evidence_sha256"]) == 9 and not ledger["screening_refits_authorized"]
    REC.verify_evidence(ledger)


@pytest.mark.parametrize("problem", ["target", "test", "status", "corrupt", "missing", "ambiguous", "exclusion", "duplicate"])
def test_bad_screening_blocks_without_deleting_it(screening, problem):
    prep, campaign = screening; root = campaign / "ridge/fits/a"
    value = REC.read(root / "terminal.json")
    if problem == "target": value["fit_sha256"] = "wrong"
    if problem == "test": value["test_opened"] = True
    if problem == "status": value["status"] = "partial"
    REC.write(root / "terminal.json", value)
    if problem == "corrupt": (root / "training_statistics.npz").write_bytes(b"corrupted")
    if problem == "missing": (root / "terminal.json").unlink()
    if problem == "ambiguous": REC.write(root / "rejected_washout.json", {"passed": False})
    if problem == "exclusion": REC.write(campaign / "ridge/fits/b/rejected_washout.json", {"passed": True})
    if problem == "duplicate": csv_file(campaign / "seed3/manifest.csv", [{"fit_id": "a", "fit_sha256": "A"}])
    before = sorted(str(p) for p in campaign.rglob("*") if p.is_file())
    with pytest.raises((RuntimeError, OSError)): REC.audit_ridge(prep, campaign, 3)
    assert before == sorted(str(p) for p in campaign.rglob("*") if p.is_file())


def test_changed_completed_evidence_blocks_completion(screening):
    prep, campaign = screening; ledger = REC.audit_ridge(prep, campaign, 3)
    (campaign / "ridge/fits/a/contract.json").write_bytes(b"different target")
    with pytest.raises(RuntimeError, match="evidence changed"): REC.verify_evidence(ledger)


def test_metadata_archive_and_marker_resolution_preserve_old_evidence(tmp_path):
    campaign, attempt = tmp_path / "campaign", tmp_path / "campaign/attempts/02"
    REC.write(campaign / "blocked.json", {"error": "old CPU pool"})
    REC.write(campaign / "broad/progress.json", {"complete": 1200})
    (campaign / "controller_attempt_01.log").write_text("original failure\n")
    (campaign / "controller_attempt_02.log").write_text("current writer\n")
    archive = REC.archive_metadata(campaign, attempt, campaign / "controller_attempt_02.log")
    assert "controller_attempt_02.log" not in archive
    assert not any("attempts/" in p for p in archive)
    REC.clear_archived_block(campaign, attempt, archive)
    assert not (campaign / "blocked.json").exists()
    assert REC.read(attempt / "previous_metadata/blocked.json")["error"] == "old CPU pool"
    assert (campaign / "controller_attempt_01.log").read_text() == "original failure\n"


def test_changed_blocked_marker_is_not_removed(tmp_path):
    campaign, attempt = tmp_path / "campaign", tmp_path / "campaign/attempts/02"
    REC.write(campaign / "blocked.json", {"error": "old"})
    archive = REC.archive_metadata(campaign, attempt)
    REC.write(campaign / "blocked.json", {"error": "new controller"})
    with pytest.raises(RuntimeError, match="changed"): REC.clear_archived_block(campaign, attempt, archive)
    assert REC.read(campaign / "blocked.json")["error"] == "new controller"


@pytest.fixture
def affinity(monkeypatch):
    state = {"mask": {0, 1, 2}}
    monkeypatch.setattr(REC.os, "sched_getaffinity", lambda pid: set(state["mask"]))
    monkeypatch.setattr(REC.os, "sched_setaffinity", lambda pid, mask: state.update(mask=set(mask)))
    return state


def adapter(tmp_path, function, permitted=range(9), attempts=3):
    return REC.FreshPoolPreflight(function, permitted, tmp_path / "attempt",
        {"resource_attempts": attempts, "resource_backoff_seconds": 30}, tmp_path / "campaign", {})


def test_each_phase_reselects_from_original_permitted_mask(tmp_path, affinity):
    observations = []
    def original(args, control):
        observations.append(REC.os.sched_getaffinity(0))
        return [3, 4, 5] if len(observations) == 1 else [6, 7, 8]
    gate = adapter(tmp_path, original)
    args = SimpleNamespace(workers=3); control = {"tau0": .0001, "prior_center": 0}
    before = dict(control)
    assert gate(args, control) == [3, 4, 5]
    assert affinity["mask"] == {3, 4, 5}
    assert gate(args, control) == [6, 7, 8]
    assert affinity["mask"] == {6, 7, 8}
    assert observations == [set(range(9)), set(range(9))] and control == before


def test_original_physical_core_gate_is_retained(tmp_path, affinity, monkeypatch):
    monkeypatch.setattr(RUN.BACKEND, "_cpu_snapshot", lambda interval: {c: 100 if c < 6 else 0 for c in range(36)})
    monkeypatch.setattr(RUN.BACKEND, "_physical", lambda c: (0, c // 2))
    real_path = RUN.Path
    monkeypatch.setattr(RUN, "Path", lambda p: SimpleNamespace(read_text=lambda: "MemAvailable: 314572800 kB\n")
                        if str(p) == "/proc/meminfo" else real_path(p))
    monkeypatch.setattr(RUN.shutil, "disk_usage", lambda path: SimpleNamespace(free=300 * 2**30))
    args = SimpleNamespace(workers=9, campaign_root=tmp_path / "campaign")
    args.campaign_root.mkdir()
    control = {"python_executable": sys.executable, "python_prefix": sys.prefix, "frozen_sources": [],
               "runtime_versions": {"python": sys.version, "numpy": RUN.np.__version__,
                                    "pandas": RUN.pd.__version__, "scipy": RUN.scipy.__version__}}
    affinity["mask"] = set(range(0, 18, 2))
    with pytest.raises(RuntimeError, match="only 6"): RUN.preflight(args, control)
    cpus = adapter(tmp_path, RUN.preflight, range(36))(args, control)
    assert cpus == list(range(6, 24, 2))
    assert len({c // 2 for c in cpus}) == 9


def test_transient_contention_retries_but_preserves_target(tmp_path, affinity, monkeypatch):
    calls, sleeps = [], []
    def original(args, control):
        calls.append(dict(control))
        if len(calls) < 3: raise RuntimeError("only 2 idle physical cores, need 3")
        return [3, 4, 5]
    monkeypatch.setattr(REC.time, "sleep", sleeps.append)
    control = {"tau0": .001, "workers": 3}
    assert adapter(tmp_path, original)(SimpleNamespace(workers=3), control) == [3, 4, 5]
    assert calls == [control] * 3 and sleeps == [30, 30]


def test_exhausted_resource_retries_stop_scheduling(tmp_path, affinity, monkeypatch):
    calls = []
    def original(args, control):
        calls.append(1); raise RuntimeError("only 2 idle physical cores, need 3")
    monkeypatch.setattr(REC.time, "sleep", lambda value: None)
    with pytest.raises(RuntimeError, match="only 2"): adapter(tmp_path, original)(SimpleNamespace(workers=3), {})
    assert len(calls) == 3
    assert REC.read(tmp_path / "attempt/live.json")["status"] == "WAITING_FOR_IDLE_CORES"


@pytest.mark.parametrize("message", ["resource floor: disk=190", "Python environment differs", "source/input changed"])
def test_non_cpu_failures_are_never_retried_or_bypassed(tmp_path, affinity, message):
    calls = []
    def original(args, control):
        calls.append(1); raise RuntimeError(message)
    with pytest.raises(RuntimeError, match=message): adapter(tmp_path, original)(SimpleNamespace(workers=3), {})
    assert len(calls) == 1


@pytest.mark.parametrize("cpus", [[3, 3, 4], [3, 4], [3, 4, 99]])
def test_invalid_core_pools_fail_closed(tmp_path, affinity, cpus):
    with pytest.raises(RuntimeError, match="invalid CPU pool"):
        adapter(tmp_path, lambda args, control: cpus)(SimpleNamespace(workers=3), {})


def test_worker_count_cannot_change_the_normal_posterior_contract(tmp_path):
    stats = tmp_path / "stats"; stats.mkdir(); REC.write(stats / "terminal.json", {"hash": "fixed"})
    control = {"normal_runtime": "/frozen/runtime", "rhs_max_iter": 2000}
    a = RUN.BACKEND._normal_contract("fit", stats, tmp_path / "output", .0001, dict(control, workers=15), tmp_path)
    b = RUN.BACKEND._normal_contract("fit", stats, tmp_path / "output", .0001, dict(control, workers=9), tmp_path)
    assert a == b and a["test_access_authorized"] is False


def test_resource_identity_is_immutable(tmp_path):
    REC.immutable(tmp_path / "identity.json", {"fitting_head": "frozen", "workers": 15})
    with pytest.raises(RuntimeError): REC.immutable(tmp_path / "identity.json", {"fitting_head": "new", "workers": 15})


def test_completed_screening_queue_stays_empty(tmp_path):
    seen = []
    queue = REC.ResumeQueue(lambda *args, **kwargs: seen.append(args) or {"scheduled": 0}, tmp_path)
    result = queue([], [1, 2], tmp_path, tmp_path / "broad/progress.json", 1248, fail_fast=True)
    assert result["scheduled"] == 0 and seen[0][0] == []
    assert REC.read(tmp_path / "queue_events.json")[0]["expected_total"] == 1248


def test_screening_refit_is_rejected_before_dispatch(tmp_path):
    called = []
    queue = REC.ResumeQueue(lambda *args, **kwargs: called.append(1), tmp_path)
    with pytest.raises(RuntimeError, match="refuses a screening refit"):
        queue([("bad", ["python", "433.py", "--mode", "ridge-cell"], tmp_path / "log")],
              [1], tmp_path, tmp_path / "progress.json", 1)
    assert not called


def test_rhs_queue_is_passed_through_without_target_changes(tmp_path):
    tasks = [("fit", ["Rscript", "frozen.R", "--contract", "same.json"], tmp_path / "fit.log")]
    seen = []
    queue = REC.ResumeQueue(lambda *args, **kwargs: seen.append((args, kwargs)) or "ok", tmp_path)
    assert queue(tasks, [1], tmp_path, tmp_path / "progress.json", 90, fail_fast=True) == "ok"
    assert seen[0][0][0] is tasks and seen[0][1] == {"fail_fast": True}


def recovery_args(tmp_path):
    campaign = tmp_path / "campaigns" / DRIVER.TAG; campaign.mkdir(parents=True)
    prep = tmp_path / "prep" / DRIVER.TAG; prep.mkdir(parents=True)
    return SimpleNamespace(protocol=SCRIPTS.parents[2] / "application/config/pricefm_stage_r123_resume_protocol_20261004.json",
        workers=9, campaign_root=campaign, prep_dir=prep, attempt_id="unit_01", mode="controller",
        frozen_code_root=tmp_path / "frozen", log_file=None)


def test_controller_lock_race_never_overwrites_other_controller_state(tmp_path, monkeypatch):
    args = recovery_args(tmp_path); REC.write(args.campaign_root / "blocked.json", {"keep": "original"})
    original = lambda *args: [1] * 9
    original_queue = lambda *args, **kwargs: None
    def locked(args): raise BlockingIOError("other controller obtained the lock")
    fake = SimpleNamespace(preflight=original, BACKEND=SimpleNamespace(_run_queue=original_queue),
                           parser=RUN.parser, controller=locked)
    monkeypatch.setattr(DRIVER, "load_frozen", lambda root: fake)
    monkeypatch.setattr(DRIVER, "audit", lambda *args: ({"evidence_sha256": {}}, {}))
    with pytest.raises(BlockingIOError): DRIVER.main(args)
    assert REC.read(args.campaign_root / "blocked.json") == {"keep": "original"}
    assert REC.read(args.campaign_root / "attempts/unit_01/live.json")["status"] == "LOCK_CONFLICT"
    assert fake.preflight is original and fake.BACKEND._run_queue is original_queue


def test_active_campaign_lock_prevents_audit_and_launch(tmp_path, monkeypatch):
    args = recovery_args(tmp_path); calls = []
    monkeypatch.setattr(DRIVER, "load_frozen", lambda root: calls.append(1))
    with (args.campaign_root / "controller.lock").open("a+") as lock:
        DRIVER.fcntl.flock(lock, DRIVER.fcntl.LOCK_EX | DRIVER.fcntl.LOCK_NB)
        with pytest.raises(BlockingIOError): DRIVER.main(args)
    assert not calls


def test_remaining_fit_counts_exclude_companions(tmp_path):
    assert REC.remaining_primary_fits(tmp_path)["remaining_primary_fits"] == 213
    for path in ("rhs/center/fits/a/terminal.json", "rhs/pilot/fits/b/terminal.json",
                 "al_internal/a/split=1/quantiles/al/tau=0.50/terminal.json",
                 "al_internal/a/split=1/companions/cap750/tau=0.50/terminal.json"):
        REC.write(tmp_path / path, {})
    remaining = REC.remaining_primary_fits(tmp_path)
    assert remaining["normal_remaining"] == 148 and remaining["al_remaining"] == 62
    assert remaining["remaining_primary_fits"] == 210
