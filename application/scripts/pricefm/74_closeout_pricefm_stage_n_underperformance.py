#!/usr/bin/env python3
"""Close out the Stage-N PriceFM underperformance search.

This script is intentionally conservative.  Stage-N spent compute on
region/fold rows where the current Q-DESN decision surface lagged PriceFM, but
candidate selection must remain validation-only.  Test metrics are reported as
audit diagnostics and may be used as promotion guardrails, not as hidden
selection criteria.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MANIFEST = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_n_underperformance_broad_20260625/manifest.csv"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_n_underperformance_broad_20260625"
)
DEFAULT_CURRENT_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/"
    "current_decision_surface_table.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_closeout_20260625"
)


META_COLS = [
    "id",
    "stage",
    "priority",
    "lag_window",
    "feature_policy",
    "feature_dim",
    "projection_scale",
    "depth",
    "units",
    "alpha",
    "rho",
    "input_scale",
    "recurrent_sparsity",
    "state_output",
    "tau0",
    "seed",
    "graph_degree",
    "graph_source",
    "graph_hash",
    "input_scope",
    "output_scope",
    "lead_covariate_status",
    "spatial_information_set",
    "candidate_family",
    "factor_changed",
    "target_tier",
    "stage_n_rescue_reason",
    "selection_rule",
    "selection_is_validation_only",
    "selected_on_split",
    "selected_on_unit",
    "selection_metric",
    "test_metrics_role",
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest-csv", default=DEFAULT_MANIFEST)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--current-decision-surface-csv", default=DEFAULT_CURRENT_SURFACE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--validation-tolerance", type=float, default=0.0)
    p.add_argument("--test-veto-tolerance", type=float, default=0.0)
    p.add_argument("--pricefm-close-delta", type=float, default=0.25)
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


def numeric(frame, col):
    if col not in frame.columns:
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def normalize_region_fold(frame, label):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def cell_status(run_dir):
    path = run_dir / "cell_status.csv"
    if not path.exists() or path.stat().st_size == 0:
        return "missing_status"
    try:
        status = pd.read_csv(path)
    except Exception:
        return "status_parse_error"
    if "status" not in status.columns:
        return "missing_status_column"
    vals = set(status["status"].astype(str))
    if "failed" in vals or "error" in vals:
        return "failed"
    if any("complete" in val for val in vals):
        return "completed"
    if "planned" in vals:
        return "planned_only"
    return ",".join(sorted(vals)) or "unknown"


def read_metric_summary(metric_path):
    metric = pd.read_csv(metric_path)
    require_columns(metric, ["method_id", "split", "unit", "AQL"], str(metric_path))
    metric = metric[metric["unit"].astype(str).eq("original")].copy()
    rows = []
    for method_id, sub in metric.groupby(metric["method_id"].astype(str), sort=False):
        row = {"method_id": method_id}
        for _, metric_row in sub.iterrows():
            split = str(metric_row["split"])
            for col in ["AQL", "AQCR", "MAE", "RMSE"]:
                if col in metric_row.index:
                    row["{}_{}".format(split, col)] = pd.to_numeric(
                        pd.Series([metric_row[col]]), errors="coerce"
                    ).iloc[0]
        rows.append(row)
    return rows


def read_long_metric_file(metric_path, extra_cols):
    metric = pd.read_csv(metric_path)
    require_columns(metric, ["method_id", "split", "unit", "AQL"], str(metric_path))
    metric = metric[metric["unit"].astype(str).eq("original")].copy()
    rows = []
    for _, metric_row in metric.iterrows():
        row = {
            "method_id": str(metric_row["method_id"]),
            "split": str(metric_row["split"]),
            "unit": str(metric_row["unit"]),
        }
        for col in extra_cols + ["AQL", "AQCR", "MAE", "RMSE"]:
            if col in metric_row.index:
                row[col] = metric_row[col]
        rows.append(row)
    return rows


def collect_candidate_metrics(manifest, run_root):
    run_root = repo_path(run_root)
    records = []
    missing = []
    for _, manifest_row in manifest.iterrows():
        exp_id = str(manifest_row["id"])
        run_dir = run_root / exp_id
        status = cell_status(run_dir)
        metric_paths = list(run_dir.glob("cells/region=*/fold=*/model/metric_summary.csv"))
        if not metric_paths:
            missing.append({
                "id": exp_id,
                "priority": manifest_row.get("priority", ""),
                "status": status,
                "run_dir": config_path_value(run_dir),
            })
            continue
        for metric_path in metric_paths:
            region = metric_path.parts[-4].split("=", 1)[1]
            fold = int(metric_path.parts[-3].split("=", 1)[1])
            for metric_row in read_metric_summary(metric_path):
                record = {
                    "region": region,
                    "fold": fold,
                    "cell_status": status,
                    "metric_summary": config_path_value(metric_path),
                    "run_dir": config_path_value(run_dir),
                }
                for col in META_COLS:
                    if col in manifest_row.index:
                        record[col] = manifest_row[col]
                record.update(metric_row)
                records.append(record)
    metrics = pd.DataFrame(records)
    missing = pd.DataFrame(missing)
    if not metrics.empty:
        metrics = normalize_region_fold(metrics, "candidate metrics")
    return metrics, missing


def collect_long_metrics(manifest, run_root, filename, extra_cols):
    run_root = repo_path(run_root)
    records = []
    for _, manifest_row in manifest.iterrows():
        exp_id = str(manifest_row["id"])
        run_dir = run_root / exp_id
        metric_paths = list(run_dir.glob("cells/region=*/fold=*/model/{}".format(filename)))
        for metric_path in metric_paths:
            region = metric_path.parts[-4].split("=", 1)[1]
            fold = int(metric_path.parts[-3].split("=", 1)[1])
            for metric_row in read_long_metric_file(metric_path, extra_cols):
                record = {
                    "region": region,
                    "fold": fold,
                    "metric_file": config_path_value(metric_path),
                    "run_dir": config_path_value(run_dir),
                }
                for col in META_COLS:
                    if col in manifest_row.index:
                        record[col] = manifest_row[col]
                record.update(metric_row)
                records.append(record)
    out = pd.DataFrame(records)
    if not out.empty:
        out = normalize_region_fold(out, filename)
    return out


def select_by_metric(metrics, split_col, value_col, label):
    eligible = metrics[
        metrics["cell_status"].eq("completed")
        & metrics[value_col].notna()
    ].copy()
    if eligible.empty:
        return pd.DataFrame()
    eligible = eligible.sort_values(["region", "fold", value_col, "id", "method_id"])
    out = eligible.groupby(["region", "fold"], as_index=False).first()
    out["selection_view"] = label
    out = out.rename(columns={value_col: split_col})
    return out


def select_by_rule(metrics, rule_id):
    eligible = metrics[
        metrics["cell_status"].eq("completed")
        & metrics["val_AQL"].notna()
        & metrics["test_AQL"].notna()
    ].copy()
    if eligible.empty:
        return pd.DataFrame()
    if rule_id == "val_aql_min":
        eligible["_selection_score"] = numeric(eligible, "val_AQL")
    elif rule_id == "val_mae_min":
        eligible["_selection_score"] = numeric(eligible, "val_MAE")
        eligible["_selection_score"] = eligible["_selection_score"].fillna(numeric(eligible, "val_AQL"))
    elif rule_id == "val_rmse_min":
        eligible["_selection_score"] = numeric(eligible, "val_RMSE")
        eligible["_selection_score"] = eligible["_selection_score"].fillna(numeric(eligible, "val_AQL"))
    elif rule_id == "robust_rank_val_aql_mae_rmse":
        rank_cols = []
        for col in ["val_AQL", "val_MAE", "val_RMSE"]:
            if col in eligible.columns:
                rank_col = "_rank_{}".format(col)
                eligible[rank_col] = eligible.groupby(["region", "fold"])[col].rank(
                    method="average", na_option="bottom"
                )
                rank_cols.append(rank_col)
        eligible["_selection_score"] = eligible[rank_cols].mean(axis=1)
    else:
        raise ValueError("Unknown Stage-N selection rule: {}".format(rule_id))
    eligible = eligible.sort_values(["region", "fold", "_selection_score", "val_AQL", "id", "method_id"])
    out = eligible.groupby(["region", "fold"], as_index=False).first()
    out["selection_view"] = rule_id
    return out.drop(columns=[c for c in out.columns if c.startswith("_rank_") or c == "_selection_score"])


def build_current_surface(path):
    current = read_csv_required(path, "current decision surface")
    current = normalize_region_fold(current, "current decision surface")
    require_columns(
        current,
        ["region", "fold", "median_selection_AQL", "median_test_AQL", "pricefm_AQL"],
        "current decision surface",
    )
    current = current.rename(columns={
        "median_selection_AQL": "current_val_AQL",
        "median_test_AQL": "current_test_AQL",
        "best_local_method": "current_method_id",
        "experiment_id": "current_experiment_id",
    })
    for col in ["current_val_AQL", "current_test_AQL", "pricefm_AQL"]:
        current[col] = numeric(current, col)
    keep = [
        "region",
        "fold",
        "current_method_id",
        "current_experiment_id",
        "current_val_AQL",
        "current_test_AQL",
        "pricefm_AQL",
        "decision_label",
        "information_set",
    ]
    return current[[col for col in keep if col in current.columns]].copy()


def attach_comparisons(selected, current, args):
    if selected.empty:
        return selected
    merged = selected.merge(current, on=["region", "fold"], how="left", validate="one_to_one")
    merged["delta_val_vs_current"] = numeric(merged, "val_AQL") - numeric(merged, "current_val_AQL")
    merged["delta_test_vs_current"] = numeric(merged, "test_AQL") - numeric(merged, "current_test_AQL")
    merged["delta_test_vs_pricefm"] = numeric(merged, "test_AQL") - numeric(merged, "pricefm_AQL")
    merged["validation_beats_current"] = (
        merged["delta_val_vs_current"] < -float(args.validation_tolerance)
    )
    merged["test_beats_current"] = (
        merged["delta_test_vs_current"] < -float(args.test_veto_tolerance)
    )
    merged["test_beats_pricefm"] = merged["delta_test_vs_pricefm"] < 0.0
    merged["test_close_to_pricefm"] = (
        merged["delta_test_vs_pricefm"] <= float(args.pricefm_close_delta)
    )
    merged["promotion_recommended"] = (
        merged["validation_beats_current"] & merged["test_beats_current"]
    )
    merged["promotion_decision"] = "do_not_promote"
    merged.loc[
        merged["validation_beats_current"] & ~merged["test_beats_current"],
        "promotion_decision",
    ] = "validation_gain_test_veto"
    merged.loc[
        ~merged["validation_beats_current"] & merged["test_beats_current"],
        "promotion_decision",
    ] = "test_gain_validation_miss"
    merged.loc[
        merged["promotion_recommended"],
        "promotion_decision",
    ] = "promote_validation_and_test_gain"
    return merged.sort_values(["region", "fold"]).reset_index(drop=True)


def build_selection_rule_sensitivity(metrics, current, args):
    rules = [
        "val_aql_min",
        "val_mae_min",
        "val_rmse_min",
        "robust_rank_val_aql_mae_rmse",
    ]
    rows = []
    selected_rows = []
    for rule_id in rules:
        selected = select_by_rule(metrics, rule_id)
        selected = attach_comparisons(selected, current, args)
        if selected.empty:
            rows.append({
                "rule_id": rule_id,
                "n_region_folds": 0,
                "n_test_improvements": 0,
                "n_beats_pricefm": 0,
                "mean_test_delta_vs_current": float("nan"),
                "mean_test_delta_vs_pricefm": float("nan"),
                "selection_uses_test_metrics": False,
            })
            continue
        selected["rule_id"] = rule_id
        selected_rows.append(selected)
        rows.append({
            "rule_id": rule_id,
            "n_region_folds": int(selected.shape[0]),
            "n_test_improvements": int(selected["test_beats_current"].sum()),
            "n_beats_pricefm": int(selected["test_beats_pricefm"].sum()),
            "n_promotions_strict": int(selected["promotion_recommended"].sum()),
            "mean_test_delta_vs_current": float(selected["delta_test_vs_current"].mean()),
            "median_test_delta_vs_current": float(selected["delta_test_vs_current"].median()),
            "mean_test_delta_vs_pricefm": float(selected["delta_test_vs_pricefm"].mean()),
            "median_test_delta_vs_pricefm": float(selected["delta_test_vs_pricefm"].median()),
            "selection_uses_test_metrics": False,
            "method_counts": {
                str(key): int(value)
                for key, value in selected["method_id"].value_counts().items()
            },
        })
    detail = pd.concat(selected_rows, ignore_index=True) if selected_rows else pd.DataFrame()
    return pd.DataFrame(rows), detail


def build_instability(validation_selected, test_oracle):
    if validation_selected.empty or test_oracle.empty:
        return pd.DataFrame()
    left_cols = [
        "region",
        "fold",
        "id",
        "method_id",
        "val_AQL",
        "test_AQL",
        "delta_test_vs_current",
        "delta_test_vs_pricefm",
        "promotion_decision",
    ]
    right_cols = [
        "region",
        "fold",
        "id",
        "method_id",
        "val_AQL",
        "test_AQL",
        "delta_test_vs_current",
        "delta_test_vs_pricefm",
    ]
    left = validation_selected[left_cols].rename(columns={
        "id": "validation_selected_id",
        "method_id": "validation_selected_method",
        "val_AQL": "validation_selected_val_AQL",
        "test_AQL": "validation_selected_test_AQL",
        "delta_test_vs_current": "validation_selected_delta_vs_current",
        "delta_test_vs_pricefm": "validation_selected_delta_vs_pricefm",
    })
    right = test_oracle[right_cols].rename(columns={
        "id": "test_oracle_id",
        "method_id": "test_oracle_method",
        "val_AQL": "test_oracle_val_AQL",
        "test_AQL": "test_oracle_test_AQL",
        "delta_test_vs_current": "test_oracle_delta_vs_current",
        "delta_test_vs_pricefm": "test_oracle_delta_vs_pricefm",
    })
    out = left.merge(right, on=["region", "fold"], how="outer", validate="one_to_one")
    out["same_candidate"] = (
        out["validation_selected_id"].astype(str).eq(out["test_oracle_id"].astype(str))
        & out["validation_selected_method"].astype(str).eq(out["test_oracle_method"].astype(str))
    )
    out["oracle_gain_missed_by_validation"] = (
        (out["test_oracle_delta_vs_current"] < 0.0)
        & (out["validation_selected_delta_vs_current"] >= 0.0)
    )
    out["oracle_advantage_over_validation"] = (
        out["test_oracle_test_AQL"] - out["validation_selected_test_AQL"]
    )
    out["instability_label"] = "aligned"
    out.loc[~out["same_candidate"], "instability_label"] = "different_candidate"
    out.loc[
        out["oracle_gain_missed_by_validation"],
        "instability_label",
    ] = "oracle_gain_missed_by_validation"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def build_split_shift_summary(validation_selected, test_oracle):
    if validation_selected.empty:
        return pd.DataFrame()
    rows = []
    for label, frame in [
        ("validation_selected", validation_selected),
        ("test_oracle", test_oracle),
    ]:
        if frame.empty:
            continue
        work = frame.copy()
        work["view"] = label
        work["val_to_test_AQL_shift"] = numeric(work, "test_AQL") - numeric(work, "val_AQL")
        work["abs_val_to_test_AQL_shift"] = work["val_to_test_AQL_shift"].abs()
        denom = numeric(work, "val_AQL").abs().clip(lower=1.0e-8)
        work["relative_val_to_test_AQL_shift"] = work["val_to_test_AQL_shift"] / denom
        work["current_val_to_test_AQL_shift"] = (
            numeric(work, "current_test_AQL") - numeric(work, "current_val_AQL")
        )
        keep = [
            "view", "region", "fold", "id", "method_id", "val_AQL", "test_AQL",
            "val_to_test_AQL_shift", "abs_val_to_test_AQL_shift",
            "relative_val_to_test_AQL_shift", "current_val_to_test_AQL_shift",
            "delta_test_vs_current", "delta_test_vs_pricefm", "promotion_decision",
        ]
        rows.append(work[[col for col in keep if col in work.columns]])
    return pd.concat(rows, ignore_index=True).sort_values(["region", "fold", "view"])


def build_horizon_gap_summary(validation_selected, test_oracle, horizon_group_metrics):
    if validation_selected.empty or test_oracle.empty or horizon_group_metrics.empty:
        return pd.DataFrame()
    instability = build_instability(validation_selected, test_oracle)
    rows = []
    h = horizon_group_metrics.copy()
    h["AQL"] = pd.to_numeric(h["AQL"], errors="coerce")
    h = h[h["AQL"].notna()].copy()
    for _, item in instability.iterrows():
        region = str(item["region"])
        fold = int(item["fold"])
        val_id = str(item["validation_selected_id"])
        val_method = str(item["validation_selected_method"])
        oracle_id = str(item["test_oracle_id"])
        oracle_method = str(item["test_oracle_method"])
        for group in sorted(h[
            h["region"].astype(str).eq(region)
            & h["fold"].astype(int).eq(fold)
        ]["horizon_group"].dropna().astype(str).unique()):
            base = {
                "region": region,
                "fold": fold,
                "horizon_group": group,
                "validation_selected_id": val_id,
                "validation_selected_method": val_method,
                "test_oracle_id": oracle_id,
                "test_oracle_method": oracle_method,
            }
            for prefix, exp_id, method in [
                ("validation_selected", val_id, val_method),
                ("test_oracle", oracle_id, oracle_method),
            ]:
                sub = h[
                    h["id"].astype(str).eq(exp_id)
                    & h["method_id"].astype(str).eq(method)
                    & h["region"].astype(str).eq(region)
                    & h["fold"].astype(int).eq(fold)
                    & h["horizon_group"].astype(str).eq(group)
                ]
                for split in ["val", "test"]:
                    vals = sub[sub["split"].astype(str).eq(split)]["AQL"]
                    base["{}_{}_AQL".format(prefix, split)] = (
                        float(vals.iloc[0]) if not vals.empty else float("nan")
                    )
            base["oracle_minus_validation_test_AQL"] = (
                base["test_oracle_test_AQL"] - base["validation_selected_test_AQL"]
            )
            base["oracle_better_on_test_group"] = base["oracle_minus_validation_test_AQL"] < 0.0
            rows.append(base)
    return pd.DataFrame(rows).sort_values(["region", "fold", "horizon_group"])


def summarize_counts(validation_selected, test_oracle, candidate_metrics, missing, manifest):
    def metric_summary(frame, prefix):
        if frame.empty:
            return {
                "{}_n_region_folds".format(prefix): 0,
                "{}_beats_current".format(prefix): 0,
                "{}_beats_pricefm".format(prefix): 0,
                "{}_mean_delta_vs_current".format(prefix): float("nan"),
                "{}_mean_delta_vs_pricefm".format(prefix): float("nan"),
            }
        return {
            "{}_n_region_folds".format(prefix): int(frame.shape[0]),
            "{}_beats_current".format(prefix): int(frame["test_beats_current"].sum()),
            "{}_beats_pricefm".format(prefix): int(frame["test_beats_pricefm"].sum()),
            "{}_mean_delta_vs_current".format(prefix): float(frame["delta_test_vs_current"].mean()),
            "{}_mean_delta_vs_pricefm".format(prefix): float(frame["delta_test_vs_pricefm"].mean()),
        }

    summary = {
        "manifest_rows": int(manifest.shape[0]),
        "candidate_metric_rows": int(candidate_metrics.shape[0]),
        "missing_metric_rows": int(missing.shape[0]),
        "completed_cells": int(
            candidate_metrics[["id", "region", "fold"]].drop_duplicates().shape[0]
        ) if not candidate_metrics.empty else 0,
    }
    summary.update(metric_summary(validation_selected, "validation_selected"))
    summary.update(metric_summary(test_oracle, "test_oracle"))
    if not validation_selected.empty:
        summary["validation_selected_promotion_recommended"] = int(
            validation_selected["promotion_recommended"].sum()
        )
        summary["validation_selected_method_counts"] = (
            validation_selected["method_id"].value_counts().to_dict()
        )
    if not test_oracle.empty:
        summary["test_oracle_method_counts"] = test_oracle["method_id"].value_counts().to_dict()
    return summary


def group_count(frame, group_cols, label):
    if frame.empty:
        return pd.DataFrame(columns=group_cols + ["view", "n"])
    out = frame.groupby(group_cols, dropna=False).size().reset_index(name="n")
    out["view"] = label
    return out


def write_report(
    out_dir,
    summary,
    validation_selected,
    test_oracle,
    instability,
    rule_sensitivity,
):
    report = out_dir / "stage_n_underperformance_closeout_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM Stage-N Underperformance Closeout\n\n")
        f.write("Stage-N is complete. Candidate selection in this closeout uses validation AQL; ")
        f.write("test metrics are audit diagnostics and promotion guardrails only.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Validation-Selected Rows\n\n")
        f.write("| region | fold | candidate | method | val AQL | test AQL | current test AQL | PriceFM AQL | decision |\n")
        f.write("|---|---:|---|---|---:|---:|---:|---:|---|\n")
        for _, row in validation_selected.sort_values(["region", "fold"]).iterrows():
            f.write("| {region} | {fold} | {candidate} | {method} | {val:.3f} | {test:.3f} | {cur:.3f} | {pfm:.3f} | {decision} |\n".format(
                region=row["region"],
                fold=int(row["fold"]),
                candidate=row["id"],
                method=row["method_id"],
                val=float(row["val_AQL"]),
                test=float(row["test_AQL"]),
                cur=float(row["current_test_AQL"]),
                pfm=float(row["pricefm_AQL"]),
                decision=row["promotion_decision"],
            ))
        f.write("\n## Test-Oracle Diagnostic\n\n")
        f.write("The test-oracle table is diagnostic only. It shows available upside in the grid, ")
        f.write("but must not be used as the promotion rule.\n\n")
        f.write("| region | fold | candidate | method | test AQL | current test AQL | PriceFM AQL |\n")
        f.write("|---|---:|---|---|---:|---:|---:|\n")
        for _, row in test_oracle.sort_values(["region", "fold"]).iterrows():
            f.write("| {region} | {fold} | {candidate} | {method} | {test:.3f} | {cur:.3f} | {pfm:.3f} |\n".format(
                region=row["region"],
                fold=int(row["fold"]),
                candidate=row["id"],
                method=row["method_id"],
                test=float(row["test_AQL"]),
                cur=float(row["current_test_AQL"]),
                pfm=float(row["pricefm_AQL"]),
            ))
        f.write("\n## Selection Instability\n\n")
        f.write("| region | fold | label | validation candidate | oracle candidate | oracle advantage |\n")
        f.write("|---|---:|---|---|---|---:|\n")
        for _, row in instability.sort_values(["region", "fold"]).iterrows():
            f.write("| {region} | {fold} | {label} | {val_id} | {oracle_id} | {adv:.3f} |\n".format(
                region=row["region"],
                fold=int(row["fold"]),
                label=row["instability_label"],
                val_id=row["validation_selected_id"],
                oracle_id=row["test_oracle_id"],
                adv=float(row["oracle_advantage_over_validation"]),
            ))
        f.write("\n## Validation-Only Rule Sensitivity\n\n")
        f.write("| rule | test improvements | mean delta vs current | mean delta vs PriceFM |\n")
        f.write("|---|---:|---:|---:|\n")
        for _, row in rule_sensitivity.sort_values("rule_id").iterrows():
            f.write("| {rule} | {n} | {dc:.3f} | {dp:.3f} |\n".format(
                rule=row["rule_id"],
                n=int(row["n_test_improvements"]),
                dc=float(row["mean_test_delta_vs_current"]),
                dp=float(row["mean_test_delta_vs_pricefm"]),
            ))
        f.write("\n## Decision\n\n")
        f.write("Do not replace the current decision surface wholesale from Stage-N. ")
        f.write("Promote only validation-selected rows that also pass the test guardrail, ")
        f.write("then investigate the remaining validation/test mismatch before another broad launch.\n")
    return report


def closeout(args):
    manifest = read_csv_required(args.manifest_csv, "Stage-N manifest")
    require_columns(manifest, ["id", "priority"], "Stage-N manifest")
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    metrics, missing = collect_candidate_metrics(manifest, args.run_root)
    horizon_metrics = collect_long_metrics(manifest, args.run_root, "metric_by_horizon.csv", ["horizon"])
    horizon_group_metrics = collect_long_metrics(
        manifest, args.run_root, "metric_by_horizon_group.csv", ["horizon_group"]
    )
    current = build_current_surface(args.current_decision_surface_csv)

    validation_selected = select_by_metric(metrics, "val_AQL", "val_AQL", "validation_selected")
    validation_selected = attach_comparisons(validation_selected, current, args)
    test_oracle = select_by_metric(metrics, "test_AQL", "test_AQL", "test_oracle")
    test_oracle = attach_comparisons(test_oracle, current, args)
    instability = build_instability(validation_selected, test_oracle)
    split_shift = build_split_shift_summary(validation_selected, test_oracle)
    horizon_gap = build_horizon_gap_summary(validation_selected, test_oracle, horizon_group_metrics)
    rule_sensitivity, rule_selected = build_selection_rule_sensitivity(metrics, current, args)

    method_summary = pd.concat([
        group_count(validation_selected, ["method_id"], "validation_selected"),
        group_count(test_oracle, ["method_id"], "test_oracle"),
        group_count(
            metrics[metrics["cell_status"].eq("completed")],
            ["method_id"],
            "all_completed_method_rows",
        ),
    ], ignore_index=True)
    factor_summary = pd.concat([
        group_count(validation_selected, ["factor_changed"], "validation_selected"),
        group_count(test_oracle, ["factor_changed"], "test_oracle"),
    ], ignore_index=True)
    promotions = validation_selected[validation_selected["promotion_recommended"]].copy()
    remaining_gap = validation_selected[~validation_selected["test_beats_pricefm"]].copy()
    health = pd.DataFrame([
        {"check": "manifest_rows", "status": "pass", "value": int(manifest.shape[0])},
        {"check": "candidate_metric_rows", "status": "pass" if not metrics.empty else "fail", "value": int(metrics.shape[0])},
        {"check": "missing_metric_rows", "status": "pass" if missing.empty else "warn", "value": int(missing.shape[0])},
        {"check": "horizon_metric_rows", "status": "pass" if not horizon_metrics.empty else "warn", "value": int(horizon_metrics.shape[0])},
        {"check": "horizon_group_metric_rows", "status": "pass" if not horizon_group_metrics.empty else "warn", "value": int(horizon_group_metrics.shape[0])},
        {"check": "validation_selected_region_folds", "status": "pass", "value": int(validation_selected.shape[0])},
        {"check": "test_oracle_region_folds", "status": "pass", "value": int(test_oracle.shape[0])},
        {"check": "failed_cells", "status": "pass" if not metrics["cell_status"].eq("failed").any() else "fail", "value": int(metrics["cell_status"].eq("failed").sum())},
    ])
    summary = summarize_counts(validation_selected, test_oracle, metrics, missing, manifest)

    metrics.to_csv(out_dir / "candidate_method_metrics.csv", index=False)
    metrics.to_csv(out_dir / "stage_n_cell_method_metrics.csv", index=False)
    missing.to_csv(out_dir / "missing_metric_files.csv", index=False)
    validation_selected.to_csv(out_dir / "validation_selected_closeout.csv", index=False)
    test_oracle.to_csv(out_dir / "test_oracle_diagnostics.csv", index=False)
    instability.to_csv(out_dir / "selection_instability_audit.csv", index=False)
    split_shift.to_csv(out_dir / "split_shift_summary.csv", index=False)
    horizon_gap.to_csv(out_dir / "horizon_gap_summary.csv", index=False)
    rule_sensitivity.to_csv(out_dir / "selection_rule_sensitivity.csv", index=False)
    rule_selected.to_csv(out_dir / "selection_rule_selected_rows.csv", index=False)
    method_summary.to_csv(out_dir / "method_summary.csv", index=False)
    factor_summary.to_csv(out_dir / "factor_summary.csv", index=False)
    promotions.to_csv(out_dir / "promotion_candidates.csv", index=False)
    remaining_gap.to_csv(out_dir / "remaining_pricefm_gap.csv", index=False)
    health.to_csv(out_dir / "closeout_health.csv", index=False)
    if not rule_sensitivity.empty:
        summary["best_validation_only_rule_by_test_improvements"] = str(
            rule_sensitivity.sort_values(
                ["n_test_improvements", "mean_test_delta_vs_current"],
                ascending=[False, True],
            ).iloc[0]["rule_id"]
        )
    report = write_report(
        out_dir,
        summary,
        validation_selected,
        test_oracle,
        instability,
        rule_sensitivity,
    )
    summary.update({
        "manifest_csv": config_path_value(args.manifest_csv),
        "run_root": config_path_value(args.run_root),
        "current_decision_surface_csv": config_path_value(args.current_decision_surface_csv),
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
    })
    write_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main():
    closeout(parser().parse_args())


if __name__ == "__main__":
    main()
