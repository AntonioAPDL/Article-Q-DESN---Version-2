#!/usr/bin/env python3
"""Validate PriceFM reservoir-grid configs and completed adapter manifests."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import sys
from pathlib import Path

import yaml

from pricefm_common import load_config, repo_path, write_json
from pricefm_desn_adapter import normalize_reservoir_config, sha256_json
from pricefm_full_run import cell_paths, make_cell_config


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"


def load_grid_module():
    spec = importlib.util.spec_from_file_location("pricefm_grid_prepare", GRID_PREP_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_csv(value, cast=str):
    if value is None or str(value).strip() == "":
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", required=True)
    p.add_argument("--priorities", default=None)
    p.add_argument("--stages", default=None)
    p.add_argument("--ids", default=None)
    p.add_argument("--max-experiments", type=int, default=None)
    p.add_argument("--write-generated", action="store_true")
    p.add_argument("--generated-root", default=None)
    p.add_argument("--require-cell-configs", action="store_true")
    p.add_argument("--require-feature-manifests", action="store_true")
    p.add_argument("--output-json", default=None)
    p.add_argument("--output-csv", default=None)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def select_rows(rows, priorities=None, stages=None, ids=None, max_experiments=None):
    priorities = set(priorities or [])
    stages = set(stages or [])
    ids = set(ids or [])
    out = []
    for row in rows:
        if priorities and int(row["priority"]) not in priorities:
            continue
        if stages and str(row["stage"]) not in stages:
            continue
        if ids and str(row["id"]) not in ids:
            continue
        out.append(row)
    if max_experiments is not None:
        out = out[:int(max_experiments)]
    return out


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def read_json_if_exists(path):
    path = repo_path(path)
    if not path.exists():
        return None
    with open(path, "r") as f:
        return json.load(f)


def compare_dicts(expected, observed, keys):
    mismatches = []
    for key in keys:
        if expected.get(key) != observed.get(key):
            mismatches.append("{} expected={!r} observed={!r}".format(
                key, expected.get(key), observed.get(key)
            ))
    return mismatches


def validate_grid(grid_config, priorities=None, stages=None, ids=None,
                  max_experiments=None, write_generated=False,
                  require_cell_configs=False, require_feature_manifests=False,
                  generated_root=None):
    grid_mod = load_grid_module()
    grid = grid_mod.load_grid(grid_config)
    rows = grid_mod.prepare_grid(
        grid,
        generated_root or grid["base"]["generated_root"],
        write=bool(write_generated),
    )
    selected = select_rows(rows, priorities, stages, ids, max_experiments)
    out = []
    for row in selected:
        full_payload = read_yaml(row["full_config"])
        full = full_payload["pricefm_desn_full"]
        data_cfg = load_config(full["data_config"])
        for region in [str(x) for x in full["scope"]["regions"]]:
            for fold in [int(x) for x in full["scope"]["folds"]]:
                messages = []
                status = "passed"
                generated_cell = make_cell_config(full, data_cfg, region, fold)["pricefm_desn_smoke"]
                feature_map = str(full["adapter"]["feature_map"])
                expected_reservoir = None
                expected_reservoir_hash = ""
                if feature_map == "window_reservoir_v1":
                    expected_reservoir = normalize_reservoir_config(
                        full["adapter"],
                        int(full["adapter"]["feature_dim"]),
                    )
                    expected_reservoir_hash = sha256_json(expected_reservoir)
                    cell_reservoir = normalize_reservoir_config(
                        generated_cell["adapter"],
                        int(generated_cell["adapter"]["feature_dim"]),
                    )
                    mismatches = compare_dicts(
                        expected_reservoir,
                        cell_reservoir,
                        [
                            "depth", "units", "alpha", "rho", "input_scale",
                            "recurrent_sparsity", "bias_scale",
                            "reservoir_activation", "state_output",
                        ],
                    )
                    if mismatches:
                        status = "failed"
                        messages.extend(["generated_cell " + x for x in mismatches])

                paths = cell_paths(full, region, fold)
                cell_cfg_path = paths["config"]
                feature_manifest_path = paths["adapter"] / "feature_manifest.json"
                actual_cell_cfg = read_yaml(cell_cfg_path) if repo_path(cell_cfg_path).exists() else None
                feature_manifest = read_json_if_exists(feature_manifest_path)
                if require_cell_configs and actual_cell_cfg is None:
                    status = "failed"
                    messages.append("missing cell config {}".format(config_path_value(cell_cfg_path)))
                if actual_cell_cfg is not None and expected_reservoir is not None:
                    actual_adapter = actual_cell_cfg["pricefm_desn_smoke"]["adapter"]
                    actual_reservoir = normalize_reservoir_config(
                        actual_adapter,
                        int(actual_adapter["feature_dim"]),
                    )
                    mismatches = compare_dicts(
                        expected_reservoir,
                        actual_reservoir,
                        [
                            "depth", "units", "alpha", "rho", "input_scale",
                            "recurrent_sparsity", "bias_scale",
                            "reservoir_activation", "state_output",
                        ],
                    )
                    if mismatches:
                        status = "failed"
                        messages.extend(["cell_config " + x for x in mismatches])

                observed_reservoir_hash = ""
                matrix_hash = ""
                train_x_hash = ""
                if require_feature_manifests and feature_manifest is None:
                    status = "failed"
                    messages.append("missing feature manifest {}".format(config_path_value(feature_manifest_path)))
                if feature_manifest is not None and expected_reservoir is not None:
                    observed = feature_manifest.get("reservoir")
                    observed_reservoir_hash = str(feature_manifest.get("reservoir_config_sha256", ""))
                    matrix_hash = str(feature_manifest.get("feature_map_matrix_sha256", ""))
                    if observed != expected_reservoir:
                        status = "failed"
                        messages.append("feature_manifest reservoir mismatch")
                    if observed_reservoir_hash != expected_reservoir_hash:
                        status = "failed"
                        messages.append("feature_manifest reservoir_config_sha256 mismatch")
                    adapter_manifest = read_json_if_exists(paths["adapter"] / "adapter_manifest.json")
                    if adapter_manifest is not None:
                        train_x_hash = str(adapter_manifest.get("splits", {}).get("train", {}).get("X_sha256", ""))

                out.append({
                    "id": row["id"],
                    "region": region,
                    "fold": int(fold),
                    "priority": int(row["priority"]),
                    "stage": row["stage"],
                    "status": status,
                    "message": "; ".join(messages),
                    "full_config": row["full_config"],
                    "cell_config": config_path_value(cell_cfg_path),
                    "feature_manifest": config_path_value(feature_manifest_path),
                    "feature_map": feature_map,
                    "feature_dim": int(full["adapter"]["feature_dim"]),
                    "expected_reservoir_config_sha256": expected_reservoir_hash,
                    "observed_reservoir_config_sha256": observed_reservoir_hash,
                    "feature_map_matrix_sha256": matrix_hash,
                    "train_X_sha256": train_x_hash,
                })
    return {
        "grid_id": grid["grid_id"],
        "n_selected": len(selected),
        "rows": out,
        "status": "passed" if all(row["status"] == "passed" for row in out) else "failed",
    }


def write_csv(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "id", "region", "fold", "priority", "stage", "status", "message", "full_config",
        "cell_config", "feature_manifest", "feature_map", "feature_dim",
        "expected_reservoir_config_sha256", "observed_reservoir_config_sha256",
        "feature_map_matrix_sha256", "train_X_sha256",
    ]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def main():
    args = parser().parse_args()
    result = validate_grid(
        args.grid_config,
        priorities=parse_csv(args.priorities, int),
        stages=parse_csv(args.stages, str),
        ids=parse_csv(args.ids, str),
        max_experiments=args.max_experiments,
        write_generated=bool(args.write_generated),
        require_cell_configs=bool(args.require_cell_configs),
        require_feature_manifests=bool(args.require_feature_manifests),
        generated_root=args.generated_root,
    )
    if args.output_json:
        write_json(repo_path(args.output_json), result)
    if args.output_csv:
        write_csv(args.output_csv, result["rows"])
    print(json.dumps(result, indent=2, sort_keys=True))
    if result["status"] != "passed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
