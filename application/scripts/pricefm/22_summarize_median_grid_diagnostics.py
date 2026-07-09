#!/usr/bin/env python3
"""Summarize PriceFM fold-2/3 median grid diagnostics without refitting models."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_NEW_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_deep_targeted_registry_20260603"
)
DEFAULT_PREVIOUS_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_selection_registry_20260602"
)
DEFAULT_PRICEFM_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_folds123_20260602/fold_metric_summary.csv"
)
DEFAULT_PRICEFM_FOLD_TEMPLATE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_fold{fold}_20260602"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_deep_targeted_diagnostics_20260603"
)
DEFAULT_SELECTION_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--new-registry-dir", default=DEFAULT_NEW_REGISTRY)
    p.add_argument("--previous-registry-dir", default=DEFAULT_PREVIOUS_REGISTRY)
    p.add_argument("--pricefm-summary", default=DEFAULT_PRICEFM_SUMMARY)
    p.add_argument("--pricefm-fold-template", default=DEFAULT_PRICEFM_FOLD_TEMPLATE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--selection-methods", default=DEFAULT_SELECTION_METHODS)
    p.add_argument("--top-n", type=int, default=15)
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def rel_path(path):
    path = repo_path(path)
    try:
        return str(path.relative_to(repo_path(".")))
    except ValueError:
        return str(path)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} is missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def read_csv_optional(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    return pd.read_csv(path)


def registry_csv(registry_dir):
    return repo_path(registry_dir) / "median_selection_registry.csv"


def rankings_csv(registry_dir):
    return repo_path(registry_dir) / "median_candidate_rankings.csv"


def metrics_csv(registry_dir):
    return repo_path(registry_dir) / "median_candidate_metrics.csv"


def completion_csv(registry_dir):
    return repo_path(registry_dir) / "median_candidate_completion.csv"


def clean_duplicate_suffix_columns(frame):
    drop_cols = [c for c in frame.columns if c.endswith(".1")]
    if drop_cols:
        frame = frame.drop(columns=drop_cols)
    return frame


def original_registry_frame(registry_dir, source_label, region, folds):
    frame = read_csv_required(registry_csv(registry_dir), "{} registry".format(source_label))
    frame = frame[
        frame["region"].astype(str).eq(str(region))
        & frame["fold"].astype(int).isin(folds)
    ].copy()
    if frame.empty:
        raise ValueError("{} registry has no rows for region {} folds {}".format(
            source_label, region, folds
        ))
    frame.insert(0, "registry_source", source_label)
    return frame.sort_values(["region", "fold"]).reset_index(drop=True)


def selected_metric(row, prefix):
    col = "{}_AQL".format(prefix)
    if col in row and pd.notna(row[col]):
        return float(row[col])
    if prefix == "selection" and "selection_metric_value" in row:
        return float(row["selection_metric_value"])
    return float("nan")


def selected_spec_columns(prefix, row):
    fields = [
        "experiment_id", "selected_method_id", "lag_window", "feature_dim",
        "depth", "units", "alpha", "rho", "input_scale", "tau0", "seed",
        "stage", "priority", "model_dir", "run_dir",
    ]
    out = {}
    for field in fields:
        if field in row:
            out["{}_{}".format(prefix, field)] = row[field]
    out["{}_val_AQL".format(prefix)] = selected_metric(row, "selection")
    out["{}_test_AQL".format(prefix)] = selected_metric(row, "test")
    if "test_MAE" in row:
        out["{}_test_MAE".format(prefix)] = row["test_MAE"]
    if "test_RMSE" in row:
        out["{}_test_RMSE".format(prefix)] = row["test_RMSE"]
    return out


def selection_delta_summary(previous, new):
    rows = []
    for _, new_row in new.iterrows():
        fold = int(new_row["fold"])
        region = str(new_row["region"])
        prev_sub = previous[
            previous["region"].astype(str).eq(region)
            & previous["fold"].astype(int).eq(fold)
        ]
        if prev_sub.empty:
            continue
        prev_row = prev_sub.iloc[0]
        out = {"region": region, "fold": fold}
        out.update(selected_spec_columns("previous", prev_row))
        out.update(selected_spec_columns("new", new_row))
        out["delta_val_AQL_new_minus_previous"] = (
            out["new_val_AQL"] - out["previous_val_AQL"]
        )
        out["delta_test_AQL_new_minus_previous"] = (
            out["new_test_AQL"] - out["previous_test_AQL"]
        )
        if out["delta_val_AQL_new_minus_previous"] < 0:
            out["decision"] = "promote_new_on_validation"
            out["retained_experiment_id"] = out.get("new_experiment_id")
        else:
            out["decision"] = "retain_previous_authoritative"
            out["retained_experiment_id"] = out.get("previous_experiment_id")
        rows.append(out)
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def top_candidates(registry_dir, region, folds, top_n):
    rankings = read_csv_required(rankings_csv(registry_dir), "new registry rankings")
    rankings = clean_duplicate_suffix_columns(rankings)
    rankings = rankings[
        rankings["region"].astype(str).eq(str(region))
        & rankings["fold"].astype(int).isin(folds)
    ].copy()
    if rankings.empty:
        return rankings
    rankings["AQL"] = pd.to_numeric(rankings["AQL"], errors="coerce")
    rankings["rank"] = pd.to_numeric(rankings["rank"], errors="coerce")
    rankings = rankings[rankings["AQL"].notna()].copy()
    best = rankings.groupby(["region", "fold"])["AQL"].transform("min")
    rankings["delta_AQL_from_fold_best"] = rankings["AQL"] - best
    cols = [
        "region", "fold", "rank", "experiment_id", "method_id", "AQL",
        "delta_AQL_from_fold_best", "MAE", "RMSE", "stage", "priority",
        "lag_window", "feature_dim", "depth", "units", "alpha", "rho",
        "input_scale", "tau0", "seed", "run_dir",
    ]
    rankings = rankings.sort_values(["region", "fold", "rank", "method_id"])
    return rankings.groupby(["region", "fold"]).head(top_n)[
        [c for c in cols if c in rankings.columns]
    ].reset_index(drop=True)


def completion_summary(registry_dir, region, folds):
    comp = read_csv_required(completion_csv(registry_dir), "new completion summary")
    comp = comp[
        comp["region"].astype(str).eq(str(region))
        & comp["fold"].astype(int).isin(folds)
    ].copy()
    if comp.empty:
        return comp
    out = comp.groupby(["priority"], as_index=False).agg(
        n_cells=("completed", "size"),
        n_completed=("completed", "sum"),
    )
    out["all_completed"] = out["n_cells"].eq(out["n_completed"])
    return out


def pattern_summary(registry_dir, region, folds, selection_methods):
    metrics = read_csv_required(metrics_csv(registry_dir), "new candidate metrics")
    metrics = metrics[
        metrics["region"].astype(str).eq(str(region))
        & metrics["fold"].astype(int).isin(folds)
        & metrics["split"].astype(str).eq("val")
        & metrics["unit"].astype(str).eq("original")
    ].copy()
    if selection_methods:
        metrics = metrics[metrics["method_id"].astype(str).isin(selection_methods)].copy()
    metrics["AQL"] = pd.to_numeric(metrics["AQL"], errors="coerce")
    metrics = metrics[metrics["AQL"].notna()].copy()
    rows = []
    pattern_cols = [
        "stage", "lag_window", "feature_dim", "depth", "alpha", "rho",
        "input_scale", "tau0",
    ]
    for col in pattern_cols:
        if col not in metrics.columns:
            continue
        for (fold, value), sub in metrics.groupby(["fold", col], dropna=False):
            sub = sub.sort_values(["AQL", "method_id", "experiment_id"])
            best = sub.iloc[0]
            rows.append({
                "fold": int(fold),
                "pattern_type": col,
                "pattern_value": str(value),
                "n_metric_rows": int(len(sub)),
                "n_experiments": int(sub["experiment_id"].nunique()),
                "best_AQL": float(best["AQL"]),
                "median_AQL": float(sub["AQL"].median()),
                "best_experiment_id": best["experiment_id"],
                "best_method_id": best["method_id"],
                "best_stage": best.get("stage", ""),
                "best_lag_window": best.get("lag_window", ""),
                "best_feature_dim": best.get("feature_dim", ""),
                "best_alpha": best.get("alpha", ""),
                "best_rho": best.get("rho", ""),
                "best_input_scale": best.get("input_scale", ""),
            })
    return pd.DataFrame(rows).sort_values(
        ["fold", "pattern_type", "best_AQL"]
    ).reset_index(drop=True)


def load_selected_horizon_groups(registry, source_label):
    rows = []
    for _, row in registry.iterrows():
        path = repo_path(row["model_dir"]) / "metric_by_horizon_group.csv"
        metrics = read_csv_optional(path)
        if metrics is None:
            rows.append({
                "source": source_label,
                "region": row["region"],
                "fold": int(row["fold"]),
                "experiment_id": row["experiment_id"],
                "method_id": row["selected_method_id"],
                "horizon_group": "missing",
                "metric_path": rel_path(path),
            })
            continue
        metrics = metrics[
            metrics["method_id"].astype(str).eq(str(row["selected_method_id"]))
            & metrics["split"].astype(str).eq("test")
            & metrics["unit"].astype(str).eq("original")
        ].copy()
        for key, value in {
            "source": source_label,
            "region": row["region"],
            "fold": int(row["fold"]),
            "experiment_id": row["experiment_id"],
            "metric_path": rel_path(path),
        }.items():
            metrics.insert(0, key, value)
        rows.append(metrics)
    return pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()


def horizon_delta_summary(horizon):
    if horizon.empty:
        return horizon
    keep_sources = {
        "previous_authoritative_median",
        "new_deep_targeted_median",
    }
    frame = horizon[horizon["source"].isin(keep_sources)].copy()
    if frame.empty:
        return frame
    values = ["AQL", "MAE", "RMSE"]
    pivots = []
    for metric in values:
        if metric not in frame.columns:
            continue
        sub = frame.pivot_table(
            index=["region", "fold", "horizon_group"],
            columns="source",
            values=metric,
            aggfunc="first",
        ).reset_index()
        sub.columns.name = None
        sub.insert(3, "metric", metric)
        old = "previous_authoritative_median"
        new = "new_deep_targeted_median"
        if old in sub.columns and new in sub.columns:
            sub["new_minus_previous"] = sub[new] - sub[old]
        pivots.append(sub)
    return pd.concat(pivots, ignore_index=True) if pivots else pd.DataFrame()


def pricefm_reference_summary(summary_path, region, folds):
    frame = read_csv_required(summary_path, "PriceFM fold comparison summary")
    frame = frame[
        frame["fold"].astype(int).isin(folds)
        & frame["split"].astype(str).eq("test")
        & frame["unit"].astype(str).eq("original")
    ].copy()
    if frame.empty:
        return frame
    wanted = {
        "pricefm_phase1_pretraining",
        "qdesn_exal_rhs_ns_exact_chunked",
        "qdesn_al_rhs_ns_exact_chunked",
        "normal_rhs_ns",
    }
    frame = frame[frame["method_id"].astype(str).isin(wanted)].copy()
    frame.insert(0, "region", region)
    return frame.sort_values(["fold", "AQL", "method_id"]).reset_index(drop=True)


def pricefm_reference_horizon(template, region, folds):
    rows = []
    wanted = {
        "pricefm_phase1_pretraining",
        "qdesn_exal_rhs_ns_exact_chunked",
        "qdesn_al_rhs_ns_exact_chunked",
    }
    for fold in folds:
        path = repo_path(str(template).format(fold=int(fold))) / "pricefm_vs_desn_metric_by_horizon_group.csv"
        frame = read_csv_optional(path)
        if frame is None:
            continue
        frame = frame[
            frame["method_id"].astype(str).isin(wanted)
            & frame["split"].astype(str).eq("test")
            & frame["unit"].astype(str).eq("original")
        ].copy()
        frame.insert(0, "source", "seven_quantile_phase1_reference")
        frame.insert(1, "region", region)
        frame.insert(2, "fold", int(fold))
        frame.insert(3, "experiment_id", "phase1_vs_desn_fold{}".format(int(fold)))
        frame.insert(4, "metric_path", rel_path(path))
        rows.append(frame)
    return pd.concat(rows, ignore_index=True) if rows else pd.DataFrame()


def make_figures(out_dir, selection_delta, horizon_delta, reference_summary):
    figures = []
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover - environment dependent
        return ["figures skipped: matplotlib unavailable ({})".format(exc)]

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)

    if not selection_delta.empty:
        fig, ax = plt.subplots(figsize=(10, 5))
        x = range(len(selection_delta))
        width = 0.22
        labels = [
            "{} fold {}".format(row["region"], int(row["fold"]))
            for _, row in selection_delta.iterrows()
        ]
        series = [
            ("previous val", "previous_val_AQL", -1.5 * width),
            ("new val", "new_val_AQL", -0.5 * width),
            ("previous test", "previous_test_AQL", 0.5 * width),
            ("new test", "new_test_AQL", 1.5 * width),
        ]
        for label, col, offset in series:
            ax.bar([i + offset for i in x], selection_delta[col], width=width, label=label)
        ax.set_xticks(list(x))
        ax.set_xticklabels(labels)
        ax.set_ylabel("AQL, original scale")
        ax.set_title("Deep Targeted Median Grid Versus Previous Registry")
        ax.grid(axis="y", alpha=0.22)
        ax.legend(fontsize=8, ncol=2)
        fig.tight_layout()
        path = fig_dir / "median_registry_new_vs_previous_aql.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))

    if not horizon_delta.empty and "AQL" in set(horizon_delta["metric"].astype(str)):
        aql = horizon_delta[horizon_delta["metric"].astype(str).eq("AQL")].copy()
        fig, ax = plt.subplots(figsize=(11, 5.5))
        for fold, sub in aql.groupby("fold"):
            sub = sub.sort_values("horizon_group")
            ax.plot(
                sub["horizon_group"],
                sub["new_minus_previous"],
                marker="o",
                linewidth=1.4,
                label="fold {}".format(int(fold)),
            )
        ax.axhline(0.0, color="black", linewidth=1.0)
        ax.set_xlabel("Horizon group")
        ax.set_ylabel("New median AQL minus previous median AQL")
        ax.set_title("Selected Median Horizon-Group Delta")
        ax.grid(alpha=0.22)
        ax.legend()
        fig.tight_layout()
        path = fig_dir / "median_horizon_group_delta_aql.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))

    if not reference_summary.empty:
        fig, ax = plt.subplots(figsize=(11, 5.5))
        methods = list(reference_summary.sort_values("method_id")["method_id"].unique())
        folds = sorted(int(x) for x in reference_summary["fold"].unique())
        width = 0.8 / max(len(methods), 1)
        for i, method_id in enumerate(methods):
            values = []
            for fold in folds:
                sub = reference_summary[
                    reference_summary["fold"].astype(int).eq(fold)
                    & reference_summary["method_id"].astype(str).eq(str(method_id))
                ]
                values.append(float(sub["AQL"].iloc[0]) if not sub.empty else float("nan"))
            ax.bar([j - 0.4 + width / 2 + i * width for j in range(len(folds))],
                   values, width=width, label=method_id)
        ax.set_xticks(list(range(len(folds))))
        ax.set_xticklabels(["fold {}".format(f) for f in folds])
        ax.set_ylabel("AQL, original scale")
        ax.set_title("Seven-Quantile PriceFM Context")
        ax.grid(axis="y", alpha=0.22)
        ax.legend(fontsize=8)
        fig.tight_layout()
        path = fig_dir / "seven_quantile_phase1_context_aql.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        figures.append(rel_path(path))

    return figures


def md_value(value, digits=6):
    if isinstance(value, float):
        text = ("{:." + str(int(digits)) + "f}").format(value)
    else:
        text = str(value)
    return text.replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    lines = [
        "| " + " | ".join(frame.columns) + " |",
        "| " + " | ".join(["---"] * len(frame.columns)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(
            md_value(row[col], digits=float_digits) for col in frame.columns
        ) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, completion, selection_delta, top, patterns,
                 horizon_delta, reference_summary, figures):
    report = out_dir / "median_grid_diagnostics_report.md"
    with open(report, "w") as f:
        f.write("# PriceFM DE_LU Fold 2/3 Median Deep-Grid Diagnostics\n\n")
        f.write("Region: `{}`  \n".format(args.region))
        f.write("Folds: `{}`  \n".format(args.folds))
        f.write("New registry: `{}`  \n".format(rel_path(args.new_registry_dir)))
        f.write("Previous registry: `{}`\n\n".format(rel_path(args.previous_registry_dir)))
        f.write("## Completion\n\n")
        f.write(markdown_table(completion))
        f.write("\n\n## Decision Table\n\n")
        f.write(markdown_table(
            selection_delta,
            columns=[
                "region", "fold", "previous_experiment_id", "previous_val_AQL",
                "previous_test_AQL", "new_experiment_id", "new_val_AQL",
                "new_test_AQL", "delta_val_AQL_new_minus_previous",
                "delta_test_AQL_new_minus_previous", "decision",
            ],
        ))
        f.write("\n\n## Top New Candidates\n\n")
        f.write(markdown_table(
            top.groupby(["region", "fold"]).head(10),
            columns=[
                "region", "fold", "rank", "experiment_id", "method_id", "AQL",
                "delta_AQL_from_fold_best", "MAE", "RMSE", "stage",
                "lag_window", "feature_dim", "alpha", "rho", "input_scale",
            ],
        ))
        f.write("\n\n## Pattern Summary\n\n")
        f.write(markdown_table(
            patterns.groupby(["fold", "pattern_type"]).head(3),
            columns=[
                "fold", "pattern_type", "pattern_value", "n_experiments",
                "best_AQL", "median_AQL", "best_experiment_id",
                "best_method_id",
            ],
        ))
        f.write("\n\n## Horizon-Group Delta\n\n")
        f.write(markdown_table(
            horizon_delta[horizon_delta["metric"].astype(str).eq("AQL")]
            if not horizon_delta.empty and "metric" in horizon_delta.columns else horizon_delta,
            columns=[
                "region", "fold", "horizon_group", "metric",
                "previous_authoritative_median", "new_deep_targeted_median",
                "new_minus_previous",
            ],
        ))
        f.write("\n\n## Seven-Quantile PriceFM Context\n\n")
        f.write("This table is context from the previous seven-quantile comparison, not a median-only registry selector.\n\n")
        f.write(markdown_table(
            reference_summary,
            columns=["region", "fold", "method_id", "AQL", "MAE", "RMSE"],
        ))
        f.write("\n\n## Figures\n\n")
        for fig in figures:
            f.write("- `{}`\n".format(fig))
        f.write("\n\n## Interpretation\n\n")
        f.write("- The deep grid completed, but its validation-selected median specs are worse than the previous promoted fold-specific registry on both folds.\n")
        f.write("- The previous registry should remain authoritative for fold 2 and fold 3 median Q-DESN runs.\n")
        f.write("- The new grid is still useful diagnostically: it shows local input-scale/rho neighborhoods but does not support another blind reservoir expansion.\n")
        f.write("- The next productive work is feature-geometry diagnostics, horizon-specific features, or a small P2 diagnostic such as direct flat/window features, not a broader alpha/rho/n search.\n")
    return report


def main():
    args = parser().parse_args()
    folds = parse_csv(args.folds, int)
    selection_methods = parse_csv(args.selection_methods, str)
    if not folds:
        raise ValueError("At least one fold is required.")

    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    previous = original_registry_frame(
        args.previous_registry_dir, "previous_authoritative_median", args.region, folds
    )
    new = original_registry_frame(
        args.new_registry_dir, "new_deep_targeted_median", args.region, folds
    )
    completion = completion_summary(args.new_registry_dir, args.region, folds)
    delta = selection_delta_summary(previous, new)
    top = top_candidates(args.new_registry_dir, args.region, folds, args.top_n)
    patterns = pattern_summary(args.new_registry_dir, args.region, folds, selection_methods)

    horizon = pd.concat([
        load_selected_horizon_groups(previous, "previous_authoritative_median"),
        load_selected_horizon_groups(new, "new_deep_targeted_median"),
        pricefm_reference_horizon(args.pricefm_fold_template, args.region, folds),
    ], ignore_index=True)
    horizon_delta = horizon_delta_summary(horizon)
    reference_summary = pricefm_reference_summary(args.pricefm_summary, args.region, folds)
    figures = make_figures(out_dir, delta, horizon_delta, reference_summary)

    completion.to_csv(out_dir / "completion_summary.csv", index=False)
    delta.to_csv(out_dir / "selection_delta_summary.csv", index=False)
    top.to_csv(out_dir / "top_candidates_compact.csv", index=False)
    patterns.to_csv(out_dir / "stage_pattern_summary.csv", index=False)
    horizon.to_csv(out_dir / "horizon_group_diagnostics.csv", index=False)
    horizon_delta.to_csv(out_dir / "horizon_group_delta_summary.csv", index=False)
    reference_summary.to_csv(out_dir / "seven_quantile_pricefm_context.csv", index=False)
    report = write_report(
        out_dir, args, completion, delta, top, patterns,
        horizon_delta, reference_summary, figures,
    )
    payload = {
        "region": args.region,
        "folds": folds,
        "new_registry_dir": rel_path(args.new_registry_dir),
        "previous_registry_dir": rel_path(args.previous_registry_dir),
        "pricefm_summary": rel_path(args.pricefm_summary),
        "outputs": {
            "completion_summary": rel_path(out_dir / "completion_summary.csv"),
            "selection_delta_summary": rel_path(out_dir / "selection_delta_summary.csv"),
            "top_candidates_compact": rel_path(out_dir / "top_candidates_compact.csv"),
            "stage_pattern_summary": rel_path(out_dir / "stage_pattern_summary.csv"),
            "horizon_group_diagnostics": rel_path(out_dir / "horizon_group_diagnostics.csv"),
            "horizon_group_delta_summary": rel_path(out_dir / "horizon_group_delta_summary.csv"),
            "seven_quantile_pricefm_context": rel_path(out_dir / "seven_quantile_pricefm_context.csv"),
            "report": rel_path(report),
            "figures": figures,
        },
    }
    write_json(out_dir / "summary.json", payload)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
