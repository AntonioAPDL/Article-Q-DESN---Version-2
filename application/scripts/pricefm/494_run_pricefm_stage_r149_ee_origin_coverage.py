#!/usr/bin/env python3
"""R149: retained-posterior, train-only origin coverage and MC sensitivity.

Numerical imports occur only inside the guarded worker/preparation entry points.
Original R137 fits and R148 records retain their original producer identities.
"""
from __future__ import annotations

import argparse
import array
import ast
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = "pricefm_stage_r149_ee_origin_coverage_20261023"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CONFIG = ROOT / "application/config" / (TAG + ".json")
PREP = DATA / "launch_prep" / TAG
OUT = DATA / "campaigns" / TAG
METRICS = ("AQL", "median_MAE", "coverage_80", "width_80")
QUANTILES = (.1, .25, .45, .5, .55, .75, .9)
_KERNEL = None
_VALIDATED = {}


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode()).hexdigest()


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n")
    os.replace(temporary, path)


def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError("immutable R149 record differs: " + str(path))
    else:
        write(path, value)


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected:
            raise RuntimeError("pinned original record changed: " + path)


def source_identity():
    config = read(CONFIG)
    branch = git(ROOT, "branch", "--show-current")
    if branch != config["required_branch"] or git(ROOT, "status", "--porcelain"):
        raise RuntimeError("clean committed dedicated R149 source required")
    return dict(branch=branch, head=git(ROOT, "rev-parse", "HEAD"))


def validate_config(c):
    prohibited = ("al_authorized", "exal_authorized", "joint_authorized", "mcmc_authorized",
        "official_evaluation_authorized", "promotion_authorized", "registry_mutation_authorized",
        "article_mutation_authorized", "test_used_for_selection", "automatic_future_stage_authorized")
    if any(c.get(k) is not False for k in prohibited):
        raise ValueError("R149 forbids fitting, official evaluation and automatic admission")
    if (c["tag"] != TAG or c["region"] != "EE" or c["splits"] != [1, 2, 3]
            or c["choices"] != {"C0": "r134_0cab1abbe8ace168", "C5": "r134_19b9f530c3d2246e"}
            or c["full_daily_counts"] != {"1": 124, "2": 134, "3": 173}
            or c["clock_offsets_steps"] != [0, 24, 48, 72] or c["paths"] != 100
            or c["horizon_steps"] != 96 or c["quantiles"] != list(QUANTILES)
            or c["task_count"] != 18 or c["new_model_fits"] != 0 or c["new_geometry_count"] != 0
            or c["chunk_origins"] != 8 or c["extra_MC_master_seeds"] != [2026102301, 2026102302]
            or c["allowed_task_kinds"] != ["full_origin_replay", "mc_panel_replay"]
            or c["replay_atol"] != 1e-12 or c["replay_rtol"] != 1e-10
            or c["primary_aggregation"] != "equal_three_inner_split_macro"
            or c["eligible_support"] != "validation_positions_except_last_for_all_four_clock_offsets"):
        raise ValueError("R149 frozen scientific allocation differs")
    return c


def kernel():
    global _KERNEL
    c = validate_config(read(CONFIG))
    path = Path(c["parent_root"]) / "application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py"
    if digest(path) != c["parent_kernel_sha256"]:
        raise RuntimeError("frozen R148 numerical kernel changed")
    if _KERNEL is None:
        spec = importlib.util.spec_from_file_location("pricefm_r149_immutable_r148", path)
        _KERNEL = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_KERNEL)
    return _KERNEL


def guarded_runtime(cpu=None):
    kernel().guarded_runtime(cpu)


def parent_manifest(check_all=False):
    c = validate_config(read(CONFIG))
    if (git(c["parent_root"], "rev-parse", "HEAD") != c["parent_head"]
            or git(c["parent_root"], "status", "--porcelain")):
        raise RuntimeError("frozen R148 worktree changed")
    verify_hashes(c["parent_pins"])
    parent = kernel().read_preparation()
    if parent["source"]["head"] != c["parent_head"]:
        raise RuntimeError("R148 producer differs")
    if check_all:
        verify_hashes(parent["source_sha256"])
        verify_hashes(parent["input_sha256"])
        verify_hashes({v["path"]: v["sha256"] for v in parent["banks"].values()})
    return parent


def task_name(role, split, seed_index):
    return f"EE_{role}_s{split}_" + ("full_seed0" if seed_index == 0 else f"mc_seed{seed_index}_panel48")


def scientific_identity(task):
    """Stable replay identity, distinct from this run's producer/source identity."""
    keys = ("region", "role", "candidate_id", "split", "kind", "spec", "tau0", "parent_source",
        "parent_task", "parent_seal_sha256", "parent_input_sha256", "parent_fit", "scaler_path",
        "scaler_sha256", "bank", "paths", "forecast_seed", "seed_index", "clock_offsets_steps",
        "daily_origin_positions", "validation_origin_positions", "train_origin_positions",
        "origin_timestamps", "original_panels", "parent_r148_result_sha256", "kernel_sha256")
    return {k: task[k] for k in keys}


def build_preparation(identity):
    c = validate_config(read(CONFIG))
    parent = parent_manifest(check_all=True)
    tasks, inputs = [], dict(c["parent_pins"])
    for role, candidate in c["choices"].items():
        for split in c["splits"]:
            old = next(t for t in parent["tasks"] if t["candidate_id"] == candidate and t["split"] == split)
            if not kernel().task_complete(old["name"]):
                raise RuntimeError("R148 original paired result incomplete")
            old_folder = kernel().OUT / "tasks_done" / old["name"]
            old_paths = [kernel().OUT / "tasks" / (old["name"] + ".json"),
                         old_folder / "result.json", old_folder / "completed_evidence.json"]
            inputs.update({str(p): digest(p) for p in old_paths})
            inputs.update(old["parent_input_sha256"])
            inputs[old["scaler_path"]] = old["scaler_sha256"]
            validation = old["panels"]["validation_origin_positions"]
            full = validation[:-1]
            if len(full) != c["full_daily_counts"][str(split)]:
                raise RuntimeError("eligible common-origin count differs")
            if role == "C0" and old["tau0"] != .0024929739307713865:
                raise RuntimeError("actual frozen control tau0 differs")
            for seed_index, seed in enumerate([old["forecast_seed"]] + c["extra_MC_master_seeds"]):
                daily = full if seed_index == 0 else [validation[i] for i in old["panels"]["large"]]
                stamps = {}
                # R148 timestamp manifest gives an exact daily anchor for each small/large index.
                anchor0 = dt.datetime.fromisoformat(old["panels"]["large_daily_anchors"][0])
                position0 = validation[old["panels"]["large"][0]]
                for offset in c["clock_offsets_steps"]:
                    stamps[str(offset)] = [(anchor0 + dt.timedelta(days=i-position0,
                        minutes=15*offset)).isoformat() for i in daily]
                task = {k: old[k] for k in ("candidate_id", "spec", "specification_sha256", "tau0",
                    "parent_task", "parent_fit", "parent_source", "parent_seal_sha256",
                    "parent_input_sha256", "scaler_path", "scaler_sha256", "bank")}
                task.update(name=task_name(role, split, seed_index), region="EE", role=role, split=split,
                    kind="full_origin_replay" if seed_index == 0 else "mc_panel_replay",
                    seed_index=seed_index, forecast_seed=seed, paths=100,
                    clock_offsets_steps=c["clock_offsets_steps"], daily_origin_positions=daily,
                    validation_origin_positions=validation,
                    train_origin_positions=old["panels"]["train_origin_positions"],
                    origin_timestamps=stamps, original_panels=old["panels"],
                    parent_r148_task=old["name"], parent_r148_result=str(old_folder / "result.json"),
                    parent_r148_result_sha256=digest(old_folder / "result.json"),
                    kernel_sha256=c["parent_kernel_sha256"],
                    dependency_task=None if seed_index == 0 else task_name(role, split, 0),
                    posterior_updated=False, new_model_fits=0, test_opened=False)
                task["scientific_identity_sha256"] = fingerprint(scientific_identity(task))
                tasks.append(task)
    sources = dict(parent["source_sha256"])
    for pattern in ("application/scripts/pricefm/*r149*.py", "application/config/*r149*.json",
                    "application/tests/*r149*.py"):
        sources.update({str(p): digest(p) for p in ROOT.glob(pattern)})
    for p in (ENTRY, CONFIG, ROOT / "application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py",
              ROOT / "docs/implementation_notes/pricefm_stage_r149_ee_origin_coverage_20261023.md"):
        sources[str(p)] = digest(p)
    result = dict(status="R149_PREPARED_TRAINING_ONLY_NOT_PROMOTED", source=identity,
        config_sha256=digest(CONFIG), parent_source=parent["source"], source_sha256=sources,
        input_sha256=inputs, dependency=parent["dependency"], dependency_head=parent["dependency_head"],
        banks=parent["banks"], task_count=18, tasks=tasks, new_model_fits=0,
        official_evaluation_authorized=False, test_opened=False, posterior_updated=False,
        primary_aggregation=c["primary_aggregation"], secondary_aggregation=c["secondary_aggregation"],
        daily_origins_per_geometry=431, origin_clock_windows_per_geometry=1724,
        last_validation_day_excluded_for_all_clocks=True, paths=100,
        scope="cached_Normal_RHS_moments_only; full_origin_original_seed_plus_sparse_MC_sensitivity",
        numerical_threadpools=[])
    validate_preparation(result)
    return result


def validate_preparation(prep):
    c = validate_config(read(CONFIG))
    if (prep["task_count"] != 18 or len(prep["tasks"]) != 18 or prep["new_model_fits"] != 0
            or prep["test_opened"] is not False or prep["posterior_updated"] is not False
            or prep["official_evaluation_authorized"] is not False
            or prep["parent_source"]["head"] != c["parent_head"]):
        raise RuntimeError("R149 preparation scope differs")
    expected = {(r, s, z) for r in c["choices"] for s in (1, 2, 3) for z in (0, 1, 2)}
    if (len({t["name"] for t in prep["tasks"]}) != 18
            or {(t["role"], t["split"], t["seed_index"]) for t in prep["tasks"]} != expected):
        raise RuntimeError("R149 requires the complete declared eighteen-task DAG")
    original_manifest = read(c["parent_preparation"])
    originals = {t["name"]: t for t in original_manifest["tasks"]}
    if any(prep["source_sha256"].get(p) != h for p, h in original_manifest["source_sha256"].items()):
        raise RuntimeError("original dependency/source ledger was relabelled or truncated")
    for t in prep["tasks"]:
        old = originals[t["parent_r148_task"]]
        z = t["seed_index"]
        validation = old["panels"]["validation_origin_positions"]
        expected_daily = validation[:-1] if z == 0 else [validation[i] for i in old["panels"]["large"]]
        if (t["name"] != task_name(t["role"], t["split"], z)
                or t["candidate_id"] != c["choices"][t["role"]] or t["region"] != "EE"
                or t["kind"] != ("full_origin_replay" if z == 0 else "mc_panel_replay")
                or t["forecast_seed"] != ([old["forecast_seed"]] + c["extra_MC_master_seeds"])[z]
                or t["paths"] != 100 or t["clock_offsets_steps"] != [0, 24, 48, 72]
                or t["daily_origin_positions"] != expected_daily
                or t["validation_origin_positions"] != validation
                or t["train_origin_positions"] != old["panels"]["train_origin_positions"]
                or t["original_panels"] != old["panels"]
                or t["dependency_task"] != (None if z == 0 else task_name(t["role"], t["split"], 0))
                or t["posterior_updated"] is not False or t["new_model_fits"] != 0
                or t["test_opened"] is not False
                or t["scientific_identity_sha256"] != fingerprint(scientific_identity(t))):
            raise RuntimeError("R149 descriptor cohort/seed/scope differs")
        for key in ("candidate_id", "spec", "specification_sha256", "tau0", "parent_task", "parent_fit",
                    "parent_source", "parent_seal_sha256", "parent_input_sha256", "scaler_path", "scaler_sha256", "bank"):
            if t[key] != old[key]:
                raise RuntimeError("original cached provenance was relabelled: " + key)
        if (t["kernel_sha256"] != c["parent_kernel_sha256"]
                or t["parent_r148_result_sha256"] != prep["input_sha256"].get(t["parent_r148_result"])):
            raise RuntimeError("original kernel/result ledger identity differs")
        expected_inputs = dict(t["parent_input_sha256"])
        expected_inputs[t["scaler_path"]] = t["scaler_sha256"]
        if any(prep["input_sha256"].get(p) != h for p, h in expected_inputs.items()):
            raise RuntimeError("original fit/scaler input ledger was truncated")
        for offset in t["clock_offsets_steps"]:
            start = dt.datetime.fromisoformat(old["panels"]["large_daily_anchors"][0])
            base = validation[old["panels"]["large"][0]]
            stamps = [(start + dt.timedelta(days=i-base, minutes=15*offset)).isoformat() for i in expected_daily]
            if t["origin_timestamps"][str(offset)] != stamps:
                raise RuntimeError("origin timestamps differ from original cohort")
    return prep


def prepare():
    guarded_runtime()
    if (PREP / "prepared.json").exists():
        prep = read_preparation()
        verify_hashes(prep["source_sha256"])
        verify_hashes(prep["input_sha256"])
        return prep
    prep = build_preparation(source_identity())
    for task in prep["tasks"]:
        immutable(OUT / "tasks" / (task["name"] + ".json"), task)
    immutable(PREP / "preparation.json", prep)
    immutable(PREP / "prepared.json", dict(preparation_sha256=digest(PREP / "preparation.json"),
        source=prep["source"], config_sha256=digest(CONFIG)))
    return prep


def read_preparation():
    receipt = read(PREP / "prepared.json")
    if receipt["preparation_sha256"] != digest(PREP / "preparation.json"):
        raise RuntimeError("R149 prepared manifest changed")
    prep = read(PREP / "preparation.json")
    if (prep["source"] != source_identity() or prep["config_sha256"] != digest(CONFIG)
            or receipt["source"] != prep["source"] or receipt["config_sha256"] != prep["config_sha256"]):
        raise RuntimeError("R149 prepared producer source differs")
    return validate_preparation(prep)


def preparation_complete():
    if not (PREP / "prepared.json").is_file():
        return False
    read_preparation()
    return True


def checkpoint_context(task, source):
    return dict(source=source, task_sha256=fingerprint(task),
        scientific_identity_sha256=task["scientific_identity_sha256"],
        original_parent_source=task["parent_source"], parent_seal_sha256=task["parent_seal_sha256"],
        scaler_sha256=task["scaler_sha256"], bank=task["bank"], forecast_seed=task["forecast_seed"],
        paths=task["paths"], horizon_steps=96, quantiles=list(QUANTILES),
        kernel_sha256=task["kernel_sha256"])


def chunk_descriptors(task):
    result = []
    for offset in task["clock_offsets_steps"]:
        for start in range(0, len(task["daily_origin_positions"]), 8):
            positions = task["daily_origin_positions"][start:start + 8]
            result.append(dict(name=f"clock{offset:02d}_part{start//8:03d}", clock_offset_steps=offset,
                start=start, origin_positions=positions,
                origin_timestamps=task["origin_timestamps"][str(offset)][start:start + 8],
                stable_rng_origin_keys=[i*96+offset for i in positions]))
    return result


def array_shapes(n, reference=False):
    shapes = {"origin_positions": (n,), "clock_offsets": (n,), "stable_rng_origin_keys": (n,),
        "origin_timestamps_ns": (n,), "weekday_UTC": (n,), "month_UTC": (n,),
        "truth_standardized": (n, 96), "truth_eur": (n, 96),
        "deterministic_standardized": (n, 96, 7), "stochastic_standardized": (n, 96, 7),
        "deterministic_eur": (n, 96, 7), "stochastic_eur": (n, 96, 7),
        "deterministic_origin_AQL": (n,), "stochastic_origin_AQL": (n,),
        "lag_features": (n, 4)}
    if reference:
        shapes.update(R148_deterministic_reference=(48, 96, 7),
            R148_reference_origin_positions=(48,), R148_reference_clock_offsets=(48,))
    return shapes


INT_ARRAYS = {"origin_positions", "clock_offsets", "stable_rng_origin_keys", "origin_timestamps_ns", "weekday_UTC", "month_UTC",
              "R148_reference_origin_positions", "R148_reference_clock_offsets"}


def load_npz_light(path):
    """Validate numeric NPZ using only the standard library in the resource parent."""
    result = {}
    with zipfile.ZipFile(path) as packet:
        names = packet.namelist()
        if len(names) != len(set(names)) or any(not n.endswith(".npy") or "/" in n for n in names):
            raise RuntimeError("invalid numeric packet members")
        for name in names:
            payload = packet.read(name)
            if payload[:6] != b"\x93NUMPY" or payload[6:8] not in (b"\x01\x00", b"\x02\x00"):
                raise RuntimeError("unsupported numeric packet")
            width = 2 if payload[6] == 1 else 4
            size = int.from_bytes(payload[8:8+width], "little")
            header = ast.literal_eval(payload[8+width:8+width+size].decode("latin1").strip())
            key = name[:-4]
            expected = "<i8" if key in INT_ARRAYS else "<f8"
            if header["descr"] != expected or header["fortran_order"] is not False:
                raise RuntimeError("numeric packet dtype/order differs")
            shape = tuple(header["shape"])
            values = array.array("q" if key in INT_ARRAYS else "d")
            values.frombytes(payload[8+width+size:])
            if sys.byteorder != "little":
                values.byteswap()
            if len(values) != math.prod(shape) or any(not math.isfinite(v) for v in values):
                raise RuntimeError("nonfinite or truncated numeric packet")
            result[key] = (shape, values)
    return result


def as_light(arrays):
    if all(isinstance(v, tuple) and len(v) == 2 for v in arrays.values()):
        return arrays
    return {k: (tuple(v.shape), v.ravel().tolist()) for k, v in arrays.items()}


def expected_rows(task, descriptor=None):
    if descriptor is not None:
        return [(p, descriptor["clock_offset_steps"], s) for p, s in
                zip(descriptor["origin_positions"], descriptor["origin_timestamps"])]
    return [(p, offset, stamp) for offset in task["clock_offsets_steps"]
        for p, stamp in zip(task["daily_origin_positions"], task["origin_timestamps"][str(offset)])]


def validate_arrays(task, arrays, descriptor=None):
    arrays = as_light(arrays)
    rows = expected_rows(task, descriptor)
    n = len(rows)
    shapes = array_shapes(n, reference=descriptor is None and task["seed_index"] == 0)
    if set(arrays) != set(shapes) or any(arrays[k][0] != shape for k, shape in shapes.items()):
        raise RuntimeError("retained prediction/loss packet has invalid shapes or members")
    for key, (_, values) in arrays.items():
        if any(not math.isfinite(v) for v in values):
            raise RuntimeError("nonfinite retained array: " + key)
    for key, wanted in (("origin_positions", [v[0] for v in rows]),
                        ("clock_offsets", [v[1] for v in rows]),
                        ("stable_rng_origin_keys", [v[0]*96+v[1] for v in rows]),
                        ("origin_timestamps_ns", [round(dt.datetime.fromisoformat(v[2]).timestamp()*1e9) for v in rows]),
                        ("weekday_UTC", [dt.datetime.fromisoformat(v[2]).weekday() for v in rows]),
                        ("month_UTC", [dt.datetime.fromisoformat(v[2]).month for v in rows])):
        if list(arrays[key][1]) != wanted:
            raise RuntimeError("exact retained origin/clock identity differs: " + key)
    scaler = read(task["scaler_path"])
    center, scale = scaler["price_mean"], scaler["price_scale"]
    if not math.isfinite(center) or not math.isfinite(scale) or scale <= 0:
        raise RuntimeError("invalid original training scaler")
    for base in ("truth", "deterministic", "stochastic"):
        for a, b in zip(arrays[base+"_standardized"][1], arrays[base+"_eur"][1]):
            if not math.isclose(a*scale+center, b, rel_tol=1e-12, abs_tol=1e-10):
                raise RuntimeError("standardized/EUR identity differs")
    truth = arrays["truth_eur"][1]
    for policy in ("deterministic", "stochastic"):
        pred = arrays[policy+"_eur"][1]
        losses = arrays[policy+"_origin_AQL"][1]
        for i in range(n):
            total = 0.0
            for h in range(96):
                previous = -math.inf
                for q, level in enumerate(QUANTILES):
                    value = pred[(i*96+h)*7+q]
                    if value < previous - 1e-12:
                        raise RuntimeError("crossing retained quantiles")
                    previous = value
                    error = truth[i*96+h]-value
                    total += max(level*error, (level-1)*error)
            if not math.isclose(losses[i], total/(96*7), rel_tol=1e-11, abs_tol=1e-10):
                raise RuntimeError("retained per-origin loss differs from predictions")
    return arrays


def selected_values(a, name, rows):
    shape, values = a[name]
    width = math.prod(shape[1:])
    return [v for i in rows for v in values[i*width:(i+1)*width]]


def byte_hash(values):
    values = array.array("d", values)
    if sys.byteorder != "little":
        values.byteswap()
    return hashlib.sha256(values.tobytes()).hexdigest()


def validate_replay_arrays(task, arrays):
    """Recheck original hashes and tolerant reference comparison from retained bytes."""
    a = as_light(arrays)
    old = read(task["parent_r148_result"])
    if digest(task["parent_r148_result"]) != task["parent_r148_result_sha256"]:
        raise RuntimeError("original R148 paired record changed")
    panels = task["original_panels"]
    validation = task["validation_origin_positions"]
    daily = task["daily_origin_positions"]
    large = [validation[i] for i in panels["large"]]
    small = [validation[i] for i in panels["small"]]
    expected_ref_positions = large*4
    expected_ref_offsets = [offset for offset in (0, 24, 48, 72) for _ in large]
    if (list(a["R148_reference_origin_positions"][1]) != expected_ref_positions
            or list(a["R148_reference_clock_offsets"][1]) != expected_ref_offsets):
        raise RuntimeError("canonical R148 deterministic reference coverage differs")
    c = validate_config(read(CONFIG))
    reference = a["R148_deterministic_reference"][1]
    for j, offset in enumerate((0, 24, 48, 72)):
        identity = old["origin_identities"][j]
        if identity["clock_offset_steps"] != offset:
            raise RuntimeError("R148 clock order differs")
        large_rows = [j*len(daily)+daily.index(i) for i in large]
        small_rows = [j*len(daily)+daily.index(i) for i in small]
        if (byte_hash(selected_values(a, "stochastic_standardized", large_rows)) != identity["large_prediction_sha256"]
                or byte_hash(selected_values(a, "stochastic_standardized", small_rows)) != identity["small_prediction_sha256"]):
            raise RuntimeError("original stochastic prediction bytes were not replayed exactly")
        ref_small = [j*12+large.index(i) for i in small]
        if byte_hash(selected_values(a, "R148_deterministic_reference", ref_small)) != identity["deterministic_small_prediction_sha256"]:
            raise RuntimeError("canonical frozen twelve-origin deterministic reference hash differs")
        full = selected_values(a, "deterministic_standardized", large_rows)
        target = reference[j*12*96*7:(j+1)*12*96*7]
        if any(abs(v-w) > c["replay_atol"]+c["replay_rtol"]*abs(w) for v, w in zip(full, target)):
            raise RuntimeError("full/chunk deterministic predictions fail declared replay tolerance")


def validate_chunk(task, descriptor, metadata, arrays=None, source=None):
    if descriptor not in chunk_descriptors(task):
        raise RuntimeError("unknown or altered checkpoint coverage")
    if (metadata.get("certified") is not True or metadata.get("descriptor") != descriptor
            or metadata.get("context") != checkpoint_context(task, source or read_preparation()["source"])
            or metadata.get("posterior_updated") is not False or metadata.get("new_model_fits") != 0):
        raise RuntimeError("checkpoint source/posterior/seed context differs")
    if arrays is not None:
        validate_arrays(task, arrays, descriptor)


def verify_packet(folder, artifact_names):
    folder = Path(folder)
    seal = read(folder / "completed_evidence.json")
    if set(seal.get("artifacts", {})) != set(artifact_names):
        raise RuntimeError("sealed packet lacks exact required artifact set")
    for name, expected in seal["artifacts"].items():
        if digest(folder / name) != expected:
            raise RuntimeError("sealed artifact changed: " + str(folder / name))
    return seal


def metrics_light(arrays, positions=None):
    a = as_light(arrays)
    idx = list(range(a["truth_eur"][0][0])) if positions is None else positions
    truth = a["truth_eur"][1]
    result = {}
    for policy in ("deterministic", "stochastic"):
        pred, losses = a[policy+"_eur"][1], a[policy+"_origin_AQL"][1]
        mae = covered = width = 0.0
        for i in idx:
            for h in range(96):
                base = (i*96+h)*7
                y = truth[i*96+h]
                mae += abs(y-pred[base+3])
                covered += pred[base] <= y <= pred[base+6]
                width += pred[base+6]-pred[base]
        result[policy] = dict(AQL=sum(losses[i] for i in idx)/len(idx),
            median_MAE=mae/(len(idx)*96), coverage_80=covered/(len(idx)*96), width_80=width/(len(idx)*96))
    return result


def validate_result(task, result, arrays=None):
    if (result.get("certified") is not True or result.get("kind") != task["kind"]
            or any(result.get(k) != task[k] for k in ("candidate_id", "role", "split", "tau0", "forecast_seed", "seed_index"))
            or result.get("scientific_identity_sha256") != task["scientific_identity_sha256"]
            or result.get("posterior_updated") is not False or result.get("new_model_fits") != 0
            or result.get("test_opened") is not False or result.get("units") != "EUR/MWh"
            or result.get("paths") != 100 or result.get("equal_origin_weights") is not True
            or result.get("origin_clock_windows") != 4*len(task["daily_origin_positions"])
            or result.get("daily_origin_count") != len(task["daily_origin_positions"])
            or result.get("automatic_future_stage_authorized") is not False
            or result.get("original_moments_unchanged") is not True):
        raise RuntimeError("R149 result scope/identity differs")
    pools = result.get("numerical_threadpools", [])
    if not pools or any(p.get("num_threads") != 1 for p in pools):
        raise RuntimeError("R149 result lacks actual single numerical thread proof")
    if task["seed_index"] == 0:
        proof = result.get("R148_replay", {})
        if (proof.get("stochastic_bitwise_verified") is not True
                or proof.get("canonical_deterministic_reference_hash_verified") is not True
                or proof.get("full_deterministic_subset_within_predeclared_tolerance") is not True
                or proof.get("clock_count") != 4):
            raise RuntimeError("original-seed replay proof incomplete")
    else:
        if (result.get("MC_scope") != "nested48_conditional_MC_only_not_full_cohort_stability"
                or result.get("dependency_task") != task["dependency_task"]
                or result.get("dependency_seal_sha256") != digest(OUT / "tasks_done" / task["dependency_task"] / "completed_evidence.json")):
            raise RuntimeError("MC dependency/scope differs")
    if set(result.get("metrics", {})) != {"deterministic", "stochastic"}:
        raise RuntimeError("missing retained policy metrics")
    clocks = result.get("clock_metrics", [])
    if [r.get("clock_offset_steps") for r in clocks] != [0, 24, 48, 72]:
        raise RuntimeError("result four-clock support differs")
    for policy in ("deterministic", "stochastic"):
        for key in METRICS:
            values = [result["metrics"][policy][key]] + [r["metrics"][policy][key] for r in clocks]
            if any(isinstance(v, bool) or not isinstance(v, (float, int)) or not math.isfinite(v)
                   or v < 0 or (key == "coverage_80" and v > 1) for v in values):
                raise RuntimeError("invalid result metric")
            if not math.isclose(values[0], sum(values[1:])/4, rel_tol=1e-12, abs_tol=1e-10):
                raise RuntimeError("result unequal clock weighting")
    if arrays is not None:
        a = validate_arrays(task, arrays)
        if task["seed_index"] == 0:
            validate_replay_arrays(task, a)
        expected = metrics_light(a)
        for policy in expected:
            for key, value in expected[policy].items():
                if not math.isclose(result["metrics"][policy][key], value, rel_tol=1e-11, abs_tol=1e-10):
                    raise RuntimeError("retained prediction metrics disagree with result")
        n = len(task["daily_origin_positions"])
        for i, row in enumerate(clocks):
            expected = metrics_light(a, list(range(i*n, (i+1)*n)))
            for policy in expected:
                for key, value in expected[policy].items():
                    if not math.isclose(row["metrics"][policy][key], value, rel_tol=1e-11, abs_tol=1e-10):
                        raise RuntimeError("clock metrics disagree with exact retained rows")
        if task["seed_index"] == 0:
            for label, key in (("16", "small"), ("48", "large")):
                origins = [task["validation_origin_positions"][i] for i in task["original_panels"][key]]
                n = len(task["daily_origin_positions"])
                selection = [j*n+task["daily_origin_positions"].index(i) for j in range(4) for i in origins]
                measured = metrics_light(a, selection)
                for policy in measured:
                    for key, value in measured[policy].items():
                        if not math.isclose(result["original_nested_panel_metrics"][label][policy][key], value,
                                            rel_tol=1e-11, abs_tol=1e-10):
                            raise RuntimeError("extracted old panel metrics differ from retained common rows")


def validate_MC_arrays(task, arrays, full_arrays):
    a, full = as_light(arrays), as_light(full_arrays)
    full_pairs = list(zip(full["origin_positions"][1], full["clock_offsets"][1]))
    wanted = list(zip(a["origin_positions"][1], a["clock_offsets"][1]))
    if len(full_pairs) != len(set(full_pairs)):
        raise RuntimeError("MC dependency has duplicate origin/clock rows")
    indices = [full_pairs.index(pair) for pair in wanted]
    for key in ("deterministic_standardized", "deterministic_eur", "truth_standardized", "truth_eur",
                "deterministic_origin_AQL", "lag_features"):
        if list(a[key][1]) != selected_values(full, key, indices):
            raise RuntimeError("MC retained deterministic/truth/lag rows differ from full dependency: " + key)


def task_complete(name):
    prep = read_preparation()
    task = next((t for t in prep["tasks"] if t["name"] == name), None)
    if task is None:
        raise ValueError("unknown R149 task")
    folder = OUT / "tasks_done" / name
    if not folder.exists():
        return False
    if task["dependency_task"] and not task_complete(task["dependency_task"]):
        raise RuntimeError("MC completed packet has no valid full original-seed dependency")
    descriptor_path = OUT / "tasks" / (name + ".json")
    if read(descriptor_path) != task:
        raise RuntimeError("immutable R149 task descriptor differs")
    paths = [descriptor_path, Path(task["scaler_path"]), Path(task["parent_r148_result"])] + [folder / p for p in ("completed_evidence.json", "result.json", "predictions.npz")]
    if task["dependency_task"]:
        paths += [OUT / "tasks_done" / task["dependency_task"] / p for p in ("completed_evidence.json", "result.json", "predictions.npz")]
    signature = (fingerprint(task), prep["source"]["head"], tuple(
        (str(p), p.stat().st_mtime_ns, p.stat().st_ctime_ns, p.stat().st_size) for p in paths))
    if _VALIDATED.get(name) == signature:
        return True
    verify_hashes({task["scaler_path"]: task["scaler_sha256"], task["parent_r148_result"]: task["parent_r148_result_sha256"]})
    seal = verify_packet(folder, {"result.json", "predictions.npz"})
    if (seal["metadata"].get("context") != checkpoint_context(task, prep["source"])
            or seal["metadata"].get("certified") is not True
            or seal["metadata"].get("source_head") != prep["source"]["head"]):
        raise RuntimeError("completed task producer/context differs")
    arrays = load_npz_light(folder / "predictions.npz")
    validate_result(task, read(folder / "result.json"), arrays)
    if task["dependency_task"]:
        validate_MC_arrays(task, arrays, load_npz_light(OUT / "tasks_done" / task["dependency_task"] / "predictions.npz"))
    _VALIDATED[name] = signature
    return True


def pending_task_names():
    prep = read_preparation()
    ready = [t for t in prep["tasks"] if not task_complete(t["name"])
        and (t["dependency_task"] is None or task_complete(t["dependency_task"]))]
    return [t["name"] for t in sorted(ready, key=lambda t: (t["seed_index"] != 0, t["role"], t["split"], t["seed_index"]))]


def all_tasks_complete():
    return all(task_complete(t["name"]) for t in read_preparation()["tasks"])


def load_numerical(prep):
    """Import only immutable numerical helpers, without rebinding any R148 globals."""
    parent_config = read(Path(read(CONFIG)["parent_root"]) / "application/config/pricefm_stage_r148_ee_parallel_development_20261023.json")
    engine_root = Path(parent_config["engine_root"])
    if (git(engine_root, "rev-parse", "HEAD") != parent_config["engine_head"]
            or git(engine_root, "status", "--porcelain")
            or git(prep["dependency"], "rev-parse", "HEAD") != prep["dependency_head"]
            or git(prep["dependency"], "status", "--porcelain")):
        raise RuntimeError("frozen numerical worktree changed")
    path = engine_root / "application/scripts/pricefm/pricefm_r134_core.py"
    if digest(path) != parent_config["engine_core_sha256"]:
        raise RuntimeError("frozen R141/R137 numerical core changed")
    spec = importlib.util.spec_from_file_location("pricefm_r149_frozen_core", path)
    core = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(core)
    runtime = core.dependencies(Path(prep["dependency"]))
    kernel().numerical_threadpools()
    return core, runtime


def training_lag_thresholds(raw, train):
    import numpy as np
    # Every value is available strictly before each exact inner-training origin.
    history = raw.price_history[np.asarray(train), -96:]
    ramps = np.diff(history, axis=1)
    values = np.column_stack((np.std(history, axis=1), np.sqrt(np.mean(ramps**2, axis=1)),
                              np.mean(np.abs(ramps), axis=1), np.max(np.abs(ramps), axis=1)))
    return dict(training_origin_positions=list(train), training_origin_identity_sha256=fingerprint(list(train)),
        feature_names=["lag24h_price_SD", "lag24h_ramp_RMS", "lag24h_mean_absolute_ramp", "lag24h_max_absolute_ramp"],
        units="EUR/MWh", quantile_policy="numpy_linear_on_exact_inner_training_origin_features_only",
        q50=np.quantile(values, .5, axis=0).tolist(), q90=np.quantile(values, .9, axis=0).tolist(),
        no_validation_or_official_loss_used=True)


def numerical_context(prep, task):
    import numpy as np
    core, runtime = load_numerical(prep)
    verify_hashes(task["parent_input_sha256"])
    verify_hashes({task["bank"]["path"]: task["bank"]["sha256"], task["scaler_path"]: task["scaler_sha256"],
                   task["parent_r148_result"]: task["parent_r148_result_sha256"]})
    raw = core.load_arrays(runtime, Path(task["bank"]["path"]))
    cell = runtime.internal_splits(len(raw.response))[task["split"]-1]
    if (cell["train"].tolist() != task["train_origin_positions"]
            or cell["validation"].tolist() != task["validation_origin_positions"]):
        raise RuntimeError("frozen inner train/validation cohort changed")
    scaled, scaler = runtime.standardize_from_training_origins(raw, cell["train"])
    if fingerprint(scaler) != fingerprint(read(task["scaler_path"])):
        raise RuntimeError("exact cached training-only scaler changed")
    fit = runtime.load_normal_fit(Path(task["parent_fit"]))
    pools = kernel().numerical_threadpools()
    return dict(core=core, runtime=runtime, raw=raw, scaled=scaled, scaler=scaler, cell=cell, fit=fit,
                pools=pools, thresholds=training_lag_thresholds(raw, cell["train"].tolist()))


def retained_chunk(context, task, descriptor, heartbeat, deterministic_override=None):
    import numpy as np
    from pricefm_r127_contract import shifted_windows, window_identity
    from pricefm_r126_contract import loss
    runtime, core = context["runtime"], context["core"]
    positions = np.asarray(descriptor["origin_positions"], dtype=int)
    offset = descriptor["clock_offset_steps"]
    validation = np.asarray(task["validation_origin_positions"], dtype=int)
    shifted = shifted_windows(context["scaled"], positions, offset, validation)
    raw_shifted = shifted_windows(context["raw"], positions, offset, validation)
    window_identity(shifted,
        dt.datetime.fromisoformat(str(context["raw"].anchors[validation[0]])),
        dt.datetime.fromisoformat(str(context["raw"].anchors[validation[-1]]))+dt.timedelta(days=1))
    if [dt.datetime.fromisoformat(str(a)).isoformat() for a in shifted.anchors] != descriptor["origin_timestamps"]:
        raise RuntimeError("shifted window timestamps differ from frozen descriptor")
    seed = runtime.BASE.deterministic_seed(task["forecast_seed"], "EE", task["split"])
    stochastic, audit = core.normal_predictions(runtime, shifted, task["spec"], context["fit"],
        np.asarray(descriptor["stable_rng_origin_keys"], dtype=int),
        runtime.BASE.deterministic_seed(seed, "clock", offset), paths=100,
        observe=lambda event: heartbeat(dict(event, chunk=descriptor["name"], clock_offset_steps=offset)))
    deterministic = (kernel().deterministic_predictions(runtime, shifted, task["spec"], context["fit"])
                     if deterministic_override is None else deterministic_override)
    scale, center = context["scaler"]["price_scale"], context["scaler"]["price_mean"]
    history = raw_shifted.price_history[:, -96:]
    ramps = np.diff(history, axis=1)
    n = len(positions)
    arrays = dict(origin_positions=positions, clock_offsets=np.full(n, offset),
        stable_rng_origin_keys=np.asarray(descriptor["stable_rng_origin_keys"]),
        origin_timestamps_ns=np.asarray([round(dt.datetime.fromisoformat(s).timestamp()*1e9)
                                         for s in descriptor["origin_timestamps"]]),
        weekday_UTC=np.asarray([dt.datetime.fromisoformat(s).weekday() for s in descriptor["origin_timestamps"]]),
        month_UTC=np.asarray([dt.datetime.fromisoformat(s).month for s in descriptor["origin_timestamps"]]),
        truth_standardized=shifted.response, truth_eur=shifted.response*scale+center,
        deterministic_standardized=deterministic, stochastic_standardized=stochastic,
        deterministic_eur=deterministic*scale+center, stochastic_eur=stochastic*scale+center,
        deterministic_origin_AQL=loss(shifted.response, deterministic).mean(axis=(1, 2))*scale,
        stochastic_origin_AQL=loss(shifted.response, stochastic).mean(axis=(1, 2))*scale,
        lag_features=np.column_stack((np.std(history, axis=1), np.sqrt(np.mean(ramps**2, axis=1)),
            np.mean(np.abs(ramps), axis=1), np.max(np.abs(ramps), axis=1))))
    if not np.allclose(arrays["truth_eur"], raw_shifted.response, rtol=1e-12, atol=1e-10):
        raise RuntimeError("raw shifted truths differ from inverse training scaling")
    arrays = {k: np.ascontiguousarray(v, dtype="<i8" if k in INT_ARRAYS else "<f8") for k, v in arrays.items()}
    validate_arrays(task, arrays, descriptor)
    return arrays, audit


def seal_chunk(prep, task, descriptor, context, heartbeat, deterministic_override=None):
    import numpy as np
    folder = OUT / "checkpoints" / task["name"] / descriptor["name"]
    if folder.exists():
        seal = verify_packet(folder, {"chunk.json", "predictions.npz"})
        metadata = read(folder / "chunk.json")
        if seal["metadata"] != {"context": checkpoint_context(task, prep["source"]), "certified": True}:
            raise RuntimeError("checkpoint seal context differs")
        with np.load(folder / "predictions.npz", allow_pickle=False) as packet:
            arrays = {k: packet[k] for k in packet.files}
        validate_chunk(task, descriptor, metadata, arrays, prep["source"])
        return arrays, metadata
    attempt = OUT / "attempts" / task["name"] / (descriptor["name"]+"."+uuid.uuid4().hex)
    attempt.mkdir(parents=True)
    started = time.time()
    heartbeat(dict(status="chunk_running", chunk=descriptor["name"], origin_count=len(descriptor["origin_positions"])))
    arrays, audit = retained_chunk(context, task, descriptor, heartbeat, deterministic_override)
    metadata = dict(certified=True, descriptor=descriptor, context=checkpoint_context(task, prep["source"]),
        posterior_updated=False, new_model_fits=0, sampler_audit=audit,
        elapsed_seconds=time.time()-started, numerical_threadpools=kernel().numerical_threadpools())
    validate_chunk(task, descriptor, metadata, arrays, prep["source"])
    np.savez_compressed(attempt / "predictions.npz", **arrays)
    write(attempt / "chunk.json", metadata)
    write(attempt / "completed_evidence.json", dict(artifacts={p: digest(attempt/p)
        for p in ("chunk.json", "predictions.npz")}, metadata={"context": checkpoint_context(task, prep["source"]), "certified": True}))
    folder.parent.mkdir(parents=True, exist_ok=True)
    os.rename(attempt, folder)
    heartbeat(dict(status="chunk_sealed", chunk=descriptor["name"], elapsed_seconds=metadata["elapsed_seconds"]))
    return arrays, metadata


def canonical_reference(context, task, arrays):
    import numpy as np
    from pricefm_r127_contract import shifted_windows, common_metrics
    old = read(task["parent_r148_result"])
    panel = task["original_panels"]
    validation = np.asarray(task["validation_origin_positions"], dtype=int)
    large = validation[panel["large"]]
    small_take = [list(panel["large"]).index(i) for i in panel["small"]]
    references, proofs = [], []
    config = validate_config(read(CONFIG))
    for j, offset in enumerate((0, 24, 48, 72)):
        shifted = shifted_windows(context["scaled"], large, offset, validation)
        reference = kernel().deterministic_predictions(context["runtime"], shifted, task["spec"], context["fit"])
        identity = old["origin_identities"][j]
        if hashlib.sha256(reference[small_take].tobytes()).hexdigest() != identity["deterministic_small_prediction_sha256"]:
            raise RuntimeError("canonical original deterministic twelve-batch reference failed byte hash")
        for label, take in (("16", small_take), ("48", list(range(12)))):
            measured = kernel().scaled_metric(common_metrics(shifted.response[take], reference[take]), context["scaler"]["price_scale"])
            expected = old["clock_metrics"]["deterministic"+label][j]
            if any(not math.isclose(measured[k], expected[k], rel_tol=config["replay_rtol"], abs_tol=config["replay_atol"])
                   for k in METRICS):
                raise RuntimeError("canonical deterministic reference did not replay original metrics")
        daily = task["daily_origin_positions"]
        full = arrays["deterministic_standardized"][[j*len(daily)+daily.index(int(i)) for i in large]]
        if not np.allclose(full, reference, rtol=config["replay_rtol"], atol=config["replay_atol"]):
            raise RuntimeError("full/chunk deterministic old-panel replay tolerance exceeded")
        references.append(reference)
        proofs.append(dict(clock_offset_steps=offset, canonical_small_prediction_sha256=identity["deterministic_small_prediction_sha256"],
            max_absolute_difference=float(np.max(np.abs(full-reference))),
            reference_large_sha256=hashlib.sha256(reference.tobytes()).hexdigest()))
    arrays.update(R148_deterministic_reference=np.ascontiguousarray(np.concatenate(references), dtype="<f8"),
        R148_reference_origin_positions=np.asarray(large.tolist()*4, dtype="<i8"),
        R148_reference_clock_offsets=np.asarray([offset for offset in (0, 24, 48, 72) for _ in large], dtype="<i8"))
    validate_replay_arrays(task, arrays)
    return dict(stochastic_bitwise_verified=True, canonical_deterministic_reference_hash_verified=True,
        full_deterministic_subset_within_predeclared_tolerance=True, clock_count=4,
        atol=config["replay_atol"], rtol=config["replay_rtol"], clocks=proofs,
        standardized_prediction_bytes=True,
        proof="canonical_12_row_D_reference_old_small_hash_and_metrics_then_full_subset_tolerance; S_old16_and48_bitwise")


def make_result(prep, task, context, arrays, chunk_records, replay):
    a = as_light(arrays)
    n = len(task["daily_origin_positions"])
    clock_metrics = [dict(clock_offset_steps=offset, metrics=metrics_light(a, list(range(j*n, (j+1)*n))))
        for j, offset in enumerate((0, 24, 48, 72))]
    result = {k: task[k] for k in ("kind", "candidate_id", "role", "split", "tau0", "forecast_seed", "seed_index", "scientific_identity_sha256")}
    result.update(certified=True, metrics=metrics_light(a), clock_metrics=clock_metrics,
        daily_origin_count=n, origin_clock_windows=4*n, equal_origin_weights=True, units="EUR/MWh", paths=100,
        posterior_updated=False, new_model_fits=0, test_opened=False,
        automatic_future_stage_authorized=False, numerical_threadpools=kernel().numerical_threadpools(),
        original_moments_unchanged=True, checkpoint_count=len(chunk_records),
        checkpoint_elapsed_seconds=[v["elapsed_seconds"] for v in chunk_records],
        lag_feature_training_thresholds=context["thresholds"],
        scope="Normal_policy_package_comparison_not_pure_variance_causality; two_prefits_not_unbiased_geometry_search")
    if task["seed_index"] == 0:
        result["R148_replay"] = replay
        panel_metrics = {}
        for label, key in (("16", "small"), ("48", "large")):
            origins = [task["validation_origin_positions"][i] for i in task["original_panels"][key]]
            indices = [j*n+task["daily_origin_positions"].index(i) for j in range(4) for i in origins]
            panel_metrics[label] = metrics_light(a, indices)
        result["original_nested_panel_metrics"] = panel_metrics
    else:
        result.update(MC_scope="nested48_conditional_MC_only_not_full_cohort_stability",
            dependency_task=task["dependency_task"],
            dependency_seal_sha256=digest(OUT / "tasks_done" / task["dependency_task"] / "completed_evidence.json"))
    validate_result(task, result, arrays)
    return result


def worker(name, cpu):
    # Resource supervisor sets priorities before exec; direct ordinary launch is refused.
    guarded_runtime(cpu)
    import numpy as np
    prep = read_preparation()
    task = next((t for t in prep["tasks"] if t["name"] == name), None)
    if task is None:
        raise ValueError("unknown R149 task")
    if task["dependency_task"] and not task_complete(task["dependency_task"]):
        raise RuntimeError("MC task cannot precede its valid original-seed full replay")
    if read(OUT / "tasks" / (name+".json")) != task:
        raise RuntimeError("R149 task descriptor changed")
    locks = OUT / "locks"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks / (name+".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if task_complete(name):
            return {"status": "already_complete", "name": name}
        verify_hashes(prep["source_sha256"])
        context = numerical_context(prep, task)
        started, last_beat = time.time(), [0.0]
        def beat(event):
            now = time.time()
            if now-last_beat[0] >= 5 or event.get("status") in ("running", "completed", "chunk_sealed"):
                write(OUT / "heartbeats" / (name+".json"), dict(event, epoch=now, task=name, cpu=cpu, pid=os.getpid()))
                last_beat[0] = now
        beat({"status": "running"})
        dependency = None
        if task["dependency_task"]:
            with np.load(OUT / "tasks_done" / task["dependency_task"] / "predictions.npz", allow_pickle=False) as packet:
                dependency = {k: packet[k] for k in packet.files}
        chunks, records = [], []
        for descriptor in chunk_descriptors(task):
            deterministic = None
            if dependency is not None:
                pairs = list(zip(dependency["origin_positions"].tolist(), dependency["clock_offsets"].tolist()))
                selection = [pairs.index((p, descriptor["clock_offset_steps"])) for p in descriptor["origin_positions"]]
                deterministic = dependency["deterministic_standardized"][selection]
            arrays, metadata = seal_chunk(prep, task, descriptor, context, beat, deterministic)
            chunks.append(arrays)
            records.append(metadata)
        arrays = {k: np.ascontiguousarray(np.concatenate([v[k] for v in chunks]), dtype="<i8" if k in INT_ARRAYS else "<f8")
                  for k in array_shapes(1)}
        replay = canonical_reference(context, task, arrays) if task["seed_index"] == 0 else None
        verify_hashes(task["parent_input_sha256"])
        verify_hashes({task["scaler_path"]: task["scaler_sha256"], task["bank"]["path"]: task["bank"]["sha256"]})
        result = make_result(prep, task, context, arrays, records, replay)
        attempt = OUT / "attempts" / name / ("final."+uuid.uuid4().hex)
        attempt.mkdir(parents=True)
        np.savez_compressed(attempt / "predictions.npz", **arrays)
        write(attempt / "result.json", result)
        write(attempt / "completed_evidence.json", dict(artifacts={p: digest(attempt/p) for p in ("result.json", "predictions.npz")},
            metadata=dict(context=checkpoint_context(task, prep["source"]), certified=True,
                elapsed_seconds=time.time()-started, cpu=cpu, source_head=prep["source"]["head"])))
        destination = OUT / "tasks_done" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise RuntimeError("existing unverified R149 final packet requires review")
        os.rename(attempt, destination)
        if not task_complete(name):
            raise RuntimeError("sealed R149 result failed independent completion verification")
        beat(dict(status="completed", elapsed_seconds=time.time()-started))
        return result


def paired_days(prep=None):
    prep = read_preparation() if prep is None else prep
    full = [t for t in prep["tasks"] if t["seed_index"] == 0]
    if len(full) != 6 or not all(task_complete(t["name"]) for t in full):
        return []
    tables = {}
    for task in full:
        a = load_npz_light(OUT / "tasks_done" / task["name"] / "predictions.npz")
        n = len(task["daily_origin_positions"])
        for i, origin in enumerate(task["daily_origin_positions"]):
            key = (task["split"], origin)
            row = tables.setdefault(key, dict(split=task["split"], origin_key=origin,
                weekday=int(a["weekday_UTC"][1][i]), month=int(a["month_UTC"][1][i]),
                timestamp=task["origin_timestamps"]["0"][i]))
            row["control_loss" if task["role"] == "C0" else "competitor_loss"] = sum(
                a["stochastic_origin_AQL"][1][j*n+i] for j in range(4))/4
    rows = [tables[k] for k in sorted(tables)]
    if len(rows) != 431 or any(not {"control_loss", "competitor_loss"}.issubset(r) for r in rows):
        raise RuntimeError("paired daily analysis requires exact common 431-day cohort")
    return rows


def status():
    prep = read_preparation()
    completed = [t for t in prep["tasks"] if task_complete(t["name"])]
    groups = {}
    for task in completed:
        groups.setdefault((task["role"], task["seed_index"]), []).append((task, read(OUT / "tasks_done" / task["name"] / "result.json")))
    summaries = {}
    for (role, seed_index), rows in groups.items():
        if {t["split"] for t, _ in rows} != {1, 2, 3}:
            continue
        count = sum(r["origin_clock_windows"] for _, r in rows)
        summary = dict(equal_split_macro={policy: {k: sum(r["metrics"][policy][k] for _, r in rows)/3 for k in METRICS}
            for policy in ("deterministic", "stochastic")},
            pooled_origin_clock={policy: {k: sum(r["metrics"][policy][k]*r["origin_clock_windows"] for _, r in rows)/count for k in METRICS}
            for policy in ("deterministic", "stochastic")}, origin_clock_windows=count,
            split_records=[dict(split=t["split"], metrics=r["metrics"], origin_clock_windows=r["origin_clock_windows"])
                           for t, r in sorted(rows, key=lambda v: v[0]["split"])])
        summaries[f"{role}_seed{seed_index}"] = summary
    contrasts = {}
    for seed_index in (0, 1, 2):
        c, v = (summaries.get(f"{role}_seed{seed_index}") for role in ("C0", "C5"))
        if c and v:
            contrasts[f"seed{seed_index}"] = {scope: {policy: v[scope][policy]["AQL"]-c[scope][policy]["AQL"]
                for policy in ("deterministic", "stochastic")} for scope in ("equal_split_macro", "pooled_origin_clock")}
    sparse = {}
    for role in ("C0", "C5"):
        for z in (0, 1, 2):
            rows = groups.get((role, z), [])
            if {t["split"] for t, _ in rows} == {1, 2, 3}:
                sparse.setdefault(role, {})[str(z)] = sum(
                    (r["original_nested_panel_metrics"]["48"]["stochastic"]["AQL"] if z == 0
                     else r["metrics"]["stochastic"]["AQL"]) for _, r in rows)/3
    sparse_contrasts = {str(z): sparse["C5"][str(z)]-sparse["C0"][str(z)] for z in (0, 1, 2)
                        if all(str(z) in sparse.get(role, {}) for role in ("C0", "C5"))}
    return dict(status="R149_REPLAY_COMPLETE_NOT_PROMOTED" if len(completed) == 18 else "R149_PARTIAL_REPLAY_NOT_PROMOTED",
        source=prep["source"], completed=len(completed), total=18, pending=18-len(completed),
        full_origin_completed=sum(t["seed_index"] == 0 for t in completed),
        sparse_extra_MC_completed=sum(t["seed_index"] != 0 for t in completed),
        complete_three_split_scores=summaries, competitor_minus_control_AQL=contrasts,
        matched_nested48_stochastic_MC_macro_AQL=sparse,
        matched_nested48_stochastic_MC_competitor_minus_control=sparse_contrasts,
        MC_sensitivity_scope="same_nested48_only_original_seed_extracted_from_full; not_full_cohort_MC_stability",
        primary_aggregation="equal_three_inner_split_macro", secondary_aggregation="pooled_daily_origins_times_four_clocks",
        automatic_future_stage_authorized=False, new_model_fits=0, test_opened=False,
        limitations=["two_preselected_cached_fits_not_unbiased_geometry_selection",
            "full_origin_rank_uses_one_forecast_MC_seed", "sparse_three_seed_sensitivity_does_not_establish_full_cohort_rank_stability",
            "policy_package_contrast_not_pure_variance_causality", "official_test_seen_previously_but_not_opened_by_R149"],
        summary_artifact=str(OUT / "closeout.json") if (OUT / "closeout.json").exists() else None)


def write_closeout(reason, details=None):
    snapshot = status()
    rows = paired_days()
    analysis = None
    if rows:
        helper_path = ROOT / "application/scripts/pricefm/pricefm_r149_sampling_analysis.py"
        spec = importlib.util.spec_from_file_location("pricefm_r149_sampling_analysis", helper_path)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        prep = read_preparation()
        panels = {label: {t["split"]: [t["validation_origin_positions"][i] for i in t["original_panels"][key]]
            for t in prep["tasks"] if t["role"] == "C0" and t["seed_index"] == 0}
            for label, key in (("16", "small"), ("48", "large"))}
        analysis = helper.analyze_sampling(rows, legacy_panels=panels)
        write(OUT / "paired_daily_losses.json", rows)
        write(OUT / "sampling_analysis.json", analysis)
    value = dict(snapshot, reason=reason, details=details, epoch=time.time(),
        paired_daily_count=len(rows), sampling_analysis=analysis,
        future_AL_admission=False, future_pool_expansion_authorized=False)
    write(OUT / "closeout.json", value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "worker", "status", "closeout"))
    parser.add_argument("--name")
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--reason", default="manual_read_only_closeout")
    args = parser.parse_args()
    if args.command == "prepare":
        guarded_runtime(args.cpu)
        result = prepare()
        print(json.dumps(dict(status=result["status"], task_count=len(result["tasks"]))))
    elif args.command == "worker":
        if args.name is None or args.cpu is None:
            parser.error("worker requires --name and --cpu")
        result = worker(args.name, args.cpu)
        print(json.dumps({k: result.get(k) for k in ("certified", "kind", "candidate_id", "split")}))
    elif args.command == "closeout":
        print(json.dumps(write_closeout(args.reason)))
    else:
        print(json.dumps(status()))


if __name__ == "__main__":
    main()
