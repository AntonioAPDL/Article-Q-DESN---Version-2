#!/usr/bin/env python3
"""Run one host's resumable R112B Normal Ridge-to-RHS extension."""

from __future__ import annotations

import argparse
import copy
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sys
import threading
import time
from typing import Any

import pandas as pd
import yaml


STAGE = "R112B"
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file
from pricefm_region_frozen_contract import atomic_write_json, git_identity


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
PREP = DATA / "launch_prep/pricefm_stage_r112a_normal_extension_prep_20260922"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r112b_normal_extension_20260922"
MATERIALIZE = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
RUN_MODEL = SCRIPT_DIR / "10_run_desn_model_full.py"
BUILD_WINDOWS = SCRIPT_DIR / "05_build_windows.py"
APPROVAL = "RUN_PRICEFM_R112B_NORMAL_EXTENSION"
HOST_WORKER_CEILINGS = {"muscat": 25, "jerez": 50}
GRID_BLOCK = "pricefm_desn_experiment_grid"


def load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RUNNER = load_module(
    SCRIPT_DIR / "333_orchestrate_pricefm_stage_r100_targeted_normal_screen.py",
    "pricefm_r100_runner",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--host", choices=sorted(HOST_WORKER_CEILINGS), required=True)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--workers", type=int, required=True)
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--approval-token", required=True)
    p.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    p.add_argument("--minimum-free-gib", type=float, default=250.0)
    p.add_argument("--minimum-memory-gib", type=float, default=64.0)
    p.add_argument("--preflight-only", action="store_true")
    return p


def host_root(campaign: Path, host: str) -> Path:
    return campaign.resolve() / "hosts" / host


def physical_inventory(cpus: list[int]) -> dict[str, Any]:
    cores: dict[tuple[int, int], list[int]] = {}
    for cpu in cpus:
        key = RUNNER.physical_core(cpu)
        cores.setdefault(key, []).append(cpu)
    return {
        "physical_core_count": len(cores),
        "logical_cpu_count": len(cpus),
        "logical_siblings_per_selected_core": {
            f"package{package}_core{core}": sorted(values)
            for (package, core), values in sorted(cores.items())
        },
    }


def valid_marker(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text())
        return (
            data.get("stage") == STAGE
            and data.get("status") == "completed_compacted"
            and data.get("test_opened") is False
            and all(
                Path(row["path"]).is_file()
                and sha256_file(row["path"]) == row["sha256"]
                for row in data.get("retained", [])
            )
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def record(path: Path, role: str) -> dict[str, Any]:
    return {
        "role": role,
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def compact(row: Any, region: str, folds: list[int]) -> None:
    run_dir = Path(row.run_dir)
    retained: list[dict[str, Any]] = []
    for fold in folds:
        cell = run_dir / f"cells/region={region}/fold={fold}"
        model = cell / "model"
        metric = model / "metric_summary.csv"
        method = model / "model_method_summary.csv"
        for path in (metric, method):
            if not path.is_file() or path.stat().st_size == 0:
                raise RuntimeError(f"missing R112B screening result: {path}")
        metrics = pd.read_csv(metric)
        if metrics.split.astype(str).str.lower().eq("test").any():
            raise RuntimeError(f"test row entered R112B: {metric}")
        retained.extend([
            record(metric, f"fold{fold}_metric"),
            record(method, f"fold{fold}_method"),
        ])
        adapter = cell / "adapter"
        if adapter.exists():
            shutil.rmtree(adapter)
        for path in list(model.iterdir()):
            if path.name not in {"metric_summary.csv", "model_method_summary.csv"}:
                shutil.rmtree(path) if path.is_dir() else path.unlink()
    atomic_write_json(run_dir / "r112b_compaction_terminal.json", {
        "stage": STAGE,
        "status": "completed_compacted",
        "experiment_id": str(row.id),
        "region": region,
        "folds": folds,
        "retained": retained,
        "binary_model_artifacts_retained": False,
        "test_opened": False,
    })


def run_queue(
    manifest: pd.DataFrame,
    cpus: list[int],
    code_root: Path,
    campaign: Path,
    phase: str,
    minimum_free_gib: float,
    minimum_memory_gib: float,
) -> dict[str, int]:
    tasks = []
    for row in manifest.itertuples(index=False):
        region = str(row.campaign_region)
        folds = [int(value) for value in json.loads(row.folds)]
        marker = Path(row.run_dir) / "r112b_compaction_terminal.json"
        if not valid_marker(marker):
            tasks.append((row, region, folds))
    completed_before = int(len(manifest) - len(tasks))
    state_lock = threading.Lock()
    progress = {"complete": completed_before, "failed": 0}
    buckets = [[] for _ in cpus]
    for index, task in enumerate(tasks):
        buckets[index % len(cpus)].append(task)

    def worker(cpu: int, bucket: list[Any]) -> tuple[int, int]:
        local_complete = 0
        local_failed = 0
        for row, region, folds in bucket:
            log = campaign / f"logs/{phase}/{region}/{row.id}.log"
            try:
                RUNNER.ensure_runtime_capacity(minimum_free_gib, minimum_memory_gib)
                RUNNER.command([
                    PYTHON,
                    RUN_MODEL,
                    "--config", row.full_config,
                    "--jobs", "1",
                    "--resume", "true",
                    "--force", "false",
                    "--dry-run", "false",
                    "--regions", region,
                    "--folds", ",".join(map(str, folds)),
                ], cwd=code_root, log=log, cpu=cpu)
                compact(row, region, folds)
                local_complete += 1
            except Exception as error:
                local_failed += 1
                run_dir = Path(row.run_dir)
                run_dir.mkdir(parents=True, exist_ok=True)
                atomic_write_json(run_dir / "r112b_failure_terminal.json", {
                    "stage": STAGE,
                    "status": "failed_closed",
                    "experiment_id": str(row.id),
                    "region": region,
                    "error": repr(error),
                    "log": str(log),
                })
            with state_lock:
                if valid_marker(Path(row.run_dir) / "r112b_compaction_terminal.json"):
                    progress["complete"] += 1
                else:
                    progress["failed"] += 1
                atomic_write_json(campaign / f"{phase}_progress.json", {
                    "stage": STAGE,
                    "phase": phase,
                    "completed_before_resume": completed_before,
                    "complete": progress["complete"],
                    "failed": progress["failed"],
                    "total": len(manifest),
                    "updated_at_epoch": time.time(),
                })
        return local_complete, local_failed

    failures = 0
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [
            pool.submit(worker, cpu, bucket)
            for cpu, bucket in zip(cpus, buckets)
            if bucket
        ]
        for future in as_completed(futures):
            _, failed = future.result()
            failures += failed
    actual = sum(
        valid_marker(Path(path) / "r112b_compaction_terminal.json")
        for path in manifest.run_dir
    )
    return {"complete": int(actual), "failed": int(failures), "total": int(len(manifest))}


def prepare_rhs(launch: pd.DataFrame, code_root: Path, campaign: Path) -> pd.DataFrame:
    advance = load_module(
        SCRIPT_DIR / "292_advance_pricefm_stage_r93_ridge_to_rhs.py",
        "pricefm_r112b_ridge_reader",
    )
    manifests = []
    for launch_row in launch.itertuples(index=False):
        region = str(launch_row.region)
        candidates = pd.read_csv(launch_row.candidate_manifest)
        ridge_manifest = pd.read_csv(Path(launch_row.generated_root) / "manifest.csv")
        cells, _ = advance.collect_ridge_results(
            candidates, ridge_manifest, [101, 102, 103], region,
        )
        ranked = advance.rank_candidates(candidates, cells)
        selected = ranked.head(int(launch_row.ridge_top_k)).copy()
        if len(selected) != 30:
            raise RuntimeError(f"R112B expected Ridge top 30 for {region}")
        closeout = campaign / f"regions/{region}/ridge_closeout"
        closeout.mkdir(parents=True, exist_ok=True)
        cells.to_csv(closeout / "pricefm_stage_r112b_ridge_cell_metrics.csv", index=False)
        ranked.to_csv(closeout / "pricefm_stage_r112b_ridge_ranking.csv", index=False)
        selected.to_csv(closeout / "pricefm_stage_r112b_ridge_top30.csv", index=False)

        source_grid = yaml.safe_load(Path(launch_row.grid_path).read_text())
        experiments = {
            str(item["id"]): item
            for item in source_grid[GRID_BLOCK]["experiments"]
        }
        base_data = yaml.safe_load(
            Path(source_grid[GRID_BLOCK]["base"]["data_config"]).read_text()
        )
        base_full = yaml.safe_load(
            Path(source_grid[GRID_BLOCK]["base"]["full_config"]).read_text()
        )
        rhs_prep = campaign / f"regions/{region}/rhs_prep"
        rhs_generated = campaign / f"regions/{region}/rhs_generated"
        rhs_runs = campaign / f"regions/{region}/rhs_runs"
        rhs_prep.mkdir(parents=True, exist_ok=True)
        data_path = rhs_prep / "data.yaml"
        full_path = rhs_prep / "full.yaml"
        with data_path.open("w") as handle:
            yaml.safe_dump(base_data, handle, sort_keys=False)
        full = base_full["pricefm_desn_full"]
        full["data_config"] = str(data_path)
        full["normal"].update({
            "enabled": True,
            "prior_types": ["rhs_ns"],
            "predictive_quantile_mode": "analytic_normal",
        })
        full["qdesn_vb"]["enabled"] = False
        with full_path.open("w") as handle:
            yaml.safe_dump(base_full, handle, sort_keys=False)

        arms = []
        rhs_experiments = []
        for item in selected.itertuples(index=False):
            tau_ref = RUNNER.tau_reference(
                float(launch_row.r98_tau0),
                int(launch_row.r98_observed_readout_features),
                int(item.n_state_features),
            )
            for multiplier in (0.25, 1.0, 4.0):
                tau0 = tau_ref * multiplier
                fingerprint = hashlib.sha256(
                    f"{item.candidate_id}|{tau0:.17g}".encode()
                ).hexdigest()
                experiment_id = (
                    f"r112b_{region.lower().replace('_', '')}_rhs_"
                    f"r{int(item.ridge_rank):02d}_m{multiplier:g}_{fingerprint[:10]}"
                )
                experiment = copy.deepcopy(experiments[str(item.candidate_id)])
                experiment.update({
                    "id": experiment_id,
                    "stage": "pricefm_stage_r112b_normal_extension_rhs",
                    "tau0": tau0,
                    "normal": {
                        "enabled": True,
                        "prior_types": ["rhs_ns"],
                        "predictive_quantile_mode": "analytic_normal",
                    },
                    "qdesn_vb": {"enabled": False},
                    "exact_equivalence": {"enabled": False},
                    "stage_r112b_parent_ridge_candidate_id": str(item.candidate_id),
                    "stage_r112b_ridge_rank": int(item.ridge_rank),
                    "stage_r112b_rhs_tau0_phase": "design_size_adjusted_coarse",
                    "rationale": "R112B all-region Normal RHS selection on inner validation only.",
                })
                rhs_experiments.append(experiment)
                arms.append({
                    "experiment_id": experiment_id,
                    "parent_ridge_candidate_id": item.candidate_id,
                    "region": region,
                    "ridge_rank": int(item.ridge_rank),
                    "feature_policy": item.feature_policy,
                    "lag_window": int(item.lag_window),
                    "depth": int(item.depth),
                    "units": item.units,
                    "alpha": float(item.alpha),
                    "rho": float(item.rho),
                    "input_scale": float(item.input_scale),
                    "state_output": item.state_output,
                    "seed": int(item.seed),
                    "candidate_readout_features": int(item.n_state_features),
                    "r98_readout_features": int(launch_row.r98_observed_readout_features),
                    "r98_tau0": float(launch_row.r98_tau0),
                    "tau_multiplier": multiplier,
                    "tau_ref": tau_ref,
                    "tau0": tau0,
                    "test_access_authorized": False,
                })
        grid = copy.deepcopy(source_grid)
        block = grid[GRID_BLOCK]
        block["grid_id"] = f"pricefm_stage_r112b_normal_rhs_{region.lower()}_20260922"
        block["purpose"] = "Ridge-top30 dimension-adjusted Normal RHS screen; train/validation only."
        block["base"] = {
            "data_config": str(data_path),
            "full_config": str(full_path),
            "generated_root": str(rhs_generated),
            "run_root": str(rhs_runs),
        }
        block["fixed"]["normal"] = {
            "enabled": True,
            "prior_types": ["rhs_ns"],
            "predictive_quantile_mode": "analytic_normal",
        }
        block["fixed"]["qdesn_vb"] = {"enabled": False}
        block["experiments"] = rhs_experiments
        block["experiment_blocks"] = []
        grid_path = rhs_prep / "pricefm_stage_r112b_rhs_grid.yaml"
        with grid_path.open("w") as handle:
            yaml.safe_dump(grid, handle, sort_keys=False)
        pd.DataFrame(arms).to_csv(
            rhs_prep / "pricefm_stage_r112b_rhs_manifest.csv", index=False
        )
        manifest_path = rhs_generated / "manifest.csv"
        if not manifest_path.is_file():
            RUNNER.command([
                PYTHON,
                MATERIALIZE,
                "--grid-config", grid_path,
                "--write",
                "--output-root", rhs_generated,
            ], cwd=code_root, log=campaign / f"logs/materialize_rhs_{region}.log")
        manifest = pd.read_csv(manifest_path)
        manifest["campaign_region"] = region
        manifests.append(manifest)
    return pd.concat(manifests, ignore_index=True)


def close_rhs(launch: pd.DataFrame, rhs_manifest: pd.DataFrame, campaign: Path, host: str) -> dict[str, Any]:
    winners = []
    failures = []
    for launch_row in launch.itertuples(index=False):
        region = str(launch_row.region)
        rows = rhs_manifest[rhs_manifest.campaign_region.eq(region)]
        arms = pd.read_csv(
            campaign / f"regions/{region}/rhs_prep/pricefm_stage_r112b_rhs_manifest.csv"
        )
        metrics = []
        for row in rows.itertuples(index=False):
            fold_values = []
            converged = True
            n_features = 0
            for fold in (101, 102, 103):
                model = Path(row.run_dir) / f"cells/region={region}/fold={fold}/model"
                metric = pd.read_csv(model / "metric_summary.csv")
                method = pd.read_csv(model / "model_method_summary.csv")
                selected = metric[
                    metric.method_id.eq("normal_rhs_ns")
                    & metric.split.eq("val")
                    & metric.unit.eq("original")
                ]
                fitted = method[method.method_id.eq("normal_rhs_ns")]
                if len(selected) != 1 or len(fitted) != 1:
                    converged = False
                    break
                value = float(selected.iloc[0].AQL)
                converged = (
                    converged
                    and str(fitted.iloc[0].converged).lower() in {"true", "1"}
                    and math.isfinite(value)
                )
                fold_values.append(value)
                n_features = max(n_features, int(fitted.iloc[0].n_features))
            metrics.append({
                "experiment_id": str(row.id),
                "region": region,
                "median_validation_AQL": float(pd.Series(fold_values).median()) if fold_values else math.nan,
                "max_validation_AQL": max(fold_values) if fold_values else math.nan,
                "sd_validation_AQL": float(pd.Series(fold_values).std()) if len(fold_values) == 3 else math.nan,
                "n_features": n_features,
                "n_inner_folds": len(fold_values),
                "converged": converged,
            })
        ranked = pd.DataFrame(metrics).merge(
            arms, on=["experiment_id", "region"], validate="one_to_one"
        )
        ranked["eligible"] = (
            ranked.converged
            & ranked.n_inner_folds.eq(3)
            & ranked.median_validation_AQL.map(math.isfinite)
        )
        ranked = ranked.sort_values(
            [
                "eligible", "median_validation_AQL", "max_validation_AQL",
                "sd_validation_AQL", "n_features", "experiment_id",
            ],
            ascending=[False, True, True, True, True, True],
            kind="stable",
        )
        ranked.insert(0, "rhs_rank", range(1, len(ranked) + 1))
        closeout = campaign / f"regions/{region}/rhs_closeout"
        closeout.mkdir(parents=True, exist_ok=True)
        ranking_path = closeout / "pricefm_stage_r112b_rhs_ranking.csv"
        ranked.to_csv(ranking_path, index=False)
        eligible = ranked[ranked.eligible]
        if eligible.empty:
            failures.append(region)
            continue
        winner = eligible.iloc[0].to_dict()
        winner.update({
            "stage": STAGE,
            "status": "provisional_normal_winner_frozen",
            "host": host,
            "selection_uses_outer_validation": False,
            "selection_uses_test": False,
            "quantile_fit_authorized": False,
            "test_scoring_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "ranking_path": str(ranking_path.resolve()),
            "ranking_sha256": sha256_file(ranking_path),
        })
        contract = closeout / "pricefm_stage_r112b_frozen_normal_contract.json"
        serializable = {
            key: (value.item() if hasattr(value, "item") else value)
            for key, value in winner.items()
        }
        atomic_write_json(contract, serializable)
        winners.append({
            "region": region,
            "host": host,
            "contract": str(contract.resolve()),
            "contract_sha256": sha256_file(contract),
            "experiment_id": winner["experiment_id"],
            "validation_AQL": winner["median_validation_AQL"],
            "tau0": winner["tau0"],
        })
    winners_path = campaign / f"pricefm_stage_r112b_{host}_normal_winners.csv"
    pd.DataFrame(winners).to_csv(winners_path, index=False)
    terminal = {
        "stage": STAGE,
        "status": "completed_host_normal_winners_frozen" if not failures else "completed_with_region_failures",
        "host": host,
        "regions_expected": len(launch),
        "regions_complete": len(winners),
        "regions_failed": failures,
        "winners_path": str(winners_path.resolve()),
        "winners_sha256": sha256_file(winners_path),
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_write_json(campaign / "host_terminal.json", terminal)
    return terminal


def verify_hash_rows(frame: pd.DataFrame) -> None:
    for row in frame.itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError(f"R112B source changed: {path}")


def preflight(args: argparse.Namespace) -> tuple[list[int], pd.DataFrame, Path, dict[str, Any]]:
    if args.approval_token != APPROVAL:
        raise RuntimeError(f"R112B requires --approval-token {APPROVAL}")
    cpus = RUNNER.parse_cpus(args.cpu_list)
    ceiling = HOST_WORKER_CEILINGS[args.host]
    if args.workers != len(cpus) or not 1 <= args.workers <= ceiling:
        raise RuntimeError(
            f"R112B {args.host} requires one distinct CPU per worker and at most {ceiling} workers"
        )
    identity = git_identity(args.code_root.resolve())
    if (
        not identity.clean
        or identity.head != identity.upstream_head
        or not identity.branch.startswith("work/pricefm-")
    ):
        raise RuntimeError("R112B requires a clean synchronized PriceFM task branch")
    summary = json.loads((args.prep_dir / "summary.json").read_text())
    if (
        summary.get("stage") != "R112A"
        or summary.get("status") != "completed_launch_prep_not_launched"
        or summary.get("head") != identity.head
        or summary.get("selection_uses_test") is not False
        or summary.get("launch_started") is not False
    ):
        raise RuntimeError("R112B preparation identity or contract changed")
    for row in summary.get("outputs", []):
        path = Path(row["path"])
        if not path.is_file() or sha256_file(path) != row["sha256"]:
            raise RuntimeError(f"R112B prepared output changed: {path}")
    verify_hash_rows(pd.read_csv(args.prep_dir / "source_manifest.csv"))
    control = json.loads((args.prep_dir / "pricefm_stage_r112a_launch_control.json").read_text())
    if (
        control.get("approval_token_required_for_r112b") != APPROVAL
        or control.get("launch_authorized") is not False
        or control.get("selection_uses_test") is not False
        or control.get("runtime_cpu_preflight_required") is not True
    ):
        raise RuntimeError("R112B launch-control contract changed")
    all_launch = pd.read_csv(
        args.prep_dir / "pricefm_stage_r112a_normal_extension_launch_manifest.csv"
    )
    launch = all_launch[all_launch.host.eq(args.host)].copy()
    expected = 14 if args.host == "jerez" else 7
    if (
        len(launch) != expected
        or launch.region.nunique() != expected
        or not launch.candidate_count.eq(240).all()
        or launch.test_access_authorized.any()
        or launch.launch_authorized.any()
    ):
        raise RuntimeError(f"R112B {args.host} launch subset changed")
    for row in launch.itertuples(index=False):
        if sha256_file(Path(row.grid_path)) != row.grid_sha256:
            raise RuntimeError(f"R112B grid changed: {row.grid_path}")
        if sha256_file(Path(row.candidate_manifest)) != row.candidate_manifest_sha256:
            raise RuntimeError(f"R112B candidate manifest changed: {row.candidate_manifest}")
    first = RUNNER.cpu_snapshot()
    second = RUNNER.cpu_snapshot()
    usage = {cpu: max(first[cpu], second[cpu]) for cpu in cpus}
    if any(value > args.maximum_cpu_percent for value in usage.values()):
        busy = {cpu: value for cpu, value in usage.items() if value > args.maximum_cpu_percent}
        raise RuntimeError(f"selected R112B CPUs are busy: {busy}")
    resources = RUNNER.ensure_runtime_capacity(
        args.minimum_free_gib, args.minimum_memory_gib
    )
    campaign = host_root(args.campaign_root, args.host)
    campaign.mkdir(parents=True, exist_ok=True)
    audit = {
        "stage": STAGE,
        "status": "preflight_passed_not_launched" if args.preflight_only else "preflight_passed",
        "host": args.host,
        "workers": args.workers,
        "logical_cpus": cpus,
        **physical_inventory(cpus),
        "selected_cpu_percent": usage,
        **resources,
        "git_identity": identity.to_dict(),
        "regions": len(launch),
        "ridge_candidates": int(launch.candidate_count.sum()),
        "selection_uses_test": False,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_write_json(campaign / "launch_preflight.json", audit)
    return cpus, launch, campaign, audit


def run(args: argparse.Namespace) -> dict[str, Any]:
    cpus, launch, campaign, audit = preflight(args)
    if args.preflight_only:
        return audit
    code_root = args.code_root.resolve()
    ridge = RUNNER.materialize_all(launch, code_root, campaign)
    expected_ridge = len(launch) * 240
    if len(ridge) != expected_ridge or ridge.id.duplicated().any():
        raise RuntimeError("R112B Ridge materialization is incomplete")
    RUNNER.verify_or_build_windows(ridge, code_root, campaign)
    ridge_result = run_queue(
        ridge, cpus, code_root, campaign, "ridge",
        args.minimum_free_gib, args.minimum_memory_gib,
    )
    if ridge_result["complete"] != ridge_result["total"]:
        terminal = {"stage": STAGE, "status": "failed_closed_ridge", **ridge_result}
        atomic_write_json(campaign / "host_terminal.json", terminal)
        raise RuntimeError(f"R112B Ridge queue incomplete: {ridge_result}")
    rhs = prepare_rhs(launch, code_root, campaign)
    expected_rhs = len(launch) * 30 * 3
    if len(rhs) != expected_rhs or rhs.id.duplicated().any():
        raise RuntimeError("R112B RHS materialization is incomplete")
    rhs_result = run_queue(
        rhs, cpus, code_root, campaign, "rhs",
        args.minimum_free_gib, args.minimum_memory_gib,
    )
    if rhs_result["complete"] != rhs_result["total"]:
        terminal = {"stage": STAGE, "status": "failed_closed_rhs", **rhs_result}
        atomic_write_json(campaign / "host_terminal.json", terminal)
        raise RuntimeError(f"R112B RHS queue incomplete: {rhs_result}")
    closeout = close_rhs(launch, rhs, campaign, args.host)
    return {
        "stage": STAGE,
        "status": "controller_complete",
        "host": args.host,
        "preflight": audit,
        "ridge": ridge_result,
        "rhs": rhs_result,
        "closeout": closeout,
    }


def main() -> int:
    args = parser().parse_args()
    campaign = host_root(args.campaign_root, args.host)
    campaign.mkdir(parents=True, exist_ok=True)
    lock = (campaign / "controller.lock").open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError(f"another R112B controller owns {args.host}") from error
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
        return 0
    except Exception as error:
        failure = {
            "stage": STAGE,
            "status": "failed_closed",
            "host": args.host,
            "error": repr(error),
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
        }
        atomic_write_json(campaign / "controller_failure.json", failure)
        terminal = campaign / "host_terminal.json"
        if not terminal.is_file():
            atomic_write_json(terminal, failure)
        raise
    finally:
        lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
