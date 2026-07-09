"""Tests for Stage-S PriceFM targeted-rescue manifest preparation."""

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


stage_s = load_script("79_prepare_pricefm_stage_s_targeted_rescue.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def base_score_row(region, fold, action="no_launch", mode="no_action"):
    info = "target_only" if action == stage_s.GRAPH_PARITY_ACTION else "pricefm_graph_inputs"
    policy = "target_only" if action == stage_s.GRAPH_PARITY_ACTION else "graph_khop"
    return {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "model_family": "qdesn_exal",
        "information_set": info,
        "local_AQL": 10.0,
        "pricefm_AQL": 9.0,
        "delta_abs": 1.0 if action != "no_launch" else -0.5,
        "delta_rel": 0.1,
        "local_wins": action == "no_launch",
        "decision_label": "pricefm_better" if action != "no_launch" else "local_beats_pricefm",
        "feature_policy": policy,
        "experiment_id": "current_{}_{}".format(region, fold),
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "seed": 20260628,
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.35,
        "graph_degree": 2 if policy == "graph_khop" else "",
        "current_validation_AQL": 10.5,
        "current_median_test_AQL": 10.0,
        "abs_test_minus_validation_AQL": 0.5,
        "primary_failure_mode": mode,
    }


def recommendation_row(region, fold, action, priority, mode):
    return {
        "region": region,
        "fold": fold,
        "primary_failure_mode": mode,
        "secondary_failure_modes": "",
        "recommended_action": action,
        "stage_s_priority": priority,
        "writes_launch_config": False,
        "requires_authorization_before_launch": True,
        "diagnostic_rationale": "unit",
        "current_delta_AQL": 1.0,
        "current_information_set": "target_only",
    }


def template_grid():
    return {
        "pricefm_desn_experiment_grid": {
            "grid_id": "template",
            "purpose": "unit",
            "base": {
                "data_config": "application/config/pricefm_data_pipeline.yaml",
                "full_config": "application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml",
                "generated_root": "old/generated",
                "run_root": "old/run",
            },
            "scope": {
                "regions": ["AA"],
                "folds": [1],
                "quantiles": [0.5],
                "horizons": "all",
                "ranking_split": "val",
                "audit_split": "test",
                "ranking_unit": "original",
                "ranking_metric": "AQL",
            },
            "fixed": {
                "lead_window": 96,
                "feature_map": "window_reservoir_v1",
                "include_intercept": True,
                "shrink_intercept": False,
                "train_origin_limit": 3000,
                "train_origin_selection": "tail",
                "row_chunk_size": 512,
                "projection_scale": 1.0,
                "recurrent_sparsity": 0.05,
                "reservoir_activation": "tanh",
                "state_output": "final_layer",
                "default_jobs": 1,
                "qdesn_likelihoods": ["al", "exal"],
                "warm_start_enabled": True,
                "exact_equivalence_train_rows": 1000,
                "artifact_hygiene": {
                    "enabled": True,
                    "clean_adapter_patterns": ["X_*.csv"],
                    "clean_model_patterns": ["*.rds", "*.rda"],
                    "preserve_patterns": ["metric_summary.csv", "report.md"],
                },
            },
            "launch": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    }


def make_fixture(tmp_path, *, duplicate_recommendations=False):
    root = tmp_path / "inputs"
    out = tmp_path / "out"
    grid = tmp_path / "stage_s.yaml"
    rec = [
        recommendation_row("AA", 1, stage_s.GRAPH_PARITY_ACTION, stage_s.STAGE_S_PRIORITY, "graph_parity_gap"),
        recommendation_row("BB", 2, stage_s.HORIZON_ACTION, stage_s.STAGE_S_PRIORITY, "late_horizon_gap"),
        recommendation_row("RO", 1, "no_launch", "not_eligible", "selection_instability"),
    ]
    if duplicate_recommendations:
        rec.append(dict(rec[0]))
    for i in range(39):
        rec.append(recommendation_row("ZZ{:02d}".format(i), 1 + i % 3, "no_launch", "not_eligible", "no_action"))
    score = [
        base_score_row("AA", 1, stage_s.GRAPH_PARITY_ACTION, "graph_parity_gap"),
        base_score_row("BB", 2, stage_s.HORIZON_ACTION, "late_horizon_gap"),
        base_score_row("RO", 1, "no_launch", "selection_instability"),
    ]
    for i in range(39):
        score.append(base_score_row("ZZ{:02d}".format(i), 1 + i % 3, "no_launch", "no_action"))
    surface = [
        {"region": row["region"], "fold": row["fold"], "local_AQL": row["local_AQL"], "pricefm_AQL": row["pricefm_AQL"]}
        for row in score
    ]
    horizon = [
        {
            "source_label": "stage_n",
            "region": "BB",
            "fold": 2,
            "horizon_group": "49-72",
            "horizon_band": "middle_late",
            "validation_selected_AQL": 8.0,
            "test_oracle_AQL": 7.5,
            "oracle_minus_validation_AQL": -0.5,
            "oracle_better": True,
        }
    ]
    write_csv(root / "rec.csv", rec)
    write_csv(root / "score.csv", score)
    write_csv(root / "surface.csv", surface)
    write_csv(root / "horizon.csv", horizon)
    write_yaml(root / "template.yaml", template_grid())
    return {
        "rec": root / "rec.csv",
        "score": root / "score.csv",
        "surface": root / "surface.csv",
        "horizon": root / "horizon.csv",
        "template": root / "template.yaml",
        "out": out,
        "grid": grid,
    }


def args_for(paths, **kwargs):
    args = stage_s.parser().parse_args([])
    args.stage_r_recommendations_csv = str(paths["rec"])
    args.stage_r_scorecard_csv = str(paths["score"])
    args.stage_r_horizon_csv = str(paths["horizon"])
    args.stage_m_surface_csv = str(paths["surface"])
    args.template_grid_config = str(paths["template"])
    args.output_dir = str(paths["out"])
    args.stage_s_grid_config = str(paths["grid"])
    args.stage_s_generated_root = str(paths["out"] / "generated")
    args.stage_s_run_root = str(paths["out"] / "runs")
    args.force = True
    args.max_graph_variants_per_row = 12
    args.max_horizon_variants_per_row = 6
    args.max_total_experiments = 30
    for key, value in kwargs.items():
        setattr(args, key, value)
    return args


def test_stage_s_writes_manifest_only_by_default(tmp_path):
    paths = make_fixture(tmp_path)
    summary = stage_s.prepare(args_for(paths))
    assert summary["status"] == "completed"
    assert summary["write_grid"] is False
    assert summary["writes_launch_configs"] is False
    assert summary["launches_models"] is False
    assert not paths["grid"].exists()
    targets = pd.read_csv(paths["out"] / "stage_s_target_rows.csv")
    manifest = pd.read_csv(paths["out"] / "stage_s_experiment_manifest.csv")
    blocked = pd.read_csv(paths["out"] / "stage_s_blocked_rows.csv")
    assert set(zip(targets["region"], targets["fold"])) == {("AA", 1), ("BB", 2)}
    assert ("RO", 1) not in set(zip(targets["region"], targets["fold"]))
    assert ("RO", 1) in set(zip(blocked["region"], blocked["fold"]))
    assert len(manifest) == 18
    assert manifest["selection_is_validation_only"].all()
    assert manifest["test_metrics_role"].eq("audit_only").all()


def test_stage_s_graph_and_horizon_metadata_are_correct(tmp_path):
    paths = make_fixture(tmp_path)
    stage_s.prepare(args_for(paths))
    manifest = pd.read_csv(paths["out"] / "stage_s_experiment_manifest.csv")
    graph = manifest[manifest["recommended_action"].eq(stage_s.GRAPH_PARITY_ACTION)]
    horizon = manifest[manifest["recommended_action"].eq(stage_s.HORIZON_ACTION)]
    assert set(graph["feature_policy"]) == {"graph_khop", "graph_summary_mean"}
    assert set(graph["graph_degree"].astype(int)) == {1, 2}
    assert graph["input_scope"].str.startswith("pricefm_").all()
    assert graph["graph_hash"].str.len().eq(64).all()
    assert set(horizon["candidate_family"]) == {"horizon_block_pilot"}
    assert set(horizon["selection_rule"]) == {"horizon_block_validation_audit"}


def test_stage_s_can_write_grid_when_requested(tmp_path):
    paths = make_fixture(tmp_path)
    summary = stage_s.prepare(args_for(paths, write_grid=True))
    assert summary["write_grid"] is True
    assert paths["grid"].exists()
    payload = yaml.safe_load(paths["grid"].read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["grid_id"] == "pricefm_stage_s_targeted_rescue_20260628"
    assert len(grid["experiments"]) == summary["n_experiments"]
    assert grid["fixed"]["artifact_hygiene"]["enabled"] is True
    assert "*.rds" in grid["fixed"]["artifact_hygiene"]["clean_model_patterns"]
    assert grid["launch"]["stage_s_priority0_targeted_rescue"]["cell_jobs"] == 1


def test_stage_s_missing_input_fails(tmp_path):
    paths = make_fixture(tmp_path)
    paths["rec"].unlink()
    with pytest.raises(FileNotFoundError, match="Stage-R recommendations"):
        stage_s.prepare(args_for(paths))


def test_stage_s_duplicate_recommendations_fail(tmp_path):
    paths = make_fixture(tmp_path, duplicate_recommendations=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_s.prepare(args_for(paths))


def test_stage_s_experiment_cap_fails(tmp_path):
    paths = make_fixture(tmp_path)
    with pytest.raises(ValueError, match="exceeds cap"):
        stage_s.prepare(args_for(paths, max_total_experiments=5))
