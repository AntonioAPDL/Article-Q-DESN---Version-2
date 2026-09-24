#!/usr/bin/env python3.11
"""Detached, gated, resumable controller for the full Search III campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time


STAGES = ("ridge_a", "ridge_b", "ridge_guard", "rhs_pilot", "rhs_screen", "confirmation")
ACTIVE_PATTERNS = (
    "389_continue_glofas_part4_joint_fit.R",
    "423_run_glofas_quantile_certification_continuation.R",
)
ACTIVE_SESSIONS = (
    "glofas_part4_joint_al_gatefix_r4_20260921",
    "glofas_part4_joint_exal_gatefix_r4_20260921",
    "glofas_quantile_selective_cont_r4_4core_20260922",
)
COMPATIBLE_OVERLAP_PROCESS_TOKENS = (
    "389_continue_glofas_part4_joint_fit.R",
    "--likelihood exal",
    "glofas_part4_joint_continuation_integrity_r4_gatefix_20260921",
)
COMPATIBLE_OVERLAP_SESSION = "glofas_part4_joint_exal_gatefix_r4_20260921"


def run(command, cwd, log=None, check=True):
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log is not None:
        log.write(f"$ {shlex.join(str(x) for x in command)}\n{result.stdout}")
        log.flush()
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {shlex.join(command)}\n{result.stdout}")
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_ready(repo: Path) -> tuple[bool, dict]:
    status = run(["git", "status", "--porcelain"], repo, check=False).stdout.strip()
    head = run(["git", "rev-parse", "HEAD"], repo).stdout.strip()
    divergence = run(["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"], repo, check=False)
    values = divergence.stdout.split()
    synced = divergence.returncode == 0 and values == ["0", "0"]
    return not status and synced, {"head": head, "dirty": bool(status), "divergence": values}


def process_matches() -> list[str]:
    output = subprocess.run(["ps", "-eo", "pid=,args="], text=True, stdout=subprocess.PIPE, check=True).stdout
    return [line.strip() for line in output.splitlines() if any(pattern in line for pattern in ACTIVE_PATTERNS)]


def sessions() -> set[str]:
    result = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return set(result.stdout.splitlines()) if result.returncode == 0 else set()


def certification_complete(closeout_root: Path) -> bool:
    path = closeout_root / "local_trackers/runtime_configs/glofas_quantile_selective_continuation_r4_20260922/tables/certification_continuation_health_latest.csv"
    if not path.exists():
        return False
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    return len(rows) == 8 and all(row.get("state") == "completed" for row in rows)


def closeout_gate(
    closeout_root: Path,
    allow_compatible_closeout_overlap: bool = False,
    *,
    matched_processes: list[str] | None = None,
    active_session_names: set[str] | None = None,
    cert_complete: bool | None = None,
) -> tuple[bool, dict]:
    """Require a complete closeout, optionally admitting one exact exAL worker.

    The injectable observations are used only by focused scheduler tests. The
    production path always probes the process table, tmux, and certification
    table directly.
    """
    matched = process_matches() if matched_processes is None else list(matched_processes)
    all_sessions = sessions() if active_session_names is None else set(active_session_names)
    active_sessions = sorted(set(ACTIVE_SESSIONS) & all_sessions)
    cert = certification_complete(closeout_root) if cert_complete is None else cert_complete
    compatible = [
        line for line in matched
        if all(token in line for token in COMPATIBLE_OVERLAP_PROCESS_TOKENS)
    ]
    blocking_processes = [line for line in matched if line not in compatible]
    compatible_session_active = COMPATIBLE_OVERLAP_SESSION in active_sessions
    blocking_sessions = [
        name for name in active_sessions if name != COMPATIBLE_OVERLAP_SESSION
    ]
    overlap_pair_valid = (
        len(compatible) == 1
        and compatible_session_active
        and not blocking_processes
        and not blocking_sessions
    )
    no_closeout_activity = not matched and not active_sessions
    overlap_workers = 1 if allow_compatible_closeout_overlap and overlap_pair_valid else 0
    activity_ok = no_closeout_activity or (
        allow_compatible_closeout_overlap and overlap_pair_valid
    )
    return activity_ok and cert, {
        "policy": "compatible_exal_overlap" if allow_compatible_closeout_overlap else "strict",
        "matching_processes": matched,
        "compatible_processes": compatible,
        "blocking_processes": blocking_processes,
        "active_sessions": active_sessions,
        "compatible_session_active": compatible_session_active,
        "blocking_sessions": blocking_sessions,
        "overlap_pair_valid": overlap_pair_valid,
        "overlap_workers": overlap_workers,
        "quantile_certification_complete": cert,
    }


def physical_cpu_count() -> int:
    result = subprocess.run(
        ["lscpu", "-p=Core,Socket"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode:
        return 0
    pairs = {
        tuple(field.strip() for field in line.split(",")[:2])
        for line in result.stdout.splitlines()
        if line and not line.startswith("#")
    }
    return len(pairs)


def evaluate_resource_state(
    *,
    logical_cpus: int,
    physical_cpus: int,
    available_memory_gib: int,
    data_free_gib: int,
    load1: float,
    workers: int,
    overlap_workers: int,
    max_total_workers: int,
) -> tuple[bool, dict]:
    planned_total_workers = workers + overlap_workers
    ok = (
        logical_cpus >= 40
        and physical_cpus >= max_total_workers
        and planned_total_workers <= max_total_workers
        and available_memory_gib >= 100
        and data_free_gib >= 100
        and load1 <= 12
    )
    return ok, {
        "logical_cpus": logical_cpus,
        "physical_cpus": physical_cpus,
        "available_memory_gib": available_memory_gib,
        "data_free_gib": data_free_gib,
        "load1": load1,
        "search3_workers": workers,
        "compatible_overlap_workers": overlap_workers,
        "planned_total_workers": planned_total_workers,
        "max_total_workers": max_total_workers,
    }


def resource_gate(workers: int, overlap_workers: int, max_total_workers: int) -> tuple[bool, dict]:
    logical_cpus = os.cpu_count() or 1
    physical_cpus = physical_cpu_count()
    mem = run(["bash", "-lc", "awk '/MemAvailable/ {print int($2/1024/1024)}' /proc/meminfo"], Path("/"), check=False)
    available_gib = int(mem.stdout.strip() or 0)
    disk = shutil.disk_usage("/data")
    free_gib = int(disk.free / 1024**3)
    load1 = os.getloadavg()[0]
    return evaluate_resource_state(
        logical_cpus=logical_cpus,
        physical_cpus=physical_cpus,
        available_memory_gib=available_gib,
        data_free_gib=free_gib,
        load1=load1,
        workers=workers,
        overlap_workers=overlap_workers,
        max_total_workers=max_total_workers,
    )


def stage_health(stage_root: Path) -> dict:
    path = stage_root / "tables/health_latest.csv"
    if not path.exists():
        return {}
    with path.open(newline="") as handle:
        return next(csv.DictReader(handle))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-root", required=True)
    parser.add_argument("--search2-ridge-root", required=True)
    parser.add_argument("--closeout-root", required=True)
    parser.add_argument("--data-root", default="")
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--capacity", type=int, default=28)
    parser.add_argument("--max-total-workers", type=int, default=28)
    parser.add_argument("--allow-compatible-closeout-overlap", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=300)
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--controller", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--session-label", default="glofas_search3_rainy_20core_20260923")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    campaign = Path(args.campaign_root).resolve()
    closeout = Path(args.closeout_root).resolve()
    ridge = Path(args.search2_ridge_root).resolve()
    rscript = shutil.which(args.rscript)
    if rscript is None:
        raise RuntimeError(f"Rscript is unavailable: {args.rscript}")
    if args.workers < 1 or args.workers > 20:
        raise RuntimeError("This Muscat campaign is capped at 20 one-thread workers")
    if args.max_total_workers < args.workers:
        raise RuntimeError("--max-total-workers cannot be smaller than --workers")
    ready, source = source_ready(repo)
    if not ready:
        raise RuntimeError(f"Search III source is not clean and synchronized: {source}")
    if args.dry_run:
        gate, closeout_state = closeout_gate(
            closeout,
            allow_compatible_closeout_overlap=args.allow_compatible_closeout_overlap,
        )
        resources, resource_state = resource_gate(
            args.workers,
            int(closeout_state["overlap_workers"]),
            args.max_total_workers,
        )
        print(json.dumps({"source": source, "closeout_gate": gate, "closeout": closeout_state,
                          "resource_gate": resources, "resources": resource_state,
                          "workers": args.workers, "capacity": args.capacity,
                          "max_total_workers": args.max_total_workers,
                          "allow_compatible_closeout_overlap": args.allow_compatible_closeout_overlap}, indent=2))
        return 0
    if not args.controller:
        if shutil.which("tmux") is None:
            raise RuntimeError("tmux is required for detached Search III launch")
        if args.session_label in sessions():
            raise RuntimeError(f"tmux session already exists: {args.session_label}")
        cmd = [sys.executable, str(Path(__file__).resolve()), "--campaign-root", str(campaign),
               "--search2-ridge-root", str(ridge), "--closeout-root", str(closeout),
               "--workers", str(args.workers), "--capacity", str(args.capacity),
               "--max-total-workers", str(args.max_total_workers),
               "--poll-seconds", str(args.poll_seconds), "--rscript", rscript, "--controller"]
        if args.allow_compatible_closeout_overlap:
            cmd.append("--allow-compatible-closeout-overlap")
        if args.data_root:
            cmd.extend(["--data-root", args.data_root])
        subprocess.run(["tmux", "new-session", "-d", "-s", args.session_label, shlex.join(cmd)], check=True)
        print(f"session={args.session_label}\ncampaign_root={campaign}\nworkers={args.workers}\ncapacity={args.capacity}\nmax_total_workers={args.max_total_workers}\nallow_compatible_closeout_overlap={args.allow_compatible_closeout_overlap}")
        return 0

    campaign.mkdir(parents=True, exist_ok=True)
    (campaign / "logs").mkdir(exist_ok=True)
    with (campaign / "logs/controller.log").open("a", buffering=1) as log:
        log.write(
            f"controller_start source_head={source['head']} workers={args.workers} "
            f"capacity={args.capacity} max_total_workers={args.max_total_workers} "
            f"allow_compatible_closeout_overlap={args.allow_compatible_closeout_overlap}\n"
        )
        while True:
            gate, closeout_state = closeout_gate(
                closeout,
                allow_compatible_closeout_overlap=args.allow_compatible_closeout_overlap,
            )
            resources, resource_state = resource_gate(
                args.workers,
                int(closeout_state["overlap_workers"]),
                args.max_total_workers,
            )
            record = {"checked_at": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
                      "closeout_gate": gate, "closeout": closeout_state,
                      "resource_gate": resources, "resources": resource_state}
            (campaign / "logs/gate_latest.json").write_text(json.dumps(record, indent=2) + "\n")
            log.write(f"gate closeout={gate} resources={resources} state={json.dumps(record, sort_keys=True)}\n")
            if gate and resources:
                break
            time.sleep(max(30, args.poll_seconds))

        manifest = campaign / "configs/campaign_manifest.yaml"
        if not manifest.exists():
            cmd = [rscript, "application/scripts/427_prepare_glofas_search3.R",
                   "--campaign_root", str(campaign), "--stage", "stage0",
                   "--search2_ridge_root", str(ridge)]
            if args.data_root:
                cmd.extend(["--data_root", args.data_root])
            run(cmd, repo, log=log)

        for stage in STAGES:
            stage_root = campaign / "stages" / stage
            if not (stage_root / "configs/job_manifest.csv").exists():
                run([rscript, "application/scripts/427_prepare_glofas_search3.R",
                     "--campaign_root", str(campaign), "--stage", stage], repo, log=log)
            health = stage_health(stage_root)
            completed = int(health.get("completed", 0) or 0)
            total = int(health.get("total", 0) or 0)
            failed = int(health.get("failed", 0) or 0)
            if failed:
                raise RuntimeError(f"Search III stage {stage} already contains {failed} failed jobs")
            if not total or completed != total:
                code = run([sys.executable, "application/scripts/430_launch_glofas_search3.py",
                            "--runtime-root", str(stage_root), "--workers", str(args.workers),
                            "--capacity", str(args.capacity), "--poll-seconds", "15",
                            "--rscript", rscript, "--scheduler"], repo, log=log, check=False).returncode
                run([rscript, "application/scripts/431_check_glofas_search3.R",
                     "--runtime_root", str(stage_root)], repo, log=log, check=False)
                health = stage_health(stage_root)
                if code or int(health.get("failed", 0) or 0) or int(health.get("completed", 0) or 0) != int(health.get("total", 0) or 0):
                    raise RuntimeError(f"Search III stage {stage} did not close cleanly: {health}")
            else:
                run([rscript, "application/scripts/431_check_glofas_search3.R",
                     "--runtime_root", str(stage_root)], repo, log=log)
            log.write(f"stage_complete stage={stage} health={json.dumps(health, sort_keys=True)}\n")

        completion = campaign / "stages/confirmation/status/CAMPAIGN_COMPLETE"
        if not completion.exists():
            raise RuntimeError("Search III confirmation closed without the scientific-adoption gate")
        inventory = []
        for path in sorted(campaign.rglob("*")):
            if path.is_file() and path.name != "artifact_manifest.csv":
                inventory.append({"relative_path": str(path.relative_to(campaign)), "size": path.stat().st_size, "sha256": sha256(path)})
        with (campaign / "tables/artifact_manifest.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=("relative_path", "size", "sha256")); writer.writeheader(); writer.writerows(inventory)
        log.write("SEARCH3_RAINY_SEASON_COMPLETE_PENDING_SCIENTIFIC_ADOPTION\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
