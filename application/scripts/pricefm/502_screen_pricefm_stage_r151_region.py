#!/usr/bin/env python3
"""One prospective DK_2 cached screen; immutable R150 numerical APIs composed.

Scheduling, metadata preparation and validation use only the standard library.
Numerical imports occur after an actual, owned R151 worker policy receipt.
No producer globals are rebound, posterior is fitted or official bank is opened.
"""
from __future__ import annotations

import argparse
import ast
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
import zipfile

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = "pricefm_stage_r151_region_20261023"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CONFIG = ROOT/"application/config"/(TAG+".json")
PREP = DATA/"launch_prep"/TAG
OUT = DATA/"campaigns"/TAG
_PRODUCER = None
_PREPARATION = {}
_COMPLETE = {}


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1048576), b""):
            h.update(block)
    return h.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name+"."+uuid.uuid4().hex+".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False)+"\n")
    os.replace(temporary, path)


def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError("immutable regional record differs: "+str(path))
    else:
        write(path, value)


def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected:
            raise RuntimeError("pinned regional artifact changed: "+path)


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def producer():
    global _PRODUCER
    c = read(CONFIG)
    verify_hashes({c["producer_entry"]: c["producer_sha256"]})
    if _PRODUCER is None:
        spec = importlib.util.spec_from_file_location("r151_region_immutable_ADD497", c["producer_entry"])
        _PRODUCER = importlib.util.module_from_spec(spec); spec.loader.exec_module(_PRODUCER)
    return _PRODUCER


def validate_config(c):
    if (c.get("tag") != TAG or c.get("region") != "DK_2"
            or c.get("required_branch") != "work/pricefm-r151-continuation-recovery-20261023"
            or c.get("new_model_fits") != 0 or c.get("new_geometries") != 0
            or any(c.get(k) is not False for k in ("official_evaluation_authorized", "AL_authorized", "promotion_authorized", "test_used_for_selection"))
            or c.get("paths") != 100 or c.get("horizon_steps") != 96
            or c.get("quantiles") != [.1, .25, .45, .5, .55, .75, .9]
            or c.get("clock_offsets_steps") != [0, 24, 48, 72] or c.get("chunk_origins") != 8
            or c.get("extra_seeds") != [2026102301, 2026102302]
            or c.get("primary_aggregation") != "equal_three_inner_split_macro"
            or c.get("practical_margin") != {"absolute": .1, "relative": .01}
            or c.get("seed0_trigger_fraction") != .5
            or c.get("audit_key") != "pricefm_continuation_plan_20261023_2149PDT|regional|DK_2|v1"
            or c.get("benchmark_max_seconds") != 1200 or c.get("cost_headroom") != 1.5
            or c.get("benchmark_D_repeats") != 3 or c.get("benchmark_S_repeats") != 1
            or c.get("max_new_D_components") != 63 or c.get("max_new_S_components") != 27
            or c.get("max_numerical_waves") != 3 or c.get("max_projected_cpu_seconds") != 32400
            or c.get("wave_lease_seconds") != 7200 or c.get("wave_dispatch_seconds") != 5400
            or c.get("maximum_replacement_reserve") != 1):
        raise ValueError("frozen one-region cached scope or finite allocation differs")
    packages = c.get("packages", []); ids = [p["package_id"] for p in packages]
    if (len(packages) != 21 or len(set(ids)) != 21
            or len({p["candidate_id"] for p in packages}) != 20
            or len({(p["candidate_id"], p["tau0"]) for p in packages}) != 21
            or any(p["spec"]["region"] != "DK_2" or p["p"] != 1+sum(p["spec"]["units"]) for p in packages)):
        raise ValueError("21 exact packages / 20 DK_2 geometries required")
    by_id = {p["package_id"]: p for p in packages}
    if (c.get("control") != "C0" or by_id["C0"]["candidate_id"] != "r134_c05562984f2b74bc"
            or by_id["C0"]["tau0"] != .0024929739307713865
            or by_id["C0_alt"]["candidate_id"] != by_id["C0"]["candidate_id"]
            or by_id["C0_alt"]["tau0"] != 2.4929739307713866e-5):
        raise ValueError("actual and original alternate DK_2 C0 packages differ")
    policies = {p["spec"]["feature_policy"] for p in packages}
    for key in ("benchmark_D_packages", "benchmark_S_packages"):
        panel = c.get(key, [])
        if len(set(panel)) != len(panel) or "C0" not in panel or any(i not in by_id for i in panel):
            raise ValueError("fixed representative benchmark panel differs")
        if {by_id[i]["spec"]["feature_policy"] for i in panel} != policies:
            raise ValueError("benchmark must cover every regional input policy")
        if max(by_id[i]["p"] for i in panel) != max(p["p"] for p in packages):
            raise ValueError("benchmark must cover maximum readout dimension")
    return c


def source_identity():
    c = validate_config(read(CONFIG))
    if git(ROOT, "branch", "--show-current") != c["required_branch"] or git(ROOT, "status", "--porcelain"):
        raise RuntimeError("clean committed dedicated R151 source required")
    return dict(head=git(ROOT, "rev-parse", "HEAD"), branch=c["required_branch"])


def bank_anchors(path):
    """Read only the pinned Unicode NPY anchor member, without NumPy."""
    with zipfile.ZipFile(path) as packet:
        with packet.open("anchors.npy") as stream:
            lead = stream.read(8)
            if lead[:6] != b"\x93NUMPY" or lead[6:8] not in (b"\x01\x00", b"\x02\x00"):
                raise ValueError("unsupported bank anchor NPY")
            width = 2 if lead[6] == 1 else 4
            size = int.from_bytes(stream.read(width), "little")
            if size > 65536: raise ValueError("oversized bank anchor header")
            head = ast.literal_eval(stream.read(size).decode("latin1").strip())
            dtype = head["descr"]
            if not dtype.startswith("<U") or head["fortran_order"] is not False or len(head["shape"]) != 1:
                raise ValueError("one-dimensional little-endian Unicode anchors required")
            chars = int(dtype[2:]); count = head["shape"][0]
            payload = stream.read()
            if len(payload) != count*chars*4: raise ValueError("truncated/padded anchor member")
            values = [payload[i*chars*4:(i+1)*chars*4].decode("utf-32-le").rstrip("\0") for i in range(count)]
    parsed = [dt.datetime.fromisoformat(s) for s in values]
    if not parsed or any(v.utcoffset() != dt.timedelta(0) for v in parsed):
        raise ValueError("exact aware UTC training bank anchors required")
    if any(b-a != dt.timedelta(days=1) for a, b in zip(parsed, parsed[1:])):
        raise ValueError("common bank anchors must be consecutive UTC days")
    return values


def split_boundaries(path, n):
    """Extract the exact pinned inherited split declaration, then replay in worker."""
    tree = ast.parse(Path(path).read_text())
    function = next(v for v in tree.body if isinstance(v, ast.FunctionDef) and v.name == "internal_splits")
    bounds = next(ast.literal_eval(v.value) for v in function.body if isinstance(v, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == "boundaries" for t in v.targets))
    requirements = [v for v in ast.walk(function) if isinstance(v, ast.Compare)
                    and any(isinstance(a, ast.Constant) and a.value == n for a in v.comparators)]
    if not requirements or len(bounds) != 3 or bounds[-1][1] != n:
        raise ValueError("bank support does not match pinned original split helper")
    if any(not 0 < a < b <= n for a, b in bounds): raise ValueError("invalid inherited split support")
    return bounds


def cohort(anchors, boundaries, split, offsets):
    train_stop, validation_stop = boundaries[split-1]
    validation = list(range(train_stop, validation_stop)); daily = validation[:-1]
    stamps = {str(o): [(dt.datetime.fromisoformat(anchors[p])+dt.timedelta(minutes=15*o)).isoformat()
                       for p in daily] for o in offsets}
    return dict(train_origin_positions=list(range(train_stop)), validation_origin_positions=validation,
                daily_origin_positions=daily, origin_timestamps=stamps)


def name_for(package, split, mode, seed_index):
    return "DK_2_"+package+"_s"+str(split)+"_"+mode+"_seed"+str(seed_index)


def names_for(packages, mode, seeds):
    return [name_for(p, split, mode, seed) for p in packages for seed in seeds for split in (1, 2, 3)]


def choose_nominees(packages, losses, control, key):
    p = producer(); by_id = {v["package_id"]: v for v in packages}
    if set(losses) != set(by_id) or any(not math.isfinite(v) for v in losses.values()):
        raise ValueError("complete finite deterministic regional pool required")
    a = p.strongest(losses, [control]); order = p.audit_permutation(packages, key)
    excluded = {by_id[control]["candidate_id"], by_id[a]["candidate_id"]}
    eligible = [i for i in order if by_id[i]["candidate_id"] not in excluded]
    if not eligible: raise ValueError("geometry-distinct regional audit nominee unavailable")
    return dict(A=a, B=eligible[0], audit_key=key, audit_order=order, eligible_audit_order=eligible,
                audit_rule="SHA256(key|canonical_package_id), then ID; exclude C0 and A geometries")


def verify_evidence_lineage(record, directory, ledger, summary, contract_path):
    """The pre-score external audit binds moments, not only a self-consistent seal."""
    directory = Path(directory)
    expected = {str(directory/"completed_evidence.json"): record["completed_evidence_sha256"],
        str(directory/"fit/beta_mean.bin"): record["beta_mean_sha256"],
        str(directory/"fit/beta_cov.bin"): record["beta_cov_sha256"],
        str(contract_path): record["contract_sha256"]}
    if (str(directory) != record["directory"] or any(not h or ledger.get(p) != h for p, h in expected.items())
            or any(summary.get(k) != record[k] for k in ("p", "n", "omega_shape", "omega_rate", "posterior_target_sha256"))
            or summary.get("full_variational_certified") is not True):
        raise RuntimeError("cached parent differs from prospectively pinned regional moments/target/contract")


def build_preparation(identity):
    c = validate_config(read(CONFIG)); p = producer()
    pins = {c[k]: c[k+"_sha256"] for k in ("regional_evidence", "parent_preparation", "split_helper")}
    verify_hashes(pins); evidence = read(c["regional_evidence"]); old = read(c["parent_preparation"])
    region = evidence["regions"][c["region"]]; cache = Path(region["campaign"])
    if old["source"] != c["parent_source"] or region["source"] != c["parent_source"]:
        raise RuntimeError("original regional producer identity differs")
    verify_hashes(old["source_sha256"]); verify_hashes(old["bank_sha256"])
    sources = dict(old["source_sha256"])
    sources[c["producer_entry"]] = c["producer_sha256"]
    for pattern in ("application/scripts/pricefm/*r151*.py", "application/config/*r151*.json",
                    "application/tests/*r151*.py", "docs/implementation_notes/*r151*.md"):
        sources.update({str(v): digest(v) for v in ROOT.glob(pattern)})
    inputs = dict(pins); inputs.update(old["bank_sha256"])
    banks = {Path(v).stem: dict(path=v, sha256=h) for v, h in old["bank_sha256"].items()}
    anchors = None
    for bank in banks.values():
        found = bank_anchors(bank["path"])
        if anchors is not None and found != anchors: raise RuntimeError("regional feature banks have different cohorts")
        anchors = found
    boundaries = split_boundaries(c["split_helper"], len(anchors))
    cohorts = {s: cohort(anchors, boundaries, s, c["clock_offsets_steps"]) for s in (1, 2, 3)}
    proposed = {(v["candidate_id"], v["tau0"]) for v in region["packages"]+region["mandatory_control_packages"]}
    if {(v["candidate_id"], v["tau0"]) for v in c["packages"]} != proposed:
        raise RuntimeError("prospective pool differs from verified train-only union")
    tasks = []
    for package in c["packages"]:
        original_package = next(v for v in region["packages"] if v["candidate_id"] == package["candidate_id"])
        audited_package = next(v for v in region["packages"]+region["mandatory_control_packages"]
            if v["candidate_id"] == package["candidate_id"] and v["tau0"] == package["tau0"])
        if package["spec"] != original_package["spec"]: raise RuntimeError("geometry changed after regional freeze")
        for split in (1, 2, 3):
            parent = f"rhs_DK_2_{package['candidate_id']}_s{split}_t{package['tau0']:.12e}"
            descriptor, result, ledger = p.kernel().verify_cached_packet(cache, parent, old["source"]["head"], heavy=True)
            terminal = read(cache/"tasks_done"/parent/"fit/terminal.json")
            summary = read(cache/"tasks_done"/parent/"fit/fit_summary.json")
            contract_path = cache/"contracts"/(parent+".json"); contract = read(contract_path)
            if (descriptor["spec"] != package["spec"] or descriptor["tau0"] != package["tau0"]
                    or descriptor["region"] != "DK_2" or descriptor["split"] != split
                    or result["certified"] is not True or terminal["full_variational_certified"] is not True
                    or terminal["test_opened"] is not False or terminal["tau0"] != package["tau0"]
                    or summary["p"] != package["p"] or summary["contract_sha256"] != digest(contract_path)
                    or contract["tau0"] != package["tau0"]):
                raise RuntimeError("exact certified regional cached posterior differs")
            stats, stats_result, stats_ledger = p.kernel().verify_cached_packet(cache, descriptor["stats_name"], old["source"]["head"], heavy=False)
            if stats["candidate_id"] != package["candidate_id"] or stats["split"] != split or stats_result["certified"] is not True:
                raise RuntimeError("exact training-only scaler parent differs")
            scaler = cache/"tasks_done"/descriptor["stats_name"]/"scaler.json"
            expected_scaler = next(v for v in original_package["scalers"] if v["split"] == split)
            if str(scaler) != expected_scaler["path"] or digest(scaler) != expected_scaler["sha256"]:
                raise RuntimeError("prospective regional scaler pin differs")
            ledger.update({str(contract_path): digest(contract_path)})
            audited_fit = next(v for v in audited_package["fits"] if v["split"] == split)
            verify_evidence_lineage(audited_fit, cache/"tasks_done"/parent, ledger, summary, contract_path)
            inputs.update(ledger); inputs.update(stats_ledger)
            for mode, seeds in (("D", (0,)), ("S", (0, 1, 2))):
                for seed_index in seeds:
                    task = dict(name=name_for(package["package_id"], split, mode, seed_index), kind="cached_"+mode+"_full_origin",
                        region="DK_2", package_id=package["package_id"], candidate_id=package["candidate_id"], tau0=package["tau0"],
                        spec=package["spec"], p=package["p"], split=split, mode=mode, seed_index=seed_index,
                        forecast_seed=([old["protocol"]["forecast_seed"]]+c["extra_seeds"])[seed_index], paths=100,
                        parent_task=parent, parent_source=old["source"], parent_fit=str(cache/"tasks_done"/parent/"fit"),
                        parent_seal_sha256=digest(cache/"tasks_done"/parent/"completed_evidence.json"), parent_input_sha256=ledger,
                        scaler_path=str(scaler), scaler_sha256=digest(scaler), bank=banks[package["spec"]["feature_policy"]],
                        clock_offsets_steps=c["clock_offsets_steps"], horizon_steps=96, quantiles=c["quantiles"],
                        new_model_fits=0, posterior_updated=False, test_opened=False, **cohorts[split])
                    task["scientific_identity_sha256"] = fingerprint(p.task_identity(task)); task["reuse"] = None
                    tasks.append(task)
    verify_hashes(sources)
    return dict(status="R151_REGION_PREPARED_NO_NUMERICAL_ADMISSION", source=identity, config_sha256=digest(CONFIG),
        source_sha256=sources, input_sha256=inputs, dependency=old["dependency"], dependency_head=old["dependency_head"],
        region=c["region"], packages=c["packages"], control=c["control"], tasks=tasks, banks=banks,
        original_regional_source=old["source"], potential_task_count=len(tasks), imported_components=0, new_model_fits=0,
        frozen_audit_permutation=p.audit_permutation(c["packages"], c["audit_key"]),
        cohort_audit=dict(bank_origins=len(anchors), split_boundaries=boundaries,
            daily_counts={str(s): len(v["daily_origin_positions"]) for s, v in cohorts.items()},
            policy="derived from own pinned bank anchors and original split helper; final validation day excluded"),
        official_outcomes_exposed_development_only=True, test_opened=False, posterior_updated=False)


def prepare():
    value = build_preparation(source_identity())
    immutable(PREP/"preparation.json", value)
    immutable(PREP/"prepared.json", dict(source=value["source"], sha256=digest(PREP/"preparation.json")))
    for task in value["tasks"]: immutable(OUT/"tasks"/(task["name"]+".json"), task)
    return dict(status=value["status"], potential_components=len(value["tasks"]), D_components=63, S_max=27,
                new_model_fits=0, cohort_audit=value["cohort_audit"])


def read_preparation():
    key = digest(PREP/"preparation.json")
    if key not in _PREPARATION:
        value = read(PREP/"preparation.json")
        if read(PREP/"prepared.json") != dict(source=value["source"], sha256=key) or value["config_sha256"] != digest(CONFIG):
            raise RuntimeError("regional preparation seal or config differs")
        _PREPARATION.clear(); _PREPARATION[key] = value
    return _PREPARATION[key]


def task_by_name(name, prep=None):
    task = next((v for v in (prep or read_preparation())["tasks"] if v["name"] == name), None)
    if task is None: raise ValueError("unknown regional component: "+name)
    if task["scientific_identity_sha256"] != fingerprint(producer().task_identity(task)):
        raise RuntimeError("regional scientific task identity differs")
    return task


def task_complete(name):
    p = producer(); prep = read_preparation()
    if name == "__finalize__":
        if not (OUT/"assessment_seal.json").exists(): return False
        if read(OUT/"assessment_seal.json") != dict(sha256=digest(OUT/"assessment.json"), source=prep["source"]):
            raise RuntimeError("regional final assessment seal differs")
        if read(OUT/"assessment.json").get("source") != prep["source"]:
            raise RuntimeError("regional assessment producer differs")
        return True
    if name == "__benchmark__":
        folder = OUT/"benchmark"
        if not (folder/"completed_evidence.json").exists(): return False
        timing = read(folder/"timings.json")
        panels = {v["retained_prediction_packet"] for v in timing["rows"]}
        if any(Path(v).name != v or not v.endswith(".npz") for v in panels):
            raise RuntimeError("regional benchmark retained panel path escapes packet")
        seal = p.verify_packet(folder, {"timings.json", "branch.json"}|panels)
        if seal.get("context") != dict(source=prep["source"], preparation_sha256=digest(PREP/"preparation.json")):
            raise RuntimeError("regional benchmark context differs")
        return True
    task = task_by_name(name, prep)
    if read(OUT/"tasks"/(name+".json")) != task: raise RuntimeError("regional immutable descriptor differs")
    folder = OUT/"tasks_done"/name
    if not folder.exists(): return False
    files = [folder/v for v in ("completed_evidence.json", "predictions.npz", "result.json")]
    files += [Path(task["scaler_path"]), Path(task["bank"]["path"])] + [Path(v) for v in task["parent_input_sha256"]]
    signature = (fingerprint(task), tuple((str(v), v.stat().st_mtime_ns, v.stat().st_ctime_ns, v.stat().st_size) for v in files))
    if _COMPLETE.get(name) == signature: return True
    seal = p.verify_packet(folder, {"predictions.npz", "result.json"}); result = read(folder/"result.json")
    if (seal.get("context") != p.context_identity(task, prep) or seal.get("certified") is not True
            or result.get("scientific_identity_sha256") != task["scientific_identity_sha256"]
            or result.get("source") != prep["source"] or result.get("units") != "EUR/MWh"
            or result.get("mode") != task["mode"] or result.get("new_model_fits") != 0
            or result.get("posterior_updated") is not False or result.get("test_opened") is not False
            or result.get("origin_clock_windows") != 4*len(task["daily_origin_positions"])
            or not result.get("numerical_threadpools") or any(v["num_threads"] != 1 for v in result["numerical_threadpools"])
            or not math.isfinite(result["metrics"]["AQL"]) or result["metrics"]["AQL"] < 0):
        raise RuntimeError("regional final packet scope, source or policy differs")
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["bank"]["path"]: task["bank"]["sha256"], task["scaler_path"]: task["scaler_sha256"]})
    p.validate_arrays(task, p.read_npz(folder/"predictions.npz", headers_only=True), read(task["scaler_path"]), semantic=False)
    _COMPLETE[name] = signature; return True


def component_loss(package, mode, seed=0):
    names = names_for([package], mode, [seed])
    if not all(task_complete(n) for n in names): raise RuntimeError("complete three-split regional component required")
    return sum(read(OUT/"tasks_done"/n/"result.json")["metrics"]["AQL"] for n in names)/3


def write_decision(name, value):
    immutable(OUT/"decisions"/(name+".json"), value)
    immutable(OUT/"decisions"/(name+".seal.json"), dict(sha256=digest(OUT/"decisions"/(name+".json")),
        source=read_preparation()["source"], preparation_sha256=digest(PREP/"preparation.json")))


def read_decision(name):
    path = OUT/"decisions"/(name+".json")
    if read(path.with_name(name+".seal.json")) != dict(sha256=digest(path), source=read_preparation()["source"],
            preparation_sha256=digest(PREP/"preparation.json")):
        raise RuntimeError("regional decision seal differs")
    return read(path)


def pricing():
    if not task_complete("__benchmark__"): raise RuntimeError("regional cost-only benchmark not complete")
    return read(OUT/"benchmark/branch.json")


def manifest_state():
    prep = read_preparation()
    if not task_complete("__benchmark__"): return "BENCHMARK", ["__benchmark__"], [], False
    price = pricing()
    if not price["prefix_admitted"]: return "DEFERRED_UNFUNDED_PREFIX", [], [], True
    names = names_for([v["package_id"] for v in prep["packages"]], "D", [0])
    if not all(task_complete(n) for n in names): return "DETERMINISTIC_POOL", names, [], False
    if not (OUT/"decisions/nominees.seal.json").exists(): return "NOMINATION_REQUIRED", names, [], False
    nominees = read_decision("nominees")["nominees"]
    if len(nominees) != 2 or len(set(nominees)) != 2: raise RuntimeError("regional nominee set changed")
    names += names_for([prep["control"]]+nominees, "S", [0])
    if not all(task_complete(n) for n in names): return "NOMINEE_SEED0", names, [], False
    if not (OUT/"decisions/extra_seeds.seal.json").exists(): return "EXTRA_SEED_DECISION_REQUIRED", names, [], False
    extra = read_decision("extra_seeds"); names += extra["required_extra_components"]
    if any(v not in nominees for v in extra["qualified"]): raise RuntimeError("regional qualifier set changed")
    if extra["unfunded_pending"]: return "MATCHED_MC_UNFUNDED_PENDING", names, extra["unfunded_pending"], False
    if not all(task_complete(n) for n in names): return "MATCHED_FULL_MC", names, [], False
    return "READY_FOR_ASSESSMENT", names, [], True


def estimate_task(name):
    if name == "__finalize__":
        return dict(name=name, kind="independent_semantic_finalization", estimated_cpu_seconds=1800., estimated_wall_seconds=1800., estimated_max_chunk_wall_seconds=1800.)
    if name == "__benchmark__":
        return dict(name=name, kind="cost_only_benchmark", estimated_cpu_seconds=1200., estimated_wall_seconds=1200., estimated_max_chunk_wall_seconds=1200.)
    value = pricing()["task_estimates"][name]
    return dict(name=name, kind=task_by_name(name)["kind"], **{k: value[k] for k in
        ("estimated_cpu_seconds", "estimated_wall_seconds", "estimated_max_chunk_wall_seconds")})


def queue_state():
    phase, names, unfunded, terminal = manifest_state(); complete = [n for n in names if task_complete(n)]
    pending = [n for n in names if n not in complete]
    assessment = read(OUT/"assessment.json") if task_complete("__finalize__") else {}
    scientific_complete = (phase == "READY_FOR_ASSESSMENT" and not pending and not unfunded
        and assessment.get("status") == "R151_REGION_SCIENTIFICALLY_COMPLETE_NOT_PROMOTED"
        and assessment.get("scientific_complete") is True
        and assessment.get("required_components") == assessment.get("verified_components") == len(names))
    return dict(phase=phase, ready=[estimate_task(n) for n in pending if n not in unfunded], pending=pending,
        complete=complete, total=len(names), terminal=terminal, unfunded_pending=unfunded, new_model_fits=0,
        scientific_complete=scientific_complete, promotion_authorized=False,
        resource_projection=pricing()["resource_projection"] if phase != "BENCHMARK" else {})


def extra_admission(prefix, qualifiers, control, price, remaining_CPU_seconds, completed_charges, budget_view=None):
    if remaining_CPU_seconds is None or not math.isfinite(remaining_CPU_seconds) or remaining_CPU_seconds < 0:
        raise ValueError("fresh finite remaining-window CPU allowance required for atomic MC admission")
    extras = names_for([control]+list(qualifiers), "S", [1, 2]) if qualifiers else []
    prefix_cpu = sum(completed_charges[n]["charged_CPU_seconds"] for n in prefix)
    cpu = sum(price["task_estimates"][n]["estimated_cpu_seconds"] for n in extras)
    remaining = max(0., min(remaining_CPU_seconds, price["benchmark_adjusted_available_CPU_seconds"]-prefix_cpu-price["replacement_reserve_CPU_seconds"]))
    fits = cpu <= remaining
    return dict(qualified=list(qualifiers), required_extra_components=extras, admitted_extra_components=extras if fits else [],
        unfunded_pending=[] if fits else extras, atomic_qualified_set_admitted=fits, prefix_charged_CPU_seconds=prefix_cpu,
        extra_projected_CPU_seconds=cpu, remaining_CPU_seconds=remaining, explicit_remaining_window_CPU_seconds=remaining_CPU_seconds,
        completed_prefix_CPU_charges=completed_charges, resource_budget_view=budget_view,
        status="ADMITTED_MATCHED_EXTRAS" if fits else "DEFERRED_UNFUNDED_MATCHED_EXTRAS",
        rule="entire qualified set and one shared control; no cost-based nominee or seed replacement")


def advance(remaining_CPU_seconds=None, budget_view=None):
    prep = read_preparation(); p = producer(); phase, names, _, _ = manifest_state()
    if phase == "NOMINATION_REQUIRED":
        losses = {v["package_id"]: component_loss(v["package_id"], "D") for v in prep["packages"]}
        rule = choose_nominees(prep["packages"], losses, prep["control"], read(CONFIG)["audit_key"])
        if rule["audit_order"] != prep["frozen_audit_permutation"]: raise RuntimeError("frozen regional audit order differs")
        write_decision("nominees", dict(nominees=[rule["A"], rule["B"]], rule=rule, nomination_losses=losses, source=prep["source"]))
    elif phase == "EXTRA_SEED_DECISION_REQUIRED":
        nominees = read_decision("nominees")["nominees"]; control = component_loss(prep["control"], "S")
        gains = {n: control-component_loss(n, "S") for n in nominees}; trigger = .5*p.practical_margin(control)
        qualified = [n for n in nominees if gains[n] >= trigger]
        decision = extra_admission(names, qualified, prep["control"], pricing(), remaining_CPU_seconds,
            {n: completed_CPU_charge(n, prep) for n in names}, budget_view)
        decision.update(seed0_gains=gains, seed0_control_AQL=control, exploration_trigger=trigger, source=prep["source"])
        write_decision("extra_seeds", decision)
    return queue_state()


def prefix_contract(prep, estimates, available):
    c = read(CONFIG); packages = prep["packages"]; control = prep["control"]
    ids = [v["package_id"] for v in packages]; scenarios = []
    d = sum(estimates[n]["estimated_cpu_seconds"] for n in names_for(ids, "D", [0]))
    for a in ids:
        if a == control: continue
        # B is fixed by geometry exclusions and SHA order, independently of scores.
        losses = {i: 2. for i in ids}; losses[a] = 1.
        b = choose_nominees(packages, losses, control, c["audit_key"])["B"]
        initial = names_for([control, a, b], "S", [0])
        scenarios.append(dict(A=a, B=b, seed0_CPU_seconds=sum(estimates[n]["estimated_cpu_seconds"] for n in initial)))
    worst = max(scenarios, key=lambda v: (v["seed0_CPU_seconds"], v["A"]))
    replacement = max(v["estimated_cpu_seconds"] for v in estimates.values())
    total = d+worst["seed0_CPU_seconds"]+replacement
    return dict(D_CPU_seconds=d, worst_seed0_nomination=worst, all_prospective_seed0_scenarios=scenarios,
        replacement_reserve_CPU_seconds=replacement, maximum_replacements=1, worst_prefix_CPU_seconds=total,
        benchmark_adjusted_available_CPU_seconds=available, prefix_admitted=total <= available,
        no_losses_used=True, extras_conditioned_on_remaining_budget=True)


def validate_worker_lease(receipt, prep, name, now=None):
    """Bind a payload to one exact immutable regional admission before imports."""
    now = time.time() if now is None else now
    base = PREP/"muscat_resources"
    matches = [(path, read(path)) for path in base.glob("wave_*/lease.json")
        if read(path).get("lease_id") == receipt.get("lease_id")]
    if len(matches) != 1: raise RuntimeError("regional worker must resolve exactly one immutable lease ID")
    path, lease = matches[0]; wave = lease.get("wave")
    seconds = 1200 if wave == "benchmark" else 7200
    if (wave not in ("benchmark", "1", "2", "3") or path.parent.name != "wave_"+str(wave)
            or lease.get("stage") != "R151_REGION" or lease.get("region") != "DK_2"
            or lease.get("source_head") != prep["source"]["head"] or lease.get("nonrenewing") is not True
            or lease.get("seconds") != seconds or lease.get("expires_epoch") != receipt.get("lease_expires_epoch")
            or not lease.get("started_epoch", float("inf")) <= now < lease.get("expires_epoch", -float("inf"))
            or not math.isclose(lease["expires_epoch"]-lease["started_epoch"], seconds, rel_tol=0., abs_tol=1e-6)
            or lease.get("preparation_sha256") != digest(PREP/"preparation.json")
            or lease.get("boot_id") != Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            or lease.get("orchestration_config_sha256") != digest(ROOT/"application/config/pricefm_stage_r151_orchestration_20261023.json")
            or lease.get("outer_context_sha256") != digest(base/"outer_context.json")):
        raise RuntimeError("regional worker immutable finite lease/source/preparation/boot differs")
    context = read(base/"outer_context.json"); outer = read(context["outer_capsule_path"])
    if (lease.get("outer_run_id") != context["run_id"] or lease.get("outer_unit") != outer["unit"]
            or lease.get("outer_invocation_id") != outer["attested"]["InvocationID"]):
        raise RuntimeError("regional lease outer lifetime backlink differs")
    if name == "__benchmark__" and wave != "benchmark":
        raise RuntimeError("regional benchmark cannot consume a numerical wave")
    if wave == "benchmark" and name != "__benchmark__":
        if name != "__finalize__" or not task_complete("__benchmark__") or pricing().get("prefix_admitted") is not False:
            raise RuntimeError("benchmark admission cannot release D/S or a nondeferred assessment")
    return lease


def validate_worker_process(process):
    own_stat = Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()
    if (process.get("pid") != os.getpid() or process.get("start_ticks") != int(own_stat[19])
            or process.get("boot_id") != Path("/proc/sys/kernel/random/boot_id").read_text().strip()):
        raise RuntimeError("regional policy proof process lifetime differs after exec")


def guard(cpu, receipt_path, name):
    receipt = read(receipt_path); prep = read_preparation()
    if (receipt.get("schema_version") != 1 or receipt.get("stage") != "R151" or receipt.get("task") != name
            or receipt.get("source_head") != prep["source"]["head"] or receipt.get("cpu") != cpu
            or receipt.get("lease_expires_epoch", 0) <= time.time() or receipt.get("expected_affinity") != [cpu]
            or receipt.get("expected_scheduler") != 5 or receipt.get("numerical_threads") != 1 or receipt.get("io_class") != 3
            or not receipt.get("worker_invocation_id") or not receipt.get("worker_cgroup") or not receipt.get("actual_probe")):
        raise RuntimeError("regional worker policy receipt differs")
    if cpu not in range(15, 30) or os.sched_getaffinity(0) != {cpu} or os.sched_getscheduler(0) != os.SCHED_IDLE:
        raise RuntimeError("regional worker requires one physical CPU15–29 and SCHED_IDLE")
    if not subprocess.check_output(["ionice", "-p", str(os.getpid())], text=True).startswith("idle"):
        raise RuntimeError("regional worker requires idle I/O")
    paths = {line.split(":", 2)[2] for line in Path("/proc/self/cgroup").read_text().splitlines()}
    if receipt["worker_cgroup"] not in paths or receipt["worker_invocation_id"] != os.environ.get("INVOCATION_ID"):
        raise RuntimeError("actual regional worker ownership differs")
    proof = receipt["actual_probe"]; props = proof.get("properties", {}); process = proof.get("process", {})
    if (props.get("Id") != receipt.get("unit") or props.get("InvocationID") != receipt["worker_invocation_id"]
            or props.get("ControlGroup") != receipt["worker_cgroup"] or process.get("scheduler") != 5
            or process.get("affinity") != [cpu] or props.get("IOSchedulingClass") != "3"):
        raise RuntimeError("actual regional unit policy proof differs")
    validate_worker_process(process)
    for k in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        if os.environ.get(k) != "1": raise RuntimeError("single numerical thread environment required")
    validate_worker_lease(receipt, prep, name)
    if source_identity() != prep["source"]: raise RuntimeError("regional source release changed")
    verify_hashes(prep["source_sha256"]); return receipt


def predict(context, task, descriptor, beat):
    """The sole regional adaptation: original region participates in seed derivation."""
    import numpy as np
    from pricefm_r127_contract import shifted_windows, window_identity
    runtime = context["runtime"]; p = producer(); offset = descriptor["clock_offset_steps"]
    positions = np.asarray(descriptor["origin_positions"], dtype=int)
    validation = np.asarray(task["validation_origin_positions"], dtype=int)
    arrays = shifted_windows(context["scaled"], positions, offset, validation)
    raw = shifted_windows(context["raw"], positions, offset, validation)
    window_identity(arrays, dt.datetime.fromisoformat(str(context["raw"].anchors[validation[0]])),
        dt.datetime.fromisoformat(str(context["raw"].anchors[validation[-1]]))+dt.timedelta(days=1))
    if [dt.datetime.fromisoformat(str(v)).isoformat() for v in arrays.anchors] != descriptor["origin_timestamps"]:
        raise RuntimeError("regional shifted absolute clock differs")
    if task["mode"] == "D":
        prediction = p.kernel().deterministic_predictions(runtime, arrays, task["spec"], context["fit"])
        audit = dict(policy="unchanged_omega_mean_plus_zVz_analytic_Normal_quantiles", simulated_paths=0)
    else:
        seed = runtime.BASE.deterministic_seed(task["forecast_seed"], task["region"], task["split"])
        prediction, audit = context["core"].normal_predictions(runtime, arrays, task["spec"], context["fit"],
            np.asarray(descriptor["stable_rng_origin_keys"], dtype=int), runtime.BASE.deterministic_seed(seed, "clock", offset),
            paths=100, observe=lambda event: beat(dict(event, chunk=descriptor["name"])))
    if not np.isfinite(prediction).all(): raise RuntimeError("nonfinite regional forecast")
    if not np.allclose(raw.response, arrays.response*context["scaler"]["price_scale"]+context["scaler"]["price_mean"], rtol=1e-12, atol=1e-10):
        raise RuntimeError("regional inverse scaler / raw truth differs")
    return prediction, arrays.response, audit


def legacy_control_replay(context, task, descriptor, prediction, truth):
    """Compare wiring with the actual original regional producer's call chain.

    This is a no-loss benchmark check, not an additional screening component.
    No equivalent retained full-cohort control array has been established.
    """
    import numpy as np
    from pricefm_r127_contract import shifted_windows
    c = read(CONFIG); parent = read(c["parent_preparation"])
    actual = next(p for p in c["packages"] if p["package_id"] == "C0")
    if (task["package_id"] != "C0" or task["seed_index"] != 0
            or task["candidate_id"] != actual["candidate_id"] or task["tau0"] != actual["tau0"]
            or task["forecast_seed"] != parent["protocol"]["forecast_seed"]):
        raise RuntimeError("legacy control replay requires exact actual C0 and original seed")
    runtime = context["runtime"]; offset = descriptor["clock_offset_steps"]
    positions = np.asarray(descriptor["origin_positions"], dtype=int)
    arrays = shifted_windows(context["scaled"], positions, offset, np.asarray(task["validation_origin_positions"], dtype=int))
    if task["mode"] == "D":
        reference = producer().kernel().deterministic_predictions(runtime, arrays, task["spec"], context["fit"])
        okay = np.allclose(reference, prediction, atol=1e-12, rtol=1e-10)
        rule = "same_original_analytic_kernel_call_chain_consistency_atol1e-12_rtol1e-10_not_independent_D_implementation"
    else:
        original_seed = runtime.BASE.deterministic_seed(parent["protocol"]["forecast_seed"], c["region"], task["split"])
        reference, _ = context["core"].normal_predictions(runtime, arrays, task["spec"], context["fit"],
            positions*96+offset, runtime.BASE.deterministic_seed(original_seed, "clock", offset), paths=100)
        okay = np.array_equal(reference, prediction); rule = "bitwise_original_R141_regional_absolute_clock_RNG_call_chain"
    if not okay or not np.array_equal(arrays.response, truth):
        raise RuntimeError("regional C0 differs from original producer mathematical replay")
    return dict(status="PASS_ACTUAL_C0_ORIGINAL_MATH_REPLAY", rule=rule, mode=task["mode"],
        original_regional_source=parent["source"], seed=parent["protocol"]["forecast_seed"], region=c["region"],
        paths=100 if task["mode"] == "S" else 0, no_candidate_AQL_computed=True,
        reference_prediction_bytes_sha256=hashlib.sha256(np.ascontiguousarray(reference, dtype="<f8").tobytes()).hexdigest(),
        retained_original_full_cohort_packet_reuse=False)


def start_CPU_attempt(task, prep, receipt, policy_path):
    folder = OUT/"cpu_accounting"/task["name"]/receipt["worker_invocation_id"]
    value = dict(source=prep["source"], task=task["name"], scientific_identity_sha256=task["scientific_identity_sha256"],
        policy_invocation_id=receipt["worker_invocation_id"], policy_receipt_path=str(policy_path), policy_receipt_sha256=digest(policy_path),
        prior_started_invocations=sorted(v.parent.name for v in folder.parent.glob("*/started.json")),
        preexisting_checkpoint_count=len(list((OUT/"checkpoints"/task["name"]).glob("*/completed_evidence.json"))))
    immutable(folder/"started.json", value); return folder, value


def finish_CPU_attempt(folder, started, completed):
    child = resource.getrusage(resource.RUSAGE_CHILDREN); process = time.process_time(); children = child.ru_utime+child.ru_stime
    value = dict(started, completed_component=completed, observed_process_CPU_seconds=process,
        observed_terminated_children_CPU_seconds=children, observed_total_CPU_seconds=process+children,
        task_final_seal_sha256=digest(OUT/"tasks_done"/started["task"]/"completed_evidence.json") if completed else None,
        post_observation_exit_allowance_CPU_seconds=5., hard_CPU_quota=False, exact_exit_CPU_measurement=False)
    immutable(folder/"observed.json", value)
    immutable(folder/"observed.seal.json", dict(sha256=digest(folder/"observed.json"), source=started["source"]))


def completed_CPU_charge(name, prep=None):
    prep = prep or read_preparation(); task = task_by_name(name, prep)
    if not task_complete(name): raise RuntimeError("CPU credit requires strict final component")
    estimate = pricing()["task_estimates"][name]["estimated_cpu_seconds"]
    starts = list((OUT/"cpu_accounting"/name).glob("*/started.json")); totals = []; errors = []; final = 0; prior = set()
    present = {v.parent.name for v in starts}
    for path in starts:
        try:
            started = read(path); observed = read(path.parent/"observed.json")
            previous = started.get("prior_started_invocations")
            if not isinstance(previous, list) or any(not isinstance(v, str) or not v or "/" in v or v in (".", "..") for v in previous):
                raise ValueError("invalid CPU attempt lineage")
            prior.update(previous)
            if (started.get("source") != prep["source"] or started.get("task") != name
                    or started.get("scientific_identity_sha256") != task["scientific_identity_sha256"]
                    or started.get("policy_invocation_id") != path.parent.name or any(observed.get(k) != v for k, v in started.items())
                    or read(path.parent/"observed.seal.json") != dict(sha256=digest(path.parent/"observed.json"), source=prep["source"])
                    or observed.get("post_observation_exit_allowance_CPU_seconds") != 5.
                    or observed.get("hard_CPU_quota") is not False or observed.get("exact_exit_CPU_measurement") is not False
                    or type(observed.get("completed_component")) is not bool
                    or started.get("preexisting_checkpoint_count", 0) and not previous):
                raise ValueError("CPU attempt source/task/seal differs")
            verify_hashes({started["policy_receipt_path"]: started["policy_receipt_sha256"]})
            policy = read(started["policy_receipt_path"])
            if policy.get("task") != name or policy.get("source_head") != prep["source"]["head"] or policy.get("worker_invocation_id") != path.parent.name:
                raise ValueError("CPU receipt policy differs")
            values = [observed[k] for k in ("observed_process_CPU_seconds", "observed_terminated_children_CPU_seconds", "observed_total_CPU_seconds")]
            if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in values):
                raise ValueError("invalid observed CPU")
            if not math.isclose(values[0]+values[1], values[2], rel_tol=1e-12, abs_tol=1e-10): raise ValueError("CPU sum differs")
            if observed["completed_component"]:
                if observed["task_final_seal_sha256"] != digest(OUT/"tasks_done"/name/"completed_evidence.json"):
                    raise ValueError("CPU credit final scientific seal differs")
                final += 1
            totals.append(values[2])
        except Exception as error:
            errors.append(dict(attempt=str(path), error=repr(error)))
    missing_prior = sorted(prior-present); missing = len(errors)+len(missing_prior)
    if not final: missing = max(1, missing)
    charge = sum(v+5. for v in totals)+missing*estimate
    return dict(charged_CPU_seconds=charge, observed_CPU_seconds=sum(totals), observed_attempts=len(totals),
        unknown_or_malformed_attempts=missing, missing_prior_invocations=missing_prior, verified_final_CPU_receipts=final,
        receipt_errors=errors, credit_eligible=bool(totals) and not missing and bool(final),
        frozen_component_CPU_seconds=estimate, hard_CPU_quota=False, exact_exit_CPU_measurement=False,
        charge_rule="all observed attempts process+terminated-child CPU +5s each; full estimate per unknown attempt")


def checkpoint(prep, task, descriptor, context, beat):
    import numpy as np
    p = producer(); folder = OUT/"checkpoints"/task["name"]/descriptor["name"]
    identity = dict(context=p.context_identity(task, prep), descriptor=descriptor)
    if folder.exists():
        seal = p.verify_packet(folder, {"chunk.json", "predictions.npz"})
        if seal.get("identity") != identity or seal.get("certified") is not True: raise RuntimeError("regional checkpoint context differs")
        p.validate_arrays(task, p.read_npz(folder/"predictions.npz"), context["scaler"], descriptor)
        with np.load(folder/"predictions.npz", allow_pickle=False) as packet: return {k: packet[k] for k in packet.files}
    wall = time.monotonic(); cpu = time.process_time(); beat(dict(status="chunk_running", chunk=descriptor["name"]))
    prediction, truth, audit = predict(context, task, descriptor, beat)
    arrays = p.retained_arrays(context, task, descriptor, prediction, truth)
    p.validate_arrays(task, p.light(arrays), context["scaler"], descriptor)
    attempt = OUT/"attempts"/task["name"]/(descriptor["name"]+"."+uuid.uuid4().hex); attempt.mkdir(parents=True)
    np.savez_compressed(attempt/"predictions.npz", **arrays)
    write(attempt/"chunk.json", dict(identity=identity, sampler_audit=audit, numerical_threadpools=p.kernel().numerical_threadpools(),
        elapsed_seconds=time.monotonic()-wall, cpu_seconds=time.process_time()-cpu, new_model_fits=0, posterior_updated=False))
    write(attempt/"completed_evidence.json", dict(identity=identity, certified=True,
        artifacts={v: digest(attempt/v) for v in ("chunk.json", "predictions.npz")}))
    folder.parent.mkdir(parents=True, exist_ok=True); os.rename(attempt, folder)
    beat(dict(status="chunk_sealed", chunk=descriptor["name"])); return arrays


def worker(name, cpu, policy_receipt):
    receipt = guard(cpu, policy_receipt, name); prep = read_preparation(); p = producer()
    if name == "__finalize__": return finalize()
    if name == "__benchmark__": return benchmark(prep, cpu, policy_receipt, time.process_time())
    task = task_by_name(name, prep)
    if name not in [v["name"] for v in queue_state()["ready"]] and not task_complete(name):
        raise RuntimeError("regional task not funded or admitted")
    locks = OUT/"locks"; locks.mkdir(parents=True, exist_ok=True)
    with (locks/(name+".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
        if task_complete(name): return dict(status="already_complete", name=name)
        folder, started = start_CPU_attempt(task, prep, receipt, policy_receipt)
        import numpy as np
        def beat(event): write(OUT/"heartbeats"/(name+".json"), dict(event, epoch=time.time(), task=name, cpu=cpu, pid=os.getpid()))
        beat(dict(status="context_loading")); context = p.numerical_context(prep, task); parts = []
        for descriptor in p.chunks(task):
            if time.time() >= receipt["lease_expires_epoch"] or (Path(policy_receipt).parent/"stop_requests"/(name+".json")).exists():
                beat(dict(status="cooperative_checkpoint_stop")); finish_CPU_attempt(folder, started, False)
                return dict(status="deferred_at_checkpoint", name=name)
            parts.append(checkpoint(prep, task, descriptor, context, beat))
        arrays = {k: np.ascontiguousarray(np.concatenate([v[k] for v in parts]), dtype="<i8" if k in p.INT_KEYS else "<f8") for k in p.array_shapes(1)}
        p.validate_arrays(task, p.light(arrays), context["scaler"]); verify_hashes(task["parent_input_sha256"])
        result = dict(name=name, source=prep["source"], certified=True, mode=task["mode"],
            scientific_identity_sha256=task["scientific_identity_sha256"], units="EUR/MWh", metrics=p.metrics(p.light(arrays)),
            origin_clock_windows=len(arrays["origin_positions"]), numerical_threadpools=p.kernel().numerical_threadpools(),
            new_model_fits=0, posterior_updated=False, test_opened=False, promotion_authorized=False)
        attempt = OUT/"attempts"/name/("final."+uuid.uuid4().hex); attempt.mkdir(parents=True)
        np.savez_compressed(attempt/"predictions.npz", **arrays); write(attempt/"result.json", result)
        write(attempt/"completed_evidence.json", dict(context=p.context_identity(task, prep), certified=True,
            artifacts={v: digest(attempt/v) for v in ("result.json", "predictions.npz")}))
        target = OUT/"tasks_done"/name; target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists(): raise RuntimeError("unverified existing regional packet requires review")
        os.rename(attempt, target)
        if not task_complete(name): raise RuntimeError("sealed regional packet failed strict completion")
        finish_CPU_attempt(folder, started, True); beat(dict(status="completed")); return result


def benchmark(prep, cpu, policy_receipt, startup_cpu=0.):
    """Fixed timing panel; compute no candidate loss or scientific selection."""
    import numpy as np
    c = read(CONFIG); p = producer(); receipt = read(policy_receipt)
    begin = time.monotonic(); cpu_begin = time.process_time()
    deadline = min(begin+1200., begin+receipt["lease_expires_epoch"]-time.time())
    rows = []; attempt = OUT/"attempts/__benchmark__"/uuid.uuid4().hex; attempt.mkdir(parents=True)
    def beat(event): write(OUT/"heartbeats/__benchmark__.json", dict(event, epoch=time.time(), task="__benchmark__", cpu=cpu, pid=os.getpid()))
    for mode in ("D", "S"):
        for package in c["benchmark_"+mode+"_packages"]:
            task = task_by_name(name_for(package, 3, mode, 0), prep)
            if time.monotonic() >= deadline: raise RuntimeError("regional benchmark lease exhausted")
            wall0 = time.monotonic(); cpu0 = time.process_time(); beat(dict(status="context_loading", package_id=package, mode=mode))
            context = p.numerical_context(prep, task); cold = time.monotonic()-wall0; cold_cpu = time.process_time()-cpu0
            descriptor = p.chunks(task)[0]; previous = None
            for repetition in range(c["benchmark_"+mode+"_repeats"]):
                if time.monotonic() >= deadline or (Path(policy_receipt).parent/"stop_requests/__benchmark__.json").exists():
                    raise RuntimeError("regional benchmark cap/stop reached; no prefix admitted")
                wall0 = time.monotonic(); cpu0 = time.process_time()
                prediction, truth, audit = predict(context, task, descriptor, beat)
                arithmetic = time.monotonic()-wall0; arithmetic_cpu = time.process_time()-cpu0
                replay = legacy_control_replay(context, task, descriptor, prediction, truth) if package == "C0" and repetition == 0 else None
                if previous is not None and not np.array_equal(prediction, previous): raise RuntimeError("warm regional arithmetic repeat changed")
                previous = prediction.copy()
                wall0 = time.monotonic(); cpu0 = time.process_time(); path = attempt/(mode+"_"+package+"_"+str(repetition)+".npz")
                np.savez_compressed(path, **p.retained_arrays(context, task, descriptor, prediction, truth, compute_loss=False))
                packet_hash = digest(path); packet_bytes = path.stat().st_size
                rows.append(dict(mode=mode, package_id=package, p=task["p"], spec=task["spec"], split=3, clock_offset_steps=0,
                    origin_count=len(descriptor["origin_positions"]), repetition=repetition,
                    cold_context_wall_seconds=cold if repetition == 0 else 0., cold_context_cpu_seconds=cold_cpu if repetition == 0 else 0.,
                    arithmetic_wall_seconds=arithmetic, arithmetic_cpu_seconds=arithmetic_cpu,
                    serialization_wall_seconds=time.monotonic()-wall0, serialization_cpu_seconds=time.process_time()-cpu0,
                    retained_prediction_packet=path.name, retained_prediction_sha256=packet_hash, compressed_bytes=packet_bytes,
                    numerical_threadpools=p.kernel().numerical_threadpools(), sampler_audit=audit, original_control_replay=replay))
            del context
    wall = time.monotonic()-begin; cpu_time = time.process_time()-cpu_begin
    expected = len(c["benchmark_D_packages"])*3+len(c["benchmark_S_packages"])
    if len(rows) != expected or time.monotonic() >= deadline: raise RuntimeError("regional benchmark incomplete or over cap")
    share = min(1., .75*cpu_time/wall)
    # Existing pure pricing API supplies per-task envelopes only; its EE branch
    # totals omit unimported C0 S0 and therefore are deliberately discarded.
    estimates = p.prospective_costs(prep["packages"], prep["tasks"], rows, prep["control"], prep["control"],
        c["audit_key"], startup_cpu, share, 1.5)["task_estimates"]
    price = prefix_contract(prep, estimates, c["max_projected_cpu_seconds"]*share)
    price.update(task_estimates=estimates, source=prep["source"], preparation_sha256=digest(PREP/"preparation.json"),
        status="ADMITTED_COMPLETE_D_AND_WORST_S0_PREFIX" if price["prefix_admitted"] else "DEFERRED_UNFUNDED_COMPLETE_PREFIX",
        finite_three_wave_CPU_ceiling=c["max_projected_cpu_seconds"], contingency_factor=1.5,
        resource_projection=dict(effective_cpu_share=cpu_time/wall, conservative_idle_share=share,
            max_chunk_wall_seconds=max(v["estimated_max_chunk_wall_seconds"] for v in estimates.values()),
            max_observed_chunk_wall_seconds=max(v["arithmetic_wall_seconds"]+v["serialization_wall_seconds"] for v in rows)),
        no_new_candidate_AQL_inspected=True, no_automatic_budget_expansion=True, independent_regional_benchmark=True)
    replay_calls = sum(row["original_control_replay"] is not None for row in rows)
    write(attempt/"timings.json", dict(status="R151_FIXED_TIMINGS_COMPLETE_NO_SELECTION_LOSS", rows=rows,
        arithmetic_calls=expected+replay_calls, timed_prediction_calls=expected, untimed_control_replay_prediction_calls=replay_calls,
        elapsed_seconds=wall, process_CPU_seconds=cpu_time, delivered_effective_cores=cpu_time/wall,
        new_model_fits=0, no_new_candidate_AQL_computed=True, forecast_paths=100, source=prep["source"],
        serialization_schema="retained standardized/EUR/identity NPZ with explicit zero origin_AQL; no loss computed"))
    write(attempt/"branch.json", price)
    write(attempt/"completed_evidence.json", dict(context=dict(source=prep["source"], preparation_sha256=digest(PREP/"preparation.json")),
        artifacts={v: digest(attempt/v) for v in ["timings.json", "branch.json"]+[row["retained_prediction_packet"] for row in rows]}))
    if (OUT/"benchmark").exists(): raise RuntimeError("existing regional benchmark requires strict review")
    os.rename(attempt, OUT/"benchmark"); beat(dict(status="completed", timed_prediction_calls=expected, arithmetic_calls=expected+replay_calls)); return price


def finalize():
    prep = read_preparation(); p = producer(); phase, names, unfunded, terminal = manifest_state()
    if phase == "DEFERRED_UNFUNDED_PREFIX":
        result = dict(status="R151_REGION_DEFERRED_UNFUNDED_COMPLETE_PREFIX", source=prep["source"], pricing=pricing(),
            scientific_complete=False, new_model_fits=0, promotion_authorized=False, automatic_followon_admitted=False)
    else:
        if not terminal or unfunded: raise RuntimeError("regional science incomplete: "+phase)
        verify_hashes(prep["source_sha256"]); verify_hashes(prep["input_sha256"]); verification = []
        for name in names:
            if not task_complete(name): raise RuntimeError("required regional component missing")
            task = task_by_name(name, prep); arrays = p.read_npz(OUT/"tasks_done"/name/"predictions.npz")
            p.validate_arrays(task, arrays, read(task["scaler_path"])); measured = p.metrics(arrays)
            recorded = read(OUT/"tasks_done"/name/"result.json")["metrics"]
            if any(not math.isclose(measured[k], recorded[k], rel_tol=1e-11, abs_tol=1e-10) for k in measured):
                raise RuntimeError("independent regional metric replay differs")
            verification.append(dict(name=name, metrics=measured))
        extra = read_decision("extra_seeds"); confirmed = {}
        control = [component_loss(prep["control"], "S", s) for s in (0, 1, 2)] if extra["qualified"] else []
        for nominee in extra["qualified"]:
            candidate = [component_loss(nominee, "S", s) for s in (0, 1, 2)]
            confirmed[nominee] = dict(p.confirm_gains(control, candidate), control_AQL_by_seed=control, candidate_AQL_by_seed=candidate)
        eligible = {v: -d["mean_gain"] for v, d in confirmed.items() if d["eligible_for_AL_proposal"]}
        lead = p.strongest(eligible) if eligible else None; proposal = None
        if lead:
            package = next(v for v in prep["packages"] if v["package_id"] == lead)
            actual = next(v for v in prep["packages"] if v["package_id"] == prep["control"])
            proposal = dict(package_id=lead, cached_candidate_AL_fits_to_verify=42 if package["candidate_id"] == actual["candidate_id"] else 0,
                new_candidate_fits_if_exact_identity_reused=0 if package["candidate_id"] == actual["candidate_id"] else 21,
                forecast_components=18, paths=500, default_iterations=300, operator="cdf_pool_clipped",
                same_package_Normal_driver_and_AL_receiver=True, launched=False, separate_budget_required=True)
        result = dict(status="R151_REGION_SCIENTIFICALLY_COMPLETE_NOT_PROMOTED", source=prep["source"], region=prep["region"],
            scientific_complete=True,
            required_components=len(names), verified_components=len(verification), verification=verification,
            nominations=read_decision("nominees"), extra_seed_decision=extra, matched_three_seed_results=confirmed,
            conditional_AL_proposal=proposal, new_model_fits=0, official_test_opened=False, independent_confirmation=False,
            automatic_followon_admitted=False, disposition="ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED" if lead else "STOP_NO_STABLE_PRACTICAL_LEAD")
    immutable(OUT/"assessment.json", result)
    immutable(OUT/"assessment_seal.json", dict(sha256=digest(OUT/"assessment.json"), source=prep["source"]))
    return result


def metadata_audit():
    value = build_preparation(dict(head="METADATA_AUDIT_NO_RELEASE", branch=read(CONFIG)["required_branch"]))
    return dict(status="PASS_REGIONAL_METADATA_NO_FORECAST_OR_DATA_WRITES", packages=len(value["packages"]),
        potential_components=len(value["tasks"]), source_pins=len(value["source_sha256"]), input_pins=len(value["input_sha256"]),
        cohort_audit=value["cohort_audit"], new_model_fits=0, numerical_imports=[n for n in ("numpy", "pandas", "scipy") if n in sys.modules])


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("action", choices=["prepare", "status", "advance", "worker", "finalize", "metadata-audit"])
    parser.add_argument("--name"); parser.add_argument("--cpu", type=int); parser.add_argument("--policy-receipt", type=Path)
    parser.add_argument("--remaining-CPU-seconds", type=float); args = parser.parse_args()
    if args.action == "prepare": value = prepare()
    elif args.action == "status": value = queue_state()
    elif args.action == "advance": value = advance(args.remaining_CPU_seconds)
    elif args.action == "worker": value = worker(args.name, args.cpu, args.policy_receipt)
    elif args.action == "finalize":
        if args.cpu is None or args.policy_receipt is None: parser.error("finalize requires an owned CPU/policy receipt")
        guard(args.cpu, args.policy_receipt, "__finalize__"); value = finalize()
    else: value = metadata_audit()
    print(json.dumps(value, sort_keys=True, allow_nan=False), flush=True)


if __name__ == "__main__": main()
