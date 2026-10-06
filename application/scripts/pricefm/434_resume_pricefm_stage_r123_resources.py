#!/usr/bin/env python3
"""Resume frozen R123 fits with an independently versioned resource controller."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS"):
    os.environ[key] = "1"

import pricefm_r123_recovery as REC

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r123_bg_input_connectivity_20261003"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def load_frozen(root):
    scripts = root / "application/scripts/pricefm"
    sys.path.insert(0, str(scripts))
    loader = importlib.util.spec_from_file_location("r123_frozen_resource_recovery", scripts / "433_run_pricefm_stage_r123_connectivity.py")
    module = importlib.util.module_from_spec(loader); loader.loader.exec_module(module)
    return module


def audit(args, frozen, attempt, protocol):
    frozen.verify_preparation(args.prep_dir)
    control = REC.read(args.prep_dir / "launch_control.json")
    if control["code_head"] != protocol["frozen_fit_head"] or git(args.frozen_code_root, "rev-parse", "HEAD") != control["code_head"]:
        raise RuntimeError("frozen fitting worktree HEAD differs")
    if git(args.frozen_code_root, "status", "--porcelain") or git(ROOT, "status", "--porcelain"):
        raise RuntimeError("recovery and fitting worktrees must be committed and clean")
    if not git(ROOT, "branch", "--show-current").startswith("work/pricefm-"):
        raise RuntimeError("recovery requires a dedicated PriceFM branch")
    for flag in ("official_validation_authorized", "official_test_authorized", "article_mutation_authorized",
                 "registry_mutation_authorized", "exal_authorized", "joint_authorized", "mcmc_authorized"):
        if REC.read(args.prep_dir / "protocol.json")[flag] is not False:
            raise RuntimeError(f"unexpected scientific authorization: {flag}")
    frozen.verify_sources(control); frozen.verify_generated(args.campaign_root)
    design = REC.read(args.campaign_root / "broad_design_identity.json")
    if (REC.digest(args.prep_dir / "candidate_manifest.csv") != design["candidate_sha256"]
            or REC.digest(args.prep_dir / "execution_manifest.csv") != design["execution_sha256"]):
        raise RuntimeError("frozen screening design differs")
    ledger = REC.audit_ridge(args.prep_dir, args.campaign_root, protocol["expected_ridge_cells"])
    if len(REC.rows(args.campaign_root / "seed3/ranking.csv")) < protocol["minimum_robust_structures"]:
        raise RuntimeError("insufficient robust structures for the frozen RHS phase")
    gate = REC.read(args.prep_dir / "prior_gate.json")
    if gate["status"] != "R123_PRIOR_GATE_PASS" or not all(gate["checks"].values()):
        raise RuntimeError("frozen prior gate did not pass")
    if REC.digest(args.prep_dir / "prior_gate.json") != REC.read(args.prep_dir / "prior_gate_identity.json")["sha256"]:
        raise RuntimeError("prior gate evidence differs")
    REC.immutable(attempt / "screening_evidence.json", ledger)
    archive = REC.archive_metadata(args.campaign_root, attempt, args.log_file)
    driver_files = [Path(__file__).resolve(), Path(REC.__file__).resolve(), args.protocol.resolve()]
    identity = {"driver_head": git(ROOT, "rev-parse", "HEAD"), "driver_branch": git(ROOT, "branch", "--show-current"),
                "driver_worktree": str(ROOT), "driver_sources": {str(p): REC.digest(p) for p in driver_files},
                "fitting_head": control["code_head"], "fitting_worktree": str(args.frozen_code_root),
                "prep_identity_sha256": REC.digest(args.prep_dir / "identity.json"),
                "workers": args.workers, "statistical_contract_changed": False,
                "screening_refits_authorized": False, "test_opened": False}
    REC.immutable(attempt / "identity.json", identity)
    REC.write(attempt / "audit_summary.json", {"status": "RECOVERY_AUDIT_PASS", "cells": ledger["cells"],
              "completed_fits": ledger["fitted"], "washout_excluded": ledger["washout_excluded"],
              "source_files_verified": len(control["frozen_sources"]), "screening_hashes_verified": len(ledger["evidence_sha256"]),
              **REC.remaining_primary_fits(args.campaign_root), "updated_at_epoch": time.time()})
    return ledger, archive


def main(args):
    protocol = REC.read(args.protocol)
    for flag in ("official_test_authorized", "article_mutation_authorized", "statistical_changes_authorized"):
        if protocol[flag] is not False: raise ValueError(f"forbidden recovery authorization: {flag}")
    if not protocol["minimum_workers"] <= args.workers <= protocol["maximum_workers"]:
        raise ValueError("resource-only worker count outside 9..15")
    if (args.campaign_root.name != TAG or args.prep_dir.name != TAG
            or not args.attempt_id.replace("_", "").replace("-", "").isalnum()):
        raise ValueError("recovery scope or attempt ID differs")
    attempt = args.campaign_root / "attempts" / args.attempt_id
    attempt.mkdir(parents=True, exist_ok=True)
    permitted = os.sched_getaffinity(0)
    with (args.campaign_root / "recovery_controller.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Check the original lock before touching metadata or clearing any marker.
        with (args.campaign_root / "controller.lock").open("a+") as original_lock:
            fcntl.flock(original_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            running = args.campaign_root / "running.json"
            if running.exists() and Path(f"/proc/{REC.read(running)['pid']}").exists():
                raise RuntimeError("a campaign controller is already alive")
            frozen = load_frozen(args.frozen_code_root)
            ledger, archive = audit(args, frozen, attempt, protocol)
        if args.mode == "audit":
            REC.write(attempt / "live.json", {"status": "PREPARED_NOT_LAUNCHED", "updated_at_epoch": time.time()})
            return REC.read(attempt / "audit_summary.json")
        original = frozen.preflight
        original_queue = frozen.BACKEND._run_queue
        frozen.preflight = REC.FreshPoolPreflight(original, permitted, attempt, protocol, args.campaign_root, archive)
        frozen.BACKEND._run_queue = REC.ResumeQueue(original_queue, attempt)
        frozen_args = frozen.parser().parse_args(["--code-root", str(args.frozen_code_root),
            "--campaign-root", str(args.campaign_root), "--prep-dir", str(args.prep_dir), "--workers", str(args.workers)])
        REC.write(attempt / "live.json", {"status": "STARTING", "pid": os.getpid(), "updated_at_epoch": time.time()})
        try:
            result = frozen.controller(frozen_args)
            REC.verify_evidence(ledger)
            REC.write(attempt / "live.json", {"status": "COMPLETE", "pid": os.getpid(),
                      "screening_unchanged": True, "integration_status": "NOT_READY_FOR_INTEGRATION",
                      "updated_at_epoch": time.time()})
            return result
        except BlockingIOError:
            REC.write(attempt / "live.json", {"status": "LOCK_CONFLICT", "pid": os.getpid(),
                      "updated_at_epoch": time.time()})
            raise
        except Exception as error:
            REC.write(attempt / "live.json", {"status": "BLOCKED", "pid": os.getpid(),
                      "error_type": type(error).__name__, "error": str(error), "updated_at_epoch": time.time()})
            REC.write(args.campaign_root / "blocked.json", {"error_type": type(error).__name__, "error": str(error),
                      "recovery_attempt": str(attempt), "test_opened": False, "updated_at_epoch": time.time()})
            raise
        finally:
            frozen.preflight = original
            frozen.BACKEND._run_queue = original_queue


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("audit", "controller"), default="controller")
    parser.add_argument("--frozen-code-root", type=Path, required=True)
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT / "campaigns" / TAG)
    parser.add_argument("--prep-dir", type=Path, default=DEFAULT / "launch_prep" / TAG)
    parser.add_argument("--workers", type=int, default=15)
    parser.add_argument("--attempt-id", default="r123_resource_resume_20261004_01")
    parser.add_argument("--log-file", type=Path)
    parser.add_argument("--protocol", type=Path, default=ROOT / "application/config/pricefm_stage_r123_resume_protocol_20261004.json")
    args = parser.parse_args()
    try:
        import json
        print(json.dumps(main(args), sort_keys=True))
    except Exception:
        traceback.print_exc(); sys.exit(1)
