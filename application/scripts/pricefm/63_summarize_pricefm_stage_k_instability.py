#!/usr/bin/env python3
"""Consolidate Stage-J PriceFM instability diagnostics for Stage-K planning."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_CLOSEOUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_j_information_set_rescue_priority0_closeout_20260623"
)
DEFAULT_SEEDROB_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_j_information_set_rescue_seedrob_summary_20260623"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_k_instability_diagnostics_20260623"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--closeout-decisions-csv",
        default=str(Path(DEFAULT_CLOSEOUT_DIR) / "rescue_closeout_decisions.csv"),
    )
    p.add_argument(
        "--candidate-metrics-csv",
        default=str(Path(DEFAULT_CLOSEOUT_DIR) / "rescue_candidate_metrics.csv"),
    )
    p.add_argument(
        "--seedrob-decisions-csv",
        default=str(Path(DEFAULT_SEEDROB_DIR) / "seedrob_decisions.csv"),
    )
    p.add_argument(
        "--seedrob-summary-csv",
        default=str(Path(DEFAULT_SEEDROB_DIR) / "seedrob_candidate_summary.csv"),
    )
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_optional(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    try:
        return pd.read_csv(path)
    except pd.errors.EmptyDataError:
        return pd.DataFrame()


def add_key(frame):
    if frame.empty:
        return frame
    out = frame.copy()
    if "region" in out.columns:
        out["region"] = out["region"].astype(str)
    if "fold" in out.columns:
        out["fold"] = pd.to_numeric(out["fold"], errors="coerce").astype("Int64")
    if "source_rescue_experiment_id" not in out.columns and "experiment_id" in out.columns:
        out["source_rescue_experiment_id"] = out["experiment_id"].astype(str)
    return out


def classify_row(row):
    closeout = str(row.get("closeout_label", ""))
    seed_pass = row.get("pass_seed_robustness", None)
    mean_test_delta = row.get("mean_test_delta_vs_current", None)
    try:
        mean_test_delta = float(mean_test_delta)
    except (TypeError, ValueError):
        mean_test_delta = None

    if seed_pass is True or str(seed_pass).lower() == "true":
        return "seed_robust_candidate"
    if seed_pass is False or str(seed_pass).lower() == "false":
        if mean_test_delta is not None and mean_test_delta <= 0.0:
            return "seed_unstable_audit_helpful"
        return "seed_unstable_audit_harmful_or_unknown"
    if closeout == "robustness_candidate":
        return "needs_seed_robustness"
    if closeout == "validation_candidate_audit_worse":
        return "validation_audit_mismatch"
    if closeout == "validation_overfit_warning":
        return "validation_overfit_severe"
    if closeout in ("keep_current", "keep_current_registry"):
        return "stable_keep_current"
    if closeout:
        return closeout
    return "unclassified"


def candidate_flat(closeout, candidates, seed_summary):
    closeout = add_key(closeout)
    candidates = add_key(candidates)
    seed_summary = add_key(seed_summary)
    if not closeout.empty:
        base = closeout.copy()
    elif not candidates.empty:
        base = candidates.copy()
    else:
        base = pd.DataFrame()
    if base.empty:
        return base

    keep_seed_cols = [
        "region", "fold", "source_rescue_experiment_id", "n_seeds",
        "n_validation_improved", "n_test_improved", "validation_win_rate",
        "mean_val_delta_vs_current", "max_val_delta_vs_current",
        "mean_test_delta_vs_current", "max_test_delta_vs_current",
        "pass_seed_robustness", "recommended_action",
    ]
    if not seed_summary.empty:
        base = base.merge(
            seed_summary[[c for c in keep_seed_cols if c in seed_summary.columns]],
            on=["region", "fold", "source_rescue_experiment_id"],
            how="left",
            suffixes=("", "_seedrob"),
        )
    base["stage_k_failure_class"] = base.apply(classify_row, axis=1)
    base["stage_k_next_action"] = base["stage_k_failure_class"].map({
        "seed_robust_candidate": "queue_validation_clean_closeout",
        "seed_unstable_audit_helpful": "try_regularized_graph_summary_multiseed",
        "seed_unstable_audit_harmful_or_unknown": "defer_or_reduce_graph_width",
        "needs_seed_robustness": "run_seed_robustness_before_promotion",
        "validation_audit_mismatch": "try_regularized_graph_summary_multiseed",
        "validation_overfit_severe": "prefer_compact_summary_or_target_only",
        "stable_keep_current": "keep_authoritative_current",
    }).fillna("manual_review")
    return base


def seed_sensitivity(seed_decisions):
    seed_decisions = add_key(seed_decisions)
    if seed_decisions.empty:
        return seed_decisions
    group_cols = ["region", "fold", "source_rescue_experiment_id"]
    rows = []
    for key, sub in seed_decisions.groupby(group_cols, dropna=False):
        rows.append({
            "region": key[0],
            "fold": int(key[1]),
            "source_rescue_experiment_id": key[2],
            "n_seeds": int(sub.shape[0]),
            "val_delta_min": float(sub["val_delta_vs_current"].min()),
            "val_delta_max": float(sub["val_delta_vs_current"].max()),
            "val_delta_sd": float(sub["val_delta_vs_current"].std(ddof=0)),
            "test_delta_min": float(sub["test_delta_vs_current"].min()),
            "test_delta_max": float(sub["test_delta_vs_current"].max()),
            "test_delta_sd": float(sub["test_delta_vs_current"].std(ddof=0)),
            "validation_win_rate": float(sub["validation_improved"].mean()),
            "test_win_rate": float(sub["test_improved"].mean()),
        })
    return pd.DataFrame(rows).sort_values([
        "region", "fold", "source_rescue_experiment_id"
    ]).reset_index(drop=True)


def failure_taxonomy(flat):
    if flat.empty:
        return pd.DataFrame(columns=["stage_k_failure_class", "n_rows"])
    return (
        flat.groupby("stage_k_failure_class", dropna=False)
        .size()
        .reset_index(name="n_rows")
        .sort_values(["n_rows", "stage_k_failure_class"], ascending=[False, True])
        .reset_index(drop=True)
    )


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


def write_report(out_dir, flat, sensitivity, taxonomy):
    report = out_dir / "stage_k_diagnostic_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-K Instability Diagnostics\n\n")
        f.write("This is a selection-clean consolidation of Stage-J outcomes. ")
        f.write("Test columns remain audit-only and do not promote candidates.\n\n")
        f.write("## Failure Taxonomy\n\n")
        f.write(markdown_table(taxonomy))
        f.write("\n\n## Candidate Next Actions\n\n")
        f.write(markdown_table(
            flat,
            columns=[
                "region", "fold", "experiment_id", "method_id", "feature_policy",
                "graph_degree", "val_delta_vs_current", "test_delta_vs_current",
                "closeout_label", "stage_k_failure_class", "stage_k_next_action",
            ],
            limit=120,
        ))
        f.write("\n\n## Seed Sensitivity\n\n")
        f.write(markdown_table(sensitivity, limit=80))
        f.write("\n")
    return report


def summarize(args):
    closeout = read_csv_optional(args.closeout_decisions_csv)
    candidates = read_csv_optional(args.candidate_metrics_csv)
    seed_decisions = read_csv_optional(args.seedrob_decisions_csv)
    seed_summary = read_csv_optional(args.seedrob_summary_csv)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    flat = candidate_flat(closeout, candidates, seed_summary)
    sensitivity = seed_sensitivity(seed_decisions)
    taxonomy = failure_taxonomy(flat)

    flat.to_csv(out_dir / "stage_j_candidate_flat.csv", index=False)
    sensitivity.to_csv(out_dir / "stage_j_seed_sensitivity.csv", index=False)
    taxonomy.to_csv(out_dir / "stage_j_failure_taxonomy.csv", index=False)
    report = write_report(out_dir, flat, sensitivity, taxonomy)
    summary = {
        "n_closeout_rows": int(closeout.shape[0]),
        "n_candidate_rows": int(candidates.shape[0]),
        "n_seed_decision_rows": int(seed_decisions.shape[0]),
        "n_flat_rows": int(flat.shape[0]),
        "n_failure_classes": int(taxonomy.shape[0]),
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
