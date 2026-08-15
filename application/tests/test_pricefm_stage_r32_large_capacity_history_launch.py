"""Tests for the PriceFM Stage-R32 large-capacity/history launch prep."""

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
    path = SCRIPT_DIR / "155_prepare_pricefm_stage_r32_large_capacity_history_launch.py"
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


def make_template(tmp_path: Path) -> Path:
    data_config = tmp_path / "pricefm_data.yaml"
    full_config = tmp_path / "pricefm_full.yaml"
    write_yaml(
        data_config,
        {
            "pricefm": {
                "regions": ["HU", "NO_4", "SE_1", "SE_2", "AT", "RO", "SK", "FI", "NO_3"],
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
        "stage_r25_arm": "long_lag_weighted",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "test_minus_pricefm": 1.0,
        "test_minus_current_qdesn": 0.5,
        "best_observed_stage_r25_r27_test_minus_pricefm": 0.8,
        "r28_queue": "large_capacity_history_rescue",
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
    out = tmp_path / "out"
    grid_config = tmp_path / "stage_r32.yaml"
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
    return r29, out, template, grid_config


def args_for(mod, r29: Path, out: Path, template: Path, grid_config: Path):
    return mod.parser().parse_args(
        [
            "--stage-r29-dir",
            str(r29),
            "--template-grid-config",
            str(template),
            "--output-dir",
            str(out),
            "--grid-config",
            str(grid_config),
            "--grid-id",
            "pricefm_stage_r32_large_capacity_history_unit",
            "--generated-root",
            str(out / "generated"),
            "--run-root",
            str(out / "runs"),
            "--expected-cases",
            "2",
            "--d-values",
            "3,4",
            "--n-values",
            "100",
            "--lag-windows",
            "300",
            "--write-grid",
            "true",
            "--force",
            "true",
        ]
    )


def test_stage_r32_materializes_large_capacity_grid_without_launching(tmp_path):
    mod = load_script()
    r29, out, template, grid_config = make_fixture(tmp_path)
    summary = mod.run(args_for(mod, r29, out, template, grid_config))

    assert summary["status"] == "completed"
    assert summary["n_launch_experiments"] == 8
    assert summary["prep_invoked_launcher"] is False
    assert summary["lag_windows"] == [300]
    assert summary["depths"] == [3, 4]
    assert summary["n_values"] == [100]
    assert grid_config.exists()

    payload = yaml.safe_load(grid_config.read_text())["pricefm_desn_experiment_grid"]
    experiments = payload["experiments"]
    assert len(experiments) == 8
    assert {exp["lag_window"] for exp in experiments} == {300}
    assert {exp["depth"] for exp in experiments} == {3, 4}
    assert {tuple(exp["units"]) for exp in experiments} == {(100, 100, 100), (100, 100, 100, 100)}
    assert {exp["state_output"] for exp in experiments} == {"final_layer", "concat_layers"}
    assert {exp["alpha"] for exp in experiments} == {0.25, 0.40}
    assert {exp["tau0"] for exp in experiments} == {0.0005, 0.001}
    assert payload["launch"]["stage_r32_full_background_launch_authorized_by_user"]["dry_run"] is False

    manifest = pd.read_csv(out / "pricefm_stage_r32_large_capacity_launch_manifest.csv")
    assert manifest["mutates_registry"].map(lambda x: str(x).lower() == "false").all()
    assert manifest["mutates_manuscript"].map(lambda x: str(x).lower() == "false").all()
    assert not manifest["launcher_invoked_by_prep"].map(bool).any()
    assert manifest["selection_rule"].eq("validation_AQL_only_within_case").all()
    gates = pd.read_csv(out / "pricefm_stage_r32_launch_prep_gates.csv")
    assert gates["passed"].map(bool).all()

    alpha_tau0 = pd.read_csv(out / "pricefm_stage_r32_alpha_tau0_reference.csv")
    assert {"alpha", "tau0"}.issubset(set(alpha_tau0["parameter"]))


def test_stage_r32_rejects_unrequested_width_axis(tmp_path):
    mod = load_script()
    r29, out, template, grid_config = make_fixture(tmp_path)
    args = args_for(mod, r29, out, template, grid_config)
    args.n_values = "120"
    try:
        mod.run(args)
    except ValueError as exc:
        assert "n values 100, 200, and 300" in str(exc)
    else:
        raise AssertionError("Stage-R32 should reject non-pre-registered n values")
