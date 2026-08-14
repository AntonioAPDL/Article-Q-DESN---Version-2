#!/usr/bin/env python3
"""Prepare missing PriceFM region/folds for Stage-E paper-quantile completion.

This script does not fit models. It audits a median-selection registry against
one or more already-frozen quantile decision registries, then writes the
region/fold rows that still need seven-quantile local-vs-PriceFM evaluation.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--median-registry-csv", required=True)
    p.add_argument(
        "--decision-source",
        action="append",
        default=[],
        help="Existing frozen decision source as label=path. May be repeated.",
    )
    p.add_argument("--output-dir", required=True)
    p.add_argument("--stage-label", default="stage_e_full_panel_quantile_completion")
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def validate_unique_region_folds(frame, context):
    require_columns(frame, ["region", "fold"], context)
    keys = frame[["region", "fold"]].copy()
    keys["region"] = keys["region"].astype(str)
    keys["fold"] = pd.to_numeric(keys["fold"], errors="raise").astype(int)
    dup = keys[keys.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        raise ValueError(
            "{} has duplicate region/fold rows:\n{}".format(
                context, dup.to_string(index=False)
            )
        )


def normalize_keys(frame):
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def parse_decision_source(value):
    if "=" not in str(value):
        raise ValueError("--decision-source must have form label=path")
    label, path = str(value).split("=", 1)
    label = label.strip()
    path = path.strip()
    if not label or not path:
        raise ValueError("--decision-source must have non-empty label and path")
    return label, path


def read_decision_sources(values):
    rows = []
    sources = []
    for value in values:
        label, path = parse_decision_source(value)
        frame = read_csv_required(path, "decision source {}".format(label))
        require_columns(frame, ["region", "fold", "stage_c_quantile_decision"], label)
        validate_unique_region_folds(frame, label)
        frame = normalize_keys(frame)
        frame["decision_source"] = label
        frame["decision_source_path"] = config_path_value(path)
        rows.append(frame[["region", "fold", "stage_c_quantile_decision", "decision_source", "decision_source_path"]])
        sources.append({"label": label, "path": config_path_value(path), "rows": int(frame.shape[0])})
    if rows:
        decisions = pd.concat(rows, ignore_index=True)
    else:
        decisions = pd.DataFrame(columns=[
            "region", "fold", "stage_c_quantile_decision",
            "decision_source", "decision_source_path",
        ])
    return decisions, sources


def prepare(args):
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    median = read_csv_required(args.median_registry_csv, "median registry")
    validate_unique_region_folds(median, "median registry")
    median = normalize_keys(median)

    decisions, sources = read_decision_sources(args.decision_source)
    if not decisions.empty:
        decision_keys = decisions[["region", "fold"]].drop_duplicates()
        decision_keys["has_quantile_decision"] = True
        source_labels = (
            decisions.groupby(["region", "fold"], as_index=False)
            .agg(covered_decision_sources=("decision_source", lambda x: "|".join(x.astype(str))))
        )
    else:
        decision_keys = pd.DataFrame(columns=["region", "fold", "has_quantile_decision"])
        source_labels = pd.DataFrame(columns=["region", "fold", "covered_decision_sources"])

    coverage = median.merge(decision_keys, on=["region", "fold"], how="left")
    coverage = coverage.merge(source_labels, on=["region", "fold"], how="left")
    coverage["has_quantile_decision"] = coverage["has_quantile_decision"].fillna(False).astype(bool)
    coverage["covered_decision_sources"] = coverage["covered_decision_sources"].fillna("")
    coverage["stage_e_action"] = coverage["has_quantile_decision"].map(
        {True: "already_frozen", False: "needs_paper_quantile_completion"}
    )

    missing = coverage[~coverage["has_quantile_decision"]].copy()
    registry_cols = [col for col in median.columns if col in missing.columns]
    missing_registry = missing[registry_cols].copy()

    coverage_path = out_dir / "stage_e_coverage_audit.csv"
    missing_path = out_dir / "stage_e_missing_quantile_registry.csv"
    coverage.to_csv(coverage_path, index=False)
    missing_registry.to_csv(missing_path, index=False)

    by_region = (
        coverage.groupby(["region", "stage_e_action"], as_index=False)
        .size()
        .rename(columns={"size": "n_region_folds"})
        .sort_values(["region", "stage_e_action"])
    )
    by_region_path = out_dir / "stage_e_coverage_by_region.csv"
    by_region.to_csv(by_region_path, index=False)

    summary = {
        "status": "completed",
        "stage_label": args.stage_label,
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "decision_sources": sources,
        "output_dir": config_path_value(out_dir),
        "n_median_rows": int(median.shape[0]),
        "n_existing_decision_sources": len(sources),
        "n_existing_decision_rows_raw": int(decisions.shape[0]),
        "n_covered_region_folds": int(coverage["has_quantile_decision"].sum()),
        "n_missing_region_folds": int((~coverage["has_quantile_decision"]).sum()),
        "outputs": {
            "coverage_audit": config_path_value(coverage_path),
            "coverage_by_region": config_path_value(by_region_path),
            "missing_quantile_registry": config_path_value(missing_path),
        },
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = prepare(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
