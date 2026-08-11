#!/usr/bin/env python3
"""Launch or resume the full PriceFM R52 replay and R53 M0 campaign."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from queue import Empty, Queue

import pandas as pd

from pricefm_common import parse_bool


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "authoritative/pricefm_stage_r52_r53_exal_m0_launch_prep_20260811"
R_BIN = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
CASE_RUNNER = Path(__file__).with_name("183_prepare_pricefm_stage_r52_exal_m0_case.R")
CHAIN_RUNNER = Path(__file__).with_name("184_run_pricefm_stage_r53_exal_m0_chain.R")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--jobs", type=int, default=24)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--phase", choices=["all", "cases", "chains"], default="all")
    p.add_argument("--resume", type=parse_bool, default=True)
    p.add_argument("--force-incomplete", type=parse_bool, default=True)
    p.add_argument("--busy-cpu-threshold", type=float, default=50.0)
    p.add_argument("--external-active-case-id", default="")
    p.add_argument("--external-case-poll-seconds", type=float, default=30.0)
    return p


def parse_cpu_list(value: str) -> list[int]:
    cpus = [int(part.strip()) for part in value.split(",") if part.strip()]
    if len(cpus) != len(set(cpus)) or any(cpu < 0 for cpu in cpus):
        raise ValueError("CPU list must contain unique nonnegative logical CPU IDs")
    return cpus


def topology() -> tuple[dict[int, int], dict[int, int]]:
    text = subprocess.check_output(["lscpu", "-p=CPU,CORE,ONLINE"], text=True)
    cpu_to_core: dict[int, int] = {}
    representative: dict[int, int] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        cpu_text, core_text, online = line.split(",")[:3]
        if online.strip().upper() not in {"Y", "YES"}:
            continue
        cpu, core = int(cpu_text), int(core_text)
        cpu_to_core[cpu] = core
        representative[core] = min(cpu, representative.get(core, cpu))
    return cpu_to_core, representative


def discover_cpus(jobs: int, busy_threshold: float) -> tuple[list[int], list[dict]]:
    cpu_to_core, representative = topology()
    ps = subprocess.check_output(["ps", "-eo", "pid=,psr=,pcpu=,args="], text=True)
    busy_cores: set[int] = set()
    evidence: list[dict] = []
    for line in ps.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) < 4:
            continue
        try:
            pid, psr, pcpu = int(parts[0]), int(parts[1]), float(parts[2])
        except ValueError:
            continue
        if pid == os.getpid() or pcpu < busy_threshold or psr not in cpu_to_core:
            continue
        core = cpu_to_core[psr]
        busy_cores.add(core)
        evidence.append({"pid": pid, "logical_cpu": psr, "physical_core": core, "pcpu": pcpu, "command": parts[3]})
    available = [representative[core] for core in sorted(representative) if core not in busy_cores]
    if len(available) < jobs:
        raise RuntimeError(f"Only {len(available)} unused physical cores found for {jobs} workers")
    return available[:jobs], evidence


def validate_distinct_physical(cpus: list[int]) -> None:
    cpu_to_core, _ = topology()
    missing = [cpu for cpu in cpus if cpu not in cpu_to_core]
    if missing:
        raise ValueError(f"Unknown CPU IDs: {missing}")
    cores = [cpu_to_core[cpu] for cpu in cpus]
    if len(cores) != len(set(cores)):
        raise ValueError("CPU list includes SMT siblings from the same physical core")


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def completed_summary(path: Path, eligibility_field: str | None = None) -> bool:
    if not path.exists():
        return False
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return False
    if payload.get("status") != "completed":
        return False
    return True if eligibility_field is None else bool(payload.get(eligibility_field))


def case_process_active(row) -> bool:
    process_table = subprocess.check_output(["ps", "-eo", "args="], text=True)
    config = str(row.config)
    return any(CASE_RUNNER.name in line and config in line for line in process_table.splitlines())


def partition_external_case(cases: pd.DataFrame, case_id: str) -> tuple[list, list]:
    rows = list(cases.itertuples(index=False))
    if not case_id:
        return rows, []
    external = [row for row in rows if row.id == case_id]
    if len(external) != 1:
        raise ValueError(f"External active case must identify exactly one manifest row: {case_id}")
    return [row for row in rows if row.id != case_id], external


class CampaignRecorder:
    def __init__(self, root: Path, case_total: int, chain_total: int, cpus: list[int]):
        self.root = root
        self.lock = threading.Lock()
        self.case_total = case_total
        self.chain_total = chain_total
        self.cpus = cpus
        self.results: list[dict] = []
        self.started = time.time()
        root.mkdir(parents=True, exist_ok=True)

    def record(self, result: dict) -> None:
        with self.lock:
            self.results.append(result)
            with (self.root / "events.jsonl").open("a") as handle:
                handle.write(json.dumps(result, sort_keys=True) + "\n")
            self.publish(result.get("phase", "unknown"))

    def publish(self, phase: str, status: str = "running", error: str | None = None) -> None:
        case_done = sum(
            completed_summary(Path(row.output_dir) / "case_summary.json", "m0_launch_eligible")
            for row in self.case_manifest.itertuples(index=False)
        )
        chain_done = sum(
            completed_summary(Path(row.output_dir) / "job_summary.json")
            for row in self.chain_manifest.itertuples(index=False)
        )
        payload = {
            "status": status, "phase": phase, "case_total": self.case_total,
            "case_completed": case_done, "case_remaining": self.case_total - case_done,
            "chain_total": self.chain_total, "chain_completed": chain_done,
            "chain_remaining": self.chain_total - chain_done, "worker_cpus": self.cpus,
            "elapsed_seconds": round(time.time() - self.started, 3),
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        }
        if error is not None:
            payload["error"] = error
        atomic_json(self.root / "campaign_state.json", payload)


def run_one(row, phase: str, cpu: int, runner: Path, artifact_repo: Path, resume: bool, force_incomplete: bool) -> dict:
    output = Path(row.output_dir)
    summary = output / ("case_summary.json" if phase == "cases" else "job_summary.json")
    eligibility = "m0_launch_eligible" if phase == "cases" else None
    if resume and completed_summary(summary, eligibility):
        return {"id": row.id, "phase": phase, "status": "skipped_completed", "return_code": 0, "cpu_id": cpu, "elapsed_seconds": 0.0}
    output.mkdir(parents=True, exist_ok=True)
    log_path = output / ("case.log" if phase == "cases" else "chain.log")
    command = ["taskset", "-c", str(cpu), str(R_BIN), str(runner), "--config", str(row.config), "--force", str(bool(force_incomplete)).lower()]
    env = os.environ.copy()
    env.update({
        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
        "BLIS_NUM_THREADS": "1", "VECLIB_MAXIMUM_THREADS": "1", "NUMEXPR_NUM_THREADS": "1",
    })
    started = time.time()
    with log_path.open("a") as log:
        log.write(f"\n=== launch attempt {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} cpu={cpu} ===\n")
        log.flush()
        proc = subprocess.run(command, cwd=str(artifact_repo), stdout=log, stderr=subprocess.STDOUT, env=env, check=False)
    status = "completed" if proc.returncode == 0 and completed_summary(summary, eligibility) else "failed"
    return {
        "id": row.id, "phase": phase, "status": status, "return_code": proc.returncode,
        "cpu_id": cpu, "elapsed_seconds": round(time.time() - started, 3), "log": str(log_path),
    }


def run_lanes(rows, phase: str, cpus: list[int], runner: Path, args, recorder: CampaignRecorder) -> list[dict]:
    work: Queue = Queue()
    for row in rows:
        work.put(row)

    def lane(cpu):
        output = []
        while True:
            try:
                row = work.get_nowait()
            except Empty:
                break
            result = run_one(row, phase, cpu, runner, args.artifact_repo, args.resume, args.force_incomplete)
            recorder.record(result)
            print(json.dumps(result, sort_keys=True), flush=True)
            output.append(result)
            work.task_done()
        return output

    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(lane, cpu) for cpu in cpus]
        for future in as_completed(futures):
            results.extend(future.result())
    return results


def run(args) -> dict:
    prep = args.prep_dir.resolve()
    gates = pd.read_csv(prep / "pricefm_stage_r52_r53_prelaunch_gates.csv")
    summary = json.loads((prep / "summary.json").read_text())
    if not gates.passed.astype(bool).all() or not summary.get("launch_authorized"):
        raise RuntimeError("R52/R53 prelaunch gates have not authorized launch")
    cases = pd.read_csv(prep / "pricefm_stage_r52_case_manifest.csv")
    chains = pd.read_csv(prep / "pricefm_stage_r53_launch_manifest.csv")
    jobs = min(int(args.jobs), len(cases), len(chains))
    if jobs < 1:
        raise ValueError("At least one worker is required")
    if args.cpu_list:
        cpus = parse_cpu_list(args.cpu_list)
        if len(cpus) < jobs:
            raise ValueError("CPU list is shorter than requested worker count")
        cpus = cpus[:jobs]
        busy_evidence = []
    else:
        cpus, busy_evidence = discover_cpus(jobs, args.busy_cpu_threshold)
    validate_distinct_physical(cpus)

    orchestration = prep / "orchestration"
    pd.DataFrame(busy_evidence).to_csv(orchestration / "busy_core_exclusions.csv", index=False) if orchestration.exists() else None
    recorder = CampaignRecorder(orchestration, len(cases), len(chains), cpus)
    recorder.case_manifest = cases
    recorder.chain_manifest = chains
    orchestration.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(busy_evidence).to_csv(orchestration / "busy_core_exclusions.csv", index=False)
    atomic_json(orchestration / "launch_contract.json", {
        "worker_count": len(cpus), "logical_cpus": cpus,
        "one_process_per_physical_core": True, "threads_per_process": 1,
        "phase": args.phase, "resume": args.resume, "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    recorder.publish("starting")

    all_results: list[dict] = []
    try:
        if args.phase in {"all", "cases"}:
            case_rows, external_rows = partition_external_case(cases, args.external_active_case_id)
            all_results.extend(run_lanes(case_rows, "cases", cpus, CASE_RUNNER, args, recorder))
            failed_cases = [row for row in all_results if row["phase"] == "cases" and row["status"] == "failed"]
            if failed_cases:
                raise RuntimeError(f"{len(failed_cases)} case replay jobs failed; M0 chains were not started")
            for row in external_rows:
                while (
                    not completed_summary(Path(row.output_dir) / "case_summary.json", "m0_launch_eligible")
                    and case_process_active(row)
                ):
                    recorder.publish("waiting_external_case")
                    time.sleep(max(float(args.external_case_poll_seconds), 1.0))
                result = run_one(
                    row, "cases", cpus[0], CASE_RUNNER, args.artifact_repo,
                    args.resume, args.force_incomplete,
                )
                recorder.record(result)
                print(json.dumps(result, sort_keys=True), flush=True)
                all_results.append(result)
                if result["status"] == "failed":
                    raise RuntimeError("External case replay failed; M0 chains were not started")
        if args.phase in {"all", "chains"}:
            unready = [row.id for row in cases.itertuples(index=False) if not completed_summary(Path(row.output_dir) / "case_summary.json", "m0_launch_eligible")]
            if unready:
                raise RuntimeError(f"M0 chain launch blocked by {len(unready)} incomplete case replays")
            all_results.extend(run_lanes(list(chains.itertuples(index=False)), "chains", cpus, CHAIN_RUNNER, args, recorder))

        status_table = pd.DataFrame(all_results).sort_values(["phase", "id"])
        status_table.to_csv(orchestration / "launch_status.csv", index=False)
        failed = int(status_table.status.eq("failed").sum()) if not status_table.empty else 0
        final = {
            "status": "completed" if failed == 0 else "completed_with_failures",
            "worker_count": len(cpus), "logical_cpus": cpus, "results": len(status_table),
            "failed": failed, "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        atomic_json(orchestration / "launch_summary.json", final)
        recorder.publish("finished", status=final["status"])
        if failed:
            raise RuntimeError(f"{failed} R52/R53 jobs failed")
        return final
    except Exception as exc:
        recorder.publish("failed", status="failed", error=str(exc))
        raise


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
