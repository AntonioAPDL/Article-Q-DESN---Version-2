#!/usr/bin/env python3
"""Prepare the bounded PriceFM R102 causal Normal refit campaign."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_graph import graph_adj_matrix, graph_hash
from pricefm_recursive_normal import posterior_target_hash


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R101 = DATA / "launch_prep/pricefm_stage_r101_recursive_contract_20260916"
R97_PROCESSED = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/processed_validation"
NORMAL_RUNTIME = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
OUTPUT = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r102_recursive_normal_20260916"
QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
FOLDS = [1, 2, 3]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r101-dir", type=Path, default=R101)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--source-processed", type=Path, default=R97_PROCESSED)
    p.add_argument("--normal-runtime", type=Path, default=NORMAL_RUNTIME)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--posterior-paths", type=int, default=500)
    p.add_argument("--write", action="store_true")
    p.add_argument("--force", action="store_true")
    return p


def _json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _parse(value: Any) -> Any:
    if isinstance(value, (dict, list)):
        return value
    if pd.isna(value):
        return None
    return json.loads(str(value))


def _verify_r101(root: Path) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    summary = _json(root / "summary.json")
    if summary.get("status") != "completed_recursive_contract_engine_ready":
        raise RuntimeError("R101 is not complete")
    for role, expected in (summary.get("output_sha256") or {}).items():
        filename = (summary.get("output_files") or {}).get(role)
        if role == "report":
            filename = "pricefm_stage_r101_recursive_contract_closeout.md"
        if not filename or sha256_file(root / filename) != expected:
            raise RuntimeError("R101 output hash mismatch: {}".format(role))
    gates = pd.read_csv(root / "pricefm_stage_r101_gates.csv")
    if not gates.passed.astype(str).str.lower().isin(["true", "1"]).all():
        raise RuntimeError("R101 has a failed gate")
    control = pd.read_csv(root / "pricefm_stage_r101_r98_control_panel.csv")
    primary = pd.read_csv(root / "pricefm_stage_r101_r100_primary_panel.csv")
    structures = pd.read_csv(root / "pricefm_stage_r101_unique_structure_manifest.csv")
    contracts = pd.read_csv(root / "pricefm_stage_r101_unique_contract_manifest.csv")
    if (len(control), len(primary), len(structures), len(contracts)) != (38, 38, 48, 49):
        raise RuntimeError("R101 panel/contract counts changed")
    return summary, control, primary, structures, contracts


def _spec(row: pd.Series) -> dict[str, Any]:
    return {
        "region": str(row.region),
        "feature_policy": str(row.feature_policy),
        "lag_window": int(row.lag_window),
        "depth": int(row.depth),
        "units": [int(x) for x in _parse(row.units)],
        "alpha": float(row.alpha),
        "rho": float(row.rho),
        "input_scale": float(row.input_scale),
        "state_output": str(row.state_output),
        "seed": int(row.seed),
        "spatial": _parse(row.spatial) or {},
        "tau0": float(row.tau0),
        "structure_sha256": str(row.structure_sha256),
        "contract_sha256": str(row.contract_sha256),
        "active_regions": [str(x) for x in _parse(row.active_regions)],
    }


def _base_data_config(source_processed: Path, runtime_processed: Path) -> dict[str, Any]:
    candidate = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/regions/AT/surface_grid/configs/train_validation_data.yaml"
    config = yaml.safe_load(candidate.read_text())
    pricefm = config["pricefm"]
    pricefm["processed_dir"] = str(runtime_processed.resolve())
    pricefm["splits"] = [item for item in pricefm["splits"] if "test" not in item]
    pricefm["source_processed_dir"] = str(source_processed.resolve())
    pricefm["selection_firewall"] = "train_validation_only_test_absent"
    return config


def build(args: argparse.Namespace) -> dict[str, Any]:
    r101 = args.r101_dir.resolve()
    summary, control, primary, structures, contracts = _verify_r101(r101)
    if args.workers < 1 or args.workers > 50:
        raise ValueError("workers must be between 1 and 50")
    if args.posterior_paths != 500:
        raise ValueError("R102 production contract requires exactly 500 paths")
    regions = list(graph_adj_matrix())
    if sorted(control.region.astype(str)) != sorted(regions) or sorted(primary.region.astype(str)) != sorted(regions):
        raise RuntimeError("R101 panels do not cover the PriceFM graph")
    if control.test_used_for_selection.astype(str).str.lower().isin(["true", "1"]).any() or primary.test_used_for_selection.astype(str).str.lower().isin(["true", "1"]).any():
        raise RuntimeError("R101 source selection opened test outcomes")

    campaign = args.campaign_root.resolve()
    runtime_processed = campaign / "processed_recursive"
    configs = campaign / "configs"
    stats_root = campaign / "statistics"
    fits_root = campaign / "fits"
    base_config = _base_data_config(args.source_processed.resolve(), runtime_processed)
    data_configs: dict[int, dict[str, Any]] = {}
    for lag in sorted(structures.lag_window.astype(int).unique()):
        config = json.loads(json.dumps(base_config))
        config["pricefm"]["windows"]["lag_window"] = int(lag)
        data_configs[int(lag)] = config

    design_rows: list[dict[str, Any]] = []
    for _, row in structures.sort_values(["region", "structure_sha256"]).iterrows():
        spec = _spec(row)
        for fold in FOLDS:
            design_id = "r102_design_{}_f{}".format(spec["structure_sha256"][:16], fold)
            design_rows.append({
                "design_id": design_id,
                "region": spec["region"],
                "fold": fold,
                "structure_sha256": spec["structure_sha256"],
                "lag_window": spec["lag_window"],
                "active_regions": json.dumps(spec["active_regions"], separators=(",", ":")),
                "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
                "data_config_path": str(configs / "data_L{}.yaml".format(spec["lag_window"])),
                "statistics_dir": str(stats_root / design_id),
                "selection_split": "train_validation_only",
                "test_access_authorized": False,
            })
    designs = pd.DataFrame(design_rows)
    if len(designs) != 144 or designs.design_id.duplicated().any():
        raise RuntimeError("R102 requires 144 unique design-fold cells")

    design_lookup = designs.set_index(["structure_sha256", "fold"]).design_id.to_dict()
    fit_rows: list[dict[str, Any]] = []
    for _, row in structures.iterrows():
        spec = _spec(row)
        for fold in FOLDS:
            design_id = design_lookup[(spec["structure_sha256"], fold)]
            fit_id = "r102_ridge_{}_f{}".format(spec["structure_sha256"][:16], fold)
            stats_terminal = str(stats_root / design_id / "terminal.json")
            fit_rows.append({
                "fit_id": fit_id,
                "design_id": design_id,
                "region": spec["region"],
                "fold": fold,
                "prior_type": "scaled_ridge",
                "tau0": "",
                "structure_sha256": spec["structure_sha256"],
                "contract_sha256": "",
                "statistics_dir": str(stats_root / design_id),
                "statistics_terminal": stats_terminal,
                "output_dir": str(fits_root / fit_id),
                "selection_split": "train_validation_only",
                "test_access_authorized": False,
            })
    for _, row in contracts.iterrows():
        spec = _spec(row)
        for fold in FOLDS:
            design_id = design_lookup[(spec["structure_sha256"], fold)]
            fit_id = "r102_rhs_{}_f{}".format(spec["contract_sha256"][:16], fold)
            fit_rows.append({
                "fit_id": fit_id,
                "design_id": design_id,
                "region": spec["region"],
                "fold": fold,
                "prior_type": "rhs_ns",
                "tau0": spec["tau0"],
                "structure_sha256": spec["structure_sha256"],
                "contract_sha256": spec["contract_sha256"],
                "statistics_dir": str(stats_root / design_id),
                "statistics_terminal": str(stats_root / design_id / "terminal.json"),
                "output_dir": str(fits_root / fit_id),
                "selection_split": "train_validation_only",
                "test_access_authorized": False,
            })
    fits = pd.DataFrame(fit_rows)
    if len(fits) != 291 or fits.fit_id.duplicated().any() or (fits.prior_type.value_counts().to_dict() != {"rhs_ns": 147, "scaled_ridge": 144}):
        raise RuntimeError("R102 fit manifest must contain 144 Ridge and 147 RHS fits")

    ridge_lookup = fits[fits.prior_type.eq("scaled_ridge")].set_index(["structure_sha256", "fold"]).fit_id.to_dict()
    rhs_lookup = fits[fits.prior_type.eq("rhs_ns")].set_index(["contract_sha256", "fold"]).fit_id.to_dict()
    panel_rows: list[dict[str, Any]] = []
    for panel_name, panel in (("r98_control", control), ("r100_primary", primary)):
        for _, row in panel.iterrows():
            for fold in FOLDS:
                panel_rows.append({
                    "panel": panel_name,
                    "region": str(row.region),
                    "fold": fold,
                    "structure_sha256": str(row.structure_sha256),
                    "contract_sha256": str(row.contract_sha256),
                    "ridge_fit_id": ridge_lookup[(str(row.structure_sha256), fold)],
                    "rhs_fit_id": rhs_lookup[(str(row.contract_sha256), fold)],
                    "posterior_paths": 500,
                    "selection_split": "validation_only_complete_panel",
                    "test_access_authorized": False,
                })
    panels = pd.DataFrame(panel_rows)
    if len(panels) != 228 or panels[["panel", "region", "fold"]].duplicated().any():
        raise RuntimeError("R102 panel map must contain 2 x 38 x 3 rows")

    window_rows = []
    for _, row in structures.iterrows():
        active = [str(x) for x in _parse(row.active_regions)]
        for fold in FOLDS:
            for region in active:
                for split, boundary in (("train", "contained_half_open"), ("val", "operational_half_open")):
                    lag = int(row.lag_window)
                    window_rows.append({
                        "lag_window": lag,
                        "fold": fold,
                        "region": region,
                        "split": split,
                        "boundary_mode": boundary,
                        "runtime_path": str(runtime_processed / "windows" / "fold_{}".format(fold) / "region={}".format(region) / "{}_L{}_H96_{}.npz".format(split, lag, boundary)),
                        "test_access_authorized": False,
                    })
    windows = pd.DataFrame(window_rows).drop_duplicates(["lag_window", "fold", "region", "split"]).sort_values(["lag_window", "fold", "region", "split"])

    gates = pd.DataFrame([
        ("r101_status", summary["status"] == "completed_recursive_contract_engine_ready", summary["status"]),
        ("design_cells", len(designs) == 144, len(designs)),
        ("ridge_fits", int(fits.prior_type.eq("scaled_ridge").sum()) == 144, int(fits.prior_type.eq("scaled_ridge").sum())),
        ("rhs_fits", int(fits.prior_type.eq("rhs_ns").sum()) == 147, int(fits.prior_type.eq("rhs_ns").sum())),
        ("panel_map", len(panels) == 228, len(panels)),
        ("posterior_paths", args.posterior_paths == 500, args.posterior_paths),
        ("graph_hash", graph_hash() == summary["graph_sha256"], graph_hash()),
        ("test_split_absent", set(windows.split) == {"train", "val"}, ";".join(sorted(windows.split.unique()))),
        ("later_surfaces_blocked", True, "quantile;test;registry;article;joint;mcmc"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R102 preparation gate failed")

    source_paths = [
        r101 / "summary.json",
        r101 / "pricefm_stage_r101_r98_control_panel.csv",
        r101 / "pricefm_stage_r101_r100_primary_panel.csv",
        r101 / "pricefm_stage_r101_unique_structure_manifest.csv",
        r101 / "pricefm_stage_r101_unique_contract_manifest.csv",
        args.normal_runtime / "DESCRIPTION",
        args.normal_runtime / "R/qdesn_normal.R",
        args.normal_runtime / "R/priors_beta.R",
        args.normal_runtime / "R/qdesn_rhs_prior.R",
        Path(__file__).resolve(),
        Path(__file__).resolve().parent / "pricefm_recursive_normal.py",
        Path(__file__).resolve().parents[2] / "R/pricefm_recursive_normal_fit.R",
        Path(__file__).resolve().parent / "336_fit_pricefm_stage_r102_recursive_normal.R",
        Path(__file__).resolve().parent / "337_build_pricefm_stage_r102_recursive_statistics.py",
        Path(__file__).resolve().parent / "338_orchestrate_pricefm_stage_r102_recursive_normal.py",
    ]
    sources = pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths])
    return {
        "summary": {
            "stage": "R102",
            "status": "prepared_not_launched",
            "design_cells": 144,
            "ridge_fits": 144,
            "rhs_fits": 147,
            "total_fits": 291,
            "panel_region_fold_rows": 228,
            "window_requirements": len(windows),
            "workers_requested": args.workers,
            "posterior_paths": 500,
            "quantiles": QUANTILES,
            "selection_unit": "complete_38_region_panel",
            "selection_split": "validation_only",
            "test_opened": False,
            "quantile_fit_authorized": False,
            "joint_fit_authorized": False,
            "mcmc_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "launch_authorized": False,
            "next_gate": "clean_pushed_task_branch_plus_focused_tests_before_R102_launch",
        },
        "designs": designs,
        "fits": fits,
        "panels": panels,
        "windows": windows,
        "gates": gates,
        "sources": sources,
        "data_configs": data_configs,
        "runtime_processed": runtime_processed,
        "campaign": campaign,
        "source_processed": args.source_processed.resolve(),
        "normal_runtime": args.normal_runtime.resolve(),
        "workers": int(args.workers),
    }


def materialize(bundle: dict[str, Any], output: Path, force: bool = False) -> dict[str, Any]:
    output = output.resolve()
    if output.exists() and any(output.iterdir()) and not force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    bundle["campaign"].mkdir(parents=True, exist_ok=True)
    config_root = bundle["campaign"] / "configs"
    config_root.mkdir(parents=True, exist_ok=True)
    for lag, config in bundle["data_configs"].items():
        (config_root / "data_L{}.yaml".format(lag)).write_text(yaml.safe_dump(config, sort_keys=False))
    files = {
        "designs": "pricefm_stage_r102_design_manifest.csv",
        "fits": "pricefm_stage_r102_fit_manifest.csv",
        "panels": "pricefm_stage_r102_panel_map.csv",
        "windows": "pricefm_stage_r102_window_requirements.csv",
        "gates": "pricefm_stage_r102_prep_gates.csv",
        "sources": "source_manifest.csv",
    }
    for key, name in files.items():
        bundle[key].to_csv(output / name, index=False, quoting=csv.QUOTE_MINIMAL)
    control = {
        "stage": "R102",
        "campaign_root": str(bundle["campaign"]),
        "runtime_processed": str(bundle["runtime_processed"]),
        "source_processed": str(bundle["source_processed"]),
        "normal_runtime": str(bundle["normal_runtime"]),
        "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        "python": str(DATA / "venv/bin/python"),
        "workers": int(bundle["workers"]),
        "approval_token": "RUN_PRICEFM_R102_RECURSIVE_NORMAL",
        "launch_authorized": False,
        "selection_split": "train_validation_only",
        "forbidden": ["test", "quantile", "joint", "mcmc", "registry", "article"],
    }
    write_json(output / "pricefm_stage_r102_launch_control.json", control)
    summary = dict(bundle["summary"])
    summary["output_files"] = files
    summary["output_sha256"] = {key: sha256_file(output / name) for key, name in files.items()}
    summary["launch_control_sha256"] = sha256_file(output / "pricefm_stage_r102_launch_control.json")
    write_json(output / "summary.json", summary)
    report = """# PriceFM Stage-R102 recursive Normal launch preparation

R102 is prepared but not launched. It reuses the frozen R101 contracts and
contains 144 unique causal design-fold cells, 144 exact scaled-Ridge fits, and
147 Normal RHS_NS VB fits. The two complete panel maps each cover 38 regions
and three folds. No R100 search candidate is repeated.

The training design initializes on `L-1` rows, transitions on the final
observed row for horizon one, and then teacher-forces only after each
prediction. Validation recursion will replace those post-origin observations
with synchronized Normal posterior-predictive draws. All source data contracts
contain train and validation only.

Launching remains blocked until this source is committed and pushed on a clean
PriceFM task branch and the focused Python/R parity tests pass. Quantile fits,
outer-test scoring, joint models, MCMC, registry mutation, and article mutation
remain blocked until the later gates.
"""
    (output / "pricefm_stage_r102_launch_prep.md").write_text(report)
    summary["report_sha256"] = sha256_file(output / "pricefm_stage_r102_launch_prep.md")
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    args = parser().parse_args()
    bundle = build(args)
    if args.write:
        summary = materialize(bundle, args.output_dir, force=args.force)
    else:
        summary = bundle["summary"]
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
