#!/usr/bin/env python3
"""Close out a graph/local median rescue grid without promoting it blindly.

The rescue grid is a diagnostic layer after the graph/local region-panel
comparison. It is not the authoritative median registry. This script summarizes
the completed rescue candidates, compares each weak fold to the current median
registry, and writes a conservative queue for follow-up robustness checks.

Selection remains validation-clean. Test metrics are copied as audit fields and
are used only to label rescue risk; they do not create a new authoritative
winner by themselves.
"""

from __future__ import annotations

import argparse
import ast
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
    p.add_argument("--run-root", required=True)
    p.add_argument("--current-registry-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--split-select", default="val")
    p.add_argument("--split-audit", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--priority", type=float, default=None)
    p.add_argument("--model-methods", default=",".join(DEFAULT_MODEL_METHODS))
    p.add_argument("--validation-tolerance", type=float, default=0.0)
    p.add_argument("--test-tolerance", type=float, default=0.0)
    p.add_argument("--severe-test-rel-threshold", type=float, default=0.05)
    p.add_argument("--robustness-seeds", default="20260616,20260617,20260618")
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
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return ast.literal_eval(text)
    return value


def first_jsonish_scalar(value):
    value = parse_jsonish(value)
    if isinstance(value, (list, tuple)):
        if not value:
            return None
        return value[0]
    return value


def finite_or_nan(value):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float("nan")
    return out if math.isfinite(out) else float("nan")


def experiment_run_dir(row, args):
    run_dir = row.get("run_dir", "")
    if isinstance(run_dir, str) and run_dir.strip():
        return repo_path(run_dir)
    if not pd.isna(run_dir):
        text = str(run_dir).strip()
        if text:
            return repo_path(text)
    return repo_path(args.run_root) / str(row["id"])


def metric_path(row, args):
    run_dir = experiment_run_dir(row, args)
    region = str(first_jsonish_scalar(row["regions"]))
    fold = int(first_jsonish_scalar(row["folds"]))
    return run_dir / "cells" / "region={}".format(region) / "fold={}".format(fold) / "model" / "metric_summary.csv"


def collect_metrics(manifest, args):
    methods = [m.strip() for m in str(args.model_methods).split(",") if m.strip()]
    rows = []
    missing = []
    for _, exp in manifest.iterrows():
        path = metric_path(exp, args)
        region = str(first_jsonish_scalar(exp["regions"]))
        fold = int(first_jsonish_scalar(exp["folds"]))
        if not path.exists():
            missing.append({"id": exp["id"], "region": region, "fold": fold, "metric_path": config_path_value(path)})
            continue
        metric = pd.read_csv(path)
        keep = metric[
            metric["split"].astype(str).eq(str(args.split_select))
            & metric["unit"].astype(str).eq(str(args.unit))
            & metric["method_id"].isin(methods)
        ].copy()
        if keep.empty:
            missing.append({"id": exp["id"], "region": region, "fold": fold, "metric_path": config_path_value(path)})
            continue
        for _, row in keep.iterrows():
            audit = metric[
                metric["split"].astype(str).eq(str(args.split_audit))
                & metric["unit"].astype(str).eq(str(args.unit))
                & metric["method_id"].eq(str(row["method_id"]))
            ]
            audit_row = audit.iloc[0] if not audit.empty else pd.Series(dtype=object)
            rec = {
                "region": region,
                "fold": fold,
                "experiment_id": str(exp["id"]),
                "method_id": str(row["method_id"]),
                "selection_AQL": finite_or_nan(row.get("AQL")),
                "selection_MAE": finite_or_nan(row.get("MAE")),
                "selection_RMSE": finite_or_nan(row.get("RMSE")),
                "test_AQL": finite_or_nan(audit_row.get("AQL")),
                "test_MAE": finite_or_nan(audit_row.get("MAE")),
                "test_RMSE": finite_or_nan(audit_row.get("RMSE")),
                "feature_policy": str(exp.get("feature_policy", "")),
                "graph_degree": exp.get("graph_degree", ""),
                "input_scope": str(exp.get("input_scope", "")),
                "spatial_information_set": str(exp.get("spatial_information_set", "")),
                "lag_window": exp.get("lag_window", ""),
                "depth": exp.get("depth", ""),
                "units": exp.get("units", ""),
                "alpha": exp.get("alpha", ""),
                "rho": exp.get("rho", ""),
                "input_scale": exp.get("input_scale", ""),
                "tau0": exp.get("tau0", ""),
                "seed": exp.get("seed", ""),
                "priority": exp.get("priority", ""),
                "run_dir": config_path_value(experiment_run_dir(exp, args)),
                "full_config": str(exp.get("full_config", "")),
                "data_config": str(exp.get("data_config", "")),
                "rationale": str(exp.get("rationale", "")),
            }
            rows.append(rec)
    return pd.DataFrame(rows), pd.DataFrame(missing)


def experiment_best(candidate_metrics):
    if candidate_metrics.empty:
        return candidate_metrics
    return (
        candidate_metrics.sort_values(["region", "fold", "experiment_id", "selection_AQL"])
        .groupby(["region", "fold", "experiment_id"], as_index=False)
        .head(1)
        .reset_index(drop=True)
    )


def fold_best(experiment_best_frame):
    if experiment_best_frame.empty:
        return experiment_best_frame
    return (
        experiment_best_frame.sort_values(["region", "fold", "selection_AQL"])
        .groupby(["region", "fold"], as_index=False)
        .head(1)
        .reset_index(drop=True)
    )


def current_registry_view(registry):
    required = {"region", "fold", "selection_AQL", "test_AQL"}
    missing = required - set(registry.columns)
    if missing:
        raise ValueError("Current registry missing required columns: {}".format(sorted(missing)))
    out = registry.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    if out.duplicated(["region", "fold"]).any():
        dup = out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
        raise ValueError("Current registry has duplicate region/fold rows: {}".format(
            dup.drop_duplicates().to_dict("records")
        ))
    cols = [
        "region", "fold", "selected_method_id", "experiment_id", "selected_source",
        "selection_AQL", "test_AQL", "test_MAE", "test_RMSE", "feature_policy",
        "spatial_information_set", "graph_degree", "depth", "units", "alpha",
        "rho", "input_scale", "tau0", "seed",
    ]
    present = [c for c in cols if c in out.columns]
    out = out[present].copy()
    rename = {
        "selected_method_id": "current_method_id",
        "experiment_id": "current_experiment_id",
        "selected_source": "current_selected_source",
        "selection_AQL": "current_selection_AQL",
        "test_AQL": "current_test_AQL",
        "test_MAE": "current_test_MAE",
        "test_RMSE": "current_test_RMSE",
        "feature_policy": "current_feature_policy",
        "spatial_information_set": "current_spatial_information_set",
        "graph_degree": "current_graph_degree",
        "depth": "current_depth",
        "units": "current_units",
        "alpha": "current_alpha",
        "rho": "current_rho",
        "input_scale": "current_input_scale",
        "tau0": "current_tau0",
        "seed": "current_seed",
    }
    return out.rename(columns=rename)


def classify(row, args):
    val_improved = bool(row["validation_improved"])
    test_improved = bool(row["test_improved"])
    rel = finite_or_nan(row.get("test_rel_delta_vs_current"))
    if val_improved and test_improved:
        return "robustness_candidate"
    if val_improved and not test_improved:
        if math.isfinite(rel) and rel >= float(args.severe_test_rel_threshold):
            return "validation_overfit_warning"
        return "validation_candidate_audit_worse"
    if (not val_improved) and test_improved:
        return "test_only_diagnostic"
    return "keep_current"


def build_decisions(fold_best_frame, current, args):
    out = fold_best_frame.merge(current, on=["region", "fold"], how="left", validate="many_to_one")
    if out["current_selection_AQL"].isna().any():
        missing = out[out["current_selection_AQL"].isna()][["region", "fold"]].to_dict("records")
        raise ValueError("Rescue fold not present in current registry: {}".format(missing))
    out["val_delta_vs_current"] = out["selection_AQL"] - out["current_selection_AQL"]
    out["test_delta_vs_current"] = out["test_AQL"] - out["current_test_AQL"]
    out["test_rel_delta_vs_current"] = out["test_delta_vs_current"] / out["current_test_AQL"].abs().clip(lower=1.0e-8)
    out["validation_improved"] = out["val_delta_vs_current"] < -float(args.validation_tolerance)
    out["test_improved"] = out["test_delta_vs_current"] < -float(args.test_tolerance)
    out["closeout_label"] = out.apply(lambda row: classify(row, args), axis=1)
    out["authoritative_action"] = "keep_current_registry"
    out.loc[out["closeout_label"].eq("robustness_candidate"), "authoritative_action"] = (
        "queue_seed_robustness_before_promotion"
    )
    out["test_metrics_role"] = "audit_only"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def make_seed_plan(decisions, args):
    seeds = [int(x.strip()) for x in str(args.robustness_seeds).split(",") if x.strip()]
    candidates = decisions[decisions["closeout_label"].eq("robustness_candidate")].copy()
    rows = []
    for _, row in candidates.iterrows():
        for seed in seeds:
            rec = {
                "region": row["region"],
                "fold": int(row["fold"]),
                "source_experiment_id": row["experiment_id"],
                "source_method_id": row["method_id"],
                "robustness_seed": seed,
                "recommended_stage": "median_rescue_seed_robustness",
                "selection_rule": "validation_AQL_stability_then_quantile_promotion",
                "feature_policy": row["feature_policy"],
                "graph_degree": row.get("graph_degree", ""),
                "depth": row.get("depth", ""),
                "units": row.get("units", ""),
                "alpha": row.get("alpha", ""),
                "rho": row.get("rho", ""),
                "input_scale": row.get("input_scale", ""),
                "tau0": row.get("tau0", ""),
            }
            rows.append(rec)
    return pd.DataFrame(rows)


def hypothetical_registry(current_registry, decisions, mode):
    current = current_registry.copy()
    by_key = {(str(row["region"]), int(row["fold"])): row for _, row in decisions.iterrows()}
    rows = []
    for _, row in current.iterrows():
        key = (str(row["region"]), int(row["fold"]))
        dec = by_key.get(key)
        if dec is None:
            rows.append(row.to_dict())
            continue
        replace = False
        if mode == "validation_selected":
            replace = bool(dec["validation_improved"])
        elif mode == "robustness_candidates":
            replace = str(dec["closeout_label"]) == "robustness_candidate"
        if not replace:
            rows.append(row.to_dict())
            continue
        out = row.to_dict()
        out["selected_method_id"] = dec["method_id"]
        out["method_id"] = dec["method_id"]
        out["experiment_id"] = dec["experiment_id"]
        out["selection_AQL"] = dec["selection_AQL"]
        out["selection_metric_value"] = dec["selection_AQL"]
        out["test_AQL"] = dec["test_AQL"]
        out["test_MAE"] = dec["test_MAE"]
        out["test_RMSE"] = dec["test_RMSE"]
        out["feature_policy"] = dec["feature_policy"]
        out["spatial_information_set"] = dec["spatial_information_set"]
        out["graph_degree"] = dec["graph_degree"]
        out["depth"] = dec["depth"]
        out["units"] = dec["units"]
        out["alpha"] = dec["alpha"]
        out["rho"] = dec["rho"]
        out["input_scale"] = dec["input_scale"]
        out["tau0"] = dec["tau0"]
        out["seed"] = dec["seed"]
        out["run_dir"] = dec["run_dir"]
        out["full_config"] = dec["full_config"]
        out["data_config"] = dec["data_config"]
        out["selected_source"] = "rescue_diagnostic"
        out["candidate_source_final"] = "graph_local_rescue_20260615"
        out["selection_is_validation_only"] = True
        out["closeout_label"] = dec["closeout_label"]
        rows.append(out)
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def summarize_registry(frame, label):
    return {
        "label": label,
        "n_region_folds": int(frame.shape[0]),
        "mean_median_test_AQL": float(frame["test_AQL"].mean()),
        "median_median_test_AQL": float(frame["test_AQL"].median()),
        "mean_selection_AQL": float(frame["selection_AQL"].mean()),
    }


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


def write_report(out_dir, args, decisions, summary_rows, seed_plan):
    report = out_dir / "pricefm_graph_local_median_rescue_closeout_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Graph/Local Median Rescue Closeout\n\n")
        f.write("This closeout summarizes the completed median-only rescue grid. ")
        f.write("It does not replace the current authoritative graph/local median registry.\n\n")
        f.write("## Inputs\n\n")
        f.write("- Manifest: `{}`\n".format(config_path_value(args.manifest_csv)))
        f.write("- Run root: `{}`\n".format(config_path_value(args.run_root)))
        f.write("- Current registry: `{}`\n".format(config_path_value(args.current_registry_csv)))
        f.write("- Selection split/unit/metric: `{}` / `{}` / `{}`\n\n".format(
            args.split_select, args.unit, args.metric
        ))
        f.write("## Decision Counts\n\n")
        f.write(markdown_table(
            decisions["closeout_label"].value_counts().rename_axis("closeout_label").reset_index(name="n")
        ))
        f.write("\n\n## Registry-Level Test AQL Audit\n\n")
        f.write(markdown_table(pd.DataFrame(summary_rows)))
        f.write("\n\n## Fold Decisions\n\n")
        f.write(markdown_table(
            decisions,
            columns=[
                "region", "fold", "experiment_id", "method_id", "selection_AQL",
                "current_selection_AQL", "val_delta_vs_current", "test_AQL",
                "current_test_AQL", "test_delta_vs_current", "test_rel_delta_vs_current",
                "closeout_label", "authoritative_action",
            ],
        ))
        f.write("\n\n## Robustness Seed Plan\n\n")
        f.write(markdown_table(seed_plan))
        f.write("\n\n## Interpretation\n\n")
        f.write("- `robustness_candidate` means validation and audit test both improved versus the current median registry. It is still not an authoritative promotion until seed robustness passes.\n")
        f.write("- `validation_candidate_audit_worse` and `validation_overfit_warning` mark validation wins that did not transfer to the test audit.\n")
        f.write("- `test_only_diagnostic` is useful for diagnosis but cannot drive selection.\n")
        f.write("- Seven-quantile synthesis should wait until median rescue candidates pass robustness gates.\n")
    return report


def closeout(args):
    manifest = read_csv_required(args.manifest_csv, "manifest")
    priority = getattr(args, "priority", None)
    if priority is not None:
        if "priority" not in manifest.columns:
            raise ValueError("Cannot filter by priority because manifest lacks a priority column")
        manifest = manifest[pd.to_numeric(manifest["priority"], errors="coerce").eq(float(priority))].copy()
        if manifest.empty:
            raise ValueError("No manifest rows matched priority={}".format(priority))
    current_registry = read_csv_required(args.current_registry_csv, "current registry")
    metrics, missing = collect_metrics(manifest, args)
    exp_best = experiment_best(metrics)
    best = fold_best(exp_best)
    current = current_registry_view(current_registry)
    decisions = build_decisions(best, current, args)
    seed_plan = make_seed_plan(decisions, args)

    validation_selected = hypothetical_registry(current_registry, decisions, "validation_selected")
    robustness_registry = hypothetical_registry(current_registry, decisions, "robustness_candidates")
    summaries = [
        summarize_registry(current_registry, "current_authoritative"),
        summarize_registry(validation_selected, "hypothetical_validation_selected_rescue"),
        summarize_registry(robustness_registry, "hypothetical_robustness_candidates_only"),
    ]

    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(out_dir / "rescue_candidate_metrics.csv", index=False)
    exp_best.to_csv(out_dir / "rescue_experiment_best_metrics.csv", index=False)
    best.to_csv(out_dir / "rescue_fold_best_by_validation.csv", index=False)
    decisions.to_csv(out_dir / "rescue_closeout_decisions.csv", index=False)
    missing.to_csv(out_dir / "missing_metric_files.csv", index=False)
    decisions[decisions["closeout_label"].eq("robustness_candidate")].to_csv(
        out_dir / "robustness_candidate_queue.csv",
        index=False,
    )
    decisions[decisions["closeout_label"].eq("test_only_diagnostic")].to_csv(
        out_dir / "test_only_diagnostic_queue.csv",
        index=False,
    )
    seed_plan.to_csv(out_dir / "robustness_seed_plan.csv", index=False)
    validation_selected.to_csv(out_dir / "hypothetical_validation_selected_registry.csv", index=False)
    robustness_registry.to_csv(out_dir / "hypothetical_robustness_candidate_registry.csv", index=False)
    pd.DataFrame(summaries).to_csv(out_dir / "registry_level_test_aql_audit.csv", index=False)
    report = write_report(out_dir, args, decisions, summaries, seed_plan)

    summary = {
        "status": "completed",
        "manifest_csv": config_path_value(args.manifest_csv),
        "run_root": config_path_value(args.run_root),
        "current_registry_csv": config_path_value(args.current_registry_csv),
        "priority_filter": priority,
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
        "n_experiments_in_manifest": int(manifest.shape[0]),
        "n_candidate_metric_rows": int(metrics.shape[0]),
        "n_experiment_bests": int(exp_best.shape[0]),
        "n_rescue_folds": int(decisions.shape[0]),
        "n_missing_metric_files": int(missing.shape[0]),
        "decision_counts": {
            str(k): int(v) for k, v in decisions["closeout_label"].value_counts().to_dict().items()
        },
        "n_robustness_candidates": int(decisions["closeout_label"].eq("robustness_candidate").sum()),
        "n_test_only_diagnostics": int(decisions["closeout_label"].eq("test_only_diagnostic").sum()),
        "registry_test_aql_audit": summaries,
        "selection_rule": "best rescue candidate per fold by validation AQL; current registry remains authoritative",
        "test_metrics_role": "audit/risk_label_only",
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = closeout(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
