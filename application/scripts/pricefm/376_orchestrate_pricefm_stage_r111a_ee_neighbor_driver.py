#!/usr/bin/env python3
"""Run the dependency-ordered R111A FI/LV driver and EE replay campaign."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pandas as pd


TAG = "pricefm_stage_r111a_ee_neighbor_driver_20260921"
DEFAULT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns") / TAG
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
REGIONS = ("FI", "LV")
INNER_FOLDS = (1, 2, 3)
FOLDS = (1, 2, 3)


def sha256_json(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def physical_cpu_pool(max_workers: int) -> dict:
    topology: dict[tuple[int, int], list[int]] = {}
    text = subprocess.check_output(["lscpu", "-p=CPU,CORE,SOCKET"], text=True)
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        cpu, core, socket = (int(value) for value in line.split(","))
        topology.setdefault((socket, core), []).append(cpu)

    active_cpus: set[int] = set()
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
            active_cpus.add(cpu)
    busy_keys = {key for key, cpus in topology.items() if active_cpus.intersection(cpus)}
    free_keys = sorted(set(topology) - busy_keys)
    # Preserve one otherwise-free physical core for the OS and unrelated work.
    usable = max(0, len(free_keys) - 1)
    selected_keys = free_keys[: min(int(max_workers), usable)]
    cpus = [min(topology[key]) for key in selected_keys]
    if not cpus:
        raise RuntimeError("no free physical CPU is available for R111A")
    return {
        "logical_cpus_online": sum(len(value) for value in topology.values()),
        "physical_cores_online": len(topology),
        "busy_logical_cpus_observed": sorted(active_cpus),
        "busy_physical_cores_observed": [list(value) for value in sorted(busy_keys)],
        "reserved_free_physical_cores": 1,
        "selected_logical_cpus": cpus,
        "selected_physical_core_count": len(cpus),
    }


def valid_terminal(output_dir: Path, expected_hash: str | None = None) -> bool:
    path = output_dir / "terminal.json"
    if not path.is_file():
        return False
    try:
        terminal = json.loads(path.read_text())
    except Exception:
        return False
    if terminal.get("status") != "completed_r111a_direct_case" or terminal.get("test_opened") is not False:
        return False
    return expected_hash is None or terminal.get("task_contract_sha256") == expected_hash


def run_command(task_id: str, command: list[str], cpu: int, log_path: Path, env: dict) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log_path.open("a") as log:
        log.write("COMMAND " + " ".join(command) + "\n")
        log.flush()
        process = subprocess.run(
            ["taskset", "-c", str(cpu), *command],
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            text=True,
        )
    return {
        "task_id": task_id,
        "cpu": cpu,
        "returncode": process.returncode,
        "elapsed_seconds": round(time.time() - started, 3),
        "log_path": str(log_path),
    }


def run_parallel(tasks: list[dict], cpus: list[int], max_workers: int, status_path: Path) -> list[dict]:
    env = os.environ.copy()
    env.update({
        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
        "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
    })
    workers = min(len(tasks), len(cpus), int(max_workers))
    if workers < 1:
        return []
    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {}
        for index, task in enumerate(tasks):
            cpu = cpus[index % workers]
            future = executor.submit(
                run_command, task["task_id"], task["command"], cpu, task["log_path"], env
            )
            futures[future] = task
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            write_csv(status_path, sorted(results, key=lambda row: row["task_id"]))
    failures = [row for row in results if row["returncode"] != 0]
    if failures:
        raise RuntimeError("R111A phase failed: " + ", ".join(row["task_id"] for row in failures))
    return results


def mean_metrics(root: Path, phase: str) -> pd.DataFrame:
    paths = sorted((root / "runs" / phase).glob("**/metric_summary.csv"))
    if not paths:
        raise RuntimeError(f"no metrics found for {phase}")
    return pd.concat([pd.read_csv(path) for path in paths], ignore_index=True)


def select_ridge(metrics: pd.DataFrame) -> list[dict]:
    grouped = metrics.groupby(["region", "readout"], as_index=False).agg(
        mean_inner_AQL_scaled=("AQL_scaled", "mean"),
        worst_inner_AQL_scaled=("AQL_scaled", "max"),
        complete_inner_folds=("inner_fold", "nunique"),
    )
    if set(grouped.region) != set(REGIONS) or not (grouped.complete_inner_folds == 3).all():
        raise RuntimeError("incomplete Ridge inner-fold surface")
    priority = {"shared": 0, "block24": 1}
    grouped["priority"] = grouped.readout.map(priority)
    selected = grouped.sort_values(
        ["region", "mean_inner_AQL_scaled", "worst_inner_AQL_scaled", "priority"]
    ).drop_duplicates("region", keep="first")
    return selected.drop(columns="priority").to_dict("records")


def select_final(ridge: pd.DataFrame, rhs: pd.DataFrame, ridge_selection: list[dict]) -> list[dict]:
    selected_readout = {row["region"]: row["readout"] for row in ridge_selection}
    candidates: list[dict] = []
    for region in REGIONS:
        readout = selected_readout[region]
        ridge_rows = ridge[(ridge.region == region) & (ridge.readout == readout)]
        candidates.append({
            "region": region, "readout": readout, "prior_type": "scaled_ridge", "tau0": None,
            "mean_inner_AQL_scaled": float(ridge_rows.AQL_scaled.mean()),
            "worst_inner_AQL_scaled": float(ridge_rows.AQL_scaled.max()),
            "complete_inner_folds": int(ridge_rows.inner_fold.nunique()),
            "priority": 0,
        })
        for tau0, frame in rhs[rhs.region == region].groupby("tau0"):
            candidates.append({
                "region": region, "readout": readout, "prior_type": "rhs_ns", "tau0": float(tau0),
                "mean_inner_AQL_scaled": float(frame.AQL_scaled.mean()),
                "worst_inner_AQL_scaled": float(frame.AQL_scaled.max()),
                "complete_inner_folds": int(frame.inner_fold.nunique()),
                "priority": 1,
            })
    table = pd.DataFrame(candidates)
    if not (table.complete_inner_folds == 3).all():
        raise RuntimeError("incomplete final inner-fold surface")
    selected = table.sort_values(
        ["region", "mean_inner_AQL_scaled", "worst_inner_AQL_scaled", "priority", "tau0"],
        na_position="first",
    ).drop_duplicates("region", keep="first")
    return selected.drop(columns="priority").to_dict("records")


def task_contract(base: dict, output_dir: Path) -> dict:
    value = dict(base)
    value["output_dir"] = str(output_dir)
    value["task_contract_sha256"] = sha256_json(value)
    return value


def completed_budget(base: dict, output_dir: Path, candidates: tuple[int, ...]) -> int | None:
    """Recover the exact ceiling encoded by a valid completed terminal."""
    terminal_path = output_dir / "terminal.json"
    if not terminal_path.is_file():
        return None
    try:
        terminal = json.loads(terminal_path.read_text())
    except Exception:
        return None
    if terminal.get("status") != "completed_r111a_direct_case" or terminal.get("test_opened") is not False:
        return None
    for budget in candidates:
        candidate = task_contract(base | {"max_iter": int(budget)}, output_dir)
        if terminal.get("task_contract_sha256") == candidate["task_contract_sha256"]:
            return int(budget)
    return None


def materialize_and_run(
    root: Path, code_root: Path, phase: str, task_specs: list[dict], cpus: list[int], max_workers: int
) -> list[dict]:
    pending = []
    rows = []
    for spec in task_specs:
        output_dir = Path(spec["output_dir"])
        contract = task_contract(spec, output_dir)
        contract_path = root / "contracts" / phase / f"{spec['task_id']}.json"
        write_json(contract_path, contract)
        row = {key: value for key, value in contract.items() if not isinstance(value, (list, dict))}
        row["contract_path"] = str(contract_path)
        rows.append(row)
        output_dir.parent.mkdir(parents=True, exist_ok=True)
        if valid_terminal(output_dir, contract["task_contract_sha256"]):
            continue
        pending.append({
            "task_id": spec["task_id"],
            "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/374_run_pricefm_stage_r111a_direct_case.R"), "--contract", str(contract_path)],
            "log_path": root / "logs" / phase / f"{spec['task_id']}.log",
        })
    write_csv(root / "contracts" / f"{phase}_resolved_manifest.csv", rows)
    return run_parallel(pending, cpus, max_workers, root / f"{phase}_launch_status.csv")


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
        campaign.get("stage") != "R111A"
        or campaign.get("test_access_authorized") is not False
        or campaign.get("fit_task_count") != 30
        or campaign.get("replay_case_count") != 3
        or campaign.get("task_count") != 33
        or campaign.get("broad_all_region_launch_authorized") is not False
    ):
        raise RuntimeError("invalid R111A campaign contract")
    if subprocess.check_output(["git", "-C", str(code_root), "rev-parse", "HEAD"], text=True).strip() != campaign["head"]:
        raise RuntimeError("R111A code HEAD differs from its frozen campaign contract")
    sources = list(csv.DictReader((root / "source_manifest.csv").open()))
    for source in sources:
        path = Path(source["path"])
        if not path.is_file() or sha256_file(path) != source["sha256"]:
            raise RuntimeError(f"R111A source changed after preparation: {path}")

    resources = physical_cpu_pool(args.workers)
    resources["observed_at_epoch"] = time.time()
    write_json(root / "resource_allocation.json", resources)
    cpus = resources["selected_logical_cpus"]

    adapter_rows = list(csv.DictReader((root / "adapter_manifest.csv").open()))
    adapter_tasks = []
    for row in adapter_rows:
        adapter_dir = Path(row["adapter_dir"])
        manifest_path = adapter_dir / "adapter_manifest.json"
        valid = False
        if manifest_path.is_file():
            manifest = json.loads(manifest_path.read_text())
            valid = set(manifest.get("splits", {})) == {"train", "val"}
        if not valid:
            adapter_tasks.append({
                "task_id": f"adapter__{row['region']}__fold{row['fold']}",
                "command": [sys.executable, str(code_root / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"), "--smoke-config", row["config_path"], "--force", "true"],
                "log_path": root / "logs/adapters" / f"{row['region']}__fold{row['fold']}.log",
            })
    run_parallel(adapter_tasks, cpus, args.workers, root / "adapter_launch_status.csv")
    for row in adapter_rows:
        manifest = json.loads((Path(row["adapter_dir"]) / "adapter_manifest.json").read_text())
        if set(manifest.get("splits", {})) != {"train", "val"}:
            raise RuntimeError("adapter split contamination detected")

    common = {
        "stage": "R111A",
        "selection_split": "fold1_training_inner_only",
        "test_access_authorized": False,
        "package_path": str(campaign["specs"] and Path(campaign["output_root"]).parents[1] / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
        "helper_path": str(code_root / "application/R/pricefm_recursive_normal_fit.R"),
        "horizon_helper_path": str(code_root / "application/scripts/pricefm/pricefm_horizon_readout.R"),
        "quantiles": campaign["quantiles"],
        "n_inner_folds": 3,
        "max_iter": 300,
        "min_iter": 50,
        "tol": 1e-5,
        "n_paths": 500,
    }
    # The runtime package lives beside campaigns under data_local/pricefm.
    common["package_path"] = str(root.parents[1] / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm")

    ridge_tasks = []
    for region in REGIONS:
        for readout in ("shared", "block24"):
            for inner in INNER_FOLDS:
                task_id = f"ridge__{region}__{readout}__inner{inner}"
                ridge_tasks.append(common | {
                    "task_id": task_id, "phase": "ridge_selection", "region": region,
                    "outer_fold": 1, "inner_fold": inner, "readout": readout,
                    "prior_type": "scaled_ridge", "tau0": None,
                    "adapter_dir": str(root / "adapters" / f"region={region}" / "fold=1"),
                    "output_dir": str(root / "runs/ridge_selection" / region / readout / f"inner={inner}"),
                    "seed": 2026092400 + inner,
                })
    materialize_and_run(root, code_root, "ridge_selection", ridge_tasks, cpus, args.workers)
    ridge = mean_metrics(root, "ridge_selection")
    ridge_selection = select_ridge(ridge)
    write_csv(root / "ridge_region_selection.csv", ridge_selection)
    readout_by_region = {row["region"]: row["readout"] for row in ridge_selection}

    rhs_tasks = []
    for region in REGIONS:
        anchor = float(campaign["specs"][region]["tau0"])
        for label, tau0 in (("anchor", anchor), ("quarter", anchor / 4.0)):
            for inner in INNER_FOLDS:
                task_id = f"rhs__{region}__{label}__inner{inner}"
                rhs_output = root / "runs/rhs_selection" / region / label / f"inner={inner}"
                rhs_base = common | {
                    "task_id": task_id, "phase": "rhs_selection", "region": region,
                    "outer_fold": 1, "inner_fold": inner, "readout": readout_by_region[region],
                    "prior_type": "rhs_ns", "tau0": tau0,
                    "adapter_dir": str(root / "adapters" / f"region={region}" / "fold=1"),
                    "output_dir": str(rhs_output),
                    "seed": 2026092500 + inner,
                }
                previous_budget = completed_budget(rhs_base, rhs_output, (500, 750, 1500))
                rhs_tasks.append(rhs_base | {"max_iter": previous_budget or 1500})
    materialize_and_run(root, code_root, "rhs_selection", rhs_tasks, cpus, args.workers)
    rhs = mean_metrics(root, "rhs_selection")
    final_selection = select_final(ridge, rhs, ridge_selection)
    write_csv(root / "final_region_selection.csv", final_selection)

    selected = {row["region"]: row for row in final_selection}
    final_tasks = []
    for region in REGIONS:
        choice = selected[region]
        for fold in FOLDS:
            task_id = f"final__{region}__fold{fold}"
            final_output = root / "runs/outer_validation" / region / f"fold={fold}"
            final_base = common | {
                "task_id": task_id, "phase": "outer_validation", "region": region,
                "outer_fold": fold, "inner_fold": None, "readout": choice["readout"],
                "prior_type": choice["prior_type"],
                "tau0": None if choice["prior_type"] == "scaled_ridge" else float(choice["tau0"]),
                "adapter_dir": str(root / "adapters" / f"region={region}" / f"fold={fold}"),
                "output_dir": str(final_output),
                "selection_split": "frozen_policy_outer_validation_transfer",
                "seed": 2026092600 + fold,
            }
            allowed_budgets = (750, 1000, 1500) if choice["prior_type"] == "rhs_ns" else (300,)
            previous_budget = completed_budget(final_base, final_output, allowed_budgets)
            default_budget = 1500 if choice["prior_type"] == "rhs_ns" else 300
            final_tasks.append(final_base | {"max_iter": previous_budget or default_budget})
    materialize_and_run(root, code_root, "outer_validation", final_tasks, cpus, args.workers)

    replay_tasks = []
    for fold in FOLDS:
        command = [
            sys.executable,
            str(code_root / "application/scripts/pricefm/375_replay_pricefm_stage_r111a_ee_all_active.py"),
            "--campaign-root", str(root), "--mode", "case", "--fold", str(fold),
            "--posterior-paths", "500",
        ]
        replay_tasks.append({
            "task_id": f"replay__EE__fold{fold}",
            "command": command,
            "log_path": root / "logs/replay" / f"EE__fold{fold}.log",
        })
    run_parallel(replay_tasks, cpus, args.workers, root / "replay_launch_status.csv")

    closeout = subprocess.run([
        sys.executable,
        str(code_root / "application/scripts/pricefm/375_replay_pricefm_stage_r111a_ee_all_active.py"),
        "--campaign-root", str(root), "--mode", "finalize",
    ])
    if closeout.returncode != 0:
        raise RuntimeError("R111A closeout failed")
    write_json(root / "orchestrator_terminal.json", {
        "status": "completed_r111a_orchestration", "stage": "R111A", "task_count": 33,
        "fit_task_count": 30, "replay_case_count": 3,
        "adapter_count": 6, "selected_physical_core_count": len(cpus),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    })


if __name__ == "__main__":
    main()
