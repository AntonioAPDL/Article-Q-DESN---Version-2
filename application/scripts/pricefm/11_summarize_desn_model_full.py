#!/usr/bin/env python3
"""Aggregate completed cells from the full PriceFM DESN comparison."""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from pricefm_common import load_config, repo_path, summarize
from pricefm_full_run import (
    cell_paths,
    iter_cells,
    load_full_config,
    markdown_table,
    parse_time_log,
    resolve_folds,
    resolve_regions,
)


METRIC_COLUMNS = ["AQL", "AQCR", "MAE", "RMSE"]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_desn_model_full.yaml")
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    return p


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in ("", "all"):
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def read_csv_if_exists(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    return pd.read_csv(path)


def collect_cells(full_cfg, data_cfg, regions=None, folds=None):
    metric_rows = []
    horizon_rows = []
    group_rows = []
    method_rows = []
    exact_rows = []
    warm_rows = []
    runtime_rows = []
    status_rows = []
    for region, fold in iter_cells(full_cfg, data_cfg, regions=regions, folds=folds):
        paths = cell_paths(full_cfg, region, fold)
        model = paths["model"]
        completed = (model / "metric_summary.csv").exists()
        status_rows.append({
            "region": region,
            "fold": int(fold),
            "completed": bool(completed),
            "model_dir": str(model),
        })
        for filename, sink in [
            ("metric_summary.csv", metric_rows),
            ("metric_by_horizon.csv", horizon_rows),
            ("metric_by_horizon_group.csv", group_rows),
            ("model_method_summary.csv", method_rows),
            ("exact_equivalence.csv", exact_rows),
            ("warm_start_diagnostics.csv", warm_rows),
        ]:
            df = read_csv_if_exists(model / filename)
            if df is None:
                continue
            df.insert(0, "fold", int(fold))
            df.insert(0, "region", region)
            sink.append(df)
        timing = parse_time_log(paths["model_time"])
        runtime_rows.append({
            "region": region,
            "fold": int(fold),
            "elapsed_wall": timing["elapsed_wall"],
            "max_rss_kb": timing["max_rss_kb"],
        })
    return {
        "status": pd.DataFrame(status_rows),
        "metrics": pd.concat(metric_rows, ignore_index=True) if metric_rows else pd.DataFrame(),
        "horizon": pd.concat(horizon_rows, ignore_index=True) if horizon_rows else pd.DataFrame(),
        "horizon_group": pd.concat(group_rows, ignore_index=True) if group_rows else pd.DataFrame(),
        "methods": pd.concat(method_rows, ignore_index=True) if method_rows else pd.DataFrame(),
        "exact": pd.concat(exact_rows, ignore_index=True) if exact_rows else pd.DataFrame(),
        "warm": pd.concat(warm_rows, ignore_index=True) if warm_rows else pd.DataFrame(),
        "runtime": pd.DataFrame(runtime_rows),
    }


def numeric_mean(df, group_cols):
    if df.empty:
        return df
    cols = [c for c in METRIC_COLUMNS if c in df.columns]
    return df.groupby(group_cols, as_index=False)[cols].mean()


def method_rankings(macro):
    if macro.empty:
        return macro
    out = macro[(macro["split"] == "test") & (macro["unit"] == "original")].copy()
    if out.empty:
        return out
    out["rank_AQL"] = out["AQL"].rank(method="min", ascending=True)
    out["rank_RMSE"] = out["RMSE"].rank(method="min", ascending=True)
    return out.sort_values(["rank_AQL", "method_id"])


def make_figures(out_dir, macro, horizon_group, runtime):
    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        return {"figures_skipped": "matplotlib unavailable: {}".format(exc)}

    made = []
    if macro.empty or not {"split", "unit", "method_id", "AQL"}.issubset(macro.columns):
        test_orig = pd.DataFrame()
    else:
        test_orig = macro[(macro["split"] == "test") & (macro["unit"] == "original")].copy()
    if not test_orig.empty:
        test_orig = test_orig.sort_values("AQL")
        plt.figure(figsize=(10, 5))
        plt.bar(test_orig["method_id"], test_orig["AQL"])
        plt.xticks(rotation=45, ha="right")
        plt.ylabel("AQL")
        plt.title("PriceFM Full DESN Test AQL")
        plt.tight_layout()
        path = fig_dir / "test_aql_by_method.png"
        plt.savefig(path, dpi=160)
        plt.close()
        made.append(str(path))

        plt.figure(figsize=(10, 5))
        plt.bar(test_orig["method_id"], test_orig["AQCR"])
        plt.xticks(rotation=45, ha="right")
        plt.ylabel("AQCR")
        plt.title("PriceFM Full DESN Test Quantile Crossing")
        plt.tight_layout()
        path = fig_dir / "test_aqcr_by_method.png"
        plt.savefig(path, dpi=160)
        plt.close()
        made.append(str(path))

    if horizon_group.empty or not {"split", "unit", "horizon_group", "method_id", "AQL"}.issubset(horizon_group.columns):
        hg = pd.DataFrame()
    else:
        hg = horizon_group[(horizon_group["split"] == "test") & (horizon_group["unit"] == "original")].copy()
    if not hg.empty:
        for group, df in hg.groupby("horizon_group"):
            df = df.sort_values("AQL")
            plt.figure(figsize=(10, 5))
            plt.bar(df["method_id"], df["AQL"])
            plt.xticks(rotation=45, ha="right")
            plt.ylabel("AQL")
            plt.title("Test AQL, Horizons {}".format(group))
            plt.tight_layout()
            path = fig_dir / "test_aql_horizon_group_{}.png".format(str(group).replace("-", "_"))
            plt.savefig(path, dpi=160)
            plt.close()
            made.append(str(path))

    if not runtime.empty and "max_rss_kb" in runtime.columns:
        rt = runtime[pd.to_numeric(runtime["max_rss_kb"], errors="coerce").notna()].copy()
        if not rt.empty:
            rt["max_rss_mb"] = pd.to_numeric(rt["max_rss_kb"], errors="coerce") / 1024.0
            plt.figure(figsize=(10, 5))
            plt.hist(rt["max_rss_mb"], bins=20)
            plt.xlabel("Max RSS (MB)")
            plt.ylabel("Cells")
            plt.title("Per-Cell Memory Distribution")
            plt.tight_layout()
            path = fig_dir / "cell_memory_histogram.png"
            plt.savefig(path, dpi=160)
            plt.close()
            made.append(str(path))
    return {"figures": made}


def write_report(out_dir, payload):
    status = payload["status"]
    metrics = payload["metrics"]
    macro = payload["macro"]
    rankings = payload["rankings"]
    exact = payload["exact"]
    warm = payload["warm"]
    runtime = payload["runtime"]
    path = out_dir / "pricefm_desn_full_report.md"
    completed = int(status["completed"].sum()) if not status.empty else 0
    total = int(len(status))
    with open(path, "w") as f:
        f.write("# PriceFM DESN Full Comparison Report\n\n")
        f.write("Completed cells: `{}` / `{}`\n\n".format(completed, total))
        f.write("## Test Original-Unit Macro Rankings\n\n")
        if rankings.empty:
            f.write("_No completed metrics yet._\n\n")
        else:
            cols = ["method_id", "AQL", "AQCR", "MAE", "RMSE", "rank_AQL"]
            f.write(markdown_table(rankings[cols].to_dict("records"), cols))
            f.write("\n")
        f.write("## Exact Equivalence\n\n")
        if exact.empty:
            f.write("_No exact-equivalence rows yet._\n\n")
        else:
            cols = [c for c in ["region", "fold", "likelihood_family", "prior_family", "tau",
                                "beta_mean_max_abs_diff", "beta_cov_max_abs_diff",
                                "train_prediction_max_abs_diff", "tolerance", "passed"] if c in exact.columns]
            f.write(markdown_table(exact[cols].head(30).to_dict("records"), cols))
            f.write("\n")
        f.write("## Runtime\n\n")
        if runtime.empty:
            f.write("_No runtime rows yet._\n")
        else:
            f.write("Runtime rows: `{}`\n\n".format(len(runtime)))
            if "max_rss_kb" in runtime.columns:
                rss = pd.to_numeric(runtime["max_rss_kb"], errors="coerce")
                if rss.notna().any():
                    f.write("Max observed RSS: `{:.1f} MB`\n\n".format(rss.max() / 1024.0))
        f.write("## Warm-Start Diagnostics\n\n")
        if warm.empty:
            f.write("_No warm-start diagnostic rows yet._\n\n")
        else:
            cols = [c for c in ["region", "fold", "method_id", "likelihood_family", "tau",
                                "init_source", "init_components", "fallback_used",
                                "converged", "iter"] if c in warm.columns]
            f.write(markdown_table(warm[cols].head(30).to_dict("records"), cols))
            f.write("\n")
        f.write("## Notes\n\n")
        f.write("- Metrics are macro-averaged across completed region/fold cells.\n")
        f.write("- Generated row-level outputs remain under ignored local paths.\n")
        f.write("- Incomplete cells are explicit in `cell_completion_summary.csv`.\n")
    return path


def main():
    args = parser().parse_args()
    full_cfg = load_full_config(args.config)
    data_cfg = load_config(full_cfg["data_config"])
    regions = parse_csv(args.regions, str)
    folds = parse_csv(args.folds, int)
    # Validate overrides early.
    resolve_regions(full_cfg, data_cfg, regions)
    resolve_folds(full_cfg, data_cfg, folds)

    out_dir = repo_path(full_cfg["run"]["output_dir"])
    summary_dir = out_dir / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)

    payload = collect_cells(full_cfg, data_cfg, regions=regions, folds=folds)
    payload["metrics"].to_csv(summary_dir / "metric_summary_all_cells.csv", index=False)
    payload["horizon"].to_csv(summary_dir / "metric_by_horizon_all_cells.csv", index=False)
    payload["horizon_group"].to_csv(summary_dir / "metric_by_horizon_group_all_cells.csv", index=False)
    payload["methods"].to_csv(summary_dir / "method_summary_all_cells.csv", index=False)
    payload["exact"].to_csv(summary_dir / "exact_equivalence_summary.csv", index=False)
    payload["warm"].to_csv(summary_dir / "warm_start_diagnostics_all_cells.csv", index=False)
    payload["runtime"].to_csv(summary_dir / "runtime_summary.csv", index=False)
    payload["status"].to_csv(summary_dir / "cell_completion_summary.csv", index=False)

    macro = numeric_mean(payload["metrics"], ["method_id", "split", "unit"])
    macro.to_csv(summary_dir / "metric_summary_macro.csv", index=False)
    horizon_macro = numeric_mean(payload["horizon"], ["method_id", "split", "unit", "horizon"])
    horizon_macro.to_csv(summary_dir / "metric_by_horizon_macro.csv", index=False)
    group_macro = numeric_mean(payload["horizon_group"], ["method_id", "split", "unit", "horizon_group"])
    group_macro.to_csv(summary_dir / "metric_by_horizon_group_macro.csv", index=False)
    rankings = method_rankings(macro)
    rankings.to_csv(summary_dir / "method_rankings.csv", index=False)
    aqcr = macro[["method_id", "split", "unit", "AQCR"]] if not macro.empty else pd.DataFrame()
    aqcr.to_csv(summary_dir / "quantile_crossing_summary.csv", index=False)

    payload.update({"macro": macro, "rankings": rankings})
    fig_info = make_figures(summary_dir, macro, group_macro, payload["runtime"])
    with open(summary_dir / "figure_manifest.json", "w") as f:
        import json

        json.dump(fig_info, f, indent=2, sort_keys=True)
        f.write("\n")
    report = write_report(summary_dir, payload)
    summarize(summary_dir, {
        "report": str(report),
        "completed_cells": int(payload["status"]["completed"].sum()) if not payload["status"].empty else 0,
        "total_cells": int(len(payload["status"])),
    })


if __name__ == "__main__":
    main()
