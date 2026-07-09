#!/usr/bin/env python3
"""Close out graph-neighbor median candidates against local median winners.

This closeout is deliberately validation-only: graph-neighbor candidates are
promoted only when their validation AQL improves over the current local
region/fold winner. Test metrics are copied as audit fields, never as hidden
selection criteria.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_CANDIDATE_SOURCE = "graph_khop_degree1_20260614"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--local-registry-csv", required=True)
    p.add_argument("--graph-registry-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--grid-id", default="pricefm_graph_local_median_closeout_20260614")
    p.add_argument("--candidate-source", default=DEFAULT_CANDIDATE_SOURCE)
    p.add_argument("--validation-tolerance", type=float, default=0.0)
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


def numeric_value(row, *names):
    for name in names:
        if name in row.index and pd.notna(row[name]):
            try:
                return float(row[name])
            except (TypeError, ValueError):
                pass
    return float("nan")


def text_value(row, *names, default=""):
    for name in names:
        if name in row.index and pd.notna(row[name]):
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


def key_frame(frame, label):
    required = {"region", "fold", "experiment_id"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError("{} registry missing columns: {}".format(label, sorted(missing)))
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    if out.duplicated(["region", "fold"]).any():
        dup = out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
        raise ValueError("{} registry has duplicate region/fold rows: {}".format(
            label, dup.drop_duplicates().to_dict("records")
        ))
    return out


def assert_same_region_folds(local, graph):
    local_keys = set(zip(local["region"], local["fold"]))
    graph_keys = set(zip(graph["region"], graph["fold"]))
    if local_keys != graph_keys:
        missing_graph = sorted(local_keys - graph_keys)
        extra_graph = sorted(graph_keys - local_keys)
        raise ValueError(
            "Graph/local registries must cover the same region/fold keys. "
            "missing_graph={} extra_graph={}".format(missing_graph, extra_graph)
        )


def comparison_row(local_row, graph_row, args):
    local_val = selected_val_aql(local_row)
    graph_val = selected_val_aql(graph_row)
    local_test = selected_test_aql(local_row)
    graph_test = selected_test_aql(graph_row)
    local_mae = selected_test_mae(local_row)
    graph_mae = selected_test_mae(graph_row)
    local_rmse = selected_test_rmse(local_row)
    graph_rmse = selected_test_rmse(graph_row)
    val_delta = graph_val - local_val
    test_delta = graph_test - local_test
    mae_delta = graph_mae - local_mae
    rmse_delta = graph_rmse - local_rmse
    validation_improved = bool(pd.notna(val_delta) and val_delta < -float(args.validation_tolerance))
    final_decision = (
        "promote_graph_validation_win"
        if validation_improved
        else "keep_local_validation_not_improved"
    )
    return {
        "region": text_value(local_row, "region"),
        "fold": int(local_row["fold"]),
        "local_method_id": selected_method(local_row),
        "local_experiment_id": selected_experiment(local_row),
        "local_val_AQL": local_val,
        "local_test_AQL": local_test,
        "local_test_MAE": local_mae,
        "local_test_RMSE": local_rmse,
        "graph_method_id": selected_method(graph_row),
        "graph_experiment_id": selected_experiment(graph_row),
        "graph_val_AQL": graph_val,
        "graph_test_AQL": graph_test,
        "graph_test_MAE": graph_mae,
        "graph_test_RMSE": graph_rmse,
        "val_delta_graph_minus_local": val_delta,
        "test_delta_graph_minus_local": test_delta,
        "mae_delta_graph_minus_local": mae_delta,
        "rmse_delta_graph_minus_local": rmse_delta,
        "validation_improved": validation_improved,
        "test_improved": bool(pd.notna(test_delta) and test_delta < 0.0),
        "promotion_recommended": validation_improved,
        "selected_source": "graph" if validation_improved else "local",
        "final_decision": final_decision,
    }


def make_decision_table(local, graph, args):
    rows = []
    graph_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in graph.iterrows()
    }
    for _, local_row in local.sort_values(["region", "fold"]).iterrows():
        key = (str(local_row["region"]), int(local_row["fold"]))
        rows.append(comparison_row(local_row, graph_idx[key], args))
    return sort_region_fold(pd.DataFrame(rows))


def default_feature_metadata(row, selected_source):
    out = row.to_dict()
    policy = str(out.get("feature_policy", ""))
    if selected_source == "graph" or policy == "graph_khop":
        degree = int(float(out.get("graph_degree", 1)))
        out["feature_policy"] = "graph_khop"
        out["graph_degree"] = degree
        out.setdefault("graph_source", "PriceFM.graph_adj_matrix")
        out["input_scope"] = "pricefm_graph_khop_degree{}".format(degree)
        out["output_scope"] = "target_region_path"
        out["lead_covariate_status"] = "realized_ex_post"
        out["spatial_information_set"] = "pricefm_released_graph_khop"
    else:
        out.setdefault("feature_policy", "target_only")
        out.setdefault("input_scope", "local_target_only")
        out.setdefault("output_scope", "target_region_path")
        out.setdefault("lead_covariate_status", "realized_ex_post")
        out.setdefault("spatial_information_set", "local_only_not_pricefm_graph")
    return out


def normalize_final_row(row, selected_source, source_label):
    out = default_feature_metadata(row, selected_source)
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
    out["candidate_source_final"] = source_label
    out["selected_source"] = selected_source
    out["selection_is_validation_only"] = True
    out["selection_decision_rule"] = "graph_promoted_only_if_validation_AQL_improves"
    return out


def merged_registry(local, graph, decisions, args):
    local_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in local.iterrows()
    }
    graph_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in graph.iterrows()
    }
    rows = []
    for _, dec in decisions.iterrows():
        key = (str(dec["region"]), int(dec["fold"]))
        use_graph = bool(dec["promotion_recommended"])
        selected_source = "graph" if use_graph else "local"
        source_label = (
            str(args.candidate_source)
            if use_graph
            else text_value(
                local_idx[key],
                "candidate_source_final",
                "candidate_source",
                default="local_authoritative",
            )
        )
        base = normalize_final_row(
            graph_idx[key] if use_graph else local_idx[key],
            selected_source,
            source_label,
        )
        for k, v in dec.to_dict().items():
            base[k] = v
        base["changed_from_local"] = bool(use_graph)
        base["candidate_source_final"] = source_label
        base["selection_is_validation_only"] = True
        rows.append(base)
    return sort_region_fold(pd.DataFrame(rows))


def region_summary(decisions):
    rows = []
    for region, sub in decisions.groupby("region"):
        rows.append({
            "region": region,
            "n_folds": int(len(sub)),
            "n_graph_validation_improved": int(sub["validation_improved"].sum()),
            "n_graph_promoted": int(sub["promotion_recommended"].sum()),
            "n_graph_test_improved": int(sub["test_improved"].sum()),
            "mean_val_delta_graph_minus_local": float(sub["val_delta_graph_minus_local"].mean()),
            "mean_test_delta_graph_minus_local": float(sub["test_delta_graph_minus_local"].mean()),
            "mean_rmse_delta_graph_minus_local": float(sub["rmse_delta_graph_minus_local"].mean()),
        })
    return pd.DataFrame(rows).sort_values("region").reset_index(drop=True)


def counts_by(frame, columns):
    present = [c for c in columns if c in frame.columns]
    return (
        frame.groupby(present, dropna=False)
        .size()
        .reset_index(name="n")
        .sort_values(present)
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
    path = out_dir / "graph_neighbor_closeout_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Graph/Local Median Closeout\n\n")
        f.write("Grid: `{}`\n\n".format(args.grid_id))
        f.write("Graph candidate source: `{}`\n\n".format(args.candidate_source))
        f.write("Rule: promote graph-neighbor only if validation AQL improves over the local winner. ")
        f.write("Test metrics are audit fields only.\n\n")
        f.write("## Decision Counts\n\n")
        f.write(markdown_table(
            decisions["final_decision"].value_counts().rename_axis("final_decision").reset_index(name="n")
        ))
        f.write("\n\n## Decisions\n\n")
        f.write(markdown_table(
            decisions,
            columns=[
                "region", "fold", "local_experiment_id", "graph_experiment_id",
                "local_val_AQL", "graph_val_AQL", "val_delta_graph_minus_local",
                "local_test_AQL", "graph_test_AQL", "test_delta_graph_minus_local",
                "selected_source", "final_decision",
            ],
        ))
        f.write("\n\n## Region Summary\n\n")
        f.write(markdown_table(reg_summary))
        f.write("\n\n## Final Registry\n\n")
        f.write(markdown_table(
            registry,
            columns=[
                "region", "fold", "selected_source", "method_id", "experiment_id",
                "selection_AQL", "test_AQL", "feature_policy", "spatial_information_set",
                "graph_degree", "candidate_source_final", "final_decision",
            ],
        ))
        f.write("\n\n## Notes\n\n")
        f.write("- This is a median-only closeout used to seed the paper-quantile promotion grid.\n")
        f.write("- Graph promotion is validation-driven; test improvements do not promote a row by themselves.\n")
        f.write("- Local rows remain target-region-only; graph rows use the released PriceFM graph neighborhood as an input feature policy.\n")
    return path


def closeout(args):
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    local = key_frame(read_csv_required(args.local_registry_csv, "local registry"), "local")
    graph = key_frame(read_csv_required(args.graph_registry_csv, "graph registry"), "graph")
    assert_same_region_folds(local, graph)
    decisions = make_decision_table(local, graph, args)
    registry = merged_registry(local, graph, decisions, args)
    reg_summary = region_summary(decisions)
    method_counts = counts_by(registry, ["selected_source", "method_id"])
    source_counts = counts_by(registry, ["selected_source", "candidate_source_final"])
    policy_counts = counts_by(registry, ["selected_source", "feature_policy", "spatial_information_set"])

    decisions.to_csv(out_dir / "promotion_decisions.csv", index=False)
    decisions.to_csv(out_dir / "graph_vs_local_median_comparison.csv", index=False)
    registry.to_csv(out_dir / "merged_selection_registry.csv", index=False)
    reg_summary.to_csv(out_dir / "graph_vs_local_region_summary.csv", index=False)
    method_counts.to_csv(out_dir / "method_counts.csv", index=False)
    source_counts.to_csv(out_dir / "source_counts.csv", index=False)
    policy_counts.to_csv(out_dir / "feature_policy_counts.csv", index=False)
    report = write_report(out_dir, args, decisions, registry, reg_summary)

    summary = {
        "grid_id": args.grid_id,
        "candidate_source": args.candidate_source,
        "local_registry_csv": config_path_value(args.local_registry_csv),
        "graph_registry_csv": config_path_value(args.graph_registry_csv),
        "output_dir": config_path_value(out_dir),
        "selection_rule": "promote graph iff graph validation AQL improves over local",
        "test_metrics_role": "audit_only",
        "n_region_folds": int(len(decisions)),
        "n_graph_validation_improved": int(decisions["validation_improved"].sum()),
        "n_graph_promoted": int(decisions["promotion_recommended"].sum()),
        "n_local_kept": int((~decisions["promotion_recommended"]).sum()),
        "n_graph_test_improved": int(decisions["test_improved"].sum()),
        "mean_val_delta_graph_minus_local": float(decisions["val_delta_graph_minus_local"].mean()),
        "mean_test_delta_graph_minus_local": float(decisions["test_delta_graph_minus_local"].mean()),
        "outputs": {
            "promotion_decisions": config_path_value(out_dir / "promotion_decisions.csv"),
            "merged_selection_registry": config_path_value(out_dir / "merged_selection_registry.csv"),
            "graph_vs_local_region_summary": config_path_value(out_dir / "graph_vs_local_region_summary.csv"),
            "method_counts": config_path_value(out_dir / "method_counts.csv"),
            "source_counts": config_path_value(out_dir / "source_counts.csv"),
            "feature_policy_counts": config_path_value(out_dir / "feature_policy_counts.csv"),
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
