#!/usr/bin/env python3
"""Preflight or explicitly launch dependency-aware R95 all-fold validation fits."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
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

from pricefm_desn_adapter import window_npz_path
from pricefm_region_frozen_contract import (
    binary_artifacts,
    quarantine_path,
    validate_git_identity,
    validate_no_test_adapter,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r95_region_frozen_allfold_validation_20260907"
MANIFEST = DATA / "experiment_grids" / TAG / "task_manifest.csv"
APPROVAL_TOKEN = "RUN_PRICEFM_R95_ALLFOLD_VALIDATION"
BLOCKED = (
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)
WARM_PARENT_TAU = {
    0.50: None,
    0.45: 0.50,
    0.25: 0.45,
    0.10: 0.25,
    0.55: 0.50,
    0.75: 0.55,
    0.90: 0.75,
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--manifest", type=Path, default=MANIFEST)
    value.add_argument("--workers", type=int, default=20)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--prep-cpu-list", default="")
    value.add_argument("--minimum-free-gib", type=float, default=80.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=40.0)
    value.add_argument("--maximum-cpu-snapshot-percent", type=float, default=25.0)
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--approval-token", default="")
    value.add_argument("--poll-seconds", type=float, default=15.0)
    value.add_argument("--retry-limit", type=int, default=1)
    value.add_argument("--closeout-output-dir", type=Path, default=DATA / "authoritative/pricefm_stage_r95_allfold_validation_closeout_20260907")
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
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


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
    online = set(range(os.cpu_count() or 0))
    if not cpus or len(cpus) != len(set(cpus)) or not set(cpus).issubset(online):
        raise RuntimeError("CPU list must contain unique online logical CPU IDs")
    return cpus


def available_memory_gib() -> float:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def cpu_snapshot(interval: float = 0.8) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        result: dict[int, tuple[int, int]] = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if not fields or not fields[0].startswith("cpu") or not fields[0][3:].isdigit():
                continue
            ticks = [int(value) for value in fields[1:]]
            result[int(fields[0][3:])] = (
                sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0),
            )
        return result

    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100.0 * (1.0 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        for cpu, (total, idle) in before.items()
        if cpu in after and after[cpu][0] > total
    }


def choose_cpus(count: int, maximum: float) -> tuple[list[int], dict[int, float]]:
    first = cpu_snapshot()
    second = cpu_snapshot()
    usage = {cpu: max(first.get(cpu, 100.0), second.get(cpu, 100.0)) for cpu in first}
    eligible = [
        cpu for cpu, value in sorted(usage.items(), key=lambda item: (item[1], item[0]))
        if value <= maximum
    ]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs pass two <= {maximum}% snapshots")
    return eligible[:count], usage


def capped_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in THREAD_ENV:
        environment[name] = "1"
    return environment


def process_observation(pid: int) -> dict[str, Any]:
    stat = Path(f"/proc/{pid}/stat")
    status = Path(f"/proc/{pid}/status")
    if not stat.is_file():
        return {"process_alive": False}
    fields = stat.read_text().split()
    rss_kib = None
    if status.is_file():
        for line in status.read_text().splitlines():
            if line.startswith("VmRSS:"):
                rss_kib = int(line.split()[1])
                break
    return {
        "process_alive": True,
        "cpu_time_ticks": int(fields[13]) + int(fields[14]),
        "resident_memory_kib": rss_kib,
    }


def artifact_record(path: Path, role: str) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(path)
    return {
        "path": str(path.resolve()),
        "role": role,
        "sha256": sha256(path),
        "bytes": path.stat().st_size,
    }


def load_task(row: dict[str, Any]) -> dict[str, Any]:
    path = Path(row["task_config"])
    if not path.is_file() or sha256(path) != str(row["task_config_sha256"]):
        raise RuntimeError(f"R95 task hash mismatch: {row['task_id']}")
    task = json.loads(path.read_text())
    if task.get("task_id") != row["task_id"]:
        raise RuntimeError(f"R95 task ID mismatch: {row['task_id']}")
    return task


def terminal_state(task: dict[str, Any]) -> str | None:
    output = Path(task["output_dir"])
    path = output / "terminal.json"
    if not path.is_file():
        return None
    try:
        terminal = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None
    status = terminal.get("status")
    if (
        status not in {"completed", "completed_numerically_ineligible"}
        or terminal.get("task_id") != task.get("task_id")
        or terminal.get("pipeline_contract_sha256") != task.get("pipeline_contract_sha256")
        or terminal.get("test_loaded") is not False
        or terminal.get("test_opened") is not False
        or terminal.get("test_access_authorized") is not False
    ):
        return None
    records = terminal.get("artifacts") or []
    if not records:
        return None
    for record in records:
        source = Path(record["path"])
        if not source.is_file() or sha256(source) != str(record["sha256"]):
            return None
    search_root = Path(task["normal_model_dir"]).parent if task["runner_type"] == "normal_full" else output
    if binary_artifacts(search_root):
        return None
    if status == "completed" and terminal.get("numerical_gate_passed") is not True:
        return None
    if status == "completed_numerically_ineligible" and terminal.get("numerical_gate_passed") is not False:
        return None
    return str(status)


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int], usage: dict[int, float]) -> dict[str, Any]:
    control_path = args.manifest.parent / "launch_control.json"
    pipeline_path = args.manifest.parent / "pipeline_contract.json"
    if not control_path.is_file() or not pipeline_path.is_file():
        raise FileNotFoundError("R95 launch control or pipeline contract is missing")
    control = json.loads(control_path.read_text())
    pipeline = json.loads(pipeline_path.read_text())
    git = validate_git_identity(args.code_root, control["git_identity"], require_clean=True)
    family_counts = manifest.likelihood_family.value_counts().to_dict()
    if (
        len(manifest) != 30
        or manifest.task_id.duplicated().any()
        or family_counts != {"al": 14, "exal": 14, "normal_rhs": 2}
        or set(manifest.fold.astype(int)) != {2, 3}
        or not manifest.stage.eq("R95").all()
        or manifest.pipeline_contract_sha256.nunique() != 1
        or str(manifest.pipeline_contract_sha256.iloc[0]) != control["pipeline_contract_sha256"]
        or pipeline.get("pipeline_contract_sha256") != control["pipeline_contract_sha256"]
    ):
        raise RuntimeError("R95 manifest/control contract is inconsistent")
    if args.workers < 1 or args.workers > 20 or len(cpus) < args.workers:
        raise RuntimeError("R95 requires 1--20 unique worker CPUs")
    if args.retry_limit not in {0, 1}:
        raise RuntimeError("R95 permits at most one automatic retry")
    for name in ("test_opened", *BLOCKED):
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R95 manifest authorizes forbidden action: {name}")
    if manifest.launch_authorized.map(boolish).any():
        raise RuntimeError("R95 preparation may not authorize its own launch")
    known = set(manifest.task_id.astype(str))
    task_payloads: dict[str, dict[str, Any]] = {}
    for row in manifest.to_dict("records"):
        task = load_task(row)
        task_payloads[task["task_id"]] = task
        if (
            task.get("stage") != "R95"
            or task.get("selection_split") != "val"
            or task.get("launch_authorized") is not False
            or task.get("test_opened") is not False
            or any(task.get(name) is not False for name in BLOCKED)
        ):
            raise RuntimeError(f"R95 task firewall mismatch: {row['task_id']}")
        if (
            task.get("region") != pipeline["region"]
            or int(task.get("fold")) not in {2, 3}
            or task.get("pipeline_contract_sha256") != pipeline["pipeline_contract_sha256"]
            or task.get("frozen_desn") != pipeline["frozen_desn"]
            or task.get("rhs") != pipeline["rhs"]
            or task.get("qdesn_vb") != pipeline["qdesn_vb"]
            or Path(task.get("data_config", "")).resolve() != Path(pipeline["generated_data_config"]["path"]).resolve()
            or Path(task.get("runtime_manifest", "")).resolve() != Path(pipeline["r94_runtime_manifest"]["path"]).resolve()
        ):
            raise RuntimeError(f"R95 task diverges from the frozen pipeline: {row['task_id']}")
        parents = [str(value) for value in task.get("parent_task_ids") or []]
        if any(parent not in known for parent in parents):
            raise RuntimeError(f"R95 task has an unknown dependency: {row['task_id']}")
        for field, hash_field in (
            ("data_config", "data_config_sha256"),
            ("runtime_manifest", "runtime_manifest_sha256"),
            ("runner_script", "runner_script_sha256"),
        ):
            if sha256(task[field]) != task[hash_field]:
                raise RuntimeError(f"R95 task source changed: {task[field]}")
        if task["runner_type"] == "normal_full" and sha256(task["normal_full_config"]) != task["normal_full_config_sha256"]:
            raise RuntimeError(f"R95 normal config changed: {task['task_id']}")
    for fold in (2, 3):
        normal = [
            task for task in task_payloads.values()
            if int(task["fold"]) == fold and task["likelihood_family"] == "normal_rhs"
        ]
        if len(normal) != 1 or normal[0].get("parent_task_ids"):
            raise RuntimeError(f"R95 fold {fold} normal dependency is invalid")
        al = {
            float(task["tau"]): task for task in task_payloads.values()
            if int(task["fold"]) == fold and task["likelihood_family"] == "al"
        }
        exal = {
            float(task["tau"]): task for task in task_payloads.values()
            if int(task["fold"]) == fold and task["likelihood_family"] == "exal"
        }
        if set(al) != set(WARM_PARENT_TAU) or set(exal) != set(WARM_PARENT_TAU):
            raise RuntimeError(f"R95 fold {fold} quantile surface is invalid")
        for tau, parent_tau in WARM_PARENT_TAU.items():
            expected_al_parent = normal[0]["task_id"] if parent_tau is None else al[parent_tau]["task_id"]
            if al[tau].get("parent_task_ids") != [expected_al_parent]:
                raise RuntimeError(f"R95 fold {fold} AL tau {tau} dependency changed")
            if exal[tau].get("parent_task_ids") != [al[tau]["task_id"]]:
                raise RuntimeError(f"R95 fold {fold} exAL tau {tau} dependency changed")
    with Path(pipeline["generated_data_config"]["path"]).open() as handle:
        data = yaml.safe_load(handle)["pricefm"]
    if any("test" in item for split in data["splits"] for item in split):
        raise RuntimeError("R95 generated data config contains a test split")
    free = shutil.disk_usage(args.manifest.parent).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R95 resource gate failed: disk={free:.1f} GiB memory={memory:.1f} GiB")
    selected_usage = {str(cpu): round(usage.get(cpu, math.nan), 3) for cpu in cpus[: args.workers]}
    if any(value > args.maximum_cpu_snapshot_percent for value in selected_usage.values() if math.isfinite(value)):
        raise RuntimeError("R95 selected CPU exceeds the repeated snapshot threshold")
    return {
        "status": "preflight_passed_not_launched",
        "tasks": 30,
        "workers": args.workers,
        "cpu_ids": cpus[: args.workers],
        "cpu_snapshot_max_percent": selected_usage,
        "one_process_per_cpu": True,
        "threads_per_process": 1,
        "free_disk_gib": round(free, 3),
        "available_memory_gib": round(memory, 3),
        "git_identity": git.to_dict(),
        "pipeline_contract_sha256": control["pipeline_contract_sha256"],
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }


def run_logged(command: list[str], log: Path, *, cwd: Path, cpus: list[int] | None = None) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    wrapped = command
    if cpus:
        wrapped = ["taskset", "-c", ",".join(map(str, cpus)), *command]
    with log.open("a") as handle:
        handle.write(f"START epoch={time.time()} command={json.dumps(wrapped)}\n")
        handle.flush()
        result = subprocess.run(
            wrapped,
            cwd=cwd,
            env=capped_environment(),
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        handle.write(f"END epoch={time.time()} returncode={result.returncode}\n")
    return int(result.returncode)


def preprocessing_complete(pipeline: dict[str, Any], terminal_path: Path) -> bool:
    if not terminal_path.is_file():
        return False
    try:
        terminal = json.loads(terminal_path.read_text())
    except (json.JSONDecodeError, OSError):
        return False
    if (
        terminal.get("status") != "completed"
        or terminal.get("pipeline_contract_sha256") != pipeline["pipeline_contract_sha256"]
        or terminal.get("test_opened") is not False
    ):
        return False
    return all(Path(record["path"]).is_file() and sha256(record["path"]) == record["sha256"] for record in terminal.get("artifacts") or [])


def prepare_data(pipeline: dict[str, Any], args: argparse.Namespace, prep_cpus: list[int]) -> dict[str, Any]:
    terminal_path = args.manifest.parent / "preprocessing_terminal.json"
    if preprocessing_complete(pipeline, terminal_path):
        return {"status": "skipped_hash_valid_completed", "terminal": str(terminal_path)}
    processed = Path(pipeline["processed_dir"])
    if processed.exists() and any(processed.iterdir()):
        quarantine_path(processed, processed.parent / "quarantine", "invalid_or_partial_r95_preprocessing")
    processed.mkdir(parents=True, exist_ok=True)
    data_config = Path(pipeline["generated_data_config"]["path"])
    python = Path(pipeline["normal_full_config"]["path"])
    with python.open() as handle:
        python_bin = Path(yaml.safe_load(handle)["pricefm_desn_full"]["python_bin"])
    logs = args.manifest.parent / "preprocessing_logs"
    commands = [
        [str(python_bin), str(args.code_root / "application/scripts/pricefm/03_make_splits.py"), "--config", str(data_config), "--force", "false"],
        [str(python_bin), str(args.code_root / "application/scripts/pricefm/04_fit_scalers.py"), "--config", str(data_config), "--force", "false"],
        [
            str(python_bin), str(args.code_root / "application/scripts/pricefm/05_build_windows.py"),
            "--config", str(data_config), "--force", "false", "--pilot-only", "false",
            "--regions", ",".join(pipeline["active_window_regions"]), "--folds", "2,3",
        ],
    ]
    for index, command in enumerate(commands, start=1):
        code = run_logged(command, logs / f"stage_{index}.log", cwd=args.code_root, cpus=prep_cpus)
        if code != 0:
            raise RuntimeError(f"R95 preprocessing stage {index} failed with return code {code}")
    with data_config.open() as handle:
        data_payload = yaml.safe_load(handle)
    artifacts = []
    for fold in (2, 3):
        scaler = processed / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib"
        artifacts.append(artifact_record(scaler, f"fold{fold}_scaler"))
        for region in pipeline["active_window_regions"]:
            for split in ("train", "val"):
                path = window_npz_path(data_payload, fold, region, split)
                artifacts.append(artifact_record(path, f"fold{fold}_{region}_{split}_window"))
    forbidden = sorted(processed.rglob("*test*"))
    if forbidden:
        raise RuntimeError(f"R95 preprocessing created forbidden test artifacts: {forbidden[:5]}")
    terminal = {
        "status": "completed",
        "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
        "active_window_regions": pipeline["active_window_regions"],
        "folds": [2, 3],
        "splits": ["train", "val"],
        "artifacts": artifacts,
        "test_opened": False,
        "test_access_authorized": False,
    }
    atomic_json(terminal_path, terminal)
    return {"status": "completed", "terminal": str(terminal_path), "artifacts": len(artifacts)}


def quarantine_invalid_task(task: dict[str, Any]) -> list[str]:
    moved: list[str] = []
    output = Path(task["output_dir"])
    root = Path(task.get("normal_model_dir", output)).parent if task["runner_type"] == "normal_full" else output
    for candidate in dict.fromkeys((output, root)):
        if candidate.exists() and any(candidate.iterdir()):
            destination = quarantine_path(
                candidate,
                Path(task["output_dir"]).parents[3] / "quarantine",
                f"invalid_partial_{task['task_id']}",
            )
            moved.append(str(destination))
    return moved


def write_normal_terminal(task: dict[str, Any]) -> None:
    model = Path(task["normal_model_dir"])
    adapter = Path(task["adapter_dir"])
    validate_no_test_adapter(adapter)
    required_model = {
        "normal_beta_mean.csv": "normal_beta_mean",
        "normal_beta_cov_diag.csv": "normal_beta_cov_diag",
        "model_parameter_summary.csv": "normal_parameter_summary",
        "model_method_summary.csv": "normal_method_summary",
        "model_predictions_scaled.csv": "normal_validation_predictions",
    }
    required_adapter = {
        "X_train.csv": "adapter_X_train", "y_train.csv": "adapter_y_train",
        "rows_train.csv": "adapter_rows_train", "X_val.csv": "adapter_X_val",
        "y_val.csv": "adapter_y_val", "rows_val.csv": "adapter_rows_val",
        "adapter_manifest.json": "adapter_manifest",
        "feature_manifest.json": "feature_manifest",
        "feature_map_matrix.npz": "feature_map_matrix",
    }
    artifacts = [artifact_record(model / name, role) for name, role in required_model.items()]
    artifacts.extend(artifact_record(adapter / name, role) for name, role in required_adapter.items())
    parameters = pd.read_csv(model / "model_parameter_summary.csv")
    method = pd.read_csv(model / "model_method_summary.csv")
    selected_parameter = parameters[parameters.method_id.astype(str).eq("normal_rhs_ns")]
    selected_method = method[method.method_id.astype(str).eq("normal_rhs_ns")]
    finite = (
        len(selected_parameter) == 1
        and len(selected_method) == 1
        and math.isfinite(float(selected_parameter.iloc[0].sigma))
        and float(selected_parameter.iloc[0].sigma) > 0
        and boolish(selected_method.iloc[0].converged)
    )
    if not finite:
        raise RuntimeError(f"R95 normal-RHS result is not numerically eligible: fold {task['fold']}")
    if binary_artifacts(model.parent):
        raise RuntimeError("R95 normal result contains forbidden binary model artifacts")
    output = Path(task["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    atomic_json(output / "terminal.json", {
        "status": "completed",
        "stage": "R95",
        "task_id": task["task_id"],
        "region": task["region"],
        "fold": int(task["fold"]),
        "likelihood_family": "normal_rhs",
        "numerical_gate_passed": True,
        "formal_converged": True,
        "artifacts": artifacts,
        "pipeline_contract_sha256": task["pipeline_contract_sha256"],
        "test_loaded": False,
        "test_opened": False,
        "test_access_authorized": False,
        "binary_model_artifacts_written": False,
    })


def command_for_task(task: dict[str, Any], code_root: Path) -> list[str]:
    if task["runner_type"] == "normal_full":
        return [
            str(Path(yaml.safe_load(Path(task["normal_full_config"]).read_text())["pricefm_desn_full"]["python_bin"])),
            str(code_root / "application/scripts/pricefm/10_run_desn_model_full.py"),
            "--config", task["normal_full_config"],
            "--jobs", "1", "--resume", "true", "--force", "false", "--dry-run", "false",
            "--regions", task["region"], "--folds", str(task["fold"]), "--max-cells", "1",
        ]
    return [
        "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        str(code_root / "application/scripts/pricefm/308_run_pricefm_stage_r95_quantile_atom.R"),
        "--task-config", task["task_config"], "--code-root", str(code_root),
    ]


def run_one(
    row: dict[str, Any],
    cpu: int,
    args: argparse.Namespace,
    update_state,
) -> dict[str, Any]:
    task = load_task(row)
    task["task_config"] = row["task_config"]
    existing = terminal_state(task)
    if existing:
        status = "skipped_completed" if existing == "completed" else "skipped_numerically_ineligible"
        update_state(task["task_id"], {"status": status, "cpu": cpu, "process_alive": False})
        return {**row, "status": status, "cpu": cpu, "returncode": 0, "attempts": 0}
    quarantined: list[str] = []
    last_code = 1
    started_all = time.time()
    for attempt in range(1, args.retry_limit + 2):
        if Path(task["output_dir"]).exists() and any(Path(task["output_dir"]).iterdir()):
            quarantined.extend(quarantine_invalid_task(task))
        log = Path(task["output_dir"]) / f"worker_attempt_{attempt}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        command = command_for_task(task, args.code_root.resolve())
        started = time.time()
        with log.open("a") as handle:
            handle.write(f"START task={task['task_id']} attempt={attempt} cpu={cpu} epoch={started}\n")
            process = subprocess.Popen(
                ["taskset", "-c", str(cpu), *command],
                cwd=args.code_root,
                env=capped_environment(),
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
            update_state(task["task_id"], {
                "status": "running", "attempt": attempt, "cpu": cpu, "pid": process.pid,
                "started_at_epoch": started, "worker_log": str(log),
                **process_observation(process.pid),
            })
            while process.poll() is None:
                time.sleep(max(0.2, args.poll_seconds))
                update_state(task["task_id"], {
                    "status": "running", "attempt": attempt, "cpu": cpu, "pid": process.pid,
                    "elapsed_seconds": round(time.time() - started, 3),
                    "worker_log": str(log),
                    "worker_log_bytes": log.stat().st_size,
                    "worker_log_mtime": log.stat().st_mtime,
                    **process_observation(process.pid),
                })
            last_code = int(process.returncode)
            handle.write(f"END returncode={last_code} epoch={time.time()}\n")
        if last_code == 0 and task["runner_type"] == "normal_full":
            try:
                write_normal_terminal(task)
            except Exception as error:
                with log.open("a") as handle:
                    handle.write(f"NORMAL_TERMINAL_ERROR {error!r}\n")
                last_code = 1
        state = terminal_state(task)
        if state:
            final = "completed" if state == "completed" else "completed_numerically_ineligible"
            update_state(task["task_id"], {
                "status": final, "cpu": cpu, "pid": None, "process_alive": False,
                "returncode": last_code, "attempts": attempt,
                "elapsed_seconds": round(time.time() - started_all, 3),
            })
            return {
                **row, "status": final, "cpu": cpu, "returncode": last_code,
                "attempts": attempt, "elapsed_seconds": round(time.time() - started_all, 3),
                "quarantined_partials": json.dumps(quarantined),
            }
    update_state(task["task_id"], {
        "status": "failed", "cpu": cpu, "pid": None, "process_alive": False,
        "returncode": last_code, "attempts": args.retry_limit + 1,
        "elapsed_seconds": round(time.time() - started_all, 3),
    })
    return {
        **row, "status": "failed", "cpu": cpu, "returncode": last_code,
        "attempts": args.retry_limit + 1,
        "elapsed_seconds": round(time.time() - started_all, 3),
        "quarantined_partials": json.dumps(quarantined),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values(["fold", "runner_type", "tau"], na_position="first")
    if args.cpu_list:
        cpus = parse_cpus(args.cpu_list)
        first, second = cpu_snapshot(), cpu_snapshot()
        usage = {cpu: max(first.get(cpu, 100.0), second.get(cpu, 100.0)) for cpu in first}
    else:
        cpus, usage = choose_cpus(args.workers, args.maximum_cpu_snapshot_percent)
    audit = preflight(manifest, args, cpus, usage)
    atomic_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return audit
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"R95 launch requires --approval-token {APPROVAL_TOKEN}")

    lock_path = args.manifest.parent / "launcher.lock"
    lock_handle = lock_path.open("a+")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        lock_handle.close()
        raise RuntimeError("another R95 launcher owns this manifest") from error
    try:
        pipeline = json.loads((args.manifest.parent / "pipeline_contract.json").read_text())
        prep_cpus = parse_cpus(args.prep_cpu_list) if args.prep_cpu_list else cpus[: min(2, len(cpus))]
        preprocessing = prepare_data(pipeline, args, prep_cpus)
        rows = {str(row["task_id"]): row for row in manifest.to_dict("records")}
        tasks = {task_id: load_task(row) for task_id, row in rows.items()}
        states: dict[str, dict[str, Any]] = {
            task_id: {
                "status": (
                    "completed" if terminal_state(task) == "completed" else
                    "completed_numerically_ineligible" if terminal_state(task) == "completed_numerically_ineligible" else
                    "queued"
                ),
                "fold": int(task["fold"]),
                "family": task["likelihood_family"],
                "tau": task.get("tau"),
                "parents": task.get("parent_task_ids") or [],
                "cpu": None,
                "pid": None,
            }
            for task_id, task in tasks.items()
        }
        state_lock = threading.Lock()

        def update_state(task_id: str, updates: dict[str, Any]) -> None:
            with state_lock:
                states[task_id].update(updates)
                counts = pd.Series([state["status"] for state in states.values()]).value_counts().to_dict()
                atomic_json(args.manifest.parent / "scheduler_state.json", {
                    "stage": "R95", "launcher_pid": os.getpid(),
                    "updated_at_epoch": time.time(), "preprocessing": preprocessing,
                    "counts": {str(key): int(value) for key, value in counts.items()},
                    "tasks": states, "test_opened": False,
                    "test_access_authorized": False,
                })

        first_task = next(iter(states))
        update_state(first_task, {})
        statuses: list[dict[str, Any]] = []
        available = list(cpus[: args.workers])
        running: dict[Any, tuple[str, int]] = {}
        unfinished = {
            task_id for task_id, state in states.items()
            if state["status"] not in {"completed", "completed_numerically_ineligible"}
        }
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            while unfinished or running:
                progress = False
                for task_id in sorted(list(unfinished)):
                    parents = tasks[task_id].get("parent_task_ids") or []
                    parent_states = [states[str(parent)]["status"] for parent in parents]
                    if any(state in {"failed", "blocked_dependency"} for state in parent_states):
                        states[task_id]["status"] = "blocked_dependency"
                        unfinished.remove(task_id)
                        statuses.append({**rows[task_id], "status": "blocked_dependency"})
                        update_state(task_id, {"status": "blocked_dependency"})
                        progress = True
                        continue
                    if any(state == "completed_numerically_ineligible" for state in parent_states):
                        states[task_id]["status"] = "blocked_dependency"
                        unfinished.remove(task_id)
                        statuses.append({**rows[task_id], "status": "blocked_dependency"})
                        update_state(task_id, {"status": "blocked_dependency"})
                        progress = True
                        continue
                    if available and all(state in {"completed", "skipped_completed"} for state in parent_states):
                        cpu = available.pop(0)
                        future = pool.submit(run_one, rows[task_id], cpu, args, update_state)
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
                            result = {**rows[task_id], "status": "failed", "error": repr(error), "cpu": cpu}
                            update_state(task_id, {"status": "failed", "error": repr(error)})
                        statuses.append(result)
                        available.append(cpu)
                        available.sort()
                        atomic_csv(args.manifest.parent / "launch_status.csv", pd.DataFrame(statuses))
                        progress = True
                if not progress and unfinished:
                    raise RuntimeError("R95 dependency scheduler reached an unresolved deadlock")

        status_frame = pd.DataFrame(statuses)
        current = {task_id: terminal_state(task) for task_id, task in tasks.items()}
        completed = sum(state == "completed" for state in current.values())
        ineligible = sum(state == "completed_numerically_ineligible" for state in current.values())
        failures = 30 - completed - ineligible
        closeout = None
        if failures == 0:
            closeout_command = [
                str(Path(yaml.safe_load(Path(pipeline["normal_full_config"]["path"]).read_text())["pricefm_desn_full"]["python_bin"])),
                str(args.code_root / "application/scripts/pricefm/310_closeout_pricefm_stage_r95_allfold_validation.py"),
                "--manifest", str(args.manifest),
                "--r94-frozen", pipeline["family_selection_source"]["path"],
                "--output-dir", str(args.closeout_output_dir),
            ]
            closeout_log = args.manifest.parent / "closeout.log"
            code = run_logged(closeout_command, closeout_log, cwd=args.code_root, cpus=[cpus[0]])
            closeout = {"returncode": code, "log": str(closeout_log), "output_dir": str(args.closeout_output_dir)}
            if code != 0:
                failures += 1
        status = (
            "completed_validation_closeout" if failures == 0 else
            "completed_with_numerically_ineligible_exal" if completed + ineligible == 30 else
            "completed_with_failures"
        )
        summary = {
            "status": status,
            "tasks": 30,
            "completed": completed,
            "numerically_ineligible": ineligible,
            "failed_or_blocked": failures,
            "workers": args.workers,
            "cpu_ids": cpus[: args.workers],
            "preprocessing": preprocessing,
            "closeout": closeout,
            "test_opened": False,
            **{name: False for name in BLOCKED},
        }
        atomic_json(args.manifest.parent / "launch_summary.json", summary)
        return summary
    finally:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        lock_handle.close()


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {
        "preflight_passed_not_launched",
        "completed_validation_closeout",
        "completed_with_numerically_ineligible_exal",
    } else 1


if __name__ == "__main__":
    raise SystemExit(main())
