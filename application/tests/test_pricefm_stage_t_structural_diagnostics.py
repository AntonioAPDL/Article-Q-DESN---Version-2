"""Tests for Stage-T PriceFM structural diagnostics."""

from pathlib import Path
import importlib.util
import json
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


stage_t = load_script("81_diagnose_pricefm_structural_parity.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def make_fixture(tmp_path, *, bad_stage_s_role=False, duplicate_surface=False):
    root = tmp_path / "inputs"
    out = tmp_path / "out"

    surface = [
        {
            "region": "AA",
            "fold": 1,
            "local_AQL": 7.0,
            "pricefm_AQL": 8.0,
            "delta_abs": -1.0,
            "delta_rel": -0.125,
            "information_set": "pricefm_graph_inputs",
            "feature_policy": "graph_khop",
            "spatial_information_set": "pricefm_released_graph_khop",
            "graph_degree": 1,
            "experiment_id": "current_aa",
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        },
        {
            "region": "BB",
            "fold": 1,
            "local_AQL": 10.0,
            "pricefm_AQL": 9.0,
            "delta_abs": 1.0,
            "delta_rel": 0.111,
            "information_set": "target_only",
            "feature_policy": "target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph_degree": "",
            "experiment_id": "current_bb",
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        },
        {
            "region": "CC",
            "fold": 2,
            "local_AQL": 9.5,
            "pricefm_AQL": 9.0,
            "delta_abs": 0.5,
            "delta_rel": 0.056,
            "information_set": "pricefm_graph_inputs",
            "feature_policy": "graph_khop",
            "spatial_information_set": "pricefm_released_graph_khop",
            "graph_degree": 2,
            "experiment_id": "current_cc",
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        },
    ]
    if duplicate_surface:
        surface[2]["region"] = "BB"
        surface[2]["fold"] = 1
    write_csv(root / "surface.csv", surface)

    write_json(root / "stage_r_summary.json", {
        "diagnostic_only": True,
        "stage_m_surface_changed": False,
        "stage_m_rows": 3,
    })
    write_csv(root / "stage_r_scorecard.csv", surface)
    write_csv(root / "stage_r_failures.csv", [
        {
            "region": "AA", "fold": 1,
            "primary_failure_mode": "no_action",
            "recommended_action": "no_launch",
            "current_delta_AQL": -1.0,
        },
        {
            "region": "BB", "fold": 1,
            "primary_failure_mode": "graph_parity_gap",
            "recommended_action": "graph_parity_targeted_grid",
            "current_delta_AQL": 1.0,
        },
        {
            "region": "CC", "fold": 2,
            "primary_failure_mode": "late_horizon_gap",
            "recommended_action": "horizon_block_selection_pilot",
            "current_delta_AQL": 0.5,
        },
    ])
    write_csv(root / "stage_r_infoset.csv", [
        {
            "information_set": "pricefm_graph_inputs",
            "feature_policy": "graph_khop",
            "rows": 2,
            "wins": 1,
            "mean_delta_AQL": -0.25,
            "median_delta_AQL": -0.25,
            "mean_qdesn_AQL": 8.25,
            "mean_pricefm_AQL": 8.5,
            "win_rate": 0.5,
        },
        {
            "information_set": "target_only",
            "feature_policy": "target_only",
            "rows": 1,
            "wins": 0,
            "mean_delta_AQL": 1.0,
            "median_delta_AQL": 1.0,
            "mean_qdesn_AQL": 10.0,
            "mean_pricefm_AQL": 9.0,
            "win_rate": 0.0,
        },
    ])
    write_csv(root / "stage_r_transfer.csv", [
        {
            "source_label": "stage_m_alignment",
            "n_rows": 3,
            "n_region_folds": 3,
            "test_win_rate": 0.33,
            "pricefm_win_rate": 0.0,
            "disagree_rate": 0.5,
            "mean_test_delta_vs_pricefm": 1.0,
            "mean_spearman_val_test_rank": 0.1,
        }
    ])
    write_csv(root / "stage_r_horizon.csv", [
        {
            "region": "BB",
            "fold": 1,
            "horizon_group": "1-24",
            "horizon_band": "early",
            "validation_selected_AQL": 4.0,
            "test_oracle_AQL": 3.5,
            "oracle_minus_validation_AQL": -0.5,
        },
        {
            "region": "BB",
            "fold": 1,
            "horizon_group": "73-96",
            "horizon_band": "late",
            "validation_selected_AQL": 7.0,
            "test_oracle_AQL": 6.0,
            "oracle_minus_validation_AQL": -1.0,
        },
    ])
    write_json(root / "stage_s_summary.json", {
        "run_clean": True,
        "stage_m_surface_changed": False,
        "promotion_recommended": False,
        "validation_selected_beats_stage_m": 0,
        "validation_selected_beats_pricefm": 0,
        "test_oracle_beats_stage_m": 0,
        "test_oracle_beats_pricefm": 0,
        "best_test_oracle_vs_pricefm": 0.7,
        "median_validation_selected_vs_pricefm": 2.0,
        "binary_artifacts": 0,
    })
    write_csv(root / "stage_s_selection.csv", [
        {
            "candidate_family": "graph_parity_rescue",
            "rows": 1,
            "beats_stage_m": 0,
            "beats_pricefm": 0,
            "median_test_minus_stage_m": 1.0,
            "median_test_minus_pricefm": 2.0,
            "best_test_minus_pricefm": 0.7,
        }
    ])
    write_csv(root / "stage_s_validation.csv", [
        {
            "regions": '["BB"]',
            "folds": "[1]",
            "candidate_family": "graph_parity_rescue",
            "id": "candidate_bb",
            "selection_is_validation_only": True,
            "test_metrics_role": "selection" if bad_stage_s_role else "audit_only",
            "test_best_AQL": 11.0,
        }
    ])
    write_csv(root / "stage_s_oracle.csv", [
        {
            "regions": '["BB"]',
            "folds": "[1]",
            "candidate_family": "graph_parity_rescue",
            "id": "oracle_bb",
            "test_best_AQL": 10.5,
        }
    ])
    write_csv(root / "stage_s_variants.csv", [
        {
            "candidate_family": "graph_parity_rescue",
            "factor_changed": "compact_d2_anchor",
            "n": 1,
            "median_val_AQL": 9.0,
            "median_test_AQL": 10.0,
            "best_test_AQL": 10.0,
            "median_test_minus_pricefm": 1.0,
        }
    ])
    (root / "paper.txt").write_text(
        "PriceFM uses price load solar wind day-ahead 96 graph mask rolling fold.",
        encoding="utf-8",
    )
    (root / "pipeline.md").write_text(
        "generation is optional and RobustScaler is recorded.",
        encoding="utf-8",
    )

    return [
        "--stage-m-surface-csv", str(root / "surface.csv"),
        "--stage-r-summary-json", str(root / "stage_r_summary.json"),
        "--stage-r-scorecard-csv", str(root / "stage_r_scorecard.csv"),
        "--stage-r-failures-csv", str(root / "stage_r_failures.csv"),
        "--stage-r-infoset-csv", str(root / "stage_r_infoset.csv"),
        "--stage-r-transfer-csv", str(root / "stage_r_transfer.csv"),
        "--stage-r-horizon-csv", str(root / "stage_r_horizon.csv"),
        "--stage-s-summary-json", str(root / "stage_s_summary.json"),
        "--stage-s-selection-csv", str(root / "stage_s_selection.csv"),
        "--stage-s-validation-csv", str(root / "stage_s_validation.csv"),
        "--stage-s-oracle-csv", str(root / "stage_s_oracle.csv"),
        "--stage-s-variants-csv", str(root / "stage_s_variants.csv"),
        "--paper-text", str(root / "paper.txt"),
        "--pipeline-report", str(root / "pipeline.md"),
        "--output-dir", str(out),
        "--expected-region-folds", "3",
    ], out


def test_stage_t_structural_diagnostics_are_diagnostic_only(tmp_path):
    argv, out = make_fixture(tmp_path)
    summary = stage_t.summarize(stage_t.parser().parse_args(argv))

    assert summary["diagnostic_only"] is True
    assert summary["writes_launch_configs"] is False
    assert summary["fits_models"] is False
    assert summary["stage_m_rows"] == 3
    assert summary["stage_m_qdesn_wins"] == 1
    assert summary["stage_s_promotion_recommended"] is False
    assert summary["recommended_next_stage"] == "pricefm_information_set_transform_horizon_parity_audit"
    assert (out / "stage_t_structural_scorecard.csv").exists()
    assert (out / "stage_t_mechanism_ranking.csv").exists()
    assert (out / "stage_t_structural_diagnostics_report.md").exists()

    scorecard = pd.read_csv(out / "stage_t_structural_scorecard.csv")
    bb = scorecard[scorecard["region"].eq("BB")].iloc[0]
    assert bb["stage_s_targeted"]
    assert bb["structural_signal"] == "stage_s_falsified_local_rescue_family"


def test_stage_t_rejects_test_metric_selection_role(tmp_path):
    argv, _ = make_fixture(tmp_path, bad_stage_s_role=True)
    with pytest.raises(ValueError, match="test metrics must be audit-only"):
        stage_t.summarize(stage_t.parser().parse_args(argv))


def test_stage_t_rejects_duplicate_stage_m_keys(tmp_path):
    argv, _ = make_fixture(tmp_path, duplicate_surface=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_t.summarize(stage_t.parser().parse_args(argv))


def test_stage_t_rejects_stage_s_promotion_summary(tmp_path):
    argv, _ = make_fixture(tmp_path)
    summary_path = Path(argv[argv.index("--stage-s-summary-json") + 1])
    payload = json.loads(summary_path.read_text())
    payload["promotion_recommended"] = True
    summary_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ValueError, match="promoted a candidate"):
        stage_t.summarize(stage_t.parser().parse_args(argv))
