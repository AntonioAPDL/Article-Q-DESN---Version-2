#!/usr/bin/env python3
"""Select PriceFM DESN median specs per region/fold from a completed grid."""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path

import pandas as pd

from pricefm_common import repo_path, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
GRID_PREP_PATH = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"


DEFAULT_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-config", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--regions", default=None)
    p.add_argument("--folds", default=None)
    p.add_argument("--selection-split", default="val")
    p.add_argument("--selection-unit", default="original")
    p.add_argument("--selection-metric", default="AQL")
    p.add_argument("--selection-methods", default=DEFAULT_METHODS)
    p.add_argument("--require-complete", default="true")
    p.add_argument("--priorities", default=None, help="Optional comma-separated priority filter.")
    p.add_argument("--stages", default=None, help="Optional comma-separated stage filter.")
    p.add_argument("--ids", default=None, help="Optional comma-separated experiment id filter.")
    p.add_argument(
        "--parity-summary",
        default=None,
        help="Optional path to a previously written Q-DESN model-selection parity summary.",
    )
    p.add_argument(
        "--expected-horizons",
        default="1:96",
        help="Horizon contract recorded in package-style metadata.",
    )
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def parse_horizons(value):
    text = str(value).strip()
    if ":" in text:
        left, right = text.split(":", 1)
        return list(range(int(left), int(right) + 1))
    return [int(x.strip()) for x in text.split(",") if x.strip()]


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


def read_csv_if_exists(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    return pd.read_csv(path)


def unique_columns(columns):
    out = []
    seen = set()
    for col in columns:
        if col in seen:
            continue
        out.append(col)
        seen.add(col)
    return out


def row_scope(row):
    regions = json.loads(row.get("regions", "[]")) if str(row.get("regions", "")).strip() else []
    folds = json.loads(row.get("folds", "[]")) if str(row.get("folds", "")).strip() else []
    return [str(x) for x in regions], [int(x) for x in folds]


def scope_selected(row, regions=None, folds=None):
    row_regions, row_folds = row_scope(row)
    if regions is not None and not (set(row_regions) & set(regions)):
        return False
    if folds is not None and not (set(row_folds) & set(folds)):
        return False
    return True


def select_rows(rows, priorities=None, stages=None, ids=None):
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
    return out


def cell_model_dir(row, region, fold):
    return repo_path(row["run_dir"]) / "cells" / "region={}".format(region) / "fold={}".format(int(fold)) / "model"


def cell_adapter_dir(row, region, fold):
    return repo_path(row["run_dir"]) / "cells" / "region={}".format(region) / "fold={}".format(int(fold)) / "adapter"


def flatten_row_spec(row):
    out = {
        "experiment_id": row["id"],
        "stage": row["stage"],
        "priority": int(row["priority"]),
        "lag_window": int(row["lag_window"]),
        "feature_map": row["feature_map"],
        "feature_policy": row.get("feature_policy", "target_only"),
        "feature_dim": int(row["feature_dim"]),
        "projection_scale": float(row["projection_scale"]),
        "depth": row["depth"],
        "units": row["units"],
        "alpha": row["alpha"],
        "rho": row["rho"],
        "input_scale": row["input_scale"],
        "recurrent_sparsity": row["recurrent_sparsity"],
        "state_output": row["state_output"],
        "quantiles": row["quantiles"],
        "tau0": float(row["tau0"]),
        "seed": int(row["seed"]),
        "data_config": row["data_config"],
        "full_config": row["full_config"],
        "run_dir": row["run_dir"],
        "rationale": row.get("rationale", ""),
    }
    for key in [
        "input_scope",
        "output_scope",
        "lead_covariate_status",
        "spatial_information_set",
        "graph_degree",
        "graph_source",
        "graph_hash",
        "final_decision",
        "candidate_source_final",
        "candidate_source",
        "selection_is_validation_only",
    ]:
        if key in row:
            out[key] = row.get(key, "")
    return out


def collect_candidate_metrics(rows, regions=None, folds=None):
    metric_rows = []
    status_rows = []
    for row in rows:
        if not scope_selected(row, regions=regions, folds=folds):
            continue
        row_regions, row_folds = row_scope(row)
        for region in row_regions:
            if regions is not None and region not in set(regions):
                continue
            for fold in row_folds:
                if folds is not None and int(fold) not in set(folds):
                    continue
                model_dir = cell_model_dir(row, region, fold)
                metrics = read_csv_if_exists(model_dir / "metric_summary.csv")
                completed = metrics is not None
                status_rows.append({
                    **flatten_row_spec(row),
                    "region": region,
                    "fold": int(fold),
                    "completed": bool(completed),
                    "model_dir": config_path_value(model_dir),
                })
                if metrics is None:
                    continue
                metrics = metrics.copy()
                for key, value in {
                    **flatten_row_spec(row),
                    "region": region,
                    "fold": int(fold),
                    "model_dir": config_path_value(model_dir),
                    "adapter_dir": config_path_value(cell_adapter_dir(row, region, fold)),
                }.items():
                    metrics.insert(0, key, value)
                metric_rows.append(metrics)
    return (
        pd.concat(metric_rows, ignore_index=True) if metric_rows else pd.DataFrame(),
        pd.DataFrame(status_rows),
    )


def select_registry(candidate_metrics, selection_split, selection_unit,
                    selection_metric, selection_methods):
    if candidate_metrics.empty:
        raise ValueError("No candidate metrics were found.")
    required = {"region", "fold", "method_id", "split", "unit", selection_metric}
    missing = required - set(candidate_metrics.columns)
    if missing:
        raise ValueError("Candidate metrics missing columns: {}".format(sorted(missing)))
    df = candidate_metrics[
        candidate_metrics["split"].astype(str).eq(str(selection_split))
        & candidate_metrics["unit"].astype(str).eq(str(selection_unit))
    ].copy()
    if selection_methods:
        df = df[df["method_id"].astype(str).isin(selection_methods)].copy()
    if df.empty:
        raise ValueError("No candidate rows match the selection rule.")
    df[selection_metric] = pd.to_numeric(df[selection_metric], errors="coerce")
    df = df[df[selection_metric].notna()].copy()
    if df.empty:
        raise ValueError("Selection metric is missing or nonnumeric for all candidate rows.")
    winners = []
    for (region, fold), sub in df.groupby(["region", "fold"]):
        best = sub.sort_values([selection_metric, "method_id", "experiment_id"]).iloc[0].to_dict()
        out = {
            "region": region,
            "fold": int(fold),
            "selected_on_split": selection_split,
            "selected_on_unit": selection_unit,
            "selection_metric": selection_metric,
            "selected_method_id": best["method_id"],
            "selection_metric_value": float(best[selection_metric]),
        }
        for key in [
            "AQL", "AQCR", "MAE", "RMSE", "experiment_id", "stage", "priority",
            "lag_window", "feature_map", "feature_dim", "projection_scale",
            "feature_policy", "input_scope", "output_scope",
            "lead_covariate_status", "spatial_information_set",
            "graph_degree", "graph_source", "graph_hash",
            "depth", "units", "alpha", "rho", "input_scale",
            "recurrent_sparsity", "state_output", "quantiles", "tau0", "seed",
            "data_config", "full_config", "run_dir", "model_dir", "adapter_dir",
            "rationale",
        ]:
            if key in best:
                out["selection_" + key if key in {"AQL", "AQCR", "MAE", "RMSE"} else key] = best[key]
        audit = candidate_metrics[
            candidate_metrics["region"].astype(str).eq(str(region))
            & candidate_metrics["fold"].astype(int).eq(int(fold))
            & candidate_metrics["experiment_id"].astype(str).eq(str(best["experiment_id"]))
            & candidate_metrics["method_id"].astype(str).eq(str(best["method_id"]))
            & candidate_metrics["split"].astype(str).eq("test")
            & candidate_metrics["unit"].astype(str).eq(str(selection_unit))
        ]
        if not audit.empty:
            audit_row = audit.iloc[0]
            for metric in ["AQL", "AQCR", "MAE", "RMSE"]:
                if metric in audit_row:
                    out["test_" + metric] = audit_row[metric]
        winners.append(out)
    return pd.DataFrame(winners).sort_values(["region", "fold"]).reset_index(drop=True)


def selection_method_coverage(candidate_metrics, selection_split, selection_unit,
                              selection_metric, selection_methods):
    if candidate_metrics.empty:
        return pd.DataFrame()
    required = {"region", "fold", "method_id", "split", "unit", selection_metric}
    missing = required - set(candidate_metrics.columns)
    if missing:
        raise ValueError("Candidate metrics missing columns: {}".format(sorted(missing)))
    df = candidate_metrics[
        candidate_metrics["split"].astype(str).eq(str(selection_split))
        & candidate_metrics["unit"].astype(str).eq(str(selection_unit))
    ].copy()
    if df.empty:
        return pd.DataFrame()
    df[selection_metric] = pd.to_numeric(df[selection_metric], errors="coerce")
    rows = []
    requested = [str(x) for x in (selection_methods or [])]
    for (region, fold), sub in df.groupby(["region", "fold"]):
        present = sorted(str(x) for x in sub.loc[sub[selection_metric].notna(), "method_id"].unique())
        if requested:
            methods = requested
        else:
            methods = present
        for method in methods:
            method_rows = sub[sub["method_id"].astype(str).eq(method)].copy()
            finite_rows = method_rows[method_rows[selection_metric].notna()]
            rows.append({
                "region": region,
                "fold": int(fold),
                "method_id": method,
                "selection_split": selection_split,
                "selection_unit": selection_unit,
                "selection_metric": selection_metric,
                "n_rows": int(method_rows.shape[0]),
                "n_finite_metric_rows": int(finite_rows.shape[0]),
                "covered": bool(finite_rows.shape[0] > 0),
            })
    out = pd.DataFrame(rows)
    if not out.empty:
        out = out.sort_values(["region", "fold", "method_id"]).reset_index(drop=True)
    return out


def assert_selection_method_coverage(coverage):
    if coverage.empty:
        raise ValueError("No selection-method coverage rows were produced.")
    missing = coverage[~coverage["covered"]].copy()
    if not missing.empty:
        raise ValueError(
            "Missing finite selection metrics for requested method/fold rows: {}".format(
                missing[["region", "fold", "method_id"]].to_dict("records")
            )
        )


def fold_rankings(candidate_metrics, selection_split, selection_unit,
                  selection_metric, selection_methods):
    if candidate_metrics.empty:
        return pd.DataFrame()
    df = candidate_metrics[
        candidate_metrics["split"].astype(str).eq(str(selection_split))
        & candidate_metrics["unit"].astype(str).eq(str(selection_unit))
    ].copy()
    if selection_methods:
        df = df[df["method_id"].astype(str).isin(selection_methods)].copy()
    if df.empty:
        return df
    df[selection_metric] = pd.to_numeric(df[selection_metric], errors="coerce")
    df = df[df[selection_metric].notna()].copy()
    df = df.sort_values(["region", "fold", selection_metric, "method_id", "experiment_id"])
    df["rank"] = df.groupby(["region", "fold"])[selection_metric].rank(method="first", ascending=True)
    keep = unique_columns([
        "region", "fold", "rank", "experiment_id", "method_id", selection_metric,
        "AQL", "AQCR", "MAE", "RMSE", "stage", "priority", "lag_window",
        "feature_dim", "depth", "units", "alpha", "rho", "input_scale",
        "tau0", "seed", "run_dir",
    ])
    return df[[c for c in keep if c in df.columns]].reset_index(drop=True)


def package_style_candidate_metrics(candidate_metrics, selection_split, selection_unit,
                                    selection_metric, selection_methods):
    if candidate_metrics.empty:
        return pd.DataFrame()
    out = candidate_metrics.copy()
    out["candidate_id"] = out["experiment_id"].astype(str)
    out["metric_name"] = str(selection_metric)
    out["metric_value"] = pd.to_numeric(out[selection_metric], errors="coerce")
    out["selection_split"] = str(selection_split)
    out["selection_unit"] = str(selection_unit)
    out["selection_metric"] = str(selection_metric)
    requested = set(str(x) for x in (selection_methods or []))
    out["selection_method_requested"] = out["method_id"].astype(str).isin(requested) if requested else True
    out["is_selection_row"] = (
        out["split"].astype(str).eq(str(selection_split))
        & out["unit"].astype(str).eq(str(selection_unit))
        & out["selection_method_requested"]
        & out["metric_value"].notna()
    )
    out["is_test_audit_row"] = out["split"].astype(str).eq("test")
    out["target_contract"] = "pricefm_direct_horizon_fold_aql"
    out["selector_surface"] = "article_pricefm_artifact_registry"
    out["package_selector"] = "exdqlm::qdesn_model_selection"
    out["package_launch_ready"] = False
    out["full_package_candidate_controls_preserved"] = True
    cols = unique_columns([
        "selector_surface", "package_selector", "package_launch_ready",
        "target_contract", "region", "fold", "candidate_id",
        "experiment_id", "method_id", "split", "unit", "metric_name",
        "metric_value", "selection_split", "selection_unit",
        "selection_metric", "selection_method_requested", "is_selection_row",
        "is_test_audit_row", "full_package_candidate_controls_preserved",
        "AQL", "AQCR", "MAE", "RMSE", "stage", "priority", "lag_window",
        "feature_map", "feature_dim", "projection_scale", "depth", "units",
        "alpha", "rho", "input_scale", "recurrent_sparsity", "state_output",
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set",
        "graph_degree", "graph_source", "graph_hash",
        "quantiles", "tau0", "seed", "data_config", "full_config",
        "run_dir", "model_dir", "adapter_dir", "rationale",
    ])
    return out[[c for c in cols if c in out.columns]].reset_index(drop=True)


def package_style_winners(registry):
    if registry.empty:
        return pd.DataFrame()
    out = registry.copy()
    out["candidate_id"] = out["experiment_id"].astype(str)
    out["selector_surface"] = "article_pricefm_artifact_registry"
    out["package_selector"] = "exdqlm::qdesn_model_selection"
    out["package_launch_ready"] = False
    out["target_contract"] = "pricefm_direct_horizon_fold_aql"
    out["preserves_full_data_target"] = True
    out["selection_is_validation_only"] = out["selected_on_split"].astype(str).eq("val")
    cols = unique_columns([
        "selector_surface", "package_selector", "package_launch_ready",
        "target_contract", "region", "fold", "candidate_id",
        "experiment_id", "selected_method_id", "selected_on_split",
        "selected_on_unit", "selection_metric", "selection_metric_value",
        "selection_is_validation_only", "preserves_full_data_target",
        "test_AQL", "test_AQCR", "test_MAE", "test_RMSE", "stage",
        "priority", "lag_window", "feature_map", "feature_dim",
        "projection_scale", "depth", "units", "alpha", "rho",
        "input_scale", "recurrent_sparsity", "state_output", "quantiles",
        "feature_policy", "input_scope", "output_scope",
        "lead_covariate_status", "spatial_information_set",
        "graph_degree", "graph_source", "graph_hash",
        "tau0", "seed", "data_config", "full_config", "run_dir",
        "model_dir", "adapter_dir", "rationale",
    ])
    return out[[c for c in cols if c in out.columns]].reset_index(drop=True)


def package_style_method_coverage(coverage):
    if coverage.empty:
        return pd.DataFrame()
    out = coverage.copy()
    out["selector_surface"] = "article_pricefm_artifact_registry"
    out["package_selector"] = "exdqlm::qdesn_model_selection"
    out["package_launch_ready"] = False
    out["target_contract"] = "pricefm_direct_horizon_fold_aql"
    cols = unique_columns([
        "selector_surface", "package_selector", "package_launch_ready",
        "target_contract", "region", "fold", "method_id",
        "selection_split", "selection_unit", "selection_metric",
        "n_rows", "n_finite_metric_rows", "covered",
    ])
    return out[[c for c in cols if c in out.columns]].reset_index(drop=True)


def read_optional_json(path):
    if path is None:
        return None
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        return None
    with open(path, "r") as f:
        return json.load(f)


def package_style_contract(args, grid_id, status, registry, coverage):
    parity_payload = read_optional_json(args.parity_summary)
    horizons = parse_horizons(args.expected_horizons)
    return {
        "grid_id": grid_id,
        "selector_surface": "article_pricefm_artifact_registry",
        "package_selector": "exdqlm::qdesn_model_selection",
        "target_contract": "pricefm_direct_horizon_fold_aql",
        "package_launch_ready": False,
        "launch_blocked_reason": (
            "The generic package selector does not yet encode the PriceFM "
            "direct-horizon adapter and fold-level horizon scoring contract."
        ),
        "selection": {
            "split": args.selection_split,
            "unit": args.selection_unit,
            "metric": args.selection_metric,
            "methods": parse_csv(args.selection_methods, str),
            "validation_selected_test_audit_only": True,
        },
        "filters": {
            "regions": parse_csv(args.regions, str),
            "folds": parse_csv(args.folds, int),
            "priorities": parse_csv(args.priorities, int),
            "stages": parse_csv(args.stages, str),
            "ids": parse_csv(args.ids, str),
        },
        "expected_horizons": horizons,
        "n_completed_cells": int(status["completed"].sum()) if not status.empty else 0,
        "n_cells": int(len(status)),
        "n_selected_rows": int(len(registry)),
        "method_coverage_complete": bool(not coverage.empty and coverage["covered"].map(parse_bool).all()),
        "parity_gate": {
            "required_before_package_style_claim": True,
            "validated_by_selector": False,
            "summary_path": config_path_value(args.parity_summary) if args.parity_summary else None,
            "loaded_summary": parity_payload.get("summary", parity_payload) if isinstance(parity_payload, dict) else None,
        },
        "outputs": {
            "candidate_metrics": "model_selection_candidate_metrics.csv",
            "method_coverage": "model_selection_method_coverage.csv",
            "winners": "model_selection_winners.csv",
            "contract": "model_selection_contract.json",
            "parity_summary": "model_selection_parity_summary.json",
        },
    }


def write_package_style_outputs(out_dir, metrics, registry, coverage, status, args, grid_id):
    pkg_metrics = package_style_candidate_metrics(
        metrics,
        args.selection_split,
        args.selection_unit,
        args.selection_metric,
        parse_csv(args.selection_methods, str),
    )
    pkg_coverage = package_style_method_coverage(coverage)
    pkg_winners = package_style_winners(registry)
    contract = package_style_contract(args, grid_id, status, registry, coverage)
    parity_summary = {
        "grid_id": grid_id,
        "parity_gate_required": True,
        "parity_validated_by_selector": False,
        "parity_summary_input": config_path_value(args.parity_summary) if args.parity_summary else None,
        "validator_script": "application/scripts/pricefm/30_validate_qdesn_model_selection_parity.py",
        "expected_horizons": parse_horizons(args.expected_horizons),
    }
    loaded = read_optional_json(args.parity_summary)
    if loaded is not None:
        parity_summary["loaded_parity_summary"] = loaded.get("summary", loaded) if isinstance(loaded, dict) else loaded
    pkg_metrics.to_csv(out_dir / "model_selection_candidate_metrics.csv", index=False)
    pkg_coverage.to_csv(out_dir / "model_selection_method_coverage.csv", index=False)
    pkg_winners.to_csv(out_dir / "model_selection_winners.csv", index=False)
    write_json(out_dir / "model_selection_contract.json", contract)
    write_json(out_dir / "model_selection_parity_summary.json", parity_summary)
    return {
        "candidate_metrics": str(out_dir / "model_selection_candidate_metrics.csv"),
        "method_coverage": str(out_dir / "model_selection_method_coverage.csv"),
        "winners": str(out_dir / "model_selection_winners.csv"),
        "contract": str(out_dir / "model_selection_contract.json"),
        "parity_summary": str(out_dir / "model_selection_parity_summary.json"),
    }


def markdown_value(value, float_digits=6):
    if isinstance(value, float):
        text = ("{:." + str(int(float_digits)) + "f}").format(value)
    else:
        text = str(value)
    return text.replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        values = []
        for col in cols:
            values.append(markdown_value(row[col], float_digits=float_digits))
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def write_report(out_dir, registry, rankings, status, args, grid_id):
    coverage_path = out_dir / "median_selection_method_coverage.csv"
    coverage = read_csv_if_exists(coverage_path)
    with open(out_dir / "median_selection_registry_report.md", "w") as f:
        f.write("# PriceFM DESN Median Selection Registry\n\n")
        f.write("Grid: `{}`\n\n".format(grid_id))
        f.write("Selection rule: `{}` / `{}` / `{}`  \n".format(
            args.selection_split, args.selection_unit, args.selection_metric
        ))
        f.write("Selection methods: `{}`\n\n".format(parse_csv(args.selection_methods, str)))
        f.write("Completed cells: `{}` / `{}`\n\n".format(
            int(status["completed"].sum()) if not status.empty else 0,
            int(len(status)),
        ))
        f.write("## Selected Specs\n\n")
        f.write(markdown_table(
            registry,
            columns=[
                "region", "fold", "selected_method_id", "selection_metric_value",
                "test_AQL", "test_MAE", "test_RMSE", "experiment_id",
                "lag_window", "feature_dim", "depth", "units", "alpha", "rho",
                "input_scale", "tau0", "seed",
            ],
        ))
        f.write("\n\n## Top Candidate Rankings\n\n")
        f.write(markdown_table(
            rankings.groupby(["region", "fold"]).head(10),
            columns=unique_columns([
                "region", "fold", "rank", "experiment_id", "method_id",
                args.selection_metric, "AQL", "MAE", "RMSE", "lag_window",
                "feature_dim", "depth", "units", "alpha", "rho", "input_scale",
            ]),
        ))
        f.write("\n\n## Selection Method Coverage\n\n")
        if coverage is None:
            f.write("_Coverage file was not available._\n")
        else:
            f.write(markdown_table(
                coverage,
                columns=[
                    "region", "fold", "method_id", "selection_split",
                    "selection_unit", "selection_metric", "n_rows",
                    "n_finite_metric_rows", "covered",
                ],
            ))
        f.write("\n\n## Notes\n\n")
        f.write("- Selection uses validation metrics only. Test metrics are audit fields.\n")
        f.write("- Every requested selection method must have a finite metric for each selected region/fold.\n")
        f.write("- Package-style outputs are written as compatibility metadata, not as package launch approval.\n")
        f.write("- PriceFM/Q-DESN package parity must still be checked with `30_validate_qdesn_model_selection_parity.py`.\n")
        f.write("- Generated row-level outputs remain in ignored local paths.\n")
    return out_dir / "median_selection_registry_report.md"


def main():
    args = parser().parse_args()
    grid_mod = load_grid_module()
    grid = grid_mod.load_grid(args.grid_config)
    rows = grid_mod.prepare_grid(grid, grid["base"]["generated_root"], write=False)
    rows = select_rows(
        rows,
        priorities=parse_csv(args.priorities, int),
        stages=parse_csv(args.stages, str),
        ids=parse_csv(args.ids, str),
    )
    regions = parse_csv(args.regions, str)
    folds = parse_csv(args.folds, int)
    selection_methods = parse_csv(args.selection_methods, str)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    metrics, status = collect_candidate_metrics(rows, regions=regions, folds=folds)
    if parse_bool(args.require_complete) and (status.empty or not status["completed"].all()):
        missing = status[~status["completed"]] if not status.empty else status
        missing.to_csv(out_dir / "median_selection_incomplete_cells.csv", index=False)
        raise SystemExit("Selection grid has incomplete cells; see median_selection_incomplete_cells.csv")
    registry = select_registry(
        metrics, args.selection_split, args.selection_unit,
        args.selection_metric, selection_methods,
    )
    rankings = fold_rankings(
        metrics, args.selection_split, args.selection_unit,
        args.selection_metric, selection_methods,
    )
    coverage = selection_method_coverage(
        metrics, args.selection_split, args.selection_unit,
        args.selection_metric, selection_methods,
    )
    coverage.to_csv(out_dir / "median_selection_method_coverage.csv", index=False)
    assert_selection_method_coverage(coverage)

    metrics.to_csv(out_dir / "median_candidate_metrics.csv", index=False)
    status.to_csv(out_dir / "median_candidate_completion.csv", index=False)
    registry.to_csv(out_dir / "median_selection_registry.csv", index=False)
    rankings.to_csv(out_dir / "median_candidate_rankings.csv", index=False)
    package_outputs = write_package_style_outputs(
        out_dir, metrics, registry, coverage, status, args, grid["grid_id"]
    )
    report = write_report(out_dir, registry, rankings, status, args, grid["grid_id"])
    payload = {
        "grid_id": grid["grid_id"],
        "selection_split": args.selection_split,
        "selection_unit": args.selection_unit,
        "selection_metric": args.selection_metric,
        "selection_methods": selection_methods,
        "priorities": parse_csv(args.priorities, int),
        "stages": parse_csv(args.stages, str),
        "ids": parse_csv(args.ids, str),
        "outputs": {
            "candidate_metrics": str(out_dir / "median_candidate_metrics.csv"),
            "candidate_completion": str(out_dir / "median_candidate_completion.csv"),
            "method_coverage": str(out_dir / "median_selection_method_coverage.csv"),
            "registry": str(out_dir / "median_selection_registry.csv"),
            "rankings": str(out_dir / "median_candidate_rankings.csv"),
            "report": str(report),
            "package_style": package_outputs,
        },
    }
    write_json(out_dir / "summary.json", payload)
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
