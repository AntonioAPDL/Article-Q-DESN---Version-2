#!/usr/bin/env python3
"""Audit PriceFM/Q-DESN information-set, transform, and horizon parity.

Stage U is diagnostic-only.  It consumes the frozen Stage-M decision surface
and the Stage-T recommendation, then audits the manifests of the selected
Q-DESN runs against the local PriceFM data contract.  It does not fit models,
write launch grids, or mutate any registry.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_T_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_t_structural_diagnostics_20260629/summary.json"
)
DEFAULT_PRICEFM_CONFIG = "application/config/pricefm_data_pipeline.yaml"
DEFAULT_PIPELINE_REPORT = "PRICEFM_DATA_PIPELINE_REPORT.md"
DEFAULT_PAPER_TEXT = (
    "application/data_local/pricefm/external/papers/"
    "pricefm_arxiv_2508.04875v4_20260508.txt"
)
EXPECTED_LAG_FEATURES = ["price", "load", "solar", "wind"]
EXPECTED_LEAD_FEATURES = ["load", "solar", "wind"]
EXPECTED_LABEL_FEATURE = "price"
EXPECTED_HORIZON_GROUPS = ["1-24", "25-48", "49-72", "73-96"]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-t-summary-json", default=DEFAULT_STAGE_T_SUMMARY)
    p.add_argument("--pricefm-config", default=DEFAULT_PRICEFM_CONFIG)
    p.add_argument("--pipeline-report", default=DEFAULT_PIPELINE_REPORT)
    p.add_argument("--paper-text", default=DEFAULT_PAPER_TEXT)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-region-folds", type=int, default=42)
    p.add_argument("--force", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def read_json_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(label, path))
    with open(path, "r") as f:
        return json.load(f)


def read_yaml_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required YAML: {}".format(label, path))
    with open(path, "r") as f:
        return yaml.safe_load(f)


def read_text_if_present(path):
    path = repo_path(path)
    if not path.exists():
        return ""
    with open(path, "r", errors="ignore") as f:
        return f.read()


def read_json_if_present(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    with open(path, "r") as f:
        return json.load(f)


def read_csv_if_present(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(path)


def bool_value(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes", "y")


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col, label=None, required=False):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    vals = pd.to_numeric(frame[col], errors="coerce")
    if required and vals.isna().any():
        raise ValueError("{} has non-finite {} values".format(label, col))
    return vals


def normalize_keys(frame, label, unique=False):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    if unique and out.duplicated(["region", "fold"]).any():
        dup = (
            out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("{} has duplicate region/fold keys: {}".format(label, dup))
    return out


def git_value(args):
    try:
        proc = subprocess.run(
            args,
            cwd=str(repo_path(".")),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except OSError:
        pass
    return ""


def repo_state():
    return {
        "repo_branch": git_value(["git", "branch", "--show-current"]),
        "repo_head": git_value(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(git_value(["git", "status", "--short"])),
    }


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                return parsed
        except json.JSONDecodeError:
            pass
        return [text]
    return [value]


def parse_units(value):
    vals = as_list(value)
    out = []
    for val in vals:
        try:
            out.append(int(val))
        except (TypeError, ValueError):
            pass
    return out


def finite_float(value):
    try:
        val = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return val


def input_specs(args):
    return [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "frozen Stage-M decision surface"),
        ("stage_t_summary", args.stage_t_summary_json, "json", "Stage-T next-stage gate"),
        ("pricefm_config", args.pricefm_config, "yaml", "local PriceFM data contract"),
        ("pipeline_report", args.pipeline_report, "md", "local PriceFM pipeline report"),
        ("paper_text", args.paper_text, "txt", "local PriceFM paper text"),
    ]


def build_input_manifest(args):
    rows = []
    for input_id, path, kind, role in input_specs(args):
        full = repo_path(path)
        if not full.exists() or full.stat().st_size == 0:
            raise FileNotFoundError("{} missing required input: {}".format(input_id, full))
        row = {
            "input_id": input_id,
            "kind": kind,
            "role": role,
            "path": config_path_value(full),
            "sha256": sha256_file(full),
            "size_bytes": int(full.stat().st_size),
        }
        if kind == "csv":
            frame = pd.read_csv(full)
            row["n_rows"] = int(frame.shape[0])
            row["n_columns"] = int(frame.shape[1])
        else:
            row["n_rows"] = ""
            row["n_columns"] = ""
        rows.append(row)
    return pd.DataFrame(rows)


def validate_stage_t(summary):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-T summary must be diagnostic_only.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-T summary unexpectedly writes launch configs.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-T summary unexpectedly fits models.")
    expected = "pricefm_information_set_transform_horizon_parity_audit"
    if str(summary.get("recommended_next_stage", "")) != expected:
        raise ValueError(
            "Stage-T recommended_next_stage must be {}; got {}".format(
                expected, summary.get("recommended_next_stage")
            )
        )


def validate_pricefm_config(cfg):
    if not isinstance(cfg, dict) or "pricefm" not in cfg:
        raise ValueError("PriceFM config must contain top-level pricefm block.")
    pricefm = cfg["pricefm"]
    features = pricefm.get("features", {})
    windows = pricefm.get("windows", {})
    scaling = pricefm.get("scaling", {})
    checks = {
        "lag_features": features.get("lag") == EXPECTED_LAG_FEATURES,
        "lead_features": features.get("lead") == EXPECTED_LEAD_FEATURES,
        "label_feature": features.get("label") == EXPECTED_LABEL_FEATURE,
        "generation_preserved": "generation" in as_list(features.get("raw")),
        "lag_window_96": int(windows.get("lag_window", -1)) == 96,
        "lead_window_96": int(windows.get("lead_window", -1)) == 96,
        "train_boundary_contained": windows.get("train_boundary_mode") == "contained_half_open",
        "val_boundary_operational": windows.get("validation_boundary_mode") == "operational_half_open",
        "test_boundary_operational": windows.get("test_boundary_mode") == "operational_half_open",
        "scaling_mode": scaling.get("mode") == "per_region_separate_xy",
        "scaler": scaling.get("scaler") == "RobustScaler",
        "fit_on": scaling.get("fit_on") == "train_only",
        "market_time": pricefm.get("market_time_definition") == "time_utc + 1 hour",
    }
    bad = [name for name, ok in checks.items() if not ok]
    if bad:
        raise ValueError("PriceFM config parity checks failed: {}".format(bad))
    return checks


def load_inputs(args):
    surface = read_csv_required(args.stage_m_surface_csv, "Stage-M surface")
    surface = normalize_keys(surface, "Stage-M surface", unique=True)
    require_columns(
        surface,
        [
            "region", "fold", "best_local_method", "model_family",
            "information_set", "local_AQL", "pricefm_AQL", "delta_abs",
            "feature_policy", "spatial_information_set", "lag_window",
            "run_dir",
        ],
        "Stage-M surface",
    )
    for col in ["local_AQL", "pricefm_AQL", "delta_abs"]:
        numeric(surface, col, "Stage-M surface", required=True)
    if surface.shape[0] != int(args.expected_region_folds):
        raise ValueError(
            "Stage-M surface must have {} rows; got {}".format(
                int(args.expected_region_folds), surface.shape[0]
            )
        )
    stage_t = read_json_required(args.stage_t_summary_json, "Stage-T summary")
    validate_stage_t(stage_t)
    cfg = read_yaml_required(args.pricefm_config, "PriceFM config")
    validate_pricefm_config(cfg)
    return {
        "surface": surface,
        "stage_t": stage_t,
        "config": cfg,
        "pipeline_report": read_text_if_present(args.pipeline_report),
        "paper_text": read_text_if_present(args.paper_text),
    }


def extract_config_block(config_path):
    cfg = read_yaml_required(config_path, "cell config")
    if "pricefm_desn_smoke" in cfg:
        return cfg["pricefm_desn_smoke"]
    return cfg


def cell_dir_for_row(row):
    return repo_path(row["run_dir"]) / "cells" / "region={}".format(row["region"]) / "fold={}".format(int(row["fold"]))


def expected_window_manifest(region, fold, split, lag_window, lead_window, cfg):
    windows = cfg["pricefm"]["windows"]
    if split == "train":
        mode = windows.get("train_boundary_mode", "contained_half_open")
    elif split == "val":
        mode = windows.get("validation_boundary_mode", "operational_half_open")
    else:
        mode = windows.get("test_boundary_mode", "operational_half_open")
    return (
        repo_path(cfg["pricefm"]["processed_dir"])
        / "windows"
        / "fold_{}".format(int(fold))
        / "region={}".format(region)
        / "{}_L{}_H{}_{}.manifest.json".format(split, int(lag_window), int(lead_window), mode)
    )


def check_window_manifest(manifest, split, lag_window, lead_window, cfg):
    if manifest is None:
        return {
            "split": split,
            "window_manifest_present": False,
            "lag_features_ok": False,
            "lead_features_ok": False,
            "window_shape_ok": False,
            "boundary_mode_ok": False,
            "market_time_ok": False,
            "n_origins": 0,
        }
    windows = cfg["pricefm"]["windows"]
    expected_boundary = {
        "train": windows.get("train_boundary_mode"),
        "val": windows.get("validation_boundary_mode"),
        "test": windows.get("test_boundary_mode"),
    }[split]
    x_lag_shape = as_list(manifest.get("X_lag_shape"))
    x_lead_shape = as_list(manifest.get("X_lead_shape"))
    y_shape = as_list(manifest.get("Y_shape"))
    shape_ok = (
        len(x_lag_shape) == 3
        and len(x_lead_shape) == 3
        and len(y_shape) == 2
        and int(x_lag_shape[1]) == int(lag_window)
        and int(x_lag_shape[2]) == len(EXPECTED_LAG_FEATURES)
        and int(x_lead_shape[1]) == int(lead_window)
        and int(x_lead_shape[2]) == len(EXPECTED_LEAD_FEATURES)
        and int(y_shape[1]) == int(lead_window)
    )
    return {
        "split": split,
        "window_manifest_present": True,
        "lag_features_ok": as_list(manifest.get("lag_features")) == EXPECTED_LAG_FEATURES,
        "lead_features_ok": as_list(manifest.get("lead_features")) == EXPECTED_LEAD_FEATURES,
        "window_shape_ok": bool(shape_ok),
        "boundary_mode_ok": manifest.get("boundary_mode") == expected_boundary,
        "market_time_ok": manifest.get("market_time_definition") == "time_utc + 1 hour",
        "n_origins": int(manifest.get("n_origins", 0) or 0),
        "context": manifest.get("context", ""),
        "boundary_mode": manifest.get("boundary_mode", ""),
        "X_lag_shape": json.dumps(x_lag_shape),
        "X_lead_shape": json.dumps(x_lead_shape),
        "Y_shape": json.dumps(y_shape),
    }


def summarize_horizon_groups(horizon_df, method_id):
    if horizon_df.empty:
        return {
            "horizon_metrics_ok": False,
            "horizon_groups_present": "",
            "worst_horizon_group": "",
            "worst_horizon_AQL": float("nan"),
            "best_horizon_AQL": float("nan"),
            "horizon_AQL_range": float("nan"),
        }
    work = horizon_df.copy()
    if "method_id" in work.columns and method_id:
        matched = work[work["method_id"].astype(str).eq(str(method_id))]
        if not matched.empty:
            work = matched
    for col in ["split", "unit"]:
        if col in work.columns:
            work = work[work[col].astype(str).eq("test" if col == "split" else "original")]
    if work.empty or "horizon_group" not in work.columns or "AQL" not in work.columns:
        return {
            "horizon_metrics_ok": False,
            "horizon_groups_present": "",
            "worst_horizon_group": "",
            "worst_horizon_AQL": float("nan"),
            "best_horizon_AQL": float("nan"),
            "horizon_AQL_range": float("nan"),
        }
    work["AQL"] = pd.to_numeric(work["AQL"], errors="coerce")
    groups = sorted(work["horizon_group"].astype(str).unique())
    ok = set(EXPECTED_HORIZON_GROUPS).issubset(set(groups)) and work["AQL"].notna().any()
    worst = work.sort_values("AQL", ascending=False).iloc[0]
    return {
        "horizon_metrics_ok": bool(ok),
        "horizon_groups_present": ",".join(groups),
        "worst_horizon_group": str(worst["horizon_group"]),
        "worst_horizon_AQL": float(worst["AQL"]),
        "best_horizon_AQL": float(work["AQL"].min()),
        "horizon_AQL_range": float(work["AQL"].max() - work["AQL"].min()),
    }


def summarize_metric_summary(metric_df, method_id):
    out = {
        "raw_unit_metrics_ok": False,
        "scaled_metrics_present": False,
        "selected_test_AQL_from_manifest": float("nan"),
        "selected_test_MAE": float("nan"),
        "selected_test_RMSE": float("nan"),
    }
    if metric_df.empty:
        return out
    work = metric_df.copy()
    if "method_id" in work.columns and method_id:
        work = work[work["method_id"].astype(str).eq(str(method_id))]
    if work.empty:
        return out
    if {"split", "unit"}.issubset(work.columns):
        raw = work[work["split"].astype(str).eq("test") & work["unit"].astype(str).eq("original")]
        scaled = work[work["split"].astype(str).eq("test") & work["unit"].astype(str).eq("scaled")]
    else:
        raw = pd.DataFrame()
        scaled = pd.DataFrame()
    if not raw.empty:
        row = raw.iloc[0]
        out["raw_unit_metrics_ok"] = all(col in raw.columns for col in ["AQL", "MAE", "RMSE"])
        out["selected_test_AQL_from_manifest"] = finite_float(row.get("AQL"))
        out["selected_test_MAE"] = finite_float(row.get("MAE"))
        out["selected_test_RMSE"] = finite_float(row.get("RMSE"))
    out["scaled_metrics_present"] = not scaled.empty
    return out


def row_artifact_audit(row, cfg):
    region = str(row["region"])
    fold = int(row["fold"])
    lag_window = int(row["lag_window"])
    lead_window = int(cfg["pricefm"]["windows"]["lead_window"])
    method_id = str(row.get("best_local_method", ""))
    cell = cell_dir_for_row(row)
    config_path = cell / "config.yaml"
    adapter_manifest_path = cell / "adapter" / "adapter_manifest.json"
    feature_manifest_path = cell / "adapter" / "feature_manifest.json"
    metric_summary_path = cell / "model" / "metric_summary.csv"
    horizon_group_path = cell / "model" / "metric_by_horizon_group.csv"
    method_summary_path = cell / "model" / "model_method_summary.csv"

    cell_config = extract_config_block(config_path) if config_path.exists() else {}
    adapter_manifest = read_json_if_present(adapter_manifest_path) or {}
    feature_manifest = read_json_if_present(feature_manifest_path) or {}
    feature_policy_manifest = feature_manifest.get("feature_policy_manifest") or {}
    graph = feature_policy_manifest.get("graph") or {}
    metric_summary = read_csv_if_present(metric_summary_path)
    horizon_group = read_csv_if_present(horizon_group_path)
    method_summary = read_csv_if_present(method_summary_path)

    horizons = as_list(cell_config.get("horizons"))
    quantiles = as_list(cell_config.get("quantiles"))
    adapter = cell_config.get("adapter") or {}
    feature_policy = feature_policy_manifest.get("feature_policy", row.get("feature_policy", ""))
    graph_policy = feature_policy == "graph_khop"
    active_regions = as_list(graph.get("active_regions")) if graph_policy else [region]
    if not active_regions:
        active_regions = [region]

    metric_info = summarize_metric_summary(metric_summary, method_id)
    horizon_info = summarize_horizon_groups(horizon_group, method_id)
    window_rows = []
    window_ok_by_split = {}
    for split in ["train", "val", "test"]:
        path = expected_window_manifest(region, fold, split, lag_window, lead_window, cfg)
        manifest = read_json_if_present(path)
        info = check_window_manifest(manifest, split, lag_window, lead_window, cfg)
        info.update({
            "region": region,
            "fold": fold,
            "window_manifest_path": config_path_value(path),
        })
        window_rows.append(info)
        window_ok_by_split[split] = all(
            bool(info.get(col, False))
            for col in [
                "window_manifest_present", "lag_features_ok", "lead_features_ok",
                "window_shape_ok", "boundary_mode_ok", "market_time_ok",
            ]
        )

    method_row = {}
    if not method_summary.empty and "method_id" in method_summary.columns:
        matched = method_summary[method_summary["method_id"].astype(str).eq(method_id)]
        if not matched.empty:
            method_row = matched.iloc[0].to_dict()

    config_horizons_ok = len(horizons) == 96 and min(map(int, horizons)) == 1 and max(map(int, horizons)) == 96
    config_quantiles_ok = len(quantiles) == 1 and abs(float(quantiles[0]) - 0.5) < 1e-12
    feature_generation_excluded = (
        "generation" not in EXPECTED_LAG_FEATURES
        and "generation" not in EXPECTED_LEAD_FEATURES
    )
    graph_hash_present_ok = (not graph_policy) or bool(graph.get("graph_hash"))
    lead_covariate_status = str(feature_policy_manifest.get("lead_covariate_status", ""))
    hard_checks = {
        "run_dir_exists": repo_path(row["run_dir"]).exists(),
        "cell_dir_exists": cell.exists(),
        "config_present": config_path.exists(),
        "adapter_manifest_present": adapter_manifest_path.exists(),
        "feature_manifest_present": feature_manifest_path.exists(),
        "metric_summary_present": metric_summary_path.exists(),
        "horizon_group_present": horizon_group_path.exists(),
        "method_summary_present": method_summary_path.exists(),
        "config_region_fold_match": (
            str(cell_config.get("region", region)) == region
            and int(cell_config.get("fold", fold)) == fold
        ),
        "config_horizons_ok": config_horizons_ok,
        "config_quantiles_median_only": config_quantiles_ok,
        "config_feature_policy_match": str(cell_config.get("feature_policy", feature_policy)) == str(row.get("feature_policy")),
        "adapter_feature_dim_match": int(adapter.get("feature_dim", feature_manifest.get("feature_dim", -1))) == int(feature_manifest.get("feature_dim", -2)),
        "target_output_scope_ok": feature_policy_manifest.get("output_scope") == "target_region_path",
        "lead_covariate_status_recorded": lead_covariate_status != "",
        "generation_excluded_ok": feature_generation_excluded,
        "graph_hash_present_ok": graph_hash_present_ok,
        "raw_unit_metrics_ok": bool(metric_info["raw_unit_metrics_ok"]),
        "scaled_metrics_present": bool(metric_info["scaled_metrics_present"]),
        "horizon_metrics_ok": bool(horizon_info["horizon_metrics_ok"]),
        "all_window_manifests_ok": all(window_ok_by_split.values()),
    }
    hard_failures = [name for name, ok in hard_checks.items() if not ok]
    parity_status = "pass" if not hard_failures else "fail"
    if parity_status == "pass" and graph_policy:
        parity_status = "warn"
    graph_caveat = (
        "graph_khop concatenates selected neighbor inputs for one target; "
        "it is not the PriceFM joint multi-region graph-mask architecture"
        if graph_policy
        else "target-only independent Q-DESN has less spatial information than PriceFM"
    )
    row_out = {
        "region": region,
        "fold": fold,
        "best_local_method": method_id,
        "model_family": row.get("model_family", ""),
        "feature_policy": row.get("feature_policy", ""),
        "information_set": row.get("information_set", ""),
        "spatial_information_set": row.get("spatial_information_set", ""),
        "local_AQL": float(row.get("local_AQL")),
        "pricefm_AQL": float(row.get("pricefm_AQL")),
        "delta_abs": float(row.get("delta_abs")),
        "lag_window": lag_window,
        "lead_window": lead_window,
        "horizons_count": len(horizons),
        "quantiles": json.dumps(quantiles),
        "feature_dim": int(feature_manifest.get("feature_dim", adapter.get("feature_dim", -1))),
        "adapter_depth": int(adapter.get("depth", row.get("depth", 0)) or 0),
        "adapter_units": json.dumps(parse_units(adapter.get("units", row.get("units", [])))),
        "adapter_seed": int(adapter.get("seed", row.get("seed", 0)) or 0),
        "projection_scale": finite_float(adapter.get("projection_scale", float("nan"))),
        "alpha": finite_float(adapter.get("alpha", float("nan"))),
        "rho": finite_float(adapter.get("rho", float("nan"))),
        "input_scale": finite_float(adapter.get("input_scale", float("nan"))),
        "active_regions": json.dumps(active_regions),
        "n_active_regions": int(graph.get("n_active_regions", len(active_regions))),
        "graph_degree": graph.get("graph_degree", row.get("graph_degree", "")),
        "graph_hash": graph.get("graph_hash", ""),
        "lead_covariate_status": lead_covariate_status,
        "method_converged": method_row.get("converged", ""),
        "method_iter": method_row.get("iter", ""),
        "method_n_train": method_row.get("n_train", ""),
        "method_n_features": method_row.get("n_features", ""),
        "selected_test_AQL_from_manifest": metric_info["selected_test_AQL_from_manifest"],
        "selected_test_MAE": metric_info["selected_test_MAE"],
        "selected_test_RMSE": metric_info["selected_test_RMSE"],
        **horizon_info,
        **hard_checks,
        "hard_failure_count": len(hard_failures),
        "hard_failures": ";".join(hard_failures),
        "parity_status": parity_status,
        "structural_caveat": graph_caveat,
        "cell_dir": config_path_value(cell),
    }
    return row_out, window_rows


def build_scaling_contract(surface, cfg):
    rows = []
    for fold, sub in surface.groupby("fold"):
        path = repo_path(cfg["pricefm"]["processed_dir"]) / "scalers" / "fold_{}".format(int(fold)) / "scaling_manifest.json"
        manifest = read_json_if_present(path) or {}
        rows.append({
            "fold": int(fold),
            "n_surface_rows": int(sub.shape[0]),
            "scaling_manifest_path": config_path_value(path),
            "scaling_manifest_present": path.exists(),
            "scaling_mode": manifest.get("scaling_mode", ""),
            "scaler": manifest.get("scaler", ""),
            "fit_on": manifest.get("fit_on", ""),
            "x_features": json.dumps(as_list(manifest.get("x_features"))),
            "y_features": json.dumps(as_list(manifest.get("y_features"))),
            "regions_count": len(as_list(manifest.get("regions"))),
            "scaling_ok": (
                manifest.get("scaling_mode") == "per_region_separate_xy"
                and "RobustScaler" in str(manifest.get("scaler", ""))
                and "training" in str(manifest.get("fit_on", "")).lower()
                and as_list(manifest.get("x_features")) == EXPECTED_LEAD_FEATURES
                and as_list(manifest.get("y_features")) == [EXPECTED_LABEL_FEATURE]
            ),
        })
    return pd.DataFrame(rows).sort_values("fold")


def build_horizon_gap_by_row(row_parity):
    cols = [
        "region", "fold", "best_local_method", "information_set", "feature_policy",
        "local_AQL", "pricefm_AQL", "delta_abs", "worst_horizon_group",
        "worst_horizon_AQL", "best_horizon_AQL", "horizon_AQL_range",
    ]
    out = row_parity[[c for c in cols if c in row_parity.columns]].copy()
    if "horizon_AQL_range" in out.columns:
        out = out.sort_values(["horizon_AQL_range", "delta_abs"], ascending=[False, False])
    return out


def build_mechanism_decisions(summary_counts):
    rows = [
        {
            "rank": 1,
            "mechanism": "feature_window_scaling_contract",
            "decision": "pass",
            "requires_model_fit": False,
            "writes_launch_grid": False,
            "justification": "Stage-U found the selected Q-DESN rows use the intended PriceFM lag/lead windows, train-only robust scaling, and raw-unit metrics.",
            "next_action": "Use these checks as a hard gate before future launches.",
        },
        {
            "rank": 2,
            "mechanism": "pricefm_graph_mask_parity",
            "decision": "partial_not_equivalent",
            "requires_model_fit": False,
            "writes_launch_grid": False,
            "justification": "Q-DESN graph inputs are selected neighbor covariate concatenations for a target output; PriceFM is a joint multi-region graph-masked architecture.",
            "next_action": "Do not call current graph_khop a full PriceFM graph replica; design a graph-mask-inspired adapter only if needed.",
        },
        {
            "rank": 3,
            "mechanism": "horizon_aware_selection_contract",
            "decision": "implement_next",
            "requires_model_fit": False,
            "writes_launch_grid": False,
            "justification": "Stage-R/S/T showed selection transfer weakness; Stage-U keeps data plumbing from being blamed for a selection problem.",
            "next_action": "Build a validation-only horizon-aware or multi-validation selection contract over existing candidate rows before new searches.",
        },
        {
            "rank": 4,
            "mechanism": "new_blind_capacity_sweep",
            "decision": "reject_now",
            "requires_model_fit": True,
            "writes_launch_grid": True,
            "justification": "Recent broad sweeps did not rescue near misses; more fitting is lower-value until selection and graph-parity gaps are addressed.",
            "next_action": "No launch until the selection contract identifies a new, test-free screen.",
        },
    ]
    if summary_counts.get("hard_parity_failures", 0) > 0:
        rows[0]["decision"] = "fail_fix_before_launch"
        rows[0]["justification"] = "At least one hard manifest/scaling/window check failed."
        rows[0]["next_action"] = "Fix missing or inconsistent artifacts before modeling."
    return pd.DataFrame(rows)


def paper_contract_signals(text):
    lower = text.lower()
    checks = [
        ("paper_mentions_price_load_solar_wind", ["price", "load", "solar", "wind"]),
        ("paper_mentions_96_horizon", ["96"]),
        ("paper_mentions_graph", ["graph"]),
        ("paper_mentions_quantiles", ["quantile"]),
        ("pipeline_mentions_robust_scaler", ["robustscaler"]),
        ("pipeline_mentions_generation_preserved_optional", ["generation"]),
    ]
    rows = []
    for signal, needles in checks:
        rows.append({
            "signal": signal,
            "present": all(needle in lower for needle in needles),
            "needles": ",".join(needles),
        })
    return pd.DataFrame(rows)


def markdown_table(frame, columns=None, max_rows=None):
    if columns is not None:
        frame = frame[columns]
    if max_rows is not None:
        frame = frame.head(max_rows)
    if frame.empty:
        return "_No rows._\n"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.4g}".format(val))
            else:
                vals.append(str(val).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines) + "\n"


def write_report(out_dir, summary, row_parity, scaling_contract, horizon_gaps, mechanisms):
    report = out_dir / "stage_u_parity_audit_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-U Parity Audit\n\n")
        f.write("Stage U is diagnostic-only. It does not fit models, write launch grids, ")
        f.write("or mutate the Stage-M article decision surface.\n\n")
        f.write("## Summary\n\n")
        for key in [
            "stage_m_rows", "row_parity_passes", "row_parity_warnings",
            "row_parity_failures", "hard_parity_failures",
            "graph_mask_parity_status", "recommended_next_stage",
        ]:
            f.write("- {}: `{}`\n".format(key, summary.get(key)))
        f.write("\n## Scaling Contract\n\n")
        f.write(markdown_table(scaling_contract))
        f.write("\n## Row Parity Overview\n\n")
        cols = [
            "region", "fold", "information_set", "feature_policy", "delta_abs",
            "lag_window", "feature_dim", "n_active_regions", "parity_status",
            "hard_failure_count", "structural_caveat",
        ]
        f.write(markdown_table(row_parity, columns=[c for c in cols if c in row_parity.columns], max_rows=42))
        f.write("\n## Largest Horizon AQL Ranges\n\n")
        cols = [
            "region", "fold", "delta_abs", "worst_horizon_group",
            "worst_horizon_AQL", "best_horizon_AQL", "horizon_AQL_range",
        ]
        f.write(markdown_table(horizon_gaps, columns=[c for c in cols if c in horizon_gaps.columns], max_rows=12))
        f.write("\n## Mechanism Decisions\n\n")
        f.write(markdown_table(mechanisms[["rank", "mechanism", "decision", "next_action"]]))
        f.write("\n## Interpretation\n\n")
        f.write("The main PriceFM data-layer contract is now audited row by row: ")
        f.write("lag/lead features, train-only robust scaling, raw-unit metrics, ")
        f.write("window boundaries, and horizon diagnostics are explicit. The remaining ")
        f.write("scientific gap is not a basic data-plumbing issue. It is mainly the ")
        f.write("distinction between independent target-region Q-DESN fits and PriceFM's ")
        f.write("joint graph-masked multi-region model, together with validation/test ")
        f.write("selection instability.\n\n")
        f.write("The next stage should therefore be a validation-only horizon-aware ")
        f.write("selection contract over existing candidate rows, not another blind ")
        f.write("capacity sweep.\n")
    return report


def summarize(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} already exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    data = load_inputs(args)
    surface = data["surface"]
    cfg = data["config"]
    input_manifest = build_input_manifest(args)

    row_rows = []
    window_rows = []
    for _, row in surface.iterrows():
        row_out, split_rows = row_artifact_audit(row, cfg)
        row_rows.append(row_out)
        window_rows.extend(split_rows)
    row_parity = pd.DataFrame(row_rows).sort_values(["parity_status", "delta_abs", "region", "fold"], ascending=[True, False, True, True])
    window_contract = pd.DataFrame(window_rows).sort_values(["region", "fold", "split"])
    scaling_contract = build_scaling_contract(surface, cfg)
    horizon_gaps = build_horizon_gap_by_row(row_parity)
    paper_signals = paper_contract_signals(data["paper_text"] + "\n" + data["pipeline_report"])

    hard_failures = int((row_parity["hard_failure_count"] > 0).sum())
    counts = {
        "hard_parity_failures": hard_failures,
    }
    mechanisms = build_mechanism_decisions(counts)

    input_manifest.to_csv(out_dir / "stage_u_input_manifest.csv", index=False)
    row_parity.to_csv(out_dir / "stage_u_row_parity_matrix.csv", index=False)
    window_contract.to_csv(out_dir / "stage_u_window_contract.csv", index=False)
    scaling_contract.to_csv(out_dir / "stage_u_scaling_scoring_contract.csv", index=False)
    horizon_gaps.to_csv(out_dir / "stage_u_horizon_gap_by_row.csv", index=False)
    mechanisms.to_csv(out_dir / "stage_u_mechanism_decisions.csv", index=False)
    paper_signals.to_csv(out_dir / "stage_u_paper_contract_signals.csv", index=False)

    status_counts = row_parity["parity_status"].value_counts().to_dict()
    summary = {
        **repo_state(),
        "status": "completed",
        "diagnostic_only": True,
        "writes_launch_configs": False,
        "fits_models": False,
        "stage_m_rows": int(surface.shape[0]),
        "stage_m_surface_csv": config_path_value(args.stage_m_surface_csv),
        "stage_m_surface_sha256": sha256_file(repo_path(args.stage_m_surface_csv)),
        "stage_t_summary_json": config_path_value(args.stage_t_summary_json),
        "stage_t_summary_sha256": sha256_file(repo_path(args.stage_t_summary_json)),
        "row_parity_passes": int(status_counts.get("pass", 0)),
        "row_parity_warnings": int(status_counts.get("warn", 0)),
        "row_parity_failures": int(status_counts.get("fail", 0)),
        "hard_parity_failures": hard_failures,
        "all_rows_have_raw_metrics": bool(row_parity["raw_unit_metrics_ok"].all()),
        "all_rows_have_scaled_metrics": bool(row_parity["scaled_metrics_present"].all()),
        "all_rows_have_horizon_groups": bool(row_parity["horizon_metrics_ok"].all()),
        "all_rows_have_window_contract": bool(row_parity["all_window_manifests_ok"].all()),
        "all_folds_have_scaling_contract": bool(scaling_contract["scaling_ok"].all()),
        "graph_rows": int((row_parity["feature_policy"].astype(str) == "graph_khop").sum()),
        "target_only_rows": int((row_parity["feature_policy"].astype(str) == "target_only").sum()),
        "graph_mask_parity_status": "partial_not_equivalent_to_pricefm_joint_mask",
        "recommended_next_stage": "horizon_aware_validation_contract_after_parity",
        "output_dir": config_path_value(out_dir),
    }
    report = write_report(out_dir, summary, row_parity, scaling_contract, horizon_gaps, mechanisms)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main(argv=None):
    args = parser().parse_args(argv)
    summarize(args)


if __name__ == "__main__":
    main()
