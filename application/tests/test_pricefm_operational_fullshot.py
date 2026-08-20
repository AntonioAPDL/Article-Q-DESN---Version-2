from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPO_ROOT / "application" / "scripts" / "pricefm"
sys.path.insert(0, str(SCRIPT_ROOT))

import pricefm_operational_fullshot as common


def load_script(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prepare_module = load_script("pricefm_prepare_operational", "190_prepare_pricefm_operational_fullshot.py")
phase1_module = load_script("pricefm_select_phase1", "192_select_pricefm_operational_phase1.py")
phase2_module = load_script("pricefm_prepare_phase2", "193_prepare_pricefm_operational_phase2.py")
winner_module = load_script("pricefm_select_winners", "194_select_pricefm_operational_winners.py")
test_module = load_script("pricefm_score_test", "195_score_pricefm_operational_test.py")
closeout_module = load_script("pricefm_closeout", "196_closeout_pricefm_operational_fullshot.py")
campaign_module = load_script("pricefm_campaign", "197_launch_pricefm_operational_campaign.py")
elastic_module = load_script(
    "pricefm_elastic_campaign", "198_launch_pricefm_operational_elastic_campaign.py"
)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def test_common_metrics_graph_deduplication_and_seed_contract() -> None:
    regions = ["A", "B", "C"]
    adjacency = {"A": ["A", "B"], "B": ["A", "B", "C"], "C": ["B", "C"]}
    rows = common.graph_mask_rows(adjacency, regions)
    canonical = [row for row in rows if row["is_canonical"]]
    assert len(rows) == 33
    assert len(canonical) == 8
    assert common.deterministic_seed("x", 1) == common.deterministic_seed("x", 1)
    assert common.deterministic_seed("x", 1) != common.deterministic_seed("x", 2)

    y_true = np.array([[0.0, 2.0]])
    prediction = np.stack([y_true, y_true, y_true], axis=-1)
    metrics = common.model_metrics(y_true, prediction, [0.1, 0.5, 0.9])
    assert metrics == {"AQL": 0.0, "AQCR": 0.0, "MAE": 0.0, "RMSE": 0.0}


def test_preparation_uses_train_only_scalers_and_never_reads_test_predictions(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    regions = ["A", "B"]
    upstream = tmp_path / "upstream"
    (upstream / "PriceFM").mkdir(parents=True)
    (upstream / "PriceFM" / "data.py").write_text(
        "def graph_adj_matrix():\n"
        "    adjacency_dict = {'A': ['A', 'B'], 'B': ['A', 'B']}\n"
        "    return adjacency_dict\n",
        encoding="utf-8",
    )
    for filename in ("model.py", "pipeline.py"):
        (upstream / "PriceFM" / filename).write_text("# fixture\n", encoding="utf-8")
    (upstream / "FM_Tutorials.ipynb").write_text("{}\n", encoding="utf-8")

    timestamps = pd.date_range("2021-12-31 23:00:00+00:00", periods=7 * 96 + 1, freq="15min")
    raw = pd.DataFrame({"time_utc": timestamps})
    for offset, region in enumerate(regions):
        base = np.arange(len(raw), dtype=float) + offset
        raw[f"{region}-load"] = base + 1
        raw[f"{region}-solar"] = base % 17
        raw[f"{region}-wind"] = base % 23
        raw[f"{region}-price"] = base / 10
    raw_path = tmp_path / "raw.csv"
    raw.to_csv(raw_path, index=False)
    config = {
        "pricefm": {
            "time_col": "time_utc",
            "regions": regions,
            "splits": [{
                "fold": 1,
                "train": ["2022-01-01", "2022-01-03"],
                "val": ["2022-01-03", "2022-01-05"],
                "test": ["2022-01-05", "2022-01-07"],
            }],
            "windows": {"lag_window": 4, "lead_window": 4},
        }
    }
    config_path = tmp_path / "config.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")
    monkeypatch.setattr(prepare_module, "git_revision", lambda _: "fixture-commit")
    monkeypatch.setattr(prepare_module, "pip_freeze", lambda: "fixture==1\n")
    root = tmp_path / "artifacts"
    result = prepare_module.prepare(argparse.Namespace(
        config=str(config_path),
        raw_csv=str(raw_path),
        upstream_root=str(upstream),
        artifact_root=str(root),
        reference_window_root="",
        strict_source=False,
        force=False,
    ))
    assert result["n_windows"] == 6
    assert result["n_phase1_trials"] == 3
    assert result["n_canonical_phase2_trials"] == 4
    assert result["fits_models"] is False
    assert result["reads_test_predictions"] is False
    scaler = np.load(root / "data" / "scalers" / "fold_1" / "region=A.npz")
    train = raw.loc[(raw.time_utc >= "2021-12-31 23:00:00+00:00") & (raw.time_utc < "2022-01-02 23:00:00+00:00")]
    assert np.isclose(scaler["y_center"][0], train["A-price"].median())


def make_selection_fixture(root: Path) -> list[str]:
    regions = [f"R{index:02d}" for index in range(38)]
    common.atomic_write_json(root / "provenance" / "protocol.json", {
        "run_tag": "fixture", "regions": regions
    })
    phase1_rows = []
    for fold in (1, 2, 3):
        for replicate in (1, 2, 3):
            trial_id = f"p1_f{fold}_rep{replicate}"
            trial_dir = root / "phase1" / "trials" / trial_id
            trial_dir.mkdir(parents=True)
            checkpoint = trial_dir / "best_model.keras"
            checkpoint.write_bytes(f"{trial_id}\n".encode())
            metrics = [{
                "trial_id": trial_id,
                "phase": "phase1",
                "fold": fold,
                "region": region,
                "canonical_degree": "phase1",
                "replicate": replicate,
                "seed": replicate,
                "n_origins": 2,
                "AQL": 1.0 + replicate / 100,
                "AQCR": 0,
                "MAE": 1,
                "RMSE": 1,
            } for region in regions]
            metric_path = trial_dir / "validation_metrics.csv"
            write_csv(metric_path, metrics)
            common.atomic_write_json(trial_dir / "status.json", {
                "status": "completed",
                "checkpoint": str(checkpoint),
                "checkpoint_sha256": common.sha256_file(checkpoint),
                "validation_metrics": str(metric_path),
                "validation_metrics_sha256": common.sha256_file(metric_path),
            })
            phase1_rows.append({
                "task_kind": "fit", "phase": "phase1", "trial_id": trial_id,
                "fold": fold, "region": "", "canonical_degree": "", "mask_hash": "",
                "mask_json": "", "replicate": replicate, "seed": replicate,
                "epochs": 1, "batch_size": 1, "initializer_checkpoint": "",
                "initializer_sha256": "", "trial_dir": str(trial_dir),
            })
    write_csv(root / "phase1" / "trial_manifest.csv", phase1_rows)
    phase1_module.select_phase1(root)

    mask_rows = []
    for region_index, region in enumerate(regions):
        count = 10 if region_index < 7 else 9
        for degree in range(count):
            mask = [1 if item == region or index < degree else 0 for index, item in enumerate(regions)]
            mask[region_index] = 1
            mask_rows.append({
                "region": region,
                "degree": degree,
                "canonical_degree": degree,
                "is_canonical": True,
                "mask_hash": common.sha256_payload(mask),
                "n_active_regions": sum(mask),
                "active_regions_json": json.dumps([item for item, active in zip(regions, mask) if active]),
                "mask_json": json.dumps(mask, separators=(",", ":")),
                "eccentricity": count - 1,
            })
    assert len(mask_rows) == 349
    write_csv(root / "graph" / "canonical_masks.csv", mask_rows)
    phase2_module.prepare_phase2(root)
    manifest = common.read_csv_rows(root / "phase2" / "screen" / "trial_manifest.csv")
    checkpoint = root / "phase2" / "shared_fixture.keras"
    checkpoint.write_bytes(b"phase2 fixture\n")
    checkpoint_hash = common.sha256_file(checkpoint)
    for row in manifest:
        trial_dir = Path(row["trial_dir"])
        trial_dir.mkdir(parents=True)
        metric_path = trial_dir / "validation_metrics.csv"
        write_csv(metric_path, [{
            "trial_id": row["trial_id"], "phase": "phase2", "fold": row["fold"],
            "region": row["region"], "canonical_degree": row["canonical_degree"],
            "replicate": 1, "seed": row["seed"], "n_origins": 2,
            "AQL": 2.0 + int(row["canonical_degree"]), "AQCR": 0, "MAE": 2, "RMSE": 2,
        }])
        common.atomic_write_json(trial_dir / "status.json", {
            "status": "completed", "checkpoint": str(checkpoint),
            "checkpoint_sha256": checkpoint_hash,
        })
    return regions


def test_full_validation_selection_freeze_has_114_case_specific_winners(tmp_path: Path) -> None:
    root = tmp_path / "fixture"
    make_selection_fixture(root)
    stability = winner_module.plan_stability(root, 0.01)
    assert stability["n_stability_trials"] == 0
    freeze = winner_module.freeze_winners(root)
    assert freeze["n_primary_winners"] == 114
    assert freeze["n_sensitivity_winners"] == 114
    primary = common.read_csv_rows(freeze["cell_specific_winners"])
    assert len({(row["fold"], row["region"]) for row in primary}) == 114
    assert {row["candidate_id"] for row in primary} == {"phase1_shared"}
    test_preparation = test_module.prepare(root)
    assert test_preparation["n_unique_test_tasks"] == 114
    assert test_preparation["n_selector_rows"] == 228


def test_closeout_requires_dual_gate_and_never_mutates_registry_or_article(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "root"
    primary_rows = []
    sensitivity_rows = []
    registry_rows = []
    for fold in (1, 2, 3):
        for region_index in range(38):
            region = f"R{region_index:02d}"
            operational = 0.8 if region_index == 0 else 1.2
            metric = {
                "selector": "cell_specific", "fold": fold, "region": region,
                "candidate_id": "x", "phase": "phase2", "canonical_degree": 0,
                "AQL": operational, "AQCR": 0, "MAE": 1, "RMSE": 1,
                "task_id": "x", "predictions": "x",
            }
            primary_rows.append(metric)
            sensitivity_rows.append({**metric, "selector": "region_global"})
            registry_rows.append({
                "region": region, "fold": fold, "qdesn_method_id": "qdesn", "qdesn_AQL": 1.0,
                "pricefm_method_id": "cached", "pricefm_AQL": 1.1,
            })
    primary_path = root / "test" / "cell_specific_metrics.csv"
    sensitivity_path = root / "test" / "region_global_metrics.csv"
    registry_path = tmp_path / "registry.csv"
    write_csv(primary_path, primary_rows)
    write_csv(sensitivity_path, sensitivity_rows)
    write_csv(registry_path, registry_rows)
    common.atomic_write_json(root / "test" / "aggregation_summary.json", {
        "selectors": {
            "cell_specific": {"path": str(primary_path), "sha256": common.sha256_file(primary_path)},
            "region_global": {"path": str(sensitivity_path), "sha256": common.sha256_file(sensitivity_path)},
        }
    })
    monkeypatch.setattr(closeout_module, "QDESN_REGISTRY_SHA256", common.sha256_file(registry_path))
    summary = closeout_module.closeout(root, registry_path)
    assert summary["n_dual_promotion_gate_pass"] == 3
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False


def test_campaign_hard_codes_20_physical_workers_and_taskset(tmp_path: Path) -> None:
    args = argparse.Namespace(
        python=str(tmp_path / "python"), config="c", raw_csv="r", upstream_root="u",
        artifact_root=str(tmp_path / "artifacts"), reference_window_root="w",
        qdesn_registry="q", log_root=str(tmp_path / "logs"), workers=19,
        required_idle_physical_cores=20, max_core_utilization=0.1, cpu_sample_seconds=0.01,
        poll_seconds=1, minimum_memory_gib=1, minimum_disk_gib=1, maximum_load_1m=99,
        maximum_attempts=2,
    )
    with pytest.raises(ValueError, match="exactly 20 workers"):
        campaign_module.Campaign(args)
    source = (SCRIPT_ROOT / "197_launch_pricefm_operational_campaign.py").read_text()
    assert '["taskset", "-c", cpuset_text(core)' in source
    assert '"one_model_per_physical_core": True' in source
    assert "registry_mutated=False" in source
    assert "article_mutated=False" in source


def test_campaign_preserves_venv_entrypoint_and_preflights_exact_python(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_python = tmp_path / "python3.11"
    real_python.write_text("fixture\n")
    venv_python = tmp_path / "venv" / "bin" / "python"
    venv_python.parent.mkdir(parents=True)
    venv_python.symlink_to(real_python)
    args = argparse.Namespace(
        python=str(venv_python), config="c", raw_csv="r", upstream_root="u",
        artifact_root=str(tmp_path / "pricefm" / "benchmarks" / "campaign"),
        reference_window_root="w", qdesn_registry="q", log_root=str(tmp_path / "logs"),
        workers=20, required_idle_physical_cores=20, max_core_utilization=0.1,
        cpu_sample_seconds=0.01, poll_seconds=1, minimum_memory_gib=1,
        minimum_disk_gib=1, maximum_load_1m=99, maximum_attempts=2,
        global_lock_path=str(tmp_path / "pricefm.lock"),
    )
    campaign = campaign_module.Campaign(args)
    assert campaign.python == venv_python
    assert campaign.python != real_python

    observed = {}

    def fake_run(command, **kwargs):
        observed["command"] = command
        payload = {
            "sys_executable": str(venv_python),
            "sys_prefix": str(tmp_path / "venv"),
            "sys_base_prefix": "/usr",
            "python": "3.11.13",
            "numpy": "2.0.2",
            "pandas": "2.2.3",
            "tensorflow": "2.18.0",
        }
        return SimpleNamespace(returncode=0, stdout=json.dumps(payload) + "\n", stderr="")

    monkeypatch.setattr(campaign_module.subprocess, "run", fake_run)
    preflight = campaign.validate_python_environment()
    assert observed["command"][0] == str(venv_python)
    assert preflight["status"] == "passed"
    assert preflight["numpy"] == "2.0.2"
    frozen = json.loads((Path(args.log_root) / "python_environment_preflight.json").read_text())
    assert frozen["requested_python"] == str(venv_python)


def test_campaign_python_preflight_rejects_missing_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    python = tmp_path / "venv" / "bin" / "python"
    python.parent.mkdir(parents=True)
    python.write_text("fixture\n")
    args = argparse.Namespace(
        python=str(python), config="c", raw_csv="r", upstream_root="u",
        artifact_root=str(tmp_path / "pricefm" / "benchmarks" / "campaign"),
        reference_window_root="w", qdesn_registry="q", log_root=str(tmp_path / "logs"),
        workers=20, required_idle_physical_cores=20, max_core_utilization=0.1,
        cpu_sample_seconds=0.01, poll_seconds=1, minimum_memory_gib=1,
        minimum_disk_gib=1, maximum_load_1m=99, maximum_attempts=2,
        global_lock_path=str(tmp_path / "pricefm.lock"),
    )
    campaign = campaign_module.Campaign(args)
    monkeypatch.setattr(
        campaign_module.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(
            returncode=1, stdout="", stderr="ModuleNotFoundError: No module named 'numpy'"
        ),
    )
    with pytest.raises(RuntimeError, match="preflight failed"):
        campaign.validate_python_environment()
    frozen = json.loads((Path(args.log_root) / "python_environment_preflight.json").read_text())
    assert frozen["status"] == "failed"
    assert "numpy" in frozen["stderr"]


def elastic_args(tmp_path: Path, **overrides: object) -> argparse.Namespace:
    values = {
        "python": str(tmp_path / "venv" / "bin" / "python"),
        "config": "c",
        "raw_csv": "r",
        "upstream_root": "u",
        "artifact_root": str(tmp_path / "pricefm" / "benchmarks" / "campaign"),
        "reference_window_root": "w",
        "qdesn_registry": "q",
        "log_root": str(tmp_path / "logs"),
        "minimum_dispatch_workers": 1,
        "maximum_workers": 20,
        "max_core_utilization": 0.1,
        "cpu_sample_seconds": 0.01,
        "consecutive_sample_gap_seconds": 0.0,
        "resource_poll_seconds": 1.0,
        "status_poll_seconds": 1.0,
        "minimum_memory_gib": 128.0,
        "minimum_disk_gib": 150.0,
        "maximum_projected_load": 60.0,
        "niceness": 10,
        "maximum_attempts": 2,
        "global_lock_path": str(tmp_path / "pricefm.lock"),
    }
    values.update(overrides)
    return argparse.Namespace(**values)


def core(package: int, number: int, *logical_cpus: int) -> dict[str, object]:
    return {"package": package, "core": number, "logical_cpus": list(logical_cpus)}


def test_elastic_capacity_uses_only_stable_nonactive_physical_cores() -> None:
    idle = [core(0, 0, 0, 32), core(0, 1, 4, 36), core(1, 0, 1, 33)]
    selected, evidence = elastic_module.stable_dispatch_capacity(
        current_idle=idle,
        previous_idle_keys={(0, 0), (0, 1), (1, 0)},
        active_core_keys={(0, 1)},
        active_count=1,
        load_1m=57.2,
        minimum_dispatch_workers=1,
        maximum_workers=20,
        maximum_projected_load=60.0,
    )
    assert [elastic_module.physical_key(item) for item in selected] == [(0, 0), (1, 0)]
    assert evidence["stable_idle_physical_cores"] == 2
    assert evidence["dispatch_slots"] == 2
    assert evidence["projected_load"] == pytest.approx(59.2)


def test_elastic_capacity_respects_load_and_minimum_dispatch() -> None:
    idle = [core(0, 0, 0, 32), core(0, 1, 4, 36)]
    blocked_by_load, load_evidence = elastic_module.stable_dispatch_capacity(
        idle, {(0, 0), (0, 1)}, set(), 0, 60.1, 1, 20, 60.0
    )
    assert blocked_by_load == []
    assert load_evidence["load_slots"] == 0
    blocked_by_minimum, minimum_evidence = elastic_module.stable_dispatch_capacity(
        idle[:1], {(0, 0)}, set(), 0, 55.0, 2, 20, 60.0
    )
    assert blocked_by_minimum == []
    assert minimum_evidence["dispatch_slots"] == 0


def test_elastic_snapshot_requires_two_consecutive_idle_samples(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    campaign = elastic_module.ElasticCampaign(elastic_args(tmp_path))
    samples = iter([
        {
            "idle_cores": [core(0, 0, 0, 32), core(0, 1, 4, 36)],
            "idle_keys": {(0, 0), (0, 1)},
            "n_idle_physical_cores": 2,
            "n_physical_cores": 32,
            "available_memory_gib": 400.0,
            "free_disk_gib": 300.0,
            "load_1m": 55.0,
        },
        {
            "idle_cores": [core(0, 1, 4, 36), core(1, 0, 1, 33)],
            "idle_keys": {(0, 1), (1, 0)},
            "n_idle_physical_cores": 2,
            "n_physical_cores": 32,
            "available_memory_gib": 400.0,
            "free_disk_gib": 300.0,
            "load_1m": 55.0,
        },
    ])
    monkeypatch.setattr(campaign, "resource_sample", lambda: next(samples))
    monkeypatch.setattr(elastic_module.time, "sleep", lambda _: None)
    selected, evidence = campaign.stable_resource_snapshot(set(), 0)
    assert [elastic_module.physical_key(item) for item in selected] == [(0, 1)]
    assert evidence["stable_idle_physical_cores"] == 1
    assert evidence["memory_gate"] is True
    assert evidence["disk_gate"] is True


def test_elastic_campaign_preserves_exact_venv_and_pins_nice_worker(tmp_path: Path) -> None:
    real_python = tmp_path / "python3.11"
    real_python.write_text("fixture\n")
    venv_python = tmp_path / "venv" / "bin" / "python"
    venv_python.parent.mkdir(parents=True)
    venv_python.symlink_to(real_python)
    campaign = elastic_module.ElasticCampaign(
        elastic_args(tmp_path, python=str(venv_python))
    )
    assert campaign.python == venv_python
    command = campaign.pinned_command(core(1, 0, 1, 33), [str(venv_python), "worker.py"])
    assert command[:7] == ["nice", "-n", "10", "taskset", "-c", "1,33", str(venv_python)]
    assert command[-1] == "worker.py"


def test_elastic_pool_skips_hash_verified_completed_work(tmp_path: Path) -> None:
    campaign = elastic_module.ElasticCampaign(elastic_args(tmp_path))
    trial = tmp_path / "trial"
    trial.mkdir()
    checkpoint = trial / "best_model.keras"
    checkpoint.write_bytes(b"fixture model\n")
    common.atomic_write_json(trial / "status.json", {
        "status": "completed",
        "checkpoint": str(checkpoint),
        "checkpoint_sha256": common.sha256_file(checkpoint),
    })
    manifest = tmp_path / "manifest.csv"
    write_csv(manifest, [{"trial_dir": str(trial), "seed": 1}])

    def should_not_launch(_: int) -> list[str]:
        raise AssertionError("Completed work was relaunched")

    campaign.run_pool(
        "fixture_fit", manifest, should_not_launch, campaign.fit_complete, "trial_dir"
    )
    health = json.loads((Path(campaign.args.log_root) / "campaign_health.json").read_text())
    assert health["status"] == "completed"
    assert health["completed"] == 1
    assert health["remaining"] == 0


def test_elastic_pool_dispatches_and_completes_actual_pending_rows(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    campaign = elastic_module.ElasticCampaign(elastic_args(
        tmp_path, resource_poll_seconds=0.0, status_poll_seconds=0.0
    ))
    rows = [
        {"task_dir": str(tmp_path / f"task_{index}"), "seed": index + 1}
        for index in range(3)
    ]
    manifest = tmp_path / "pending.csv"
    write_csv(manifest, rows)
    available = [core(0, 0, 0, 32), core(0, 1, 4, 36)]
    capacity = {
        "stable_idle_physical_cores": 2,
        "dispatch_slots": 2,
        "projected_load": 52.0,
    }
    monkeypatch.setattr(
        campaign,
        "stable_resource_snapshot",
        lambda active_keys, active_count: (available[: max(0, 2 - active_count)], capacity),
    )
    monkeypatch.setattr(elastic_module.time, "sleep", lambda _: None)
    launched: list[int] = []

    class FakeProcess:
        def __init__(self, command, **kwargs):
            index = int(command[-1])
            launched.append(index)
            task_dir = Path(rows[index]["task_dir"])
            task_dir.mkdir(parents=True, exist_ok=True)
            (task_dir / "done").write_text("completed\n")
            self.pid = 1000 + index

        def poll(self):
            return 0

    monkeypatch.setattr(elastic_module.subprocess, "Popen", FakeProcess)

    def completion(row: dict[str, str], verify: bool = True) -> bool:
        return (Path(row["task_dir"]) / "done").is_file()

    campaign.run_pool(
        "fixture_elastic_fit",
        manifest,
        lambda index: ["fixture-worker", str(index)],
        completion,
        "task_dir",
    )
    assert sorted(launched) == [0, 1, 2]
    health = json.loads((Path(campaign.args.log_root) / "campaign_health.json").read_text())
    assert health["status"] == "completed"
    assert health["completed"] == 3
    assert health["remaining"] == 0
    assert health["capacity"] == capacity


def test_elastic_scheduler_changes_orchestration_not_science() -> None:
    source = (SCRIPT_ROOT / "198_launch_pricefm_operational_elastic_campaign.py").read_text()
    for script in (
        "190_prepare_pricefm_operational_fullshot.py",
        "191_run_pricefm_operational_fullshot_trial.py",
        "192_select_pricefm_operational_phase1.py",
        "193_prepare_pricefm_operational_phase2.py",
        "194_select_pricefm_operational_winners.py",
        "195_score_pricefm_operational_test.py",
        "196_closeout_pricefm_operational_fullshot.py",
    ):
        assert script in source
    assert '"scientific_protocol_changed": False' in source
    assert "registry_mutated=False" in source
    assert "article_mutated=False" in source
    assert '"nice", "-n"' in source
    assert '"taskset", "-c"' in source
