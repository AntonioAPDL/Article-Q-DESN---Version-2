#!/usr/bin/env python3
"""Launch the frozen R90 scoring-only test audit with one process per CPU."""

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
TAG = "pricefm_stage_r90_scoring_only_test_audit_20260905"
GRID = DATA / "experiment_grids" / TAG
PREP = DATA / "authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905"
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=GRID / "task_manifest.csv")
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--minimum-free-gib", type=float, default=20.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=20.0)
    p.add_argument("--maximum-cpu-snapshot-percent", type=float, default=25.0)
    p.add_argument("--authorize", action="store_true")
    p.add_argument("--preflight-only", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, payload: Any) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    tmp = path.with_name(path.name + ".tmp")
    frame.to_csv(tmp, index=False)
    tmp.replace(path)


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
            low, high = map(int, token.split("-", 1))
            cpus.extend(range(low, high + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise RuntimeError("CPU list must contain unique logical CPU IDs")
    if not set(cpus).issubset(set(range(os.cpu_count() or 0))):
        raise RuntimeError("CPU list contains an offline or out-of-range ID")
    return cpus


def _proc_cpu_times() -> dict[int, tuple[int, int]]:
    values = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
            ticks = [int(value) for value in fields[1:]]
            values[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
    return values


def least_busy_cpus(count: int, maximum: float) -> list[int]:
    before = _proc_cpu_times(); time.sleep(0.75); after = _proc_cpu_times()
    usage = {}
    for cpu in sorted(set(before) & set(after)):
        total = after[cpu][0] - before[cpu][0]
        idle = after[cpu][1] - before[cpu][1]
        usage[cpu] = 100.0 * (1.0 - idle / total) if total else 100.0
    eligible = [cpu for cpu, value in sorted(usage.items(), key=lambda x: (x[1], x[0])) if value <= maximum]
    if len(eligible) < count:
        raise RuntimeError(f"Only {len(eligible)} CPUs satisfy the <= {maximum}% snapshot gate")
    return eligible[:count]


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def completion_state(row: dict[str, Any]) -> str | None:
    output = Path(row["output_dir"])
    terminal_path = output / "terminal.json"
    if not terminal_path.is_file():
        return None
    terminal = json.loads(terminal_path.read_text())
    if (
        terminal.get("status") != "completed" or terminal.get("stage") != "R90"
        or terminal.get("task_id") != row["task_id"]
        or terminal.get("case_id") != row["case_id"]
        or terminal.get("model_fitted") is not False
    ):
        return None
    for terminal_key, row_key in (
        ("task_config_sha256", "task_config_sha256"),
        ("config_sha256", "config_sha256"),
        ("selected_manifest_sha256", "selected_manifest_sha256"),
        ("scorer_script_sha256", "scorer_script_sha256"),
        ("adapter_script_sha256", "adapter_script_sha256"),
    ):
        if terminal.get(terminal_key) != row[row_key]:
            return None
    for name, expected in (terminal.get("retained_artifact_sha256") or {}).items():
        path = Path(row["adapter_dir"]) / name if name in {
            "rows_test.csv", "adapter_manifest.json", "feature_manifest.json"
        } else output / name
        if not path.is_file() or sha256(path) != expected:
            return None
    return "completed"


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    prep = json.loads((args.prep_dir / "summary.json").read_text())
    if prep.get("status") != "scoring_only_test_audit_prepared_not_run" or prep.get("test_opened") is not False:
        raise RuntimeError("R90 prep is not frozen and test-sealed")
    if len(manifest) != 56 or manifest.task_id.duplicated().any() or manifest.case_id.nunique() != 56:
        raise RuntimeError("R90 requires exactly 56 unique case tasks")
    if not manifest.test_access_authorized.map(boolish).all():
        raise RuntimeError("R90 test scoring is not authorized")
    for name in BLOCKED:
        if manifest[name].map(boolish).any():
            raise RuntimeError(f"R90 manifest authorizes forbidden action: {name}")
    if args.workers < 1 or len(cpus) < args.workers:
        raise RuntimeError("R90 requires one unique CPU per worker")
    for row in manifest.itertuples(index=False):
        for path_name, hash_name in (
            ("task_config", "task_config_sha256"),
            ("config", "config_sha256"),
            ("selected_manifest", "selected_manifest_sha256"),
            ("scorer_script", "scorer_script_sha256"),
            ("adapter_script", "adapter_script_sha256"),
        ):
            path = Path(getattr(row, path_name))
            if not path.is_file() or sha256(path) != str(getattr(row, hash_name)):
                raise RuntimeError(f"Changed R90 launch input: {path}")
    free = shutil.disk_usage(DATA).free / 1024**3
    memory = available_memory_gib()
    if free < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError(f"R90 resource gate failed: disk={free:.1f} GiB memory={memory:.1f} GiB")
    return {
        "tasks": 56, "workers": args.workers, "cpu_ids": cpus[:args.workers],
        "one_process_per_cpu": True, "threads_per_process": 1,
        "free_disk_gib": round(free, 3), "available_memory_gib": round(memory, 3),
        "model_refits": 0, "selection_frozen": True, "test_scoring_authorized": True,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }


def run_one(row: dict[str, Any], cpu: int, code_root: Path) -> dict[str, Any]:
    output = Path(row["output_dir"]); output.mkdir(parents=True, exist_ok=True)
    log = output / "worker.log"
    if completion_state(row):
        return {**row, "cpu": cpu, "status": "skipped_completed", "returncode": 0,
                "elapsed_seconds": 0.0, "worker_log": str(log)}
    env = dict(os.environ)
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS",
    ):
        env[name] = "1"
    command = [
        "taskset", "-c", str(cpu), sys.executable,
        str(code_root / "application/scripts/pricefm/285_run_pricefm_stage_r90_scoring_only_case.py"),
        "--task-config", row["task_config"], "--code-root", str(code_root), "--force",
    ]
    started = time.time()
    with log.open("a") as handle:
        handle.write(f"START task={row['task_id']} cpu={cpu} time={started}\n")
        handle.flush()
        result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT)
        handle.write(f"END returncode={result.returncode} time={time.time()}\n")
    return {
        **row, "cpu": cpu, "status": completion_state(row) or "failed",
        "returncode": int(result.returncode), "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest).sort_values(["region", "fold"])
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy_cpus(
        args.workers, args.maximum_cpu_snapshot_percent
    )
    audit = preflight(manifest, args, cpus)
    atomic_json(args.manifest.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        return {"status": "preflight_passed_not_launched", **audit}
    if not args.authorize:
        raise RuntimeError("R90 scoring launch requires explicit --authorize")
    rows = manifest.to_dict("records"); statuses: list[dict[str, Any]] = []
    pool = ThreadPoolExecutor(max_workers=args.workers); pending: dict[Any, int] = {}; iterator = iter(rows)

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
                    result = {"task_id": "launcher_exception", "cpu": cpu,
                              "status": "launcher_exception", "returncode": 1, "error": repr(error)}
                statuses.append(result)
                frame = pd.DataFrame(statuses)
                sort = [name for name in ("region", "fold") if name in frame]
                atomic_csv(args.manifest.parent / "launch_status.csv", frame.sort_values(sort) if sort else frame)
                submit(cpu)
    finally:
        pool.shutdown(wait=True)
    frame = pd.DataFrame(statuses)
    completed = int(frame.status.isin(("completed", "skipped_completed")).sum())
    summary = {
        "status": "completed" if completed == 56 else "completed_with_failures",
        "tasks": 56, "completed": completed, "failed": 56 - completed,
        "workers": args.workers, "cpu_ids": cpus[:args.workers],
        "model_refits": 0, "test_opened": True,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_json(args.manifest.parent / "launch_summary.json", summary)
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {"preflight_passed_not_launched", "completed"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
