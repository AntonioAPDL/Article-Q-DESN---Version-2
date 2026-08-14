#!/usr/bin/env python3
"""Merge independent PriceFM single-quantile DESN runs into paper-style metrics."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from pathlib import Path

import joblib
import pandas as pd

from pricefm_common import load_config, pricefm_block, repo_path, summarize, write_json
from pricefm_full_run import config_path_value, markdown_table, parse_time_log
from pricefm_metrics import inverse_scale_y, metric_dict, normalize_quantiles


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
REFERENCE_CSV = "application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--reference-csv", default=REFERENCE_CSV)
    p.add_argument("--region", default=None)
    p.add_argument("--fold", type=int, default=None)
    p.add_argument("--require-complete", default="true")
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def load_grid_module():
    spec = importlib.util.spec_from_file_location("pricefm_grid_prepare", GRID_PREP_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_yaml(path):
    import yaml

    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} is missing required file {}".format(context, path))
    return pd.read_csv(path)


def cell_model_dir(run_dir, region, fold):
    return repo_path(run_dir) / "cells" / "region={}".format(region) / "fold={}".format(int(fold)) / "model"


def cell_adapter_dir(run_dir, region, fold):
    return repo_path(run_dir) / "cells" / "region={}".format(region) / "fold={}".format(int(fold)) / "adapter"


def cell_time_log(run_dir, region, fold):
    return repo_path(run_dir) / "logs" / "region={}_fold={}.time.log".format(region, int(fold))


def load_y_scaler(data_cfg, fold, region):
    spec = pricefm_block(data_cfg)
    path = repo_path(
        Path(spec["processed_dir"]) / "scalers" / "fold_{}".format(fold) / "per_region_separate_xy_scalers.joblib"
    )
    scalers = joblib.load(path)
    return scalers[region]["y_scaler"]


def row_identity(rows):
    cols = [c for c in ["split", "origin_id", "horizon", "response_market_time", "y_scaled"] if c in rows.columns]
    return rows.loc[:, cols].sort_values(["origin_id", "horizon"]).reset_index(drop=True)


def assert_same_rows(reference, current, context):
    ref = row_identity(reference)
    cur = row_identity(current)
    if list(ref.columns) != list(cur.columns) or ref.shape != cur.shape or not ref.equals(cur):
        raise ValueError("Row identity mismatch for {}".format(context))


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


def horizon_group_label(horizon):
    horizon = int(horizon)
    start = ((horizon - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return "{}-{}".format(start, end)


def quantile_slug(tau):
    return ("{:.4g}".format(float(tau))).replace(".", "p")


def load_reference(reference_csv, region):
    path = repo_path(reference_csv)
    if not path.exists():
        return pd.DataFrame()
    ref = pd.read_csv(path)
    if "target_country" not in ref.columns:
        return pd.DataFrame()
    ref = ref[ref["target_country"].astype(str) == str(region)].copy()
    if ref.empty:
        return pd.DataFrame()
    ref.insert(0, "method_id", "pricefm_phase1_pretraining_reference")
    ref.insert(1, "split", "test")
    ref.insert(2, "unit", "original")
    ref.insert(3, "reference_scope", "region_level_external_csv")
    ref.insert(4, "benchmark_role", "context_only_not_fold_aligned")
    return ref[[c for c in [
        "method_id", "split", "unit", "reference_scope", "benchmark_role",
        "AQL", "AQCR", "MAE", "RMSE",
    ] if c in ref.columns]]


def resolve_row_scope(full, region_override=None, fold_override=None):
    """Resolve a grid row scope, returning None when an override excludes it."""
    scoped_regions = [str(x) for x in full["scope"]["regions"]]
    scoped_folds = [int(x) for x in full["scope"]["folds"]]

    if region_override is not None:
        local_region = str(region_override)
        if local_region not in scoped_regions:
            return None
    else:
        if len(scoped_regions) != 1:
            raise ValueError("grid row has multiple regions; pass --region explicitly")
        local_region = scoped_regions[0]

    if fold_override is not None:
        local_fold = int(fold_override)
        if local_fold not in scoped_folds:
            return None
    else:
        if len(scoped_folds) != 1:
            raise ValueError("grid row has multiple folds; pass --fold explicitly")
        local_fold = scoped_folds[0]

    return local_region, local_fold


def method_metrics(rows_by_split, pred, horizons, quantiles, y_scaler):
    metric_rows = []
    horizon_rows = []
    group_rows = []
    for method_id, method_df in pred.groupby("method_id"):
        for split, split_pred in method_df.groupby("split"):
            truth_scaled = pivot_truth(rows_by_split[split], horizons)
            pred_scaled = pivot_predictions(split_pred, horizons, quantiles)
            truth_orig = inverse_scale_y(truth_scaled, y_scaler)
            pred_orig = inverse_scale_y(pred_scaled, y_scaler)
            for unit, truth, forecast in [
                ("scaled", truth_scaled, pred_scaled),
                ("original", truth_orig, pred_orig),
            ]:
                metric_rows.append({
                    "method_id": method_id,
                    "split": split,
                    "unit": unit,
                    **metric_dict(truth, forecast, quantiles),
                })
            for h_idx, horizon in enumerate(horizons):
                for unit, truth, forecast in [
                    ("scaled", truth_scaled[:, [h_idx]], pred_scaled[:, [h_idx], :]),
                    ("original", truth_orig[:, [h_idx]], pred_orig[:, [h_idx], :]),
                ]:
                    horizon_rows.append({
                        "method_id": method_id,
                        "split": split,
                        "unit": unit,
                        "horizon": int(horizon),
                        **metric_dict(truth, forecast, quantiles),
                    })
            for group in sorted({horizon_group_label(h) for h in horizons}):
                idx = [i for i, h in enumerate(horizons) if horizon_group_label(h) == group]
                for unit, truth, forecast in [
                    ("scaled", truth_scaled[:, idx], pred_scaled[:, idx, :]),
                    ("original", truth_orig[:, idx], pred_orig[:, idx, :]),
                ]:
                    group_rows.append({
                        "method_id": method_id,
                        "split": split,
                        "unit": unit,
                        "horizon_group": group,
                        **metric_dict(truth, forecast, quantiles),
                    })
    return (
        pd.DataFrame(metric_rows).sort_values(["split", "unit", "AQL", "method_id"]),
        pd.DataFrame(horizon_rows).sort_values(["split", "unit", "horizon", "AQL", "method_id"]),
        pd.DataFrame(group_rows).sort_values(["split", "unit", "horizon_group", "AQL", "method_id"]),
    )


def validate_prediction_coverage(pred, quantiles):
    required = {"method_id", "split", "origin_id", "horizon", "tau", "pred_scaled"}
    missing = required - set(pred.columns)
    if missing:
        raise ValueError("combined predictions are missing columns: {}".format(", ".join(sorted(missing))))
    expected = set(float(x) for x in quantiles)
    rows = []
    for method_id, method_df in pred.groupby("method_id"):
        observed = sorted(float(x) for x in method_df["tau"].unique())
        status = "passed" if set(observed) == expected else "failed"
        rows.append({
            "method_id": method_id,
            "status": status,
            "expected_quantiles": json.dumps(sorted(expected)),
            "observed_quantiles": json.dumps(observed),
        })
    out = pd.DataFrame(rows).sort_values("method_id")
    if not out.empty and not (out["status"] == "passed").all():
        raise ValueError("At least one method is missing one or more quantile predictions")
    duplicate_key = ["method_id", "split", "origin_id", "horizon", "tau"]
    dup = pred.duplicated(duplicate_key)
    if dup.any():
        raise ValueError("combined predictions contain duplicate method/split/origin/horizon/tau rows")
    return out


def collect_quantile_cells(grid_config, require_complete=True, region_override=None, fold_override=None):
    grid_mod = load_grid_module()
    grid = grid_mod.load_grid(grid_config)
    rows = grid_mod.prepare_grid(grid, grid["base"]["generated_root"], write=False)
    if not rows:
        raise ValueError("grid has no experiments")

    pred_parts = []
    exact_parts = []
    method_parts = []
    warm_parts = []
    trace_parts = []
    param_parts = []
    runtime_rows = []
    cell_rows = []
    rows_by_split = {}
    full_rows = []
    data_cfg = None
    all_quantiles = []

    for row in rows:
        full_payload = read_yaml(row["full_config"])
        full = full_payload["pricefm_desn_full"]
        resolved_scope = resolve_row_scope(full, region_override=region_override, fold_override=fold_override)
        if resolved_scope is None:
            continue
        local_region, local_fold = resolved_scope
        full_rows.append(full)
        data_cfg = data_cfg or load_config(full["data_config"])
        q = [float(x) for x in full["scope"]["quantiles"]]
        if len(q) != 1:
            raise ValueError("paper-quantile merge expects one quantile per experiment; {} has {}".format(row["id"], q))
        all_quantiles.extend(q)
        model_dir = cell_model_dir(row["run_dir"], local_region, local_fold)
        adapter_dir = cell_adapter_dir(row["run_dir"], local_region, local_fold)
        complete = (model_dir / "predictions_with_naive_scaled.csv").exists() and (model_dir / "metric_summary.csv").exists()
        cell_rows.append({
            "id": row["id"],
            "tau": q[0],
            "region": local_region,
            "fold": local_fold,
            "complete": bool(complete),
            "model_dir": config_path_value(model_dir),
            "adapter_dir": config_path_value(adapter_dir),
        })
        if require_complete and not complete:
            raise FileNotFoundError("experiment {} is incomplete at {}".format(row["id"], model_dir))
        if not complete:
            continue

        for split in ("val", "test"):
            split_rows = read_csv_required(adapter_dir / "rows_{}.csv".format(split), row["id"])
            split_rows = split_rows.sort_values(["origin_id", "horizon"]).reset_index(drop=True)
            if split in rows_by_split:
                assert_same_rows(rows_by_split[split], split_rows, "{} / {}".format(row["id"], split))
            else:
                rows_by_split[split] = split_rows

        pred = read_csv_required(model_dir / "predictions_with_naive_scaled.csv", row["id"])
        pred["source_experiment_id"] = row["id"]
        pred_parts.append(pred)

        for name, sink in [
            ("exact_equivalence.csv", exact_parts),
            ("model_method_summary.csv", method_parts),
            ("warm_start_diagnostics.csv", warm_parts),
            ("model_trace_summary.csv", trace_parts),
            ("model_parameter_summary.csv", param_parts),
        ]:
            path = model_dir / name
            if path.exists() and path.stat().st_size > 0:
                df = pd.read_csv(path)
                df.insert(0, "tau_cell", q[0])
                df.insert(0, "source_experiment_id", row["id"])
                sink.append(df)

        timing = parse_time_log(cell_time_log(row["run_dir"], local_region, local_fold))
        runtime_rows.append({
            "id": row["id"],
            "tau": q[0],
            "elapsed_wall": timing["elapsed_wall"],
            "max_rss_kb": timing["max_rss_kb"],
        })

    if not full_rows:
        raise ValueError("No grid rows matched the requested region/fold scope")

    quantiles = list(normalize_quantiles(sorted(set(all_quantiles))))
    if len(quantiles) != len(all_quantiles):
        raise ValueError("expected exactly one cell per quantile; got {}".format(all_quantiles))
    if not pred_parts:
        return {
            "grid": grid,
            "cells": pd.DataFrame(cell_rows),
            "predictions": pd.DataFrame(),
            "quantiles": quantiles,
            "rows_by_split": rows_by_split,
            "data_cfg": data_cfg,
            "full": full_rows[0],
            "exact": pd.DataFrame(),
            "methods": pd.DataFrame(),
            "warm": pd.DataFrame(),
            "trace": pd.DataFrame(),
            "parameters": pd.DataFrame(),
            "runtime": pd.DataFrame(runtime_rows),
        }

    pred = pd.concat(pred_parts, ignore_index=True)
    pred["tau"] = pred["tau"].astype(float)
    return {
        "grid": grid,
        "cells": pd.DataFrame(cell_rows),
        "predictions": pred,
        "quantiles": quantiles,
        "rows_by_split": rows_by_split,
        "data_cfg": data_cfg,
        "full": full_rows[0],
        "exact": pd.concat(exact_parts, ignore_index=True) if exact_parts else pd.DataFrame(),
        "methods": pd.concat(method_parts, ignore_index=True) if method_parts else pd.DataFrame(),
        "warm": pd.concat(warm_parts, ignore_index=True) if warm_parts else pd.DataFrame(),
        "trace": pd.concat(trace_parts, ignore_index=True) if trace_parts else pd.DataFrame(),
        "parameters": pd.concat(param_parts, ignore_index=True) if param_parts else pd.DataFrame(),
        "runtime": pd.DataFrame(runtime_rows),
    }


def make_figures(out_dir, metrics, horizon_group, reference, region, fold):
    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        return {"figures_skipped": "matplotlib unavailable: {}".format(exc)}

    made = []
    test_orig = metrics[(metrics["split"] == "test") & (metrics["unit"] == "original")].copy()
    if not test_orig.empty:
        plot_df = test_orig.sort_values("AQL")
        plt.figure(figsize=(11, 5))
        plt.bar(plot_df["method_id"], plot_df["AQL"], label="DESN")
        if not reference.empty and "AQL" in reference.columns:
            plt.axhline(
                float(reference["AQL"].iloc[0]),
                color="crimson",
                linestyle="--",
                label="PriceFM region reference",
            )
        plt.xticks(rotation=40, ha="right")
        plt.ylabel("AQL")
        plt.title("{} Fold-{} Seven-Quantile Test AQL".format(region, int(fold)))
        plt.legend(fontsize=8)
        plt.tight_layout()
        path = fig_dir / "test_aql_vs_pricefm_reference.png"
        plt.savefig(path, dpi=160)
        plt.close()
        made.append(str(path))

        for metric in ["MAE", "RMSE", "AQCR"]:
            if metric not in plot_df.columns:
                continue
            plt.figure(figsize=(11, 5))
            plt.bar(plot_df["method_id"], plot_df[metric])
            if metric in reference.columns and not reference.empty:
                plt.axhline(
                    float(reference[metric].iloc[0]),
                    color="crimson",
                    linestyle="--",
                    label="PriceFM region reference",
                )
                plt.legend(fontsize=8)
            plt.xticks(rotation=40, ha="right")
            plt.ylabel(metric)
            plt.title("{} Fold-{} Seven-Quantile Test {}".format(region, int(fold), metric))
            plt.tight_layout()
            path = fig_dir / "test_{}_vs_pricefm_reference.png".format(metric.lower())
            plt.savefig(path, dpi=160)
            plt.close()
            made.append(str(path))

    hg = horizon_group[(horizon_group["split"] == "test") & (horizon_group["unit"] == "original")].copy()
    if not hg.empty:
        best = test_orig.sort_values("AQL")["method_id"].head(4).tolist()
        hg = hg[hg["method_id"].isin(best)]
        if not hg.empty:
            piv = hg.pivot_table(index="horizon_group", columns="method_id", values="AQL", aggfunc="first")
            piv.plot(kind="bar", figsize=(11, 5))
            plt.ylabel("AQL")
            plt.title("Test AQL By Horizon Group")
            plt.xticks(rotation=0)
            plt.tight_layout()
            path = fig_dir / "test_aql_by_horizon_group_top_methods.png"
            plt.savefig(path, dpi=160)
            plt.close()
            made.append(str(path))
    return {"figures": made}


def write_report(out_dir, payload, metrics, horizon_group, coverage, reference, figures, region, fold):
    path = out_dir / "paper_quantile_report.md"
    cells = payload["cells"]
    completed = int(cells["complete"].sum()) if not cells.empty else 0
    total = int(len(cells))
    test_orig = metrics[(metrics["split"] == "test") & (metrics["unit"] == "original")].copy()
    with open(path, "w") as f:
        f.write("# PriceFM {} Fold-{} Paper-Quantile DESN Report\n\n".format(region, int(fold)))
        f.write("Cells complete: `{}` / `{}`  \n".format(completed, total))
        f.write("Quantiles: `{}`  \n".format([float(x) for x in payload["quantiles"]]))
        f.write("Grid: `{}`\n\n".format(payload["grid"]["grid_id"]))
        f.write("## Test Original-Unit Metrics\n\n")
        cols = [c for c in ["method_id", "AQL", "AQCR", "MAE", "RMSE"] if c in test_orig.columns]
        f.write(markdown_table(test_orig[cols].sort_values("AQL").to_dict("records"), cols))
        f.write("\n## PriceFM Region-Level Reference\n\n")
        if reference.empty:
            f.write("_No local PriceFM reference row was found._\n\n")
        else:
            ref_cols = [c for c in [
                "method_id", "reference_scope", "benchmark_role", "AQL", "MAE", "RMSE",
            ] if c in reference.columns]
            f.write(markdown_table(reference[ref_cols].to_dict("records"), ref_cols))
            f.write("\n")
            f.write(
                "This row comes from the external region-level PriceFM result CSV. "
                "It is useful context, but it is not the authoritative fold-aligned "
                "benchmark. Use `18_compare_pricefm_phase1_desn_quantiles.py` outputs "
                "for apples-to-apples fold comparisons.\n\n"
            )
        f.write("## Quantile Coverage\n\n")
        f.write(markdown_table(coverage.to_dict("records"), list(coverage.columns)))
        f.write("\n## Figures\n\n")
        for fig in figures.get("figures", []):
            f.write("- `{}`\n".format(fig))
        if not figures.get("figures"):
            f.write("_No figures were produced._\n")
        f.write("\n## Notes\n\n")
        f.write("- Each quantile was run as an independent single-core cell for parallel scheduling.\n")
        f.write("- The merged AQL uses the seven PriceFM tutorial quantiles.\n")
        f.write("- Median MAE/RMSE use the tau=0.50 cell.\n")
        f.write("- Cross-quantile warm starts are intentionally disabled by this cell decomposition.\n")
        f.write("- Fold-aligned PriceFM comparisons are produced separately by script `18`.\n")
    return path


def complete_summary_payload(out_dir, payload, report):
    return {
        "status": "complete",
        "grid_id": payload["grid"]["grid_id"],
        "completed_cells": int(payload["cells"]["complete"].sum()),
        "total_cells": int(len(payload["cells"])),
        "report": str(report),
        "metrics": str(out_dir / "paper_quantile_metric_summary.csv"),
        "reference": str(out_dir / "pricefm_reference_comparison.csv"),
    }


def main():
    args = parser().parse_args()
    require_complete = parse_bool(args.require_complete)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    payload = collect_quantile_cells(
        args.grid_config,
        require_complete=require_complete,
        region_override=args.region,
        fold_override=args.fold,
    )
    payload["cells"].to_csv(out_dir / "quantile_cell_status.csv", index=False)
    payload["runtime"].to_csv(out_dir / "quantile_cell_runtime.csv", index=False)
    payload["exact"].to_csv(out_dir / "exact_equivalence_by_quantile.csv", index=False)
    payload["methods"].to_csv(out_dir / "method_summary_by_quantile.csv", index=False)
    payload["warm"].to_csv(out_dir / "warm_start_diagnostics_by_quantile.csv", index=False)
    payload["parameters"].to_csv(out_dir / "parameter_summary_by_quantile.csv", index=False)
    payload["trace"].to_csv(out_dir / "trace_summary_by_quantile.csv", index=False)

    if payload["predictions"].empty:
        write_json(out_dir / "summary.json", {
            "status": "incomplete",
            "grid_id": payload["grid"]["grid_id"],
            "completed_cells": 0,
            "total_cells": int(len(payload["cells"])),
        })
        return

    coverage = validate_prediction_coverage(payload["predictions"], payload["quantiles"])
    coverage.to_csv(out_dir / "quantile_coverage.csv", index=False)
    payload["predictions"].to_csv(out_dir / "combined_predictions_scaled.csv", index=False)

    horizons = sorted(int(x) for x in payload["rows_by_split"]["test"]["horizon"].unique())
    first_full = payload["full"]
    region = str(args.region or first_full["scope"]["regions"][0])
    fold = int(args.fold or first_full["scope"]["folds"][0])
    y_scaler = load_y_scaler(payload["data_cfg"], fold, region)
    metrics, horizon_metrics, horizon_group = method_metrics(
        payload["rows_by_split"],
        payload["predictions"],
        horizons,
        payload["quantiles"],
        y_scaler,
    )
    metrics.to_csv(out_dir / "paper_quantile_metric_summary.csv", index=False)
    horizon_metrics.to_csv(out_dir / "paper_quantile_metric_by_horizon.csv", index=False)
    horizon_group.to_csv(out_dir / "paper_quantile_metric_by_horizon_group.csv", index=False)

    reference = load_reference(args.reference_csv, region)
    reference.to_csv(out_dir / "pricefm_reference_comparison.csv", index=False)
    figures = make_figures(out_dir, metrics, horizon_group, reference, region, fold)
    with open(out_dir / "figure_manifest.json", "w") as f:
        json.dump(figures, f, indent=2, sort_keys=True)
        f.write("\n")
    report = write_report(out_dir, payload, metrics, horizon_group, coverage, reference, figures, region, fold)
    summary_payload = complete_summary_payload(out_dir, payload, report)
    write_json(out_dir / "summary.json", summary_payload)
    summarize(out_dir, summary_payload)


if __name__ == "__main__":
    main()
