#!/usr/bin/env python3
"""Freeze the all-region PriceFM campaign and its overall-AQL decision rule."""

from __future__ import annotations

import argparse
import ast
import json
import math
from pathlib import Path
import sys
from typing import Any

import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    atomic_write_json,
    canonical_sha256,
    file_record,
    prepare_empty_directory,
    sha256_file,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R92 = Path(
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__integration_pricefm_r91_20260905/"
    "application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905/"
    "pricefm_full_surface_decision_registry.csv"
)
R96 = DATA / (
    "authoritative/pricefm_stage_r96_scoring_only_test_closeout_20260908/"
    "pricefm_stage_r96_se2_fold_comparison.csv"
)
SOURCE_DATA = Path(__file__).resolve().parents[2] / "config/pricefm_data_pipeline.yaml"
TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
OUTPUT = DATA / f"authoritative/{TAG}_prep"
CAMPAIGN_ROOT = DATA / "campaigns" / TAG
REUSE_REGION = "SE_2"
R92_SHA256 = "3922a06a965e8eac6320edbc2cb38464c007c51698814b419271690f9a4c9f87"
R96_SHA256 = "b93302cd85059b8dafac12dae59bc251d30105948a302a2d7f516be65805a985"
SPEC_FIELDS = (
    "lag_window", "depth", "units", "alpha", "rho", "input_scale",
    "tau0", "seed", "state_output",
)
OPTIONAL_SPEC_FIELDS = (
    "graph_degree", "neighbor_regions", "max_neighbor_regions",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--authority-registry", type=Path, default=R92)
    value.add_argument("--history-root", type=Path, default=DATA / "authoritative")
    value.add_argument("--source-data-config", type=Path, default=SOURCE_DATA)
    value.add_argument("--se2-comparison", type=Path, default=R96)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN_ROOT)
    value.add_argument("--reuse-region", default=REUSE_REGION)
    value.add_argument("--workers", type=int, default=20)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    value.add_argument("--allow-fixture-hashes", action="store_true")
    return value


def parse_units(value: Any) -> list[int]:
    parsed = ast.literal_eval(str(value)) if isinstance(value, str) else value
    if not isinstance(parsed, (list, tuple)):
        parsed = [parsed]
    result = [int(float(item)) for item in parsed]
    if not result or any(item <= 0 for item in result):
        raise ValueError(f"invalid DESN units: {value!r}")
    return result


def normalize(field: str, value: Any) -> Any:
    if field == "units":
        return tuple(parse_units(value))
    if field in {"lag_window", "depth", "seed", "graph_degree", "max_neighbor_regions"}:
        return int(float(value))
    if field in {"alpha", "rho", "input_scale", "tau0"}:
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"non-finite {field}: {value!r}")
        return round(number, 14)
    if field == "neighbor_regions":
        parsed = ast.literal_eval(str(value)) if isinstance(value, str) else value
        return tuple(str(item) for item in parsed)
    return str(value)


def historical_spec_index(history_root: Path, experiment_ids: set[str]) -> dict[str, dict[str, Any]]:
    observed = {
        experiment_id: {field: set() for field in (*SPEC_FIELDS, *OPTIONAL_SPEC_FIELDS)}
        for experiment_id in experiment_ids
    }
    source_paths: dict[str, set[str]] = {experiment_id: set() for experiment_id in experiment_ids}
    for path in sorted(history_root.glob("*/*.csv")):
        try:
            header = pd.read_csv(path, nrows=0)
        except Exception:
            continue
        if "experiment_id" not in header.columns:
            continue
        available = [field for field in (*SPEC_FIELDS, *OPTIONAL_SPEC_FIELDS) if field in header.columns]
        if not available:
            continue
        try:
            frame = pd.read_csv(path, usecols=["experiment_id", *available], low_memory=False)
        except Exception:
            continue
        frame = frame[frame.experiment_id.astype(str).isin(experiment_ids)]
        for row in frame.to_dict("records"):
            experiment_id = str(row["experiment_id"])
            for field in available:
                value = row.get(field)
                if pd.isna(value):
                    continue
                observed[experiment_id][field].add(normalize(field, value))
            source_paths[experiment_id].add(str(path.resolve()))

    resolved: dict[str, dict[str, Any]] = {}
    failures: list[str] = []
    for experiment_id in sorted(experiment_ids):
        values: dict[str, Any] = {}
        for field in SPEC_FIELDS:
            candidates = observed[experiment_id][field]
            if len(candidates) != 1:
                failures.append(f"{experiment_id}:{field}:{sorted(map(str, candidates))}")
                continue
            values[field] = next(iter(candidates))
        if len(values) == len(SPEC_FIELDS):
            values["units"] = list(values["units"])
            for field in OPTIONAL_SPEC_FIELDS:
                candidates = observed[experiment_id][field]
                if len(candidates) > 1:
                    failures.append(f"{experiment_id}:{field}:{sorted(map(str, candidates))}")
                elif len(candidates) == 1:
                    values[field] = next(iter(candidates))
            if "neighbor_regions" in values:
                values["neighbor_regions"] = list(values["neighbor_regions"])
            values["source_files"] = sorted(source_paths[experiment_id])
            resolved[experiment_id] = values
    if failures:
        raise RuntimeError("historical specification resolution is incomplete or ambiguous: " + "; ".join(failures[:20]))
    return resolved


def authoritative_controls(registry: pd.DataFrame, history_root: Path) -> pd.DataFrame:
    experiment_ids = set(registry.experiment_id.astype(str))
    index = historical_spec_index(history_root, experiment_ids)
    rows: list[dict[str, Any]] = []
    for source in registry.sort_values(["region", "fold"]).itertuples(index=False):
        experiment_id = str(source.experiment_id)
        spec = index[experiment_id]
        rows.append({
            "region": str(source.region),
            "fold": int(source.fold),
            "experiment_id": experiment_id,
            "feature_policy": str(source.feature_policy),
            "lag_window": spec["lag_window"],
            "depth": spec["depth"],
            "units": json.dumps(spec["units"], separators=(",", ":")),
            "alpha": spec["alpha"],
            "rho": spec["rho"],
            "input_scale": spec["input_scale"],
            "state_output": spec["state_output"],
            "seed": spec["seed"],
            "tau0": spec["tau0"],
            "graph_degree": spec.get("graph_degree"),
            "neighbor_regions": json.dumps(spec.get("neighbor_regions", []), separators=(",", ":")),
            "max_neighbor_regions": spec.get("max_neighbor_regions"),
            "specification_source_count": len(spec["source_files"]),
            "specification_source_paths": json.dumps(spec["source_files"], separators=(",", ":")),
        })
    return pd.DataFrame(rows)


def read_regions(path: Path) -> list[str]:
    payload = yaml.safe_load(path.read_text())
    return [str(value) for value in payload["pricefm"]["regions"]]


def validate_registry(registry: pd.DataFrame, regions: list[str]) -> None:
    required = {
        "region", "fold", "experiment_id", "feature_policy", "qdesn_AQL", "pricefm_AQL",
    }
    missing = sorted(required - set(registry.columns))
    if missing:
        raise RuntimeError(f"R92 authority omits required fields: {missing}")
    expected = {(region, fold) for region in regions for fold in (1, 2, 3)}
    observed = set(zip(registry.region.astype(str), registry.fold.astype(int)))
    if observed != expected or len(registry) != len(expected):
        raise RuntimeError("R92 authority is not the exact configured 38-region by three-fold surface")
    if registry.duplicated(["region", "fold"]).any():
        raise RuntimeError("R92 authority contains duplicate region/fold rows")


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= int(args.workers) <= 20:
        raise RuntimeError("R97 permits 1--20 concurrent one-core model processes")
    for path in (args.authority_registry, args.history_root, args.source_data_config, args.se2_comparison):
        if not path.exists():
            raise FileNotFoundError(path)
    if not args.allow_fixture_hashes:
        if sha256_file(args.authority_registry) != R92_SHA256:
            raise RuntimeError("R97 authority is not the hash-pinned R92 full surface")
        if sha256_file(args.se2_comparison) != R96_SHA256:
            raise RuntimeError("R97 reuse surface is not the hash-pinned R96 SE_2 closeout")
    regions = read_regions(args.source_data_config)
    registry = pd.read_csv(args.authority_registry, low_memory=False)
    validate_registry(registry, regions)
    if args.reuse_region not in regions:
        raise RuntimeError("reuse region is absent from the configured PriceFM panel")
    se2 = pd.read_csv(args.se2_comparison)
    if set(se2.region.astype(str)) != {args.reuse_region} or sorted(se2.fold.astype(int)) != [1, 2, 3]:
        raise RuntimeError("the frozen reuse surface is not the exact three-fold SE_2 result")
    controls = authoritative_controls(registry, args.history_root)
    if len(controls) != 114 or controls.duplicated(["region", "fold"]).any():
        raise RuntimeError("resolved authoritative controls are not the exact 114-case surface")

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or (args.output_dir.parent / "quarantine"),
        reason="replaced_r97_global_campaign_prep",
        allow_quarantine=args.quarantine_existing,
    )
    campaign_root = args.campaign_root.resolve()
    campaign_root.mkdir(parents=True, exist_ok=True)
    controls_path = output / "pricefm_stage_r97_authoritative_spec_controls.csv"
    controls.to_csv(controls_path, index=False)

    region_rows = []
    for region in regions:
        reused = region == args.reuse_region
        root = campaign_root / "regions" / region
        region_rows.append({
            "region": region,
            "folds": "1,2,3",
            "case_count": 3,
            "action": "reuse_frozen_r96" if reused else "run_region_frozen_validation_ladder",
            "execution_required": not reused,
            "ridge_candidates": 0 if reused else 240,
            "ridge_inner_fit_cells": 0 if reused else 720,
            "rhs_coarse_arms": 0 if reused else 90,
            "rhs_inner_fit_cells": 0 if reused else 270,
            "region_root": str(root.resolve()),
        })
    region_plan = pd.DataFrame(region_rows)
    region_plan_path = output / "pricefm_stage_r97_region_plan.csv"
    region_plan.to_csv(region_plan_path, index=False)

    authority_mean = float(registry.qdesn_AQL.astype(float).mean())
    pricefm_mean = float(registry.pricefm_AQL.astype(float).mean())
    contract = {
        "schema_version": 1,
        "stage": "R97",
        "status": "campaign_frozen_not_launched",
        "tag": TAG,
        "campaign_root": str(campaign_root),
        "scientific_estimand": "complete_region_specific_challenger_surface",
        "regions": regions,
        "folds": [1, 2, 3],
        "case_count": 114,
        "regions_to_fit": [region for region in regions if region != args.reuse_region],
        "regions_to_fit_count": len(regions) - 1,
        "reused_region": args.reuse_region,
        "selection": {
            "unit": "region",
            "desn_and_tau0": "one_region_specific_pair_selected_without_test_data",
            "likelihood_family": "one_whole_AL_or_exAL_family_per_region_selected_on_fold1_validation",
            "fold_or_quantile_specific_retuning": False,
            "test_driven_case_mixing": False,
        },
        "final_decision": {
            "primary_metric": "AQL_original",
            "aggregation": "unweighted_arithmetic_mean_over_exactly_114_region_fold_cases",
            "candidate_surface": "all_R97_region_specific_results_with_frozen_R96_SE_2_reuse",
            "primary_comparator": "complete_current_R92_authoritative_QDESN_surface",
            "secondary_comparator": "complete_cached_PriceFM_surface",
            "per_case_dual_comparator_veto": False,
            "promotion_gate": "candidate_mean_AQL_strictly_below_current_R92_mean_AQL",
            "pricefm_reporting": "report_candidate_minus_PriceFM_mean_AQL_without_using_test_to_select_cases",
        },
        "frozen_comparator_values": {
            "current_authoritative_qdesn_mean_AQL": authority_mean,
            "cached_pricefm_mean_AQL": pricefm_mean,
        },
        "workers": int(args.workers),
        "one_model_process_per_cpu": True,
        "streaming_screen_compaction_required": True,
        "authority_registry": file_record(args.authority_registry, "R92_full_surface_authority"),
        "resolved_controls": file_record(controls_path, "R97_all_case_spec_controls"),
        "se2_reuse": file_record(args.se2_comparison, "R96_frozen_SE_2_test_surface"),
        "source_data_config": file_record(args.source_data_config, "PriceFM_data_contract"),
        "test_opened_during_selection": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    contract_hash = canonical_sha256(contract)
    contract["campaign_contract_sha256"] = contract_hash
    contract_path = output / "pricefm_stage_r97_campaign_contract.json"
    atomic_write_json(contract_path, contract)

    gates = pd.DataFrame([
        {"gate": "exact_38_regions", "passed": len(regions) == 38, "observed": len(regions)},
        {"gate": "exact_114_cases", "passed": len(registry) == 114, "observed": len(registry)},
        {"gate": "all_authoritative_specs_resolved", "passed": len(controls) == 114, "observed": len(controls)},
        {"gate": "reuse_exactly_SE2", "passed": int((~region_plan.execution_required).sum()) == 1, "observed": args.reuse_region},
        {"gate": "fit_remaining_37_regions", "passed": int(region_plan.execution_required.sum()) == 37, "observed": int(region_plan.execution_required.sum())},
        {"gate": "overall_mean_primary", "passed": contract["final_decision"]["aggregation"].startswith("unweighted"), "observed": "114-case mean"},
        {"gate": "no_per_case_veto", "passed": contract["final_decision"]["per_case_dual_comparator_veto"] is False, "observed": False},
        {"gate": "no_test_driven_mixing", "passed": contract["selection"]["test_driven_case_mixing"] is False, "observed": False},
        {"gate": "mutations_blocked", "passed": not contract["registry_mutation_authorized"] and not contract["article_mutation_authorized"], "observed": "blocked"},
    ])
    if not gates.passed.astype(bool).all():
        raise RuntimeError(f"R97 campaign gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates_path = output / "pricefm_stage_r97_campaign_gates.csv"
    gates.to_csv(gates_path, index=False)
    source_path = output / "source_manifest.csv"
    pd.DataFrame([
        file_record(args.authority_registry, "R92_full_surface_authority"),
        file_record(args.source_data_config, "PriceFM_data_contract"),
        file_record(args.se2_comparison, "R96_frozen_SE_2_surface"),
        file_record(controls_path, "resolved_authoritative_controls"),
        file_record(region_plan_path, "campaign_region_plan"),
        file_record(contract_path, "campaign_contract"),
    ]).to_csv(source_path, index=False)
    report_path = output / "pricefm_stage_r97_global_campaign_plan.md"
    report_path.write_text(
        "# PriceFM Stage-R97 global region-specific campaign\n\n"
        "R97 fits a separate, validation-selected DESN/tau0/family contract for each of "
        "37 regions and reuses the already frozen SE_2 surface. Individual region/fold "
        "results are diagnostics, not vetoes. The single primary decision is the unweighted "
        "mean original-scale AQL over all 114 region/fold cases. The complete challenger "
        f"surface must beat the frozen R92 mean ({authority_mean:.9f}); cached PriceFM "
        f"({pricefm_mean:.9f}) is reported as a second complete-surface benchmark. No "
        "test-driven case replacement, registry mutation, or article mutation is allowed.\n"
    )
    summary = {
        "status": "completed_campaign_frozen_not_launched",
        "stage": "R97",
        "regions": len(regions),
        "regions_to_fit": 37,
        "reused_regions": 1,
        "cases": 114,
        "workers": int(args.workers),
        "current_authoritative_qdesn_mean_AQL": authority_mean,
        "cached_pricefm_mean_AQL": pricefm_mean,
        "campaign_contract_sha256": contract_hash,
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "launch_invoked": False,
        "registry_mutated": False,
        "article_mutated": False,
        "outputs": {
            "controls": str(controls_path), "region_plan": str(region_plan_path),
            "contract": str(contract_path), "gates": str(gates_path),
            "source_manifest": str(source_path), "report": str(report_path),
        },
    }
    summary["output_sha256"] = {
        name: sha256_file(path) for name, path in {
            **{key: Path(value) for key, value in summary["outputs"].items()},
        }.items()
    }
    atomic_write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
