#!/usr/bin/env python3
"""Close out a Stage-B PriceFM median registry for new regions.

This closeout is append/triage oriented. Unlike
``34_closeout_pricefm_median_registry.py``, it does not require every
region/fold to exist in a previous authoritative registry. The previous
registry is used only as context for already-covered checks.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_NAIVE_METHODS = "naive1_prev_day,naive2_prev3_avg,naive3_prev7_avg"
DEFAULT_QDESN_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)
DEFAULT_DIAGNOSTIC_METHODS = "normal_rhs_ns,normal_scaled_ridge"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--registry-dir", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--previous-registry-csv", default=None)
    p.add_argument("--grid-id", default="pricefm_stage_b_median_batch1_20260616")
    p.add_argument("--candidate-source", default="stage_b_local_median_batch1_20260616")
    p.add_argument("--selection-methods", default=DEFAULT_QDESN_METHODS)
    p.add_argument("--naive-methods", default=DEFAULT_NAIVE_METHODS)
    p.add_argument("--diagnostic-methods", default=DEFAULT_DIAGNOSTIC_METHODS)
    p.add_argument("--selection-split", default="val")
    p.add_argument("--test-split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--close-rel-threshold", type=float, default=0.05)
    p.add_argument("--severe-aql-warning", type=float, default=1.0)
    p.add_argument("--severe-rel-warning", type=float, default=0.10)
    return p


def parse_csv(value):
    if value is None or str(value).strip() == "":
        return []
    return [x.strip() for x in str(value).split(",") if x.strip()]


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


def read_csv_optional(path):
    if path is None:
        return None
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    return pd.read_csv(path)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def metric_subset(metrics, split, unit, methods=None):
    out = metrics[
        metrics["split"].astype(str).eq(str(split))
        & metrics["unit"].astype(str).eq(str(unit))
    ].copy()
    if methods:
        out = out[out["method_id"].astype(str).isin(set(methods))].copy()
    return out


def best_by_region_fold(metrics, split, unit, metric, methods, prefix):
    sub = metric_subset(metrics, split, unit, methods=methods)
    if sub.empty:
        return pd.DataFrame(columns=["region", "fold"])
    sub[metric] = numeric(sub[metric])
    sub = sub[sub[metric].notna()].copy()
    if sub.empty:
        return pd.DataFrame(columns=["region", "fold"])
    sub = sub.sort_values(["region", "fold", metric, "method_id", "experiment_id"])
    best = sub.groupby(["region", "fold"], as_index=False).first()
    keep = [
        "region", "fold", "method_id", "experiment_id",
        metric, "MAE", "RMSE",
    ]
    keep = [col for col in keep if col in best.columns]
    best = best[keep].copy()
    rename = {
        "method_id": "{}_method_id".format(prefix),
        "experiment_id": "{}_experiment_id".format(prefix),
        metric: "{}_{}".format(prefix, metric),
        "MAE": "{}_MAE".format(prefix),
        "RMSE": "{}_RMSE".format(prefix),
    }
    return best.rename(columns=rename)


def selected_test_metrics(metrics, registry, test_split, unit, metric):
    sub = metric_subset(metrics, test_split, unit)
    keys = ["region", "fold", "experiment_id", "method_id"]
    sub = sub.rename(columns={"method_id": "selected_method_id"})
    keep = [
        "region", "fold", "experiment_id", "selected_method_id",
        metric, "MAE", "RMSE",
    ]
    keep = [col for col in keep if col in sub.columns]
    sub = sub[keep].copy()
    sub = sub.rename(columns={
        metric: "selected_test_{}".format(metric),
        "MAE": "selected_test_MAE",
        "RMSE": "selected_test_RMSE",
    })
    return registry.merge(
        sub,
        on=["region", "fold", "experiment_id", "selected_method_id"],
        how="left",
        validate="one_to_one",
    )


def fold_triage(delta, rel_delta, close_rel_threshold):
    if pd.isna(delta):
        return "missing_naive_comparison"
    if delta < 0.0:
        return "local_beats_naive"
    if pd.notna(rel_delta) and rel_delta <= float(close_rel_threshold):
        return "local_close_to_naive"
    return "local_lags_naive"


def add_previous_context(frame, previous):
    out = frame.copy()
    if previous is None or previous.empty:
        out["already_in_previous_registry"] = False
        return out
    require_columns(previous, ["region", "fold"], "previous registry")
    prev = previous[["region", "fold"]].copy()
    prev["already_in_previous_registry"] = True
    out = out.merge(prev.drop_duplicates(), on=["region", "fold"], how="left")
    out["already_in_previous_registry"] = out["already_in_previous_registry"].fillna(False)
    return out


def build_selection_with_triage(registry, metrics, previous, args):
    require_columns(
        registry,
        [
            "region", "fold", "selected_method_id", "selection_metric_value",
            "experiment_id", "selected_on_split", "selected_on_unit",
            "selection_metric",
        ],
        "median selection registry",
    )
    require_columns(
        metrics,
        ["region", "fold", "method_id", "split", "unit", args.metric],
        "median candidate metrics",
    )
    selected = selected_test_metrics(
        metrics,
        registry,
        args.test_split,
        args.unit,
        args.metric,
    )
    naive = best_by_region_fold(
        metrics,
        args.test_split,
        args.unit,
        args.metric,
        parse_csv(args.naive_methods),
        "best_naive_test",
    )
    selected = selected.merge(naive, on=["region", "fold"], how="left", validate="one_to_one")
    selected["selected_test_{}".format(args.metric)] = numeric(
        selected["selected_test_{}".format(args.metric)]
    )
    selected["best_naive_test_{}".format(args.metric)] = numeric(
        selected["best_naive_test_{}".format(args.metric)]
    )
    selected["test_delta_vs_best_naive"] = (
        selected["selected_test_{}".format(args.metric)]
        - selected["best_naive_test_{}".format(args.metric)]
    )
    denom = selected["best_naive_test_{}".format(args.metric)].abs().clip(lower=1.0e-8)
    selected["test_rel_delta_vs_best_naive"] = selected["test_delta_vs_best_naive"] / denom
    selected["beats_best_naive_test"] = selected["test_delta_vs_best_naive"] < 0.0
    selected["fold_triage"] = [
        fold_triage(delta, rel, args.close_rel_threshold)
        for delta, rel in zip(
            selected["test_delta_vs_best_naive"],
            selected["test_rel_delta_vs_best_naive"],
        )
    ]
    selected["severe_test_warning"] = (
        (selected["test_delta_vs_best_naive"] > float(args.severe_aql_warning))
        | (selected["test_rel_delta_vs_best_naive"] > float(args.severe_rel_warning))
    )
    selected = add_previous_context(selected, previous)
    selected["candidate_source"] = args.candidate_source
    selected["grid_id"] = args.grid_id
    selected["selection_is_validation_only"] = True
    return selected.sort_values(["region", "fold"]).reset_index(drop=True)


def diagnostic_table(metrics, args):
    methods = parse_csv(args.diagnostic_methods)
    if not methods:
        return pd.DataFrame()
    val = best_by_region_fold(
        metrics,
        args.selection_split,
        args.unit,
        args.metric,
        methods,
        "diagnostic_val",
    )
    test = best_by_region_fold(
        metrics,
        args.test_split,
        args.unit,
        args.metric,
        methods,
        "diagnostic_test",
    )
    if val.empty and test.empty:
        return pd.DataFrame()
    out = val.merge(test, on=["region", "fold"], how="outer")
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def region_triage_label(n_folds, n_beats, n_severe):
    if n_folds == 0:
        return "missing"
    if n_beats == n_folds and n_severe == 0:
        return "local_strong"
    if n_beats >= max(1, n_folds - 1) and n_severe == 0:
        return "local_promising"
    if n_beats > 0:
        return "local_mixed_rescue"
    return "local_fail_rescue"


def region_summary(selection, metric="AQL"):
    selected_col = "selected_test_{}".format(metric)
    naive_col = "best_naive_test_{}".format(metric)
    rows = []
    for region, sub in selection.groupby("region"):
        n_folds = int(sub.shape[0])
        n_beats = int(sub["beats_best_naive_test"].fillna(False).sum())
        n_severe = int(sub["severe_test_warning"].fillna(False).sum())
        rows.append({
            "region": region,
            "n_folds": n_folds,
            "n_beats_best_naive_test": n_beats,
            "n_lags_best_naive_test": int(n_folds - n_beats),
            "n_severe_test_warning": n_severe,
            "mean_selection_{}".format(metric): float(numeric(sub["selection_metric_value"]).mean()),
            "mean_selected_test_{}".format(metric): float(numeric(sub[selected_col]).mean()),
            "mean_best_naive_test_{}".format(metric): float(numeric(sub[naive_col]).mean()),
            "mean_test_delta_vs_best_naive": float(numeric(sub["test_delta_vs_best_naive"]).mean()),
            "mean_test_rel_delta_vs_best_naive": float(numeric(sub["test_rel_delta_vs_best_naive"]).mean()),
            "stage_b_triage": region_triage_label(n_folds, n_beats, n_severe),
        })
    return pd.DataFrame(rows).sort_values(["stage_b_triage", "region"]).reset_index(drop=True)


def method_spec_summary(selection):
    cols = [
        "selected_method_id", "experiment_id", "depth", "units",
        "alpha", "rho", "input_scale", "stage_b_region_triage",
    ]
    present = [col for col in cols if col in selection.columns]
    if not present:
        return pd.DataFrame()
    return (
        selection.groupby(present, dropna=False)
        .size()
        .reset_index(name="n")
        .sort_values(["n"] + present, ascending=[False] + [True] * len(present))
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


def markdown_table(frame, columns=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[col for col in columns if col in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[col]) for col in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, selection, regions, diagnostics):
    path = out_dir / "stage_b_closeout_report.md"
    selected_col = "selected_test_{}".format(args.metric)
    naive_col = "best_naive_test_{}".format(args.metric)
    with open(path, "w") as f:
        f.write("# PriceFM Stage-B Median Closeout\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        f.write("Candidate source: `{}`\n\n".format(args.candidate_source))
        f.write(
            "Selection rule: validation `{}` on `{}` scale. Test metrics and "
            "naive comparisons are diagnostics only.\n\n".format(args.metric, args.unit)
        )
        f.write("## Region Triage\n\n")
        f.write(markdown_table(
            regions,
            columns=[
                "region", "n_folds", "n_beats_best_naive_test",
                "mean_selected_test_{}".format(args.metric),
                "mean_best_naive_test_{}".format(args.metric),
                "mean_test_delta_vs_best_naive", "stage_b_triage",
            ],
        ))
        f.write("\n\n## Selected Rows\n\n")
        f.write(markdown_table(
            selection,
            columns=[
                "region", "fold", "selected_method_id", "experiment_id",
                "selection_metric_value", selected_col,
                "best_naive_test_method_id", naive_col,
                "test_delta_vs_best_naive", "fold_triage",
                "stage_b_region_triage",
            ],
        ))
        if diagnostics is not None and not diagnostics.empty:
            f.write("\n\n## Normal-DESN Diagnostic Winners\n\n")
            f.write(markdown_table(diagnostics.head(48)))
        f.write("\n\n## Notes\n\n")
        f.write("- This is an append-style closeout for new regions.\n")
        f.write("- It does not overwrite the existing six-region authoritative registry.\n")
        f.write("- Fold-aligned PriceFM comparison is still required before claims against PriceFM.\n")
        f.write("- Regions labeled `local_fail_rescue` should not be promoted to paper quantiles without rescue.\n")
    return path


def closeout(args):
    registry_dir = repo_path(args.registry_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    registry = read_csv_required(registry_dir / "median_selection_registry.csv", "median registry")
    metrics = read_csv_required(registry_dir / "median_candidate_metrics.csv", "candidate metrics")
    previous = read_csv_optional(args.previous_registry_csv)
    selection = build_selection_with_triage(registry, metrics, previous, args)
    regions = region_summary(selection, args.metric)
    region_label = regions[["region", "stage_b_triage"]].rename(
        columns={"stage_b_triage": "stage_b_region_triage"}
    )
    selection = selection.merge(region_label, on="region", how="left", validate="many_to_one")
    diagnostics = diagnostic_table(metrics, args)
    specs = method_spec_summary(selection)

    selection.to_csv(out_dir / "stage_b_selection_registry_with_triage.csv", index=False)
    regions.to_csv(out_dir / "stage_b_region_summary.csv", index=False)
    specs.to_csv(out_dir / "stage_b_method_spec_summary.csv", index=False)
    if diagnostics is not None and not diagnostics.empty:
        diagnostics.to_csv(out_dir / "stage_b_normal_diagnostic.csv", index=False)
    report = write_report(out_dir, args, selection, regions, diagnostics)

    summary = {
        "grid_id": args.grid_id,
        "candidate_source": args.candidate_source,
        "registry_dir": config_path_value(registry_dir),
        "output_dir": config_path_value(out_dir),
        "previous_registry_csv": (
            config_path_value(args.previous_registry_csv)
            if args.previous_registry_csv else None
        ),
        "n_region_folds": int(selection.shape[0]),
        "n_regions": int(regions.shape[0]),
        "n_beats_best_naive_test": int(selection["beats_best_naive_test"].fillna(False).sum()),
        "mean_selected_test_{}".format(args.metric): float(
            selection["selected_test_{}".format(args.metric)].mean()
        ),
        "mean_best_naive_test_{}".format(args.metric): float(
            selection["best_naive_test_{}".format(args.metric)].mean()
        ),
        "region_triage_counts": regions["stage_b_triage"].value_counts().sort_index().to_dict(),
        "outputs": {
            "selection_registry_with_triage": config_path_value(out_dir / "stage_b_selection_registry_with_triage.csv"),
            "region_summary": config_path_value(out_dir / "stage_b_region_summary.csv"),
            "method_spec_summary": config_path_value(out_dir / "stage_b_method_spec_summary.csv"),
            "normal_diagnostic": (
                config_path_value(out_dir / "stage_b_normal_diagnostic.csv")
                if diagnostics is not None and not diagnostics.empty else None
            ),
            "report": config_path_value(report),
        },
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = closeout(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
