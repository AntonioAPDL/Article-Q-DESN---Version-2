#!/usr/bin/env python3
"""Run the resumable R102 causal Normal refit campaign."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_recursive_normal import posterior_target_hash


SCRIPT_DIR = Path(__file__).resolve().parent
CODE_ROOT = SCRIPT_DIR.parents[2]
ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r102_recursive_normal_20260916"
APPROVAL = "RUN_PRICEFM_R102_RECURSIVE_NORMAL"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--code-root", type=Path, default=CODE_ROOT)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", default="0-19")
    p.add_argument("--approval-token", default="")
    p.add_argument("--preflight-only", action="store_true")
    p.add_argument("--minimum-free-gib", type=float, default=100.0)
    p.add_argument("--minimum-memory-gib", type=float, default=64.0)
    p.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    return p


def parse_cpus(value: str) -> list[int]:
    result: list[int] = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lo, hi = token.split("-", 1)
            result.extend(range(int(lo), int(hi) + 1))
        else:
            result.append(int(token))
    if not result or len(result) != len(set(result)) or min(result) < 0 or max(result) >= os.cpu_count():
        raise ValueError("invalid CPU list")
    return result


def truthy(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes"}


def command(cmd: list[str], cwd: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    full = ["taskset", "-c", str(cpu)] + cmd if cpu is not None else cmd
    with log.open("a") as handle:
        handle.write("$ {}\n".format(" ".join(map(str, full))))
        handle.flush()
        process = subprocess.run(full, cwd=str(cwd), stdout=handle, stderr=subprocess.STDOUT, check=False)
    if process.returncode:
        raise RuntimeError("command failed with status {}: {}".format(process.returncode, " ".join(cmd)))


def git_identity(root: Path) -> dict[str, Any]:
    def git(*parts: str) -> str:
        return subprocess.check_output(
            ["git", *parts], cwd=str(root), text=True, stderr=subprocess.DEVNULL
        ).strip()
    branch = git("branch", "--show-current")
    head = git("rev-parse", "HEAD")
    try:
        upstream = git("rev-parse", "@{upstream}")
    except subprocess.CalledProcessError:
        upstream = None
    dirty = bool(git("status", "--porcelain"))
    return {"branch": branch, "head": head, "upstream_head": upstream, "dirty": dirty}


def cpu_snapshot() -> dict[int, float]:
    first = Path("/proc/stat").read_text().splitlines()
    time.sleep(0.4)
    second = Path("/proc/stat").read_text().splitlines()
    def parse(lines: list[str]) -> dict[int, tuple[int, int]]:
        out = {}
        for line in lines:
            fields = line.split()
            if len(fields) < 5 or not fields[0].startswith("cpu") or fields[0] == "cpu":
                continue
            index = int(fields[0][3:])
            values = [int(x) for x in fields[1:]]
            idle = values[3] + (values[4] if len(values) > 4 else 0)
            out[index] = (sum(values), idle)
        return out
    a, b = parse(first), parse(second)
    return {cpu: 100.0 * (1.0 - (b[cpu][1] - a[cpu][1]) / max(1, b[cpu][0] - a[cpu][0])) for cpu in a}


def resources(path: Path) -> dict[str, float]:
    disk = shutil.disk_usage(path)
    available_kib = 0
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            available_kib = int(line.split()[1])
            break
    return {
        "free_disk_gib": disk.free / 2**30,
        "available_memory_gib": available_kib / 2**20,
    }


def valid_stats(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file():
        return False
    payload = json.loads(terminal.read_text())
    if payload.get("status") != "completed_causal_sufficient_statistics" or payload.get("test_opened"):
        return False
    return all((path / name).is_file() and sha256_file(path / name) == item["sha256"] for name, item in payload.get("files", {}).items())


def valid_fit(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file():
        return False
    payload = json.loads(terminal.read_text())
    if payload.get("status") != "completed_recursive_normal_fit" or payload.get("test_opened"):
        return False
    return all((path / item["path"]).is_file() and sha256_file(path / item["path"]) == item["sha256"] for item in payload.get("artifacts", []))


def preflight(args: argparse.Namespace) -> tuple[list[int], dict[str, Any], pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    prep = args.prep_dir.resolve()
    summary = json.loads((prep / "summary.json").read_text())
    control = json.loads((prep / "pricefm_stage_r102_launch_control.json").read_text())
    for key, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][key]:
            raise RuntimeError("R102 prep hash mismatch: {}".format(key))
    sources = pd.read_csv(prep / "source_manifest.csv")
    for row in sources.itertuples(index=False):
        if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256):
            raise RuntimeError("R102 source hash mismatch: {}".format(row.path))
    designs = pd.read_csv(prep / "pricefm_stage_r102_design_manifest.csv")
    fits = pd.read_csv(prep / "pricefm_stage_r102_fit_manifest.csv")
    windows = pd.read_csv(prep / "pricefm_stage_r102_window_requirements.csv")
    if (set(windows.split) != {"train", "val"}
            or designs.test_access_authorized.map(truthy).any()
            or fits.test_access_authorized.map(truthy).any()):
        raise RuntimeError("R102 split firewall failed")
    cpus = parse_cpus(args.cpu_list)
    if args.workers != len(cpus) or args.workers != int(control["workers"]):
        raise RuntimeError("workers must match the prepared control and CPU count")
    identity = git_identity(args.code_root.resolve())
    resource = resources(args.campaign_root.parent)
    usage = cpu_snapshot()
    selected_usage = {cpu: usage[cpu] for cpu in cpus}
    checks = {
        "approval_token": args.approval_token == APPROVAL,
        "clean_task_branch": not identity["dirty"] and identity["head"] == identity["upstream_head"] and identity["branch"].startswith("work/pricefm-"),
        "disk": resource["free_disk_gib"] >= args.minimum_free_gib,
        "memory": resource["available_memory_gib"] >= args.minimum_memory_gib,
        "cpus": all(value <= args.maximum_cpu_percent for value in selected_usage.values()),
    }
    audit = {
        "stage": "R102",
        "status": "preflight_passed_not_launched" if all(checks.values()) else "preflight_blocked",
        "checks": checks,
        "git_identity": identity,
        "resources": resource,
        "selected_cpu_percent": selected_usage,
        "workers": args.workers,
        "design_cells": len(designs),
        "fits": len(fits),
        "test_opened": False,
    }
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    write_json(args.campaign_root / "launch_preflight.json", audit)
    if not args.preflight_only and not all(checks.values()):
        raise RuntimeError("R102 production preflight is blocked: {}".format([key for key, value in checks.items() if not value]))
    return cpus, audit, designs, fits, windows


def prepare_processed(control: dict[str, Any], campaign: Path) -> None:
    runtime = Path(control["runtime_processed"])
    source = Path(control["source_processed"])
    runtime.mkdir(parents=True, exist_ok=True)
    for name in ("splits_scaled", "scalers"):
        destination = runtime / name
        if destination.is_symlink():
            if destination.resolve() != (source / name).resolve():
                raise RuntimeError("R102 processed symlink target changed")
        elif destination.exists():
            raise RuntimeError("R102 processed dependency exists but is not a symlink")
        else:
            destination.symlink_to(source / name, target_is_directory=True)
    write_json(campaign / "processed_dependency_manifest.json", {
        "status": "linked_read_only_dependencies",
        "source_processed": str(source.resolve()),
        "runtime_processed": str(runtime.resolve()),
        "test_opened": False,
    })


def build_windows(args: argparse.Namespace, windows: pd.DataFrame, cpus: list[int]) -> None:
    for index, (lag, group) in enumerate(windows.groupby("lag_window", sort=True)):
        regions = sorted(group.region.astype(str).unique())
        config = args.campaign_root / "configs" / "data_L{}.yaml".format(int(lag))
        command([
            str(DATA / "venv/bin/python"),
            str(args.code_root / "application/scripts/pricefm/05_build_windows.py"),
            "--config", str(config), "--pilot-only", "false",
            "--regions", ",".join(regions), "--folds", "1,2,3",
            "--resume", "true", "--force", "false",
        ], args.code_root, args.campaign_root / "logs/windows_L{}.log".format(int(lag)), cpus[index % len(cpus)])
    missing = [path for path in windows.runtime_path if not Path(path).is_file()]
    if missing:
        raise RuntimeError("R102 window build incomplete: {} missing".format(len(missing)))


def run_queue(tasks: list[tuple[str, list[str], Path]], cpus: list[int], root: Path, progress_path: Path) -> None:
    lock = threading.Lock()
    progress = {"complete": 0, "failed": 0, "total": len(tasks)}
    buckets = [[] for _ in cpus]
    for index, task in enumerate(tasks):
        buckets[index % len(cpus)].append(task)
    def worker(cpu: int, bucket: list[tuple[str, list[str], Path]]) -> None:
        for task_id, cmd, log in bucket:
            try:
                command(cmd, root, log, cpu)
                ok = True
            except Exception:
                ok = False
            with lock:
                progress["complete" if ok else "failed"] += 1
                progress["updated_at_epoch"] = time.time()
                write_json(progress_path, progress)
            if not ok:
                raise RuntimeError("R102 task failed: {}".format(task_id))
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures):
            future.result()


def run(args: argparse.Namespace) -> dict[str, Any]:
    cpus, audit, designs, fits, windows = preflight(args)
    if args.preflight_only:
        return audit
    prep_control = json.loads((args.prep_dir / "pricefm_stage_r102_launch_control.json").read_text())
    prepare_processed(prep_control, args.campaign_root)
    build_windows(args, windows, cpus)
    python = str(DATA / "venv/bin/python")
    pending_designs = designs[~designs.statistics_dir.map(lambda value: valid_stats(Path(value)))]
    design_tasks = [(
        str(row.design_id),
        [python, str(args.code_root / "application/scripts/pricefm/337_build_pricefm_stage_r102_recursive_statistics.py"),
         "--manifest", str(args.prep_dir / "pricefm_stage_r102_design_manifest.csv"), "--design-id", str(row.design_id), "--force"],
        args.campaign_root / "logs/statistics/{}.log".format(row.design_id),
    ) for row in pending_designs.itertuples(index=False)]
    run_queue(design_tasks, cpus, args.code_root, args.campaign_root / "statistics_progress.json")
    if not all(valid_stats(Path(path)) for path in designs.statistics_dir):
        raise RuntimeError("R102 statistics are incomplete")

    contract_root = args.campaign_root / "fit_contracts"
    contract_root.mkdir(parents=True, exist_ok=True)
    pending_fit_tasks = []
    for row in fits.itertuples(index=False):
        output = Path(row.output_dir)
        if valid_fit(output):
            continue
        output.parent.mkdir(parents=True, exist_ok=True)
        stats_terminal = Path(row.statistics_dir) / "terminal.json"
        stats_hash = sha256_file(stats_terminal)
        target_hash = posterior_target_hash(stats_hash, str(row.prior_type), None if pd.isna(row.tau0) else float(row.tau0))
        contract = {
            "fit_id": str(row.fit_id),
            "stats_dir": str(Path(row.statistics_dir).resolve()),
            "output_dir": str(output.resolve()),
            "prior_type": str(row.prior_type),
            "tau0": None if pd.isna(row.tau0) else float(row.tau0),
            "package_path": prep_control["normal_runtime"],
            "helper_path": str((args.code_root / "application/R/pricefm_recursive_normal_fit.R").resolve()),
            "max_iter": 100,
            "min_iter": 50,
            "tol": 1e-5,
            "posterior_target_sha256": target_hash,
            "selection_split": "train_validation_only",
            "test_access_authorized": False,
        }
        contract_path = contract_root / "{}.json".format(row.fit_id)
        write_json(contract_path, contract)
        pending_fit_tasks.append((
            str(row.fit_id),
            [prep_control["rscript"], str(args.code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)],
            args.campaign_root / "logs/fits/{}.log".format(row.fit_id),
        ))
    run_queue(pending_fit_tasks, cpus, args.code_root, args.campaign_root / "fits_progress.json")
    complete = sum(valid_fit(Path(path)) for path in fits.output_dir)
    if complete != len(fits):
        raise RuntimeError("R102 fit closeout incomplete: {}/{}".format(complete, len(fits)))
    terminal = {
        "stage": "R102A",
        "status": "completed_normal_refits_paths_pending",
        "design_cells_complete": len(designs),
        "fits_complete": complete,
        "rhs_complete": int(fits.prior_type.eq("rhs_ns").sum()),
        "ridge_complete": int(fits.prior_type.eq("scaled_ridge").sum()),
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "next_gate": "R102B_synchronized_validation_paths_and_complete_panel_freeze",
    }
    write_json(args.campaign_root / "campaign_terminal.json", terminal)
    return terminal


def main() -> int:
    args = parser().parse_args()
    args.prep_dir = args.prep_dir.resolve()
    args.campaign_root = args.campaign_root.resolve()
    args.code_root = args.code_root.resolve()
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    lock = (args.campaign_root / "controller.lock").open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R102 controller owns this campaign") from error
    try:
        result = run(args)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    finally:
        lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
