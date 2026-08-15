#!/usr/bin/env python3
"""Design a horizon-aware PriceFM/Q-DESN selection contract.

Stage V is diagnostic-only.  It consumes the frozen Stage-M surface, the
Stage-U parity audit, and completed candidate run artifacts from earlier
searches.  It evaluates validation-only selection rules, then attaches test
metrics only for audit.  It does not fit models, write launch grids, or mutate
the Stage-M article decision surface.
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
    "pricefm_stage_v_horizon_selection_contract_20260629"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_STAGE_M_CURRENT_VT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_validation_test_alignment_20260624/"
    "current_median_validation_test.csv"
)
DEFAULT_STAGE_U_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/summary.json"
)
DEFAULT_STAGE_U_ROW_PARITY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/stage_u_row_parity_matrix.csv"
)
DEFAULT_STAGE_U_HORIZON = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/stage_u_horizon_gap_by_row.csv"
)
DEFAULT_STAGE_O_RULE_AUDIT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_o_selection_promotion_hardening_20260626/"
    "stage_o_selection_rule_audit.csv"
)
DEFAULT_CANDIDATE_RUN_ROOTS = [
    "application/data_local/pricefm/runs/"
    "pricefm_stage_n_underperformance_broad_20260625",
    "application/data_local/pricefm/runs/"
    "pricefm_stage_q_nearmiss_refinement_20260626",
    "application/data_local/pricefm/runs/"
    "pricefm_stage_s_targeted_rescue_20260628",
]

EXPECTED_HORIZON_GROUPS = ["1-24", "25-48", "49-72", "73-96"]
QDESN_PREFIXES = ("qdesn_",)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--stage-m-current-vt-csv", default=DEFAULT_STAGE_M_CURRENT_VT)
    p.add_argument("--stage-u-summary-json", default=DEFAULT_STAGE_U_SUMMARY)
    p.add_argument("--stage-u-row-parity-csv", default=DEFAULT_STAGE_U_ROW_PARITY)
    p.add_argument("--stage-u-horizon-csv", default=DEFAULT_STAGE_U_HORIZON)
    p.add_argument("--stage-o-rule-audit-csv", default=DEFAULT_STAGE_O_RULE_AUDIT)
    p.add_argument("--candidate-run-root", action="append", default=None)
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


def read_csv_if_present(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(path)


def read_yaml_if_present(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with open(path, "r") as f:
        payload = yaml.safe_load(f) or {}
    if isinstance(payload, dict) and "pricefm_desn_smoke" in payload:
        return payload["pricefm_desn_smoke"] or {}
    return payload if isinstance(payload, dict) else {}


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


def candidate_roots(args):
    roots = args.candidate_run_root
    if not roots:
        roots = DEFAULT_CANDIDATE_RUN_ROOTS
    return [repo_path(root) for root in roots]


def input_specs(args):
    specs = [
        ("stage_m_surface", args.stage_m_surface_csv, "csv", "frozen Stage-M surface"),
        ("stage_m_current_vt", args.stage_m_current_vt_csv, "csv", "current median validation/test metrics"),
        ("stage_u_summary", args.stage_u_summary_json, "json", "Stage-U parity gate"),
        ("stage_u_row_parity", args.stage_u_row_parity_csv, "csv", "Stage-U row parity matrix"),
        ("stage_u_horizon", args.stage_u_horizon_csv, "csv", "Stage-U horizon gap table"),
        ("stage_o_rule_audit", args.stage_o_rule_audit_csv, "csv", "Stage-O rule precedent"),
    ]
    for i, root in enumerate(candidate_roots(args), start=1):
        specs.append((
            "candidate_run_root_{}".format(i),
            str(root),
            "dir",
            "completed candidate run root",
        ))
    return specs


def build_input_manifest(args):
    rows = []
    for input_id, path, kind, role in input_specs(args):
        full = repo_path(path)
        if not full.exists():
            raise FileNotFoundError("{} missing required input: {}".format(input_id, full))
        row = {
            "input_id": input_id,
            "kind": kind,
            "role": role,
            "path": config_path_value(full),
            "size_bytes": int(full.stat().st_size) if full.is_file() else "",
            "sha256": sha256_file(full) if full.is_file() else "",
            "n_rows": "",
            "n_columns": "",
        }
        if kind == "csv":
            frame = pd.read_csv(full)
            row["n_rows"] = int(frame.shape[0])
            row["n_columns"] = int(frame.shape[1])
        elif kind == "dir":
            row["n_rows"] = len(list(full.glob("**/model/metric_summary.csv")))
            row["n_columns"] = ""
        rows.append(row)
    return pd.DataFrame(rows)


def validate_stage_u(summary):
    if not bool_value(summary.get("diagnostic_only", False)):
        raise ValueError("Stage-U summary must be diagnostic_only.")
    if bool_value(summary.get("writes_launch_configs", True)):
        raise ValueError("Stage-U summary unexpectedly writes launch configs.")
    if bool_value(summary.get("fits_models", True)):
        raise ValueError("Stage-U summary unexpectedly fits models.")
    if int(summary.get("hard_parity_failures", -1)) != 0:
        raise ValueError("Stage-U hard parity failures must be zero.")
    expected = "horizon_aware_validation_contract_after_parity"
    if str(summary.get("recommended_next_stage", "")) != expected:
        raise ValueError(
            "Stage-U recommended_next_stage must be {}; got {}".format(
                expected, summary.get("recommended_next_stage")
            )
        )


def load_inputs(args):
    surface = read_csv_required(args.stage_m_surface_csv, "Stage-M surface")
    surface = normalize_keys(surface, "Stage-M surface", unique=True)
    require_columns(
        surface,
        [
            "region", "fold", "best_local_method", "local_AQL",
            "pricefm_AQL", "delta_abs", "feature_policy", "run_dir",
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
    current_vt = read_csv_required(args.stage_m_current_vt_csv, "Stage-M current validation/test")
    current_vt = normalize_keys(current_vt, "Stage-M current validation/test", unique=True)
    require_columns(current_vt, ["selection_AQL", "test_AQL"], "Stage-M current validation/test")
    numeric(current_vt, "selection_AQL", "Stage-M current validation/test", required=True)
    numeric(current_vt, "test_AQL", "Stage-M current validation/test", required=True)
    stage_u_summary = read_json_required(args.stage_u_summary_json, "Stage-U summary")
    validate_stage_u(stage_u_summary)
    row_parity = read_csv_required(args.stage_u_row_parity_csv, "Stage-U row parity")
    row_parity = normalize_keys(row_parity, "Stage-U row parity", unique=True)
    stage_u_horizon = read_csv_required(args.stage_u_horizon_csv, "Stage-U horizon")
    stage_u_horizon = normalize_keys(stage_u_horizon, "Stage-U horizon", unique=True)
    stage_o_rule_audit = read_csv_required(args.stage_o_rule_audit_csv, "Stage-O rule audit")
    require_columns(stage_o_rule_audit, ["rule_id", "selection_uses_test_metrics"], "Stage-O rule audit")
    return {
        "surface": surface,
        "current_vt": current_vt,
        "stage_u_summary": stage_u_summary,
        "stage_u_row_parity": row_parity,
        "stage_u_horizon": stage_u_horizon,
        "stage_o_rule_audit": stage_o_rule_audit,
    }


def source_label_from_root(root):
    name = Path(root).name
    if "stage_n" in name:
        return "stage_n_candidate_root"
    if "stage_q" in name:
        return "stage_q_candidate_root"
    if "stage_s" in name:
        return "stage_s_candidate_root"
    return name


def infer_cell_parts(metric_path):
    parts = list(Path(metric_path).parts)
    if "cells" not in parts:
        raise ValueError("Metric path has no cells component: {}".format(metric_path))
    idx = parts.index("cells")
    experiment_id = parts[idx - 1]
    region_part = parts[idx + 1]
    fold_part = parts[idx + 2]
    region = region_part.split("=", 1)[1] if "=" in region_part else region_part
    fold_text = fold_part.split("=", 1)[1] if "=" in fold_part else fold_part
    cell_dir = Path(*parts[: idx + 3])
    return experiment_id, region, int(fold_text), cell_dir


def finite_float(value):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return out if math.isfinite(out) else float("nan")


def as_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return int(default)


def flatten_units(value):
    if isinstance(value, list):
        return json.dumps(value)
    if value is None:
        return ""
    return str(value)


def config_metadata(cell_dir):
    cfg = read_yaml_if_present(cell_dir / "config.yaml")
    adapter = cfg.get("adapter") or {}
    rhs_ns = cfg.get("rhs_ns") or {}
    qdesn_vb = cfg.get("qdesn_vb") or {}
    return {
        "feature_policy": cfg.get("feature_policy", ""),
        "lag_window": len(cfg.get("horizons") or []) or "",
        "feature_dim": adapter.get("feature_dim", ""),
        "depth": adapter.get("depth", ""),
        "units": flatten_units(adapter.get("units")),
        "alpha": finite_float(adapter.get("alpha")),
        "rho": finite_float(adapter.get("rho")),
        "input_scale": finite_float(adapter.get("input_scale")),
        "projection_scale": finite_float(adapter.get("projection_scale")),
        "seed": as_int(adapter.get("seed", cfg.get("run", {}).get("seed", 0))),
        "tau0": finite_float(rhs_ns.get("tau0")),
        "vb_max_iter": as_int(qdesn_vb.get("max_iter", 0)),
        "vb_min_iter": as_int(qdesn_vb.get("min_iter_elbo", 0)),
    }


def qdesn_methods(metric_df):
    if metric_df.empty or "method_id" not in metric_df.columns:
        return []
    methods = metric_df["method_id"].astype(str).unique()
    return sorted([m for m in methods if m.startswith(QDESN_PREFIXES)])


def add_metric_values(row, metric_df, method_id):
    if metric_df.empty:
        return row
    work = metric_df.copy()
    require_columns(work, ["method_id", "split", "unit", "AQL", "MAE", "RMSE"], "metric_summary")
    work = work[
        work["method_id"].astype(str).eq(str(method_id))
        & work["unit"].astype(str).eq("original")
        & work["split"].astype(str).isin(["val", "test"])
    ].copy()
    for col in ["AQL", "MAE", "RMSE"]:
        work[col] = pd.to_numeric(work[col], errors="coerce")
    for split in ["val", "test"]:
        sub = work[work["split"].astype(str).eq(split)]
        if sub.empty:
            for metric in ["AQL", "MAE", "RMSE"]:
                row["{}_{}".format(split, metric)] = float("nan")
        else:
            first = sub.iloc[0]
            for metric in ["AQL", "MAE", "RMSE"]:
                row["{}_{}".format(split, metric)] = finite_float(first.get(metric))
    return row


def group_slug(group):
    return str(group).replace("-", "_")


def add_horizon_values(row, horizon_df, method_id):
    if horizon_df.empty:
        for split in ["val", "test"]:
            for group in EXPECTED_HORIZON_GROUPS:
                row["{}_hg_{}_AQL".format(split, group_slug(group))] = float("nan")
        return row
    require_columns(
        horizon_df,
        ["method_id", "split", "unit", "horizon_group", "AQL", "MAE", "RMSE"],
        "metric_by_horizon_group",
    )
    work = horizon_df[
        horizon_df["method_id"].astype(str).eq(str(method_id))
        & horizon_df["unit"].astype(str).eq("original")
        & horizon_df["split"].astype(str).isin(["val", "test"])
    ].copy()
    for metric in ["AQL", "MAE", "RMSE"]:
        work[metric] = pd.to_numeric(work[metric], errors="coerce")
    for split in ["val", "test"]:
        split_rows = work[work["split"].astype(str).eq(split)]
        for group in EXPECTED_HORIZON_GROUPS:
            sub = split_rows[split_rows["horizon_group"].astype(str).eq(group)]
            for metric in ["AQL", "MAE", "RMSE"]:
                row["{}_hg_{}_{}".format(split, group_slug(group), metric)] = (
                    finite_float(sub.iloc[0].get(metric)) if not sub.empty else float("nan")
                )
    return row


def add_horizon_summaries(row):
    for split in ["val", "test"]:
        vals = [
            row.get("{}_hg_{}_AQL".format(split, group_slug(group)), float("nan"))
            for group in EXPECTED_HORIZON_GROUPS
        ]
        finite = [v for v in vals if math.isfinite(v)]
        missing = [g for g, v in zip(EXPECTED_HORIZON_GROUPS, vals) if not math.isfinite(v)]
        row["{}_horizon_missing_groups".format(split)] = ";".join(missing)
        row["{}_horizon_groups_complete".format(split)] = len(missing) == 0
        row["{}_horizon_mean_AQL".format(split)] = float(pd.Series(finite).mean()) if finite else float("nan")
        row["{}_horizon_max_AQL".format(split)] = max(finite) if finite else float("nan")
        row["{}_horizon_min_AQL".format(split)] = min(finite) if finite else float("nan")
        row["{}_horizon_range_AQL".format(split)] = max(finite) - min(finite) if finite else float("nan")
        early = row.get("{}_hg_1_24_AQL".format(split), float("nan"))
        midlate = [
            row.get("{}_hg_49_72_AQL".format(split), float("nan")),
            row.get("{}_hg_73_96_AQL".format(split), float("nan")),
        ]
        midlate_finite = [v for v in midlate if math.isfinite(v)]
        row["{}_horizon_early_AQL".format(split)] = early
        row["{}_horizon_midlate_mean_AQL".format(split)] = (
            float(pd.Series(midlate_finite).mean()) if midlate_finite else float("nan")
        )
    return row


def metric_row(metric_path, source_label, methods=None):
    metric_path = repo_path(metric_path)
    experiment_id, region, fold, cell_dir = infer_cell_parts(metric_path)
    metric_df = read_csv_if_present(metric_path)
    horizon_df = read_csv_if_present(cell_dir / "model" / "metric_by_horizon_group.csv")
    method_ids = methods if methods is not None else qdesn_methods(metric_df)
    meta = config_metadata(cell_dir)
    rows = []
    for method_id in method_ids:
        row = {
            "source_label": source_label,
            "experiment_id": experiment_id,
            "region": str(region),
            "fold": int(fold),
            "method_id": str(method_id),
            "cell_dir": config_path_value(cell_dir),
            "metric_summary_path": config_path_value(metric_path),
            "horizon_group_path": config_path_value(cell_dir / "model" / "metric_by_horizon_group.csv"),
            **meta,
        }
        row = add_metric_values(row, metric_df, method_id)
        row = add_horizon_values(row, horizon_df, method_id)
        row = add_horizon_summaries(row)
        rows.append(row)
    return rows


def collect_run_root_candidates(root):
    root = repo_path(root)
    source_label = source_label_from_root(root)
    rows = []
    if not root.exists():
        return rows
    for metric_path in sorted(root.glob("**/model/metric_summary.csv")):
        rows.extend(metric_row(metric_path, source_label))
    return rows


def collect_stage_m_candidates(surface):
    rows = []
    for _, row in surface.iterrows():
        cell_dir = (
            repo_path(row["run_dir"])
            / "cells"
            / "region={}".format(row["region"])
            / "fold={}".format(int(row["fold"]))
        )
        metric_path = cell_dir / "model" / "metric_summary.csv"
        if not metric_path.exists():
            continue
        rows.extend(metric_row(metric_path, "stage_m_current_cells"))
    return rows


def enrich_candidates(candidates, surface, current_vt):
    if candidates.empty:
        return candidates
    surface_small = surface[[
        "region", "fold", "best_local_method", "local_AQL", "pricefm_AQL",
        "delta_abs", "feature_policy", "information_set",
    ]].rename(columns={
        "best_local_method": "stage_m_best_method",
        "local_AQL": "stage_m_surface_AQL",
        "delta_abs": "stage_m_delta_vs_pricefm",
        "feature_policy": "stage_m_feature_policy",
        "information_set": "stage_m_information_set",
    })
    current_small = current_vt[["region", "fold", "selection_AQL", "test_AQL"]].rename(columns={
        "selection_AQL": "current_validation_AQL",
        "test_AQL": "current_median_test_AQL",
    })
    out = candidates.merge(surface_small, on=["region", "fold"], how="left", validate="many_to_one")
    out = out.merge(current_small, on=["region", "fold"], how="left", validate="many_to_one")
    for col in [
        "val_AQL", "val_MAE", "val_RMSE", "test_AQL", "test_MAE", "test_RMSE",
        "stage_m_surface_AQL", "pricefm_AQL", "current_validation_AQL",
        "current_median_test_AQL",
    ]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    out["val_delta_vs_current_median"] = out["val_AQL"] - out["current_validation_AQL"]
    out["test_delta_vs_current_median"] = out["test_AQL"] - out["current_median_test_AQL"]
    out["test_delta_vs_stage_m_surface"] = out["test_AQL"] - out["stage_m_surface_AQL"]
    out["test_delta_vs_pricefm"] = out["test_AQL"] - out["pricefm_AQL"]
    out["validation_metrics_complete"] = out[["val_AQL", "val_MAE", "val_RMSE"]].notna().all(axis=1)
    out["test_metrics_complete"] = out[["test_AQL", "test_MAE", "test_RMSE"]].notna().all(axis=1)
    out["horizon_rule_eligible"] = (
        out["validation_metrics_complete"]
        & out["test_metrics_complete"]
        & out["val_horizon_groups_complete"].astype(bool)
    )
    out["candidate_key"] = (
        out["source_label"].astype(str)
        + "::"
        + out["experiment_id"].astype(str)
        + "::"
        + out["region"].astype(str)
        + "::"
        + out["fold"].astype(str)
        + "::"
        + out["method_id"].astype(str)
    )
    out = out.drop_duplicates("candidate_key", keep="first")
    return out.sort_values(["region", "fold", "source_label", "experiment_id", "method_id"]).reset_index(drop=True)


def build_candidate_universe(args, surface, current_vt):
    rows = collect_stage_m_candidates(surface)
    for root in candidate_roots(args):
        rows.extend(collect_run_root_candidates(root))
    candidates = pd.DataFrame(rows)
    if candidates.empty:
        return candidates
    return enrich_candidates(candidates, surface, current_vt)


def build_candidate_health(candidates, expected_region_folds):
    if candidates.empty:
        return pd.DataFrame([{
            "source_label": "all",
            "candidate_rows": 0,
            "region_folds": 0,
            "validation_metrics_complete": 0,
            "test_metrics_complete": 0,
            "val_horizon_groups_complete": 0,
            "horizon_rule_eligible": 0,
        }])
    rows = []
    for source, sub in candidates.groupby("source_label", dropna=False):
        rows.append({
            "source_label": source,
            "candidate_rows": int(sub.shape[0]),
            "region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "validation_metrics_complete": int(sub["validation_metrics_complete"].sum()),
            "test_metrics_complete": int(sub["test_metrics_complete"].sum()),
            "val_horizon_groups_complete": int(sub["val_horizon_groups_complete"].sum()),
            "horizon_rule_eligible": int(sub["horizon_rule_eligible"].sum()),
            "expected_region_folds": int(expected_region_folds),
        })
    rows.append({
        "source_label": "all",
        "candidate_rows": int(candidates.shape[0]),
        "region_folds": int(candidates[["region", "fold"]].drop_duplicates().shape[0]),
        "validation_metrics_complete": int(candidates["validation_metrics_complete"].sum()),
        "test_metrics_complete": int(candidates["test_metrics_complete"].sum()),
        "val_horizon_groups_complete": int(candidates["val_horizon_groups_complete"].sum()),
        "horizon_rule_eligible": int(candidates["horizon_rule_eligible"].sum()),
        "expected_region_folds": int(expected_region_folds),
    })
    return pd.DataFrame(rows)


def rule_definitions():
    rows = [
        {
            "rule_id": "val_aql_min",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": False,
            "description": "Minimize total validation AQL.",
        },
        {
            "rule_id": "robust_rank_val_aql_mae_rmse",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": False,
            "description": "Minimize the sum of validation AQL, MAE, and RMSE ranks.",
        },
        {
            "rule_id": "horizon_max_aql_min",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize the worst validation horizon-block AQL.",
        },
        {
            "rule_id": "horizon_midlate_mean_min",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize the average validation AQL over horizons 49-96.",
        },
        {
            "rule_id": "horizon_balanced_rank",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Balance total validation AQL, worst block, range, and late-block ranks.",
        },
        {
            "rule_id": "horizon_guarded_val_aql",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Minimize validation AQL after candidate-local horizon max/range guardrails.",
        },
        {
            "rule_id": "current_safe_horizon_guarded",
            "score_direction": "min",
            "selection_uses_test_metrics": False,
            "requires_complete_val_horizon": True,
            "description": "Prefer candidates that improve current validation AQL and satisfy horizon guardrails.",
        },
    ]
    return pd.DataFrame(rows)


def rank_series(series):
    return pd.to_numeric(series, errors="coerce").rank(method="average", na_option="bottom")


def scored_group(group, rule_id):
    g = group.copy()
    g["rule_score"] = float("nan")
    g["rule_fallback_used"] = False
    g["rule_guard_max_threshold"] = float("nan")
    g["rule_guard_range_threshold"] = float("nan")
    if rule_id == "val_aql_min":
        eligible = g[g["validation_metrics_complete"]].copy()
        eligible["rule_score"] = eligible["val_AQL"]
        return eligible
    if rule_id == "robust_rank_val_aql_mae_rmse":
        eligible = g[g["validation_metrics_complete"]].copy()
        eligible["rule_score"] = (
            rank_series(eligible["val_AQL"])
            + rank_series(eligible["val_MAE"])
            + rank_series(eligible["val_RMSE"])
        )
        return eligible
    eligible = g[g["horizon_rule_eligible"]].copy()
    if eligible.empty:
        return eligible
    if rule_id == "horizon_max_aql_min":
        eligible["rule_score"] = eligible["val_horizon_max_AQL"]
        return eligible
    if rule_id == "horizon_midlate_mean_min":
        eligible["rule_score"] = eligible["val_horizon_midlate_mean_AQL"]
        return eligible
    if rule_id == "horizon_balanced_rank":
        eligible["rule_score"] = (
            rank_series(eligible["val_AQL"])
            + rank_series(eligible["val_horizon_max_AQL"])
            + rank_series(eligible["val_horizon_range_AQL"])
            + rank_series(eligible["val_horizon_midlate_mean_AQL"])
        )
        return eligible
    if rule_id in ["horizon_guarded_val_aql", "current_safe_horizon_guarded"]:
        max_thr = float(eligible["val_horizon_max_AQL"].quantile(0.75))
        range_thr = float(eligible["val_horizon_range_AQL"].quantile(0.75))
        guarded = eligible[
            eligible["val_horizon_max_AQL"].le(max_thr)
            & eligible["val_horizon_range_AQL"].le(range_thr)
        ].copy()
        if rule_id == "current_safe_horizon_guarded":
            guarded = guarded[guarded["val_delta_vs_current_median"].le(0.0)].copy()
        if guarded.empty:
            guarded = eligible.copy()
            guarded["rule_fallback_used"] = True
        guarded["rule_guard_max_threshold"] = max_thr
        guarded["rule_guard_range_threshold"] = range_thr
        guarded["rule_score"] = guarded["val_AQL"]
        return guarded
    raise ValueError("Unknown selection rule: {}".format(rule_id))


def select_by_rules(candidates):
    defs = rule_definitions()
    if candidates.empty:
        return pd.DataFrame(), defs
    selected = []
    for rule_id in defs["rule_id"]:
        for (region, fold), group in candidates.groupby(["region", "fold"], dropna=False):
            scored = scored_group(group, rule_id)
            if scored.empty:
                selected.append({
                    "rule_id": rule_id,
                    "region": region,
                    "fold": int(fold),
                    "selection_status": "no_eligible_candidate",
                    "selection_uses_test_metrics": False,
                })
                continue
            scored = scored.sort_values(
                ["rule_score", "val_AQL", "val_horizon_max_AQL", "source_label", "experiment_id", "method_id"],
                ascending=[True, True, True, True, True, True],
            )
            row = scored.iloc[0].to_dict()
            row.update({
                "rule_id": rule_id,
                "selection_status": "selected",
                "selection_uses_test_metrics": False,
                "selection_metrics_role": "validation_only",
                "test_metrics_role": "audit_only_after_selection",
                "test_oracle_AQL": float(group["test_AQL"].min()) if group["test_AQL"].notna().any() else float("nan"),
            })
            row["test_regret_vs_candidate_oracle"] = row["test_AQL"] - row["test_oracle_AQL"]
            selected.append(row)
    selected = pd.DataFrame(selected)
    return selected.sort_values(["rule_id", "region", "fold"]).reset_index(drop=True), defs


def summarize_rules(selected):
    if selected.empty:
        return pd.DataFrame()
    work = selected[selected["selection_status"].astype(str).eq("selected")].copy()
    if work.empty:
        return pd.DataFrame()
    for col in [
        "val_AQL", "test_AQL", "val_delta_vs_current_median",
        "test_delta_vs_current_median", "test_delta_vs_stage_m_surface",
        "test_delta_vs_pricefm", "test_regret_vs_candidate_oracle",
    ]:
        work[col] = pd.to_numeric(work[col], errors="coerce")
    rows = []
    for rule_id, sub in work.groupby("rule_id", dropna=False):
        rows.append({
            "rule_id": rule_id,
            "n_region_folds": int(sub[["region", "fold"]].drop_duplicates().shape[0]),
            "selection_uses_test_metrics": bool(sub["selection_uses_test_metrics"].astype(bool).any()),
            "fallback_rows": int(sub.get("rule_fallback_used", pd.Series(False, index=sub.index)).astype(bool).sum()),
            "mean_validation_AQL": float(sub["val_AQL"].mean()),
            "mean_test_AQL": float(sub["test_AQL"].mean()),
            "mean_val_delta_vs_current_median": float(sub["val_delta_vs_current_median"].mean()),
            "mean_test_delta_vs_current_median": float(sub["test_delta_vs_current_median"].mean()),
            "median_test_delta_vs_current_median": float(sub["test_delta_vs_current_median"].median()),
            "mean_test_delta_vs_stage_m_surface": float(sub["test_delta_vs_stage_m_surface"].mean()),
            "mean_test_delta_vs_pricefm": float(sub["test_delta_vs_pricefm"].mean()),
            "test_improved_vs_current_median_rows": int(sub["test_delta_vs_current_median"].lt(0.0).sum()),
            "test_improved_vs_stage_m_surface_rows": int(sub["test_delta_vs_stage_m_surface"].lt(0.0).sum()),
            "beats_pricefm_rows": int(sub["test_delta_vs_pricefm"].lt(0.0).sum()),
            "mean_test_regret_vs_candidate_oracle": float(sub["test_regret_vs_candidate_oracle"].mean()),
            "median_test_regret_vs_candidate_oracle": float(sub["test_regret_vs_candidate_oracle"].median()),
        })
    out = pd.DataFrame(rows)
    out["test_improved_vs_current_median_rate"] = (
        out["test_improved_vs_current_median_rows"] / out["n_region_folds"].clip(lower=1)
    )
    out["test_improved_vs_stage_m_surface_rate"] = (
        out["test_improved_vs_stage_m_surface_rows"] / out["n_region_folds"].clip(lower=1)
    )
    out["beats_pricefm_rate"] = out["beats_pricefm_rows"] / out["n_region_folds"].clip(lower=1)
    return out.sort_values(
        ["mean_test_delta_vs_current_median", "mean_test_regret_vs_candidate_oracle", "rule_id"],
        ascending=[True, True, True],
    ).reset_index(drop=True)


def build_region_fold_rule_matrix(selected):
    if selected.empty:
        return pd.DataFrame()
    keep = selected[selected["selection_status"].astype(str).eq("selected")].copy()
    if keep.empty:
        return keep
    cols = [
        "region", "fold", "rule_id", "source_label", "experiment_id",
        "method_id", "val_AQL", "test_AQL", "current_validation_AQL",
        "current_median_test_AQL", "pricefm_AQL", "test_delta_vs_current_median",
        "test_delta_vs_stage_m_surface", "test_delta_vs_pricefm",
        "val_horizon_max_AQL", "val_horizon_range_AQL",
        "val_horizon_midlate_mean_AQL", "test_regret_vs_candidate_oracle",
    ]
    return keep[[col for col in cols if col in keep.columns]].sort_values(["region", "fold", "rule_id"])


def build_horizon_rule_diagnostics(selected):
    if selected.empty:
        return pd.DataFrame()
    work = selected[selected["selection_status"].astype(str).eq("selected")].copy()
    if work.empty:
        return work
    horizon_rules = [
        "horizon_max_aql_min",
        "horizon_midlate_mean_min",
        "horizon_balanced_rank",
        "horizon_guarded_val_aql",
        "current_safe_horizon_guarded",
    ]
    work = work[work["rule_id"].isin(horizon_rules)].copy()
    if work.empty:
        return work
    rows = []
    for rule_id, sub in work.groupby("rule_id", dropna=False):
        rows.append({
            "rule_id": rule_id,
            "rows": int(sub.shape[0]),
            "mean_val_horizon_max_AQL": float(pd.to_numeric(sub["val_horizon_max_AQL"], errors="coerce").mean()),
            "mean_val_horizon_range_AQL": float(pd.to_numeric(sub["val_horizon_range_AQL"], errors="coerce").mean()),
            "mean_val_horizon_midlate_AQL": float(pd.to_numeric(sub["val_horizon_midlate_mean_AQL"], errors="coerce").mean()),
            "mean_test_horizon_max_AQL": float(pd.to_numeric(sub["test_horizon_max_AQL"], errors="coerce").mean()),
            "mean_test_horizon_range_AQL": float(pd.to_numeric(sub["test_horizon_range_AQL"], errors="coerce").mean()),
            "mean_test_horizon_midlate_AQL": float(pd.to_numeric(sub["test_horizon_midlate_mean_AQL"], errors="coerce").mean()),
            "fallback_rows": int(sub.get("rule_fallback_used", pd.Series(False, index=sub.index)).astype(bool).sum()),
        })
    return pd.DataFrame(rows).sort_values("rule_id").reset_index(drop=True)


def build_mechanism_decisions(rule_audit, candidate_health):
    rows = []
    if rule_audit.empty:
        rows.append({
            "rank": 1,
            "mechanism": "horizon_aware_validation_selection",
            "decision": "blocked_no_candidates",
            "writes_launch_config": False,
            "fits_models": False,
            "justification": "No eligible candidate rows were available for validation-only horizon scoring.",
            "next_action": "Fix candidate artifact availability before designing another launch.",
        })
        return pd.DataFrame(rows)
    best = rule_audit.iloc[0]
    improves = (
        float(best["mean_test_delta_vs_current_median"]) < -0.05
        and float(best["test_improved_vs_current_median_rate"]) >= 0.5
    )
    beats_some_pricefm = int(best["beats_pricefm_rows"]) > 0
    if improves and beats_some_pricefm:
        decision = "consider_small_confirmation_launch"
        next_action = "Design a small confirmation run that freezes this validation-only rule before promotion."
        justification = (
            "The best audit rule improved current median test AQL on average and beats PriceFM "
            "for at least one region/fold, but test data remain audit-only."
        )
    elif improves:
        decision = "diagnostic_positive_but_not_pricefm_competitive"
        next_action = "Use this rule only as a screening diagnostic; do not promote without a confirmation gate."
        justification = (
            "The best audit rule improved current Q-DESN median rows on average, but did not "
            "show enough PriceFM competitiveness."
        )
    else:
        decision = "do_not_launch_from_stage_v"
        next_action = "Do not run another capacity sweep until selection instability or graph-parity mechanisms change."
        justification = (
            "No validation-only horizon rule produced a strong enough audit signal over the existing "
            "candidate universe."
        )
    rows.append({
        "rank": 1,
        "mechanism": "horizon_aware_validation_selection",
        "decision": decision,
        "writes_launch_config": False,
        "fits_models": False,
        "best_audit_rule": best["rule_id"],
        "justification": justification,
        "next_action": next_action,
    })
    rows.append({
        "rank": 2,
        "mechanism": "candidate_artifact_health",
        "decision": "pass" if int(candidate_health.tail(1)["horizon_rule_eligible"].iloc[0]) > 0 else "fail",
        "writes_launch_config": False,
        "fits_models": False,
        "best_audit_rule": "",
        "justification": "Candidate scanning found validation/test metrics and validation horizon blocks for rule scoring.",
        "next_action": "Keep metric summaries and horizon summaries as the minimal retained artifact for future screens.",
    })
    rows.append({
        "rank": 3,
        "mechanism": "test_metric_leakage_guard",
        "decision": "pass" if not bool(rule_audit["selection_uses_test_metrics"].any()) else "fail",
        "writes_launch_config": False,
        "fits_models": False,
        "best_audit_rule": "",
        "justification": "All Stage-V rules are declared validation-only; test metrics are attached after selection.",
        "next_action": "Preserve this contract before any future confirmation launch.",
    })
    return pd.DataFrame(rows)


def recommended_next_stage(rule_audit):
    if rule_audit.empty:
        return "fix_candidate_artifacts_before_more_search"
    best = rule_audit.iloc[0]
    improves = (
        float(best["mean_test_delta_vs_current_median"]) < -0.05
        and float(best["test_improved_vs_current_median_rate"]) >= 0.5
        and int(best["beats_pricefm_rows"]) > 0
    )
    if improves:
        return "design_small_confirmation_launch_from_stage_v_contract"
    return "do_not_launch_more_capacity_until_selection_or_graph_model_changes"


def markdown_table(frame, columns=None, max_rows=20):
    if frame is None or frame.empty:
        return "_No rows._"
    work = frame.copy()
    if columns is not None:
        work = work[[col for col in columns if col in work.columns]]
    if max_rows is not None:
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
    return "\n".join(lines)


def write_report(path, summary, candidate_health, rule_audit, matrix, horizon_diag, mechanisms):
    lines = [
        "# PriceFM Stage-V horizon selection contract",
        "",
        "Stage V is diagnostic-only. It evaluates validation-only selection "
        "rules over completed Q-DESN candidate artifacts and attaches test "
        "metrics only after each rule has selected a row.",
        "",
        "## Health",
        "",
        "- Diagnostic only: `{}`".format(summary["diagnostic_only"]),
        "- Fits models: `{}`".format(summary["fits_models"]),
        "- Writes launch configs: `{}`".format(summary["writes_launch_configs"]),
        "- Stage-M surface changed: `{}`".format(summary["stage_m_surface_changed"]),
        "- Candidate rows: `{}`".format(summary["candidate_rows"]),
        "- Horizon-rule eligible rows: `{}`".format(summary["horizon_rule_eligible_rows"]),
        "- Rules evaluated: `{}`".format(summary["rules_evaluated"]),
        "- Best audit rule: `{}`".format(summary["best_audit_rule"]),
        "- Recommended next stage: `{}`".format(summary["recommended_next_stage"]),
        "",
        "## Candidate Health",
        "",
        markdown_table(candidate_health, max_rows=20),
        "",
        "## Rule Audit",
        "",
        markdown_table(rule_audit, [
            "rule_id", "n_region_folds", "selection_uses_test_metrics",
            "fallback_rows", "mean_test_delta_vs_current_median",
            "test_improved_vs_current_median_rate", "mean_test_delta_vs_pricefm",
            "beats_pricefm_rows", "mean_test_regret_vs_candidate_oracle",
        ], max_rows=20),
        "",
        "## Horizon Diagnostics",
        "",
        markdown_table(horizon_diag, max_rows=20),
        "",
        "## Largest Selected Losses By Best Audit Rule",
        "",
    ]
    if not matrix.empty and summary.get("best_audit_rule"):
        sub = matrix[matrix["rule_id"].astype(str).eq(str(summary["best_audit_rule"]))].copy()
        sub = sub.sort_values("test_delta_vs_pricefm", ascending=False)
        lines.append(markdown_table(sub, [
            "region", "fold", "source_label", "experiment_id", "method_id",
            "val_AQL", "test_AQL", "pricefm_AQL", "test_delta_vs_current_median",
            "test_delta_vs_pricefm", "val_horizon_max_AQL",
            "val_horizon_midlate_mean_AQL",
        ], max_rows=12))
    else:
        lines.append("_No selected rows._")
    lines.extend([
        "",
        "## Mechanism Decisions",
        "",
        markdown_table(mechanisms, [
            "rank", "mechanism", "decision", "best_audit_rule",
            "writes_launch_config", "fits_models", "next_action",
        ], max_rows=20),
        "",
        "## Interpretation",
        "",
        "The Stage-V contract is a selection diagnostic, not a new model run. "
        "A useful rule must be validation-only, improve the current Q-DESN "
        "median rows under test audit, and avoid pretending to be a direct "
        "promotion rule. If the audit signal is weak, the correct response is "
        "not another broad capacity sweep; it is a mechanism change such as "
        "a better graph-information adapter or a multi-validation stability "
        "contract.",
        "",
        "## Output Manifest",
        "",
    ])
    for key, value in sorted(summary["outputs"].items()):
        lines.append("- `{}`: `{}`".format(key, value))
    repo_path(path).write_text("\n".join(lines) + "\n")


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def design(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} already exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    inputs = load_inputs(args)
    input_manifest = build_input_manifest(args)
    candidates = build_candidate_universe(args, inputs["surface"], inputs["current_vt"])
    candidate_health = build_candidate_health(candidates, args.expected_region_folds)
    selected, defs = select_by_rules(candidates)
    if not selected.empty and bool(selected["selection_uses_test_metrics"].astype(bool).any()):
        raise ValueError("Stage-V rule selection leaked test metrics.")
    rule_audit = summarize_rules(selected)
    matrix = build_region_fold_rule_matrix(selected)
    horizon_diag = build_horizon_rule_diagnostics(selected)
    mechanisms = build_mechanism_decisions(rule_audit, candidate_health)

    best_rule = "" if rule_audit.empty else str(rule_audit.iloc[0]["rule_id"])
    outputs = {
        "input_manifest_csv": out_dir / "stage_v_input_manifest.csv",
        "candidate_universe_csv": out_dir / "stage_v_candidate_universe.csv",
        "candidate_health_csv": out_dir / "stage_v_candidate_health.csv",
        "rule_definitions_csv": out_dir / "stage_v_rule_definitions.csv",
        "rule_selected_rows_csv": out_dir / "stage_v_rule_selected_rows.csv",
        "rule_audit_csv": out_dir / "stage_v_rule_audit.csv",
        "region_fold_rule_matrix_csv": out_dir / "stage_v_region_fold_rule_matrix.csv",
        "horizon_rule_diagnostics_csv": out_dir / "stage_v_horizon_rule_diagnostics.csv",
        "mechanism_decisions_csv": out_dir / "stage_v_mechanism_decisions.csv",
        "summary_md": out_dir / "stage_v_horizon_selection_contract_report.md",
        "summary_json": out_dir / "summary.json",
    }
    summary = {
        **repo_state(),
        "status": "completed",
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "stage_u_hard_parity_failures": int(inputs["stage_u_summary"].get("hard_parity_failures", 0)),
        "stage_m_rows": int(inputs["surface"].shape[0]),
        "candidate_rows": int(candidates.shape[0]),
        "candidate_region_folds": int(candidates[["region", "fold"]].drop_duplicates().shape[0]) if not candidates.empty else 0,
        "horizon_rule_eligible_rows": int(candidates["horizon_rule_eligible"].sum()) if not candidates.empty else 0,
        "rules_evaluated": int(defs.shape[0]),
        "selected_rows": int(selected[selected["selection_status"].astype(str).eq("selected")].shape[0]) if not selected.empty else 0,
        "selection_uses_test_metrics_any": bool(selected["selection_uses_test_metrics"].astype(bool).any()) if not selected.empty else False,
        "best_audit_rule": best_rule,
        "recommended_next_stage": recommended_next_stage(rule_audit),
        "output_dir": config_path_value(out_dir),
        "stage_m_surface_csv": config_path_value(args.stage_m_surface_csv),
        "stage_m_surface_sha256": sha256_file(repo_path(args.stage_m_surface_csv)),
        "stage_u_summary_json": config_path_value(args.stage_u_summary_json),
        "stage_u_summary_sha256": sha256_file(repo_path(args.stage_u_summary_json)),
    }
    if not rule_audit.empty:
        best = rule_audit.iloc[0]
        summary.update({
            "best_rule_mean_test_delta_vs_current_median": finite_float(best["mean_test_delta_vs_current_median"]),
            "best_rule_test_improved_rate": finite_float(best["test_improved_vs_current_median_rate"]),
            "best_rule_mean_test_delta_vs_pricefm": finite_float(best["mean_test_delta_vs_pricefm"]),
            "best_rule_beats_pricefm_rows": int(best["beats_pricefm_rows"]),
            "best_rule_mean_test_regret_vs_candidate_oracle": finite_float(best["mean_test_regret_vs_candidate_oracle"]),
        })
    summary["outputs"] = {key: config_path_value(value) for key, value in outputs.items()}

    write_frame(outputs["input_manifest_csv"], input_manifest)
    write_frame(outputs["candidate_universe_csv"], candidates)
    write_frame(outputs["candidate_health_csv"], candidate_health)
    write_frame(outputs["rule_definitions_csv"], defs)
    write_frame(outputs["rule_selected_rows_csv"], selected)
    write_frame(outputs["rule_audit_csv"], rule_audit)
    write_frame(outputs["region_fold_rule_matrix_csv"], matrix)
    write_frame(outputs["horizon_rule_diagnostics_csv"], horizon_diag)
    write_frame(outputs["mechanism_decisions_csv"], mechanisms)
    write_report(outputs["summary_md"], summary, candidate_health, rule_audit, matrix, horizon_diag, mechanisms)
    write_json(outputs["summary_json"], summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main(argv=None):
    args = parser().parse_args(argv)
    design(args)


if __name__ == "__main__":
    main()
