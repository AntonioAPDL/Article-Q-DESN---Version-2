#!/usr/bin/env python3
"""Freeze Stage-C paper-quantile comparison decisions.

This script is intentionally narrow. It does not fit local models and it does
not run PriceFM. It consumes a completed Stage-C local-vs-PriceFM comparison
directory and writes explicit promotion, close-call, and fallback registries.

The promotion rule is strict: a local DESN/Q-DESN candidate is promoted only
when the best local method beats cached fold-aligned PriceFM Phase-I on
original-unit test AQL. Close local losses are kept for review but are not
promoted as wins.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json
from pricefm_graph import graph_hash


DEFAULT_PRICEFM_METHOD = "pricefm_phase1_pretraining"
PROMOTED_LABEL = "stage_c_confirmed_local_win"
CLOSE_LABEL = "stage_c_local_close_to_pricefm"
FALLBACK_LABEL = "stage_c_pricefm_fallback"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--comparison-dir", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--registry-csv", default=None)
    p.add_argument("--pricefm-method", default=DEFAULT_PRICEFM_METHOD)
    p.add_argument("--split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--close-rel-threshold", type=float, default=0.05)
    p.add_argument("--grid-id", default="pricefm_stage_c_quantile_decisions_20260618")
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


def validate_comparison_status(status):
    require_columns(status, ["region", "fold", "status", "return_code"], "comparison status")
    bad = status[
        ~status["status"].astype(str).eq("completed")
        | (numeric(status["return_code"]) != 0)
    ].copy()
    if not bad.empty:
        cols = [col for col in ["region", "fold", "kind", "status", "return_code"] if col in bad.columns]
        raise ValueError(
            "comparison status is not fully completed:\n{}".format(
                bad[cols].to_string(index=False)
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
    frame = row_alignment.copy()
    for col in [
        "available_prediction_rows", "available_unique_response_rows",
        "aligned_prediction_rows", "aligned_unique_response_rows",
    ]:
        frame[col] = numeric(frame[col])
    bad = frame[
        (frame["available_prediction_rows"] != frame["aligned_prediction_rows"])
        | (frame["available_unique_response_rows"] != frame["aligned_unique_response_rows"])
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


def validate_unique_region_folds(frame, context):
    require_columns(frame, ["region", "fold"], context)
    dup = frame[frame.duplicated(["region", "fold"], keep=False)].copy()
    if not dup.empty:
        raise ValueError(
            "{} has duplicate region/fold rows:\n{}".format(
                context, dup[["region", "fold"]].to_string(index=False)
            )
        )


def original_metric_panel(panel_metric, args):
    require_columns(
        panel_metric,
        ["region", "fold", "method_id", "split", "unit", args.metric],
        "panel metrics",
    )
    frame = panel_metric[
        panel_metric["split"].astype(str).eq(str(args.split))
        & panel_metric["unit"].astype(str).eq(str(args.unit))
    ].copy()
    if frame.empty:
        raise ValueError("no panel metrics found for split={} unit={}".format(args.split, args.unit))
    frame[args.metric] = numeric(frame[args.metric])
    if frame[args.metric].isna().any():
        raise ValueError("panel metrics contain non-finite {}".format(args.metric))
    return frame


def best_local_vs_pricefm(panel_metric, args):
    pricefm = panel_metric[panel_metric["method_id"].astype(str).eq(str(args.pricefm_method))].copy()
    local = panel_metric[~panel_metric["method_id"].astype(str).eq(str(args.pricefm_method))].copy()
    if pricefm.empty:
        raise ValueError("missing PriceFM method '{}' in panel metrics".format(args.pricefm_method))
    if local.empty:
        raise ValueError("no local DESN/Q-DESN methods found in panel metrics")

    pricefm = pricefm[["region", "fold", args.metric]].rename(
        columns={args.metric: "pricefm_{}".format(args.metric)}
    )
    validate_unique_region_folds(pricefm, "PriceFM panel metrics")

    local = local.sort_values(["region", "fold", args.metric, "method_id"])
    best = local.groupby(["region", "fold"], as_index=False).first()
    best = best[["region", "fold", "method_id", args.metric]].rename(
        columns={"method_id": "best_local_method", args.metric: "local_{}".format(args.metric)}
    )
    out = best.merge(pricefm, on=["region", "fold"], how="outer", validate="one_to_one")
    validate_unique_region_folds(out, "best local versus PriceFM")
    local_col = "local_{}".format(args.metric)
    price_col = "pricefm_{}".format(args.metric)
    out[local_col] = numeric(out[local_col])
    out[price_col] = numeric(out[price_col])
    if out[[local_col, price_col]].isna().any().any():
        raise ValueError("best local versus PriceFM contains missing metric values")
    out["delta_abs"] = out[local_col] - out[price_col]
    out["delta_rel"] = out["delta_abs"] / out[price_col].abs().clip(lower=1.0e-8)
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def decision_label(delta_abs, delta_rel, close_rel_threshold):
    if delta_abs < 0.0:
        return PROMOTED_LABEL
    if delta_rel <= close_rel_threshold:
        return CLOSE_LABEL
    return FALLBACK_LABEL


def recommendation(label):
    if label == PROMOTED_LABEL:
        return "promote_local_candidate"
    if label == CLOSE_LABEL:
        return "review_close_local_loss"
    return "prefer_pricefm_for_now"


def attach_registry_context(decisions, registry_csv):
    if registry_csv is None or str(registry_csv).strip() == "":
        return decisions
    registry = read_csv_required(registry_csv, "source registry")
    require_columns(registry, ["region", "fold"], "source registry")
    cols = [
        "region", "fold", "experiment_id", "selected_method_id",
        "selected_on_split", "selected_on_unit", "selection_metric",
        "selection_metric_value", "feature_map", "lag_window", "depth",
        "units", "alpha", "rho", "input_scale", "projection_scale",
        "tau0", "seed", "priority_queue", "queue", "stage_c_priority",
        "candidate_source_final", "candidate_source", "selected_source",
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set", "graph_degree",
        "graph_source", "graph_hash", "run_dir", "model_dir", "adapter_dir",
    ]
    cols = [col for col in cols if col in registry.columns]
    ctx = registry[cols].copy().drop_duplicates(["region", "fold"], keep="first")
    validate_unique_region_folds(ctx, "source registry context")
    out = decisions.merge(ctx, on=["region", "fold"], how="left", validate="one_to_one")
    return normalize_feature_metadata(out)


def normalize_feature_metadata(frame):
    """Normalize local/graph feature metadata after registry joins."""
    out = frame.copy()
    if "feature_policy" not in out.columns:
        return out
    metadata_cols = [
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set", "graph_source",
        "graph_hash",
    ]
    for col in metadata_cols:
        if col not in out.columns:
            out[col] = ""
        out[col] = out[col].astype("object")

    policy = out["feature_policy"].fillna("").astype(str)
    graph_mask = policy.eq("graph_khop")
    if graph_mask.any():
        if "graph_degree" not in out.columns:
            out["graph_degree"] = ""
        degree = pd.to_numeric(out.loc[graph_mask, "graph_degree"], errors="coerce").fillna(1).astype(int)
        out.loc[graph_mask, "feature_policy"] = "graph_khop"
        out.loc[graph_mask, "graph_degree"] = degree.values
        out.loc[graph_mask, "graph_source"] = "PriceFM.graph_adj_matrix"
        out.loc[graph_mask, "graph_hash"] = graph_hash()
        out.loc[graph_mask, "input_scope"] = [
            "pricefm_graph_khop_degree{}".format(int(x)) for x in degree
        ]
        out.loc[graph_mask, "output_scope"] = "target_region_path"
        out.loc[graph_mask, "lead_covariate_status"] = "realized_ex_post"
        out.loc[graph_mask, "spatial_information_set"] = "pricefm_released_graph_khop"

    local_mask = policy.eq("target_only")
    if local_mask.any():
        defaults = {
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        }
        for col, default in defaults.items():
            if col not in out.columns:
                out[col] = ""
            blank_mask = out[col].isna() | out[col].astype(str).eq("")
            out.loc[local_mask & blank_mask, col] = default
    return out


def horizon_diagnostics(panel_horizon_group, decisions, args):
    if panel_horizon_group.empty:
        return pd.DataFrame()
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
        return pd.DataFrame()
    rows = []
    for row in decisions.itertuples(index=False):
        local = sub[
            sub["region"].astype(str).eq(str(row.region))
            & (numeric(sub["fold"]).astype("Int64") == int(row.fold))
            & sub["method_id"].astype(str).eq(str(row.best_local_method))
        ].copy()
        pricefm = sub[
            sub["region"].astype(str).eq(str(row.region))
            & (numeric(sub["fold"]).astype("Int64") == int(row.fold))
            & sub["method_id"].astype(str).eq(str(args.pricefm_method))
        ].copy()
        if local.empty or pricefm.empty:
            raise ValueError("missing horizon-group metrics for {} fold {}".format(row.region, int(row.fold)))
        local = local[["region", "fold", "horizon_group", args.metric]].rename(
            columns={args.metric: "local_{}".format(args.metric)}
        )
        pricefm = pricefm[["region", "fold", "horizon_group", args.metric]].rename(
            columns={args.metric: "pricefm_{}".format(args.metric)}
        )
        merged = local.merge(pricefm, on=["region", "fold", "horizon_group"], how="inner")
        if merged.empty:
            raise ValueError("no common horizon groups for {} fold {}".format(row.region, int(row.fold)))
        merged["best_local_method"] = row.best_local_method
        merged["delta_abs"] = (
            numeric(merged["local_{}".format(args.metric)])
            - numeric(merged["pricefm_{}".format(args.metric)])
        )
        rows.append(merged)
    return pd.concat(rows, ignore_index=True).sort_values(["region", "fold", "horizon_group"]).reset_index(drop=True)


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


def write_report(out_dir, args, decisions, promoted, close, fallback, horizon):
    path = out_dir / "stage_c_quantile_decision_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-C Quantile Decisions\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        if str(args.notes).strip():
            f.write("{}\n\n".format(str(args.notes).strip()))
        f.write(
            "This report freezes Stage-C completion-fold seven-quantile decisions "
            "against cached fold-aligned PriceFM Phase-I predictions. Median "
            "selection evidence is treated as screening evidence only; promotion "
            "requires the full paper-quantile comparison.\n\n"
        )
        f.write("## Counts\n\n")
        f.write("- Evaluated region/folds: `{}`\n".format(int(decisions.shape[0])))
        f.write("- Confirmed local wins: `{}`\n".format(int(promoted.shape[0])))
        f.write("- Close local losses: `{}`\n".format(int(close.shape[0])))
        f.write("- PriceFM fallbacks: `{}`\n\n".format(int(fallback.shape[0])))
        f.write("## Decision Registry\n\n")
        f.write(markdown_table(
            decisions,
            [
                "region", "fold", "best_local_method", "local_AQL",
                "pricefm_AQL", "delta_abs", "delta_rel",
                "stage_c_quantile_decision", "stage_c_recommendation",
            ],
        ))
        f.write("\n\n## Horizon Diagnostics\n\n")
        f.write(markdown_table(
            horizon,
            [
                "region", "fold", "horizon_group", "best_local_method",
                "local_AQL", "pricefm_AQL", "delta_abs",
            ],
        ))
        f.write("\n\n## Rules\n\n")
        f.write("- `stage_c_confirmed_local_win`: best local original-unit test AQL is lower than PriceFM.\n")
        f.write("- `stage_c_local_close_to_pricefm`: best local AQL is not lower, but relative gap is within the close threshold.\n")
        f.write("- `stage_c_pricefm_fallback`: PriceFM remains the benchmark choice for that region/fold.\n")
        f.write("- Row-alignment equality is required for all methods before freeze outputs are written.\n")
    return path


def freeze(args):
    comparison_dir = repo_path(args.comparison_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.close_rel_threshold < 0:
        raise ValueError("--close-rel-threshold must be non-negative")

    summary_in = read_json_required(comparison_dir / "summary.json", "comparison summary")
    validate_summary(summary_in)
    status = read_csv_required(comparison_dir / "region_panel_comparison_status.csv", "comparison status")
    validate_comparison_status(status)
    row_alignment = read_csv_required(comparison_dir / "panel_row_alignment.csv", "row alignment")
    validate_row_alignment(row_alignment)
    panel_metric = read_csv_required(comparison_dir / "panel_metric.csv", "panel metrics")
    panel_horizon_group_path = comparison_dir / "panel_horizon_group.csv"
    panel_horizon_group = (
        read_csv_required(panel_horizon_group_path, "horizon-group metrics")
        if panel_horizon_group_path.exists()
        else pd.DataFrame()
    )

    original = original_metric_panel(panel_metric, args)
    decisions = best_local_vs_pricefm(original, args)
    decisions["stage_c_quantile_decision"] = [
        decision_label(row.delta_abs, row.delta_rel, args.close_rel_threshold)
        for row in decisions.itertuples(index=False)
    ]
    decisions["stage_c_recommendation"] = decisions["stage_c_quantile_decision"].map(recommendation)
    decisions["preserves_stage_c_local_promotion"] = decisions["stage_c_quantile_decision"].eq(PROMOTED_LABEL)
    decisions = attach_registry_context(decisions, args.registry_csv)
    horizon = horizon_diagnostics(panel_horizon_group, decisions, args)

    promoted = decisions[decisions["stage_c_quantile_decision"].eq(PROMOTED_LABEL)].copy()
    close = decisions[decisions["stage_c_quantile_decision"].eq(CLOSE_LABEL)].copy()
    fallback = decisions[decisions["stage_c_quantile_decision"].eq(FALLBACK_LABEL)].copy()

    decisions.to_csv(out_dir / "stage_c_quantile_decision_registry.csv", index=False)
    promoted.to_csv(out_dir / "stage_c_quantile_promoted_local_registry.csv", index=False)
    close.to_csv(out_dir / "stage_c_quantile_close_registry.csv", index=False)
    fallback.to_csv(out_dir / "stage_c_quantile_pricefm_fallback_registry.csv", index=False)
    horizon.to_csv(out_dir / "stage_c_quantile_horizon_group_diagnostics.csv", index=False)
    report = write_report(out_dir, args, decisions, promoted, close, fallback, horizon)

    summary = {
        "grid_id": args.grid_id,
        "status": "completed",
        "comparison_dir": config_path_value(comparison_dir),
        "registry_csv": config_path_value(args.registry_csv) if args.registry_csv else None,
        "output_dir": config_path_value(out_dir),
        "source_summary": summary_in,
        "split": args.split,
        "unit": args.unit,
        "metric": args.metric,
        "pricefm_method": args.pricefm_method,
        "close_rel_threshold": float(args.close_rel_threshold),
        "n_evaluated": int(decisions.shape[0]),
        "n_promoted_local": int(promoted.shape[0]),
        "n_close_to_pricefm": int(close.shape[0]),
        "n_pricefm_fallback": int(fallback.shape[0]),
        "mean_local_AQL": float(numeric(decisions["local_AQL"]).mean()),
        "mean_pricefm_AQL": float(numeric(decisions["pricefm_AQL"]).mean()),
        "mean_delta_abs": float(numeric(decisions["delta_abs"]).mean()),
        "mean_delta_rel": float(numeric(decisions["delta_rel"]).mean()),
        "promoted_region_folds": [
            {"region": str(row.region), "fold": int(row.fold), "method": str(row.best_local_method)}
            for row in promoted.itertuples(index=False)
        ],
        "close_region_folds": [
            {"region": str(row.region), "fold": int(row.fold), "method": str(row.best_local_method)}
            for row in close.itertuples(index=False)
        ],
        "fallback_region_folds": [
            {"region": str(row.region), "fold": int(row.fold), "method": str(row.best_local_method)}
            for row in fallback.itertuples(index=False)
        ],
        "outputs": {
            "decision_registry": config_path_value(out_dir / "stage_c_quantile_decision_registry.csv"),
            "promoted_local_registry": config_path_value(out_dir / "stage_c_quantile_promoted_local_registry.csv"),
            "close_registry": config_path_value(out_dir / "stage_c_quantile_close_registry.csv"),
            "pricefm_fallback_registry": config_path_value(out_dir / "stage_c_quantile_pricefm_fallback_registry.csv"),
            "horizon_diagnostics": config_path_value(out_dir / "stage_c_quantile_horizon_group_diagnostics.csv"),
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
