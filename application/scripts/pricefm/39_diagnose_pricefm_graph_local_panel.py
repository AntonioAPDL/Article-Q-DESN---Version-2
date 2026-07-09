#!/usr/bin/env python3
"""Diagnose graph/local PriceFM DESN panel gaps and propose rescue scope."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--comparison-root", required=True)
    p.add_argument("--registry-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--baseline-method", default="pricefm_phase1_pretraining")
    p.add_argument("--split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--include-close", type=parse_bool, default=True)
    p.add_argument("--close-rel-threshold", type=float, default=0.05)
    p.add_argument("--severe-rel-threshold", type=float, default=0.10)
    p.add_argument("--dry-run", type=parse_bool, default=False)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def test_original(frame, split, unit):
    return frame[(frame["split"].astype(str) == str(split)) & (frame["unit"].astype(str) == str(unit))].copy()


def best_selected_vs_baseline(metric, baseline_method, split, unit):
    metric = test_original(metric, split, unit)
    base = metric[metric["method_id"].eq(baseline_method)][["region", "fold", "AQL"]].rename(
        columns={"AQL": "pricefm_AQL"}
    )
    selected = metric[~metric["method_id"].eq(baseline_method)].copy()
    best = (
        selected.sort_values(["region", "fold", "AQL"])
        .groupby(["region", "fold"], as_index=False)
        .head(1)
    )
    out = best.merge(base, on=["region", "fold"], how="left", validate="one_to_one")
    out["delta_abs"] = out["AQL"] - out["pricefm_AQL"]
    out["delta_rel"] = out["delta_abs"] / out["pricefm_AQL"].abs().clip(lower=1.0e-8)
    out["decision_label"] = "selected_lags_pricefm"
    out.loc[out["delta_abs"] <= 0.0, "decision_label"] = "selected_beats_pricefm"
    out.loc[
        (out["delta_abs"] > 0.0) & (out["delta_rel"] <= 0.05),
        "decision_label",
    ] = "selected_close_to_pricefm"
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def best_selected_horizon_groups(horizon_group, baseline_method, split, unit):
    frame = test_original(horizon_group, split, unit)
    base = frame[frame["method_id"].eq(baseline_method)][
        ["region", "fold", "horizon_group", "AQL"]
    ].rename(columns={"AQL": "pricefm_AQL"})
    selected = frame[~frame["method_id"].eq(baseline_method)].copy()
    best = (
        selected.sort_values(["region", "fold", "horizon_group", "AQL"])
        .groupby(["region", "fold", "horizon_group"], as_index=False)
        .head(1)
    )
    out = best.merge(base, on=["region", "fold", "horizon_group"], how="left")
    out["delta_abs"] = out["AQL"] - out["pricefm_AQL"]
    out["delta_rel"] = out["delta_abs"] / out["pricefm_AQL"].abs().clip(lower=1.0e-8)
    return out.sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)


def registry_columns(registry):
    wanted = [
        "region", "fold", "selected_source", "feature_policy", "input_scope",
        "spatial_information_set", "graph_degree", "experiment_id",
        "selected_method_id", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "tau0", "seed", "local_val_AQL",
        "graph_val_AQL", "val_delta_graph_minus_local", "local_test_AQL",
        "graph_test_AQL", "test_delta_graph_minus_local", "validation_improved",
        "test_improved",
    ]
    return [col for col in wanted if col in registry.columns]


def rescue_action(row, severe_threshold):
    selected_source = str(row.get("selected_source", ""))
    test_improved = bool(row.get("test_improved", False))
    rel = float(row.get("delta_rel", 0.0))
    region = str(row.get("region", ""))
    if selected_source == "graph":
        return "tune_graph_degree1_and_degree2_geometry"
    if region == "NO_4" and not test_improved:
        return "local_capacity_plus_graph_degree2_rescue"
    if selected_source == "local" and test_improved:
        return "retest_graph_geometry_validation"
    if rel >= severe_threshold:
        return "broad_local_and_graph_rescue"
    return "light_local_graph_rescue"


def rescue_priority(row, severe_threshold):
    rel = float(row.get("delta_rel", 0.0))
    if rel >= severe_threshold:
        return 0
    if str(row.get("decision_label", "")).endswith("close_to_pricefm"):
        return 2
    return 1


def build_diagnostics(args):
    comparison_root = repo_path(args.comparison_root)
    metric = read_csv_required(comparison_root / "panel_metric.csv", "comparison")
    horizon = read_csv_required(comparison_root / "panel_horizon_group.csv", "comparison")
    registry = read_csv_required(args.registry_csv, "registry")
    registry["region"] = registry["region"].astype(str)
    registry["fold"] = registry["fold"].astype(int)

    fold = best_selected_vs_baseline(metric, args.baseline_method, args.split, args.unit)
    fold = fold.merge(
        registry[registry_columns(registry)],
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
    )

    horizon_diag = best_selected_horizon_groups(horizon, args.baseline_method, args.split, args.unit)
    weak_mask = fold["decision_label"].ne("selected_beats_pricefm")
    if not bool(args.include_close):
        weak_mask &= fold["delta_rel"] > float(args.close_rel_threshold)
    rescue = fold[weak_mask].copy()
    if not rescue.empty:
        rescue["rescue_priority"] = rescue.apply(
            lambda row: rescue_priority(row, float(args.severe_rel_threshold)),
            axis=1,
        )
        rescue["recommended_action"] = rescue.apply(
            lambda row: rescue_action(row, float(args.severe_rel_threshold)),
            axis=1,
        )
        rescue = rescue.sort_values(["rescue_priority", "delta_rel"], ascending=[True, False])

    region = (
        fold.assign(
            beat=fold["decision_label"].eq("selected_beats_pricefm"),
            close=fold["decision_label"].eq("selected_close_to_pricefm"),
            lag=fold["decision_label"].eq("selected_lags_pricefm"),
        )
        .groupby("region", as_index=False)
        .agg(
            folds=("fold", "size"),
            beats=("beat", "sum"),
            close=("close", "sum"),
            lags=("lag", "sum"),
            mean_delta_rel=("delta_rel", "mean"),
            median_delta_rel=("delta_rel", "median"),
            mean_selected_AQL=("AQL", "mean"),
            mean_pricefm_AQL=("pricefm_AQL", "mean"),
        )
        .sort_values("region")
    )
    horizon_summary = (
        horizon_diag.assign(win=horizon_diag["delta_abs"] <= 0.0)
        .groupby("horizon_group", as_index=False)
        .agg(
            rows=("win", "size"),
            wins=("win", "sum"),
            mean_delta_rel=("delta_rel", "mean"),
            median_delta_rel=("delta_rel", "median"),
            mean_selected_AQL=("AQL", "mean"),
            mean_pricefm_AQL=("pricefm_AQL", "mean"),
        )
        .sort_values("horizon_group")
    )
    return {
        "fold": fold,
        "rescue": rescue,
        "region": region,
        "horizon": horizon_diag,
        "horizon_summary": horizon_summary,
    }


def write_report(output_dir, diagnostics, args):
    path = repo_path(output_dir) / "graph_local_panel_diagnostic_report.md"
    fold = diagnostics["fold"]
    rescue = diagnostics["rescue"]
    with open(path, "w") as f:
        f.write("# PriceFM Graph/Local Panel Diagnostics\n\n")
        f.write("Comparison root: `{}`.\n\n".format(config_path_value(args.comparison_root)))
        f.write("Registry: `{}`.\n\n".format(config_path_value(args.registry_csv)))
        f.write("## Panel Decision Counts\n\n")
        f.write("| decision | count |\n|---|---:|\n")
        for label, count in fold["decision_label"].value_counts().items():
            f.write("| {} | {} |\n".format(label, int(count)))
        if not rescue.empty:
            f.write("\n## Rescue Scope\n\n")
            f.write("| priority | region | fold | decision | selected_source | delta_rel | recommended_action |\n")
            f.write("|---:|---|---:|---|---|---:|---|\n")
            for row in rescue.itertuples(index=False):
                f.write(
                    "| {} | {} | {} | {} | {} | {:.2%} | {} |\n".format(
                        int(row.rescue_priority),
                        row.region,
                        int(row.fold),
                        row.decision_label,
                        getattr(row, "selected_source", ""),
                        float(row.delta_rel),
                        row.recommended_action,
                    )
                )
        f.write("\n## Notes\n\n")
        f.write("- Rescue scope is validation-clean: PriceFM metrics diagnose, but do not select models.\n")
        f.write("- Targeted median rescue should precede any seven-quantile refresh.\n")
    return path


def main():
    args = parser().parse_args()
    diagnostics = build_diagnostics(args)
    output_dir = repo_path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if not bool(args.dry_run):
        diagnostics["fold"].to_csv(output_dir / "fold_diagnostics.csv", index=False)
        diagnostics["rescue"].to_csv(output_dir / "recommended_rescue_scope.csv", index=False)
        diagnostics["region"].to_csv(output_dir / "region_summary.csv", index=False)
        diagnostics["horizon"].to_csv(output_dir / "horizon_group_diagnostics.csv", index=False)
        diagnostics["horizon_summary"].to_csv(output_dir / "horizon_group_summary.csv", index=False)
        report = write_report(output_dir, diagnostics, args)
    else:
        report = output_dir / "graph_local_panel_diagnostic_report.md"
    summary = {
        "status": "planned" if bool(args.dry_run) else "completed",
        "dry_run": bool(args.dry_run),
        "n_region_folds": int(diagnostics["fold"].shape[0]),
        "n_rescue_rows": int(diagnostics["rescue"].shape[0]),
        "output_dir": config_path_value(output_dir),
        "report": config_path_value(report),
    }
    if not bool(args.dry_run):
        write_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
