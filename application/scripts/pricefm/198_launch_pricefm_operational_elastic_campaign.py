#!/usr/bin/env python3
"""Run the restartable PriceFM operational benchmark on elastic idle cores."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
from datetime import datetime, timezone
import fcntl
import json
import math
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
    p.add_argument("--minimum-dispatch-workers", type=int, default=1)
    p.add_argument("--maximum-workers", type=int, default=20)
    p.add_argument("--max-core-utilization", type=float, default=0.10)
    p.add_argument("--cpu-sample-seconds", type=float, default=5.0)
    p.add_argument("--consecutive-sample-gap-seconds", type=float, default=5.0)
    p.add_argument("--resource-poll-seconds", type=float, default=60.0)
    p.add_argument("--status-poll-seconds", type=float, default=5.0)
    p.add_argument("--minimum-memory-gib", type=float, default=128.0)
    p.add_argument("--minimum-disk-gib", type=float, default=150.0)
    p.add_argument("--maximum-projected-load", type=float, default=60.0)
    p.add_argument("--niceness", type=int, default=10)
    p.add_argument("--maximum-attempts", type=int, default=2)
    p.add_argument("--global-lock-path", default="")
    return p


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def physical_key(core: dict[str, object]) -> tuple[int, int]:
    return int(core["package"]), int(core["core"])


def stable_dispatch_capacity(
    current_idle: list[dict[str, object]],
    previous_idle_keys: set[tuple[int, int]],
    active_core_keys: set[tuple[int, int]],
    active_count: int,
    load_1m: float,
    minimum_dispatch_workers: int,
    maximum_workers: int,
    maximum_projected_load: float,
) -> tuple[list[dict[str, object]], dict[str, object]]:
    """Select stable physical cores without exceeding worker or load headroom."""
    stable = [
        core for core in current_idle
        if physical_key(core) in previous_idle_keys
        and physical_key(core) not in active_core_keys
    ]
    worker_slots = max(0, maximum_workers - active_count)
    load_slots = max(0, math.floor(maximum_projected_load - load_1m))
    dispatch_slots = min(len(stable), worker_slots, load_slots)
    if dispatch_slots < minimum_dispatch_workers:
        dispatch_slots = 0
    selected = stable[:dispatch_slots]
    evidence = {
        "stable_idle_physical_cores": len(stable),
        "worker_slots": worker_slots,
        "load_slots": load_slots,
        "dispatch_slots": dispatch_slots,
        "active_workers": active_count,
        "load_1m": load_1m,
        "projected_load": load_1m + dispatch_slots,
        "maximum_projected_load": maximum_projected_load,
    }
    return selected, evidence


class ElasticCampaign:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        if not 1 <= args.minimum_dispatch_workers <= args.maximum_workers <= 20:
            raise ValueError("Elastic workers must satisfy 1 <= minimum <= maximum <= 20")
        if not 0 <= args.niceness <= 19:
            raise ValueError("Niceness must be between 0 and 19")
        if args.maximum_projected_load > max((os.cpu_count() or 1) - 4, 1):
            raise ValueError("Projected load must preserve at least four logical CPUs of headroom")
        self.script_root = Path(__file__).resolve().parent
        self.python = Path(os.path.abspath(os.path.expanduser(args.python)))
        self.root = Path(args.artifact_root).resolve()
        self.log_root = Path(args.log_root).resolve()
        self.log_root.mkdir(parents=True, exist_ok=True)
        self.health_path = self.log_root / "campaign_health.json"
        self.events_path = self.log_root / "campaign_events.jsonl"
        raw_global_lock = getattr(args, "global_lock_path", "")
        self.global_lock_path = (
            Path(os.path.abspath(os.path.expanduser(raw_global_lock)))
            if raw_global_lock
            else self.root.parents[1] / "locks" / "pricefm_exclusive_campaign.lock"
        )
        self._global_lock_handle = None
        self._local_lock_handle = None
        self.lock_acquired = False

    def acquire_lock(self) -> None:
        self.global_lock_path.parent.mkdir(parents=True, exist_ok=True)
        self._global_lock_handle = self.global_lock_path.open("a+", encoding="utf-8")
        try:
            fcntl.flock(self._global_lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(
                f"Another PriceFM campaign owns {self.global_lock_path}"
            ) from error
        self._global_lock_handle.seek(0)
        self._global_lock_handle.truncate()
        self._global_lock_handle.write(json.dumps({
            "pid": os.getpid(),
            "campaign": self.root.name,
            "scheduler_mode": "elastic_1_to_20",
            "acquired_utc": utc_now(),
        }) + "\n")
        self._global_lock_handle.flush()

        local_lock = self.log_root / "campaign.lock"
        self._local_lock_handle = local_lock.open("w", encoding="utf-8")
        try:
            fcntl.flock(self._local_lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"Another elastic scheduler owns {local_lock}") from error
        self._local_lock_handle.write(str(os.getpid()))
        self._local_lock_handle.flush()
        self.lock_acquired = True

    def validate_python_environment(self) -> dict[str, object]:
        if not self.python.is_file():
            raise FileNotFoundError(self.python)
        probe = (
            "import json,sys,numpy,pandas,tensorflow;"
            "print(json.dumps({"
            "'sys_executable':sys.executable,'sys_prefix':sys.prefix,"
            "'sys_base_prefix':sys.base_prefix,'python':sys.version.split()[0],"
            "'numpy':numpy.__version__,'pandas':pandas.__version__,"
            "'tensorflow':tensorflow.__version__},sort_keys=True))"
        )
        result = subprocess.run(
            [str(self.python), "-c", probe],
            text=True,
            capture_output=True,
            check=False,
            env=thread_limited_environment(),
        )
        if result.returncode != 0:
            atomic_write_json(self.log_root / "python_environment_preflight.json", {
                "status": "failed",
                "requested_python": str(self.python),
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            })
            raise RuntimeError(
                f"PriceFM Python environment preflight failed for {self.python}"
            )
        try:
            payload = json.loads(result.stdout.strip().splitlines()[-1])
        except (IndexError, json.JSONDecodeError) as error:
            raise RuntimeError("Python environment preflight returned invalid JSON") from error
        observed = Path(os.path.abspath(payload["sys_executable"]))
        if observed != self.python:
            raise RuntimeError(
                f"Python entrypoint drift: requested {self.python}, observed {observed}"
            )
        if payload["sys_prefix"] == payload["sys_base_prefix"]:
            raise RuntimeError(f"PriceFM interpreter is not inside a venv: {self.python}")
        preflight = {
            "status": "passed",
            "requested_python": str(self.python),
            **payload,
        }
        atomic_write_json(self.log_root / "python_environment_preflight.json", preflight)
        return preflight

    def write_launch_contract(self) -> None:
        scripts = sorted(self.script_root.glob("19[0-8]_*.py")) + [
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
            "scheduler_mode": "elastic_1_to_20_physical_cores",
            "scheduler_amendment_only": True,
            "scientific_protocol_changed": False,
            "script_manifest": [
                {"path": str(path), "sha256": sha256_file(path)} for path in scripts
            ],
            "arguments": vars(self.args),
            "one_model_per_physical_core": True,
            "threads_per_model": 1,
            "active_models_are_never_preempted": True,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })

    def update(self, stage: str, status: str, **extra: object) -> None:
        payload = {
            "run_tag": self.root.name,
            "scheduler_pid": os.getpid(),
            "scheduler_mode": "elastic_1_to_20_physical_cores",
            "stage": stage,
            "status": status,
            "updated_utc": utc_now(),
            "minimum_dispatch_workers": self.args.minimum_dispatch_workers,
            "maximum_workers": self.args.maximum_workers,
            "one_model_per_physical_core": True,
            "threads_per_model": 1,
            "scientific_protocol_changed": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            **extra,
        }
        atomic_write_json(self.health_path, payload)
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\n")

    def resource_sample(self) -> dict[str, object]:
        idle, all_cores = idle_physical_cores(
            self.args.max_core_utilization, self.args.cpu_sample_seconds
        )
        return {
            "idle_cores": idle,
            "idle_keys": {physical_key(core) for core in idle},
            "n_idle_physical_cores": len(idle),
            "n_physical_cores": len(all_cores),
            "available_memory_gib": available_memory_gib(),
            "free_disk_gib": free_disk_gib(self.root),
            "load_1m": os.getloadavg()[0],
        }

    def stable_resource_snapshot(
        self,
        active_core_keys: set[tuple[int, int]],
        active_count: int,
    ) -> tuple[list[dict[str, object]], dict[str, object]]:
        first = self.resource_sample()
        time.sleep(max(self.args.consecutive_sample_gap_seconds, 0.0))
        second = self.resource_sample()
        memory_pass = second["available_memory_gib"] >= self.args.minimum_memory_gib
        disk_pass = second["free_disk_gib"] >= self.args.minimum_disk_gib
        selected, capacity = stable_dispatch_capacity(
            current_idle=second["idle_cores"],
            previous_idle_keys=first["idle_keys"],
            active_core_keys=active_core_keys,
            active_count=active_count,
            load_1m=float(second["load_1m"]),
            minimum_dispatch_workers=self.args.minimum_dispatch_workers,
            maximum_workers=self.args.maximum_workers,
            maximum_projected_load=self.args.maximum_projected_load,
        )
        if not memory_pass or not disk_pass:
            selected = []
            capacity["dispatch_slots"] = 0
        evidence = {
            **capacity,
            "first_idle_physical_cores": first["n_idle_physical_cores"],
            "second_idle_physical_cores": second["n_idle_physical_cores"],
            "available_memory_gib": second["available_memory_gib"],
            "minimum_memory_gib": self.args.minimum_memory_gib,
            "memory_gate": memory_pass,
            "free_disk_gib": second["free_disk_gib"],
            "minimum_disk_gib": self.args.minimum_disk_gib,
            "disk_gate": disk_pass,
            "selected_physical_cores": [
                {
                    "package": core["package"],
                    "core": core["core"],
                    "logical_cpus": core["logical_cpus"],
                }
                for core in selected
            ],
        }
        return selected, evidence

    def wait_for_control_core(self, stage: str) -> dict[str, object]:
        while True:
            selected, evidence = self.stable_resource_snapshot(set(), 0)
            if selected:
                core = selected[0]
                self.update(stage, "control_resource_gate_passed", **evidence)
                return core
            self.update(stage, "waiting_for_control_resource", **evidence)
            time.sleep(max(self.args.resource_poll_seconds, 1.0))

    def command(self, script: str, *arguments: str) -> list[str]:
        return [str(self.python), str(self.script_root / script), *map(str, arguments)]

    def pinned_command(self, core: dict[str, object], command: list[str]) -> list[str]:
        return [
            "nice", "-n", str(self.args.niceness),
            "taskset", "-c", cpuset_text(core),
            *command,
        ]

    def run_control(self, stage: str, command: list[str]) -> None:
        core = self.wait_for_control_core(stage)
        pinned = self.pinned_command(core, command)
        log_path = self.log_root / f"{stage}.log"
        self.update(stage, "running_control", command=pinned, log=str(log_path))
        with log_path.open("a", encoding="utf-8") as handle:
            result = subprocess.run(
                pinned,
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

        active: dict[int, tuple[subprocess.Popen, int, dict[str, object], object, Path]] = {}
        attempts: defaultdict[int, int] = defaultdict(int)
        next_resource_poll = 0.0
        last_capacity_evidence: dict[str, object] = {}
        while pending or active:
            finished: list[int] = []
            for pid, (process, row_index, core, log_handle, log_path) in list(active.items()):
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
                        active=len(active) - 1,
                        remaining=len(rows) - len(completed),
                        failed_row_index=row_index,
                        returncode=returncode,
                        attempts=attempts[row_index],
                        log=str(log_path),
                    )
                    raise RuntimeError(f"{stage} row {row_index} failed; see {log_path}")
                finished.append(pid)
            for pid in finished:
                del active[pid]

            now = time.monotonic()
            if pending and now >= next_resource_poll:
                active_keys = {physical_key(core) for _, _, core, _, _ in active.values()}
                selected, last_capacity_evidence = self.stable_resource_snapshot(
                    active_keys, len(active)
                )
                for core in selected:
                    if not pending:
                        break
                    row_index = pending.popleft()
                    row = rows[row_index]
                    attempts[row_index] += 1
                    task_dir = Path(row[directory_field])
                    task_dir.mkdir(parents=True, exist_ok=True)
                    log_path = task_dir / "scheduler_worker.log"
                    log_handle = log_path.open("a", encoding="utf-8")
                    command = self.pinned_command(core, command_for_row(row_index))
                    log_handle.write(
                        f"\n=== elastic attempt {attempts[row_index]} {utc_now()} "
                        f"physical_core={physical_key(core)} ===\n"
                    )
                    log_handle.flush()
                    process = subprocess.Popen(
                        command,
                        cwd=self.script_root,
                        env=thread_limited_environment(int(row.get("seed", 1))),
                        stdout=log_handle,
                        stderr=subprocess.STDOUT,
                        text=True,
                    )
                    active[process.pid] = (process, row_index, core, log_handle, log_path)
                next_resource_poll = time.monotonic() + self.args.resource_poll_seconds

            status = "running_models" if active else "waiting_for_elastic_capacity"
            if not pending and not active:
                status = "completed"
            self.update(
                stage,
                status,
                total=len(rows),
                completed=len(completed),
                active=len(active),
                remaining=len(rows) - len(completed),
                active_physical_cores=[
                    {
                        "package": core["package"],
                        "core": core["core"],
                        "logical_cpus": core["logical_cpus"],
                    }
                    for _, _, core, _, _ in active.values()
                ],
                capacity=last_capacity_evidence,
            )
            if pending or active:
                time.sleep(max(self.args.status_poll_seconds, 1.0))

    def run(self) -> None:
        self.acquire_lock()
        python_preflight = self.validate_python_environment()
        self.write_launch_contract()
        self.update(
            "startup",
            "validated",
            artifact_root=str(self.root),
            log_root=str(self.log_root),
            global_lock=str(self.global_lock_path),
            python_preflight=python_preflight,
        )

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
            ))

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
            "194_select_pricefm_operational_winners.py", "freeze",
            "--artifact-root", str(self.root)
        ))
        self.run_control("test_prepare", self.command(
            "195_score_pricefm_operational_test.py", "prepare",
            "--artifact-root", str(self.root)
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
            "195_score_pricefm_operational_test.py", "aggregate",
            "--artifact-root", str(self.root)
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
    campaign = ElasticCampaign(args)
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
