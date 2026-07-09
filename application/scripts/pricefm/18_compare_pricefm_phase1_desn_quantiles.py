#!/usr/bin/env python3
"""Compare local PriceFM Phase-I forecasts against DESN paper-quantile outputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, pricefm_block, repo_path, write_json
from pricefm_metrics import inverse_scale_y, metric_dict, normalize_quantiles


DEFAULT_PRICEFM = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_de_lu_fold1_apples_to_apples_20260602"
)
DEFAULT_DESN = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_fold1_20260602"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--pricefm-output-dir", default=DEFAULT_PRICEFM)
    p.add_argument("--desn-output-dir", default=DEFAULT_DESN)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--fold", type=int, default=1)
    p.add_argument("--split", default="test")
    p.add_argument("--methods", default="pricefm_phase1_pretraining,qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked,normal_rhs_ns,normal_scaled_ridge")
    p.add_argument("--quantiles", default="0.10,0.25,0.45,0.50,0.55,0.75,0.90")
    p.add_argument("--fan-horizon", type=int, default=1)
    p.add_argument("--max-origins", type=int, default=120)
    return p


def parse_csv_list(value):
    return [x.strip() for x in str(value).split(",") if x.strip()]


def parse_quantiles(value):
    return [float(x) for x in normalize_quantiles(parse_csv_list(value))]


def read_csv_required(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("Missing required CSV: {}".format(path))
    return pd.read_csv(path)


def load_y_scaler(cfg, fold, region):
    spec = pricefm_block(cfg)
    path = repo_path(
        Path(spec["processed_dir"])
        / "scalers"
        / "fold_{}".format(int(fold))
        / "per_region_separate_xy_scalers.joblib"
    )
    scalers = joblib.load(path)
    return scalers[region]["y_scaler"]


def first_cell_adapter_dir(desn_dir):
    status = read_csv_required(Path(desn_dir) / "quantile_cell_status.csv")
    if status.empty:
        raise ValueError("quantile_cell_status.csv is empty")
    return repo_path(status.sort_values("tau")["adapter_dir"].iloc[0])


def load_desn_rows(desn_dir, split):
    path = first_cell_adapter_dir(desn_dir) / "rows_{}.csv".format(split)
    rows = read_csv_required(path)
    for col in ["origin_market_time", "response_market_time"]:
        rows[col] = pd.to_datetime(rows[col], utc=True).dt.strftime("%Y-%m-%dT%H:%M:%S%z")
        rows[col] = rows[col].str.replace(r"(\+0000)$", "+00:00", regex=True)
    return rows


def augment_desn_predictions(desn_dir, split):
    pred = read_csv_required(Path(desn_dir) / "combined_predictions_scaled.csv")
    pred = pred[pred["split"].astype(str) == str(split)].copy()
    rows = load_desn_rows(desn_dir, split)
    keep = ["split", "origin_id", "horizon", "origin_market_time", "response_market_time", "y_scaled"]
    out = pred.merge(rows[keep], on=["split", "origin_id", "horizon"], how="left", validate="many_to_one")
    if out["y_scaled"].isna().any():
        raise ValueError("DESN prediction rows failed to merge with adapter rows")
    return out


def normalize_time_cols(frame):
    out = frame.copy()
    for col in ["origin_market_time", "response_market_time"]:
        out[col] = pd.to_datetime(out[col], utc=True).dt.strftime("%Y-%m-%dT%H:%M:%S%z")
        out[col] = out[col].str.replace(r"(\+0000)$", "+00:00", regex=True)
    return out


def load_pricefm_predictions(pricefm_dir, split):
    pred = read_csv_required(Path(pricefm_dir) / "pricefm_phase1_predictions_scaled.csv")
    pred = pred[pred["split"].astype(str) == str(split)].copy()
    required = {"method_id", "split", "origin_id", "horizon", "tau", "pred_scaled", "y_scaled", "origin_market_time", "response_market_time"}
    missing = required - set(pred.columns)
    if missing:
        raise ValueError("PriceFM predictions missing columns: {}".format(sorted(missing)))
    return normalize_time_cols(pred)


def row_key_cols(include_tau=False):
    cols = ["split", "origin_market_time", "response_market_time", "horizon"]
    if include_tau:
        cols.append("tau")
    return cols


def align_predictions(pricefm_pred, desn_pred, methods):
    combined = pd.concat([pricefm_pred, desn_pred], ignore_index=True, sort=False)
    combined["tau"] = combined["tau"].astype(float)
    combined = combined[combined["method_id"].isin(methods)].copy()
    if combined.empty:
        raise ValueError("No predictions remain after method filtering")
    method_sets = {}
    for method_id, df in combined.groupby("method_id"):
        method_sets[method_id] = set(map(tuple, df[row_key_cols(include_tau=True)].to_numpy()))
    common = set.intersection(*method_sets.values())
    if not common:
        raise ValueError("No common prediction rows across selected methods")
    common_df = pd.DataFrame(list(common), columns=row_key_cols(include_tau=True))
    aligned = combined.merge(common_df, on=row_key_cols(include_tau=True), how="inner")
    aligned = aligned.sort_values(["method_id", "split", "origin_market_time", "horizon", "tau"]).reset_index(drop=True)
    row_audit = []
    base_rows = len(common_df.drop_duplicates(row_key_cols(include_tau=False)))
    for method_id, df in combined.groupby("method_id"):
        row_audit.append({
            "method_id": method_id,
            "available_prediction_rows": int(df.shape[0]),
            "available_unique_response_rows": int(df.drop_duplicates(row_key_cols(include_tau=False)).shape[0]),
            "aligned_prediction_rows": int(aligned[aligned["method_id"] == method_id].shape[0]),
            "aligned_unique_response_rows": int(base_rows),
        })
    return aligned, pd.DataFrame(row_audit)


def metric_arrays(method_df, quantiles):
    row_cols = ["origin_market_time", "horizon"]
    truth = method_df.drop_duplicates(row_cols).pivot(
        index="origin_market_time", columns="horizon", values="y_scaled"
    )
    pred = method_df.pivot_table(
        index="origin_market_time",
        columns=["horizon", "tau"],
        values="pred_scaled",
        aggfunc="first",
    )
    origins = sorted(truth.index)
    horizons = sorted(int(h) for h in method_df["horizon"].unique())
    y = truth.loc[origins, horizons].to_numpy()
    blocks = []
    for h in horizons:
        blocks.append(pred[h].loc[origins, quantiles].to_numpy())
    return y, np.stack(blocks, axis=1), horizons


def horizon_group_label(horizon):
    horizon = int(horizon)
    start = ((horizon - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return "{}-{}".format(start, end)


def compute_metrics(aligned, quantiles, y_scaler):
    rows = []
    horizon_rows = []
    group_rows = []
    for method_id, df in aligned.groupby("method_id"):
        y_scaled, p_scaled, horizons = metric_arrays(df, quantiles)
        y_orig = inverse_scale_y(y_scaled, y_scaler)
        p_orig = inverse_scale_y(p_scaled, y_scaler)
        for unit, y, p in [("scaled", y_scaled, p_scaled), ("original", y_orig, p_orig)]:
            rows.append({
                "method_id": method_id,
                "split": df["split"].iloc[0],
                "unit": unit,
                **metric_dict(y, p, quantiles),
            })
            for h_idx, h in enumerate(horizons):
                horizon_rows.append({
                    "method_id": method_id,
                    "split": df["split"].iloc[0],
                    "unit": unit,
                    "horizon": int(h),
                    **metric_dict(y[:, [h_idx]], p[:, [h_idx], :], quantiles),
                })
            for group in sorted({horizon_group_label(h) for h in horizons}):
                idx = [i for i, h in enumerate(horizons) if horizon_group_label(h) == group]
                group_rows.append({
                    "method_id": method_id,
                    "split": df["split"].iloc[0],
                    "unit": unit,
                    "horizon_group": group,
                    **metric_dict(y[:, idx], p[:, idx, :], quantiles),
                })
    return (
        pd.DataFrame(rows).sort_values(["unit", "AQL", "method_id"]),
        pd.DataFrame(horizon_rows).sort_values(["unit", "horizon", "AQL", "method_id"]),
        pd.DataFrame(group_rows).sort_values(["unit", "horizon_group", "AQL", "method_id"]),
    )


def add_original_columns(frame, y_scaler):
    out = frame.copy()
    out["pred_original"] = inverse_scale_y(out["pred_scaled"].to_numpy(), y_scaler)
    out["y_original"] = inverse_scale_y(out["y_scaled"].to_numpy(), y_scaler)
    return out


def method_horizon_frame(aligned_orig, method_id, horizon, quantiles, max_origins):
    sub = aligned_orig[
        (aligned_orig["method_id"] == method_id)
        & (aligned_orig["horizon"].astype(int) == int(horizon))
    ].copy()
    origins = sorted(sub["origin_market_time"].unique())[: int(max_origins)]
    sub = sub[sub["origin_market_time"].isin(origins)].copy()
    piv = sub.pivot_table(index="origin_market_time", columns="tau", values="pred_original", aggfunc="first")
    base = sub.drop_duplicates("origin_market_time").sort_values("origin_market_time")
    out = base[["origin_market_time", "response_market_time", "y_original"]].copy()
    for tau in quantiles:
        out[tau] = piv.loc[out["origin_market_time"], tau].to_numpy()
    out["response_market_time"] = pd.to_datetime(out["response_market_time"], utc=True)
    return out


def plot_fan_panels(aligned_orig, methods, quantiles, out_dir, horizon, max_origins):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []
    methods = [m for m in methods if m in set(aligned_orig["method_id"])]
    fig, axes = plt.subplots(len(methods), 1, figsize=(15, max(4, 3.0 * len(methods))), sharex=True)
    if len(methods) == 1:
        axes = [axes]
    for ax, method_id in zip(axes, methods):
        df = method_horizon_frame(aligned_orig, method_id, horizon, quantiles, max_origins)
        x = df["response_market_time"]
        ax.plot(x, df["y_original"], color="black", linewidth=1.4, label="observed")
        if 0.1 in quantiles and 0.9 in quantiles:
            ax.fill_between(x, df[0.1], df[0.9], color="#9CA3AF", alpha=0.32, label="0.10-0.90")
        if 0.25 in quantiles and 0.75 in quantiles:
            ax.fill_between(x, df[0.25], df[0.75], color="#2563EB", alpha=0.20, label="0.25-0.75")
        for tau in quantiles:
            if abs(tau - 0.5) < 1.0e-12:
                ax.plot(x, df[tau], color="#DC2626", linewidth=1.5, label="0.50")
            else:
                ax.plot(x, df[tau], color="#2563EB", alpha=0.58, linewidth=0.7)
        ax.set_title(method_id)
        ax.set_ylabel("Price")
        ax.grid(alpha=0.20)
        ax.xaxis.set_major_locator(mdates.MonthLocator())
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
    axes[0].legend(fontsize=8, ncol=4, loc="best")
    axes[-1].set_xlabel("Response market time")
    fig.suptitle("PriceFM Phase-I vs DESN Quantile Fans, Horizon {}".format(int(horizon)), y=0.995)
    fig.tight_layout(rect=[0, 0, 1, 0.975])
    path = fig_dir / "pricefm_vs_desn_quantile_fans_h{:02d}.png".format(int(horizon))
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    pair = ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked"]
    pair = [m for m in pair if m in set(aligned_orig["method_id"])]
    horizons = [1, 24, 48, 96]
    fig, axes = plt.subplots(len(horizons), len(pair), figsize=(7.5 * len(pair), 3.3 * len(horizons)), sharex=False)
    if len(pair) == 1:
        axes = np.asarray(axes).reshape(len(horizons), 1)
    for i, h in enumerate(horizons):
        for j, method_id in enumerate(pair):
            ax = axes[i, j]
            df = method_horizon_frame(aligned_orig, method_id, h, quantiles, max_origins)
            x = df["response_market_time"]
            ax.plot(x, df["y_original"], color="black", linewidth=1.2)
            if 0.1 in quantiles and 0.9 in quantiles:
                ax.fill_between(x, df[0.1], df[0.9], color="#9CA3AF", alpha=0.32)
            if 0.25 in quantiles and 0.75 in quantiles:
                ax.fill_between(x, df[0.25], df[0.75], color="#2563EB", alpha=0.20)
            if 0.5 in quantiles:
                ax.plot(x, df[0.5], color="#DC2626", linewidth=1.3)
            for tau in quantiles:
                if abs(tau - 0.5) >= 1.0e-12:
                    ax.plot(x, df[tau], color="#2563EB", alpha=0.58, linewidth=0.7)
            ax.set_title("{} | h={}".format(method_id, h))
            ax.grid(alpha=0.20)
            ax.xaxis.set_major_locator(mdates.MonthLocator())
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
            if j == 0:
                ax.set_ylabel("Price")
    fig.suptitle("PriceFM Phase-I and Q-DESN exAL RHS_NS Predictive Distributions", y=0.995)
    fig.tight_layout(rect=[0, 0, 1, 0.975])
    path = fig_dir / "pricefm_vs_qdesn_exal_fans_h001_h024_h048_h096.png"
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))
    return made


def plot_metric_by_horizon(horizon_metrics, out_dir):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []
    for metric in ["AQL", "MAE", "RMSE"]:
        df = horizon_metrics[horizon_metrics["unit"] == "original"].copy()
        if df.empty or metric not in df.columns:
            continue
        fig, ax = plt.subplots(figsize=(12, 5))
        for method_id, sub in df.groupby("method_id"):
            sub = sub.sort_values("horizon")
            ax.plot(sub["horizon"], sub[metric], linewidth=1.2, label=method_id)
        ax.set_title("Original-Scale {} By Horizon".format(metric))
        ax.set_xlabel("Horizon")
        ax.set_ylabel(metric)
        ax.grid(alpha=0.22)
        ax.legend(fontsize=8, ncol=2)
        fig.tight_layout()
        path = fig_dir / "pricefm_vs_desn_{}_by_horizon.png".format(metric.lower())
        fig.savefig(path, dpi=170)
        plt.close(fig)
        made.append(str(path))
    return made


def markdown_table(frame):
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        values = [str(row[col]) for col in cols]
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def write_report(out_dir, metric, horizon_group, row_audit, figures, pricefm_summary_path, region, fold):
    original = metric[(metric["split"] == "test") & (metric["unit"] == "original")].copy()
    with open(out_dir / "pricefm_vs_desn_report.md", "w") as f:
        f.write("# PriceFM Phase-I vs DESN/Q-DESN {} Fold-{} Comparison\n\n".format(region, int(fold)))
        f.write("This report compares locally regenerated PriceFM Phase-I predictions with the Article-Q-DESN paper-quantile outputs on the aligned prediction rows.\n\n")
        f.write("PriceFM summary: `{}`\n\n".format(pricefm_summary_path))
        f.write("## Test Metrics, Original Scale\n\n")
        f.write(markdown_table(original))
        f.write("\n\n## Horizon-Group Metrics, Original Scale\n\n")
        f.write(markdown_table(horizon_group[horizon_group["unit"] == "original"]))
        f.write("\n\n## Row Alignment\n\n")
        f.write(markdown_table(row_audit))
        f.write("\n\n## Figures\n\n")
        for fig in figures:
            f.write("- `{}`\n".format(fig))


def main():
    args = parser().parse_args()
    cfg = load_config(args.config)
    quantiles = parse_quantiles(args.quantiles)
    methods = parse_csv_list(args.methods)
    pricefm_dir = repo_path(args.pricefm_output_dir)
    desn_dir = repo_path(args.desn_output_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    y_scaler = load_y_scaler(cfg, args.fold, args.region)

    pricefm_pred = load_pricefm_predictions(pricefm_dir, args.split)
    desn_pred = augment_desn_predictions(desn_dir, args.split)
    aligned, row_audit = align_predictions(pricefm_pred, desn_pred, methods)
    aligned_orig = add_original_columns(aligned, y_scaler)
    metric, horizon_metric, horizon_group = compute_metrics(aligned, quantiles, y_scaler)

    aligned.to_csv(out_dir / "pricefm_vs_desn_predictions_scaled.csv", index=False)
    aligned_orig.to_csv(out_dir / "pricefm_vs_desn_predictions_original.csv", index=False)
    metric.to_csv(out_dir / "pricefm_vs_desn_metric_summary.csv", index=False)
    horizon_metric.to_csv(out_dir / "pricefm_vs_desn_metric_by_horizon.csv", index=False)
    horizon_group.to_csv(out_dir / "pricefm_vs_desn_metric_by_horizon_group.csv", index=False)
    row_audit.to_csv(out_dir / "pricefm_vs_desn_row_alignment_audit.csv", index=False)
    figures = []
    figures.extend(plot_fan_panels(aligned_orig, methods, quantiles, out_dir, args.fan_horizon, args.max_origins))
    figures.extend(plot_metric_by_horizon(horizon_metric, out_dir))
    payload = {
        "region": args.region,
        "fold": int(args.fold),
        "split": args.split,
        "quantiles": quantiles,
        "methods": methods,
        "pricefm_output_dir": str(pricefm_dir),
        "desn_output_dir": str(desn_dir),
        "n_aligned_prediction_rows": int(aligned.shape[0]),
        "n_aligned_response_rows": int(aligned.drop_duplicates(row_key_cols(include_tau=False)).shape[0]),
        "outputs": {
            "metrics": str(out_dir / "pricefm_vs_desn_metric_summary.csv"),
            "horizon_metrics": str(out_dir / "pricefm_vs_desn_metric_by_horizon.csv"),
            "row_alignment": str(out_dir / "pricefm_vs_desn_row_alignment_audit.csv"),
            "figures": figures,
        },
    }
    write_json(out_dir / "summary.json", payload)
    write_report(
        out_dir, metric, horizon_group, row_audit, figures,
        pricefm_dir / "summary.json", args.region, args.fold
    )
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
