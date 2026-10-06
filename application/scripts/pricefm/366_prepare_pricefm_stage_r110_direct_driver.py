#!/usr/bin/env python3
"""Prepare the bounded PriceFM R110 direct-driver campaign without fitting."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path

import yaml


STAGE = "R110"
TAG = "pricefm_stage_r110_direct_driver_20260921"
REGIONS = ("BG", "EE", "BE")
FOLDS = (1, 2, 3)
INNER_FOLDS = (1, 2, 3)
READOUTS = ("shared", "block24")
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
HORIZONS = tuple(range(1, 97))

OLD_DATA_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CAMPAIGN_ROOT = OLD_DATA_ROOT / "campaigns" / TAG
R97_ROOT = OLD_DATA_ROOT / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
PACKAGE_PATH = OLD_DATA_ROOT / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"

SPECS = {
    "BG": {
        "feature_policy": "target_only",
        "feature_dim": 40,
        "depth": 3,
        "units": [40, 40, 40],
        "lag_window": 240,
        "alpha": 0.25,
        "rho": 0.82,
        "input_scale": 0.35,
        "tau0": 1.0e-4,
        "neighbors": [],
    },
    "EE": {
        "feature_policy": "graph_summary_mean",
        "feature_dim": 64,
        "depth": 3,
        "units": [64, 64, 64],
        "lag_window": 168,
        "alpha": 0.35,
        "rho": 0.90,
        "input_scale": 0.15,
        "tau0": 1.0e-4,
        "neighbors": ["FI", "LV"],
    },
    "BE": {
        "feature_policy": "graph_summary_mean",
        "feature_dim": 48,
        "depth": 2,
        "units": [48, 48],
        "lag_window": 168,
        "alpha": 0.40,
        "rho": 0.95,
        "input_scale": 0.25,
        "tau0": 2.0e-3,
        "neighbors": ["DE_LU", "FR", "NL"],
    },
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_json(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0]) if rows else []
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def data_config_for_region(region: str) -> Path:
    return R97_ROOT / "global_scoring" / "grid" / "configs" / region / "test_data.yaml"


def adapter_config(root: Path, region: str, fold: int) -> dict:
    spec = SPECS[region]
    return {
        "pricefm_desn_smoke": {
            "data_config": str(data_config_for_region(region)),
            "package_path": str(PACKAGE_PATH),
            "region": region,
            "fold": fold,
            "splits": ["train", "val"],
            "horizons": list(HORIZONS),
            "quantiles": list(QUANTILES),
            "feature_policy": spec["feature_policy"],
            "adapter": {
                "output_root": str(root / "runs"),
                "feature_map": "window_reservoir_v1",
                "feature_dim": spec["feature_dim"],
                "seed": 2026090601,
                "include_intercept": True,
                "keep_matrices_after_success": True,
                "row_chunk_size": 1024,
                "projection_scale": 1.0,
                "depth": spec["depth"],
                "units": spec["units"],
                "alpha": spec["alpha"],
                "rho": spec["rho"],
                "input_scale": spec["input_scale"],
                "recurrent_sparsity": 0.05,
                "reservoir_activation": "tanh",
                "state_output": "final_layer",
                "spatial": {
                    "graph_degree": 1,
                    "neighbor_regions": spec["neighbors"],
                    "max_neighbor_regions": len(spec["neighbors"]),
                },
                "output_dir": str(root / "adapters" / f"region={region}" / f"fold={fold}"),
            },
            "run": {
                "output_dir": str(root / "runs" / f"region={region}" / f"fold={fold}"),
                "nd_predictive": 500,
                "seed": 2026092100 + fold,
                "default_jobs": 1,
            },
            "artifact_hygiene": {"enabled": True, "preserve_patterns": ["*.csv", "*.json", "*.npz"]},
        },
        "pricefm_stage_r110": {
            "stage": STAGE,
            "role": "train_validation_only_direct_driver",
            "selection_scope": "one_policy_per_region_shared_across_outer_folds",
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        },
    }


def conceptual_tasks(root: Path) -> list[dict]:
    rows: list[dict] = []
    for region in REGIONS:
        for readout in READOUTS:
            for inner_fold in INNER_FOLDS:
                rows.append({
                    "task_id": f"ridge__{region}__{readout}__inner{inner_fold}",
                    "phase": "ridge_selection",
                    "region": region,
                    "outer_fold": 1,
                    "inner_fold": inner_fold,
                    "readout": readout,
                    "prior_type": "scaled_ridge",
                    "tau0": "",
                    "dependency": "adapter_fold1",
                    "output_dir": str(root / "runs/ridge_selection" / region / readout / f"inner={inner_fold}"),
                })
        for tau_label, tau0 in (("anchor", SPECS[region]["tau0"]), ("quarter", SPECS[region]["tau0"] / 4.0)):
            for inner_fold in INNER_FOLDS:
                rows.append({
                    "task_id": f"rhs__{region}__{tau_label}__inner{inner_fold}",
                    "phase": "rhs_selection",
                    "region": region,
                    "outer_fold": 1,
                    "inner_fold": inner_fold,
                    "readout": "selected_ridge_readout",
                    "prior_type": "rhs_ns",
                    "tau0": f"{tau0:.17g}",
                    "dependency": "ridge_region_selection",
                    "output_dir": str(root / "runs/rhs_selection" / region / tau_label / f"inner={inner_fold}"),
                })
        for fold in FOLDS:
            rows.append({
                "task_id": f"final__{region}__fold{fold}",
                "phase": "outer_validation",
                "region": region,
                "outer_fold": fold,
                "inner_fold": "",
                "readout": "selected_region_readout",
                "prior_type": "selected_region_prior",
                "tau0": "selected_region_tau0",
                "dependency": "final_region_selection",
                "output_dir": str(root / "runs/outer_validation" / region / f"fold={fold}"),
            })
    return rows


def prepare(code_root: Path, output_root: Path) -> dict:
    code_root = code_root.resolve()
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    if any(not data_config_for_region(region).is_file() for region in REGIONS) or not PACKAGE_PATH.is_dir():
        raise FileNotFoundError("Frozen R97 data or exdqlm runtime is unavailable")

    config_rows = []
    for region in REGIONS:
        for fold in FOLDS:
            path = output_root / "configs" / region / f"fold_{fold}.yaml"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(adapter_config(output_root, region, fold), sort_keys=False))
            config_rows.append({
                "region": region,
                "fold": fold,
                "config_path": str(path),
                "config_sha256": sha256_file(path),
                "adapter_dir": str(output_root / "adapters" / f"region={region}" / f"fold={fold}"),
                "selection_split": "train_inner_only" if fold == 1 else "outer_validation_transfer_only",
                "test_access_authorized": False,
            })

    tasks = conceptual_tasks(output_root)
    write_csv(output_root / "adapter_manifest.csv", config_rows)
    write_csv(output_root / "conceptual_task_manifest.csv", tasks)
    source_paths = [
        code_root / "application/scripts/pricefm/366_prepare_pricefm_stage_r110_direct_driver.py",
        code_root / "application/scripts/pricefm/367_run_pricefm_stage_r110_direct_case.R",
        code_root / "application/scripts/pricefm/368_orchestrate_pricefm_stage_r110_direct_driver.py",
        code_root / "application/scripts/pricefm/369_closeout_pricefm_stage_r110_direct_driver.py",
        code_root / "application/scripts/pricefm/pricefm_desn_adapter.py",
        code_root / "application/scripts/pricefm/pricefm_horizon_readout.R",
        code_root / "application/R/pricefm_recursive_normal_fit.R",
        PACKAGE_PATH / "R/priors_beta.R",
        PACKAGE_PATH / "R/qdesn_rhs_ns_prior.R",
        *(data_config_for_region(region) for region in REGIONS),
    ]
    sources = [{"path": str(path), "sha256": sha256_file(path)} for path in source_paths]
    write_csv(output_root / "source_manifest.csv", sources)

    contract = {
        "stage": STAGE,
        "tag": TAG,
        "status": "prepared_not_launched",
        "code_root": str(code_root),
        "branch": git_value(code_root, "branch", "--show-current"),
        "head": git_value(code_root, "rev-parse", "HEAD"),
        "output_root": str(output_root),
        "regions": list(REGIONS),
        "folds": list(FOLDS),
        "inner_folds": list(INNER_FOLDS),
        "quantiles": list(QUANTILES),
        "posterior_paths": 500,
        "task_count": len(tasks),
        "phase_counts": {
            "ridge_selection": 18,
            "rhs_selection": 18,
            "outer_validation": 9,
        },
        "max_workers": 30,
        "scheduler_contract": "one_single_thread_task_per_distinct_physical_core",
        "selection_contract": "fold1_training_inner_folds_only_one_policy_per_region",
        "outer_validation_contract": "frozen_region_policy_scored_on_each_outer_validation_fold",
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "specs": SPECS,
        "rhs_shape_contract": "a_tau=(d+1)/2 with d=p-1 because intercept is excluded",
        "source_manifest_sha256": sha256_file(output_root / "source_manifest.csv"),
    }
    contract["contract_sha256"] = sha256_json(contract)
    write_json(output_root / "campaign_contract.json", contract)
    return contract


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-root", type=Path, default=CAMPAIGN_ROOT)
    args = parser.parse_args()
    print(json.dumps(prepare(args.code_root, args.output_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
