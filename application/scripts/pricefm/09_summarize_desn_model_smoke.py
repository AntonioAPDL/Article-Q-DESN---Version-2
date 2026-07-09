#!/usr/bin/env python3
"""Summarize a PriceFM DESN model smoke run."""

from __future__ import print_function

import csv
from pathlib import Path

import pandas as pd

from pricefm_baselines import make_naive_quantile_forecast
from pricefm_common import load_config, pricefm_block, repo_path, summarize
from pricefm_desn_adapter import load_smoke_config
from pricefm_metrics import inverse_scale_y, metric_dict


def parser():
    import argparse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--smoke-config", default="application/config/pricefm_desn_model_smoke.yaml")
    p.add_argument("--run-dir", default=None)
    return p


def ensure_market_index(df, split_time_col, time_col):
    if isinstance(df.index, pd.DatetimeIndex) and df.index.name == split_time_col:
        return df.sort_index()
    if split_time_col in df.columns:
        df[split_time_col] = pd.to_datetime(df[split_time_col], utc=True)
        return df.sort_values(split_time_col).set_index(split_time_col)
    if time_col in df.columns:
        df[split_time_col] = pd.to_datetime(df[time_col], utc=True) + pd.Timedelta(hours=1)
        return df.sort_values(split_time_col).set_index(split_time_col)
    raise ValueError("Dataframe lacks market-time columns")


def load_scaled_price_series(data_cfg, fold, region):
    spec = pricefm_block(data_cfg)
    root = repo_path(Path(spec["processed_dir"]) / "splits_scaled" / "fold_{}".format(fold))
    frames = []
    for split in ("train", "val", "test"):
        frame = pd.read_parquet(root / "{}_scaled.parquet".format(split))
        frames.append(ensure_market_index(frame, spec["split_time_col"], spec["time_col"]))
    df = pd.concat(frames).sort_index()
    return df["{}-{}".format(region, spec["features"]["label"])]


def load_y_scaler(data_cfg, fold, region):
    import joblib

    spec = pricefm_block(data_cfg)
    path = repo_path(Path(spec["processed_dir"]) / "scalers" /
                     "fold_{}".format(fold) / "per_region_separate_xy_scalers.joblib")
    scalers = joblib.load(path)
    return scalers[region]["y_scaler"]


def pivot_truth(rows, horizons):
    wide = rows.pivot(index="origin_id", columns="horizon", values="y_scaled")
    return wide.loc[:, horizons].to_numpy()


def pivot_predictions(pred, horizons, quantiles):
    piv = pred.pivot_table(
        index="origin_id",
        columns=["horizon", "tau"],
        values="pred_scaled",
        aggfunc="first",
    )
    blocks = []
    for h in horizons:
        blocks.append(piv[h].loc[:, quantiles].to_numpy())
    import numpy as np

    return np.stack(blocks, axis=1)


def predictions_frame(method_id, split, rows, pred_arr, quantiles):
    out = []
    for q_idx, tau in enumerate(quantiles):
        tmp = rows[["split", "origin_id", "horizon"]].copy()
        tmp["method_id"] = method_id
        tmp["tau"] = tau
        tmp["pred_scaled"] = pred_arr[:, :, q_idx].reshape(-1)
        out.append(tmp[["method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"]])
    return pd.concat(out, ignore_index=True)


def markdown_table(df):
    if df.empty:
        return "_No rows._\n"
    cols = list(df.columns)
    rows = []
    rows.append("| " + " | ".join(cols) + " |")
    rows.append("| " + " | ".join(["---"] * len(cols)) + " |")
    for _, row in df.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val))
        rows.append("| " + " | ".join(vals) + " |")
    return "\n".join(rows) + "\n"


def horizon_group_label(horizon):
    horizon = int(horizon)
    start = ((horizon - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return "{}-{}".format(start, end)


def make_cell_figures(run_dir, rows, pred, y_scaler, quantiles):
    fig_dir = run_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        return {"figures_skipped": "matplotlib unavailable: {}".format(exc)}

    made = []

    trace_path = run_dir / "model_trace_summary.csv"
    if trace_path.exists() and trace_path.stat().st_size > 0:
        trace = pd.read_csv(trace_path)
        if {"method_id", "iter", "elbo"}.issubset(trace.columns):
            elbo = trace[pd.to_numeric(trace["elbo"], errors="coerce").notna()].copy()
            if not elbo.empty:
                plt.figure(figsize=(10, 5))
                for method_id, df in elbo.groupby("method_id"):
                    df = df.sort_values("iter")
                    plt.plot(df["iter"], df["elbo"], marker="o", linewidth=1.5, label=method_id)
                plt.xlabel("VB iteration")
                plt.ylabel("ELBO / objective")
                plt.title("VB Objective Trace")
                plt.legend(fontsize=8)
                plt.tight_layout()
                path = fig_dir / "trace_elbo.png"
                plt.savefig(path, dpi=160)
                plt.close()
                made.append(str(path))

        cols = [c for c in ["sigma", "gamma", "omega2", "rhs_tau", "rhs_lambda_mean", "parameter_change"]
                if c in trace.columns and pd.to_numeric(trace[c], errors="coerce").notna().any()]
        if cols:
            nrows = len(cols)
            fig, axes = plt.subplots(nrows, 1, figsize=(10, max(3, 2.4 * nrows)), sharex=True)
            if nrows == 1:
                axes = [axes]
            for ax, col in zip(axes, cols):
                for method_id, df in trace.groupby("method_id"):
                    vals = pd.to_numeric(df[col], errors="coerce")
                    if vals.notna().any():
                        ax.plot(df["iter"], vals, marker="o", linewidth=1.2, label=method_id)
                ax.set_ylabel(col)
                ax.grid(alpha=0.25)
            axes[0].legend(fontsize=8)
            axes[-1].set_xlabel("VB iteration")
            fig.suptitle("VB Parameter Diagnostics")
            fig.tight_layout()
            path = fig_dir / "trace_parameter_diagnostics.png"
            fig.savefig(path, dpi=160)
            plt.close(fig)
            made.append(str(path))

    param_path = run_dir / "model_parameter_summary.csv"
    if param_path.exists() and param_path.stat().st_size > 0:
        params = pd.read_csv(param_path)
        value_cols = [c for c in ["beta_l2", "beta_max_abs", "beta_cov_trace", "sigma", "gamma", "omega2"]
                      if c in params.columns and pd.to_numeric(params[c], errors="coerce").notna().any()]
        if value_cols and "method_id" in params.columns:
            nrows = len(value_cols)
            fig, axes = plt.subplots(nrows, 1, figsize=(10, max(3, 2.2 * nrows)))
            if nrows == 1:
                axes = [axes]
            for ax, col in zip(axes, value_cols):
                df = params[["method_id", col]].copy()
                df[col] = pd.to_numeric(df[col], errors="coerce")
                df = df[df[col].notna()]
                ax.bar(df["method_id"], df[col])
                ax.set_ylabel(col)
                ax.tick_params(axis="x", rotation=35)
            fig.suptitle("Final Parameter Summaries")
            fig.tight_layout()
            path = fig_dir / "final_parameter_summary.png"
            fig.savefig(path, dpi=160)
            plt.close(fig)
            made.append(str(path))

    if "test" in rows and not pred.empty:
        test_rows = rows["test"][["origin_id", "horizon", "response_market_time", "y_scaled"]].copy()
        test_rows["response_market_time"] = pd.to_datetime(test_rows["response_market_time"], utc=True)
        med_tau = float(quantiles[min(range(len(quantiles)), key=lambda i: abs(float(quantiles[i]) - 0.5))])
        test_pred = pred[(pred["split"] == "test") & (pred["tau"].astype(float) == med_tau)].copy()
        if not test_pred.empty:
            merged = test_pred.merge(test_rows, on=["origin_id", "horizon"], how="left")
            keep_origins = sorted(merged["origin_id"].dropna().unique().tolist())[:14]
            merged = merged[merged["origin_id"].isin(keep_origins)].copy()
            if not merged.empty:
                merged["pred_orig"] = inverse_scale_y(merged["pred_scaled"].to_numpy(), y_scaler)
                merged["y_orig"] = inverse_scale_y(merged["y_scaled"].to_numpy(), y_scaler)
                truth = (merged[["response_market_time", "y_orig"]]
                         .drop_duplicates()
                         .sort_values("response_market_time"))
                method_order = [
                    "normal_scaled_ridge",
                    "normal_rhs_ns",
                    "qdesn_al_rhs_ns_exact_chunked",
                    "qdesn_exal_rhs_ns_exact_chunked",
                    "naive1_prev_day",
                ]
                available = [m for m in method_order if m in set(merged["method_id"])]
                plt.figure(figsize=(13, 5))
                plt.plot(truth["response_market_time"], truth["y_orig"], color="black",
                         linewidth=1.8, label="observed")
                for method_id in available:
                    df = merged[merged["method_id"] == method_id].sort_values("response_market_time")
                    plt.plot(df["response_market_time"], df["pred_orig"], linewidth=1.0, alpha=0.9, label=method_id)
                plt.ylabel("Price")
                plt.xlabel("Response market time")
                plt.title("Test Fit vs Observed Data, First 14 Origins")
                plt.legend(fontsize=8, ncol=2)
                plt.tight_layout()
                path = fig_dir / "test_fit_first14_origins.png"
                plt.savefig(path, dpi=160)
                plt.close()
                made.append(str(path))

                qmethods = [m for m in [
                    "qdesn_al_rhs_ns_exact_chunked",
                    "qdesn_exal_rhs_ns_exact_chunked",
                    "normal_rhs_ns",
                    "normal_scaled_ridge",
                ] if m in set(merged["method_id"])]
                for method_id in qmethods:
                    df = merged[merged["method_id"] == method_id].sort_values("response_market_time")
                    plt.figure(figsize=(13, 4))
                    plt.plot(truth["response_market_time"], truth["y_orig"], color="black",
                             linewidth=1.5, label="observed")
                    plt.plot(df["response_market_time"], df["pred_orig"], linewidth=1.0, label=method_id)
                    plt.ylabel("Price")
                    plt.xlabel("Response market time")
                    plt.title("Test Fit vs Observed Data: {}".format(method_id))
                    plt.legend(fontsize=8)
                    plt.tight_layout()
                    safe = method_id.replace("/", "_").replace(" ", "_")
                    path = fig_dir / "test_fit_{}.png".format(safe)
                    plt.savefig(path, dpi=160)
                    plt.close()
                    made.append(str(path))

    return {"figures": made}


def main():
    args = parser().parse_args()
    smoke = load_smoke_config(args.smoke_config)
    data_cfg = load_config(smoke["data_config"])
    run_dir = repo_path(args.run_dir or smoke["run"]["output_dir"])
    adapter_dir = repo_path(smoke["adapter"]["output_dir"])
    fold = int(smoke["fold"])
    region = smoke["region"]
    horizons = [int(h) for h in smoke["horizons"]]
    quantiles = [float(q) for q in smoke["quantiles"]]
    y_scaler = load_y_scaler(data_cfg, fold, region)

    rows = {
        split: pd.read_csv(adapter_dir / "rows_{}.csv".format(split))
        for split in ("train", "val", "test")
    }
    for split in rows:
        rows[split] = rows[split].sort_values(["origin_id", "horizon"]).reset_index(drop=True)

    model_pred = pd.read_csv(run_dir / "model_predictions_scaled.csv")
    all_pred = [model_pred]

    price_series = load_scaled_price_series(data_cfg, fold, region)
    train_y = pivot_truth(rows["train"], horizons)
    train_anchors = rows["train"].drop_duplicates("origin_id").sort_values("origin_id")["origin_market_time"].tolist()
    for days, method_id in [(1, "naive1_prev_day"), (3, "naive2_prev3_avg"), (7, "naive3_prev7_avg")]:
        for split in ("val", "test"):
            split_rows = rows[split]
            eval_anchors = split_rows.drop_duplicates("origin_id").sort_values("origin_id")["origin_market_time"].tolist()
            pred = make_naive_quantile_forecast(
                price_series,
                train_anchors,
                train_y,
                eval_anchors,
                horizons,
                quantiles,
                days=days,
            )
            all_pred.append(predictions_frame(method_id, split, split_rows, pred, quantiles))

    pred = pd.concat(all_pred, ignore_index=True)
    pred.to_csv(run_dir / "predictions_with_naive_scaled.csv", index=False)

    metric_rows = []
    horizon_metric_rows = []
    horizon_group_metric_rows = []
    for method_id, method_df in pred.groupby("method_id"):
        for split, split_pred in method_df.groupby("split"):
            truth_scaled = pivot_truth(rows[split], horizons)
            pred_scaled = pivot_predictions(split_pred, horizons, quantiles)
            truth_orig = inverse_scale_y(truth_scaled, y_scaler)
            pred_orig = inverse_scale_y(pred_scaled, y_scaler)
            metrics_scaled = metric_dict(truth_scaled, pred_scaled, quantiles)
            metrics_orig = metric_dict(truth_orig, pred_orig, quantiles)
            metric_rows.append({
                "method_id": method_id,
                "split": split,
                "unit": "scaled",
                **metrics_scaled,
            })
            metric_rows.append({
                "method_id": method_id,
                "split": split,
                "unit": "original",
                **metrics_orig,
            })
            for h_idx, horizon in enumerate(horizons):
                scaled_h = metric_dict(truth_scaled[:, [h_idx]], pred_scaled[:, [h_idx], :], quantiles)
                orig_h = metric_dict(truth_orig[:, [h_idx]], pred_orig[:, [h_idx], :], quantiles)
                horizon_metric_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "unit": "scaled",
                    "horizon": int(horizon),
                    **scaled_h,
                })
                horizon_metric_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "unit": "original",
                    "horizon": int(horizon),
                    **orig_h,
                })
            for group in sorted({horizon_group_label(h) for h in horizons}):
                idx = [i for i, h in enumerate(horizons) if horizon_group_label(h) == group]
                if not idx:
                    continue
                scaled_g = metric_dict(truth_scaled[:, idx], pred_scaled[:, idx, :], quantiles)
                orig_g = metric_dict(truth_orig[:, idx], pred_orig[:, idx, :], quantiles)
                horizon_group_metric_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "unit": "scaled",
                    "horizon_group": group,
                    **scaled_g,
                })
                horizon_group_metric_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "unit": "original",
                    "horizon_group": group,
                    **orig_g,
                })
    metrics = pd.DataFrame(metric_rows).sort_values(["split", "unit", "AQL", "method_id"])
    metrics.to_csv(run_dir / "metric_summary.csv", index=False)
    horizon_metrics = pd.DataFrame(horizon_metric_rows).sort_values(
        ["split", "unit", "horizon", "AQL", "method_id"]
    )
    horizon_metrics.to_csv(run_dir / "metric_by_horizon.csv", index=False)
    horizon_group_metrics = pd.DataFrame(horizon_group_metric_rows).sort_values(
        ["split", "unit", "horizon_group", "AQL", "method_id"]
    )
    horizon_group_metrics.to_csv(run_dir / "metric_by_horizon_group.csv", index=False)

    model_methods = pd.read_csv(run_dir / "model_method_summary.csv")
    exact_path = run_dir / "exact_equivalence.csv"
    exact = pd.read_csv(exact_path) if exact_path.exists() else pd.DataFrame()
    warm_path = run_dir / "warm_start_diagnostics.csv"
    warm = pd.read_csv(warm_path) if warm_path.exists() else pd.DataFrame()
    figure_info = make_cell_figures(run_dir, rows, pred, y_scaler, quantiles)
    with open(run_dir / "figure_manifest.json", "w") as f:
        import json

        json.dump(figure_info, f, indent=2, sort_keys=True)
        f.write("\n")

    report_path = run_dir / "report.md"
    with open(report_path, "w") as f:
        f.write("# PriceFM DESN Model Smoke Report\n\n")
        f.write("Region: `{}`  \nFold: `{}`  \nHorizons: `{}`  \nQuantiles: `{}`\n\n".format(
            region, fold, horizons, quantiles
        ))
        f.write("## Methods\n\n")
        for method_id in sorted(pred["method_id"].unique()):
            f.write("- `{}`\n".format(method_id))
        f.write("\n## Original-Unit Test Metrics\n\n")
        test_orig = metrics[(metrics["split"] == "test") & (metrics["unit"] == "original")]
        f.write(markdown_table(test_orig))
        f.write("\n\n## Exact Chunking Gate\n\n")
        if exact.empty:
            f.write("No exact-equivalence gate was recorded.\n")
        else:
            f.write(markdown_table(exact))
        f.write("\n## Model Fit Summary\n\n")
        f.write(markdown_table(model_methods))
        f.write("\n## Warm-Start Diagnostics\n\n")
        if warm.empty:
            f.write("No warm-start diagnostics were recorded.\n")
        else:
            cols = [
                c for c in [
                    "method_id", "likelihood_family", "tau", "fit_order",
                    "init_source", "init_components", "fallback_used",
                    "converged", "iter",
                ]
                if c in warm.columns
            ]
            f.write(markdown_table(warm[cols]))
        f.write("\n## Diagnostic Figures\n\n")
        figures = figure_info.get("figures", [])
        if figures:
            for path in figures:
                f.write("- `{}`\n".format(path))
        else:
            f.write("_No diagnostic figures were produced._\n")

    summarize(run_dir, {
        "report": str(report_path),
        "metrics": str(run_dir / "metric_summary.csv"),
        "predictions": str(run_dir / "predictions_with_naive_scaled.csv"),
        "figures": figure_info,
        "n_methods": int(pred["method_id"].nunique()),
    })


if __name__ == "__main__":
    main()
