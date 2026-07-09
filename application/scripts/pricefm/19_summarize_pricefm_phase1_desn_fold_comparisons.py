#!/usr/bin/env python3
"""Aggregate local PriceFM Phase-I vs DESN/Q-DESN fold comparisons."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_TEMPLATE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_fold{fold}_20260602"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_folds123_20260602"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--folds", default="1,2,3")
    p.add_argument("--comparison-dir-template", default=DEFAULT_TEMPLATE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--baseline-method", default="pricefm_phase1_pretraining")
    return p


def parse_folds(value):
    folds = [int(x.strip()) for x in str(value).split(",") if x.strip()]
    if not folds:
        raise ValueError("At least one fold is required.")
    return folds


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} is missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def comparison_dir(template, fold):
    return repo_path(str(template).format(fold=int(fold)))


def collect_fold_outputs(template, folds):
    metric_rows = []
    row_audit_rows = []
    sources = []
    for fold in folds:
        comp_dir = comparison_dir(template, fold)
        metric = read_csv_required(comp_dir / "pricefm_vs_desn_metric_summary.csv", "fold {}".format(fold))
        metric = metric[metric["unit"].astype(str).eq("original")].copy()
        if metric.empty:
            raise ValueError("fold {} has no original-scale metric rows".format(fold))
        metric.insert(0, "fold", int(fold))
        metric.insert(1, "comparison_dir", str(comp_dir))
        metric_rows.append(metric)

        row_audit = read_csv_required(
            comp_dir / "pricefm_vs_desn_row_alignment_audit.csv",
            "fold {}".format(fold),
        )
        row_audit.insert(0, "fold", int(fold))
        row_audit.insert(1, "comparison_dir", str(comp_dir))
        row_audit_rows.append(row_audit)
        sources.append({"fold": int(fold), "comparison_dir": str(comp_dir)})
    return pd.concat(metric_rows, ignore_index=True), pd.concat(row_audit_rows, ignore_index=True), sources


def macro_metrics(fold_metric):
    metrics = [c for c in ["AQL", "AQCR", "MAE", "RMSE"] if c in fold_metric.columns]
    grouped = fold_metric.groupby("method_id", as_index=False)[metrics].agg(["mean", "std", "min", "max"])
    grouped.columns = [
        "{}_{}".format(metric, stat) if stat else metric
        for metric, stat in grouped.columns.to_flat_index()
    ]
    return grouped.sort_values(["AQL_mean", "method_id"]).reset_index(drop=True)


def fold_winners(fold_metric):
    rows = []
    for fold, df in fold_metric.groupby("fold"):
        best = df.sort_values(["AQL", "method_id"]).iloc[0]
        rows.append({
            "fold": int(fold),
            "best_method_id": best["method_id"],
            "best_AQL": float(best["AQL"]),
            "best_MAE": float(best["MAE"]),
            "best_RMSE": float(best["RMSE"]),
        })
    return pd.DataFrame(rows).sort_values("fold")


def deltas_vs_baseline(fold_metric, baseline_method):
    rows = []
    for fold, df in fold_metric.groupby("fold"):
        base = df[df["method_id"].eq(baseline_method)]
        if base.empty:
            raise ValueError("fold {} is missing baseline method {}".format(fold, baseline_method))
        base = base.iloc[0]
        for _, row in df.iterrows():
            out = {
                "fold": int(fold),
                "method_id": row["method_id"],
                "baseline_method_id": baseline_method,
            }
            for metric in ["AQL", "MAE", "RMSE"]:
                out[metric] = float(row[metric])
                out["baseline_{}".format(metric)] = float(base[metric])
                out["delta_{}".format(metric)] = float(row[metric] - base[metric])
                out["ratio_{}".format(metric)] = float(row[metric] / base[metric]) if float(base[metric]) != 0.0 else float("nan")
            rows.append(out)
    return pd.DataFrame(rows).sort_values(["fold", "delta_AQL", "method_id"])


def plot_aql_by_fold(fold_metric, delta, out_dir, baseline_method):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []

    methods = list(fold_metric.sort_values(["method_id"])["method_id"].unique())
    folds = sorted(int(x) for x in fold_metric["fold"].unique())
    width = 0.8 / max(len(methods), 1)
    x = range(len(folds))
    fig, ax = plt.subplots(figsize=(13, 6))
    for i, method_id in enumerate(methods):
        vals = []
        for fold in folds:
            sub = fold_metric[(fold_metric["fold"].eq(fold)) & (fold_metric["method_id"].eq(method_id))]
            vals.append(float(sub["AQL"].iloc[0]) if not sub.empty else float("nan"))
        offsets = [xx - 0.4 + width / 2 + i * width for xx in x]
        ax.bar(offsets, vals, width=width, label=method_id)
    ax.set_xticks(list(x))
    ax.set_xticklabels(["fold {}".format(f) for f in folds])
    ax.set_ylabel("AQL, original scale")
    ax.set_title("PriceFM Phase-I vs DESN/Q-DESN AQL By Fold")
    ax.grid(axis="y", alpha=0.22)
    ax.legend(fontsize=8, ncol=2)
    fig.tight_layout()
    path = fig_dir / "aql_by_fold_method.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    non_baseline = delta[~delta["method_id"].eq(baseline_method)].copy()
    fig, ax = plt.subplots(figsize=(13, 6))
    for method_id, sub in non_baseline.groupby("method_id"):
        sub = sub.sort_values("fold")
        ax.plot(sub["fold"], sub["delta_AQL"], marker="o", linewidth=1.4, label=method_id)
    ax.axhline(0.0, color="black", linewidth=1.0)
    ax.set_xlabel("Fold")
    ax.set_ylabel("AQL minus {}".format(baseline_method))
    ax.set_title("Original-Scale AQL Delta Versus Local PriceFM Phase-I")
    ax.grid(alpha=0.22)
    ax.legend(fontsize=8)
    fig.tight_layout()
    path = fig_dir / "aql_delta_vs_pricefm_by_fold.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))
    return made


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, columns].copy()
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        values = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                values.append(("{:." + str(int(float_digits)) + "f}").format(value))
            else:
                values.append(str(value))
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def write_report(out_dir, region, folds, fold_metric, macro, winners, delta, row_audit, figures, baseline_method):
    with open(out_dir / "pricefm_vs_desn_fold_robustness_report.md", "w") as f:
        f.write("# PriceFM Phase-I vs DESN/Q-DESN {} Fold Robustness Summary\n\n".format(region))
        f.write("Folds: `{}`\n\n".format(",".join(str(x) for x in folds)))
        f.write("Baseline method: `{}`\n\n".format(baseline_method))
        f.write("## Fold Winners By AQL\n\n")
        f.write(markdown_table(winners))
        f.write("\n\n## Macro Metrics, Original Scale\n\n")
        f.write(markdown_table(
            macro,
            columns=["method_id", "AQL_mean", "AQL_std", "MAE_mean", "RMSE_mean"],
        ))
        f.write("\n\n## Fold Metrics, Original Scale\n\n")
        f.write(markdown_table(
            fold_metric.sort_values(["fold", "AQL", "method_id"]),
            columns=["fold", "method_id", "AQL", "AQCR", "MAE", "RMSE"],
        ))
        f.write("\n\n## Delta Versus Local PriceFM Phase-I\n\n")
        f.write(markdown_table(
            delta.sort_values(["fold", "delta_AQL", "method_id"]),
            columns=["fold", "method_id", "delta_AQL", "ratio_AQL", "delta_MAE", "delta_RMSE"],
        ))
        f.write("\n\n## Row Alignment Audit\n\n")
        audit_cols = [
            c for c in [
                "fold", "method_id", "available_prediction_rows",
                "available_unique_response_rows", "aligned_prediction_rows",
                "aligned_unique_response_rows",
            ] if c in row_audit.columns
        ]
        f.write(markdown_table(row_audit.sort_values(["fold", "method_id"]), columns=audit_cols))
        f.write("\n\n## Figures\n\n")
        for fig in figures:
            f.write("- `{}`\n".format(fig))


def main():
    args = parser().parse_args()
    folds = parse_folds(args.folds)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    fold_metric, row_audit, sources = collect_fold_outputs(args.comparison_dir_template, folds)
    macro = macro_metrics(fold_metric)
    winners = fold_winners(fold_metric)
    delta = deltas_vs_baseline(fold_metric, args.baseline_method)
    figures = plot_aql_by_fold(fold_metric, delta, out_dir, args.baseline_method)

    fold_metric.to_csv(out_dir / "fold_metric_summary.csv", index=False)
    macro.to_csv(out_dir / "macro_metric_summary.csv", index=False)
    winners.to_csv(out_dir / "fold_winners.csv", index=False)
    delta.to_csv(out_dir / "method_delta_vs_pricefm.csv", index=False)
    row_audit.to_csv(out_dir / "fold_row_alignment_audit.csv", index=False)
    write_report(out_dir, args.region, folds, fold_metric, macro, winners, delta, row_audit, figures, args.baseline_method)
    payload = {
        "region": args.region,
        "folds": folds,
        "baseline_method": args.baseline_method,
        "comparison_sources": sources,
        "outputs": {
            "fold_metric_summary": str(out_dir / "fold_metric_summary.csv"),
            "macro_metric_summary": str(out_dir / "macro_metric_summary.csv"),
            "fold_winners": str(out_dir / "fold_winners.csv"),
            "method_delta_vs_pricefm": str(out_dir / "method_delta_vs_pricefm.csv"),
            "row_alignment": str(out_dir / "fold_row_alignment_audit.csv"),
            "report": str(out_dir / "pricefm_vs_desn_fold_robustness_report.md"),
            "figures": figures,
        },
    }
    write_json(out_dir / "summary.json", payload)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
