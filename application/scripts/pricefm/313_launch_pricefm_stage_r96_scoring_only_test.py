#!/usr/bin/env python3
"""Launch the three-fold R96 scoring-only test audit and automatic closeout."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r96_se2_scoring_only_test_20260908"
GRID = DATA / "experiment_grids" / TAG
PREP = DATA / "authoritative/pricefm_stage_r96_scoring_only_test_prep_20260908"
CLOSEOUT = DATA / "authoritative/pricefm_stage_r96_scoring_only_test_closeout_20260908"
APPROVAL_TOKEN = "RUN_PRICEFM_R96_SCORING_ONLY_TEST"
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--manifest", type=Path, default=GRID / "task_manifest.csv")
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--workers", type=int, default=3)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--minimum-free-gib", type=float, default=40.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=20.0)
    value.add_argument("--maximum-cpu-snapshot-percent", type=float, default=25.0)
    value.add_argument("--approval-token", default="")
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--closeout-output-dir", type=Path, default=CLOSEOUT)
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, payload: Any) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    temporary = path.with_name(path.name + ".tmp")
    frame.to_csv(temporary, index=False)
    temporary.replace(path)


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"true", "1", "yes", "y", "on"}


def parse_cpus(value: str) -> list[int]:
    cpus: list[int] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = map(int, token.split("-", 1))
            cpus.extend(range(lower, upper + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise RuntimeError("R96 CPU list must contain unique logical CPU IDs")
    if not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise RuntimeError("R96 CPU list contains an offline or out-of-range ID")
    return cpus


def _proc_cpu_times() -> dict[int, tuple[int, int]]:
    values = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
            ticks = [int(value) for value in fields[1:]]
            values[int(fields[0][3:])] = (
                sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0),
            )
    return values


def cpu_snapshot() -> dict[int, float]:
    before = _proc_cpu_times()
    time.sleep(0.8)
    after = _proc_cpu_times()
    usage = {}
    for cpu in sorted(set(before) & set(after)):
        total = after[cpu][0] - before[cpu][0]
        idle = after[cpu][1] - before[cpu][1]
        usage[cpu] = 100.0 * (1.0 - idle / total) if total else 100.0
    return usage


def least_busy_cpus(count: int, maximum: float) -> tuple[list[int], dict[int, float]]:
    usage = cpu_snapshot()
    eligible = [
        cpu for cpu, value in sorted(usage.items(), key=lambda item: (item[1], item[0]))
        if value <= maximum
    ]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs pass the R96 <= {maximum}% gate")
    return eligible[:count], usage


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def completion_state(row: dict[str, Any]) -> str | None:
    terminal_path = Path(row["output_dir"]) / "terminal.json"
    if not terminal_path.is_file():
        return None
    terminal = json.loads(terminal_path.read_text())
    if (
        terminal.get("status") != "completed"
        or terminal.get("stage") != "R96"
        or terminal.get("task_id") != row["task_id"]
        or terminal.get("case_id") != row["case_id"]
        or terminal.get("task_config_sha256") != row["task_config_sha256"]
        or terminal.get("validation_replay_passed") is not True
        or terminal.get("model_fitted") is not False
        or terminal.get("selection_changed") is not False
    ):
        return None
    task = json.loads(Path(row["task_config"]).read_text())
    adapter = Path(task["adapter_dir"])
    for name, expected in terminal.get("retained_artifact_sha256", {}).items():
        path = adapter / name if name in {
            "rows_test.csv", "rows_val.csv", "adapter_manifest.json", "feature_manifest.json"
        } else Path(row["output_dir"]) / name
        if not path.is_file() or sha256(path) != expected:
            return None
    return "completed"


def preflight(
    manifest: pd.DataFrame,
    args: argparse.Namespace,
    cpus: list[int],
    usage: dict[int, float],
) -> tuple[dict[str, Any], dict[str, Any]]:
    prep = json.loads((args.prep_dir / "summary.json").read_text())
    pipeline_path = args.manifest.parent / "pipeline_contract.json"
    pipeline = json.loads(pipeline_path.read_text())
    if (
        prep.get("status") != "r96_scoring_only_test_prepared_not_run"
        or prep.get("test_opened") is not False
        or prep.get("test_access_authorized") is not True
        or prep.get("pipeline_contract_sha256") != pipeline.get("pipeline_contract_sha256")
    ):
        raise RuntimeError("R96 preparation is not frozen and authorized")
    if len(manifest) != 3 or manifest.task_id.duplicated().any() or manifest.fold.astype(int).tolist() != [1, 2, 3]:
        raise RuntimeError("R96 requires exactly one scoring task per SE_2 fold")
    if not manifest.test_access_authorized.map(boolish).all():
        raise RuntimeError("R96 test scoring is not authorized")
    for name in BLOCKED:
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R96 manifest authorizes forbidden action: {name}")
    for row in manifest.itertuples(index=False):
        task_path = Path(row.task_config)
        if not task_path.is_file() or sha256(task_path) != row.task_config_sha256:
            raise RuntimeError(f"Changed R96 task: {task_path}")
        task = json.loads(task_path.read_text())
        for path_key, hash_key in (
            ("config", "config_sha256"), ("selected_manifest", "selected_manifest_sha256"),
            ("reference_manifest", "reference_manifest_sha256"),
            ("scorer_script", "scorer_script_sha256"), ("adapter_script", "adapter_script_sha256"),
        ):
            path = Path(task[path_key])
            if not path.is_file() or sha256(path) != task[hash_key]:
                raise RuntimeError(f"Changed R96 launch input: {path}")
    expected = pipeline["git_identity"]
    code_root = args.code_root.resolve()
    observed = {
        "branch": git_value(code_root, "branch", "--show-current"),
        "head": git_value(code_root, "rev-parse", "HEAD"),
        "upstream": git_value(code_root, "rev-parse", "--abbrev-ref", "@{upstream}"),
        "upstream_head": git_value(code_root, "rev-parse", "@{upstream}"),
        "clean": not bool(git_value(code_root, "status", "--porcelain=v1", "--untracked-files=normal")),
    }
    if any(observed[key] != expected[key] for key in ("branch", "head", "upstream", "upstream_head")) or not observed["clean"]:
        raise RuntimeError(f"R96 git identity changed after preparation: {observed}")
    free = shutil.disk_usage(DATA).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R96 resource gate failed: disk={free:.1f} GiB memory={memory:.1f} GiB")
    selected_usage = {str(cpu): round(usage.get(cpu, 0.0), 3) for cpu in cpus[:args.workers]}
    return ({
        "status": "preflight_passed_not_launched", "tasks": 3,
        "workers": args.workers, "cpu_ids": cpus[:args.workers],
        "cpu_snapshot_percent": selected_usage,
        "one_process_per_cpu": True, "threads_per_process": 1,
        "free_disk_gib": round(free, 3), "available_memory_gib": round(memory, 3),
        "model_refits": 0, "selection_frozen": True,
        "test_scoring_authorized": True,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "git_identity": observed,
    }, pipeline)


def run_logged(command: list[str], log: Path, code_root: Path, cpus: list[int]) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS",
    ):
        env[name] = "1"
    wrapped = ["taskset", "-c", ",".join(map(str, cpus)), *command]
    with log.open("w") as handle:
        result = subprocess.run(wrapped, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
    return int(result.returncode)


def prepare_data(pipeline: dict[str, Any], args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    terminal_path = args.manifest.parent / "preprocessing_terminal.json"
    processed = Path(pipeline["processed_dir"])
    if terminal_path.is_file():
        terminal = json.loads(terminal_path.read_text())
        if (
            terminal.get("status") == "completed"
            and terminal.get("pipeline_contract_sha256") == pipeline["pipeline_contract_sha256"]
            and terminal.get("test_opened") is True
        ):
            return terminal
    if processed.exists() and any(processed.iterdir()):
        raise RuntimeError("R96 partial preprocessing exists without a valid terminal")
    config = pipeline["generated_data_config"]["path"]
    logs = args.manifest.parent / "preprocessing_logs"
    commands = [
        [sys.executable, "application/scripts/pricefm/03_make_splits.py", "--config", config, "--force", "true"],
        [sys.executable, "application/scripts/pricefm/04_fit_scalers.py", "--config", config, "--force", "true"],
        [
            sys.executable, "application/scripts/pricefm/05_build_windows.py",
            "--config", config, "--force", "true", "--pilot-only", "false",
            "--regions", ",".join(pipeline["active_window_regions"]),
            "--folds", ",".join(map(str, pipeline["folds"])),
        ],
    ]
    for index, command in enumerate(commands, start=1):
        code = run_logged(command, logs / f"stage_{index}.log", args.code_root.resolve(), cpus)
        if code:
            raise RuntimeError(f"R96 preprocessing stage {index} failed; see {logs / f'stage_{index}.log'}")
    artifacts = []
    for fold in pipeline["folds"]:
        scaler = processed / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
        artifacts.append({"path": str(scaler), "sha256": sha256(scaler), "role": f"fold{fold}_scaler"})
        for region in pipeline["active_window_regions"]:
            for split in ("val", "test"):
                window = processed / (
                    f"windows/fold_{fold}/region={region}/{split}_L240_H96_operational_half_open.npz"
                )
                artifacts.append({"path": str(window), "sha256": sha256(window), "role": f"fold{fold}_{region}_{split}"})
    terminal = {
        "status": "completed", "pipeline_contract_sha256": pipeline["pipeline_contract_sha256"],
        "artifacts": artifacts, "test_opened": True, "test_access_authorized": True,
        "model_fitted": False,
    }
    atomic_json(terminal_path, terminal)
    return terminal


def run_one(row: dict[str, Any], cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row["output_dir"])
    output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    if completion_state(row):
        return {**row, "cpu": cpu, "status": "skipped_completed", "returncode": 0,
                "elapsed_seconds": 0.0, "worker_log": str(log)}
    command = [
        sys.executable,
        str(code_root / "application/scripts/pricefm/312_run_pricefm_stage_r96_scoring_only_fold.py"),
        "--task-config", row["task_config"], "--code-root", str(code_root), "--force",
    ]
    started = time.time()
    code = run_logged(command, log, code_root, [cpu])
    return {
        **row, "cpu": cpu, "status": completion_state(row) or "failed",
        "returncode": code, "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values("fold")
    if args.workers < 1 or args.workers > 3:
        raise RuntimeError("R96 workers must be between 1 and 3")
    if args.cpu_list:
        cpus = parse_cpus(args.cpu_list)
        usage = cpu_snapshot()
        if len(cpus) < args.workers:
            raise RuntimeError("R96 requires one unique CPU per worker")
        if any(usage.get(cpu, 100.0) > args.maximum_cpu_snapshot_percent for cpu in cpus[:args.workers]):
            raise RuntimeError("An explicitly selected R96 CPU exceeds the utilization gate")
    else:
        cpus, usage = least_busy_cpus(args.workers, args.maximum_cpu_snapshot_percent)
    audit, pipeline = preflight(manifest, args, cpus, usage)
    atomic_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return audit
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"R96 scoring launch requires --approval-token {APPROVAL_TOKEN}")
    preprocessing = prepare_data(pipeline, args, cpus[: min(3, len(cpus))])

    rows = manifest.to_dict("records")
    statuses: list[dict[str, Any]] = []
    pending: dict[Any, int] = {}
    iterator = iter(rows)
    pool = ThreadPoolExecutor(max_workers=args.workers)

    def submit(cpu: int) -> None:
        try:
            row = next(iterator)
        except StopIteration:
            return
        pending[pool.submit(run_one, row, cpu, args.code_root.resolve())] = cpu

    for cpu in cpus[:args.workers]:
        submit(cpu)
    try:
        while pending:
            done, _ = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                cpu = pending.pop(future)
                try:
                    result = future.result()
                except Exception as error:
                    result = {
                        "task_id": "launcher_exception", "cpu": cpu,
                        "status": "launcher_exception", "returncode": 1,
                        "error": repr(error),
                    }
                statuses.append(result)
                status_frame = pd.DataFrame(statuses)
                sort_columns = [
                    name for name in ("region", "fold") if name in status_frame.columns
                ]
                atomic_csv(
                    args.manifest.parent / "launch_status.csv",
                    status_frame.sort_values(sort_columns) if sort_columns else status_frame,
                )
                submit(cpu)
    finally:
        pool.shutdown(wait=True)
    frame = pd.DataFrame(statuses)
    completed = int(frame.status.isin(("completed", "skipped_completed")).sum())
    summary = {
        "status": "completed_scoring_only_test" if completed == 3 else "completed_with_failures",
        "tasks": 3, "completed": completed, "failed": 3 - completed,
        "workers": args.workers, "cpu_ids": cpus[:args.workers],
        "preprocessing": {"status": preprocessing["status"], "artifacts": len(preprocessing["artifacts"])},
        "model_refits": 0, "selection_changes": 0,
        "test_opened": True, "test_access_authorized": True,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_json(args.manifest.parent / "launch_summary.json", summary)
    if completed == 3:
        closeout_script = args.code_root / "application/scripts/pricefm/314_closeout_pricefm_stage_r96_scoring_only_test.py"
        closeout_log = args.manifest.parent / "closeout.log"
        code = run_logged([
            sys.executable, str(closeout_script),
            "--grid-dir", str(args.manifest.parent),
            "--prep-dir", str(args.prep_dir),
            "--output-dir", str(args.closeout_output_dir),
        ], closeout_log, args.code_root.resolve(), [cpus[0]])
        summary["closeout"] = {
            "returncode": code, "log": str(closeout_log),
            "output_dir": str(args.closeout_output_dir),
        }
        if code:
            summary["status"] = "completed_scoring_closeout_failed"
        atomic_json(args.manifest.parent / "launch_summary.json", summary)
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {"preflight_passed_not_launched", "completed_scoring_only_test"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
