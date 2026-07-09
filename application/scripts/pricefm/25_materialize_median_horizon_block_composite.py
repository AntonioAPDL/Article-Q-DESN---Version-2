#!/usr/bin/env python3
"""Materialize PriceFM median horizon-block composites from completed runs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import load_config, pricefm_block, repo_path, write_json
from pricefm_metrics import inverse_scale_y, metric_dict


DEFAULT_SELECTION_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_horizon_block_selection_20260604"
)
DEFAULT_OUTPUT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_de_lu_folds23_horizon_block_composite_materialized_20260604"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--selection-dir", default=DEFAULT_SELECTION_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    p.add_argument("--data-config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--region", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--splits", default="val,test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--method-id", default="horizon_block_median_composite")
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
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def horizon_group_label(horizon):
    horizon = int(horizon)
    start = ((horizon - 1) // 24) * 24 + 1
    end = min(start + 23, 96)
    return "{}-{}".format(start, end)


def block_horizons(label):
    if "-" not in str(label):
        raise ValueError("horizon block must be start-end: {}".format(label))
    start, end = [int(x) for x in str(label).split("-", 1)]
    if start < 1 or end < start:
        raise ValueError("invalid horizon block: {}".format(label))
    return list(range(start, end + 1))


def normalize_time_cols(frame):
    out = frame.copy()
    for col in ["origin_market_time", "response_market_time"]:
        if col in out.columns:
            out[col] = pd.to_datetime(out[col], utc=True).dt.strftime("%Y-%m-%dT%H:%M:%S%z")
            out[col] = out[col].str.replace(r"(\+0000)$", "+00:00", regex=True)
    return out


def adapter_dir_for_model(model_dir):
    model_dir = repo_path(model_dir)
    if model_dir.name != "model":
        raise ValueError("model_dir must end in 'model': {}".format(model_dir))
    return model_dir.parent / "adapter"


def load_y_scaler(data_cfg, fold, region):
    import joblib

    spec = pricefm_block(data_cfg)
    path = repo_path(
        Path(spec["processed_dir"])
        / "scalers"
        / "fold_{}".format(int(fold))
        / "per_region_separate_xy_scalers.joblib"
    )
    scalers = joblib.load(path)
    return scalers[str(region)]["y_scaler"]


def load_selected_prediction_rows(selection_row, split):
    model_dir = repo_path(selection_row["model_dir"])
    method_id = str(selection_row["method_id"])
    block = str(selection_row["horizon_group"])
    pred = read_csv_required(model_dir / "model_predictions_scaled.csv", "model predictions")
    pred = pred[
        pred["method_id"].astype(str).eq(method_id)
        & pred["split"].astype(str).eq(str(split))
        & pred["horizon"].astype(int).isin(block_horizons(block))
    ].copy()
    if pred.empty:
        raise ValueError(
            "No prediction rows for method={}, split={}, block={}, model_dir={}".format(
                method_id, split, block, rel_path(model_dir)
            )
        )
    rows = read_csv_required(adapter_dir_for_model(model_dir) / "rows_{}.csv".format(split), "adapter rows")
    rows = rows[rows["horizon"].astype(int).isin(block_horizons(block))].copy()
    rows = normalize_time_cols(rows)
    merged = pred.merge(
        rows[["split", "origin_id", "horizon", "origin_market_time", "response_market_time", "y_scaled"]],
        on=["split", "origin_id", "horizon"],
        how="left",
        validate="many_to_one",
    )
    if merged["y_scaled"].isna().any():
        raise ValueError("Prediction rows failed to align with adapter truth rows.")
    merged["source_method_id"] = method_id
    merged["source_experiment_id"] = selection_row["experiment_id"]
    merged["source_model_dir"] = rel_path(model_dir)
    merged["horizon_group"] = block
    for key in [
        "region", "fold", "stage", "lag_window", "feature_map", "feature_dim",
        "depth", "units", "alpha", "rho", "input_scale", "tau0", "seed",
    ]:
        if key in selection_row:
            merged["source_" + key] = selection_row[key]
    for col in [
        "source_stage", "source_lag_window", "source_feature_map",
        "source_feature_dim", "source_depth", "source_units", "source_alpha",
        "source_rho", "source_input_scale", "source_tau0", "source_seed",
    ]:
        if col not in merged.columns:
            merged[col] = ""
    return merged


def ensure_complete_coverage(frame, expected_blocks):
    if frame.empty:
        raise ValueError("Composite frame is empty.")
    expected_horizons = []
    for block in expected_blocks:
        expected_horizons.extend(block_horizons(block))
    expected_horizons = sorted(set(expected_horizons))
    got_horizons = sorted(int(x) for x in frame["horizon"].unique())
    if got_horizons != expected_horizons:
        raise ValueError("Composite horizon coverage mismatch: got {}, expected {}".format(got_horizons, expected_horizons))
    key = ["split", "origin_market_time", "response_market_time", "horizon", "tau"]
    dup = frame.duplicated(key).sum()
    if dup:
        raise ValueError("Composite has duplicate prediction keys: {}".format(int(dup)))
    counts = frame.groupby(["split", "horizon", "tau"], as_index=False).size()
    for (split, tau), sub in counts.groupby(["split", "tau"]):
        if int(sub["size"].min()) != int(sub["size"].max()):
            raise ValueError("Uneven origin coverage for split={}, tau={}".format(split, tau))
    return counts


def metric_arrays(method_df, quantiles):
    truth = method_df.drop_duplicates(["origin_market_time", "horizon"]).pivot(
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


def compute_metrics(predictions, method_id, y_scalers=None):
    y_scalers = y_scalers or {}
    rows = []
    horizon_rows = []
    group_rows = []
    quantiles = sorted(float(x) for x in predictions["tau"].unique())
    for (region, fold, split), df in predictions.groupby(["region", "fold", "split"]):
        y_scaled, p_scaled, horizons = metric_arrays(df, quantiles)
        unit_payloads = [("scaled", y_scaled, p_scaled)]
        scaler = y_scalers.get((str(region), int(fold)))
        if scaler is not None:
            unit_payloads.append(("original", inverse_scale_y(y_scaled, scaler), inverse_scale_y(p_scaled, scaler)))
        for unit, y, p in unit_payloads:
            rows.append({
                "method_id": method_id,
                "region": region,
                "fold": int(fold),
                "split": split,
                "unit": unit,
                **metric_dict(y, p, quantiles),
            })
            for h_idx, horizon in enumerate(horizons):
                horizon_rows.append({
                    "method_id": method_id,
                    "region": region,
                    "fold": int(fold),
                    "split": split,
                    "unit": unit,
                    "horizon": int(horizon),
                    **metric_dict(y[:, [h_idx]], p[:, [h_idx], :], quantiles),
                })
            for group in sorted({horizon_group_label(h) for h in horizons}):
                idx = [i for i, h in enumerate(horizons) if horizon_group_label(h) == group]
                group_rows.append({
                    "method_id": method_id,
                    "region": region,
                    "fold": int(fold),
                    "split": split,
                    "unit": unit,
                    "horizon_group": group,
                    **metric_dict(y[:, idx], p[:, idx, :], quantiles),
                })
    return (
        pd.DataFrame(rows).sort_values(["region", "fold", "split", "unit"]),
        pd.DataFrame(horizon_rows).sort_values(["region", "fold", "split", "unit", "horizon"]),
        pd.DataFrame(group_rows).sort_values(["region", "fold", "split", "unit", "horizon_group"]),
    )


def materialize(selection, region, folds, splits, method_id):
    selection = selection[
        selection["region"].astype(str).eq(str(region))
        & selection["fold"].astype(int).isin(set(folds))
    ].copy()
    if selection.empty:
        raise ValueError("No horizon-block rows for requested region/folds.")
    rows = []
    audits = []
    for (reg, fold), fold_sel in selection.groupby(["region", "fold"]):
        blocks = sorted(str(x) for x in fold_sel["horizon_group"].unique())
        if len(blocks) != fold_sel.shape[0]:
            raise ValueError("Duplicate selected horizon blocks for region={}, fold={}".format(reg, fold))
        for split in splits:
            pieces = []
            for _, sel_row in fold_sel.sort_values("horizon_group").iterrows():
                pieces.append(load_selected_prediction_rows(sel_row, split))
            combo = pd.concat(pieces, ignore_index=True)
            combo = normalize_time_cols(combo)
            combo["region"] = str(reg)
            combo["fold"] = int(fold)
            combo["method_id"] = str(method_id)
            combo = combo[[
                "method_id", "region", "fold", "split", "origin_id", "origin_market_time",
                "response_market_time", "horizon", "horizon_group", "tau", "pred_scaled",
                "y_scaled", "source_method_id", "source_experiment_id", "source_model_dir",
                "source_stage", "source_lag_window", "source_feature_map",
                "source_feature_dim", "source_depth", "source_units", "source_alpha",
                "source_rho", "source_input_scale", "source_tau0", "source_seed",
            ]]
            coverage = ensure_complete_coverage(combo, blocks)
            audits.append({
                "region": str(reg),
                "fold": int(fold),
                "split": str(split),
                "n_blocks": int(len(blocks)),
                "horizon_min": int(combo["horizon"].min()),
                "horizon_max": int(combo["horizon"].max()),
                "n_horizons": int(combo["horizon"].nunique()),
                "n_quantiles": int(combo["tau"].nunique()),
                "n_prediction_rows": int(combo.shape[0]),
                "origin_count_min": int(coverage["size"].min()),
                "origin_count_max": int(coverage["size"].max()),
                "duplicate_keys": 0,
            })
            rows.append(combo)
    return pd.concat(rows, ignore_index=True), pd.DataFrame(audits)


def compare_to_baseline(metric_summary, baseline_delta, unit, metric):
    base = baseline_delta.copy()
    base = base.rename(columns={
        "metric_role": "role",
        "baseline_{}".format(metric): "baseline_metric",
        "horizon_block_{}".format(metric): "pre_materialized_horizon_block_metric",
        "delta_{}_horizon_block_minus_baseline".format(metric): "pre_materialized_delta",
    })
    role_split = {"selection": "val", "audit": "test"}
    base["split"] = base["role"].map(role_split)
    comp = metric_summary[metric_summary["unit"].astype(str).eq(str(unit))].copy()
    comp = comp.rename(columns={metric: "materialized_horizon_block_metric"})
    merged = base.merge(
        comp[["region", "fold", "split", "materialized_horizon_block_metric"]],
        on=["region", "fold", "split"],
        how="left",
    )
    merged["materialized_delta"] = merged["materialized_horizon_block_metric"] - merged["baseline_metric"]
    merged["materialized_minus_pre_materialized"] = (
        merged["materialized_horizon_block_metric"] - merged["pre_materialized_horizon_block_metric"]
    )
    return merged.sort_values(["region", "fold", "role"]).reset_index(drop=True)


def make_figures(out_dir, comparison):
    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    made = []
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:
        return {"figures_skipped": "matplotlib unavailable: {}".format(exc)}
    if not comparison.empty:
        plot = comparison.copy()
        plot["label"] = plot["region"].astype(str) + " fold " + plot["fold"].astype(str) + " " + plot["role"].astype(str)
        plt.figure(figsize=(10, 5))
        plt.bar(plot["label"], plot["materialized_delta"])
        plt.axhline(0.0, color="black", linewidth=1.0)
        plt.xticks(rotation=35, ha="right")
        plt.ylabel("Composite minus retained AQL")
        plt.title("Materialized Horizon-Block Composite Delta")
        plt.tight_layout()
        path = fig_dir / "materialized_composite_aql_delta.png"
        plt.savefig(path, dpi=160)
        plt.close()
        made.append(rel_path(path))
    return {"figures": made}


def write_report(out_dir, comparison, source_map, audit, figures):
    path = out_dir / "horizon_block_composite_materialization_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Horizon-Block Composite Materialization\n\n")
        f.write("This report materializes validation-selected median horizon-block specialists from completed model outputs. No models are refit.\n\n")
        f.write("## Composite Delta Versus Retained Global Median\n\n")
        if comparison.empty:
            f.write("_No comparison rows._\n\n")
        else:
            cols = [
                "region", "fold", "role", "baseline_metric",
                "materialized_horizon_block_metric", "materialized_delta",
                "materialized_minus_pre_materialized",
            ]
            f.write(markdown_table(comparison[cols]))
            f.write("\n")
        f.write("## Source Map\n\n")
        cols = [c for c in [
            "region", "fold", "horizon_group", "experiment_id", "method_id",
            "stage", "lag_window", "feature_dim", "alpha", "rho", "input_scale",
        ] if c in source_map.columns]
        f.write(markdown_table(source_map[cols]))
        f.write("\n")
        f.write("## Coverage Audit\n\n")
        f.write(markdown_table(audit))
        f.write("\n")
        if figures.get("figures"):
            f.write("## Figures\n\n")
            for fig in figures["figures"]:
                f.write("- `{}`\n".format(fig))
        f.write("\n## Selection Rules\n\n")
        f.write("- Horizon-block sources are selected by validation metrics only.\n")
        f.write("- Test metrics are audit-only.\n")
        f.write("- The composite is a workflow selection rule, not a new inference model.\n")
    return path


def markdown_table(df):
    if df.empty:
        return "_No rows._\n"
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "| " + " | ".join(["---"] * len(cols)) + " |"]
    for _, row in df.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines) + "\n"


def main():
    args = parser().parse_args()
    selection_dir = repo_path(args.selection_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    region = str(args.region)
    folds = parse_csv(args.folds, int)
    splits = parse_csv(args.splits, str)
    selection = read_csv_required(selection_dir / "horizon_block_selection.csv", "horizon-block selection")
    composite, audit = materialize(selection, region, folds, splits, args.method_id)

    data_cfg = load_config(args.data_config)
    y_scalers = {(region, int(fold)): load_y_scaler(data_cfg, fold, region) for fold in folds}
    metric_summary, metric_horizon, metric_group = compute_metrics(composite, args.method_id, y_scalers)
    baseline_delta = read_csv_required(selection_dir / "horizon_block_composite_delta.csv", "horizon-block delta")
    comparison = compare_to_baseline(metric_summary, baseline_delta, args.unit, args.metric)
    source_map = selection[
        selection["region"].astype(str).eq(region)
        & selection["fold"].astype(int).isin(set(folds))
    ].sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)
    figures = make_figures(out_dir, comparison)

    composite.to_csv(out_dir / "horizon_block_composite_predictions_scaled.csv", index=False)
    metric_summary.to_csv(out_dir / "horizon_block_composite_metric_summary.csv", index=False)
    metric_horizon.to_csv(out_dir / "horizon_block_composite_metric_by_horizon.csv", index=False)
    metric_group.to_csv(out_dir / "horizon_block_composite_metric_by_horizon_group.csv", index=False)
    comparison.to_csv(out_dir / "horizon_block_composite_vs_baseline.csv", index=False)
    source_map.to_csv(out_dir / "horizon_block_composite_source_map.csv", index=False)
    audit.to_csv(out_dir / "horizon_block_composite_coverage_audit.csv", index=False)
    report = write_report(out_dir, comparison, source_map, audit, figures)
    write_json(out_dir / "summary.json", {
        "selection_dir": rel_path(selection_dir),
        "output_dir": rel_path(out_dir),
        "region": region,
        "folds": folds,
        "splits": splits,
        "method_id": args.method_id,
        "metric": args.metric,
        "unit": args.unit,
        "outputs": {
            "report": rel_path(report),
            "comparison": rel_path(out_dir / "horizon_block_composite_vs_baseline.csv"),
            "predictions": rel_path(out_dir / "horizon_block_composite_predictions_scaled.csv"),
        },
    })
    print(json.dumps({"output_dir": rel_path(out_dir), "report": rel_path(report)}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
