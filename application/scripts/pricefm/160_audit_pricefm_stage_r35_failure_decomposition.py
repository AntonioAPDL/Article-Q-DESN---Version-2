#!/usr/bin/env python3
"""Diagnose the completed PriceFM Stage-R34 surface before any new launch."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_R34_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r34_lean_capacity_history_closeout_20260728"
)
DEFAULT_R21_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r21_failure_atlas_20260709"
)
DEFAULT_R23_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r23_mechanism_capability_audit_20260709"
)
DEFAULT_R27_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r27_calibration_parity_audit_20260711"
)
DEFAULT_R28_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r28_objective_model_family_audit_20260711"
)
DEFAULT_FULL_SURFACE_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_full_surface_decision_closeout_20260704"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r35_failure_decomposition_20260804"
)

R34_METRICS = "pricefm_stage_r34_metric_rows.csv"
R34_SELECTED = "pricefm_stage_r34_validation_selected_cases.csv"
R34_ORACLE = "pricefm_stage_r34_test_oracle_diagnostics.csv"
R34_PROMOTION = "pricefm_stage_r34_full_quantile_promotion_queue.csv"
R34_MCMC = "pricefm_stage_r34_mcmc_confirmation_queue.csv"
R34_GATES = "pricefm_stage_r34_decision_gates.csv"
R21_ATLAS = "pricefm_stage_r21_failure_atlas.csv"
R23_CAPABILITY = "pricefm_stage_r23_runner_capability_matrix.csv"
R27_DIAGNOSIS = "pricefm_stage_r27_mechanism_diagnosis.csv"
R28_CAPABILITY = "pricefm_stage_r28_objective_model_capability_matrix.csv"
FULL_HORIZON = "pricefm_full_surface_horizon_diagnostics.csv"

OUT_CASES = "pricefm_stage_r35_case_failure_decomposition.csv"
OUT_HORIZONS = "pricefm_stage_r35_selected_horizon_diagnostics.csv"
OUT_CALIBRATION = "pricefm_stage_r35_prediction_calibration_diagnostics.csv"
OUT_TRANSFER = "pricefm_stage_r35_validation_transfer_audit.csv"
OUT_RESPONSE = "pricefm_stage_r35_capacity_response_surface.csv"
OUT_CAPABILITY = "pricefm_stage_r35_runner_capability_decision.csv"
OUT_SATURATION = "pricefm_stage_r35_mechanism_saturation_ledger.csv"
OUT_QUEUE = "pricefm_stage_r35_case_specific_next_queue.csv"
OUT_SPLITS = "pricefm_stage_r35_split_boundary_audit.csv"
OUT_HISTORY = "pricefm_stage_r35_test_adaptation_ledger.csv"
OUT_PROTOCOL = "pricefm_stage_r35_confirmation_protocol.csv"
OUT_GATES = "pricefm_stage_r35_decision_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r35_failure_decomposition_report.md"

SOURCE_DEFAULTS = {
    "model_runner": "application/scripts/pricefm/08_run_desn_model_smoke.R",
    "adapter_builder": "application/scripts/pricefm/pricefm_desn_adapter.py",
    "grid_materializer": "application/scripts/pricefm/12_prepare_desn_experiment_grid.py",
    "grid_launcher": "application/scripts/pricefm/13_run_desn_experiment_grid.py",
}

HISTORY_DEFAULTS = [
    (
        "stage_r10",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r10_mechanism_pivot_closeout_20260707/summary.json",
    ),
    (
        "stage_r14",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r14_structural_readout_rescue_closeout_20260708/summary.json",
    ),
    (
        "stage_r16",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r16_history_anchor_rescue_closeout_20260708/summary.json",
    ),
    (
        "stage_r19",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r19_same_quantile_nearmiss_closeout_20260708/summary.json",
    ),
    (
        "stage_r22d",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r22d_case_specific_screening_closeout_20260709/summary.json",
    ),
    (
        "stage_r26",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r26_r25_broad_horizon_final_closeout_20260711/summary.json",
    ),
    (
        "stage_r27",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r27_calibration_parity_audit_20260711/summary.json",
    ),
    (
        "stage_r32",
        "application/data_local/pricefm/authoritative/"
        "pricefm_stage_r32_partial_stop_closeout_20260721/summary.json",
    ),
    ("stage_r34", f"{DEFAULT_R34_DIR}/summary.json"),
]

HORIZON_ORDER = {"1-24": 1, "25-48": 2, "49-72": 3, "73-96": 4, "all": 5}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r34-dir", default=DEFAULT_R34_DIR)
    p.add_argument("--stage-r21-dir", default=DEFAULT_R21_DIR)
    p.add_argument("--stage-r23-dir", default=DEFAULT_R23_DIR)
    p.add_argument("--stage-r27-dir", default=DEFAULT_R27_DIR)
    p.add_argument("--stage-r28-dir", default=DEFAULT_R28_DIR)
    p.add_argument("--full-surface-dir", default=DEFAULT_FULL_SURFACE_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    for label, default in SOURCE_DEFAULTS.items():
        p.add_argument(f"--source-{label.replace('_', '-')}", default=default)
    p.add_argument(
        "--history-summary",
        action="append",
        default=None,
        help="Repeat as stage_label=/path/to/summary.json. Defaults to R10-R34 closeouts.",
    )
    p.add_argument("--expected-experiments", type=int, default=480)
    p.add_argument("--expected-method-rows", type=int, default=960)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--near-gap-threshold", type=float, default=0.75)
    p.add_argument("--far-gap-threshold", type=float, default=1.25)
    p.add_argument("--selection-penalty-threshold", type=float, default=0.25)
    p.add_argument("--unstable-spearman-threshold", type=float, default=0.0)
    p.add_argument("--flat-axis-threshold", type=float, default=0.05)
    p.add_argument("--calibration-coverage-threshold", type=float, default=0.05)
    p.add_argument("--calibration-bias-ratio-threshold", type=float, default=0.20)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed", "completed"}


def finite_float(value: Any, default: float = float("nan")) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float(default)
    return out if math.isfinite(out) else float(default)


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with full.open("r") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{label} must contain a JSON object: {full}")
    return payload


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [column for column in columns if column not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_paths(args: argparse.Namespace) -> dict[str, Path]:
    return {label: repo_path(getattr(args, f"source_{label}")) for label in SOURCE_DEFAULTS}


def read_inputs(args: argparse.Namespace) -> dict[str, Any]:
    r34 = Path(args.stage_r34_dir)
    r21 = Path(args.stage_r21_dir)
    r23 = Path(args.stage_r23_dir)
    r27 = Path(args.stage_r27_dir)
    r28 = Path(args.stage_r28_dir)
    full = Path(args.full_surface_dir)
    return {
        "r34_summary": read_json_required(r34 / "summary.json", "Stage-R34 summary"),
        "metrics": read_csv_required(r34 / R34_METRICS, "Stage-R34 metric rows"),
        "selected": read_csv_required(r34 / R34_SELECTED, "Stage-R34 validation selection"),
        "oracle": read_csv_required(r34 / R34_ORACLE, "Stage-R34 test oracle"),
        "promotions": read_csv_required(r34 / R34_PROMOTION, "Stage-R34 promotion queue"),
        "mcmc": read_csv_required(r34 / R34_MCMC, "Stage-R34 MCMC queue"),
        "r34_gates": read_csv_required(r34 / R34_GATES, "Stage-R34 gates"),
        "r21_atlas": read_csv_required(r21 / R21_ATLAS, "Stage-R21 failure atlas"),
        "r23_capability": read_csv_required(r23 / R23_CAPABILITY, "Stage-R23 capability"),
        "r27_summary": read_json_required(r27 / "summary.json", "Stage-R27 summary"),
        "r27_diagnosis": read_csv_required(r27 / R27_DIAGNOSIS, "Stage-R27 diagnosis"),
        "r28_summary": read_json_required(r28 / "summary.json", "Stage-R28 summary"),
        "r28_capability": read_csv_required(r28 / R28_CAPABILITY, "Stage-R28 capability"),
        "full_horizon": read_csv_required(full / FULL_HORIZON, "full-surface horizon diagnostics"),
    }


def validate_inputs(inputs: dict[str, Any], args: argparse.Namespace) -> None:
    metrics = inputs["metrics"]
    selected = inputs["selected"]
    oracle = inputs["oracle"]
    require_columns(
        metrics,
        [
            "experiment_id",
            "region",
            "fold",
            "method_id",
            "val_AQL",
            "test_AQL",
            "test_minus_current_qdesn",
            "test_minus_pricefm",
            "beats_current_qdesn_on_test",
            "beats_pricefm_on_test",
            "lag_window",
            "depth",
            "n_per_layer",
            "tau0",
            "alpha",
            "rho",
            "input_scale",
            "state_output",
            "readout_interaction",
        ],
        "Stage-R34 metric rows",
    )
    require_columns(
        selected,
        [
            "experiment_id",
            "region",
            "fold",
            "method_id",
            "target_quantile",
            "horizon_focus",
            "val_AQL",
            "test_AQL",
            "current_qdesn_AQL",
            "current_pricefm_AQL",
            "test_minus_current_qdesn",
            "test_minus_pricefm",
            "metric_summary_path",
            "selection_is_validation_only",
            "selected_by",
        ],
        "Stage-R34 validation selection",
    )
    require_columns(
        oracle,
        ["region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL", "test_minus_pricefm"],
        "Stage-R34 test oracle",
    )
    require_columns(inputs["r34_gates"], ["gate", "passed"], "Stage-R34 gates")
    require_columns(
        inputs["full_horizon"],
        ["region", "fold", "horizon_group", "horizon_delta_AQL_qdesn_minus_pricefm"],
        "full-surface horizon diagnostics",
    )
    summary = inputs["r34_summary"]
    failures = []
    if not bool(summary.get("run_complete", False)) or summary.get("status") != "completed_cleanly":
        failures.append("r34_not_complete")
    if len(metrics) != int(args.expected_method_rows):
        failures.append("unexpected_metric_row_count")
    if metrics["experiment_id"].nunique() != int(args.expected_experiments):
        failures.append("unexpected_experiment_count")
    if len(selected) != int(args.expected_cases) or len(oracle) != int(args.expected_cases):
        failures.append("unexpected_case_count")
    if selected[["region", "fold"]].duplicated().any() or oracle[["region", "fold"]].duplicated().any():
        failures.append("duplicate_case_selection")
    if not selected["selection_is_validation_only"].map(boolish).all():
        failures.append("selection_not_validation_only")
    if not selected["selected_by"].astype(str).eq("validation_AQL_only").all():
        failures.append("selection_rule_changed")
    if len(inputs["promotions"]) or len(inputs["mcmc"]):
        failures.append("r34_queue_not_empty")
    gate_map = inputs["r34_gates"].set_index("gate")["passed"].map(boolish).to_dict()
    if not gate_map.get("r33_complete", False) or not gate_map.get("validation_selection_frozen", False):
        failures.append("r34_completion_gate_failed")
    if gate_map.get("dual_reference_winner_exists", True):
        failures.append("unexpected_dual_reference_winner")
    if metrics["beats_pricefm_on_test"].map(boolish).any():
        failures.append("unexpected_pricefm_win_in_surface")
    if failures:
        raise ValueError(f"Stage-R35 input contract failed: {failures}")


def validation_transfer(metrics: pd.DataFrame, selected: pd.DataFrame, oracle: pd.DataFrame, args: argparse.Namespace) -> pd.DataFrame:
    rows = []
    selected_by_case = selected.set_index(["region", "fold"])
    oracle_by_case = oracle.set_index(["region", "fold"])
    for (region, fold), group in metrics.groupby(["region", "fold"], sort=True):
        sel = selected_by_case.loc[(region, fold)]
        ora = oracle_by_case.loc[(region, fold)]
        val_rank = group["val_AQL"].rank(method="min", ascending=True)
        test_rank = group["test_AQL"].rank(method="min", ascending=True)
        selected_mask = (
            group["experiment_id"].astype(str).eq(str(sel["experiment_id"]))
            & group["method_id"].astype(str).eq(str(sel["method_id"]))
        )
        oracle_mask = (
            group["experiment_id"].astype(str).eq(str(ora["experiment_id"]))
            & group["method_id"].astype(str).eq(str(ora["method_id"]))
        )
        penalty = float(sel["test_AQL"] - ora["test_AQL"])
        spearman = group["val_AQL"].corr(group["test_AQL"], method="spearman")
        pearson = group["val_AQL"].corr(group["test_AQL"], method="pearson")
        unstable = (
            (math.isfinite(finite_float(spearman)) and float(spearman) <= float(args.unstable_spearman_threshold))
            or penalty >= float(args.selection_penalty_threshold)
        )
        rows.append(
            {
                "region": region,
                "fold": int(fold),
                "candidate_rows": int(len(group)),
                "validation_test_spearman": spearman,
                "validation_test_pearson": pearson,
                "selected_test_rank": int(test_rank.loc[selected_mask].iloc[0]),
                "oracle_validation_rank": int(val_rank.loc[oracle_mask].iloc[0]),
                "selected_test_AQL": float(sel["test_AQL"]),
                "oracle_test_AQL": float(ora["test_AQL"]),
                "selection_penalty_AQL": penalty,
                "selected_test_minus_pricefm": float(sel["test_minus_pricefm"]),
                "oracle_test_minus_pricefm": float(ora["test_minus_pricefm"]),
                "oracle_can_beat_pricefm": float(ora["test_minus_pricefm"]) < 0.0,
                "selection_instability_flag": bool(unstable),
                "selection_fix_sufficient_for_pricefm_win": float(ora["test_minus_pricefm"]) < 0.0,
                "test_oracle_role": "diagnostic_only_not_selection",
            }
        )
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def capacity_response(metrics: pd.DataFrame, args: argparse.Namespace) -> pd.DataFrame:
    varied_axes = ["lag_window", "depth", "n_per_layer", "tau0", "method_id"]
    fixed_axes = ["alpha", "rho", "input_scale", "state_output", "readout_interaction"]
    rows = []
    for (region, fold), case in metrics.groupby(["region", "fold"], sort=True):
        for axis in varied_axes + fixed_axes:
            levels = case[axis].drop_duplicates().tolist()
            grouped = (
                case.groupby(axis, dropna=False)
                .agg(rows=("test_AQL", "size"), median_val_AQL=("val_AQL", "median"), median_test_AQL=("test_AQL", "median"))
                .reset_index()
            )
            test_span = float(grouped["median_test_AQL"].max() - grouped["median_test_AQL"].min()) if len(grouped) > 1 else 0.0
            val_span = float(grouped["median_val_AQL"].max() - grouped["median_val_AQL"].min()) if len(grouped) > 1 else 0.0
            best_test = grouped.sort_values(["median_test_AQL", axis], kind="mergesort").iloc[0]
            best_val = grouped.sort_values(["median_val_AQL", axis], kind="mergesort").iloc[0]
            if len(levels) == 1:
                status = "not_identifiable_fixed_in_r33"
            elif test_span < float(args.flat_axis_threshold):
                status = "flat_test_response"
            elif str(best_test[axis]) != str(best_val[axis]):
                status = "response_present_but_validation_transfer_disagrees"
            else:
                status = "response_present_but_no_pricefm_win"
            rows.append(
                {
                    "region": region,
                    "fold": int(fold),
                    "axis": axis,
                    "n_levels": int(len(levels)),
                    "levels": json.dumps([str(value) for value in levels]),
                    "best_validation_level": str(best_val[axis]),
                    "best_test_level_diagnostic_only": str(best_test[axis]),
                    "median_validation_effect_span_AQL": val_span,
                    "median_test_effect_span_AQL": test_span,
                    "best_levels_agree": str(best_test[axis]) == str(best_val[axis]),
                    "axis_diagnosis": status,
                    "supports_broader_same_family_search": False,
                }
            )
    return pd.DataFrame(rows).sort_values(["region", "fold", "axis"]).reset_index(drop=True)


def model_dir_from_row(row: pd.Series) -> Path:
    return Path(str(row["metric_summary_path"])).parent


def horizon_group(horizon: pd.Series) -> pd.Series:
    values = pd.to_numeric(horizon, errors="raise").astype(int)
    return pd.cut(
        values,
        bins=[0, 24, 48, 72, 96],
        labels=["1-24", "25-48", "49-72", "73-96"],
        include_lowest=True,
    ).astype(str)


def selected_horizon_diagnostics(selected: pd.DataFrame, full_horizon: pd.DataFrame) -> tuple[pd.DataFrame, list[Path]]:
    rows = []
    sources: list[Path] = []
    baseline = full_horizon.copy()
    baseline["fold"] = baseline["fold"].astype(int)
    for _, selected_row in selected.iterrows():
        model_dir = model_dir_from_row(selected_row)
        path = model_dir / "metric_by_horizon_group.csv"
        frame = read_csv_required(path, f"selected horizon metrics {selected_row['region']}/{selected_row['fold']}")
        sources.append(path)
        require_columns(frame, ["method_id", "split", "unit", "horizon_group", "AQL"], str(path))
        frame = frame[
            frame["method_id"].astype(str).eq(str(selected_row["method_id"]))
            & frame["unit"].astype(str).eq("original")
            & frame["split"].astype(str).isin(["val", "test"])
        ].copy()
        pivot = frame.pivot_table(index="horizon_group", columns="split", values="AQL", aggfunc="first").reset_index()
        if not {"val", "test"}.issubset(pivot.columns) or len(pivot) != 4:
            raise ValueError(f"Selected horizon artifact is incomplete: {path}")
        for _, value in pivot.iterrows():
            group = str(value["horizon_group"])
            ref = baseline[
                baseline["region"].astype(str).eq(str(selected_row["region"]))
                & baseline["fold"].astype(int).eq(int(selected_row["fold"]))
                & baseline["horizon_group"].astype(str).eq(group)
            ]
            rows.append(
                {
                    "region": selected_row["region"],
                    "fold": int(selected_row["fold"]),
                    "experiment_id": selected_row["experiment_id"],
                    "method_id": selected_row["method_id"],
                    "horizon_group": group,
                    "is_pre_registered_focus": group == str(selected_row["horizon_focus"]),
                    "selected_val_AQL": float(value["val"]),
                    "selected_test_AQL": float(value["test"]),
                    "selected_val_test_gap_AQL": float(value["test"] - value["val"]),
                    "current_qdesn_minus_pricefm_AQL": (
                        float(ref.iloc[0]["horizon_delta_AQL_qdesn_minus_pricefm"]) if len(ref) == 1 else float("nan")
                    ),
                    "current_qdesn_loses_to_pricefm_in_block": (
                        bool(float(ref.iloc[0]["horizon_delta_AQL_qdesn_minus_pricefm"]) > 0.0) if len(ref) == 1 else False
                    ),
                    "candidate_pricefm_block_delta_available": False,
                    "candidate_block_role": "mechanism_diagnostic_not_promotion",
                    "metric_source": str(path),
                }
            )
    out = pd.DataFrame(rows)
    out["horizon_order"] = out["horizon_group"].map(HORIZON_ORDER)
    return out.sort_values(["region", "fold", "horizon_order"]).drop(columns="horizon_order").reset_index(drop=True), sources


def lag1_residual_correlation(frame: pd.DataFrame) -> float:
    values = []
    for _, group in frame.groupby("horizon"):
        ordered = group.sort_values("origin_id")
        residual = ordered["residual_scaled"].to_numpy(dtype=float)
        if len(residual) >= 3:
            current = residual[1:]
            lagged = residual[:-1]
            if np.std(current) > 1.0e-12 and np.std(lagged) > 1.0e-12:
                corr = float(np.corrcoef(current, lagged)[0, 1])
                if math.isfinite(corr):
                    values.append(corr)
    return float(np.mean(values)) if values else float("nan")


def prediction_and_split_diagnostics(selected: pd.DataFrame, args: argparse.Namespace) -> tuple[pd.DataFrame, pd.DataFrame, list[Path]]:
    diagnostic_rows = []
    split_rows = []
    sources: list[Path] = []
    for _, selected_row in selected.iterrows():
        model_dir = model_dir_from_row(selected_row)
        adapter_dir = model_dir.parent / "adapter"
        prediction_path = model_dir / "model_predictions_scaled.csv"
        predictions = read_csv_required(prediction_path, f"selected predictions {selected_row['region']}/{selected_row['fold']}")
        require_columns(predictions, ["method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"], str(prediction_path))
        predictions = predictions[
            predictions["method_id"].astype(str).eq(str(selected_row["method_id"]))
            & np.isclose(pd.to_numeric(predictions["tau"], errors="coerce"), float(selected_row["target_quantile"]))
            & predictions["split"].astype(str).isin(["val", "test"])
        ].copy()
        sources.append(prediction_path)
        for split in ["train", "val", "test"]:
            rows_path = adapter_dir / f"rows_{split}.csv"
            truth = read_csv_required(rows_path, f"selected {split} rows {selected_row['region']}/{selected_row['fold']}")
            require_columns(truth, ["split", "origin_id", "horizon", "origin_market_time", "response_market_time", "y_scaled"], str(rows_path))
            sources.append(rows_path)
            split_rows.append(
                {
                    "region": selected_row["region"],
                    "fold": int(selected_row["fold"]),
                    "experiment_id": selected_row["experiment_id"],
                    "split": split,
                    "rows": int(len(truth)),
                    "first_origin_market_time": str(truth["origin_market_time"].min()),
                    "last_origin_market_time": str(truth["origin_market_time"].max()),
                    "last_response_market_time": str(truth["response_market_time"].max()),
                    "artifact_path": str(rows_path),
                }
            )
            if split == "train":
                continue
            pred = predictions[predictions["split"].astype(str).eq(split)].copy()
            merged = truth.merge(
                pred[["origin_id", "horizon", "pred_scaled"]],
                on=["origin_id", "horizon"],
                how="inner",
                validate="one_to_one",
            )
            if len(merged) != len(truth):
                raise ValueError(
                    f"Prediction/truth alignment incomplete for {selected_row['region']} fold {selected_row['fold']} {split}"
                )
            merged["horizon_group"] = horizon_group(merged["horizon"])
            merged["residual_scaled"] = merged["pred_scaled"] - merged["y_scaled"]
            groups = [("all", merged)] + list(merged.groupby("horizon_group", sort=False))
            for group_name, group in groups:
                tau = float(selected_row["target_quantile"])
                u = group["y_scaled"].to_numpy() - group["pred_scaled"].to_numpy()
                pinball = np.where(u >= 0.0, tau * u, (tau - 1.0) * u)
                mae = float(np.mean(np.abs(group["residual_scaled"])))
                mean_bias = float(group["residual_scaled"].mean())
                coverage = float((group["y_scaled"] <= group["pred_scaled"]).mean())
                bias_ratio = abs(mean_bias) / mae if mae > 0 else 0.0
                coverage_error = abs(coverage - tau)
                pred_sd = float(group["pred_scaled"].std(ddof=0))
                truth_sd = float(group["y_scaled"].std(ddof=0))
                severity = (
                    "material_location_or_coverage_miscalibration"
                    if coverage_error > float(args.calibration_coverage_threshold)
                    or bias_ratio > float(args.calibration_bias_ratio_threshold)
                    else "limited_median_miscalibration"
                )
                diagnostic_rows.append(
                    {
                        "region": selected_row["region"],
                        "fold": int(selected_row["fold"]),
                        "experiment_id": selected_row["experiment_id"],
                        "method_id": selected_row["method_id"],
                        "split": split,
                        "horizon_group": str(group_name),
                        "rows": int(len(group)),
                        "target_quantile": tau,
                        "pinball_loss_scaled": float(np.mean(pinball)),
                        "mae_scaled": mae,
                        "rmse_scaled": float(np.sqrt(np.mean(np.square(group["residual_scaled"])))),
                        "mean_signed_error_scaled": mean_bias,
                        "median_signed_error_scaled": float(group["residual_scaled"].median()),
                        "absolute_bias_to_mae_ratio": bias_ratio,
                        "empirical_quantile_coverage": coverage,
                        "absolute_coverage_error": coverage_error,
                        "prediction_to_truth_sd_ratio": pred_sd / truth_sd if truth_sd > 0 else float("nan"),
                        "mean_horizon_specific_residual_lag1": lag1_residual_correlation(group),
                        "calibration_diagnosis": severity,
                        "postfit_role": "diagnostic_only_existing_predictions",
                    }
                )
    diagnostics = pd.DataFrame(diagnostic_rows)
    diagnostics["horizon_order"] = diagnostics["horizon_group"].map(HORIZON_ORDER)
    diagnostics = diagnostics.sort_values(["region", "fold", "split", "horizon_order"]).drop(columns="horizon_order").reset_index(drop=True)
    splits = pd.DataFrame(split_rows).sort_values(["region", "fold", "split"]).reset_index(drop=True)
    return diagnostics, splits, sources


def runner_capability(paths: dict[str, Path]) -> pd.DataFrame:
    texts = {label: path.read_text(errors="replace") if path.exists() else "" for label, path in paths.items()}
    runner = texts["model_runner"]
    adapter = texts["adapter_builder"]
    grid = texts["grid_materializer"]
    al_only = "setdiff(qdesn_likelihoods, c(\"al\", \"exal\"))" in runner
    weighting = "train_index_qdesn <- rep" in runner and "horizon_weighting" in runner
    block = "append_readout_interactions" in adapter and "readout_interaction" in grid
    rows = [
        (
            "current_al_exal_static_readout",
            al_only,
            True,
            "Runner explicitly restricts qdesn_vb likelihoods to AL/exAL.",
            "scientifically_exhausted_by_r34",
            "Do not launch another broader AL/exAL capacity grid.",
        ),
        (
            "integer_frequency_horizon_weighting",
            weighting,
            True,
            "Runner replicates training indices using configured horizon frequencies.",
            "implemented_but_insufficient",
            "May remain as a control, not the sole new mechanism.",
        ),
        (
            "horizon_block_design_interactions",
            block,
            True,
            "Adapter appends horizon-block interaction columns consumed by the fit.",
            "implemented_but_insufficient",
            "Do not relabel another block-interaction grid as a new family.",
        ),
        (
            "validation_only_postfit_calibration",
            False,
            True,
            "R27 calibration is a separate read-only prediction transformation, not a fit-time runner branch.",
            "audited_and_insufficient",
            "Retain only as a post-prediction diagnostic.",
        ),
        (
            "fully_separate_horizon_specific_readout",
            False,
            False,
            "Current block interactions share one fitted AL/exAL model; no separate per-block fit contract exists.",
            "requires_implementation_and_tests",
            "Implement explicit block-specific coefficients/regularization before launch.",
        ),
        (
            "new_likelihood_or_direct_quantile_loss",
            False,
            False,
            "No runner branch exposes a likelihood/loss beyond AL/exAL.",
            "requires_implementation_and_tests",
            "Add a real model-code path; YAML labels alone are forbidden.",
        ),
        (
            "nested_temporal_validation_selector",
            False,
            False,
            "The grid ranks one validation aggregate and has no nested rolling-origin selector.",
            "requires_orchestration_implementation",
            "Implement selection stability without consulting the existing test split.",
        ),
        (
            "mcmc_confirmation",
            False,
            False,
            "PriceFM screening runner is VB; MCMC remains downstream confirmation.",
            "blocked_without_promotable_vb_winner",
            "Do not use MCMC as a rescue optimizer.",
        ),
    ]
    return pd.DataFrame(
        [
            {
                "mechanism": mechanism,
                "currently_consumed": consumed,
                "evidence_observed": evidence_observed,
                "code_evidence": evidence,
                "stage_r35_status": status,
                "required_next_action": action,
                "expensive_launch_ready": False,
            }
            for mechanism, consumed, evidence_observed, evidence, status, action in rows
        ]
    )


def mechanism_saturation(inputs: dict[str, Any], capability: pd.DataFrame) -> pd.DataFrame:
    summary = inputs["r34_summary"]
    r27 = inputs["r27_summary"]
    rows = [
        (
            "reservoir_capacity_depth_width_history",
            "R33/R34",
            f"{summary.get('metric_summaries')} experiments; 0 validation-selected or oracle PriceFM wins",
            "saturated_current_family",
            False,
        ),
        (
            "al_exal_likelihood_choice",
            "R33/R34",
            "960 AL/exAL rows; 0 PriceFM wins",
            "saturated_current_implementation",
            False,
        ),
        (
            "horizon_weighted_training",
            "R25/R33",
            "Consumed integer-frequency weighting remained present without a PriceFM win",
            "insufficient_as_primary_mechanism",
            False,
        ),
        (
            "horizon_block_readout_interactions",
            "R30/R33",
            "Consumed horizon-block design interactions remained present without a PriceFM win",
            "insufficient_as_primary_mechanism",
            False,
        ),
        (
            "postfit_calibration",
            "R27",
            f"{r27.get('n_full_surface_calibrated_pricefm_wins', 0)} calibrated PriceFM wins",
            "insufficient_on_existing_predictions",
            False,
        ),
        (
            "graph_information_set",
            "R25/R27/R33",
            "Graph and target-only policies were represented; all current R33 cases still lose to PriceFM",
            "not_sufficient_alone_exact_parity_still_auditable",
            False,
        ),
        (
            "validation_selection",
            "R34",
            "Weak case-level validation/test transfer, but even test-oracle rows never beat PriceFM",
            "secondary_problem_not_sufficient_explanation",
            False,
        ),
        (
            "new_consumed_objective_or_model_family",
            "R35",
            "Current runner has no consumed non-AL/exAL family",
            "only_justified_next_model_work",
            True,
        ),
    ]
    out = pd.DataFrame(
        rows,
        columns=["mechanism", "evidence_stage", "evidence", "diagnosis", "eligible_for_implementation_design"],
    )
    out["same_family_relaunch_allowed"] = False
    out["launch_authorized_now"] = False
    return out


def case_decomposition(
    metrics: pd.DataFrame,
    selected: pd.DataFrame,
    oracle: pd.DataFrame,
    transfer: pd.DataFrame,
    calibration: pd.DataFrame,
    response: pd.DataFrame,
    r21: pd.DataFrame,
    args: argparse.Namespace,
) -> pd.DataFrame:
    selected_view = selected.copy()
    selected_view = selected_view.rename(
        columns={
            "experiment_id": "selected_experiment_id",
            "method_id": "selected_method_id",
            "val_AQL": "selected_val_AQL",
            "test_AQL": "selected_test_AQL",
            "test_minus_current_qdesn": "selected_test_minus_current_qdesn",
            "test_minus_pricefm": "selected_test_minus_pricefm",
        }
    )
    oracle_view = oracle[
        ["region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL", "test_minus_current_qdesn", "test_minus_pricefm"]
    ].rename(
        columns={
            "experiment_id": "oracle_experiment_id",
            "method_id": "oracle_method_id",
            "val_AQL": "oracle_val_AQL",
            "test_AQL": "oracle_test_AQL",
            "test_minus_current_qdesn": "oracle_test_minus_current_qdesn",
            "test_minus_pricefm": "oracle_test_minus_pricefm",
        }
    )
    all_case = (
        metrics.groupby(["region", "fold"])
        .agg(
            r33_rows=("test_AQL", "size"),
            r33_rows_beating_current_qdesn=("beats_current_qdesn_on_test", lambda s: int(s.map(boolish).sum())),
            r33_rows_beating_pricefm=("beats_pricefm_on_test", lambda s: int(s.map(boolish).sum())),
            best_any_test_minus_current_qdesn=("test_minus_current_qdesn", "min"),
            best_any_test_minus_pricefm=("test_minus_pricefm", "min"),
        )
        .reset_index()
    )
    cal = calibration[
        calibration["split"].astype(str).eq("test") & calibration["horizon_group"].astype(str).eq("all")
    ][
        [
            "region",
            "fold",
            "absolute_bias_to_mae_ratio",
            "absolute_coverage_error",
            "prediction_to_truth_sd_ratio",
            "mean_horizon_specific_residual_lag1",
            "calibration_diagnosis",
        ]
    ].copy()
    response_summary = (
        response[response["n_levels"] > 1]
        .groupby(["region", "fold"])
        .agg(
            max_axis_test_effect_span_AQL=("median_test_effect_span_AQL", "max"),
            flat_varied_axes=("axis_diagnosis", lambda s: int(s.eq("flat_test_response").sum())),
            unstable_varied_axes=("axis_diagnosis", lambda s: int(s.eq("response_present_but_validation_transfer_disagrees").sum())),
        )
        .reset_index()
    )
    columns = [
        "region",
        "fold",
        "stage_r21_primary_failure_pattern",
        "stage_r21_recommended_mechanism",
        "stage_r15_information_set_parity_flag",
        "worst_horizon_group_r21",
    ]
    available = [column for column in columns if column in r21.columns]
    out = (
        selected_view.merge(oracle_view, on=["region", "fold"], how="left", validate="one_to_one")
        .merge(transfer, on=["region", "fold"], how="left", validate="one_to_one", suffixes=("", "_transfer"))
        .merge(all_case, on=["region", "fold"], how="left", validate="one_to_one")
        .merge(cal, on=["region", "fold"], how="left", validate="one_to_one")
        .merge(response_summary, on=["region", "fold"], how="left", validate="one_to_one")
        .merge(r21[available], on=["region", "fold"], how="left", validate="one_to_one")
    )
    def failure_mode(row: pd.Series) -> str:
        gap = float(row["oracle_test_minus_pricefm"])
        unstable = boolish(row["selection_instability_flag"])
        if gap >= float(args.far_gap_threshold):
            return "structural_objective_or_information_gap_far"
        if unstable:
            return "model_family_ceiling_plus_validation_transfer_instability"
        if gap <= float(args.near_gap_threshold):
            return "near_gap_but_current_model_family_ceiling"
        return "model_family_ceiling_mid_gap"
    out["primary_stage_r35_failure_mode"] = out.apply(failure_mode, axis=1)
    out["selection_is_primary_failure"] = out["selection_fix_sufficient_for_pricefm_win"].map(boolish)
    out["same_family_capacity_search_supported"] = False
    out["new_consumed_mechanism_required"] = True
    out["test_metrics_role_stage_r35"] = "diagnostic_only_not_future_selection"
    return out.sort_values(["oracle_test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def case_queue(cases: pd.DataFrame, args: argparse.Namespace) -> pd.DataFrame:
    rows = []
    for _, row in cases.iterrows():
        harm_guard = int(row["r33_rows_beating_current_qdesn"]) > 0
        gap = float(row["oracle_test_minus_pricefm"])
        unstable = boolish(row["selection_instability_flag"])
        if harm_guard:
            queue = "priority0_current_qdesn_harm_guard"
            priority = 0
            mechanism = "new_family_with_authoritative_qdesn_fallback"
        elif gap <= float(args.near_gap_threshold):
            queue = "priority1_near_gap_new_mechanism_qualification"
            priority = 1
            mechanism = "fully_separate_horizon_readout_or_new_consumed_objective"
        elif gap >= float(args.far_gap_threshold):
            queue = "priority3_far_gap_hold"
            priority = 3
            mechanism = "hold_until_new_family_has_independent_near_gap_evidence"
        elif unstable:
            queue = "priority2_nested_validation_before_new_family"
            priority = 2
            mechanism = "nested_temporal_selection_plus_new_consumed_objective"
        else:
            queue = "priority2_mid_gap_new_mechanism_hold"
            priority = 2
            mechanism = "new_consumed_objective_after_qualification"
        rows.append(
            {
                "region": row["region"],
                "fold": int(row["fold"]),
                "stage_r35_priority": priority,
                "stage_r35_queue": queue,
                "exploratory_oracle_test_minus_pricefm": gap,
                "protect_current_qdesn": harm_guard,
                "validation_transfer_unstable": unstable,
                "recommended_new_mechanism": mechanism,
                "specification_scope": "case_specific_not_shared",
                "future_selection_rule": "nested_temporal_validation_only_within_case",
                "existing_test_role": "quarantined_audit_not_selection",
                "fresh_confirmation_required": True,
                "launch_ready_now": False,
                "launch_yaml_allowed_now": False,
            }
        )
    return pd.DataFrame(rows).sort_values(["stage_r35_priority", "exploratory_oracle_test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def parse_history_specs(args: argparse.Namespace) -> list[tuple[str, Path]]:
    values = args.history_summary
    if not values:
        return [(label, repo_path(path)) for label, path in HISTORY_DEFAULTS]
    rows = []
    for value in values:
        if "=" not in value:
            raise ValueError(f"--history-summary must be stage=path: {value}")
        label, path = value.split("=", 1)
        rows.append((label.strip(), repo_path(path.strip())))
    return rows


def test_adaptation_ledger(args: argparse.Namespace) -> tuple[pd.DataFrame, list[Path]]:
    rows = []
    paths = []
    for order, (stage, path) in enumerate(parse_history_specs(args), start=1):
        payload = read_json_required(path, f"{stage} history summary")
        paths.append(path)
        test_keys = sorted(key for key in payload if "test" in key.lower() or "beat" in key.lower() or "promotion" in key.lower())
        rows.append(
            {
                "chronological_order": order,
                "stage": stage,
                "summary_path": str(path),
                "summary_sha256": sha256_file(path),
                "test_or_promotion_keys_observed": json.dumps(test_keys),
                "test_evidence_was_available": bool(test_keys),
                "adaptation_role": "historical_exploratory_audit",
                "independence_implication": "existing_test_split_no_longer_pristine_for_new_family_selection",
            }
        )
    return pd.DataFrame(rows), paths


def confirmation_protocol(splits: pd.DataFrame, history: pd.DataFrame) -> pd.DataFrame:
    latest_response = str(splits["last_response_market_time"].max())
    repeated_test = int(history["test_evidence_was_available"].map(boolish).sum())
    rows = [
        (
            1,
            "freeze_r34_negative_closeout",
            True,
            "R34 has no validation-selected or oracle PriceFM winner.",
            "No registry/article/full-quantile/MCMC promotion.",
        ),
        (
            2,
            "quarantine_existing_test_for_future_selection",
            True,
            f"Test/promotion evidence appears in {repeated_test} historical stage summaries.",
            "Do not rank new specifications with the existing test split.",
        ),
        (
            3,
            "implement_consumed_new_mechanism",
            False,
            "Current runner is restricted to the exhausted AL/exAL family.",
            "Add code, unit tests, exact field propagation, and prediction artifacts first.",
        ),
        (
            4,
            "nested_temporal_validation_case_specific_selection",
            False,
            "Validation/test transfer is weak and current selector uses one aggregate validation window.",
            "Freeze one specification per case without test access.",
        ),
        (
            5,
            "independent_confirmation_window",
            False,
            f"Latest response in current artifacts is {latest_response}; no later unused period is evidenced.",
            "Acquire later data or pre-register rolling-origin cross-fitting with strict audit disclosure.",
        ),
        (
            6,
            "dual_reference_test_gate",
            False,
            "Future frozen candidate must beat authoritative Q-DESN and cached PriceFM.",
            "Only then permit full-quantile confirmation.",
        ),
        (
            7,
            "full_quantile_and_reproducibility_gate",
            False,
            "Median evidence alone is not article promotion evidence.",
            "Require all paper quantiles and source/artifact hashes.",
        ),
        (
            8,
            "mcmc_confirmation_then_article_registry",
            False,
            "MCMC is confirmatory, not a rescue optimizer.",
            "Mutate registry/article only after confirmed MCMC evidence.",
        ),
    ]
    return pd.DataFrame(rows, columns=["order", "gate", "passed_now", "evidence", "required_action"])


def decision_gates(
    inputs: dict[str, Any],
    transfer: pd.DataFrame,
    capability: pd.DataFrame,
    history: pd.DataFrame,
    args: argparse.Namespace,
) -> pd.DataFrame:
    rows = [
        ("r34_complete", bool(inputs["r34_summary"].get("run_complete", False)), "R34 must be complete."),
        ("r34_no_pricefm_surface_win", not inputs["metrics"]["beats_pricefm_on_test"].map(boolish).any(), "No R33 row beats PriceFM."),
        ("r34_no_promotion_queue", len(inputs["promotions"]) == 0 and len(inputs["mcmc"]) == 0, "Promotion and MCMC queues are empty."),
        ("oracle_cannot_solve_gap", not transfer["oracle_can_beat_pricefm"].map(boolish).any(), "Even test-oracle selection cannot beat PriceFM."),
        ("new_mechanism_not_runner_ready", not capability.loc[capability["mechanism"].eq("new_likelihood_or_direct_quantile_loss"), "currently_consumed"].map(boolish).any(), "A new loss/likelihood requires implementation."),
        ("existing_test_is_adaptive", history["test_evidence_was_available"].map(boolish).sum() >= 2, "Repeated historical test audits require renewed confirmation design."),
        ("same_family_relaunch_authorized", False, "R34 falsifies another broader R33-style capacity grid."),
        ("new_expensive_launch_authorized", False, "Requires implemented mechanism and nested-validation/fresh-confirmation gates."),
        ("full_quantile_launch_authorized", False, "Requires a future dual-reference winner."),
        ("mcmc_launch_authorized", False, "Requires full-quantile confirmation first."),
        ("registry_mutation_authorized", False, "No promotable evidence exists."),
        ("article_mutation_authorized", False, "No promotable evidence exists."),
        ("writes_launch_yaml", False, "Stage-R35 is read-only and writes no launch YAML."),
    ]
    return pd.DataFrame([{"gate": gate, "passed": bool(passed), "detail": detail} for gate, passed, detail in rows])


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in sorted(set(repo_path(path) for path in paths), key=str):
        rows.append(
            {
                "path": str(path),
                "exists": path.exists(),
                "bytes": int(path.stat().st_size) if path.exists() and path.is_file() else 0,
                "sha256": sha256_file(path) if path.exists() and path.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def render_report(summary: dict[str, Any], cases: pd.DataFrame, queue: pd.DataFrame) -> str:
    near = int(summary["near_gap_cases"])
    guards = int(queue["protect_current_qdesn"].map(boolish).sum())
    return "\n".join(
        [
            "# PriceFM Stage-R35 Failure Decomposition",
            "",
            f"- R34 experiments: `{summary['r34_experiments']}`",
            f"- R34 method rows: `{summary['r34_method_rows']}`",
            f"- Validation-selected PriceFM wins: `{summary['validation_selected_pricefm_wins']}`",
            f"- Test-oracle PriceFM wins: `{summary['test_oracle_pricefm_wins']}`",
            f"- Validation-transfer unstable cases: `{summary['validation_transfer_unstable_cases']}`",
            f"- Near-gap new-mechanism cases: `{near}`",
            f"- Current-Q-DESN harm guards: `{guards}`",
            f"- Historical test-visible stages: `{summary['test_visible_history_stages']}`",
            "",
            "R34 rules out another broader AL/exAL reservoir-capacity search: no row beats",
            "PriceFM even under diagnostic test-oracle selection. Validation instability is real",
            "but secondary because perfect retrospective selection cannot close the gap.",
            "",
            "The next model experiment is blocked until runner/model code consumes a genuinely",
            "new objective or fully separate horizon-specific readout and a nested temporal",
            "selection protocol is pre-registered. Existing test results are quarantined from",
            "future specification selection. MCMC, registry, and article mutation remain blocked.",
            "",
        ]
    )


def write_frame(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def run(args: argparse.Namespace) -> dict[str, Any]:
    inputs = read_inputs(args)
    validate_inputs(inputs, args)
    paths = source_paths(args)
    missing_sources = [label for label, path in paths.items() if not path.exists()]
    if missing_sources:
        raise FileNotFoundError(f"Stage-R35 source files missing: {missing_sources}")

    transfer = validation_transfer(inputs["metrics"], inputs["selected"], inputs["oracle"], args)
    response = capacity_response(inputs["metrics"], args)
    horizons, horizon_sources = selected_horizon_diagnostics(inputs["selected"], inputs["full_horizon"])
    calibration, splits, prediction_sources = prediction_and_split_diagnostics(inputs["selected"], args)
    capability = runner_capability(paths)
    saturation = mechanism_saturation(inputs, capability)
    cases = case_decomposition(
        inputs["metrics"],
        inputs["selected"],
        inputs["oracle"],
        transfer,
        calibration,
        response,
        inputs["r21_atlas"],
        args,
    )
    queue = case_queue(cases, args)
    history, history_sources = test_adaptation_ledger(args)
    protocol = confirmation_protocol(splits, history)
    gates = decision_gates(inputs, transfer, capability, history, args)

    r34 = Path(args.stage_r34_dir)
    fixed_sources = [
        Path(__file__).resolve(),
        r34 / "summary.json",
        r34 / R34_METRICS,
        r34 / R34_SELECTED,
        r34 / R34_ORACLE,
        r34 / R34_PROMOTION,
        r34 / R34_MCMC,
        r34 / R34_GATES,
        Path(args.stage_r21_dir) / R21_ATLAS,
        Path(args.stage_r23_dir) / R23_CAPABILITY,
        Path(args.stage_r27_dir) / "summary.json",
        Path(args.stage_r27_dir) / R27_DIAGNOSIS,
        Path(args.stage_r28_dir) / "summary.json",
        Path(args.stage_r28_dir) / R28_CAPABILITY,
        Path(args.full_surface_dir) / FULL_HORIZON,
    ] + list(paths.values())
    sources = source_manifest(fixed_sources + horizon_sources + prediction_sources + history_sources)
    if not sources["exists"].map(boolish).all():
        raise ValueError("Stage-R35 source manifest contains missing files")

    selected_wins = int(inputs["selected"]["beats_pricefm_on_test"].map(boolish).sum())
    oracle_wins = int((pd.to_numeric(inputs["oracle"]["test_minus_pricefm"], errors="coerce") < 0).sum())
    summary = {
        "stage": "pricefm_stage_r35_failure_decomposition",
        "status": "completed_read_only_new_mechanism_required",
        "r34_experiments": int(inputs["metrics"]["experiment_id"].nunique()),
        "r34_method_rows": int(len(inputs["metrics"])),
        "r34_cases": int(len(inputs["selected"])),
        "validation_selected_pricefm_wins": selected_wins,
        "test_oracle_pricefm_wins": oracle_wins,
        "validation_transfer_unstable_cases": int(transfer["selection_instability_flag"].map(boolish).sum()),
        "median_validation_test_spearman": float(transfer["validation_test_spearman"].median()),
        "median_selection_penalty_AQL": float(transfer["selection_penalty_AQL"].median()),
        "near_gap_cases": int((cases["oracle_test_minus_pricefm"] <= float(args.near_gap_threshold)).sum()),
        "far_gap_cases": int((cases["oracle_test_minus_pricefm"] >= float(args.far_gap_threshold)).sum()),
        "current_qdesn_harm_guard_cases": int(queue["protect_current_qdesn"].map(boolish).sum()),
        "test_visible_history_stages": int(history["test_evidence_was_available"].map(boolish).sum()),
        "latest_response_market_time": str(splits["last_response_market_time"].max()),
        "recommended_next_action": "implement_and_test_new_consumed_objective_or_fully_separate_horizon_readout_then_nested_validation_design",
        "same_family_relaunch_authorized": False,
        "new_expensive_launch_authorized": False,
        "full_quantile_launch_authorized": False,
        "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "writes_launch_yaml": False,
        "fits_models": False,
    }

    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"Stage-R35 output exists; use --force true to replace it: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {
        OUT_CASES: cases,
        OUT_HORIZONS: horizons,
        OUT_CALIBRATION: calibration,
        OUT_TRANSFER: transfer,
        OUT_RESPONSE: response,
        OUT_CAPABILITY: capability,
        OUT_SATURATION: saturation,
        OUT_QUEUE: queue,
        OUT_SPLITS: splits,
        OUT_HISTORY: history,
        OUT_PROTOCOL: protocol,
        OUT_GATES: gates,
        OUT_SOURCE: sources,
    }
    for name, frame in outputs.items():
        write_frame(output_dir / name, frame)
    write_json(output_dir / OUT_SUMMARY, summary)
    (output_dir / OUT_REPORT).write_text(render_report(summary, cases, queue))
    if list(output_dir.glob("*.yaml")) or list(output_dir.glob("*.yml")):
        raise RuntimeError("Stage-R35 must not write launch YAML")
    return summary


def main() -> None:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
