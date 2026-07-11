"""Tests for PriceFM Stage-R25 post-R24 broad launch prep."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name: str):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def template_grid(path: Path, tmp_path: Path) -> Path:
    write_yaml(
        path,
        {
            "pricefm_desn_experiment_grid": {
                "grid_id": "unit_template",
                "purpose": "unit",
                "base": {
                    "data_config": "application/config/pricefm_data_pipeline.yaml",
                    "full_config": "application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml",
                    "generated_root": str(tmp_path / "generated_template"),
                    "run_root": str(tmp_path / "runs_template"),
                },
                "scope": {
                    "regions": [],
                    "folds": [],
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
                    "exact_equivalence_train_rows": 1000,
                },
                "launch": {},
                "experiments": [],
                "experiment_blocks": [],
            }
        },
    )
    return path


def case_summary_row(case_id: str, region: str, fold: int, focus: str, gap_q: float, gap_p: float) -> dict:
    return {
        "stage_r22b_case_id": case_id,
        "region": region,
        "fold": fold,
        "case_feasibility_status": "existing_prediction_calibration_ready",
        "horizon_focus": focus,
        "validation_selected_experiment_id": f"{case_id}_selected",
        "validation_selected_screening_arm": "horizon_weighted_readout_loss",
        "validation_selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "val_AQL": 1.0,
        "validation_selected_test_AQL": 3.0,
        "current_qdesn_AQL": 2.5,
        "current_pricefm_AQL": 2.0,
        "validation_selected_minus_current_qdesn": gap_q,
        "validation_selected_minus_pricefm": gap_p,
        "beats_current_qdesn_on_test": False,
        "beats_pricefm_on_test": False,
        "validation_selected_beats_both": False,
        "test_oracle_experiment_id": f"{case_id}_oracle",
        "test_oracle_screening_arm": "horizon_weighted_readout_loss",
        "test_oracle_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "test_oracle_AQL": 3.0,
        "test_oracle_minus_current_qdesn": gap_q,
        "test_oracle_minus_pricefm": gap_p,
        "test_oracle_beats_both": False,
        "closeout_decision": "not_promotable",
    }


def selected_row(case_id: str, region: str, fold: int, focus: str, policy: str, units: str) -> dict:
    return {
        "experiment_id": f"{case_id}_selected",
        "region": region,
        "fold": fold,
        "priority": 0,
        "target_quantile": 0.5,
        "stage": "stage_r22c_case_specific_horizon_screening",
        "stage_r22b_case_id": case_id,
        "stage_r22b_candidate_id": f"{case_id}_candidate",
        "screening_arm": "horizon_weighted_readout_loss",
        "candidate_family": "case_specific_horizon_weighted_readout",
        "horizon_focus": focus,
        "horizon_weight_multiplier": 2.0,
        "max_promotable_test_AQL": 2.0,
        "feature_policy": policy,
        "implemented_feature_policy": True,
        "lag_window": 96,
        "depth": 2,
        "units": units,
        "feature_dim": 64,
        "state_output": "final_layer",
        "alpha": 0.35,
        "rho": 0.82,
        "input_scale": 0.30,
        "tau0": 0.001,
        "seed": 1,
        "graph_degree": 1,
        "selection_is_validation_only": True,
        "selection_rule": "validation_AQL_only_within_experiment",
        "test_metrics_role": "audit_only_after_frozen_validation_selection",
        "launch_authorized_by_user": True,
        "launcher_invoked_by_prep": False,
        "fits_models_when_launched": True,
        "mutates_registry": False,
        "mutates_manuscript": False,
        "requires_stage_r22c_closeout_gate": True,
        "requires_full_quantile_gate": True,
        "case_specific_spec_key": f"{case_id}_key",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "val_AQL": 1.0,
        "test_AQL": 3.0,
        "current_qdesn_AQL": 2.5,
        "current_pricefm_AQL": 2.0,
        "test_minus_current_qdesn": 0.5,
        "test_minus_pricefm": 1.0,
    }


def make_fixture(tmp_path: Path):
    r22d = tmp_path / "r22d"
    r23 = tmp_path / "r23"
    r24 = tmp_path / "r24"
    out = tmp_path / "out"
    grid_config = tmp_path / "grid.yaml"
    generated = tmp_path / "generated"
    runs = tmp_path / "runs"
    template = template_grid(tmp_path / "template.yaml", tmp_path)

    write_json(r22d / "summary.json", {"stage": "pricefm_stage_r22d_case_specific_screening_closeout", "status": "completed_no_promotions"})
    write_csv(
        r22d / "pricefm_stage_r22d_case_summary.csv",
        [
            case_summary_row("r22b_no_4_f1", "NO_4", 1, "1-24", 0.45, 0.7),
            case_summary_row("r22b_hu_f2", "HU", 2, "25-48", 1.9, 3.2),
        ],
    )
    write_csv(
        r22d / "pricefm_stage_r22d_validation_selected_case.csv",
        [
            selected_row("r22b_no_4_f1", "NO_4", 1, "1-24", "graph_summary_mean_std", "[96, 64]"),
            selected_row("r22b_hu_f2", "HU", 2, "25-48", "graph_khop", "[128, 96, 64]"),
        ],
    )
    write_csv(r22d / "pricefm_stage_r22d_metric_rows.csv", [{"experiment_id": "x", "region": "NO_4", "fold": 1}])
    (r22d / "pricefm_stage_r22d_promotion_queue.csv").parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(columns=["experiment_id", "region", "fold"]).to_csv(
        r22d / "pricefm_stage_r22d_promotion_queue.csv",
        index=False,
    )

    write_json(r23 / "summary.json", {"stage": "pricefm_stage_r23_mechanism_capability_audit", "status": "completed_expensive_path_blocked_until_mechanisms_are_real"})
    write_csv(
        r23 / "pricefm_stage_r23_runner_capability_matrix.csv",
        [{"mechanism": "horizon_weighted_readout_loss", "effective_status": "metadata_only_not_implemented_in_pricefm_runner"}],
    )
    write_csv(
        r23 / "pricefm_stage_r23_expensive_path_bounds_recommendation.csv",
        [{"axis_group": "horizon_weighted_loss", "must_implement_before_launch": True}],
    )

    write_json(r24 / "summary.json", {"stage": "pricefm_stage_r24_postfit_calibration_materialized", "status": "completed_no_ready_postfit_candidates"})
    write_csv(r24 / "pricefm_stage_r24_no_launch_gates.csv", [{"gate": "unit", "passed": True}])
    return r22d, r23, r24, out, grid_config, generated, runs, template


def test_stage_r25_materializes_true_horizon_weighted_broad_grid(tmp_path):
    mod = load_script("149_prepare_pricefm_stage_r25_post_r24_broad_launch.py")
    r22d, r23, r24, out, grid_config, generated, runs, template = make_fixture(tmp_path)
    summary = mod.run(
        mod.parser().parse_args(
            [
                "--r22d-dir",
                str(r22d),
                "--r23-dir",
                str(r23),
                "--r24-dir",
                str(r24),
                "--template-grid-config",
                str(template),
                "--output-dir",
                str(out),
                "--grid-config",
                str(grid_config),
                "--generated-root",
                str(generated),
                "--run-root",
                str(runs),
                "--expected-cases",
                "2",
                "--arms-per-case",
                "10",
                "--write-grid",
                "true",
                "--force",
                "true",
            ]
        )
    )
    assert summary["status"] == "completed"
    assert summary["n_launch_experiments"] == 20
    manifest = pd.read_csv(out / "pricefm_stage_r25_launch_manifest.csv")
    assert manifest.shape[0] == 20
    assert manifest["horizon_weighting_enabled"].map(bool).all()
    assert manifest["mutates_registry"].map(lambda x: str(x).lower() == "false").all()
    assert manifest["mutates_manuscript"].map(lambda x: str(x).lower() == "false").all()
    assert {"short_lag_weighted", "long_lag_weighted", "alt_information_set_weighted"}.issubset(
        set(manifest["stage_r25_arm"])
    )
    gates = pd.read_csv(out / "pricefm_stage_r25_launch_prep_gates.csv")
    assert gates["passed"].map(bool).all()

    payload = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    assert payload["grid_id"] == "pricefm_stage_r25_post_r24_broad_horizon_weighted_20260709"
    assert len(payload["experiments"]) == 20
    first = payload["experiments"][0]
    weighting = first["training"]["horizon_weighting"]
    assert weighting["enabled"] is True
    assert weighting["mode"] == "integer_frequency_replication"
    assert weighting["apply_to"] == ["qdesn"]
    assert payload["fixed"]["qdesn_likelihoods"] == ["al", "exal"]
    assert not list(out.glob("*.rds"))


def test_stage_r25_refuses_unresolved_r24_gates(tmp_path):
    mod = load_script("149_prepare_pricefm_stage_r25_post_r24_broad_launch.py")
    r22d, r23, r24, out, grid_config, generated, runs, template = make_fixture(tmp_path)
    write_csv(r24 / "pricefm_stage_r24_no_launch_gates.csv", [{"gate": "unit", "passed": False}])
    try:
        mod.run(
            mod.parser().parse_args(
                [
                    "--r22d-dir",
                    str(r22d),
                    "--r23-dir",
                    str(r23),
                    "--r24-dir",
                    str(r24),
                    "--template-grid-config",
                    str(template),
                    "--output-dir",
                    str(out),
                    "--grid-config",
                    str(grid_config),
                    "--generated-root",
                    str(generated),
                    "--run-root",
                    str(runs),
                    "--expected-cases",
                    "2",
                    "--arms-per-case",
                    "10",
                    "--write-grid",
                    "false",
                    "--force",
                    "true",
                ]
            )
        )
    except ValueError as exc:
        assert "Stage-R24 gates failed" in str(exc)
    else:
        raise AssertionError("Stage-R25 should reject failed R24 gates")
