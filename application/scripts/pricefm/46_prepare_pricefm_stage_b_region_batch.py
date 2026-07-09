#!/usr/bin/env python3
"""Prepare the PriceFM Stage-B new-region median-selection batch.

The script writes a local, ignored DESN/Q-DESN experiment grid plus a compact
batch manifest. It does not launch model fits. Stage B is deliberately
local-first: graph-neighbor A/B is the next stage after each new region/fold
has a validation-selected local median baseline.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import load_config, parse_bool, pricefm_block, repo_path, write_json
from pricefm_graph import get_k_hop_regions


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_CURRENT_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_region_panel_median_graph_local_closeout_20260614/merged_selection_registry.csv"
)
DEFAULT_PHASE1 = "application/data_local/pricefm/external/PriceFM/Result/phase1_pretraining.csv"
DEFAULT_GRID_ID = "pricefm_stage_b_median_batch1_20260616"
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_b_median_batch1_20260616.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_b_median_batch1_20260616"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_b_median_batch1_20260616"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_b_median_batch1_plan_20260616"
)
DEFAULT_REGIONS = "PT,BG,ES,FR,FI,IT_NORD,AT,PL"


REGION_ROLES = {
    "PT": "low_graph_degree_edge_case",
    "IT_SARD": "low_graph_degree_edge_case",
    "BG": "hard_phase1_low_graph_degree",
    "ES": "iberian_medium_graph_pair",
    "FR": "high_volatility_graph_hub",
    "FI": "nordic_negative_price_graph",
    "IT_NORD": "italian_hub_high_spread",
    "AT": "high_graph_degree_hub_adjacent",
    "NL": "high_graph_degree_hub_adjacent",
    "PL": "high_graph_degree_hard_region",
    "SE_3": "high_graph_degree_nordic_bridge",
}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", default="application/config/pricefm_data_pipeline.yaml")
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--current-registry-csv", default=DEFAULT_CURRENT_REGISTRY)
    p.add_argument("--phase1-reference-csv", default=DEFAULT_PHASE1)
    p.add_argument("--candidate-regions", default=DEFAULT_REGIONS)
    p.add_argument("--folds", default="1,2,3")
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--write", type=parse_bool, default=True)
    p.add_argument("--allow-covered", type=parse_bool, default=False)
    return p


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
    return merged.sort_values("region").reset_index(drop=True), [str(x) for x in spec["regions"]]


def covered_regions(current_registry_csv):
    registry = read_csv_required(current_registry_csv, "current median registry")
    if "region" not in registry.columns:
        raise ValueError("Current registry must include a region column.")
    return set(registry["region"].astype(str).unique())


def graph_summary(region, all_regions):
    d1 = get_k_hop_regions(region, all_regions, 1)
    d2 = get_k_hop_regions(region, all_regions, 2)
    return {
        "degree1_n": int(len(d1)),
        "degree2_n": int(len(d2)),
        "degree1_regions": "|".join(d1),
        "degree2_regions": "|".join(d2),
    }


def build_region_manifest(scores, candidate_regions, all_regions, covered, allow_covered=False):
    candidate_regions = [str(x) for x in candidate_regions]
    if not candidate_regions:
        raise ValueError("candidate-regions must be nonempty.")
    score_idx = {str(row["region"]): row for _, row in scores.iterrows()}
    missing = [r for r in candidate_regions if r not in score_idx]
    if missing:
        raise ValueError("Candidate regions absent from score universe: {}".format(missing))
    repeated = sorted({r for r in candidate_regions if candidate_regions.count(r) > 1})
    if repeated:
        raise ValueError("Duplicate candidate regions: {}".format(repeated))
    already = [r for r in candidate_regions if r in covered]
    if already and not bool(allow_covered):
        raise ValueError("Candidate regions already covered by current registry: {}".format(already))
    rows = []
    for rank, region in enumerate(candidate_regions, start=1):
        row = score_idx[region].to_dict()
        out = {
            "batch_rank": int(rank),
            "region": region,
            "selection_role": REGION_ROLES.get(region, "manual_stage_b_candidate"),
            "already_covered": bool(region in covered),
        }
        for key in [
            "phase1_AQL", "phase1_MAE", "phase1_RMSE", "median",
            "spread_p99_p01", "tail_range", "negative_rate", "zero_rate",
            "min", "p01", "p99", "max",
        ]:
            out[key] = row[key]
        out.update(graph_summary(region, all_regions))
        rows.append(out)
    return pd.DataFrame(rows)


def candidate_experiments(regions, folds):
    common = {
        "stage": "stage_b_local_median",
        "regions": list(regions),
        "folds": [int(x) for x in folds],
        "feature_map": "window_reservoir_v1",
        "feature_policy": "target_only",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
        "candidate_source": "stage_b_local_median_batch1_20260616",
        "candidate_source_final": "stage_b_local_median_batch1_20260616",
        "selection_is_validation_only": True,
        "target_label": "stage_b_new_region_local_median_validation",
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "quantile": 0.50,
        "state_output": "final_layer",
    }
    specs = [
        {
            "id": "stageb_core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601",
            "priority": 0,
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260601,
            "rationale": "Stage-B local-first anchor from the corrected DE_LU fold-1 winner geometry.",
        },
        {
            "id": "stageb_lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603",
            "priority": 0,
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.25,
            "seed": 20260603,
            "rationale": "Stage-B local-first lower-input-scale anchor from DE_LU fold-2 follow-up.",
        },
        {
            "id": "stageb_d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603",
            "priority": 0,
            "lag_window": 96,
            "depth": 2,
            "units": [80, 80],
            "alpha": 0.40,
            "rho": 0.90,
            "input_scale": 0.35,
            "seed": 20260603,
            "rationale": "Stage-B local-first compact D=2 anchor from DE_LU fold-3 follow-up.",
        },
        {
            "id": "stageb_compact_l096_d1_n080_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 96,
            "depth": 1,
            "units": [80],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Optional compact local diagnostic after priority 0 is inspected.",
        },
        {
            "id": "stageb_short_l072_d1_n120_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 72,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Optional shorter-context local diagnostic.",
        },
        {
            "id": "stageb_long_l128_d1_n120_a0p5_r0p9_in0p50_seed20260603",
            "priority": 1,
            "lag_window": 128,
            "depth": 1,
            "units": [120],
            "alpha": 0.50,
            "rho": 0.90,
            "input_scale": 0.50,
            "seed": 20260603,
            "rationale": "Optional slightly longer-context local diagnostic.",
        },
    ]
    out = []
    for spec in specs:
        row = dict(common)
        row.update(spec)
        out.append(row)
    return out


def build_grid(template_payload, grid_id, generated_root, run_root, region_manifest, folds):
    payload = copy.deepcopy(template_payload)
    if GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain {}".format(GRID_BLOCK))
    grid = payload[GRID_BLOCK]
    regions = [str(x) for x in region_manifest["region"].tolist()]
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Stage-B median-only new-region expansion. This is a local-first "
        "validation-selection grid; graph-neighbor A/B is prepared only after "
        "local median winners exist for these new regions."
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
    grid.setdefault("fixed", {})
    grid["fixed"]["feature_policy"] = "target_only"
    grid["fixed"]["train_origin_limit"] = 3000
    grid["fixed"]["shrink_intercept"] = False
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["experiments"] = candidate_experiments(regions, folds)
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "dry_run_gate": {
            "priorities": [0],
            "experiment_jobs": 3,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Run first with --dry-run true before launching priority 0.",
        },
        "priority0_stage_b_local_median": {
            "priorities": [0],
            "experiment_jobs": 3,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "First real Stage-B launch: 3 local median geometries over selected regions/folds.",
        },
        "priority1_optional_local_diagnostics": {
            "priorities": [1],
            "experiment_jobs": 3,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Optional diagnostics after priority 0 closeout is inspected.",
        },
    }
    return payload


def planned_cell_summary(region_manifest, grid_payload):
    grid = grid_payload[GRID_BLOCK]
    n_regions = int(region_manifest.shape[0])
    n_folds = len(grid["scope"]["folds"])
    rows = []
    for exp in grid["experiments"]:
        rows.append({
            "experiment_id": str(exp["id"]),
            "priority": int(exp["priority"]),
            "feature_policy": str(exp["feature_policy"]),
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
    return pd.DataFrame(rows).sort_values(["priority", "experiment_id"]).reset_index(drop=True)


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


def write_report(summary_dir, region_manifest, cell_summary, grid_path, grid_payload):
    report = summary_dir / "stage_b_median_batch_report.md"
    grid = grid_payload[GRID_BLOCK]
    priority0_cells = int(cell_summary[cell_summary["priority"].eq(0)]["n_cells"].sum())
    all_cells = int(cell_summary["n_cells"].sum())
    with open(report, "w") as f:
        f.write("# PriceFM Stage-B Median Batch 1\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(grid_path)))
        f.write("Grid id: `{}`\n\n".format(grid["grid_id"]))
        f.write("## Purpose\n\n")
        f.write(
            "This batch expands beyond the six-region graph/local panel using a "
            "local-first median-selection gate. Selection uses validation AQL. "
            "PriceFM test metrics remain audit-only. Graph-neighbor A/B should "
            "be generated only after local median winners exist for these new "
            "regions.\n\n"
        )
        f.write("## Selected Regions\n\n")
        f.write(markdown_table(region_manifest, columns=[
            "batch_rank", "region", "selection_role", "phase1_AQL",
            "phase1_MAE", "spread_p99_p01", "negative_rate",
            "degree1_n", "degree2_n",
        ]))
        f.write("\n\n## Planned Experiments\n\n")
        f.write(markdown_table(cell_summary, columns=[
            "experiment_id", "priority", "feature_policy", "n_regions",
            "n_folds", "n_cells", "lag_window", "depth", "units",
            "alpha", "rho", "input_scale", "seed",
        ]))
        f.write("\n\nPriority-0 planned cells: `{}`\n\n".format(priority0_cells))
        f.write("All planned cells, including optional diagnostics: `{}`\n\n".format(all_cells))
        f.write("## Launch Discipline\n\n")
        f.write("- Materialize configs with `12_prepare_desn_experiment_grid.py --write`.\n")
        f.write("- Dry-run priority 0 with `13_run_desn_experiment_grid.py --dry-run true`.\n")
        f.write("- Launch priority 0 only after the dry-run passes.\n")
        f.write("- Do not run priority 1 until priority 0 has a completed validation closeout.\n")
        f.write("- Do not promote quantiles from this batch until validation-selected median rows are frozen.\n")
        f.write("- Keep graph-neighbor A/B as the next-stage comparison, not part of the first local baseline launch.\n")
    return report


def main():
    args = parser().parse_args()
    folds = parse_csv(args.folds, int)
    candidate_regions = parse_csv(args.candidate_regions, str)
    scores, all_regions = load_region_scores(args.config, args.phase1_reference_csv)
    covered = covered_regions(args.current_registry_csv)
    region_manifest = build_region_manifest(
        scores,
        candidate_regions,
        all_regions,
        covered,
        allow_covered=bool(args.allow_covered),
    )
    template = read_yaml(args.template_grid_config)
    payload = build_grid(
        template,
        args.grid_id,
        args.generated_root,
        args.run_root,
        region_manifest,
        folds,
    )
    cell_summary = planned_cell_summary(region_manifest, payload)
    summary_dir = repo_path(args.summary_dir)
    grid_path = repo_path(args.output_grid_config)
    if bool(args.write):
        write_yaml(grid_path, payload)
        summary_dir.mkdir(parents=True, exist_ok=True)
        scores.to_csv(summary_dir / "stage_b_region_score_universe.csv", index=False)
        region_manifest.to_csv(summary_dir / "stage_b_region_batch_manifest.csv", index=False)
        cell_summary.to_csv(summary_dir / "stage_b_planned_cell_summary.csv", index=False)
        report = write_report(summary_dir, region_manifest, cell_summary, grid_path, payload)
        write_json(summary_dir / "summary.json", {
            "grid_config": config_path_value(grid_path),
            "grid_id": args.grid_id,
            "regions": region_manifest["region"].astype(str).tolist(),
            "folds": folds,
            "n_regions": int(region_manifest.shape[0]),
            "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
            "n_priority0_experiments": int(cell_summary["priority"].eq(0).sum()),
            "n_priority0_cells": int(cell_summary[cell_summary["priority"].eq(0)]["n_cells"].sum()),
            "n_all_cells": int(cell_summary["n_cells"].sum()),
            "report": config_path_value(report),
        })
    print(json.dumps({
        "grid_config": config_path_value(grid_path),
        "summary_dir": config_path_value(summary_dir),
        "regions": region_manifest["region"].astype(str).tolist(),
        "folds": folds,
        "n_experiments": len(payload[GRID_BLOCK]["experiments"]),
        "n_priority0_cells": int(cell_summary[cell_summary["priority"].eq(0)]["n_cells"].sum()),
        "n_all_cells": int(cell_summary["n_cells"].sum()),
        "write": bool(args.write),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
