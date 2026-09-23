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


def closeout_gate(closeout_root: Path) -> tuple[bool, dict]:
    matched = process_matches()
    active_sessions = sorted(set(ACTIVE_SESSIONS) & sessions())
    cert = certification_complete(closeout_root)
    return not matched and not active_sessions and cert, {
        "matching_processes": matched, "active_sessions": active_sessions,
        "quantile_certification_complete": cert,
    }


def resource_gate() -> tuple[bool, dict]:
    cpus = os.cpu_count() or 1
    mem = run(["bash", "-lc", "awk '/MemAvailable/ {print int($2/1024/1024)}' /proc/meminfo"], Path("/"), check=False)
    available_gib = int(mem.stdout.strip() or 0)
    disk = shutil.disk_usage("/data")
    free_gib = int(disk.free / 1024**3)
    load1 = os.getloadavg()[0]
    ok = cpus >= 40 and available_gib >= 100 and free_gib >= 100 and load1 <= 12
    return ok, {"logical_cpus": cpus, "available_memory_gib": available_gib, "data_free_gib": free_gib, "load1": load1}


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
    ready, source = source_ready(repo)
    if not ready:
        raise RuntimeError(f"Search III source is not clean and synchronized: {source}")
    if args.dry_run:
        gate, closeout_state = closeout_gate(closeout)
        resources, resource_state = resource_gate()
        print(json.dumps({"source": source, "closeout_gate": gate, "closeout": closeout_state,
                          "resource_gate": resources, "resources": resource_state,
                          "workers": args.workers, "capacity": args.capacity}, indent=2))
        return 0
    if not args.controller:
        if shutil.which("tmux") is None:
            raise RuntimeError("tmux is required for detached Search III launch")
        if args.session_label in sessions():
            raise RuntimeError(f"tmux session already exists: {args.session_label}")
        cmd = [sys.executable, str(Path(__file__).resolve()), "--campaign-root", str(campaign),
               "--search2-ridge-root", str(ridge), "--closeout-root", str(closeout),
               "--workers", str(args.workers), "--capacity", str(args.capacity),
               "--poll-seconds", str(args.poll_seconds), "--rscript", rscript, "--controller"]
        if args.data_root:
            cmd.extend(["--data-root", args.data_root])
        subprocess.run(["tmux", "new-session", "-d", "-s", args.session_label, shlex.join(cmd)], check=True)
        print(f"session={args.session_label}\ncampaign_root={campaign}\nworkers={args.workers}\ncapacity={args.capacity}")
        return 0

    campaign.mkdir(parents=True, exist_ok=True)
    (campaign / "logs").mkdir(exist_ok=True)
    with (campaign / "logs/controller.log").open("a", buffering=1) as log:
        log.write(f"controller_start source_head={source['head']} workers={args.workers} capacity={args.capacity}\n")
        while True:
            gate, closeout_state = closeout_gate(closeout)
            resources, resource_state = resource_gate()
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
