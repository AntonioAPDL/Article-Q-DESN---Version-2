"""Tests for Stage-V PriceFM horizon-aware selection contract."""

from pathlib import Path
import importlib.util
import json
import sys

import pandas as pd
import pytest
import yaml


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


stage_v = load_script("83_design_pricefm_horizon_selection_contract.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def cell_dir(root, exp_id, region="AA", fold=1):
    return root / exp_id / "cells" / f"region={region}" / f"fold={fold}"


def metric_rows(method_id, val_aql, test_aql):
    return [
        {
            "method_id": method_id,
            "split": "val",
            "unit": "original",
            "AQL": val_aql,
            "AQCR": 0.0,
            "MAE": 2.0 * val_aql,
            "RMSE": 3.0 * val_aql,
        },
        {
            "method_id": method_id,
            "split": "test",
            "unit": "original",
            "AQL": test_aql,
            "AQCR": 0.0,
            "MAE": 2.0 * test_aql,
            "RMSE": 3.0 * test_aql,
        },
        {
            "method_id": "normal_rhs_ns",
            "split": "val",
            "unit": "original",
            "AQL": 99.0,
            "AQCR": 0.0,
            "MAE": 99.0,
            "RMSE": 99.0,
        },
    ]


def horizon_rows(method_id, split, values):
    rows = []
    for group, aql in values.items():
        rows.append({
            "method_id": method_id,
            "split": split,
            "unit": "original",
            "horizon_group": group,
            "AQL": aql,
            "AQCR": 0.0,
            "MAE": 2.0 * aql,
            "RMSE": 3.0 * aql,
        })
    return rows


def make_cell(root, exp_id, *, val_aql, test_aql, val_groups, test_groups):
    method_id = "qdesn_exal_rhs_ns_exact_chunked"
    cell = cell_dir(root, exp_id)
    write_yaml(cell / "config.yaml", {
        "pricefm_desn_smoke": {
            "region": "AA",
            "fold": 1,
            "horizons": list(range(1, 97)),
            "quantiles": [0.5],
            "feature_policy": "graph_khop",
            "adapter": {
                "feature_dim": 40,
                "depth": 1,
                "units": [40],
                "alpha": 0.4,
                "rho": 0.9,
                "input_scale": 0.25,
                "projection_scale": 0.5,
                "seed": 123,
            },
            "rhs_ns": {"tau0": 0.001},
            "qdesn_vb": {"max_iter": 50, "min_iter_elbo": 25},
        }
    })
    write_csv(cell / "model" / "metric_summary.csv", metric_rows(method_id, val_aql, test_aql))
    write_csv(
        cell / "model" / "metric_by_horizon_group.csv",
        horizon_rows(method_id, "val", val_groups)
        + horizon_rows(method_id, "test", test_groups),
    )
    return cell


def make_fixture(tmp_path, *, bad_stage_u=False, duplicate_surface=False):
    root = tmp_path / "fixture"
    output = tmp_path / "out"
    candidate_root = root / "pricefm_stage_n_candidate_run"
    current_root = root / "current_run"
    method_id = "qdesn_exal_rhs_ns_exact_chunked"

    make_cell(
        current_root,
        "current_exp",
        val_aql=5.5,
        test_aql=7.0,
        val_groups={"1-24": 5.0, "25-48": 5.5, "49-72": 5.8, "73-96": 5.7},
        test_groups={"1-24": 6.0, "25-48": 7.0, "49-72": 7.5, "73-96": 7.5},
    )
    make_cell(
        candidate_root,
        "exp_total_best",
        val_aql=5.0,
        test_aql=8.0,
        val_groups={"1-24": 1.0, "25-48": 2.0, "49-72": 10.0, "73-96": 9.0},
        test_groups={"1-24": 5.0, "25-48": 6.0, "49-72": 10.0, "73-96": 11.0},
    )
    make_cell(
        candidate_root,
        "exp_horizon_best",
        val_aql=5.2,
        test_aql=6.0,
        val_groups={"1-24": 5.2, "25-48": 4.8, "49-72": 4.0, "73-96": 4.8},
        test_groups={"1-24": 5.5, "25-48": 6.0, "49-72": 6.2, "73-96": 6.3},
    )
    make_cell(
        candidate_root,
        "exp_missing_horizon",
        val_aql=1.0,
        test_aql=9.0,
        val_groups={"1-24": 1.0, "25-48": 1.1},
        test_groups={"1-24": 9.0, "25-48": 9.1, "49-72": 9.2, "73-96": 9.3},
    )

    surface_rows = [{
        "region": "AA",
        "fold": 1,
        "best_local_method": method_id,
        "model_family": "qdesn_exal",
        "information_set": "pricefm_graph_inputs",
        "local_AQL": 7.0,
        "pricefm_AQL": 6.5,
        "delta_abs": 0.5,
        "delta_rel": 0.07,
        "feature_policy": "graph_khop",
        "run_dir": str(current_root / "current_exp"),
    }]
    if duplicate_surface:
        surface_rows.append(surface_rows[0].copy())
    write_csv(root / "surface.csv", surface_rows)
    write_csv(root / "current_vt.csv", [{
        "region": "AA",
        "fold": 1,
        "selected_method_id": method_id,
        "model_family": "qdesn_exal",
        "selection_AQL": 5.5,
        "test_AQL": 7.0,
    }])
    write_json(root / "stage_u_summary.json", {
        "diagnostic_only": True,
        "writes_launch_configs": False,
        "fits_models": False,
        "hard_parity_failures": 1 if bad_stage_u else 0,
        "recommended_next_stage": "horizon_aware_validation_contract_after_parity",
    })
    write_csv(root / "stage_u_row_parity.csv", [{
        "region": "AA",
        "fold": 1,
        "parity_status": "pass",
        "hard_failure_count": 0,
    }])
    write_csv(root / "stage_u_horizon.csv", [{
        "region": "AA",
        "fold": 1,
        "worst_horizon_group": "49-72",
        "horizon_AQL_range": 2.0,
    }])
    write_csv(root / "stage_o_rule_audit.csv", [{
        "rule_id": "robust_rank_val_aql_mae_rmse",
        "selection_uses_test_metrics": False,
    }])

    argv = [
        "--stage-m-surface-csv", str(root / "surface.csv"),
        "--stage-m-current-vt-csv", str(root / "current_vt.csv"),
        "--stage-u-summary-json", str(root / "stage_u_summary.json"),
        "--stage-u-row-parity-csv", str(root / "stage_u_row_parity.csv"),
        "--stage-u-horizon-csv", str(root / "stage_u_horizon.csv"),
        "--stage-o-rule-audit-csv", str(root / "stage_o_rule_audit.csv"),
        "--candidate-run-root", str(candidate_root),
        "--output-dir", str(output),
        "--expected-region-folds", "1",
    ]
    return argv, output


def test_stage_v_generates_validation_only_outputs(tmp_path):
    argv, output = make_fixture(tmp_path)
    summary = stage_v.design(stage_v.parser().parse_args(argv))

    assert summary["diagnostic_only"] is True
    assert summary["fits_models"] is False
    assert summary["writes_launch_configs"] is False
    assert summary["stage_m_surface_changed"] is False
    assert summary["selection_uses_test_metrics_any"] is False
    assert summary["candidate_rows"] >= 4
    assert summary["horizon_rule_eligible_rows"] < summary["candidate_rows"]
    assert (output / "stage_v_rule_selected_rows.csv").exists()
    assert (output / "stage_v_horizon_selection_contract_report.md").exists()

    selected = pd.read_csv(output / "stage_v_rule_selected_rows.csv")
    assert not selected["selection_uses_test_metrics"].astype(bool).any()
    val_pick = selected[selected["rule_id"].eq("val_aql_min")].iloc[0]
    assert val_pick["experiment_id"] == "exp_missing_horizon"
    horizon_pick = selected[selected["rule_id"].eq("horizon_midlate_mean_min")].iloc[0]
    assert horizon_pick["experiment_id"] == "exp_horizon_best"

    candidates = pd.read_csv(output / "stage_v_candidate_universe.csv")
    missing = candidates[candidates["experiment_id"].eq("exp_missing_horizon")].iloc[0]
    assert missing["val_horizon_groups_complete"] in [False, "False", 0]
    assert missing["horizon_rule_eligible"] in [False, "False", 0]


def test_stage_v_rejects_stage_u_hard_failures(tmp_path):
    argv, _ = make_fixture(tmp_path, bad_stage_u=True)
    with pytest.raises(ValueError, match="hard parity failures"):
        stage_v.design(stage_v.parser().parse_args(argv))


def test_stage_v_rejects_duplicate_stage_m_keys(tmp_path):
    argv, _ = make_fixture(tmp_path, duplicate_surface=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_v.design(stage_v.parser().parse_args(argv))
