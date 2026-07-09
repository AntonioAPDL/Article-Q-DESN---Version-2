#!/usr/bin/env python3
"""Patch a PriceFM median registry from seed-robust rescue winners."""

from __future__ import annotations

import argparse
import json

import pandas as pd

from pricefm_common import repo_path, write_json
from pricefm_graph import graph_hash


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--current-registry-csv", required=True)
    p.add_argument("--seedrob-decisions-csv", required=True)
    p.add_argument("--promotion-ready-csv", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--candidate-source", default="graph_local_rescue_seedrob_20260616")
    p.add_argument("--allow-empty", default="false")
    return p


def parse_bool(value):
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "y", "on"):
        return True
    if text in ("0", "false", "no", "n", "off"):
        return False
    raise ValueError("expected boolean value, got {}".format(value))


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


def validate_current_registry(frame):
    required = {"region", "fold", "selection_AQL", "test_AQL", "selected_method_id", "experiment_id"}
    missing = required - set(frame.columns)
    if missing:
        raise ValueError("Current registry missing required columns: {}".format(sorted(missing)))
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    if out.duplicated(["region", "fold"]).any():
        dup = out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
        raise ValueError("Current registry has duplicate rows: {}".format(
            dup.drop_duplicates().to_dict("records")
        ))
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def ready_keys(ready):
    required = {"region", "fold", "source_rescue_experiment_id", "pass_seed_robustness"}
    missing = required - set(ready.columns)
    if missing:
        raise ValueError("Promotion-ready CSV missing columns: {}".format(sorted(missing)))
    if ready.empty:
        return []
    passed = ready[ready["pass_seed_robustness"].astype(bool)].copy()
    return [
        (str(row["region"]), int(row["fold"]), str(row["source_rescue_experiment_id"]))
        for _, row in passed.iterrows()
    ]


def best_seed_rows(decisions, keys):
    required = {
        "region", "fold", "source_rescue_experiment_id", "experiment_id",
        "method_id", "selection_AQL", "test_AQL", "test_MAE", "test_RMSE",
        "feature_map", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "tau0", "seed", "run_dir",
        "full_config", "data_config",
    }
    missing = required - set(decisions.columns)
    if missing:
        raise ValueError("Seed decisions missing required columns: {}".format(sorted(missing)))
    rows = []
    for region, fold, source_id in keys:
        sub = decisions[
            decisions["region"].astype(str).eq(region)
            & decisions["fold"].astype(int).eq(int(fold))
            & decisions["source_rescue_experiment_id"].astype(str).eq(source_id)
        ].copy()
        if sub.empty:
            raise ValueError("No seed decisions for ready key: {}".format((region, fold, source_id)))
        rows.append(sub.sort_values("selection_AQL").iloc[0])
    return pd.DataFrame(rows).reset_index(drop=True)


def normalize_feature_metadata(row):
    """Return internally consistent feature-policy metadata for registry rows."""
    out = dict(row)
    policy = str(out.get("feature_policy", "target_only") or "target_only")
    if policy == "graph_khop":
        degree = int(float(out.get("graph_degree", 1)))
        out["feature_policy"] = "graph_khop"
        out["graph_degree"] = degree
        out["graph_source"] = str(out.get("graph_source") or "PriceFM.graph_adj_matrix")
        out["graph_hash"] = str(out.get("graph_hash") or graph_hash())
        out["input_scope"] = "pricefm_graph_khop_degree{}".format(degree)
        out["output_scope"] = str(out.get("output_scope") or "target_region_path")
        out["lead_covariate_status"] = str(out.get("lead_covariate_status") or "realized_ex_post")
        out["spatial_information_set"] = "pricefm_released_graph_khop"
        return out

    out["feature_policy"] = "target_only"
    out["input_scope"] = str(out.get("input_scope") or "local_target_only")
    out["output_scope"] = str(out.get("output_scope") or "target_region_path")
    out["lead_covariate_status"] = str(out.get("lead_covariate_status") or "realized_ex_post")
    out["spatial_information_set"] = str(out.get("spatial_information_set") or "local_only_not_pricefm_graph")
    return out


def patch_row(current_row, seed_row, candidate_source):
    out = current_row.to_dict()
    out["selected_method_id"] = str(seed_row["method_id"])
    out["method_id"] = str(seed_row["method_id"])
    out["experiment_id"] = str(seed_row["experiment_id"])
    out["selection_metric"] = out.get("selection_metric", "AQL")
    out["selection_metric_value"] = float(seed_row["selection_AQL"])
    out["selection_AQL"] = float(seed_row["selection_AQL"])
    out["test_AQL"] = float(seed_row["test_AQL"])
    out["test_MAE"] = float(seed_row["test_MAE"])
    out["test_RMSE"] = float(seed_row["test_RMSE"])
    for key in [
        "feature_map", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "tau0", "seed", "run_dir",
        "full_config", "data_config", "feature_policy", "input_scope",
        "output_scope", "lead_covariate_status", "spatial_information_set",
        "graph_degree", "graph_source", "graph_hash",
    ]:
        if key in seed_row.index:
            out[key] = seed_row[key]
    out["selected_source"] = "rescue_seedrob"
    out["candidate_source"] = str(candidate_source)
    out["candidate_source_final"] = str(candidate_source)
    out["selection_is_validation_only"] = True
    out["selection_decision_rule"] = "seedrob_rescue_patch_only_after_validation_and_audit_gate"
    out["final_decision"] = "patch_rescue_seedrob_passed"
    out["source_rescue_experiment_id"] = str(seed_row["source_rescue_experiment_id"])
    out["source_current_experiment_id"] = str(current_row["experiment_id"])
    return normalize_feature_metadata(out)


def patch_registry(args):
    current = validate_current_registry(read_csv_required(args.current_registry_csv, "current registry"))
    decisions = read_csv_required(args.seedrob_decisions_csv, "seedrob decisions")
    ready = read_csv_required(args.promotion_ready_csv, "promotion-ready queue")
    keys = ready_keys(ready)
    if not keys and not parse_bool(args.allow_empty):
        raise ValueError("No promotion-ready rows; refusing to write a patched registry.")
    seed_rows = best_seed_rows(decisions, keys) if keys else pd.DataFrame()
    seed_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in seed_rows.iterrows()
    }
    patched_rows = []
    patch_only = []
    for _, row in current.iterrows():
        key = (str(row["region"]), int(row["fold"]))
        if key in seed_idx:
            patched = patch_row(row, seed_idx[key], args.candidate_source)
            patched_rows.append(patched)
            patch_only.append(patched)
        else:
            patched_rows.append(normalize_feature_metadata(row.to_dict()))
    patched = pd.DataFrame(patched_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    patch_frame = pd.DataFrame(patch_only).sort_values(["region", "fold"]).reset_index(drop=True)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    patched.to_csv(out_dir / "patched_selection_registry.csv", index=False)
    patch_frame.to_csv(out_dir / "patch_rows_registry.csv", index=False)
    seed_rows.to_csv(out_dir / "selected_seed_rows.csv", index=False)
    payload = {
        "status": "completed",
        "current_registry_csv": config_path_value(args.current_registry_csv),
        "seedrob_decisions_csv": config_path_value(args.seedrob_decisions_csv),
        "promotion_ready_csv": config_path_value(args.promotion_ready_csv),
        "output_dir": config_path_value(out_dir),
        "n_current_rows": int(current.shape[0]),
        "n_patch_rows": int(patch_frame.shape[0]),
        "patched_selection_registry": config_path_value(out_dir / "patched_selection_registry.csv"),
        "patch_rows_registry": config_path_value(out_dir / "patch_rows_registry.csv"),
    }
    write_json(out_dir / "summary.json", payload)
    return payload


def main():
    args = parser().parse_args()
    print(json.dumps(patch_registry(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
