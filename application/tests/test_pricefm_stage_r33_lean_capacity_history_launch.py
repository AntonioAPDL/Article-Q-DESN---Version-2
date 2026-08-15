"""Tests for the PriceFM Stage-R33 lean capacity/history launch prep."""

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


def load_script():
    path = SCRIPT_DIR / "157_prepare_pricefm_stage_r33_lean_capacity_history_launch.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def make_template(tmp_path: Path) -> Path:
    data_config = tmp_path / "pricefm_data.yaml"
    full_config = tmp_path / "pricefm_full.yaml"
    write_yaml(
        data_config,
        {
            "pricefm": {
                "regions": ["FI", "HU", "NO_3", "NO_4", "SE_1", "SE_2", "SK"],
                "windows": {"lag_window": 96, "lead_window": 96},
                "pilot": {"region": "HU", "fold": 2},
            }
        },
    )
    write_yaml(full_config, {"pricefm_desn_full": {"dummy": True}})
    template = tmp_path / "template.yaml"
    write_yaml(
        template,
        {
            "pricefm_desn_experiment_grid": {
                "grid_id": "template",
                "purpose": "unit",
                "base": {
                    "data_config": str(data_config),
                    "full_config": str(full_config),
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
    return template


def case_row(region: str, fold: int, policy: str) -> dict:
    return {
        "region": region,
        "fold": fold,
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "horizon_focus": "25-48",
        "feature_policy": policy,
        "stage_r25_arm": "deeper_units_weighted",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "test_minus_pricefm": 1.0,
        "test_minus_current_qdesn": 0.5,
        "best_observed_stage_r25_r27_test_minus_pricefm": 0.8,
        "r28_queue": "moderate_gap_horizon_block_readout",
        "include_in_stage_r29_main_launch": True,
        "current_pricefm_AQL": 7.0,
        "current_qdesn_AQL": 8.0,
        "lag_window": 96,
        "depth": 3,
        "units": "[128, 96, 64]",
        "feature_dim": 64,
        "state_output": "final_layer",
        "alpha": 0.4,
        "rho": 0.86,
        "input_scale": 0.3,
        "tau0": 0.001,
        "horizon_weight_multiplier": 2.5,
        "selection_rule_for_next_launch": "validation_AQL_only_within_case",
        "test_metrics_role_next_launch": "audit_only_after_frozen_validation_selection",
        "stage_r29_case_status": "included_in_horizon_block_readout_main_launch",
    }


def make_fixture(tmp_path: Path):
    r29 = tmp_path / "r29"
    r32 = tmp_path / "r32"
    out = tmp_path / "out"
    grid_config = tmp_path / "stage_r33.yaml"
    template = make_template(tmp_path)
    write_csv(
        r29 / "pricefm_stage_r29_case_plan.csv",
        [
            case_row("HU", 2, "graph_khop"),
            case_row("NO_4", 2, "graph_neighbor_spread_summary"),
        ],
    )
    write_csv(r29 / "pricefm_stage_r29_launch_prep_gates.csv", [{"gate": "ok", "passed": True, "detail": "ok"}])
    write_csv(
        r29 / "pricefm_stage_r29_stage_r30_launch_manifest.csv",
        [
            {
                "experiment_id": "r30_hu_f2",
                "region": "HU",
                "fold": 2,
                "alpha": 0.25,
                "rho": 0.95,
                "input_scale": 0.2,
                "tau0": 0.0005,
                "horizon_weight_multiplier": 2.0,
            },
            {
                "experiment_id": "r30_no4_f2",
                "region": "NO_4",
                "fold": 2,
                "alpha": 0.5,
                "rho": 0.82,
                "input_scale": 0.3,
                "tau0": 0.001,
                "horizon_weight_multiplier": 3.0,
            },
        ],
    )
    write_csv(
        r32 / "pricefm_stage_r32_partial_closeout_gates.csv",
        [
            {"gate": "lean_redesign_recommended", "passed": True, "detail": "recommended"},
            {"gate": "r32_relaunch_same_design_allowed", "passed": False, "detail": "blocked"},
        ],
    )
    write_csv(
        r32 / "pricefm_stage_r32_partial_next_design_recommendations.csv",
        [
            {"recommendation": "do_not_resume_r32_same_design", "value": "true", "rationale": "negative", "launch_allowed_now": False},
            {"recommendation": "n_per_layer_bounds", "value": "48,64,96", "rationale": "lean", "launch_allowed_now": False},
            {"recommendation": "depth_bounds", "value": "2,3", "rationale": "lean", "launch_allowed_now": False},
            {"recommendation": "lag_window_bounds", "value": "96,168,240", "rationale": "lean", "launch_allowed_now": False},
            {"recommendation": "state_output_priority", "value": "final_layer first", "rationale": "lean", "launch_allowed_now": False},
            {"recommendation": "regularization_grid", "value": "tau0 0.001-0.002", "rationale": "reference", "launch_allowed_now": False},
            {"recommendation": "targeting_rule", "value": "wait for R30 closeout", "rationale": "targeted", "launch_allowed_now": False},
        ],
    )
    write_csv(
        r32 / "pricefm_stage_r32_partial_capacity_diagnostics.csv",
        [{"stage_r32_profile": "balanced_final_layer", "lag_window": 300, "depth": 3, "n_per_layer": 100}],
    )
    write_json(
        r32 / "summary.json",
        {"status": "completed", "r32_completed_with_metrics": 9, "r32_beats_both_rows": 0},
    )
    return r29, r32, out, template, grid_config


def args_for(mod, r29: Path, r32: Path, out: Path, template: Path, grid_config: Path):
    return mod.parser().parse_args(
        [
            "--stage-r29-dir",
            str(r29),
            "--stage-r32-closeout-dir",
            str(r32),
            "--template-grid-config",
            str(template),
            "--output-dir",
            str(out),
            "--grid-config",
            str(grid_config),
            "--grid-id",
            "pricefm_stage_r33_lean_capacity_history_unit",
            "--generated-root",
            str(out / "generated"),
            "--run-root",
            str(out / "runs"),
            "--expected-cases",
            "2",
            "--write-grid",
            "true",
            "--force",
            "true",
        ]
    )


def test_stage_r33_materializes_requested_lean_grid_without_launching(tmp_path):
    mod = load_script()
    r29, r32, out, template, grid_config = make_fixture(tmp_path)
    summary = mod.run(args_for(mod, r29, r32, out, template, grid_config))

    assert summary["status"] == "completed"
    assert summary["n_launch_experiments"] == 48
    assert summary["arms_per_case"] == 24
    assert summary["prep_invoked_launcher"] is False
    assert summary["launch_authorized_by_user"] is False
    assert summary["depths"] == [2, 3]
    assert summary["n_values"] == [48, 64, 96]
    assert summary["lag_windows"] == [96, 100]
    assert summary["tau0_values"] == [0.0001, 0.0005]
    assert grid_config.exists()

    payload = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    experiments = payload["experiments"]
    assert len(experiments) == 48
    assert {exp["lag_window"] for exp in experiments} == {96, 100}
    assert {exp["depth"] for exp in experiments} == {2, 3}
    assert {tuple(exp["units"]) for exp in experiments} == {
        (48, 48),
        (64, 64),
        (96, 96),
        (48, 48, 48),
        (64, 64, 64),
        (96, 96, 96),
    }
    assert {exp["state_output"] for exp in experiments} == {"final_layer"}
    assert {exp["alpha"] for exp in experiments} == {0.2}
    assert {exp["rho"] for exp in experiments} == {0.95}
    assert {exp["input_scale"] for exp in experiments} == {0.2}
    assert {exp["tau0"] for exp in experiments} == {0.0001, 0.0005}
    launch_block = payload["launch"]["stage_r33_full_background_launch_requires_explicit_user_authorization"]
    assert launch_block["dry_run"] is False
    assert launch_block["authorized_now"] is False

    manifest = pd.read_csv(out / "pricefm_stage_r33_launch_manifest.csv")
    assert manifest["mutates_registry"].eq(False).all()
    assert manifest["mutates_manuscript"].eq(False).all()
    assert manifest["launcher_invoked_by_prep"].eq(False).all()
    assert manifest["launch_authorized_by_user"].eq(False).all()
    assert manifest["selection_rule"].eq("validation_AQL_only_within_case").all()
    gates = pd.read_csv(out / "pricefm_stage_r33_launch_prep_gates.csv")
    assert gates["passed"].map(bool).all()
    design = pd.read_csv(out / "pricefm_stage_r33_design_audit.csv")
    assert {"depth_D", "width_n", "lag_window_m", "tau0"}.issubset(set(design["axis"]))


def test_stage_r33_rejects_r32_depth_or_tau0_drift(tmp_path):
    mod = load_script()
    r29, r32, out, template, grid_config = make_fixture(tmp_path)
    args = args_for(mod, r29, r32, out, template, grid_config)
    args.d_values = "2,4"
    try:
        mod.run(args)
    except ValueError as exc:
        assert "D values 2 and 3" in str(exc)
    else:
        raise AssertionError("Stage-R33 should reject the old R32 depth axis")

    args = args_for(mod, r29, r32, out, template, grid_config)
    args.tau0_values = "0.0005,0.001"
    try:
        mod.run(args)
    except ValueError as exc:
        assert "tau0 values 1e-4 and 5e-4" in str(exc)
    else:
        raise AssertionError("Stage-R33 should reject drifting away from the requested tau0 pair")
