"""Helpers for the PriceFM full-surface benchmark closeout."""

from __future__ import annotations

import ast
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import load_config, pricefm_block, repo_path


PAPER_QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
PRICEFM_METHOD = "pricefm_phase1_pretraining"
QDESN_PREFIX = "qdesn_"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}

DEFAULT_CONFIG = "application/config/pricefm_data_pipeline.yaml"
DEFAULT_OUTPUT_AUDIT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_full_surface_readiness_audit_20260704"
)
DEFAULT_OUTPUT_CLOSEOUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_full_surface_decision_closeout_20260704"
)
DEFAULT_CURRENT_R3Q_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_coverage_quantiles_stage_r3q_decision_closeout_20260703"
)
DEFAULT_CURRENT_R3Q_REGISTRY = (
    DEFAULT_CURRENT_R3Q_DIR + "/coverage_quantile_decision_registry.csv"
)
DEFAULT_CURRENT_R3Q_COMPARISON_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_coverage_quantiles_priority0_comparison_fixed_20260702"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv"
)
DEFAULT_STAGE_M_QUANTILE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_quantile_decision_registry.csv"
)
DEFAULT_STAGE_M_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv"
)
DEFAULT_STAGE_M_COMPARABILITY_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_comparability_audit_20260624/summary.json"
)
DEFAULT_BRIDGE_ROWS = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_coverage_expansion_plan_20260701/paper_quantile_exists_not_stage_m_rows.csv"
)
DEFAULT_STAGE_B_BRIDGE_COMPARISON_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_cached_vs_stage_b_combined_promotion_rescue_20260617"
)
DEFAULT_REGION_PANEL_LOCAL_COMPARISON_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_region_panel_from_local_ar_20260613"
)
DEFAULT_REGION_PANEL_GRAPH_COMPARISON_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_region_panel_graph_local_20260614"
)


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full)


def read_json_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required JSON: {full}")
    with open(full, "r") as f:
        return json.load(f)


def read_csv_optional(path: str | Path) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(full)


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def repo_relative(path: str | Path) -> str:
    full = repo_path(path)
    root = repo_path(".")
    try:
        return str(full.relative_to(root))
    except ValueError:
        return str(full)


def sha256_file_or_blank(path: str | Path) -> str:
    full = repo_path(path)
    if not full.exists() or not full.is_file():
        return ""
    h = hashlib.sha256()
    with open(full, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def finite_float(value: Any) -> float:
    if value is None or pd.isna(value):
        return float("nan")
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return out if math.isfinite(out) else float("nan")


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None or pd.isna(value):
        return False
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed"}


def first_nonblank(row: pd.Series, names: list[str], default: Any = "") -> Any:
    for name in names:
        if name not in row.index:
            continue
        value = row[name]
        if pd.notna(value) and str(value).strip() != "":
            return value
    return default


def parse_jsonish(value: Any) -> Any:
    if isinstance(value, (list, tuple, dict)):
        return value
    if value is None or pd.isna(value):
        return None
    text = str(value).strip()
    if not text:
        return None
    for parser in (json.loads, ast.literal_eval):
        try:
            return parser(text)
        except (ValueError, SyntaxError, TypeError, json.JSONDecodeError):
            continue
    return text


def quantile_set(value: Any) -> set[float]:
    parsed = parse_jsonish(value)
    if parsed is None:
        return set()
    if not isinstance(parsed, (list, tuple, set)):
        parsed = [parsed]
    out = set()
    for val in parsed:
        try:
            out.add(round(float(val), 4))
        except (TypeError, ValueError):
            return set()
    return out


def expected_quantile_set() -> set[float]:
    return {round(float(x), 4) for x in PAPER_QUANTILES}


def configured_cells(config: str | Path = DEFAULT_CONFIG) -> pd.DataFrame:
    cfg = load_config(config)
    spec = pricefm_block(cfg)
    rows = [
        {"region": str(region), "fold": int(split["fold"])}
        for region in spec["regions"]
        for split in spec["splits"]
    ]
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def normalize_keys(frame: pd.DataFrame, label: str, unique: bool = True) -> pd.DataFrame:
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    if unique and out.duplicated(["region", "fold"]).any():
        dupes = (
            out.loc[out.duplicated(["region", "fold"], keep=False), ["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError(f"{label} has duplicate region/fold keys: {dupes}")
    return out


def window_dir_for(config: str | Path, region: str, fold: int) -> Path:
    cfg = load_config(config)
    spec = pricefm_block(cfg)
    return repo_path(Path(spec["processed_dir"]) / "windows" / f"fold_{int(fold)}" / f"region={region}")


def window_present(config: str | Path, region: str, fold: int) -> bool:
    path = window_dir_for(config, region, fold)
    return path.exists() and any(path.iterdir())


def comparison_status_complete(root: str | Path) -> bool:
    status = read_csv_optional(Path(root) / "region_panel_comparison_status.csv")
    if status.empty or "status" not in status.columns:
        return False
    return status["status"].astype(str).eq("completed").all()


def row_alignment_complete(root: str | Path) -> bool:
    align = read_csv_optional(Path(root) / "panel_row_alignment.csv")
    if align.empty:
        return False
    pairs = [
        ("available_prediction_rows", "aligned_prediction_rows"),
        ("available_unique_response_rows", "aligned_unique_response_rows"),
    ]
    for left, right in pairs:
        if left in align.columns and right in align.columns:
            if not (pd.to_numeric(align[left], errors="coerce") == pd.to_numeric(align[right], errors="coerce")).all():
                return False
    return True


def binary_artifact_count(root: str | Path) -> int:
    full = repo_path(root)
    if not full.exists():
        return 0
    return sum(1 for path in full.rglob("*") if path.is_file() and path.suffix in BINARY_SUFFIXES)


def panel_metric(root: str | Path) -> pd.DataFrame:
    metric = read_csv_required(Path(root) / "panel_metric.csv", "panel metric")
    require_columns(metric, ["region", "fold", "method_id", "split", "unit", "AQL"], "panel metric")
    out = normalize_keys(metric, "panel metric", unique=False)
    out["method_id"] = out["method_id"].astype(str)
    out["split"] = out["split"].astype(str)
    out["unit"] = out["unit"].astype(str)
    out["AQL"] = pd.to_numeric(out["AQL"], errors="coerce")
    return out


def metric_value(metric: pd.DataFrame, region: str, fold: int, method_id: str, column: str = "AQL") -> float:
    rows = metric[
        metric["region"].astype(str).eq(str(region))
        & metric["fold"].astype(int).eq(int(fold))
        & metric["method_id"].astype(str).eq(str(method_id))
        & metric["split"].astype(str).eq("test")
        & metric["unit"].astype(str).eq("original")
    ].copy()
    if rows.empty or column not in rows.columns:
        return float("nan")
    vals = pd.to_numeric(rows[column], errors="coerce").dropna()
    if vals.empty:
        return float("nan")
    return float(vals.iloc[0])


def method_available(metric: pd.DataFrame, region: str, fold: int, method_id: str) -> bool:
    return math.isfinite(metric_value(metric, region, fold, method_id))


def q30_metric_root(row: pd.Series) -> str:
    source = str(row.get("primary_median_source", ""))
    policy = str(row.get("primary_median_feature_policy", row.get("feature_policy", ""))).lower()
    spatial = str(row.get("primary_median_spatial_information_set", "")).lower()
    if "stage_b_decision_registry" in source:
        return DEFAULT_STAGE_B_BRIDGE_COMPARISON_DIR
    if "graph" in policy or "graph" in spatial:
        return DEFAULT_REGION_PANEL_GRAPH_COMPARISON_DIR
    return DEFAULT_REGION_PANEL_LOCAL_COMPARISON_DIR


def primary_median_registry_row(row: pd.Series) -> pd.Series | None:
    source = str(row.get("primary_median_source", ""))
    if not source:
        return None
    path = repo_path(source)
    if not path.exists():
        return None
    try:
        frame = normalize_keys(pd.read_csv(path), source, unique=False)
    except Exception:
        return None
    region = str(row["region"])
    fold = int(row["fold"])
    exp = str(row.get("primary_median_experiment_id", ""))
    method = str(row.get("primary_median_method", ""))
    candidates = frame[frame["region"].eq(region) & frame["fold"].eq(fold)].copy()
    if candidates.empty:
        return None
    exp_match = pd.Series(False, index=candidates.index)
    for col in ["experiment_id", "primary_median_experiment_id", "run_id"]:
        if col in candidates.columns:
            exp_match = exp_match | candidates[col].astype(str).eq(exp)
    method_match = pd.Series(False, index=candidates.index)
    for col in ["selected_method_id", "best_local_method", "primary_median_method"]:
        if col in candidates.columns:
            method_match = method_match | candidates[col].astype(str).eq(method)
    matches = candidates[exp_match | method_match].copy()
    if matches.empty:
        return candidates.iloc[0]
    return matches.iloc[0]


def validation_selection_evidence(row: pd.Series | None) -> bool:
    if row is None:
        return False
    selected_on_split = str(first_nonblank(row, ["selected_on_split", "selected_on_split_median_registry"], "")).lower()
    if selected_on_split == "val":
        return True
    if boolish(first_nonblank(row, ["selection_is_validation_only", "selection_is_validation_only_median_registry"], False)):
        return True
    final_decision = str(first_nonblank(row, ["final_decision"], "")).lower()
    return "validation" in final_decision


def decision_label(delta_abs: float, delta_rel: float, close_threshold_rel: float = 0.05) -> str:
    if delta_abs <= 0.0:
        return "qdesn_wins"
    if math.isfinite(delta_rel) and delta_rel <= close_threshold_rel:
        return "qdesn_close"
    return "pricefm_wins"


def article_recommendation(label: str) -> str:
    if label == "qdesn_wins":
        return "promote_qdesn"
    if label == "qdesn_close":
        return "candidate_qdesn"
    return "pricefm_reference"


def rescue_tier(delta_abs: float, delta_rel: float, label: str) -> str:
    if label == "qdesn_wins":
        return "none"
    if label == "qdesn_close":
        return "monitor"
    if delta_abs >= 0.75 or (math.isfinite(delta_rel) and delta_rel >= 0.10):
        return "priority0"
    return "priority1"


def feature_information_set(row: pd.Series) -> str:
    text = " ".join(
        str(first_nonblank(row, [name], ""))
        for name in [
            "feature_policy",
            "input_scope",
            "spatial_information_set",
            "primary_median_feature_policy",
            "primary_median_spatial_information_set",
        ]
    ).lower()
    if "graph" in text:
        return "graph"
    if "target" in text or "local" in text:
        return "target_only"
    return "unknown"
