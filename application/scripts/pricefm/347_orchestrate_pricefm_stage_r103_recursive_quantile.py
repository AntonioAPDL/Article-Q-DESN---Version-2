#!/usr/bin/env python3
"""Launch and resume the validation-only R103 recursive quantile campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
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
from pricefm_region_frozen_contract import git_identity


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r103_recursive_quantile_20260916"
PYTHON = DATA / "venv/bin/python"
WORKER = Path(__file__).with_name("345_run_pricefm_stage_r103_quantile_case.py")
CLOSEOUT = Path(__file__).with_name("346_closeout_pricefm_stage_r103_recursive_quantile.py")
APPROVAL = "RUN_PRICEFM_R103_RECURSIVE_QUANTILE"
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--workers", type=int, default=12)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    value.add_argument("--minimum-free-gib", type=float, default=80.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=48.0)
    value.add_argument("--approval-token", required=True)
    value.add_argument("--preflight-only", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def parse_cpus(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = map(int, token.split("-", 1))
            result.extend(range(lower, upper + 1))
        else:
            result.append(int(token))
    if len(result) != len(set(result)) or any(cpu < 0 or cpu >= (os.cpu_count() or 0) for cpu in result):
        raise RuntimeError("R103 CPU list is invalid")
    return result


def cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        values = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(value) for value in fields[1:]]
                values[int(fields[0][3:])] = (
                    sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0)
                )
        return values
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100.0 * (1 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        if after[cpu][0] > total else 100.0
        for cpu, (total, idle) in before.items()
    }


def physical_core(cpu: int) -> str:
    path = Path("/sys/devices/system/cpu/cpu{}/topology/core_id".format(cpu))
    package = Path("/sys/devices/system/cpu/cpu{}/topology/physical_package_id".format(cpu))
    return "{}:{}".format(package.read_text().strip(), path.read_text().strip())


def choose_cpus(workers: int, maximum: float, explicit: str) -> tuple[list[int], dict[int, float]]:
    first = cpu_snapshot()
    second = cpu_snapshot()
    usage = {cpu: max(first[cpu], second[cpu]) for cpu in first}
    core_usage: dict[str, float] = {}
    for cpu, observed in usage.items():
        core = physical_core(cpu)
        core_usage[core] = max(core_usage.get(core, 0.0), observed)
    candidates = parse_cpus(explicit) if explicit else [
        cpu for cpu, observed in sorted(usage.items(), key=lambda item: (item[1], item[0]))
        if observed <= maximum and core_usage[physical_core(cpu)] <= maximum
    ]
    selected = []
    cores = set()
    for cpu in candidates:
        core = physical_core(cpu)
        if core in cores or core_usage[core] > maximum:
            continue
        selected.append(cpu)
        cores.add(core)
        if len(selected) == workers:
            break
    if len(selected) != workers:
        raise RuntimeError("only {} idle physical cores satisfy the R103 gate".format(len(selected)))
    return selected, usage


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def valid_case(path: Path, case_id: str, case_contract_sha256: str) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        terminal = read_json(terminal_path)
        if (
            terminal.get("status") != "completed_recursive_quantile_case"
            or terminal.get("case_id") != case_id
            or terminal.get("case_contract_sha256") != case_contract_sha256
            or terminal.get("test_opened") is not False
            or int(terminal.get("atoms_complete", -1)) != 14
        ):
            return False
        artifacts_valid = all(
            Path(record["path"]).is_file()
            and sha256_file(record["path"]) == record["sha256"]
            for record in terminal["artifacts"]
        )
        metrics = pd.read_csv(path / "family_validation_metrics.csv")
        al = metrics[metrics.family.eq("al")]
        return artifacts_valid and len(al) == 1 and bool(al.iloc[0].numerically_eligible)
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    if summary.get("status") != "prepared_validation_only_campaign" or summary.get("test_opened") is not False:
        raise RuntimeError("R103 prep is invalid")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R103 prep hash mismatch: {}".format(role))
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError("R103 source changed: {}".format(path))
    cases = pd.read_csv(prep / "pricefm_stage_r103_case_manifest.csv")
    if len(cases) != 114 or cases.test_access_authorized.astype(bool).any():
        raise RuntimeError("R103 case manifest is invalid")
    return summary, cases


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.approval_token != APPROVAL:
        raise RuntimeError("R103 approval token mismatch")
    if not 1 <= int(args.workers) <= 20:
        raise RuntimeError("R103 permits 1--20 one-core workers")
    prep = args.prep_dir.resolve()
    campaign = args.campaign_root.resolve()
    summary, cases = verify_prep(prep)
    code_root = Path(summary["source_git"]["worktree"]).resolve()
    git = git_identity(code_root)
    if not git.clean or git.head != git.upstream_head or git.head != summary["source_git"]["head"]:
        raise RuntimeError("R103 launch source is dirty, unsynchronized, or differs from prep")
    if shutil.disk_usage(campaign.parent).free / 1024**3 < float(args.minimum_free_gib):
        raise RuntimeError("R103 disk gate failed")
    if available_memory_gib() < float(args.minimum_available_memory_gib):
        raise RuntimeError("R103 memory gate failed")
    cpus, usage = choose_cpus(int(args.workers), float(args.maximum_cpu_percent), args.cpu_list)
    preflight = {
        "stage": "R103",
        "status": "preflight_passed_not_launched" if args.preflight_only else "preflight_passed",
        "workers": len(cpus),
        "cpus": cpus,
        "physical_cores": [physical_core(cpu) for cpu in cpus],
        "cpu_usage_percent": {str(cpu): usage[cpu] for cpu in cpus},
        "available_memory_gib": available_memory_gib(),
        "free_disk_gib": shutil.disk_usage(campaign.parent).free / 1024**3,
        "source_git": git.to_dict(),
        "cases_total": len(cases),
        "test_opened": False,
    }
    campaign.mkdir(parents=True, exist_ok=True)
    write_json(campaign / ("launch_preflight.no_run.json" if args.preflight_only else "launch_preflight.json"), preflight)
    if args.preflight_only:
        print(json.dumps(preflight, indent=2, sort_keys=True))
        return preflight

    state_lock = threading.Lock()
    state: dict[str, Any] = {"complete": 0, "failed": 0, "running": 0, "total": len(cases), "cases": {}}
    for row in cases.itertuples(index=False):
        if valid_case(Path(row.output_dir), str(row.case_id), str(row.case_contract_sha256)):
            state["complete"] += 1
            state["cases"][str(row.case_id)] = "complete_reused"
    write_json(campaign / "progress.json", state)
    pending = [
        row for row in cases.itertuples(index=False)
        if not valid_case(Path(row.output_dir), str(row.case_id), str(row.case_contract_sha256))
    ]
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    logs = campaign / "logs"
    logs.mkdir(exist_ok=True)

    def execute(row: Any, cpu: int) -> tuple[str, bool, str | None]:
        case_id = str(row.case_id)
        with state_lock:
            state["running"] += 1
            state["cases"][case_id] = "running"
            write_json(campaign / "progress.json", state)
        log_path = logs / "{}.log".format(case_id)
        command = [
            "taskset", "-c", str(cpu), str(PYTHON), str(WORKER),
            "--prep-dir", str(prep), "--case-id", case_id,
        ]
        with log_path.open("a") as handle:
            handle.write("$ " + " ".join(command) + "\n")
            handle.flush()
            result = subprocess.run(command, cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
        ok = result.returncode == 0 and valid_case(
            Path(row.output_dir), case_id, str(row.case_contract_sha256)
        )
        error = None if ok else "worker_returncode_{}".format(result.returncode)
        with state_lock:
            state["running"] -= 1
            if ok:
                state["complete"] += 1
                state["cases"][case_id] = "complete"
            else:
                state["failed"] += 1
                state["cases"][case_id] = error
            write_json(campaign / "progress.json", state)
        return case_id, ok, error

    buckets = [[] for _ in cpus]
    for index, row in enumerate(pending):
        buckets[index % len(cpus)].append(row)
    failures = []
    failures_lock = threading.Lock()

    def cpu_worker(cpu: int, bucket: list[Any]) -> None:
        for row in bucket:
            case_id, ok, error = execute(row, cpu)
            if not ok:
                with failures_lock:
                    failures.append({"case_id": case_id, "error": error})

    with ThreadPoolExecutor(max_workers=len(cpus)) as executor:
        futures = [
            executor.submit(cpu_worker, cpu, bucket)
            for cpu, bucket in zip(cpus, buckets)
            if bucket
        ]
        for future in as_completed(futures):
            future.result()
    if failures or state["complete"] != len(cases):
        terminal = {
            "stage": "R103",
            "status": "incomplete_with_failures",
            "complete": state["complete"],
            "failed": len(failures),
            "failures": failures,
            "test_opened": False,
        }
        write_json(campaign / "campaign_terminal.json", terminal)
        raise RuntimeError("R103 campaign has failed cases")
    closeout_log = logs / "closeout.log"
    with closeout_log.open("a") as handle:
        result = subprocess.run(
            [str(PYTHON), str(CLOSEOUT), "--prep-dir", str(prep), "--force"],
            cwd=code_root, env=env, stdout=handle, stderr=subprocess.STDOUT, check=False,
        )
    if result.returncode:
        raise RuntimeError("R103 closeout failed")
    closeout_summary = DATA / "authoritative/pricefm_stage_r103_recursive_quantile_closeout_20260916/summary.json"
    terminal = read_json(closeout_summary)
    campaign_terminal = {
        "stage": "R103",
        "status": terminal["status"],
        "cases_complete": state["complete"],
        "atoms_complete": 1596,
        "selected_AL_regions": terminal["selected_AL_regions"],
        "selected_exAL_regions": terminal["selected_exAL_regions"],
        "aggregate_validation_AQL_original": terminal["aggregate_validation_AQL_original"],
        "closeout_summary_path": str(closeout_summary.resolve()),
        "closeout_summary_sha256": sha256_file(closeout_summary),
        "next_gate": terminal["next_gate"],
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(campaign / "campaign_terminal.json", campaign_terminal)
    print(json.dumps(campaign_terminal, indent=2, sort_keys=True))
    return campaign_terminal


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
