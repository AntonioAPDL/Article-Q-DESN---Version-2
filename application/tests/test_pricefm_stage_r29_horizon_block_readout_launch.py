"""Tests for the PriceFM Stage-R29 horizon-block readout launch prep."""

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
    path = SCRIPT_DIR / "154_prepare_pricefm_stage_r29_horizon_block_readout_launch.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def case_row(region: str, fold: int, queue: str) -> dict:
    return {
        "region": region,
        "fold": fold,
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "horizon_focus": "73-96" if region == "NO_4" else "1-24",
        "feature_policy": "target_only",
        "stage_r25_arm": "alt_information_set_weighted",
        "method_id": "qdesn_al_rhs_ns_exact_chunked",
        "test_minus_pricefm": 0.5,
        "test_minus_current_qdesn": 0.1,
        "best_observed_stage_r25_r27_test_minus_pricefm": 0.4,
        "r28_queue": queue,
        "include_in_stage_r29_main_launch": True,
        "current_pricefm_AQL": 1.2,
        "current_qdesn_AQL": 1.3,
        "lag_window": 96,
        "depth": 2,
        "units": "[96, 96]",
        "feature_dim": 96,
        "state_output": "final_layer",
        "alpha": 0.4,
        "rho": 0.86,
        "input_scale": 0.25,
        "tau0": 0.001,
        "horizon_weight_multiplier": 2.0,
        "selection_rule_for_next_launch": "validation_AQL_only_within_case",
        "test_metrics_role_next_launch": "audit_only_after_frozen_validation_selection",
    }


def make_template(tmp_path: Path) -> Path:
    data_config = tmp_path / "pricefm_data.yaml"
    full_config = tmp_path / "pricefm_full.yaml"
    regions = ["NO_4", "FI", "NO_3", "SE_1", "SE_2", "EE", "SE_3"]
    write_yaml(
        data_config,
        {
            "pricefm": {
                "regions": regions,
                "windows": {"lag_window": 96, "lead_window": 96},
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
                "base": {
                    "data_config": str(data_config),
                    "full_config": str(full_config),
                    "generated_root": str(tmp_path / "generated"),
                    "run_root": str(tmp_path / "runs"),
                },
                "scope": {
                    "regions": ["NO_4"],
                    "folds": [2],
                    "quantiles": [0.5],
                    "ranking_split": "val",
                    "ranking_unit": "original",
                    "ranking_metric": "AQL",
                },
                "fixed": {
                    "lead_window": 96,
                    "include_intercept": True,
                    "row_chunk_size": 512,
                    "projection_scale": 1.0,
                    "train_origin_limit": 3000,
                    "train_origin_selection": "tail",
                    "qdesn_likelihoods": ["al", "exal"],
                },
                "experiments": [],
                "experiment_blocks": [],
            }
        },
    )
    return template


def make_fixture(tmp_path: Path):
    r28 = tmp_path / "r28"
    out = tmp_path / "out"
    grid_config = tmp_path / "stage_r30.yaml"
    template = make_template(tmp_path)
    write_json(
        r28 / "summary.json",
        {
            "status": "completed_main_launch_path_ready",
            "recommended_stage_r30_experiments": 8,
        },
    )
    write_csv(
        r28 / "pricefm_stage_r28_case_target_queue.csv",
        [
            case_row("NO_4", 2, "near_gap_horizon_block_readout"),
            case_row("FI", 3, "far_gap_horizon_block_readout_diagnostic"),
        ],
    )
    write_csv(
        r28 / "pricefm_stage_r28_main_launch_recommendations.csv",
        [
            {
                "recommendation": "stage_r29_prepare_stage_r30_horizon_block_readout_main_launch",
                "allowed": True,
                "n_target_cases": 2,
                "recommended_arms_per_case": 4,
                "recommended_experiments": 8,
                "why": "ok",
                "scientific_gate_after_run": "beat both",
            }
        ],
    )
    write_csv(
        r28 / "pricefm_stage_r28_objective_model_capability_matrix.csv",
        [
            {
                "mechanism": "horizon_block_readout_interaction",
                "current_support": "implemented_design_matrix_axis",
                "runner_consumes_it": True,
                "evidence": "ok",
                "launch_implication": "ok",
            }
        ],
    )
    write_csv(r28 / "pricefm_stage_r28_design_gates.csv", [{"gate": "ok", "passed": True, "detail": "ok"}])
    return r28, out, template, grid_config


def args_for(mod, r28: Path, out: Path, template: Path, grid_config: Path):
    return mod.parser().parse_args(
        [
            "--stage-r28-dir",
            str(r28),
            "--template-grid-config",
            str(template),
            "--output-dir",
            str(out),
            "--grid-config",
            str(grid_config),
            "--grid-id",
            "pricefm_stage_r30_horizon_block_readout_main_test",
            "--generated-root",
            str(out / "generated"),
            "--run-root",
            str(out / "runs"),
            "--expected-cases",
            "2",
            "--arms-per-case",
            "4",
            "--write-grid",
            "true",
            "--force",
            "true",
        ]
    )


def test_stage_r29_materializes_horizon_block_launch_yaml_without_launching(tmp_path):
    r28, out, template, grid_config = make_fixture(tmp_path)
    mod = load_script()
    summary = mod.run(args_for(mod, r28, out, template, grid_config))

    assert summary["status"] == "completed"
    assert summary["n_launch_experiments"] == 8
    assert summary["writes_launch_yaml"] is True
    assert summary["prep_invoked_launcher"] is False
    assert grid_config.exists()
    payload = yaml.safe_load(grid_config.read_text())
    experiments = payload["pricefm_desn_experiment_grid"]["experiments"]
    assert len(experiments) == 8
    assert {exp["readout_interaction"] for exp in experiments} == {"horizon_block"}
    assert {exp["horizon_block_size"] for exp in experiments} == {24}
    assert {exp["readout_interaction_basis"] for exp in experiments} == {"state_lead"}
    manifest = pd.read_csv(out / "pricefm_stage_r29_stage_r30_launch_manifest.csv")
    assert manifest["readout_interaction"].eq("horizon_block").all()
    assert not manifest["mutates_registry"].map(bool).any()
    gates = pd.read_csv(out / "pricefm_stage_r29_launch_prep_gates.csv")
    assert gates["passed"].map(bool).all()
