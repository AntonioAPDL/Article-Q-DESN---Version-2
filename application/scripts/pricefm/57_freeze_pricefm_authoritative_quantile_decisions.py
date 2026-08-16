#!/usr/bin/env python3
"""Merge frozen PriceFM quantile decisions into one authoritative registry.

Decision sources are supplied in precedence order from lowest to highest.
When the same region/fold appears in multiple sources, the later source wins.
The merged output must cover every region/fold in the median registry exactly
once.
"""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import repo_path, write_json
from pricefm_graph import graph_hash


DECISION_COL = "stage_c_quantile_decision"
PROMOTED_LABEL = "stage_c_confirmed_local_win"
CLOSE_LABEL = "stage_c_local_close_to_pricefm"
FALLBACK_LABEL = "stage_c_pricefm_fallback"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--median-registry-csv", required=True)
    p.add_argument(
        "--decision-source",
        action="append",
        default=[],
        help="Frozen decision source as label=path, in increasing precedence order.",
    )
    p.add_argument("--output-dir", required=True)
    p.add_argument("--registry-id", default="pricefm_authoritative_quantile_decisions")
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


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def normalize_keys(frame):
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    return out


def validate_unique_region_folds(frame, context):
    require_columns(frame, ["region", "fold"], context)
    keys = normalize_keys(frame[["region", "fold"]])
    dup = keys[keys.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        raise ValueError(
            "{} has duplicate region/fold rows:\n{}".format(
                context, dup.to_string(index=False)
            )
        )


def parse_decision_source(value):
    if "=" not in str(value):
        raise ValueError("--decision-source must have form label=path")
    label, path = str(value).split("=", 1)
    label = label.strip()
    path = path.strip()
    if not label or not path:
        raise ValueError("--decision-source must have non-empty label and path")
    return label, path


def drop_prior_median_registry_columns(frame):
    """Allow prior authoritative registries as decision sources.

    Authoritative outputs already include columns merged from their historical
    median registry, named ``*_median_registry``.  Those columns must not be
    carried into a later merge with a newer median registry, otherwise pandas
    can create duplicate suffixed names.  The decision columns themselves are
    unsuffixed, so dropping only these historical median columns preserves the
    selected decision while letting the current median registry be the source of
    record for median-stage metadata.
    """
    drop_cols = [col for col in frame.columns if col.endswith("_median_registry")]
    if not drop_cols:
        return frame
    return frame.drop(columns=drop_cols)


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def normalize_feature_metadata(frame):
    """Coalesce and normalize feature-policy metadata after source/median merge."""
    out = frame.copy()
    metadata = [
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set", "graph_degree",
        "graph_source", "graph_hash",
    ]
    for col in metadata:
        median_col = "{}_median_registry".format(col)
        if col in out.columns:
            out[col] = out[col].astype("object")
        if median_col in out.columns:
            out[median_col] = out[median_col].astype("object")
        if col not in out.columns and median_col in out.columns:
            out[col] = out[median_col]
        elif col in out.columns and median_col in out.columns:
            blank = out[col].isna() | out[col].astype(str).eq("")
            out.loc[blank, col] = out.loc[blank, median_col]
    if "feature_policy" not in out.columns:
        return out

    for col in [
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set",
        "graph_source", "graph_hash",
    ]:
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
            blank = out[col].isna() | out[col].astype(str).eq("")
            out.loc[local_mask & blank, col] = default
    return out


def read_sources(values):
    if not values:
        raise ValueError("At least one --decision-source is required")
    frames = []
    metadata = []
    for precedence, value in enumerate(values, start=1):
        label, path = parse_decision_source(value)
        frame = read_csv_required(path, "decision source {}".format(label))
        require_columns(frame, ["region", "fold", DECISION_COL], label)
        validate_unique_region_folds(frame, label)
        frame = drop_prior_median_registry_columns(frame)
        frame = normalize_keys(frame)
        frame["decision_source"] = label
        frame["decision_source_path"] = config_path_value(path)
        frame["decision_precedence"] = precedence
        frames.append(frame)
        metadata.append({
            "label": label,
            "path": config_path_value(path),
            "precedence": precedence,
            "rows": int(frame.shape[0]),
        })
    return pd.concat(frames, ignore_index=True), metadata


def freeze(args):
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    median = read_csv_required(args.median_registry_csv, "median registry")
    validate_unique_region_folds(median, "median registry")
    median = normalize_keys(median)
    median_keys = median[["region", "fold"]].copy()

    all_decisions, source_meta = read_sources(args.decision_source)
    selected = (
        all_decisions.sort_values(["region", "fold", "decision_precedence"])
        .groupby(["region", "fold"], as_index=False)
        .tail(1)
        .sort_values(["region", "fold"])
        .reset_index(drop=True)
    )

    coverage = median_keys.merge(
        selected[["region", "fold", "decision_source", DECISION_COL]],
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
    )
    missing = coverage[coverage[DECISION_COL].isna()].copy()
    extra = selected.merge(median_keys, on=["region", "fold"], how="left", indicator=True)
    extra = extra[extra["_merge"].eq("left_only")].copy()
    if not missing.empty or not extra.empty:
        raise ValueError(
            "Decision coverage mismatch: missing={} extra={}".format(
                missing[["region", "fold"]].to_dict("records"),
                extra[["region", "fold", "decision_source"]].to_dict("records"),
            )
        )

    merged = selected.merge(
        median,
        on=["region", "fold"],
        how="left",
        suffixes=("", "_median_registry"),
        validate="one_to_one",
    )
    merged = normalize_feature_metadata(merged)
    validate_unique_region_folds(merged, "authoritative decision registry")

    registry_path = out_dir / "authoritative_quantile_decision_registry.csv"
    merged.to_csv(registry_path, index=False)

    promoted = merged[merged[DECISION_COL].eq(PROMOTED_LABEL)].copy()
    close = merged[merged[DECISION_COL].eq(CLOSE_LABEL)].copy()
    fallback = merged[merged[DECISION_COL].eq(FALLBACK_LABEL)].copy()
    promoted.to_csv(out_dir / "authoritative_quantile_promoted_local_registry.csv", index=False)
    close.to_csv(out_dir / "authoritative_quantile_close_registry.csv", index=False)
    fallback.to_csv(out_dir / "authoritative_quantile_pricefm_fallback_registry.csv", index=False)

    source_counts = (
        merged.groupby(["decision_source", DECISION_COL], as_index=False)
        .size()
        .rename(columns={"size": "n_region_folds"})
        .sort_values(["decision_source", DECISION_COL])
    )
    source_counts_path = out_dir / "authoritative_quantile_source_counts.csv"
    source_counts.to_csv(source_counts_path, index=False)

    mean_fields = {}
    for col in ["local_AQL", "pricefm_AQL", "delta_abs", "delta_rel"]:
        if col in merged.columns:
            mean_fields["mean_{}".format(col)] = float(numeric(merged[col]).mean())

    summary = {
        "status": "completed",
        "registry_id": args.registry_id,
        "notes": args.notes,
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "decision_sources": source_meta,
        "output_dir": config_path_value(out_dir),
        "n_region_folds": int(merged.shape[0]),
        "n_promoted_local": int(promoted.shape[0]),
        "n_close_to_pricefm": int(close.shape[0]),
        "n_pricefm_fallback": int(fallback.shape[0]),
        **mean_fields,
        "outputs": {
            "authoritative_registry": config_path_value(registry_path),
            "promoted_local_registry": config_path_value(out_dir / "authoritative_quantile_promoted_local_registry.csv"),
            "close_registry": config_path_value(out_dir / "authoritative_quantile_close_registry.csv"),
            "pricefm_fallback_registry": config_path_value(out_dir / "authoritative_quantile_pricefm_fallback_registry.csv"),
            "source_counts": config_path_value(source_counts_path),
        },
    }
    write_json(out_dir / "summary.json", summary)
    write_report(out_dir / "authoritative_quantile_decision_report.md", summary, merged, source_counts)
    return summary


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


def write_report(path, summary, decisions, source_counts):
    with open(path, "w") as f:
        f.write("# PriceFM Authoritative Quantile Decisions\n\n")
        if str(summary.get("notes", "")).strip():
            f.write("{}\n\n".format(str(summary["notes"]).strip()))
        f.write("## Summary\n\n")
        f.write("- Region/folds: `{}`\n".format(summary["n_region_folds"]))
        f.write("- Local promotions: `{}`\n".format(summary["n_promoted_local"]))
        f.write("- Close local losses: `{}`\n".format(summary["n_close_to_pricefm"]))
        f.write("- PriceFM fallbacks: `{}`\n\n".format(summary["n_pricefm_fallback"]))
        f.write("## Source Counts\n\n")
        f.write(markdown_table(source_counts, ["decision_source", DECISION_COL, "n_region_folds"]))
        f.write("\n\n## Decisions\n\n")
        f.write(markdown_table(
            decisions,
            [
                "region", "fold", "decision_source", "best_local_method",
                "local_AQL", "pricefm_AQL", "delta_abs", "delta_rel",
                DECISION_COL, "stage_c_recommendation",
            ],
        ))
        f.write("\n")


def main():
    args = parser().parse_args()
    summary = freeze(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
