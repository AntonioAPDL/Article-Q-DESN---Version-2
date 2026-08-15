#!/usr/bin/env python3
"""Validate and freeze the current PriceFM decision surface."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import shutil

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_i_unresolved_seedrob_patched_registry_20260623/"
    "patched_selection_registry.csv"
)
DEFAULT_QUANTILE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_authoritative_quantile_decisions_stage_i_unresolved_20260623/"
    "authoritative_quantile_decision_registry.csv"
)
DEFAULT_STAGE_J_CLOSEOUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_j_information_set_rescue_priority0_closeout_20260623/"
    "rescue_closeout_decisions.csv"
)
DEFAULT_STAGE_K_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_k_regularized_graph_multiseed_summary_20260623/"
    "multiseed_geometry_summary.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--quantile-decision-registry-csv", default=DEFAULT_QUANTILE_REGISTRY)
    p.add_argument("--stage-j-closeout-csv", default=DEFAULT_STAGE_J_CLOSEOUT)
    p.add_argument("--stage-k-summary-csv", default=DEFAULT_STAGE_K_SUMMARY)
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


def numeric_series(frame, col):
    if col not in frame.columns:
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def finite_count(frame, col):
    vals = numeric_series(frame, col)
    return int(vals.notna().sum())


def duplicate_key_rows(frame):
    if not {"region", "fold"}.issubset(frame.columns):
        return pd.DataFrame(columns=["region", "fold"])
    work = frame.copy()
    work["region"] = work["region"].astype(str)
    work["fold"] = work["fold"].astype(int)
    dup = work[work.duplicated(["region", "fold"], keep=False)]
    return dup[["region", "fold"]].drop_duplicates().sort_values(["region", "fold"])


def key_frame(frame):
    out = frame[["region", "fold"]].copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    return out.drop_duplicates().sort_values(["region", "fold"]).reset_index(drop=True)


def health_row(dataset, check, status, detail="", n_rows=None):
    return {
        "dataset": dataset,
        "check": check,
        "status": status,
        "detail": detail,
        "n_rows": n_rows,
    }


def require_columns(frame, columns, label, health):
    missing = [c for c in columns if c not in frame.columns]
    status = "pass" if not missing else "fail"
    health.append(health_row(label, "required_columns", status, ",".join(missing), len(frame)))


def check_unique_keys(frame, label, health):
    dup = duplicate_key_rows(frame)
    status = "pass" if dup.empty else "fail"
    detail = "" if dup.empty else dup.to_dict("records")
    health.append(health_row(label, "unique_region_fold_keys", status, str(detail), len(frame)))
    return dup


def check_finite(frame, label, columns, health):
    bad_rows = []
    for col in columns:
        vals = numeric_series(frame, col)
        bad = frame[vals.isna()].copy()
        if not bad.empty and {"region", "fold"}.issubset(frame.columns):
            for _, row in bad[["region", "fold"]].drop_duplicates().iterrows():
                bad_rows.append({"region": str(row["region"]), "fold": int(row["fold"]), "column": col})
        elif not bad.empty:
            bad_rows.append({"column": col, "n_bad": int(bad.shape[0])})
    status = "pass" if not bad_rows else "fail"
    health.append(health_row(label, "finite_required_metrics", status, json.dumps(bad_rows), len(frame)))
    return bad_rows


def write_report(out_dir, summary, health, median, quantile, gaps, stage_k):
    report = out_dir / "current_decision_surface_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-L Current Decision Surface\n\n")
        f.write("This report validates the current median and paper-quantile decision ")
        f.write("surface before any further targeted rescue launch.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Health Checks\n\n")
        f.write("| dataset | check | status | detail |\n")
        f.write("|---|---|---|---|\n")
        for row in health:
            f.write("| {dataset} | {check} | {status} | {detail} |\n".format(
                dataset=row["dataset"],
                check=row["check"],
                status=row["status"],
                detail=str(row["detail"]).replace("|", "\\|"),
            ))
        f.write("\n## Registry Sizes\n\n")
        f.write("| registry | rows | unique region/folds |\n")
        f.write("|---|---:|---:|\n")
        f.write("| current median | {} | {} |\n".format(len(median), len(key_frame(median))))
        f.write("| current quantile decision | {} | {} |\n".format(len(quantile), len(key_frame(quantile))))
        f.write("| Stage-K geometry summary | {} | {} |\n".format(len(stage_k), len(key_frame(stage_k)) if {"region", "fold"}.issubset(stage_k.columns) else 0))
        f.write("\n## Broad Quantile Median Field Gaps\n\n")
        if gaps.empty:
            f.write("_No gaps._\n")
        else:
            f.write("| region | fold | missing_selection_AQL | missing_test_AQL |\n")
            f.write("|---|---:|---|---|\n")
            for _, row in gaps.iterrows():
                f.write("| {} | {} | {} | {} |\n".format(
                    row["region"], int(row["fold"]),
                    bool(row["missing_selection_AQL"]),
                    bool(row["missing_test_AQL"]),
                ))
        f.write("\n## Decision\n\n")
        if summary["fatal_failures"] == 0:
            f.write("The current decision surface is finite and usable for Stage-L tooling.\n")
        else:
            f.write("The current decision surface failed validation. Do not launch Stage-L fits.\n")
    return report


def summarize(args):
    median = read_csv_required(args.median_registry_csv, "median registry")
    quantile = read_csv_required(args.quantile_decision_registry_csv, "quantile decision registry")
    stage_j = read_csv_required(args.stage_j_closeout_csv, "Stage-J closeout")
    stage_k = read_csv_required(args.stage_k_summary_csv, "Stage-K summary")

    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} already exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    health = []
    require_columns(median, ["region", "fold", "selection_AQL", "test_AQL"], "current_median", health)
    require_columns(quantile, ["region", "fold", "local_AQL", "pricefm_AQL", "delta_abs"], "current_quantile", health)
    require_columns(stage_j, ["region", "fold", "selection_AQL", "test_AQL"], "stage_j_closeout", health)
    require_columns(stage_k, ["region", "fold", "mean_val_delta_vs_current", "pass_multiseed_validation_gate"], "stage_k_summary", health)

    for label, frame in [
        ("current_median", median),
        ("current_quantile", quantile),
        ("stage_j_closeout", stage_j),
    ]:
        check_unique_keys(frame, label, health)

    check_finite(median, "current_median", ["selection_AQL", "test_AQL"], health)
    check_finite(quantile, "current_quantile", ["local_AQL", "pricefm_AQL", "delta_abs"], health)
    check_finite(stage_j, "stage_j_closeout", ["selection_AQL", "test_AQL"], health)
    check_finite(stage_k, "stage_k_summary", ["mean_val_delta_vs_current", "max_val_delta_vs_current"], health)

    n_region_folds = len(key_frame(quantile)) if {"region", "fold"}.issubset(quantile.columns) else 0
    health.append(health_row(
        "current_quantile", "expected_region_fold_count",
        "pass" if n_region_folds == int(args.expected_region_folds) else "fail",
        "{}".format(n_region_folds), len(quantile)
    ))

    median_keys = key_frame(median)
    quantile_keys = key_frame(quantile)
    missing_median = quantile_keys.merge(median_keys, on=["region", "fold"], how="left", indicator=True)
    missing_median = missing_median[missing_median["_merge"].eq("left_only")][["region", "fold"]]
    health.append(health_row(
        "current_surface", "median_covers_quantile_keys",
        "pass" if missing_median.empty else "fail",
        "" if missing_median.empty else str(missing_median.to_dict("records")),
        len(quantile_keys),
    ))

    gaps = pd.DataFrame(columns=["region", "fold", "missing_selection_AQL", "missing_test_AQL"])
    if {"region", "fold", "selection_AQL", "test_AQL"}.issubset(quantile.columns):
        work = quantile[["region", "fold", "selection_AQL", "test_AQL"]].copy()
        work["region"] = work["region"].astype(str)
        work["fold"] = work["fold"].astype(int)
        work["missing_selection_AQL"] = numeric_series(work, "selection_AQL").isna()
        work["missing_test_AQL"] = numeric_series(work, "test_AQL").isna()
        gaps = work[work["missing_selection_AQL"] | work["missing_test_AQL"]][[
            "region", "fold", "missing_selection_AQL", "missing_test_AQL",
        ]].sort_values(["region", "fold"])

    health_frame = pd.DataFrame(health)
    fatal_failures = int((health_frame["status"] == "fail").sum())
    summary = {
        "fatal_failures": fatal_failures,
        "n_current_median_rows": int(len(median)),
        "n_current_quantile_rows": int(len(quantile)),
        "n_stage_j_closeout_rows": int(len(stage_j)),
        "n_stage_k_geometry_rows": int(len(stage_k)),
        "n_quantile_median_field_gap_rows": int(len(gaps)),
        "output_dir": config_path_value(out_dir),
    }

    median.to_csv(out_dir / "current_median_registry.csv", index=False)
    quantile.to_csv(out_dir / "current_quantile_decision_registry.csv", index=False)
    health_frame.to_csv(out_dir / "registry_health.csv", index=False)
    gaps.to_csv(out_dir / "quantile_registry_median_field_gaps.csv", index=False)
    paths = {
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "quantile_decision_registry_csv": config_path_value(args.quantile_decision_registry_csv),
        "stage_j_closeout_csv": config_path_value(args.stage_j_closeout_csv),
        "stage_k_summary_csv": config_path_value(args.stage_k_summary_csv),
    }
    write_json(out_dir / "baseline_paths.json", paths)
    report = write_report(out_dir, summary, health, median, quantile, gaps, stage_k)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    if fatal_failures:
        raise ValueError("Current decision surface failed {} health checks; see {}".format(
            fatal_failures, out_dir / "registry_health.csv"
        ))
    return summary


def main():
    args = parser().parse_args()
    summary = summarize(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
