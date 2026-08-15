#!/usr/bin/env python3
"""Freeze Stage-B seven-quantile PriceFM comparison decisions.

This script runs after the local DESN/Q-DESN seven-paper-quantile panel has
already been compared with cached or regenerated PriceFM Phase-I predictions.
It does not fit models and it does not run PriceFM. It only turns comparison
outputs into explicit evaluated, confirmed, and exception registries.

The key rule is intentionally strict: a median-selected or seed-robust candidate
is not promotion-ready until the seven-quantile comparison is complete and the
best local method beats PriceFM on original-unit test AQL.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_PRICEFM_METHOD = "pricefm_phase1_pretraining"
CONFIRMED_LABEL = "confirmed_win"
LOSS_LABEL = "evaluated_loss"
SHORT_HORIZON_LABEL = "needs_short_horizon_rescue"
FALLBACK_LABEL = "pricefm_fallback_candidate"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--comparison-dir", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--registry-csv", default=None)
    p.add_argument("--cached-pricefm-root", default=None)
    p.add_argument("--pricefm-method", default=DEFAULT_PRICEFM_METHOD)
    p.add_argument("--split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--grid-id", default="pricefm_stage_b_confirmed_panel_20260618")
    p.add_argument("--notes", default="")
    return p


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
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def read_json_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required JSON: {}".format(context, path))
    with open(path, "r") as f:
        return json.load(f)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def validate_summary(summary):
    status = str(summary.get("status", ""))
    if status != "completed":
        raise ValueError("comparison summary status is {}, expected completed".format(status))


def validate_status(status):
    require_columns(status, ["region", "fold", "status", "return_code"], "comparison status")
    bad = status[
        ~status["status"].astype(str).eq("completed")
        | (pd.to_numeric(status["return_code"], errors="coerce") != 0)
    ].copy()
    if not bad.empty:
        cols = [col for col in ["region", "fold", "kind", "status", "return_code"] if col in bad.columns]
        raise ValueError(
            "comparison status is not fully completed:\n{}".format(
                bad[cols].to_string(index=False)
            )
        )


def validate_unique_region_folds(frame, context):
    require_columns(frame, ["region", "fold"], context)
    dup = frame[frame.duplicated(["region", "fold"], keep=False)].copy()
    if not dup.empty:
        raise ValueError(
            "{} has duplicate region/fold rows:\n{}".format(
                context, dup[["region", "fold"]].to_string(index=False)
            )
        )


def validate_row_alignment(row_alignment):
    require_columns(
        row_alignment,
        [
            "region", "fold", "method_id",
            "available_prediction_rows", "available_unique_response_rows",
            "aligned_prediction_rows", "aligned_unique_response_rows",
        ],
        "row alignment",
    )
    for col in [
        "available_prediction_rows", "available_unique_response_rows",
        "aligned_prediction_rows", "aligned_unique_response_rows",
    ]:
        row_alignment[col] = numeric(row_alignment[col])
    bad = row_alignment[
        (row_alignment["available_prediction_rows"] != row_alignment["aligned_prediction_rows"])
        | (
            row_alignment["available_unique_response_rows"]
            != row_alignment["aligned_unique_response_rows"]
        )
    ].copy()
    if not bad.empty:
        raise ValueError(
            "row alignment is imperfect:\n{}".format(
                bad[[
                    "region", "fold", "method_id",
                    "available_prediction_rows", "aligned_prediction_rows",
                    "available_unique_response_rows", "aligned_unique_response_rows",
                ]].to_string(index=False)
            )
        )


def original_metric_panel(panel_metric, split, unit):
    require_columns(
        panel_metric,
        ["region", "fold", "method_id", "split", "unit", "AQL"],
        "panel metrics",
    )
    sub = panel_metric[
        panel_metric["split"].astype(str).eq(str(split))
        & panel_metric["unit"].astype(str).eq(str(unit))
    ].copy()
    if sub.empty:
        raise ValueError("no panel metrics found for split={} unit={}".format(split, unit))
    return sub


def best_local_from_metric(panel_metric, pricefm_method, metric):
    sub = panel_metric.copy()
    sub[metric] = numeric(sub[metric])
    pricefm = sub[sub["method_id"].astype(str).eq(pricefm_method)].copy()
    local = sub[~sub["method_id"].astype(str).eq(pricefm_method)].copy()
    if pricefm.empty:
        raise ValueError("missing PriceFM method '{}' in panel metrics".format(pricefm_method))
    if local.empty:
        raise ValueError("no local methods found in panel metrics")
    pricefm = pricefm[["region", "fold", metric]].rename(columns={metric: "pricefm_{}".format(metric)})
    validate_unique_region_folds(pricefm, "PriceFM panel metrics")
    local = local.sort_values(["region", "fold", metric, "method_id"])
    best = local.groupby(["region", "fold"], as_index=False).first()
    best = best[["region", "fold", "method_id", metric]].rename(
        columns={"method_id": "best_method", metric: "best_{}".format(metric)}
    )
    out = best.merge(pricefm, on=["region", "fold"], how="outer", validate="one_to_one")
    return out


def load_or_compute_best(comparison_dir, panel_metric, args):
    best_path = repo_path(comparison_dir) / "best_local_vs_pricefm_by_region_fold.csv"
    if best_path.exists() and best_path.stat().st_size > 0:
        best = pd.read_csv(best_path)
        require_columns(
            best,
            ["region", "fold", "best_method", "best_AQL", "pricefm_AQL", "delta", "rel_delta"],
            "best local versus PriceFM table",
        )
        validate_unique_region_folds(best, "best local versus PriceFM table")
        return best.copy()
    best = best_local_from_metric(panel_metric, args.pricefm_method, args.metric)
    b_col = "best_{}".format(args.metric)
    p_col = "pricefm_{}".format(args.metric)
    best[b_col] = numeric(best[b_col])
    best[p_col] = numeric(best[p_col])
    best["delta"] = best[b_col] - best[p_col]
    best["rel_delta"] = best["delta"] / best[p_col].abs().clip(lower=1.0e-8)
    return best.rename(columns={b_col: "best_AQL", p_col: "pricefm_AQL"})


def horizon_best_vs_pricefm(panel_horizon_group, best, args):
    require_columns(
        panel_horizon_group,
        ["region", "fold", "method_id", "split", "unit", "horizon_group", args.metric],
        "horizon-group metrics",
    )
    sub = panel_horizon_group[
        panel_horizon_group["split"].astype(str).eq(str(args.split))
        & panel_horizon_group["unit"].astype(str).eq(str(args.unit))
    ].copy()
    if sub.empty:
        raise ValueError("no horizon-group metrics found for split={} unit={}".format(args.split, args.unit))
    rows = []
    for row in best.itertuples(index=False):
        local = sub[
            sub["region"].astype(str).eq(str(row.region))
            & (pd.to_numeric(sub["fold"], errors="coerce").astype("Int64") == int(row.fold))
            & sub["method_id"].astype(str).eq(str(row.best_method))
        ].copy()
        pricefm = sub[
            sub["region"].astype(str).eq(str(row.region))
            & (pd.to_numeric(sub["fold"], errors="coerce").astype("Int64") == int(row.fold))
            & sub["method_id"].astype(str).eq(str(args.pricefm_method))
        ].copy()
        if local.empty or pricefm.empty:
            raise ValueError("missing horizon metrics for {} fold {}".format(row.region, int(row.fold)))
        local = local[["region", "fold", "horizon_group", args.metric]].rename(
            columns={args.metric: "local_{}".format(args.metric)}
        )
        pricefm = pricefm[["region", "fold", "horizon_group", args.metric]].rename(
            columns={args.metric: "pricefm_{}".format(args.metric)}
        )
        merged = local.merge(pricefm, on=["region", "fold", "horizon_group"], how="inner")
        if merged.empty:
            raise ValueError("no common horizon groups for {} fold {}".format(row.region, int(row.fold)))
        merged["best_method"] = row.best_method
        merged["delta"] = numeric(merged["local_{}".format(args.metric)]) - numeric(
            merged["pricefm_{}".format(args.metric)]
        )
        rows.append(merged)
    out = pd.concat(rows, ignore_index=True)
    return out.sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)


def label_rows(best, horizon):
    best = best.copy()
    best["delta"] = numeric(best["delta"])
    best["rel_delta"] = numeric(best["rel_delta"])
    best["promotion_label"] = LOSS_LABEL
    best.loc[best["delta"] < 0.0, "promotion_label"] = CONFIRMED_LABEL
    best["preserves_stage_b_promotion"] = best["promotion_label"].eq(CONFIRMED_LABEL)
    best["exception_label"] = ""
    best.loc[best["promotion_label"].eq(LOSS_LABEL), "exception_label"] = FALLBACK_LABEL

    losses = horizon[horizon["delta"] > 0.0].copy()
    if not losses.empty:
        worst = losses.sort_values(["region", "fold", "delta"], ascending=[True, True, False])
        worst = worst.groupby(["region", "fold"], as_index=False).first()
        worst = worst[["region", "fold", "horizon_group", "delta"]].rename(
            columns={"horizon_group": "worst_horizon_group", "delta": "worst_horizon_delta"}
        )
        best = best.merge(worst, on=["region", "fold"], how="left", validate="one_to_one")
        mask = best["promotion_label"].eq(LOSS_LABEL) & best["worst_horizon_group"].astype(str).eq("1-24")
        best.loc[mask, "exception_label"] = SHORT_HORIZON_LABEL
    else:
        best["worst_horizon_group"] = ""
        best["worst_horizon_delta"] = pd.NA
    return best.sort_values(["promotion_label", "region", "fold"]).reset_index(drop=True)


def registry_context(registry_csv):
    if registry_csv is None or str(registry_csv).strip() == "":
        return None
    registry = read_csv_required(registry_csv, "source registry")
    require_columns(registry, ["region", "fold"], "source registry")
    cols = [
        "region", "fold", "experiment_id", "selected_method_id", "candidate_source_final",
        "selected_source", "decision_label", "final_decision", "input_scope",
        "spatial_information_set", "graph_degree", "feature_map", "lag_window",
        "depth", "units", "alpha", "rho", "input_scale", "tau0", "seed",
        "run_dir", "model_dir", "adapter_dir",
    ]
    cols = [col for col in cols if col in registry.columns]
    ctx = registry[cols].copy()
    ctx = ctx.drop_duplicates(["region", "fold"], keep="first")
    validate_unique_region_folds(ctx, "source registry context")
    return ctx


def write_report(out_dir, args, evaluated, confirmed, exceptions, horizon):
    path = out_dir / "stage_b_confirmed_panel_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-B Confirmed Panel\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        if str(args.notes).strip():
            f.write("{}\n\n".format(str(args.notes).strip()))
        f.write("This report freezes seven-quantile local DESN/Q-DESN decisions after ")
        f.write("comparison with fold-aligned PriceFM Phase-I predictions. Median-only ")
        f.write("or seed-robust evidence is treated as screening evidence, not as final ")
        f.write("promotion evidence.\n\n")
        f.write("## Counts\n\n")
        f.write("- Evaluated region/folds: `{}`\n".format(int(evaluated.shape[0])))
        f.write("- Confirmed local wins: `{}`\n".format(int(confirmed.shape[0])))
        f.write("- Exceptions/losses: `{}`\n\n".format(int(exceptions.shape[0])))
        f.write("## Evaluated Rows\n\n")
        f.write(markdown_table(
            evaluated,
            [
                "region", "fold", "best_method", "best_AQL", "pricefm_AQL",
                "delta", "rel_delta", "promotion_label", "exception_label",
                "worst_horizon_group", "worst_horizon_delta",
            ],
        ))
        f.write("\n\n## Horizon Diagnostics\n\n")
        f.write(markdown_table(
            horizon,
            [
                "region", "fold", "horizon_group", "best_method",
                "local_AQL", "pricefm_AQL", "delta",
            ],
        ))
        f.write("\n\n## Rules\n\n")
        f.write("- `confirmed_win` requires seven-quantile comparison completion and original-unit test AQL delta < 0.\n")
        f.write("- `evaluated_loss` rows must not enter promotion panels as local wins.\n")
        f.write("- `needs_short_horizon_rescue` is assigned when a losing row's largest horizon loss is group `1-24`.\n")
        f.write("- Row-alignment equality is required for all available methods before any freeze output is written.\n")
    return path


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns):
    if frame is None or frame.empty:
        return "_No rows._"
    cols = [col for col in columns if col in frame.columns]
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame[cols].iterrows():
        lines.append("| " + " | ".join(markdown_value(row[col]) for col in cols) + " |")
    return "\n".join(lines)


def freeze(args):
    comparison_dir = repo_path(args.comparison_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    summary_in = read_json_required(comparison_dir / "summary.json", "comparison summary")
    validate_summary(summary_in)
    status = read_csv_required(comparison_dir / "region_panel_comparison_status.csv", "comparison status")
    validate_status(status)
    row_alignment = read_csv_required(comparison_dir / "panel_row_alignment.csv", "row alignment")
    validate_row_alignment(row_alignment)
    panel_metric = read_csv_required(comparison_dir / "panel_metric.csv", "panel metrics")
    panel_horizon_group = read_csv_required(comparison_dir / "panel_horizon_group.csv", "horizon-group metrics")

    original_metric = original_metric_panel(panel_metric, args.split, args.unit)
    best = load_or_compute_best(comparison_dir, original_metric, args)
    validate_unique_region_folds(best, "best local versus PriceFM table")

    expected_keys = set(zip(best["region"].astype(str), best["fold"].astype(int)))
    status_keys = set(zip(status["region"].astype(str), status["fold"].astype(int)))
    missing_status = sorted(expected_keys - status_keys)
    if missing_status:
        raise ValueError("comparison status missing region/fold keys: {}".format(missing_status))

    horizon = horizon_best_vs_pricefm(panel_horizon_group, best, args)
    evaluated = label_rows(best, horizon)
    ctx = registry_context(args.registry_csv)
    if ctx is not None:
        evaluated = evaluated.merge(ctx, on=["region", "fold"], how="left", validate="one_to_one")

    confirmed = evaluated[evaluated["promotion_label"].eq(CONFIRMED_LABEL)].copy()
    exceptions = evaluated[~evaluated["promotion_label"].eq(CONFIRMED_LABEL)].copy()

    evaluated.to_csv(out_dir / "evaluated_stage_b_panel.csv", index=False)
    confirmed.to_csv(out_dir / "confirmed_stage_b_panel.csv", index=False)
    exceptions.to_csv(out_dir / "stage_b_exceptions.csv", index=False)
    horizon.to_csv(out_dir / "horizon_group_diagnostics.csv", index=False)
    report = write_report(out_dir, args, evaluated, confirmed, exceptions, horizon)

    summary = {
        "grid_id": args.grid_id,
        "status": "completed",
        "comparison_dir": config_path_value(comparison_dir),
        "cached_pricefm_root": (
            config_path_value(args.cached_pricefm_root)
            if args.cached_pricefm_root is not None
            else None
        ),
        "registry_csv": config_path_value(args.registry_csv) if args.registry_csv else None,
        "output_dir": config_path_value(out_dir),
        "source_summary": summary_in,
        "split": args.split,
        "unit": args.unit,
        "metric": args.metric,
        "pricefm_method": args.pricefm_method,
        "n_evaluated": int(evaluated.shape[0]),
        "n_confirmed": int(confirmed.shape[0]),
        "n_exceptions": int(exceptions.shape[0]),
        "confirmed_regions": sorted(confirmed["region"].astype(str).unique().tolist()),
        "exception_region_folds": [
            {"region": str(row.region), "fold": int(row.fold), "label": str(row.exception_label)}
            for row in exceptions.itertuples(index=False)
        ],
        "mean_local_AQL": float(numeric(evaluated["best_AQL"]).mean()),
        "mean_pricefm_AQL": float(numeric(evaluated["pricefm_AQL"]).mean()),
        "mean_delta": float(numeric(evaluated["delta"]).mean()),
        "mean_rel_delta": float(numeric(evaluated["rel_delta"]).mean()),
        "confirmed_mean_local_AQL": float(numeric(confirmed["best_AQL"]).mean()) if not confirmed.empty else None,
        "confirmed_mean_pricefm_AQL": float(numeric(confirmed["pricefm_AQL"]).mean()) if not confirmed.empty else None,
        "confirmed_mean_delta": float(numeric(confirmed["delta"]).mean()) if not confirmed.empty else None,
        "confirmed_mean_rel_delta": float(numeric(confirmed["rel_delta"]).mean()) if not confirmed.empty else None,
        "outputs": {
            "evaluated_panel": config_path_value(out_dir / "evaluated_stage_b_panel.csv"),
            "confirmed_panel": config_path_value(out_dir / "confirmed_stage_b_panel.csv"),
            "exceptions": config_path_value(out_dir / "stage_b_exceptions.csv"),
            "horizon_diagnostics": config_path_value(out_dir / "horizon_group_diagnostics.csv"),
            "report": config_path_value(report),
        },
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = freeze(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
