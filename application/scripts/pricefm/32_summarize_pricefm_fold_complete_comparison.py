#!/usr/bin/env python3
"""Summarize a fold-complete PriceFM Phase-I vs DESN/Q-DESN comparison.

Unlike script 19, this accepts an explicit fold-to-comparison-directory map.
That lets the authoritative fold-1 run and the improved folds-2/3 follow-up
runs live in their natural output locations while still producing one clean
fold-complete report.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import repo_path, write_json


DEFAULT_FOLD_DIRS = (
    "1:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold1_20260602,"
    "2:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold2_followup_20260605,"
    "3:application/data_local/pricefm/authoritative/pricefm_phase1_vs_desn_de_lu_fold3_followup_20260605"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_folds123_followup_authoritative_20260606"
)
DEFAULT_FOLD1_GRID = (
    "application/config/pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml"
)
DEFAULT_FOLDS23_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_followup_registry_20260605/model_selection_winners.csv"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--fold-comparison-dirs", default=DEFAULT_FOLD_DIRS)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--baseline-method", default="pricefm_phase1_pretraining")
    p.add_argument("--fold1-grid-config", default=DEFAULT_FOLD1_GRID)
    p.add_argument("--folds23-registry", default=DEFAULT_FOLDS23_REGISTRY)
    return p


def parse_fold_dirs(value):
    out = []
    for item in str(value).split(","):
        text = item.strip()
        if not text:
            continue
        if ":" not in text:
            raise ValueError("Fold comparison mapping must use fold:path entries.")
        fold, path = text.split(":", 1)
        out.append((int(fold), repo_path(path)))
    if not out:
        raise ValueError("At least one fold comparison directory is required.")
    folds = [fold for fold, _ in out]
    if len(folds) != len(set(folds)):
        raise ValueError("Duplicate folds in comparison directory mapping.")
    return sorted(out, key=lambda x: x[0])


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
        raise FileNotFoundError("{} is missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def read_json_if_exists(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with open(path, "r") as f:
        return json.load(f)


def collect_fold_outputs(fold_dirs):
    metric_parts = []
    horizon_parts = []
    horizon_group_parts = []
    row_audit_parts = []
    sources = []
    for fold, comp_dir in fold_dirs:
        context = "fold {}".format(int(fold))
        metric = read_csv_required(comp_dir / "pricefm_vs_desn_metric_summary.csv", context)
        metric = metric[
            metric["split"].astype(str).eq("test")
            & metric["unit"].astype(str).eq("original")
        ].copy()
        if metric.empty:
            raise ValueError("{} has no test/original metric rows.".format(context))
        metric.insert(0, "fold", int(fold))
        metric.insert(1, "comparison_dir", config_path_value(comp_dir))
        metric_parts.append(metric)

        horizon = read_csv_required(comp_dir / "pricefm_vs_desn_metric_by_horizon.csv", context)
        horizon = horizon[
            horizon["split"].astype(str).eq("test")
            & horizon["unit"].astype(str).eq("original")
        ].copy()
        horizon.insert(0, "fold", int(fold))
        horizon.insert(1, "comparison_dir", config_path_value(comp_dir))
        horizon_parts.append(horizon)

        group = read_csv_required(comp_dir / "pricefm_vs_desn_metric_by_horizon_group.csv", context)
        group = group[
            group["split"].astype(str).eq("test")
            & group["unit"].astype(str).eq("original")
        ].copy()
        group.insert(0, "fold", int(fold))
        group.insert(1, "comparison_dir", config_path_value(comp_dir))
        horizon_group_parts.append(group)

        row_audit = read_csv_required(comp_dir / "pricefm_vs_desn_row_alignment_audit.csv", context)
        row_audit.insert(0, "fold", int(fold))
        row_audit.insert(1, "comparison_dir", config_path_value(comp_dir))
        row_audit_parts.append(row_audit)

        summary = read_json_if_exists(comp_dir / "summary.json")
        sources.append({
            "fold": int(fold),
            "comparison_dir": config_path_value(comp_dir),
            "desn_output_dir": summary.get("desn_output_dir"),
            "pricefm_output_dir": summary.get("pricefm_output_dir"),
            "n_aligned_prediction_rows": summary.get("n_aligned_prediction_rows"),
            "n_aligned_response_rows": summary.get("n_aligned_response_rows"),
        })

    return {
        "metric": pd.concat(metric_parts, ignore_index=True),
        "horizon": pd.concat(horizon_parts, ignore_index=True),
        "horizon_group": pd.concat(horizon_group_parts, ignore_index=True),
        "row_audit": pd.concat(row_audit_parts, ignore_index=True),
        "sources": sources,
    }


def macro_metrics(fold_metric):
    metrics = [c for c in ["AQL", "AQCR", "MAE", "RMSE"] if c in fold_metric.columns]
    grouped = fold_metric.groupby("method_id", as_index=False)[metrics].agg(["mean", "std", "min", "max"])
    grouped.columns = [
        "{}_{}".format(metric, stat) if stat else metric
        for metric, stat in grouped.columns.to_flat_index()
    ]
    return grouped.sort_values(["AQL_mean", "method_id"]).reset_index(drop=True)


def deltas_vs_baseline(fold_metric, baseline_method):
    rows = []
    for fold, df in fold_metric.groupby("fold"):
        base = df[df["method_id"].astype(str).eq(str(baseline_method))]
        if base.empty:
            raise ValueError("fold {} missing baseline method {}".format(fold, baseline_method))
        base = base.iloc[0]
        for _, row in df.iterrows():
            out = {
                "fold": int(fold),
                "method_id": row["method_id"],
                "baseline_method_id": baseline_method,
            }
            for metric in ["AQL", "AQCR", "MAE", "RMSE"]:
                if metric not in row or metric not in base:
                    continue
                value = float(row[metric])
                baseline = float(base[metric])
                out[metric] = value
                out["baseline_{}".format(metric)] = baseline
                out["delta_{}".format(metric)] = value - baseline
                out["ratio_{}".format(metric)] = value / baseline if baseline != 0.0 else float("nan")
            rows.append(out)
    return pd.DataFrame(rows).sort_values(["fold", "delta_AQL", "method_id"]).reset_index(drop=True)


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
    return pd.DataFrame(rows).sort_values("fold").reset_index(drop=True)


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
    return value


def load_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def first_fold1_spec(path):
    payload = load_yaml(path)
    grid = payload["pricefm_desn_experiment_grid"]
    exp = grid["experiments"][0]
    return {
        "fold": 1,
        "selection_source": "fold1_authoritative_config",
        "experiment_id": exp["id"],
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "lag_window": int(exp["lag_window"]),
        "feature_dim": int(exp.get("feature_dim", exp["units"][0] if isinstance(exp["units"], list) else exp["units"])),
        "depth": int(exp["depth"]),
        "units": json.dumps(parse_jsonish(exp["units"])),
        "alpha": exp["alpha"],
        "rho": exp["rho"],
        "input_scale": exp["input_scale"],
        "projection_scale": exp.get("projection_scale", 1.0),
        "tau0": float(exp["tau0"]),
        "seed": int(exp["seed"]),
        "selection_metric_value": "",
        "test_AQL": "",
    }


def selected_spec_summary(fold1_grid_config, folds23_registry):
    rows = [first_fold1_spec(fold1_grid_config)]
    reg_path = repo_path(folds23_registry)
    if reg_path.exists() and reg_path.stat().st_size > 0:
        reg = pd.read_csv(reg_path)
        for _, row in reg.sort_values(["fold"]).iterrows():
            rows.append({
                "fold": int(row["fold"]),
                "selection_source": "folds23_validation_registry",
                "experiment_id": row["experiment_id"],
                "selected_method_id": row["selected_method_id"],
                "lag_window": int(row["lag_window"]),
                "feature_dim": int(row["feature_dim"]),
                "depth": int(row["depth"]),
                "units": row["units"],
                "alpha": row["alpha"],
                "rho": row["rho"],
                "input_scale": row["input_scale"],
                "projection_scale": row["projection_scale"],
                "tau0": float(row["tau0"]),
                "seed": int(row["seed"]),
                "selection_metric_value": row.get("selection_metric_value", ""),
                "test_AQL": row.get("test_AQL", ""),
            })
    return pd.DataFrame(rows).sort_values("fold").reset_index(drop=True)


def plot_figures(out_dir, fold_metric, delta, macro, horizon_group, baseline_method):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []

    methods = list(macro.sort_values(["AQL_mean", "method_id"])["method_id"])
    folds = sorted(int(x) for x in fold_metric["fold"].unique())
    width = 0.82 / max(len(methods), 1)
    x = list(range(len(folds)))
    fig, ax = plt.subplots(figsize=(13.5, 6.2))
    for i, method_id in enumerate(methods):
        vals = []
        for fold in folds:
            sub = fold_metric[fold_metric["fold"].eq(fold) & fold_metric["method_id"].eq(method_id)]
            vals.append(float(sub["AQL"].iloc[0]) if not sub.empty else float("nan"))
        offsets = [xx - 0.41 + width / 2 + i * width for xx in x]
        ax.bar(offsets, vals, width=width, label=method_id)
    ax.set_xticks(x)
    ax.set_xticklabels(["fold {}".format(f) for f in folds])
    ax.set_ylabel("AQL, original scale")
    ax.set_title("DE_LU Fold-Complete PriceFM Phase-I vs DESN/Q-DESN AQL")
    ax.grid(axis="y", alpha=0.22)
    ax.legend(fontsize=8, ncol=2)
    fig.tight_layout()
    path = fig_dir / "fold_complete_aql_by_fold_method.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    fig, ax = plt.subplots(figsize=(13.5, 6.2))
    for method_id, sub in delta[~delta["method_id"].eq(baseline_method)].groupby("method_id"):
        sub = sub.sort_values("fold")
        ax.plot(sub["fold"], sub["delta_AQL"], marker="o", linewidth=1.5, label=method_id)
    ax.axhline(0.0, color="black", linewidth=1.0)
    ax.set_xlabel("Fold")
    ax.set_ylabel("AQL minus {}".format(baseline_method))
    ax.set_title("DE_LU Fold-Complete AQL Delta Versus PriceFM Phase-I")
    ax.grid(alpha=0.22)
    ax.legend(fontsize=8)
    fig.tight_layout()
    path = fig_dir / "fold_complete_aql_delta_vs_pricefm.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    top = macro.sort_values(["AQL_mean", "method_id"]).head(5).copy()
    fig, ax = plt.subplots(figsize=(11.5, 5.5))
    ax.bar(top["method_id"], top["AQL_mean"], yerr=top["AQL_std"].fillna(0.0), capsize=4)
    ax.set_ylabel("Mean AQL across folds")
    ax.set_title("DE_LU Macro AQL, Folds 1/2/3")
    ax.grid(axis="y", alpha=0.22)
    ax.tick_params(axis="x", rotation=35)
    fig.tight_layout()
    path = fig_dir / "fold_complete_macro_aql.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    top_methods = top["method_id"].tolist()
    hg = horizon_group[horizon_group["method_id"].isin(top_methods)].copy()
    if not hg.empty:
        avg = hg.groupby(["horizon_group", "method_id"], as_index=False)["AQL"].mean()
        piv = avg.pivot(index="horizon_group", columns="method_id", values="AQL")
        piv = piv.reindex(["1-24", "25-48", "49-72", "73-96"])
        fig, ax = plt.subplots(figsize=(12.5, 5.5))
        piv.plot(kind="bar", ax=ax)
        ax.set_ylabel("Mean AQL across folds")
        ax.set_title("DE_LU Mean AQL By Horizon Block")
        ax.grid(axis="y", alpha=0.22)
        ax.tick_params(axis="x", rotation=0)
        fig.tight_layout()
        path = fig_dir / "fold_complete_aql_by_horizon_block.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        made.append(str(path))
    return made


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append(("{:." + str(int(float_digits)) + "f}").format(value))
            else:
                vals.append(str(value))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(out_dir, region, fold_dirs, fold_metric, macro, winners, delta,
                 specs, row_audit, figures, baseline_method):
    path = out_dir / "pricefm_vs_desn_fold_complete_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Phase-I vs DESN/Q-DESN {} Fold-Complete Report\n\n".format(region))
        f.write("Folds: `{}`\n\n".format(",".join(str(fold) for fold, _ in fold_dirs)))
        f.write("Baseline method: `{}`\n\n".format(baseline_method))
        f.write("## Main Takeaway\n\n")
        best = macro.sort_values(["AQL_mean", "method_id"]).iloc[0]
        f.write(
            "Best macro-AQL method: `{}` with mean AQL `{:.6f}` across folds. "
            "This report uses the authoritative fold-1 DESN run plus the "
            "improved follow-up folds-2/3 registry-selected runs.\n\n".format(
                best["method_id"], float(best["AQL_mean"])
            )
        )
        f.write("## Selected DESN Specs\n\n")
        f.write(markdown_table(specs, columns=[
            "fold", "selection_source", "experiment_id", "selected_method_id",
            "lag_window", "feature_dim", "depth", "units", "alpha", "rho",
            "input_scale", "tau0", "seed",
        ]))
        f.write("\n\n## Fold Winners By AQL\n\n")
        f.write(markdown_table(winners))
        f.write("\n\n## Macro Metrics, Original Scale\n\n")
        f.write(markdown_table(macro, columns=[
            "method_id", "AQL_mean", "AQL_std", "AQL_min", "AQL_max",
            "MAE_mean", "RMSE_mean",
        ]))
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
        f.write("\n\n## Notes\n\n")
        f.write("- Test metrics are computed on fold-aligned rows only.\n")
        f.write("- Folds 2/3 use validation-selected follow-up median specs promoted to all paper quantiles.\n")
        f.write("- No model fits are launched by this summarizer.\n")
    return path


def main():
    args = parser().parse_args()
    fold_dirs = parse_fold_dirs(args.fold_comparison_dirs)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    payload = collect_fold_outputs(fold_dirs)
    macro = macro_metrics(payload["metric"])
    delta = deltas_vs_baseline(payload["metric"], args.baseline_method)
    winners = fold_winners(payload["metric"])
    specs = selected_spec_summary(args.fold1_grid_config, args.folds23_registry)
    figures = plot_figures(
        out_dir,
        payload["metric"],
        delta,
        macro,
        payload["horizon_group"],
        args.baseline_method,
    )
    report = write_report(
        out_dir,
        args.region,
        fold_dirs,
        payload["metric"],
        macro,
        winners,
        delta,
        specs,
        payload["row_audit"],
        figures,
        args.baseline_method,
    )

    payload["metric"].to_csv(out_dir / "fold_metric_summary.csv", index=False)
    payload["horizon"].to_csv(out_dir / "fold_horizon_metric_summary.csv", index=False)
    payload["horizon_group"].to_csv(out_dir / "fold_horizon_group_metric_summary.csv", index=False)
    payload["row_audit"].to_csv(out_dir / "fold_row_alignment_audit.csv", index=False)
    macro.to_csv(out_dir / "macro_metric_summary.csv", index=False)
    delta.to_csv(out_dir / "method_delta_vs_pricefm.csv", index=False)
    winners.to_csv(out_dir / "fold_winners.csv", index=False)
    specs.to_csv(out_dir / "selected_spec_summary.csv", index=False)
    summary = {
        "region": args.region,
        "folds": [int(fold) for fold, _ in fold_dirs],
        "baseline_method": args.baseline_method,
        "comparison_sources": payload["sources"],
        "best_macro_method": str(macro.iloc[0]["method_id"]),
        "best_macro_AQL": float(macro.iloc[0]["AQL_mean"]),
        "outputs": {
            "fold_metric_summary": str(out_dir / "fold_metric_summary.csv"),
            "macro_metric_summary": str(out_dir / "macro_metric_summary.csv"),
            "method_delta_vs_pricefm": str(out_dir / "method_delta_vs_pricefm.csv"),
            "fold_winners": str(out_dir / "fold_winners.csv"),
            "selected_spec_summary": str(out_dir / "selected_spec_summary.csv"),
            "row_alignment": str(out_dir / "fold_row_alignment_audit.csv"),
            "report": str(report),
            "figures": figures,
        },
    }
    write_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
