"""Tests for the PriceFM Stage-R32 partial-stop closeout."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script():
    path = SCRIPT_DIR / "156_closeout_pricefm_stage_r32_partial_stop.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def manifest_row(exp: str, region: str = "AA", fold: int = 1) -> dict:
    return {
        "experiment_id": exp,
        "region": region,
        "fold": fold,
        "priority": 0,
        "target_quantile": 0.5,
        "stage": "stage_r32_large_capacity_history_screening",
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "stage_r32_arm": "cap_l300_d3_n100_balanced_final_layer",
        "stage_r32_profile": "balanced_final_layer",
        "horizon_focus": "1-24",
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_weight_multiplier": 3.0,
        "feature_policy": "target_only",
        "implemented_feature_policy": True,
        "lag_window": 300,
        "depth": 3,
        "n_per_layer": 100,
        "units": "[100, 100, 100]",
        "feature_dim": 100,
        "state_output": "final_layer",
        "readout_interaction": "horizon_block",
        "horizon_block_size": 24,
        "readout_interaction_basis": "state_lead",
        "alpha": 0.4,
        "rho": 0.86,
        "input_scale": 0.3,
        "tau0": 0.001,
        "seed": 2026073201,
        "graph_degree": 0,
        "current_pricefm_AQL": 1.0,
        "current_qdesn_AQL": 1.1,
        "selection_is_validation_only": True,
        "selection_rule": "validation_AQL_only_within_case",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r33_closeout_gate": True,
        "requires_full_quantile_gate": True,
        "requires_mcmc_confirmation_gate": True,
        "case_specific_spec_key": exp[-8:],
    }


def write_metric(path: Path, q_test: float = 1.2, q_val: float = 1.15) -> None:
    write_csv(
        path,
        [
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": q_val, "MAE": 1.0, "RMSE": 1.0},
            {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": q_test, "MAE": 1.0, "RMSE": 1.0},
            {"method_id": "naive_last", "split": "test", "unit": "original", "AQL": 1.4, "MAE": 1.0, "RMSE": 1.0},
            {"method_id": "normal_reference", "split": "test", "unit": "original", "AQL": 1.5, "MAE": 1.0, "RMSE": 1.0},
        ],
    )


def make_fixture(tmp_path: Path):
    manifest = tmp_path / "manifest.csv"
    case_plan = tmp_path / "case_plan.csv"
    grid = tmp_path / "grid.yaml"
    run_root = tmp_path / "runs"
    out = tmp_path / "out"
    rows = [
        manifest_row("r32_complete_nonwinner"),
        manifest_row("r32_failed"),
        manifest_row("r32_manual_stopped"),
        manifest_row("r32_queued", region="BB", fold=2),
    ]
    write_csv(manifest, rows)
    write_csv(case_plan, [{"region": "AA", "fold": 1}, {"region": "BB", "fold": 2}])
    grid.write_text("pricefm_desn_experiment_grid: {}\n")

    complete = run_root / "r32_complete_nonwinner"
    write_csv(complete / "cell_status.csv", [{"status": "completed", "message": "ok", "elapsed_seconds": 12}])
    write_metric(complete / "cells" / "region=AA" / "fold=1" / "model" / "metric_summary.csv")
    (complete / "cells" / "region=AA" / "fold=1" / "adapter").mkdir(parents=True)
    (complete / "cells" / "region=AA" / "fold=1" / "adapter" / "X_train.csv").write_text("heavy")

    failed = run_root / "r32_failed"
    write_csv(failed / "cell_status.csv", [{"status": "model_failed", "message": "return code 137", "elapsed_seconds": 30}])
    (failed / "cells" / "region=AA" / "fold=1" / "adapter").mkdir(parents=True)
    (failed / "cells" / "region=AA" / "fold=1" / "adapter" / "feature_map_matrix.npz").write_text("heavy")

    stopped = run_root / "r32_manual_stopped"
    (stopped / "cells" / "region=AA" / "fold=1" / "adapter").mkdir(parents=True)
    (stopped / "cells" / "region=AA" / "fold=1" / "adapter" / "rows_train.csv").write_text("heavy")
    return manifest, case_plan, grid, run_root, out


def args_for(mod, manifest: Path, case_plan: Path, grid: Path, run_root: Path, out: Path, execute_cleanup: bool = True):
    return mod.parser().parse_args(
        [
            "--manifest",
            str(manifest),
            "--case-plan",
            str(case_plan),
            "--grid-config",
            str(grid),
            "--run-root",
            str(run_root),
            "--output-dir",
            str(out),
            "--expected-experiments",
            "4",
            "--expected-cases",
            "2",
            "--skip-process-check",
            "true",
            "--execute-cleanup",
            str(execute_cleanup).lower(),
            "--force",
            "true",
        ]
    )


def test_r32_partial_stop_closeout_classifies_and_cleans_nonwinner_heavy_files(tmp_path):
    mod = load_script()
    manifest, case_plan, grid, run_root, out = make_fixture(tmp_path)
    summary = mod.run(args_for(mod, manifest, case_plan, grid, run_root, out))

    assert summary["status"] == "completed"
    assert summary["planned_experiments"] == 4
    assert summary["completed_with_metrics"] == 1
    assert summary["failed_without_metrics"] == 1
    assert summary["manual_stopped_no_metric"] == 1
    assert summary["queued_not_started"] == 1
    assert summary["metric_rows_beating_both"] == 0
    assert summary["cleanup_executed"] is True
    assert summary["cleanup_deleted_files"] == 3

    assert not (run_root / "r32_complete_nonwinner" / "cells" / "region=AA" / "fold=1" / "adapter" / "X_train.csv").exists()
    assert not (run_root / "r32_failed" / "cells" / "region=AA" / "fold=1" / "adapter" / "feature_map_matrix.npz").exists()
    assert not (run_root / "r32_manual_stopped" / "cells" / "region=AA" / "fold=1" / "adapter" / "rows_train.csv").exists()
    assert (run_root / "r32_complete_nonwinner" / "cells" / "region=AA" / "fold=1" / "model" / "metric_summary.csv").exists()

    status = pd.read_csv(out / "pricefm_stage_r32_partial_run_status.csv")
    assert set(status["closeout_status"]) == {
        "completed_with_metrics",
        "failed_without_metrics",
        "manual_stopped_no_metric",
        "queued_not_started",
    }
    gates = pd.read_csv(out / "pricefm_stage_r32_partial_closeout_gates.csv")
    assert gates.loc[gates["gate"].eq("registry_mutation_allowed"), "passed"].iloc[0] == False
    assert gates.loc[gates["gate"].eq("r32_relaunch_same_design_allowed"), "passed"].iloc[0] == False

    cleanup = pd.read_csv(out / "pricefm_stage_r32_partial_cleanup_manifest.csv")
    assert cleanup.shape[0] == 3
    cleanup_summary = json.loads((out / "pricefm_stage_r32_partial_cleanup_summary.json").read_text())
    assert cleanup_summary["deleted_files"] == 3


def test_r32_cleanup_preserves_promotable_metric_winner(tmp_path):
    mod = load_script()
    manifest, case_plan, grid, run_root, out = make_fixture(tmp_path)
    write_metric(
        run_root / "r32_complete_nonwinner" / "cells" / "region=AA" / "fold=1" / "model" / "metric_summary.csv",
        q_test=0.9,
        q_val=0.8,
    )
    summary = mod.run(args_for(mod, manifest, case_plan, grid, run_root, out))

    assert summary["metric_rows_beating_both"] == 1
    assert (run_root / "r32_complete_nonwinner" / "cells" / "region=AA" / "fold=1" / "adapter" / "X_train.csv").exists()
    cleanup = pd.read_csv(out / "pricefm_stage_r32_partial_cleanup_manifest.csv")
    assert "r32_complete_nonwinner" not in set(cleanup["experiment_id"])
