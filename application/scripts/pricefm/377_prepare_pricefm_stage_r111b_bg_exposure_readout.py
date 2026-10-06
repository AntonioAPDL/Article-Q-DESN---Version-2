#!/usr/bin/env python3
"""Prepare the bounded R111B BG recursive-exposure readout campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

import pandas as pd


STAGE = "R111B"
TAG = "pricefm_stage_r111b_bg_exposure_readout_20260922"
REGION = "BG"
FOLDS = (1, 2, 3)
INNER_FOLDS = (1, 2, 3)
ARMS = ("teacher_recent", "recursive_mean", "mixed_equal")
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)

DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CAMPAIGN = DATA / "campaigns" / TAG
R103 = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
R110 = DATA / "campaigns/pricefm_stage_r110_direct_driver_20260921"
R110B = DATA / "authoritative/pricefm_stage_r110_frozen_qdesn_replay_20260921"
R110D = DATA / "authoritative/pricefm_stage_r110d_focus_failure_atlas_20260921"
R111A = DATA / "campaigns/pricefm_stage_r111a_ee_neighbor_driver_20260921"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_hash(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def require_summary(path: Path, stage: str, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if (
        value.get("stage") != stage
        or value.get("status") != status
        or value.get("test_opened") is not False
        or value.get("registry_mutated") is not False
        or value.get("article_mutated") is not False
    ):
        raise RuntimeError(f"invalid frozen {stage} summary: {path}")
    return value


def family_metric_paths() -> list[Path]:
    return [
        DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916/cases"
        / f"region={REGION}" / f"fold={fold}" / "family_validation_metrics.csv"
        for fold in FOLDS
    ]


def selected_bg_family() -> str:
    rows = []
    for fold, path in zip(FOLDS, family_metric_paths()):
        frame = pd.read_csv(path)
        if set(frame.family) != {"al", "exal"} or bool(frame.test_opened.any()):
            raise RuntimeError(f"invalid R103 BG family evidence: {path}")
        rows.append(frame)
    values = pd.concat(rows, ignore_index=True)
    fold_one = values[values.fold.eq(1)].sort_values(
        ["validation_AQL_original", "family"], kind="mergesort"
    )
    if len(fold_one) != 2 or not bool(fold_one.numerically_eligible.all()):
        raise RuntimeError("R103 BG fold-1 family decision is incomplete")
    return str(fold_one.iloc[0].family)


def validate_authority() -> list[Path]:
    r111a_summary = require_summary(
        R111A / "summary.json", "R111A", "completed_ee_neighbor_driver_closeout"
    )
    if (
        r111a_summary.get("all_gates_passed") is not True
        or r111a_summary.get("ee_neighbor_mechanism_resolved") is not True
        or r111a_summary.get("next_stage") != "R111B_BG_exposure_readout_design"
        or r111a_summary.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("R111A does not authorize the bounded R111B design")
    r110_summary = require_summary(
        R110 / "summary.json", "R110", "completed_direct_driver_closeout"
    )
    r110b_summary = require_summary(
        R110B / "summary.json", "R110B", "completed_frozen_qdesn_replay_closeout"
    )
    r110d_summary = require_summary(
        R110D / "summary.json", "R110D", "completed_focus_failure_atlas"
    )
    queue_path = R110D / "pricefm_stage_r110d_action_queue.csv"
    queue = pd.read_csv(queue_path)
    row = queue[queue.target.eq(REGION)]
    if (
        len(row) != 1
        or row.iloc[0].action != "design_exposure_aligned_readout_screen"
        or row.iloc[0].reuse != "R110_target_paths_and_frozen_BG_reservoir_geometry"
        or r110d_summary.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("R110D BG mechanism contract changed")
    if selected_bg_family() != "al":
        raise RuntimeError("R111B requires the frozen BG AL family decision")
    selection = pd.read_csv(R110 / "final_region_selection.csv")
    row = selection[selection.region.eq(REGION)]
    if (
        len(row) != 1
        or row.iloc[0].readout != "block24"
        or row.iloc[0].prior_type != "rhs_ns"
        or abs(float(row.iloc[0].tau0) - 2.5e-5) > 1e-15
    ):
        raise RuntimeError("frozen BG normal-driver policy changed")
    return [
        R111A / "summary.json",
        R110 / "summary.json",
        R110B / "summary.json",
        R110D / "summary.json",
        queue_path,
        R110 / "final_region_selection.csv",
        *family_metric_paths(),
    ]


def task_contract(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["task_contract_sha256"] = canonical_hash(result)
    return result


def conceptual_tasks(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for fold in FOLDS:
        for inner in INNER_FOLDS:
            rows.append({
                "task_id": f"driver__BG__fold{fold}__inner{inner}",
                "phase": "crossfit_normal_driver", "outer_fold": fold,
                "inner_fold": inner, "arm": "", "tau": "",
                "dependency": "frozen_r110_BG_driver_policy",
                "output_dir": str(root / "runs/drivers" / f"fold={fold}" / f"inner={inner}"),
            })
            rows.append({
                "task_id": f"design__BG__fold{fold}__inner{inner}",
                "phase": "crossfit_exposure_design", "outer_fold": fold,
                "inner_fold": inner, "arm": "", "tau": "",
                "dependency": f"driver__BG__fold{fold}__inner{inner}",
                "output_dir": str(root / "runs/designs" / f"fold={fold}" / f"inner={inner}"),
            })
    for arm in ARMS:
        for holdout in INNER_FOLDS:
            rows.append({
                "task_id": f"screen__{arm}__holdout{holdout}",
                "phase": "median_arm_screen", "outer_fold": 1,
                "inner_fold": holdout, "arm": arm, "tau": 0.5,
                "dependency": "fold1_crossfit_exposure_designs",
                "output_dir": str(root / "runs/screen" / arm / f"holdout={holdout}"),
            })
    for fold in FOLDS:
        for tau in QUANTILES:
            label = str(tau).replace(".", "p")
            rows.append({
                "task_id": f"final__BG__fold{fold}__tau{label}",
                "phase": "final_al_readout", "outer_fold": fold,
                "inner_fold": "", "arm": "selected_fold1_training_arm", "tau": tau,
                "dependency": "frozen_fold1_training_arm",
                "output_dir": str(root / "runs/final" / f"fold={fold}" / f"tau={label}"),
            })
        rows.append({
            "task_id": f"replay__BG__fold{fold}",
            "phase": "outer_validation_replay", "outer_fold": fold,
            "inner_fold": "", "arm": "selected_fold1_training_arm", "tau": "",
            "dependency": f"seven_final_AL_readouts_and_R110_driver_fold{fold}",
            "output_dir": str(root / "replay" / f"fold={fold}"),
        })
    return rows


def prepare(code_root: Path, output_root: Path) -> dict[str, Any]:
    code_root = code_root.resolve()
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    evidence = validate_authority()
    case_configs = [R103 / "cases" / f"r103_bg_f{fold}.json" for fold in FOLDS]
    adapters = [R110 / "adapters" / "region=BG" / f"fold={fold}" for fold in FOLDS]
    outer_drivers = [R110 / "runs/outer_validation/BG" / f"fold={fold}" for fold in FOLDS]
    required = [*case_configs, *evidence]
    required.extend(path / "adapter_manifest.json" for path in adapters)
    required.extend(path / "terminal.json" for path in outer_drivers)
    if any(not path.is_file() for path in required):
        missing = [str(path) for path in required if not path.is_file()]
        raise FileNotFoundError("R111B frozen evidence is incomplete: " + ", ".join(missing))

    driver_rows = []
    design_rows = []
    for fold in FOLDS:
        r103_config = json.loads(case_configs[fold - 1].read_text())
        spec = json.loads(r103_config["spec_json"])
        if (
            spec.get("region") != REGION
            or spec.get("active_regions") != [REGION]
            or float(spec.get("tau0")) != 1e-4
            or list(spec.get("units")) != [40, 40, 40]
            or int(spec.get("lag_window")) != 240
        ):
            raise RuntimeError(f"frozen BG Q-DESN specification changed in fold {fold}")
        for inner in INNER_FOLDS:
            driver = task_contract({
                "stage": STAGE,
                "task_id": f"driver__BG__fold{fold}__inner{inner}",
                "phase": "crossfit_normal_driver",
                "region": REGION,
                "outer_fold": fold,
                "inner_fold": inner,
                "adapter_dir": str(adapters[fold - 1]),
                "output_dir": str(output_root / "runs/drivers" / f"fold={fold}" / f"inner={inner}"),
                "readout": "block24",
                "prior_type": "rhs_ns",
                "tau0": 2.5e-5,
                "max_iter": 1500,
                "min_iter": 50,
                "tol": 1e-5,
                "n_paths": 500,
                "seed": 2026092700 + 10 * fold + inner,
                "selection_split": "outer_fold_training_inner_only",
                "test_access_authorized": False,
                "helper_path": str(code_root / "application/R/pricefm_recursive_normal_fit.R"),
                "horizon_helper_path": str(code_root / "application/scripts/pricefm/pricefm_horizon_readout.R"),
                "package_path": str(DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
            })
            driver_path = output_root / "contracts/drivers" / f"{driver['task_id']}.json"
            write_json(driver_path, driver)
            driver_rows.append({
                "task_id": driver["task_id"], "outer_fold": fold, "inner_fold": inner,
                "contract_path": str(driver_path), "contract_sha256": sha256_file(driver_path),
                "output_dir": driver["output_dir"], "test_access_authorized": False,
            })
            design = task_contract({
                "stage": STAGE,
                "task_id": f"design__BG__fold{fold}__inner{inner}",
                "phase": "crossfit_exposure_design",
                "region": REGION,
                "outer_fold": fold,
                "inner_fold": inner,
                "r103_case_config": str(case_configs[fold - 1]),
                "driver_dir": driver["output_dir"],
                "output_dir": str(output_root / "runs/designs" / f"fold={fold}" / f"inner={inner}"),
                "posterior_paths": 500,
                "recursive_reduction": "pathwise_design_mean",
                "selection_split": "outer_fold_training_crossfit_block_only",
                "test_access_authorized": False,
            })
            design_path = output_root / "contracts/designs" / f"{design['task_id']}.json"
            write_json(design_path, design)
            design_rows.append({
                "task_id": design["task_id"], "outer_fold": fold, "inner_fold": inner,
                "contract_path": str(design_path), "contract_sha256": sha256_file(design_path),
                "output_dir": design["output_dir"], "test_access_authorized": False,
            })

    write_csv(output_root / "driver_task_manifest.csv", driver_rows)
    write_csv(output_root / "design_task_manifest.csv", design_rows)
    tasks = conceptual_tasks(output_root)
    write_csv(output_root / "conceptual_task_manifest.csv", tasks)

    sources = [
        code_root / "application/scripts/pricefm/377_prepare_pricefm_stage_r111b_bg_exposure_readout.py",
        code_root / "application/scripts/pricefm/378_run_pricefm_stage_r111b_crossfit_driver.R",
        code_root / "application/scripts/pricefm/379_build_pricefm_stage_r111b_exposure_design.py",
        code_root / "application/scripts/pricefm/380_run_pricefm_stage_r111b_al_readout.R",
        code_root / "application/scripts/pricefm/381_replay_closeout_pricefm_stage_r111b.py",
        code_root / "application/scripts/pricefm/382_orchestrate_pricefm_stage_r111b_bg_exposure_readout.py",
        code_root / "application/scripts/pricefm/pricefm_recursive_quantile.py",
        code_root / "application/scripts/pricefm/pricefm_recursive_driver_diagnostics.py",
        code_root / "application/scripts/pricefm/345_run_pricefm_stage_r103_quantile_case.py",
        code_root / "application/scripts/pricefm/350_audit_pricefm_stage_r104_forecast_operator.py",
        code_root / "application/R/pricefm_recursive_normal_fit.R",
        code_root / "application/scripts/pricefm/pricefm_horizon_readout.R",
        *required,
    ]
    write_csv(output_root / "source_manifest.csv", [
        {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256_file(path)}
        for path in sources
    ])
    contract = {
        "stage": STAGE,
        "tag": TAG,
        "status": "prepared_not_launched",
        "code_root": str(code_root),
        "branch": git_value(code_root, "branch", "--show-current"),
        "head": git_value(code_root, "rev-parse", "HEAD"),
        "output_root": str(output_root),
        "region": REGION,
        "folds": list(FOLDS),
        "inner_folds": list(INNER_FOLDS),
        "arms": list(ARMS),
        "quantiles": list(QUANTILES),
        "selected_family": "al",
        "qdesn_tau0": 1e-4,
        "normal_driver_policy": {"readout": "block24", "prior_type": "rhs_ns", "tau0": 2.5e-5},
        "posterior_paths": 500,
        "crossfit_driver_tasks": 9,
        "exposure_design_tasks": 9,
        "median_screen_tasks": 9,
        "final_quantile_tasks": 21,
        "replay_tasks": 3,
        "model_fit_tasks": 39,
        "task_count": len(tasks),
        "max_workers": 30,
        "scheduler_contract": "one_single_thread_task_per_distinct_idle_physical_core",
        "family_selection_contract": "R103_fold1_validation_only_region_frozen_AL",
        "selection_contract": "three_leave_one_crossfit_blocks_inside_fold1_training_median_AL_only_neutral_initialization",
        "final_fit_contract": "selected_arm_frozen_then_fit_seven_AL_quantiles_on_three_crossfit_blocks_per_outer_fold",
        "evaluation_contract": "R110_500_path_BG_driver_on_outer_validation_only",
        "initialization_contract": "matching_R103_AL_posterior_is_initialization_only_and_never_prior_center",
        "prior_contract": "zero_centered_rhs_ns_fixed_tau0_1e-4_all_arms_folds_quantiles",
        "broad_all_region_launch_authorized": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "source_manifest_sha256": sha256_file(output_root / "source_manifest.csv"),
    }
    contract["contract_sha256"] = canonical_hash(contract)
    write_json(output_root / "campaign_contract.json", contract)
    return contract


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-root", type=Path, default=CAMPAIGN)
    args = parser.parse_args()
    print(json.dumps(prepare(args.code_root, args.output_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
