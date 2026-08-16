#!/usr/bin/env python3
"""Prepare a dry-run PriceFM bridge to package Q-DESN model selection.

The package-level ``exdqlm::qdesn_model_selection()`` API is now authoritative
for generic Q-DESN model selection. This script maps completed/planned PriceFM
experiment-grid candidates into package-v2-style configuration files where the
controls are representable, and writes an explicit compatibility report for the
PriceFM-only pieces that are not launch-ready in the package selector yet.

This script never launches fits.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from pathlib import Path

import yaml

from pricefm_common import repo_path, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
DEFAULT_METHODS = "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    p.add_argument("--priorities", default=None)
    p.add_argument("--stages", default=None)
    p.add_argument("--ids", default=None)
    p.add_argument("--quantile", type=float, default=0.50)
    p.add_argument("--selection-methods", default=DEFAULT_METHODS)
    p.add_argument("--write", default="true")
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def load_grid_module():
    spec = importlib.util.spec_from_file_location("pricefm_grid_prepare", GRID_PREP_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def parse_jsonish(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("[") or text.startswith("{") or text.startswith('"'):
            return json.loads(text)
        return value
    return value


def as_list(value):
    value = parse_jsonish(value)
    if isinstance(value, list):
        return value
    return [value]


def row_regions(row):
    return [str(x) for x in as_list(row["regions"])]


def row_folds(row):
    return [int(x) for x in as_list(row["folds"])]


def row_quantiles(row):
    return [float(x) for x in as_list(row["quantiles"])]


def filter_rows(rows, regions=None, folds=None, priorities=None, stages=None, ids=None, quantile=0.50):
    regions = set(regions or [])
    folds = set(folds or [])
    priorities = set(priorities or [])
    stages = set(stages or [])
    ids = set(ids or [])
    out = []
    for row in rows:
        if regions and not (set(row_regions(row)) & regions):
            continue
        if folds and not (set(row_folds(row)) & folds):
            continue
        if priorities and int(row["priority"]) not in priorities:
            continue
        if stages and str(row["stage"]) not in stages:
            continue
        if ids and str(row["id"]) not in ids:
            continue
        if float(quantile) not in set(row_quantiles(row)):
            continue
        out.append(row)
    return out


def normalize_vector(value, length):
    values = as_list(value)
    out = [float(x) for x in values]
    if len(out) == 1 and length > 1:
        out = out * length
    if len(out) != length:
        raise ValueError("Vector length {} does not match expected length {}".format(len(out), length))
    return out


def pricefm_row_to_candidate(row):
    depth = int(parse_jsonish(row["depth"]))
    units = [int(x) for x in as_list(row["units"])]
    if len(units) == 1 and depth > 1:
        units = units * depth
    if len(units) != depth:
        raise ValueError("Experiment {} has units inconsistent with depth.".format(row["id"]))
    alpha = normalize_vector(row["alpha"], depth)
    rho = normalize_vector(row["rho"], depth)
    candidate = {
        "id": str(row["id"]),
        "D": depth,
        "n": units,
        "n_tilde": units[1:] if depth > 1 else [],
        "m": int(row["lag_window"]),
        "alpha": alpha[0] if len(alpha) == 1 else alpha,
        "rho": rho[0] if len(rho) == 1 else rho,
        "seed": int(row["seed"]),
        "metadata": {
            "pricefm_experiment_id": str(row["id"]),
            "pricefm_feature_map": str(row["feature_map"]),
            "pricefm_feature_dim": int(row["feature_dim"]),
            "pricefm_projection_scale": float(row["projection_scale"]),
            "pricefm_input_scale": parse_jsonish(row["input_scale"]),
            "pricefm_state_output": str(row["state_output"]),
            "pricefm_tau0": float(row["tau0"]),
            "pricefm_rationale": str(row.get("rationale", "")),
        },
    }
    return candidate


def grouped_rows(rows):
    groups = {}
    for row in rows:
        for region in row_regions(row):
            for fold in row_folds(row):
                key = (region, int(fold))
                groups.setdefault(key, []).append(row)
    return groups


def require_common_tau0(rows):
    tau0_values = sorted({round(float(row["tau0"]), 16) for row in rows})
    if len(tau0_values) != 1:
        raise ValueError("Package v2 bridge currently requires one tau0 per config; got {}".format(tau0_values))
    return float(tau0_values[0])


def build_package_v2_config(grid, rows, region, fold, quantile, selection_methods):
    tau0 = require_common_tau0(rows)
    candidates = [pricefm_row_to_candidate(row) for row in rows]
    fixed = grid["fixed"]
    scope = grid["scope"]
    train_origin_limit = int(fixed.get("train_origin_limit", 3000))
    lead_window = int(fixed.get("lead_window", 96))
    grid_id = str(grid["grid_id"])
    tune_name = "pricefm_{}_fold{}_tau{}_bridge".format(
        str(region).lower(),
        int(fold),
        str(float(quantile)).replace(".", "p"),
    )
    return {
        "pipeline": {
            "mode": "real",
            "profile": "pricefm_bridge_dry_run",
            "pricefm_bridge_launch_ready": False,
        },
        "pricefm_bridge": {
            "grid_id": grid_id,
            "region": str(region),
            "fold": int(fold),
            "quantile": float(quantile),
            "selection_methods": list(selection_methods),
            "selection_split": str(scope.get("ranking_split", "val")),
            "selection_unit": str(scope.get("ranking_unit", "original")),
            "selection_metric": str(scope.get("ranking_metric", "AQL")),
            "audit_split": str(scope.get("audit_split", "test")),
            "package_launch_ready": False,
            "launch_blocked_reason": (
                "Generic package v2 model selection does not yet represent the "
                "PriceFM direct-horizon adapter, feature projection controls, "
                "or fold-level 1:96 horizon scoring contract."
            ),
        },
        "forecast": {
            "mode": "origin",
            "horizon": lead_window,
        },
        "split": {
            "use_last": True,
            "train_n": train_origin_limit,
        },
        "p_vec": [float(quantile)],
        "readout": {
            "include_input": True,
            "input_mode": "raw_y_lags",
            "reservoir_lags": 1,
        },
        "vb": {
            "max_iter": 100,
            "min_iter_elbo": 50,
            "tol": 1.0e-4,
            "tol_par": 1.0e-4,
            "n_samp_xi": 80,
            "readout_scale": True,
            "priors": {
                "beta": {
                    "type": "rhs_ns",
                    "rhs_ns": {
                        "tau0": tau0,
                        "s2": 0.1,
                        "shrink_intercept": bool(fixed.get("shrink_intercept", False)),
                    },
                },
            },
        },
        "model_selection": {
            "tune_name": tune_name,
            "objective": {
                "primary": "crps_synth",
                "secondary": "calcrps_mean",
                "lambda": 0.0,
            },
            "calcrps": {
                "enabled": False,
            },
            "tracking": {
                "enabled": True,
            },
            "stages": [
                {
                    "name": "pricefm_bridge_candidates",
                    "seeds": [1],
                    "p_vec": [float(quantile)],
                    "nd_draws": 1000,
                    "synth_n_samp": 500,
                    "origins": {
                        "policy": "all",
                    },
                    "horizon": lead_window,
                    "candidate_grid": {
                        "candidates": candidates,
                    },
                    "budget": {
                        "max_candidates": len(candidates),
                        "strategy": "explicit_candidates",
                    },
                }
            ],
        },
    }


def compatibility_rows(rows, region, fold, config_path):
    out = []
    for row in rows:
        out.append({
            "region": region,
            "fold": int(fold),
            "experiment_id": row["id"],
            "config_path": config_path_value(config_path),
            "representable_candidate_controls": True,
            "package_launch_ready": False,
            "blocked_pricefm_controls": (
                "feature_dim,projection_scale,input_scale,direct_horizon_adapter,"
                "fold_horizon_scoring,method_specific_al_exal_rhs_ns"
            ),
        })
    return out


def markdown_table(rows, columns):
    if not rows:
        return "_No rows._"
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join(["---"] * len(columns)) + " |",
    ]
    for row in rows:
        vals = [str(row.get(col, "")).replace("|", "\\|") for col in columns]
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(path, manifest_rows, compatibility, grid_config):
    columns = ["region", "fold", "n_candidates", "tau0", "package_launch_ready", "config_path"]
    with open(repo_path(path), "w") as f:
        f.write("# PriceFM Q-DESN Model-Selection Bridge Dry Run\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(grid_config)))
        f.write("## Generated Configs\n\n")
        f.write(markdown_table(manifest_rows, columns))
        f.write("\n\n## Compatibility Decision\n\n")
        f.write(
            "The generated package v2 configs are candidate/contract artifacts, "
            "not launch-ready PriceFM selectors. They preserve the representable "
            "Q-DESN controls and explicitly block launch until the package "
            "selector supports PriceFM direct-horizon windows and fold-level "
            "1:96 horizon scoring.\n\n"
        )
        f.write("## Candidate Compatibility\n\n")
        f.write(markdown_table(
            compatibility[:20],
            ["region", "fold", "experiment_id", "representable_candidate_controls", "package_launch_ready"],
        ))
        if len(compatibility) > 20:
            f.write("\n\n_Only first 20 candidate rows shown._\n")


def write_csv(path, rows):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def build_bridge(grid_config, output_dir, regions=None, folds=None, priorities=None,
                 stages=None, ids=None, quantile=0.50, selection_methods=None,
                 write=True):
    grid_mod = load_grid_module()
    grid = grid_mod.load_grid(str(grid_config))
    rows = grid_mod.prepare_grid(grid, grid["base"]["generated_root"], write=False)
    selected = filter_rows(
        rows,
        regions=regions,
        folds=folds,
        priorities=priorities,
        stages=stages,
        ids=ids,
        quantile=quantile,
    )
    if not selected:
        raise ValueError("No PriceFM grid rows matched the bridge filters.")
    methods = selection_methods or DEFAULT_METHODS.split(",")
    output_dir = repo_path(output_dir)
    manifest_rows = []
    compatibility = []
    for (region, fold), group in sorted(grouped_rows(selected).items()):
        cfg = build_package_v2_config(grid, group, region, fold, quantile, methods)
        tau0 = require_common_tau0(group)
        cfg_path = output_dir / "configs" / "{}_fold{}_qdesn_model_selection_v2_bridge.yaml".format(
            str(region).lower(),
            int(fold),
        )
        if write:
            write_yaml(cfg_path, cfg)
        manifest_rows.append({
            "region": region,
            "fold": int(fold),
            "n_candidates": len(group),
            "quantile": float(quantile),
            "tau0": tau0,
            "selection_methods": ",".join(methods),
            "package_launch_ready": False,
            "config_path": config_path_value(cfg_path),
        })
        compatibility.extend(compatibility_rows(group, region, fold, cfg_path))
    summary = {
        "grid_config": config_path_value(grid_config),
        "output_dir": config_path_value(output_dir),
        "n_configs": len(manifest_rows),
        "n_candidate_rows": len(compatibility),
        "package_launch_ready": False,
        "manifest_csv": config_path_value(output_dir / "bridge_manifest.csv"),
        "compatibility_csv": config_path_value(output_dir / "bridge_compatibility.csv"),
        "report": config_path_value(output_dir / "qdesn_model_selection_bridge_report.md"),
    }
    if write:
        write_csv(output_dir / "bridge_manifest.csv", manifest_rows)
        write_csv(output_dir / "bridge_compatibility.csv", compatibility)
        write_report(output_dir / "qdesn_model_selection_bridge_report.md", manifest_rows, compatibility, grid_config)
        write_json(output_dir / "summary.json", summary)
    return {
        "summary": summary,
        "manifest": manifest_rows,
        "compatibility": compatibility,
    }


def main():
    args = parser().parse_args()
    out = build_bridge(
        grid_config=args.grid_config,
        output_dir=args.output_dir,
        regions=parse_csv(args.regions, str),
        folds=parse_csv(args.folds, int),
        priorities=parse_csv(args.priorities, int),
        stages=parse_csv(args.stages, str),
        ids=parse_csv(args.ids, str),
        quantile=float(args.quantile),
        selection_methods=parse_csv(args.selection_methods, str),
        write=parse_bool(args.write),
    )
    print(json.dumps(out["summary"], indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
