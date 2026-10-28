"""Future COST_ONLY worker; current environment/parity grants cannot run it.

This is a new orchestration adapter, not the historical Study.benchmark host
wrapper. Prediction, control replay, retained-array serialization mapping and
all-parent numerical preflight use unchanged hash/AST-pinned source functions.
No loss, selection or prefix admission is performed.
"""
from __future__ import annotations

import argparse
import ast
import builtins
import datetime as dt
import gc
import hashlib
from importlib import metadata
import json
import math
import os
from pathlib import Path
import platform
import resource
import signal
import sys
import time
from types import SimpleNamespace

from . import benchmark_plan as planning
from .environment import (THREAD_ENV, REFERENCE_NUMERICAL_ENV, require_compute,
    require_reference_profile, validate_reference_profile_record)
from .registry import SCHEMA as QUALIFICATION_SCHEMA
from .fixture import Resolver, SOURCE_PINS, digest, fingerprint, read_json, write_json
from .science import _assert_frozen_imports, _context, _load_module, _referenced_globals

WORKER_IMPORT_EPOCH = time.time()
WORKER_IMPORT_MONOTONIC = time.monotonic()
AUTHORITY_SCHEMA = "r156_hb_cost_only_authority_v1"
EXPECTED_CONTROLLER = "muscat.be.ucsc.edu"
EXPECTED_HOSTS = frozenset((EXPECTED_CONTROLLER, "jerez.be.ucsc.edu", "hb.ucsc.edu"))
EXECUTED_SOURCE_FILES = frozenset(("__init__.py", "benchmark.py", "benchmark_plan.py", "science.py", "fixture.py",
    "environment.py", "control.py", "registry.py", "cost_control.py"))
# Original497 imports these four names from the frozen R150 contract. The
# R149 fixture additionally has calendar arrays; those are a separate schema.
RETAINED_INT_KEYS = frozenset(("origin_positions", "clock_offsets", "stable_rng_origin_keys", "origin_timestamps_ns"))
FUNCTIONS = {
    "predict": dict(role="canonical502", ast_sha256="55a07c106f52b6a70ff0fffce5d6c98895498c8833e2deefa026880fbe19cd32",
        globals=["RuntimeError", "dict", "dt", "int", "producer", "str"]),
    "legacy_control_replay": dict(role="canonical502", ast_sha256="96ebb2c8a378d544a7198e88a2d704ed8375a91ab415203125137495f5361c12",
        globals=["CONFIG", "RuntimeError", "dict", "hashlib", "int", "next", "producer", "read"]),
    "retained_arrays": dict(role="canonical497", ast_sha256="853b4f7f17dde9efd59061e0710e44a8027be7ea2c64490a95562efe5a24ba96",
        globals=["INT_KEYS", "dict", "dt", "len", "round"]),
    "numeric_preflight": dict(role="canonical506", owner="Study", ast_sha256="333de5149119e04e1c8b7179a9a07ddd447aa33d6f685035e44d4dcb1b140f71",
        globals=["RuntimeError", "dict", "float", "len", "math", "max", "time"]),
}


class BenchmarkError(RuntimeError):
    pass


def _pin_json(pin):
    if not isinstance(pin, dict) or set(pin) != {"path", "sha256"} or digest(pin["path"]) != pin["sha256"]:
        raise BenchmarkError("missing or changed gate evidence pin")
    return planning.read_metadata(pin["path"])


def validate_authority(authority, plan, plan_sha, allocation, now=None):
    """Prospective receipt schema deliberately absent from current grants."""
    now = time.time() if now is None else now
    if (authority.get("schema") != AUTHORITY_SCHEMA or authority.get("status") != "ADMITTED_COST_ONLY"
            or authority.get("issuer") != EXPECTED_CONTROLLER or authority.get("controller") != EXPECTED_CONTROLLER
            or authority.get("role") != plan["study"] + "_COST_ONLY_BENCHMARK"
            or authority.get("plan_sha256") != plan_sha or authority.get("study") != plan["study"]
            or authority.get("scope_id") != plan["claim"]["planned_attempt_id"]
            or authority.get("scientific_exclusion_key") != plan["claim"]["scientific_exclusion_key"]
            or authority.get("slurm_job_id") != allocation["job_id"] or authority.get("node") != allocation["node"]
            or authority.get("resources") != planning.LIMITS
            or authority.get("reference_numerical_environment") != REFERENCE_NUMERICAL_ENV
            or authority.get("full_prefix_admitted") is not False or authority.get("automatic_retry") is not False):
        raise BenchmarkError("new region-specific COST_ONLY authority required; environment/parity grants are insufficient")
    start, expiry = authority.get("started_epoch"), authority.get("expires_epoch")
    if (type(start) not in (int, float) or type(expiry) not in (int, float) or not math.isfinite(start)
            or not math.isfinite(expiry) or not start <= now < expiry or not 0 < expiry - start <= 1200
            or type(authority.get("memory_mib")) is not int or authority["memory_mib"] <= 0):
        raise BenchmarkError("finite current CPU/wall/memory admission required")
    executed = authority.get("executed_sources")
    if (not isinstance(executed, dict) or set(executed) != EXECUTED_SOURCE_FILES
            or any(digest(Path(__file__).with_name(name)) != sha for name, sha in executed.items())):
        raise BenchmarkError("entire reviewed cost execution source closure required")
    review = _pin_json(authority.get("adapter_review"))
    if (review.get("schema") != "r156_hb_cost_adapter_review_v1" or review.get("status") != "REVIEWED_TESTED_COST_ONLY"
            or review.get("issuer") != EXPECTED_CONTROLLER or review.get("controller_sources") != executed
            or review.get("plan_sha256") != plan_sha
            or review.get("adapter_sources") != plan.get("adapter_feasibility", {}).get("adapter_sources")
            or review.get("tests_passed") is not True or review.get("no_AQL") is not True
            or review.get("no_selection") is not True or review.get("full_prefix_admitted") is not False):
        raise BenchmarkError("pinned approved Muscat issuer and execution-source review required")
    runtime = _pin_json(authority.get("runtime_result"))
    if runtime.get("status") != "verified" or not runtime.get("threadpoolctl") or any(p.get("num_threads") != 1 for p in runtime["threadpoolctl"]):
        raise BenchmarkError("sealed actual Python/native one-thread runtime verification required")
    parity = _pin_json(authority.get("parity_result"))
    parity_seal = _pin_json(authority.get("parity_seal"))
    parity_pin = authority["parity_result"]
    if (parity.get("status") != "PASS_TEST_FORECAST_PARITY" or parity.get("accepted") is not True
            or parity.get("execution", {}).get("namespace") != "TEST"
            or parity["execution"].get("fixture_manifest_sha256") != authority.get("accepted_parity_fixture_manifest_sha256")
            or parity_seal.get("status") != "COMPLETE_TEST_ONLY"
            or parity_seal.get("artifacts", {}).get(Path(parity_pin["path"]).name) != parity_pin["sha256"]):
        raise BenchmarkError("sealed accepted whole-chunk scientific parity required")
    parity_runtime = _pin_json(authority.get("parity_runtime_result"))
    qualification = _pin_json(authority.get("parity_qualification_seal"))
    if (parity_runtime.get("status") != "verified" or parity_runtime.get("python_version") != runtime.get("python_version")
            or parity_runtime.get("executable") != runtime.get("executable")
            or parity_runtime.get("versions") != runtime.get("versions")
            or qualification.get("schema") != QUALIFICATION_SCHEMA or qualification.get("application_passed") is not True
            or qualification.get("files", {}).get("environment-runtime.json") != authority["parity_runtime_result"]["sha256"]
            or qualification.get("files", {}).get("TEST/parity/parity.json") != authority["parity_result"]["sha256"]
            or not qualification.get("job_id") or qualification["job_id"] != parity["execution"].get("slurm_job_id")
            or qualification["job_id"] != parity_runtime.get("allocation", {}).get("job_id")):
        raise BenchmarkError("accepted parity must bind its exact reference-profile runtime and qualification seal")
    try:
        validate_reference_profile_record(parity_runtime.get("reference_numerical_profile", {}))
    except (RuntimeError, TypeError, AttributeError) as error:
        raise BenchmarkError("accepted parity reference numerical profile is missing or invalid") from error
    native = parity_runtime.get("native_library_sha256")
    if (not isinstance(native, dict) or len(native) != 2
            or any(not isinstance(path, str) or not Path(path).is_absolute() or not isinstance(sha, str)
                or len(sha) != 64 or any(char not in "0123456789abcdef" for char in sha) for path, sha in native.items())):
        raise BenchmarkError("accepted parity must pin both actually loaded OpenBLAS library hashes")
    ee = _pin_json(authority.get("EE_completion_receipt"))
    required = ee.get("required_task_names", [])
    if (ee.get("status") != "COMPLETE_EE_DISPOSITION_DELIVERED_DRAINED" or len(required) != 12
            or len(required) != len(set(required)) or ee.get("completed_task_names") != required
            or ee.get("assessment_accepted") is not True):
        raise BenchmarkError("complete accepted EE disposition and delivery required")
    assessment = _pin_json(ee.get("scientific_assessment"))
    qualified = assessment.get("qualified_from_unchanged_initial_S0")
    valid_qualified = qualified in (["r134_5c42f007409acfb3"], ["r134_984fd326bd5fd13e"])
    expected_names = ["EE_{}_s{}_S_seed{}".format(package, split, seed)
        for package in (["C0"] + qualified if valid_qualified else [])
        for seed in (1, 2) for split in (1, 2, 3)]
    if (assessment.get("status") != "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED"
            or assessment.get("required_task_names") != required or required != expected_names
            or assessment.get("disposition") not in ("STOP_NO_QUALIFYING_CONFIRMED_LEAD", "HOLD_ALGORITHMIC_STABILITY_UNRESOLVED",
                "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED")
            or assessment.get("all_new_components_independently_revalidated") is not True
            or assessment.get("AL_proposal_admitted") is not False or assessment.get("automatic_followon") is not False
            or assessment.get("new_fits") != 0 or assessment.get("official_origins") != 0):
        raise BenchmarkError("EE receipt does not bind the complete matched assessment")
    delivery = ee.get("delivered_report")
    if not isinstance(delivery, dict) or set(delivery) != {"path", "sha256"} or digest(delivery["path"]) != delivery["sha256"]:
        raise BenchmarkError("pinned EE delivered report required")
    drain = _pin_json(ee.get("physical_drain"))
    if (drain.get("status") != "DRAINED" or drain.get("live_worker_pids") != [] or drain.get("live_job_ids") != []
            or drain.get("active_scientific_claims") != [] or type(drain.get("observed_epoch")) not in (int, float)
            or not 0 <= now - drain["observed_epoch"] <= 300):
        raise BenchmarkError("fresh physical EE drain proof required")
    claim = _pin_json(authority.get("cross_server_claim"))
    if (claim.get("schema") != "r156_hb_cross_server_cost_claim_v1" or claim.get("status") != "EXCLUSIVE_CLAIMED"
            or claim.get("controller") != EXPECTED_CONTROLLER or claim.get("study") != plan["study"]
            or claim.get("region") != plan["region"] or claim.get("plan_sha256") != plan_sha
            or set(claim.get("all_hosts", [])) != EXPECTED_HOSTS
            or claim.get("scope_id") != authority["scope_id"] or claim.get("slurm_job_id") != allocation["job_id"]
            or claim.get("scientific_exclusion_key") != plan["claim"]["scientific_exclusion_key"]
            or claim.get("overlapping_live_claims") != [] or claim.get("all_hosts_observed") is not True
            or type(claim.get("observed_epoch")) not in (int, float) or not 0 <= now - claim["observed_epoch"] <= 300):
        raise BenchmarkError("fresh cross-server exclusive claim required")
    return dict(runtime=runtime, parity=parity, parity_runtime=parity_runtime, EE=ee, drain=drain, claim=claim)


def validate_actual_runtime(runtime):
    if (platform.python_version() != runtime.get("python_version")
            or not isinstance(runtime.get("versions"), dict)
            or {name: metadata.version(name) for name in runtime["versions"]} != runtime["versions"]):
        raise BenchmarkError("actual Python/package versions differ from the accepted runtime seal")


def aggregate_cpu_seconds():
    children = resource.getrusage(resource.RUSAGE_CHILDREN)
    return time.process_time() + children.ru_utime + children.ru_stime


class Budget:
    def __init__(self, authority, wall=time.monotonic, cpu=None):
        self.wall, self.cpu = wall, aggregate_cpu_seconds if cpu is None else cpu
        self.deadline = min(WORKER_IMPORT_MONOTONIC + 1200, wall() + authority["expires_epoch"] - time.time())
        self.receipt = dict(lease_expires_epoch=authority["expires_epoch"])

    def check(self):
        # Absolute process CPU includes interpreter/import/startup work.
        if self.wall() >= self.deadline or self.cpu() >= 1200:
            raise BenchmarkError("whole cost-panel1200CPU/1200wall cap exhausted; no admission or retry")


def install_hard_limits(budget):
    """Standalone worker only; external Slurm cgroups/timeout remain required."""
    remaining = budget.deadline - time.monotonic()
    if remaining <= 0:
        raise BenchmarkError("cost-panel wall allowance already exhausted")
    old_soft, old_hard = resource.getrlimit(resource.RLIMIT_CPU)
    cap = min(1200, old_hard) if old_hard != resource.RLIM_INFINITY else 1200
    soft = min(cap, old_soft) if old_soft != resource.RLIM_INFINITY else cap
    resource.setrlimit(resource.RLIMIT_CPU, (soft, cap))
    def exhausted(signum, frame):
        raise BenchmarkError("hard cost-panel wall/CPU backstop reached")
    signal.signal(signal.SIGALRM, exhausted)
    signal.signal(signal.SIGXCPU, exhausted)
    signal.setitimer(signal.ITIMER_REAL, remaining)


def extract_original(name, resolver, bindings):
    """Exact single function AST in a private reviewed dependency namespace."""
    record = FUNCTIONS[name]
    logical, source_sha = SOURCE_PINS[record["role"]]
    path = resolver.path(logical)
    if digest(path) != source_sha:
        raise BenchmarkError("frozen cost-panel source changed")
    source = path.read_text()
    tree = ast.parse(source, filename=str(path))
    body = tree.body
    if record.get("owner"):
        owners = [n for n in body if isinstance(n, ast.ClassDef) and n.name == record["owner"]]
        body = owners[0].body if len(owners) == 1 else []
    matches = [n for n in body if isinstance(n, ast.FunctionDef) and n.name == name]
    if len(matches) != 1 or matches[0].decorator_list:
        raise BenchmarkError("one undecorated canonical cost-panel function required")
    node = matches[0]
    if hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest() != record["ast_sha256"]:
        raise BenchmarkError("frozen cost-panel AST differs")
    # Original retained_arrays has the sole literal default True. No default
    # expression or annotation is allowed to execute while defining a bridge.
    if (node.returns is not None or any(arg.annotation is not None for arg in node.args.args)
            or any(not isinstance(value, ast.Constant) or type(value.value) not in (bool, type(None)) for value in node.args.defaults)
            or node.args.kw_defaults):
        raise BenchmarkError("unsupported executable cost-panel signature")
    import symtable
    symbols = symtable.symtable(ast.get_source_segment(source, node), str(path), "exec").get_children()[0]
    if _referenced_globals(symbols) != set(record["globals"]) or set(bindings) != set(record["globals"]):
        raise BenchmarkError("cost-panel global allowlist differs")
    builtin_bindings = {key: value for key, value in bindings.items() if key in vars(builtins)}
    namespace = dict(bindings, __builtins__={**builtin_bindings, "__import__": builtins.__import__})
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), "exec"), namespace)
    return namespace[name]


def load_staged(plan, root):
    assets = {path: dict(entry, path=entry["staged_relative_path"]) for path, entry in plan["input_allowlist"].items()}
    if any(entry["bytes"] is None for entry in assets.values()):
        raise BenchmarkError("complete staged source/parent/bank inventory required")
    resolver = Resolver(root, dict(assets=assets))
    resolver.verify_all()
    prep_pin = plan["canonical_preparation"]
    prep = planning.read_metadata(resolver.path(prep_pin["path"]))
    if digest(resolver.path(prep_pin["path"])) != prep_pin["sha256"] or prep["source"] != prep_pin["source"]:
        raise BenchmarkError("staged original preparation identity changed")
    config_pin = plan["canonical_config"]
    config = planning.read_metadata(resolver.path(config_pin["path"]))
    planning.validate_metadata(plan["study"], config, prep)
    if planning.make_schedule(plan["study"], config, prep) != plan["schedule"] or planning.make_preflight(prep) != plan["all_parent_preflight"]:
        raise BenchmarkError("staged canonical schedule/all-parent coverage changed")
    for ledger in (prep["source_sha256"], prep["input_sha256"]):
        if any(path not in assets or assets[path]["sha256"] != sha for path, sha in ledger.items()):
            raise BenchmarkError("an original input/source ledger member was omitted")
    return prep, config, resolver


def frozen_adapter(plan, prep, config, resolver, budget, expected_native_library_sha256):
    """Imports occur only after the new authority and every staged hash pass."""
    actual_profile = require_reference_profile(expected_native_library_sha256)
    _assert_frozen_imports(resolver)
    core = _load_module("_pricefm_hb_cost_r134", resolver.path(SOURCE_PINS["core"][0]))
    kernel = _load_module("_pricefm_hb_cost_r148", resolver.path(SOURCE_PINS["kernel"][0]))
    tasks = {task["name"]: task for task in prep["tasks"]}
    def context(task):
        budget.check()
        mapped = dict(task=task, dependency_root=prep["dependency"], size=dict(normal_dimension=task["p"]))
        result = _context(mapped, resolver, core, kernel)
        budget.check()
        return result
    producer = SimpleNamespace(kernel=lambda: kernel, numerical_context=lambda preparation, task: context(task))
    shared = dict(dt=dt, producer=lambda: producer, CONFIG=plan["canonical_config"]["path"],
        read=lambda logical: planning.read_metadata(resolver.path(logical)), hashlib=hashlib, INT_KEYS=RETAINED_INT_KEYS, math=math, time=time)
    def bind(name):
        return extract_original(name, resolver, {key: vars(builtins)[key] if key in vars(builtins) else shared[key] for key in FUNCTIONS[name]["globals"]})
    predict, replay, retained, numeric = (bind(name) for name in ("predict", "legacy_control_replay", "retained_arrays", "numeric_preflight"))
    self = SimpleNamespace(producer=lambda: producer,
        name_for=lambda package, split, mode, seed: config["region"] + "_" + package + "_s" + str(split) + "_" + mode + "_seed" + str(seed),
        task_by_name=lambda name, preparation: tasks[name])
    def preflight(preparation, receipt, beat):
        return numeric(self, preparation, receipt, beat)
    def cleanup(value):
        value.clear()
        gc.collect()
        budget.check()
    return SimpleNamespace(context=context, predict=predict, control_replay=replay, retained_arrays=retained,
        preflight=preflight, pools=kernel.numerical_threadpools, cleanup=cleanup, reference_numerical_profile=actual_profile)


def timing_panel(plan, prep, adapter, budget, output, serializer, array_equal, wall=time.monotonic, cpu=time.process_time):
    """Testable orchestration: exact schedule and no metric/selection callable."""
    budget.check()
    events, rows, calls = [], [], []
    def beat(event):
        budget.check()
        events.append(event)
    preflight = adapter.preflight(prep, budget.receipt, beat)
    if preflight.get("parents") != planning.COUNTS[plan["study"]]["parents"]:
        raise BenchmarkError("all-parent numerical preflight incomplete")
    tasks = {task["name"]: task for task in prep["tasks"]}
    context = None
    previous = None
    group = None
    cold_wall = cold_cpu = cleanup_wall = cleanup_cpu = 0.0
    index = 0
    try:
        while index < len(plan["schedule"]):
            call = plan["schedule"][index]
            if call["kind"] != "timed_prediction":
                raise BenchmarkError("control replay is not adjacent to its first C0 timed call")
            task = tasks[call["task"]]
            if fingerprint(task) != call["task_sha256"]:
                raise BenchmarkError("timed task scientific identity differs")
            budget.check()
            if group != call["context_id"]:
                if context is not None:
                    w0, c0 = wall(), cpu()
                    adapter.cleanup(context)
                    cleanup_wall += wall() - w0
                    cleanup_cpu += cpu() - c0
                context = None
                previous = None
                w0, c0 = wall(), cpu()
                context = adapter.context(task)
                cold_wall, cold_cpu = wall() - w0, cpu() - c0
                group = call["context_id"]
            w0, c0 = wall(), cpu()
            prediction, truth, audit = adapter.predict(context, task, call["descriptor"], beat)
            arithmetic_wall, arithmetic_cpu = wall() - w0, cpu() - c0
            calls.append(dict(sequence=call["sequence"], kind=call["kind"], task=call["task"]))
            budget.check()
            replay = None
            replay_wall = replay_cpu = 0.0
            if index + 1 < len(plan["schedule"]) and plan["schedule"][index + 1]["kind"] == "control_replay":
                next_call = plan["schedule"][index + 1]
                if call["package_id"] != "C0" or call["repetition"] != 0 or next_call["reference_to_prediction_sequence"] != call["sequence"]:
                    raise BenchmarkError("original first-C0 replay identity differs")
                w0, c0 = wall(), cpu()
                replay = adapter.control_replay(context, task, call["descriptor"], prediction, truth)
                replay_wall, replay_cpu = wall() - w0, cpu() - c0
                calls.append(dict(sequence=next_call["sequence"], kind=next_call["kind"], task=call["task"]))
                index += 1
                budget.check()
            if previous is not None and not array_equal(prediction, previous):
                raise BenchmarkError("warm arithmetic repeat changed; complete panel failed")
            previous = prediction.copy()
            w0, c0 = wall(), cpu()
            path = Path(output) / call["serialization"]["retained_packet"]
            arrays = adapter.retained_arrays(context, task, call["descriptor"], prediction, truth, compute_loss=False)
            serializer(path, arrays)
            packet_sha, packet_bytes = digest(path), path.stat().st_size
            rows.append(dict(mode=call["mode"], package_id=call["package_id"], p=task["p"], spec=task["spec"], split=3,
                clock_offset_steps=0, origin_count=8, repetition=call["repetition"],
                cold_context_wall_seconds=cold_wall if call["repetition"] == 0 else 0.0,
                cold_context_cpu_seconds=cold_cpu if call["repetition"] == 0 else 0.0,
                arithmetic_wall_seconds=arithmetic_wall, arithmetic_cpu_seconds=arithmetic_cpu,
                serialization_wall_seconds=wall() - w0, serialization_cpu_seconds=cpu() - c0,
                control_replay_wall_seconds=replay_wall, control_replay_cpu_seconds=replay_cpu,
                retained_prediction_packet=path.name, retained_prediction_sha256=packet_sha, compressed_bytes=packet_bytes,
                numerical_threadpools=adapter.pools(), sampler_audit=audit, original_control_replay=replay))
            budget.check()
            index += 1
    finally:
        if context is not None:
            w0, c0 = wall(), cpu()
            adapter.cleanup(context)
            cleanup_wall += wall() - w0
            cleanup_cpu += cpu() - c0
    if len(rows) != 16 or len(calls) != 18 or [call["sequence"] for call in calls] != list(range(1, 19)):
        raise BenchmarkError("incomplete fixed18-call panel")
    budget.check()
    return dict(status="COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION", rows=rows,
        arithmetic_calls=18, timed_prediction_calls=16, untimed_control_replay_prediction_calls=2, calls=calls,
        numerical_preflight=preflight, explicit_cleanup_wall_seconds=cleanup_wall, explicit_cleanup_cpu_seconds=cleanup_cpu,
        events=events, no_new_candidate_AQL_computed=True, no_scientific_selection=True,
        full_prefix_admitted=False, prefix_pricing_performed=False, automatic_retry=False, new_model_fits=0,
        official_origins=0, forecast_paths=100,
        serialization_schema="original497 retained standardized/EUR/identity NPZ with zero origin_AQL; compute_loss=False")


def run_benchmark(plan_path, authority_path, authority_sha256, stage_root, output_dir):
    allocation = require_compute()
    if any(os.environ.get(key) != value for key, value in THREAD_ENV.items()):
        raise BenchmarkError("all numerical thread controls must be one before imports")
    if any(os.environ.get(key) != value for key, value in REFERENCE_NUMERICAL_ENV.items()):
        raise BenchmarkError("the accepted original numerical environment is required before imports")
    planning.dry_run(plan_path)
    plan = planning.read_metadata(plan_path)
    for name, expected in plan["adapter_feasibility"]["adapter_sources"].items():
        if Path(name).name != name or digest(Path(__file__).with_name(name)) != expected:
            raise BenchmarkError("reviewed cost-panel adapter source changed")
    if digest(authority_path) != authority_sha256:
        raise BenchmarkError("explicit prospective authority SHA256 differs")
    authority = planning.read_metadata(authority_path)
    gate = validate_authority(authority, plan, digest(plan_path), allocation)
    validate_actual_runtime(gate["parity_runtime"])
    budget = Budget(authority)
    budget.check()
    output = Path(output_dir).resolve()
    if "BENCHMARK_TEST" not in output.parts or any(p in ("tasks_done", "checkpoints", "training_banks") for p in output.parts):
        raise BenchmarkError("fresh separate BENCHMARK_TEST namespace required")
    if output.name != authority["scope_id"]:
        raise BenchmarkError("output namespace must bind the one prospective attempt")
    output.mkdir(parents=True, exist_ok=False)
    install_hard_limits(budget)
    identity = dict(scope_id=authority["scope_id"], study=plan["study"], role=authority["role"], allocation=allocation,
        authority_sha256=authority_sha256, plan_sha256=digest(plan_path), source=plan["canonical_preparation"]["source"],
        preparation_sha256=plan["canonical_preparation"]["sha256"], scientific_exclusion_key=plan["claim"]["scientific_exclusion_key"],
        namespace="BENCHMARK_TEST", worker_import_epoch=WORKER_IMPORT_EPOCH, full_prefix_admitted=False)
    write_json(output / "execution_identity.json", identity)
    try:
        prep, config, resolver = load_staged(plan, stage_root)
        budget.check()
        adapter = frozen_adapter(plan, prep, config, resolver, budget, gate["parity_runtime"]["native_library_sha256"])
        import numpy as np
        result = timing_panel(plan, prep, adapter, budget, output,
            lambda path, arrays: np.savez_compressed(path, **arrays), np.array_equal)
        _assert_frozen_imports(resolver)
        result.update(execution=identity, process_CPU_seconds=time.process_time(),
            aggregate_CPU_seconds=aggregate_cpu_seconds(),
            elapsed_seconds=time.monotonic() - WORKER_IMPORT_MONOTONIC,
            peak_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            source_functions=FUNCTIONS, adapter_executed_historical_Study_benchmark=False,
            adapter_patched_frozen_module_globals=False, gate_evidence=authority,
            actual_reference_numerical_profile=adapter.reference_numerical_profile,
            final_accounting_authority="external Slurm/supervisor exit accounting includes final record/seal costs")
        write_json(output / "timings.json", result)
        budget.check()
        write_json(output / "completed_evidence.json", dict(status="COMPLETE_COST_PANEL_ONLY_NO_SCIENCE_ADMISSION", execution=identity,
            artifacts={str(path.relative_to(output)): digest(path) for path in sorted(output.rglob("*")) if path.is_file()}))
        return result
    except BaseException as error:
        write_json(output / "failure.json", dict(status="FAILED_COST_PANEL_NO_ADMISSION_NO_RETRY", execution=identity,
            error_type=type(error).__name__, error=str(error), process_CPU_seconds=time.process_time(),
            aggregate_CPU_seconds=aggregate_cpu_seconds(),
            elapsed_seconds=time.monotonic() - WORKER_IMPORT_MONOTONIC))
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--authority", required=True)
    parser.add_argument("--authority-sha256", required=True)
    parser.add_argument("--stage-root", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args(argv)
    result = run_benchmark(args.plan, args.authority, args.authority_sha256, args.stage_root, args.output_dir)
    print(result["status"])


if __name__ == "__main__":
    main()
