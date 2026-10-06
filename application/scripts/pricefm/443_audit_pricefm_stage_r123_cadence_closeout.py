#!/usr/bin/env python3
"""Read-only parent audit and automatic evidence freeze; never fit or rescore."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace

for name in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
             "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS"):
    os.environ[name] = "1"

import numpy as np
import pandas as pd
import pricefm_r123_recovery as REC
import pricefm_r123_runtime as RT
from pricefm_internal_target_embargo import guarded_splits, regular_axis
from pricefm_r123_closeout_evidence import active_fit_processes, audit_ladder, authorized_ladders, finish_receipt

ROOT = Path(__file__).resolve().parents[3]
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r123_closeout_hardening_20261005"
PARENT = "pricefm_stage_r123_certified_successor_20261005"


def parent_module(args):
    path = args.parent_code / "application/scripts/pricefm/441_run_pricefm_stage_r123_certified_successor.py"
    spec = importlib.util.spec_from_file_location("r123_cadence_parent", path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def parent_args(args):
    return SimpleNamespace(prep_dir=args.parent_prep, campaign_root=args.parent_campaign,
        frozen_code_root=args.frozen_code_root)


def own_identity(args):
    if args.output.name != TAG or args.parent_campaign.name != PARENT:
        raise ValueError("audit output must be isolated from the parent")
    if args.output.resolve().is_relative_to(args.parent_campaign.resolve()):
        raise ValueError("audit output may not be inside the active parent")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("commit and freeze the audit source first")
    REC.immutable(args.output / "source_identity.json", dict(head=head,
        branch=subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip(),
        source=str(ROOT), scripts_sha256={str(p): REC.digest(p) for p in
            (Path(__file__), Path(__file__).with_name("pricefm_internal_target_embargo.py"),
             Path(__file__).with_name("pricefm_r123_closeout_evidence.py"))}))
    return head


def audit_arrays(arrays, frame, *, expected_step_minutes=15):
    """Prove target timestamps by matching every stored label to its source row."""
    axis = regular_axis(frame.index)
    if axis["sample_step_minutes"] != expected_step_minutes:
        raise RuntimeError("executed target cadence differs from the frozen 15-minute design")
    times = pd.DatetimeIndex(pd.to_datetime(arrays.anchors, utc=True)).as_unit("ns")
    positions = frame.index.get_indexer(times)
    if (positions < 0).any() or (positions + 96 > len(frame)).any():
        raise RuntimeError("window anchor cannot be matched to 96 source rows")
    rows = positions[:, None] + np.arange(96)[None, :]
    target = frame["BG-price"].to_numpy(dtype=np.float32)[rows].astype(float)
    if not np.array_equal(target, arrays.response):
        raise RuntimeError("executed labels differ from the claimed source timestamps")
    clean, boundaries = guarded_splits(times, RT.internal_splits(len(times)),
        sample_step=pd.Timedelta(axis["sample_step_ns"], unit="ns"))
    unchanged = all(np.array_equal(x["validation"], y["validation"])
        for x, y in zip(clean, RT.internal_splits(len(times))))
    if not unchanged:
        raise RuntimeError("fitted targets overlap internal validation; do not certify or silently rescore")
    return dict(axis=axis, boundaries=boundaries, targets_exactly_match_source=True,
        horizon_steps=96, forecast_duration_hours=24, first_target_is_anchor=True,
        last_target_offset_hours=23.75, excluded_origins=0, no_rescoring_needed=True,
        training_and_validation_indices_unchanged=True, priors_unchanged=True,
        interpretation_correction="96 quarter-hourly steps, not 96 hours", test_opened=False)


def cadence_audit(args, m, control):
    candidates = pd.read_csv(args.parent_prep / "candidate_manifest.csv")
    spec = RT.normalize_spec(dict(json.loads(candidates.iloc[0].spec_json), seed=int(m.B.RESERVOIR_SEEDS[0])))
    arrays = m.B._selection_arrays(control, spec)
    processed = Path(control["runtime_processed"])
    axis_path = processed / "splits_scaled/fold_1/train_scaled.parquet"
    frame = pd.read_parquet(axis_path, columns=["BG-price"])
    value = audit_arrays(arrays, frame)
    window = processed / "windows/fold_1/region=BG/train_L3120_H96_contained_half_open.npz"
    value.update(parent_source_head=control["code_head"], parent_tag=PARENT,
        evidence_sha256={str(p): REC.digest(p) for p in
            (axis_path, window, window.with_suffix(".manifest.json"), args.parent_prep / "identity.json")})
    REC.immutable(args.output / "cadence_audit.json", value)
    return value


def snapshot(args):
    root = args.parent_campaign
    primary = list((root / "al_internal").glob("*/split=*/quantiles/al/tau=*/terminal.json"))
    companions = list((root / "al_internal").glob("*/split=*/companions/cap=*/tau=*/terminal.json"))
    progress = REC.read(root / "al_internal/progress.json") if (root / "al_internal/progress.json").exists() else {}
    eligible = 0; converged = 0; capped = 0; malformed = 0
    for path in primary:
        try:
            value = REC.read(path)
            eligible += int(value["external_gate_passed"] is True)
            converged += int(value["formal_converged"] is True)
            capped += int(value["formal_converged"] is False)
        except (OSError, ValueError, KeyError):
            malformed += 1
    if len(primary) > 63: raise RuntimeError("unexpected primary AL inventory")
    return dict(pid=os.getpid(), at_epoch=time.time(), primary_al_atoms_complete=len(primary),
        primary_al_atoms_maximum=63, primary_al_atoms_not_complete=63 - len(primary),
        primary_al_atoms_raw_eligible=eligible, primary_al_atoms_formal_converged=converged,
        primary_al_atoms_not_formal_converged=capped, primary_al_atoms_malformed=malformed,
        live_counts_contract_certified=False,
        companion_al_atoms_complete=len(companions), ladder_progress=progress,
        parent_terminal_present=(root / "terminal.json").exists(),
        parent_block_present=(root / "blocked.json").exists(), scientific_models_launched_by_observer=0)


def freeze_parent(args, m, control):
    root = args.parent_campaign
    # The parent holds this lock throughout computation. Read-only access waits
    # for controller exit before collecting the final scientific evidence.
    with (root / "controller.lock").open("r") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if active_fit_processes(root, args.parent_prep):
            raise BlockingIOError("parent numerical writers remain active after controller exit")
        own_identity(args)
        m.verify(parent_args(args))
        REC.verify_evidence(REC.read(args.output / "cadence_audit.json"))
        if (root / "completed_evidence.json").exists():
            REC.verify_evidence(REC.read(root / "completed_evidence.json"))
        rows = REC.rows(root / "rhs/manifest.csv")
        groups = {}
        certified = 0; scored = set()
        for row in rows:
            valid = m.normal_valid(row["output_dir"])
            certified += int(valid)
            group = groups.setdefault((row["candidate_id"], float(row["tau0"])), {})
            split = int(row["split"])
            if split not in (1, 2, 3) or split in group:
                raise RuntimeError("duplicated or invalid Normal split")
            group[split] = valid
            score = Path(row["output_dir"]) / "validation_score.json"
            if valid and score.exists():
                m.verified_score(score, row["contract_path"])
                scored.add((row["candidate_id"], float(row["tau0"]), int(row["split"])))
        complete_groups = sum(set(group) == {1, 2, 3} and all(group.values()) for group in groups.values())
        expected_ladders = authorized_ladders(root)
        ladder_metrics = []
        ladder_keys = set()
        for path in sorted((root / "al_internal").glob("*/split=*/metrics.json")):
            REC.verify_evidence(REC.read(path.parent / "successor_ladder_hashes.json"))
            value = audit_ladder(args, m, control, path, expected_ladders, rows)
            ladder_keys.add((value["candidate_id"], value["split"]))
            ladder_metrics.append(value)
        state = snapshot(args)
        done = REC.read(root / "terminal.json") if state["parent_terminal_present"] else None
        expected = "R123_CERTIFIED_INTERNAL_COMPLETE_TEST_BLOCKED"
        success = done is not None and done["status"] == expected and not state["parent_block_present"]
        if success and (complete_groups != 37 or ladder_keys != set(expected_ladders)
                or len(ladder_metrics) != 9 or state["primary_al_atoms_malformed"]
                or not all(x["eligible"] for x in ladder_metrics) or state["primary_al_atoms_complete"] != 63
                or state["ladder_progress"].get("complete") != 9
                or state["ladder_progress"].get("failed") != 0
                or any((cid, tau, split) not in scored for (cid, tau), group in groups.items()
                    if set(group) == {1, 2, 3} and all(group.values()) for split in (1, 2, 3))):
            raise RuntimeError("parent completion contradicts the independent evidence inventory")
        result = dict(status="R123_CADENCE_VERIFIED_PARENT_COMPLETE" if success else "R123_PARENT_INCOMPLETE_FROZEN",
            parent_source_head=control["code_head"], certified_normal_fits=certified,
            complete_normal_candidate_scale_groups=complete_groups, al_ladders=ladder_metrics,
            parent_terminal=done, parent_block=REC.read(root / "blocked.json") if state["parent_block_present"] else None,
            **state, no_fits_repeated=True, no_scores_regenerated=True, test_opened=False,
            parent_completion_ledger_present=(root / "completed_evidence.json").exists(),
            al_full_variational_stationarity_certified=False,
            registry_mutated=False, article_mutated=False, integration_status="NOT_READY_FOR_INTEGRATION")
        ledger = {str(p): REC.digest(p) for p in root.rglob("*") if p.is_file()
            and p.name not in ("controller.lock", "controller.log")}
        REC.immutable(args.output / "parent_evidence.json", dict(evidence_sha256=ledger))
        REC.immutable(args.output / "terminal.json", result)
        return finish_receipt(args.output)


def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / "observer.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        own_identity(args)
        if (args.output / "terminal.json").exists():
            return finish_receipt(args.output)
        m = parent_module(args); control = m.verify(parent_args(args))
        if args.mode == "monitor":
            cpus = m.preflight(SimpleNamespace(workers=1, campaign_root=args.output),
                REC.read(args.parent_prep / "protocol.json"))
            os.sched_setaffinity(0, set(cpus))
        evidence = cadence_audit(args, m, control)
        if args.mode == "audit": return evidence
        while True:
            state = snapshot(args)
            REC.write(args.output / "live.json", state)
            if state["parent_terminal_present"] or state["parent_block_present"]:
                try: return freeze_parent(args, m, control)
                except BlockingIOError: pass
            if args.mode == "closeout": raise RuntimeError("parent still active; no evidence freeze attempted")
            time.sleep(args.poll_seconds)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("audit", "monitor", "closeout"), default="audit")
    p.add_argument("--output", type=Path, default=DATA / "campaigns" / TAG)
    p.add_argument("--parent-prep", type=Path, default=DATA / "launch_prep" / PARENT)
    p.add_argument("--parent-campaign", type=Path, default=DATA / "campaigns" / PARENT)
    p.add_argument("--parent-code", type=Path, required=True)
    p.add_argument("--frozen-code-root", type=Path, required=True)
    p.add_argument("--poll-seconds", type=int, default=60)
    return p


if __name__ == "__main__":
    args = parser().parse_args()
    if args.poll_seconds < 30: raise ValueError("minimum monitoring interval is 30 seconds")
    try: print(json.dumps(run(args)))
    except Exception as e:
        REC.write(args.output / "observer_blocked.json", dict(error=str(e), type=type(e).__name__,
            parent_jobs_changed=False, test_opened=False))
        raise
