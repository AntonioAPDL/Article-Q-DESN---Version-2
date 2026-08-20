#!/usr/bin/env python3
"""Launch or resume the resource-gated PriceFM R56 EE-fold-1 confirmation."""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import pandas as pd
import yaml

from pricefm_common import parse_bool


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
PRICEFM_ROOT = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = PRICEFM_ROOT / "authoritative/pricefm_stage_r56_ee_f1_confirmation_prep_20260820"
R_BIN = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
GLOBAL_LOCK = PRICEFM_ROOT / "locks/pricefm_exclusive_campaign.lock"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--r-bin", type=Path, default=R_BIN)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--global-lock", type=Path, default=GLOBAL_LOCK)
    p.add_argument("--jobs", type=int, default=20)
    p.add_argument("--required-idle-physical-cores", type=int, default=20)
    p.add_argument("--max-core-utilization", type=float, default=0.10)
    p.add_argument("--cpu-sample-seconds", type=float, default=5.0)
    p.add_argument("--poll-seconds", type=float, default=120.0)
    p.add_argument("--minimum-memory-gib", type=float, default=128.0)
    p.add_argument("--minimum-disk-gib", type=float, default=100.0)
    p.add_argument("--maximum-load-1m", type=float, default=36.0)
    p.add_argument("--maximum-attempts", type=int, default=2)
    p.add_argument("--wait-for-resources", type=parse_bool, default=True)
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--authorize-launch", type=parse_bool, default=False)
    return p


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def physical_core_topology(sysfs_root: Path = Path("/sys/devices/system/cpu")) -> list[dict]:
    groups: dict[tuple[int, int], list[int]] = {}
    for cpu_dir in sysfs_root.glob("cpu[0-9]*"):
        cpu = int(cpu_dir.name[3:])
        topology = cpu_dir / "topology"
        try:
            package = int((topology / "physical_package_id").read_text().strip())
            core = int((topology / "core_id").read_text().strip())
        except (FileNotFoundError, ValueError):
            continue
        groups.setdefault((package, core), []).append(cpu)
    return [
        {"package": package, "core": core, "logical_cpus": sorted(cpus)}
        for (package, core), cpus in sorted(groups.items())
    ]


def read_proc_stat(path: Path = Path("/proc/stat")) -> dict[int, tuple[int, int]]:
    rows: dict[int, tuple[int, int]] = {}
    for line in path.read_text().splitlines():
        if not line.startswith("cpu") or not line[3:4].isdigit():
            continue
        fields = line.split()
        values = [int(value) for value in fields[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        rows[int(fields[0][3:])] = (idle, sum(values))
    return rows


def sample_cpu_utilization(seconds: float) -> dict[int, float]:
    before = read_proc_stat()
    time.sleep(seconds)
    after = read_proc_stat()
    utilization: dict[int, float] = {}
    for cpu, (idle_before, total_before) in before.items():
        idle_after, total_after = after[cpu]
        total_delta = total_after - total_before
        idle_delta = idle_after - idle_before
        utilization[cpu] = 0.0 if total_delta <= 0 else 1.0 - idle_delta / total_delta
    return utilization


def idle_physical_cores(max_utilization: float, sample_seconds: float) -> tuple[list[dict], list[dict]]:
    utilization = sample_cpu_utilization(sample_seconds)
    all_cores = physical_core_topology()
    idle: list[dict] = []
    annotated: list[dict] = []
    for core in all_cores:
        values = [utilization.get(cpu, 1.0) for cpu in core["logical_cpus"]]
        row = {**core, "max_logical_utilization": max(values), "mean_logical_utilization": sum(values) / len(values)}
        annotated.append(row)
        if row["max_logical_utilization"] <= max_utilization:
            idle.append(row)
    return idle, annotated


def available_memory_gib() -> float:
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) / 1024**2
    raise RuntimeError("MemAvailable is absent from /proc/meminfo")


def free_disk_gib(path: Path) -> float:
    probe = path
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    return shutil.disk_usage(probe).free / 1024**3


def thread_limited_environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment.update({
        "OMP_NUM_THREADS": "1",
        "OPENBLAS_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
        "BLIS_NUM_THREADS": "1",
        "VECLIB_MAXIMUM_THREADS": "1",
        "NUMEXPR_NUM_THREADS": "1",
    })
    return environment


def completed_job(row, verify_files: bool = True) -> bool:
    output = Path(row.output_dir)
    summary_path = output / "job_summary.json"
    if not summary_path.is_file():
        return False
    try:
        summary = json.loads(summary_path.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    valid = (
        summary.get("status") == "completed"
        and summary.get("id") == row.id
        and int(summary.get("n_burn", -1)) == int(row.n_burn)
        and int(summary.get("n_mcmc", -1)) == int(row.n_mcmc)
        and summary.get("core_update_mode") == "m0_v_collapsed_support_logit"
        and bool(summary.get("finite_draws"))
    )
    if not valid or not verify_files:
        return valid
    return all((output / name).is_file() for name in (
        "posterior_draws.rds",
        "scalar_draws.csv.gz",
        "posterior_mean_predictions.csv.gz",
    ))


class Campaign:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        if args.jobs != 20 or args.required_idle_physical_cores != 20:
            raise ValueError("R56 requires exactly 20 workers and 20 idle physical cores")
        self.prep = args.prep_dir.resolve()
        self.orchestration = self.prep / "orchestration"
        self.orchestration.mkdir(parents=True, exist_ok=True)
        self.health_path = self.orchestration / "campaign_health.json"
        self.events_path = self.orchestration / "campaign_events.jsonl"
        self._lock_handle = None
        self.lock_acquired = False
        self.manifest: pd.DataFrame | None = None

    def update(self, stage: str, status: str, **extra: object) -> None:
        completed = 0
        total = 0
        if self.manifest is not None:
            total = len(self.manifest)
            completed = sum(completed_job(row) for row in self.manifest.itertuples(index=False))
        payload = {
            "run_tag": "pricefm_stage_r56_ee_f1_full_budget_confirmation_20260820",
            "scheduler_pid": os.getpid(),
            "stage": stage,
            "status": status,
            "updated_utc": utc_now(),
            "total": total,
            "completed": completed,
            "remaining": total - completed,
            "workers": self.args.jobs,
            "one_process_per_physical_core": True,
            "threads_per_process": 1,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            **extra,
        }
        atomic_json(self.health_path, payload)
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\n")

    def acquire_lock(self) -> None:
        lock_path = self.args.global_lock.resolve()
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock_handle = lock_path.open("a+", encoding="utf-8")
        try:
            fcntl.flock(self._lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"Another PriceFM campaign owns {lock_path}") from error
        self._lock_handle.seek(0)
        self._lock_handle.truncate()
        self._lock_handle.write(json.dumps({"pid": os.getpid(), "campaign": "R56", "acquired_utc": utc_now()}) + "\n")
        self._lock_handle.flush()
        self.lock_acquired = True

    def verify_contract(self) -> tuple[pd.DataFrame, Path]:
        summary = json.loads((self.prep / "summary.json").read_text())
        launch = yaml.safe_load((self.prep / "pricefm_stage_r56_launch.yaml").read_text())["pricefm_stage_r56_launch"]
        gates = pd.read_csv(self.prep / "pricefm_stage_r56_prelaunch_gates.csv")
        if not self.args.authorize_launch:
            raise RuntimeError("R56 launcher requires --authorize-launch true")
        if not summary.get("launch_authorized") or not launch.get("launch_authorized_by_user"):
            raise RuntimeError("R56 prep was not materialized with explicit launch authorization")
        if not gates.passed.astype(bool).all():
            raise RuntimeError("R56 prelaunch gates are not all passing")
        source_manifest = pd.read_csv(self.prep / "source_manifest.csv")
        drifted = []
        for source in source_manifest.itertuples(index=False):
            path = Path(source.path)
            if not path.is_file() or sha256(path) != source.sha256:
                drifted.append(str(path))
        if drifted:
            raise RuntimeError(f"R56 frozen source drift: {drifted[:3]}")
        manifest_path = Path(launch["manifest"])
        manifest = pd.read_csv(manifest_path)
        if len(manifest) != 28 or manifest.groupby("tau").chain.nunique().ne(4).any():
            raise RuntimeError("R56 launch manifest is incomplete")
        if manifest.region.ne("EE").any() or manifest.fold.ne(1).any():
            raise RuntimeError("R56 manifest escaped the bounded EE/fold-1 target")
        if manifest.n_burn.ne(5000).any() or manifest.n_mcmc.ne(20000).any():
            raise RuntimeError("R56 manifest budget drifted")
        worker = Path(launch["worker"])
        if not worker.is_file() or not self.args.r_bin.is_file():
            raise FileNotFoundError(worker if not worker.is_file() else self.args.r_bin)
        self.manifest = manifest
        return manifest, worker

    def resource_snapshot(self) -> dict:
        idle, all_cores = idle_physical_cores(
            self.args.max_core_utilization, self.args.cpu_sample_seconds
        )
        return {
            "idle_cores": idle,
            "n_idle_physical_cores": len(idle),
            "n_physical_cores": len(all_cores),
            "available_memory_gib": available_memory_gib(),
            "free_disk_gib": free_disk_gib(self.prep),
            "load_1m": os.getloadavg()[0],
        }

    def wait_for_resources(self) -> list[dict]:
        while True:
            snapshot = self.resource_snapshot()
            gates = {
                "idle_core_gate": snapshot["n_idle_physical_cores"] >= self.args.required_idle_physical_cores,
                "memory_gate": snapshot["available_memory_gib"] >= self.args.minimum_memory_gib,
                "disk_gate": snapshot["free_disk_gib"] >= self.args.minimum_disk_gib,
                "load_gate": snapshot["load_1m"] <= self.args.maximum_load_1m,
            }
            fields = {
                "gates": gates,
                "n_idle_physical_cores": snapshot["n_idle_physical_cores"],
                "required_idle_physical_cores": self.args.required_idle_physical_cores,
                "available_memory_gib": round(snapshot["available_memory_gib"], 3),
                "minimum_memory_gib": self.args.minimum_memory_gib,
                "free_disk_gib": round(snapshot["free_disk_gib"], 3),
                "minimum_disk_gib": self.args.minimum_disk_gib,
                "load_1m": round(snapshot["load_1m"], 3),
                "maximum_load_1m": self.args.maximum_load_1m,
            }
            if all(gates.values()):
                cores = list(snapshot["idle_cores"][: self.args.jobs])
                self.update("resource_gate", "passed", selected_physical_cores=cores, **fields)
                return cores
            self.update("resource_gate", "waiting", **fields)
            if not self.args.wait_for_resources:
                raise RuntimeError(f"R56 host resource gates failed: {gates}")
            time.sleep(max(self.args.poll_seconds, 1.0))

    def run(self) -> dict:
        self.acquire_lock()
        manifest, worker = self.verify_contract()
        completed_indices = {
            index for index, row in enumerate(manifest.itertuples(index=False))
            if self.args.resume and completed_job(row)
        }
        pending = deque(index for index in range(len(manifest)) if index not in completed_indices)
        if not pending:
            result = {"status": "completed", "total": len(manifest), "completed": len(manifest), "failed": 0}
            atomic_json(self.orchestration / "launch_summary.json", result)
            self.update("campaign", "completed")
            return result

        cores = self.wait_for_resources()
        free_cores = deque(cores)
        active: dict[int, tuple[subprocess.Popen, int, dict, object, Path]] = {}
        attempts: defaultdict[int, int] = defaultdict(int)
        status_rows: list[dict] = []
        self.update("campaign", "running")
        while pending or active:
            while pending and free_cores:
                index = pending.popleft()
                row = manifest.iloc[index]
                core = free_cores.popleft()
                attempts[index] += 1
                output_dir = Path(row.output_dir)
                output_dir.mkdir(parents=True, exist_ok=True)
                log_path = output_dir / "chain.log"
                log_handle = log_path.open("a", encoding="utf-8")
                cpu = min(core["logical_cpus"])
                command = [
                    "taskset", "-c", str(cpu), str(self.args.r_bin), str(worker),
                    "--config", str(row.config), "--force", "false",
                ]
                log_handle.write(f"\n=== R56 attempt {attempts[index]} {utc_now()} cpu={cpu} ===\n")
                log_handle.flush()
                process = subprocess.Popen(
                    command,
                    cwd=str(self.args.artifact_repo),
                    env=thread_limited_environment(),
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                active[process.pid] = (process, index, core, log_handle, log_path)

            finished: list[int] = []
            for pid, (process, index, core, log_handle, log_path) in list(active.items()):
                returncode = process.poll()
                if returncode is None:
                    continue
                log_handle.close()
                row = manifest.iloc[index]
                row_view = next(pd.DataFrame([row]).itertuples(index=False))
                success = returncode == 0 and completed_job(row_view)
                status_rows.append({
                    "id": row.id,
                    "attempt": attempts[index],
                    "return_code": returncode,
                    "status": "completed" if success else "failed_attempt",
                    "physical_package": core["package"],
                    "physical_core": core["core"],
                    "logical_cpu": min(core["logical_cpus"]),
                    "log": str(log_path),
                    "finished_utc": utc_now(),
                })
                if success:
                    completed_indices.add(index)
                elif attempts[index] < self.args.maximum_attempts:
                    pending.append(index)
                else:
                    pd.DataFrame(status_rows).to_csv(self.orchestration / "launch_status.csv", index=False)
                    self.update("campaign", "failed", failed_job=str(row.id), log=str(log_path))
                    raise RuntimeError(f"R56 job failed twice: {row.id}; see {log_path}")
                free_cores.append(core)
                finished.append(pid)
            for pid in finished:
                del active[pid]
            pd.DataFrame(status_rows).to_csv(self.orchestration / "launch_status.csv", index=False)
            self.update("campaign", "running" if active or pending else "completed", active=len(active))
            if active:
                time.sleep(5.0)

        result = {
            "status": "completed",
            "total": len(manifest),
            "completed": len(completed_indices),
            "failed": 0,
            "finished_utc": utc_now(),
            "registry_mutated": False,
            "article_mutated": False,
        }
        atomic_json(self.orchestration / "launch_summary.json", result)
        self.update("campaign", "completed")
        return result


def main() -> None:
    args = parser().parse_args()
    campaign = Campaign(args)
    try:
        result = campaign.run()
        print(json.dumps(result, indent=2, sort_keys=True))
    except BaseException as error:
        if campaign.lock_acquired:
            campaign.update("campaign", "failed", error_type=type(error).__name__, error=str(error))
        raise


if __name__ == "__main__":
    main()
