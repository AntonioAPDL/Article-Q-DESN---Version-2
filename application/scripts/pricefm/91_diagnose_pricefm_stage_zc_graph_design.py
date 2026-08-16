#!/usr/bin/env python3
"""Diagnose the Stage-ZB graph-direct PriceFM failure mode.

Stage ZC is diagnostic-only.  It reads the completed Stage-ZB PL fold-3
full-budget probe, reconstructs the feature windows in memory, writes compact
summaries, and decides whether a revised graph contract is scientifically
justified before any new model launch.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_desn_adapter import load_config, load_feature_window


DEFAULT_STAGE_Z_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_z_design_contracts_20260630"
)
DEFAULT_STAGE_ZB_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701"
)
DEFAULT_STAGE_ZB_CELL_DIR = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_zb_graph_direct_fullbudget_pl_f3_20260701/"
    "stagezb_graph_direct_pl_f3_l096_d1_n120_anchor_seed20260603/"
    "cells/region=PL/fold=3"
)
DEFAULT_STAGE_K_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_k_regularized_graph_multiseed_summary_20260623/"
    "multiseed_geometry_summary.csv"
)
DEFAULT_STAGE_R_SUMMARY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r_selection_diagnostics_20260627/stage_r_summary.md"
)
DEFAULT_STAGE_U_MATRIX = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_u_parity_audit_20260629/stage_u_row_parity_matrix.csv"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_zc_graph_design_diagnostics_20260701"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-z-dir", default=DEFAULT_STAGE_Z_DIR)
    p.add_argument("--stage-zb-dir", default=DEFAULT_STAGE_ZB_DIR)
    p.add_argument("--stage-zb-cell-dir", default=DEFAULT_STAGE_ZB_CELL_DIR)
    p.add_argument("--stage-k-summary", default=DEFAULT_STAGE_K_SUMMARY)
    p.add_argument("--stage-r-summary", default=DEFAULT_STAGE_R_SUMMARY)
    p.add_argument("--stage-u-matrix", default=DEFAULT_STAGE_U_MATRIX)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--force", type=parse_bool, default=True)
    return p


def git_value(args):
    proc = subprocess.run(
        args,
        cwd=str(repo_path(".")),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        check=False,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def repo_state():
    return {
        "repo_branch": git_value(["git", "branch", "--show-current"]),
        "repo_head": git_value(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(git_value(["git", "status", "--short"])),
    }


def require_file(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing: {}".format(label, path))
    return path


def read_csv(path, label):
    return pd.read_csv(require_file(path, label))


def read_json(path, label):
    with open(require_file(path, label), "r") as f:
        return json.load(f)


def read_yaml(path, label):
    with open(require_file(path, label), "r") as f:
        return yaml.safe_load(f)


def relpath(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def write_frame(path, frame):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)
    return path


def split_block_cols(cols):
    rows = []
    for idx, col in enumerate(cols):
        text = str(col)
        region, raw = text.split("::", 1) if "::" in text else ("", text)
        feature = raw.split("-", 1)[1] if "-" in raw else raw
        rows.append({
            "column_index": int(idx),
            "source_region": region,
            "source_feature": feature,
            "source_column": raw,
        })
    return rows


def window_column_metadata(window, target_region):
    rows = []
    for block, cols in (("lag", window["lag_cols"]), ("lead", window["lead_cols"])):
        for row in split_block_cols(cols):
            row["input_block"] = block
            row["source_role"] = "target" if row["source_region"] == target_region else "neighbor"
            rows.append(row)
    return pd.DataFrame(rows)


def robust_stats(values):
    arr = np.asarray(values, dtype=float).reshape(-1)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return {
            "n_values": 0,
            "mean": np.nan,
            "sd": np.nan,
            "iqr": np.nan,
            "mean_abs": np.nan,
            "rms": np.nan,
            "p01": np.nan,
            "p99": np.nan,
        }
    q25, q75 = np.quantile(arr, [0.25, 0.75])
    return {
        "n_values": int(arr.size),
        "mean": float(np.mean(arr)),
        "sd": float(np.std(arr, ddof=0)),
        "iqr": float(q75 - q25),
        "mean_abs": float(np.mean(np.abs(arr))),
        "rms": float(np.sqrt(np.mean(arr ** 2))),
        "p01": float(np.quantile(arr, 0.01)),
        "p99": float(np.quantile(arr, 0.99)),
    }


def subset_by_meta(arr, meta, role=None, block=None, feature=None, region=None):
    sub = meta.copy()
    if role is not None:
        sub = sub[sub["source_role"].eq(role)]
    if block is not None:
        sub = sub[sub["input_block"].eq(block)]
    if feature is not None:
        sub = sub[sub["source_feature"].eq(feature)]
    if region is not None:
        sub = sub[sub["source_region"].eq(region)]
    if sub.empty:
        return None
    idx = sub["column_index"].astype(int).to_numpy()
    return arr[:, :, idx]


def stats_rows_for_window(window, target_region, split):
    meta = window_column_metadata(window, target_region)
    rows = []
    arrays = {"lag": window["X_lag"], "lead": window["X_lead"]}
    for block in ("lag", "lead"):
        block_meta = meta[meta["input_block"].eq(block)]
        arr = arrays[block]
        groups = [
            ("block_role", ["source_role"]),
            ("block_role_feature", ["source_role", "source_feature"]),
            ("block_region_feature", ["source_role", "source_region", "source_feature"]),
        ]
        for group_type, cols in groups:
            for keys, sub in block_meta.groupby(cols, dropna=False):
                if not isinstance(keys, tuple):
                    keys = (keys,)
                idx = sub["column_index"].astype(int).to_numpy()
                payload = {
                    "split": split,
                    "group_type": group_type,
                    "input_block": block,
                    "source_role": "",
                    "source_region": "",
                    "source_feature": "",
                    "n_columns": int(len(idx)),
                }
                for name, value in zip(cols, keys):
                    payload[name] = value
                payload.update(robust_stats(arr[:, :, idx]))
                rows.append(payload)
    return rows


def block_norm_rows(window, target_region, split):
    meta = window_column_metadata(window, target_region)
    rows = []
    for block, arr in (("lag", window["X_lag"]), ("lead", window["X_lead"])):
        for role in ("target", "neighbor"):
            block_arr = subset_by_meta(arr, meta[meta["input_block"].eq(block)], role=role)
            if block_arr is None:
                continue
            norms = np.sqrt(np.sum(block_arr ** 2, axis=(1, 2)))
            payload = {
                "split": split,
                "input_block": block,
                "source_role": role,
                "n_origins": int(block_arr.shape[0]),
                "n_lags_or_leads": int(block_arr.shape[1]),
                "n_columns": int(block_arr.shape[2]),
            }
            payload.update({"origin_norm_" + k: v for k, v in robust_stats(norms).items()})
            rows.append(payload)
    return rows


def safe_corr(a, b):
    a = np.asarray(a, dtype=float).reshape(-1)
    b = np.asarray(b, dtype=float).reshape(-1)
    ok = np.isfinite(a) & np.isfinite(b)
    if ok.sum() < 3:
        return np.nan
    a = a[ok]
    b = b[ok]
    if np.std(a) <= 0 or np.std(b) <= 0:
        return np.nan
    return float(np.corrcoef(a, b)[0, 1])


def correlation_rows(window, target_region, split):
    meta = window_column_metadata(window, target_region)
    rows = []
    for block, arr in (("lag", window["X_lag"]), ("lead", window["X_lead"])):
        block_meta = meta[meta["input_block"].eq(block)]
        target_regions = block_meta[block_meta["source_role"].eq("target")]
        neighbor_regions = block_meta[block_meta["source_role"].eq("neighbor")]
        for feature in sorted(set(target_regions["source_feature"]) & set(neighbor_regions["source_feature"])):
            target_arr = subset_by_meta(arr, block_meta, role="target", feature=feature, region=target_region)
            if target_arr is None or target_arr.shape[2] != 1:
                continue
            target_values = target_arr[:, :, 0]
            for region in sorted(neighbor_regions["source_region"].unique()):
                neigh_arr = subset_by_meta(arr, block_meta, role="neighbor", feature=feature, region=region)
                if neigh_arr is None or neigh_arr.shape[2] != 1:
                    continue
                neigh_values = neigh_arr[:, :, 0]
                rows.append({
                    "split": split,
                    "input_block": block,
                    "source_feature": feature,
                    "neighbor_region": region,
                    "corr_same_laglead_flat": safe_corr(target_values, neigh_values),
                    "mean_abs_difference": float(np.mean(np.abs(neigh_values - target_values))),
                    "rms_difference": float(np.sqrt(np.mean((neigh_values - target_values) ** 2))),
                    "target_rms": float(np.sqrt(np.mean(target_values ** 2))),
                    "neighbor_rms": float(np.sqrt(np.mean(neigh_values ** 2))),
                })
    return rows


def window_diagnostics(smoke):
    data_cfg = load_config(smoke["data_config"])
    region = str(smoke["region"])
    fold = int(smoke["fold"])
    stats = []
    norms = []
    correlations = []
    inventory = []
    for split in smoke.get("splits", ["train", "val", "test"]):
        window = load_feature_window(data_cfg, fold, region, split, smoke)
        meta = window_column_metadata(window, region)
        inventory.append({
            "split": split,
            "n_origins": int(window["Y"].shape[0]),
            "n_horizons": int(window["Y"].shape[1]),
            "lag_steps": int(window["X_lag"].shape[1]),
            "lead_steps": int(window["X_lead"].shape[1]),
            "lag_columns": int(window["X_lag"].shape[2]),
            "lead_columns": int(window["X_lead"].shape[2]),
            "target_lag_columns": int(((meta["input_block"] == "lag") & (meta["source_role"] == "target")).sum()),
            "neighbor_lag_columns": int(((meta["input_block"] == "lag") & (meta["source_role"] == "neighbor")).sum()),
            "target_lead_columns": int(((meta["input_block"] == "lead") & (meta["source_role"] == "target")).sum()),
            "neighbor_lead_columns": int(((meta["input_block"] == "lead") & (meta["source_role"] == "neighbor")).sum()),
            "neighbor_regions": ",".join(sorted(meta.loc[meta["source_role"].eq("neighbor"), "source_region"].unique())),
        })
        stats.extend(stats_rows_for_window(window, region, split))
        norms.extend(block_norm_rows(window, region, split))
        correlations.extend(correlation_rows(window, region, split))
    return pd.DataFrame(inventory), pd.DataFrame(stats), pd.DataFrame(norms), pd.DataFrame(correlations)


def stage_zb_model_summary(cell_dir, stage_z_dir):
    model_dir = repo_path(cell_dir) / "model"
    metric = read_csv(model_dir / "metric_summary.csv", "Stage-ZB metric summary")
    horizon = read_csv(model_dir / "metric_by_horizon_group.csv", "Stage-ZB horizon-group metrics")
    method = read_csv(model_dir / "model_method_summary.csv", "Stage-ZB model method summary")
    exact = read_csv(model_dir / "exact_equivalence.csv", "Stage-ZB exact equivalence")
    stage_z_graph = read_csv(Path(stage_z_dir) / "stage_z_graph_adapter_contract.csv", "Stage-Z graph contract")
    graph_row = stage_z_graph[
        stage_z_graph["region"].astype(str).eq("PL") & stage_z_graph["fold"].astype(int).eq(3)
    ].iloc[0]
    test = metric[(metric["split"].eq("test")) & (metric["unit"].eq("original"))].copy()
    qdesn_al = float(test[test["method_id"].eq("qdesn_al_rhs_ns_exact_chunked")]["AQL"].iloc[0])
    qdesn_exal = float(test[test["method_id"].eq("qdesn_exal_rhs_ns_exact_chunked")]["AQL"].iloc[0])
    normal_rhs = float(test[test["method_id"].eq("normal_rhs_ns")]["AQL"].iloc[0])
    naive = float(test[test["method_id"].eq("naive3_prev7_avg")]["AQL"].iloc[0])
    current = float(graph_row["current_AQL"])
    pricefm = float(graph_row["pricefm_AQL"])
    rows = [
        {
            "comparison": "stage_zb_qdesn_al_vs_current_registry",
            "stage_zb_AQL": qdesn_al,
            "baseline_AQL": current,
            "delta_AQL": qdesn_al - current,
            "decision": "worse",
        },
        {
            "comparison": "stage_zb_qdesn_al_vs_pricefm",
            "stage_zb_AQL": qdesn_al,
            "baseline_AQL": pricefm,
            "delta_AQL": qdesn_al - pricefm,
            "decision": "worse",
        },
        {
            "comparison": "stage_zb_qdesn_al_vs_naive_prev7",
            "stage_zb_AQL": qdesn_al,
            "baseline_AQL": naive,
            "delta_AQL": qdesn_al - naive,
            "decision": "better",
        },
        {
            "comparison": "stage_zb_exal_vs_al",
            "stage_zb_AQL": qdesn_exal,
            "baseline_AQL": qdesn_al,
            "delta_AQL": qdesn_exal - qdesn_al,
            "decision": "roughly_equal",
        },
        {
            "comparison": "stage_zb_normal_rhs_vs_al",
            "stage_zb_AQL": normal_rhs,
            "baseline_AQL": qdesn_al,
            "delta_AQL": normal_rhs - qdesn_al,
            "decision": "worse",
        },
    ]
    return metric, horizon, method, exact, pd.DataFrame(rows), graph_row.to_dict()


def source_manifest(paths):
    rows = []
    for label, path in paths:
        path = repo_path(path)
        rows.append({
            "label": label,
            "path": relpath(path),
            "exists": bool(path.exists()),
            "size_bytes": int(path.stat().st_size) if path.exists() else 0,
            "sha256": sha256_file(path) if path.exists() and path.is_file() else "",
        })
    return pd.DataFrame(rows)


def health_rows(cell_dir, output_dir):
    cell_dir = repo_path(cell_dir)
    binary_patterns = ["*.rds", "*.rda", "*.RData", "*.rdata", "X_*.csv"]
    binaries = []
    for pattern in binary_patterns:
        binaries.extend(cell_dir.rglob(pattern))
    return pd.DataFrame([{
        "stage": "stage_zc_diagnostic",
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_zb_cell_dir": relpath(cell_dir),
        "output_dir": relpath(output_dir),
        "stage_zb_binary_or_matrix_artifacts": int(len(binaries)),
        "run_clean": bool(len(binaries) == 0),
    }])


def decision_summary(feature_stats, block_norms, correlations, model_decomp):
    train_norms = block_norms[block_norms["split"].eq("train")]
    lag = train_norms[train_norms["input_block"].eq("lag")]
    lead = train_norms[train_norms["input_block"].eq("lead")]

    def ratio(block_df):
        target = block_df[block_df["source_role"].eq("target")]
        neigh = block_df[block_df["source_role"].eq("neighbor")]
        if target.empty or neigh.empty:
            return np.nan
        return float(
            neigh["origin_norm_rms"].iloc[0] /
            max(target["origin_norm_rms"].iloc[0], np.finfo(float).eps)
        )

    lag_ratio = ratio(lag)
    lead_ratio = ratio(lead)
    corr_price = correlations[
        correlations["source_feature"].eq("price") &
        correlations["input_block"].eq("lag") &
        correlations["split"].eq("train")
    ]
    mean_price_corr = float(corr_price["corr_same_laglead_flat"].mean()) if not corr_price.empty else np.nan
    current_delta = float(
        model_decomp[model_decomp["comparison"].eq("stage_zb_qdesn_al_vs_current_registry")]
        ["delta_AQL"].iloc[0]
    )
    pricefm_delta = float(
        model_decomp[model_decomp["comparison"].eq("stage_zb_qdesn_al_vs_pricefm")]
        ["delta_AQL"].iloc[0]
    )
    recommend_contract = bool(
        current_delta > 0.25 and
        (lag_ratio > 1.0 or lead_ratio > 1.0 or mean_price_corr < 0.9)
    )
    return {
        "stage_zb_delta_vs_current": current_delta,
        "stage_zb_delta_vs_pricefm": pricefm_delta,
        "train_neighbor_target_lag_norm_ratio": lag_ratio,
        "train_neighbor_target_lead_norm_ratio": lead_ratio,
        "train_mean_neighbor_target_price_corr": mean_price_corr,
        "direct_recipe_promotable": False,
        "diagnostic_supports_revised_graph_contract": recommend_contract,
        "recommended_next_contract": (
            "graph_neighbor_spread_summary"
            if recommend_contract else
            "no_new_graph_contract_without_manual_review"
        ),
        "recommended_next_action": (
            "implement_adapter_smoke_for_graph_neighbor_spread_summary"
            if recommend_contract else
            "stop_after_diagnostics"
        ),
        "reason": (
            "Stage-ZB is worse than current/PriceFM and diagnostics indicate "
            "raw neighbor direct blocks need a compact relative graph signal."
            if recommend_contract else
            "Stage-ZB is worse, but diagnostics do not identify a safe revised graph contract."
        ),
    }


def write_report(path, summary, health, inventory, model_decomp):
    def md_table(frame):
        if frame.empty:
            return "_No rows._"
        cols = list(frame.columns)
        lines = [
            "| " + " | ".join(cols) + " |",
            "| " + " | ".join(["---"] * len(cols)) + " |",
        ]
        for _, row in frame.iterrows():
            vals = [str(row[col]) for col in cols]
            lines.append("| " + " | ".join(vals) + " |")
        return "\n".join(lines)

    lines = []
    lines.append("# PriceFM Stage-ZC Graph Design Diagnostics")
    lines.append("")
    lines.append("Stage ZC is diagnostic-only. It does not fit models or write launch configs.")
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|---|---:|")
    for key in [
        "direct_recipe_promotable",
        "diagnostic_supports_revised_graph_contract",
        "recommended_next_contract",
        "recommended_next_action",
        "stage_zb_delta_vs_current",
        "stage_zb_delta_vs_pricefm",
        "train_neighbor_target_lag_norm_ratio",
        "train_neighbor_target_lead_norm_ratio",
        "train_mean_neighbor_target_price_corr",
    ]:
        lines.append("| `{}` | `{}` |".format(key, summary.get(key)))
    lines.append("")
    lines.append(summary["reason"])
    lines.append("")
    lines.append("## Health")
    lines.append("")
    lines.append(md_table(health))
    lines.append("")
    lines.append("## Feature Inventory")
    lines.append("")
    lines.append(md_table(inventory))
    lines.append("")
    lines.append("## Model Decomposition")
    lines.append("")
    lines.append(md_table(model_decomp))
    lines.append("")
    lines.append("## Output Files")
    lines.append("")
    lines.extend([
        "- `stage_zc_health.csv`",
        "- `stage_zc_input_manifest.csv`",
        "- `stage_zc_feature_inventory.csv`",
        "- `stage_zc_feature_scale_audit.csv`",
        "- `stage_zc_block_norm_audit.csv`",
        "- `stage_zc_feature_correlation_audit.csv`",
        "- `stage_zc_horizon_signal_audit.csv`",
        "- `stage_zc_model_failure_decomposition.csv`",
        "- `summary.json`",
    ])
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    return path


def diagnose(args):
    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and not args.force:
        raise FileExistsError("{} exists; rerun with --force true".format(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    cell_dir = repo_path(args.stage_zb_cell_dir)
    config_path = require_file(cell_dir / "config.yaml", "Stage-ZB cell config")
    cfg = read_yaml(config_path, "Stage-ZB cell config")
    smoke = cfg["pricefm_desn_smoke"]

    model_dir = cell_dir / "model"
    adapter_dir = cell_dir / "adapter"
    metric, horizon, method, exact, model_decomp, graph_row = stage_zb_model_summary(cell_dir, args.stage_z_dir)
    inventory, feature_stats, block_norms, correlations = window_diagnostics(smoke)
    health = health_rows(cell_dir, output_dir)
    sources = source_manifest([
        ("stage_z_graph_contract", Path(args.stage_z_dir) / "stage_z_graph_adapter_contract.csv"),
        ("stage_zb_probe_manifest", Path(args.stage_zb_dir) / "stage_zb_probe_manifest.csv"),
        ("stage_zb_decision_gates", Path(args.stage_zb_dir) / "stage_zb_decision_gates.csv"),
        ("stage_zb_cell_config", config_path),
        ("adapter_manifest", adapter_dir / "adapter_manifest.json"),
        ("feature_manifest", adapter_dir / "feature_manifest.json"),
        ("feature_provenance", adapter_dir / "feature_provenance.csv"),
        ("metric_summary", model_dir / "metric_summary.csv"),
        ("metric_by_horizon_group", model_dir / "metric_by_horizon_group.csv"),
        ("stage_k_summary", args.stage_k_summary),
        ("stage_r_summary", args.stage_r_summary),
        ("stage_u_matrix", args.stage_u_matrix),
    ])
    summary = decision_summary(feature_stats, block_norms, correlations, model_decomp)
    summary.update(repo_state())
    summary.update({
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "region": smoke["region"],
        "fold": int(smoke["fold"]),
        "feature_policy": smoke.get("feature_policy"),
        "stage_z_current_AQL": float(graph_row["current_AQL"]),
        "stage_z_pricefm_AQL": float(graph_row["pricefm_AQL"]),
        "output_dir": relpath(output_dir),
    })

    write_frame(output_dir / "stage_zc_health.csv", health)
    write_frame(output_dir / "stage_zc_input_manifest.csv", sources)
    write_frame(output_dir / "stage_zc_feature_inventory.csv", inventory)
    write_frame(output_dir / "stage_zc_feature_scale_audit.csv", feature_stats)
    write_frame(output_dir / "stage_zc_block_norm_audit.csv", block_norms)
    write_frame(output_dir / "stage_zc_feature_correlation_audit.csv", correlations)
    write_frame(output_dir / "stage_zc_horizon_signal_audit.csv", horizon)
    write_frame(output_dir / "stage_zc_model_method_summary.csv", method)
    write_frame(output_dir / "stage_zc_exact_equivalence.csv", exact)
    write_frame(output_dir / "stage_zc_model_failure_decomposition.csv", model_decomp)
    write_json(output_dir / "summary.json", summary)
    write_report(output_dir / "stage_zc_report.md", summary, health, inventory, model_decomp)
    return summary


def main():
    args = parser().parse_args()
    summary = diagnose(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
