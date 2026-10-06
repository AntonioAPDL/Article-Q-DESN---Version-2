#!/usr/bin/env python3
"""Launch and close the resumable PriceFM R102B validation surfaces."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r102b_recursive_validation_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r102b_recursive_validation_20260916"
APPROVAL = "RUN_PRICEFM_R102B_RECURSIVE_VALIDATION"
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--code-root", type=Path, default=Path(__file__).resolve().parents[3])
    value.add_argument("--workers", type=int, default=12)
    value.add_argument("--cpu-list", default="17-28")
    value.add_argument("--approval-token", default="")
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--maximum-cpu-percent", type=float, default=10.0)
    value.add_argument("--minimum-free-gib", type=float, default=100.0)
    value.add_argument("--minimum-memory-gib", type=float, default=64.0)
    return value


def parse_cpus(value: str) -> list[int]:
    out = []
    for piece in str(value).split(","):
        piece = piece.strip()
        if "-" in piece:
            start, stop = map(int, piece.split("-", 1))
            out.extend(range(start, stop + 1))
        elif piece:
            out.append(int(piece))
    if not out or len(out) != len(set(out)) or any(cpu < 0 for cpu in out):
        raise ValueError("CPU list must contain unique non-negative IDs")
    return out


def git(command: list[str], root: Path) -> str:
    return subprocess.check_output(["git", *command], cwd=root, text=True).strip()


def git_identity(root: Path) -> dict[str, Any]:
    upstream = git(["rev-parse", "@{u}"], root)
    return {
        "branch": git(["branch", "--show-current"], root),
        "head": git(["rev-parse", "HEAD"], root),
        "upstream_head": upstream,
        "dirty": bool(git(["status", "--porcelain"], root)),
    }


def cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        out = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(x) for x in fields[1:]]
                out[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
        return out
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100.0 * (1.0 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        if after[cpu][0] > total else 100.0
        for cpu, (total, idle) in before.items()
    }


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def environment() -> dict[str, str]:
    value = dict(os.environ)
    for name in THREAD_ENV:
        value[name] = "1"
    value["PYTHONPATH"] = "application/scripts/pricefm"
    return value


def truthy(value: Any) -> bool:
    return value is True or str(value).strip().lower() in {"1", "true", "yes"}


def command(values: list[str], root: Path, log: Path, cpu: int | None = None) -> None:
    args = [str(x) for x in values]
    if cpu is not None:
        args = ["taskset", "-c", str(cpu), *args]
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as handle:
        handle.write("$ " + " ".join(args) + "\n")
        handle.flush()
        result = subprocess.run(args, cwd=root, env=environment(), stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError("command failed ({}); see {}".format(result.returncode, log))


def valid_surface(path: Path) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") != "completed_recursive_validation_surface" or terminal.get("test_opened") is not False:
            return False
        artifacts = {row["role"]: row for row in terminal.get("artifacts", [])}
        for row in artifacts.values():
            file = path / row["path"]
            if not file.is_file() or sha256_file(file) != row["sha256"]:
                return False
        origins = pd.read_csv(path / artifacts["origin_manifest"]["path"])
        return len(origins) == int(terminal["origins"]) and all(
            Path(row.path).is_file()
            and Path(row.terminal_path).is_file()
            and sha256_file(Path(row.path)) == str(row.sha256)
            and sha256_file(Path(row.terminal_path)) == str(row.terminal_sha256)
            for row in origins.itertuples(index=False)
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def preflight(args: argparse.Namespace) -> tuple[list[int], pd.DataFrame, dict[str, Any]]:
    prep = args.prep_dir.resolve()
    summary = json.loads((prep / "summary.json").read_text())
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R102B prep hash mismatch: {}".format(role))
    control = json.loads((prep / "pricefm_stage_r102b_launch_control.json").read_text())
    if sha256_file(prep / "pricefm_stage_r102b_launch_control.json") != summary["launch_control_sha256"]:
        raise RuntimeError("R102B launch-control hash mismatch")
    sources = pd.read_csv(prep / "source_manifest.csv")
    for row in sources.itertuples(index=False):
        if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256):
            raise RuntimeError("R102B source hash mismatch: {}".format(row.path))
    tasks = pd.read_csv(prep / "pricefm_stage_r102b_task_manifest.csv")
    if len(tasks) != 12 or tasks.test_access_authorized.map(truthy).any():
        raise RuntimeError("R102B task firewall failed")
    cpus = parse_cpus(args.cpu_list)
    if args.workers != len(cpus) or args.workers != int(control["workers"]):
        raise RuntimeError("workers must match the prepared R102B control and CPU count")
    identity = git_identity(args.code_root.resolve())
    usage = cpu_snapshot()
    selected_usage = {cpu: usage[cpu] for cpu in cpus}
    resources = {
        "available_memory_gib": available_memory_gib(),
        "free_disk_gib": shutil.disk_usage(args.campaign_root.parent).free / 1024**3,
    }
    checks = {
        "approval_token": args.approval_token == APPROVAL,
        "clean_task_branch": not identity["dirty"] and identity["head"] == identity["upstream_head"] and identity["branch"].startswith("work/pricefm-"),
        "cpus": all(value <= args.maximum_cpu_percent for value in selected_usage.values()),
        "disk": resources["free_disk_gib"] >= args.minimum_free_gib,
        "memory": resources["available_memory_gib"] >= args.minimum_memory_gib,
    }
    audit = {
        "stage": "R102B",
        "status": "preflight_passed_not_launched" if all(checks.values()) else "preflight_blocked",
        "checks": checks,
        "git_identity": identity,
        "selected_cpu_percent": selected_usage,
        "resources": resources,
        "workers": args.workers,
        "surface_tasks": len(tasks),
        "test_opened": False,
    }
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    write_json(args.campaign_root / "launch_preflight.json", audit)
    if not args.preflight_only and not all(checks.values()):
        raise RuntimeError("R102B preflight blocked: {}".format([key for key, value in checks.items() if not value]))
    return cpus, tasks, audit


def run(args: argparse.Namespace) -> dict[str, Any]:
    cpus, tasks, audit = preflight(args)
    if args.preflight_only:
        return audit
    pending = [row for row in tasks.itertuples(index=False) if not valid_surface(Path(row.output_dir))]
    lock = threading.Lock()
    progress = {"complete": len(tasks) - len(pending), "failed": 0, "total": len(tasks)}
    buckets = [[] for _ in cpus]
    for index, row in enumerate(pending):
        buckets[index % len(cpus)].append(row)

    def worker(cpu: int, bucket: list[Any]) -> None:
        for row in bucket:
            ok = False
            try:
                command([
                    str(DATA / "venv/bin/python"),
                    str(args.code_root / "application/scripts/pricefm/340_run_pricefm_stage_r102b_recursive_validation.py"),
                    "--prep-dir", str(args.prep_dir),
                    "--task-id", str(row.task_id),
                ], args.code_root, args.campaign_root / "logs" / "{}.log".format(row.task_id), cpu)
                ok = valid_surface(Path(row.output_dir))
            finally:
                with lock:
                    progress["complete" if ok else "failed"] += 1
                    progress["updated_at_epoch"] = time.time()
                    write_json(args.campaign_root / "surface_progress.json", progress)
            if not ok:
                raise RuntimeError("R102B task failed: {}".format(row.task_id))

    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures):
            future.result()
    if not all(valid_surface(Path(path)) for path in tasks.output_dir):
        raise RuntimeError("R102B surfaces are incomplete")
    closeout = DATA / "authoritative/pricefm_stage_r102b_recursive_validation_closeout_20260916"
    command([
        str(DATA / "venv/bin/python"),
        str(args.code_root / "application/scripts/pricefm/341_closeout_pricefm_stage_r102b_recursive_validation.py"),
        "--prep-dir", str(args.prep_dir),
        "--output-dir", str(closeout),
        "--force",
    ], args.code_root, args.campaign_root / "logs/closeout.log")
    summary = json.loads((closeout / "summary.json").read_text())
    terminal = {
        "stage": "R102B",
        "status": summary["status"],
        "surface_tasks_complete": summary["surface_tasks_complete"],
        "posterior_paths": summary["posterior_paths"],
        "selected_panel": summary["selected_panel"],
        "aggregate_validation_AQL_original": summary["aggregate_validation_AQL_original"],
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "closeout_summary_path": str((closeout / "summary.json").resolve()),
        "closeout_summary_sha256": sha256_file(closeout / "summary.json"),
        "next_gate": summary["next_gate"],
    }
    write_json(args.campaign_root / "campaign_terminal.json", terminal)
    return terminal


def main() -> int:
    args = parser().parse_args()
    args.prep_dir = args.prep_dir.resolve()
    args.campaign_root = args.campaign_root.resolve()
    args.code_root = args.code_root.resolve()
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    with (args.campaign_root / "controller.lock").open("a+") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("another R102B controller owns this campaign") from error
        result = run(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
