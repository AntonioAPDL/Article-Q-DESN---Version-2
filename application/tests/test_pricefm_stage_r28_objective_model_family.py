"""Tests for the PriceFM Stage-R28 objective/model-family audit."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script():
    path = SCRIPT_DIR / "153_audit_pricefm_stage_r28_objective_model_family.py"
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


def selected_row(region: str, fold: int, gap: float) -> dict:
    return {
        "experiment_id": f"r25_{region.lower()}_f{fold}",
        "region": region,
        "fold": fold,
        "stage_r22b_case_id": f"r22b_{region.lower()}_f{fold}",
        "horizon_focus": "73-96" if region == "NO_4" else "1-24",
        "feature_policy": "target_only",
        "stage_r25_arm": "alt_information_set_weighted",
        "method_id": "qdesn_al_rhs_ns_exact_chunked",
        "test_minus_pricefm": gap,
        "test_minus_current_qdesn": 0.1,
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
    }


def make_fixture(tmp_path: Path):
    r26 = tmp_path / "r26"
    r27 = tmp_path / "r27"
    r25 = tmp_path / "r25"
    src = tmp_path / "src"
    out = tmp_path / "out"
    src.mkdir(parents=True, exist_ok=True)
    write_json(
        r26 / "summary.json",
        {
            "status": "completed_negative_no_promotions",
            "n_rows_beating_pricefm": 0,
            "best_validation_selected_test_minus_pricefm": 0.4,
        },
    )
    write_json(
        r27 / "summary.json",
        {
            "status": "completed_read_only_calibration_parity_audit",
            "n_full_surface_calibrated_pricefm_wins": 0,
            "best_any_calibrated_test_minus_pricefm": 0.3,
        },
    )
    selected = [selected_row("NO_4", 2, 0.4), selected_row("FI", 3, 2.0)]
    metric = []
    for row in selected:
        for method in ["qdesn_al_rhs_ns_exact_chunked", "qdesn_exal_rhs_ns_exact_chunked"]:
            metric.append({
                **row,
                "method_id": method,
                "test_minus_pricefm": row["test_minus_pricefm"] + (0.05 if "exal" in method else 0.0),
                "test_minus_current_qdesn": row["test_minus_current_qdesn"],
            })
    write_csv(r26 / "pricefm_stage_r26_final_validation_selected_case.csv", selected)
    write_csv(r26 / "pricefm_stage_r26_final_metric_rows.csv", metric)
    case_rows = []
    for row in selected:
        for scope in ["full_surface_calibrated", "r26_selected_only_calibrated", "test_oracle_calibrated_audit_only"]:
            case_rows.append({
                "selection_scope": scope,
                "region": row["region"],
                "fold": row["fold"],
                "test_minus_pricefm": row["test_minus_pricefm"] - 0.1,
                "test_minus_current_qdesn": row["test_minus_current_qdesn"],
                "calibration_rule": "horizon_block_quantile_shift_on_validation",
            })
    write_csv(r27 / "pricefm_stage_r27_case_calibration_selection.csv", case_rows)
    write_csv(
        r27 / "pricefm_stage_r27_next_action_plan.csv",
        [
            {
                "priority": 3,
                "action": "if_no_calibrated_beat_both_pivot_to_objective_or_model_family",
                "condition": "no validation-selected calibrated candidate beats both baselines",
                "allowed_next": True,
                "rationale": "pivot",
            }
        ],
    )
    write_csv(
        r27 / "pricefm_stage_r27_information_set_parity_audit.csv",
        [
            {
                "experiment_id": "a",
                "region": "NO_4",
                "fold": 2,
                "best_calibrated_test_minus_pricefm": 0.3,
                "information_set_diagnosis": "graph_information_present_but_pricefm_gap_remains",
            }
        ],
    )
    write_csv(r25 / "pricefm_stage_r25_launch_manifest.csv", [{"experiment_id": "a"}])
    (src / "pricefm_desn_adapter.py").write_text("readout_interaction horizon_block horizon_block_size append_readout_interactions feature_policy\n")
    (src / "pricefm_full_run.py").write_text("readout_interaction horizon_block horizon_block_size feature_policy horizon_weighting\n")
    (src / "12_prepare_desn_experiment_grid.py").write_text("readout_interaction horizon_block horizon_block_size\n")
    (src / "08_run_desn_model_smoke.R").write_text("fit_qdesn_like('al')\nfit_qdesn_like('exal')\nhorizon_weighting\nrep(seq_len(nrow(X_train)))\n")
    (src / "13_run_desn_experiment_grid.py").write_text("dry-run false\n")
    return r26, r27, r25, src, out


def args_for(mod, r26: Path, r27: Path, r25: Path, src: Path, out: Path):
    return mod.parser().parse_args(
        [
            "--stage-r26-dir",
            str(r26),
            "--stage-r27-dir",
            str(r27),
            "--stage-r25-prep-dir",
            str(r25),
            "--output-dir",
            str(out),
            "--source-adapter-builder",
            str(src / "pricefm_desn_adapter.py"),
            "--source-full-run-orchestrator",
            str(src / "pricefm_full_run.py"),
            "--source-grid-materializer",
            str(src / "12_prepare_desn_experiment_grid.py"),
            "--source-model-runner",
            str(src / "08_run_desn_model_smoke.R"),
            "--source-grid-launcher",
            str(src / "13_run_desn_experiment_grid.py"),
            "--expected-cases",
            "2",
            "--force",
            "true",
        ]
    )


def test_stage_r28_recommends_supported_horizon_block_main_launch(tmp_path):
    r26, r27, r25, src, out = make_fixture(tmp_path)
    mod = load_script()
    summary = mod.run(args_for(mod, r26, r27, r25, src, out))

    assert summary["status"] == "completed_main_launch_path_ready"
    assert summary["recommended_stage_r30_experiments"] == 8
    capability = pd.read_csv(out / "pricefm_stage_r28_objective_model_capability_matrix.csv")
    hb = capability.set_index("mechanism").loc["horizon_block_readout_interaction"]
    assert hb["current_support"] == "implemented_design_matrix_axis"
    rec = pd.read_csv(out / "pricefm_stage_r28_main_launch_recommendations.csv")
    assert rec.set_index("recommendation").loc[
        "stage_r29_prepare_stage_r30_horizon_block_readout_main_launch",
        "allowed",
    ]
    gates = pd.read_csv(out / "pricefm_stage_r28_design_gates.csv")
    assert gates["passed"].map(bool).all()
    assert not list(out.glob("*.yaml"))
