#!/usr/bin/env python3
"""Run the restartable PriceFM operational benchmark on idle physical cores."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time
from typing import Callable

from pricefm_operational_fullshot import (
    atomic_write_json,
    available_memory_gib,
    cpuset_text,
    free_disk_gib,
    idle_physical_cores,
    read_csv_rows,
    read_json,
    sha256_file,
    thread_limited_environment,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--python", required=True)
    p.add_argument("--config", required=True)
    p.add_argument("--raw-csv", required=True)
    p.add_argument("--upstream-root", required=True)
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--reference-window-root", required=True)
    p.add_argument("--qdesn-registry", required=True)
    p.add_argument("--log-root", required=True)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--required-idle-physical-cores", type=int, default=20)
    p.add_argument("--max-core-utilization", type=float, default=0.10)
    p.add_argument("--cpu-sample-seconds", type=float, default=5.0)
    p.add_argument("--poll-seconds", type=float, default=120.0)
    p.add_argument("--minimum-memory-gib", type=float, default=128.0)
    p.add_argument("--minimum-disk-gib", type=float, default=150.0)
    p.add_argument("--maximum-load-1m", type=float, default=36.0)
    p.add_argument("--maximum-attempts", type=int, default=2)
    return p


class Campaign:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        if args.workers != 20 or args.required_idle_physical_cores != 20:
            raise ValueError("This preregistered campaign requires exactly 20 workers and 20 idle physical cores")
        self.script_root = Path(__file__).resolve().parent
        self.python = Path(args.python).resolve()
        self.root = Path(args.artifact_root).resolve()
        self.log_root = Path(args.log_root).resolve()
        self.log_root.mkdir(parents=True, exist_ok=True)
        self.health_path = self.log_root / "campaign_health.json"
        self.events_path = self.log_root / "campaign_events.jsonl"
        self._lock_handle = None
        self.lock_acquired = False

    def acquire_lock(self) -> None:
        lock_path = self.log_root / "campaign.lock"
        self._lock_handle = lock_path.open("w", encoding="utf-8")
        try:
            fcntl.flock(self._lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"Another campaign scheduler owns {lock_path}") from error
        self._lock_handle.write(str(os.getpid()))
        self._lock_handle.flush()
        self.lock_acquired = True

    def write_launch_contract(self) -> None:
        scripts = sorted(self.script_root.glob("19[0-7]_*.py")) + [
            self.script_root / "pricefm_operational_fullshot.py"
        ]
        revision = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.script_root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        atomic_write_json(self.log_root / "launch_contract.json", {
            "run_tag": self.root.name,
            "git_revision": revision,
            "script_manifest": [
                {"path": str(path), "sha256": sha256_file(path)} for path in scripts
            ],
            "arguments": vars(self.args),
            "one_model_per_physical_core": True,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })

    def update(self, stage: str, status: str, **extra: object) -> None:
        payload = {
            "run_tag": self.root.name,
            "scheduler_pid": os.getpid(),
            "stage": stage,
            "status": status,
            "updated_utc": datetime.now(timezone.utc).isoformat(),
            "workers": self.args.workers,
            "one_model_per_physical_core": True,
            **extra,
        }
        atomic_write_json(self.health_path, payload)
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\n")

    def resource_snapshot(self) -> dict[str, object]:
        idle, all_cores = idle_physical_cores(
            self.args.max_core_utilization, self.args.cpu_sample_seconds
        )
        return {
            "idle_cores": idle,
            "n_idle_physical_cores": len(idle),
            "n_physical_cores": len(all_cores),
            "available_memory_gib": available_memory_gib(),
            "free_disk_gib": free_disk_gib(self.root),
            "load_1m": os.getloadavg()[0],
        }

    def wait_for_cores(self, stage: str) -> list[dict[str, object]]:
        while True:
            snapshot = self.resource_snapshot()
            gates = {
                "idle_core_gate": snapshot["n_idle_physical_cores"] >= self.args.required_idle_physical_cores,
                "memory_gate": snapshot["available_memory_gib"] >= self.args.minimum_memory_gib,
                "disk_gate": snapshot["free_disk_gib"] >= self.args.minimum_disk_gib,
                "load_gate": snapshot["load_1m"] <= self.args.maximum_load_1m,
            }
            if all(gates.values()):
                chosen = list(snapshot["idle_cores"][: self.args.workers])
                self.update(
                    stage,
                    "resource_gate_passed",
                    gates=gates,
                    n_idle_physical_cores=snapshot["n_idle_physical_cores"],
                    selected_physical_cores=[
                        {"package": core["package"], "core": core["core"], "logical_cpus": core["logical_cpus"]}
                        for core in chosen
                    ],
                    available_memory_gib=snapshot["available_memory_gib"],
                    free_disk_gib=snapshot["free_disk_gib"],
                    load_1m=snapshot["load_1m"],
                )
                return chosen
            self.update(
                stage,
                "waiting_for_resources",
                gates=gates,
                n_idle_physical_cores=snapshot["n_idle_physical_cores"],
                required_idle_physical_cores=self.args.required_idle_physical_cores,
                available_memory_gib=snapshot["available_memory_gib"],
                minimum_memory_gib=self.args.minimum_memory_gib,
                free_disk_gib=snapshot["free_disk_gib"],
                minimum_disk_gib=self.args.minimum_disk_gib,
                load_1m=snapshot["load_1m"],
                maximum_load_1m=self.args.maximum_load_1m,
            )
            time.sleep(self.args.poll_seconds)

    def run_control(self, stage: str, command: list[str], require_resource_gate: bool = False) -> None:
        prefix: list[str] = []
        if require_resource_gate:
            core = self.wait_for_cores(stage)[0]
            prefix = ["taskset", "-c", cpuset_text(core)]
        log_path = self.log_root / f"{stage}.log"
        self.update(stage, "running_control", command=prefix + command, log=str(log_path))
        with log_path.open("a", encoding="utf-8") as handle:
            result = subprocess.run(
                prefix + command,
                cwd=self.script_root,
                env=thread_limited_environment(),
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
        if result.returncode != 0:
            self.update(stage, "failed", returncode=result.returncode, log=str(log_path))
            raise RuntimeError(f"Control stage failed: {stage}; see {log_path}")
        self.update(stage, "completed_control", log=str(log_path))

    @staticmethod
    def fit_complete(row: dict[str, str], verify_hash: bool = True) -> bool:
        status_path = Path(row["trial_dir"]) / "status.json"
        if not status_path.is_file():
            return False
        try:
            status = read_json(status_path)
            checkpoint = Path(status.get("checkpoint", ""))
            if status.get("status") != "completed" or not checkpoint.is_file():
                return False
            return not verify_hash or sha256_file(checkpoint) == status.get("checkpoint_sha256")
        except (OSError, ValueError, json.JSONDecodeError):
            return False

    @staticmethod
    def test_complete(row: dict[str, str], verify_hash: bool = True) -> bool:
        status_path = Path(row["task_dir"]) / "status.json"
        if not status_path.is_file():
            return False
        try:
            status = read_json(status_path)
            metrics = Path(status.get("metrics", ""))
            predictions = Path(status.get("predictions", ""))
            if status.get("status") != "completed" or not metrics.is_file() or not predictions.is_file():
                return False
            return not verify_hash or (
                sha256_file(metrics) == status.get("metrics_sha256")
                and sha256_file(predictions) == status.get("predictions_sha256")
            )
        except (OSError, ValueError, json.JSONDecodeError):
            return False

    def run_pool(
        self,
        stage: str,
        manifest: Path,
        command_for_row: Callable[[int], list[str]],
        completion: Callable[[dict[str, str], bool], bool],
        directory_field: str,
    ) -> None:
        rows = read_csv_rows(manifest)
        completed = {index for index, row in enumerate(rows) if completion(row, True)}
        pending = deque(index for index in range(len(rows)) if index not in completed)
        if not pending:
            self.update(stage, "completed", total=len(rows), completed=len(rows), remaining=0)
            return
        cores = self.wait_for_cores(stage)
        free_cores = deque(cores)
        active: dict[int, tuple[subprocess.Popen, int, dict[str, object], object, Path]] = {}
        attempts: defaultdict[int, int] = defaultdict(int)

        while pending or active:
            while pending and free_cores:
                row_index = pending.popleft()
                row = rows[row_index]
                core = free_cores.popleft()
                attempts[row_index] += 1
                task_dir = Path(row[directory_field])
                task_dir.mkdir(parents=True, exist_ok=True)
                log_path = task_dir / "scheduler_worker.log"
                log_handle = log_path.open("a", encoding="utf-8")
                command = ["taskset", "-c", cpuset_text(core), *command_for_row(row_index)]
                process = subprocess.Popen(
                    command,
                    cwd=self.script_root,
                    env=thread_limited_environment(int(row.get("seed", 1))),
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                active[process.pid] = (process, row_index, core, log_handle, log_path)

            finished = []
            for pid, (process, row_index, core, log_handle, log_path) in active.items():
                returncode = process.poll()
                if returncode is None:
                    continue
                log_handle.close()
                row = rows[row_index]
                if returncode == 0 and completion(row, True):
                    completed.add(row_index)
                elif attempts[row_index] < self.args.maximum_attempts:
                    pending.append(row_index)
                else:
                    self.update(
                        stage,
                        "failed",
                        total=len(rows),
                        completed=len(completed),
                        failed_row_index=row_index,
                        returncode=returncode,
                        attempts=attempts[row_index],
                        log=str(log_path),
                    )
                    raise RuntimeError(f"{stage} row {row_index} failed; see {log_path}")
                free_cores.append(core)
                finished.append(pid)
            for pid in finished:
                del active[pid]
            self.update(
                stage,
                "running_models" if active or pending else "completed",
                total=len(rows),
                completed=len(completed),
                active=len(active),
                remaining=len(rows) - len(completed),
                selected_physical_cores=[
                    {"package": core["package"], "core": core["core"], "logical_cpus": core["logical_cpus"]}
                    for core in cores
                ],
            )
            if active:
                time.sleep(5)

    def command(self, script: str, *arguments: str) -> list[str]:
        return [str(self.python), str(self.script_root / script), *map(str, arguments)]

    def run(self) -> None:
        self.acquire_lock()
        self.write_launch_contract()
        if not self.python.is_file():
            raise FileNotFoundError(self.python)
        self.update("startup", "validated", artifact_root=str(self.root), log_root=str(self.log_root))

        preparation = self.root / "provenance" / "preparation_summary.json"
        if not preparation.is_file():
            self.run_control("prepare", self.command(
                "190_prepare_pricefm_operational_fullshot.py",
                "--config", self.args.config,
                "--raw-csv", self.args.raw_csv,
                "--upstream-root", self.args.upstream_root,
                "--artifact-root", str(self.root),
                "--reference-window-root", self.args.reference_window_root,
                "--strict-source", "true",
                "--force", "true",
            ), require_resource_gate=True)

        phase1_manifest = self.root / "phase1" / "trial_manifest.csv"
        self.run_pool(
            "phase1_fit",
            phase1_manifest,
            lambda index: self.command(
                "191_run_pricefm_operational_fullshot_trial.py",
                "--manifest", str(phase1_manifest),
                "--row-index", str(index),
                "--artifact-root", str(self.root),
                "--upstream-root", self.args.upstream_root,
            ),
            self.fit_complete,
            "trial_dir",
        )
        self.run_control("phase1_select", self.command(
            "192_select_pricefm_operational_phase1.py", "--artifact-root", str(self.root)
        ))
        self.run_control("phase2_prepare", self.command(
            "193_prepare_pricefm_operational_phase2.py", "--artifact-root", str(self.root)
        ))

        phase2_manifest = self.root / "phase2" / "screen" / "trial_manifest.csv"
        self.run_pool(
            "phase2_screen_fit",
            phase2_manifest,
            lambda index: self.command(
                "191_run_pricefm_operational_fullshot_trial.py",
                "--manifest", str(phase2_manifest),
                "--row-index", str(index),
                "--artifact-root", str(self.root),
                "--upstream-root", self.args.upstream_root,
            ),
            self.fit_complete,
            "trial_dir",
        )
        self.run_control("stability_prepare", self.command(
            "194_select_pricefm_operational_winners.py", "plan-stability",
            "--artifact-root", str(self.root), "--relative-near-tie", "0.01"
        ))
        stability_manifest = self.root / "phase2" / "stability" / "trial_manifest.csv"
        self.run_pool(
            "phase2_stability_fit",
            stability_manifest,
            lambda index: self.command(
                "191_run_pricefm_operational_fullshot_trial.py",
                "--manifest", str(stability_manifest),
                "--row-index", str(index),
                "--artifact-root", str(self.root),
                "--upstream-root", self.args.upstream_root,
            ),
            self.fit_complete,
            "trial_dir",
        )
        self.run_control("winner_freeze", self.command(
            "194_select_pricefm_operational_winners.py", "freeze", "--artifact-root", str(self.root)
        ))
        self.run_control("test_prepare", self.command(
            "195_score_pricefm_operational_test.py", "prepare", "--artifact-root", str(self.root)
        ))

        test_manifest = self.root / "test" / "trial_manifest.csv"
        self.run_pool(
            "test_score",
            test_manifest,
            lambda index: self.command(
                "195_score_pricefm_operational_test.py", "run-one",
                "--artifact-root", str(self.root),
                "--upstream-root", self.args.upstream_root,
                "--row-index", str(index),
            ),
            self.test_complete,
            "task_dir",
        )
        self.run_control("test_aggregate", self.command(
            "195_score_pricefm_operational_test.py", "aggregate", "--artifact-root", str(self.root)
        ))
        self.run_control("closeout", self.command(
            "196_closeout_pricefm_operational_fullshot.py",
            "--artifact-root", str(self.root),
            "--qdesn-registry", self.args.qdesn_registry,
        ))
        self.update(
            "campaign",
            "completed",
            closeout=str(self.root / "closeout" / "summary.json"),
            registry_mutated=False,
            article_mutated=False,
        )


def main() -> None:
    args = parser().parse_args()
    campaign = Campaign(args)
    try:
        campaign.run()
    except BaseException as error:
        if campaign.lock_acquired:
            campaign.update(
                "campaign",
                "failed",
                error_type=type(error).__name__,
                error=str(error),
            )
        raise


if __name__ == "__main__":
    main()
