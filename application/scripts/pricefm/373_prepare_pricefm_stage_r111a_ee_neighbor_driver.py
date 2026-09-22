#!/usr/bin/env python3
"""Prepare the bounded R111A FI/LV driver completion and EE replay campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

import pandas as pd
import yaml


STAGE = "R111A"
TAG = "pricefm_stage_r111a_ee_neighbor_driver_20260921"
REGIONS = ("FI", "LV")
FOLDS = (1, 2, 3)
INNER_FOLDS = (1, 2, 3)
READOUTS = ("shared", "block24")
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
HORIZONS = tuple(range(1, 97))

DATA_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CAMPAIGN_ROOT = DATA_ROOT / "campaigns" / TAG
R97_ROOT = DATA_ROOT / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
R110_ROOT = DATA_ROOT / "campaigns/pricefm_stage_r110_direct_driver_20260921"
R110B_ROOT = DATA_ROOT / "authoritative/pricefm_stage_r110_frozen_qdesn_replay_20260921"
R110D_ROOT = DATA_ROOT / "authoritative/pricefm_stage_r110d_focus_failure_atlas_20260921"
R103_ROOT = DATA_ROOT / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
PACKAGE_PATH = DATA_ROOT / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"

SPECS: dict[str, dict[str, Any]] = {
    "FI": {
        "feature_policy": "target_only",
        "feature_dim": 96,
        "depth": 2,
        "units": [96, 96],
        "lag_window": 240,
        "alpha": 0.50,
        "rho": 0.82,
        "input_scale": 0.15,
        "tau0": 1.0e-2,
        "neighbors": [],
        "graph_degree": 0,
    },
    "LV": {
        "feature_policy": "graph_summary_mean",
        "feature_dim": 40,
        "depth": 3,
        "units": [40, 40, 40],
        "lag_window": 96,
        "alpha": 0.35,
        "rho": 0.90,
        "input_scale": 0.20,
        "tau0": 1.0e-2,
        "neighbors": ["EE", "LT"],
        "graph_degree": 1,
    },
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_json(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def data_config_for_region(region: str) -> Path:
    return R97_ROOT / "global_scoring/grid/configs" / region / "test_data.yaml"


def validate_authorization() -> list[Path]:
    summary_path = R110D_ROOT / "summary.json"
    queue_path = R110D_ROOT / "pricefm_stage_r110d_action_queue.csv"
    summary = json.loads(summary_path.read_text())
    queue = pd.read_csv(queue_path)
    row = queue[queue.target.eq("EE")]
    if (
        summary.get("stage") != "R110D"
        or summary.get("status") != "completed_focus_failure_atlas"
        or summary.get("ee_neighbor_driver_completion_authorized") is not True
        or summary.get("broad_all_region_launch_authorized") is not False
        or summary.get("test_opened") is not False
        or len(row) != 1
        or str(row.iloc[0].action) != "complete_active_neighbor_direct_drivers"
        or str(row.iloc[0].regions_to_fit) != "FI|LV"
        or bool(row.iloc[0].authorized) is not True
    ):
        raise RuntimeError("R110D does not authorize the bounded R111A campaign")
    return [summary_path, queue_path]


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
                    "graph_degree": spec["graph_degree"],
                    "neighbor_regions": spec["neighbors"],
                    "max_neighbor_regions": len(spec["neighbors"]),
                },
                "output_dir": str(root / "adapters" / f"region={region}" / f"fold={fold}"),
            },
            "run": {
                "output_dir": str(root / "runs" / f"region={region}" / f"fold={fold}"),
                "nd_predictive": 500,
                "seed": 2026092400 + fold,
                "default_jobs": 1,
            },
            "artifact_hygiene": {
                "enabled": True,
                "preserve_patterns": ["*.csv", "*.json", "*.npz"],
            },
        },
        "pricefm_stage_r111a": {
            "stage": STAGE,
            "role": "ee_neighbor_direct_driver_completion",
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
                    "fold": 1,
                    "inner_fold": inner_fold,
                    "readout": readout,
                    "prior_type": "scaled_ridge",
                    "tau0": "",
                    "dependency": "fold1_train_adapter",
                    "output_dir": str(root / "runs/ridge_selection" / region / readout / f"inner={inner_fold}"),
                })
        for label, tau0 in (("anchor", SPECS[region]["tau0"]), ("quarter", SPECS[region]["tau0"] / 4.0)):
            for inner_fold in INNER_FOLDS:
                rows.append({
                    "task_id": f"rhs__{region}__{label}__inner{inner_fold}",
                    "phase": "rhs_selection",
                    "region": region,
                    "fold": 1,
                    "inner_fold": inner_fold,
                    "readout": "selected_ridge_readout",
                    "prior_type": "rhs_ns",
                    "tau0": f"{tau0:.17g}",
                    "dependency": "ridge_region_selection",
                    "output_dir": str(root / "runs/rhs_selection" / region / label / f"inner={inner_fold}"),
                })
        for fold in FOLDS:
            rows.append({
                "task_id": f"final__{region}__fold{fold}",
                "phase": "outer_validation",
                "region": region,
                "fold": fold,
                "inner_fold": "",
                "readout": "selected_region_readout",
                "prior_type": "selected_region_prior",
                "tau0": "selected_region_tau0",
                "dependency": "final_region_selection",
                "output_dir": str(root / "runs/outer_validation" / region / f"fold={fold}"),
            })
    for fold in FOLDS:
        rows.append({
            "task_id": f"replay__EE__fold{fold}",
            "phase": "ee_all_active_replay",
            "region": "EE",
            "fold": fold,
            "inner_fold": "",
            "readout": "frozen_r103_ee",
            "prior_type": "frozen_r103_family",
            "tau0": "frozen_r103_tau0",
            "dependency": "FI_LV_final_drivers_and_EE_R110_target_driver",
            "output_dir": str(root / "replay/cases/region=EE" / f"fold={fold}"),
        })
    return rows


def prepare(code_root: Path, output_root: Path) -> dict:
    code_root = code_root.resolve()
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    authorization = validate_authorization()
    required = [data_config_for_region(region) for region in REGIONS]
    required.extend(
        R103_ROOT / "cases" / f"r103_ee_f{fold}.json" for fold in FOLDS
    )
    required.extend([R110_ROOT / "summary.json", R110B_ROOT / "summary.json"])
    if not PACKAGE_PATH.is_dir() or any(not path.is_file() for path in required):
        raise FileNotFoundError("R111A frozen source evidence is incomplete")

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
        code_root / "application/scripts/pricefm/373_prepare_pricefm_stage_r111a_ee_neighbor_driver.py",
        code_root / "application/scripts/pricefm/374_run_pricefm_stage_r111a_direct_case.R",
        code_root / "application/scripts/pricefm/375_replay_pricefm_stage_r111a_ee_all_active.py",
        code_root / "application/scripts/pricefm/376_orchestrate_pricefm_stage_r111a_ee_neighbor_driver.py",
        code_root / "application/scripts/pricefm/pricefm_recursive_normal.py",
        code_root / "application/scripts/pricefm/pricefm_recursive_quantile.py",
        code_root / "application/R/pricefm_recursive_normal_fit.R",
        code_root / "application/scripts/pricefm/pricefm_horizon_readout.R",
        PACKAGE_PATH / "R/priors_beta.R",
        PACKAGE_PATH / "R/qdesn_rhs_ns_prior.R",
        *authorization,
        *required,
    ]
    write_csv(output_root / "source_manifest.csv", [
        {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256_file(path)}
        for path in source_paths
    ])

    contract = {
        "stage": STAGE,
        "tag": TAG,
        "status": "prepared_not_launched",
        "code_root": str(code_root),
        "branch": git_value(code_root, "branch", "--show-current"),
        "head": git_value(code_root, "rev-parse", "HEAD"),
        "output_root": str(output_root),
        "fit_regions": list(REGIONS),
        "replay_target": "EE",
        "replay_active_regions": ["EE", "FI", "LV"],
        "folds": list(FOLDS),
        "inner_folds": list(INNER_FOLDS),
        "quantiles": list(QUANTILES),
        "posterior_paths": 500,
        "fit_task_count": 30,
        "replay_case_count": 3,
        "task_count": len(tasks),
        "phase_counts": {
            "ridge_selection": 12,
            "rhs_selection": 12,
            "outer_validation": 6,
            "ee_all_active_replay": 3,
        },
        "rhs_iteration_ceiling_ladder": [750, 1500],
        "final_rhs_iteration_ceiling": 1500,
        "max_workers": 30,
        "scheduler_contract": "one_single_thread_task_per_distinct_idle_physical_core",
        "selection_contract": "fold1_training_inner_folds_only_one_policy_per_region",
        "outer_validation_contract": "frozen_region_policy_scored_on_each_outer_validation_fold",
        "replay_contract": "reuse_EE_R110_target_paths_and_frozen_R103_EE_readout_with_new_FI_LV_paths",
        "path_scale_contract": "each_active_region_path_remains_in_its_own_frozen_processed_response_scale",
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "broad_all_region_launch_authorized": False,
        "specs": SPECS,
        "rhs_shape_contract": "a_tau=(d+1)/2 with d=p-1 because intercept is excluded",
        "authorization_summary_sha256": sha256_file(R110D_ROOT / "summary.json"),
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
