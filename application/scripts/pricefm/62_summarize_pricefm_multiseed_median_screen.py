#!/usr/bin/env python3
"""Summarize multi-seed PriceFM median screens without promoting test wins."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MODEL_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked",
    "qdesn_al_rhs_ns_exact_chunked",
    "normal_rhs_ns",
    "normal_scaled_ridge",
)

GEOMETRY_COLUMNS = [
    "region", "fold", "method_id", "feature_policy", "graph_degree",
    "feature_map", "lag_window", "depth", "units", "alpha", "rho",
    "input_scale", "projection_scale", "tau0",
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-csv", required=True)
    p.add_argument("--current-registry-csv", required=True)
    p.add_argument("--current-registry-label", default="current_registry")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--split-select", default="val")
    p.add_argument("--split-audit", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--model-methods", default=",".join(DEFAULT_MODEL_METHODS))
    p.add_argument("--min-validation-win-rate", type=float, default=2.0 / 3.0)
    p.add_argument("--max-mean-validation-delta", type=float, default=0.0)
    p.add_argument("--max-validation-delta", type=float, default=0.02)
    p.add_argument("--max-mean-test-delta-warning", type=float, default=0.0)
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
    region = str(first_jsonish_scalar(row["regions"] if "regions" in row else row["region"]))
    fold = int(first_jsonish_scalar(row["folds"] if "folds" in row else row["fold"]))
    return run_dir / "cells" / "region={}".format(region) / "fold={}".format(fold) / "model" / "metric_summary.csv"


def current_registry_view(registry):
    required = {"region", "fold", "selection_AQL", "test_AQL"}
    missing = required - set(registry.columns)
    if missing:
        raise ValueError("Current registry missing required columns: {}".format(sorted(missing)))
    out = registry.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    duplicated = out[out.duplicated(["region", "fold"], keep=False)]
    if not duplicated.empty:
        keys = (
            duplicated[["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("Current registry has duplicate region/fold keys: {}".format(keys))
    nonfinite = []
    for col in ("selection_AQL", "test_AQL"):
        values = pd.to_numeric(out[col], errors="coerce")
        bad = out[values.isna()][["region", "fold"]].drop_duplicates()
        for _, row in bad.iterrows():
            nonfinite.append({
                "region": str(row["region"]),
                "fold": int(row["fold"]),
                "column": col,
            })
        out[col] = values
    if nonfinite:
        raise ValueError("Current registry has non-finite required metric fields: {}".format(nonfinite))
    keep = [
        "region", "fold", "selection_AQL", "test_AQL", "test_MAE", "test_RMSE",
        "selected_method_id", "experiment_id",
    ]
    for col in keep:
        if col not in out.columns:
            out[col] = None
    return out[keep].rename(columns={
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
        region = str(first_jsonish_scalar(exp["regions"] if "regions" in exp else exp["region"]))
        fold = int(first_jsonish_scalar(exp["folds"] if "folds" in exp else exp["fold"]))
        path = metric_path(exp)
        if not path.exists():
            missing.append({
                "experiment_id": exp["id"],
                "region": region,
                "fold": fold,
                "metric_path": config_path_value(path),
                "reason": "metric_summary_missing",
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
                "reason": "no_candidate_method_on_selection_split",
            })
            continue
        best = candidates.sort_values("AQL").iloc[0]
        audit = metric[
            metric["split"].astype(str).eq(str(args.split_audit))
            & metric["unit"].astype(str).eq(str(args.unit))
            & metric["method_id"].eq(str(best["method_id"]))
        ]
        audit_row = audit.iloc[0] if not audit.empty else pd.Series(dtype=object)
        rows.append({
            "region": region,
            "fold": fold,
            "experiment_id": str(exp["id"]),
            "method_id": str(best["method_id"]),
            "selection_AQL": finite_or_nan(best.get("AQL")),
            "selection_MAE": finite_or_nan(best.get("MAE")),
            "selection_RMSE": finite_or_nan(best.get("RMSE")),
            "test_AQL": finite_or_nan(audit_row.get("AQL")),
            "test_MAE": finite_or_nan(audit_row.get("MAE")),
            "test_RMSE": finite_or_nan(audit_row.get("RMSE")),
            "robustness_seed": int(exp.get("robustness_seed", exp.get("seed", 0))),
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
            "candidate_source": str(exp.get("candidate_source", exp.get("stage", ""))),
        })
    return pd.DataFrame(rows), pd.DataFrame(missing)


def seed_decisions(seed_metrics, current, current_registry_label="current_registry"):
    out = seed_metrics.merge(current, on=["region", "fold"], how="left", validate="many_to_one")
    if out["current_selection_AQL"].isna().any():
        missing = (
            out[out["current_selection_AQL"].isna()][["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError(
            "Screen fold not in current registry '{}': {}".format(
                current_registry_label, missing
            )
        )
    out["val_delta_vs_current"] = out["selection_AQL"] - out["current_selection_AQL"]
    out["test_delta_vs_current"] = out["test_AQL"] - out["current_test_AQL"]
    out["validation_improved"] = out["val_delta_vs_current"] < 0.0
    out["test_improved"] = out["test_delta_vs_current"] < 0.0
    return out.sort_values(["region", "fold", "experiment_id"]).reset_index(drop=True)


def geometry_key(row):
    parts = []
    for col in GEOMETRY_COLUMNS:
        parts.append("{}={}".format(col, row.get(col, "")))
    return "|".join(parts)


def aggregate_geometry(decisions, args):
    if decisions.empty:
        return pd.DataFrame()
    work = decisions.copy()
    work["geometry_key"] = work.apply(geometry_key, axis=1)
    rows = []
    group_cols = ["region", "fold", "geometry_key"]
    for key, sub in work.groupby(group_cols, dropna=False):
        n = int(sub.shape[0])
        validation_win_rate = float(sub["validation_improved"].mean()) if n else float("nan")
        mean_val_delta = float(sub["val_delta_vs_current"].mean()) if n else float("nan")
        max_val_delta = float(sub["val_delta_vs_current"].max()) if n else float("nan")
        mean_test_delta = float(sub["test_delta_vs_current"].mean()) if n else float("nan")
        pass_gate = (
            n > 0
            and validation_win_rate >= float(args.min_validation_win_rate)
            and mean_val_delta <= float(args.max_mean_validation_delta)
            and max_val_delta <= float(args.max_validation_delta)
        )
        audit_label = (
            "audit_helpful_or_neutral"
            if mean_test_delta <= float(args.max_mean_test_delta_warning)
            else "audit_deterioration_warning"
        )
        first = sub.iloc[0]
        rows.append({
            "region": key[0],
            "fold": int(key[1]),
            "geometry_key": key[2],
            "method_id": first.get("method_id", ""),
            "feature_policy": first.get("feature_policy", ""),
            "graph_degree": first.get("graph_degree", ""),
            "feature_map": first.get("feature_map", ""),
            "lag_window": first.get("lag_window", ""),
            "depth": first.get("depth", ""),
            "units": first.get("units", ""),
            "alpha": first.get("alpha", ""),
            "rho": first.get("rho", ""),
            "input_scale": first.get("input_scale", ""),
            "projection_scale": first.get("projection_scale", ""),
            "tau0": first.get("tau0", ""),
            "n_seeds": n,
            "n_validation_improved": int(sub["validation_improved"].sum()),
            "n_test_improved": int(sub["test_improved"].sum()),
            "validation_win_rate": validation_win_rate,
            "mean_val_delta_vs_current": mean_val_delta,
            "max_val_delta_vs_current": max_val_delta,
            "mean_test_delta_vs_current": mean_test_delta,
            "max_test_delta_vs_current": float(sub["test_delta_vs_current"].max()),
            "pass_multiseed_validation_gate": bool(pass_gate),
            "test_audit_label": audit_label,
            "recommended_action": (
                "queue_closeout_against_current_registry"
                if pass_gate
                else "do_not_promote"
            ),
        })
    return pd.DataFrame(rows).sort_values([
        "region", "fold", "pass_multiseed_validation_gate",
        "mean_val_delta_vs_current",
    ], ascending=[True, True, False, True]).reset_index(drop=True)


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None, limit=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[c for c in columns if c in frame.columns]].copy()
    if limit is not None:
        frame = frame.head(int(limit))
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[c]) for c in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, seed_rows, geometry_summary, missing):
    report = out_dir / "pricefm_multiseed_median_screen_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Multi-Seed Median Screen\n\n")
        f.write("This report summarizes median candidates across random seeds. ")
        f.write("Validation metrics decide whether a candidate can enter closeout; ")
        f.write("test metrics are audit-only.\n\n")
        f.write("## Current Baseline\n\n")
        f.write("- Current registry label: `{}`\n".format(
            getattr(args, "current_registry_label", "current_registry")
        ))
        f.write("- Current registry CSV: `{}`\n\n".format(
            config_path_value(getattr(args, "current_registry_csv", ""))
        ))
        f.write("## Gate\n\n")
        f.write("- Minimum validation win rate: `{}`\n".format(args.min_validation_win_rate))
        f.write("- Maximum mean validation AQL delta: `{}`\n".format(args.max_mean_validation_delta))
        f.write("- Maximum single-seed validation AQL delta: `{}`\n\n".format(args.max_validation_delta))
        f.write("## Geometry Summary\n\n")
        f.write(markdown_table(
            geometry_summary,
            columns=[
                "region", "fold", "method_id", "feature_policy", "graph_degree",
                "n_seeds", "n_validation_improved", "validation_win_rate",
                "mean_val_delta_vs_current", "mean_test_delta_vs_current",
                "pass_multiseed_validation_gate", "test_audit_label",
                "recommended_action",
            ],
            limit=80,
        ))
        f.write("\n\n## Seed-Level Rows\n\n")
        f.write(markdown_table(
            seed_rows,
            columns=[
                "region", "fold", "experiment_id", "robustness_seed", "method_id",
                "selection_AQL", "current_selection_AQL", "val_delta_vs_current",
                "test_AQL", "current_test_AQL", "test_delta_vs_current",
                "validation_improved", "test_improved",
            ],
            limit=120,
        ))
        f.write("\n\n## Missing Metrics\n\n")
        f.write(markdown_table(missing, limit=80))
        f.write("\n")
    return report


def summarize(args):
    manifest = read_csv_required(args.manifest_csv, "manifest")
    current = current_registry_view(read_csv_required(args.current_registry_csv, "current registry"))
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    seed_metrics, missing = collect_seed_metrics(manifest, args)
    if bool(args.require_complete) and not missing.empty:
        missing.to_csv(out_dir / "missing_metric_files.csv", index=False)
        raise FileNotFoundError(
            "Missing or unusable metric_summary files for {} manifest rows; see {}".format(
                int(missing.shape[0]), out_dir / "missing_metric_files.csv"
            )
        )
    current_label = getattr(args, "current_registry_label", "current_registry")
    decisions = seed_decisions(seed_metrics, current, current_label) if not seed_metrics.empty else pd.DataFrame()
    geometry = aggregate_geometry(decisions, args)
    precloseout = geometry[geometry["pass_multiseed_validation_gate"].astype(bool)].copy() if not geometry.empty else pd.DataFrame()

    seed_metrics.to_csv(out_dir / "multiseed_metric_winners.csv", index=False)
    decisions.to_csv(out_dir / "multiseed_seed_decisions.csv", index=False)
    geometry.to_csv(out_dir / "multiseed_geometry_summary.csv", index=False)
    precloseout.to_csv(out_dir / "multiseed_precloseout_queue.csv", index=False)
    missing.to_csv(out_dir / "missing_metric_files.csv", index=False)
    report = write_report(out_dir, args, decisions, geometry, missing)
    summary = {
        "n_manifest_rows": int(manifest.shape[0]),
        "n_seed_metric_rows": int(seed_metrics.shape[0]),
        "n_geometry_rows": int(geometry.shape[0]),
        "n_precloseout_rows": int(precloseout.shape[0]),
        "n_missing_metric_rows": int(missing.shape[0]),
        "current_registry_csv": config_path_value(args.current_registry_csv),
        "current_registry_label": current_label,
        "report": config_path_value(report),
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = summarize(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
