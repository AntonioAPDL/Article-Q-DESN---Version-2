#!/usr/bin/env python3
"""Plot diagnostics for merged PriceFM paper-quantile DESN runs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import yaml

from pricefm_common import load_config, pricefm_block, repo_path, write_json
from pricefm_metrics import inverse_scale_y


DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_fold1_paper_quantiles_authoritative_20260602"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--max-origins", type=int, default=120)
    p.add_argument("--horizon", type=int, default=1)
    return p


def read_csv(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(path)


def load_cell_config(cell_status):
    if cell_status.empty:
        raise ValueError("quantile_cell_status.csv is empty")
    adapter_dir = repo_path(cell_status.sort_values("tau")["adapter_dir"].iloc[0])
    cfg_path = adapter_dir.parent / "config.yaml"
    with open(cfg_path, "r") as f:
        return yaml.safe_load(f)["pricefm_desn_smoke"], cfg_path


def load_y_scaler(data_cfg, fold, region):
    spec = pricefm_block(data_cfg)
    path = repo_path(
        Path(spec["processed_dir"])
        / "scalers"
        / "fold_{}".format(int(fold))
        / "per_region_separate_xy_scalers.joblib"
    )
    scalers = joblib.load(path)
    return scalers[region]["y_scaler"]


def load_rows(cell_status, split):
    adapter_dir = repo_path(cell_status.sort_values("tau")["adapter_dir"].iloc[0])
    rows = pd.read_csv(adapter_dir / "rows_{}.csv".format(split))
    rows["response_market_time"] = pd.to_datetime(rows["response_market_time"], utc=True)
    return rows.sort_values(["origin_id", "horizon"]).reset_index(drop=True)


def quantile_columns(frame):
    return sorted(float(x) for x in frame["tau"].dropna().unique())


def pivot_method_horizon(pred, rows, method_id, horizon, quantiles, y_scaler, max_origins):
    base = rows[rows["horizon"].astype(int) == int(horizon)].copy()
    base = base.sort_values("origin_id").head(int(max_origins))
    sub = pred[
        (pred["method_id"] == method_id)
        & (pred["split"] == "test")
        & (pred["horizon"].astype(int) == int(horizon))
        & (pred["origin_id"].isin(base["origin_id"]))
    ].copy()
    piv = sub.pivot_table(index="origin_id", columns="tau", values="pred_scaled", aggfunc="first")
    piv = piv.reindex(base["origin_id"]).loc[:, quantiles]
    out = base[["origin_id", "response_market_time", "y_scaled"]].copy()
    out["y_orig"] = inverse_scale_y(out["y_scaled"].to_numpy(), y_scaler)
    for tau in quantiles:
        out[tau] = inverse_scale_y(piv[tau].to_numpy(), y_scaler)
    return out


def plot_quantile_fans(pred, rows, y_scaler, out_dir, region, fold, horizon=1, max_origins=120):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    quantiles = quantile_columns(pred)
    methods = [
        "qdesn_exal_rhs_ns_exact_chunked",
        "qdesn_al_rhs_ns_exact_chunked",
        "normal_rhs_ns",
        "normal_scaled_ridge",
        "naive1_prev_day",
        "naive2_prev3_avg",
        "naive3_prev7_avg",
    ]
    methods = [m for m in methods if m in set(pred["method_id"])]
    fig_dir = out_dir / "figures" / "paper_quantile_diagnostics"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []

    nrows = len(methods)
    fig, axes = plt.subplots(nrows, 1, figsize=(15, max(4, 3.0 * nrows)), sharex=True)
    if nrows == 1:
        axes = [axes]
    for ax, method_id in zip(axes, methods):
        df = pivot_method_horizon(pred, rows, method_id, horizon, quantiles, y_scaler, max_origins)
        x = df["response_market_time"]
        ax.plot(x, df["y_orig"], color="black", linewidth=1.5, label="observed")
        if 0.1 in quantiles and 0.9 in quantiles:
            ax.fill_between(x, df[0.1], df[0.9], color="#93c5fd", alpha=0.28, label="0.10-0.90")
        if 0.25 in quantiles and 0.75 in quantiles:
            ax.fill_between(x, df[0.25], df[0.75], color="#2563eb", alpha=0.20, label="0.25-0.75")
        for tau in quantiles:
            if abs(tau - 0.5) < 1.0e-12:
                ax.plot(x, df[tau], color="#dc2626", linewidth=1.5, label="0.50")
            else:
                ax.plot(x, df[tau], color="#2563eb", linewidth=0.7, alpha=0.65)
        ax.set_title(method_id)
        ax.set_ylabel("Price")
        ax.grid(alpha=0.18)
    axes[0].legend(fontsize=8, ncol=4, loc="best")
    axes[-1].set_xlabel("Response market time")
    fig.suptitle(
        "{} Fold-{} Test Quantile Fans, Horizon {}".format(region, int(fold), int(horizon)),
        y=0.995,
    )
    fig.tight_layout(rect=[0.0, 0.0, 1.0, 0.975])
    path = fig_dir / "test_quantile_fans_all_methods_h{:02d}.png".format(int(horizon))
    fig.savefig(path, dpi=170)
    plt.close(fig)
    made.append(str(path))

    winner = "qdesn_exal_rhs_ns_exact_chunked"
    if winner in set(pred["method_id"]):
        horizons = [1, 24, 48, 96]
        fig, axes = plt.subplots(len(horizons), 1, figsize=(15, 12), sharex=False)
        for ax, h in zip(axes, horizons):
            df = pivot_method_horizon(pred, rows, winner, h, quantiles, y_scaler, max_origins)
            x = df["response_market_time"]
            ax.plot(x, df["y_orig"], color="black", linewidth=1.5, label="observed")
            ax.fill_between(x, df[0.1], df[0.9], color="#93c5fd", alpha=0.28)
            ax.fill_between(x, df[0.25], df[0.75], color="#2563eb", alpha=0.20)
            ax.plot(x, df[0.5], color="#dc2626", linewidth=1.5, label="0.50")
            ax.set_title("{}: horizon {}".format(winner, h))
            ax.set_ylabel("Price")
            ax.grid(alpha=0.18)
        axes[0].legend(fontsize=8, ncol=3, loc="best")
        axes[-1].set_xlabel("Response market time")
        fig.suptitle("Winner Quantile Fans Across Forecast Horizons", y=0.995)
        fig.tight_layout(rect=[0.0, 0.0, 1.0, 0.975])
        path = fig_dir / "winner_quantile_fans_h001_h024_h048_h096.png"
        fig.savefig(path, dpi=170)
        plt.close(fig)
        made.append(str(path))
    return made


def finite_trace(trace, value_col):
    if trace.empty or value_col not in trace.columns:
        return pd.DataFrame()
    out = trace.copy()
    out[value_col] = pd.to_numeric(out[value_col], errors="coerce")
    out["iter"] = pd.to_numeric(out["iter"], errors="coerce")
    out["tau_cell"] = pd.to_numeric(out["tau_cell"], errors="coerce")
    return out[out[value_col].notna() & out["iter"].notna() & out["tau_cell"].notna()].copy()


def plot_trace_grid(trace, value_col, out_dir, title=None, y_label=None):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    df = finite_trace(trace, value_col)
    if df.empty:
        return None
    methods = sorted(df["method_id"].dropna().unique())
    nrows = len(methods)
    fig, axes = plt.subplots(nrows, 1, figsize=(12, max(4, 3.0 * nrows)), sharex=True)
    if nrows == 1:
        axes = [axes]
    cmap = plt.get_cmap("viridis")
    taus = sorted(df["tau_cell"].unique())
    colors = {tau: cmap(i / max(1, len(taus) - 1)) for i, tau in enumerate(taus)}
    for ax, method_id in zip(axes, methods):
        sub = df[df["method_id"] == method_id]
        for tau in taus:
            tdf = sub[sub["tau_cell"] == tau].sort_values("iter")
            if tdf.empty:
                continue
            ax.plot(tdf["iter"], tdf[value_col], linewidth=1.2, color=colors[tau], label="{:.2g}".format(tau))
        ax.set_title(method_id)
        ax.set_ylabel(y_label or value_col)
        ax.grid(alpha=0.22)
    axes[0].legend(title="tau", fontsize=8, ncol=min(len(taus), 7), loc="best")
    axes[-1].set_xlabel("VB iteration")
    fig.suptitle(title or "{} Trace".format(value_col), y=0.995)
    fig.tight_layout(rect=[0.0, 0.0, 1.0, 0.970])
    fig_dir = out_dir / "figures" / "paper_quantile_diagnostics"
    fig_dir.mkdir(parents=True, exist_ok=True)
    path = fig_dir / "trace_{}.png".format(value_col)
    fig.savefig(path, dpi=170)
    plt.close(fig)
    return str(path)


def plot_final_parameter_summary(params, out_dir):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if params.empty:
        return []
    fig_dir = out_dir / "figures" / "paper_quantile_diagnostics"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []
    value_cols = [
        col for col in ["beta_l2", "beta_max_abs", "beta_cov_trace", "sigma", "gamma", "omega2"]
        if col in params.columns and pd.to_numeric(params[col], errors="coerce").notna().any()
    ]
    if not value_cols:
        return made
    for col in value_cols:
        df = params.copy()
        df[col] = pd.to_numeric(df[col], errors="coerce")
        df = df[df[col].notna()]
        if df.empty:
            continue
        fig, ax = plt.subplots(figsize=(12, 5))
        for method_id, sub in df.groupby("method_id"):
            sub = sub.sort_values("tau_cell")
            ax.plot(sub["tau_cell"], sub[col], marker="o", linewidth=1.2, label=method_id)
        ax.set_xlabel("tau")
        ax.set_ylabel(col)
        ax.set_title("Final {} By Quantile".format(col))
        ax.grid(alpha=0.22)
        ax.legend(fontsize=8, ncol=2)
        fig.tight_layout()
        path = fig_dir / "final_{}_by_tau.png".format(col)
        fig.savefig(path, dpi=170)
        plt.close(fig)
        made.append(str(path))
    return made


def main():
    args = parser().parse_args()
    out_dir = repo_path(args.output_dir)
    cell_status = read_csv(out_dir / "quantile_cell_status.csv")
    pred = read_csv(out_dir / "combined_predictions_scaled.csv")
    trace = read_csv(out_dir / "trace_summary_by_quantile.csv")
    params = read_csv(out_dir / "parameter_summary_by_quantile.csv")
    if pred.empty:
        raise ValueError("combined_predictions_scaled.csv is missing or empty")
    cfg, cfg_path = load_cell_config(cell_status)
    data_cfg = load_config(cfg["data_config"])
    region = str(cfg["region"])
    fold = int(cfg["fold"])
    y_scaler = load_y_scaler(data_cfg, fold, region)
    rows_test = load_rows(cell_status, "test")

    figures = []
    figures.extend(plot_quantile_fans(
        pred,
        rows_test,
        y_scaler,
        out_dir,
        region=region,
        fold=fold,
        horizon=int(args.horizon),
        max_origins=int(args.max_origins),
    ))
    for value_col, title, label in [
        ("elbo", "VB Objective / ELBO Traces By Quantile", "ELBO / objective"),
        ("sigma", "Sigma Traces By Quantile", "sigma"),
        ("gamma", "Gamma Traces By Quantile", "gamma"),
        ("rhs_lambda_mean", "RHS Lambda Mean Traces By Quantile", "rhs lambda mean"),
        ("parameter_change", "Parameter-Change Traces By Quantile", "parameter change"),
    ]:
        path = plot_trace_grid(trace, value_col, out_dir, title=title, y_label=label)
        if path:
            figures.append(path)
    figures.extend(plot_final_parameter_summary(params, out_dir))

    manifest = {
        "source_output_dir": str(out_dir),
        "cell_config": str(cfg_path),
        "region": region,
        "fold": fold,
        "horizon": int(args.horizon),
        "max_origins": int(args.max_origins),
        "figures": figures,
    }
    write_json(out_dir / "paper_quantile_diagnostic_figure_manifest.json", manifest)
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
