#!/usr/bin/env python3
"""Run the dependency-ordered R111B BG exposure-readout campaign."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import time
from typing import Any

import pandas as pd


TAG = "pricefm_stage_r111b_bg_exposure_readout_20260922"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
DEFAULT_ROOT = DATA / "campaigns" / TAG
R103 = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
FOLDS = (1, 2, 3)
INNER_FOLDS = (1, 2, 3)
ARMS = ("teacher_recent", "recursive_mean", "mixed_equal")
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


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
    if not rows:
        return
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def physical_cpu_pool(max_workers: int) -> dict[str, Any]:
    topology: dict[tuple[int, int], list[int]] = {}
    text = subprocess.check_output(["lscpu", "-p=CPU,CORE,SOCKET"], text=True)
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        cpu, core, socket = (int(value) for value in line.split(","))
        topology.setdefault((socket, core), []).append(cpu)
    active: set[int] = set()
    ps = subprocess.check_output(["ps", "-eo", "psr=,pcpu=,args="], text=True)
    for line in ps.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) < 3:
            continue
        try:
            cpu, percent = int(fields[0]), float(fields[1])
        except ValueError:
            continue
        if percent >= 20.0 and TAG not in fields[2]:
            active.add(cpu)
    busy = {key for key, cpus in topology.items() if active.intersection(cpus)}
    free = sorted(set(topology) - busy)
    selected = free[: min(int(max_workers), max(0, len(free) - 1))]
    cpus = [min(topology[key]) for key in selected]
    if not cpus:
        raise RuntimeError("no free physical CPU is available for R111B")
    return {
        "logical_cpus_online": sum(len(value) for value in topology.values()),
        "physical_cores_online": len(topology),
        "busy_logical_cpus_observed": sorted(active),
        "busy_physical_cores_observed": [list(value) for value in sorted(busy)],
        "reserved_free_physical_cores": 1,
        "selected_logical_cpus": cpus,
        "selected_physical_core_count": len(cpus),
    }


def run_command(task_id: str, command: list[str], cpu: int, log_path: Path, env: dict[str, str]) -> dict[str, Any]:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log_path.open("a") as log:
        log.write("COMMAND " + " ".join(command) + "\n")
        log.flush()
        process = subprocess.run(
            ["taskset", "-c", str(cpu), *command], stdout=log,
            stderr=subprocess.STDOUT, env=env, text=True,
        )
    return {
        "task_id": task_id, "cpu": cpu, "returncode": process.returncode,
        "elapsed_seconds": round(time.time() - started, 3), "log_path": str(log_path),
    }


def run_parallel(
    tasks: list[dict[str, Any]], cpus: list[int], workers: int, status_path: Path
) -> list[dict[str, Any]]:
    if not tasks:
        return []
    env = os.environ.copy()
    env.update({
        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
        "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
        "RCPP_PARALLEL_NUM_THREADS": "1", "BLIS_NUM_THREADS": "1",
    })
    count = min(len(tasks), len(cpus), int(workers))
    results: list[dict[str, Any]] = []
    available: queue.Queue[int] = queue.Queue()
    for cpu in cpus[:count]:
        available.put(cpu)

    def run_on_distinct_core(task: dict[str, Any]) -> dict[str, Any]:
        cpu = available.get()
        try:
            return run_command(task["task_id"], task["command"], cpu, task["log_path"], env)
        finally:
            available.put(cpu)

    with concurrent.futures.ThreadPoolExecutor(max_workers=count) as executor:
        futures = {
            executor.submit(run_on_distinct_core, task): task for task in tasks
        }
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            write_csv(status_path, sorted(results, key=lambda row: row["task_id"]))
    failures = [row for row in results if row["returncode"] != 0]
    if failures:
        raise RuntimeError("R111B phase failed: " + ", ".join(row["task_id"] for row in failures))
    return results


def valid_terminal(path: Path, status: str, contract_hash: str | None = None) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        value = json.loads(terminal_path.read_text())
        return (
            value.get("status") == status
            and value.get("test_opened") is False
            and (contract_hash is None or value.get("task_contract_sha256") == contract_hash)
        )
    except (OSError, json.JSONDecodeError):
        return False


def task_contract(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["task_contract_sha256"] = canonical_hash(result)
    return result


def r103_config(fold: int) -> dict[str, Any]:
    return json.loads((R103 / "cases" / f"r103_bg_f{fold}.json").read_text())


def common_al_contract(config: dict[str, Any], code_root: Path) -> dict[str, Any]:
    return {
        "stage": "R111B", "region": "BG", "family": "al", "tau0": 1e-4,
        "runtime_manifest": config["runtime_manifest"],
        "runtime_manifest_sha256": config["runtime_manifest_sha256"],
        "runtime_library": config["runtime_library"], "adapters": config["adapters"],
        "rhs": config["rhs"], "qdesn_vb": config["qdesn_vb"],
        "test_access_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "runner_path": str(code_root / "application/scripts/pricefm/380_run_pricefm_stage_r111b_al_readout.R"),
    }


def atom_dir(fold: int, tau: float) -> Path:
    label = str(tau).replace(".", "p")
    return (
        DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916/cases"
        / "region=BG" / f"fold={fold}" / "atoms" / f"r103_bg_f{fold}_al_{label}"
    )


def write_resolved_contract(root: Path, phase: str, value: dict[str, Any]) -> Path:
    contract = task_contract(value)
    path = root / "contracts" / phase / f"{contract['task_id']}.json"
    write_json(path, contract)
    return path


def select_arm(root: Path) -> str:
    paths = sorted((root / "runs/screen").glob("**/metric_summary.csv"))
    if len(paths) != 9:
        raise RuntimeError("R111B median screen is incomplete")
    metrics = pd.concat([pd.read_csv(path) for path in paths], ignore_index=True)
    grouped = metrics.groupby("arm", as_index=False).agg(
        mean_AQL_scaled=("AQL_scaled", "mean"),
        worst_AQL_scaled=("AQL_scaled", "max"),
        complete_holdouts=("holdout_inner_fold", "nunique"),
        all_converged=("converged", "all"),
    )
    if set(grouped.arm) != set(ARMS) or not grouped.complete_holdouts.eq(3).all() or not grouped.all_converged.all():
        raise RuntimeError("R111B median screen is not selection-complete")
    priority = {"recursive_mean": 0, "mixed_equal": 1, "teacher_recent": 2}
    grouped["priority"] = grouped.arm.map(priority)
    selected = grouped.sort_values(
        ["mean_AQL_scaled", "worst_AQL_scaled", "priority"], kind="mergesort"
    ).iloc[0]
    metrics.to_csv(root / "median_arm_screen_metrics.csv", index=False)
    grouped.drop(columns="priority").to_csv(root / "median_arm_screen_summary.csv", index=False)
    value = {
        "stage": "R111B", "selected_arm": str(selected.arm),
        "mean_AQL_scaled": float(selected.mean_AQL_scaled),
        "worst_AQL_scaled": float(selected.worst_AQL_scaled),
        "selection_split": "fold1_training_crossfit_only",
        "selection_quantile": 0.5, "test_opened": False,
    }
    write_json(root / "selected_exposure_arm.json", value)
    return str(selected.arm)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--workers", type=int, default=30)
    args = parser.parse_args()
    root = args.campaign_root.resolve()
    code_root = args.code_root.resolve()
    campaign = json.loads((root / "campaign_contract.json").read_text())
    if (
        campaign.get("stage") != "R111B"
        or campaign.get("task_count") != 51
        or campaign.get("model_fit_tasks") != 39
        or campaign.get("test_access_authorized") is not False
        or campaign.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("invalid R111B campaign contract")
    head = subprocess.check_output(["git", "-C", str(code_root), "rev-parse", "HEAD"], text=True).strip()
    if head != campaign["head"]:
        raise RuntimeError("R111B code HEAD differs from its frozen campaign contract")
    for row in csv.DictReader((root / "source_manifest.csv").open()):
        path = Path(row["path"])
        if not path.is_file() or sha256_file(path) != row["sha256"]:
            raise RuntimeError(f"R111B frozen source changed: {path}")

    resources = physical_cpu_pool(args.workers)
    resources["observed_at_epoch"] = time.time()
    write_json(root / "resource_allocation.json", resources)
    cpus = resources["selected_logical_cpus"]

    driver_tasks = []
    for row in csv.DictReader((root / "driver_task_manifest.csv").open()):
        contract = json.loads(Path(row["contract_path"]).read_text())
        output = Path(row["output_dir"])
        if valid_terminal(output, "completed_r111b_crossfit_driver", contract["task_contract_sha256"]):
            continue
        driver_tasks.append({
            "task_id": row["task_id"],
            "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/378_run_pricefm_stage_r111b_crossfit_driver.R"), "--contract", row["contract_path"]],
            "log_path": root / "logs/drivers" / f"{row['task_id']}.log",
        })
    run_parallel(driver_tasks, cpus, args.workers, root / "driver_launch_status.csv")

    design_tasks = []
    for row in csv.DictReader((root / "design_task_manifest.csv").open()):
        contract = json.loads(Path(row["contract_path"]).read_text())
        output = Path(row["output_dir"])
        if valid_terminal(output, "completed_r111b_exposure_design", contract["task_contract_sha256"]):
            continue
        design_tasks.append({
            "task_id": row["task_id"],
            "command": [sys.executable, str(code_root / "application/scripts/pricefm/379_build_pricefm_stage_r111b_exposure_design.py"), "--contract", row["contract_path"]],
            "log_path": root / "logs/designs" / f"{row['task_id']}.log",
        })
    run_parallel(design_tasks, cpus, args.workers, root / "design_launch_status.csv")

    screen_tasks = []
    screen_rows = []
    config = r103_config(1)
    common = common_al_contract(config, code_root)
    all_blocks = [str(root / "runs/designs" / "fold=1" / f"inner={inner}") for inner in INNER_FOLDS]
    for arm in ARMS:
        for holdout in INNER_FOLDS:
            task_id = f"screen__{arm}__holdout{holdout}"
            output = root / "runs/screen" / arm / f"holdout={holdout}"
            training = [path for inner, path in zip(INNER_FOLDS, all_blocks) if inner != holdout]
            posterior_target = canonical_hash({
                "family": "al", "tau": 0.5, "tau0": 1e-4, "arm": arm,
                "training_blocks": [sha256_file(Path(path) / "terminal.json") for path in training],
                "rhs": config["rhs"], "prior_sigma": config["qdesn_vb"]["prior_sigma"],
            })
            path = write_resolved_contract(root, "screen", common | {
                "task_id": task_id, "phase": "median_arm_screen", "outer_fold": 1,
                "holdout_inner_fold": holdout, "arm": arm, "tau": 0.5,
                "training_block_dirs": training,
                "evaluation_block_dir": all_blocks[holdout - 1],
                "initializer_policy": "neutral_training_only", "output_dir": str(output),
                "posterior_target_sha256": posterior_target,
                "selection_split": "fold1_training_crossfit_only",
                "seed": 2026092800 + 10 * ARMS.index(arm) + holdout,
            })
            contract = json.loads(path.read_text())
            screen_rows.append({
                "task_id": task_id, "arm": arm, "holdout_inner_fold": holdout,
                "contract_path": str(path), "output_dir": str(output),
                "posterior_target_sha256": posterior_target,
            })
            if not valid_terminal(output, "completed_r111b_al_readout", contract["task_contract_sha256"]):
                screen_tasks.append({
                    "task_id": task_id,
                    "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/380_run_pricefm_stage_r111b_al_readout.R"), "--contract", str(path)],
                    "log_path": root / "logs/screen" / f"{task_id}.log",
                })
    write_csv(root / "screen_resolved_manifest.csv", screen_rows)
    run_parallel(screen_tasks, cpus, args.workers, root / "screen_launch_status.csv")
    arm = select_arm(root)

    final_tasks = []
    final_rows = []
    for fold in FOLDS:
        config = r103_config(fold)
        common = common_al_contract(config, code_root)
        blocks = [str(root / "runs/designs" / f"fold={fold}" / f"inner={inner}") for inner in INNER_FOLDS]
        for tau in QUANTILES:
            label = str(tau).replace(".", "p")
            task_id = f"final__BG__fold{fold}__tau{label}"
            output = root / "runs/final" / f"fold={fold}" / f"tau={label}"
            posterior_target = canonical_hash({
                "family": "al", "tau": tau, "tau0": 1e-4, "arm": arm,
                "training_blocks": [sha256_file(Path(path) / "terminal.json") for path in blocks],
                "rhs": config["rhs"], "prior_sigma": config["qdesn_vb"]["prior_sigma"],
            })
            path = write_resolved_contract(root, "final", common | {
                "task_id": task_id, "phase": "final_al_readout", "outer_fold": fold,
                "arm": arm, "tau": tau, "training_block_dirs": blocks,
                "initializer_policy": "matching_R103_AL_same_fold_tau",
                "initializer_dir": str(atom_dir(fold, tau)), "output_dir": str(output),
                "posterior_target_sha256": posterior_target,
                "selection_split": "frozen_fold1_training_arm_outer_fold_training_only",
                "seed": 2026092900 + 100 * fold + QUANTILES.index(tau),
            })
            contract = json.loads(path.read_text())
            final_rows.append({
                "task_id": task_id, "outer_fold": fold, "tau": tau, "arm": arm,
                "contract_path": str(path), "output_dir": str(output),
                "posterior_target_sha256": posterior_target,
            })
            if not valid_terminal(output, "completed_r111b_al_readout", contract["task_contract_sha256"]):
                final_tasks.append({
                    "task_id": task_id,
                    "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/380_run_pricefm_stage_r111b_al_readout.R"), "--contract", str(path)],
                    "log_path": root / "logs/final" / f"{task_id}.log",
                })
    write_csv(root / "final_resolved_manifest.csv", final_rows)
    run_parallel(final_tasks, cpus, args.workers, root / "final_launch_status.csv")

    replay_tasks = []
    for fold in FOLDS:
        output = root / "replay" / f"fold={fold}"
        if valid_terminal(output, "completed_r111b_bg_replay_case"):
            continue
        replay_tasks.append({
            "task_id": f"replay__BG__fold{fold}",
            "command": [sys.executable, str(code_root / "application/scripts/pricefm/381_replay_closeout_pricefm_stage_r111b.py"), "--campaign-root", str(root), "--mode", "case", "--fold", str(fold)],
            "log_path": root / "logs/replay" / f"fold{fold}.log",
        })
    run_parallel(replay_tasks, cpus, args.workers, root / "replay_launch_status.csv")
    subprocess.run([
        sys.executable, str(code_root / "application/scripts/pricefm/381_replay_closeout_pricefm_stage_r111b.py"),
        "--campaign-root", str(root), "--mode", "finalize",
    ], check=True)
    write_json(root / "orchestrator_terminal.json", {
        "stage": "R111B", "status": "completed_r111b_orchestration",
        "task_count": 51, "model_fit_tasks": 39, "crossfit_driver_tasks": 9,
        "exposure_design_tasks": 9, "median_screen_tasks": 9,
        "final_quantile_tasks": 21, "replay_tasks": 3,
        "selected_arm": arm, "selected_physical_core_count": len(cpus),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    })


if __name__ == "__main__":
    main()
