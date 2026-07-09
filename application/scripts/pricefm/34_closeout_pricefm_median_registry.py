#!/usr/bin/env python3
"""Close out a PriceFM median registry against a previous authoritative registry.

The selector writes validation-selected winners for a completed grid. This
script merges those winners with a previous authoritative registry and adds
stability audit labels without using test metrics as hidden selection criteria.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_SELECTION_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--new-registry-dir", required=True)
    p.add_argument("--previous-registry-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--grid-id", default=None)
    p.add_argument("--candidate-source", default="local_ar_20260610")
    p.add_argument("--selection-methods", default=DEFAULT_SELECTION_METHODS)
    p.add_argument("--validation-tolerance", type=float, default=0.0)
    p.add_argument("--tiny-validation-gain", type=float, default=0.01)
    p.add_argument("--test-aql-warning", type=float, default=0.25)
    p.add_argument("--test-rmse-warning", type=float, default=1.0)
    p.add_argument("--severe-test-aql-warning", type=float, default=1.0)
    p.add_argument("--severe-test-rmse-warning", type=float, default=5.0)
    p.add_argument("--input-scope", default="local_target_only")
    p.add_argument("--output-scope", default="target_region_path")
    p.add_argument("--lead-covariate-status", default="realized_ex_post")
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


def numeric_value(row, *names):
    for name in names:
        if name in row and pd.notna(row[name]):
            try:
                return float(row[name])
            except (TypeError, ValueError):
                pass
    return float("nan")


def text_value(row, *names, default=""):
    for name in names:
        if name in row and pd.notna(row[name]):
            return str(row[name])
    return default


def selected_method(row):
    return text_value(row, "selected_method_id", "method_id")


def selected_experiment(row):
    return text_value(row, "experiment_id", "current_experiment_id")


def selected_val_aql(row):
    return numeric_value(row, "selection_metric_value", "selection_AQL", "current_val_AQL")


def selected_test_aql(row):
    return numeric_value(row, "test_AQL", "current_test_AQL")


def selected_test_mae(row):
    return numeric_value(row, "test_MAE", "current_test_MAE")


def selected_test_rmse(row):
    return numeric_value(row, "test_RMSE", "current_test_RMSE")


def sort_region_fold(frame):
    if frame.empty:
        return frame
    return frame.sort_values(["region", "fold"]).reset_index(drop=True)


def read_method_convergence(model_dir, method_id):
    model_dir = repo_path(model_dir)
    path = model_dir / "model_method_summary.csv"
    if not path.exists() or path.stat().st_size == 0:
        return None
    try:
        summary = pd.read_csv(path)
    except Exception:
        return None
    if "method_id" not in summary.columns or "converged" not in summary.columns:
        return None
    sub = summary[summary["method_id"].astype(str).eq(str(method_id))]
    if sub.empty:
        return None
    val = sub.iloc[0]["converged"]
    if isinstance(val, str):
        return val.strip().lower() in {"true", "1", "yes", "y"}
    return bool(val)


def candidate_converged(row):
    model_dir = text_value(row, "model_dir", default="")
    method_id = selected_method(row)
    if not model_dir or not method_id:
        return None
    return read_method_convergence(model_dir, method_id)


def comparison_row(previous_row, new_row, args):
    prev_val = selected_val_aql(previous_row)
    new_val = selected_val_aql(new_row)
    prev_test = selected_test_aql(previous_row)
    new_test = selected_test_aql(new_row)
    prev_rmse = selected_test_rmse(previous_row)
    new_rmse = selected_test_rmse(new_row)
    prev_mae = selected_test_mae(previous_row)
    new_mae = selected_test_mae(new_row)
    val_delta = new_val - prev_val
    test_delta = new_test - prev_test
    rmse_delta = new_rmse - prev_rmse
    mae_delta = new_mae - prev_mae
    validation_improved = bool(pd.notna(val_delta) and val_delta < -float(args.validation_tolerance))
    tiny_val_gain = bool(validation_improved and abs(val_delta) <= float(args.tiny_validation_gain))
    test_aql_deterioration = bool(pd.notna(test_delta) and test_delta > float(args.test_aql_warning))
    test_rmse_deterioration = bool(pd.notna(rmse_delta) and rmse_delta > float(args.test_rmse_warning))
    severe_test_instability = bool(
        (pd.notna(test_delta) and test_delta > float(args.severe_test_aql_warning))
        or (pd.notna(rmse_delta) and rmse_delta > float(args.severe_test_rmse_warning))
    )
    conv = candidate_converged(new_row)
    convergence_risk = bool(conv is False)
    if not validation_improved:
        decision = "keep_previous_no_val_gain"
    elif convergence_risk:
        decision = "review_val_gain_convergence_risk"
    elif severe_test_instability or test_aql_deterioration or test_rmse_deterioration:
        decision = "review_val_gain_test_risk"
    else:
        decision = "promote_candidate"
    return {
        "region": text_value(new_row, "region"),
        "fold": int(new_row["fold"]),
        "current_method_id": selected_method(previous_row),
        "current_experiment_id": selected_experiment(previous_row),
        "current_val_AQL": prev_val,
        "current_test_AQL": prev_test,
        "current_test_MAE": prev_mae,
        "current_test_RMSE": prev_rmse,
        "candidate_method_id": selected_method(new_row),
        "candidate_experiment_id": selected_experiment(new_row),
        "candidate_val_AQL": new_val,
        "candidate_test_AQL": new_test,
        "candidate_test_MAE": new_mae,
        "candidate_test_RMSE": new_rmse,
        "val_delta_vs_current": val_delta,
        "test_delta_vs_current": test_delta,
        "mae_delta_vs_current": mae_delta,
        "rmse_delta_vs_current": rmse_delta,
        "validation_improved": validation_improved,
        "tiny_val_gain": tiny_val_gain,
        "test_aql_deterioration": test_aql_deterioration,
        "test_rmse_deterioration": test_rmse_deterioration,
        "severe_test_instability": severe_test_instability,
        "candidate_converged": conv,
        "convergence_risk": convergence_risk,
        "promotion_recommended": decision == "promote_candidate",
        "final_decision": decision,
    }


def make_decision_table(previous, new, args):
    rows = []
    for _, new_row in new.sort_values(["region", "fold"]).iterrows():
        region = str(new_row["region"])
        fold = int(new_row["fold"])
        sub = previous[
            previous["region"].astype(str).eq(region)
            & previous["fold"].astype(int).eq(fold)
        ]
        if sub.empty:
            raise ValueError("Previous registry is missing region={} fold={}".format(region, fold))
        rows.append(comparison_row(sub.iloc[0], new_row, args))
    return sort_region_fold(pd.DataFrame(rows))


def with_metadata(frame, args):
    out = frame.copy()
    out["input_scope"] = args.input_scope
    out["output_scope"] = args.output_scope
    out["lead_covariate_status"] = args.lead_covariate_status
    out["spatial_information_set"] = "local_only_not_pricefm_graph"
    return out


def normalize_final_row(row, source_label, args):
    out = row.to_dict()
    method = selected_method(row)
    exp = selected_experiment(row)
    out["method_id"] = method
    out["selected_method_id"] = method
    out["experiment_id"] = exp
    out["selection_metric"] = out.get("selection_metric", "AQL")
    out["selection_metric_value"] = selected_val_aql(row)
    out["selection_AQL"] = selected_val_aql(row)
    out["test_AQL"] = selected_test_aql(row)
    out["test_MAE"] = selected_test_mae(row)
    out["test_RMSE"] = selected_test_rmse(row)
    out["candidate_source"] = source_label
    return out


def merged_registry(previous, new, decisions, args):
    rows = []
    previous = previous.copy()
    new = new.copy()
    for _, dec in decisions.iterrows():
        region = str(dec["region"])
        fold = int(dec["fold"])
        prev_row = previous[
            previous["region"].astype(str).eq(region)
            & previous["fold"].astype(int).eq(fold)
        ].iloc[0]
        new_row = new[
            new["region"].astype(str).eq(region)
            & new["fold"].astype(int).eq(fold)
        ].iloc[0]
        use_new = str(dec["final_decision"]) == "promote_candidate"
        base = normalize_final_row(new_row if use_new else prev_row, args.candidate_source if use_new else text_value(prev_row, "candidate_source_final", "candidate_source", default="previous"), args)
        for key, value in dec.to_dict().items():
            base[key] = value
        base["changed_from_current"] = bool(use_new)
        base["candidate_source_final"] = args.candidate_source if use_new else text_value(prev_row, "candidate_source_final", "candidate_source", default="previous")
        base["selection_is_validation_only"] = True
        rows.append(base)
    return with_metadata(sort_region_fold(pd.DataFrame(rows)), args)


def stability_flags(decisions):
    cols = [
        "region", "fold", "final_decision", "validation_improved",
        "tiny_val_gain", "test_aql_deterioration", "test_rmse_deterioration",
        "severe_test_instability", "candidate_converged", "convergence_risk",
        "val_delta_vs_current", "test_delta_vs_current", "rmse_delta_vs_current",
    ]
    return decisions[[c for c in cols if c in decisions.columns]].copy()


def region_summary(decisions):
    rows = []
    for region, sub in decisions.groupby("region"):
        rows.append({
            "region": region,
            "n_folds": int(len(sub)),
            "n_validation_improved": int(sub["validation_improved"].sum()),
            "n_promote_candidate": int(sub["promotion_recommended"].sum()),
            "n_review": int(sub["final_decision"].astype(str).str.startswith("review").sum()),
            "mean_val_delta": float(sub["val_delta_vs_current"].mean()),
            "mean_test_delta": float(sub["test_delta_vs_current"].mean()),
            "mean_rmse_delta": float(sub["rmse_delta_vs_current"].mean()),
        })
    return pd.DataFrame(rows).sort_values("region").reset_index(drop=True)


def method_counts(registry):
    return (
        registry.groupby(["method_id", "final_decision"], dropna=False)
        .size()
        .reset_index(name="n")
        .sort_values(["final_decision", "method_id"])
        .reset_index(drop=True)
    )


def source_counts(registry):
    cols = ["candidate_source_final", "final_decision"]
    return (
        registry.groupby(cols, dropna=False)
        .size()
        .reset_index(name="n")
        .sort_values(cols)
        .reset_index(drop=True)
    )


def spec_summary(registry):
    cols = ["depth", "units", "input_scale", "alpha", "rho", "method_id", "final_decision"]
    present = [c for c in cols if c in registry.columns]
    return (
        registry.groupby(present, dropna=False)
        .size()
        .reset_index(name="n")
        .sort_values(["final_decision", "n"], ascending=[True, False])
        .reset_index(drop=True)
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
        frame = frame[[c for c in columns if c in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[c]) for c in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, args, decisions, registry, reg_summary):
    path = out_dir / "local_ar_closeout_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Region-Panel Median Local-AR Closeout\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id or "unknown"))
        f.write("Candidate source: `{}`\n\n".format(args.candidate_source))
        f.write("Selection rule: validation AQL on original scale. Test metrics are audit fields only.\n\n")
        f.write("Input scope: `{}`  \n".format(args.input_scope))
        f.write("Output scope: `{}`  \n".format(args.output_scope))
        f.write("Lead covariate status: `{}`\n\n".format(args.lead_covariate_status))
        f.write("## Decision Counts\n\n")
        f.write(markdown_table(decisions["final_decision"].value_counts().rename_axis("final_decision").reset_index(name="n")))
        f.write("\n\n## Decisions\n\n")
        f.write(markdown_table(
            decisions,
            columns=[
                "region", "fold", "current_experiment_id", "candidate_experiment_id",
                "candidate_method_id", "candidate_val_AQL", "val_delta_vs_current",
                "candidate_test_AQL", "test_delta_vs_current", "rmse_delta_vs_current",
                "candidate_converged", "final_decision",
            ],
        ))
        f.write("\n\n## Region Summary\n\n")
        f.write(markdown_table(reg_summary))
        f.write("\n\n## Final Registry\n\n")
        f.write(markdown_table(
            registry,
            columns=[
                "region", "fold", "method_id", "experiment_id", "selection_AQL",
                "test_AQL", "test_RMSE", "depth", "units", "alpha", "rho",
                "input_scale", "candidate_source_final", "final_decision",
            ],
        ))
        f.write("\n\n## Notes\n\n")
        f.write("- Review rows keep the previous authoritative row in the merged registry until manually resolved.\n")
        f.write("- The local-AR run is a local target-region information set, not PriceFM's spatial graph information set.\n")
        f.write("- D4/D5 follow-up should target only folds with credible depth signal.\n")
    return path


def copy_candidate_metrics(previous_registry_csv, new_registry_dir, out_dir, args):
    frames = []
    prev_dir = repo_path(previous_registry_csv).parent
    prev_metrics = read_csv_optional(prev_dir / "merged_candidate_metrics.csv")
    if prev_metrics is not None:
        prev_metrics = prev_metrics.copy()
        prev_metrics["candidate_source_closeout"] = "previous_authoritative"
        frames.append(prev_metrics)
    new_metrics = read_csv_optional(repo_path(new_registry_dir) / "median_candidate_metrics.csv")
    if new_metrics is not None:
        new_metrics = new_metrics.copy()
        new_metrics["candidate_source_closeout"] = args.candidate_source
        frames.append(new_metrics)
    if not frames:
        return None
    out = pd.concat(frames, ignore_index=True, sort=False)
    out.to_csv(out_dir / "merged_candidate_metrics.csv", index=False)
    return out


def closeout(args):
    new_dir = repo_path(args.new_registry_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    previous = read_csv_required(args.previous_registry_csv, "previous registry")
    new = read_csv_required(new_dir / "median_selection_registry.csv", "new median registry")
    decisions = make_decision_table(previous, new, args)
    registry = merged_registry(previous, new, decisions, args)
    flags = stability_flags(decisions)
    reg_summary = region_summary(decisions)
    methods = method_counts(registry)
    sources = source_counts(registry)
    specs = spec_summary(registry)
    candidates = copy_candidate_metrics(args.previous_registry_csv, new_dir, out_dir, args)

    decisions.to_csv(out_dir / "promotion_decisions.csv", index=False)
    decisions.to_csv(out_dir / "winner_changes_vs_previous.csv", index=False)
    registry.to_csv(out_dir / "merged_selection_registry.csv", index=False)
    flags.to_csv(out_dir / "stability_flags.csv", index=False)
    reg_summary.to_csv(out_dir / "region_summary.csv", index=False)
    methods.to_csv(out_dir / "method_counts.csv", index=False)
    sources.to_csv(out_dir / "source_counts.csv", index=False)
    specs.to_csv(out_dir / "spec_summary.csv", index=False)
    report = write_report(out_dir, args, decisions, registry, reg_summary)

    summary = {
        "grid_id": args.grid_id,
        "candidate_source": args.candidate_source,
        "previous_registry_csv": config_path_value(args.previous_registry_csv),
        "new_registry_dir": config_path_value(args.new_registry_dir),
        "output_dir": config_path_value(out_dir),
        "input_scope": args.input_scope,
        "output_scope": args.output_scope,
        "lead_covariate_status": args.lead_covariate_status,
        "n_region_folds": int(len(decisions)),
        "n_validation_improved": int(decisions["validation_improved"].sum()),
        "n_promote_candidate": int(decisions["promotion_recommended"].sum()),
        "n_review": int(decisions["final_decision"].astype(str).str.startswith("review").sum()),
        "n_keep_previous": int(decisions["final_decision"].astype(str).str.startswith("keep_previous").sum()),
        "mean_val_delta": float(decisions["val_delta_vs_current"].mean()),
        "mean_test_delta": float(decisions["test_delta_vs_current"].mean()),
        "mean_rmse_delta": float(decisions["rmse_delta_vs_current"].mean()),
        "outputs": {
            "promotion_decisions": config_path_value(out_dir / "promotion_decisions.csv"),
            "merged_selection_registry": config_path_value(out_dir / "merged_selection_registry.csv"),
            "stability_flags": config_path_value(out_dir / "stability_flags.csv"),
            "region_summary": config_path_value(out_dir / "region_summary.csv"),
            "method_counts": config_path_value(out_dir / "method_counts.csv"),
            "source_counts": config_path_value(out_dir / "source_counts.csv"),
            "spec_summary": config_path_value(out_dir / "spec_summary.csv"),
            "merged_candidate_metrics": config_path_value(out_dir / "merged_candidate_metrics.csv") if candidates is not None else None,
            "report": config_path_value(report),
        },
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = closeout(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
