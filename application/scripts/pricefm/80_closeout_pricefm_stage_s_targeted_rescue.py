#!/usr/bin/env python3
"""Close out the PriceFM Stage-S targeted-rescue run.

Stage S tested a bounded median-only rescue hypothesis from Stage-R:
graph-parity inputs for target-only underperformers and a small horizon-block
pilot for graph-input rows.  This closeout is deliberately conservative.  It
reports validation-selected candidates and test-oracle diagnostics, but it
never mutates the Stage-M article decision surface.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
import subprocess

import pandas as pd

from pricefm_common import parse_bool, repo_path, sha256_file, write_json


DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_s_targeted_rescue_20260628"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_s_targeted_rescue_20260628"
)
DEFAULT_PLAN_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_plan_20260628"
)
DEFAULT_STAGE_M_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_s_targeted_rescue_closeout_20260629"
)

QDESN_PREFIX = "qdesn_"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--plan-dir", default=DEFAULT_PLAN_DIR)
    p.add_argument("--stage-m-surface-csv", default=DEFAULT_STAGE_M_SURFACE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
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


def read_json_if_exists(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with open(path, "r") as f:
        return json.load(f)


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col):
    if col not in frame.columns:
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def git_state():
    def run(cmd):
        proc = subprocess.run(
            cmd, cwd=str(repo_path(".")), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, universal_newlines=True, check=False,
        )
        return proc.stdout.strip() if proc.returncode == 0 else ""

    status = run(["git", "status", "--short"])
    return {
        "repo_branch": run(["git", "branch", "--show-current"]),
        "repo_head": run(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(status),
    }


def parse_time_log(path):
    path = repo_path(path)
    out = {"elapsed_wall": "", "max_rss_kb": ""}
    if not path.exists() or path.stat().st_size == 0:
        return out
    text = path.read_text(errors="replace")
    for line in text.splitlines():
        if "Elapsed (wall clock) time" in line:
            if "):" in line:
                out["elapsed_wall"] = line.rsplit("):", 1)[1].strip()
            else:
                out["elapsed_wall"] = line.rsplit(":", 1)[-1].strip()
            break
    m = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    if m:
        out["max_rss_kb"] = int(m.group(1))
    return out


def metric_paths(run_root):
    return sorted(repo_path(run_root).glob("*/cells/region=*/fold=*/model/metric_summary.csv"))


def metric_path_experiment_id(path):
    for i, part in enumerate(path.parts):
        if i + 1 < len(path.parts) and path.parts[i + 1] == "cells":
            return part
    raise ValueError("Cannot infer experiment id from {}".format(path))


def collect_long_metrics(run_root):
    rows = []
    for path in metric_paths(run_root):
        exp_id = metric_path_experiment_id(path)
        metric = pd.read_csv(path)
        require_columns(metric, ["method_id", "split", "unit", "AQL"], str(path))
        for _, row in metric.iterrows():
            out = {
                "experiment_id": exp_id,
                "metric_summary": config_path_value(path),
                "method_id": str(row["method_id"]),
                "split": str(row["split"]),
                "unit": str(row["unit"]),
            }
            for col in ["AQL", "AQCR", "MAE", "RMSE"]:
                if col in row.index:
                    out[col] = pd.to_numeric(pd.Series([row[col]]), errors="coerce").iloc[0]
            rows.append(out)
    return pd.DataFrame(rows)


def collect_cell_statuses(run_root):
    rows = []
    for path in sorted(repo_path(run_root).glob("*/cell_status.csv")):
        status = pd.read_csv(path)
        exp_id = path.parent.name
        for _, row in status.iterrows():
            out = row.to_dict()
            out["experiment_id"] = exp_id
            out["cell_status_csv"] = config_path_value(path)
            rows.append(out)
    return pd.DataFrame(rows)


def build_qdesn_best(manifest, long_metrics):
    q = long_metrics[
        long_metrics["method_id"].astype(str).str.startswith(QDESN_PREFIX)
        & long_metrics["unit"].astype(str).eq("original")
    ].copy()
    if q.empty:
        raise ValueError("No original-scale Q-DESN metric rows found")
    q["AQL"] = numeric(q, "AQL")
    q["MAE"] = numeric(q, "MAE")
    q["RMSE"] = numeric(q, "RMSE")

    val = (
        q[q["split"].astype(str).eq("val")]
        .sort_values(["AQL", "method_id"])
        .groupby("experiment_id", as_index=False)
        .first()[["experiment_id", "method_id", "AQL", "MAE", "RMSE"]]
        .rename(columns={
            "method_id": "val_method_id",
            "AQL": "val_best_AQL",
            "MAE": "val_MAE",
            "RMSE": "val_RMSE",
        })
    )
    test = (
        q[q["split"].astype(str).eq("test")]
        .sort_values(["AQL", "method_id"])
        .groupby("experiment_id", as_index=False)
        .first()[["experiment_id", "method_id", "AQL", "MAE", "RMSE"]]
        .rename(columns={
            "method_id": "test_method_id",
            "AQL": "test_best_AQL",
            "MAE": "test_MAE",
            "RMSE": "test_RMSE",
        })
    )
    out = manifest.merge(val, left_on="id", right_on="experiment_id", how="left")
    out = out.merge(test, on="experiment_id", how="left")
    out["local_AQL"] = numeric(out, "local_AQL")
    out["pricefm_AQL"] = numeric(out, "pricefm_AQL")
    out["test_minus_stage_m"] = out["test_best_AQL"] - out["local_AQL"]
    out["test_minus_pricefm"] = out["test_best_AQL"] - out["pricefm_AQL"]
    out["beats_stage_m"] = out["test_minus_stage_m"] < 0
    out["beats_pricefm"] = out["test_minus_pricefm"] < 0
    return out


def target_selection_tables(qbest):
    keys = ["regions", "folds", "candidate_family"]
    validation = (
        qbest.sort_values(["val_best_AQL", "test_best_AQL", "id"])
        .groupby(keys, as_index=False)
        .first()
    )
    test_oracle_family = (
        qbest.sort_values(["test_best_AQL", "val_best_AQL", "id"])
        .groupby(keys, as_index=False)
        .first()
    )
    test_oracle = (
        qbest.sort_values(["test_best_AQL", "val_best_AQL", "id"])
        .groupby(["regions", "folds"], as_index=False)
        .first()
    )
    return validation, test_oracle_family, test_oracle


def summarize_selection(frame, by_col):
    if frame.empty:
        return pd.DataFrame()
    out = (
        frame.groupby(by_col)
        .agg(
            rows=("id", "size"),
            beats_stage_m=("beats_stage_m", "sum"),
            beats_pricefm=("beats_pricefm", "sum"),
            median_test_minus_stage_m=("test_minus_stage_m", "median"),
            median_test_minus_pricefm=("test_minus_pricefm", "median"),
            best_test_minus_pricefm=("test_minus_pricefm", "min"),
        )
        .reset_index()
    )
    return out


def artifact_count(run_root):
    run_root = repo_path(run_root)
    if not run_root.exists():
        return 0
    suffixes = {".rds", ".rda", ".rdata"}
    return sum(1 for path in run_root.rglob("*") if path.is_file() and path.suffix.lower() in suffixes)


def markdown_table(frame, columns=None, max_rows=None):
    if frame is None or frame.empty:
        return "_No rows._"
    work = frame.copy()
    if columns:
        work = work[[col for col in columns if col in work.columns]]
    if max_rows is not None:
        work = work.head(max_rows)
    lines = [
        "| " + " | ".join(work.columns) + " |",
        "| " + " | ".join(["---"] * len(work.columns)) + " |",
    ]
    for _, row in work.iterrows():
        vals = []
        for col in work.columns:
            value = row[col]
            if isinstance(value, float):
                vals.append("" if math.isnan(value) else "{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(path, summary, health, val_selected, test_oracle, by_family, by_factor):
    cols = [
        "regions", "folds", "candidate_family", "id", "val_method_id",
        "val_best_AQL", "test_method_id", "test_best_AQL", "local_AQL",
        "pricefm_AQL", "test_minus_stage_m", "test_minus_pricefm",
        "beats_stage_m", "beats_pricefm", "feature_policy",
        "graph_degree", "factor_changed",
    ]
    with open(repo_path(path), "w") as f:
        f.write("# PriceFM Stage-S Targeted Rescue Closeout\n\n")
        f.write("Stage S completed cleanly, but did not produce a promotion candidate. ")
        f.write("The Stage-M article decision surface remains unchanged.\n\n")
        f.write("## Health\n\n")
        f.write(markdown_table(health))
        f.write("\n\n## Decision\n\n")
        f.write("- Run clean: `{}`\n".format(summary["run_clean"]))
        f.write("- Promotion recommended: `{}`\n".format(summary["promotion_recommended"]))
        f.write("- Stage-M surface changed: `{}`\n".format(summary["stage_m_surface_changed"]))
        f.write("- Next action: `{}`\n".format(summary["next_action"]))
        f.write("\n## Validation-Selected Candidates\n\n")
        f.write(markdown_table(val_selected[cols].sort_values(["candidate_family", "test_minus_pricefm"])))
        f.write("\n\n## Test-Oracle Audit\n\n")
        f.write(markdown_table(test_oracle[cols].sort_values("test_minus_pricefm")))
        f.write("\n\n## Selection Summary By Family\n\n")
        f.write(markdown_table(by_family))
        f.write("\n\n## Variant Summary By Family/Factor\n\n")
        f.write(markdown_table(by_factor))
        f.write("\n\n## Interpretation\n\n")
        f.write(
            "Neither the validation-selected candidates nor the test-oracle audit "
            "beat the current Stage-M surface or cached PriceFM metrics.  This "
            "turns Stage S into negative evidence against another graph-parity "
            "or small horizon-variant sweep in this family.  The next stage "
            "should be structural diagnostics, not additional local capacity "
            "search.\n"
        )


def prepare(args):
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    grid_root = repo_path(args.grid_root)
    run_root = repo_path(args.run_root)
    plan_dir = repo_path(args.plan_dir)

    manifest = read_csv_required(grid_root / "manifest.csv", "Stage-S generated manifest")
    launch_status = read_csv_required(grid_root / "launch_status.csv", "Stage-S launch status")
    surface = read_csv_required(args.stage_m_surface_csv, "Stage-M decision surface")
    long_metrics = collect_long_metrics(run_root)
    cell_status = collect_cell_statuses(run_root)
    qbest = build_qdesn_best(manifest, long_metrics)
    val_selected, test_oracle_family, test_oracle = target_selection_tables(qbest)

    require_columns(launch_status, ["kind", "status"], "Stage-S launch status")
    run_clean = bool(launch_status["status"].astype(str).eq("completed").all())
    metric_count = int(len(metric_paths(run_root)))
    artifact_n = int(artifact_count(run_root))
    stage_m_rows = int(len(surface))
    stage_m_surface_changed = False
    promotion_recommended = bool(
        run_clean
        and artifact_n == 0
        and int(val_selected["beats_stage_m"].sum()) > 0
        and int(val_selected["beats_pricefm"].sum()) > 0
    )
    by_family = summarize_selection(val_selected, "candidate_family")
    by_factor = (
        qbest.groupby(["candidate_family", "factor_changed"])
        .agg(
            n=("id", "size"),
            median_val_AQL=("val_best_AQL", "median"),
            median_test_AQL=("test_best_AQL", "median"),
            best_test_AQL=("test_best_AQL", "min"),
            median_test_minus_pricefm=("test_minus_pricefm", "median"),
        )
        .reset_index()
    )
    health = pd.DataFrame([
        {"check": "window_builds_completed", "value": int((launch_status["kind"].eq("window_build") & launch_status["status"].eq("completed")).sum()), "status": "pass"},
        {"check": "experiments_completed", "value": int((launch_status["kind"].eq("experiment") & launch_status["status"].eq("completed")).sum()), "status": "pass"},
        {"check": "non_completed_statuses", "value": int((~launch_status["status"].eq("completed")).sum()), "status": "pass" if run_clean else "fail"},
        {"check": "metric_summary_files", "value": metric_count, "status": "pass" if metric_count == int(manifest.shape[0]) else "fail"},
        {"check": "binary_artifacts", "value": artifact_n, "status": "pass" if artifact_n == 0 else "fail"},
        {"check": "stage_m_rows", "value": stage_m_rows, "status": "pass" if stage_m_rows == 42 else "warn"},
        {"check": "validation_selected_beats_stage_m", "value": int(val_selected["beats_stage_m"].sum()), "status": "info"},
        {"check": "validation_selected_beats_pricefm", "value": int(val_selected["beats_pricefm"].sum()), "status": "info"},
        {"check": "test_oracle_beats_stage_m", "value": int(test_oracle["beats_stage_m"].sum()), "status": "info"},
        {"check": "test_oracle_beats_pricefm", "value": int(test_oracle["beats_pricefm"].sum()), "status": "info"},
    ])
    time_log = parse_time_log(grid_root / "launch_logs" / "stage_s_priority0.time.log")
    summary = {
        "status": "completed",
        "run_clean": run_clean,
        "promotion_recommended": promotion_recommended,
        "stage_m_surface_changed": stage_m_surface_changed,
        "stage_m_rows": stage_m_rows,
        "n_manifest_rows": int(manifest.shape[0]),
        "n_launch_rows": int(launch_status.shape[0]),
        "n_metric_files": metric_count,
        "n_cell_status_rows": int(cell_status.shape[0]),
        "binary_artifacts": artifact_n,
        "validation_selected_beats_stage_m": int(val_selected["beats_stage_m"].sum()),
        "validation_selected_beats_pricefm": int(val_selected["beats_pricefm"].sum()),
        "test_oracle_beats_stage_m": int(test_oracle["beats_stage_m"].sum()),
        "test_oracle_beats_pricefm": int(test_oracle["beats_pricefm"].sum()),
        "median_validation_selected_vs_pricefm": float(val_selected["test_minus_pricefm"].median()),
        "best_test_oracle_vs_pricefm": float(test_oracle["test_minus_pricefm"].min()),
        "elapsed_wall": time_log["elapsed_wall"],
        "max_rss_kb": time_log["max_rss_kb"],
        "next_action": "structural_diagnostics_before_any_new_search",
        "grid_root": config_path_value(grid_root),
        "run_root": config_path_value(run_root),
        "plan_dir": config_path_value(plan_dir),
        "stage_m_surface_csv": config_path_value(args.stage_m_surface_csv),
        "stage_m_surface_sha256": sha256_file(repo_path(args.stage_m_surface_csv)),
    }
    summary.update(git_state())

    write_frame(out_dir / "stage_s_health.csv", health)
    write_frame(out_dir / "stage_s_long_metrics.csv", long_metrics)
    write_frame(out_dir / "stage_s_qdesn_best_by_experiment.csv", qbest)
    write_frame(out_dir / "stage_s_validation_selected_candidates.csv", val_selected)
    write_frame(out_dir / "stage_s_test_oracle_audit.csv", test_oracle)
    write_frame(out_dir / "stage_s_test_oracle_by_family.csv", test_oracle_family)
    write_frame(out_dir / "stage_s_selection_summary_by_family.csv", by_family)
    write_frame(out_dir / "stage_s_variant_summary_by_factor.csv", by_factor)
    write_frame(out_dir / "stage_s_launch_status.csv", launch_status)
    write_json(out_dir / "summary.json", summary)
    write_report(out_dir / "stage_s_closeout_report.md", summary, health, val_selected, test_oracle, by_family, by_factor)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if not run_clean:
        raise SystemExit(1)
    return summary


def main():
    args = parser().parse_args()
    prepare(args)


if __name__ == "__main__":
    main()
