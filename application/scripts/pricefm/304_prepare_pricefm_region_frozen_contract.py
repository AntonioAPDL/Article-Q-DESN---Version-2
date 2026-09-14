#!/usr/bin/env python3
"""Freeze a reusable, region-specific PriceFM calibration request contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_graph import graph_scope_manifest_for_policy
from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    copy_file_verified,
    file_record,
    prepare_empty_directory,
    sha256_file,
)


POLICIES = (
    "target_only", "graph_summary_mean", "graph_summary_mean_std", "graph_khop"
)
POLICY_WEIGHTS = {
    "target_only": 0.40,
    "graph_summary_mean": 0.30,
    "graph_summary_mean_std": 0.20,
    "graph_khop": 0.10,
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--pipeline-id", required=True)
    value.add_argument("--target-region", required=True)
    value.add_argument("--authority-registry", type=Path, required=True)
    value.add_argument("--control-registry", type=Path, required=True)
    value.add_argument("--data-config", type=Path, required=True)
    value.add_argument("--artifact-root", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--selection-fold", type=int, default=1)
    value.add_argument("--real-folds", default="1,2,3")
    value.add_argument("--candidate-count", type=int, default=240)
    value.add_argument("--ridge-top-k", type=int, default=30)
    value.add_argument("--coarse-tau0", default="1e-4,1e-3,1e-2")
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def parse_ints(value: str) -> list[int]:
    result = [int(token.strip()) for token in value.split(",") if token.strip()]
    if not result or len(result) != len(set(result)):
        raise RuntimeError("fold list must contain unique integers")
    return result


def parse_floats(value: str) -> list[float]:
    result = [float(token.strip()) for token in value.split(",") if token.strip()]
    if not result or any(number <= 0 for number in result):
        raise RuntimeError("tau0 grid must contain positive values")
    return result


def load_data_config(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict) or not isinstance(payload.get("pricefm"), dict):
        raise RuntimeError(f"invalid PriceFM data configuration: {path}")
    return payload["pricefm"]


def select_rows(frame: pd.DataFrame, region: str, folds: list[int], label: str) -> pd.DataFrame:
    required = {"region", "fold"}
    if not required.issubset(frame):
        raise RuntimeError(f"{label} omits {sorted(required - set(frame.columns))}")
    selected = frame[
        frame.region.astype(str).eq(region)
        & frame.fold.astype(int).isin(folds)
    ].copy().sort_values("fold")
    if selected.fold.astype(int).tolist() != folds:
        raise RuntimeError(f"{label} does not contain exactly folds {folds} for {region}")
    return selected


def graph_contract(region: str, regions: list[str]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "target_only": {
            "target_region": region, "neighbor_regions": [], "graph_degree": 0,
            "degree_zero_equals_target_only": True,
        }
    }
    for policy in POLICIES[1:]:
        manifest = graph_scope_manifest_for_policy(
            region, regions, policy, spatial={"graph_degree": 1}
        )
        result[policy] = {
            "target_region": region,
            "neighbor_regions": list(manifest["neighbor_regions"]),
            "graph_degree": 1,
            "graph_source": manifest["graph_source"],
            "graph_hash": manifest["graph_hash"],
            "degree_zero_equals_target_only": len(manifest["neighbor_regions"]) == 0,
        }
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    folds = parse_ints(args.real_folds)
    if folds != [1, 2, 3] or args.selection_fold not in folds:
        raise RuntimeError("PriceFM region contracts require real folds 1,2,3")
    if args.candidate_count < 10 or args.ridge_top_k < 1 or args.ridge_top_k >= args.candidate_count:
        raise RuntimeError("candidate-count/top-k contract is invalid")
    authority_path = args.authority_registry.resolve()
    control_path = args.control_registry.resolve()
    data_path = args.data_config.resolve()
    for path in (authority_path, control_path, data_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    data = load_data_config(data_path)
    regions = [str(value) for value in data.get("regions", [])]
    region = str(args.target_region)
    if region not in regions:
        raise RuntimeError(f"target region is absent from data configuration: {region}")
    authority = select_rows(pd.read_csv(authority_path, low_memory=False), region, folds, "authority")
    controls = select_rows(pd.read_csv(control_path, low_memory=False), region, folds, "controls")
    split_map = {int(item["fold"]): item for item in data.get("splits", [])}
    if sorted(split_map) != folds:
        raise RuntimeError("data configuration does not expose exactly real folds 1,2,3")

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or (args.output_dir.parent / "quarantine"),
        reason=f"replaced_{args.pipeline_id}",
        allow_quarantine=args.quarantine_existing,
    )
    frozen_dir = output / "frozen_sources"
    frozen_dir.mkdir()
    frozen_records = [
        copy_file_verified(authority_path, frozen_dir / "authority_registry.csv"),
        copy_file_verified(control_path, frozen_dir / "control_registry.csv"),
        copy_file_verified(data_path, frozen_dir / "data_config.yaml"),
    ]
    authority.to_csv(output / "target_authority_rows.csv", index=False)
    controls.to_csv(output / "target_control_rows.csv", index=False)
    seed = int(canonical_sha256({"pipeline_id": args.pipeline_id, "region": region})[:8], 16)
    contract = {
        "schema_version": 1,
        "pipeline_id": str(args.pipeline_id),
        "target_region": region,
        "selection_fold": int(args.selection_fold),
        "real_folds": folds,
        "quantiles": list(PAPER_QUANTILES),
        "artifact_root": str(args.artifact_root.resolve()),
        "authority_registry": file_record(authority_path, "input_authority_registry"),
        "control_registry": file_record(control_path, "input_control_registry"),
        "data_config": file_record(data_path, "input_data_config"),
        "frozen_sources": frozen_records,
        "candidate_bank": {
            "candidate_count": int(args.candidate_count),
            "policy_weights": POLICY_WEIGHTS,
            "mandatory_authoritative_fold_controls": folds,
            "deterministic_seed": seed,
            "geometry_axes": {
                "units": [[48], [64], [96], [128], [160], [48, 48], [64, 64],
                          [80, 80], [96, 96], [120, 120], [96, 48], [120, 64],
                          [40, 40, 40], [48, 48, 48], [64, 64, 64],
                          [80, 80, 80], [96, 64, 48]],
                "lag_window": [48, 96, 168, 240],
                "alpha": [0.25, 0.35, 0.40, 0.45, 0.50, 0.55],
                "rho": [0.82, 0.90, 0.95],
                "input_scale": [0.15, 0.20, 0.25, 0.35, 0.50],
                "state_output": ["final_layer"],
            },
        },
        "ridge_top_k": int(args.ridge_top_k),
        "normal_rhs": {
            "coarse_tau0_grid": parse_floats(args.coarse_tau0),
            "conditional_refinement": {
                "interior": "adjacent_log_midpoints",
                "lower_boundary": "one_pre_registered_lower_decade",
                "upper_boundary": "one_pre_registered_upper_decade",
                "maximum_new_arms": 2,
            },
        },
        "graph_contract": graph_contract(region, regions),
        "selection": {
            "geometry_window": "three_temporal_validation_windows_inside_selection_fold_training",
            "family_window": "reserved_selection_fold_validation",
            "metric": "original_scale_AQL",
            "whole_family_only": True,
            "fold_or_quantile_specific_retuning": False,
        },
        "resource_policy": {
            "one_process_per_logical_cpu": True,
            "numerical_threads_per_process": 1,
            "resource_snapshot_required": True,
        },
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    contract["contract_sha256"] = canonical_sha256(contract)
    contract_path = output / "pricefm_region_frozen_contract.json"
    atomic_write_json(contract_path, contract)
    gates = pd.DataFrame([
        {"gate": "region_in_data", "passed": True, "observed": region},
        {"gate": "three_authority_rows", "passed": len(authority) == 3, "observed": len(authority)},
        {"gate": "three_control_rows", "passed": len(controls) == 3, "observed": len(controls)},
        {"gate": "exact_quantiles", "passed": tuple(contract["quantiles"]) == PAPER_QUANTILES, "observed": len(PAPER_QUANTILES)},
        {"gate": "test_sealed", "passed": not contract["test_opened"] and not contract["test_access_authorized"], "observed": "sealed"},
        {"gate": "mutations_blocked", "passed": all(contract[name] is False for name in (
            "registry_mutation_authorized", "article_mutation_authorized",
            "joint_model_authorized", "mcmc_authorized",
        )), "observed": "blocked"},
        {"gate": "no_launch_yaml", "passed": not list(output.rglob("*.yaml")), "observed": "none_except_frozen_input"},
    ])
    # The frozen input is an evidence copy, not an executable launch document.
    gates.loc[gates.gate.eq("no_launch_yaml"), "passed"] = not list(output.rglob("*launch*.yaml"))
    if not gates.passed.all():
        raise RuntimeError(f"region contract gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_region_frozen_contract_gates.csv", index=False)
    sources = [file_record(Path(__file__), "contract_builder"), *[
        file_record(item["path"], item["role"]) for item in frozen_records
    ]]
    pd.DataFrame(sources).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "region_contract_frozen_not_launched",
        "pipeline_id": args.pipeline_id,
        "target_region": region,
        "contract": str(contract_path),
        "contract_sha256": sha256_file(contract_path),
        "selection_fold": args.selection_fold,
        "real_folds": folds,
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "pricefm_region_frozen_contract.md").write_text(
        f"# PriceFM Region-Frozen Contract: {region}\n\n"
        f"Pipeline `{args.pipeline_id}` freezes one region-level scientific selection unit. "
        "Geometry and tau0 are selected inside Fold-1 training; AL versus exAL is selected "
        "on reserved Fold-1 validation. The winning complete family is then reused unchanged "
        "for all three folds. Test access and all registry/article/joint/MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
