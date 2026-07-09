#!/usr/bin/env python3
"""Close out the Stage-W Priority-0 PriceFM Q-DESN screen.

Stage W is a region/fold-specific median screen over severe underperformers.
This closeout is intentionally conservative: it audits the completed Priority-0
fits, records validation-selected and test-oracle diagnostics, and decides
whether later priorities are justified.  It never mutates the Stage-M decision
surface and never promotes a candidate from test-oracle information.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_w_region_fold_screening_20260629"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_w_region_fold_screening_20260629"
)
DEFAULT_PLAN_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_region_fold_screening_plan_20260629"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_TIME_LOG = (
    "application/data_local/pricefm/logs/"
    "stage_w_priority0_20260630_012938.time.log"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_w_priority0_closeout_20260630"
)

QDESN_PREFIX = "qdesn_"
DEFAULT_PRIORITIES = "0"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--plan-dir", default=DEFAULT_PLAN_DIR)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--time-log", default=DEFAULT_TIME_LOG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--priorities", default=DEFAULT_PRIORITIES)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--require-complete", type=parse_bool, default=True)
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


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col, default=float("nan")):
    if col not in frame.columns:
        return pd.Series([default] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if math.isfinite(out) else default


def as_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return int(default)


def parse_jsonish(value):
    if isinstance(value, (list, tuple)):
        return list(value)
    if pd.isna(value):
        return []
    text = str(value).strip()
    if not text:
        return []
    if text.startswith("["):
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return [text]
        return parsed if isinstance(parsed, list) else [parsed]
    return [text]


def parse_priorities(value):
    vals = parse_jsonish(value.replace(",", ",") if isinstance(value, str) else value)
    if len(vals) == 1 and isinstance(vals[0], str) and "," in vals[0]:
        vals = [x.strip() for x in vals[0].split(",") if x.strip()]
    return sorted({as_int(v) for v in vals})


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def markdown_table(frame, columns=None, max_rows=None):
    if frame is None or frame.empty:
        return "_No rows._"
    work = frame.copy()
    if columns is not None:
        work = work[[col for col in columns if col in work.columns]]
    if max_rows is not None:
        work = work.head(max_rows)
    headers = list(work.columns)
    out = ["| {} |".format(" | ".join(headers))]
    out.append("| {} |".format(" | ".join(["---"] * len(headers))))
    for _, row in work.iterrows():
        vals = []
        for col in headers:
            value = row[col]
            if isinstance(value, float):
                vals.append("" if math.isnan(value) else "{:.6g}".format(value))
            else:
                vals.append(str(value))
        out.append("| {} |".format(" | ".join(vals)))
    return "\n".join(out)


def normalize_manifest(manifest, priorities):
    id_col = "id" if "id" in manifest.columns else "experiment_id"
    require_columns(manifest, [id_col, "priority", "regions", "folds"], "Stage-W manifest")
    out = manifest.copy()
    out["experiment_id"] = out[id_col].astype(str)
    out["priority"] = pd.to_numeric(out["priority"], errors="raise").astype(int)
    out = out[out["priority"].isin(priorities)].copy()
    if out.empty:
        raise ValueError("Stage-W manifest has no rows for priorities {}".format(priorities))
    out["region"] = out["regions"].map(lambda x: str(parse_jsonish(x)[0]))
    out["fold"] = out["folds"].map(lambda x: as_int(parse_jsonish(x)[0]))
    if out["experiment_id"].duplicated().any():
        dup = out[out["experiment_id"].duplicated(keep=False)]["experiment_id"].tolist()
        raise ValueError("Stage-W manifest has duplicate experiment IDs: {}".format(dup))
    out["local_AQL"] = numeric(out, "local_AQL")
    out["pricefm_AQL"] = numeric(out, "pricefm_AQL")
    keep = [
        "experiment_id", "region", "fold", "priority", "candidate_family",
        "factor_changed", "feature_policy", "graph_degree", "input_scope",
        "spatial_information_set", "lag_window", "units", "depth", "alpha",
        "rho", "input_scale", "tau0", "seed", "local_AQL", "pricefm_AQL",
        "selection_rule", "selection_is_validation_only", "test_metrics_role",
        "run_dir",
    ]
    return out[[col for col in keep if col in out.columns]].copy()


def load_manifest(grid_root, plan_dir, priorities):
    grid_manifest = repo_path(Path(grid_root) / "manifest.csv")
    if grid_manifest.exists():
        return normalize_manifest(pd.read_csv(grid_manifest), priorities)
    plan_manifest = repo_path(Path(plan_dir) / "stage_w_experiment_manifest.csv")
    return normalize_manifest(pd.read_csv(plan_manifest), priorities)


def experiment_metric_paths(run_root):
    return sorted(repo_path(run_root).glob("*/cells/region=*/fold=*/model/metric_summary.csv"))


def experiment_from_metric_path(path, run_root):
    rel = path.relative_to(repo_path(run_root))
    return rel.parts[0]


def region_fold_from_path(path):
    region = None
    fold = None
    for part in path.parts:
        if part.startswith("region="):
            region = part.split("=", 1)[1]
        elif part.startswith("fold="):
            fold = as_int(part.split("=", 1)[1])
    if region is None or fold is None:
        raise ValueError("Cannot infer region/fold from {}".format(path))
    return region, fold


def collect_long_metrics(manifest, run_root):
    meta = manifest.set_index("experiment_id").to_dict("index")
    rows = []
    for path in experiment_metric_paths(run_root):
        exp_id = experiment_from_metric_path(path, run_root)
        if exp_id not in meta:
            continue
        region, fold = region_fold_from_path(path)
        metric = pd.read_csv(path)
        require_columns(metric, ["method_id", "split", "unit", "AQL"], str(path))
        for _, row in metric.iterrows():
            out = {
                "region": region,
                "fold": fold,
                "experiment_id": exp_id,
                "method_id": str(row["method_id"]),
                "split": str(row["split"]),
                "unit": str(row["unit"]),
                "metric_summary": config_path_value(path),
            }
            for col in ["AQL", "AQCR", "MAE", "RMSE"]:
                if col in row.index:
                    out[col] = as_float(row[col])
            for key, val in meta[exp_id].items():
                if key not in out:
                    out[key] = val
            rows.append(out)
    return pd.DataFrame(rows)


def build_qdesn_method_metrics(long_metrics):
    if long_metrics.empty:
        return pd.DataFrame()
    original = long_metrics[
        long_metrics["unit"].astype(str).eq("original")
        & long_metrics["method_id"].astype(str).str.startswith(QDESN_PREFIX)
    ].copy()
    if original.empty:
        return original
    keys = [
        "region", "fold", "experiment_id", "method_id", "priority",
        "candidate_family", "factor_changed", "feature_policy", "graph_degree",
        "input_scope", "spatial_information_set", "lag_window", "units", "depth",
        "alpha", "rho", "input_scale", "tau0", "seed", "local_AQL", "pricefm_AQL",
    ]
    keys = [col for col in keys if col in original.columns]
    rows = []
    for key, sub in original.groupby(keys, dropna=False, sort=False):
        row = dict(zip(keys, key if isinstance(key, tuple) else (key,)))
        for split, split_sub in sub.groupby("split", sort=False):
            prefix = str(split)
            for metric in ["AQL", "AQCR", "MAE", "RMSE"]:
                vals = split_sub[metric] if metric in split_sub.columns else pd.Series(dtype=float)
                row["{}_{}".format(prefix, metric)] = as_float(vals.iloc[0]) if len(vals) else float("nan")
        rows.append(row)
    return pd.DataFrame(rows)


def choose_min(frame, group_cols, metric_col, prefix):
    rows = []
    for _, sub in frame.dropna(subset=[metric_col]).groupby(group_cols, sort=True):
        ordered = sub.sort_values([metric_col, "experiment_id", "method_id"], kind="mergesort")
        row = ordered.iloc[0].to_dict()
        row["selection_type"] = prefix
        rows.append(row)
    return pd.DataFrame(rows)


def add_decision_columns(selected):
    if selected.empty:
        return selected
    out = selected.copy()
    out["delta_vs_current_AQL"] = out["test_AQL"] - out["local_AQL"]
    out["delta_vs_pricefm_AQL"] = out["test_AQL"] - out["pricefm_AQL"]

    def decision(row):
        test = row["test_AQL"]
        current = row["local_AQL"]
        pricefm = row["pricefm_AQL"]
        if pd.notna(test) and pd.notna(current) and pd.notna(pricefm) and test < min(current, pricefm):
            return "promote_validation_and_test_pricefm_win"
        if pd.notna(test) and pd.notna(current) and test < current:
            return "candidate_only_beats_current_not_pricefm"
        return "reject_validation_worse_current"

    out["validation_selected_decision"] = out.apply(decision, axis=1)
    return out


def build_validation_transfer(qdesn_metrics, validation_selected, test_oracle):
    if qdesn_metrics.empty or validation_selected.empty or test_oracle.empty:
        return pd.DataFrame()
    val_cols = [
        "region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL",
        "candidate_family", "factor_changed",
    ]
    validation = validation_selected[[col for col in val_cols if col in validation_selected.columns]].copy()
    oracle = test_oracle[[col for col in val_cols if col in test_oracle.columns]].copy()
    validation = validation.rename(columns={
        "experiment_id": "validation_selected_experiment_id",
        "method_id": "validation_selected_method_id",
        "val_AQL": "validation_selected_val_AQL",
        "test_AQL": "validation_selected_test_AQL",
        "candidate_family": "validation_selected_family",
        "factor_changed": "validation_selected_factor",
    })
    oracle = oracle.rename(columns={
        "experiment_id": "test_oracle_experiment_id",
        "method_id": "test_oracle_method_id",
        "val_AQL": "test_oracle_val_AQL",
        "test_AQL": "test_oracle_test_AQL",
        "candidate_family": "test_oracle_family",
        "factor_changed": "test_oracle_factor",
    })
    out = validation.merge(oracle, on=["region", "fold"], how="outer")
    out["test_regret_vs_oracle"] = out["validation_selected_test_AQL"] - out["test_oracle_test_AQL"]
    cors = []
    for (region, fold), sub in qdesn_metrics.groupby(["region", "fold"], sort=True):
        corr = sub[["val_AQL", "test_AQL"]].dropna().corr(method="spearman").iloc[0, 1]
        cors.append({"region": region, "fold": fold, "validation_test_spearman": corr})
    out = out.merge(pd.DataFrame(cors), on=["region", "fold"], how="left")
    out["oracle_missed_by_validation"] = (
        out["validation_selected_experiment_id"].astype(str)
        + "::"
        + out["validation_selected_method_id"].astype(str)
        != out["test_oracle_experiment_id"].astype(str)
        + "::"
        + out["test_oracle_method_id"].astype(str)
    )
    return out


def build_family_summary(qdesn_metrics):
    if qdesn_metrics.empty or "candidate_family" not in qdesn_metrics.columns:
        return pd.DataFrame()
    rows = []
    for keys, sub in qdesn_metrics.dropna(subset=["test_AQL"]).groupby(
        ["region", "fold", "candidate_family"], sort=True
    ):
        best = sub.sort_values(["test_AQL", "experiment_id", "method_id"], kind="mergesort").iloc[0]
        rows.append({
            "region": keys[0],
            "fold": keys[1],
            "candidate_family": keys[2],
            "best_experiment_id": best["experiment_id"],
            "best_method_id": best["method_id"],
            "best_test_AQL": best["test_AQL"],
            "best_val_AQL": best.get("val_AQL", float("nan")),
            "delta_vs_current_AQL": best["test_AQL"] - best["local_AQL"],
            "delta_vs_pricefm_AQL": best["test_AQL"] - best["pricefm_AQL"],
            "factor_changed": best.get("factor_changed", ""),
        })
    return pd.DataFrame(rows)


def collect_horizon_metrics(qdesn_metrics, run_root, validation_selected, test_oracle):
    selected_keys = []
    for label, frame in [("validation_selected", validation_selected), ("test_oracle", test_oracle)]:
        for _, row in frame.iterrows():
            selected_keys.append({
                "region": row["region"],
                "fold": row["fold"],
                "experiment_id": row["experiment_id"],
                "method_id": row["method_id"],
                "selection_type": label,
            })
    if not selected_keys:
        return pd.DataFrame()
    key_frame = pd.DataFrame(selected_keys)
    rows = []
    for _, key in key_frame.iterrows():
        path = (
            repo_path(run_root)
            / str(key["experiment_id"])
            / "cells"
            / "region={}".format(key["region"])
            / "fold={}".format(int(key["fold"]))
            / "model"
            / "metric_by_horizon_group.csv"
        )
        if not path.exists():
            continue
        metric = pd.read_csv(path)
        required = ["method_id", "split", "unit", "horizon_group", "AQL"]
        require_columns(metric, required, str(path))
        metric = metric[
            metric["method_id"].astype(str).eq(str(key["method_id"]))
            & metric["unit"].astype(str).eq("original")
            & metric["split"].astype(str).eq("test")
        ].copy()
        for _, row in metric.iterrows():
            rows.append({
                "region": key["region"],
                "fold": int(key["fold"]),
                "selection_type": key["selection_type"],
                "experiment_id": key["experiment_id"],
                "method_id": key["method_id"],
                "horizon_group": str(row["horizon_group"]),
                "test_AQL": as_float(row["AQL"]),
                "test_MAE": as_float(row.get("MAE", float("nan"))),
                "test_RMSE": as_float(row.get("RMSE", float("nan"))),
            })
    horizon = pd.DataFrame(rows)
    if horizon.empty:
        return horizon
    wide = horizon.pivot_table(
        index=["region", "fold", "horizon_group"],
        columns="selection_type",
        values="test_AQL",
        aggfunc="first",
    ).reset_index()
    if {"validation_selected", "test_oracle"}.issubset(set(wide.columns)):
        wide["validation_test_regret_vs_oracle"] = wide["validation_selected"] - wide["test_oracle"]
    return wide


def collect_exact_equivalence(manifest, run_root):
    meta = manifest.set_index("experiment_id").to_dict("index")
    rows = []
    for path in sorted(repo_path(run_root).glob("*/cells/region=*/fold=*/model/exact_equivalence.csv")):
        exp_id = experiment_from_metric_path(path, run_root)
        if exp_id not in meta:
            continue
        region, fold = region_fold_from_path(path)
        exact = pd.read_csv(path)
        for _, row in exact.iterrows():
            out = {
                "region": region,
                "fold": fold,
                "experiment_id": exp_id,
                "exact_equivalence": config_path_value(path),
            }
            for col in exact.columns:
                out[col] = row[col]
            for key, val in meta[exp_id].items():
                if key not in out:
                    out[key] = val
            rows.append(out)
    return pd.DataFrame(rows)


def collect_cell_status(run_root, manifest):
    rows = []
    expected = set(manifest["experiment_id"].astype(str))
    for path in sorted(repo_path(run_root).glob("*/cell_status.csv")):
        exp_id = path.parent.name
        if exp_id not in expected:
            continue
        status = pd.read_csv(path)
        for _, row in status.iterrows():
            out = {"experiment_id": exp_id}
            for col in status.columns:
                out[col] = row[col]
            rows.append(out)
    return pd.DataFrame(rows)


def collect_launch_status(grid_root, priorities):
    path = repo_path(Path(grid_root) / "launch_status.csv")
    if not path.exists():
        return pd.DataFrame()
    status = pd.read_csv(path)
    if "priority" in status.columns:
        status = status[
            status["priority"].isna()
            | pd.to_numeric(status["priority"], errors="coerce").isin(priorities)
        ].copy()
    return status


def parse_time_log(path):
    path = repo_path(path)
    if not path.exists():
        return {}
    text = path.read_text()
    out = {"time_log": config_path_value(path)}
    patterns = {
        "elapsed_wall_clock": r"Elapsed \(wall clock\) time \([^)]+\):\s*(.+)",
        "max_rss_kb": r"Maximum resident set size \(kbytes\):\s*(\d+)",
        "exit_status": r"Exit status:\s*(\d+)",
        "cpu_percent": r"Percent of CPU this job got:\s*(.+)",
        "user_seconds": r"User time \(seconds\):\s*([0-9.]+)",
        "system_seconds": r"System time \(seconds\):\s*([0-9.]+)",
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, text)
        if match:
            value = match.group(1).strip()
            out[key] = as_float(value) if key.endswith(("kb", "seconds", "status")) else value
    return out


def count_binary_artifacts(run_root):
    suffixes = {".rds", ".rda", ".RData", ".rdata"}
    count = 0
    for path in repo_path(run_root).rglob("*"):
        if path.is_file() and path.suffix in suffixes:
            count += 1
    return count


def build_health(args, manifest, long_metrics, exact, cell_status, launch_status):
    time_info = parse_time_log(args.time_log)
    expected = len(manifest)
    experiment_launch = launch_status[
        launch_status.get("kind", pd.Series(dtype=str)).astype(str).eq("experiment")
    ] if not launch_status.empty and "kind" in launch_status.columns else launch_status
    metric_file_count = long_metrics["metric_summary"].nunique() if not long_metrics.empty else 0
    exact_passed = int(exact["passed"].astype(bool).sum()) if not exact.empty and "passed" in exact.columns else 0
    exact_rows = len(exact)
    completed_cells = int(cell_status["status"].astype(str).eq("completed").sum()) if not cell_status.empty else 0
    nonzero_launch = 0
    if not experiment_launch.empty and "return_code" in experiment_launch.columns:
        nonzero_launch = int((pd.to_numeric(experiment_launch["return_code"], errors="coerce").fillna(0) != 0).sum())
    health = {
        "expected_priority_experiments": expected,
        "completed_launch_experiments": int(experiment_launch["status"].astype(str).eq("completed").sum()) if not experiment_launch.empty and "status" in experiment_launch.columns else 0,
        "completed_cell_status_rows": completed_cells,
        "metric_files": int(metric_file_count),
        "exact_equivalence_rows": int(exact_rows),
        "exact_equivalence_passed": exact_passed,
        "nonzero_launch_return_codes": nonzero_launch,
        "binary_artifacts": count_binary_artifacts(args.run_root),
        "stage_m_surface_changed": False,
        "run_clean": (
            metric_file_count == expected
            and completed_cells == expected
            and (exact_rows == 0 or exact_passed == exact_rows)
            and nonzero_launch == 0
            and count_binary_artifacts(args.run_root) == 0
        ),
    }
    health.update(time_info)
    return health


def build_summary(args, manifest, validation_selected, test_oracle, transfer, family, health):
    decisions = validation_selected["validation_selected_decision"].value_counts().to_dict() if not validation_selected.empty else {}
    n_validation_pricefm_wins = int(decisions.get("promote_validation_and_test_pricefm_win", 0))
    n_candidate_only = int(decisions.get("candidate_only_beats_current_not_pricefm", 0))
    n_rejected = int(decisions.get("reject_validation_worse_current", 0))
    oracle_beats_current = int((test_oracle["delta_vs_current_AQL"] < 0).sum()) if not test_oracle.empty else 0
    oracle_beats_pricefm = int((test_oracle["delta_vs_pricefm_AQL"] < 0).sum()) if not test_oracle.empty else 0
    stage_w_test_oracle_improves_most = oracle_beats_current >= max(1, math.ceil(0.5 * len(test_oracle)))
    priority1_recommended = bool(n_validation_pricefm_wins > 0 and stage_w_test_oracle_improves_most)
    return {
        "status": "completed",
        "output_dir": config_path_value(args.output_dir),
        "priorities": parse_priorities(args.priorities),
        "n_experiments": int(len(manifest)),
        "n_region_folds": int(manifest[["region", "fold"]].drop_duplicates().shape[0]),
        "run_clean": bool(health["run_clean"]),
        "stage_m_surface_changed": False,
        "priority1_recommended": priority1_recommended,
        "validation_selected_pricefm_wins": n_validation_pricefm_wins,
        "validation_selected_candidate_only_wins": n_candidate_only,
        "validation_selected_rejected": n_rejected,
        "test_oracle_beats_current": oracle_beats_current,
        "test_oracle_beats_pricefm": oracle_beats_pricefm,
        "median_test_regret_vs_oracle": as_float(transfer["test_regret_vs_oracle"].median()) if not transfer.empty else float("nan"),
        "min_validation_test_spearman": as_float(transfer["validation_test_spearman"].min()) if not transfer.empty else float("nan"),
        "max_validation_test_spearman": as_float(transfer["validation_test_spearman"].max()) if not transfer.empty else float("nan"),
        "recommended_next_stage": (
            "build_horizon_aware_selection_failure_contract_before_new_fits"
            if not priority1_recommended
            else "review_validation_selected_promotions_before_priority1"
        ),
    }


def validate_complete(args, manifest, health):
    if not args.require_complete:
        return
    problems = []
    expected = int(health["expected_priority_experiments"])
    if int(health["metric_files"]) != expected:
        problems.append("metric_files {} != expected {}".format(health["metric_files"], expected))
    if int(health["completed_cell_status_rows"]) != expected:
        problems.append("completed_cell_status_rows {} != expected {}".format(health["completed_cell_status_rows"], expected))
    if int(health["nonzero_launch_return_codes"]) != 0:
        problems.append("nonzero launch return codes present")
    if int(health["binary_artifacts"]) != 0:
        problems.append("binary artifacts present")
    if int(health["exact_equivalence_rows"]) and int(health["exact_equivalence_passed"]) != int(health["exact_equivalence_rows"]):
        problems.append("exact equivalence failures present")
    if problems:
        raise RuntimeError("Stage-W closeout completeness failed: {}".format("; ".join(problems)))


def write_report(path, args, summary, health, validation_selected, test_oracle, transfer, family, horizon, exact):
    lines = []
    lines.append("# PriceFM Stage-W Priority-0 Closeout")
    lines.append("")
    lines.append("Stage-W Priority 0 was a region/fold-specific median screen over severe Q-DESN underperformance rows. This closeout uses test metrics only as audit evidence; candidate selection remains validation-only and the Stage-M decision surface is unchanged.")
    lines.append("")
    lines.append("## Health")
    lines.append("")
    lines.append(markdown_table(pd.DataFrame([health]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Decision Summary")
    lines.append("")
    decision = {
        "run_clean": summary["run_clean"],
        "stage_m_surface_changed": summary["stage_m_surface_changed"],
        "priority1_recommended": summary["priority1_recommended"],
        "validation_selected_pricefm_wins": summary["validation_selected_pricefm_wins"],
        "validation_selected_candidate_only_wins": summary["validation_selected_candidate_only_wins"],
        "validation_selected_rejected": summary["validation_selected_rejected"],
        "test_oracle_beats_current": summary["test_oracle_beats_current"],
        "test_oracle_beats_pricefm": summary["test_oracle_beats_pricefm"],
        "recommended_next_stage": summary["recommended_next_stage"],
    }
    lines.append(markdown_table(pd.DataFrame([decision]).T.reset_index().rename(columns={"index": "field", 0: "value"})))
    lines.append("")
    lines.append("## Validation-Selected Rows")
    lines.append("")
    lines.append(markdown_table(
        validation_selected.sort_values(["region", "fold"]),
        [
            "region", "fold", "experiment_id", "method_id", "candidate_family",
            "val_AQL", "test_AQL", "local_AQL", "pricefm_AQL",
            "delta_vs_current_AQL", "delta_vs_pricefm_AQL",
            "validation_selected_decision",
        ],
    ))
    lines.append("")
    lines.append("## Test-Oracle Audit")
    lines.append("")
    lines.append(markdown_table(
        test_oracle.sort_values(["region", "fold"]),
        [
            "region", "fold", "experiment_id", "method_id", "candidate_family",
            "val_AQL", "test_AQL", "local_AQL", "pricefm_AQL",
            "delta_vs_current_AQL", "delta_vs_pricefm_AQL",
        ],
    ))
    lines.append("")
    lines.append("## Validation/Test Transfer")
    lines.append("")
    lines.append(markdown_table(
        transfer.sort_values(["region", "fold"]),
        [
            "region", "fold", "validation_selected_test_AQL", "test_oracle_test_AQL",
            "test_regret_vs_oracle", "validation_test_spearman",
            "oracle_missed_by_validation",
        ],
    ))
    lines.append("")
    lines.append("## Family Audit")
    lines.append("")
    lines.append(markdown_table(
        family.sort_values(["region", "fold", "candidate_family"]),
        [
            "region", "fold", "candidate_family", "best_test_AQL",
            "delta_vs_current_AQL", "delta_vs_pricefm_AQL", "best_experiment_id",
            "best_method_id", "factor_changed",
        ],
        max_rows=30,
    ))
    lines.append("")
    lines.append("## Horizon-Regret Audit")
    lines.append("")
    lines.append(markdown_table(
        horizon.sort_values(["region", "fold", "horizon_group"]),
        ["region", "fold", "horizon_group", "validation_selected", "test_oracle", "validation_test_regret_vs_oracle"],
        max_rows=30,
    ))
    lines.append("")
    lines.append("## Exact Equivalence")
    lines.append("")
    if exact.empty:
        lines.append("_No exact-equivalence rows were found._")
    else:
        exact_summary = pd.DataFrame([{
            "rows": len(exact),
            "passed": int(exact["passed"].astype(bool).sum()) if "passed" in exact.columns else "",
            "max_beta_mean_diff": exact["beta_mean_max_abs_diff"].max() if "beta_mean_max_abs_diff" in exact.columns else float("nan"),
            "max_beta_cov_diff": exact["beta_cov_max_abs_diff"].max() if "beta_cov_max_abs_diff" in exact.columns else float("nan"),
            "max_prediction_diff": exact["train_prediction_max_abs_diff"].max() if "train_prediction_max_abs_diff" in exact.columns else float("nan"),
        }])
        lines.append(markdown_table(exact_summary))
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- Priority 0 completed cleanly and should be kept as negative/diagnostic evidence.")
    if summary["priority1_recommended"]:
        lines.append("- Priority 1 is not automatically launched by this script; validation-selected wins require manual review before further compute.")
    else:
        lines.append("- Priority 1 is not recommended from this closeout because validation-selected rows do not provide enough reliable test improvement.")
    lines.append("- The next step should diagnose validation/test transfer and horizon-specific failure modes before launching another large search family.")
    lines.append("")
    repo_path(path).write_text("\n".join(lines) + "\n")


def closeout(args):
    priorities = parse_priorities(args.priorities)
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError("{} already exists; re-run with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(args.grid_root, args.plan_dir, priorities)
    long_metrics = collect_long_metrics(manifest, args.run_root)
    qdesn_metrics = build_qdesn_method_metrics(long_metrics)
    validation_selected = add_decision_columns(
        choose_min(qdesn_metrics, ["region", "fold"], "val_AQL", "validation_selected")
    )
    test_oracle = add_decision_columns(
        choose_min(qdesn_metrics, ["region", "fold"], "test_AQL", "test_oracle")
    )
    transfer = build_validation_transfer(qdesn_metrics, validation_selected, test_oracle)
    family = build_family_summary(qdesn_metrics)
    horizon = collect_horizon_metrics(qdesn_metrics, args.run_root, validation_selected, test_oracle)
    exact = collect_exact_equivalence(manifest, args.run_root)
    cell_status = collect_cell_status(args.run_root, manifest)
    launch_status = collect_launch_status(args.grid_root, priorities)
    health = build_health(args, manifest, long_metrics, exact, cell_status, launch_status)
    validate_complete(args, manifest, health)
    summary = build_summary(args, manifest, validation_selected, test_oracle, transfer, family, health)

    write_frame(output_dir / "stage_w_priority0_health.csv", pd.DataFrame([health]))
    write_frame(output_dir / "stage_w_priority0_long_metrics.csv", long_metrics)
    write_frame(output_dir / "stage_w_priority0_qdesn_method_metrics.csv", qdesn_metrics)
    write_frame(output_dir / "stage_w_priority0_validation_selected.csv", validation_selected)
    write_frame(output_dir / "stage_w_priority0_test_oracle_audit.csv", test_oracle)
    write_frame(output_dir / "stage_w_priority0_validation_transfer.csv", transfer)
    write_frame(output_dir / "stage_w_priority0_family_summary.csv", family)
    write_frame(output_dir / "stage_w_priority0_horizon_gap_summary.csv", horizon)
    write_frame(output_dir / "stage_w_priority0_exact_equivalence.csv", exact)
    write_report(
        output_dir / "stage_w_priority0_report.md",
        args,
        summary,
        health,
        validation_selected,
        test_oracle,
        transfer,
        family,
        horizon,
        exact,
    )
    outputs = {
        "health_csv": config_path_value(output_dir / "stage_w_priority0_health.csv"),
        "long_metrics_csv": config_path_value(output_dir / "stage_w_priority0_long_metrics.csv"),
        "qdesn_method_metrics_csv": config_path_value(output_dir / "stage_w_priority0_qdesn_method_metrics.csv"),
        "validation_selected_csv": config_path_value(output_dir / "stage_w_priority0_validation_selected.csv"),
        "test_oracle_audit_csv": config_path_value(output_dir / "stage_w_priority0_test_oracle_audit.csv"),
        "validation_transfer_csv": config_path_value(output_dir / "stage_w_priority0_validation_transfer.csv"),
        "family_summary_csv": config_path_value(output_dir / "stage_w_priority0_family_summary.csv"),
        "horizon_gap_summary_csv": config_path_value(output_dir / "stage_w_priority0_horizon_gap_summary.csv"),
        "exact_equivalence_csv": config_path_value(output_dir / "stage_w_priority0_exact_equivalence.csv"),
        "report_md": config_path_value(output_dir / "stage_w_priority0_report.md"),
    }
    summary["outputs"] = outputs
    write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    return closeout(parser().parse_args())


if __name__ == "__main__":
    main()
