#!/usr/bin/env python3
"""R150: bounded full-origin replay from certified, unchanged Normal moments.

The supervisor imports only standard-library code. Numerical dependencies are
loaded exclusively after an independently attested per-worker unit policy.
This stage never fits a model, opens an official bank, or launches AL.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import uuid

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
from pricefm_r150_contract import (QUANTILES, INT_KEYS, array_shapes, audit_permutation, strongest, select_branch,
    prospective_costs, choose_nominees,
    confirm_gains, expected_rows, fingerprint, metrics, practical_margin, read_npz, validate_arrays)

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = "pricefm_stage_r150_cached_continuation_20261023"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CONFIG = ROOT / "application/config" / (TAG+".json")
PREP = DATA / "launch_prep" / TAG
OUT = DATA / "campaigns" / TAG
_MODULES = {}
_VALIDATED = {}
_PREPARATION_CACHE = {}


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name+"."+uuid.uuid4().hex+".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False)+"\n")
    os.replace(temporary, path)


def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError("immutable R150 record differs: "+str(path))
    else:
        write(path, value)


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected:
            raise RuntimeError("pinned artifact changed: "+path)


def import_frozen(name, path, expected):
    if digest(path) != expected:
        raise RuntimeError("frozen helper differs: "+str(path))
    if name not in _MODULES:
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _MODULES[name] = module
    return _MODULES[name]


def original():
    c = validate_config(read(CONFIG))
    return import_frozen("r150_original_r149", c["original_science_entry"], c["original_science_sha256"])


def kernel():
    return original().kernel()


def validate_config(c):
    prohibited = ("al_authorized", "new_fits_authorized", "new_geometry_authorized",
        "official_evaluation_authorized", "promotion_authorized", "article_mutation_authorized",
        "registry_mutation_authorized", "automatic_future_stage_authorized", "test_used_for_selection")
    if any(c.get(k) is not False for k in prohibited):
        raise ValueError("R150 cached scope does not authorize fits/promotion/official access")
    if (c.get("tag") != TAG or c.get("region") != "EE" or c.get("paths") != 100
            or c.get("quantiles") != list(QUANTILES) or c.get("horizon_steps") != 96
            or c.get("clock_offsets_steps") != [0, 24, 48, 72] or c.get("chunk_origins") != 8
            or c.get("full_daily_counts") != {"1": 124, "2": 134, "3": 173}
            or c.get("extra_seeds") != [2026102301, 2026102302]
            or c.get("primary_aggregation") != "equal_three_inner_split_macro"
            or c.get("practical_margin") != {"absolute": .10, "relative": .01}
            or c.get("seed0_trigger_fraction") != .5 or c.get("audit_key") != "pricefm_continuation_plan_20261023|audit_v1"
            or c.get("benchmark_max_seconds") != 1200 or c.get("cost_headroom") != 1.5
            or c.get("max_new_D_components") != 72 or c.get("max_new_S_B1") != 24
            or c.get("max_new_S_B2") != 84 or c.get("branch_policy") != "B1_cost_default_B2_if_relative_cost_and_finite_budget_fit"
            or c.get("max_projected_cpu_seconds") != 32400 or c.get("max_numerical_waves") != 3
            or c.get("wave_lease_seconds") != 7200 or c.get("wave_dispatch_seconds") != 5400):
        raise ValueError("frozen R150 allocation differs")
    packages = c.get("packages", [])
    ids = [p["package_id"] for p in packages]
    if (len(packages) != 26 or len(set(ids)) != 26
            or len({p["candidate_id"] for p in packages}) != 25
            or len({(p["candidate_id"], p["tau0"]) for p in packages}) != 26
            or c["control"] not in ids or c["negative_control"] not in ids):
        raise ValueError("26 exact packages / 25 geometries required")
    control = next(p for p in packages if p["package_id"] == c["control"])
    alt = [p for p in packages if p["candidate_id"] == control["candidate_id"] and p != control]
    if (control["candidate_id"] != "r134_0cab1abbe8ace168" or control["tau0"] != .0024929739307713865
            or len(alt) != 1 or alt[0]["tau0"] != .00024929739307713865):
        raise ValueError("actual C0 and separate certified alternate scale required")
    if len(c.get("benchmark_D_packages", [])) != 5 or len(c.get("benchmark_S_packages", [])) != 3:
        raise ValueError("18-call benchmark coverage differs")
    lookup = {p["package_id"]: p for p in packages}
    if not {193, 337, 385, 769}.issubset({lookup[p]["p"] for p in c["benchmark_D_packages"]}):
        raise ValueError("benchmark misses dimension envelope")
    if not any(lookup[p]["spec"]["feature_policy"] == "graph_neighbor_exogenous" for p in c["benchmark_D_packages"]):
        raise ValueError("benchmark misses input diversity")
    return c


def source_identity():
    c = validate_config(read(CONFIG))
    if git(ROOT, "branch", "--show-current") != c["required_branch"] or git(ROOT, "status", "--porcelain"):
        raise RuntimeError("clean committed dedicated R150 worktree required")
    return dict(branch=c["required_branch"], head=git(ROOT, "rev-parse", "HEAD"))


def name_for(package, split, mode, seed_index):
    return "EE_"+package+"_s"+str(split)+"_"+mode+"_seed"+str(seed_index)


def task_identity(task):
    return {k: v for k, v in task.items() if k not in ("scientific_identity_sha256", "reuse")}


def build_preparation(identity):
    c = validate_config(read(CONFIG))
    verify_hashes(c["original_pins"])
    old = original().read_preparation()
    original().parent_manifest(check_all=True)
    if old["source"]["head"] != c["original_science_head"]:
        raise RuntimeError("R149 scientific producer differs")
    verify_hashes(old["source_sha256"])
    verify_hashes(old["input_sha256"])
    original_config = read(Path(read(original().CONFIG)["parent_root"])/"application/config/pricefm_stage_r148_ee_parallel_development_20261023.json")
    cache = Path(original_config["cache_root"])
    original_fit = read(original_config["cache_preparation"])
    inputs = dict(c["original_pins"])
    inputs.update(old["input_sha256"])
    sources = dict(old["source_sha256"])
    for pattern in ("application/scripts/pricefm/*r150*.py", "application/config/*r150*.json",
                    "application/tests/*r150*.py", "docs/implementation_notes/*r150*.md"):
        sources.update({str(p): digest(p) for p in ROOT.glob(pattern)})
    original_full = {(t["candidate_id"], t["tau0"], t["split"]): t for t in old["tasks"] if t["seed_index"] == 0}
    cohorts = {s: next(t for t in old["tasks"] if t["split"] == s and t["seed_index"] == 0) for s in (1, 2, 3)}
    tasks = []
    for package in c["packages"]:
        for split in (1, 2, 3):
            parent_name = f"rhs_EE_{package['candidate_id']}_s{split}_t{package['tau0']:.12e}"
            descriptor, result, ledger = kernel().verify_cached_packet(cache, parent_name, original_config["cache_source_head"], heavy=True)
            terminal = read(cache/"tasks_done"/parent_name/"fit/terminal.json")
            if (descriptor["spec"] != package["spec"] or descriptor["tau0"] != package["tau0"]
                    or descriptor["split"] != split or descriptor["region"] != "EE"
                    or result["certified"] is not True or terminal["full_variational_certified"] is not True
                    or terminal["test_opened"] is not False or terminal["tau0"] != package["tau0"]):
                raise RuntimeError("exact certified cached Normal package differs")
            stats, stats_result, stats_hashes = kernel().verify_cached_packet(cache, descriptor["stats_name"], original_config["cache_source_head"], heavy=False)
            if stats["candidate_id"] != package["candidate_id"] or stats["split"] != split or stats_result["certified"] is not True:
                raise RuntimeError("training scaler parent differs")
            scaler = cache/"tasks_done"/descriptor["stats_name"]/"scaler.json"
            inputs.update(ledger)
            inputs.update(stats_hashes)
            inputs[str(scaler)] = digest(scaler)
            common = cohorts[split]
            for mode, seed_indices in (("D", (0,)), ("S", (0, 1, 2))):
                for seed_index in seed_indices:
                    task = dict(name=name_for(package["package_id"], split, mode, seed_index),
                        kind="cached_"+mode+"_full_origin", region="EE", package_id=package["package_id"],
                        candidate_id=package["candidate_id"], tau0=package["tau0"], p=package["p"],
                        spec=package["spec"], mode=mode, split=split, seed_index=seed_index,
                        forecast_seed=([common["forecast_seed"]]+c["extra_seeds"])[seed_index], paths=100,
                        parent_task=parent_name, parent_source=original_fit["source"],
                        parent_seal_sha256=digest(cache/"tasks_done"/parent_name/"completed_evidence.json"),
                        parent_fit=str(cache/"tasks_done"/parent_name/"fit"), parent_input_sha256=ledger,
                        scaler_path=str(scaler), scaler_sha256=digest(scaler),
                        bank=old["banks"][package["spec"]["feature_policy"]],
                        clock_offsets_steps=c["clock_offsets_steps"],
                        daily_origin_positions=common["daily_origin_positions"],
                        validation_origin_positions=common["validation_origin_positions"],
                        train_origin_positions=common["train_origin_positions"], origin_timestamps=common["origin_timestamps"],
                        horizon_steps=96, quantiles=list(QUANTILES), source_kernel_sha256=c["original_kernel_sha256"],
                        new_model_fits=0, posterior_updated=False, test_opened=False)
                    task["scientific_identity_sha256"] = fingerprint(task_identity(task))
                    reusable = original_full.get((package["candidate_id"], package["tau0"], split)) if seed_index == 0 else None
                    task["reuse"] = None
                    if reusable is not None:
                        if not original().task_complete(reusable["name"]):
                            raise RuntimeError("original full component fails strict validation")
                        folder = original().OUT/"tasks_done"/reusable["name"]
                        task["reuse"] = dict(producer=old["source"], task=reusable["name"], mode=mode,
                            task_path=str(original().OUT/"tasks"/(reusable["name"]+".json")),
                            task_sha256=digest(original().OUT/"tasks"/(reusable["name"]+".json")),
                            packet=str(folder), seal_sha256=digest(folder/"completed_evidence.json"),
                            predictions_sha256=digest(folder/"predictions.npz"), result_sha256=digest(folder/"result.json"))
                        inputs.update({str(folder/f): digest(folder/f) for f in ("completed_evidence.json", "predictions.npz", "result.json")})
                    tasks.append(task)
    prep = dict(schema_version=1, status="R150_PREPARED_CACHED_ONLY_NOT_PROMOTED", source=identity,
        config_sha256=digest(CONFIG), source_sha256=sources, input_sha256=inputs,
        dependency=old["dependency"], dependency_head=old["dependency_head"], banks=old["banks"],
        packages=c["packages"], control=c["control"], negative_control=c["negative_control"],
        potential_task_count=len(tasks), tasks=tasks, original_scientific_source=old["source"],
        imported_components=sum(t["reuse"] is not None for t in tasks),
        new_model_fits=0, test_opened=False, posterior_updated=False,
        primary_aggregation=c["primary_aggregation"], admitted_task_count_is_branch_dependent=True,
        frozen_audit_permutation=audit_permutation(c["packages"], c["audit_key"]))
    if len(tasks) != 312 or prep["imported_components"] != 12:
        raise RuntimeError("312 potential components and 12 exact imports required")
    verify_hashes(sources)
    return prep


def prepare():
    if (PREP/"prepared.json").exists():
        return read_preparation()
    identity = source_identity()
    prep = build_preparation(identity)
    immutable(PREP/"preparation.json", prep)
    for task in prep["tasks"]:
        immutable(OUT/"tasks"/(task["name"]+".json"), task)
    immutable(PREP/"prepared.json", dict(source=identity, preparation_sha256=digest(PREP/"preparation.json")))
    return prep


def read_preparation():
    paths = [PREP/"preparation.json", PREP/"prepared.json", CONFIG]
    signature = tuple((str(p), p.stat().st_mtime_ns, p.stat().st_ctime_ns, p.stat().st_size) for p in paths)
    if _PREPARATION_CACHE.get("signature") == signature:
        return _PREPARATION_CACHE["value"]
    prep = read(PREP/"preparation.json")
    seal = read(PREP/"prepared.json")
    if (seal != dict(source=prep["source"], preparation_sha256=digest(PREP/"preparation.json"))
            or prep["config_sha256"] != digest(CONFIG) or prep["new_model_fits"] != 0
            or prep["test_opened"] is not False or len(prep["tasks"]) != 312
            or prep["source"]["head"] != git(ROOT, "rev-parse", "HEAD")):
        raise RuntimeError("R150 preparation seal/source/config differs")
    validate_config(read(CONFIG))
    _PREPARATION_CACHE.update(signature=signature, value=prep)
    return prep


def task_by_name(name, prep=None):
    task = next((t for t in (prep or read_preparation())["tasks"] if t["name"] == name), None)
    if task is None:
        raise ValueError("unknown R150 component: "+name)
    if task["scientific_identity_sha256"] != fingerprint(task_identity(task)):
        raise RuntimeError("task identity differs")
    return task


def context_identity(task, prep):
    return dict(source=prep["source"], task_sha256=fingerprint(task),
                scientific_identity_sha256=task["scientific_identity_sha256"], mode=task["mode"],
                seed=task["forecast_seed"], parent_seal_sha256=task["parent_seal_sha256"],
                scaler_sha256=task["scaler_sha256"], bank=task["bank"], paths=100)


def chunks(task):
    result = []
    for offset in task["clock_offsets_steps"]:
        for start in range(0, len(task["daily_origin_positions"]), 8):
            positions = task["daily_origin_positions"][start:start+8]
            result.append(dict(name=f"clock{offset:02d}_part{start//8:03d}", clock_offset_steps=offset,
                origin_positions=positions, origin_timestamps=task["origin_timestamps"][str(offset)][start:start+8],
                stable_rng_origin_keys=[p*96+offset for p in positions]))
    return result


def verify_packet(folder, expected):
    folder = Path(folder)
    seal = read(folder/"completed_evidence.json")
    if set(seal.get("artifacts", {})) != set(expected):
        raise RuntimeError("missing or unexpected sealed artifact")
    verify_hashes({str(folder/p): h for p, h in seal["artifacts"].items()})
    return seal


def validate_reuse(task):
    reuse = task["reuse"]
    if reuse is None:
        raise ValueError("no imported component")
    folder = Path(reuse["packet"])
    files = [Path(reuse["task_path"]), Path(task["scaler_path"]), Path(task["bank"]["path"])]
    files += [folder/p for p in ("completed_evidence.json", "predictions.npz", "result.json")]
    files += [Path(p) for p in task["parent_input_sha256"]]
    signature = (fingerprint(task), tuple((str(p), p.stat().st_mtime_ns, p.stat().st_ctime_ns, p.stat().st_size) for p in files))
    cache_key = "reuse_"+task["name"]
    if _VALIDATED.get(cache_key, {}).get("signature") == signature:
        return _VALIDATED[cache_key]["metrics"]
    verify_hashes({reuse["task_path"]: reuse["task_sha256"],
        str(folder/"completed_evidence.json"): reuse["seal_sha256"],
        str(folder/"predictions.npz"): reuse["predictions_sha256"], str(folder/"result.json"): reuse["result_sha256"]})
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["scaler_path"]: task["scaler_sha256"], task["bank"]["path"]: task["bank"]["sha256"]})
    old = read(reuse["task_path"])
    keys = ("candidate_id", "tau0", "split", "forecast_seed", "paths", "bank", "scaler_path", "scaler_sha256",
            "daily_origin_positions", "clock_offsets_steps", "origin_timestamps", "parent_seal_sha256")
    if (any(task[k] != old[k] for k in keys) or old["seed_index"] != 0
            or reuse["producer"]["head"] != read(CONFIG)["original_science_head"]):
        raise RuntimeError("source-preserving extraction identity differs")
    result = read(folder/"result.json")["metrics"]["deterministic" if task["mode"] == "D" else "stochastic"]
    _VALIDATED[cache_key] = dict(signature=signature, metrics=result)
    return result


def task_complete(name):
    if name == "__benchmark__":
        if not (OUT/"benchmark"/"completed_evidence.json").exists():
            return False
        seal = verify_packet(OUT/"benchmark", {"timings.json", "branch.json"})
        prep = read_preparation()
        if seal.get("context") != dict(source=prep["source"], preparation_sha256=digest(PREP/"preparation.json")):
            raise RuntimeError("benchmark producer/context differs")
        return True
    prep = read_preparation()
    task = task_by_name(name, prep)
    if read(OUT/"tasks"/(name+".json")) != task:
        raise RuntimeError("immutable component descriptor differs")
    if task["reuse"]:
        validate_reuse(task)
        return True
    folder = OUT/"tasks_done"/name
    if not folder.exists():
        return False
    files = [folder/p for p in ("completed_evidence.json", "result.json", "predictions.npz")]
    files += [Path(task["scaler_path"]), Path(task["bank"]["path"])] + [Path(p) for p in task["parent_input_sha256"]]
    signature = (fingerprint(task), tuple((str(p), p.stat().st_mtime_ns, p.stat().st_ctime_ns, p.stat().st_size) for p in files))
    if _VALIDATED.get(name) == signature:
        return True
    seal = verify_packet(folder, {"result.json", "predictions.npz"})
    if seal.get("context") != context_identity(task, prep) or seal.get("certified") is not True:
        raise RuntimeError("component producer/context differs")
    result = read(folder/"result.json")
    if (result.get("scientific_identity_sha256") != task["scientific_identity_sha256"]
            or result.get("units") != "EUR/MWh" or result.get("new_model_fits") != 0
            or result.get("posterior_updated") is not False or result.get("test_opened") is not False
            or result.get("mode") != task["mode"] or result.get("origin_clock_windows") != 4*len(task["daily_origin_positions"])
            or not result.get("numerical_threadpools") or any(p["num_threads"] != 1 for p in result["numerical_threadpools"])
            or not math.isfinite(result["metrics"]["AQL"]) or result["metrics"]["AQL"] < 0):
        raise RuntimeError("result identity/scope/policy differs")
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["scaler_path"]: task["scaler_sha256"], task["bank"]["path"]: task["bank"]["sha256"]})
    validate_arrays(task, read_npz(folder/"predictions.npz", headers_only=True), read(task["scaler_path"]), semantic=False)
    _VALIDATED[name] = signature
    return True


def component_loss(package, mode, seed_index=0):
    values = []
    for split in (1, 2, 3):
        name = name_for(package, split, mode, seed_index)
        if not task_complete(name):
            raise RuntimeError("incomplete required component: "+name)
        task = task_by_name(name)
        values.append((validate_reuse(task) if task["reuse"] else read(OUT/"tasks_done"/name/"result.json")["metrics"])["AQL"])
    return sum(values)/3


def component_names(packages, mode, seeds):
    return [name_for(p, split, mode, seed) for p in packages for seed in seeds for split in (1, 2, 3)]


def write_decision(name, value):
    immutable(OUT/"decisions"/(name+".json"), value)
    immutable(OUT/"decisions"/(name+".seal.json"), dict(sha256=digest(OUT/"decisions"/(name+".json")),
        source=read_preparation()["source"], preparation_sha256=digest(PREP/"preparation.json")))


def read_decision(name):
    path = OUT/"decisions"/(name+".json")
    expected = dict(sha256=digest(path), source=read_preparation()["source"],
                    preparation_sha256=digest(PREP/"preparation.json"))
    if read(OUT/"decisions"/(name+".seal.json")) != expected:
        raise RuntimeError("immutable decision seal changed: "+name)
    return read(path)


def manifest_state():
    """Derive the finite admitted DAG without creating or examining new scores."""
    prep = read_preparation()
    if not task_complete("__benchmark__"):
        return "BENCHMARK", ["__benchmark__"], False
    branch_record = read(OUT/"benchmark/branch.json")
    if branch_record.get("budget_disposition") == "DEFERRED_NEITHER_FULL_BRANCH_FITS":
        return "RESOURCE_BUDGET_DEFERRED", [], False
    branch = branch_record["branch"]
    all_packages = [p["package_id"] for p in prep["packages"]]
    first = component_names(all_packages, "D" if branch == "B1" else "S", [0])
    if not all(task_complete(n) for n in first):
        return ("DETERMINISTIC_POOL" if branch == "B1" else "STOCHASTIC_POOL"), first, False
    if not (OUT/"decisions/nominees.seal.json").exists():
        return "NOMINATION_REQUIRED", first, False
    nominees = read_decision("nominees")["nominees"]
    seed0 = component_names(nominees, "S", [0])
    if not all(task_complete(n) for n in seed0):
        return "NOMINEE_SEED0", list(dict.fromkeys(first+seed0)), False
    if not (OUT/"decisions/extra_seeds.seal.json").exists():
        return "EXTRA_SEED_DECISION_REQUIRED", list(dict.fromkeys(first+seed0)), False
    qualified = read_decision("extra_seeds")["qualified"]
    if (len(set(nominees)) != len(nominees) or len(nominees) > (2 if branch == "B1" else 1)
            or any(p not in all_packages or p == prep["control"] for p in nominees)
            or len(set(qualified)) != len(qualified) or any(p not in nominees for p in qualified)):
        raise RuntimeError("decision exceeds the finite candidate/seed allocation")
    extras = component_names(([prep["control"]]+qualified) if qualified else [], "S", [1, 2])
    names = list(dict.fromkeys(first+seed0+extras))
    # C0 original-seed S is an immutable matched comparator, including B1.
    names = list(dict.fromkeys(names+component_names([prep["control"]], "S", [0])))
    if not all(task_complete(n) for n in names):
        return "MATCHED_FULL_MC", names, False
    return "READY_FOR_ASSESSMENT", names, True


def advance():
    """Metadata transitions only. Decisions become immutable before dispatch."""
    prep = read_preparation()
    phase, names, terminal = manifest_state()
    c = read(CONFIG)
    if phase == "NOMINATION_REQUIRED":
        branch = read(OUT/"benchmark/branch.json")["branch"]
        mode = "D" if branch == "B1" else "S"
        losses = {p["package_id"]: component_loss(p["package_id"], mode) for p in prep["packages"]}
        if branch == "B1":
            nomination = choose_nominees(prep["packages"], losses, c["control"], c["negative_control"], c["audit_key"])
            if nomination["audit_order"] != prep["frozen_audit_permutation"]:
                raise RuntimeError("pre-score frozen audit permutation changed")
            nominees = [nomination["A"], nomination["B"]]
        else:
            nominees = [strongest(losses, [c["control"]])]
            nomination = dict(A=nominees[0], audit_rule="B2 one strongest full S seed0 package; no runner-up cascade")
        write_decision("nominees", dict(branch=branch, nominees=nominees, rule=nomination,
            nomination_losses=losses, source=prep["source"], preparation_sha256=digest(PREP/"preparation.json")))
    elif phase == "EXTRA_SEED_DECISION_REQUIRED":
        nominees = read_decision("nominees")["nominees"]
        control = component_loss(c["control"], "S")
        gains = {p: control-component_loss(p, "S") for p in nominees}
        trigger = .5*practical_margin(control)
        qualified = [p for p in nominees if gains[p] >= trigger]
        write_decision("extra_seeds", dict(qualified=qualified, nominees=nominees,
            seed0_control_AQL=control, seed0_gains=gains, exploration_trigger=trigger,
            rule="seed0 matched aggregate gain >= half practical margin", source=prep["source"]))
    return queue_state()


def queue_state():
    phase, names, terminal = manifest_state()
    complete = [n for n in names if task_complete(n)]
    pending = [n for n in names if n not in complete]
    ready = []
    for name in pending:
        if name == "__benchmark__":
            ready.append(dict(name=name, kind="bounded_18_call_benchmark", estimated_cpu_seconds=1200))
        else:
            task = task_by_name(name)
            estimate = estimate_task(task)
            frozen = read(OUT/"benchmark/branch.json")["task_estimates"][name]
            ready.append(dict(name=name, kind=task["kind"], estimated_cpu_seconds=estimate,
                estimated_wall_seconds=frozen["estimated_wall_seconds"],
                estimated_max_chunk_wall_seconds=frozen["estimated_max_chunk_wall_seconds"]))
    result = dict(phase=phase, ready=ready, pending=pending, complete=complete, total=len(names),
        terminal=terminal, scientific_complete=(OUT/"assessment.json").exists(),
        new_model_fits=0, promotion_authorized=False)
    if (OUT/"benchmark/branch.json").exists():
        result["resource_projection"] = read(OUT/"benchmark/branch.json")["resource_projection"]
    return result


def estimate_task(task):
    if not (OUT/"benchmark/branch.json").exists():
        return None
    return read(OUT/"benchmark/branch.json")["task_estimates"][task["name"]]["estimated_cpu_seconds"]


def guarded_runtime(cpu, receipt_path, name):
    """Refuse numerical imports until the actual systemd policy is attested."""
    receipt = read(receipt_path)
    prep = read_preparation()
    if (receipt.get("schema_version") != 1 or receipt.get("stage") != "R150"
            or receipt.get("task") != name or receipt.get("cpu") != cpu
            or receipt.get("expected_affinity") != [cpu] or receipt.get("expected_scheduler") != 5
            or receipt.get("numerical_threads") != 1 or receipt.get("io_class") != 3
            or receipt.get("source_head") != prep["source"]["head"]
            or receipt.get("lease_expires_epoch", 0) <= time.time()
            or not receipt.get("worker_invocation_id") or not receipt.get("worker_cgroup")
            or not receipt.get("unit") or not receipt.get("probe_id") or not receipt.get("actual_probe")):
        raise RuntimeError("actual worker unit policy receipt missing/invalid/expired")
    if cpu not in range(15, 30) or os.sched_getaffinity(0) != {cpu} or os.sched_getscheduler(0) != os.SCHED_IDLE:
        raise RuntimeError("one admitted physical CPU15–29 and SCHED_IDLE required")
    if not subprocess.check_output(["ionice", "-p", str(os.getpid())], text=True).startswith("idle"):
        raise RuntimeError("idle numerical I/O required")
    actual_cgroups = {line.split(":", 2)[2] for line in Path("/proc/self/cgroup").read_text().splitlines()}
    if receipt["worker_cgroup"] not in actual_cgroups:
        raise RuntimeError("worker cgroup differs from attested owned unit")
    if os.environ.get("INVOCATION_ID") != receipt["worker_invocation_id"]:
        raise RuntimeError("actual worker unit invocation differs from policy receipt")
    properties = receipt["actual_probe"].get("properties", {})
    process_proof = receipt["actual_probe"].get("process", {})
    if (properties.get("Id") != receipt["unit"] or properties.get("InvocationID") != receipt["worker_invocation_id"]
            or properties.get("ControlGroup") != receipt["worker_cgroup"]
            or process_proof.get("scheduler") != 5 or process_proof.get("affinity") != [cpu]
            or properties.get("IOSchedulingClass") != "3"):
        raise RuntimeError("receipt lacks matching actual service policy proof")
    for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
                "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        if os.environ.get(key) != "1":
            raise RuntimeError("one numerical thread required: "+key)
    verify_hashes(prep["source_sha256"])
    source_identity()
    return receipt


def numerical_context(prep, task):
    """Original immutable helper APIs; never rebind any producer globals."""
    core, runtime = original().load_numerical(prep)
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["bank"]["path"]: task["bank"]["sha256"], task["scaler_path"]: task["scaler_sha256"]})
    raw = core.load_arrays(runtime, Path(task["bank"]["path"]))
    cell = runtime.internal_splits(len(raw.response))[task["split"]-1]
    if cell["train"].tolist() != task["train_origin_positions"] or cell["validation"].tolist() != task["validation_origin_positions"]:
        raise RuntimeError("exact frozen inner cohort differs")
    scaled, scaler = runtime.standardize_from_training_origins(raw, cell["train"])
    if fingerprint(scaler) != fingerprint(read(task["scaler_path"])):
        raise RuntimeError("training-only scaler identity differs")
    fit = runtime.load_normal_fit(Path(task["parent_fit"]))
    if len(fit["beta_mean"]) != task["p"]:
        raise RuntimeError("readout moment dimension differs")
    return dict(core=core, runtime=runtime, raw=raw, scaled=scaled, scaler=scaler, fit=fit,
                pools=kernel().numerical_threadpools())


def predict(context, task, descriptor, beat):
    import numpy as np
    from pricefm_r127_contract import shifted_windows, window_identity
    positions = np.asarray(descriptor["origin_positions"], dtype=int)
    validation = np.asarray(task["validation_origin_positions"], dtype=int)
    offset = descriptor["clock_offset_steps"]
    arrays = shifted_windows(context["scaled"], positions, offset, validation)
    raw = shifted_windows(context["raw"], positions, offset, validation)
    window_identity(arrays, dt.datetime.fromisoformat(str(context["raw"].anchors[validation[0]])),
        dt.datetime.fromisoformat(str(context["raw"].anchors[validation[-1]]))+dt.timedelta(days=1))
    if [dt.datetime.fromisoformat(str(s)).isoformat() for s in arrays.anchors] != descriptor["origin_timestamps"]:
        raise RuntimeError("absolute shifted timestamps differ")
    if task["mode"] == "D":
        prediction = kernel().deterministic_predictions(context["runtime"], arrays, task["spec"], context["fit"])
        audit = dict(policy="unchanged_omega_mean_plus_zVz_analytic_Normal_quantiles", simulated_paths=0)
    else:
        runtime = context["runtime"]
        seed = runtime.BASE.deterministic_seed(task["forecast_seed"], "EE", task["split"])
        prediction, audit = context["core"].normal_predictions(runtime, arrays, task["spec"], context["fit"],
            np.asarray(descriptor["stable_rng_origin_keys"], dtype=int),
            runtime.BASE.deterministic_seed(seed, "clock", offset), paths=100,
            observe=lambda event: beat(dict(event, chunk=descriptor["name"])))
    if not np.isfinite(prediction).all():
        raise RuntimeError("nonfinite cached prediction")
    if not np.allclose(raw.response, arrays.response*context["scaler"]["price_scale"]+context["scaler"]["price_mean"], rtol=1e-12, atol=1e-10):
        raise RuntimeError("raw truth / inverse scaler differs")
    return prediction, arrays.response, audit


def retained_arrays(context, task, descriptor, prediction, truth, compute_loss=True):
    import numpy as np
    if compute_loss:
        from pricefm_r126_contract import loss
    scale, center = context["scaler"]["price_scale"], context["scaler"]["price_mean"]
    positions = descriptor["origin_positions"]
    result = dict(origin_positions=positions, clock_offsets=[descriptor["clock_offset_steps"]]*len(positions),
        stable_rng_origin_keys=descriptor["stable_rng_origin_keys"],
        origin_timestamps_ns=[round(dt.datetime.fromisoformat(s).timestamp()*1e9) for s in descriptor["origin_timestamps"]],
        truth_standardized=truth, truth_eur=truth*scale+center,
        prediction_standardized=prediction, prediction_eur=prediction*scale+center,
        origin_AQL=(loss(truth, prediction).mean(axis=(1, 2))*scale if compute_loss else np.zeros(len(positions))))
    return {k: np.ascontiguousarray(v, dtype="<i8" if k in INT_KEYS else "<f8") for k, v in result.items()}


def light(arrays):
    return {k: (tuple(v.shape), v.ravel().tolist()) for k, v in arrays.items()}


def seal_checkpoint(prep, task, descriptor, context, beat):
    import numpy as np
    folder = OUT/"checkpoints"/task["name"]/descriptor["name"]
    identity = dict(context=context_identity(task, prep), descriptor=descriptor)
    if folder.exists():
        seal = verify_packet(folder, {"chunk.json", "predictions.npz"})
        if seal.get("identity") != identity or seal.get("certified") is not True:
            raise RuntimeError("checkpoint identity differs")
        arrays = read_npz(folder/"predictions.npz")
        validate_arrays(task, arrays, context["scaler"], descriptor)
        with np.load(folder/"predictions.npz", allow_pickle=False) as packet:
            return {k: packet[k] for k in packet.files}
    started, cpu0 = time.monotonic(), time.process_time()
    beat(dict(status="chunk_running", chunk=descriptor["name"]))
    prediction, truth, audit = predict(context, task, descriptor, beat)
    arrays = retained_arrays(context, task, descriptor, prediction, truth)
    validate_arrays(task, light(arrays), context["scaler"], descriptor)
    attempt = OUT/"attempts"/task["name"]/(descriptor["name"]+"."+uuid.uuid4().hex)
    attempt.mkdir(parents=True)
    np.savez_compressed(attempt/"predictions.npz", **arrays)
    metadata = dict(identity=identity, numerical_threadpools=kernel().numerical_threadpools(),
        sampler_audit=audit, elapsed_seconds=time.monotonic()-started,
        cpu_seconds=time.process_time()-cpu0, peak_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        new_model_fits=0, posterior_updated=False, test_opened=False)
    write(attempt/"chunk.json", metadata)
    write(attempt/"completed_evidence.json", dict(identity=identity, certified=True,
        artifacts={p: digest(attempt/p) for p in ("chunk.json", "predictions.npz")}))
    folder.parent.mkdir(parents=True, exist_ok=True)
    os.rename(attempt, folder)
    beat(dict(status="chunk_sealed", chunk=descriptor["name"], cpu_seconds=metadata["cpu_seconds"], elapsed_seconds=metadata["elapsed_seconds"]))
    return arrays


def worker(name, cpu, policy_receipt):
    receipt = guarded_runtime(cpu, policy_receipt, name)
    import numpy as np
    prep = read_preparation()
    kernel().numerical_threadpools()
    if name == "__benchmark__":
        return benchmark(prep, cpu, policy_receipt, startup_cpu=time.process_time())
    task = task_by_name(name, prep)
    if name not in [t["name"] for t in queue_state()["ready"]] and not task_complete(name):
        raise RuntimeError("component is not admitted by current finite DAG")
    locks = OUT/"locks"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks/(name+".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
        if task_complete(name):
            return dict(status="already_complete", name=name)
        started = time.monotonic()
        def beat(event):
            write(OUT/"heartbeats"/(name+".json"), dict(event, epoch=time.time(), task=name, pid=os.getpid(), cpu=cpu))
        beat(dict(status="context_loading"))
        context = numerical_context(prep, task)
        parts = []
        for descriptor in chunks(task):
            if time.time() >= receipt["lease_expires_epoch"] or (Path(policy_receipt).parent/"stop_requests"/(name+".json")).exists():
                beat(dict(status="cooperative_checkpoint_stop"))
                return dict(status="deferred_at_checkpoint", name=name)
            parts.append(seal_checkpoint(prep, task, descriptor, context, beat))
        arrays = {k: np.ascontiguousarray(np.concatenate([v[k] for v in parts]), dtype="<i8" if k in INT_KEYS else "<f8") for k in array_shapes(1)}
        validate_arrays(task, light(arrays), context["scaler"])
        verify_hashes(task["parent_input_sha256"])
        verify_hashes({task["bank"]["path"]: task["bank"]["sha256"], task["scaler_path"]: task["scaler_sha256"]})
        result = dict(name=name, certified=True, source=prep["source"], mode=task["mode"],
            scientific_identity_sha256=task["scientific_identity_sha256"], units="EUR/MWh",
            metrics=metrics(light(arrays)), origin_clock_windows=len(arrays["origin_positions"]),
            numerical_threadpools=kernel().numerical_threadpools(), elapsed_seconds=time.monotonic()-started,
            new_model_fits=0, posterior_updated=False, test_opened=False, promotion_authorized=False,
            standardized_and_EUR_retained=True, equal_origin_clock_weights=True)
        attempt = OUT/"attempts"/name/("final."+uuid.uuid4().hex)
        attempt.mkdir(parents=True)
        np.savez_compressed(attempt/"predictions.npz", **arrays)
        write(attempt/"result.json", result)
        write(attempt/"completed_evidence.json", dict(context=context_identity(task, prep), certified=True,
            artifacts={p: digest(attempt/p) for p in ("result.json", "predictions.npz")}))
        destination = OUT/"tasks_done"/name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise RuntimeError("existing invalid packet requires review")
        os.rename(attempt, destination)
        if not task_complete(name):
            raise RuntimeError("sealed packet failed completion check")
        beat(dict(status="completed", elapsed_seconds=result["elapsed_seconds"]))
        return result


def benchmark(prep, cpu, policy_receipt, startup_cpu=0.):
    """Exactly fifteen D and three S timings; never computes candidate loss."""
    import numpy as np
    c = read(CONFIG)
    started, cpu_started = time.monotonic(), time.process_time()
    receipt = read(policy_receipt)
    deadline = min(started+c["benchmark_max_seconds"], started+receipt["lease_expires_epoch"]-time.time())
    rows = []
    attempt = OUT/"attempts"/"__benchmark__"/uuid.uuid4().hex
    attempt.mkdir(parents=True)
    def beat(event):
        write(OUT/"heartbeats/__benchmark__.json", dict(event, epoch=time.time(), task="__benchmark__", cpu=cpu, pid=os.getpid()))
    for mode, packages, repeats in (("D", c["benchmark_D_packages"], 3), ("S", c["benchmark_S_packages"], 1)):
        for package in packages:
            if time.monotonic() >= deadline or (Path(policy_receipt).parent/"stop_requests/__benchmark__.json").exists():
                raise RuntimeError("benchmark elapsed lease exhausted; no branch admitted")
            task = task_by_name(name_for(package, 3, mode, 0), prep)
            cold0, cold_cpu0 = time.monotonic(), time.process_time()
            beat(dict(status="context_loading", package_id=package, mode=mode))
            context = numerical_context(prep, task)
            cold, cold_cpu = time.monotonic()-cold0, time.process_time()-cold_cpu0
            descriptor = chunks(task)[0]
            reference = None
            if task["reuse"]:
                old_key = "deterministic_standardized" if mode == "D" else "stochastic_standardized"
                with np.load(Path(task["reuse"]["packet"])/"predictions.npz", allow_pickle=False) as packet:
                    reference = np.asarray(packet[old_key][:8])
            previous = None
            for repetition in range(repeats):
                if time.monotonic() >= deadline:
                    raise RuntimeError("benchmark cap exhausted; no branch admitted")
                usage0 = resource.getrusage(resource.RUSAGE_SELF)
                wall0, cpu0 = time.monotonic(), time.process_time()
                beat(dict(status="timing", mode=mode, package_id=package, repetition=repetition))
                prediction, truth, audit = predict(context, task, descriptor, beat)
                elapsed, cpu_seconds = time.monotonic()-wall0, time.process_time()-cpu0
                usage1 = resource.getrusage(resource.RUSAGE_SELF)
                replay = None
                if reference is not None:
                    if mode == "S":
                        if not np.array_equal(prediction, reference):
                            raise RuntimeError("original S benchmark replay is not bitwise exact")
                        replay = "bitwise_original_R149_rows"
                    else:
                        if not np.allclose(prediction, reference, atol=1e-12, rtol=1e-10):
                            raise RuntimeError("D benchmark replay exceeds frozen tolerance")
                        replay = "original_R149_rows_atol1e-12_rtol1e-10"
                if previous is not None and not np.array_equal(prediction, previous):
                    raise RuntimeError("warm arithmetic repeat changed bytes")
                previous = prediction.copy()
                serialize0, serialize_cpu0 = time.monotonic(), time.process_time()
                path = attempt/(mode+"_"+package+"_"+str(repetition)+".npz")
                # Retained temporary values support replay and measure serialization;
                # their AQL is deliberately never computed or used for branch choice.
                serialization_packet = retained_arrays(context, task, descriptor, prediction, truth, compute_loss=False)
                np.savez_compressed(path, **serialization_packet)
                packet_hash, packet_bytes = digest(path), path.stat().st_size
                serialize, serialize_cpu = time.monotonic()-serialize0, time.process_time()-serialize_cpu0
                path.unlink()
                rows.append(dict(mode=mode, package_id=package, p=task["p"], spec=task["spec"],
                    split=3, clock_offset_steps=0, origin_count=8, repetition=repetition,
                    cold_context_wall_seconds=cold if repetition == 0 else 0,
                    cold_context_cpu_seconds=cold_cpu if repetition == 0 else 0,
                    arithmetic_wall_seconds=elapsed, arithmetic_cpu_seconds=cpu_seconds,
                    serialization_wall_seconds=serialize, serialization_cpu_seconds=serialize_cpu,
                    temporary_prediction_sha256=packet_hash, compressed_bytes=packet_bytes,
                    peak_RSS_KiB=usage1.ru_maxrss, input_blocks=usage1.ru_inblock-usage0.ru_inblock,
                    output_blocks=usage1.ru_oublock-usage0.ru_oublock,
                    voluntary_context_switches=usage1.ru_nvcsw-usage0.ru_nvcsw,
                    involuntary_context_switches=usage1.ru_nivcsw-usage0.ru_nivcsw,
                    exact_or_tolerant_replay=replay, numerical_threadpools=kernel().numerical_threadpools(), sampler_audit=audit))
            del context
    if len(rows) != 18 or sum(r["mode"] == "D" for r in rows) != 15:
        raise RuntimeError("incomplete eighteen-call benchmark")
    elapsed = time.monotonic()-started
    if elapsed > c["benchmark_max_seconds"] or time.monotonic() >= deadline:
        raise RuntimeError("completed arithmetic exceeded benchmark elapsed admission")
    all_policies = {p["spec"]["feature_policy"] for p in c["packages"]}
    s_policies = {r["spec"]["feature_policy"] for r in rows if r["mode"] == "S"}
    coverage = all_policies.issubset(s_policies)
    share = min(1., .75*(time.process_time()-cpu_started)/elapsed)
    pricing = prospective_costs(prep["packages"], prep["tasks"], rows, prep["control"], prep["negative_control"],
        c["audit_key"], startup_cpu, share, c["cost_headroom"])
    b1, b2 = pricing["estimated_B1_max_cpu_seconds"], pricing["estimated_B2_max_cpu_seconds"]
    available_cpu = c["max_projected_cpu_seconds"]*share
    # Representative timing coverage and50% contingency are planning evidence,
    # not a proof that every omitted input family costs less. Missing direct S
    # family measurements are reported, rather than making B2 impossible by fiat.
    branch, disposition = select_branch(b1, b2, available_cpu)
    branch_record = dict(pricing, branch=branch,
        estimated_B1_max_cpu_seconds=b1, estimated_B2_max_cpu_seconds=b2,
        S_input_policy_coverage_complete=coverage, arithmetic_calls=18,
        missing_direct_S_feature_policies=sorted(all_policies-s_policies), budget_disposition=disposition,
        finite_three_wave_CPU_ceiling=c["max_projected_cpu_seconds"],
        benchmark_adjusted_available_CPU_seconds=available_cpu,
        rule=c["branch_policy"], source=prep["source"], preparation_sha256=digest(PREP/"preparation.json"),
        reason=("B2 representative envelope meets the <=1.5xB1 cost and finite idle-adjusted budget rule" if branch == "B2" else
                "B1 recommended default; B2 does not meet relative cost or finite idle-adjusted budget rule"),
        contingency_factor=c["cost_headroom"], statistical_confidence_bound=False,
        no_new_candidate_AQL_inspected=True, no_automatic_budget_expansion=True,
        resource_projection=dict(effective_cpu_share=(time.process_time()-cpu_started)/elapsed,
            conservative_idle_share=share,
            max_chunk_wall_seconds=max(v["estimated_max_chunk_wall_seconds"] for v in pricing["task_estimates"].values()),
            max_observed_chunk_wall_seconds=max(r["arithmetic_wall_seconds"]+r["serialization_wall_seconds"] for r in rows)))
    timing_record = dict(status="R150_18_TIMINGS_COMPLETE_NO_SELECTION_LOSS", rows=rows,
        elapsed_seconds=elapsed, process_CPU_seconds=time.process_time()-cpu_started,
        delivered_effective_cores=(time.process_time()-cpu_started)/elapsed,
        numerical_threadpools=kernel().numerical_threadpools(), new_model_fits=0,
        no_new_candidate_AQL_computed=True, forecast_paths=100, source=prep["source"])
    timing_record.update(worker_startup_CPU_seconds=startup_cpu,
        serialization_schema="actual standardized/EUR/identity packet with origin_AQL explicit zero placeholder; no candidate loss computed")
    write(attempt/"timings.json", timing_record)
    write(attempt/"branch.json", branch_record)
    write(attempt/"completed_evidence.json", dict(context=dict(source=prep["source"], preparation_sha256=digest(PREP/"preparation.json")),
        artifacts={p: digest(attempt/p) for p in ("timings.json", "branch.json")}))
    destination = OUT/"benchmark"
    if destination.exists():
        raise RuntimeError("existing benchmark requires strict verification")
    os.rename(attempt, destination)
    beat(dict(status="completed", arithmetic_calls=18, branch=branch))
    return branch_record


def imported_arrays(task):
    """Source-preserving view of one policy; no duplicated prediction packet."""
    old = original().load_npz_light(Path(task["reuse"]["packet"])/"predictions.npz")
    prefix = "deterministic" if task["mode"] == "D" else "stochastic"
    arrays = {k: old[k] for k in INT_KEYS | {"truth_standardized", "truth_eur"}}
    for suffix in ("standardized", "eur"):
        arrays["prediction_"+suffix] = old[prefix+"_"+suffix]
    arrays["origin_AQL"] = old[prefix+"_origin_AQL"]
    return arrays


def finalize():
    """Independent loss/units/cohort assessment, without any forecast engine."""
    prep = read_preparation()
    phase, names, terminal = manifest_state()
    if not terminal:
        raise RuntimeError("required admitted components incomplete: "+phase)
    verify_hashes(prep["source_sha256"])
    verify_hashes(prep["input_sha256"])
    verification = []
    for name in names:
        if not task_complete(name):
            raise RuntimeError("strict task completion failed: "+name)
        task = task_by_name(name, prep)
        arrays = imported_arrays(task) if task["reuse"] else read_npz(OUT/"tasks_done"/name/"predictions.npz")
        validate_arrays(task, arrays, read(task["scaler_path"]))
        calculated = metrics(arrays)
        recorded = validate_reuse(task) if task["reuse"] else read(OUT/"tasks_done"/name/"result.json")["metrics"]
        if any(not math.isclose(calculated[k], recorded[k], rel_tol=1e-11, abs_tol=1e-10) for k in calculated):
            raise RuntimeError("independently recomputed metric differs: "+name)
        verification.append(dict(name=name, imported=bool(task["reuse"]), metrics=calculated,
            scientific_identity_sha256=task["scientific_identity_sha256"], origin_clock_windows=len(arrays["origin_AQL"][1])))
    extra = read_decision("extra_seeds")
    confirmed = {}
    control = [component_loss(prep["control"], "S", seed) for seed in (0, 1, 2)] if extra["qualified"] else None
    for package in extra["qualified"]:
        candidate = [component_loss(package, "S", seed) for seed in (0, 1, 2)]
        confirmed[package] = dict(confirm_gains(control, candidate), control_AQL_by_seed=control,
                                 candidate_AQL_by_seed=candidate)
    eligible = [p for p in confirmed if confirmed[p]["eligible_for_AL_proposal"]]
    lead = strongest({p: -confirmed[p]["mean_gain"] for p in eligible}) if eligible else None
    if lead:
        package = next(p for p in prep["packages"] if p["package_id"] == lead)
        actual = next(p for p in prep["packages"] if p["package_id"] == prep["control"])
        cached_scale = package["candidate_id"] == actual["candidate_id"] and package["tau0"] == .00024929739307713865
        disposition = "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED"
        proposal = dict(package_id=lead, new_candidate_fits_if_exact_identity_reused=0 if cached_scale else 21,
            control_refits_authorized=False, forecast_components=18, paths=500,
            separately_benchmarked_and_budgeted_required=True, launched=False,
            stop_if_control_cache_identity_cannot_be_reused=True, default_iterations=300,
            operator="cdf_pool_clipped", same_package_Normal_driver_and_AL_receiver=True)
    else:
        disposition = "STOP_NO_QUALIFYING_CONFIRMED_LEAD" if not any(v["practical_gain"] for v in confirmed.values()) else "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED"
        proposal = None
    new_D = sum(task_by_name(n, prep)["mode"] == "D" and not task_by_name(n, prep)["reuse"] for n in names)
    new_S = sum(task_by_name(n, prep)["mode"] == "S" and not task_by_name(n, prep)["reuse"] for n in names)
    branch = read(OUT/"benchmark/branch.json")["branch"]
    c = read(CONFIG)
    if new_D > c["max_new_D_components"] or new_S > c["max_new_S_B1" if branch == "B1" else "max_new_S_B2"]:
        raise RuntimeError("finite branch component cap exceeded")
    result = dict(status="R150_COMPLETE_CACHED_DEVELOPMENT_NOT_PROMOTED", disposition=disposition,
        source=prep["source"], branch=branch, admitted_components=len(names), verified_components=len(verification),
        new_D_components=new_D, new_S_components=new_S, imported_components=sum(v["imported"] for v in verification),
        required_task_names=names, verification=verification,
        nominees=read_decision("nominees"), seed0_decision=extra, matched_three_seed_results=confirmed,
        conditional_AL_proposal=proposal, new_model_fits=0, posterior_updated=False, official_test_opened=False,
        independent_confirmation=False, automatic_followon_admitted=False,
        scope="retained-certified-Normal-full-inner-cohort-development; no global optimality or future-data uncertainty claim")
    immutable(OUT/"assessment.json", result)
    immutable(OUT/"assessment_seal.json", dict(assessment_sha256=digest(OUT/"assessment.json"), source=prep["source"]))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("prepare", "status", "advance", "finalize"):
        sub.add_parser(action)
    child = sub.add_parser("worker")
    child.add_argument("--task", "--name", dest="task", required=True)
    child.add_argument("--cpu", type=int, required=True)
    child.add_argument("--policy-receipt", type=Path, required=True)
    child.add_argument("--runtime", type=Path)
    args = parser.parse_args()
    if args.action == "prepare":
        prep = prepare()
        result = dict(source=prep["source"], potential_tasks=prep["potential_task_count"], imports=prep["imported_components"])
    elif args.action == "status":
        result = queue_state()
    elif args.action == "advance":
        result = advance()
    elif args.action == "finalize":
        result = finalize()
    else:
        result = worker(args.task, args.cpu, args.policy_receipt)
    print(json.dumps(result, sort_keys=True, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
