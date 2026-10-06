#!/usr/bin/env python3
"""Complete four R106 focus cases and run the R107 comparison."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r106_exact500_recursive_quantile_20260918"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r106_exact500_recursive_quantile_20260918"
PYTHON = DATA / "venv/bin/python"
WORKER = Path(__file__).with_name("359_run_pricefm_stage_r106_exact500_quantile_case.py")
CLOSEOUT = Path(__file__).with_name("362_closeout_pricefm_stage_r107_exact500_focus_comparison.py")
FOCUS_CASES = ("r106_bg_f1", "r106_be_f1", "r106_be_f2", "r106_be_f3")
APPROVAL = "RUN_PRICEFM_R106_FOCUS_COMPARISON"
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--workers", type=int, default=4)
    value.add_argument("--cpu-list", default="25-28")
    value.add_argument("--maximum-cpu-percent", type=float, default=25.0)
    value.add_argument("--approval-token", default="")
    value.add_argument("--preflight-only", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def parse_cpus(value: str) -> list[int]:
    cpus: list[int] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            start, stop = (int(part) for part in token.split("-", 1))
            cpus.extend(range(start, stop + 1))
        else:
            cpus.append(int(token))
    return cpus


def physical_core(cpu: int) -> str:
    base = Path("/sys/devices/system/cpu") / f"cpu{cpu}" / "topology"
    return "socket{}:core{}".format(
        (base / "physical_package_id").read_text().strip(),
        (base / "core_id").read_text().strip(),
    )


def cpu_snapshot() -> dict[int, float]:
    first = {}
    for line in Path("/proc/stat").read_text().splitlines():
        label = line.split(maxsplit=1)[0]
        if label.startswith("cpu") and label[3:].isdigit():
            fields = [int(value) for value in line.split()[1:]]
            first[int(label[3:])] = (sum(fields), fields[3] + fields[4])
    import time
    time.sleep(0.25)
    usage = {}
    for line in Path("/proc/stat").read_text().splitlines():
        label = line.split(maxsplit=1)[0]
        if label.startswith("cpu") and label[3:].isdigit():
            fields = [int(value) for value in line.split()[1:]]
            cpu = int(label[3:])
            total, idle = sum(fields), fields[3] + fields[4]
            old_total, old_idle = first[cpu]
            usage[cpu] = 100.0 * (1.0 - (idle - old_idle) / max(total - old_total, 1))
    return usage


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def verify_prep(prep: Path) -> pd.DataFrame:
    summary = read_json(prep / "summary.json")
    if summary.get("status") != "prepared_validation_only_campaign" or summary.get("test_opened") is not False:
        raise RuntimeError("R106 prep summary is invalid")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError(f"R106 prep hash mismatch: {role}")
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError(f"R106 source changed: {path}")
    cases = pd.read_csv(prep / "pricefm_stage_r106_case_manifest.csv")
    focus = cases[cases.case_id.astype(str).isin(FOCUS_CASES)].copy()
    if set(focus.case_id.astype(str)) != set(FOCUS_CASES) or len(focus) != 4:
        raise RuntimeError("R106 focus manifest is incomplete")
    for row in focus.itertuples(index=False):
        config = read_json(Path(row.case_config))
        stored = config.pop("case_contract_sha256")
        if stored != str(row.case_contract_sha256) or stored != canonical_hash(config):
            raise RuntimeError(f"R106 focus contract changed: {row.case_id}")
    return focus.sort_values("case_id").reset_index(drop=True)


def valid_case(row: Any) -> bool:
    terminal_path = Path(row.output_dir) / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        value = read_json(terminal_path)
        return (
            value.get("status") == "completed_recursive_quantile_case"
            and value.get("case_id") == str(row.case_id)
            and value.get("case_contract_sha256") == str(row.case_contract_sha256)
            and value.get("test_opened") is False
            and value.get("all_atoms_exact_500") is True
            and int(value.get("atoms_complete", -1)) == 14
        )
    except (OSError, ValueError, json.JSONDecodeError):
        return False


def active_broad_processes() -> list[str]:
    result = subprocess.run(
        ["ps", "-eo", "pid=,args="], text=True, capture_output=True, check=True
    )
    return [
        line.strip() for line in result.stdout.splitlines()
        if (
            "361_orchestrate_pricefm_stage_r106_exact500_recursive_quantile.py" in line
            or "359_run_pricefm_stage_r106_exact500_quantile_case.py" in line
            or "358_run_pricefm_stage_r106_exact500_quantile_case.R" in line
        )
        and str(os.getpid()) not in line
    ]


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.approval_token != APPROVAL:
        raise RuntimeError("R106 focus approval token mismatch")
    if int(args.workers) != 4:
        raise RuntimeError("R106 focus stage requires exactly four workers")
    prep = args.prep_dir.resolve()
    campaign = args.campaign_root.resolve()
    cases = verify_prep(prep)
    cpus = parse_cpus(args.cpu_list)
    if len(cpus) != 4 or len(set(cpus)) != 4:
        raise RuntimeError("R106 focus stage requires four unique logical CPUs")
    cores = [physical_core(cpu) for cpu in cpus]
    if len(set(cores)) != 4:
        raise RuntimeError("R106 focus CPUs must map to four physical cores")
    usage = cpu_snapshot()
    if any(usage.get(cpu, 100.0) > float(args.maximum_cpu_percent) for cpu in cpus):
        raise RuntimeError("R106 focus CPU preflight failed")
    active = active_broad_processes()
    if active:
        raise RuntimeError("R106 broad or duplicate processes remain active")
    preflight = {
        "stage": "R106-focus/R107",
        "status": "preflight_passed_not_launched" if args.preflight_only else "preflight_passed",
        "focus_cases": list(FOCUS_CASES),
        "workers": 4,
        "cpus": cpus,
        "physical_cores": cores,
        "cpu_usage_percent": {str(cpu): usage[cpu] for cpu in cpus},
        "completed_cases_reused": int(sum(valid_case(row) for row in cases.itertuples(index=False))),
        "test_opened": False,
    }
    campaign.mkdir(parents=True, exist_ok=True)
    write_json(campaign / "focus_preflight.json", preflight)
    if args.preflight_only:
        print(json.dumps(preflight, indent=2, sort_keys=True))
        return preflight

    state_lock = threading.Lock()
    state: dict[str, Any] = {
        "complete": 0, "failed": 0, "running": 0, "total": 4, "cases": {}
    }
    focus_logs = campaign / "focus_logs"
    focus_logs.mkdir(exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})

    def execute(row: Any, cpu: int) -> tuple[str, bool, str | None]:
        case_id = str(row.case_id)
        with state_lock:
            state["running"] += 1
            state["cases"][case_id] = "running"
            write_json(campaign / "focus_progress.json", state)
        command = [
            "taskset", "-c", str(cpu), str(PYTHON), str(WORKER),
            "--prep-dir", str(prep), "--case-id", case_id,
        ]
        log_path = focus_logs / f"{case_id}.log"
        with log_path.open("a") as handle:
            handle.write("$ " + " ".join(command) + "\n")
            handle.flush()
            result = subprocess.run(
                command, cwd=Path(__file__).resolve().parents[3], env=env,
                stdout=handle, stderr=subprocess.STDOUT, check=False,
            )
        ok = result.returncode == 0 and valid_case(row)
        error = None if ok else f"worker_returncode_{result.returncode}"
        with state_lock:
            state["running"] -= 1
            if ok:
                state["complete"] += 1
                state["cases"][case_id] = "complete"
            else:
                state["failed"] += 1
                state["cases"][case_id] = error
            write_json(campaign / "focus_progress.json", state)
        return case_id, ok, error

    failures = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [
            executor.submit(execute, row, cpu)
            for row, cpu in zip(cases.itertuples(index=False), cpus)
        ]
        for future in as_completed(futures):
            case_id, ok, error = future.result()
            if not ok:
                failures.append({"case_id": case_id, "error": error})
    if failures or state["complete"] != 4:
        terminal = {
            "stage": "R106-focus/R107",
            "status": "incomplete_with_failures",
            "failures": failures,
            "test_opened": False,
        }
        write_json(campaign / "focus_terminal.json", terminal)
        raise RuntimeError("R106 focus cases failed")
    closeout_log = focus_logs / "r107_closeout.log"
    with closeout_log.open("a") as handle:
        result = subprocess.run(
            [str(PYTHON), str(CLOSEOUT), "--campaign-root", str(campaign), "--force"],
            cwd=Path(__file__).resolve().parents[3], env=env,
            stdout=handle, stderr=subprocess.STDOUT, check=False,
        )
    if result.returncode:
        raise RuntimeError("R107 comparison closeout failed")
    summary_path = DATA / "authoritative/pricefm_stage_r107_exact500_focus_comparison_20260918/summary.json"
    summary = read_json(summary_path)
    terminal = {
        "stage": "R106-focus/R107",
        "status": summary["status"],
        "focus_cases_complete": 4,
        "focus_atoms_complete": summary["atoms_exact_500"],
        "recommended_action": summary["recommended_action"],
        "summary_path": str(summary_path.resolve()),
        "summary_sha256": sha256_file(summary_path),
        "test_opened": False,
    }
    write_json(campaign / "focus_terminal.json", terminal)
    print(json.dumps(terminal, indent=2, sort_keys=True))
    return terminal


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
