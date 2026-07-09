#!/usr/bin/env python3
"""Summarize graph/local median rescue seed-robustness runs."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_MODEL_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked",
    "qdesn_al_rhs_ns_exact_chunked",
    "normal_rhs_ns",
    "normal_scaled_ridge",
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-csv", required=True)
    p.add_argument("--current-registry-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--split-select", default="val")
    p.add_argument("--split-audit", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--model-methods", default=",".join(DEFAULT_MODEL_METHODS))
    p.add_argument("--min-validation-win-rate", type=float, default=1.0)
    p.add_argument("--max-mean-test-delta", type=float, default=0.0)
    p.add_argument("--max-test-rel-deterioration", type=float, default=0.05)
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


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
    return value


def first_jsonish_scalar(value):
    value = parse_jsonish(value)
    if isinstance(value, (list, tuple)):
        return value[0] if value else None
    return value


def finite_or_nan(value):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return out if math.isfinite(out) else float("nan")


def metric_path(row):
    run_dir = repo_path(row["run_dir"])
    region = str(first_jsonish_scalar(row["regions"]))
    fold = int(first_jsonish_scalar(row["folds"]))
    return run_dir / "cells" / "region={}".format(region) / "fold={}".format(fold) / "model" / "metric_summary.csv"


def current_registry_view(registry):
    required = {"region", "fold", "selection_AQL", "test_AQL"}
    missing = required - set(registry.columns)
    if missing:
        raise ValueError("Current registry missing required columns: {}".format(sorted(missing)))
    out = registry.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    return out[[
        "region", "fold", "selection_AQL", "test_AQL", "test_MAE", "test_RMSE",
        "selected_method_id", "experiment_id",
    ]].rename(columns={
        "selection_AQL": "current_selection_AQL",
        "test_AQL": "current_test_AQL",
        "test_MAE": "current_test_MAE",
        "test_RMSE": "current_test_RMSE",
        "selected_method_id": "current_method_id",
        "experiment_id": "current_experiment_id",
    })


def collect_seed_metrics(manifest, args):
    methods = [m.strip() for m in str(args.model_methods).split(",") if m.strip()]
    rows = []
    missing = []
    for _, exp in manifest.iterrows():
        path = metric_path(exp)
        region = str(first_jsonish_scalar(exp["regions"]))
        fold = int(first_jsonish_scalar(exp["folds"]))
        if not path.exists():
            missing.append({
                "experiment_id": exp["id"],
                "region": region,
                "fold": fold,
                "metric_path": config_path_value(path),
            })
            continue
        metric = pd.read_csv(path)
        candidates = metric[
            metric["split"].astype(str).eq(str(args.split_select))
            & metric["unit"].astype(str).eq(str(args.unit))
            & metric["method_id"].isin(methods)
        ].copy()
        if candidates.empty:
            missing.append({
                "experiment_id": exp["id"],
                "region": region,
                "fold": fold,
                "metric_path": config_path_value(path),
            })
            continue
        best = candidates.sort_values("AQL").iloc[0]
        audit = metric[
            metric["split"].astype(str).eq(str(args.split_audit))
            & metric["unit"].astype(str).eq(str(args.unit))
            & metric["method_id"].eq(str(best["method_id"]))
        ]
        audit_row = audit.iloc[0] if not audit.empty else pd.Series(dtype=object)
        median_registry = parse_jsonish(exp.get("median_registry", "{}"))
        if not isinstance(median_registry, dict):
            median_registry = {}
        rows.append({
            "region": region,
            "fold": fold,
            "experiment_id": str(exp["id"]),
            "source_rescue_experiment_id": str(exp.get(
                "source_rescue_experiment_id",
                median_registry.get("source_rescue_experiment_id", ""),
            )),
            "robustness_seed": int(exp.get(
                "robustness_seed",
                median_registry.get("robustness_seed", exp.get("seed")),
            )),
            "method_id": str(best["method_id"]),
            "selection_AQL": finite_or_nan(best.get("AQL")),
            "selection_MAE": finite_or_nan(best.get("MAE")),
            "selection_RMSE": finite_or_nan(best.get("RMSE")),
            "test_AQL": finite_or_nan(audit_row.get("AQL")),
            "test_MAE": finite_or_nan(audit_row.get("MAE")),
            "test_RMSE": finite_or_nan(audit_row.get("RMSE")),
            "feature_policy": str(exp.get("feature_policy", "")),
            "graph_degree": exp.get("graph_degree", ""),
            "feature_map": exp.get("feature_map", ""),
            "lag_window": exp.get("lag_window", ""),
            "depth": exp.get("depth", ""),
            "units": exp.get("units", ""),
            "alpha": exp.get("alpha", ""),
            "rho": exp.get("rho", ""),
            "input_scale": exp.get("input_scale", ""),
            "projection_scale": exp.get("projection_scale", ""),
            "tau0": exp.get("tau0", ""),
            "seed": exp.get("seed", ""),
            "run_dir": str(exp.get("run_dir", "")),
            "full_config": str(exp.get("full_config", "")),
            "data_config": str(exp.get("data_config", "")),
        })
    return pd.DataFrame(rows), pd.DataFrame(missing)


def seed_decisions(seed_metrics, current):
    out = seed_metrics.merge(current, on=["region", "fold"], how="left", validate="many_to_one")
    if out["current_selection_AQL"].isna().any():
        missing = out[out["current_selection_AQL"].isna()][["region", "fold"]].to_dict("records")
        raise ValueError("Seed robustness fold not in current registry: {}".format(missing))
    out["val_delta_vs_current"] = out["selection_AQL"] - out["current_selection_AQL"]
    out["test_delta_vs_current"] = out["test_AQL"] - out["current_test_AQL"]
    out["test_rel_delta_vs_current"] = out["test_delta_vs_current"] / out["current_test_AQL"].abs().clip(lower=1.0e-8)
    out["validation_improved"] = out["val_delta_vs_current"] < 0.0
    out["test_improved"] = out["test_delta_vs_current"] < 0.0
    return out.sort_values(["region", "fold", "source_rescue_experiment_id", "robustness_seed"]).reset_index(drop=True)


def aggregate(decisions, args):
    rows = []
    group_cols = ["region", "fold", "source_rescue_experiment_id"]
    for key, sub in decisions.groupby(group_cols, dropna=False):
        n = int(sub.shape[0])
        validation_win_rate = float(sub["validation_improved"].mean()) if n else float("nan")
        mean_test_delta = float(sub["test_delta_vs_current"].mean()) if n else float("nan")
        max_test_rel_delta = float(sub["test_rel_delta_vs_current"].max()) if n else float("nan")
        pass_gate = (
            n > 0
            and validation_win_rate >= float(args.min_validation_win_rate)
            and mean_test_delta <= float(args.max_mean_test_delta)
            and max_test_rel_delta <= float(args.max_test_rel_deterioration)
        )
        rows.append({
            "region": key[0],
            "fold": int(key[1]),
            "source_rescue_experiment_id": key[2],
            "n_seeds": n,
            "n_validation_improved": int(sub["validation_improved"].sum()),
            "n_test_improved": int(sub["test_improved"].sum()),
            "validation_win_rate": validation_win_rate,
            "mean_val_delta_vs_current": float(sub["val_delta_vs_current"].mean()),
            "max_val_delta_vs_current": float(sub["val_delta_vs_current"].max()),
            "mean_test_delta_vs_current": mean_test_delta,
            "max_test_delta_vs_current": float(sub["test_delta_vs_current"].max()),
            "max_test_rel_delta_vs_current": max_test_rel_delta,
            "pass_seed_robustness": bool(pass_gate),
            "recommended_action": (
                "patch_median_registry_then_quantile_promotion"
                if pass_gate
                else "keep_current_registry"
            ),
        })
    return pd.DataFrame(rows).sort_values(["region", "fold", "source_rescue_experiment_id"]).reset_index(drop=True)


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[c for c in columns if c in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[c]) for c in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, decisions, summary, missing):
    report = out_dir / "pricefm_graph_local_rescue_seedrob_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Graph/Local Rescue Seed Robustness\n\n")
        f.write("This report audits queued median rescue candidates across random seeds. ")
        f.write("A candidate is promotion-ready only if the seed-level gate passes.\n\n")
        f.write("## Gate\n\n")
        f.write("- Minimum validation win rate: `{}`\n".format(args.min_validation_win_rate))
        f.write("- Maximum mean test AQL delta: `{}`\n".format(args.max_mean_test_delta))
        f.write("- Maximum single-seed test relative deterioration: `{}`\n\n".format(
            args.max_test_rel_deterioration
        ))
        f.write("## Candidate Summary\n\n")
        f.write(markdown_table(summary))
        f.write("\n\n## Seed Decisions\n\n")
        f.write(markdown_table(
            decisions,
            columns=[
                "region", "fold", "source_rescue_experiment_id", "robustness_seed",
                "method_id", "selection_AQL", "current_selection_AQL",
                "val_delta_vs_current", "test_AQL", "current_test_AQL",
                "test_delta_vs_current", "validation_improved", "test_improved",
            ],
        ))
        f.write("\n\n## Missing Metrics\n\n")
        f.write(markdown_table(missing))
    return report


def summarize(args):
    manifest = read_csv_required(args.manifest_csv, "manifest")
    current = current_registry_view(read_csv_required(args.current_registry_csv, "current registry"))
    metrics, missing = collect_seed_metrics(manifest, args)
    decisions = seed_decisions(metrics, current) if not metrics.empty else pd.DataFrame()
    summary = aggregate(decisions, args) if not decisions.empty else pd.DataFrame()
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(out_dir / "seedrob_metric_winners.csv", index=False)
    decisions.to_csv(out_dir / "seedrob_decisions.csv", index=False)
    summary.to_csv(out_dir / "seedrob_candidate_summary.csv", index=False)
    missing.to_csv(out_dir / "missing_metric_files.csv", index=False)
    ready = summary[summary["pass_seed_robustness"].astype(bool)] if not summary.empty else pd.DataFrame()
    ready.to_csv(out_dir / "promotion_ready_queue.csv", index=False)
    report = write_report(out_dir, args, decisions, summary, missing)
    payload = {
        "status": "completed",
        "manifest_csv": config_path_value(args.manifest_csv),
        "current_registry_csv": config_path_value(args.current_registry_csv),
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
        "n_manifest_rows": int(manifest.shape[0]),
        "n_metric_winners": int(metrics.shape[0]),
        "n_missing_metric_files": int(missing.shape[0]),
        "n_candidates": int(summary.shape[0]),
        "n_promotion_ready": int(ready.shape[0]),
    }
    write_json(out_dir / "summary.json", payload)
    return payload


def main():
    args = parser().parse_args()
    print(json.dumps(summarize(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
