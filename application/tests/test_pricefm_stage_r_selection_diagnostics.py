"""Tests for Stage-R PriceFM selection-transfer diagnostics."""

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


stage_r = load_script("78_diagnose_pricefm_selection_transfer.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def surface_rows():
    rows = [
        {
            "region": "AA",
            "fold": 1,
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "model_family": "qdesn_exal",
            "information_set": "target_only",
            "local_AQL": 10.0,
            "pricefm_AQL": 8.8,
            "delta_abs": 1.2,
            "delta_rel": 0.136,
            "local_wins": False,
            "decision_label": "pricefm_better",
            "feature_policy": "target_only",
            "experiment_id": "current_aa",
        },
        {
            "region": "BB",
            "fold": 1,
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "model_family": "qdesn_exal",
            "information_set": "pricefm_graph_inputs",
            "local_AQL": 9.4,
            "pricefm_AQL": 8.9,
            "delta_abs": 0.5,
            "delta_rel": 0.056,
            "local_wins": False,
            "decision_label": "pricefm_better",
            "feature_policy": "graph_khop",
            "experiment_id": "current_bb",
        },
        {
            "region": "CC",
            "fold": 1,
            "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "model_family": "qdesn_al",
            "information_set": "pricefm_graph_inputs",
            "local_AQL": 7.5,
            "pricefm_AQL": 8.0,
            "delta_abs": -0.5,
            "delta_rel": -0.0625,
            "local_wins": True,
            "decision_label": "local_beats_pricefm",
            "feature_policy": "graph_khop",
            "experiment_id": "current_cc",
        },
    ]
    for i in range(39):
        rows.append({
            "region": "ZZ{:02d}".format(i),
            "fold": 1 + (i % 3),
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "model_family": "qdesn_exal",
            "information_set": "pricefm_graph_inputs",
            "local_AQL": 5.0,
            "pricefm_AQL": 6.0,
            "delta_abs": -1.0,
            "delta_rel": -0.1667,
            "local_wins": True,
            "decision_label": "local_beats_pricefm",
            "feature_policy": "graph_khop",
            "experiment_id": "current_zz{:02d}".format(i),
        })
    return rows


def current_vt_rows(surface):
    rows = []
    for row in surface:
        rows.append({
            "region": row["region"],
            "fold": row["fold"],
            "selected_method_id": row["best_local_method"],
            "model_family": row["model_family"],
            "selection_AQL": row["local_AQL"] + 0.4,
            "test_AQL": row["local_AQL"],
            "test_minus_validation_AQL": -0.4,
            "abs_test_minus_validation_AQL": 0.4,
        })
    return rows


def split_rows(surface):
    rows = []
    for row in surface:
        for contrast in ["val_minus_train", "test_minus_val", "test_minus_train"]:
            rows.append({
                "region": row["region"],
                "fold": row["fold"],
                "contrast": contrast,
                "mean_delta": 0.1,
                "sd_ratio": 0.9,
                "median_delta": 0.05,
                "q90_delta": 0.2,
                "q10_delta": -0.1,
            })
    return rows


def make_fixture(tmp_path, *, duplicate_surface=False, nonfinite=False):
    root = tmp_path / "inputs"
    out = tmp_path / "out"
    surface = surface_rows()
    if duplicate_surface:
        surface[-1]["region"] = "AA"
        surface[-1]["fold"] = 1
    if nonfinite:
        surface[0]["delta_abs"] = "bad"

    write_csv(root / "surface.csv", surface)
    write_csv(root / "current_vt.csv", current_vt_rows(surface))
    write_csv(root / "split.csv", split_rows(surface))
    write_csv(root / "alignment.csv", [
        {
            "source_label": "stage_j_priority0_closeout",
            "region": "AA",
            "fold": 1,
            "experiment_id": "diag_aa",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_AQL": 9.0,
            "test_AQL": 10.5,
            "current_selection_AQL": 10.4,
            "current_test_AQL": 10.0,
            "val_delta_vs_current": -1.4,
            "test_delta_vs_current": 0.5,
            "validation_improved": True,
            "test_improved": False,
        },
        {
            "source_label": "stage_j_priority0_closeout",
            "region": "BB",
            "fold": 1,
            "experiment_id": "diag_bb",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_AQL": 8.6,
            "test_AQL": 9.0,
            "current_selection_AQL": 9.8,
            "current_test_AQL": 9.4,
            "val_delta_vs_current": -1.2,
            "test_delta_vs_current": -0.4,
            "validation_improved": True,
            "test_improved": True,
        },
    ])
    write_csv(root / "stage_n_selected.csv", [
        {
            "region": "AA",
            "fold": 1,
            "id": "stagen_aa",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_policy": "graph_khop",
            "graph_degree": 1,
            "val_AQL": 8.9,
            "test_AQL": 9.6,
            "current_test_AQL": 10.0,
            "pricefm_AQL": 8.8,
            "delta_test_vs_current": -0.4,
            "delta_test_vs_pricefm": 0.8,
            "candidate_family": "graph_geometry",
            "selection_rule": "median_validation_AQL_only",
            "test_metrics_role": "audit_only",
            "promotion_decision": "promote_validation_and_test_gain",
        }
    ])
    write_csv(root / "stage_n_instability.csv", [
        {
            "region": "AA",
            "fold": 1,
            "validation_selected_id": "stagen_aa",
            "validation_selected_method": "qdesn_exal_rhs_ns_exact_chunked",
            "validation_selected_val_AQL": 8.9,
            "validation_selected_test_AQL": 9.6,
            "test_oracle_id": "stagen_aa_oracle",
            "test_oracle_method": "qdesn_exal_rhs_ns_exact_chunked",
            "test_oracle_val_AQL": 9.2,
            "test_oracle_test_AQL": 9.4,
            "test_oracle_delta_vs_current": -0.6,
            "test_oracle_delta_vs_pricefm": 0.6,
            "same_candidate": False,
            "oracle_gain_missed_by_validation": False,
            "oracle_advantage_over_validation": -0.2,
            "promotion_decision": "promote_validation_and_test_gain",
        }
    ])
    write_csv(root / "stage_n_horizon.csv", [
        {
            "region": "BB",
            "fold": 1,
            "horizon_group": "1-24",
            "validation_selected_id": "stagen_bb",
            "validation_selected_method": "qdesn_exal_rhs_ns_exact_chunked",
            "test_oracle_id": "stagen_bb_oracle",
            "test_oracle_method": "qdesn_exal_rhs_ns_exact_chunked",
            "validation_selected_val_AQL": 4.0,
            "validation_selected_test_AQL": 4.0,
            "test_oracle_val_AQL": 4.1,
            "test_oracle_test_AQL": 3.9,
            "oracle_minus_validation_test_AQL": -0.1,
            "oracle_better_on_test_group": True,
        },
        {
            "region": "BB",
            "fold": 1,
            "horizon_group": "49-72",
            "validation_selected_id": "stagen_bb",
            "validation_selected_method": "qdesn_exal_rhs_ns_exact_chunked",
            "test_oracle_id": "stagen_bb_oracle",
            "test_oracle_method": "qdesn_exal_rhs_ns_exact_chunked",
            "validation_selected_val_AQL": 8.0,
            "validation_selected_test_AQL": 8.0,
            "test_oracle_val_AQL": 8.1,
            "test_oracle_test_AQL": 7.9,
            "oracle_minus_validation_test_AQL": -0.1,
            "oracle_better_on_test_group": True,
        },
    ])
    write_csv(root / "stage_o_rule_audit.csv", [
        {
            "rule_id": "val_aql_min",
            "n_region_folds": 1,
            "n_test_improvements": 1,
            "n_beats_pricefm": 0,
            "n_promotions_strict": 1,
            "mean_test_delta_vs_current": -0.4,
            "mean_test_delta_vs_pricefm": 0.8,
            "selection_uses_test_metrics": False,
            "adopt_without_confirmation": False,
        }
    ])
    write_csv(root / "stage_o_rule_selected.csv", [
        {
            "rule_id": "val_aql_min",
            "region": "AA",
            "fold": 1,
            "id": "stageo_aa",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "val_AQL": 8.8,
            "test_AQL": 9.7,
            "current_test_AQL": 10.0,
            "pricefm_AQL": 8.8,
            "delta_test_vs_current": -0.3,
            "delta_test_vs_pricefm": 0.9,
            "test_metrics_role": "audit_only",
        }
    ])
    write_csv(root / "stage_p_flags.csv", [
        {
            "region": "AA",
            "fold": 1,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 9.5,
            "AQCR": 0.0,
            "MAE": 19.0,
            "RMSE": 28.5,
            "pricefm_phase1_AQL": 8.8,
            "delta_abs": 0.7,
            "delta_rel": 0.079,
            "decision_label": "local_lags_pricefm",
        }
    ])
    (root / "stage_q_summary.json").write_text(json.dumps({
        "run_clean": True,
        "stage_m_surface_changed": False,
        "priority1_launch_recommended": False,
        "no_stage_q_promotions_recommended": True,
    }))
    write_csv(root / "stage_q_transfer.csv", [
        {
            "region": "BB",
            "fold": 1,
            "n_qdesn_candidates": 4,
            "spearman_val_test_rank": 0.05,
            "validation_selected_experiment_id": "stageq_bb_val",
            "validation_selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "validation_selected_val_AQL": 8.5,
            "validation_selected_test_AQL": 10.0,
            "test_oracle_experiment_id": "stageq_bb_oracle",
            "test_oracle_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "test_oracle_val_AQL": 8.7,
            "test_oracle_test_AQL": 9.5,
            "validation_selected_test_regret": 0.5,
            "selected_delta_test_vs_stage_p": 0.6,
            "selected_delta_test_vs_pricefm": 1.1,
            "oracle_delta_test_vs_stage_p": 0.1,
            "oracle_delta_test_vs_pricefm": 0.6,
            "same_candidate": False,
        }
    ])
    write_csv(root / "stage_q_validation.csv", [
        {
            "region": "BB",
            "fold": 1,
            "experiment_id": "stageq_bb_val",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "val_AQL": 8.5,
            "test_AQL": 10.0,
            "delta_test_vs_pricefm": 1.1,
            "test_metrics_role": "audit_only",
        }
    ])
    write_csv(root / "stage_q_oracle.csv", [
        {
            "region": "BB",
            "fold": 1,
            "experiment_id": "stageq_bb_oracle",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "val_AQL": 8.7,
            "test_AQL": 9.5,
            "delta_test_vs_pricefm": 0.6,
            "test_metrics_role": "audit_only",
        }
    ])
    write_csv(root / "stage_q_horizon.csv", [
        {
            "region": "BB",
            "fold": 1,
            "experiment_id": "stageq_bb_val",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_view": "validation_selected",
            "horizon_group": "1-24",
            "AQL": 4.0,
            "MAE": 8.0,
            "RMSE": 12.0,
        },
        {
            "region": "BB",
            "fold": 1,
            "experiment_id": "stageq_bb_val",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_view": "validation_selected",
            "horizon_group": "49-72",
            "AQL": 8.0,
            "MAE": 16.0,
            "RMSE": 24.0,
        },
    ])

    args = stage_r.parser().parse_args([
        "--stage-m-surface-csv", str(root / "surface.csv"),
        "--stage-m-current-vt-csv", str(root / "current_vt.csv"),
        "--stage-m-alignment-rows-csv", str(root / "alignment.csv"),
        "--stage-m-split-csv", str(root / "split.csv"),
        "--stage-n-selected-csv", str(root / "stage_n_selected.csv"),
        "--stage-n-instability-csv", str(root / "stage_n_instability.csv"),
        "--stage-n-horizon-csv", str(root / "stage_n_horizon.csv"),
        "--stage-o-rule-audit-csv", str(root / "stage_o_rule_audit.csv"),
        "--stage-o-rule-selected-csv", str(root / "stage_o_rule_selected.csv"),
        "--stage-p-flags-csv", str(root / "stage_p_flags.csv"),
        "--stage-q-summary-json", str(root / "stage_q_summary.json"),
        "--stage-q-transfer-csv", str(root / "stage_q_transfer.csv"),
        "--stage-q-validation-csv", str(root / "stage_q_validation.csv"),
        "--stage-q-oracle-csv", str(root / "stage_q_oracle.csv"),
        "--stage-q-horizon-csv", str(root / "stage_q_horizon.csv"),
        "--output-dir", str(out),
    ])
    return args, out


def test_stage_r_writes_diagnostic_outputs_without_launch_configs(tmp_path):
    args, out = make_fixture(tmp_path)
    summary = stage_r.diagnose(args)

    assert summary["diagnostic_only"] is True
    assert summary["writes_launch_configs"] is False
    assert summary["stage_m_surface_changed"] is False
    assert summary["stage_q_priority1_launch_recommended"] is False

    expected = {
        "stage_r_input_manifest.csv",
        "stage_r_region_fold_scorecard.csv",
        "stage_r_selection_transfer_by_source.csv",
        "stage_r_candidate_transfer_rows.csv",
        "stage_r_horizon_block_diagnostics.csv",
        "stage_r_information_set_parity.csv",
        "stage_r_failure_mode_assignments.csv",
        "stage_r_next_grid_recommendations.csv",
        "stage_r_summary.md",
        "summary.json",
    }
    assert expected.issubset({p.name for p in out.iterdir()})
    assert not list(out.glob("*.yaml"))
    assert not list(out.glob("*.yml"))

    failures = pd.read_csv(out / "stage_r_failure_mode_assignments.csv")
    by_key = {(r.region, int(r.fold)): r for r in failures.itertuples()}
    assert by_key[("AA", 1)].primary_failure_mode == "graph_parity_gap"
    assert by_key[("BB", 1)].primary_failure_mode == "selection_instability"
    assert by_key[("CC", 1)].primary_failure_mode == "no_action"

    candidates = pd.read_csv(out / "stage_r_candidate_transfer_rows.csv")
    oracle = candidates[candidates["selection_view"].eq("test_oracle_audit_only")]
    assert not oracle.empty
    assert set(oracle["test_metrics_role"]) == {"audit_only"}


def test_stage_r_missing_input_fails_clearly(tmp_path):
    args, _ = make_fixture(tmp_path)
    Path(args.stage_q_summary_json).unlink()
    with pytest.raises(FileNotFoundError, match="stage_q_summary"):
        stage_r.diagnose(args)


def test_stage_r_duplicate_region_fold_keys_fail(tmp_path):
    args, _ = make_fixture(tmp_path, duplicate_surface=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_r.diagnose(args)


def test_stage_r_nonfinite_metric_fails(tmp_path):
    args, _ = make_fixture(tmp_path, nonfinite=True)
    with pytest.raises(ValueError, match="non-finite"):
        stage_r.diagnose(args)
