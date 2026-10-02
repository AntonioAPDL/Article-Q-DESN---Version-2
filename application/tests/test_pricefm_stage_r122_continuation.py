from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RUN = _load("r122_resume_runner_test", "429_run_pricefm_stage_r122_long_memory.py")
PREP = _load("r122_resume_prep_test", "430_prepare_pricefm_stage_r122_continuation.py")
BASE = _load("r122_original_prep_test", "428_prepare_pricefm_stage_r122_long_memory_launch.py")


@pytest.fixture
def packet(tmp_path):
    prep = tmp_path / "prep"; prep.mkdir()
    campaign = tmp_path / "campaign"; (campaign / "seed3").mkdir(parents=True)
    controls, control_fits = BASE._control_rows()
    control = controls.iloc[0].to_dict()
    spec = json.loads(control["spec_json"])
    spec.update(depth=2, units=[128, 128], m_y=1560, input_fan_in=8, basin="D")
    structural = RUN.fingerprint(spec)
    candidate = {**control, "candidate_id": "search_a", "structural_sha256": structural,
                 "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
                 "input_dimension": control["input_dimension"] + 830, "readout_dimension": 257,
                 "role": "search"}
    pd.DataFrame([candidate]).to_csv(prep / "candidate_manifest.csv", index=False)
    controls.to_csv(prep / "control_manifest.csv", index=False)
    rows = []
    for seed in RUN.RESERVOIR_SEEDS:
        fit_hash = RUN.fingerprint({"structural_sha256": structural, "reservoir_seed": int(seed)})
        rows.append({**candidate, "fit_id": f"r122f_{fit_hash[:16]}", "fit_sha256": fit_hash,
                     "reservoir_seed": seed, "role": "seed3" if seed == RUN.RESERVOIR_SEEDS[2] else "search"})
    broad = pd.concat([pd.DataFrame(rows[:2]), control_fits.merge(controls.drop(columns="role"),
                       on=["candidate_id", "structural_sha256"], suffixes=("", "_candidate"))],
                      ignore_index=True)
    broad.to_csv(prep / "execution_manifest.csv", index=False)
    seed3 = pd.DataFrame(rows[2:]); seed3.to_csv(campaign / "seed3/manifest.csv", index=False)
    return prep, campaign, broad, seed3


@pytest.mark.parametrize("which", ["search", "external_control", "seed3"])
def test_worker_resolves_each_known_manifest_without_expanding_broad(packet, which):
    prep, campaign, broad, seed3 = packet
    table = seed3 if which == "seed3" else broad[broad.role.eq(which)]
    row = RUN._ridge_row(prep, campaign, str(table.iloc[0].fit_id))
    assert row.role == which
    assert len(RUN._execution(prep)) == 4
    assert len(RUN._ridge_worker_manifest(prep, campaign)) == 5


def test_unknown_worker_id_has_clear_zero_match_error(packet):
    prep, campaign, _, _ = packet
    with pytest.raises(ValueError, match="0 matches"):
        RUN._ridge_row(prep, campaign, "unknown")


def test_duplicate_or_conflicting_worker_id_is_rejected(packet):
    prep, campaign, broad, _ = packet
    pd.concat([broad, broad.iloc[:1]]).to_csv(prep / "execution_manifest.csv", index=False)
    with pytest.raises(ValueError, match="duplicate fit IDs"):
        RUN._ridge_row(prep, campaign, str(broad.iloc[0].fit_id))


@pytest.mark.parametrize("field,value,message", [
    ("reservoir_seed", 2026092501, "seed is invalid"),
    ("fit_sha256", "bad", "fingerprint differs"),
    ("spec_json", '{}', "specification differs"),
    ("test_access_authorized", True, "test access"),
    ("input_dimension", 1, "input_dimension differs"),
    ("role", "search", "invalid role"),
    ("candidate_id", "missing", "candidate has 0 matches"),
])
def test_seed3_contract_corruption_is_rejected_before_fitting(packet, field, value, message):
    prep, campaign, _, seed3 = packet
    original_id = str(seed3.iloc[0].fit_id)
    seed3.loc[0, field] = value
    seed3.to_csv(campaign / "seed3/manifest.csv", index=False)
    with pytest.raises(ValueError, match=message):
        RUN._ridge_row(prep, campaign, original_id)


def _complete(campaign, row):
    root = RUN._fit_root(campaign, str(row.fit_id)); root.mkdir(parents=True)
    (root / "terminal.json").write_text(json.dumps({
        "status": "completed_r122_ridge_cell", "fit_sha256": str(row.fit_sha256), "test_opened": False,
        "fit_id": str(row.fit_id), "candidate_id": str(row.candidate_id),
        "reservoir_seed": int(row.reservoir_seed), "role": str(row.role),
    }))
    return root


def test_completed_broad_is_not_scheduled_and_seed3_dispatch_reaches_worker(packet, monkeypatch):
    prep, campaign, broad, seed3 = packet
    for row in broad.itertuples(index=False):
        _complete(campaign, row)
    args = RUN.parser().parse_args(["--cpu-list", "0"])
    args.artifact_repo = campaign.parent
    assert RUN._ridge_tasks(args, prep, campaign, SCRIPTS.parents[2], broad, "broad") == []
    tasks = RUN._ridge_tasks(args, prep, campaign, SCRIPTS.parents[2], seed3, "seed3")
    assert len(tasks) == 1
    worker_args = RUN.parser().parse_args(tasks[0][1][2:])
    (prep / "launch_control.json").write_text('{}')
    seen = []
    def data_probe(control, spec):
        seen.append(spec)
        raise RuntimeError("isolated data boundary reached")
    monkeypatch.setattr(RUN, "_selection_arrays", data_probe)
    with pytest.raises(RuntimeError, match="data boundary reached"):
        RUN.ridge_cell(worker_args)
    assert seen[0]["seed"] == RUN.RESERVOIR_SEEDS[2]
    assert seen[0]["m_y"] == 1560
    assert len(RUN._execution(prep)) == 4
    _complete(campaign, seed3.iloc[0])
    assert RUN.ridge_cell(worker_args)["test_opened"] is False
    assert len(seen) == 1  # A valid completed worker must return without refitting.
    assert RUN._ridge_tasks(args, prep, campaign, SCRIPTS.parents[2], seed3, "seed3") == []


def test_dispatch_rejects_rows_that_differ_from_the_frozen_manifest(packet):
    prep, campaign, _, seed3 = packet
    args = RUN.parser().parse_args(["--cpu-list", "0"])
    with pytest.raises(ValueError, match="queued fit_sha256 differs"):
        RUN._ridge_tasks(args, prep, campaign, SCRIPTS.parents[2],
                         seed3.assign(fit_sha256="different"), "seed3")


def test_two_seed_and_three_seed_rankings_remain_distinct(packet):
    _, _, broad, seed3 = packet
    data = pd.concat([broad[broad.role.eq("search")], seed3]).reset_index(drop=True)
    for name in ("mean_AQL", "mean_late_AQL", "worst_AQL", "mean_coverage", "mean_width"):
        data[name] = [1., 2., 3.]
    assert RUN._structural_ranking(data.iloc[:2], 2).iloc[0].seed_count == 2
    assert RUN._structural_ranking(data.iloc[:2], 3).empty
    assert RUN._structural_ranking(data, 3).iloc[0].seed_count == 3


def test_reuse_inventory_binds_all_completed_artifacts_and_detects_changes(packet):
    prep, campaign, broad, _ = packet
    row = broad.iloc[0]; root = _complete(campaign, row)
    terminal = json.loads((root / "terminal.json").read_text()); terminal["mean_AQL"] = 1.
    (root / "terminal.json").write_text(json.dumps(terminal))
    spec = json.loads(row.spec_json); spec["seed"] = int(row.reservoir_seed)
    assert spec["basin"] == "D"
    spec = RUN.RT.normalize_spec(spec)
    assert "basin" not in spec
    (root / "contract.json").write_text(json.dumps({
        "fit_sha256": row.fit_sha256, "candidate_id": row.candidate_id, "spec": spec,
        "reservoir_seed": int(row.reservoir_seed), "role": row.role, "test_opened": False,
    }))
    pd.DataFrame({"split": [1, 2, 3], "AQL": [1., 1., 1.], "late_AQL": [1., 1., 1.],
        "median_MAE": [1., 1., 1.], "interval_80_width": [1., 1., 1.],
        "interval_80_coverage": [.8, .8, .8]}).to_csv(root / "validation_metrics.csv", index=False)
    np.savez_compressed(root / "training_statistics.npz", value=np.eye(2))
    inventory = PREP.audit_broad_reuse(campaign, broad.iloc[:1])
    assert len(inventory) == 4
    inventory.to_csv(prep / "reused_output_inventory.csv", index=False)
    (prep / "launch_control.json").write_text('{"continuation": {}}')
    assert RUN._reuse_inventory_changes(prep, campaign) == []
    (root / "training_statistics.npz").write_bytes(b"changed")
    assert RUN._reuse_inventory_changes(prep, campaign) == [str((root / "training_statistics.npz").relative_to(campaign))]
    contract = json.loads((root / "contract.json").read_text()); contract["spec"]["rho"] = .9
    (root / "contract.json").write_text(json.dumps(contract))
    with pytest.raises(RuntimeError, match="terminal/contract differs"):
        PREP.audit_broad_reuse(campaign, broad.iloc[:1])


def test_queue_records_failure_evidence_and_empty_resume_counts(tmp_path, monkeypatch):
    def fail(*args):
        raise RuntimeError("isolated failure")
    monkeypatch.setattr(RUN, "_command", fail)
    state = RUN._run_queue([("a", ["fake"], tmp_path / "a.log")], [0], tmp_path,
                           tmp_path / "progress.json", 320)
    assert state["failed_this_resume"] == 1
    assert state["failures"][0]["error"] == "isolated failure"
    empty = RUN._run_queue([], [0], tmp_path, tmp_path / "empty.json", 6400)
    assert empty["scheduled_this_resume"] == 0
    assert empty["expected_total"] == 6400


def test_continuation_rejects_changed_training_inputs_and_seed_manifest(packet):
    prep, campaign, _, _ = packet
    window = campaign / "processed/windows/fold_1/train_L3120_H96_contained_half_open.npz"
    window.parent.mkdir(parents=True); window.write_bytes(b"frozen training data")
    pd.DataFrame([{"path": str(window.relative_to(campaign)), "bytes": window.stat().st_size,
                   "sha256": RUN.sha256_file(window)}]).to_csv(prep / "reused_input_inventory.csv", index=False)
    pd.DataFrame(columns=["path", "bytes", "sha256"]).to_csv(prep / "reused_output_inventory.csv", index=False)
    (prep / "launch_control.json").write_text(json.dumps({"continuation": {
        "seed3_manifest_sha256": RUN.sha256_file(campaign / "seed3/manifest.csv")}}))
    assert RUN._reuse_inventory_changes(prep, campaign) == []
    window.write_bytes(b"changed")
    assert RUN._reuse_inventory_changes(prep, campaign) == [str(window.relative_to(campaign))]
    (campaign / "seed3/manifest.csv").write_text("changed manifest")
    assert "seed3/manifest.csv" in RUN._reuse_inventory_changes(prep, campaign)


def test_numerical_threads_are_bounded_before_imports():
    runner = SCRIPTS / "429_run_pricefm_stage_r122_long_memory.py"
    script = f'import runpy, os; runpy.run_path({str(runner)!r}); print(os.environ["OPENBLAS_NUM_THREADS"])'
    result = subprocess.run([sys.executable, "-c", script], env={**os.environ,
                            "OPENBLAS_NUM_THREADS": "12", "PYTHONPATH": str(SCRIPTS)},
                            text=True, capture_output=True, check=True)
    assert result.stdout.strip() == "1"


def test_continuation_requires_new_output_and_clean_task_branch(tmp_path, monkeypatch):
    from argparse import Namespace
    output = tmp_path / "new"; output.mkdir()
    args = Namespace(original_prep=tmp_path / "old", output_dir=output,
                     campaign_root=tmp_path / "campaign", code_root=tmp_path)
    with pytest.raises(FileExistsError, match="never overwrite"):
        PREP.prepare(args)
    output.rmdir()
    monkeypatch.setattr(PREP, "_git", lambda *args: " M unrelated.R")
    with pytest.raises(RuntimeError, match="clean committed worktree"):
        PREP.prepare(args)


def test_closeouts_require_exact_broad_and_seed3_counts(tmp_path, monkeypatch):
    records = []
    for index in range(3200):
        for seed in RUN.RESERVOIR_SEEDS[:2]:
            records.append({"candidate_id": str(index), "structural_sha256": str(index),
                "role": "search" if index < 3199 else "external_control", "reservoir_seed": seed,
                "mean_AQL": 1., "mean_late_AQL": 1., "worst_AQL": 1.,
                "mean_coverage": .8, "mean_width": 1.})
    broad = pd.DataFrame(records)
    monkeypatch.setattr(RUN, "_execution", lambda prep: broad)
    monkeypatch.setattr(RUN, "_fit_metrics", lambda campaign, manifest: manifest.copy())
    ranking, metrics = RUN._broad_closeout(tmp_path, tmp_path)
    assert len(ranking) == 3199
    assert len(metrics) == 6400
    top = ranking.head(320).candidate_id.astype(str)
    seed3 = broad[broad.candidate_id.isin(top)].drop_duplicates("candidate_id").copy()
    seed3["reservoir_seed"] = RUN.RESERVOIR_SEEDS[2]
    seed3["role"] = "seed3"
    robust = RUN._third_seed_closeout(tmp_path, tmp_path, broad, seed3)
    assert len(robust) == 320
    assert set(robust.seed_count) == {3}
    assert len(pd.read_csv(tmp_path / "seed3/closeout/top96.csv")) == 96
    with pytest.raises(RuntimeError, match="319/320"):
        RUN._third_seed_closeout(tmp_path, tmp_path, broad, seed3.iloc[1:])
    monkeypatch.setattr(RUN, "_execution", lambda prep: broad.iloc[2:])
    with pytest.raises(RuntimeError, match="search=3198"):
        RUN._broad_closeout(tmp_path, tmp_path)


def test_resume_plan_only_never_loads_training_data(packet, monkeypatch):
    prep, campaign, broad, _ = packet
    for row in broad.itertuples(index=False):
        _complete(campaign, row)
    args = RUN.parser().parse_args(["--cpu-list", "0", "--resume-plan-only",
        "--prep-dir", str(prep), "--campaign-root", str(campaign)])
    (prep / "launch_control.json").write_text('{}')
    (prep / "summary.json").write_text('{}')
    monkeypatch.setattr(RUN, "_cpus", lambda *args: [0])
    monkeypatch.setattr(RUN.os, "sched_setaffinity", lambda *args: None)
    monkeypatch.setattr(RUN, "_preflight", lambda *args: {})
    def prohibited(*args):
        raise AssertionError("planning must not fit or load data")
    monkeypatch.setattr(RUN, "_prepare_processed", prohibited)
    monkeypatch.setattr(RUN, "_run_queue", prohibited)
    result = RUN.controller(args)
    assert result["broad_tasks"] == 0
    assert result["third_seed_tasks"] == 1
    assert result["test_opened"] is False


def test_continuation_does_not_regenerate_processed_windows(tmp_path, monkeypatch):
    source = tmp_path / "source"; source.mkdir()
    campaign = tmp_path / "campaign"; campaign.mkdir()
    config = tmp_path / "prep/data_configs/data.yaml"; config.parent.mkdir(parents=True)
    (config.parent.parent / "target_contract.json").write_text('{}')
    (campaign / "processed_audit.json").write_text(json.dumps({
        "status": "R122_PROCESSED_PACKET_READY", "test_opened": False}))
    control = {"runtime_processed": str(campaign / "processed"), "source_processed": str(source),
               "continuation": {}, "data_config": str(config)}
    monkeypatch.setattr(RUN.RT, "active_regions", lambda spec: ["BG"])
    def prohibited(*args):
        raise AssertionError("continuation must not rebuild windows")
    def data_boundary(*args):
        raise RuntimeError("existing windows read")
    monkeypatch.setattr(RUN, "_command", prohibited)
    monkeypatch.setattr(RUN.RT, "load_windows", data_boundary)
    with pytest.raises(RuntimeError, match="existing windows read"):
        RUN._prepare_processed(control, campaign, tmp_path, 0)
