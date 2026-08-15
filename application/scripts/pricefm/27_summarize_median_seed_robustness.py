#!/usr/bin/env python3
"""Summarize completed PriceFM median seed-robustness grid cells."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
SELECT_PATH = SCRIPT_DIR / "20_select_pricefm_desn_median_specs.py"
DEFAULT_GRID = "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_seed_robustness_20260604.yaml"
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_seed_robustness_summary_20260604"
)
DEFAULT_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", default=DEFAULT_GRID)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--regions", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--selection-split", default="val")
    p.add_argument("--audit-split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--methods", default=DEFAULT_METHODS)
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rel_path(path):
    path = repo_path(path)
    try:
        return str(path.relative_to(repo_path(".")))
    except ValueError:
        return str(path)


def geometry_cols(frame):
    candidates = [
        "region", "fold", "method_id", "stage", "lag_window", "feature_map",
        "feature_dim", "projection_scale", "depth", "units", "alpha", "rho",
        "input_scale", "tau0",
    ]
    return [c for c in candidates if c in frame.columns]


def summarize_seed_robustness(metrics, selection_split, audit_split, unit, metric, methods=None):
    if metrics.empty:
        return pd.DataFrame()
    df = metrics[
        metrics["split"].astype(str).isin({str(selection_split), str(audit_split)})
        & metrics["unit"].astype(str).eq(str(unit))
    ].copy()
    if methods:
        df = df[df["method_id"].astype(str).isin(set(methods))].copy()
    if df.empty:
        return pd.DataFrame()
    if metric not in df.columns:
        raise ValueError("Metric '{}' not found in metrics.".format(metric))
    df[metric] = pd.to_numeric(df[metric], errors="coerce")
    df = df[df[metric].notna()].copy()
    keys = geometry_cols(df)
    rows = []
    for key_vals, sub in df.groupby(keys, dropna=False):
        if not isinstance(key_vals, tuple):
            key_vals = (key_vals,)
        base = dict(zip(keys, key_vals))
        seeds = sorted(int(x) for x in sub["seed"].dropna().unique()) if "seed" in sub.columns else []
        base["n_seeds_completed"] = len(seeds)
        base["seeds_completed"] = ",".join(str(x) for x in seeds)
        for split, role in [(selection_split, "selection"), (audit_split, "audit")]:
            ss = sub[sub["split"].astype(str).eq(str(split))].copy()
            values = pd.to_numeric(ss[metric], errors="coerce").dropna()
            base[role + "_n"] = int(values.shape[0])
            if values.empty:
                base[role + "_mean_" + metric] = float("nan")
                base[role + "_sd_" + metric] = float("nan")
                base[role + "_best_" + metric] = float("nan")
                base[role + "_worst_" + metric] = float("nan")
            else:
                base[role + "_mean_" + metric] = float(values.mean())
                base[role + "_sd_" + metric] = float(values.std(ddof=0))
                base[role + "_best_" + metric] = float(values.min())
                base[role + "_worst_" + metric] = float(values.max())
        rows.append(base)
    out = pd.DataFrame(rows)
    if not out.empty:
        out = out.sort_values(["fold", "selection_mean_" + metric, "method_id"]).reset_index(drop=True)
    return out


def write_report(path, completion, summary, metric):
    with open(path, "w") as f:
        f.write("# PriceFM Median Seed-Robustness Summary\n\n")
        total = int(completion.shape[0]) if not completion.empty else 0
        complete = int(completion["completed"].sum()) if not completion.empty and "completed" in completion else 0
        f.write("Completed cells: `{}` / `{}`\n\n".format(complete, total))
        f.write("## Seed Robustness\n\n")
        if summary.empty:
            f.write("_No completed seed-robustness metrics yet._\n\n")
        else:
            cols = [c for c in [
                "region", "fold", "method_id", "stage", "lag_window",
                "feature_dim", "alpha", "rho", "input_scale", "n_seeds_completed",
                "selection_mean_" + metric, "selection_sd_" + metric,
                "selection_worst_" + metric, "audit_mean_" + metric,
                "audit_worst_" + metric,
            ] if c in summary.columns]
            f.write(markdown_table(summary[cols]))
            f.write("\n")
        f.write("## Rules\n\n")
        f.write("- Selection summaries use validation metrics.\n")
        f.write("- Test metrics are audit-only.\n")
        f.write("- A robust candidate should have good validation mean and acceptable validation worst-case across seeds.\n")


def markdown_table(df):
    if df.empty:
        return "_No rows._\n"
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
    for _, row in df.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines) + "\n"


def main():
    args = parser().parse_args()
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    grid_mod = load_module(GRID_PREP_PATH, "pricefm_grid_prep")
    select_mod = load_module(SELECT_PATH, "pricefm_median_select")
    grid = grid_mod.load_grid(args.grid_config)
    rows = grid_mod.prepare_grid(grid, grid["base"]["generated_root"], write=False)
    selected = select_mod.select_rows(rows)
    regions = parse_csv(args.regions, str)
    folds = parse_csv(args.folds, int)
    methods = parse_csv(args.methods, str)
    metrics, completion = select_mod.collect_candidate_metrics(selected, regions=regions, folds=folds)
    summary = summarize_seed_robustness(metrics, args.selection_split, args.audit_split, args.unit, args.metric, methods)
    completion.to_csv(out_dir / "seed_robustness_completion.csv", index=False)
    metrics.to_csv(out_dir / "seed_robustness_candidate_metrics.csv", index=False)
    summary.to_csv(out_dir / "seed_robustness_summary.csv", index=False)
    report = out_dir / "seed_robustness_summary_report.md"
    write_report(report, completion, summary, args.metric)
    write_json(out_dir / "summary.json", {
        "grid_config": rel_path(args.grid_config),
        "output_dir": rel_path(out_dir),
        "n_cells": int(completion.shape[0]),
        "n_completed": int(completion["completed"].sum()) if "completed" in completion else 0,
        "report": rel_path(report),
    })
    print({"output_dir": rel_path(out_dir), "report": rel_path(report)})


if __name__ == "__main__":
    main()
