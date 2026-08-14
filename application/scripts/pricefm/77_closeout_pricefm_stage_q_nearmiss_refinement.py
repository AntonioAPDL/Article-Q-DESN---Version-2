#!/usr/bin/env python3
"""Close out the Stage-Q PriceFM near-miss refinement run.

Stage Q is a median-only, validation-selected refinement screen over the two
Stage-P near misses.  This closeout is deliberately conservative: it may record
negative or positive evidence, but it never mutates the article decision
surface and it never promotes a candidate from test-oracle performance.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_PLAN_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_plan_20260626"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_q_nearmiss_refinement_20260626"
)
DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_q_nearmiss_refinement_20260626"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_q_nearmiss_refinement_closeout_20260626"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--plan-dir", default=DEFAULT_PLAN_DIR)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--grid-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--scan-logs", type=parse_bool, default=True)
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


def numeric(frame, col):
    if col not in frame.columns:
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if pd.notna(out) else default


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
    rows = []
    for _, row in work.iterrows():
        vals = []
        for col in headers:
            value = row[col]
            if isinstance(value, float):
                if math.isnan(value):
                    vals.append("")
                else:
                    vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value))
        rows.append(vals)
    out = ["| {} |".format(" | ".join(headers))]
    out.append("| {} |".format(" | ".join(["---"] * len(headers))))
    for row in rows:
        out.append("| {} |".format(" | ".join(row)))
    return "\n".join(out)


def normalize_manifest(manifest):
    require_columns(
        manifest,
        [
            "region", "fold", "experiment_id", "priority", "stage_q_decision",
            "candidate_family", "factor_changed", "stage_p_AQL", "pricefm_AQL",
        ],
        "Stage-Q manifest",
    )
    out = manifest.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["priority"] = pd.to_numeric(out["priority"], errors="raise").astype(int)
    if out["experiment_id"].duplicated().any():
        dup = out[out["experiment_id"].duplicated(keep=False)]["experiment_id"].tolist()
        raise ValueError("Stage-Q manifest has duplicate experiment IDs: {}".format(dup))
    return out


def normalize_decisions(decisions):
    require_columns(
        decisions,
        ["region", "fold", "AQL", "pricefm_phase1_AQL", "stage_q_decision"],
        "Stage-Q decisions",
    )
    out = decisions.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    out["stage_p_test_AQL"] = numeric(out, "AQL")
    out["pricefm_test_AQL"] = numeric(out, "pricefm_phase1_AQL")
    out["stage_p_val_AQL"] = numeric(out, "selection_AQL")
    keep = [
        "region", "fold", "stage_q_decision", "stage_q_priority",
        "stage_q_action", "experiment_id", "stage_p_method_id",
        "stage_p_test_AQL", "stage_p_val_AQL", "pricefm_test_AQL",
        "decision_label", "current_surface_local_AQL",
        "current_surface_pricefm_AQL",
    ]
    return out[[col for col in keep if col in out.columns]].copy()


def metric_paths(run_root):
    return sorted(repo_path(run_root).glob("*/cells/region=*/fold=*/model/metric_summary.csv"))


def experiment_from_metric_path(path):
    parts = path.parts
    try:
        idx = parts.index(repo_path(DEFAULT_RUN_ROOT).name)
        return parts[idx + 1]
    except ValueError:
        # The path may live under a temp run root during tests.
        for i, part in enumerate(parts):
            if i + 1 < len(parts) and parts[i + 1] == "cells":
                return part
    raise ValueError("Cannot infer experiment id from {}".format(path))


def region_fold_from_metric_path(path):
    region = None
    fold = None
    for part in path.parts:
        if part.startswith("region="):
            region = part.split("=", 1)[1]
        if part.startswith("fold="):
            fold = int(part.split("=", 1)[1])
    if region is None or fold is None:
        raise ValueError("Cannot infer region/fold from {}".format(path))
    return region, fold


def collect_metric_pairs(manifest, run_root):
    meta = manifest.set_index("experiment_id").to_dict("index")
    rows = []
    long_rows = []
    for path in metric_paths(run_root):
        exp_id = experiment_from_metric_path(path)
        region, fold = region_fold_from_metric_path(path)
        metric = pd.read_csv(path)
        require_columns(metric, ["method_id", "split", "unit", "AQL"], str(path))
        metric = metric[metric["unit"].astype(str).eq("original")].copy()
        for _, row in metric.iterrows():
            long_row = {
                "region": region,
                "fold": fold,
                "experiment_id": exp_id,
                "metric_summary": config_path_value(path),
                "method_id": str(row["method_id"]),
                "split": str(row["split"]),
                "unit": str(row["unit"]),
            }
            for col in ["AQL", "AQCR", "MAE", "RMSE"]:
                if col in row.index:
                    long_row[col] = as_float(row[col])
            long_row.update({k: v for k, v in meta.get(exp_id, {}).items() if k not in long_row})
            long_rows.append(long_row)

        for method_id, sub in metric.groupby(metric["method_id"].astype(str), sort=False):
            out = {
                "region": region,
                "fold": fold,
                "experiment_id": exp_id,
                "method_id": method_id,
                "metric_summary": config_path_value(path),
            }
            out.update(meta.get(exp_id, {}))
            for _, row in sub.iterrows():
                split = str(row["split"])
                for col in ["AQL", "AQCR", "MAE", "RMSE"]:
                    if col in row.index:
                        out["{}_{}".format(split, col)] = as_float(row[col])
            rows.append(out)
    pairs = pd.DataFrame(rows)
    long_metrics = pd.DataFrame(long_rows)
    if not pairs.empty:
        pairs["region"] = pairs["region"].astype(str)
        pairs["fold"] = pd.to_numeric(pairs["fold"], errors="raise").astype(int)
    return pairs, long_metrics


def collect_horizon_metrics(manifest, run_root, filename):
    meta = manifest.set_index("experiment_id").to_dict("index")
    rows = []
    for metric_path in sorted(repo_path(run_root).glob("*/cells/region=*/fold=*/model/{}".format(filename))):
        exp_id = experiment_from_metric_path(metric_path)
        region, fold = region_fold_from_metric_path(metric_path)
        metric = pd.read_csv(metric_path)
        require_columns(metric, ["method_id", "split", "unit", "AQL"], str(metric_path))
        metric = metric[
            metric["unit"].astype(str).eq("original")
            & metric["split"].astype(str).eq("test")
        ].copy()
        for _, row in metric.iterrows():
            out = {
                "region": region,
                "fold": fold,
                "experiment_id": exp_id,
                "method_id": str(row["method_id"]),
                "metric_file": config_path_value(metric_path),
            }
            out.update({k: v for k, v in meta.get(exp_id, {}).items() if k not in out})
            for col in ["horizon", "horizon_group", "AQL", "AQCR", "MAE", "RMSE"]:
                if col in row.index:
                    out[col] = row[col]
            rows.append(out)
    return pd.DataFrame(rows)


def qdesn_only(frame):
    if frame.empty:
        return frame
    return frame[frame["method_id"].astype(str).str.startswith("qdesn")].copy()


def select_best(frame, value_col, label):
    if frame.empty:
        return pd.DataFrame()
    eligible = frame[frame[value_col].notna()].copy()
    if eligible.empty:
        return pd.DataFrame()
    eligible = eligible.sort_values(["region", "fold", value_col, "experiment_id", "method_id"])
    out = eligible.groupby(["region", "fold"], as_index=False).first()
    out["selection_view"] = label
    return out


def attach_reference(frame, decisions):
    if frame.empty:
        return frame
    out = frame.merge(
        decisions,
        on=["region", "fold"],
        how="left",
        suffixes=("", "_stagep"),
        validate="many_to_one",
    )
    out["delta_test_vs_stage_p"] = numeric(out, "test_AQL") - numeric(out, "stage_p_test_AQL")
    out["delta_test_vs_pricefm"] = numeric(out, "test_AQL") - numeric(out, "pricefm_test_AQL")
    out["delta_val_vs_stage_p"] = numeric(out, "val_AQL") - numeric(out, "stage_p_val_AQL")
    out["beats_stage_p_test"] = out["delta_test_vs_stage_p"] < 0.0
    out["beats_pricefm_test"] = out["delta_test_vs_pricefm"] < 0.0
    out["eligible_for_quantile_confirmation"] = (
        out["beats_stage_p_test"] & out["delta_val_vs_stage_p"].le(0.0)
    )
    out["closeout_decision"] = "do_not_promote_stage_q"
    out.loc[
        out["eligible_for_quantile_confirmation"],
        "closeout_decision",
    ] = "queue_only_if_authorized_for_paper_quantile_confirmation"
    return out


def build_target_summary(pairs, decisions):
    q = qdesn_only(pairs)
    selected = attach_reference(select_best(q, "val_AQL", "validation_selected"), decisions)
    oracle = attach_reference(select_best(q, "test_AQL", "test_oracle_audit_only"), decisions)
    if selected.empty:
        return pd.DataFrame(), selected, oracle
    keep_oracle = [
        "region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL",
        "delta_test_vs_stage_p", "delta_test_vs_pricefm",
    ]
    oracle_small = oracle[[col for col in keep_oracle if col in oracle.columns]].rename(columns={
        "experiment_id": "oracle_experiment_id",
        "method_id": "oracle_method_id",
        "val_AQL": "oracle_val_AQL",
        "test_AQL": "oracle_test_AQL",
        "delta_test_vs_stage_p": "oracle_delta_test_vs_stage_p",
        "delta_test_vs_pricefm": "oracle_delta_test_vs_pricefm",
    })
    out = selected.merge(oracle_small, on=["region", "fold"], how="left", validate="one_to_one")
    out["validation_selected_test_regret"] = out["test_AQL"] - out["oracle_test_AQL"]
    out["oracle_same_as_validation_selected"] = (
        out["experiment_id"].astype(str).eq(out["oracle_experiment_id"].astype(str))
        & out["method_id"].astype(str).eq(out["oracle_method_id"].astype(str))
    )
    cols = [
        "region", "fold", "stage_q_decision", "experiment_id", "method_id",
        "val_AQL", "test_AQL", "stage_p_val_AQL", "stage_p_test_AQL",
        "pricefm_test_AQL", "delta_val_vs_stage_p", "delta_test_vs_stage_p",
        "delta_test_vs_pricefm", "oracle_experiment_id", "oracle_method_id",
        "oracle_val_AQL", "oracle_test_AQL", "oracle_delta_test_vs_stage_p",
        "oracle_delta_test_vs_pricefm", "validation_selected_test_regret",
        "oracle_same_as_validation_selected", "eligible_for_quantile_confirmation",
        "closeout_decision",
    ]
    return out[[col for col in cols if col in out.columns]], selected, oracle


def build_selection_transfer(pairs, decisions):
    q = qdesn_only(pairs).copy()
    if q.empty:
        return pd.DataFrame()
    rows = []
    for (region, fold), sub in q.groupby(["region", "fold"], sort=True):
        work = sub.copy()
        work["val_rank"] = work["val_AQL"].rank(method="average", na_option="bottom")
        work["test_rank"] = work["test_AQL"].rank(method="average", na_option="bottom")
        spearman = work["val_rank"].corr(work["test_rank"])
        selected = work.sort_values(["val_AQL", "experiment_id", "method_id"]).iloc[0]
        oracle = work.sort_values(["test_AQL", "experiment_id", "method_id"]).iloc[0]
        ref = decisions[
            decisions["region"].astype(str).eq(str(region))
            & decisions["fold"].astype(int).eq(int(fold))
        ]
        stage_p_test = as_float(ref["stage_p_test_AQL"].iloc[0]) if not ref.empty else float("nan")
        pricefm = as_float(ref["pricefm_test_AQL"].iloc[0]) if not ref.empty else float("nan")
        rows.append({
            "region": region,
            "fold": int(fold),
            "n_qdesn_candidates": int(work.shape[0]),
            "spearman_val_test_rank": as_float(spearman),
            "validation_selected_experiment_id": selected["experiment_id"],
            "validation_selected_method_id": selected["method_id"],
            "validation_selected_val_AQL": as_float(selected["val_AQL"]),
            "validation_selected_test_AQL": as_float(selected["test_AQL"]),
            "test_oracle_experiment_id": oracle["experiment_id"],
            "test_oracle_method_id": oracle["method_id"],
            "test_oracle_val_AQL": as_float(oracle["val_AQL"]),
            "test_oracle_test_AQL": as_float(oracle["test_AQL"]),
            "validation_selected_test_regret": as_float(selected["test_AQL"] - oracle["test_AQL"]),
            "selected_delta_test_vs_stage_p": as_float(selected["test_AQL"] - stage_p_test),
            "selected_delta_test_vs_pricefm": as_float(selected["test_AQL"] - pricefm),
            "oracle_delta_test_vs_stage_p": as_float(oracle["test_AQL"] - stage_p_test),
            "oracle_delta_test_vs_pricefm": as_float(oracle["test_AQL"] - pricefm),
            "same_candidate": bool(
                str(selected["experiment_id"]) == str(oracle["experiment_id"])
                and str(selected["method_id"]) == str(oracle["method_id"])
            ),
        })
    return pd.DataFrame(rows)


def build_family_diagnostics(pairs):
    q = qdesn_only(pairs).copy()
    if q.empty:
        return pd.DataFrame()
    group_cols = [
        "region", "fold", "candidate_family", "factor_changed",
        "graph_degree", "method_id",
    ]
    for col in group_cols:
        if col not in q.columns:
            q[col] = ""
    rows = []
    for keys, sub in q.groupby(group_cols, dropna=False, sort=True):
        best_val = sub.sort_values(["val_AQL", "experiment_id"]).iloc[0]
        best_test = sub.sort_values(["test_AQL", "experiment_id"]).iloc[0]
        row = dict(zip(group_cols, keys))
        row.update({
            "n_candidates": int(sub.shape[0]),
            "best_val_AQL": as_float(best_val["val_AQL"]),
            "best_val_test_AQL": as_float(best_val["test_AQL"]),
            "best_val_experiment_id": best_val["experiment_id"],
            "best_test_AQL": as_float(best_test["test_AQL"]),
            "best_test_val_AQL": as_float(best_test["val_AQL"]),
            "best_test_experiment_id": best_test["experiment_id"],
            "mean_test_AQL": as_float(sub["test_AQL"].mean()),
            "median_test_AQL": as_float(sub["test_AQL"].median()),
        })
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["region", "fold", "best_test_AQL"])


def method_class(method_id):
    method_id = str(method_id)
    if method_id.startswith("qdesn"):
        return "qdesn"
    if method_id.startswith("normal"):
        return "normal_desn"
    if method_id.startswith("naive"):
        return "naive"
    return "other"


def build_baseline_summary(pairs):
    if pairs.empty:
        return pd.DataFrame()
    work = pairs.copy()
    work["method_class"] = work["method_id"].map(method_class)
    rows = []
    for (region, fold, klass), sub in work.groupby(["region", "fold", "method_class"], sort=True):
        best = sub.sort_values(["test_AQL", "experiment_id", "method_id"]).iloc[0]
        rows.append({
            "region": region,
            "fold": int(fold),
            "method_class": klass,
            "best_test_AQL": as_float(best["test_AQL"]),
            "best_test_MAE": as_float(best.get("test_MAE", float("nan"))),
            "best_test_RMSE": as_float(best.get("test_RMSE", float("nan"))),
            "best_method_id": best["method_id"],
            "best_experiment_id": best["experiment_id"],
        })
    return pd.DataFrame(rows).sort_values(["region", "fold", "best_test_AQL"])


def build_selected_horizon_diagnostics(horizon_group, selected, oracle):
    if horizon_group.empty or selected.empty:
        return pd.DataFrame()
    views = []
    for view_name, frame in [
        ("validation_selected", selected),
        ("test_oracle_audit_only", oracle),
    ]:
        if frame.empty:
            continue
        small = frame[["region", "fold", "experiment_id", "method_id"]].copy()
        small["selection_view"] = view_name
        views.append(small)
    if not views:
        return pd.DataFrame()
    keys = pd.concat(views, ignore_index=True)
    h = horizon_group.copy()
    h["fold"] = pd.to_numeric(h["fold"], errors="raise").astype(int)
    out = keys.merge(
        h,
        on=["region", "fold", "experiment_id", "method_id"],
        how="left",
        validate="one_to_many",
    )
    return out.sort_values(["region", "fold", "selection_view", "horizon_group"])


def build_best_horizon_group(horizon_group):
    q = qdesn_only(horizon_group).copy()
    if q.empty or "horizon_group" not in q.columns:
        return pd.DataFrame()
    q["AQL"] = numeric(q, "AQL")
    q = q[q["AQL"].notna()].copy()
    q = q.sort_values(["region", "fold", "horizon_group", "AQL", "experiment_id", "method_id"])
    out = q.groupby(["region", "fold", "horizon_group"], as_index=False).first()
    cols = [
        "region", "fold", "horizon_group", "AQL", "MAE", "RMSE",
        "experiment_id", "method_id", "candidate_family", "factor_changed",
        "graph_degree",
    ]
    return out[[col for col in cols if col in out.columns]]


def binary_artifact_count(run_root):
    patterns = ["*.rds", "*.rda", "*.RData", "*.rdata"]
    total = 0
    for pattern in patterns:
        total += sum(1 for _ in repo_path(run_root).glob("**/{}".format(pattern)))
    return total


def scan_logs(run_root):
    patterns = ["error", "failed", "traceback", "non-finite", "nan", "warning"]
    counts = {pat: 0 for pat in patterns}
    examples = {pat: [] for pat in patterns}
    for path in repo_path(run_root).glob("*/logs/*.log"):
        text = path.read_text(errors="ignore")
        for pat in patterns:
            if re.search(pat, text, re.IGNORECASE):
                counts[pat] += 1
                if len(examples[pat]) < 5:
                    examples[pat].append(config_path_value(path))
    rows = []
    for pat in patterns:
        rows.append({
            "pattern": pat,
            "n_logs": int(counts[pat]),
            "examples": ";".join(examples[pat]),
        })
    return pd.DataFrame(rows)


def build_health(manifest, launch_status, pairs, run_root, args):
    priority0 = manifest[manifest["priority"].eq(0)].copy()
    experiment_launch = launch_status[launch_status.get("kind", "").astype(str).eq("experiment")].copy()
    completed_exps = set(pairs["experiment_id"].astype(str)) if not pairs.empty else set()
    metric_files = len(metric_paths(run_root))
    health = pd.DataFrame([{
        "priority0_manifest_rows": int(priority0.shape[0]),
        "launch_rows": int(launch_status.shape[0]),
        "launch_experiment_rows": int(experiment_launch.shape[0]),
        "launch_completed_rows": int(launch_status["status"].astype(str).eq("completed").sum())
        if "status" in launch_status.columns else 0,
        "launch_nonzero_return_codes": int(
            pd.to_numeric(launch_status.get("return_code", pd.Series(dtype=float)), errors="coerce")
            .fillna(0)
            .ne(0)
            .sum()
        ),
        "metric_summary_files": int(metric_files),
        "completed_priority0_experiments": int(len(completed_exps.intersection(set(priority0["experiment_id"].astype(str))))),
        "binary_fit_artifacts": int(binary_artifact_count(run_root)),
        "scan_logs": bool(args.scan_logs),
    }])
    health["all_priority0_metrics_present"] = (
        health["completed_priority0_experiments"].iloc[0] == health["priority0_manifest_rows"].iloc[0]
    )
    health["all_launch_rows_completed"] = (
        health["launch_completed_rows"].iloc[0] == health["launch_rows"].iloc[0]
    )
    health["run_clean"] = (
        health["all_priority0_metrics_present"].iloc[0]
        and health["all_launch_rows_completed"].iloc[0]
        and health["launch_nonzero_return_codes"].iloc[0] == 0
        and health["binary_fit_artifacts"].iloc[0] == 0
    )
    return health


def write_report(path, summary, health, target_summary, transfer, family, baseline, horizon_selected):
    lines = [
        "# PriceFM Stage-Q near-miss refinement closeout",
        "",
        "Stage Q was a median-only validation-selected refinement of the two Stage-P near misses. "
        "The completed priority-0 run is treated as evidence only; it does not mutate the "
        "article-facing decision surface.",
        "",
        "## Health",
        "",
        markdown_table(health),
        "",
        "## Target Decisions",
        "",
        markdown_table(target_summary, [
            "region", "fold", "experiment_id", "method_id", "val_AQL", "test_AQL",
            "stage_p_test_AQL", "pricefm_test_AQL", "delta_test_vs_stage_p",
            "delta_test_vs_pricefm", "oracle_experiment_id", "oracle_test_AQL",
            "validation_selected_test_regret", "closeout_decision",
        ]),
        "",
        "## Selection Transfer",
        "",
        markdown_table(transfer, [
            "region", "fold", "n_qdesn_candidates", "spearman_val_test_rank",
            "validation_selected_test_regret", "selected_delta_test_vs_stage_p",
            "selected_delta_test_vs_pricefm", "oracle_delta_test_vs_stage_p",
            "oracle_delta_test_vs_pricefm", "same_candidate",
        ]),
        "",
        "## Best Method-Class Audit",
        "",
        markdown_table(baseline, [
            "region", "fold", "method_class", "best_test_AQL",
            "best_method_id", "best_experiment_id",
        ], max_rows=20),
        "",
        "## Best Q-DESN Family Audit",
        "",
        markdown_table(family, [
            "region", "fold", "candidate_family", "factor_changed", "graph_degree",
            "method_id", "n_candidates", "best_val_AQL", "best_val_test_AQL",
            "best_test_AQL", "best_test_experiment_id",
        ], max_rows=30),
        "",
        "## Horizon-Group Audit",
        "",
        markdown_table(horizon_selected, [
            "region", "fold", "selection_view", "horizon_group", "AQL", "MAE",
            "RMSE", "experiment_id", "method_id",
        ], max_rows=30),
        "",
        "## Interpretation",
        "",
        "- Stage-Q priority 0 completed cleanly.",
        "- No validation-selected Stage-Q row should be promoted.",
        "- The current Stage-M decision surface should remain unchanged.",
        "- Stage-Q priority 1 should remain unlaunched until the validation/test transfer issue is understood.",
        "- The next useful work is diagnostic: selection transfer, horizon blocks, and information-set parity with PriceFM.",
        "",
        "## Output Manifest",
        "",
    ]
    for key, value in sorted(summary.items()):
        lines.append("- `{}`: `{}`".format(key, value))
    repo_path(path).parent.mkdir(parents=True, exist_ok=True)
    repo_path(path).write_text("\n".join(lines) + "\n")


def closeout(args):
    plan_dir = repo_path(args.plan_dir)
    run_root = repo_path(args.run_root)
    grid_root = repo_path(args.grid_root)
    output_dir = repo_path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = normalize_manifest(read_csv_required(plan_dir / "stage_q_median_refinement_manifest.csv", "Stage-Q manifest"))
    decisions = normalize_decisions(read_csv_required(plan_dir / "stage_q_stage_p_closeout_decisions.csv", "Stage-Q decisions"))
    launch_status = read_csv_required(grid_root / "launch_status.csv", "Stage-Q launch status")

    pairs, long_metrics = collect_metric_pairs(manifest, run_root)
    horizon_group = collect_horizon_metrics(manifest, run_root, "metric_by_horizon_group.csv")
    horizon = collect_horizon_metrics(manifest, run_root, "metric_by_horizon.csv")

    health = build_health(manifest, launch_status, pairs, run_root, args)
    target_summary, selected, oracle = build_target_summary(pairs, decisions)
    transfer = build_selection_transfer(pairs, decisions)
    family = build_family_diagnostics(pairs)
    baseline = build_baseline_summary(pairs)
    horizon_selected = build_selected_horizon_diagnostics(horizon_group, selected, oracle)
    horizon_best = build_best_horizon_group(horizon_group)
    log_scan = scan_logs(run_root) if args.scan_logs else pd.DataFrame()

    no_stage_q_promotions = bool(
        target_summary.empty
        or not target_summary["eligible_for_quantile_confirmation"].fillna(False).any()
    )
    summary = {
        "status": "completed",
        "plan_dir": config_path_value(plan_dir),
        "run_root": config_path_value(run_root),
        "grid_root": config_path_value(grid_root),
        "output_dir": config_path_value(output_dir),
        "n_manifest_rows": int(manifest.shape[0]),
        "n_priority0_manifest_rows": int(manifest["priority"].eq(0).sum()),
        "n_metric_summary_files": int(len(metric_paths(run_root))),
        "n_metric_pairs": int(pairs.shape[0]),
        "n_qdesn_pairs": int(qdesn_only(pairs).shape[0]),
        "n_horizon_group_rows": int(horizon_group.shape[0]),
        "n_horizon_rows": int(horizon.shape[0]),
        "run_clean": bool(health["run_clean"].iloc[0]),
        "no_stage_q_promotions_recommended": no_stage_q_promotions,
        "stage_m_surface_changed": False,
        "selection_rule": "median_validation_AQL_only",
        "test_metrics_role": "audit_only",
        "priority1_launch_recommended": False,
        "next_recommended_stage": "diagnose_validation_test_transfer_before_any_new_search",
    }

    outputs = {
        "summary_json": output_dir / "summary.json",
        "health_csv": output_dir / "stage_q_priority0_health.csv",
        "metric_pairs_csv": output_dir / "stage_q_metric_pairs.csv",
        "long_metrics_csv": output_dir / "stage_q_long_metrics.csv",
        "target_summary_csv": output_dir / "stage_q_priority0_closeout_summary.csv",
        "validation_selected_csv": output_dir / "stage_q_target_best_by_validation.csv",
        "test_oracle_csv": output_dir / "stage_q_target_best_by_test_audit.csv",
        "selection_transfer_csv": output_dir / "stage_q_selection_transfer_diagnostics.csv",
        "family_diagnostics_csv": output_dir / "stage_q_family_diagnostics.csv",
        "baseline_summary_csv": output_dir / "stage_q_method_class_baseline_summary.csv",
        "horizon_selected_csv": output_dir / "stage_q_selected_horizon_group_diagnostics.csv",
        "horizon_best_csv": output_dir / "stage_q_best_horizon_group_diagnostics.csv",
        "log_scan_csv": output_dir / "stage_q_log_scan.csv",
        "report_md": output_dir / "stage_q_closeout_report.md",
    }
    summary["outputs"] = {key: config_path_value(value) for key, value in outputs.items()}

    write_json(outputs["summary_json"], summary)
    write_frame(outputs["health_csv"], health)
    write_frame(outputs["metric_pairs_csv"], pairs)
    write_frame(outputs["long_metrics_csv"], long_metrics)
    write_frame(outputs["target_summary_csv"], target_summary)
    write_frame(outputs["validation_selected_csv"], selected)
    write_frame(outputs["test_oracle_csv"], oracle)
    write_frame(outputs["selection_transfer_csv"], transfer)
    write_frame(outputs["family_diagnostics_csv"], family)
    write_frame(outputs["baseline_summary_csv"], baseline)
    write_frame(outputs["horizon_selected_csv"], horizon_selected)
    write_frame(outputs["horizon_best_csv"], horizon_best)
    write_frame(outputs["log_scan_csv"], log_scan)
    write_report(outputs["report_md"], summary, health, target_summary, transfer, family, baseline, horizon_selected)

    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    args = parser().parse_args()
    closeout(args)


if __name__ == "__main__":
    main()
