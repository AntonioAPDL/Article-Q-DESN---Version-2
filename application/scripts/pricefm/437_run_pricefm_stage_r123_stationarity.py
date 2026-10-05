#!/usr/bin/env python3
"""Bounded, source-verified diagnostics; never launch selection or quantile fitting."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
            "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS"):
    os.environ[key] = "1"

import pricefm_r123_recovery as REC

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r123_stationarity_diagnosis_20261004"
PARENT = "pricefm_stage_r123_bg_input_connectivity_20261003"


def frozen_module(code):
    path = Path(code) / "application/scripts/pricefm/433_run_pricefm_stage_r123_connectivity.py"
    sys.path.insert(0, str(path.parent))
    loader = importlib.util.spec_from_file_location("r123_stationarity_frozen", path)
    module = importlib.util.module_from_spec(loader); loader.loader.exec_module(module)
    return module


def verify_parent(args):
    frozen = frozen_module(args.frozen_code_root)
    control = REC.read(args.prep_dir / "launch_control.json")
    frozen.verify_preparation(args.prep_dir); frozen.verify_sources(control)
    frozen.verify_generated(args.parent_campaign)
    ledger = REC.audit_ridge(args.prep_dir, args.parent_campaign, 1298)
    manifest = REC.rows(args.parent_campaign / "rhs/center/manifest.csv")
    if len(manifest) != 90 or len({row["fit_id"] for row in manifest}) != 90:
        raise RuntimeError("parent centre inventory differs")
    for row in manifest:
        contract = Path(row["contract_path"])
        ledger["evidence_sha256"][str(contract)] = REC.digest(contract)
        output = Path(row["output_dir"])
        if (output / "terminal.json").exists():
            if not frozen.guarded_normal_valid(output): raise RuntimeError("corrupt parent fit")
            for path in output.iterdir():
                if path.is_file(): ledger["evidence_sha256"][str(path)] = REC.digest(path)
        else:
            log = args.parent_campaign / f"logs/rhs_center_fit/{row['fit_id']}.log"
            lines = log.read_text().strip().splitlines()
            if output.exists() or len(lines) != 3 or lines[1:] != [
                "Error: R102 RHS fit did not meet its frozen convergence criterion", "Execution halted"]:
                raise RuntimeError("unrecognized parent rejection")
            ledger["evidence_sha256"][str(log)] = REC.digest(log)
    return frozen, control, ledger, manifest


def diagnostic_contract(row, args, control, protocol, initialization):
    parent = REC.read(row["contract_path"])
    identifier = row["fit_id"] + "_" + initialization
    checkpoint = Path(row["output_dir"]) / "fit.rds" if initialization == "resume" else None
    helper = ROOT / "application/R/pricefm_recursive_normal_fit.R"
    entrypoint = ROOT / "application/scripts/pricefm/436_diagnose_pricefm_stage_r123_stationarity.R"
    sources = [helper, entrypoint, Path(control["normal_runtime"]) / "R/qdesn_rhs_ns_prior.R",
               Path(control["normal_runtime"]) / "R/priors_beta.R"]
    return dict(parent, fit_id=identifier, candidate_id=row["candidate_id"], split=int(row["split"]),
        output_dir=str(args.output_root / "fits" / identifier), helper_path=str(helper),
        max_iter=protocol["resume_total_iteration_cap"] if checkpoint else protocol["fresh_total_iteration_cap"],
        min_iter=protocol["minimum_iteration"], convergence_mode="full_variational",
        stability_window=protocol["full_state_stability_window"],
        rhs_state_tol=protocol["rhs_state_tol"], covariance_tol=protocol["covariance_tol"],
        objective_per_observation_tol=protocol["objective_per_observation_tol"],
        precision_accuracy_tol=protocol["precision_accuracy_tol"],
        initial_fit_path=str(checkpoint) if checkpoint else None,
        initial_fit_sha256=REC.digest(checkpoint) if checkpoint else None,
        initial_tau=parent["tau0"] if initialization == "prior_scale" else 1,
        target_contract_sha256=REC.digest(row["contract_path"]),
        source_sha256={str(path): REC.digest(path) for path in sources},
        selection_authorized=False)


def valid_diagnostic(output, contract_path):
    output = Path(output)
    if not output.exists(): return False
    value = REC.read(output / "terminal.json")
    if (value["status"] not in ("R123_FULL_VARIATIONAL_CERTIFIED", "R123_VARIATIONAL_CAP_DIAGNOSTIC", "R123_NUMERICAL_ACCURACY_REJECTED")
            or value["contract_sha256"] != REC.digest(contract_path)
            or value["test_opened"] is not False or value["selection_authorized"] is not False):
        raise RuntimeError("diagnostic identity differs")
    if set(value["artifact_sha256"]) != {"fit.rds", "convergence_trace.csv", "geometry.json", "summary.json"}:
        raise RuntimeError("diagnostic artifacts incomplete")
    for name, wanted in value["artifact_sha256"].items():
        if REC.digest(output / name) != wanted: raise RuntimeError("diagnostic artifact differs")
    return True


def prepare(args):
    if args.output_root.name != TAG or args.parent_campaign.name != PARENT or args.prep_dir.name != PARENT:
        raise ValueError("diagnosis confined to R123 BG and its new output namespace")
    protocol = REC.read(args.protocol)
    if not 1 <= args.workers <= protocol["maximum_workers"]: raise ValueError("invalid worker count")
    frozen, control, ledger, rows = verify_parent(args)
    jobs = []
    for identifier in protocol["resume_candidate_ids"]:
        for split in (1, 2, 3):
            row = next(row for row in rows if row["candidate_id"] == identifier and int(row["split"]) == split)
            if not frozen.guarded_normal_valid(Path(row["output_dir"])): raise RuntimeError("missing resume fit")
            jobs.append(diagnostic_contract(row, args, control, protocol, "resume"))
    for identifier in protocol["rejected_candidate_ids"]:
        row = next(row for row in rows if row["candidate_id"] == identifier and int(row["split"]) == protocol["rejected_split"])
        if Path(row["output_dir"]).exists(): raise RuntimeError("diagnostic expects a rejected fit")
        for initialization in protocol["fresh_initial_tau"]:
            jobs.append(diagnostic_contract(row, args, control, protocol, initialization))
    if len(jobs) != 10 or len({job["fit_id"] for job in jobs}) != 10:
        raise RuntimeError("bounded diagnostic panel must contain exactly ten jobs")
    REC.immutable(args.output_root / "protocol.json", protocol)
    REC.immutable(args.output_root / "protected_parent.json", ledger)
    for job in jobs: REC.immutable(args.output_root / "contracts" / f"{job['fit_id']}.json", job)
    REC.immutable(args.output_root / "manifest.json", jobs)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("diagnostic code must be committed and clean")
    REC.immutable(args.output_root / "source_identity.json", dict(head=head,
        frozen_head=control["code_head"], protocol_sha256=REC.digest(args.protocol),
        driver_sha256=REC.digest(__file__), source_checks=len(control["frozen_sources"])))
    return frozen, control, ledger, jobs


def controller(args):
    args.output_root.mkdir(parents=True, exist_ok=True)
    with (args.output_root / "controller.lock").open("a+") as lock, \
         (args.parent_campaign / "controller.lock").open("a+") as parent_lock, \
         (args.parent_campaign / "recovery_controller.lock").open("a+") as recovery_lock:
        for handle in (lock, parent_lock, recovery_lock): fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        frozen, control, ledger, jobs = prepare(args)
        if args.mode == "prepare": return {"status": "R123_STATIONARITY_PREPARED", "jobs": len(jobs)}
        REC.verify_evidence(ledger)
        usage = frozen.BACKEND._cpu_snapshot(10); groups = {}
        for cpu, value in usage.items(): groups.setdefault(frozen.BACKEND._physical(cpu), []).append((cpu, value))
        permitted = os.sched_getaffinity(0)
        cpus = [min(cpu for cpu, _ in siblings if cpu in permitted) for siblings in groups.values()
                if any(cpu in permitted for cpu, _ in siblings) and max(v for _, v in siblings) <= 20]
        import shutil
        memory = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
                      if line.startswith("MemAvailable:")) / 2**20
        disk = shutil.disk_usage(args.output_root).free / 2**30
        if len(cpus) < args.workers or memory < 200 or disk < 200: raise RuntimeError("resource floor failed")
        cpus = sorted(cpus)[:args.workers]
        REC.write(args.output_root / "resource_gate.json", dict(cpus=cpus, workers=args.workers,
            available_memory_gib=memory, free_disk_gib=disk, physical_core_percent_max=20))
        REC.write(args.output_root / "running.json", dict(pid=os.getpid(), cpus=cpus, started_at_epoch=time.time()))
        pending = [job for job in jobs if not valid_diagnostic(job["output_dir"],
                    args.output_root / "contracts" / f"{job['fit_id']}.json")]
        # Fixed CPU slots: a slot finishes its task before admitting another task.
        def slot(index):
            for job in pending[index::len(cpus)]:
                contract = args.output_root / "contracts" / f"{job['fit_id']}.json"
                frozen.BACKEND._command([control["rscript"], str(ROOT /
                    "application/scripts/pricefm/436_diagnose_pricefm_stage_r123_stationarity.R"),
                    "--contract", str(contract)], ROOT, args.output_root / "logs" / f"{job['fit_id']}.log", cpus[index])
                if not valid_diagnostic(job["output_dir"], contract): raise RuntimeError("missing diagnostic output")
        with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
            for result in pool.map(slot, range(len(cpus))): pass
        REC.verify_evidence(ledger); frozen.verify_sources(control)
        outcomes = [REC.read(Path(job["output_dir"]) / "summary.json") for job in jobs]
        value = dict(status="R123_STATIONARITY_DIAGNOSIS_COMPLETE", jobs=len(jobs),
            certified=sum(row["converged"] for row in outcomes), capped=sum(not row["converged"] for row in outcomes),
            outcomes=outcomes, completed_at_epoch=time.time(), parent_evidence_unchanged=True,
            quantile_launch_authorized=False, test_opened=False, integration_status="NOT_READY_FOR_INTEGRATION")
        REC.immutable(args.output_root / "terminal.json", value)
        return value


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("prepare", "controller"), default="prepare")
    parser.add_argument("--frozen-code-root", type=Path, required=True)
    parser.add_argument("--parent-campaign", type=Path, default=DEFAULT / "campaigns" / PARENT)
    parser.add_argument("--prep-dir", type=Path, default=DEFAULT / "launch_prep" / PARENT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT / "campaigns" / TAG)
    parser.add_argument("--protocol", type=Path, default=ROOT / "application/config/pricefm_stage_r123_stationarity_protocol_20261004.json")
    parser.add_argument("--workers", type=int, default=10)
    args = parser.parse_args()
    try:
        import json
        print(json.dumps(controller(args), sort_keys=True))
    except Exception as error:
        REC.write(args.output_root / "blocked.json", dict(status="R123_DIAGNOSIS_BLOCKED",
            error_type=type(error).__name__, error=str(error), test_opened=False, at_epoch=time.time()))
        raise
