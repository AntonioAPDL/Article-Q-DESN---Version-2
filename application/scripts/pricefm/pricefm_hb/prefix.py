"""Source-bound FI/DK2 cached-Normal component execution and scientific DAG.

Importing this module uses the standard library only. The original 502 predict,
497 retained arrays and 506 nomination/pricing functions execute unchanged in
private hash/AST-pinned namespaces. Historical host wrappers are never patched.
No model fitting, official origins, promotion or automatic follow-on is admitted.
"""
from __future__ import annotations

import argparse
import ast
import builtins
import datetime as dt
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import signal
import symtable
import time
from types import SimpleNamespace

from . import benchmark as b, benchmark_plan as bp, registry as r
from .environment import THREAD_ENV, REFERENCE_NUMERICAL_ENV, require_compute
from .fixture import SOURCE_PINS
from .science import _referenced_globals, _assert_frozen_imports

SCHEMA = "r157_hb_cached_normal_prefix_plan_v1"
AUTHORITY_SCHEMA = "r157_hb_cached_normal_component_authority_v1"
RESULT_SCHEMA = "r157_hb_cached_normal_component_result_v1"
ASSESSMENT_SCHEMA = "r157_hb_cached_normal_assessment_v1"
OWNER = "muscat.be.ucsc.edu"
NUMERICAL_CPU_CEILING = 32400
ASSESSMENT_CPU_CEILING = 1800
MAX_WAVES = 3
WAVE_LEASE = 7200
WAVE_DISPATCH = 5400
CONTRACT_PATH = str(Path(SOURCE_PINS["canonical497"][0]).with_name("pricefm_r150_contract.py"))
CONTRACT_SHA = "ee0f3767747ddca85c91d0f84b62ccf62cad93361527a714de0e0b6ae795393f"
SOURCE_FILES = ("__init__.py", "prefix.py", "prefix_control.py", "benchmark.py", "benchmark_plan.py",
    "science.py", "fixture.py", "environment.py", "control.py", "registry.py", "cost_control.py",
    "activation.py", "handoff.py", "policy.py", "lifecycle.py", "admission.py",
    "readiness.py", "operation_budget.py", "metered_io.py")
FUNCTIONS = {
    "task_identity": ("canonical497", None, "5d8bdbf9bb22edfc2be4e5b20adebb51e90c7ad6081884b405ccabdebb75a2a7", []),
    "context_identity": ("canonical497", None, "35ec3865d97552c7a2d23ceba74873d4dae7ca265d039fa49bac1e63e3cb28c1", ["dict", "fingerprint"]),
    "chunks": ("canonical497", None, "ad073d4ada20bbd9cdd29a3184898e8c6fbeccd63109bf31ee023ce897545bfc", ["dict", "len", "range", "str"]),
    "choose_nominees": ("canonical506", "Study", "23f5aa9f6458a21b5922cd6b33201491d89ae5cbae038a9455e40b5c78d9ad6a", ["ValueError", "any", "dict", "math", "set"]),
    "prefix_contract": ("canonical506", "Study", "f63b28a54b3bea660469c3cb31bb1138c91590302b43d44c8e7112b22fc9932c", ["dict", "max", "read", "sum"]),
    "extra_admission": ("canonical506", "Study", "43b89c8fdd8d736f36bc1d253affec61789635a7a79289657eb43c88368a8a1e", ["ValueError", "dict", "list", "math", "max", "min", "sum"]),
}


class PrefixError(ValueError):
    pass


def finite(value, *, positive=False):
    return type(value) in (int, float) and math.isfinite(value) and (value > 0 if positive else value >= 0)


def load_contract(resolver=None):
    path = resolver.path(CONTRACT_PATH) if resolver is not None else Path(CONTRACT_PATH)
    if r.digest(path) != CONTRACT_SHA:
        raise PrefixError("original stdlib scientific contract differs")
    spec = importlib.util.spec_from_file_location("_pricefm_hb_prefix_contract", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def original(name, *, resolver=None, config=None):
    role, owner, ast_sha, globals_ = FUNCTIONS[name]
    logical, source_sha = SOURCE_PINS[role]
    path = resolver.path(logical) if resolver is not None else Path(logical)
    if r.digest(path) != source_sha:
        raise PrefixError("original component source differs")
    source = path.read_text(); tree = ast.parse(source); body = tree.body
    if owner:
        candidates = [n for n in body if isinstance(n, ast.ClassDef) and n.name == owner]
        body = candidates[0].body if len(candidates) == 1 else []
    found = [n for n in body if isinstance(n, ast.FunctionDef) and n.name == name]
    if len(found) != 1 or found[0].decorator_list:
        raise PrefixError("one original undecorated function required")
    node = found[0]
    if hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest() != ast_sha:
        raise PrefixError("original component AST differs")
    if node.returns is not None or any(a.annotation is not None for a in node.args.args):
        raise PrefixError("executable annotations forbidden")
    if any(not isinstance(v, ast.Constant) or v.value is not None for v in node.args.defaults) or node.args.kw_defaults:
        raise PrefixError("executable default forbidden")
    table = symtable.symtable(ast.get_source_segment(source, node), str(path), "exec").get_children()[0]
    if _referenced_globals(table) != set(globals_):
        raise PrefixError("original component global surface differs")
    shared = {"math": math, "fingerprint": r.identity, "read": lambda path: config}
    bindings = {key: vars(builtins)[key] if key in vars(builtins) else shared[key] for key in globals_}
    namespace = {**bindings, "__builtins__": {key: value for key, value in bindings.items() if key in vars(builtins)}}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), "exec"), namespace)
    return namespace[name]


def metadata(cost_plan):
    """Read pinned original JSON only; never an array payload."""
    pin = cost_plan["canonical_preparation"]
    if r.digest(pin["path"]) != pin["sha256"]:
        raise PrefixError("original preparation changed")
    prep = bp.read_metadata(pin["path"])
    cp = cost_plan["canonical_config"]
    if r.digest(cp["path"]) != cp["sha256"]:
        raise PrefixError("original regional config changed")
    config = bp.read_metadata(cp["path"])
    bp.validate_metadata(cost_plan["study"], config, prep)
    return prep, config


def names_for(prep, packages, mode, seeds):
    mapping = {(t["package_id"], t["split"], t["mode"], t["seed_index"]): t["name"] for t in prep["tasks"]}
    return [mapping[p, split, mode, seed] for p in packages for seed in seeds for split in (1, 2, 3)]


def science_adapter(prep, config, resolver=None):
    contract = load_contract(resolver)
    choose = original("choose_nominees", resolver=resolver)
    adapter = SimpleNamespace(producer=lambda: contract, CONFIG="PINNED_ORIGINAL_CONFIG",
        names_for=lambda packages, mode, seeds: names_for(prep, packages, mode, seeds))
    adapter.choose_nominees = lambda packages, losses, control, key: choose(adapter, packages, losses, control, key)
    return adapter, contract


def price_prefix(cost_plan, timing, *, preparation=None, configuration=None, resolver=None):
    """Loss-blind original prospective pricing, with headroom applied once."""
    prep, config = metadata(cost_plan) if preparation is None else (preparation, configuration)
    bp.validate_metadata(cost_plan["study"], config, prep)
    if timing.get("status") != "COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION":
        raise PrefixError("complete independent regional cost panel required")
    if (timing.get("arithmetic_calls") != 18 or len(timing.get("rows", [])) != 16
            or timing.get("no_new_candidate_AQL_computed") is not True
            or timing.get("no_scientific_selection") is not True
            or timing.get("new_model_fits") != 0 or timing.get("official_origins") != 0):
        raise PrefixError("partial or scientifically expanded cost result")
    expected = [(c["mode"], c["package_id"], c["repetition"], c["p"]) for c in cost_plan["schedule"] if c["kind"] == "timed_prediction"]
    actual = [(v.get("mode"), v.get("package_id"), v.get("repetition"), v.get("p")) for v in timing["rows"]]
    if actual != expected or timing.get("numerical_preflight", {}).get("parents") != bp.COUNTS[cost_plan["study"]]["parents"]:
        raise PrefixError("regional cost schedule/parent coverage differs")
    cpu, wall = timing.get("aggregate_CPU_seconds"), timing.get("elapsed_seconds")
    startup = timing.get("startup_cpu_seconds")
    if not finite(cpu, positive=True) or not finite(wall, positive=True) or not finite(startup):
        raise PrefixError("measured full-panel CPU/wall and explicit startup CPU required")
    if startup > cpu or cpu > 1200 or wall > 1200:
        raise PrefixError("cost CPU/wall outside complete finite panel")
    for row in timing["rows"]:
        if any(not finite(row.get(k)) for k in ("cold_context_cpu_seconds", "arithmetic_cpu_seconds", "serialization_cpu_seconds")):
            raise PrefixError("invalid measured task cost")
        if row.get("origin_count") != 8 or row.get("split") != 3 or row.get("clock_offset_steps") != 0:
            raise PrefixError("complete original eight-origin midnight cost cases required")
    share = min(1.0, .75 * cpu / wall)
    adapter, contract = science_adapter(prep, config, resolver)
    estimates = contract.prospective_costs(prep["packages"], prep["tasks"], timing["rows"], prep["control"],
        prep["control"], config["audit_key"], startup, share, 1.5)["task_estimates"]
    priced = original("prefix_contract", config=config, resolver=resolver)(adapter, prep, estimates, NUMERICAL_CPU_CEILING * share)
    rounded={name:math.ceil(v['estimated_cpu_seconds']) for name,v in estimates.items()}
    rounded_d=sum(rounded[n] for n in names_for(prep,[v['package_id'] for v in prep['packages']],'D',[0]))
    rounded_s0=max(sum(rounded[n] for n in names_for(prep,[prep['control'],v['A'],v['B']],'S',[0]))
        for v in priced['all_prospective_seed0_scenarios'])
    rounded_replacement=max(rounded.values())
    rounded_total=rounded_d+rounded_s0+rounded_replacement
    priced.update(original_continuous_prefix_admitted=priced['prefix_admitted'],
        rounded_task_CPU_reservations=rounded,rounded_replacement_CPU_reservation=rounded_replacement,
        rounded_complete_prefix_CPU_reservation=rounded_total,
        prefix_admitted=priced['prefix_admitted'] and rounded_total<=priced['benchmark_adjusted_available_CPU_seconds'])
    all_ids = [v["package_id"] for v in prep["packages"]]
    scenarios = []
    for a in all_ids:
        if a == prep["control"]: continue
        fake = {p: 2.0 for p in all_ids}; fake[a] = 1.0
        rule = adapter.choose_nominees(prep["packages"], fake, prep["control"], config["audit_key"])
        for qualified in ([a], [rule["B"]], [a, rule["B"]]):
            names = names_for(prep, [prep["control"]] + qualified, "S", [1, 2])
            scenarios.append({"A": a, "B": rule["B"], "qualified": qualified,
                "extra_components": names, "CPU_seconds": sum(estimates[n]["estimated_cpu_seconds"] for n in names)})
    return {**priced, "task_estimates": estimates, "prospective_extra_scenarios": scenarios,
        "contingency_factor": 1.5, "conservative_share": share, "measured_startup_CPU_seconds": startup,
        "numerical_CPU_ceiling": NUMERICAL_CPU_CEILING, "assessment_CPU_ceiling_separate": ASSESSMENT_CPU_CEILING,
        "maximum_waves": MAX_WAVES, "wave_lease_seconds": WAVE_LEASE, "wave_dispatch_seconds": WAVE_DISPATCH,
        "cost_panel_CPU_charged_separately": True, "no_losses_used": True, "full_prefix_admitted": False,
        "initial_component_count": bp.COUNTS[cost_plan["study"]]["D"] + 9,
        "maximum_component_count": bp.COUNTS[cost_plan["study"]]["maximum"],
        "status": "PRICED_COMPLETE_D_AND_WORST_S0" if priced["prefix_admitted"] else "DEFERRED_UNFUNDED_COMPLETE_PREFIX"}


def build_plan(cost_plan, timing, *, cost_publication, cost_result_pin, cost_accounting_pin):
    prep, _ = metadata(cost_plan)
    pricing = price_prefix(cost_plan, timing)
    return {"schema": SCHEMA, "status": "PRICED_NOT_ADMITTED", "study": cost_plan["study"], "region": cost_plan["region"],
        "cost_plan": cost_plan, "cost_publication": str(cost_publication), "cost_result": cost_result_pin,
        "cost_accounting": cost_accounting_pin, "pricing": pricing,
        "scientific_manifest": {key: prep[key] for key in ("source", "region", "control", "packages", "tasks", "frozen_audit_permutation")},
        "cost_result_staged_relative_path": "proofs/" + cost_result_pin["sha256"] + "/timings.json",
        "original_source_functions": {k: dict(role=v[0], owner=v[1], ast_sha256=v[2], globals=v[3]) for k,v in FUNCTIONS.items()},
        "stdlib_scientific_contract": {"path": CONTRACT_PATH, "sha256": CONTRACT_SHA},
        "new_model_fits": 0, "official_origins": 0, "promotion_authorized": False, "automatic_retry": False}


def validate_plan(plan, *, preparation=None, configuration=None, timing=None, resolver=None):
    if (plan.get("schema") != SCHEMA or plan.get("study") not in bp.COUNTS
            or plan.get("status") != "PRICED_NOT_ADMITTED" or plan.get("new_model_fits") != 0
            or plan.get("official_origins") != 0 or plan.get("promotion_authorized") is not False
            or plan.get("automatic_retry") is not False):
        raise PrefixError("new exact FI/DK2 cached-Normal prefix plan required")
    prep, config = metadata(plan["cost_plan"]) if preparation is None else (preparation, configuration)
    manifest = {key: prep[key] for key in ("source", "region", "control", "packages", "tasks", "frozen_audit_permutation")}
    if plan.get("scientific_manifest") != manifest:
        raise PrefixError("entire component/scientific manifest differs")
    timing_pin = plan["cost_result"]
    if timing is None:
        if r.digest(timing_pin["path"]) != timing_pin["sha256"]:
            raise PrefixError("cost result changed")
        timing = bp.read_metadata(timing_pin["path"])
    if price_prefix(plan["cost_plan"], timing, preparation=prep, configuration=config, resolver=resolver) != plan["pricing"]:
        raise PrefixError("prospective prefix pricing changed")
    return prep, config


def component_loss(prep, results, package, mode, seed=0):
    names = names_for(prep, [package], mode, [seed])
    if any(n not in results for n in names):
        raise PrefixError("complete three-split matched package required")
    values = [results[n]["metrics"]["AQL"] for n in names]
    if any(not finite(v) for v in values): raise PrefixError("nonfinite loss")
    return sum(values) / 3


def manifest_state(prep, pricing, results, decisions):
    """No score is read until its entire fixed scientific predecessor set passes."""
    if not pricing.get("prefix_admitted"):
        return {"phase": "DEFERRED_UNFUNDED_PREFIX", "required": [], "pending": [], "unfunded": [], "assessment_ready": True}
    names = names_for(prep, [p["package_id"] for p in prep["packages"]], "D", [0])
    pending = [n for n in names if n not in results]
    if pending: return {"phase": "DETERMINISTIC_POOL", "required": names, "pending": pending, "unfunded": [], "assessment_ready": False}
    if "nominees" not in decisions:
        return {"phase": "NOMINATION_REQUIRED", "required": names, "pending": [], "unfunded": [], "assessment_ready": False}
    nominated = decisions["nominees"]["nominees"]
    if len(nominated) != 2 or len(set(nominated)) != 2:
        raise PrefixError("exact A and geometry audit B required")
    names += names_for(prep, [prep["control"]] + nominated, "S", [0])
    pending = [n for n in names if n not in results]
    if pending: return {"phase": "NOMINEE_SEED0", "required": names, "pending": pending, "unfunded": [], "assessment_ready": False}
    if "extra_seeds" not in decisions:
        return {"phase": "EXTRA_SEED_DECISION_REQUIRED", "required": names, "pending": [], "unfunded": [], "assessment_ready": False}
    extra = decisions["extra_seeds"]
    if any(v not in nominated for v in extra["qualified"]): raise PrefixError("qualifier changed")
    names += extra["required_extra_components"]
    unfunded = extra["unfunded_pending"]
    pending = [n for n in names if n not in results]
    if unfunded:
        if pending != unfunded: raise PrefixError("partial unfunded set differs")
        return {"phase": "MATCHED_MC_UNFUNDED_PENDING", "required": names, "pending": pending, "unfunded": unfunded, "assessment_ready": True}
    return {"phase": "MATCHED_FULL_MC" if pending else "READY_FOR_ASSESSMENT", "required": names,
        "pending": pending, "unfunded": [], "assessment_ready": not pending}


def advance_decision(prep, config, pricing, results, decisions, remaining_CPU_seconds, completed_charges):
    adapter, contract = science_adapter(prep, config)
    state = manifest_state(prep, pricing, results, decisions)
    if state["phase"] == "NOMINATION_REQUIRED":
        losses = {p["package_id"]: component_loss(prep, results, p["package_id"], "D") for p in prep["packages"]}
        rule = adapter.choose_nominees(prep["packages"], losses, prep["control"], config["audit_key"])
        if rule["audit_order"] != prep["frozen_audit_permutation"]:
            raise PrefixError("frozen audit order differs")
        return "nominees", {"nominees": [rule["A"], rule["B"]], "rule": rule,
            "nomination_losses": losses, "source": prep["source"]}
    if state["phase"] == "EXTRA_SEED_DECISION_REQUIRED":
        nominees = decisions["nominees"]["nominees"]
        control = component_loss(prep, results, prep["control"], "S")
        gains = {n: control - component_loss(prep, results, n, "S") for n in nominees}
        trigger = .5 * contract.practical_margin(control)
        qualified = [n for n in nominees if gains[n] >= trigger]
        if set(completed_charges) != set(state["required"]) or any(not finite(v.get("charged_CPU_seconds")) for v in completed_charges.values()):
            raise PrefixError("complete actual charged prefix required for atomic extra admission")
        value = original("extra_admission")(adapter, state["required"], qualified, prep["control"], pricing,
            remaining_CPU_seconds, completed_charges)
        extras=value['required_extra_components']
        rounded=sum(pricing['rounded_task_CPU_reservations'][n] for n in extras)
        remaining=max(0.,min(remaining_CPU_seconds,pricing['benchmark_adjusted_available_CPU_seconds']-
            value['prefix_charged_CPU_seconds']-pricing['rounded_replacement_CPU_reservation']))
        if rounded>remaining:
            value.update(admitted_extra_components=[],unfunded_pending=extras,atomic_qualified_set_admitted=False,
                status='DEFERRED_UNFUNDED_MATCHED_EXTRAS')
        value.update(rounded_extra_CPU_reservation=rounded,rounded_remaining_CPU_seconds=remaining,
            resource_rounding_gate='integer Slurm/RLIMIT_CPU reservations; no scientific threshold change')
        value.update(seed0_gains=gains, seed0_control_AQL=control, exploration_trigger=trigger, source=prep["source"])
        return "extra_seeds", value
    raise PrefixError("no scientific transition is ready")


def assessment(prep, pricing, results, decisions, *, contract=None):
    """Final scalar decision after independently validated complete components."""
    state = manifest_state(prep, pricing, results, decisions)
    if not state["assessment_ready"]:
        raise PrefixError("whole required scientific set is incomplete")
    if state["phase"] == "DEFERRED_UNFUNDED_PREFIX":
        return {"schema": ASSESSMENT_SCHEMA, "status": "DEFERRED_UNFUNDED_COMPLETE_PREFIX", "scientific_complete": False,
            "source": prep["source"], "region": prep["region"], "new_model_fits": 0, "promotion_authorized": False}
    contract = load_contract() if contract is None else contract
    extra = decisions["extra_seeds"]
    pending = bool(state["unfunded"]); confirmed = {}; lead = None; proposal = None
    if not pending and extra["qualified"]:
        control = [component_loss(prep, results, prep["control"], "S", seed) for seed in (0, 1, 2)]
        for candidate in extra["qualified"]:
            values = [component_loss(prep, results, candidate, "S", seed) for seed in (0, 1, 2)]
            confirmed[candidate] = {**contract.confirm_gains(control, values), "control_AQL_by_seed": control, "candidate_AQL_by_seed": values}
        eligible = {k: -v["mean_gain"] for k,v in confirmed.items() if v["eligible_for_AL_proposal"]}
        lead = contract.strongest(eligible) if eligible else None
        if lead:
            packages = {p["package_id"]: p for p in prep["packages"]}
            same_geometry = packages[lead]["candidate_id"] == packages[prep["control"]]["candidate_id"]
            proposal = {"package_id": lead, "cached_candidate_AL_fits_to_verify": 42 if same_geometry else 0,
                "new_candidate_fits_if_exact_identity_reused": 0 if same_geometry else 21, "forecast_components": 18,
                "paths": 500, "default_iterations": 300, "operator": "cdf_pool_clipped", "launched": False,
                "same_package_Normal_driver_and_AL_receiver": True, "separate_budget_required": True}
    return {"schema": ASSESSMENT_SCHEMA, "status": "FINITE_BUDGET_DEFERRED_MATCHED_EXTRAS" if pending else "SCIENTIFICALLY_COMPLETE_NOT_PROMOTED",
        "source": prep["source"], "region": prep["region"], "scientific_complete": not pending,
        "all_D_and_matched_S0_complete": True, "required_components": len(state["required"]),
        "verified_components": len([n for n in state["required"] if n not in state["unfunded"]]),
        "nominations": decisions["nominees"], "extra_seed_decision": extra, "matched_three_seed_results": confirmed,
        "conditional_AL_proposal": proposal, "new_model_fits": 0, "official_test_opened": False,
        "independent_confirmation": False, "automatic_followon_admitted": False, "promotion_authorized": False,
        "disposition": "CLEAN_FINITE_BUDGET_DEFERRAL_NO_STABLE_LEAD_CLAIM" if pending else
            "ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED" if lead else "STOP_NO_STABLE_PRACTICAL_LEAD"}


def executed_sources():
    result = {}
    for name in SOURCE_FILES:
        path = Path(__file__).with_name(name)
        if not path.is_file(): raise PrefixError("complete prefix execution source is not installed: " + name)
        result[name] = r.digest(path)
    return result


def validate_component_authority(authority, plan, task, allocation, plan_sha):
    if (authority.get("schema") != AUTHORITY_SCHEMA or authority.get("status") != "ADMITTED_CACHED_NORMAL_COMPONENT"
            or authority.get("issuer") != OWNER or authority.get("controller") != OWNER
            or authority.get("purpose") != "CACHED_NORMAL_COMPONENT" or authority.get("study") != plan["study"]
            or authority.get("plan_sha256") != plan_sha or authority.get("task") != task["name"]
            or authority.get("task_sha256") != r.identity(task)
            or authority.get("scientific_identity_sha256") != task["scientific_identity_sha256"]
            or authority.get("slurm_job_id") != allocation["job_id"] or authority.get("node") != allocation["node"]
            or authority.get("automatic_retry") is not False or authority.get("new_model_fits") != 0
            or authority.get("official_origins") != 0 or authority.get("promotion_authorized") is not False):
        raise PrefixError("exact new component authority required")
    resources = authority.get("resources", {})
    limits = dict(resources, aggregate_cpu_seconds=resources.get("aggregate_cpu_seconds",resources.get("cpu_seconds")),
        numerical_threads=resources.get("numerical_threads",1))
    memory=authority.get("memory_mib",resources.get("memory_MiB"))
    estimate = plan["pricing"]["task_estimates"][task["name"]]
    if (limits.get("cpus") != 1 or limits.get("numerical_threads") != 1
            or not finite(limits.get("aggregate_cpu_seconds"), positive=True)
            or limits["aggregate_cpu_seconds"] != plan['pricing']['rounded_task_CPU_reservations'][task['name']]
            or type(limits.get("wall_seconds")) is not int or not 0 < limits["wall_seconds"] <= WAVE_DISPATCH
            or limits["wall_seconds"] != math.ceil(estimate["estimated_wall_seconds"])
            or type(memory) is not int or not 1024 <= memory <= 8192
            or authority.get("executed_sources") != executed_sources()):
        raise PrefixError("component allowance/source closure differs from complete frozen price")
    return limits


class ComponentBudget:
    def __init__(self, limits, gate, *, wall=time.monotonic, epoch=time.time, cpu=b.aggregate_cpu_seconds):
        self.wall, self.cpu = wall, cpu
        self.CPU_ceiling = limits["aggregate_cpu_seconds"]
        self.deadline = min(wall() + limits["wall_seconds"], wall() + gate["expires_epoch"] - epoch())
        self.receipt = {"lease_expires_epoch": gate["expires_epoch"]}
    def check(self):
        if self.wall() >= self.deadline or self.cpu() >= self.CPU_ceiling:
            raise PrefixError("whole component CPU/wall allowance exhausted; retained failure, no retry")
    def install(self):
        self.check(); old = resource.getrlimit(resource.RLIMIT_CPU)
        hard = math.ceil(self.CPU_ceiling)
        if old[1] != resource.RLIM_INFINITY: hard = min(hard, old[1])
        resource.setrlimit(resource.RLIMIT_CPU, (hard, hard))
        def expired(*args): raise PrefixError("hard component CPU/wall boundary")
        signal.signal(signal.SIGALRM, expired); signal.signal(signal.SIGXCPU, expired)
        signal.setitimer(signal.ITIMER_REAL, self.deadline-self.wall())


def seal_directory(output, filename, value):
    path = Path(output) / filename
    if path.exists(): raise FileExistsError("immutable result already exists")
    r.write(path, value)


def component_loop(prep, task, adapter, budget, output, *, serializer, concatenate, validator, metric, chunks, context_identity):
    """Complete original chunk order; no partial-component selection or retry."""
    output = Path(output); identity = context_identity(task, prep); events=[]; parts=[];event_count=0
    def beat(value):
        nonlocal event_count
        budget.check();event_count+=1;events.append(value)
        if len(events)>32:del events[0]
    budget.check(); context = adapter.context(task)
    try:
        descriptors = chunks(task)
        if len({d["name"] for d in descriptors}) != len(descriptors) or {d["clock_offset_steps"] for d in descriptors} != {0,24,48,72}:
            raise PrefixError("complete four-clock chunk surface required")
        for descriptor in descriptors:
            budget.check(); folder=output/"checkpoints"/descriptor["name"];folder.mkdir(parents=True,exist_ok=False)
            wall0,cpu0=time.monotonic(),time.process_time()
            prediction,truth,audit=adapter.predict(context,task,descriptor,beat)
            arrays=adapter.retained_arrays(context,task,descriptor,prediction,truth,compute_loss=True)
            validator(task,arrays,context["scaler"],descriptor)
            serializer(folder/"predictions.npz",arrays)
            seal_directory(folder,"chunk.json",{"identity":{"context":identity,"descriptor":descriptor},"sampler_audit":audit,
                "numerical_threadpools":adapter.pools(),"elapsed_seconds":time.monotonic()-wall0,"cpu_seconds":time.process_time()-cpu0,
                "new_model_fits":0,"posterior_updated":False})
            seal_directory(folder,"completed_evidence.json",{"identity":{"context":identity,"descriptor":descriptor},"certified":True,
                "artifacts":{n:r.digest(folder/n) for n in ("chunk.json","predictions.npz")}})
            parts.append(arrays);beat({"status":"chunk_sealed","chunk":descriptor["name"]})
        arrays=concatenate(parts);validator(task,arrays,context["scaler"],None)
        metrics=metric(arrays)
        if not finite(metrics.get("AQL")):raise PrefixError("finite nonnegative component AQL required")
        serializer(output/"predictions.npz",arrays)
        result={"schema":RESULT_SCHEMA,"name":task["name"],"source":prep["source"],"mode":task["mode"],
            "scientific_identity_sha256":task["scientific_identity_sha256"],"task_sha256":r.identity(task),"certified":True,
            "metrics":metrics,"units":"EUR/MWh","origin_clock_windows":4*len(task["daily_origin_positions"]),
            "chunk_count":len(descriptors),"numerical_threadpools":adapter.pools(),"new_model_fits":0,"posterior_updated":False,
            "test_opened":False,"promotion_authorized":False,"equal_origin_clock_weights":True,
            "last_events":events,"event_count":event_count,"event_history_policy":"last32; complete chunk seals retained"}
        seal_directory(output,"result.json",result)
        budget.check();return result
    finally:
        adapter.cleanup(context)


def run_component(plan_path, authority_path, activation_path, stage_root, output, *, activation_validator=None):
    """Real CLI worker. Closed before imports unless new root activation passes."""
    allocation=require_compute()
    if any(os.environ.get(k)!=v for k,v in {**THREAD_ENV,**REFERENCE_NUMERICAL_ENV}.items()):
        raise PrefixError("qualified one-thread historical numerical profile required")
    plan=r.read(plan_path)
    if plan.get("schema")!=SCHEMA or plan.get("study") not in bp.COUNTS:
        raise PrefixError("exact prepared component plan required")
    authority=r.read(authority_path);activation=r.read(activation_path)
    task=next((t for t in plan["scientific_manifest"]["tasks"] if t["name"]==authority.get("task")),None)
    if task is None:raise PrefixError("unknown canonical component")
    limits=validate_component_authority(authority,plan,task,allocation,r.digest(plan_path))
    if activation_validator is None:
        from .activation import validate_worker
        activation_validator=validate_worker
    gate=activation_validator(authority=authority,activation=activation,allocation=allocation,
        purpose="CACHED_NORMAL_COMPONENT",plan_sha256=r.digest(plan_path),executed_sources=executed_sources())
    b.validate_actual_runtime(gate["parity_runtime"])
    budget=ComponentBudget(limits,gate);budget.install()
    output=r.no_links(output)
    if "PREFIX_TRAINING" not in output.parts or any(n in output.parts for n in ("tasks_done","training_banks")):
        raise PrefixError("separate PREFIX_TRAINING output required")
    output.mkdir(parents=True,exist_ok=False)
    execution={"namespace":"PREFIX_TRAINING","task":task["name"],"task_sha256":r.identity(task),"allocation":allocation,
        "authority_sha256":r.digest(authority_path),"activation_sha256":r.digest(activation_path),"plan_sha256":r.digest(plan_path),
        "original_scientific_source":plan["cost_plan"]["canonical_preparation"]["source"],"executed_sources":executed_sources(),
        "no_original_host_wrapper_executed":True,"new_model_fits":0,"official_origins":0}
    seal_directory(output,"execution_identity.json",execution)
    try:
        prep,config,resolver=b.load_staged(plan["cost_plan"],stage_root)
        cost_relative=Path(plan["cost_result_staged_relative_path"])
        if cost_relative.is_absolute() or '..' in cost_relative.parts or cost_relative.parts[0]!='proofs':
            raise PrefixError("safe original cost proof staging required")
        timing_path=r.no_links(Path(stage_root).parent/cost_relative)
        if r.digest(timing_path)!=plan['cost_result']['sha256']:raise PrefixError("staged original cost evidence differs")
        validate_plan(plan,preparation=prep,configuration=config,timing=r.read(timing_path),resolver=resolver)
        if task!=next(t for t in prep["tasks"] if t["name"]==task["name"]):raise PrefixError("staged task changed")
        if task["scientific_identity_sha256"]!=r.identity(original("task_identity",resolver=resolver)(task)):
            raise PrefixError("scientific task fingerprint differs")
        adapter=b.frozen_adapter(plan["cost_plan"],prep,config,resolver,budget,gate["parity_runtime"]["native_library_sha256"])
        contract=load_contract(resolver)
        import numpy as np
        def light(arrays):return {k:(tuple(v.shape),v.ravel().tolist()) for k,v in arrays.items()}
        def validate(t,arrays,scaler,descriptor):contract.validate_arrays(t,light(arrays),scaler,descriptor)
        def concat(parts):return {k:np.ascontiguousarray(np.concatenate([v[k] for v in parts]),dtype="<i8" if k in b.RETAINED_INT_KEYS else "<f8") for k in contract.array_shapes(1)}
        result=component_loop(prep,task,adapter,budget,output,serializer=lambda path,a:np.savez_compressed(path,**a),
            concatenate=concat,validator=validate,metric=lambda a:contract.metrics(light(a)),
            chunks=original("chunks",resolver=resolver),context_identity=original("context_identity",resolver=resolver))
        _assert_frozen_imports(resolver);budget.check()
        seal_directory(output,"completed_evidence.json",{"status":"COMPLETE_CACHED_NORMAL_COMPONENT_NOT_PROMOTED","execution":execution,
            "context":original("context_identity",resolver=resolver)(task,prep),"certified":True,
            "observed_aggregate_CPU_seconds":b.aggregate_cpu_seconds(),"peak_RSS_KiB":resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            "artifacts":{str(p.relative_to(output)):r.digest(p) for p in sorted(output.rglob('*')) if p.is_file()}})
        return result
    except BaseException as exc:
        if not (output/'failure.json').exists():seal_directory(output,'failure.json',{"status":"FAILED_COMPONENT_NO_AUTOMATIC_RETRY",
            "execution":execution,"error_type":type(exc).__name__,"error":str(exc),"observed_aggregate_CPU_seconds":b.aggregate_cpu_seconds()})
        raise


def run_assessment(plan_path, authority_path, activation_path, stage_root, snapshot_path, components_root, output,
                   *, activation_validator=None):
    """One separately paid compute assessment revalidates all required raw packets."""
    allocation=require_compute();plan=r.read(plan_path);authority=r.read(authority_path);activation=r.read(activation_path)
    if (authority.get('purpose')!='PREFIX_ASSESSMENT' or authority.get('controller')!=OWNER
            or authority.get('plan_sha256')!=r.digest(plan_path) or authority.get('study')!=plan['study']
            or authority.get('assessment_snapshot_sha256')!=r.digest(snapshot_path)
            or authority.get('new_model_fits')!=0 or authority.get('official_origins')!=0
            or authority.get('promotion_authorized') is not False):
        raise PrefixError('exact independent assessment authority required')
    if any(os.environ.get(k)!=v for k,v in {**THREAD_ENV,**REFERENCE_NUMERICAL_ENV}.items()):
        raise PrefixError('qualified one-thread numerical profile required')
    resources=authority.get('resources',{})
    cpu=resources.get('cpu_seconds',resources.get('aggregate_cpu_seconds'))
    if (resources.get('cpus')!=1 or not finite(cpu,positive=True) or cpu>1800
            or type(resources.get('wall_seconds')) is not int or not 0<resources['wall_seconds']<=1800):
        raise PrefixError('separate1800CPU/wall assessment maximum required')
    if activation_validator is None:
        from .activation import validate_worker
        activation_validator=validate_worker
    gate=activation_validator(authority=authority,activation=activation,allocation=allocation,purpose='PREFIX_ASSESSMENT',
        plan_sha256=r.digest(plan_path),executed_sources=executed_sources())
    b.validate_actual_runtime(gate['parity_runtime'])
    limits=dict(resources,aggregate_cpu_seconds=cpu)
    budget=ComponentBudget(limits,gate);budget.install()
    out=r.no_links(output)
    if 'PREFIX_ASSESSMENT' not in out.parts:raise PrefixError('separate assessment namespace required')
    out.mkdir(parents=True,exist_ok=False)
    execution={'namespace':'PREFIX_ASSESSMENT','allocation':allocation,'plan_sha256':r.digest(plan_path),
        'authority_sha256':r.digest(authority_path),'activation_sha256':r.digest(activation_path),
        'snapshot_sha256':r.digest(snapshot_path),'executed_sources':executed_sources(),
        'new_model_fits':0,'official_origins':0}
    seal_directory(out,'execution_identity.json',execution)
    try:
        prep,config,resolver=b.load_staged(plan['cost_plan'],stage_root)
        relative=Path(plan['cost_result_staged_relative_path'])
        if relative.is_absolute() or '..' in relative.parts:raise PrefixError('safe cost proof path required')
        timing_path=r.no_links(Path(stage_root).parent/relative)
        if r.digest(timing_path)!=plan['cost_result']['sha256']:raise PrefixError('cost proof changed')
        validate_plan(plan,preparation=prep,configuration=config,timing=r.read(timing_path),resolver=resolver)
        # Native attestation is retained even though the original contract's
        # metric verification itself uses only scalar standard-library code.
        from .environment import require_reference_profile
        profile=require_reference_profile(gate['parity_runtime']['native_library_sha256'])
        contract=load_contract(resolver);snapshot=r.read(snapshot_path)
        if snapshot.get('plan_sha256')!=r.digest(plan_path) or snapshot.get('study')!=plan['study']:
            raise PrefixError('immutable assessment snapshot differs')
        results,decisions=snapshot['results'],snapshot['decisions']
        state=manifest_state(prep,plan['pricing'],results,decisions)
        if not state['assessment_ready']:raise PrefixError('complete required component set is not ready')
        required=[name for name in state['required'] if name not in state['unfunded']]
        if set(results)!=set(required):raise PrefixError('assessment contains a partial or expanded component set')
        from .prefix_control import verify_component
        by={t['name']:t for t in prep['tasks']};verification=[]
        for name in required:
            budget.check();folder=r.no_links(Path(components_root)/name);task=by[name]
            saved=verify_component(folder,plan,task,resolver=resolver)
            if any(saved.get(k)!=results[name].get(k) for k in ('name','source','scientific_identity_sha256','metrics')):
                raise PrefixError('copied component differs from canonical collected result')
            arrays=contract.read_npz(folder/'predictions.npz')
            scaler=r.read(resolver.path(task['scaler_path']))
            contract.validate_arrays(task,arrays,scaler)
            measured=contract.metrics(arrays)
            if any(not math.isclose(measured[k],saved['metrics'][k],rel_tol=1e-11,abs_tol=1e-10) for k in measured):
                raise PrefixError('independent full-component metric replay differs')
            verification.append({'name':name,'metrics':measured,'result_sha256':r.digest(folder/'result.json'),
                'component_seal_sha256':r.digest(folder/'completed_evidence.json')})
        result=assessment(prep,plan['pricing'],results,decisions,contract=contract)
        result.update(execution=execution,verification=verification,all_components_independently_revalidated=True,
            reference_numerical_profile=profile,observed_aggregate_CPU_seconds=b.aggregate_cpu_seconds())
        seal_directory(out,'assessment.json',result);budget.check()
        seal_directory(out,'completed_evidence.json',{'status':'COMPLETE_PREFIX_ASSESSMENT_NOT_PROMOTED','execution':execution,
            'artifacts':{str(q.relative_to(out)):r.digest(q) for q in sorted(out.rglob('*')) if q.is_file()}})
        return result
    except BaseException as exc:
        if not (out/'failure.json').exists():seal_directory(out,'failure.json',{'status':'FAILED_ASSESSMENT_NO_AUTOMATIC_RETRY',
            'execution':execution,'error_type':type(exc).__name__,'error':str(exc)})
        raise


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assessment',action='store_true')
    parser.add_argument('--snapshot');parser.add_argument('--components-root')
    for name in ("plan","authority","activation","stage-root","output"):parser.add_argument('--'+name,required=True)
    a=parser.parse_args(argv)
    if a.assessment:
        if not a.snapshot or not a.components_root:parser.error('assessment requires --snapshot and --components-root')
        result=run_assessment(a.plan,a.authority,a.activation,a.stage_root,a.snapshot,a.components_root,a.output)
        print(json.dumps({'status':result['status'],'scientific_complete':result['scientific_complete']}))
    else:
        result=run_component(a.plan,a.authority,a.activation,a.stage_root,a.output)
        print(json.dumps({"name":result["name"],"status":"COMPLETE_CACHED_NORMAL_COMPONENT_NOT_PROMOTED"}))


if __name__=='__main__':main()
