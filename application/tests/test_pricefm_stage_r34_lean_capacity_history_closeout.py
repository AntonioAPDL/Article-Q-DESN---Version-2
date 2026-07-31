import importlib.util
import sys
from pathlib import Path

import pandas as pd
import pytest


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "pricefm"
    / "158_closeout_pricefm_stage_r34_lean_capacity_history.py"
)


def load_module():
    script_dir = str(SCRIPT.parent)
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
    spec = importlib.util.spec_from_file_location("stage_r34", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def fixture_tree(tmp_path, complete=True):
    manifest_path = tmp_path / "prep" / "manifest.csv"
    grid_root = tmp_path / "grid"
    run_root = tmp_path / "runs"
    log_root = tmp_path / "logs"
    output_dir = tmp_path / "output"
    manifest = []
    experiment_rows = []
    for region, fold in [("AA", 1), ("BB", 2)]:
        for arm in range(2):
            experiment_id = f"r33_{region}_{fold}_{arm}"
            manifest.append(
                {
                    "experiment_id": experiment_id,
                    "region": region,
                    "fold": fold,
                    "stage_r33_arm": f"arm_{arm}",
                    "current_qdesn_AQL": 5.0,
                    "current_pricefm_AQL": 4.5,
                    "selection_is_validation_only": True,
                }
            )
            if complete or experiment_id != "r33_BB_2_1":
                metric = run_root / experiment_id / "cells" / f"region={region}" / f"fold={fold}" / "model" / "metric_summary.csv"
                val = 3.0 + arm
                test = (4.0 + arm * 0.2) if region == "AA" else (4.7 + arm * 0.2)
                write_csv(
                    metric,
                    [
                        {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": val},
                        {"method_id": "qdesn_al_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": test},
                        {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "val", "unit": "original", "AQL": val + 0.1},
                        {"method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": test + 0.1},
                    ],
                )
                experiment_rows.append({"kind": "experiment", "status": "completed", "return_code": 0})
    write_csv(manifest_path, manifest)
    write_csv(grid_root / "manifest.csv", manifest)
    if complete:
        write_csv(grid_root / "launch_status.csv", experiment_rows)
        log_root.mkdir(parents=True, exist_ok=True)
        (log_root / "test_run.exit").write_text("0\n")
    return manifest_path, grid_root, run_root, log_root, output_dir


def args(module, paths):
    manifest, grid_root, run_root, log_root, output_dir = paths
    return module.argparse.Namespace(
        manifest=str(manifest),
        grid_root=str(grid_root),
        run_root=str(run_root),
        log_root=str(log_root),
        run_tag="test_run",
        output_dir=str(output_dir),
        expected_experiments=4,
        expected_cases=2,
        health_only=False,
        force=False,
    )


def test_incomplete_run_is_not_finalizable(tmp_path):
    module = load_module()
    paths = fixture_tree(tmp_path, complete=False)
    manifest = module.read_csv_required(paths[0], "manifest")
    metrics = module.parse_metric_rows(manifest, paths[2])
    audit, complete, summary = module.completion_audit(manifest, metrics, args(module, paths))

    assert not complete
    assert summary["metric_summaries"] == 3
    assert summary["remaining_experiments"] == 1
    assert not audit["passed"].map(module.boolish).all()
    assert not paths[-1].exists()


def test_complete_run_freezes_validation_winners_and_separates_gates(tmp_path):
    module = load_module()
    paths = fixture_tree(tmp_path, complete=True)
    manifest = module.read_csv_required(paths[0], "manifest")
    metrics = module.parse_metric_rows(manifest, paths[2])
    audit, complete, summary = module.completion_audit(manifest, metrics, args(module, paths))

    assert complete
    assert audit["passed"].map(module.boolish).all()
    selected = module.select_cases(metrics, "val_AQL", "authoritative_case_selection")
    oracle = module.select_cases(metrics, "test_AQL", "diagnostic_test_oracle")
    promotions = module.promotion_queue(selected)
    mcmc = module.mcmc_queue(promotions)
    gates = module.decision_gates(complete, selected, promotions)

    assert len(selected) == 2
    assert set(selected["stage_r33_arm"]) == {"arm_0"}
    assert len(oracle) == 2
    assert len(promotions) == 1
    assert promotions.iloc[0]["region"] == "AA"
    assert len(mcmc) == 1
    assert mcmc.iloc[0]["mcmc_status"] == "blocked_pending_full_quantile_confirmation"
    gate = gates.set_index("gate")["passed"].map(module.boolish)
    assert gate["r33_complete"]
    assert gate["dual_reference_winner_exists"]
    assert not gate["full_quantile_launch_authorized"]
    assert not gate["mcmc_launch_authorized"]
