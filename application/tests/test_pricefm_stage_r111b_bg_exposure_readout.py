from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path
import threading
import time

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]


def load_script(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prep = load_script(
    "pricefm_r111b_prep",
    "application/scripts/pricefm/377_prepare_pricefm_stage_r111b_bg_exposure_readout.py",
)
design = load_script(
    "pricefm_r111b_design",
    "application/scripts/pricefm/379_build_pricefm_stage_r111b_exposure_design.py",
)
closeout = load_script(
    "pricefm_r111b_closeout",
    "application/scripts/pricefm/381_replay_closeout_pricefm_stage_r111b.py",
)
orchestrator = load_script(
    "pricefm_r111b_orchestrator",
    "application/scripts/pricefm/382_orchestrate_pricefm_stage_r111b_bg_exposure_readout.py",
)


def test_prepare_is_bounded_reproducible_and_test_closed(tmp_path: Path) -> None:
    result = prep.prepare(ROOT, tmp_path)
    assert result["stage"] == "R111B"
    assert result["region"] == "BG"
    assert result["selected_family"] == "al"
    assert result["family_selection_contract"] == "R103_fold1_validation_only_region_frozen_AL"
    assert result["task_count"] == 51
    assert result["model_fit_tasks"] == 39
    assert result["crossfit_driver_tasks"] == 9
    assert result["exposure_design_tasks"] == 9
    assert result["median_screen_tasks"] == 9
    assert result["final_quantile_tasks"] == 21
    assert result["replay_tasks"] == 3
    assert result["posterior_paths"] == 500
    assert result["test_access_authorized"] is False
    assert result["broad_all_region_launch_authorized"] is False
    assert result["registry_mutation_authorized"] is False
    assert result["article_mutation_authorized"] is False
    assert result["joint_model_authorized"] is False
    assert result["mcmc_authorized"] is False

    tasks = list(csv.DictReader((tmp_path / "conceptual_task_manifest.csv").open()))
    assert len(tasks) == 51
    assert {row["phase"] for row in tasks} == {
        "crossfit_normal_driver",
        "crossfit_exposure_design",
        "median_arm_screen",
        "final_al_readout",
        "outer_validation_replay",
    }
    assert not any("test" in row["dependency"].lower() for row in tasks)

    drivers = list(csv.DictReader((tmp_path / "driver_task_manifest.csv").open()))
    designs = list(csv.DictReader((tmp_path / "design_task_manifest.csv").open()))
    assert len(drivers) == len(designs) == 9
    for row in drivers:
        contract = json.loads(Path(row["contract_path"]).read_text())
        assert contract["readout"] == "block24"
        assert contract["prior_type"] == "rhs_ns"
        assert contract["tau0"] == pytest.approx(2.5e-5)
        assert contract["n_paths"] == 500
        assert contract["selection_split"] == "outer_fold_training_inner_only"
        assert contract["test_access_authorized"] is False
    sources = pd.read_csv(tmp_path / "source_manifest.csv")
    family_sources = sources[sources.path.str.endswith("family_validation_metrics.csv")]
    assert len(family_sources) == 3
    assert all(Path(path).is_file() for path in sources.path)


def test_family_choice_is_frozen_from_fold_one_only() -> None:
    assert prep.selected_bg_family() == "al"
    fold_one = pd.read_csv(prep.family_metric_paths()[0]).sort_values(
        ["validation_AQL_original", "family"], kind="mergesort"
    )
    assert fold_one.iloc[0].family == "al"


def test_exposure_contract_hash_and_firewall(tmp_path: Path) -> None:
    value = {
        "stage": "R111B",
        "phase": "crossfit_exposure_design",
        "region": "BG",
        "recursive_reduction": "pathwise_design_mean",
        "posterior_paths": 500,
        "test_access_authorized": False,
    }
    value["task_contract_sha256"] = design.canonical_hash(value)
    path = tmp_path / "contract.json"
    path.write_text(json.dumps(value))
    assert design.verify_contract(path)["region"] == "BG"
    value["posterior_paths"] = 499
    path.write_text(json.dumps(value))
    with pytest.raises(RuntimeError, match="hash mismatch"):
        design.verify_contract(path)


def test_arm_selection_uses_complete_fold_one_crossfit_only(tmp_path: Path) -> None:
    values = {"teacher_recent": 1.0, "recursive_mean": 0.8, "mixed_equal": 0.9}
    for arm, value in values.items():
        for holdout in (1, 2, 3):
            output = tmp_path / "runs/screen" / arm / f"holdout={holdout}"
            output.mkdir(parents=True)
            pd.DataFrame([{
                "task_id": f"{arm}-{holdout}",
                "arm": arm,
                "holdout_inner_fold": holdout,
                "AQL_scaled": value + holdout * 1e-3,
                "converged": True,
                "test_opened": False,
            }]).to_csv(output / "metric_summary.csv", index=False)
    assert orchestrator.select_arm(tmp_path) == "recursive_mean"
    selected = json.loads((tmp_path / "selected_exposure_arm.json").read_text())
    assert selected["selection_split"] == "fold1_training_crossfit_only"
    assert selected["test_opened"] is False


def metric_rows(policy: str, value: float, paths: int | None = None) -> list[dict]:
    rows = []
    for fold in (1, 2, 3):
        row = {
            "region": "BG",
            "fold": fold,
            "policy": policy,
            "AQL": value,
            "AQCR": 0.005,
            "n_loss_atoms": 100,
        }
        if paths is not None:
            row["posterior_paths"] = paths
        rows.append(row)
    return rows


def test_closeout_gate_requires_material_gain_fold_safety_and_r97_proximity() -> None:
    candidate = pd.DataFrame(metric_rows(closeout.POLICY, 8.0, 500))
    references = pd.DataFrame(
        metric_rows("r110_direct_target_rhs_neighbors", 10.0)
        + metric_rows("r97_direct_reference", 7.5)
    )
    assert closeout.evaluate_gates(candidate, references).passed.all()
    harmed = candidate.copy()
    harmed.loc[harmed.fold.eq(3), "AQL"] = 11.0
    gates = closeout.evaluate_gates(harmed, references)
    assert not gates.loc[gates.gate.eq("max_fold_harm_at_most_5pct_vs_r110"), "passed"].item()


def test_scheduler_never_reuses_an_active_physical_core(tmp_path: Path, monkeypatch) -> None:
    lock = threading.Lock()
    active: set[int] = set()
    overlap: list[int] = []

    def fake_run(task_id, command, cpu, log_path, env):
        with lock:
            if cpu in active:
                overlap.append(cpu)
            active.add(cpu)
        time.sleep(0.02)
        with lock:
            active.remove(cpu)
        return {"task_id": task_id, "cpu": cpu, "returncode": 0, "elapsed_seconds": 0.02, "log_path": str(log_path)}

    monkeypatch.setattr(orchestrator, "run_command", fake_run)
    tasks = [
        {"task_id": f"task-{index}", "command": ["unused"], "log_path": tmp_path / f"{index}.log"}
        for index in range(8)
    ]
    results = orchestrator.run_parallel(tasks, [11, 22, 33], 3, tmp_path / "status.csv")
    assert len(results) == 8
    assert overlap == []
    assert set(row["cpu"] for row in results) <= {11, 22, 33}


def test_workers_keep_screen_neutral_final_warm_start_and_mutations_blocked() -> None:
    worker = (ROOT / "application/scripts/pricefm/380_run_pricefm_stage_r111b_al_readout.R").read_text()
    controller = (ROOT / "application/scripts/pricefm/382_orchestrate_pricefm_stage_r111b_bg_exposure_readout.py").read_text()
    closeout_text = (ROOT / "application/scripts/pricefm/381_replay_closeout_pricefm_stage_r111b.py").read_text()
    assert '"neutral_training_only"' in worker
    assert 'init <- list(beta = rep(0, p), sigma = sigma_init)' in worker
    assert '"matching_R103_AL_same_fold_tau"' in worker
    assert "prior_center_from_initializer = FALSE" in worker
    assert '"initializer_policy": "neutral_training_only"' in controller
    assert '"initializer_policy": "matching_R103_AL_same_fold_tau"' in controller
    assert "queue.Queue" in controller
    assert '"OMP_NUM_THREADS": "1"' in controller
    assert '"broad_all_region_launch_authorized": False' in closeout_text
    assert '"registry_mutated": False' in closeout_text
    assert '"article_mutated": False' in closeout_text
