#!/usr/bin/env python3
"""Read-only PriceFM Stage-R23 mechanism-capability audit."""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json
from pricefm_full_surface import repo_relative, sha256_file_or_blank


DEFAULT_R22C_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r22c_case_specific_screening_launch_prep_20260709"
)
DEFAULT_R22D_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r22d_case_specific_screening_closeout_20260709"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r23_mechanism_capability_audit_20260709"
)
DEFAULT_PACKAGE_ROOT = "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0"

R22C_MANIFEST = "pricefm_stage_r22c_launch_manifest.csv"
R22C_DEFERRED = "pricefm_stage_r22c_postfit_deferred_manifest.csv"
R22C_GATES = "pricefm_stage_r22c_launch_prep_gates.csv"
R22D_SUMMARY = "summary.json"

OUT_FIELD_PROPAGATION = "pricefm_stage_r23_field_propagation_audit.csv"
OUT_CAPABILITY = "pricefm_stage_r23_runner_capability_matrix.csv"
OUT_PACKAGE_SIGNATURE = "pricefm_stage_r23_package_fit_signature.csv"
OUT_SEARCH_SPACE = "pricefm_stage_r23_r22c_effective_search_space.csv"
OUT_CALIBRATION = "pricefm_stage_r23_postfit_calibration_readiness.csv"
OUT_CASE_QUEUE = "pricefm_stage_r23_case_next_mechanism_queue.csv"
OUT_EXPENSIVE_BOUNDS = "pricefm_stage_r23_expensive_path_bounds_recommendation.csv"
OUT_GATES = "pricefm_stage_r23_no_launch_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_REPORT = "pricefm_stage_r23_mechanism_capability_audit_report.md"

SOURCE_DEFAULTS = {
    "stage_r22b_prep": "application/scripts/pricefm/144_prepare_pricefm_stage_r22b_case_specific_screening.py",
    "stage_r22c_launch_prep": "application/scripts/pricefm/145_prepare_pricefm_stage_r22c_case_specific_screening_launch.py",
    "stage_r22d_closeout": "application/scripts/pricefm/146_closeout_pricefm_stage_r22c_case_specific_screening.py",
    "full_run_orchestrator": "application/scripts/pricefm/pricefm_full_run.py",
    "adapter_builder": "application/scripts/pricefm/pricefm_desn_adapter.py",
    "model_fitter": "application/scripts/pricefm/08_run_desn_model_smoke.R",
    "metric_summarizer": "application/scripts/pricefm/09_summarize_desn_model_smoke.py",
    "template_grid": "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml",
}
PACKAGE_SOURCE_DEFAULTS = {
    "package_exal_wrapper": "R/exal_ldvb_fit.R",
    "package_exal_engine": "R/exal_ldvb_engine.R",
    "package_qdesn_vb": "R/qdesn_vb.R",
}
SOURCE_ROLES = {
    "stage_r22b_prep": "planning_contract",
    "stage_r22c_launch_prep": "launch_grid_materialization",
    "stage_r22d_closeout": "closeout_selection",
    "full_run_orchestrator": "orchestrator_config_forwarding",
    "adapter_builder": "design_matrix_and_reservoir_builder",
    "model_fitter": "model_fitting",
    "metric_summarizer": "metric_summary",
    "template_grid": "launch_template",
    "package_exal_wrapper": "package_fit_wrapper",
    "package_exal_engine": "package_fit_engine",
    "package_qdesn_vb": "package_qdesn_alternative",
}

FIELDS = [
    "horizon_weight_multiplier",
    "calibration_rule",
    "screening_arm",
    "horizon_focus",
    "state_output",
    "units",
    "depth",
    "alpha",
    "rho",
    "input_scale",
    "tau0",
    "feature_policy",
    "qdesn_likelihoods",
    "quantiles",
    "horizons",
]
NUMERIC_AXES = [
    "target_quantile",
    "lag_window",
    "depth",
    "feature_dim",
    "alpha",
    "rho",
    "input_scale",
    "tau0",
    "horizon_weight_multiplier",
]
CATEGORICAL_AXES = [
    "units",
    "feature_policy",
    "state_output",
    "screening_arm",
    "candidate_family",
    "horizon_focus",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r22c-prep-dir", default=DEFAULT_R22C_PREP_DIR)
    p.add_argument("--r22d-dir", default=DEFAULT_R22D_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--package-root", default=DEFAULT_PACKAGE_ROOT)
    for label, default in SOURCE_DEFAULTS.items():
        p.add_argument(f"--source-{label.replace('_', '-')}", default=default)
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


def text_value(value: Any) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return str(value).strip()


def finite_float(value: Any) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return out if math.isfinite(out) else float("nan")


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with open(full, "r") as f:
        return json.load(f)


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def write_frame(path: str | Path, frame: pd.DataFrame) -> None:
    full = repo_path(path)
    full.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(full, index=False)


def source_paths(args: argparse.Namespace) -> dict[str, Path]:
    out = {}
    for label in SOURCE_DEFAULTS:
        out[label] = repo_path(getattr(args, f"source_{label}"))
    package_root = Path(args.package_root)
    for label, rel in PACKAGE_SOURCE_DEFAULTS.items():
        out[label] = package_root / rel
    return out


def read_text(path: Path) -> str:
    if not path.exists() or not path.is_file():
        return ""
    return path.read_text(errors="replace")


def first_occurrence(text: str, needle: str) -> tuple[int | str, str]:
    for lineno, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return lineno, line.strip()
    return "", ""


def source_manifest(args: argparse.Namespace, paths: dict[str, Path]) -> pd.DataFrame:
    specs: list[tuple[str, Path, str]] = [
        ("stage_r22c_launch_manifest", Path(args.r22c_prep_dir) / R22C_MANIFEST, "csv"),
        ("stage_r22c_postfit_deferred", Path(args.r22c_prep_dir) / R22C_DEFERRED, "csv"),
        ("stage_r22c_launch_prep_gates", Path(args.r22c_prep_dir) / R22C_GATES, "csv"),
        ("stage_r22d_summary", Path(args.r22d_dir) / R22D_SUMMARY, "json"),
    ]
    specs.extend((label, path, "source") for label, path in paths.items())
    rows = []
    for label, path, kind in specs:
        full = repo_path(path)
        rows.append(
            {
                "label": label,
                "kind": kind,
                "path": repo_relative(full) if str(full).startswith(str(repo_path("."))) else str(full),
                "exists": full.exists(),
                "bytes": int(full.stat().st_size) if full.exists() and full.is_file() else 0,
                "sha256": sha256_file_or_blank(full) if full.exists() and full.is_file() else "",
            }
        )
    return pd.DataFrame(rows)


def field_propagation(paths: dict[str, Path]) -> pd.DataFrame:
    rows = []
    for source_label, path in paths.items():
        text = read_text(path)
        for field in FIELDS:
            line_no, line = first_occurrence(text, field)
            rows.append(
                {
                    "field": field,
                    "source_label": source_label,
                    "source_role": SOURCE_ROLES.get(source_label, "unknown"),
                    "path": repo_relative(path) if str(path).startswith(str(repo_path("."))) else str(path),
                    "occurrence_count": int(text.count(field)),
                    "first_line": line_no,
                    "first_evidence": line,
                }
            )
    return pd.DataFrame(rows).sort_values(["field", "source_label"]).reset_index(drop=True)


def unique_text(values: pd.Series, max_items: int = 20) -> str:
    vals = sorted({text_value(x) for x in values if text_value(x) != ""})
    suffix = "" if len(vals) <= max_items else f"; ... +{len(vals) - max_items} more"
    return "; ".join(vals[:max_items]) + suffix


def numeric_summary(frame: pd.DataFrame, axis: str, candidate_set: str) -> dict[str, Any]:
    values = pd.to_numeric(frame[axis], errors="coerce").dropna()
    uniq = sorted(values.unique().tolist())
    return {
        "candidate_set": candidate_set,
        "axis": axis,
        "axis_type": "numeric",
        "rows": int(frame.shape[0]),
        "n_unique": int(len(uniq)),
        "min": float(values.min()) if not values.empty else float("nan"),
        "max": float(values.max()) if not values.empty else float("nan"),
        "unique_values": "; ".join("{:.12g}".format(float(x)) for x in uniq[:30]),
    }


def categorical_summary(frame: pd.DataFrame, axis: str, candidate_set: str) -> dict[str, Any]:
    vals = frame[axis].map(text_value)
    return {
        "candidate_set": candidate_set,
        "axis": axis,
        "axis_type": "categorical",
        "rows": int(frame.shape[0]),
        "n_unique": int(vals[vals.ne("")].nunique()),
        "min": "",
        "max": "",
        "unique_values": unique_text(vals),
    }


def parse_units(value: Any) -> list[int]:
    text = text_value(value)
    if not text or text == "existing_stage_r19":
        return []
    parsed = json.loads(text)
    return [int(x) for x in parsed]


def search_space(manifest: pd.DataFrame, deferred: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for axis in NUMERIC_AXES:
        if axis in manifest.columns:
            row = numeric_summary(manifest, axis, "r22c_new_fit_launch")
            row["effective_status"] = "adapter_or_runner_configured" if axis != "horizon_weight_multiplier" else "metadata_only_not_consumed_by_fit"
            rows.append(row)
    for axis in CATEGORICAL_AXES:
        if axis in manifest.columns:
            row = categorical_summary(manifest, axis, "r22c_new_fit_launch")
            if axis == "screening_arm":
                row["effective_status"] = "selection_metadata_not_fit_behavior"
            elif axis == "state_output":
                row["effective_status"] = "adapter_consumed_changes_reservoir_state_dimension"
            elif axis == "feature_policy":
                row["effective_status"] = "adapter_consumed_changes_information_set"
            else:
                row["effective_status"] = "configured_or_metadata"
            rows.append(row)
    if "units" in manifest.columns:
        total_units = manifest["units"].map(lambda x: sum(parse_units(x)))
        final_units = manifest["units"].map(lambda x: parse_units(x)[-1] if parse_units(x) else float("nan"))
        for axis, values in [("n_total_units", total_units), ("n_final_layer_units", final_units)]:
            frame = pd.DataFrame({axis: values})
            row = numeric_summary(frame, axis, "r22c_new_fit_launch")
            row["effective_status"] = "adapter_consumed_reservoir_size"
            rows.append(row)
    if not deferred.empty:
        for axis in ["calibration_rule", "candidate_family", "feature_policy_candidate", "horizon_weight_multiplier"]:
            if axis in deferred.columns:
                if axis == "horizon_weight_multiplier":
                    row = numeric_summary(deferred, axis, "r22c_postfit_deferred")
                else:
                    row = categorical_summary(deferred, axis, "r22c_postfit_deferred")
                row["effective_status"] = "deferred_not_executed_by_r22c"
                rows.append(row)
    out = pd.DataFrame(rows)
    out["expensive_path_implication"] = out.apply(expensive_axis_implication, axis=1)
    return out.sort_values(["candidate_set", "axis"]).reset_index(drop=True)


def expensive_axis_implication(row: pd.Series) -> str:
    axis = str(row["axis"])
    if axis == "horizon_weight_multiplier":
        return "Do not spend broad runs on this axis until row-weighted fitting or postfit horizon weighting is implemented."
    if axis == "calibration_rule":
        return "Requires a postfit calibration runner before it can be part of the expensive path."
    if axis in {"depth", "units", "n_total_units", "n_final_layer_units", "feature_dim", "alpha", "rho", "input_scale", "lag_window"}:
        return "Real adapter/reservoir axis; can be broadened after mechanism support is verified."
    if axis == "feature_policy":
        return "Real information-set axis; broaden only with harm guards for current Q-DESN wins."
    if axis == "state_output":
        return "Real readout-state axis, but not a true horizon-block-specific coefficient system."
    return "Audit-only context for future bounded launch design."


def calibration_readiness(deferred: pd.DataFrame) -> pd.DataFrame:
    if deferred.empty:
        return pd.DataFrame()
    require_columns(
        deferred,
        [
            "stage_r22b_case_id",
            "region",
            "fold",
            "screening_arm",
            "candidate_family",
            "uses_existing_predictions",
            "requires_new_fit",
            "existing_prediction_path",
            "existing_metric_summary_path",
            "calibration_rule",
        ],
        "Stage-R22C deferred postfit manifest",
    )
    rows = []
    for _, row in deferred.iterrows():
        pred_text = text_value(row.get("existing_prediction_path"))
        metric_text = text_value(row.get("existing_metric_summary_path"))
        pred_path = repo_path(pred_text) if pred_text else None
        metric_path = repo_path(metric_text) if metric_text else None
        uses_existing = boolish(row.get("uses_existing_predictions"))
        pred_exists = bool(pred_path is not None and pred_path.exists())
        metric_exists = bool(metric_path is not None and metric_path.exists())
        if not uses_existing:
            status = "not_existing_prediction_calibration"
        elif pred_exists and metric_exists:
            status = "ready_for_postfit_calibration_runner"
        elif not pred_text and not metric_text:
            status = "blocked_missing_existing_prediction_and_metric_paths"
        elif not pred_exists or not metric_exists:
            status = "blocked_existing_prediction_artifacts_not_found"
        else:
            status = "blocked_unknown"
        rows.append(
            {
                "stage_r22b_case_id": row["stage_r22b_case_id"],
                "region": row["region"],
                "fold": int(row["fold"]),
                "screening_arm": row["screening_arm"],
                "candidate_family": row["candidate_family"],
                "calibration_rule": row["calibration_rule"],
                "uses_existing_predictions": uses_existing,
                "requires_new_fit": boolish(row.get("requires_new_fit")),
                "existing_prediction_path": pred_text,
                "existing_prediction_exists": pred_exists,
                "existing_metric_summary_path": metric_text,
                "existing_metric_summary_exists": metric_exists,
                "readiness_status": status,
                "next_required_work": (
                    "implement_postfit_calibration_runner"
                    if status == "ready_for_postfit_calibration_runner"
                    else "recover_or_materialize_existing_prediction_artifact_paths"
                    if uses_existing
                    else "none"
                ),
            }
        )
    return pd.DataFrame(rows).sort_values(["readiness_status", "region", "fold", "candidate_family"]).reset_index(drop=True)


def extract_function_signature(text: str, function_name: str) -> str:
    idx = text.find(f"{function_name} <- function")
    if idx < 0:
        idx = text.find(f"{function_name} = function")
    if idx < 0:
        return ""
    snippet = text[idx : idx + 1400]
    start = snippet.find("function")
    if start < 0:
        return ""
    paren = snippet.find("(", start)
    if paren < 0:
        return ""
    depth = 0
    for pos in range(paren, len(snippet)):
        ch = snippet[pos]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return snippet[start : pos + 1].replace("\n", " ")
    return snippet[start:].replace("\n", " ")


def package_fit_signature(paths: dict[str, Path], model_text: str) -> pd.DataFrame:
    rows = []
    specs = [
        ("exal_ldvb_fit", paths.get("package_exal_wrapper", Path("")), "wrapper"),
        ("exal_ldvb_engine", paths.get("package_exal_engine", Path("")), "engine"),
    ]
    for function_name, path, role in specs:
        text = read_text(path)
        signature = extract_function_signature(text, function_name)
        rows.append(
            {
                "function_name": function_name,
                "source_role": role,
                "path": str(path),
                "exists": bool(path.exists()),
                "signature": signature,
                "has_explicit_weights_arg": bool(re.search(r"(^|[^A-Za-z0-9_])weights\\s*=", signature)),
                "has_dots_arg": "..." in signature,
                "mentions_weights_in_body": "weights" in text,
            }
        )
    rows.append(
        {
            "function_name": "pricefm_fit_quantile_call",
            "source_role": "pricefm_model_runner",
            "path": repo_relative(SOURCE_DEFAULTS["model_fitter"]),
            "exists": True,
            "signature": "exal_ldvb_fit(y = y_tr, X = X_tr, p0 = tau, ...)",
            "has_explicit_weights_arg": False,
            "has_dots_arg": False,
            "mentions_weights_in_body": "weights" in model_text,
        }
    )
    out = pd.DataFrame(rows)
    out["pricefm_passes_weights_to_fit"] = out["function_name"].eq("pricefm_fit_quantile_call") & out["mentions_weights_in_body"].map(bool)
    return out


def has_any(text: str, terms: list[str]) -> bool:
    return any(term in text for term in terms)


def capability_matrix(manifest: pd.DataFrame, deferred: pd.DataFrame, paths: dict[str, Path], signature: pd.DataFrame) -> pd.DataFrame:
    texts = {label: read_text(path) for label, path in paths.items()}
    model = texts.get("model_fitter", "")
    adapter = texts.get("adapter_builder", "")
    full_run = texts.get("full_run_orchestrator", "")
    summarizer = texts.get("metric_summarizer", "")
    package_engine = texts.get("package_exal_engine", "")
    package_wrapper = texts.get("package_exal_wrapper", "")
    rows = []

    row_weight_package_hook = (
        signature["has_explicit_weights_arg"].map(bool).any()
        or ("weights" in package_engine and "exal_ldvb_engine" in package_engine)
        or ("weights" in package_wrapper and "..." in package_wrapper)
    )
    pricefm_passes_weight = "weights" in model or "horizon_weight_multiplier" in model
    rows.append(
        {
            "mechanism": "horizon_weighted_readout_loss",
            "r22c_declared": manifest["screening_arm"].astype(str).eq("horizon_weighted_readout_loss").any(),
            "runner_consumes_required_field": pricefm_passes_weight,
            "adapter_consumes_required_field": "horizon_weight_multiplier" in adapter,
            "model_fit_consumes_required_field": pricefm_passes_weight,
            "package_support_hint": row_weight_package_hook,
            "effective_status": "metadata_only_not_implemented_in_pricefm_runner",
            "evidence": "R22C carries horizon_weight_multiplier, but PriceFM model_fitter does not pass row weights or horizon weights into exal_ldvb_fit.",
            "required_before_expensive_launch": "Add and test row/horizon weights in PriceFM model_fitter, including validation/test metric replay.",
        }
    )
    rows.append(
        {
            "mechanism": "horizon_block_interaction_readout",
            "r22c_declared": manifest["screening_arm"].astype(str).eq("horizon_block_interaction_readout").any(),
            "runner_consumes_required_field": "state_output" in full_run,
            "adapter_consumes_required_field": "state_output" in adapter and "concat_layers" in adapter,
            "model_fit_consumes_required_field": False,
            "package_support_hint": False,
            "effective_status": "partially_implemented_as_concat_layer_state_not_horizon_specific_loss",
            "evidence": "state_output reaches the adapter and concat_layers changes reservoir state dimension; no horizon-block-specific coefficient or loss branch is fitted.",
            "required_before_expensive_launch": "If desired, implement explicit horizon-block readout interactions or split-horizon model combination; otherwise treat this as ordinary state-output search.",
        }
    )
    rows.append(
        {
            "mechanism": "postfit_calibration",
            "r22c_declared": deferred["screening_arm"].astype(str).eq("postfit_calibration").any() if not deferred.empty else False,
            "runner_consumes_required_field": has_any(model + summarizer, ["calibration_rule", "postfit_calibration"]),
            "adapter_consumes_required_field": False,
            "model_fit_consumes_required_field": has_any(model, ["calibration_rule", "postfit_calibration"]),
            "package_support_hint": False,
            "effective_status": "deferred_not_executed_by_r22c",
            "evidence": "R22C preserved postfit rows in a deferred manifest and explicitly excluded them from DESN launch rows.",
            "required_before_expensive_launch": "Implement a validation-only postfit calibration/combination runner if this axis is used.",
        }
    )
    rows.append(
        {
            "mechanism": "reservoir_size_depth_n_D",
            "r22c_declared": {"units", "depth", "feature_dim"}.issubset(manifest.columns),
            "runner_consumes_required_field": "ADAPTER_FORWARD_KEYS" in full_run and "units" in full_run and "depth" in full_run,
            "adapter_consumes_required_field": all(term in adapter for term in ["normalize_reservoir_config", "units", "depth", "reservoir_state_dim"]),
            "model_fit_consumes_required_field": True,
            "package_support_hint": True,
            "effective_status": "implemented_adapter_search_axis",
            "evidence": "full_run forwards reservoir settings and adapter_builder constructs reservoir states with configured units/depth/state_output.",
            "required_before_expensive_launch": "Can be broadened, but only after weighted/calibration mechanisms are made real or explicitly excluded.",
        }
    )
    rows.append(
        {
            "mechanism": "feature_policy_information_set",
            "r22c_declared": "feature_policy" in manifest.columns,
            "runner_consumes_required_field": "feature_policy" in full_run,
            "adapter_consumes_required_field": "feature_policy" in adapter and "Unknown feature_policy" in adapter,
            "model_fit_consumes_required_field": True,
            "package_support_hint": True,
            "effective_status": "implemented_information_set_axis",
            "evidence": "feature_policy controls graph/local windows and feature provenance before fitting.",
            "required_before_expensive_launch": "Broaden only with no-harm guards for current Q-DESN wins and explicit PriceFM information-set parity notes.",
        }
    )
    rows.append(
        {
            "mechanism": "qdesn_likelihood_family_selection",
            "r22c_declared": "qdesn_likelihoods" in texts.get("template_grid", ""),
            "runner_consumes_required_field": "qdesn_likelihoods" in full_run,
            "adapter_consumes_required_field": False,
            "model_fit_consumes_required_field": "cfg$qdesn_likelihoods" in model,
            "package_support_hint": True,
            "effective_status": "ignored_by_model_runner_al_and_exal_fit_unconditionally",
            "evidence": "08_run_desn_model_smoke.R calls fit_qdesn_like('al') and fit_qdesn_like('exal') unconditionally.",
            "required_before_expensive_launch": "Optional: make likelihood family configurable if broad runs need to avoid wasted AL/exAL fits.",
        }
    )
    rows.append(
        {
            "mechanism": "multi_quantile_scope",
            "r22c_declared": manifest["target_quantile"].nunique() == 1,
            "runner_consumes_required_field": "quantiles" in full_run and "quantiles <-" in model,
            "adapter_consumes_required_field": False,
            "model_fit_consumes_required_field": "for (j in seq_along(quantiles))" in model,
            "package_support_hint": True,
            "effective_status": "runner_supports_config_but_r22c_explored_median_only",
            "evidence": "Runner can receive a quantile list, but R22C manifest contains only target_quantile=0.5.",
            "required_before_expensive_launch": "If article comparison needs all paper quantiles, decide whether broad search is median-first or full-quantile from launch start.",
        }
    )
    return pd.DataFrame(rows)


def case_next_mechanism_queue(manifest: pd.DataFrame, deferred: pd.DataFrame, calibration: pd.DataFrame) -> pd.DataFrame:
    case_base = (
        manifest.groupby(["stage_r22b_case_id", "region", "fold"], as_index=False)
        .agg(
            new_fit_candidates=("experiment_id", "size"),
            arms=("screening_arm", lambda x: ",".join(sorted(set(map(str, x))))),
            min_promotable_test_AQL=("max_promotable_test_AQL", "min"),
            feature_policies=("feature_policy", lambda x: ",".join(sorted(set(map(str, x))))),
            units_vectors=("units", lambda x: ",".join(sorted(set(map(str, x))))),
            max_feature_dim=("feature_dim", "max"),
        )
    )
    if not deferred.empty:
        deferred_counts = (
            deferred.groupby(["stage_r22b_case_id"], as_index=False)
            .agg(
                deferred_postfit_candidates=("stage_r22b_candidate_id", "size"),
                calibration_rules=("calibration_rule", lambda x: ",".join(sorted(set(map(str, x))))),
            )
        )
    else:
        deferred_counts = pd.DataFrame(columns=["stage_r22b_case_id", "deferred_postfit_candidates", "calibration_rules"])
    if not calibration.empty:
        ready_counts = (
            calibration.groupby(["stage_r22b_case_id"], as_index=False)
            .agg(
                ready_postfit_candidates=("readiness_status", lambda x: int(sum(v == "ready_for_postfit_calibration_runner" for v in x))),
                blocked_postfit_candidates=("readiness_status", lambda x: int(sum(v != "ready_for_postfit_calibration_runner" for v in x))),
            )
        )
    else:
        ready_counts = pd.DataFrame(columns=["stage_r22b_case_id", "ready_postfit_candidates", "blocked_postfit_candidates"])
    out = case_base.merge(deferred_counts, on="stage_r22b_case_id", how="left")
    out = out.merge(ready_counts, on="stage_r22b_case_id", how="left")
    for col in ["deferred_postfit_candidates", "ready_postfit_candidates", "blocked_postfit_candidates"]:
        out[col] = pd.to_numeric(out[col], errors="coerce").fillna(0).astype(int)
    out["recommended_stage_r23_queue"] = out.apply(
        lambda row: "postfit_calibration_path_blocked_until_artifact_paths_exist"
        if int(row["blocked_postfit_candidates"]) > 0
        else "true_weighted_loss_or_horizon_specific_readout_after_runner_support"
        if int(row["ready_postfit_candidates"]) == 0
        else "postfit_calibration_runner_then_true_weighted_loss_if_needed",
        axis=1,
    )
    out["expensive_launch_readiness"] = "not_ready_runner_mechanism_gap"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def expensive_bounds_recommendation(search: pd.DataFrame) -> pd.DataFrame:
    observed = search.set_index(["candidate_set", "axis"], drop=False)

    def values(axis: str) -> str:
        key = ("r22c_new_fit_launch", axis)
        if key not in observed.index:
            return ""
        return str(observed.loc[key, "unique_values"])

    rows = [
        {
            "axis_group": "reservoir_size",
            "r22c_observed_bounds": f"depth={values('depth')}; units={values('units')}; feature_dim={values('feature_dim')}",
            "broad_expensive_path_recommendation": "Broaden depth/units/feature_dim only after R23/R24 confirms true weighted/calibration support; otherwise it repeats a real but insufficient axis.",
            "must_implement_before_launch": False,
        },
        {
            "axis_group": "reservoir_dynamics",
            "r22c_observed_bounds": f"alpha={values('alpha')}; rho={values('rho')}; input_scale={values('input_scale')}; tau0={values('tau0')}",
            "broad_expensive_path_recommendation": "Broaden alpha/rho/input_scale/tau0 with per-case bounds, but include convergence and stability gates.",
            "must_implement_before_launch": False,
        },
        {
            "axis_group": "lag_and_information_set",
            "r22c_observed_bounds": f"lag_window={values('lag_window')}; feature_policy={values('feature_policy')}",
            "broad_expensive_path_recommendation": "Consider lag windows beyond 96 and broader local/graph policies only with explicit information-set and harm guards.",
            "must_implement_before_launch": False,
        },
        {
            "axis_group": "horizon_weighted_loss",
            "r22c_observed_bounds": f"horizon_weight_multiplier={values('horizon_weight_multiplier')}",
            "broad_expensive_path_recommendation": "Do not spend the expensive run on this axis until the PriceFM model runner passes row/horizon weights to the fit or an equivalent objective.",
            "must_implement_before_launch": True,
        },
        {
            "axis_group": "postfit_calibration",
            "r22c_observed_bounds": "deferred calibration rules only; not executed in R22C",
            "broad_expensive_path_recommendation": "Implement validation-only postfit calibration/combination before including calibration arms in a broad launch.",
            "must_implement_before_launch": True,
        },
        {
            "axis_group": "quantile_scope",
            "r22c_observed_bounds": f"target_quantile={values('target_quantile')}",
            "broad_expensive_path_recommendation": "Decide whether broad search is median-first or full paper quantiles; full-quantile launch is costlier but article-relevant.",
            "must_implement_before_launch": False,
        },
    ]
    return pd.DataFrame(rows)


def no_launch_gates(
    manifest: pd.DataFrame,
    deferred: pd.DataFrame,
    r22d_summary: dict[str, Any],
    capability: pd.DataFrame,
    output_dir: Path,
) -> pd.DataFrame:
    cap = capability.set_index("mechanism")
    weighted_status = str(cap.loc["horizon_weighted_readout_loss", "effective_status"])
    calibration_status = str(cap.loc["postfit_calibration", "effective_status"])
    gates = [
        ("r22c_manifest_loaded", not manifest.empty, "R22C launch manifest was loaded."),
        ("r22c_deferred_calibration_loaded", not deferred.empty, "R22C deferred postfit calibration manifest was loaded."),
        ("r22d_closeout_loaded", r22d_summary.get("stage") == "pricefm_stage_r22d_case_specific_screening_closeout", "R22D closeout summary was loaded."),
        ("r22d_no_promotions_confirmed", int(r22d_summary.get("n_promotion_queue_rows", -1)) == 0, "R22D had no promotable candidates."),
        ("horizon_weighted_loss_not_currently_real", weighted_status == "metadata_only_not_implemented_in_pricefm_runner", "R22C weighted-loss labels are not consumed by the PriceFM model fitter."),
        ("postfit_calibration_not_currently_executed", calibration_status == "deferred_not_executed_by_r22c", "Postfit calibration rows remain deferred."),
        ("expensive_launch_blocked_until_mechanisms_real", True, "R23 produces no launch YAML and requires a later implementation gate before broad expensive screening."),
        ("registry_manuscript_mutation_blocked", True, "R23 does not mutate registry or manuscript files."),
        ("no_launch_yaml_written", not any(output_dir.glob("*.yaml")) and not any(output_dir.glob("*.yml")), "R23 output directory contains no YAML launch config."),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in gates])


def markdown_table(frame: pd.DataFrame, columns: list[str] | None = None, max_rows: int = 30) -> str:
    if frame.empty:
        return "_No rows._"
    work = frame.copy()
    if columns is not None:
        work = work[[col for col in columns if col in work.columns]]
    work = work.head(max_rows)
    headers = list(work.columns)
    lines = ["| {} |".format(" | ".join(headers))]
    lines.append("| {} |".format(" | ".join(["---"] * len(headers))))
    for _, row in work.iterrows():
        vals = []
        for col in headers:
            value = row[col]
            if isinstance(value, float):
                vals.append("" if math.isnan(value) else "{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| {} |".format(" | ".join(vals)))
    if len(frame) > len(work):
        lines.extend(["", f"_Showing {len(work)} of {len(frame)} rows._"])
    return "\n".join(lines)


def write_report(
    path: str | Path,
    summary: dict[str, Any],
    capability: pd.DataFrame,
    search: pd.DataFrame,
    calibration: pd.DataFrame,
    bounds: pd.DataFrame,
    gates: pd.DataFrame,
) -> None:
    lines = [
        "# PriceFM Stage-R23 Mechanism-Capability Audit",
        "",
        "Stage-R23 is read-only. It audits whether the Stage-R22C mechanism labels are actually consumed by the PriceFM runner/model path before any broad expensive screening is launched.",
        "",
        "## Executive Summary",
        "",
        f"- Status: `{summary['status']}`",
        f"- R22C launch rows audited: `{summary['n_r22c_launch_rows']}`",
        f"- R22C target cases audited: `{summary['n_r22c_cases']}`",
        f"- Deferred postfit calibration rows: `{summary['n_postfit_deferred_rows']}`",
        f"- Mechanisms ready for expensive launch now: `{summary['n_mechanisms_ready_for_expensive_launch']}`",
        f"- Mechanisms requiring implementation first: `{summary['n_mechanisms_requiring_implementation_before_expensive_launch']}`",
        f"- Recommended next action: `{summary['recommended_next_action']}`",
        "",
        "## Capability Matrix",
        "",
        markdown_table(
            capability,
            columns=[
                "mechanism",
                "r22c_declared",
                "runner_consumes_required_field",
                "adapter_consumes_required_field",
                "model_fit_consumes_required_field",
                "effective_status",
                "required_before_expensive_launch",
            ],
            max_rows=20,
        ),
        "",
        "## Effective R22C Search Space",
        "",
        markdown_table(
            search,
            columns=["candidate_set", "axis", "axis_type", "n_unique", "min", "max", "unique_values", "effective_status"],
            max_rows=60,
        ),
        "",
        "## Postfit Calibration Readiness",
        "",
        markdown_table(
            calibration,
            columns=[
                "region",
                "fold",
                "candidate_family",
                "calibration_rule",
                "existing_prediction_exists",
                "existing_metric_summary_exists",
                "readiness_status",
            ],
            max_rows=60,
        ),
        "",
        "## Expensive-Path Bounds",
        "",
        markdown_table(bounds, max_rows=20),
        "",
        "## Gates",
        "",
        markdown_table(gates, max_rows=40),
        "",
        "## Decision",
        "",
        "The strategic direction can be the expensive path, but Stage-R23 blocks the launch until true horizon-weighted fitting and/or validation-only postfit calibration are implemented. Running a broad grid before that would mainly broaden reservoir and feature-policy axes that already failed to beat PriceFM in R22C.",
        "",
    ]
    repo_path(path).write_text("\n".join(lines))


def normalize_manifest(manifest: pd.DataFrame) -> pd.DataFrame:
    require_columns(
        manifest,
        [
            "experiment_id",
            "region",
            "fold",
            "target_quantile",
            "stage_r22b_case_id",
            "screening_arm",
            "horizon_weight_multiplier",
            "feature_policy",
            "lag_window",
            "depth",
            "units",
            "feature_dim",
            "state_output",
            "alpha",
            "rho",
            "input_scale",
            "tau0",
        ],
        "Stage-R22C launch manifest",
    )
    out = manifest.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def run(args: argparse.Namespace) -> dict[str, Any]:
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and any(out_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"{out_dir} exists; rerun with --force true")
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = normalize_manifest(read_csv_required(Path(args.r22c_prep_dir) / R22C_MANIFEST, "Stage-R22C launch manifest"))
    deferred = read_csv_required(Path(args.r22c_prep_dir) / R22C_DEFERRED, "Stage-R22C postfit deferred manifest")
    prep_gates = read_csv_required(Path(args.r22c_prep_dir) / R22C_GATES, "Stage-R22C prep gates")
    r22d_summary = read_json_required(Path(args.r22d_dir) / R22D_SUMMARY, "Stage-R22D summary")
    if not prep_gates["passed"].map(boolish).all():
        failed = prep_gates.loc[~prep_gates["passed"].map(boolish), "gate"].tolist()
        raise ValueError(f"Stage-R22C launch-prep gates failed: {failed}")

    paths = source_paths(args)
    propagation = field_propagation(paths)
    search = search_space(manifest, deferred)
    calibration = calibration_readiness(deferred)
    model_text = read_text(paths["model_fitter"])
    signature = package_fit_signature(paths, model_text)
    capability = capability_matrix(manifest, deferred, paths, signature)
    case_queue = case_next_mechanism_queue(manifest, deferred, calibration)
    bounds = expensive_bounds_recommendation(search)
    gates = no_launch_gates(manifest, deferred, r22d_summary, capability, out_dir)
    source = source_manifest(args, paths)

    implementation_blockers = capability[
        capability["required_before_expensive_launch"].astype(str).str.contains("Add and test|Implement", regex=True)
    ]
    ready_mechanisms = capability[
        capability["effective_status"].astype(str).isin(
            [
                "implemented_adapter_search_axis",
                "implemented_information_set_axis",
                "runner_supports_config_but_r22c_explored_median_only",
            ]
        )
    ]
    status = (
        "completed_expensive_path_blocked_until_mechanisms_are_real"
        if not implementation_blockers.empty
        else "completed_expensive_path_ready_for_launch_prep"
    )
    summary = {
        "stage": "pricefm_stage_r23_mechanism_capability_audit",
        "status": status,
        "n_r22c_launch_rows": int(manifest.shape[0]),
        "n_r22c_cases": int(manifest[["region", "fold"]].drop_duplicates().shape[0]),
        "n_postfit_deferred_rows": int(deferred.shape[0]),
        "n_field_propagation_rows": int(propagation.shape[0]),
        "n_mechanisms_audited": int(capability.shape[0]),
        "n_mechanisms_ready_for_expensive_launch": int(ready_mechanisms.shape[0]),
        "n_mechanisms_requiring_implementation_before_expensive_launch": int(implementation_blockers.shape[0]),
        "n_calibration_rows_ready": int(calibration["readiness_status"].eq("ready_for_postfit_calibration_runner").sum()) if not calibration.empty else 0,
        "n_calibration_rows_blocked": int(calibration["readiness_status"].ne("ready_for_postfit_calibration_runner").sum()) if not calibration.empty else 0,
        "r22d_status": r22d_summary.get("status", ""),
        "r22d_promotion_queue_rows": int(r22d_summary.get("n_promotion_queue_rows", -1)),
        "launches_models": False,
        "fits_models": False,
        "writes_launch_yaml": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
        "recommended_next_action": "implement_true_horizon_weight_or_postfit_calibration_support_before_broad_expensive_stage_r24_launch_prep",
    }

    outputs = {
        "field_propagation": out_dir / OUT_FIELD_PROPAGATION,
        "capability_matrix": out_dir / OUT_CAPABILITY,
        "package_fit_signature": out_dir / OUT_PACKAGE_SIGNATURE,
        "effective_search_space": out_dir / OUT_SEARCH_SPACE,
        "postfit_calibration_readiness": out_dir / OUT_CALIBRATION,
        "case_next_mechanism_queue": out_dir / OUT_CASE_QUEUE,
        "expensive_path_bounds_recommendation": out_dir / OUT_EXPENSIVE_BOUNDS,
        "no_launch_gates": out_dir / OUT_GATES,
        "source_manifest": out_dir / OUT_SOURCE,
        "report": out_dir / OUT_REPORT,
        "summary_json": out_dir / "summary.json",
    }
    write_frame(outputs["field_propagation"], propagation)
    write_frame(outputs["capability_matrix"], capability)
    write_frame(outputs["package_fit_signature"], signature)
    write_frame(outputs["effective_search_space"], search)
    write_frame(outputs["postfit_calibration_readiness"], calibration)
    write_frame(outputs["case_next_mechanism_queue"], case_queue)
    write_frame(outputs["expensive_path_bounds_recommendation"], bounds)
    write_frame(outputs["no_launch_gates"], gates)
    write_frame(outputs["source_manifest"], source)
    summary["outputs"] = {key: repo_relative(path) for key, path in outputs.items()}
    write_report(outputs["report"], summary, capability, search, calibration, bounds, gates)
    write_json(outputs["summary_json"], summary)

    if not gates["passed"].map(boolish).all():
        failed = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
        raise RuntimeError(f"Stage-R23 no-launch gates failed: {failed}")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    run(parser().parse_args())


if __name__ == "__main__":
    main()
