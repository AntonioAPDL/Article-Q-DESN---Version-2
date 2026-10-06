#!/usr/bin/env python3
"""Resume saved Normal groups -> certified selection -> bounded tau -> nested AL."""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import hashlib
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from types import SimpleNamespace

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
            "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ[key] = "1"

import pandas as pd
import numpy as np
import pricefm_r123_recovery as REC
import pricefm_r123_runtime as RT
from pricefm_r123_certified_selection import certified_groups

ROOT = Path(__file__).resolve().parents[3]
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r123_certified_successor_20261005"
PARENT = "pricefm_stage_r123_bg_input_connectivity_20261003"
DIAG = "pricefm_stage_r123_stationarity_diagnosis_20261004"


def module(name, path):
    loader = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(loader); loader.loader.exec_module(value)
    return value


B = module("r123_successor_backend", Path(__file__).with_name("429_run_pricefm_stage_r122_long_memory.py"))
B.RT = RT; B.TAG = TAG
D = module("r123_successor_parent_audit", Path(__file__).with_name("437_run_pricefm_stage_r123_stationarity.py"))
ORIGINAL_COMMAND = B._command
ORIGINAL_QUANTILE_CONTRACT = B._quantile_contract
ORIGINAL_DESIGN = B._write_design
ORIGINAL_LADDER = B._al_ladder


def normal_outcome(path):
    path = Path(path)
    if not path.exists(): return None
    terminal = REC.read(path / "terminal.json")
    if terminal["status"] not in ("completed_recursive_normal_fit", "R123_SUCCESSOR_UNCERTIFIED", "R123_SUCCESSOR_NUMERICAL_FAILURE"):
        raise RuntimeError("unknown successor Normal outcome")
    contract = REC.read(terminal["contract_path"])
    if (terminal["contract_sha256"] != REC.digest(terminal["contract_path"])
            or terminal["posterior_target_sha256"] != contract["posterior_target_sha256"]
            or terminal["tag"] != TAG or contract["tag"] != TAG
            or Path(contract["output_dir"]).resolve() != path.resolve()
            or contract["convergence_mode"] != "full_variational"
            or terminal["test_opened"] is not False or terminal["official_validation_opened"] is not False):
        raise RuntimeError("successor Normal identity/target differs")
    for item in terminal["artifacts"]:
        if REC.digest(path / item["path"]) != item["sha256"]: raise RuntimeError("successor Normal artifact changed")
    certified = terminal["status"] == "completed_recursive_normal_fit"
    if certified != (terminal["converged"] is True and terminal["full_variational_certified"] is True):
        raise RuntimeError("ambiguous successor Normal certification")
    if certified and not terminal["precision_accuracy"]["accepted"]: raise RuntimeError("unreliable Gaussian conditional")
    return terminal


def normal_valid(path):
    value = normal_outcome(path)
    return value is not None and value["full_variational_certified"] is True


def quantile_contract(*args, **kwargs):
    value = ORIGINAL_QUANTILE_CONTRACT(*args, **kwargs)
    # The shared AL atom accepts this engine stage, unlike the old R123 wrapper.
    value.update(stage="R122_internal_selection", tag=TAG,
        scientific_stage="R123_certified_successor", atom_id=value["atom_id"].replace("r122_", "r123s_", 1))
    return value


def guarded_command(command, code, log, cpu=None):
    if "--config" in command and "420_fit_pricefm_stage_r121_quantile_atom.R" in " ".join(command):
        c = REC.read(command[command.index("--config") + 1]); output = Path(c["output_dir"])
        if output.exists(): raise RuntimeError("partial AL evidence preserved; refuses overwrite")
        if c["parent_type"] == "normal_rhs" and not normal_valid(c["parent_dir"]):
            raise RuntimeError("AL parent is not full-state certified")
        if c["parent_type"] == "quantile":
            parent = REC.read(Path(c["parent_dir"]) / "terminal.json")
            if not quantile_valid(c["parent_dir"], parent["posterior_target_sha256"]):
                raise RuntimeError("invalid inherited quantile initializer")
        ORIGINAL_COMMAND(command, code, log, cpu)
        REC.immutable(output / "successor_output_hashes.json", {
            p.name: REC.digest(p) for p in output.iterdir() if p.is_file()})
    else: ORIGINAL_COMMAND(command, code, log, cpu)


def quantile_valid(path, target):
    path = Path(path)
    if not path.exists(): return False
    value = REC.read(path / "terminal.json")
    if value["posterior_target_sha256"] != target or value["test_opened"] is not False or value["tag"] != TAG:
        raise RuntimeError("AL target/selection boundary differs")
    for name, wanted in REC.read(path / "successor_output_hashes.json").items():
        if REC.digest(path / name) != wanted: raise RuntimeError("AL output changed")
    return value["status"] == "completed_r121_quantile_atom"


def guarded_design(path, design, response, metadata):
    if path.exists() and not (path / "terminal.json").exists():
        raise RuntimeError("partial design preserved")
    ORIGINAL_DESIGN(path, design, response, metadata)
    terminal = REC.read(path / "terminal.json")
    if terminal["test_opened"] is not False:
        raise RuntimeError("quantile design test boundary differs")
    for name, array in (("X", design), ("y", response)):
        wanted = hashlib.sha256(np.ascontiguousarray(array, dtype="<f8").view(np.uint8)).hexdigest()
        if REC.digest(path / f"{name}.bin") != terminal[f"{name}_sha256"] or wanted != terminal[f"{name}_sha256"]:
            raise RuntimeError("saved quantile design differs from intended design")
    if REC.read(path / "design.json") != dict(n=len(response), p=design.shape[1], **metadata, test_opened=False):
        raise RuntimeError("quantile design metadata differs")


def guarded_ladder(prep, campaign, code, control, candidate, tau0, split, cpu):
    root = campaign / f"al_internal/{candidate}/split={split}"
    ledger = root / "successor_ladder_hashes.json"
    if (root / "metrics.json").exists():
        REC.verify_evidence(REC.read(ledger))
        value = REC.read(root / "metrics.json")
        if (value["candidate_id"] != candidate or value["tau0"] != tau0
                or value["split"] != split or value["test_opened"] is not False):
            raise RuntimeError("AL ladder score identity differs")
        return value
    result = ORIGINAL_LADDER(prep, campaign, code, control, candidate, tau0, split, cpu)
    REC.immutable(ledger, {"evidence_sha256": {str(path): REC.digest(path)
        for path in sorted(root.rglob("*")) if path.is_file() and path != ledger}})
    return result


B._normal_valid = normal_valid
B._command = guarded_command
B._quantile_contract = quantile_contract
B._quantile_output_valid = quantile_valid
B._write_design = guarded_design
B._al_ladder = guarded_ladder


def protocol_valid(p):
    for name in ("official_validation_authorized", "official_test_authorized", "screening_refits_authorized",
                 "registry_mutation_authorized", "article_mutation_authorized", "exal_authorized", "joint_authorized", "mcmc_authorized"):
        if p[name] is not False: raise ValueError("forbidden successor authorization")
    if (p["region"] != "BG" or p["fold"] != 1 or p["normal_max_iter"] != 2000 or
        p["center_checks"] != 63 or p["minimum_certified_candidates"] != 3 or
        p["tau_top_k"] != 10 or p["tau_multipliers"] != [.3, 3.] or p["al_top_k"] != 3 or
        p["posterior_paths"] != 500 or p["quantiles"] != list(RT.QUANTILES)):
        raise ValueError("successor scope or statistical budget differs")


def choose_complete(rows):
    groups = {}
    for row in rows:
        if (Path(row["output_dir"]) / "terminal.json").exists():
            groups.setdefault(row["candidate_id"], []).append(row)
    return [row for identifier in sorted(groups) if len(groups[identifier]) == 3
            and {int(row["split"]) for row in groups[identifier]} == {1, 2, 3} for row in groups[identifier]]


def normal_contract(row, args, control, protocol, checkpoint=None, offset=0, tau0=None, label="center"):
    original = REC.read(row["contract_path"])
    tau0 = float(original["tau0"] if tau0 is None else tau0)
    identifier = f"r123s_{row['candidate_id']}_s{row['split']}_t{tau0:.8e}"
    helper = ROOT / "application/R/pricefm_recursive_normal_fit.R"
    entry = ROOT / "application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R"
    sources = [helper, entry, Path(control["normal_runtime"]) / "R/priors_beta.R",
               Path(control["normal_runtime"]) / "R/qdesn_rhs_ns_prior.R"]
    terminal_hash = REC.digest(Path(original["stats_dir"]) / "terminal.json")
    return dict(original, tag=TAG, candidate_id=row["candidate_id"], split=int(row["split"]),
        fit_id=identifier, output_dir=str(args.campaign_root / f"rhs/{label}/fits" / identifier),
        tau0=tau0, helper_path=str(helper), convergence_mode="full_variational",
        max_iter=protocol["normal_max_iter"], min_iter=max(protocol["normal_min_iter"], offset + protocol["stability_window"]),
        stability_window=protocol["stability_window"], rhs_state_tol=protocol["rhs_state_tol"],
        covariance_tol=protocol["covariance_tol"], precision_accuracy_tol=protocol["precision_accuracy_tol"],
        objective_per_observation_tol=protocol["objective_per_observation_tol"],
        initial_fit_path=None if checkpoint is None else str(checkpoint),
        initial_fit_sha256=None if checkpoint is None else REC.digest(checkpoint),
        stats_terminal_sha256=terminal_hash, posterior_target_sha256=terminal_hash + f":tau0={tau0:.17g}",
        source_sha256={str(p): REC.digest(p) for p in sources})


def prepare(args):
    if args.prep_dir.name != TAG or args.campaign_root.name != TAG or args.parent_campaign.name != PARENT:
        raise ValueError("successor output or parent namespace differs")
    p = REC.read(args.protocol); protocol_valid(p)
    if not p["minimum_workers"] <= args.workers <= p["maximum_workers"]: raise ValueError("worker count outside 9..15")
    parent_args = SimpleNamespace(frozen_code_root=args.frozen_code_root, prep_dir=args.parent_prep, parent_campaign=args.parent_campaign)
    frozen, inherited, ledger, rows = D.verify_parent(parent_args)
    selected = choose_complete(rows)
    if len(selected) != p["center_checks"]: raise RuntimeError("complete saved parent inventory changed")
    diagnostic = REC.read(args.diagnostic_root / "freeze_receipt.json") if (args.diagnostic_root / "freeze_receipt.json").exists() else REC.read(args.diagnostic_root / "closeout/freeze_receipt.json")
    if diagnostic["status"] != "R123_FROZEN_DIAGNOSTIC_EVIDENCE_PASS": raise RuntimeError("diagnostic freeze required")
    handoff_path = args.diagnostic_root / "closeout/source_handoff_manifest.json"
    handoff = REC.read(handoff_path)
    if (handoff["head"] != diagnostic["head"] or diagnostic["jobs_complete"] != 10
            or diagnostic["certified"] != 6 or diagnostic["capped"] != 4
            or diagnostic["test_opened"] is not False):
        raise RuntimeError("diagnostic handoff identity differs")
    ledger["evidence_sha256"][str(handoff_path)] = REC.digest(handoff_path)
    for record in handoff["evidence"]:
        path = args.diagnostic_root / record["path"]
        if not path.resolve().is_relative_to(args.diagnostic_root.resolve()) or REC.digest(path) != record["sha256"]:
            raise RuntimeError("frozen diagnostic evidence changed")
        ledger["evidence_sha256"][str(path)] = record["sha256"]
    checkpoints = {}
    for job in REC.read(args.diagnostic_root / "manifest.json"):
        folder = Path(job["output_dir"]); terminal = REC.read(folder / "terminal.json")
        D.valid_diagnostic(folder, args.diagnostic_root / "contracts" / f"{job['fit_id']}.json")
        for name, wanted in terminal["artifact_sha256"].items():
            if REC.digest(folder / name) != wanted: raise RuntimeError("diagnostic checkpoint changed")
            ledger["evidence_sha256"][str(folder / name)] = wanted
        if terminal["converged"]:
            checkpoints[(job["candidate_id"], int(job["split"]))] = (folder / "fit.rds", int(terminal["iterations"]))
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("successor source must be committed and clean")
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if not branch.startswith("work/pricefm-"): raise RuntimeError("dedicated task branch required")
    source_map = {record["path"]: record for record in inherited["frozen_sources"]}
    files = list((ROOT / "application/scripts/pricefm").glob("*.py")) + list((ROOT / "application/scripts/pricefm").glob("*.R"))
    files += [ROOT / "application/R/pricefm_recursive_normal_fit.R", args.protocol]
    for path in files:
        source_map[str(path)] = dict(path=str(path), sha256=REC.digest(path), bytes=path.stat().st_size, mtime_ns=path.stat().st_mtime_ns)
    control = dict(inherited, stage="R123_certified_successor", tag=TAG, code_head=head, code_branch=branch,
        campaign_root=str(args.campaign_root), workers=args.workers,
        data_config=str(args.prep_dir / "data_configs/train_only.json"),
        frozen_sources=list(source_map.values()), rhs_max_iter=p["normal_max_iter"],
        rhs_score_max_origins_per_split=p["normal_origins_per_split"], posterior_paths=p["posterior_paths"],
        al_final_max_iter=p["al_max_iter"], al_companion_max_iter=p["al_companion_max_iter"])
    contracts = []
    for row in selected:
        terminal = REC.read(Path(row["output_dir"]) / "terminal.json")
        checkpoint, offset = checkpoints.get((row["candidate_id"], int(row["split"])),
                                             (Path(row["output_dir"]) / "fit.rds", int(terminal["iterations"])))
        if offset + p["stability_window"] > p["normal_max_iter"]: raise RuntimeError("saved checkpoint exceeds bounded continuation")
        contracts.append(normal_contract(row, args, control, p, checkpoint, offset))
    REC.immutable(args.prep_dir / "launch_control.json", control)
    REC.immutable(args.prep_dir / "protocol.json", p)
    REC.immutable(args.prep_dir / "target_contract.json", REC.read(args.parent_prep / "target_contract.json"))
    REC.immutable(args.prep_dir / "data_configs/train_only.json", {"scope": "training_only"})
    REC.immutable(args.prep_dir / "protected_parent.json", ledger)
    B._write_immutable_csv(pd.read_csv(args.parent_prep / "candidate_manifest.csv"), args.prep_dir / "candidate_manifest.csv")
    B._write_immutable_csv(pd.DataFrame(control["frozen_sources"]), args.prep_dir / "source_manifest.csv")
    REC.immutable(args.prep_dir / "center_jobs.json", contracts)
    for c in contracts: REC.immutable(args.prep_dir / "contracts/center" / f"{c['fit_id']}.json", c)
    REC.immutable(args.prep_dir / "identity.json", {name: REC.digest(args.prep_dir / name) for name in
        ("launch_control.json", "protocol.json", "target_contract.json", "data_configs/train_only.json", "protected_parent.json",
         "candidate_manifest.csv", "source_manifest.csv", "center_jobs.json")})
    return {"status": "R123_CERTIFIED_SUCCESSOR_PREPARED", "center_checks": len(contracts), "tau_maximum": 60,
            "primary_al_maximum": 63, "source_head": head, "test_opened": False}


def verify(args):
    for name, wanted in REC.read(args.prep_dir / "identity.json").items():
        if REC.digest(args.prep_dir / name) != wanted: raise RuntimeError("successor preparation changed")
    control = REC.read(args.prep_dir / "launch_control.json")
    if (Path(sys.executable).absolute() != Path(control["python_executable"]).absolute()
            or sys.prefix != control["python_prefix"]):
        raise RuntimeError("successor Python executable/prefix differs")
    D.frozen_module(args.frozen_code_root).verify_sources(control)
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip() != control["code_head"]:
        raise RuntimeError("successor checkout differs from frozen source")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("successor checkout is not clean")
    return control


def preflight(args, p):
    for attempt in range(1, p["resource_attempts"] + 1):
        usage = B._cpu_snapshot(p["cpu_audit_seconds"]); groups = {}
        for cpu, value in usage.items(): groups.setdefault(B._physical(cpu), []).append((cpu, value))
        allowed = os.sched_getaffinity(0)
        cpus = [min(cpu for cpu, _ in siblings if cpu in allowed) for siblings in groups.values()
                if any(cpu in allowed for cpu, _ in siblings) and max(v for _, v in siblings) <= p["maximum_physical_core_percent"]]
        memory = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
                      if line.startswith("MemAvailable:")) / 2**20
        disk = shutil.disk_usage(args.campaign_root.parent).free / 2**30
        if memory < p["minimum_memory_gib"] or disk < p["minimum_free_gib"]: raise RuntimeError("successor memory/disk reserve failed")
        if len(cpus) >= args.workers:
            value = dict(cpus=sorted(cpus)[:args.workers], available_idle_physical=len(cpus), workers=args.workers,
                available_memory_gib=memory, free_disk_gib=disk, at_epoch=time.time())
            REC.write(args.campaign_root / "resource_gate.json", value); return value["cpus"]
        if attempt == p["resource_attempts"]: raise RuntimeError("not enough idle physical cores")
        time.sleep(p["resource_backoff_seconds"])


def verified_score(path, contract_path):
    c = REC.read(contract_path); value = REC.read(path)
    if (value["fit_terminal_sha256"] != REC.digest(Path(c["output_dir"]) / "terminal.json")
            or value["contract_sha256"] != REC.digest(contract_path)
            or value["candidate_id"] != c["candidate_id"] or value["split"] != c["split"]
            or value["tau0"] != c["tau0"] or value["full_variational_certified"] is not True
            or value["test_opened"] is not False or value["official_validation_opened"] is not False
            or value["score_scope"] != "fold1_training_internal_validation_only"
            or value["forecast_operator"] != "recursive_normal_conditional_mean"
            or not all(math.isfinite(value[key]) and value[key] >= 0 for key in
                       ("AQL", "late_AQL", "median_MAE", "interval_80_width"))):
        raise RuntimeError("score identity, scope or finite metrics differ")
    return value


def score_cell(args):
    control = verify(args); c = REC.read(args.contract); output = Path(c["output_dir"])
    if not normal_valid(output): raise RuntimeError("cannot score an uncertified Normal fit")
    score_path = output / "validation_score.json"
    if score_path.exists():
        return verified_score(score_path, args.contract)
    candidate = pd.read_csv(args.prep_dir / "candidate_manifest.csv")
    row = candidate[candidate.candidate_id.eq(c["candidate_id"])]
    if len(row) != 1: raise RuntimeError("score candidate identity differs")
    spec = RT.normalize_spec(dict(json.loads(row.iloc[0].spec_json), seed=int(B.RESERVOIR_SEEDS[0])))
    arrays = B._selection_arrays(control, spec); item = RT.internal_splits(len(arrays.response))[c["split"] - 1]
    scaled, scaler = RT.standardize_from_training_origins(arrays, item["train"])
    score = RT.recursive_normal_score(scaled, spec, RT.load_normal_fit(output), item["validation"],
                                     maximum_origins=control["rhs_score_max_origins_per_split"])
    for name in ("AQL", "late_AQL", "median_MAE", "interval_80_width"): score[name] *= float(scaler["price_scale"])
    value = dict(score, candidate_id=c["candidate_id"], split=c["split"], tau0=c["tau0"],
        full_variational_certified=True, test_opened=False, official_validation_opened=False,
        fit_terminal_sha256=REC.digest(output / "terminal.json"), contract_sha256=REC.digest(args.contract),
        spec_sha256=str(row.iloc[0].structural_sha256), forecast_operator="recursive_normal_conditional_mean",
        score_scope="fold1_training_internal_validation_only")
    REC.immutable(score_path, value); return verified_score(score_path, args.contract)


def manifest_records(args, jobs, label):
    rows = []
    for c in jobs:
        path = args.prep_dir / f"contracts/{label}/{c['fit_id']}.json"
        if REC.read(path) != c: raise RuntimeError("Normal contract differs from immutable job")
        rows.append(dict(candidate_id=c["candidate_id"], split=c["split"], tau0=c["tau0"], fit_id=c["fit_id"],
                         contract_path=str(path), output_dir=c["output_dir"], stage_label=label))
    return rows


def run_normal_phase(args, jobs, label, cpus):
    control = verify(args); rows = manifest_records(args, jobs, label)
    B._write_immutable_csv(pd.DataFrame(rows), args.campaign_root / f"rhs/{label}/manifest.csv")
    tasks = [(r["fit_id"], [control["rscript"], str(ROOT / "application/scripts/pricefm/442_fit_pricefm_stage_r123_certified_normal.R"),
             "--contract", r["contract_path"]], args.campaign_root / f"logs/{label}_fit/{r['fit_id']}.log")
             for r in rows if normal_outcome(r["output_dir"]) is None]
    B._run_queue(tasks, cpus, ROOT, args.campaign_root / f"rhs/{label}/fit_progress.json", len(rows), fail_fast=True)
    groups = {}
    for r in rows: groups.setdefault((r["candidate_id"], r["tau0"]), []).append(r)
    complete = [r for group in groups.values() if len(group) == 3 and all(normal_valid(r["output_dir"]) for r in group) for r in group]
    scores = [(r["fit_id"], [sys.executable, __file__, "--mode", "score-cell", "--prep-dir", str(args.prep_dir),
               "--campaign-root", str(args.campaign_root), "--frozen-code-root", str(args.frozen_code_root),
               "--contract", r["contract_path"]], args.campaign_root / f"logs/{label}_score/{r['fit_id']}.log")
              for r in complete if not (Path(r["output_dir"]) / "validation_score.json").exists()]
    B._run_queue(scores, cpus, ROOT, args.campaign_root / f"rhs/{label}/score_progress.json", len(complete), fail_fast=True)
    cells = []
    for r in rows:
        if r in complete:
            value = verified_score(Path(r["output_dir"]) / "validation_score.json", r["contract_path"])
            cells.append(value)
        else: cells.append(dict(candidate_id=r["candidate_id"], split=r["split"], tau0=r["tau0"],
                                full_variational_certified=False, test_opened=False))
    REC.immutable(args.campaign_root / f"rhs/{label}/cell_metrics.json", cells)
    return rows, cells


def controller(args):
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    with (args.campaign_root / "controller.lock").open("a+") as own, \
         (args.parent_campaign / "controller.lock").open("r") as parent, \
         (args.parent_campaign / "recovery_controller.lock").open("r") as recovery:
        for handle in (own, parent, recovery): fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        control = verify(args); p = REC.read(args.prep_dir / "protocol.json")
        protocol_valid(p)
        if args.workers != control["workers"]: raise RuntimeError("worker count differs from frozen preparation")
        REC.verify_evidence(REC.read(args.prep_dir / "protected_parent.json"))
        if (args.campaign_root / "terminal.json").exists():
            REC.verify_evidence(REC.read(args.campaign_root / "completed_evidence.json"))
            return REC.read(args.campaign_root / "terminal.json")
        cpus = preflight(args, p)
        REC.write(args.campaign_root / "running.json", dict(pid=os.getpid(), cpus=cpus, source_head=control["code_head"],
            started_at_epoch=time.time(), test_opened=False))
        center_jobs = REC.read(args.prep_dir / "center_jobs.json")
        center_rows, center_cells = run_normal_phase(args, center_jobs, "center", cpus)
        ids = sorted({c["candidate_id"] for c in center_jobs})
        decision = certified_groups(center_cells, ids, p["minimum_certified_candidates"], p["tau_top_k"])
        REC.immutable(args.campaign_root / "rhs/center/selection.json", decision)
        if decision["status"] != "CERTIFIED_SELECTION_READY": raise RuntimeError("fewer than three certified scored candidates")
        centers = {c["candidate_id"]: c["tau0"] for c in center_jobs}
        by_identity = {(r["candidate_id"], int(r["split"])): r for r in center_rows}
        tau_jobs = [normal_contract(by_identity[(identifier, split)], args, control, p,
                    tau0=centers[identifier] * multiplier, label="pilot")
                    for identifier in decision["tau_candidate_ids"] for split in (1, 2, 3) for multiplier in p["tau_multipliers"]]
        for c in tau_jobs: REC.immutable(args.prep_dir / f"contracts/pilot/{c['fit_id']}.json", c)
        REC.immutable(args.campaign_root / "rhs/pilot/jobs.json", tau_jobs)
        cpus = preflight(args, p)
        tau_rows, tau_cells = run_normal_phase(args, tau_jobs, "pilot", cpus)
        final = certified_groups(center_cells + tau_cells, ids, p["minimum_certified_candidates"], p["tau_top_k"])
        if final["status"] != "CERTIFIED_SELECTION_READY": raise RuntimeError("certified selection unexpectedly incomplete")
        REC.immutable(args.campaign_root / "rhs/closeout/selection.json", final)
        B._write_immutable_csv(pd.DataFrame(center_rows + tau_rows), args.campaign_root / "rhs/manifest.csv")
        ranking = pd.DataFrame(final["ranking"])
        B._write_immutable_csv(ranking, args.campaign_root / "rhs/closeout/ranking.csv")
        chosen = B._unique_al_shortlist(ranking, p["al_top_k"])
        REC.immutable(args.campaign_root / "al_launch_authorization.json", dict(
            rule=final["rule"], selected=chosen.to_dict("records"), independent_al_authorized=True,
            test_opened=False, exal_authorized=False, joint_authorized=False, mcmc_authorized=False))
        cpus = preflight(args, p)
        # Existing nested AL adapter, fixed quantile order and score-blind acceptance.
        al = B._run_al(args.prep_dir, args.campaign_root, ROOT, cpus, chosen)
        verify(args); REC.verify_evidence(REC.read(args.prep_dir / "protected_parent.json"))
        result = dict(status="R123_CERTIFIED_INTERNAL_COMPLETE_TEST_BLOCKED", tag=TAG,
            center_checks=len(center_jobs), complete_center_candidates=len({r["candidate_id"] for r in decision["ranking"]}),
            tau_attempts=len(tau_jobs), complete_al_families=len(al), source_head=control["code_head"],
            parent_evidence_unchanged=True, test_opened=False, official_validation_opened=False,
            registry_mutated=False, article_mutated=False, integration_status="NOT_READY_FOR_INTEGRATION")
        REC.immutable(args.campaign_root / "terminal.json", result)
        REC.immutable(args.campaign_root / "completed_evidence.json", {"evidence_sha256": {
            str(path): REC.digest(path) for path in sorted(args.campaign_root.rglob("*")) if path.is_file()
            and path.name not in ("completed_evidence.json", "controller.lock", "controller.log")
            and not path.name.endswith(".tmp")}})
        return result


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("prepare", "controller", "score-cell"), default="prepare")
    p.add_argument("--prep-dir", type=Path, default=DATA / "launch_prep" / TAG)
    p.add_argument("--campaign-root", type=Path, default=DATA / "campaigns" / TAG)
    p.add_argument("--parent-prep", type=Path, default=DATA / "launch_prep" / PARENT)
    p.add_argument("--parent-campaign", type=Path, default=DATA / "campaigns" / PARENT)
    p.add_argument("--diagnostic-root", type=Path, default=DATA / "campaigns" / DIAG)
    p.add_argument("--frozen-code-root", type=Path, required=True)
    p.add_argument("--protocol", type=Path, default=ROOT / "application/config/pricefm_stage_r123_certified_successor_protocol_20261005.json")
    p.add_argument("--workers", type=int, default=15)
    p.add_argument("--contract", type=Path)
    return p


if __name__ == "__main__":
    args = parser().parse_args()
    try: print(json.dumps({"prepare": prepare, "controller": controller, "score-cell": score_cell}[args.mode](args), sort_keys=True))
    except Exception as error:
        if args.mode == "controller": REC.write(args.campaign_root / "blocked.json", dict(
            status="R123_CERTIFIED_SUCCESSOR_BLOCKED", error_type=type(error).__name__, error=str(error),
            at_epoch=time.time(), test_opened=False))
        raise
