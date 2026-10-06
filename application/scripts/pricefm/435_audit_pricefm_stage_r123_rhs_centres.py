#!/usr/bin/env python3
"""Finish frozen R123 centre fits without retrying convergence failures or selecting winners."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import os
from pathlib import Path
import sys
import threading
import time
import traceback

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
            "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS"):
    os.environ[key] = "1"

import pricefm_r123_recovery as REC

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location("r123_resource_driver_for_centre_audit",
                                              SCRIPTS / "434_resume_pricefm_stage_r123_resources.py")
DRIVER = importlib.util.module_from_spec(loader); loader.loader.exec_module(DRIVER)
CAP_ERROR = "Error: R102 RHS fit did not meet its frozen convergence criterion"


def cap_evidence(command, log, contract, output):
    """Only the frozen, pre-artifact convergence stop is admissible as a rejection."""
    text = Path(log).read_text()
    lines = text.strip().splitlines()
    if (len(lines) != 3 or not lines[0].startswith("$ ") or lines[1:] != [CAP_ERROR, "Execution halted"]
            or not lines[0].endswith(" ".join(command)) or Path(output).exists()):
        raise RuntimeError(f"unexpected failure or partial output preserved: {log}")
    return {"status": "REJECTED_FROZEN_CONVERGENCE", "log": str(log), "log_sha256": REC.digest(log),
            "contract": str(contract), "contract_sha256": REC.digest(contract),
            "output_dir": str(output), "iteration_cap": 2000, "accepted_as_fit": False}


def centre_inventory(frozen, args):
    campaign, prep = args.campaign_root, args.prep_dir
    control = REC.read(prep / "launch_control.json")
    candidates = frozen.BACKEND._ordered_candidates(prep,
        frozen.pd.read_csv(campaign / "seed3/ranking.csv"), 30)
    if len(candidates) != 30: raise RuntimeError("the frozen 30-structure shortlist is incomplete")
    manifest = frozen.pd.read_csv(campaign / "rhs/center/manifest.csv")
    if len(manifest) != 90 or manifest.fit_id.nunique() != 90:
        raise RuntimeError("centre manifest must contain exactly 90 distinct fits")
    wanted, protected = {}, {}
    for row in candidates.itertuples(index=False):
        tau0 = frozen.BACKEND._tau_center(int(row.readout_dimension), 766 * 96)
        for split in (1, 2, 3):
            identifier = f"r122rhs_{row.candidate_id}_s{split}_t{tau0:.8e}"
            stats = campaign / f"rhs/stats/{row.candidate_id}/split={split}"
            stats_terminal = REC.read(stats / "terminal.json")
            metadata = REC.read(stats / "statistics.json")
            reference = frozen.BACKEND._stats_from_ridge(
                frozen.BACKEND._canonical_fit(prep, campaign, str(row.candidate_id)), split)
            if (stats_terminal.get("status") != "completed_causal_sufficient_statistics"
                    or stats_terminal.get("test_opened") is not False
                    or metadata.get("test_opened") is not False
                    or any(metadata.get(key) != reference[key] for key in ("n", "p", "yty"))):
                raise RuntimeError(f"centre statistics metadata differs: {stats}")
            protected[str(stats / "terminal.json")] = REC.digest(stats / "terminal.json")
            for name, record in stats_terminal["files"].items():
                if name not in ("XtX.bin", "Xty.bin", "statistics.json"):
                    raise RuntimeError("unexpected sufficient-statistic artifact")
                path = stats / name
                if path.stat().st_size != record["bytes"] or REC.digest(path) != record["sha256"]:
                    raise RuntimeError(f"centre statistic checksum differs: {path}")
                protected[str(path)] = record["sha256"]
            if set(stats_terminal["files"]) != {"XtX.bin", "Xty.bin", "statistics.json"}:
                raise RuntimeError("incomplete sufficient-statistic packet")
            for key in ("XtX", "Xty"):
                payload = frozen.np.asarray(reference[key], dtype="<f8").tobytes(order="C")
                if hashlib.sha256(payload).hexdigest() != stats_terminal["files"][f"{key}.bin"]["sha256"]:
                    raise RuntimeError(f"centre statistics differ from frozen Ridge: {stats}")
            output = campaign / f"rhs/center/fits/{identifier}"
            contract_path = campaign / f"rhs/center/contracts/{identifier}.json"
            contract = frozen.BACKEND._normal_contract(identifier, stats, output, tau0, control, args.frozen_code_root)
            if REC.read(contract_path) != contract or contract["max_iter"] != 2000:
                raise RuntimeError(f"the frozen Normal contract changed: {contract_path}")
            wanted[identifier] = {"candidate_id": row.candidate_id, "split": split,
                "contract": contract_path, "output": output,
                "command": [control["rscript"], str(args.frozen_code_root /
                    "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"),
                    "--contract", str(contract_path)],
                "log": campaign / f"logs/rhs_center_fit/{identifier}.log"}
    if set(manifest.fit_id) != set(wanted): raise RuntimeError("centre IDs differ from the frozen shortlist")
    rejected, complete = {}, []
    for record in manifest.to_dict("records"):
        identifier = record["fit_id"]; item = wanted[identifier]
        if (record["candidate_id"] != item["candidate_id"] or int(record["split"]) != item["split"]
                or record["contract_path"] != str(item["contract"])
                or record["output_dir"] != str(item["output"]) or record["stage_label"] != "center"):
            raise RuntimeError(f"centre manifest paths or labels differ: {identifier}")
        protected[str(item["contract"])] = REC.digest(item["contract"])
        if frozen.guarded_normal_valid(item["output"]):
            complete.append(identifier)
            for path in item["output"].iterdir():
                if path.is_file(): protected[str(path)] = REC.digest(path)
        elif item["log"].exists():
            rejected[identifier] = cap_evidence(item["command"], item["log"], item["contract"], item["output"])
        elif item["output"].exists():
            raise RuntimeError(f"partial centre output preserved: {item['output']}")
    return candidates, wanted, protected, rejected, complete


class CentreAdmission:
    """Continue independent candidates, but never turn a capped fit into a winner."""

    def __init__(self, frozen, attempt, wanted, rejected):
        self.frozen = frozen; self.attempt = Path(attempt); self.wanted = wanted
        self.rejected = dict(rejected); self.prior_rejected = set(rejected)
        self.command = frozen.BACKEND._command; self.queue = frozen.BACKEND._run_queue
        self.lock = threading.Lock()

    def persist(self):
        REC.write(self.attempt / "convergence_rejections.json", self.rejected)

    def run_command(self, command, code, log, cpu=None):
        identifier = next((key for key, item in self.wanted.items() if command == item["command"]), None)
        try:
            return self.command(command, code, log, cpu)
        except RuntimeError as error:
            if identifier is None or not str(error).startswith("command failed (1): "): raise
            item = self.wanted[identifier]
            rejection = cap_evidence(command, log, item["contract"], item["output"])
            with self.lock:
                self.rejected[identifier] = rejection; self.persist()

    def run_queue(self, tasks, cpus, code, progress_path, expected_total, **kwargs):
        label = Path(progress_path).parent.name
        if label != "center" or int(expected_total) != 90:
            raise RuntimeError("bounded audit refuses any stage beyond the 90 centre fits/scores")
        filtered = []
        for identifier, command, log in tasks:
            if identifier not in self.wanted: raise RuntimeError("unknown centre task")
            if Path(progress_path).name == "fit_progress.json":
                item = self.wanted[identifier]
                if command != item["command"] or Path(log) != item["log"]:
                    raise RuntimeError("centre command differs from its frozen contract")
                if identifier in self.rejected:
                    current = cap_evidence(command, log, item["contract"], item["output"])
                    if current != self.rejected[identifier]: raise RuntimeError("rejected-fit evidence changed")
                    continue
                if item["output"].exists() or item["log"].exists():
                    raise RuntimeError("refusing to repeat an attempted centre fit")
            elif Path(progress_path).name == "score_progress.json":
                if ("--mode" not in command or command[command.index("--mode") + 1] != "rhs-score"
                        or not self.frozen.guarded_normal_valid(self.wanted[identifier]["output"])):
                    raise RuntimeError("only successful frozen centre fits may be scored")
            else:
                raise RuntimeError("unexpected centre queue")
            filtered.append((identifier, command, log))
        REC.write(self.attempt / f"{Path(progress_path).stem}_admission.json", {
            "expected_total": 90, "new_tasks": len(filtered), "prior_rejections_not_retried": len(self.prior_rejected),
            "screening_refits": 0, "posterior_target_changed": False, "updated_at_epoch": time.time()})
        result = self.queue(filtered, cpus, code, progress_path, expected_total, **kwargs)
        if Path(progress_path).name == "fit_progress.json":
            new_rejections = sorted(set(self.rejected) - self.prior_rejected)
            # The backend counts handled commands; expose scientific success separately.
            result["handled_this_resume"] = result["complete_this_resume"]
            result["complete_this_resume"] -= len(new_rejections)
            result["failed_this_resume"] += len(new_rejections)
            result["convergence_rejected_task_ids"] = new_rejections
            result["prior_rejections_not_retried"] = len(self.prior_rejected)
            REC.write(progress_path, result)
        return result


def main(args):
    if args.campaign_root.name != DRIVER.TAG or args.prep_dir.name != DRIVER.TAG:
        raise ValueError("audit is confined to the existing BG R123 campaign")
    if not args.attempt_id.replace("_", "").replace("-", "").isalnum(): raise ValueError("invalid attempt ID")
    protocol = REC.read(args.protocol)
    if not protocol["minimum_workers"] <= args.workers <= protocol["maximum_workers"]:
        raise ValueError("audit requires 9..15 physical workers")
    attempt = args.campaign_root / "attempts" / args.attempt_id
    attempt.mkdir(parents=True, exist_ok=True)
    with (args.campaign_root / "recovery_controller.lock").open("a+") as recovery_lock, \
         (args.campaign_root / "controller.lock").open("a+") as lock:
        fcntl.flock(recovery_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        frozen = DRIVER.load_frozen(args.frozen_code_root)
        ledger, archive = DRIVER.audit(args, frozen, attempt, protocol)
        candidates, wanted, protected, rejected, complete = centre_inventory(frozen, args)
        REC.immutable(attempt / "centre_sources.json", {"driver_head": DRIVER.git(ROOT, "rev-parse", "HEAD"),
            "driver_sha256": REC.digest(__file__), "fitting_head": protocol["frozen_fit_head"],
            "selection_rule_changed": False, "iteration_budget_changed": False})
        REC.immutable(attempt / "protected_centre_evidence.json", {"evidence_sha256": protected})
        REC.immutable(attempt / "initial_centre_inventory.json", {"converged": complete, "rejected": rejected,
            "unattempted": sorted(set(wanted) - set(complete) - set(rejected))})
        REC.write(attempt / "convergence_rejections.json", rejected)
        if args.mode == "audit":
            return {"status": "CENTRE_RESUME_AUDIT_PASS", "converged": len(complete),
                    "convergence_rejected": len(rejected), "unattempted": 90 - len(complete) - len(rejected)}
        control = REC.read(args.prep_dir / "launch_control.json")
        gate = REC.FreshPoolPreflight(frozen.preflight, os.sched_getaffinity(0), attempt,
                                     protocol, args.campaign_root, archive)
        cpus = gate(args, control)
        REC.write(args.campaign_root / "running.json", {"pid": os.getpid(), "cpus": cpus,
            "code_head": protocol["frozen_fit_head"], "recovery_attempt": str(attempt),
            "phase": "BOUNDED_CENTRE_AUDIT", "started_at_epoch": time.time(), "test_opened": False})
        REC.write(attempt / "live.json", {"status": "FITTING_CENTRES", "pid": os.getpid(),
                  "cpus": cpus, "updated_at_epoch": time.time()})
        admission = CentreAdmission(frozen, attempt, wanted, rejected)
        frozen.BACKEND._command = admission.run_command
        frozen.BACKEND._run_queue = admission.run_queue
        frozen_args = frozen.parser().parse_args(["--code-root", str(args.frozen_code_root),
            "--prep-dir", str(args.prep_dir), "--campaign-root", str(args.campaign_root),
            "--workers", str(args.workers), "--cpu-list", ",".join(map(str, cpus))])
        try:
            centers = {str(row.candidate_id): [frozen.BACKEND._tau_center(int(row.readout_dimension), 766 * 96)]
                       for row in candidates.itertuples(index=False)}
            cells = frozen.BACKEND._rhs_cells(frozen_args, args.prep_dir, args.campaign_root,
                args.frozen_code_root, cpus, candidates, centers, "center")
            successful = sum(frozen.guarded_normal_valid(item["output"]) for item in wanted.values())
            if successful + len(admission.rejected) != 90: raise RuntimeError("centre audit has unfinished cells")
            ranking = frozen.BACKEND._complete_rhs(cells)
            ranking.to_csv(attempt / "complete_candidate_ranking.csv", index=False)
            REC.verify_evidence(ledger); REC.verify_evidence({"evidence_sha256": protected})
            frozen.verify_sources(control); frozen.verify_generated(args.campaign_root)
            summary = {"status": "CENTRE_AUDIT_COMPLETE_SELECTION_BLOCKED", "pid": os.getpid(),
                "expected_fits": 90, "converged": successful, "convergence_rejected": len(admission.rejected),
                "complete_three_split_candidates": len(ranking), "unattempted": 0,
                "official_test_opened": False, "tau_al_launched": False,
                "screening_and_previous_fits_unchanged": True, "integration_status": "NOT_READY_FOR_INTEGRATION",
                "updated_at_epoch": time.time()}
            REC.write(attempt / "live.json", summary)
            REC.write(args.campaign_root / "blocked.json", dict(summary,
                error="Centre audit complete; convergence rejections require review before tau/AL selection",
                recovery_attempt=str(attempt)))
            return summary
        except Exception as error:
            summary = {"status": "BLOCKED_UNEXPECTED_ERROR", "error_type": type(error).__name__,
                "error": str(error), "pid": os.getpid(), "test_opened": False,
                "recovery_attempt": str(attempt), "updated_at_epoch": time.time()}
            REC.write(attempt / "live.json", summary); REC.write(args.campaign_root / "blocked.json", summary)
            raise
        finally:
            frozen.BACKEND._command = admission.command; frozen.BACKEND._run_queue = admission.queue


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("audit", "controller"), default="audit")
    parser.add_argument("--frozen-code-root", type=Path, required=True)
    parser.add_argument("--campaign-root", type=Path, default=DRIVER.DEFAULT / "campaigns" / DRIVER.TAG)
    parser.add_argument("--prep-dir", type=Path, default=DRIVER.DEFAULT / "launch_prep" / DRIVER.TAG)
    parser.add_argument("--workers", type=int, default=15)
    parser.add_argument("--attempt-id", default="r123_centre_audit_20261004_01")
    parser.add_argument("--log-file", type=Path)
    parser.add_argument("--protocol", type=Path,
                        default=ROOT / "application/config/pricefm_stage_r123_resume_protocol_20261004.json")
    args = parser.parse_args()
    try:
        import json
        print(json.dumps(main(args), sort_keys=True))
    except Exception:
        traceback.print_exc(); sys.exit(1)
