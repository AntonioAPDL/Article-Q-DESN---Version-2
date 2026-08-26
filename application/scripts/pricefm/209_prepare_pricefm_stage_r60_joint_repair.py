#!/usr/bin/env python3
"""Prepare the bounded R60 joint-VB repair comparison without opening test."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R59 = DATA / "authoritative/pricefm_stage_r59_joint_scoring_contract_20260826"
R57_AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
R57_GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r60_joint_repair_launch_prep_20260826"
GRID = DATA / "experiment_grids/pricefm_stage_r60_joint_repair_20260826"
RUNS = DATA / "runs/pricefm_stage_r60_joint_repair_20260826"
PYTHON = DATA / "venv/bin/python"
TARGETS = {"pricefm_joint_no_5_f2", "pricefm_joint_se_2_f2"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r59-dir", type=Path, default=R59)
    p.add_argument("--r57-authority-dir", type=Path, default=R57_AUTHORITY)
    p.add_argument("--r57-grid-dir", type=Path, default=R57_GRID)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--warm-additional-iterations", type=int, default=100)
    p.add_argument("--cold-total-iterations", type=int, default=150)
    p.add_argument("--tol", type=float, default=1e-4)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def scientific_spec_sha256(smoke: dict, runtime: dict) -> str:
    adapter = copy.deepcopy(smoke.get("adapter", {}))
    adapter.pop("output_dir", None)
    payload = {
        "region": smoke.get("region"), "fold": int(smoke.get("fold")),
        "quantiles": list(map(float, runtime["quantiles"])),
        "likelihood_family": runtime["likelihood_family"], "tau0": float(runtime["tau0"]),
        "adapter": adapter, "rhs_ns": smoke.get("rhs_ns", {}),
        "feature_policy": smoke.get("feature_policy", ""),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def arm_specs(args: argparse.Namespace) -> tuple[dict, ...]:
    return (
        {
            "arm_id": "core_plus_rhs_warm_restart_v1",
            "initialization_mode": "core_plus_rhs_warm_restart_v1",
            "max_iter": int(args.warm_additional_iterations),
            "iteration_interpretation": "additional_updates_after_nonexact_v1_state_restore",
        },
        {
            "arm_id": "cold_extended_reference",
            "initialization_mode": "cold",
            "max_iter": int(args.cold_total_iterations),
            "iteration_interpretation": "total_updates_from_historical_cold_initialization",
        },
    )


def run(args: argparse.Namespace) -> dict:
    if (
        args.warm_additional_iterations < 5 or args.cold_total_iterations < 5
        or args.tol <= 0 or args.workers < 1
    ):
        raise ValueError("Invalid R60 fit controls")
    output, grid, runs = args.output_dir.resolve(), args.grid_dir.resolve(), args.run_dir.resolve()
    prepare_dir(output, args.force)
    prepare_dir(grid, args.force)
    runs.mkdir(parents=True, exist_ok=True)

    r59_summary_path = args.r59_dir / "summary.json"
    repair_path = args.r59_dir / "pricefm_stage_r59_joint_repair_queue.csv"
    authority_path = args.r57_authority_dir / "pricefm_stage_r57_joint_case_authority.csv"
    r57_manifest_path = args.r57_grid_dir / "launch_manifest.csv"
    r59_summary = json.loads(r59_summary_path.read_text())
    repair = pd.read_csv(repair_path)
    authority = pd.read_csv(authority_path)
    old_manifest = pd.read_csv(r57_manifest_path)
    if (
        r59_summary.get("status") != "completed_joint_scoring_contract_freeze"
        or not bool(r59_summary.get("joint_scoring_contract_frozen", False))
        or bool(r59_summary.get("test_opened", True))
    ):
        raise RuntimeError("R59 scoring contract is not frozen with test sealed")
    if set(repair.case_id.astype(str)) != TARGETS or len(repair) != 2:
        raise RuntimeError(f"R60 repair queue must be exactly {sorted(TARGETS)}")
    forbidden = {"qdesn_AQL", "pricefm_AQL", "test_AQL", "cached_pricefm_test_AQL"}
    if forbidden & set(repair.columns):
        raise RuntimeError("Test outcomes leaked into the R60 repair queue")

    sources = authority.merge(
        old_manifest[["case_id", "config", "smoke_config", "output_dir"]],
        on="case_id", how="inner", validate="one_to_one",
    )
    sources = repair[[
        "case_id", "current_authoritative_validation_AQL", "checkpoint", "checkpoint_sha256",
    ]].merge(sources, on="case_id", how="inner", validate="one_to_one")
    if len(sources) != 2:
        raise RuntimeError("R60 could not recover both R57 source contracts")

    launch_rows, arm_rows, source_rows = [], [], []
    source_root = args.source_root.resolve()
    for source in sources.sort_values(["region", "fold"]).itertuples(index=False):
        checkpoint = Path(source.checkpoint).resolve()
        if not checkpoint.is_file() or sha256(checkpoint) != str(source.checkpoint_sha256):
            raise RuntimeError(f"R57 v1 checkpoint hash failed for {source.case_id}")
        old_runtime = yaml.safe_load(Path(source.config).read_text())["pricefm_stage_r57_joint_vb"]
        old_smoke = yaml.safe_load(Path(source.smoke_config).read_text())["pricefm_desn_smoke"]
        if float(old_runtime["tau0"]) != 0.001:
            raise RuntimeError(f"R60 first-line repair keeps tau0=0.001: {source.case_id}")
        inherited_spec_sha256 = scientific_spec_sha256(old_smoke, old_runtime)
        for arm in arm_specs(args):
            arm_case_id = f"{source.case_id}__{arm['arm_id']}"
            case_dir = runs / arm_case_id
            adapter_dir = case_dir / "adapter"
            model_dir = case_dir / "model"
            smoke_path = grid / "configs/adapter" / f"{arm_case_id}.yaml"
            runtime_path = grid / "configs/joint_vb" / f"{arm_case_id}.yaml"
            smoke_path.parent.mkdir(parents=True, exist_ok=True)
            runtime_path.parent.mkdir(parents=True, exist_ok=True)
            smoke = copy.deepcopy(old_smoke)
            smoke["splits"] = ["train", "val"]
            smoke["adapter"]["output_dir"] = str(adapter_dir)
            smoke["run"]["output_dir"] = str(model_dir)
            smoke["artifact_hygiene"] = {
                "enabled": True,
                "clean_adapter_patterns": ["X_*.csv", "y_*.csv", "rows_*.csv", "rows_all.csv"],
                "preserve_patterns": ["adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.*", "feature_provenance.csv"],
            }
            smoke_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))
            method_suffix = "warm_v1" if arm["initialization_mode"] != "cold" else "cold_extended"
            method_id = f"joint_qdesn_{source.likelihood_family}_rhs_ns_vb_r60_{method_suffix}"
            initialization = {"mode": arm["initialization_mode"]}
            if arm["initialization_mode"] != "cold":
                initialization.update({
                    "checkpoint": str(checkpoint),
                    "checkpoint_sha256": str(source.checkpoint_sha256),
                    "source_case_id": str(source.case_id),
                    "checkpoint_semantics": "core_plus_rhs_only_not_exact_continuation",
                })
            runtime = copy.deepcopy(old_runtime)
            runtime.update({
                "stage": "R60",
                "case_id": arm_case_id,
                "source_case_id": str(source.case_id),
                "method_id": method_id,
                "smoke_config": str(smoke_path),
                "adapter_dir": str(adapter_dir),
                "output_dir": str(model_dir),
                "source_root": str(source_root),
                "python_bin": str(args.python_bin.absolute()),
                "adapter_builder": str(source_root / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"),
                "summarizer": str(source_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
                "allowed_splits": ["train", "val"],
                "test_access_authorized": False,
                "max_iter": arm["max_iter"],
                "tol": float(args.tol),
                "initialization": initialization,
                "cleanup_adapter_after_success": True,
                "defer_cleanup_to_repair": True,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            })
            runtime_path.write_text(yaml.safe_dump({"pricefm_stage_r57_joint_vb": runtime}, sort_keys=False))
            materialized_spec_sha256 = scientific_spec_sha256(smoke, runtime)
            if materialized_spec_sha256 != inherited_spec_sha256:
                raise RuntimeError(f"R60 changed the inherited scientific specification: {arm_case_id}")
            launch_rows.append({
                "case_id": arm_case_id, "source_case_id": str(source.case_id),
                "region": str(source.region), "fold": int(source.fold),
                "likelihood_family": str(source.likelihood_family), "method_id": method_id,
                "arm_id": arm["arm_id"], "initialization_mode": arm["initialization_mode"],
                "max_iter": arm["max_iter"], "config": str(runtime_path),
                "smoke_config": str(smoke_path), "output_dir": str(model_dir),
                "scientific_spec_sha256": materialized_spec_sha256,
                "status": "prepared_not_launched",
            })
            arm_rows.append({
                "case_id": arm_case_id, "source_case_id": str(source.case_id),
                "region": str(source.region), "fold": int(source.fold),
                "likelihood_family": str(source.likelihood_family), "arm_id": arm["arm_id"],
                "initialization_mode": arm["initialization_mode"],
                "iteration_interpretation": arm["iteration_interpretation"],
                "max_iter": arm["max_iter"], "tau0": float(runtime["tau0"]),
                "inherited_scientific_spec_sha256": inherited_spec_sha256,
                "materialized_scientific_spec_sha256": materialized_spec_sha256,
                "current_authoritative_validation_AQL": float(source.current_authoritative_validation_AQL),
                "primary_scoring_role": "monotone_contract",
                "raw_joint_role": "diagnostic_not_selection", "test_access_authorized": False,
            })
            for label, path in (("runtime_config", runtime_path), ("adapter_config", smoke_path)):
                source_rows.append({
                    "case_id": arm_case_id, "label": label, "path": str(path),
                    "sha256": sha256(path), "bytes": path.stat().st_size,
                })
        source_rows.append({
            "case_id": str(source.case_id), "label": "r57_checkpoint_v1", "path": str(checkpoint),
            "sha256": sha256(checkpoint), "bytes": checkpoint.stat().st_size,
        })

    manifest = pd.DataFrame(launch_rows).sort_values(["region", "fold", "arm_id"]).reset_index(drop=True)
    arm_contract = pd.DataFrame(arm_rows).sort_values(["region", "fold", "arm_id"]).reset_index(drop=True)
    manifest_path = grid / "launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    arm_contract.to_csv(output / "pricefm_stage_r60_joint_repair_arm_contract.csv", index=False)
    for label, path in (
        ("r59_summary", r59_summary_path), ("r59_repair_queue", repair_path),
        ("r57_authority", authority_path), ("r57_launch_manifest", r57_manifest_path),
        ("prep_script", Path(__file__).resolve()),
    ):
        source_rows.append({
            "case_id": "ALL", "label": label, "path": str(path.resolve()),
            "sha256": sha256(path.resolve()), "bytes": path.stat().st_size,
        })
    code_sources = [
        source_root / "application/R/joint_qvp_qdesn.R",
        source_root / "application/R/joint_exqdesn_exact_structured_inference.R",
        source_root / "application/R/joint_exqdesn_inference_dispatch.R",
        source_root / "application/R/pricefm_joint_quantile_inference.R",
        source_root / "application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R",
        source_root / "application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py",
        source_root / "application/scripts/pricefm/205_repair_pricefm_stage_r57_joint_vb_postfit.py",
        source_root / "application/scripts/pricefm/210_closeout_pricefm_stage_r60_joint_repair.py",
        source_root / "application/scripts/pricefm/211_monitor_pricefm_stage_r60_joint_repair.py",
    ]
    for path in code_sources:
        if not path.is_file():
            raise FileNotFoundError(path)
        source_rows.append({
            "case_id": "ALL", "label": "code_source", "path": str(path.resolve()),
            "sha256": sha256(path.resolve()), "bytes": path.stat().st_size,
        })
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)

    launch = {
        "pricefm_stage_r60_joint_repair_launch": {
            "stage": "R60",
            "manifest": str(manifest_path),
            "runner": str(source_root / "application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R"),
            "launcher": str(source_root / "application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py"),
            "workers": min(int(args.workers), len(manifest)),
            "one_process_per_cpu": True,
            "numerical_threads_per_process": 1,
            "resume": True,
            "force": False,
            "selection_role": "validation_only_monotone_contract",
            "test_role": "sealed_until_r60_validation_freeze",
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    }
    launch_path = output / "pricefm_stage_r60_joint_repair_launch.yaml"
    launch_path.write_text(yaml.safe_dump(launch, sort_keys=False))
    gates = pd.DataFrame([
        {"gate": "exact_two_case_queue", "passed": set(manifest.source_case_id) == TARGETS, "observed": manifest.source_case_id.nunique()},
        {"gate": "two_arms_per_case", "passed": bool(manifest.groupby("source_case_id").size().eq(2).all()), "observed": manifest.groupby("source_case_id").size().to_dict()},
        {"gate": "v1_warm_semantics_honest", "passed": bool((manifest.initialization_mode == "core_plus_rhs_warm_restart_v1").sum() == 2), "observed": int((manifest.initialization_mode == "core_plus_rhs_warm_restart_v1").sum())},
        {"gate": "cold_reference_present", "passed": bool((manifest.initialization_mode == "cold").sum() == 2), "observed": int((manifest.initialization_mode == "cold").sum())},
        {"gate": "tau0_held_fixed", "passed": bool(arm_contract.tau0.eq(0.001).all()), "observed": sorted(arm_contract.tau0.unique().tolist())},
        {"gate": "desn_information_likelihood_held_fixed", "passed": bool(
            arm_contract.inherited_scientific_spec_sha256.eq(
                arm_contract.materialized_scientific_spec_sha256
            ).all()
        ), "observed": int(arm_contract.materialized_scientific_spec_sha256.nunique())},
        {"gate": "train_validation_only", "passed": bool(~arm_contract.test_access_authorized.any()), "observed": "train,val"},
        {"gate": "one_process_per_cpu", "passed": True, "observed": 1},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r60_joint_repair_prelaunch_gates.csv", index=False)
    if not gates.passed.astype(bool).all():
        raise RuntimeError(f"R60 prep gates failed: {gates.loc[~gates.passed.astype(bool)].to_dict('records')}")
    summary = {
        "status": "prepared_bounded_joint_repair_not_launched",
        "source_head": git_head(source_root), "target_cases": 2, "launch_cases": len(manifest),
        "warm_restart_cases": int(manifest.initialization_mode.ne("cold").sum()),
        "cold_reference_cases": int(manifest.initialization_mode.eq("cold").sum()),
        "warm_additional_iterations": int(args.warm_additional_iterations),
        "cold_total_iterations": int(args.cold_total_iterations),
        "primary_scoring_role": "monotone_contract", "selection_role": "validation_only",
        "test_access_authorized": False, "launch_authorized": True,
        "mcmc_launch_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r60_joint_repair_launch_prep_report.md").write_text(
        "# PriceFM Stage-R60 bounded joint repair prep\n\n"
        "R60 targets only `NO_5` fold 2 and `SE_2` fold 2. For each cell it compares the "
        "historical v1 core-plus-RHS warm restart with a cold extended reference while holding "
        "the selected DESN, information set, likelihood family, and `tau0=0.001` fixed. The v1 "
        "arm is explicitly not labeled exact continuation because the old checkpoint lacks the "
        "full covariance and local latent state. New outputs use full-state v2 checkpoints.\n\n"
        "Selection uses only monotone-contract original-scale validation AQL under the frozen R59 "
        "contract. Raw predictions remain diagnostic. Test, MCMC, registry, and article actions "
        "remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
