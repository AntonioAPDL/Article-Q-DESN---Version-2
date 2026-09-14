#!/usr/bin/env python3
"""Prepare the seven-atom R94 exAL repair refit without launching it."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    canonical_sha256,
    content_task_id,
    file_record,
    git_identity,
    prepare_empty_directory,
    validate_mutation_firewall,
    validate_no_test_adapter,
    validate_quantiles,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R93_TASK = DATA / (
    "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906/"
    "outer_normal_closeout/pricefm_stage_r93_quantile_task.json"
)
R93_MODEL = DATA / (
    "runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906/"
    "r93_se2_region_frozen/model"
)
AUDIT = DATA / "authoritative/pricefm_stage_r94_exal_initialization_audit_20260906/summary.json"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
RUNTIME_MANIFEST = RUNTIME / "pricefm_stage_r94_coherent_exal_init_manifest.json"
TAG = "pricefm_stage_r94_coherent_exal_refit_20260906"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r94_coherent_exal_launch_prep_20260906"
RUNNER = Path(__file__).with_name("299_run_pricefm_stage_r94_exal_component.R")
CODE_ROOT = Path(__file__).resolve().parents[3]
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BASE_SHA = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
REPAIR = (
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r93-task", type=Path, default=R93_TASK)
    p.add_argument("--r93-model-dir", type=Path, default=R93_MODEL)
    p.add_argument("--adapter-dir", type=Path, default=None)
    p.add_argument("--audit-summary", type=Path, default=AUDIT)
    p.add_argument("--runtime", type=Path, default=RUNTIME)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME_MANIFEST)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--code-root", type=Path, default=CODE_ROOT)
    p.add_argument("--quarantine-root", type=Path, default=None)
    p.add_argument("--recommended-workers", type=int, default=7)
    p.add_argument("--quarantine-existing", action="store_true")
    p.add_argument("--skip-git-check", action="store_true", help=argparse.SUPPRESS)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def tau_token(tau: float) -> str:
    return f"{tau:.2f}".replace(".", "p")


def run(args: argparse.Namespace) -> dict[str, Any]:
    source_task = json.loads(args.r93_task.read_text())
    audit = json.loads(args.audit_summary.read_text())
    runtime = json.loads(args.runtime_manifest.read_text())
    if source_task.get("stage") != "R93" or source_task.get("selection_split") != "val":
        raise RuntimeError("R94 requires the exact complete R93 quantile task")
    validate_quantiles(source_task.get("quantiles", ()), label="R93 quantiles")
    if (
        audit.get("r93_complete") is not True
        or audit.get("production_refit_preparation_authorized") is not True
        or audit.get("test_opened") is not False
        or audit.get("test_access_authorized") is not False
    ):
        raise RuntimeError("R94 production prep must wait for the complete R93 audit")
    if (
        runtime.get("status") != "installed_coherent_exal_initialization_runtime"
        or runtime.get("version") != "1.1.1.9005"
        or runtime.get("repair") != REPAIR
        or runtime.get("base_tarball_sha256") != BASE_SHA
        or runtime.get("launch_authorized") is not False
        or runtime.get("test_access_authorized") is not False
        or runtime.get("test_opened") is not False
    ):
        raise RuntimeError("R94 coherent runtime provenance is invalid")
    adapter = Path(getattr(args, "adapter_dir", None) or source_task["adapter_dir"])
    required_adapter = (
        "X_train.csv", "y_train.csv", "rows_train.csv",
        "X_val.csv", "y_val.csv", "rows_val.csv",
        "adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.npz",
    )
    if not all((adapter / name).is_file() for name in required_adapter):
        raise RuntimeError("R94 train/validation adapter is incomplete")
    validate_no_test_adapter(adapter)
    for name in BLOCKED:
        if source_task.get(name) is not False:
            raise RuntimeError(f"R93 source authorizes forbidden action: {name}")

    adapter_records = [file_record(adapter / name, f"adapter_{name}") for name in required_adapter]
    adapter_scripts = source_task.get("adapter_scripts") or []
    if not adapter_scripts:
        raise RuntimeError("R93 source task omits public-API adapter provenance")
    for item in adapter_scripts:
        path = Path(item["path"])
        if not path.is_file() or sha256(path) != str(item["sha256"]):
            raise RuntimeError(f"R93 adapter-script hash changed: {path}")

    code_root = Path(getattr(args, "code_root", CODE_ROOT)).resolve()
    if bool(getattr(args, "skip_git_check", False)):
        git = {
            "worktree": str(code_root), "branch": "fixture", "head": "fixture",
            "upstream": "fixture", "upstream_head": "fixture", "clean": True,
        }
    else:
        git = git_identity(code_root).to_dict()
        if not git["clean"] or git["head"] != git["upstream_head"]:
            raise RuntimeError("R94 prep requires a clean task branch synchronized with upstream")

    quarantine_root = Path(
        getattr(args, "quarantine_root", None)
        or (Path(args.output_dir).resolve().parent / "quarantine")
    )
    allow_quarantine = bool(getattr(args, "quarantine_existing", False))
    grid, quarantined_grid = prepare_empty_directory(
        args.grid_dir, quarantine_root=quarantine_root,
        reason="replaced_r94_grid", allow_quarantine=allow_quarantine,
    )
    output, quarantined_output = prepare_empty_directory(
        args.output_dir, quarantine_root=quarantine_root,
        reason="replaced_r94_prep", allow_quarantine=allow_quarantine,
    )
    args.run_dir.mkdir(parents=True, exist_ok=True)
    tasks_dir = grid / "tasks"
    tasks_dir.mkdir()
    rows: list[dict[str, Any]] = []
    semantic = source_task["semantic_contract"]
    profile = source_task["qdesn_vb"]["structured_sigmagam"]
    rhs = source_task["rhs"]
    pipeline_identity = {
        "schema_version": 1,
        "stage": "R94",
        "region": semantic["region"],
        "fold": int(semantic["fold"]),
        "quantiles": list(QUANTILES),
        "source_r93_task_sha256": sha256(args.r93_task),
        "runtime_manifest_sha256": sha256(args.runtime_manifest),
        "audit_summary_sha256": sha256(args.audit_summary),
        "adapter_records": adapter_records,
        "git": git,
    }
    pipeline_hash = canonical_sha256(pipeline_identity)
    for index, tau in enumerate(QUANTILES, start=1):
        atom = args.r93_model_dir / "atoms" / f"tau={tau_token(tau)}" / "al"
        beta_path = atom / "beta_summary.csv"
        parameter_path = atom / "parameter_summary.csv"
        prediction_path = atom / "predictions_scaled.csv"
        terminal_path = atom / "terminal.json"
        if not all(path.is_file() for path in (
            beta_path, parameter_path, prediction_path, terminal_path,
        )):
            raise RuntimeError(f"R94 missing R93 AL warm start at tau={tau}")
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") != "completed" or terminal.get("numerical_gate_passed") is not True:
            raise RuntimeError(f"R94 R93 AL warm start is not eligible at tau={tau}")
        beta = pd.read_csv(beta_path)
        if (
            "beta_cov_diag" not in beta
            or beta.beta_mean.isna().any()
            or beta.beta_cov_diag.isna().any()
            or not beta.beta_cov_diag.gt(0).all()
        ):
            raise RuntimeError(f"R94 AL q(beta) summary is incomplete at tau={tau}")
        task_identity = {
            "pipeline_contract_sha256": pipeline_hash,
            "region": semantic["region"], "fold": int(semantic["fold"]),
            "tau": tau, "likelihood_family": "exal",
        }
        task_id = content_task_id(
            f"r94_{semantic['region']}_f{int(semantic['fold'])}_tau{tau_token(tau)}_exal",
            task_identity,
        )
        task = {
            "schema_version": 1,
            "stage": "R94",
            "task_id": task_id,
            "case_id": f"r94_{semantic['region'].lower()}_region_frozen",
            "region": semantic["region"],
            "fold": int(semantic["fold"]),
            "tau": tau,
            "likelihood_family": "exal",
            "method_id": "qdesn_exal_rhs_ns_r94_coherent_init",
            "selection_split": "val",
            "pipeline_contract_sha256": pipeline_hash,
            "task_identity": task_identity,
            "source_r93_task": str(args.r93_task.resolve()),
            "source_r93_task_sha256": sha256(args.r93_task),
            "source_r93_semantic_contract_sha256": source_task["semantic_contract_sha256"],
            "adapter_dir": str(adapter.resolve()),
            "adapter_files": adapter_records,
            "adapter_scripts": adapter_scripts,
            "al_beta_path": str(beta_path.resolve()),
            "al_beta_sha256": sha256(beta_path),
            "al_parameter_path": str(parameter_path.resolve()),
            "al_parameter_sha256": sha256(parameter_path),
            "al_prediction_path": str(prediction_path.resolve()),
            "al_prediction_sha256": sha256(prediction_path),
            "al_source_terminal": str(terminal_path.resolve()),
            "al_source_terminal_sha256": sha256(terminal_path),
            "runtime_manifest": str(args.runtime_manifest.resolve()),
            "runtime_manifest_sha256": sha256(args.runtime_manifest),
            "r_library": str(args.runtime.resolve()),
            "audit_summary": str(args.audit_summary.resolve()),
            "audit_summary_sha256": sha256(args.audit_summary),
            "runner_script": str(RUNNER.resolve()),
            "runner_script_sha256": sha256(RUNNER),
            "git_identity": git,
            "warm_start_mode": "al_qbeta_rhs_latent_first",
            "max_iter": 200,
            "tol": float(source_task["qdesn_vb"]["tol"]),
            "n_samp": int(source_task["qdesn_vb"]["n_samp"]),
            "n_samp_xi": int(source_task["qdesn_vb"]["n_samp_xi"]),
            "structured_grid_size": int(profile["structured_grid_size"]),
            "structured_span_sd": float(profile["structured_span_sd"]),
            "min_postwarmup_updates": int(profile["min_postwarmup_updates"]),
            "postwarmup_damping": float(profile["postwarmup_damping"]),
            "postwarmup_damping_iters": int(profile["postwarmup_damping_iters"]),
            "rhs_tau0": float(rhs["tau0"]),
            "rhs_init_tau": float(rhs["init_tau"]),
            "rhs_freeze_tau_iters": int(rhs["freeze_tau_iters"]),
            "rhs_freeze_tau_warmup_iters": int(rhs["freeze_tau_warmup_iters"]),
            "seed": int(semantic["seed"]) + 9400 + index,
            "frozen_desn": {
                name: semantic[name]
                for name in (
                    "feature_policy", "depth", "units", "lag_window", "alpha", "rho",
                    "input_scale", "state_output", "tau0",
                )
            },
            "launch_authorized": False,
            "test_opened": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
            "output_dir": str(
                args.run_dir.resolve() / f"r94_{semantic['region'].lower()}_region_frozen"
                / "components" / f"tau={tau_token(tau)}" / "exal"
            ),
        }
        task_path = tasks_dir / f"{task_id}.json"
        write_json(task_path, task)
        rows.append(
            {
                "stage": "R94",
                "task_id": task_id,
                "case_id": task["case_id"],
                "region": task["region"],
                "fold": task["fold"],
                "tau": tau,
                "likelihood_family": "exal",
                "task_config": str(task_path.resolve()),
                "task_config_sha256": sha256(task_path),
                "output_dir": task["output_dir"],
                "rhs_tau0": task["rhs_tau0"],
                "feature_policy": semantic["feature_policy"],
                "depth": semantic["depth"],
                "units": semantic["units"],
                "lag_window": semantic["lag_window"],
                "warm_start_mode": task["warm_start_mode"],
                "pipeline_contract_sha256": pipeline_hash,
                "launch_authorized": False,
                "test_opened": False,
                **{name: False for name in BLOCKED},
            }
        )
    manifest = pd.DataFrame(rows).sort_values("tau")
    manifest_path = grid / "task_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    launch_control = {
        "stage": "R94",
        "tag": TAG,
        "task_manifest": str(manifest_path.resolve()),
        "tasks": 7,
        "cases": 1,
        "recommended_workers": min(7, max(1, int(args.recommended_workers))),
        "one_process_per_logical_cpu": True,
        "threads_per_process": 1,
        "resume_policy": "skip_only_hash_valid_completed_atomic_tasks",
        "invalid_partial_policy": "quarantine_then_retry_once",
        "pipeline_contract_sha256": pipeline_hash,
        "git_identity": git,
        "launch_authorized_by_prep": False,
        "test_opened": False,
        "test_access": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(grid / "launch_control.json", launch_control)
    gates = pd.DataFrame(
        [
            {"gate": "complete_R93_AL_surface", "passed": len(manifest) == 7, "observed": len(manifest)},
            {"gate": "exact_seven_quantiles", "passed": set(manifest.tau) == set(QUANTILES), "observed": sorted(manifest.tau)},
            {"gate": "exAL_only", "passed": manifest.likelihood_family.eq("exal").all(), "observed": "exal"},
            {"gate": "case_DESN_and_tau0_frozen", "passed": True, "observed": source_task["semantic_contract_sha256"]},
            {"gate": "AL_qbeta_hash_frozen", "passed": True, "observed": 7},
            {"gate": "R94_runtime_hash_frozen", "passed": True, "observed": runtime["version"]},
            {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
            {"gate": "launch_requires_explicit_authorization", "passed": not manifest.launch_authorized.any(), "observed": "blocked_by_prep"},
        ]
    )
    if not gates.passed.all():
        raise RuntimeError("R94 launch-preparation gates failed")
    gates.to_csv(output / "pricefm_stage_r94_launch_prep_gates.csv", index=False)
    source_paths = [
        Path(__file__).resolve(), RUNNER.resolve(), args.r93_task.resolve(),
        args.audit_summary.resolve(), args.runtime_manifest.resolve(),
        manifest_path, grid / "launch_control.json",
        *[Path(item["path"]) for item in adapter_records],
        *[Path(item["path"]) for item in adapter_scripts],
    ]
    pd.DataFrame(
        [{"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size} for path in source_paths]
    ).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r94_coherent_exal_refit_prepared_not_launched",
        "region": semantic["region"],
        "fold": int(semantic["fold"]),
        "tasks": 7,
        "AL_atoms_reused": 7,
        "ridge_rhs_DESN_AL_refits": 0,
        "exAL_atoms_to_refit": 7,
        "max_iter": 200,
        "recommended_workers": launch_control["recommended_workers"],
        "pipeline_contract_sha256": pipeline_hash,
        "launch_authorized": False,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutated": False,
        "article_mutated": False,
        "quarantined_previous_grid": str(quarantined_grid) if quarantined_grid else None,
        "quarantined_previous_output": str(quarantined_output) if quarantined_output else None,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r94_launch_prep_report.md").write_text(
        "# PriceFM Stage-R94 exAL Repair Launch Preparation\n\n"
        "This preparation contains exactly seven independent exAL VB atoms for the frozen R93 "
        f"{semantic['region']} fold {semantic['fold']} case. It reuses the seven hash-frozen AL "
        "q(beta) summaries, including covariance diagonals, and changes only coherent exAL "
        "initialization and numerical eligibility. Ridge, normal RHS, DESN features, AL fits, "
        "tau0, and all scientific data are reused. No launch or downstream mutation is authorized.\n"
    )
    if list(grid.rglob("*.yaml")) or list(grid.rglob("*.yml")):
        raise RuntimeError("R94 prep must not create launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
