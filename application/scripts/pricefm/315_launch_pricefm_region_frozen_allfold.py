#!/usr/bin/env python3
"""Launch a concrete region-frozen all-fold DAG without region-specific assumptions."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from typing import Any

import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    binary_artifacts,
    canonical_sha256,
    validate_git_identity,
    validate_no_test_adapter,
    validate_pretest_firewall,
)


APPROVAL_TOKEN = "RUN_PRICEFM_REGION_FROZEN_ALLFOLD_VALIDATION"
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--region-contract", type=Path, required=True)
    value.add_argument("--pipeline-contract", type=Path, required=True)
    value.add_argument("--manifest", type=Path, required=True)
    value.add_argument("--launch-control", type=Path, required=True)
    value.add_argument("--preprocessing-terminal", type=Path, required=True)
    value.add_argument("--workers", type=int, default=20)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--maximum-cpu-snapshot-percent", type=float, default=25.0)
    value.add_argument("--minimum-free-gib", type=float, default=80.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=40.0)
    value.add_argument("--poll-seconds", type=float, default=15.0)
    value.add_argument("--approval-token", default="")
    value.add_argument("--preflight-only", action="store_true")
    return value


def sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y", "on"}


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    frame.to_csv(temporary, index=False)
    temporary.replace(path)


def parse_cpus(value: str) -> list[int]:
    cpus: list[int] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = map(int, token.split("-", 1))
            if lower > upper:
                raise RuntimeError("CPU range is reversed")
            cpus.extend(range(lower, upper + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise RuntimeError("CPU list must contain unique logical CPU IDs")
    if not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise RuntimeError("CPU list contains an offline logical CPU ID")
    return cpus


def cpu_snapshot(interval: float = 0.8) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        result: dict[int, tuple[int, int]] = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(value) for value in fields[1:]]
                result[int(fields[0][3:])] = (
                    sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0),
                )
        return result

    before = read()
    time.sleep(interval)
    after = read()
    usage: dict[int, float] = {}
    for cpu in sorted(set(before) & set(after)):
        total = after[cpu][0] - before[cpu][0]
        idle = after[cpu][1] - before[cpu][1]
        usage[cpu] = 100.0 * (1.0 - idle / total) if total else 100.0
    return usage


def choose_cpus(count: int, maximum: float) -> tuple[list[int], dict[int, float]]:
    first, second = cpu_snapshot(), cpu_snapshot()
    usage = {cpu: max(first.get(cpu, 100.0), second.get(cpu, 100.0)) for cpu in first}
    eligible = [
        cpu for cpu, observed in sorted(usage.items(), key=lambda item: (item[1], item[0]))
        if observed <= maximum
    ]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs pass the <= {maximum}% gate")
    return eligible[:count], usage


def available_memory_gib() -> float:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def capped_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in THREAD_ENV:
        environment[name] = "1"
    return environment


def load_task(row: dict[str, Any]) -> dict[str, Any]:
    path = Path(row["task_config"])
    if not path.is_file() or sha256(path) != str(row["task_config_sha256"]):
        raise RuntimeError(f"Task hash mismatch: {row['task_id']}")
    task = json.loads(path.read_text())
    if task.get("task_id") != row["task_id"]:
        raise RuntimeError(f"Task identity mismatch: {row['task_id']}")
    task["task_config"] = str(path.resolve())
    return task


def validate_acyclic(tasks: dict[str, dict[str, Any]]) -> None:
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visited:
            return
        if task_id in visiting:
            raise RuntimeError("Region-frozen task graph contains a cycle")
        visiting.add(task_id)
        for parent in tasks[task_id].get("parent_task_ids") or []:
            if str(parent) not in tasks:
                raise RuntimeError(f"Unknown task dependency: {parent}")
            visit(str(parent))
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in tasks:
        visit(task_id)


def validate_launch_contract(
    region_contract: dict[str, Any],
    pipeline: dict[str, Any],
    control: dict[str, Any],
    manifest: pd.DataFrame,
) -> dict[str, dict[str, Any]]:
    validate_pretest_firewall(region_contract, label="region contract")
    validate_pretest_firewall(pipeline, label="pipeline contract")
    validate_pretest_firewall(control, label="launch control")
    region = str(region_contract["target_region"])
    if pipeline.get("region") != region or manifest.region.astype(str).nunique() != 1:
        raise RuntimeError("Region-frozen launch inputs identify different regions")
    if str(manifest.region.iloc[0]) != region:
        raise RuntimeError("Manifest region differs from the frozen region contract")
    expected_contract_hash = region_contract.get("contract_sha256")
    unhashed_region = {key: value for key, value in region_contract.items() if key != "contract_sha256"}
    if expected_contract_hash and canonical_sha256(unhashed_region) != expected_contract_hash:
        raise RuntimeError("Region contract canonical hash changed")
    pipeline_hash = str(pipeline.get("pipeline_contract_sha256", ""))
    unhashed_pipeline = {key: value for key, value in pipeline.items() if key != "pipeline_contract_sha256"}
    if not pipeline_hash or canonical_sha256(unhashed_pipeline) != pipeline_hash:
        raise RuntimeError("Pipeline contract canonical hash changed")
    if control.get("pipeline_contract_sha256") != pipeline_hash:
        raise RuntimeError("Launch control is not bound to the pipeline contract")
    if manifest.empty or manifest.task_id.duplicated().any():
        raise RuntimeError("Executable manifest must contain unique tasks")
    if manifest.pipeline_contract_sha256.astype(str).nunique() != 1 or str(
        manifest.pipeline_contract_sha256.iloc[0]
    ) != pipeline_hash:
        raise RuntimeError("Manifest is not bound to the pipeline contract")
    for name in ("test_opened", *BLOCKED):
        if name not in manifest or manifest[name].map(boolish).any():
            raise RuntimeError(f"Manifest violates the pre-test firewall: {name}")
    if "launch_authorized" not in manifest or manifest.launch_authorized.map(boolish).any():
        raise RuntimeError("Preparation must not self-authorize launch")

    tasks = {str(row["task_id"]): load_task(row) for row in manifest.to_dict("records")}
    allowed_folds = set(map(int, region_contract["real_folds"]))
    for task_id, task in tasks.items():
        if (
            task.get("region") != region
            or int(task.get("fold")) not in allowed_folds
            or task.get("selection_split") != "val"
            or task.get("pipeline_contract_sha256") != pipeline_hash
            or task.get("runner_type") not in {"normal_full", "quantile_atom"}
            or task.get("launch_authorized") is not False
            or task.get("test_opened") is not False
            or any(task.get(name) is not False for name in BLOCKED)
        ):
            raise RuntimeError(f"Task is not launch-grade and pre-test: {task_id}")
        output = Path(task["output_dir"])
        if output.name != task_id:
            raise RuntimeError(f"Task output is not content-addressed: {task_id}")
        for field, hash_field in (
            ("data_config", "data_config_sha256"),
            ("runner_script", "runner_script_sha256"),
        ):
            path = Path(task[field])
            if not path.is_file() or sha256(path) != str(task[hash_field]):
                raise RuntimeError(f"Task source hash changed: {path}")
        if task["runner_type"] == "normal_full":
            path = Path(task["normal_full_config"])
            if not path.is_file() or sha256(path) != str(task["normal_full_config_sha256"]):
                raise RuntimeError(f"Normal configuration hash changed: {task_id}")
    validate_acyclic(tasks)
    return tasks


def artifact_record(path: Path, role: str) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(path)
    return {"path": str(path.resolve()), "role": role, "sha256": sha256(path), "bytes": path.stat().st_size}


def write_normal_terminal(task: dict[str, Any]) -> None:
    model = Path(task["normal_model_dir"])
    adapter = Path(task["adapter_dir"])
    validate_no_test_adapter(adapter)
    model_files = {
        "normal_beta_mean.csv": "normal_beta_mean",
        "normal_beta_cov_diag.csv": "normal_beta_cov_diag",
        "model_parameter_summary.csv": "normal_parameter_summary",
        "model_method_summary.csv": "normal_method_summary",
        "model_predictions_scaled.csv": "normal_validation_predictions",
    }
    adapter_files = {
        "X_train.csv": "adapter_X_train", "y_train.csv": "adapter_y_train",
        "rows_train.csv": "adapter_rows_train", "X_val.csv": "adapter_X_val",
        "y_val.csv": "adapter_y_val", "rows_val.csv": "adapter_rows_val",
        "adapter_manifest.json": "adapter_manifest", "feature_manifest.json": "feature_manifest",
        "feature_map_matrix.npz": "feature_map_matrix",
    }
    artifacts = [artifact_record(model / name, role) for name, role in model_files.items()]
    artifacts += [artifact_record(adapter / name, role) for name, role in adapter_files.items()]
    parameters = pd.read_csv(model / "model_parameter_summary.csv")
    methods = pd.read_csv(model / "model_method_summary.csv")
    parameter = parameters.loc[parameters.method_id.astype(str).eq("normal_rhs_ns")]
    method = methods.loc[methods.method_id.astype(str).eq("normal_rhs_ns")]
    eligible = (
        len(parameter) == 1 and len(method) == 1
        and math.isfinite(float(parameter.iloc[0].sigma))
        and float(parameter.iloc[0].sigma) > 0
        and boolish(method.iloc[0].converged)
    )
    if not eligible or binary_artifacts(model.parent):
        raise RuntimeError(f"Normal-RHS task is not numerically eligible: {task['task_id']}")
    output = Path(task["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    atomic_json(output / "terminal.json", {
        "status": "completed", "stage": task["stage"], "task_id": task["task_id"],
        "region": task["region"], "fold": int(task["fold"]),
        "likelihood_family": "normal_rhs", "numerical_gate_passed": True,
        "formal_converged": True, "artifacts": artifacts,
        "pipeline_contract_sha256": task["pipeline_contract_sha256"],
        "test_loaded": False, "test_opened": False, "test_access_authorized": False,
        "binary_model_artifacts_written": False,
    })


def terminal_state(task: dict[str, Any]) -> str | None:
    path = Path(task["output_dir"]) / "terminal.json"
    if not path.is_file():
        return None
    try:
        terminal = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    if (
        terminal.get("status") not in {"completed", "completed_numerically_ineligible"}
        or terminal.get("stage") != task.get("stage")
        or terminal.get("task_id") != task.get("task_id")
        or terminal.get("pipeline_contract_sha256") != task.get("pipeline_contract_sha256")
        or terminal.get("test_loaded") is not False
        or terminal.get("test_opened") is not False
        or terminal.get("test_access_authorized") is not False
    ):
        return None
    for record in terminal.get("artifacts") or []:
        path = Path(record["path"])
        if not path.is_file() or sha256(path) != str(record["sha256"]):
            return None
    return str(terminal["status"])


def command_for_task(task: dict[str, Any], code_root: Path) -> list[str]:
    if task["runner_type"] == "normal_full":
        config = yaml.safe_load(Path(task["normal_full_config"]).read_text())["pricefm_desn_full"]
        return [
            str(config["python_bin"]), str(Path(task["runner_script"])),
            "--config", task["normal_full_config"], "--jobs", "1", "--resume", "true",
            "--force", "false", "--dry-run", "false", "--regions", task["region"],
            "--folds", str(task["fold"]), "--max-cells", "1",
        ]
    rscript = str(task.get("rscript_bin", "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript"))
    return [rscript, str(Path(task["runner_script"])), "--task-config", task["task_config"], "--code-root", str(code_root)]


def run_one(task: dict[str, Any], cpu: int, code_root: Path, poll_seconds: float, update) -> dict[str, Any]:
    existing = terminal_state(task)
    if existing:
        return {"task_id": task["task_id"], "status": f"skipped_{existing}", "cpu": cpu, "returncode": 0}
    output = Path(task["output_dir"])
    if output.exists() and any(output.iterdir()):
        raise RuntimeError(f"Invalid partial requires explicit quarantine review: {output}")
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    started = time.time()
    with log.open("a") as handle:
        process = subprocess.Popen(
            ["taskset", "-c", str(cpu), *command_for_task(task, code_root)],
            cwd=code_root, env=capped_environment(), stdout=handle,
            stderr=subprocess.STDOUT, text=True,
        )
        while process.poll() is None:
            update(task["task_id"], {"status": "running", "cpu": cpu, "pid": process.pid})
            time.sleep(max(0.2, poll_seconds))
    if process.returncode == 0 and task["runner_type"] == "normal_full":
        write_normal_terminal(task)
    state = terminal_state(task)
    return {
        "task_id": task["task_id"], "status": state or "failed", "cpu": cpu,
        "returncode": int(process.returncode), "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    region_contract = json.loads(args.region_contract.read_text())
    pipeline = json.loads(args.pipeline_contract.read_text())
    control = json.loads(args.launch_control.read_text())
    manifest = pd.read_csv(args.manifest)
    tasks = validate_launch_contract(region_contract, pipeline, control, manifest)
    if not 1 <= args.workers <= 20:
        raise RuntimeError("Region-frozen controller requires 1--20 workers")
    cpus, usage = (
        (parse_cpus(args.cpu_list), cpu_snapshot()) if args.cpu_list
        else choose_cpus(args.workers, args.maximum_cpu_snapshot_percent)
    )
    if len(cpus) < args.workers:
        raise RuntimeError("Region-frozen controller requires one unique CPU per worker")
    selected = {str(cpu): round(usage.get(cpu, math.nan), 3) for cpu in cpus[:args.workers]}
    if any(value > args.maximum_cpu_snapshot_percent for value in selected.values() if math.isfinite(value)):
        raise RuntimeError("A selected CPU exceeds the utilization gate")
    preprocessing = json.loads(args.preprocessing_terminal.read_text())
    if (
        preprocessing.get("status") != "completed"
        or preprocessing.get("pipeline_contract_sha256") != pipeline["pipeline_contract_sha256"]
        or preprocessing.get("test_opened") is not False
        or not all(Path(record["path"]).is_file() and sha256(record["path"]) == record["sha256"] for record in preprocessing.get("artifacts") or [])
    ):
        raise RuntimeError("Hash-valid train/validation preprocessing is required")
    git = validate_git_identity(args.code_root, control["git_identity"], require_clean=True)
    free = os.statvfs(args.manifest.parent)
    free_gib = free.f_bavail * free.f_frsize / 1024**3
    memory_gib = available_memory_gib()
    if free_gib < args.minimum_free_gib or memory_gib < args.minimum_available_memory_gib:
        raise RuntimeError("Region-frozen resource floor failed")
    audit = {
        "status": "preflight_passed_not_launched", "region": pipeline["region"],
        "tasks": len(tasks), "workers": args.workers, "cpu_ids": cpus[:args.workers],
        "cpu_snapshot_percent": selected, "one_model_process_per_cpu": True,
        "threads_per_process": 1, "free_disk_gib": round(free_gib, 3),
        "available_memory_gib": round(memory_gib, 3), "git_identity": git.to_dict(),
        "test_opened": False, **{name: False for name in BLOCKED},
    }
    atomic_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return audit
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"Launch requires --approval-token {APPROVAL_TOKEN}")

    lock_handle = (args.manifest.parent / "launcher.lock").open("a+")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        lock_handle.close()
        raise RuntimeError("Another controller owns this launch manifest") from error
    states = {task_id: {"status": terminal_state(task) or "queued"} for task_id, task in tasks.items()}
    state_lock = threading.Lock()

    def update(task_id: str, values: dict[str, Any]) -> None:
        with state_lock:
            states[task_id].update(values)
            atomic_json(args.manifest.parent / "scheduler_state.json", {
                "region": pipeline["region"], "updated_at_epoch": time.time(),
                "tasks": states, "test_opened": False,
            })

    results: list[dict[str, Any]] = []
    available = list(cpus[:args.workers])
    unfinished = {task_id for task_id, state in states.items() if state["status"] == "queued"}
    running: dict[Any, tuple[str, int]] = {}
    try:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            while unfinished or running:
                progress = False
                for task_id in sorted(list(unfinished)):
                    parent_states = [states[str(parent)]["status"] for parent in tasks[task_id].get("parent_task_ids") or []]
                    if any(state in {"failed", "blocked_dependency", "completed_numerically_ineligible"} for state in parent_states):
                        states[task_id]["status"] = "blocked_dependency"
                        results.append({"task_id": task_id, "status": "blocked_dependency"})
                        unfinished.remove(task_id)
                        progress = True
                    elif available and all(state == "completed" for state in parent_states):
                        cpu = available.pop(0)
                        future = pool.submit(run_one, tasks[task_id], cpu, args.code_root.resolve(), args.poll_seconds, update)
                        running[future] = (task_id, cpu)
                        unfinished.remove(task_id)
                        progress = True
                if running:
                    done, _ = wait(running, return_when=FIRST_COMPLETED)
                    for future in done:
                        task_id, cpu = running.pop(future)
                        try:
                            result = future.result()
                        except Exception as error:
                            result = {"task_id": task_id, "status": "failed", "cpu": cpu, "error": repr(error)}
                        final = str(result["status"]).removeprefix("skipped_")
                        states[task_id]["status"] = final
                        results.append(result)
                        available.append(cpu)
                        available.sort()
                        atomic_csv(args.manifest.parent / "launch_status.csv", pd.DataFrame(results).sort_values("task_id"))
                        progress = True
                if not progress and unfinished:
                    raise RuntimeError("Region-frozen scheduler reached an unresolved dependency deadlock")
    finally:
        lock_handle.close()
    completed = sum(terminal_state(task) in {"completed", "completed_numerically_ineligible"} for task in tasks.values())
    summary = {
        "status": "completed_validation_tasks" if completed == len(tasks) else "completed_with_failures",
        "region": pipeline["region"], "tasks": len(tasks), "completed": completed,
        "failed_or_blocked": len(tasks) - completed, "workers": args.workers,
        "cpu_ids": cpus[:args.workers], "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    atomic_json(args.manifest.parent / "launch_summary.json", summary)
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {"preflight_passed_not_launched", "completed_validation_tasks"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
