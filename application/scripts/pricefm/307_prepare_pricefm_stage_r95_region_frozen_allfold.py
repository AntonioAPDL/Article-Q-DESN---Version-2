#!/usr/bin/env python3
"""Prepare executable train/validation-only R95 all-fold tasks without launching."""

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

from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    content_task_id,
    file_record,
    git_identity,
    prepare_empty_directory,
    sha256_file,
    validate_mutation_firewall,
    validate_pretest_firewall,
    validate_quantiles,
    verify_file_record,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r95_region_frozen_allfold_validation_20260907"
R94_FROZEN = DATA / (
    "authoritative/pricefm_stage_r94_validation_family_closeout_20260907/"
    "pricefm_stage_r94_frozen_validation_family.json"
)
R93_TASK = DATA / (
    "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906/"
    "outer_normal_closeout/pricefm_stage_r93_quantile_task.json"
)
SOURCE_DATA_CONFIG = ARTIFACT_REPO / "application/config/pricefm_data_pipeline.yaml"
NORMAL_PACKAGE = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
R94_LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
R94_RUNTIME_MANIFEST = R94_LIBRARY / "pricefm_stage_r94_coherent_exal_init_manifest.json"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
PROCESSED = DATA / "processed_stage_r95_region_frozen_allfold_20260907"
OUTPUT = DATA / "authoritative/pricefm_stage_r95_allfold_launch_prep_20260907"
RUNNER = Path(__file__).with_name("308_run_pricefm_stage_r95_quantile_atom.R")
LAUNCHER = Path(__file__).with_name("309_launch_pricefm_stage_r95_allfold.py")
CLOSEOUT = Path(__file__).with_name("310_closeout_pricefm_stage_r95_allfold_validation.py")
CODE_ROOT = Path(__file__).resolve().parents[3]
R_SCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
PYTHON = DATA / "venv/bin/python"
FOLDS = (2, 3)
WARM_ORDER = (0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90)
WARM_PARENT = {
    0.50: "normal_rhs",
    0.45: "al_0.50",
    0.25: "al_0.45",
    0.10: "al_0.25",
    0.55: "al_0.50",
    0.75: "al_0.55",
    0.90: "al_0.75",
}
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
BLOCKED = (
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--r94-frozen", type=Path, default=R94_FROZEN)
    value.add_argument("--r93-task", type=Path, default=R93_TASK)
    value.add_argument("--source-data-config", type=Path, default=SOURCE_DATA_CONFIG)
    value.add_argument("--normal-package", type=Path, default=NORMAL_PACKAGE)
    value.add_argument("--r94-library", type=Path, default=R94_LIBRARY)
    value.add_argument("--r94-runtime-manifest", type=Path, default=R94_RUNTIME_MANIFEST)
    value.add_argument("--grid-dir", type=Path, default=GRID)
    value.add_argument("--run-dir", type=Path, default=RUNS)
    value.add_argument("--processed-dir", type=Path, default=PROCESSED)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--code-root", type=Path, default=CODE_ROOT)
    value.add_argument("--workers", type=int, default=20)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    value.add_argument("--skip-git-check", action="store_true", help=argparse.SUPPRESS)
    return value


def write_yaml(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp")
    with temporary.open("w") as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)
    temporary.replace(path)


def tau_token(tau: float) -> str:
    return f"{tau:.2f}".replace(".", "p")


def parse_units(value: Any) -> list[int]:
    if isinstance(value, str):
        parsed = json.loads(value)
    else:
        parsed = value
    units = [int(item) for item in parsed]
    if not units or any(item <= 0 for item in units):
        raise RuntimeError("frozen units must be positive integers")
    return units


def no_test_keys(value: Any) -> bool:
    if isinstance(value, dict):
        return all("test" not in str(key).lower() and no_test_keys(item) for key, item in value.items())
    if isinstance(value, (list, tuple)):
        return all(no_test_keys(item) for item in value)
    return True


def make_data_config(source: dict[str, Any], processed: Path) -> dict[str, Any]:
    payload = copy.deepcopy(source)
    spec = payload["pricefm"]
    for name in ("raw_dir", "interim_dir", "external_repo_dir", "log_dir"):
        path = Path(spec[name])
        if not path.is_absolute():
            spec[name] = str((ARTIFACT_REPO / path).resolve())
    spec["processed_dir"] = str(processed.resolve())
    spec["allow_absolute_local_paths"] = True
    split_by_fold = {int(item["fold"]): item for item in spec["splits"]}
    spec["splits"] = [
        {
            "fold": fold,
            "train": list(split_by_fold[fold]["train"]),
            "val": list(split_by_fold[fold]["val"]),
        }
        for fold in FOLDS
    ]
    spec["windows"]["lag_window"] = 240
    spec["pilot"] = {"enabled": True, "region": "SE_2", "fold": 2}
    if not no_test_keys(spec["splits"]):
        raise RuntimeError("R95 generated data configuration contains test keys")
    return payload


def normal_full_config(
    data_config: Path,
    run_dir: Path,
    normal_package: Path,
    frozen: dict[str, Any],
    r93_smoke: dict[str, Any],
    neighbors: list[str],
) -> dict[str, Any]:
    desn = frozen["frozen_desn"]
    adapter_source = r93_smoke["adapter"]
    adapter = {
        "output_root": str((run_dir / "normal/cells").resolve()),
        "feature_map": adapter_source["feature_map"],
        "feature_dim": int(adapter_source["feature_dim"]),
        "seed": int(adapter_source["seed"]),
        "include_intercept": True,
        "keep_matrices_after_success": True,
        "row_chunk_size": int(adapter_source.get("row_chunk_size", 512)),
        "projection_scale": float(adapter_source.get("projection_scale", 1.0)),
        "depth": int(desn["depth"]),
        "units": parse_units(desn["units"]),
        "alpha": float(desn["alpha"]),
        "rho": float(desn["rho"]),
        "input_scale": float(desn["input_scale"]),
        "recurrent_sparsity": float(adapter_source.get("recurrent_sparsity", 0.05)),
        "reservoir_activation": str(adapter_source.get("reservoir_activation", "tanh")),
        "state_output": str(desn["state_output"]),
        "spatial": {
            "graph_degree": 1,
            "neighbor_regions": neighbors,
            "max_neighbor_regions": len(neighbors),
        },
    }
    return {
        "pricefm_desn_full": {
            "data_config": str(data_config.resolve()),
            "package_path": str(normal_package.resolve()),
            "rscript_bin": str(R_SCRIPT),
            "python_bin": str(PYTHON.resolve()),
            "scope": {
                "regions": [str(frozen["region"])],
                "folds": list(FOLDS),
                "splits": ["train", "val"],
                "horizons": "all",
                "quantiles": list(PAPER_QUANTILES),
                "feature_policy": str(desn["feature_policy"]),
            },
            "adapter": adapter,
            "run": {
                "output_dir": str((run_dir / "normal").resolve()),
                "nd_predictive": 400,
                "seed": int(adapter_source["seed"]),
                "default_jobs": 1,
            },
            "rhs_ns": {
                "tau0": float(frozen["rhs_tau0"]),
                "init_tau": 1.0,
                "shrink_intercept": False,
                "freeze_tau_iters": 5,
                "freeze_tau_warmup_iters": 5,
            },
            "warm_start": {"enabled": False},
            "normal": {
                "enabled": True,
                "prior_types": ["rhs_ns"],
                "predictive_quantile_mode": "analytic_normal",
                "omega_prior": {"a": 2.0, "b": 1.0},
                "vb_control": {"max_iter": 100, "min_iter": 50, "tol": 1e-5, "verbose": False},
            },
            "qdesn_vb": {
                "enabled": False,
                "likelihoods": ["al", "exal"],
                "max_iter": 200,
                "tol": 1e-4,
                "n_samp_xi": 200,
                "prior_sigma": {"a": 1.0, "b": 1.0},
                "prior_gamma": {"mu0": 0.0, "s20": 10.0},
            },
            "exact_equivalence": {"enabled": False},
            "training": {"train_origin_limit": 3000, "train_origin_selection": "tail"},
            "artifact_hygiene": {
                "enabled": True,
                "clean_adapter_patterns": [],
                "clean_model_patterns": ["*.rds", "*.rda", "*.RData", "*.rdata"],
                "preserve_patterns": ["*.csv", "*.json", "*.log", "*.md", "*.npz"],
            },
            "nested_validation": {"enabled": False},
            "comparison_metadata": {
                "stage": "pricefm_stage_r95_region_frozen_allfold_validation",
                "selection_rule": "reuse_R94_region_frozen_contract_no_fold_retuning",
                "selection_is_validation_only": True,
                "test_metrics_role": "not_loaded_not_predicted_not_selected",
                "test_access_authorized": False,
            },
        }
    }


def task_base(
    pipeline_hash: str,
    region: str,
    fold: int,
    family: str,
    tau: float | None,
    parents: list[str],
    run_dir: Path,
) -> dict[str, Any]:
    identity = {
        "pipeline_contract_sha256": pipeline_hash,
        "region": region,
        "fold": fold,
        "likelihood_family": family,
        "tau": tau,
        "parent_task_ids": parents,
    }
    prefix = f"r95_{region}_f{fold}_{family}_{tau_token(tau) if tau is not None else 'na'}"
    task_id = content_task_id(prefix, identity)
    return {
        "schema_version": 1,
        "stage": "R95",
        "task_id": task_id,
        "region": region,
        "fold": fold,
        "likelihood_family": family,
        "tau": tau,
        "parent_task_ids": parents,
        "pipeline_contract_sha256": pipeline_hash,
        "selection_split": "val",
        "launch_authorized": False,
        "test_opened": False,
        **{name: False for name in BLOCKED},
        "output_dir": str((run_dir / f"region={region}" / f"fold={fold}" / "tasks" / task_id).resolve()),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= int(args.workers) <= 20:
        raise RuntimeError("R95 workers must be between 1 and 20")
    source_paths = (
        args.r94_frozen,
        args.r93_task,
        args.source_data_config,
        args.r94_runtime_manifest,
        RUNNER,
        LAUNCHER,
        CLOSEOUT,
    )
    for path in source_paths:
        if not Path(path).is_file():
            raise FileNotFoundError(path)
    if not args.normal_package.is_dir() or not args.r94_library.is_dir():
        raise FileNotFoundError("R95 runtime directory is missing")

    frozen = json.loads(args.r94_frozen.read_text())
    r93_task = json.loads(args.r93_task.read_text())
    validate_pretest_firewall(frozen, label="R94 frozen family")
    validate_mutation_firewall(frozen, label="R94 frozen family")
    validate_quantiles(frozen.get("quantiles", ()), label="R94 frozen quantiles")
    if (
        frozen.get("stage") != "R94"
        or frozen.get("status") != "validation_family_frozen_awaiting_allfold_pretest_fit"
        or frozen.get("selected_family") != "exal"
        or frozen.get("selection_fold") != 1
        or frozen.get("per_quantile_family_mixing") is not False
        or len(frozen.get("selected_atoms") or []) != 7
    ):
        raise RuntimeError("R95 requires the complete exAL R94 Fold-1 family freeze")
    for family in ("al", "exal"):
        atoms = (frozen.get("all_family_atoms") or {}).get(family) or []
        if len(atoms) != 7:
            raise RuntimeError(f"R94 {family} source surface is incomplete")
        for atom in atoms:
            for role in ("beta", "prediction", "terminal"):
                verify_file_record(atom[role], label=f"R94 {family} {role}")

    if r93_task.get("stage") != "R93" or r93_task.get("selection_split") != "val":
        raise RuntimeError("R95 requires the exact R93 Fold-1 task")
    # R93 predates the paired firewall schema and omitted test_opened. Its
    # immutable config and adapter are checked directly below; R95 emits both
    # fields and fails closed thereafter.
    if (
        r93_task.get("test_access_authorized") is not False
        or r93_task.get("test_opened") not in (None, False)
    ):
        raise RuntimeError("R93 legacy task authorizes or records test access")
    validate_mutation_firewall(r93_task, label="R93 task")
    validate_quantiles(r93_task.get("quantiles", ()), label="R93 task quantiles")
    r93_config = yaml.safe_load(Path(r93_task["config"]).read_text())["pricefm_desn_smoke"]
    if set(r93_config.get("splits") or []) != {"train", "val"}:
        raise RuntimeError("R93 source task is not train/validation-only")
    r93_data = yaml.safe_load(Path(r93_task["data_config"]).read_text())["pricefm"]
    if any("test" in split for split in r93_data.get("splits") or []):
        raise RuntimeError("R93 source data configuration exposes test")
    neighbors = [str(value) for value in r93_config["adapter"]["spatial"]["neighbor_regions"]]
    if neighbors != ["NO_3", "NO_4", "SE_1", "SE_3"]:
        raise RuntimeError(f"unexpected frozen SE_2 graph neighbors: {neighbors}")
    if str(frozen["frozen_desn"]["feature_policy"]) != "graph_summary_mean":
        raise RuntimeError("R95 expected the frozen graph-summary-mean information set")

    runtime = json.loads(args.r94_runtime_manifest.read_text())
    if (
        runtime.get("status") != "installed_coherent_exal_initialization_runtime"
        or runtime.get("version") != "1.1.1.9005"
        or runtime.get("repair") != REPAIR
        or runtime.get("test_opened") is not False
        or runtime.get("test_access_authorized") is not False
    ):
        raise RuntimeError("R95 coherent runtime provenance is invalid")

    code_root = args.code_root.resolve()
    if args.skip_git_check:
        git = {
            "worktree": str(code_root), "branch": "fixture", "head": "fixture",
            "upstream": "fixture", "upstream_head": "fixture", "clean": True,
        }
    else:
        identity = git_identity(code_root)
        git = identity.to_dict()
        if not identity.clean or identity.head != identity.upstream_head:
            raise RuntimeError("R95 preparation requires a clean task branch synchronized with upstream")

    quarantine = args.quarantine_root or (args.output_dir.parent / "quarantine")
    grid, quarantined_grid = prepare_empty_directory(
        args.grid_dir,
        quarantine_root=quarantine,
        reason="replaced_r95_grid",
        allow_quarantine=args.quarantine_existing,
    )
    output, quarantined_output = prepare_empty_directory(
        args.output_dir,
        quarantine_root=quarantine,
        reason="replaced_r95_prep",
        allow_quarantine=args.quarantine_existing,
    )
    args.run_dir.mkdir(parents=True, exist_ok=True)
    configs = grid / "configs"
    tasks_dir = grid / "tasks"
    configs.mkdir()
    tasks_dir.mkdir()

    with args.source_data_config.open() as handle:
        source_data = yaml.safe_load(handle)
    data_config_path = configs / "pricefm_stage_r95_train_validation_data.yaml"
    write_yaml(data_config_path, make_data_config(source_data, args.processed_dir))
    normal_config_path = configs / "pricefm_stage_r95_normal_rhs.yaml"
    write_yaml(
        normal_config_path,
        normal_full_config(
            data_config_path, args.run_dir, args.normal_package, frozen, r93_config, neighbors
        ),
    )

    adapters = [Path(item["path"]) for item in r93_task.get("adapter_scripts") or []]
    if len(adapters) != 3:
        raise RuntimeError("R93 public-API adapter provenance is incomplete")
    for item, path in zip(r93_task["adapter_scripts"], adapters):
        if not path.is_file() or sha256_file(path) != str(item["sha256"]):
            raise RuntimeError(f"R93 adapter script hash changed: {path}")

    pipeline = {
        "schema_version": 1,
        "stage": "R95",
        "tag": TAG,
        "region": str(frozen["region"]),
        "selection_fold": 1,
        "fit_folds": list(FOLDS),
        "quantiles": list(PAPER_QUANTILES),
        "warm_order": list(WARM_ORDER),
        "warm_parent": {f"{tau:.2f}": parent for tau, parent in WARM_PARENT.items()},
        "selected_family": "exal",
        "family_selection_source": file_record(args.r94_frozen, "R94_frozen_validation_family"),
        "r93_task": file_record(args.r93_task, "R93_fold1_quantile_task"),
        "source_data_config": file_record(args.source_data_config, "canonical_pricefm_data_config"),
        "generated_data_config": file_record(data_config_path, "R95_train_validation_data_config"),
        "normal_full_config": file_record(normal_config_path, "R95_normal_rhs_full_config"),
        "normal_package": str(args.normal_package.resolve()),
        "r94_library": str(args.r94_library.resolve()),
        "r94_runtime_manifest": file_record(args.r94_runtime_manifest, "R94_coherent_runtime"),
        "adapter_scripts": [file_record(path, "public_API_adapter") for path in adapters],
        "runner": file_record(RUNNER, "R95_quantile_atom_runner"),
        "launcher": file_record(LAUNCHER, "R95_dependency_launcher"),
        "closeout": file_record(CLOSEOUT, "R95_validation_closeout"),
        "frozen_desn": frozen["frozen_desn"],
        "rhs": {
            "tau0": float(frozen["rhs_tau0"]), "init_tau": 1.0,
            "shrink_intercept": False, "freeze_tau_iters": 50,
            "freeze_tau_warmup_iters": 50,
        },
        "qdesn_vb": {
            "max_iter": 200, "tol": 1e-4, "n_samp": 200, "n_samp_xi": 200,
            "prior_sigma": {"a": 1.0, "b": 1.0},
            "prior_gamma": {"mu0": 0.0, "s20": 10.0},
            "structured_sigmagam": {
                "factorization": "structured", "structured_grid_size": 151,
                "structured_span_sd": 6.0, "freeze_warmup_iters": 0,
                "force_after_warmup": True, "postwarmup_damping": 0.2,
                "postwarmup_damping_iters": 30, "min_postwarmup_updates": 35,
            },
        },
        "active_window_regions": [str(frozen["region"]), *neighbors],
        "processed_dir": str(args.processed_dir.resolve()),
        "run_dir": str(args.run_dir.resolve()),
        "git_identity": git,
        "resource_policy": {
            "maximum_workers": 20,
            "requested_workers": int(args.workers),
            "one_model_process_per_cpu": True,
            "threads_per_process": 1,
            "preprocessing_threads": 1,
        },
        "selection_rule": "R94_family_and_region_spec_frozen_no_fold_or_quantile_retuning",
        "whole_region_fallback": "AL_if_any_new_exAL_atom_is_numerically_ineligible",
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    pipeline_hash = canonical_sha256(pipeline)
    pipeline["pipeline_contract_sha256"] = pipeline_hash

    rows: list[dict[str, Any]] = []
    normal_ids: dict[int, str] = {}
    al_ids: dict[tuple[int, float], str] = {}
    for fold in FOLDS:
        normal = task_base(
            pipeline_hash, pipeline["region"], fold, "normal_rhs", None, [], args.run_dir.resolve()
        )
        normal["runner_type"] = "normal_full"
        normal["normal_full_config"] = str(normal_config_path.resolve())
        normal["normal_full_config_sha256"] = sha256_file(normal_config_path)
        normal["normal_model_dir"] = str(
            (args.run_dir / "normal/cells" / f"region={pipeline['region']}" / f"fold={fold}" / "model").resolve()
        )
        normal["adapter_dir"] = str(
            (args.run_dir / "normal/cells" / f"region={pipeline['region']}" / f"fold={fold}" / "adapter").resolve()
        )
        normal_ids[fold] = normal["task_id"]
        rows.append(normal)
        labels = {"normal_rhs": normal["task_id"]}
        for index, tau in enumerate(WARM_ORDER, start=1):
            parent_id = labels[WARM_PARENT[tau]]
            al = task_base(
                pipeline_hash, pipeline["region"], fold, "al", tau, [parent_id], args.run_dir.resolve()
            )
            al.update({
                "runner_type": "quantile_atom",
                "normal_task_id": normal["task_id"],
                "normal_task_output": normal["output_dir"],
                "adapter_dir": normal["adapter_dir"],
                "parent_task_output": next(row["output_dir"] for row in rows if row["task_id"] == parent_id),
                "method_id": "qdesn_al_rhs_ns_r95_region_frozen",
                "warm_start_mode": "normal_or_adjacent_al_mean_scale",
                "seed": int(r93_config["adapter"]["seed"]) + fold * 1000 + index * 10,
            })
            al_ids[(fold, tau)] = al["task_id"]
            rows.append(al)
            labels[f"al_{tau:.2f}"] = al["task_id"]
            exal = task_base(
                pipeline_hash, pipeline["region"], fold, "exal", tau, [al["task_id"]], args.run_dir.resolve()
            )
            exal.update({
                "runner_type": "quantile_atom",
                "normal_task_id": normal["task_id"],
                "normal_task_output": normal["output_dir"],
                "adapter_dir": normal["adapter_dir"],
                "parent_task_output": al["output_dir"],
                "method_id": "qdesn_exal_rhs_ns_r95_coherent_init",
                "warm_start_mode": "al_qbeta_rhs_latent_first",
                "seed": int(r93_config["adapter"]["seed"]) + fold * 1000 + index * 10 + 1,
            })
            rows.append(exal)

    task_paths: dict[str, Path] = {}
    manifest_rows = []
    for task in rows:
        task.update({
            "data_config": str(data_config_path.resolve()),
            "data_config_sha256": sha256_file(data_config_path),
            "r_library": str(args.r94_library.resolve()),
            "runtime_manifest": str(args.r94_runtime_manifest.resolve()),
            "runtime_manifest_sha256": sha256_file(args.r94_runtime_manifest),
            "adapter_scripts": pipeline["adapter_scripts"],
            "runner_script": str(RUNNER.resolve()) if task["runner_type"] == "quantile_atom" else str(
                (code_root / "application/scripts/pricefm/10_run_desn_model_full.py").resolve()
            ),
            "rhs": pipeline["rhs"],
            "qdesn_vb": pipeline["qdesn_vb"],
            "frozen_desn": pipeline["frozen_desn"],
        })
        task["runner_script_sha256"] = sha256_file(task["runner_script"])
        path = tasks_dir / f"{task['task_id']}.json"
        atomic_write_json(path, task)
        task_paths[task["task_id"]] = path
        manifest_rows.append({
            "stage": "R95",
            "task_id": task["task_id"],
            "region": task["region"],
            "fold": task["fold"],
            "likelihood_family": task["likelihood_family"],
            "tau": task["tau"],
            "runner_type": task["runner_type"],
            "parent_task_ids": json.dumps(task["parent_task_ids"], separators=(",", ":")),
            "task_config": str(path.resolve()),
            "task_config_sha256": sha256_file(path),
            "output_dir": task["output_dir"],
            "pipeline_contract_sha256": pipeline_hash,
            "launch_authorized": False,
            "test_opened": False,
            **{name: False for name in BLOCKED},
        })
    manifest = pd.DataFrame(manifest_rows)
    manifest_path = grid / "task_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    atomic_write_json(grid / "pipeline_contract.json", pipeline)
    launch_control = {
        "schema_version": 1,
        "stage": "R95",
        "tag": TAG,
        "task_manifest": str(manifest_path.resolve()),
        "pipeline_contract": str((grid / "pipeline_contract.json").resolve()),
        "tasks": 30,
        "normal_rhs_tasks": 2,
        "al_tasks": 14,
        "exal_tasks": 14,
        "workers": int(args.workers),
        "maximum_workers": 20,
        "one_model_process_per_cpu": True,
        "threads_per_process": 1,
        "resume_policy": "hash_valid_terminal_only",
        "invalid_partial_policy": "quarantine_then_retry_once",
        "git_identity": git,
        "pipeline_contract_sha256": pipeline_hash,
        "launch_authorized_by_prep": False,
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    atomic_write_json(grid / "launch_control.json", launch_control)

    family_counts = manifest.likelihood_family.value_counts().to_dict()
    gates = pd.DataFrame([
        {"gate": "R94_exAL_family_frozen", "passed": frozen["selected_family"] == "exal", "observed": frozen["selected_family"]},
        {"gate": "exact_30_tasks", "passed": len(manifest) == 30, "observed": len(manifest)},
        {"gate": "exact_task_mix", "passed": family_counts == {"al": 14, "exal": 14, "normal_rhs": 2}, "observed": json.dumps(family_counts, sort_keys=True)},
        {"gate": "folds_2_and_3_only", "passed": set(manifest.fold) == {2, 3}, "observed": sorted(manifest.fold.unique())},
        {"gate": "data_config_has_no_test_key", "passed": no_test_keys(yaml.safe_load(data_config_path.read_text())["pricefm"]["splits"]), "observed": "train,val"},
        {"gate": "all_mutations_blocked", "passed": all(not manifest[name].astype(bool).any() for name in ("test_opened", *BLOCKED)), "observed": "blocked"},
        {"gate": "no_launch_yaml", "passed": not list(grid.rglob("*launch*.yaml")), "observed": "none"},
        {"gate": "workers_bounded", "passed": 1 <= int(args.workers) <= 20, "observed": int(args.workers)},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R95 preparation gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r95_launch_prep_gates.csv", index=False)
    source_records = [
        file_record(Path(__file__), "R95_preparer"),
        file_record(RUNNER, "R95_quantile_worker"),
        file_record(LAUNCHER, "R95_launcher"),
        file_record(CLOSEOUT, "R95_closeout"),
        file_record(args.r94_frozen, "R94_frozen_family"),
        file_record(args.r93_task, "R93_task"),
        file_record(args.source_data_config, "source_data_config"),
        file_record(data_config_path, "generated_data_config"),
        file_record(normal_config_path, "normal_full_config"),
        file_record(args.r94_runtime_manifest, "R94_runtime_manifest"),
        *pipeline["adapter_scripts"],
    ]
    pd.DataFrame(source_records).drop_duplicates("path").to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r95_allfold_train_validation_prepared_not_launched",
        "region": pipeline["region"],
        "selection_fold_reused": 1,
        "fit_folds": list(FOLDS),
        "selected_family": "exal",
        "tasks": 30,
        "normal_rhs_tasks": 2,
        "al_tasks": 14,
        "exal_tasks": 14,
        "workers": int(args.workers),
        "pipeline_contract_sha256": pipeline_hash,
        "task_manifest": str(manifest_path.resolve()),
        "quarantined_previous_grid": str(quarantined_grid) if quarantined_grid else None,
        "quarantined_previous_output": str(quarantined_output) if quarantined_output else None,
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r95_launch_prep.md").write_text(
        "# PriceFM Stage-R95 All-Fold Launch Preparation\n\n"
        "R95 reuses the validation-selected `SE_2` Fold-1 exAL family and prepares "
        "30 train/validation-only fits for folds 2 and 3: two normal-RHS, fourteen "
        "AL, and fourteen coherent same-tau exAL atoms. Geometry, tau0, information "
        "set, family, and warm-start dependencies are immutable. Test, registry, "
        "article, joint, and MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
