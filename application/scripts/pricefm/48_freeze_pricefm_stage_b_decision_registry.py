#!/usr/bin/env python3
"""Freeze Stage-B PriceFM median decisions before quantile promotion/rescue.

The Stage-B median registry answers two different questions:

1. Did the selected Q-DESN median specification beat the fold-aligned PriceFM
   Phase-I median prediction?
2. Did the same selected specification remain sane against simple local naive
   baselines?

This script combines those two audits into a single reproducible decision
registry. It does not refit anything. It only freezes the next action for each
region/fold so downstream promotion and rescue grids are generated from one
explicit handoff artifact.
"""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_QDESN_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)
DEFAULT_PRICEFM_METHOD = "pricefm_phase1_pretraining"
PROMOTION_DECISIONS = {
    "paper_quantile_ready",
    "paper_quantile_ready_with_naive_conflict",
}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--registry-dir", required=True)
    p.add_argument("--closeout-dir", required=True)
    p.add_argument("--comparison-dir", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--grid-id", required=True)
    p.add_argument("--qdesn-methods", default=DEFAULT_QDESN_METHODS)
    p.add_argument("--pricefm-method", default=DEFAULT_PRICEFM_METHOD)
    p.add_argument("--split", default="test")
    p.add_argument("--unit", default="original")
    p.add_argument("--metric", default="AQL")
    p.add_argument("--candidate-source", default="stage_b_decision_registry_20260616")
    return p


def parse_csv(value):
    if value is None or str(value).strip() == "":
        return []
    return [x.strip() for x in str(value).split(",") if x.strip()]


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


def read_csv_optional(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    return pd.read_csv(path)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def metric_subset(panel, split, unit):
    return panel[
        panel["split"].astype(str).eq(str(split))
        & panel["unit"].astype(str).eq(str(unit))
    ].copy()


def best_method_by_fold(panel, split, unit, metric, methods, prefix):
    sub = metric_subset(panel, split, unit)
    sub = sub[sub["method_id"].astype(str).isin(set(methods))].copy()
    if sub.empty:
        return pd.DataFrame(columns=["region", "fold"])
    sub[metric] = numeric(sub[metric])
    sub = sub[sub[metric].notna()].copy()
    if sub.empty:
        return pd.DataFrame(columns=["region", "fold"])
    sub = sub.sort_values(["region", "fold", metric, "method_id"])
    best = sub.groupby(["region", "fold"], as_index=False).first()
    keep = ["region", "fold", "method_id", metric, "MAE", "RMSE"]
    keep = [col for col in keep if col in best.columns]
    best = best[keep].copy()
    rename = {
        "method_id": "{}_method_id".format(prefix),
        metric: "{}_{}".format(prefix, metric),
        "MAE": "{}_MAE".format(prefix),
        "RMSE": "{}_RMSE".format(prefix),
    }
    return best.rename(columns=rename)


def one_method_by_fold(panel, split, unit, metric, method, prefix):
    out = best_method_by_fold(panel, split, unit, metric, [method], prefix)
    if "{}_method_id".format(prefix) in out.columns:
        out = out.drop(columns=["{}_method_id".format(prefix)])
    return out


def validate_comparison_status(status):
    require_columns(status, ["status", "return_code"], "comparison status")
    bad = status[
        ~status["status"].astype(str).eq("completed")
        | (pd.to_numeric(status["return_code"], errors="coerce") != 0)
    ].copy()
    if not bad.empty:
        cols = [col for col in ["region", "fold", "kind", "status", "return_code"] if col in bad.columns]
        raise ValueError(
            "Comparison status is not fully completed:\n{}".format(
                bad[cols].to_string(index=False)
            )
        )


def fold_metrics(panel, flags, args):
    require_columns(
        panel,
        ["region", "fold", "method_id", "split", "unit", args.metric],
        "comparison panel metrics",
    )
    qdesn = best_method_by_fold(
        panel,
        args.split,
        args.unit,
        args.metric,
        parse_csv(args.qdesn_methods),
        "qdesn_best",
    )
    pricefm = one_method_by_fold(
        panel,
        args.split,
        args.unit,
        args.metric,
        args.pricefm_method,
        "pricefm_phase1",
    )
    out = qdesn.merge(pricefm, on=["region", "fold"], how="outer", validate="one_to_one")
    q_col = "qdesn_best_{}".format(args.metric)
    p_col = "pricefm_phase1_{}".format(args.metric)
    out[q_col] = numeric(out[q_col])
    out[p_col] = numeric(out[p_col])
    out["qdesn_delta_vs_pricefm"] = out[q_col] - out[p_col]
    out["qdesn_rel_delta_vs_pricefm"] = out["qdesn_delta_vs_pricefm"] / out[p_col].abs().clip(lower=1.0e-8)
    out["qdesn_beats_pricefm"] = out["qdesn_delta_vs_pricefm"] < 0.0

    if flags is not None and not flags.empty:
        require_columns(
            flags,
            ["region", "fold", "method_id", args.metric, "pricefm_phase1_{}".format(args.metric), "decision_label"],
            "selected competitiveness flags",
        )
        keep = [
            "region", "fold", "method_id", args.metric,
            "pricefm_phase1_{}".format(args.metric), "delta_abs",
            "delta_rel", "decision_label",
        ]
        keep = [col for col in keep if col in flags.columns]
        flag = flags[keep].copy().rename(columns={
            "method_id": "selected_vs_pricefm_method_id",
            args.metric: "selected_vs_pricefm_{}".format(args.metric),
            "pricefm_phase1_{}".format(args.metric): (
                "selected_vs_pricefm_pricefm_phase1_{}".format(args.metric)
            ),
            "delta_abs": "selected_vs_pricefm_delta_abs",
            "delta_rel": "selected_vs_pricefm_delta_rel",
            "decision_label": "selected_vs_pricefm_decision_label",
        })
        out = out.merge(flag, on=["region", "fold"], how="left", validate="one_to_one")
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def region_decision_label(row):
    n_folds = int(row["n_folds"])
    n_wins = int(row["n_qdesn_beats_pricefm"])
    stage_b_triage = str(row.get("stage_b_triage", ""))
    if n_folds > 0 and n_wins == n_folds:
        if stage_b_triage == "local_fail_rescue":
            return "paper_quantile_ready_with_naive_conflict"
        return "paper_quantile_ready"
    if n_folds > 0:
        return "median_rescue_needed"
    return "hold"


def region_action(label):
    return {
        "paper_quantile_ready": "launch_paper_quantiles",
        "paper_quantile_ready_with_naive_conflict": "launch_paper_quantiles_with_naive_conflict_note",
        "median_rescue_needed": "run_graph_local_median_rescue",
        "hold": "hold_manual_review",
    }.get(str(label), "hold_manual_review")


def build_region_decisions(closeout_regions, fold, metric):
    require_columns(
        closeout_regions,
        ["region", "n_folds", "stage_b_triage"],
        "Stage-B closeout region summary",
    )
    q_col = "qdesn_best_{}".format(metric)
    p_col = "pricefm_phase1_{}".format(metric)
    rows = []
    for region, sub in fold.groupby("region"):
        n_folds = int(sub.shape[0])
        rows.append({
            "region": region,
            "comparison_n_folds": n_folds,
            "n_qdesn_beats_pricefm": int(sub["qdesn_beats_pricefm"].fillna(False).sum()),
            "mean_qdesn_best_{}".format(metric): float(numeric(sub[q_col]).mean()),
            "mean_pricefm_phase1_{}".format(metric): float(numeric(sub[p_col]).mean()),
            "mean_qdesn_delta_vs_pricefm": float(numeric(sub["qdesn_delta_vs_pricefm"]).mean()),
            "mean_qdesn_rel_delta_vs_pricefm": float(numeric(sub["qdesn_rel_delta_vs_pricefm"]).mean()),
        })
    comp = pd.DataFrame(rows)
    out = closeout_regions.merge(comp, on="region", how="outer", validate="one_to_one")
    out["n_folds"] = pd.to_numeric(out["n_folds"], errors="coerce").fillna(out["comparison_n_folds"]).astype(int)
    out["n_qdesn_beats_pricefm"] = pd.to_numeric(out["n_qdesn_beats_pricefm"], errors="coerce").fillna(0).astype(int)
    out["final_decision"] = [region_decision_label(row) for _, row in out.iterrows()]
    out["recommended_action"] = [region_action(x) for x in out["final_decision"]]
    out["promote_to_paper_quantiles"] = out["final_decision"].isin(PROMOTION_DECISIONS)
    out["needs_median_rescue"] = out["final_decision"].eq("median_rescue_needed")
    return out.sort_values(["final_decision", "region"]).reset_index(drop=True)


def rescue_priority(row):
    rel = row.get("qdesn_rel_delta_vs_pricefm")
    if pd.isna(rel):
        return 1
    if bool(row.get("qdesn_beats_pricefm")):
        return 1
    return 0


def fold_recommended_action(row):
    if bool(row.get("promote_to_paper_quantiles")):
        return str(row.get("recommended_action", "launch_paper_quantiles"))
    if bool(row.get("qdesn_beats_pricefm")):
        return "confirm_rescued_region_fold_or_seed_robustness"
    return "retest_graph_geometry_validation"


def build_decision_registry(closeout_selection, closeout_regions, fold, args):
    require_columns(
        closeout_selection,
        ["region", "fold", "selected_method_id", "experiment_id", "selection_metric_value"],
        "Stage-B closeout selection registry",
    )
    region_decisions = build_region_decisions(closeout_regions, fold, args.metric)
    region_cols = [
        "region", "final_decision", "recommended_action",
        "promote_to_paper_quantiles", "needs_median_rescue",
        "stage_b_triage", "n_qdesn_beats_pricefm",
        "mean_qdesn_best_{}".format(args.metric), "mean_pricefm_phase1_{}".format(args.metric),
        "mean_qdesn_delta_vs_pricefm", "mean_qdesn_rel_delta_vs_pricefm",
    ]
    out = closeout_selection.merge(
        fold,
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
    )
    out = out.merge(region_decisions[region_cols], on="region", how="left", validate="many_to_one")
    out["candidate_source_final"] = args.candidate_source
    out["decision_grid_id"] = args.grid_id
    out["target_quantile_next_stage"] = "paper_grid_or_median_rescue"
    out["full_stage_b_median_decision_frozen"] = True
    out["fold_recommended_action"] = [fold_recommended_action(row) for _, row in out.iterrows()]
    out["rescue_priority"] = [rescue_priority(row) for _, row in out.iterrows()]
    out["delta_rel"] = out["qdesn_rel_delta_vs_pricefm"]
    out["decision_label"] = out["final_decision"]
    return (
        out.sort_values(["final_decision", "region", "fold"]).reset_index(drop=True),
        region_decisions,
    )


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[col for col in columns if col in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[col]) for col in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, registry, regions):
    path = out_dir / "stage_b_decision_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-B Decision Registry\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        f.write("Candidate source: `{}`\n\n".format(args.candidate_source))
        f.write(
            "This registry freezes the handoff after the Stage-B median-only "
            "tau=0.50 PriceFM comparison. It does not refit models.\n\n"
        )
        f.write("## Region Decisions\n\n")
        f.write(markdown_table(
            regions,
            columns=[
                "region", "stage_b_triage", "n_qdesn_beats_pricefm",
                "n_folds", "mean_qdesn_best_{}".format(args.metric),
                "mean_pricefm_phase1_{}".format(args.metric),
                "mean_qdesn_rel_delta_vs_pricefm", "final_decision",
                "recommended_action",
            ],
        ))
        f.write("\n\n## Fold Decisions\n\n")
        f.write(markdown_table(
            registry,
            columns=[
                "region", "fold", "selected_method_id", "experiment_id",
                "qdesn_best_method_id", "qdesn_best_AQL",
                "pricefm_phase1_AQL", "qdesn_rel_delta_vs_pricefm",
                "stage_b_triage", "final_decision",
                "fold_recommended_action", "rescue_priority",
            ],
        ))
        f.write("\n\n## Rules\n\n")
        f.write("- Regions whose Q-DESN median wins every fold against PriceFM are promoted to paper quantiles.\n")
        f.write("- A full PriceFM win with `local_fail_rescue` is promoted with an explicit naive-conflict label.\n")
        f.write("- Regions that do not win every fold against PriceFM are sent to a median rescue grid first.\n")
        f.write("- Large generated model outputs remain ignored under `application/data_local/`.\n")
    return path


def freeze(args):
    registry_dir = repo_path(args.registry_dir)
    closeout_dir = repo_path(args.closeout_dir)
    comparison_dir = repo_path(args.comparison_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    median_registry = read_csv_required(registry_dir / "median_selection_registry.csv", "median registry")
    closeout_selection = read_csv_required(
        closeout_dir / "stage_b_selection_registry_with_triage.csv",
        "Stage-B closeout selection registry",
    )
    closeout_regions = read_csv_required(
        closeout_dir / "stage_b_region_summary.csv",
        "Stage-B closeout region summary",
    )
    panel = read_csv_required(comparison_dir / "panel_metric.csv", "PriceFM comparison metrics")
    status = read_csv_required(comparison_dir / "region_panel_comparison_status.csv", "PriceFM comparison status")
    flags = read_csv_optional(comparison_dir / "selected_competitiveness_flags.csv")
    validate_comparison_status(status)

    require_columns(median_registry, ["region", "fold"], "median registry")
    expected_keys = set(zip(median_registry["region"].astype(str), median_registry["fold"].astype(int)))
    close_keys = set(zip(closeout_selection["region"].astype(str), closeout_selection["fold"].astype(int)))
    if expected_keys != close_keys:
        raise ValueError("Registry and closeout region/fold keys do not match.")

    fold = fold_metrics(panel, flags, args)
    fold_keys = set(zip(fold["region"].astype(str), fold["fold"].astype(int)))
    missing = sorted(expected_keys - fold_keys)
    if missing:
        raise ValueError("Comparison metrics missing region/fold keys: {}".format(missing))

    registry, regions = build_decision_registry(closeout_selection, closeout_regions, fold, args)
    promotion = registry[registry["final_decision"].isin(PROMOTION_DECISIONS)].copy()
    conflict = registry[registry["final_decision"].eq("paper_quantile_ready_with_naive_conflict")].copy()
    rescue = registry[registry["final_decision"].eq("median_rescue_needed")].copy()
    rescue_scope = rescue[[
        "region", "fold", "rescue_priority", "fold_recommended_action",
        "decision_label", "qdesn_rel_delta_vs_pricefm", "qdesn_delta_vs_pricefm",
    ]].copy().rename(columns={
        "fold_recommended_action": "recommended_action",
        "qdesn_rel_delta_vs_pricefm": "delta_rel",
        "qdesn_delta_vs_pricefm": "delta_abs",
    })

    registry.to_csv(out_dir / "stage_b_decision_registry.csv", index=False)
    regions.to_csv(out_dir / "stage_b_region_decisions.csv", index=False)
    promotion.to_csv(out_dir / "stage_b_promotion_ready_registry.csv", index=False)
    conflict.to_csv(out_dir / "stage_b_conflict_confirm_registry.csv", index=False)
    rescue.to_csv(out_dir / "stage_b_rescue_needed_registry.csv", index=False)
    rescue_scope.to_csv(out_dir / "stage_b_rescue_scope.csv", index=False)
    report = write_report(out_dir, args, registry, regions)

    summary = {
        "grid_id": args.grid_id,
        "candidate_source": args.candidate_source,
        "registry_dir": config_path_value(registry_dir),
        "closeout_dir": config_path_value(closeout_dir),
        "comparison_dir": config_path_value(comparison_dir),
        "output_dir": config_path_value(out_dir),
        "n_region_folds": int(registry.shape[0]),
        "n_regions": int(regions.shape[0]),
        "n_promotion_ready_rows": int(promotion.shape[0]),
        "n_conflict_confirm_rows": int(conflict.shape[0]),
        "n_rescue_needed_rows": int(rescue.shape[0]),
        "decision_counts": regions["final_decision"].value_counts().sort_index().to_dict(),
        "outputs": {
            "decision_registry": config_path_value(out_dir / "stage_b_decision_registry.csv"),
            "region_decisions": config_path_value(out_dir / "stage_b_region_decisions.csv"),
            "promotion_ready_registry": config_path_value(out_dir / "stage_b_promotion_ready_registry.csv"),
            "conflict_confirm_registry": config_path_value(out_dir / "stage_b_conflict_confirm_registry.csv"),
            "rescue_needed_registry": config_path_value(out_dir / "stage_b_rescue_needed_registry.csv"),
            "rescue_scope": config_path_value(out_dir / "stage_b_rescue_scope.csv"),
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
