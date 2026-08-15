#!/usr/bin/env python3
"""Prepare a diverse PriceFM region-panel median-selection grid.

This script chooses a small panel from the local PriceFM audit/reference
artifacts and writes a bounded median-only DESN/Q-DESN experiment grid. It does
not launch model fits.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import load_config, pricefm_block, repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_TEMPLATE = (
    "application/config/"
    "pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml"
)
DEFAULT_PHASE1 = "application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv"
DEFAULT_OUTPUT_GRID = (
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_region_panel_median_grid_20260606"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--phase1-reference-csv", default=DEFAULT_PHASE1)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--grid-id", default="pricefm_median_region_panel_20260606")
    p.add_argument(
        "--generated-root",
        default="application/data_local/pricefm/experiment_grids/pricefm_median_region_panel_20260606",
    )
    p.add_argument(
        "--run-root",
        default="application/data_local/pricefm/runs/pricefm_median_region_panel_20260606",
    )
    p.add_argument("--required-regions", default="DE_LU")
    p.add_argument("--folds", default="1,2,3")
    p.add_argument("--panel-size", type=int, default=6)
    p.add_argument("--write", default="true")
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return []
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} is missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def load_region_scores(config_path, phase1_reference_csv):
    cfg = load_config(config_path)
    spec = pricefm_block(cfg)
    audit_path = repo_path(Path(spec["interim_dir"]) / "audit_missingness_ranges.csv")
    audit = read_csv_required(audit_path, "PriceFM audit")
    phase1 = read_csv_required(phase1_reference_csv, "PriceFM Phase-I reference")
    phase1 = phase1.rename(columns={
        "target_country": "region",
        "AQL": "phase1_AQL",
        "MAE": "phase1_MAE",
        "RMSE": "phase1_RMSE",
    })
    price = audit[audit["feature"].astype(str).eq("price")].copy()
    if price.empty:
        raise ValueError("Audit file has no price rows.")
    price["spread_p99_p01"] = pd.to_numeric(price["p99"]) - pd.to_numeric(price["p01"])
    price["tail_range"] = pd.to_numeric(price["max"]) - pd.to_numeric(price["min"])
    cols = [
        "region", "min", "p01", "median", "p99", "max", "negative_rate",
        "zero_rate", "spread_p99_p01", "tail_range",
    ]
    merged = price[cols].merge(phase1, on="region", how="left", validate="one_to_one")
    missing = merged[merged["phase1_AQL"].isna()]
    if not missing.empty:
        raise ValueError("Missing Phase-I reference metrics for regions: {}".format(
            sorted(missing["region"].astype(str).tolist())
        ))
    configured = set(str(x) for x in spec["regions"])
    merged = merged[merged["region"].astype(str).isin(configured)].copy()
    return merged.sort_values("region").reset_index(drop=True)


def pick_first(scores, selected, sort_col, ascending, role):
    ordered = scores.sort_values([sort_col, "region"], ascending=[ascending, True])
    for _, row in ordered.iterrows():
        region = str(row["region"])
        if region not in selected:
            out = row.to_dict()
            out["selection_role"] = role
            return out
    raise ValueError("Could not select region for role {}".format(role))


def select_region_panel(scores, required_regions=None, panel_size=6):
    if int(panel_size) < 1:
        raise ValueError("panel_size must be positive.")
    required_regions = [str(x) for x in (required_regions or [])]
    by_region = {str(row["region"]): row for _, row in scores.iterrows()}
    selected = set()
    rows = []
    for region in required_regions:
        if region not in by_region:
            raise ValueError("Required region {} is absent from scores.".format(region))
        row = by_region[region].to_dict()
        row["selection_role"] = "anchor_required"
        rows.append(row)
        selected.add(region)
    roles = [
        ("hardest_phase1_aql", "phase1_AQL", False),
        ("widest_price_spread", "spread_p99_p01", False),
        ("narrowest_price_spread", "spread_p99_p01", True),
        ("highest_negative_price_rate", "negative_rate", False),
        ("highest_median_price", "median", False),
        ("lowest_phase1_aql", "phase1_AQL", True),
    ]
    for role, col, ascending in roles:
        if len(rows) >= int(panel_size):
            break
        row = pick_first(scores, selected, col, ascending, role)
        rows.append(row)
        selected.add(str(row["region"]))
    out = pd.DataFrame(rows)
    out.insert(0, "panel_rank", range(1, len(out) + 1))
    return out.reset_index(drop=True)


def panel_regions(panel):
    return [str(x) for x in panel["region"].tolist()]


def candidate_experiments(regions, folds):
    common = {
        "stage": "region_panel_median",
        "regions": list(regions),
        "folds": [int(x) for x in folds],
        "feature_map": "window_reservoir_v1",
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "quantile": 0.50,
        "state_output": "final_layer",
    }
    specs = [
        {
            "id": "panel_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601",
            "priority": 0,
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260601,
            "rationale": "Global anchor from the corrected DE_LU fold-1 winner geometry.",
        },
        {
            "id": "panel_lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603",
            "priority": 0,
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.25,
            "seed": 20260603,
            "rationale": "Fold-2 follow-up winner geometry; tests lower input scale.",
        },
        {
            "id": "panel_d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603",
            "priority": 0,
            "lag_window": 96,
            "depth": 2,
            "units": [80, 80],
            "alpha": 0.40,
            "rho": 0.90,
            "input_scale": 0.35,
            "seed": 20260603,
            "rationale": "Fold-3 follow-up winner geometry; compact D=2 representation.",
        },
        {
            "id": "panel_compact_l096_d1_n080_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 96,
            "depth": 1,
            "units": [80],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Compact D=1 diagnostic near the fold-3 anchor neighborhood.",
        },
        {
            "id": "panel_short_l072_d1_n120_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 72,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Short-context check around the one-day-ish DE_LU winners.",
        },
        {
            "id": "panel_long_l128_d1_n120_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 128,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Slightly longer context check without returning to very long windows.",
        },
    ]
    out = []
    for spec in specs:
        row = dict(common)
        row.update(spec)
        out.append(row)
    return out


def build_grid(template_payload, grid_id, generated_root, run_root, panel, folds):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template missing {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    regions = panel_regions(panel)
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Median-only region-panel selection grid. The panel is selected from "
        "PriceFM audit/reference diagnostics and the candidate set is a bounded "
        "transfer of the current DE_LU-winning neighborhoods."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = regions
    grid["scope"]["folds"] = [int(x) for x in folds]
    grid["scope"]["quantiles"] = [0.50]
    grid["scope"]["ranking_split"] = "val"
    grid["scope"]["audit_split"] = "test"
    grid["scope"]["ranking_unit"] = "original"
    grid["scope"]["ranking_metric"] = "AQL"
    grid["fixed"]["train_origin_limit"] = 3000
    grid["fixed"]["shrink_intercept"] = False
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["experiments"] = candidate_experiments(regions, folds)
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "dry_run_gate": {
            "priorities": [0, 1],
            "experiment_jobs": 10,
            "cell_jobs": 1,
            "build_windows": True,
            "note": (
                "Use --dry-run true first. Priority 0 transfers the three "
                "current DE_LU winner/anchor geometries; priority 1 adds compact "
                "context diagnostics. Selection remains validation-only."
            ),
        },
        "priority0_panel_core": {
            "priorities": [0],
            "experiment_jobs": 6,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "First real launch stage if storage/CPU budget is approved.",
        },
        "priority1_panel_diagnostics": {
            "priorities": [1],
            "experiment_jobs": 6,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Optional diagnostic stage after priority 0 is inspected.",
        },
    }
    return payload


def planned_cell_summary(panel, grid):
    n_regions = int(panel.shape[0])
    n_folds = len(grid[GRID_BLOCK]["scope"]["folds"])
    rows = []
    for exp in grid[GRID_BLOCK]["experiments"]:
        rows.append({
            "experiment_id": exp["id"],
            "priority": int(exp["priority"]),
            "n_regions": n_regions,
            "n_folds": n_folds,
            "n_cells": n_regions * n_folds,
            "lag_window": int(exp["lag_window"]),
            "depth": int(exp["depth"]),
            "units": json.dumps(exp["units"]),
            "alpha": exp["alpha"],
            "rho": exp["rho"],
            "input_scale": exp["input_scale"],
            "seed": int(exp["seed"]),
        })
    out = pd.DataFrame(rows)
    return out.sort_values(["priority", "experiment_id"]).reset_index(drop=True)


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
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append(("{:." + str(int(float_digits)) + "f}").format(value))
            else:
                vals.append(str(value))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(summary_dir, panel, cell_summary, grid_path, grid_payload):
    report = summary_dir / "region_panel_median_grid_report.md"
    grid = grid_payload[GRID_BLOCK]
    with open(report, "w") as f:
        f.write("# PriceFM Region-Panel Median Grid\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(grid_path)))
        f.write("Grid id: `{}`\n\n".format(grid["grid_id"]))
        f.write("## Selected Region Panel\n\n")
        f.write(markdown_table(panel, columns=[
            "panel_rank", "region", "selection_role", "phase1_AQL",
            "phase1_MAE", "phase1_RMSE", "median", "spread_p99_p01",
            "negative_rate", "zero_rate",
        ]))
        f.write("\n\n## Planned Cells\n\n")
        f.write(markdown_table(cell_summary, columns=[
            "experiment_id", "priority", "n_regions", "n_folds", "n_cells",
            "lag_window", "depth", "units", "alpha", "rho", "input_scale",
            "seed",
        ]))
        f.write("\n\nTotal planned cells: `{}`\n\n".format(int(cell_summary["n_cells"].sum())))
        f.write("## Launch Discipline\n\n")
        f.write("- Start with `13_run_desn_experiment_grid.py --dry-run true`.\n")
        f.write("- If approved, run priority 0 before priority 1.\n")
        f.write("- Selection uses validation AQL only; test metrics are audit-only.\n")
        f.write("- Artifact hygiene keeps `.rds`, `.rda`, `.RData`, and large adapter matrices out of retained outputs.\n")
    return report


def main():
    args = parser().parse_args()
    folds = parse_csv(args.folds, int)
    required = parse_csv(args.required_regions, str)
    scores = load_region_scores(args.config, args.phase1_reference_csv)
    panel = select_region_panel(scores, required_regions=required, panel_size=int(args.panel_size))
    template = read_yaml(args.template_grid_config)
    payload = build_grid(
        template,
        args.grid_id,
        args.generated_root,
        args.run_root,
        panel,
        folds,
    )
    cell_summary = planned_cell_summary(panel, payload)
    summary_dir = repo_path(args.summary_dir)
    grid_path = repo_path(args.output_grid_config)
    if parse_bool(args.write):
        write_yaml(grid_path, payload)
        summary_dir.mkdir(parents=True, exist_ok=True)
        scores.to_csv(summary_dir / "region_score_universe.csv", index=False)
        panel.to_csv(summary_dir / "region_panel_selection.csv", index=False)
        cell_summary.to_csv(summary_dir / "planned_cell_summary.csv", index=False)
        report = write_report(summary_dir, panel, cell_summary, grid_path, payload)
        write_json(summary_dir / "summary.json", {
            "grid_config": config_path_value(grid_path),
            "grid_id": args.grid_id,
            "regions": panel_regions(panel),
            "folds": folds,
            "n_regions": int(panel.shape[0]),
            "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
            "n_planned_cells": int(cell_summary["n_cells"].sum()),
            "report": config_path_value(report),
        })
    print(json.dumps({
        "grid_config": config_path_value(grid_path),
        "summary_dir": config_path_value(summary_dir),
        "regions": panel_regions(panel),
        "folds": folds,
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
        "n_planned_cells": int(cell_summary["n_cells"].sum()),
        "write": parse_bool(args.write),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
