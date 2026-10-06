#!/usr/bin/env python3
"""Frozen-fit, training-internal PriceFM replay; fitting and publication denied."""
from __future__ import annotations

import argparse
import csv
import fcntl
import importlib.util
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace

THREADS = ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS", "VECLIB_MAXIMUM_THREADS")
for name in THREADS:
    os.environ[name] = "1"

import numpy as np
import pandas as pd

from pricefm_r124_covariance import GaussianSampler, POLICY, projected_audit

ROOT = Path(__file__).resolve().parents[3]
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TAG = "pricefm_stage_r124_covariance_preserving_replay_20261006"
PARENT = "pricefm_stage_r123_certified_successor_20261005"
OWNER_HEAD = "40d42d15a477c2f9d50dbc69b4eb9885da91ec29"
PROTOCOL = ROOT / "application/config/pricefm_stage_r124_covariance_replay_protocol_20261006.json"
OPERATORS = ("mean_feature", "path_specific", "normal_driver")
OWNER_FIELDS = ("owner_root", "frozen_code_root", "parent_campaign", "parent_prep", "output", "prep")


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")
    temporary.replace(path)


def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError(f"immutable replay metadata differs: {path}")
    else:
        write(path, value)


def git(*args, root=ROOT):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def own_identity():
    branch = git("branch", "--show-current")
    if not branch.startswith("work/pricefm-r124-") or git("status", "--porcelain"):
        raise RuntimeError("clean committed dedicated R124 branch required")
    return dict(head=git("rev-parse", "HEAD"), branch=branch)


def protocol_valid(value):
    expected = read(PROTOCOL)
    if value != expected or value["sampler"] != POLICY:
        raise ValueError("frozen R124 protocol differs")
    if any(value[name] is not False for name in ("fitting_authorized", "screening_authorized",
            "official_validation_authorized", "official_test_authorized",
            "article_mutation_authorized", "registry_mutation_authorized", "model_selection_rule_changed")):
        raise ValueError("R124 scope firewall violation")
    return value


def owner(args):
    if (args.parent_campaign.resolve() != DATA / "campaigns" / PARENT
            or args.parent_prep.resolve() != DATA / "launch_prep" / PARENT
            or args.output.resolve() != DATA / "campaigns" / TAG
            or args.prep.resolve() != DATA / "launch_prep" / TAG):
        raise ValueError("assigned PriceFM namespace differs")
    scripts = args.owner_root / "application/scripts/pricefm"
    sys.path.insert(0, str(scripts))
    loader = importlib.util.spec_from_file_location("r124_frozen_owner",
        scripts / "441_run_pricefm_stage_r123_certified_successor.py")
    value = importlib.util.module_from_spec(loader); loader.loader.exec_module(value)
    control = value.verify(SimpleNamespace(prep_dir=args.parent_prep,
        campaign_root=args.parent_campaign, frozen_code_root=args.frozen_code_root))
    if control["code_head"] != OWNER_HEAD:
        raise RuntimeError("scientific owner source differs")
    for module in (value.REC, value.RT, value.RT.BASE, value.RT.SUPPORT, value.B, value.D):
        if not Path(module.__file__).resolve().is_relative_to(args.owner_root.resolve()):
            raise RuntimeError("a frozen helper was imported from a different checkout")
    def forbidden(*a, **k):
        raise RuntimeError("model fitting or parent campaign mutation forbidden in R124")
    for name in ("_command", "_run_al", "_al_ladder", "_write_design", "_run_rhs"):
        if hasattr(value.B, name): setattr(value.B, name, forbidden)
    return value, control


def release_valid(path, source):
    value = read(path)
    if (value.get("source_head") != source["head"] or value.get("failures") != 0
            or value.get("errors") != 0 or value.get("python_tests", 0) < 357
            or value.get("skipped", 0) != 0 or value.get("r_suites") != 4
            or value.get("r124_tests_included") is not True):
        raise RuntimeError("matching successful Python/R release receipt required")
    if (len(value.get("outcomes", [])) != 5 or any(row["exit_code"] for row in value["outcomes"])
            or "application/tests/test_pricefm_stage_r124_covariance_replay.py" not in value["outcomes"][0]["command"]
            or not value.get("evidence_sha256")):
        raise RuntimeError("complete release commands and evidence required")
    for name, expected in value["evidence_sha256"].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != expected:
            raise RuntimeError("release evidence changed")
    return value


def parent_freeze(args, m):
    from pricefm_r123_closeout_evidence import active_fit_processes
    terminal = read(args.parent_campaign / "terminal.json")
    if (terminal["status"] != "R123_CERTIFIED_INTERNAL_COMPLETE_TEST_BLOCKED"
            or terminal["source_head"] != OWNER_HEAD or terminal["complete_al_families"] != 3
            or any(terminal[k] is not False for k in
                ("test_opened", "official_validation_opened", "registry_mutated", "article_mutated"))
            or (args.parent_campaign / "blocked.json").exists()
            or active_fit_processes(args.parent_campaign, args.parent_prep)):
        raise RuntimeError("completed untouched R123 campaign required")
    ledgers = {}
    for root in (args.parent_campaign,
            DATA / "campaigns/pricefm_stage_r123_closeout_hardening_20261005",
            DATA / "campaigns/pricefm_stage_r123_dependency_resume_20261006"):
        path = root / "completed_evidence.json"
        m.REC.verify_evidence(read(path)); ledgers[str(path)] = m.REC.digest(path)
        if (root / "parent_evidence.json").exists():
            m.REC.verify_evidence(read(root / "parent_evidence.json"))
    return ledgers


def build_jobs(args, m, control):
    from pricefm_r123_closeout_evidence import authorized_ladders, verified_atom
    expected = authorized_ladders(args.parent_campaign)
    rows = m.REC.rows(args.parent_campaign / "rhs/manifest.csv")
    candidates = {r["candidate_id"]: json.loads(r["spec_json"])
                  for r in m.REC.rows(args.parent_prep / "candidate_manifest.csv")}
    jobs = []
    for (candidate, split), tau0 in sorted(expected.items()):
        root = args.parent_campaign / f"al_internal/{candidate}/split={split}"
        match = [r for r in rows if r["candidate_id"] == candidate and int(r["split"]) == split
                 and math.isclose(float(r["tau0"]), tau0, rel_tol=1e-10, abs_tol=0)]
        if len(match) != 1 or not m.normal_valid(match[0]["output_dir"]):
            raise RuntimeError("unique certified Normal parent required")
        normal = Path(match[0]["output_dir"])
        design = root / "design"; meta = read(design / "design.json"); n, p = meta["n"], meta["p"]
        m.REC.verify_evidence(read(root / "successor_ladder_hashes.json"))
        sample = np.memmap(design / "X.bin", dtype="<f8", mode="r", shape=(n, p))
        readouts = np.array(sample[np.unique(np.linspace(0, n - 1, 9, dtype=int))]); del sample
        quantile_dirs = {}; labels = []; covariance_checks = []
        fits = [("normal", normal)]
        for tau in m.RT.QUANTILES:
            diagnostics = verified_atom(SimpleNamespace(parent_prep=args.parent_prep), m, control,
                root, candidate, split, tau0, tau, normal)
            if not diagnostics["external_gate_passed"]:
                raise RuntimeError("R124 requires the frozen raw-eligible AL surface")
            fit = root / f"quantiles/al/tau={tau:.2f}"
            quantile_dirs[str(tau)] = str(fit); fits.append((f"q{tau:.2f}", fit))
            terminal = read(fit / "terminal.json")
            labels.append(dict(tau=tau, formal_converged=terminal["formal_converged"],
                               iterations=terminal["iterations"], external_gate_passed=True))
        evidence = {}
        for label, fit in fits:
            covariance = np.fromfile(fit / "beta_cov.bin", dtype="<f8").reshape(p, p)
            residual = m.RT.load_normal_fit(fit)["omega_mean"] if label == "normal" else None
            covariance_checks.append(dict(label=label, **projected_audit(covariance, readouts, residual)))
            for name in ("terminal.json", "beta_mean.bin", "beta_cov.bin"):
                evidence[str(fit / name)] = m.REC.digest(fit / name)
        identifier = f"{candidate}_s{split}"
        job = dict(tag=TAG, job_id=identifier, candidate_id=candidate, split=split, tau0=tau0,
            spec=candidates[candidate], normal_dir=str(normal), quantile_dirs=quantile_dirs,
            parent_cell=str(root), output_dir=str(args.output / "cells" / identifier),
            input_sha256=evidence, covariance_checks=covariance_checks, fit_labels=labels,
            seed=int(m.B.RESERVOIR_SEEDS[0] + split), posterior_paths=500,
            source_reservoir_seed=int(m.B.RESERVOIR_SEEDS[0]), sampler=POLICY,
            official_test_opened=False, official_validation_opened=False, fitting_authorized=False)
        jobs.append(job)
    validate_jobs(jobs)
    return jobs


def validate_jobs(jobs):
    if len(jobs) != 9 or len({j["job_id"] for j in jobs}) != 9:
        raise ValueError("exact nine unique replay cells required")
    grouped = {}
    for j in jobs:
        grouped.setdefault(j["candidate_id"], []).append(j)
        if (j["tag"] != TAG or j["posterior_paths"] != 500 or j["sampler"] != POLICY
                or any(j[k] is not False for k in ("official_test_opened",
                    "official_validation_opened", "fitting_authorized"))):
            raise ValueError("replay job scope differs")
    if len(grouped) != 3 or any({j["split"] for j in group} != {1, 2, 3}
            or len({j["tau0"] for j in group}) != 1 for group in grouped.values()):
        raise ValueError("complete frozen candidate/scale groups required")


def prepare(args):
    source = own_identity(); protocol_valid(read(PROTOCOL)); release_valid(args.validation_receipt, source)
    m, control = owner(args); ledgers = parent_freeze(args, m)
    jobs = build_jobs(args, m, control)
    sources = [Path(__file__), Path(__file__).with_name("pricefm_r124_covariance.py"),
               Path(__file__).with_name("pricefm_r124_report.py"),
               Path(__file__).with_name("pricefm_r124_release.py"), PROTOCOL]
    configurations = {}
    for job in jobs:
        path = args.prep / "jobs" / f"{job['job_id']}.json"
        immutable(path, job); configurations[str(path)] = m.REC.digest(path)
    value = dict(tag=TAG, source=source, owner_head=OWNER_HEAD,
        source_sha256={str(p): m.REC.digest(p) for p in sources}, parent_ledgers=ledgers,
        parent_prep_sha256=m.REC.digest(args.parent_prep / "identity.json"),
        protocol=read(PROTOCOL), configurations=configurations,
        validation_receipt=str(args.validation_receipt), validation_sha256=m.REC.digest(args.validation_receipt),
        args={name: str(getattr(args, name)) for name in OWNER_FIELDS},
        official_test_opened=False, official_validation_opened=False, fit_count=0)
    immutable(args.prep / "preparation.json", value)
    return dict(status="R124_PREPARED", panels=9, reused_quantile_fits=63, covariance_checks=72,
                model_refits=0, source=source)


def verify_preparation(args, m):
    value = read(args.prep / "preparation.json")
    if (value["source"] != own_identity() or value["args"] !=
            {name: str(getattr(args, name)) for name in OWNER_FIELDS}):
        raise RuntimeError("prepared source or namespace differs")
    for key in ("source_sha256", "parent_ledgers", "configurations"):
        m.REC.verify_evidence({"evidence_sha256": value[key]})
    if (m.REC.digest(args.parent_prep / "identity.json") != value["parent_prep_sha256"]
            or m.REC.digest(value["validation_receipt"]) != value["validation_sha256"]):
        raise RuntimeError("preparation or validation evidence changed")
    release_valid(value["validation_receipt"], value["source"])
    protocol_valid(value["protocol"])
    jobs = [read(p) for p in value["configurations"]]; validate_jobs(jobs)
    return value, jobs


def verified_cell(path, job, digest, *, smoke=False):
    path = Path(path)
    if not path.exists(): return None
    if not (path / "completed_evidence.json").exists():
        raise RuntimeError("partial replay output preserved; refuses overwrite")
    ledger = read(path / "completed_evidence.json")
    if set(ledger["artifact_sha256"]) != {"predictions.npz", "metrics.json", "forecast_contract.json", "terminal.json"}:
        raise RuntimeError("incomplete replay artifact ledger")
    for name, wanted in ledger["artifact_sha256"].items():
        if Path(name).name != name or digest(path / name) != wanted:
            raise RuntimeError("replay output hash changed")
    value = read(path / "terminal.json")
    origins = 2 if smoke else {1: 125, 2: 135, 3: 174}[job["split"]]
    if (value["job_id"] != job["job_id"] or value["input_sha256"] != job["input_sha256"]
            or value["sampler"] != POLICY or value["posterior_paths"] != 500
            or value["status"] != ("R124_SMOKE_COMPLETE" if smoke else "R124_FORECAST_CELL_COMPLETE")
            or value["model_refits"] != 0 or value["scored_origins"] != origins
            or value["horizon_steps"] != 96 or value["step_minutes"] != 15
            or value["units"] != "outer_fold1_training_scaled_price"
            or value["fit_labels"] != job["fit_labels"]
            or value["official_test_opened"] is not False
            or value["official_validation_opened"] is not False):
        raise RuntimeError("replay output identity differs")
    return value


def forecast(m, control, job, maximum_origins=None, observe=lambda value: None):
    spec = m.RT.normalize_spec(dict(job["spec"], seed=job["source_reservoir_seed"]))
    arrays = m.B._selection_arrays(control, spec)
    item = m.RT.internal_splits(len(arrays.response))[job["split"] - 1]
    scaled, scaler = m.RT.standardize_from_training_origins(arrays, item["train"])
    indices = item["validation"] if maximum_origins is None else item["validation"][:maximum_origins]
    selected = m.RT.subset_arrays(scaled, indices)
    normal = m.RT.load_normal_fit(Path(job["normal_dir"]))
    quantiles = {float(q): m.RT.load_quantile_fit(Path(p)) for q, p in job["quantile_dirs"].items()}
    sampler = GaussianSampler(); engine = m.RT.BASE
    original_draw, original_initialize = engine._draw_gaussian, engine.initialize_states
    completed = 0
    def tracked_initialize(*a, **k):
        nonlocal completed
        observe(dict(origins_finished=completed, origins_total=len(indices),
                     next_origin=completed, at_epoch=time.time()))
        result = original_initialize(*a, **k); completed += 1
        return result
    engine._draw_gaussian = sampler; engine.initialize_states = tracked_initialize
    try:
        values = m.RT.recursive_quantile_forecast(selected, spec, normal, quantiles, 500, job["seed"])
    finally:
        engine._draw_gaussian = original_draw; engine.initialize_states = original_initialize
    converted = {name: values[name] * float(scaler["price_scale"]) + float(scaler["price_mean"])
                 for name in ("truth", *OPERATORS)}
    if len(sampler.audit) != 8 or any(not np.isfinite(v).all() for v in converted.values()):
        raise RuntimeError("incomplete or nonfinite eight-posterior replay")
    observe(dict(origins_finished=len(indices), origins_total=len(indices), at_epoch=time.time()))
    metrics = {name: m.RT.prediction_metrics(converted["truth"], converted[name]) for name in OPERATORS}
    converted.update(origin_indices=np.asarray(indices, dtype=int),
        origin_utc=np.asarray([str(x) for x in selected.anchors], dtype="U40"))
    metadata = dict(scaler=scaler, units="outer_fold1_training_scaled_price",
        training_origins=len(item["train"]), scored_origins=len(indices), horizon_steps=96,
        step_minutes=15, forecast_duration_hours=24, posterior_paths=500,
        sampler_audit=sampler.audit, score_scope="fold1_training_internal_validation_only",
        teacher_forcing_between_origins=True, future_target_lags="generated_normal_paths_only",
        future_exogenous_convention="frozen_retrospective_exogenous_channels",
        full_variational_stationarity_certified=False, fit_labels=job["fit_labels"])
    return converted, metrics, metadata


def cell(args, *, smoke=False):
    m, control = owner(args); prep, jobs = verify_preparation(args, m)
    job = read(args.config)
    if str(args.config) not in prep["configurations"] or job not in jobs:
        raise RuntimeError("cell outside immutable manifest")
    m.REC.verify_evidence({"evidence_sha256": job["input_sha256"]})
    output = args.output / "smoke" / job["job_id"] if smoke else Path(job["output_dir"])
    output.parent.mkdir(parents=True, exist_ok=True)
    with (args.output / f"{job['job_id']}_{'smoke' if smoke else 'cell'}.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if output.exists():
            return verified_cell(output, job, m.REC.digest, smoke=smoke)
        temporary = Path(tempfile.mkdtemp(prefix=job["job_id"] + ".tmp.", dir=output.parent))
        heartbeat = args.output / "heartbeats" / f"{job['job_id']}{'_smoke' if smoke else ''}.json"
        started = time.time()
        values, metrics, metadata = forecast(m, control, job, 2 if smoke else None,
            lambda v: write(heartbeat, dict(v, job_id=job["job_id"], pid=os.getpid(),
                affinity=sorted(os.sched_getaffinity(0)), single_thread_controls={k: os.environ[k] for k in THREADS})))
        np.savez_compressed(temporary / "predictions.npz", **values)
        write(temporary / "metrics.json", metrics)
        write(temporary / "forecast_contract.json", metadata)
        terminal = dict(status="R124_SMOKE_COMPLETE" if smoke else "R124_FORECAST_CELL_COMPLETE",
            job_id=job["job_id"], candidate_id=job["candidate_id"], split=job["split"], tau0=job["tau0"],
            sampler=POLICY, posterior_paths=500, input_sha256=job["input_sha256"],
            model_refits=0, official_test_opened=False, official_validation_opened=False,
            selection_authorized=not smoke, elapsed_seconds=time.time() - started,
            source=prep["source"], **metadata)
        write(temporary / "terminal.json", terminal)
        write(temporary / "completed_evidence.json", {"artifact_sha256":
            {p.name: m.REC.digest(p) for p in temporary.iterdir() if p.is_file()}})
        if output.exists(): raise RuntimeError("concurrent destination appeared; partial evidence preserved")
        temporary.rename(output)
        m.REC.verify_evidence({"evidence_sha256": job["input_sha256"]})
        return terminal


def reserves(args):
    memory = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
                  if line.startswith("MemAvailable:")) / 2**20
    disk = shutil.disk_usage(args.output.parent).free / 2**30
    if min(memory, disk) < 200: raise RuntimeError("200-GiB memory/disk reserve failed")
    return dict(available_memory_gib=memory, free_disk_gib=disk)


def choose_replay_cpus(occupied, allowed, physical, busy, foreign, ceiling):
    if not 1 <= ceiling <= 9 or not set(occupied) <= set(allowed) or len(occupied) > ceiling:
        raise RuntimeError("active workers exceed the permitted resource budget")
    chosen = sorted(occupied); used = {physical[c] for c in chosen}
    if len(used) != len(chosen) or used & set(foreign):
        raise RuntimeError("active workers share a physical core or another pinned task")
    for cpu in sorted(allowed):
        group = physical[cpu]
        if len(chosen) == ceiling: break
        if group in used or group in foreign or busy.get(group, 100) > 20: continue
        chosen.append(cpu); used.add(group)
    if not chosen: raise RuntimeError("no healthy unused physical core available")
    return sorted(chosen)


def cpu_pool(args, m, active):
    from pricefm_r123_dependency_queue import process_identity
    usage = m.B._cpu_snapshot(10); allowed = os.sched_getaffinity(0)
    physical = {cpu: m.B._physical(cpu) for cpu in set(allowed) | set(usage)}
    busy = {group: max(usage[cpu] for cpu in usage if physical[cpu] == group) for group in set(physical.values())}
    ours = {r["pid"] for r in active.values()}; foreign = set()
    for folder in Path("/proc").iterdir():
        if not folder.name.isdigit() or int(folder.name) in ours or int(folder.name) == os.getpid(): continue
        identity = process_identity(int(folder.name))
        if not identity or identity["state"] == "Z": continue
        name = Path(identity["argv"][0]).name
        if name not in ("R", "Rscript") and not name.startswith("python"): continue
        try: cpus = os.sched_getaffinity(int(folder.name))
        except ProcessLookupError: continue
        if len(cpus) == 1: foreign.add(m.B._physical(next(iter(cpus))))
    ceiling = min(args.workers, 9)
    chosen = choose_replay_cpus({r["cpu"] for r in active.values()}, allowed,
        physical, busy, foreign, ceiling)
    return chosen, dict(reserves(args), cpus=chosen, worker_ceiling=args.workers,
        concurrent_panel_limit=ceiling, at_epoch=time.time())


def assert_no_orphan_workers(records):
    from pricefm_r123_dependency_queue import process_identity, same_process
    for folder in Path("/proc").iterdir():
        if not folder.name.isdigit(): continue
        identity = process_identity(int(folder.name))
        if not identity or identity["state"] == "Z": continue
        argv = identity["argv"]
        if str(Path(__file__)) not in argv or "cell" not in argv: continue
        if not any(same_process(record, identity) for record in records):
            raise RuntimeError("unrecorded replay worker exists; preserve it and refuse duplicate launch")


def smoke_valid(args, m, jobs, prep):
    job = next(j for j in jobs if j["candidate_id"] == "r123_3e15bdc342f556c1" and j["split"] == 3)
    value = verified_cell(args.output / "smoke" / job["job_id"], job, m.REC.digest, smoke=True)
    if value is None or value["source"] != prep["source"] or len(value["sampler_audit"]) != 8:
        raise RuntimeError("matching verified two-origin B-split-3 smoke required before launch")
    return value


def controller(args):
    from pricefm_r123_dependency_queue import process_identity, same_process
    if not 1 <= args.workers <= 15: raise ValueError("worker budget outside 1..15")
    m, control = owner(args); prep, jobs = verify_preparation(args, m)
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / "controller.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (args.output / "terminal.json").exists(): return closeout(args)
        parent_freeze(args, m)
        smoke_valid(args, m, jobs, prep)
        done = {}; active = {}; handles = {}
        for job in jobs:
            result = verified_cell(job["output_dir"], job, m.REC.digest)
            receipt = args.output / "launched" / f"{job['job_id']}.json"
            if result is not None: done[job["job_id"]] = result
            elif receipt.exists():
                record = read(receipt)
                config = args.prep / "jobs" / f"{job['job_id']}.json"
                if record["config"] != str(config) or record["config_sha256"] != m.REC.digest(config):
                    raise RuntimeError("recorded replay worker contract differs")
                if not same_process(record, process_identity(record["pid"])):
                    raise RuntimeError("unfinished replay worker exited; evidence preserved, no repeat")
                active[job["job_id"]] = record
        assert_no_orphan_workers(active.values())
        cpus, resources = cpu_pool(args, m, active)
        write(args.output / "resource_gate.json", resources)
        write(args.output / "running.json", dict(pid=os.getpid(), source=prep["source"], cpus=cpus,
            started_at_epoch=time.time(), model_refits=0))
        while len(done) != len(jobs):
            free = sorted(set(cpus) - {r["cpu"] for r in active.values()})
            for job in jobs:
                key = job["job_id"]
                if not free: break
                if key in done or key in active: continue
                reserves(args); cpu = free.pop(0)
                config = args.prep / "jobs" / f"{key}.json"
                command = ["taskset", "-c", str(cpu), sys.executable, "-B", str(Path(__file__)),
                           "--mode", "cell", "--config", str(config)]
                for name in OWNER_FIELDS: command += ["--" + name.replace("_", "-"), str(getattr(args, name))]
                log = args.output / "logs" / f"{key}.log"; log.parent.mkdir(parents=True, exist_ok=True)
                handle = log.open("x"); child = subprocess.Popen(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT)
                identity = None
                for _ in range(100):
                    identity = process_identity(child.pid)
                    if identity and Path(identity["argv"][0]).name.startswith("python"): break
                    time.sleep(.02)
                if identity is None or Path(identity["argv"][0]).name.startswith("python") is False:
                    raise RuntimeError("new replay identity missing; worker not signaled")
                record = dict(identity, cpu=cpu, config=str(config), config_sha256=m.REC.digest(config))
                immutable(args.output / "launched" / f"{key}.json", record)
                active[key] = record; handles[key] = (child, handle)
            write(args.output / "progress.json", dict(total=9, complete=len(done),
                active=[dict(job_id=k, cpu=r["cpu"], pid=r["pid"]) for k, r in active.items()],
                pending=9 - len(done) - len(active), at_epoch=time.time(), model_refits=0))
            for key, record in list(active.items()):
                identity = process_identity(record["pid"])
                if same_process(record, identity) and identity["state"] != "Z": continue
                job = next(j for j in jobs if j["job_id"] == key)
                if key in handles:
                    child, handle = handles.pop(key); returncode = child.wait(); handle.close()
                    if returncode != 0: raise RuntimeError(f"replay cell failed: {key}; evidence preserved")
                value = verified_cell(job["output_dir"], job, m.REC.digest)
                if value is None: raise RuntimeError("replay worker disappeared without complete output")
                done[key] = value; del active[key]
            if len(done) != len(jobs): time.sleep(5)
        write(args.output / "progress.json", dict(total=9, complete=9, active=[], pending=0,
            at_epoch=time.time(), model_refits=0))
        return closeout(args)


def closeout(args):
    from pricefm_r123_dependency_queue import process_identity, same_process
    m, control = owner(args); prep, jobs = verify_preparation(args, m)
    if (args.output / "completed_evidence.json").exists():
        m.REC.verify_evidence(read(args.output / "completed_evidence.json"))
        parent_freeze(args, m)
        return read(args.output / "terminal.json")
    cells = []; baseline = []; labels = []
    for job in jobs:
        receipt = args.output / "launched" / f"{job['job_id']}.json"
        if receipt.exists():
            record = read(receipt); current = process_identity(record["pid"])
            if same_process(record, current) and current["state"] != "Z":
                raise RuntimeError("replay writer remains; cannot freeze")
        path = Path(job["output_dir"])
        terminal = verified_cell(path, job, m.REC.digest)
        if terminal is None: raise RuntimeError("incomplete nine-panel replay")
        with np.load(path / "predictions.npz", allow_pickle=False) as values:
            saved = read(path / "metrics.json")
            if values["truth"].shape != (terminal["scored_origins"], 96):
                raise RuntimeError("forecast truth shape differs")
            expected = {1: (506, 631), 2: (631, 766), 3: (766, 940)}[job["split"]]
            if (not np.array_equal(values["origin_indices"], np.arange(*expected))
                    or values["origin_utc"].shape != (terminal["scored_origins"],)
                    or terminal["source"] != prep["source"]):
                raise RuntimeError("full internal forecast origins or source differs")
            for operator in OPERATORS:
                if values[operator].shape != (*values["truth"].shape, 7):
                    raise RuntimeError("forecast quantile shape differs")
                score = m.RT.prediction_metrics(values["truth"], values[operator])
                if any(not math.isfinite(v) or abs(v - saved[operator][k]) > 1e-12 for k, v in score.items()):
                    raise RuntimeError("independent metric reconstruction differs")
                cells.append(dict(candidate_id=job["candidate_id"], tau0=job["tau0"], split=job["split"],
                    operator=operator, origins=terminal["scored_origins"], **score))
        old = read(Path(job["parent_cell"]) / "metrics.json")
        baseline.append(dict(candidate_id=job["candidate_id"], split=job["split"], legacy_AQL=old["AQL"],
            legacy_coverage=old["interval_80_coverage"], legacy_late_AQL=old["late_AQL"]))
        labels.extend(dict(candidate_id=job["candidate_id"], split=job["split"], **v) for v in job["fit_labels"])
    frame = pd.DataFrame(cells); comparison = frame[frame.operator.eq("mean_feature")].merge(
        pd.DataFrame(baseline), on=["candidate_id", "split"], validate="one_to_one")
    comparison["AQL_change_percent"] = 100 * (comparison.AQL / comparison.legacy_AQL - 1)
    ranking = frame[frame.operator.eq("mean_feature")].groupby(["candidate_id", "tau0"], as_index=False).agg(
        mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"), worst_AQL=("AQL", "max"),
        mean_coverage=("interval_80_coverage", "mean"), mean_crossing=("crossing_rate", "mean"))
    ranking = ranking.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "mean_crossing", "candidate_id"], kind="mergesort")
    args.output.mkdir(parents=True, exist_ok=True)
    frame.to_csv(args.output / "operator_cell_metrics.csv", index=False)
    comparison.to_csv(args.output / "legacy_comparison.csv", index=False)
    ranking.to_csv(args.output / "corrected_internal_ranking.csv", index=False)
    pd.DataFrame(labels).to_csv(args.output / "fit_convergence_labels.csv", index=False)
    selected = ranking.iloc[0]; job = next(j for j in jobs if j["candidate_id"] == selected.candidate_id)
    choice = dict(candidate_id=job["candidate_id"], spec=job["spec"], tau0=job["tau0"],
        family="al", operator="mean_feature", internal_mean_AQL=float(selected.mean_AQL),
        score_scope="fold1_training_internal_validation_only", full_variational_stationarity_certified=False,
        official_evaluation_authorized=False, article_promotion_authorized=False)
    immutable(args.output / "corrected_internal_choice.json", choice)
    immutable(args.output / "official_evaluation_requirements.json", dict(status="PREPARATION_ONLY_NOT_A_LAUNCH_MANIFEST",
        frozen_internal_choice=choice, region="BG", folds=[1, 2, 3], quantiles=list(m.RT.QUANTILES),
        horizon_steps=96, step_minutes=15, posterior_paths=500, specifications_retuned=False,
        prerequisites=["separate official-evaluation authorization", "resolve/document capped-fit stationarity",
            "freeze full-fold training/scaler/origin contracts", "use actual cached PriceFM, not QDESN-with-PriceFM-driver",
            "fit each full training window, never reuse partial internal fits as full-fold fits",
            "use matching units/timestamps and prohibit test-driven tuning"],
        future_full_training_fits_to_prepare=24, models_fitted_now=0, official_data_opened=False))
    from pricefm_r124_report import report
    report(args.output, jobs, frame, comparison, ranking, pd.DataFrame(labels))
    parent_freeze(args, m)
    terminal = dict(status="R124_INTERNAL_FORECAST_REPLAY_COMPLETE_OFFICIAL_EVALUATION_BLOCKED",
        tag=TAG, panels_complete=9, panels_failed=0, models_refitted=0, quantile_fits_reused=63,
        normal_parents_reused=9, source=prep["source"], owner_head=OWNER_HEAD, choice=choice,
        official_test_opened=False, official_validation_opened=False,
        full_variational_stationarity_certified=False, integration_status="NOT_READY_FOR_INTEGRATION")
    immutable(args.output / "terminal.json", terminal)
    if sum(p.stat().st_size for p in args.output.rglob("*") if p.is_file()) > 500 * 2**20:
        raise RuntimeError("compact replay storage bound exceeded")
    ledger = {str(p): m.REC.digest(p) for p in sorted(args.output.rglob("*")) if p.is_file()
        and p.name not in ("completed_evidence.json", "controller.lock", "controller.log", "blocked.json")
        and not p.name.endswith(".lock") and ".tmp." not in str(p)}
    immutable(args.output / "completed_evidence.json", {"evidence_sha256": ledger})
    return terminal


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("prepare", "smoke", "controller", "cell", "closeout"), required=True)
    p.add_argument("--owner-root", type=Path, required=True)
    p.add_argument("--frozen-code-root", type=Path, required=True)
    p.add_argument("--parent-campaign", type=Path, default=DATA / "campaigns" / PARENT)
    p.add_argument("--parent-prep", type=Path, default=DATA / "launch_prep" / PARENT)
    p.add_argument("--output", type=Path, default=DATA / "campaigns" / TAG)
    p.add_argument("--prep", type=Path, default=DATA / "launch_prep" / TAG)
    p.add_argument("--validation-receipt", type=Path)
    p.add_argument("--config", type=Path)
    p.add_argument("--workers", type=int, default=15)
    return p


if __name__ == "__main__":
    args = parser().parse_args()
    try:
        result = (prepare(args) if args.mode == "prepare" else cell(args, smoke=args.mode == "smoke")
                  if args.mode in ("cell", "smoke") else controller(args) if args.mode == "controller" else closeout(args))
        print(json.dumps(result, sort_keys=True), flush=True)
    except Exception as error:
        # Refuse to write into an arbitrary supplied directory, even on failure.
        if args.output.resolve() == DATA / "campaigns" / TAG:
            destination = args.output / (f"failed_{args.config.stem}.json" if args.mode in ("cell", "smoke") and args.config else "blocked.json")
            write(destination, dict(error_type=type(error).__name__, error=str(error), mode=args.mode,
                at_epoch=time.time(), model_refits=0, existing_evidence_preserved=True))
        raise
