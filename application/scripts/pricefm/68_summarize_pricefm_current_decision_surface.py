#!/usr/bin/env python3
"""Summarize the current PriceFM local-vs-PriceFM decision surface."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv"
)
DEFAULT_QUANTILE_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_quantile_decision_registry.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--median-registry-csv", default=DEFAULT_MEDIAN_REGISTRY)
    p.add_argument("--quantile-decision-registry-csv", default=DEFAULT_QUANTILE_REGISTRY)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-region-folds", type=int, default=42)
    p.add_argument("--make-figures", type=parse_bool, default=True)
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


def require_columns(frame, columns, label):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(label, sorted(missing)))


def normalize_keys(frame, label):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    dup = out[out.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        keys = (
            dup[["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("{} has duplicate region/fold keys: {}".format(label, keys))
    return out


def numeric_column(frame, col, label, required=True):
    if col not in frame.columns:
        if required:
            raise ValueError("{} missing required numeric column {}".format(label, col))
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    vals = pd.to_numeric(frame[col], errors="coerce")
    if required and vals.isna().any():
        bad = frame.loc[vals.isna(), ["region", "fold"]].to_dict("records")
        raise ValueError("{} has non-finite {} rows: {}".format(label, col, bad))
    return vals


def first_nonblank(row, names, default=""):
    for name in names:
        if name in row.index:
            val = row[name]
            if pd.notna(val) and str(val) != "":
                return val
    return default


def method_family(method_id):
    text = str(method_id)
    if text.startswith("qdesn_exal"):
        return "qdesn_exal"
    if text.startswith("qdesn_al"):
        return "qdesn_al"
    if text.startswith("normal"):
        return "normal_desn"
    return "other"


def information_set(row):
    policy = str(first_nonblank(row, ["feature_policy", "feature_policy_median_registry"], "")).lower()
    scope = str(first_nonblank(row, ["input_scope", "input_scope_median_registry"], "")).lower()
    spatial = str(first_nonblank(row, ["spatial_information_set", "spatial_information_set_median_registry"], "")).lower()
    if (
        "target_only" in policy
        or "local_target_only" in scope
        or "local_only_not_pricefm_graph" in spatial
    ):
        return "target_only"
    if "graph" in policy or "graph" in scope or "graph" in spatial:
        return "pricefm_graph_inputs"
    if "local" in policy or "target" in policy or "local" in scope or "local" in spatial:
        return "target_only"
    return "unknown"


def decision_label(delta_abs, delta_rel):
    if delta_abs < 0.0:
        return "local_beats_pricefm"
    if pd.notna(delta_rel) and delta_rel <= 0.05:
        return "local_close_to_pricefm"
    return "pricefm_better"


def build_surface(median, quantile, expected_region_folds):
    median = normalize_keys(median, "median registry")
    quantile = normalize_keys(quantile, "quantile decision registry")
    if int(expected_region_folds) > 0 and len(quantile) != int(expected_region_folds):
        raise ValueError(
            "Expected {} region/folds, found {}".format(expected_region_folds, len(quantile))
        )
    require_columns(quantile, ["local_AQL", "pricefm_AQL", "delta_abs"], "quantile decision registry")
    quantile["local_AQL"] = numeric_column(quantile, "local_AQL", "quantile decision registry")
    quantile["pricefm_AQL"] = numeric_column(quantile, "pricefm_AQL", "quantile decision registry")
    quantile["delta_abs"] = numeric_column(quantile, "delta_abs", "quantile decision registry")
    if "delta_rel" in quantile.columns:
        quantile["delta_rel"] = pd.to_numeric(quantile["delta_rel"], errors="coerce")
    else:
        quantile["delta_rel"] = quantile["delta_abs"] / quantile["pricefm_AQL"].abs().clip(lower=1.0e-8)

    merged = quantile.merge(
        median[["region", "fold"]],
        on=["region", "fold"],
        how="left",
        indicator=True,
        validate="one_to_one",
    )
    missing = merged[merged["_merge"].eq("left_only")][["region", "fold"]]
    if not missing.empty:
        raise ValueError("Quantile rows absent from median registry: {}".format(missing.to_dict("records")))

    rows = []
    for _, row in quantile.iterrows():
        method = str(first_nonblank(row, ["best_local_method", "selected_method_id"], ""))
        if not method:
            method = str(first_nonblank(row, ["selected_method_id_median_registry"], ""))
        delta = float(row["delta_abs"])
        rel = float(row["delta_rel"]) if pd.notna(row["delta_rel"]) else float("nan")
        rows.append({
            "region": str(row["region"]),
            "fold": int(row["fold"]),
            "best_local_method": method,
            "model_family": method_family(method),
            "information_set": information_set(row),
            "local_AQL": float(row["local_AQL"]),
            "pricefm_AQL": float(row["pricefm_AQL"]),
            "delta_abs": delta,
            "delta_rel": rel,
            "local_wins": bool(delta < 0.0),
            "decision_label": decision_label(delta, rel),
            "stage_c_quantile_decision": str(first_nonblank(row, ["stage_c_quantile_decision"], "")),
            "stage_c_recommendation": str(first_nonblank(row, ["stage_c_recommendation"], "")),
            "experiment_id": str(first_nonblank(row, ["experiment_id"], "")),
            "selected_method_id_median": str(first_nonblank(row, ["selected_method_id_median_registry", "selected_method_id"], "")),
            "median_selection_AQL": pd.to_numeric(pd.Series([first_nonblank(row, ["selection_AQL", "selection_AQL_median_registry"], float("nan"))]), errors="coerce").iloc[0],
            "median_test_AQL": pd.to_numeric(pd.Series([first_nonblank(row, ["test_AQL", "test_AQL_median_registry"], float("nan"))]), errors="coerce").iloc[0],
            "feature_policy": str(first_nonblank(row, ["feature_policy", "feature_policy_median_registry"], "")),
            "input_scope": str(first_nonblank(row, ["input_scope", "input_scope_median_registry"], "")),
            "spatial_information_set": str(first_nonblank(row, ["spatial_information_set", "spatial_information_set_median_registry"], "")),
            "graph_degree": first_nonblank(row, ["graph_degree", "graph_degree_median_registry"], ""),
            "lag_window": first_nonblank(row, ["lag_window", "lag_window_median_registry"], ""),
            "depth": first_nonblank(row, ["depth", "depth_median_registry"], ""),
            "units": str(first_nonblank(row, ["units", "units_median_registry"], "")),
            "seed": first_nonblank(row, ["seed", "seed_median_registry"], ""),
            "run_dir": str(first_nonblank(row, ["run_dir", "run_dir_median_registry"], "")),
        })
    return pd.DataFrame(rows).sort_values(["fold", "region"]).reset_index(drop=True)


def aggregate(frame, group_cols):
    if not group_cols:
        grouped = [("overall", frame)]
    else:
        grouped = frame.groupby(group_cols, dropna=False)
    rows = []
    for key, sub in grouped:
        if not isinstance(key, tuple):
            key = (key,)
        row = {col: val for col, val in zip(group_cols or ["group"], key)}
        row.update({
            "n_region_folds": int(sub.shape[0]),
            "n_local_wins": int(sub["local_wins"].sum()),
            "win_rate": float(sub["local_wins"].mean()) if len(sub) else float("nan"),
            "mean_local_AQL": float(sub["local_AQL"].mean()),
            "mean_pricefm_AQL": float(sub["pricefm_AQL"].mean()),
            "mean_delta_abs": float(sub["delta_abs"].mean()),
            "median_delta_abs": float(sub["delta_abs"].median()),
            "min_delta_abs": float(sub["delta_abs"].min()),
            "max_delta_abs": float(sub["delta_abs"].max()),
        })
        rows.append(row)
    return pd.DataFrame(rows)


def markdown_table(frame, max_rows=20):
    if frame.empty:
        return "_No rows._"
    show = frame.head(max_rows).copy()
    lines = ["| " + " | ".join(show.columns) + " |"]
    lines.append("|" + "|".join(["---"] * len(show.columns)) + "|")
    for _, row in show.iterrows():
        vals = []
        for col in show.columns:
            val = row[col]
            if isinstance(val, float):
                vals.append("{:.6g}".format(val))
            else:
                vals.append(str(val).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > max_rows:
        lines.append("| ... | " + " | ".join([""] * (len(show.columns) - 1)) + " |")
    return "\n".join(lines)


def make_figures(out_dir, surface):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig_dir = out_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    paths = []

    ordered = surface.sort_values(["fold", "delta_abs", "region"]).copy()
    ordered["label"] = ordered["region"] + " f" + ordered["fold"].astype(str)
    colors = ["#2f7d32" if x else "#b3261e" for x in ordered["local_wins"]]
    fig, ax = plt.subplots(figsize=(12, 6))
    ax.bar(range(len(ordered)), ordered["delta_abs"], color=colors)
    ax.axhline(0.0, color="black", linewidth=0.8)
    ax.set_xticks(range(len(ordered)))
    ax.set_xticklabels(ordered["label"], rotation=90, fontsize=7)
    ax.set_ylabel("AQL delta: local - PriceFM")
    ax.set_title("Current PriceFM Decision Surface By Region/Fold")
    fig.tight_layout()
    path = fig_dir / "stage_m_aql_delta_by_region_fold.png"
    fig.savefig(path, dpi=160)
    plt.close(fig)
    paths.append(path)

    fold = aggregate(surface, ["fold"]).sort_values("fold")
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.bar(fold["fold"].astype(str), fold["n_local_wins"], color="#3366aa")
    ax.set_ylabel("Local wins")
    ax.set_xlabel("Fold")
    ax.set_title("Local Wins Over PriceFM By Fold")
    ax.set_ylim(0, max(fold["n_region_folds"].max(), 1))
    fig.tight_layout()
    path = fig_dir / "stage_m_local_wins_by_fold.png"
    fig.savefig(path, dpi=160)
    plt.close(fig)
    paths.append(path)

    return [config_path_value(p) for p in paths]


def write_report(out_dir, surface, overall, by_fold, by_method, by_info, figures):
    report = out_dir / "current_decision_surface_summary_report.md"
    top_wins = surface.sort_values("delta_abs").head(10)
    top_losses = surface.sort_values("delta_abs", ascending=False).head(10)
    with open(report, "w") as f:
        f.write("# PriceFM Stage-M Current Decision Surface\n\n")
        f.write("This report summarizes the current frozen local DESN/Q-DESN versus ")
        f.write("PriceFM Phase-I decision surface. Negative deltas mean the local ")
        f.write("model has lower AQL than PriceFM.\n\n")
        f.write("## Overall\n\n")
        f.write(markdown_table(overall))
        f.write("\n\n## By Fold\n\n")
        f.write(markdown_table(by_fold))
        f.write("\n\n## By Method Family\n\n")
        f.write(markdown_table(by_method))
        f.write("\n\n## By Information Set\n\n")
        f.write(markdown_table(by_info))
        f.write("\n\n## Largest Local Wins\n\n")
        f.write(markdown_table(top_wins[["region", "fold", "best_local_method", "local_AQL", "pricefm_AQL", "delta_abs"]]))
        f.write("\n\n## Largest PriceFM Wins\n\n")
        f.write(markdown_table(top_losses[["region", "fold", "best_local_method", "local_AQL", "pricefm_AQL", "delta_abs"]]))
        if figures:
            f.write("\n\n## Figures\n\n")
            for path in figures:
                f.write("- `{}`\n".format(path))
        f.write("\n")
    return report


def summarize(args):
    median = read_csv_required(args.median_registry_csv, "median registry")
    quantile = read_csv_required(args.quantile_decision_registry_csv, "quantile decision registry")
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    surface = build_surface(median, quantile, args.expected_region_folds)
    overall = aggregate(surface, [])
    by_fold = aggregate(surface, ["fold"]).sort_values("fold")
    by_method = aggregate(surface, ["model_family"]).sort_values("mean_delta_abs")
    by_info = aggregate(surface, ["information_set"]).sort_values("mean_delta_abs")
    top = pd.concat([
        surface.sort_values("delta_abs").head(10).assign(rank_type="largest_local_win"),
        surface.sort_values("delta_abs", ascending=False).head(10).assign(rank_type="largest_pricefm_win"),
    ], ignore_index=True)

    surface.to_csv(out_dir / "current_decision_surface_table.csv", index=False)
    overall.to_csv(out_dir / "aggregate_overall.csv", index=False)
    by_fold.to_csv(out_dir / "aggregate_by_fold.csv", index=False)
    by_method.to_csv(out_dir / "aggregate_by_method_family.csv", index=False)
    by_info.to_csv(out_dir / "aggregate_by_information_set.csv", index=False)
    top.to_csv(out_dir / "top_wins_losses.csv", index=False)
    figures = make_figures(out_dir, surface) if bool(args.make_figures) else []
    report = write_report(out_dir, surface, overall, by_fold, by_method, by_info, figures)
    summary = {
        "n_region_folds": int(surface.shape[0]),
        "n_local_wins": int(surface["local_wins"].sum()),
        "n_pricefm_wins": int((~surface["local_wins"]).sum()),
        "mean_delta_abs": float(surface["delta_abs"].mean()),
        "median_delta_abs": float(surface["delta_abs"].median()),
        "median_registry_csv": config_path_value(args.median_registry_csv),
        "quantile_decision_registry_csv": config_path_value(args.quantile_decision_registry_csv),
        "output_dir": config_path_value(out_dir),
        "report": config_path_value(report),
        "figures": figures,
    }
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    print(json.dumps(summarize(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
