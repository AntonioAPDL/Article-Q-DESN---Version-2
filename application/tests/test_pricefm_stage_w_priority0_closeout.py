"""Tests for the Stage-W Priority-0 PriceFM closeout."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


stage_w_closeout = load_script("85_closeout_pricefm_stage_w_priority0.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def manifest_row(experiment_id, region, fold, family, factor, current, pricefm):
    return {
        "id": experiment_id,
        "stage": "stage_w_region_fold_specific_screening",
        "priority": 0,
        "regions": '["{}"]'.format(region),
        "folds": "[{}]".format(fold),
        "candidate_family": family,
        "factor_changed": factor,
        "feature_policy": "graph_khop",
        "graph_degree": 1,
        "input_scope": "pricefm_graph_khop_degree1",
        "spatial_information_set": "pricefm_released_graph_khop",
        "lag_window": 96,
        "units": "[120]",
        "depth": 1,
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "tau0": 0.001,
        "seed": 20260630,
        "run_dir": "unused",
        "local_AQL": current,
        "pricefm_AQL": pricefm,
        "selection_rule": "region_fold_validation_aql_horizon_stability",
        "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
    }


def write_experiment(run_root, experiment_id, region, fold, val_aql, test_aql):
    model = run_root / experiment_id / "cells" / f"region={region}" / f"fold={fold}" / "model"
    write_csv(
        model / "metric_summary.csv",
        [
            {
                "method_id": "qdesn_al_rhs_ns_exact_chunked",
                "split": "val",
                "unit": "original",
                "AQL": val_aql,
                "AQCR": 0.0,
                "MAE": 2 * val_aql,
                "RMSE": 3 * val_aql,
            },
            {
                "method_id": "qdesn_al_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "AQL": test_aql,
                "AQCR": 0.0,
                "MAE": 2 * test_aql,
                "RMSE": 3 * test_aql,
            },
            {
                "method_id": "normal_rhs_ns",
                "split": "test",
                "unit": "original",
                "AQL": test_aql + 5,
                "AQCR": 0.0,
                "MAE": 2 * (test_aql + 5),
                "RMSE": 3 * (test_aql + 5),
            },
        ],
    )
    write_csv(
        model / "metric_by_horizon_group.csv",
        [
            {
                "method_id": "qdesn_al_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "horizon_group": "1-24",
                "AQL": test_aql - 0.5,
                "AQCR": 0.0,
                "MAE": 2 * test_aql,
                "RMSE": 3 * test_aql,
            },
            {
                "method_id": "qdesn_al_rhs_ns_exact_chunked",
                "split": "test",
                "unit": "original",
                "horizon_group": "25-48",
                "AQL": test_aql + 0.5,
                "AQCR": 0.0,
                "MAE": 2 * test_aql,
                "RMSE": 3 * test_aql,
            },
        ],
    )
    write_csv(
        model / "exact_equivalence.csv",
        [
            {
                "likelihood_family": "al",
                "prior_family": "rhs_ns",
                "tau": 0.5,
                "n_rows": 100,
                "beta_mean_max_abs_diff": 0.0,
                "beta_cov_max_abs_diff": 0.0,
                "train_prediction_max_abs_diff": 0.0,
                "tolerance": 1e-6,
                "passed": True,
            }
        ],
    )
    write_csv(
        run_root / experiment_id / "cell_status.csv",
        [
            {
                "region": region,
                "fold": fold,
                "status": "completed",
                "elapsed_seconds": 10.0,
                "message": "ok",
            }
        ],
    )


def make_fixture(tmp_path):
    grid_root = tmp_path / "grid"
    run_root = tmp_path / "runs"
    output_dir = tmp_path / "closeout"
    rows = [
        manifest_row("aa_bad_validation", "AA", 1, "graph_information_conversion", "khop", 9.0, 7.0),
        manifest_row("aa_test_oracle", "AA", 1, "graph_information_conversion", "summary", 9.0, 7.0),
        manifest_row("bb_candidate_only", "BB", 2, "graph_geometry_refinement", "degree", 9.0, 7.0),
    ]
    write_csv(grid_root / "manifest.csv", rows)
    write_csv(
        grid_root / "launch_status.csv",
        [
            {"id": row["id"], "kind": "experiment", "priority": 0, "status": "completed", "return_code": 0}
            for row in rows
        ],
    )
    write_experiment(run_root, "aa_bad_validation", "AA", 1, val_aql=1.0, test_aql=10.0)
    write_experiment(run_root, "aa_test_oracle", "AA", 1, val_aql=2.0, test_aql=8.0)
    write_experiment(run_root, "bb_candidate_only", "BB", 2, val_aql=1.0, test_aql=8.0)
    time_log = tmp_path / "time.log"
    time_log.write_text(
        "\tElapsed (wall clock) time (h:mm:ss or m:ss): 0:10.00\n"
        "\tMaximum resident set size (kbytes): 123456\n"
        "\tExit status: 0\n"
    )
    args = stage_w_closeout.parser().parse_args([
        "--grid-root", str(grid_root),
        "--run-root", str(run_root),
        "--plan-dir", str(tmp_path / "plan"),
        "--time-log", str(time_log),
        "--output-dir", str(output_dir),
        "--force", "true",
    ])
    return args, output_dir, run_root


def test_stage_w_priority0_closeout_detects_validation_regret(tmp_path):
    args, output_dir, _ = make_fixture(tmp_path)
    summary = stage_w_closeout.closeout(args)

    assert summary["status"] == "completed"
    assert summary["run_clean"] is True
    assert summary["priority1_recommended"] is False
    assert summary["validation_selected_candidate_only_wins"] == 1
    assert summary["validation_selected_rejected"] == 1

    validation = pd.read_csv(output_dir / "stage_w_priority0_validation_selected.csv")
    transfer = pd.read_csv(output_dir / "stage_w_priority0_validation_transfer.csv")
    health = pd.read_csv(output_dir / "stage_w_priority0_health.csv")

    assert set(validation["validation_selected_decision"]) == {
        "reject_validation_worse_current",
        "candidate_only_beats_current_not_pricefm",
    }
    aa = transfer[transfer["region"].eq("AA")].iloc[0]
    assert aa["test_regret_vs_oracle"] == pytest.approx(2.0)
    assert health["metric_files"].iloc[0] == 3
    assert (output_dir / "stage_w_priority0_report.md").exists()


def test_stage_w_priority0_closeout_requires_complete_metrics(tmp_path):
    args, _, run_root = make_fixture(tmp_path)
    missing = (
        run_root
        / "bb_candidate_only"
        / "cells"
        / "region=BB"
        / "fold=2"
        / "model"
        / "metric_summary.csv"
    )
    missing.unlink()
    with pytest.raises(RuntimeError, match="metric_files"):
        stage_w_closeout.closeout(args)
