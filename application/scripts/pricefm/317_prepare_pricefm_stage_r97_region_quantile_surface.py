#!/usr/bin/env python3
"""Materialize one launch-grade R97 all-fold AL/exAL validation surface."""

from __future__ import annotations

import argparse
import copy
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
    content_task_id,
    file_record,
    git_identity,
    prepare_empty_directory,
    sha256_file,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
SOURCE_DATA = Path(__file__).resolve().parents[2] / "config/pricefm_data_pipeline.yaml"
NORMAL_PACKAGE = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
R94_LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
R94_MANIFEST = R94_LIBRARY / "pricefm_stage_r94_coherent_exal_init_manifest.json"
RUNNER = Path(__file__).with_name("308_run_pricefm_stage_r95_quantile_atom.R")
NORMAL_RUNNER = Path(__file__).with_name("10_run_desn_model_full.py")
LAUNCHER = Path(__file__).with_name("315_launch_pricefm_region_frozen_allfold.py")
FOLDS = (1, 2, 3)
WARM_ORDER = (0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90)
WARM_PARENT = {
    0.50: "normal_rhs", 0.45: "al_0.50", 0.25: "al_0.45",
    0.10: "al_0.25", 0.55: "al_0.50", 0.75: "al_0.55", 0.90: "al_0.75",
}
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)
EXPECTED_REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--selected-normal-contract", type=Path, required=True)
    value.add_argument("--source-data-config", type=Path, default=SOURCE_DATA)
    value.add_argument("--normal-package", type=Path, default=NORMAL_PACKAGE)
    value.add_argument("--r-library", type=Path, default=R94_LIBRARY)
    value.add_argument("--runtime-manifest", type=Path, default=R94_MANIFEST)
    value.add_argument("--processed-dir", type=Path, required=True)
    value.add_argument("--grid-dir", type=Path, required=True)
    value.add_argument("--run-dir", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--workers", type=int, default=1)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def parse_units(value: Any) -> list[int]:
    values = json.loads(value) if isinstance(value, str) else value
    result = [int(item) for item in values]
    if not result or any(item <= 0 for item in result):
        raise RuntimeError("selected DESN units are invalid")
    return result


def write_yaml(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(yaml.safe_dump(payload, sort_keys=False))
    temporary.replace(path)


def no_test_keys(value: Any) -> bool:
    if isinstance(value, dict):
        return all("test" not in str(key).lower() and no_test_keys(item) for key, item in value.items())
    if isinstance(value, (list, tuple)):
        return all(no_test_keys(item) for item in value)
    return True


def data_config(source: dict[str, Any], processed: Path, lag_window: int, region: str) -> dict[str, Any]:
    payload = copy.deepcopy(source)
    spec = payload["pricefm"]
    for name in ("raw_dir", "interim_dir", "external_repo_dir", "log_dir"):
        path = Path(spec[name])
        if not path.is_absolute():
            spec[name] = str((ARTIFACT_REPO / path).resolve())
    spec["processed_dir"] = str(processed.resolve())
    spec["allow_absolute_local_paths"] = True
    by_fold = {int(item["fold"]): item for item in spec["splits"]}
    spec["splits"] = [
        {"fold": fold, "train": list(by_fold[fold]["train"]), "val": list(by_fold[fold]["val"])}
        for fold in FOLDS
    ]
    spec["windows"]["lag_window"] = int(lag_window)
    spec["pilot"] = {"enabled": True, "region": region, "fold": 1}
    if not no_test_keys(spec["splits"]):
        raise RuntimeError("R97 validation data configuration exposes test data")
    return payload


def graph_fields(region: str, regions: list[str], policy: str) -> tuple[list[str], dict[str, Any]]:
    if policy == "target_only":
        return [], {"graph_degree": 1, "neighbor_regions": [], "max_neighbor_regions": 0}
    graph = graph_scope_manifest_for_policy(region, regions, policy, spatial={"graph_degree": 1})
    neighbors = [str(value) for value in graph["neighbor_regions"]]
    return neighbors, {
        "graph_degree": 1,
        "neighbor_regions": neighbors,
        "max_neighbor_regions": len(neighbors),
    }


def full_config(
    source_data: Path, run_dir: Path, normal_package: Path, contract: dict[str, Any],
    regions: list[str],
) -> dict[str, Any]:
    region = str(contract["region"])
    units = parse_units(contract["units"])
    policy = str(contract["feature_policy"])
    neighbors, spatial = graph_fields(region, regions, policy)
    return {
        "pricefm_desn_full": {
            "data_config": str(source_data.resolve()),
            "package_path": str(normal_package.resolve()),
            "rscript_bin": str(RSCRIPT),
            "python_bin": str(PYTHON),
            "scope": {
                "regions": [region], "folds": list(FOLDS), "splits": ["train", "val"],
                "horizons": "all", "quantiles": list(PAPER_QUANTILES),
                "feature_policy": policy,
            },
            "adapter": {
                "output_root": str((run_dir / "normal/cells").resolve()),
                "feature_map": "window_reservoir_v1", "feature_dim": units[-1],
                "seed": int(contract["seed"]), "include_intercept": True,
                "keep_matrices_after_success": True, "row_chunk_size": 512,
                "projection_scale": 1.0, "depth": int(contract["depth"]),
                "units": units, "alpha": float(contract["alpha"]),
                "rho": float(contract["rho"]), "input_scale": float(contract["input_scale"]),
                "recurrent_sparsity": 0.05, "reservoir_activation": "tanh",
                "state_output": str(contract["state_output"]), "spatial": spatial,
            },
            "run": {
                "output_dir": str((run_dir / "normal").resolve()),
                "nd_predictive": 400, "seed": int(contract["seed"]), "default_jobs": 1,
            },
            "rhs_ns": {
                "tau0": float(contract["tau0"]), "init_tau": 1.0,
                "shrink_intercept": False, "freeze_tau_iters": 5,
                "freeze_tau_warmup_iters": 5,
            },
            "warm_start": {"enabled": False},
            "normal": {
                "enabled": True, "prior_types": ["rhs_ns"],
                "predictive_quantile_mode": "analytic_normal",
                "omega_prior": {"a": 2.0, "b": 1.0},
                "vb_control": {"max_iter": 500, "min_iter": 50, "tol": 1e-5, "verbose": False},
            },
            "qdesn_vb": {"enabled": False, "likelihoods": ["al", "exal"]},
            "exact_equivalence": {"enabled": False},
            "training": {"train_origin_limit": 3000, "train_origin_selection": "tail"},
            "artifact_hygiene": {
                "enabled": True, "clean_adapter_patterns": [],
                "clean_model_patterns": ["*.rds", "*.rda", "*.RData", "*.rdata"],
                "preserve_patterns": ["*.csv", "*.json", "*.log", "*.md", "*.npz"],
            },
            "nested_validation": {"enabled": False},
            "comparison_metadata": {
                "stage": "pricefm_stage_r97_region_quantile_validation",
                "selection_rule": "one_DESN_tau0_per_region_then_whole_family_on_fold1_validation",
                "selection_is_validation_only": True,
                "test_metrics_role": "not_loaded_not_predicted_not_selected",
                "test_access_authorized": False,
            },
            "pricefm_stage_r97": {"active_window_regions": [region, *neighbors]},
        }
    }


def task_id(pipeline_hash: str, region: str, fold: int, family: str, tau: float | None) -> str:
    identity = {
        "pipeline_contract_sha256": pipeline_hash, "region": region, "fold": fold,
        "family": family, "tau": tau,
    }
    token = "na" if tau is None else f"{tau:.2f}".replace(".", "p")
    return content_task_id(f"r97_{region}_f{fold}_{family}_{token}", identity)


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= int(args.workers) <= 20:
        raise RuntimeError("R97 region surface permits 1--20 one-core workers")
    for path in (args.selected_normal_contract, args.source_data_config, args.runtime_manifest, RUNNER, NORMAL_RUNNER, LAUNCHER):
        if not path.is_file():
            raise FileNotFoundError(path)
    if not args.normal_package.is_dir() or not args.r_library.is_dir():
        raise FileNotFoundError("R97 model runtime is absent")
    runtime = json.loads(args.runtime_manifest.read_text())
    if runtime.get("version") != "1.1.1.9005" or runtime.get("repair") != EXPECTED_REPAIR:
        raise RuntimeError("R97 requires the hash-pinned coherent exAL runtime")
    contract = json.loads(args.selected_normal_contract.read_text())
    required = {
        "region", "feature_policy", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "state_output", "seed", "tau0",
    }
    missing = sorted(required - set(contract))
    if missing or contract.get("test_access_authorized") is not False:
        raise RuntimeError(f"selected normal contract is incomplete or unsealed: {missing}")
    code_root = args.code_root.resolve()
    git = git_identity(code_root)
    if not git.clean or git.head != git.upstream_head or not git.branch.startswith("work/pricefm-"):
        raise RuntimeError("R97 materialization requires a clean synchronized PriceFM task branch")

    grid, quarantined_grid = prepare_empty_directory(
        args.grid_dir, quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_region_grid", allow_quarantine=args.quarantine_existing,
    )
    output, quarantined_output = prepare_empty_directory(
        args.output_dir, quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_region_prep", allow_quarantine=args.quarantine_existing,
    )
    args.run_dir.mkdir(parents=True, exist_ok=True)
    source = yaml.safe_load(args.source_data_config.read_text())
    regions = [str(value) for value in source["pricefm"]["regions"]]
    region = str(contract["region"])
    if region not in regions:
        raise RuntimeError("selected region is absent from the PriceFM data contract")
    configs = grid / "configs"
    tasks_dir = grid / "tasks"
    configs.mkdir()
    tasks_dir.mkdir()
    data_path = configs / "train_validation_data.yaml"
    write_yaml(data_path, data_config(source, args.processed_dir, int(contract["lag_window"]), region))
    full_path = configs / "normal_rhs_full.yaml"
    full = full_config(data_path, args.run_dir, args.normal_package, contract, regions)
    write_yaml(full_path, full)
    active_regions = full["pricefm_desn_full"]["pricefm_stage_r97"]["active_window_regions"]

    pipeline = {
        "schema_version": 1, "stage": "R97", "region": region,
        "selection_fold": 1, "fit_folds": list(FOLDS),
        "quantiles": list(PAPER_QUANTILES), "warm_order": list(WARM_ORDER),
        "selected_normal_contract": file_record(args.selected_normal_contract, "validation_selected_DESN_tau0"),
        "source_data_config": file_record(args.source_data_config, "PriceFM_data_contract"),
        "generated_data_config": file_record(data_path, "R97_train_validation_data"),
        "normal_full_config": file_record(full_path, "R97_normal_RHS_config"),
        "normal_package": str(args.normal_package.resolve()),
        "r_library": str(args.r_library.resolve()),
        "runtime_manifest": file_record(args.runtime_manifest, "coherent_exAL_runtime"),
        "runner": file_record(RUNNER, "repaired_quantile_atom_runner"),
        "launcher": file_record(LAUNCHER, "dependency_launcher"),
        "frozen_desn": {key: contract[key] for key in (
            "feature_policy", "lag_window", "depth", "units", "alpha", "rho",
            "input_scale", "state_output", "seed",
        )},
        "rhs_tau0": float(contract["tau0"]),
        "active_window_regions": active_regions,
        "processed_dir": str(args.processed_dir.resolve()),
        "run_dir": str(args.run_dir.resolve()),
        "family_selection_rule": "minimum_fold1_validation_AQL_among_complete_numerically_eligible_AL_and_exAL_surfaces",
        "whole_region_numerical_fallback": "AL_if_any_selected_exAL_fold_atom_is_ineligible",
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    pipeline_hash = canonical_sha256(pipeline)
    pipeline["pipeline_contract_sha256"] = pipeline_hash

    rhs = {
        "tau0": float(contract["tau0"]), "init_tau": 1.0,
        "shrink_intercept": False, "freeze_tau_iters": 50, "freeze_tau_warmup_iters": 50,
    }
    qcfg = {
        "max_iter": 200, "tol": 1e-4, "n_samp": 200, "n_samp_xi": 200,
        "prior_sigma": {"a": 1.0, "b": 1.0}, "prior_gamma": {"mu0": 0.0, "s20": 10.0},
        "structured_sigmagam": {
            "factorization": "structured", "structured_grid_size": 151,
            "structured_span_sd": 6.0, "freeze_warmup_iters": 0,
            "force_after_warmup": True, "postwarmup_damping": 0.2,
            "postwarmup_damping_iters": 30, "min_postwarmup_updates": 35,
        },
    }
    rows: list[dict[str, Any]] = []
    outputs: dict[str, str] = {}
    for fold in FOLDS:
        normal_id = task_id(pipeline_hash, region, fold, "normal_rhs", None)
        normal_output = args.run_dir / f"region={region}" / f"fold={fold}" / "tasks" / normal_id
        normal = {
            "schema_version": 1, "stage": "R95", "task_id": normal_id,
            "region": region, "fold": fold, "likelihood_family": "normal_rhs", "tau": None,
            "parent_task_ids": [], "pipeline_contract_sha256": pipeline_hash,
            "selection_split": "val", "launch_authorized": False, "test_opened": False,
            **{name: False for name in BLOCKED},
            "output_dir": str(normal_output.resolve()), "runner_type": "normal_full",
            "normal_full_config": str(full_path.resolve()),
            "normal_full_config_sha256": sha256_file(full_path),
            "normal_model_dir": str((args.run_dir / "normal/cells" / f"region={region}" / f"fold={fold}" / "model").resolve()),
            "adapter_dir": str((args.run_dir / "normal/cells" / f"region={region}" / f"fold={fold}" / "adapter").resolve()),
        }
        rows.append(normal)
        outputs[normal_id] = normal["output_dir"]
        labels = {"normal_rhs": normal_id}
        for order, tau in enumerate(WARM_ORDER, start=1):
            parent_id = labels[WARM_PARENT[tau]]
            al_id = task_id(pipeline_hash, region, fold, "al", tau)
            al_output = args.run_dir / f"region={region}" / f"fold={fold}" / "tasks" / al_id
            al = {
                "schema_version": 1, "stage": "R95", "task_id": al_id,
                "region": region, "fold": fold, "likelihood_family": "al", "tau": tau,
                "parent_task_ids": [parent_id], "pipeline_contract_sha256": pipeline_hash,
                "selection_split": "val", "launch_authorized": False, "test_opened": False,
                **{name: False for name in BLOCKED},
                "output_dir": str(al_output.resolve()), "runner_type": "quantile_atom",
                "normal_task_id": normal_id, "normal_task_output": normal["output_dir"],
                "adapter_dir": normal["adapter_dir"], "parent_task_output": outputs[parent_id],
                "method_id": "qdesn_al_rhs_ns_r97_region_frozen",
                "warm_start_mode": "normal_or_adjacent_al_mean_scale",
                "seed": int(contract["seed"]) + fold * 1000 + order * 10,
            }
            rows.append(al)
            outputs[al_id] = al["output_dir"]
            labels[f"al_{tau:.2f}"] = al_id
            exal_id = task_id(pipeline_hash, region, fold, "exal", tau)
            exal_output = args.run_dir / f"region={region}" / f"fold={fold}" / "tasks" / exal_id
            exal = {
                "schema_version": 1, "stage": "R95", "task_id": exal_id,
                "region": region, "fold": fold, "likelihood_family": "exal", "tau": tau,
                "parent_task_ids": [al_id], "pipeline_contract_sha256": pipeline_hash,
                "selection_split": "val", "launch_authorized": False, "test_opened": False,
                **{name: False for name in BLOCKED},
                "output_dir": str(exal_output.resolve()), "runner_type": "quantile_atom",
                "normal_task_id": normal_id, "normal_task_output": normal["output_dir"],
                "adapter_dir": normal["adapter_dir"], "parent_task_output": al["output_dir"],
                "method_id": "qdesn_exal_rhs_ns_r97_region_frozen",
                "warm_start_mode": "al_qbeta_rhs_latent_first",
                "seed": int(contract["seed"]) + fold * 1000 + order * 10 + 1,
            }
            rows.append(exal)
            outputs[exal_id] = exal["output_dir"]

    manifest_rows = []
    adapters = [
        code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        code_root / "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R",
        code_root / "application/scripts/pricefm/pricefm_stage_r75_large_n_gig_adapter.R",
    ]
    adapter_records = [file_record(path, "public_API_adapter") for path in adapters]
    for task in rows:
        task.update({
            "data_config": str(data_path.resolve()), "data_config_sha256": sha256_file(data_path),
            "r_library": str(args.r_library.resolve()),
            "runtime_manifest": str(args.runtime_manifest.resolve()),
            "runtime_manifest_sha256": sha256_file(args.runtime_manifest),
            "adapter_scripts": adapter_records,
            "runner_script": str((RUNNER if task["runner_type"] == "quantile_atom" else NORMAL_RUNNER).resolve()),
            "rhs": rhs, "qdesn_vb": qcfg, "frozen_desn": pipeline["frozen_desn"],
        })
        task["runner_script_sha256"] = sha256_file(task["runner_script"])
        path = tasks_dir / f"{task['task_id']}.json"
        atomic_write_json(path, task)
        manifest_rows.append({
            "stage": "R95", "task_id": task["task_id"], "region": region,
            "fold": task["fold"], "likelihood_family": task["likelihood_family"],
            "tau": task["tau"], "runner_type": task["runner_type"],
            "parent_task_ids": json.dumps(task["parent_task_ids"], separators=(",", ":")),
            "task_config": str(path.resolve()), "task_config_sha256": sha256_file(path),
            "output_dir": task["output_dir"], "pipeline_contract_sha256": pipeline_hash,
            "launch_authorized": False, "test_opened": False,
            **{name: False for name in BLOCKED},
        })
    manifest = pd.DataFrame(manifest_rows)
    manifest_path = grid / "task_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    pipeline_path = grid / "pipeline_contract.json"
    atomic_write_json(pipeline_path, pipeline)
    region_contract = {
        "schema_version": 1, "target_region": region, "selection_fold": 1,
        "real_folds": list(FOLDS), "quantiles": list(PAPER_QUANTILES),
        "test_opened": False, **{name: False for name in BLOCKED},
    }
    region_contract["contract_sha256"] = canonical_sha256(region_contract)
    region_contract_path = grid / "region_contract.json"
    atomic_write_json(region_contract_path, region_contract)
    control = {
        "schema_version": 1, "stage": "R97", "region": region,
        "tasks": len(manifest), "workers": int(args.workers),
        "one_model_process_per_cpu": True, "threads_per_process": 1,
        "git_identity": git.to_dict(), "pipeline_contract_sha256": pipeline_hash,
        "normal_convergence_recovery": {
            "enabled": True,
            "trigger": "finite_nonconverged_normal_rhs_at_iteration_ceiling",
            "retry_max_iter": 500,
            "tol": 1e-5,
            "preserve_initial_diagnostics": True,
        },
        "launch_authorized": False, "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    control_path = grid / "launch_control.json"
    atomic_write_json(control_path, control)
    counts = manifest.likelihood_family.value_counts().to_dict()
    gates = pd.DataFrame([
        {"gate": "exact_45_tasks", "passed": len(manifest) == 45, "observed": len(manifest)},
        {"gate": "exact_family_mix", "passed": counts == {"al": 21, "exal": 21, "normal_rhs": 3}, "observed": json.dumps(counts, sort_keys=True)},
        {"gate": "all_three_folds", "passed": set(manifest.fold.astype(int)) == set(FOLDS), "observed": sorted(manifest.fold.unique())},
        {"gate": "no_test_keys", "passed": no_test_keys(yaml.safe_load(data_path.read_text())["pricefm"]["splits"]), "observed": "train,val"},
        {"gate": "one_DESN_tau0", "passed": True, "observed": f"{region}:{contract['tau0']}"},
        {"gate": "launch_not_self_authorized", "passed": not manifest.launch_authorized.astype(bool).any(), "observed": False},
    ])
    if not gates.passed.astype(bool).all():
        raise RuntimeError(f"R97 region materialization gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "region_quantile_surface_gates.csv", index=False)
    summary = {
        "status": "completed_launch_grade_not_launched", "stage": "R97", "region": region,
        "tasks": 45, "normal_rhs_tasks": 3, "al_tasks": 21, "exal_tasks": 21,
        "pipeline_contract_sha256": pipeline_hash,
        "region_contract": str(region_contract_path), "pipeline_contract": str(pipeline_path),
        "manifest": str(manifest_path), "launch_control": str(control_path),
        "preprocessing_terminal": str((grid / "preprocessing_terminal.json").resolve()),
        "active_window_regions": active_regions,
        "quarantined_previous_grid": str(quarantined_grid) if quarantined_grid else None,
        "quarantined_previous_output": str(quarantined_output) if quarantined_output else None,
        "test_opened": False, "launch_invoked": False,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "region_quantile_surface_plan.md").write_text(
        f"# R97 region validation surface: {region}\n\n"
        "The selected normal-RHS DESN/tau0 contract is reused unchanged for all three "
        "folds and seven quantiles. AL and coherently initialized exAL are both fitted; "
        "one whole family is selected by Fold-1 validation only. Test data are absent.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
