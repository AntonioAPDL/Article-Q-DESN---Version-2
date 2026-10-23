#!/usr/bin/env python3
"""R148: bounded train-only rescoring of retained EE Normal-RHS moments.

Importing this module performs no I/O, numerical imports, fitting or preparation.
The resource supervisor owns scheduling, the two-hour lease and worker teardown.
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
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = "pricefm_stage_r148_ee_parallel_development_20261023"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
CONFIG = ROOT / "application/config" / (TAG + ".json")
OUT = DATA / "campaigns" / TAG
PREP = DATA / "launch_prep" / TAG


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
    path = Path(path)
    if path.exists():
        if read(path) != value:
            raise RuntimeError("immutable R148 record differs: " + str(path))
    else:
        write(path, value)


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def source_identity():
    config = read(CONFIG)
    branch = git(ROOT, "branch", "--show-current")
    if branch != config["required_branch"] or git(ROOT, "status", "--porcelain"):
        raise RuntimeError("clean committed dedicated R148 source required")
    return dict(branch=branch, head=git(ROOT, "rev-parse", "HEAD"))


def validate_config(config):
    false_keys = ("new_rhs_fits_authorized", "al_authorized", "exal_authorized",
                  "joint_authorized", "mcmc_authorized", "official_evaluation_authorized",
                  "registry_mutation_authorized", "article_mutation_authorized",
                  "promotion_authorized", "test_used_for_selection")
    if any(config.get(k) is not False for k in false_keys):
        raise ValueError("R148 forbids fitting, official evaluation and promotion")
    if (config["tag"] != TAG or config["region"] != "EE"
            or config["allowed_worker_kinds"] != ["cached_rhs_rescore"]
            or config["new_ridge_geometries"] != 0 or config["new_ridge_split_fits"] != 0
            or config["distinct_cached_rhs_geometries"] != 6
            or config["stochastic_paths"] != 100 or config["horizon_steps"] != 96
            or config["panel_origin_counts"] != [4, 12]
            or config["clock_offsets_steps"] != [0, 24, 48, 72]
            or config["quantiles"] != [.1, .25, .45, .5, .55, .75, .9]):
        raise ValueError("R148 frozen train-only scoring contract differs")
    return config


def verify_hashes(ledger):
    for path, expected in ledger.items():
        if digest(path) != expected:
            raise RuntimeError("pinned input changed: " + path)


def verify_cached_packet(cache, name, source_head, heavy=True):
    """Retain original task/source identities; never relabel old work as R148."""
    cache = Path(cache)
    task_path = cache / "tasks" / (name + ".json")
    folder = cache / "tasks_done" / name
    seal_path = folder / "completed_evidence.json"
    seal = read(seal_path)
    task = read(task_path)
    required = {"result.json"}
    if task["kind"] == "rhs":
        required |= {"fit/terminal.json", "fit/beta_mean.bin", "fit/beta_cov.bin", "fit/fit_summary.json"}
    elif task["kind"] == "stats":
        required |= {"scaler.json", "stats/terminal.json", "stats/statistics.json"}
    if not required.issubset(seal["artifacts"]):
        raise RuntimeError("cached packet lacks required artifacts: " + name)
    metadata = seal["metadata"]
    if (metadata["source_head"] != source_head
            or metadata["task_sha256"] != digest(task_path)
            or metadata.get("certified") is not True):
        raise RuntimeError("cached task identity/certification differs: " + name)
    ledger = {str(task_path): digest(task_path), str(seal_path): digest(seal_path)}
    for relative, expected in seal["artifacts"].items():
        path = (folder / relative).resolve()
        if folder.resolve() not in path.parents:
            raise RuntimeError("cached artifact escapes packet")
        if heavy or relative in required:
            if digest(path) != expected:
                raise RuntimeError("cached artifact hash differs: " + str(path))
            ledger[str(path)] = expected
    return task, read(folder / "result.json"), ledger


def distinct_selection(ranking, frozen_choice, count):
    selected = []
    seen = set()
    for row in ranking:
        if row["candidate_id"] in seen:
            continue
        row = dict(row)
        seen.add(row["candidate_id"])
        row["scale_role"] = "best_cached_Normal_RHS_scale"
        if row["candidate_id"] == frozen_choice["candidate_id"]:
            match = next((v for v in ranking if v["candidate_id"] == row["candidate_id"]
                          and v["tau0"] == frozen_choice["tau0"]), None)
            if match is None:
                raise RuntimeError("actual frozen control has no certified cached RHS group")
            row = dict(match)
            row["scale_role"] = "actual_frozen_R137_control_scale"
        selected.append(row)
        if len(selected) == count:
            break
    if len(selected) != count:
        raise RuntimeError("insufficient distinct certified cached geometries")
    return selected


def panel_indices(validation_size):
    """Preserve original Ridge4; add eight spread-out original RHS12 candidates."""
    import numpy as np
    old4 = sorted(set(np.linspace(0, validation_size - 2, 4).round().astype(int).tolist()))
    old12 = sorted(set(np.linspace(0, validation_size - 2, 12).round().astype(int).tolist()))
    if len(old4) != 4 or len(old12) != 12:
        raise ValueError("training validation panel too small")
    selected = list(old4)
    while len(selected) < 12:
        available = [i for i in old12 if i not in selected]
        if not available:
            raise RuntimeError("cannot construct nested 4/12-origin panels")
        best = min(available, key=lambda i: (-min(abs(i - j) for j in selected), i))
        selected.append(best)
    return dict(small=old4, large=sorted(selected), historical_rhs=old12,
                nested=True, large_equals_historical_rhs=sorted(selected) == old12)


def proxy_rank_context(ridge, rhs):
    ridge_scores = {v["candidate_id"]: v["mean_AQL"] for v in ridge["ranking"]}
    ridge_ranks = {v["candidate_id"]: i + 1 for i, v in enumerate(ridge["ranking"])}
    best = {}
    for row in rhs["ranking"]:
        best.setdefault(row["candidate_id"], row)
    common = sorted(set(ridge_scores) & set(best))
    rhs_order = sorted(best, key=lambda k: (best[k]["mean_AQL"], k))
    ridge_order_common = sorted(common, key=lambda k: (ridge_scores[k], k))
    return dict(Ridge_geometry_count=len(ridge_scores), RHS_certified_distinct_geometries=len(best),
        common_certified_geometries=len(common),
        conditional_Ridge_vs_RHS_Spearman=None if len(common) < 2 else spearman(
            [ridge_scores[k] for k in common], [best[k]["mean_AQL"] for k in common]),
        RHS_geometry_global_Ridge_ranks={k: ridge_ranks[k] for k in rhs_order if k in ridge_ranks},
        conditional_top5_overlap=len(set(ridge_order_common[:5]) & set(rhs_order[:5])),
        RHS_scale_policy="minimum_cached_Normal_RHS_AQL_per_geometry_no_control_override",
        limitation="conditional_on_Ridge_shortlist_and_three_split_RHS_certification; different_estimators_origin_grids_and_forecast_policies; no_causal_attribution")


def load_engine(config):
    """Use frozen helpers in an isolated namespace; no old controller/worker call."""
    for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS",
                "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS"):
        os.environ[key] = "1"
    engine_root = Path(config["engine_root"])
    directory = engine_root / "application/scripts/pricefm"
    sys.path.insert(0, str(directory))
    prior = os.environ.get("PRICEFM_R141_REGION")
    # R141 reused EE rather than launching an EE controller. Import with an
    # admissible placeholder, then isolate every mutable output global before use.
    os.environ["PRICEFM_R141_REGION"] = "AT"
    try:
        spec = importlib.util.spec_from_file_location("pricefm_r148_frozen_r141_engine",
            directory / "480_run_pricefm_stage_r141_region.py")
        engine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(engine)
    finally:
        if prior is None:
            os.environ.pop("PRICEFM_R141_REGION", None)
        else:
            os.environ["PRICEFM_R141_REGION"] = prior
    if digest(engine.core.__file__) != config["engine_core_sha256"]:
        raise RuntimeError("imported scoring core differs from frozen R141/R137")
    engine.ROOT, engine.OUT, engine.PREP, engine.ENTRY, engine.REGION = ROOT, OUT, PREP, ENTRY, "EE"
    return engine


def audit_cache(config, original):
    cache = Path(config["cache_root"])
    candidates = original["regional"]["EE"]["candidates"]
    if len(candidates) != config["expected_cached_geometries"]:
        raise RuntimeError("EE geometry inventory differs")
    ledger = {}
    records = 0
    for candidate in candidates:
        task, result, hashes = verify_cached_packet(cache, "EE_" + candidate["candidate_id"],
            config["cache_source_head"], heavy=False)
        if (task["kind"] != "ridge" or task["spec"] != candidate["spec"]
                or result.get("heavy_statistics_retained") is not False
                or {v["split"] for v in result["records"]} != {1, 2, 3}):
            raise RuntimeError("cached Ridge descriptor or split coverage differs")
        for record in result["records"]:
            if (record["certified"] is not True or record["origin_clock_pairs"] != 16
                    or record["driver"] != "deterministic_Normal_location_broad_proxy"):
                raise RuntimeError("cached Ridge scoring policy differs")
        records += len(result["records"])
        ledger.update(hashes)
    if records != config["expected_cached_ridge_split_records"]:
        raise RuntimeError("EE cached Ridge split inventory differs")
    return dict(geometries=len(candidates), certified_split_records=records,
        heavy_ridge_statistics_retained=False, cached_Ridge_origin_clock_pairs=16,
        cached_RHS_origin_clock_pairs=48,
        coverage_gap_justifying_new_geometry=False, new_Ridge_geometry_allocation=0,
        decision="diagnose_cached_scoring_policy_before_any_new_geometry"), ledger


def build_preparation(identity):
    config = validate_config(read(CONFIG))
    verify_hashes(config["cache_pins"])
    original = read(config["cache_preparation"])
    if (original["source"]["head"] != config["cache_source_head"]
            or original["dependency_head"] != config["dependency_head"]
            or original["test_used_for_selection"] is not False):
        raise RuntimeError("frozen EE training source identity differs")
    engine_root = Path(config["engine_root"])
    if (git(engine_root, "rev-parse", "HEAD") != config["engine_head"]
            or git(engine_root, "status", "--porcelain")):
        raise RuntimeError("frozen R141 worktree changed")
    if (git(original["dependency"], "rev-parse", "HEAD") != config["dependency_head"]
            or git(original["dependency"], "status", "--porcelain")):
        raise RuntimeError("frozen numerical dependency changed")
    controls = CONFIG.parent / config["controls_file"]
    if digest(controls) != config["controls_sha256"]:
        raise RuntimeError("historical control snapshot changed")
    audit, inputs = audit_cache(config, original)
    inputs.update(config["cache_pins"])
    inputs[str(controls)] = config["controls_sha256"]
    cache = Path(config["cache_root"])
    choice = read(cache / "frozen_choices.json")["EE"]
    rhs = read(cache / "rhs_closeout.json")["EE"]
    selected = distinct_selection(rhs["ranking"], choice, 6)
    if [v["candidate_id"] for v in selected] != config["expected_selected_ids"]:
        raise RuntimeError("frozen six-geometry training-only selection differs")
    engine = load_engine(config)
    runtime = engine.setup(Path(original["dependency"]))
    pools = numerical_threadpools()
    import numpy as np
    # Only immutable train-contained banks are opened; raw FINAL and official
    # designs/references are deliberately not part of this worker contract.
    banks = {}
    bank_meta = {}
    for path, expected in original["bank_sha256"].items():
        if digest(path) != expected:
            raise RuntimeError("frozen EE training bank changed")
        with np.load(path, allow_pickle=False) as packet:
            anchors = packet["anchors"].tolist()
        if (len(anchors) != 940 or min(anchors)[:10] < config["minimum_anchor"]
                or max(anchors)[:10] >= config["training_end_exclusive"]):
            raise RuntimeError("bank is not confined to frozen Fold1 training")
        feature = Path(path).stem
        banks[feature] = dict(path=path, sha256=expected)
        bank_meta[feature] = dict(origins=len(anchors), first=anchors[0], last=anchors[-1],
                                  anchor_identity=fingerprint(anchors))
    # All four policy banks must share the same exact training-origin cohort.
    if len({v["anchor_identity"] for v in bank_meta.values()}) != 1:
        raise RuntimeError("training banks have different origin cohorts")
    splits = runtime.internal_splits(940)
    tasks = []
    specs = {v["candidate_id"]: v for v in original["regional"]["EE"]["candidates"]}
    for selected_fit in selected:
        candidate = specs[selected_fit["candidate_id"]]
        if candidate["spec"]["readout"] != "pure_all_layers" or candidate["spec"]["calendar"] != "none":
            raise RuntimeError("R148 permits only the existing pure no-calendar geometry")
        for split in (1, 2, 3):
            name = f"rhs_EE_{candidate['candidate_id']}_s{split}_t{selected_fit['tau0']:.12e}"
            parent, result, hashes = verify_cached_packet(cache, name,
                config["cache_source_head"], heavy=True)
            terminal_path = cache / "tasks_done" / name / "fit/terminal.json"
            terminal = read(terminal_path)
            if (parent["kind"] != "rhs" or parent["spec"] != candidate["spec"]
                    or parent["region"] != "EE" or parent["split"] != split
                    or parent["tau0"] != selected_fit["tau0"]
                    or result["certified"] is not True
                    or terminal["full_variational_certified"] is not True
                    or terminal["test_opened"] is not False
                    or terminal["tau0"] != selected_fit["tau0"]):
                raise RuntimeError("cached Normal parent differs or is uncertified")
            inputs.update(hashes)
            stats_task, stats_result, stats_hashes = verify_cached_packet(cache, parent["stats_name"],
                config["cache_source_head"], heavy=False)
            if (stats_task["kind"] != "stats" or stats_task["candidate_id"] != candidate["candidate_id"]
                    or stats_task["split"] != split or stats_result["certified"] is not True):
                raise RuntimeError("cached training statistics/scaler lineage differs")
            inputs.update(stats_hashes)
            scaler = cache / "tasks_done" / parent["stats_name"] / "scaler.json"
            inputs[str(scaler)] = digest(scaler)
            indices = panel_indices(len(splits[split - 1]["validation"]))
            validation = splits[split - 1]["validation"].tolist()
            panels = dict(indices, validation_origin_positions=validation,
                train_origin_positions=splits[split - 1]["train"].tolist(),
                clock_offsets_steps=config["clock_offsets_steps"],
                small_daily_anchors=[anchors[validation[i]] for i in indices["small"]],
                large_daily_anchors=[anchors[validation[i]] for i in indices["large"]],
                historical_rhs_daily_anchors=[anchors[validation[i]] for i in indices["historical_rhs"]])
            panels["clock_origin_timestamps"] = {
                str(offset): {
                    label: [(dt.datetime.fromisoformat(anchors[validation[i]]) +
                        dt.timedelta(minutes=15 * offset)).isoformat() for i in indices[key]]
                    for label, key in (("small", "small"), ("large", "large"),
                                       ("historical_rhs", "historical_rhs"))}
                for offset in config["clock_offsets_steps"]}
            panels["panel_identity_sha256"] = fingerprint(panels)
            tasks.append(dict(name=f"EE_cached_rhs_{candidate['candidate_id']}_s{split}",
                kind="cached_rhs_rescore", region="EE", split=split,
                candidate_id=candidate["candidate_id"], spec=candidate["spec"],
                specification_sha256=candidate["specification_sha256"],
                tau0=selected_fit["tau0"], scale_role=selected_fit["scale_role"],
                parent_task=name, parent_fit=str(terminal_path.parent), parent_source=original["source"],
                parent_seal_sha256=digest(cache / "tasks_done" / name / "completed_evidence.json"),
                parent_input_sha256=hashes, scaler_path=str(scaler), scaler_sha256=digest(scaler),
                bank=banks[candidate["spec"]["feature_policy"]], panels=panels,
                paths=100, forecast_seed=original["protocol"]["forecast_seed"],
                posterior_moments_reused_without_update=True, test_opened=False,
                historical_RHS_grid_is_separate=True))
    source_paths = [ENTRY, CONFIG, controls,
        engine_root / "application/scripts/pricefm/480_run_pricefm_stage_r141_region.py",
        engine_root / "application/scripts/pricefm/pricefm_r134_core.py"]
    source_paths += list((ROOT / "application/scripts/pricefm").glob("*r148*.py"))
    source_paths += list((ROOT / "application/config").glob("*r148*.json"))
    source_paths += list((ROOT / "application/tests").glob("*r148*.py"))
    doc = ROOT / "docs/implementation_notes/pricefm_stage_r148_ee_parallel_development_20261023.md"
    if doc.exists():
        source_paths.append(doc)
    sources = {str(p): digest(p) for p in source_paths}
    # The original source ledger pins every imported numerical dependency.
    sources.update(original["source_sha256"])
    verify_hashes(sources)
    audit.update(dict(AL_finalist_rows=len(choice["ranking"]),
        AL_finalist_unique_geometries=len({v["candidate_id"] for v in choice["ranking"]}),
        RHS_ranked_groups=len(rhs["ranking"]), RHS_excluded_groups=len(rhs["excluded"]),
        actual_frozen_control_tau0=choice["tau0"], selected_distinct_cached_geometries=selected,
        historical_proxy_rank_context=proxy_rank_context(read(cache / "ridge_closeout.json")["EE"], rhs),
        controls=read(controls), historical_Ridge_predictor_not_reconstructed=True))
    return dict(status="R148_PREPARED_TRAINING_ONLY_NOT_PROMOTED", source=identity,
        config_sha256=digest(CONFIG), scientific_decision=audit,
        source_sha256=sources, input_sha256=inputs, banks=banks, bank_metadata=bank_meta,
        dependency=original["dependency"], dependency_head=config["dependency_head"],
        numerical_threadpools=pools,
        source_cache=original["source"], task_count=len(tasks), tasks=tasks,
        test_used_for_selection=False, official_test_seen_previously=True,
        new_model_fits=0, new_Ridge_geometries=0, official_evaluation_authorized=False,
        scoring_semantics=dict(
            deterministic="posterior_beta_mean_recurrence_no_simulated_future_innovations; analytic_Normal_quantiles_with_omega_mean_plus_zVz",
            stochastic="beta_and_omega_draw_fixed_per_path_with_independent_Normal_innovations; empirical_path_quantiles",
            paired_scope="same_cached_Normal_RHS_fit_and_exact_common_origins; not_original_Ridge_estimator",
            large_panel="nested_extension_of_historical_Ridge16_not_assumed_identical_to_historical_RHS48",
            paths=100, horizon_steps=96, clock_offsets_steps=[0, 24, 48, 72]))


def prepare():
    guarded_runtime()
    identity = source_identity()
    if (PREP / "prepared.json").exists():
        preparation = read_preparation()
        verify_hashes(preparation["source_sha256"])
        verify_hashes(preparation["input_sha256"])
        return preparation
    preparation = build_preparation(identity)
    for task in preparation["tasks"]:
        immutable(OUT / "tasks" / (task["name"] + ".json"), task)
    immutable(PREP / "cache_audit.json", preparation["scientific_decision"])
    # Written last: partial preparation cannot release numerical workers.
    immutable(PREP / "preparation.json", preparation)
    immutable(PREP / "prepared.json", dict(preparation_sha256=digest(PREP / "preparation.json"),
        source=identity, config_sha256=digest(CONFIG)))
    return preparation


def read_preparation():
    receipt = read(PREP / "prepared.json")
    if receipt["preparation_sha256"] != digest(PREP / "preparation.json"):
        raise RuntimeError("prepared manifest hash changed")
    preparation = read(PREP / "preparation.json")
    if (preparation["source"] != source_identity() or preparation["config_sha256"] != digest(CONFIG)
            or receipt["source"] != preparation["source"]
            or receipt["config_sha256"] != preparation["config_sha256"]):
        raise RuntimeError("R148 prepared source/config changed")
    if (preparation["task_count"] != 18 or preparation["new_model_fits"] != 0
            or preparation["new_Ridge_geometries"] != 0):
        raise RuntimeError("R148 prepared task scope differs")
    tasks = preparation["tasks"]
    config = validate_config(read(CONFIG))
    expected = {(candidate, split) for candidate in config["expected_selected_ids"] for split in (1, 2, 3)}
    if (len(tasks) != 18 or len({t["name"] for t in tasks}) != 18
            or {(t["candidate_id"], t["split"]) for t in tasks} != expected):
        raise RuntimeError("R148 requires exactly six distinct geometries by three splits")
    for task in tasks:
        if (task["kind"] != "cached_rhs_rescore" or task["region"] != "EE"
                or task["name"] != f"EE_cached_rhs_{task['candidate_id']}_s{task['split']}"
                or task["paths"] != 100 or task["test_opened"] is not False
                or task["posterior_moments_reused_without_update"] is not True
                or task["spec"]["readout"] != "pure_all_layers"
                or task["spec"]["calendar"] != "none"
                or task["parent_source"]["head"] != config["cache_source_head"]):
            raise RuntimeError("R148 prepared worker contract differs")
    return preparation


def preparation_complete():
    if not (PREP / "prepared.json").is_file():
        return False
    read_preparation()
    return True


def task_complete(name):
    if "/" in name or "\\" in name or not name.startswith("EE_cached_rhs_"):
        raise ValueError("invalid R148 task name")
    path = OUT / "tasks_done" / name
    if not (path / "completed_evidence.json").is_file():
        return False
    seal = read(path / "completed_evidence.json")
    task_path = OUT / "tasks" / (name + ".json")
    task = read(task_path)
    source = read(PREP / "preparation.json")["source"]
    if (seal["metadata"]["task_sha256"] != digest(task_path)
            or seal["metadata"]["source_head"] != source["head"]
            or seal["metadata"].get("certified") is not True
            or set(seal["artifacts"]) != {"result.json"}):
        raise RuntimeError("R148 completed task descriptor changed")
    for relative, expected in seal["artifacts"].items():
        target = (path / relative).resolve()
        if path.resolve() not in target.parents or digest(target) != expected:
            raise RuntimeError("R148 result seal changed")
    validate_result(read(path / "result.json"), task)
    return True


def validate_result(result, task):
    variants = {"deterministic16", "deterministic48", "stochastic16", "stochastic48"}
    if (result.get("kind") != "cached_rhs_rescore" or result.get("certified") is not True
            or result.get("candidate_id") != task["candidate_id"]
            or result.get("split") != task["split"] or result.get("tau0") != task["tau0"]
            or result.get("paths") != 100 or result.get("test_opened") is not False
            or result.get("posterior_updated") is not False or result.get("new_model_fits") != 0
            or result.get("original_cached_moments_unchanged") is not True
            or set(result.get("metrics", {})) != variants
            or set(result.get("clock_metrics", {})) != variants):
        raise RuntimeError("malformed R148 result identity or scientific scope")
    pools = result.get("numerical_threadpools", [])
    if not pools or any(p.get("num_threads") != 1 for p in pools):
        raise RuntimeError("result lacks one-thread numerical pool proof")
    for variant in variants:
        rows = [result["metrics"][variant], *result["clock_metrics"][variant]]
        if len(result["clock_metrics"][variant]) != 4:
            raise RuntimeError("incomplete four-clock scoring surface")
        for row in rows:
            for key in ("AQL", "median_MAE", "coverage_80", "width_80"):
                value = row.get(key)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                    raise RuntimeError("nonfinite or untyped R148 metric")
            if not 0 <= row["coverage_80"] <= 1 or min(row[k] for k in ("AQL", "median_MAE", "width_80")) < 0:
                raise RuntimeError("invalid R148 metric range")
        for key in ("AQL", "median_MAE", "coverage_80", "width_80"):
            mean = sum(row[key] for row in result["clock_metrics"][variant]) / 4
            if not math.isclose(result["metrics"][variant][key], mean, rel_tol=1e-12, abs_tol=1e-12):
                raise RuntimeError("aggregate metric differs from equal four-clock mean")
    identities = result.get("origin_identities", [])
    if len(identities) != 4 or {v["clock_offset_steps"] for v in identities} != {0, 24, 48, 72}:
        raise RuntimeError("incomplete origin/clock identity")
    for row in identities:
        panels = task["panels"]
        small = [panels["validation_origin_positions"][i] for i in panels["small"]]
        large = [panels["validation_origin_positions"][i] for i in panels["large"]]
        if (len(row["daily_origin_positions_small"]) != 4
                or len(row["daily_origin_positions_large"]) != 12
                or not set(row["daily_origin_positions_small"]).issubset(row["daily_origin_positions_large"])
                or row["daily_origin_positions_small"] != small
                or row["daily_origin_positions_large"] != large
                or row["stable_rng_origin_keys"] != [i * 96 + row["clock_offset_steps"] for i in large]
                or row.get("small_reused_from_large") is not True):
            raise RuntimeError("paired panel reuse proof differs")


def guarded_runtime(cpu=None):
    affinity = os.sched_getaffinity(0)
    if len(affinity) != 1 or (cpu is not None and affinity != {cpu}) or not affinity.issubset(set(range(30))):
        raise RuntimeError("guarded R148 work requires one approved physical CPU")
    if os.sched_getscheduler(0) != os.SCHED_IDLE:
        raise RuntimeError("R148 numerical work requires SCHED_IDLE")
    priority = subprocess.check_output(["ionice", "-p", str(os.getpid())], text=True).strip()
    if not priority.startswith("idle"):
        raise RuntimeError("R148 numerical work requires idle I/O priority")
    for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        if os.environ.get(key) != "1":
            raise RuntimeError("R148 numerical thread environment must be one")


def numerical_threadpools():
    from threadpoolctl import threadpool_info
    pools = threadpool_info()
    if not pools or any(p.get("num_threads") != 1 for p in pools):
        raise RuntimeError("loaded numerical pools must each have one thread")
    return pools


def deterministic_predictions(runtime, arrays, spec, fit):
    """Frozen recursive_normal_score equations, exposing shared rows for both panels."""
    import numpy as np
    engine = runtime.BASE
    idx = np.arange(len(arrays.response))
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    states = engine.initialize_states(arrays, spec, reservoir, config, idx)
    generated = np.empty((len(idx), 96))
    predictions = np.empty((len(idx), 96, 7))
    for horizon in range(96):
        transition = engine.explicit_input(arrays, spec, idx, horizon, generated[:, :horizon])
        states = engine.reservoir_step(states, transition, reservoir, config)
        design = engine.readout_rows(states, transition, spec["readout"])
        location = design @ np.asarray(fit["beta_mean"])
        variance = float(fit["omega_mean"]) + np.einsum("ij,jk,ik->i", design,
            np.asarray(fit["beta_cov"]), design, optimize=True)
        predictions[:, horizon] = engine._normal_quantiles(location, variance)
        generated[:, horizon] = location
    if not np.isfinite(predictions).all():
        raise RuntimeError("nonfinite deterministic cached Normal predictions")
    return predictions


def pending_task_names():
    preparation = read_preparation()
    return [t["name"] for t in preparation["tasks"] if not task_complete(t["name"])]


def scaled_metric(metric, scale):
    metric = dict(metric)
    for key in ("AQL", "median_MAE", "width_80"):
        metric[key] *= scale
    return metric


def score_cached(engine, runtime, preparation, task, heartbeat):
    import numpy as np
    from pricefm_r127_contract import shifted_windows, window_identity, common_metrics
    verify_hashes(task["parent_input_sha256"])
    if digest(task["bank"]["path"]) != task["bank"]["sha256"]:
        raise RuntimeError("training bank content changed")
    if digest(task["scaler_path"]) != task["scaler_sha256"]:
        raise RuntimeError("cached training scaler changed")
    arrays = engine.core.load_arrays(runtime, Path(task["bank"]["path"]))
    scaled, scaler, cell = engine.scaled_internal(runtime, arrays, task["split"])
    if fingerprint(scaler) != fingerprint(read(task["scaler_path"])):
        raise RuntimeError("recomputed training-only scaling differs from cached fit")
    if (cell["train"].tolist() != task["panels"]["train_origin_positions"]
            or cell["validation"].tolist() != task["panels"]["validation_origin_positions"]):
        raise RuntimeError("training/validation split identity changed")
    fit = runtime.load_normal_fit(Path(task["parent_fit"]))
    numerical_threadpools()
    small, large = (np.asarray(task["panels"][k], dtype=int) for k in ("small", "large"))
    if not set(small).issubset(set(large)):
        raise RuntimeError("paired panels are not nested")
    take = np.asarray([list(large).index(i) for i in small])
    idx = cell["validation"]
    seed = runtime.BASE.deterministic_seed(task["forecast_seed"], "EE", task["split"])
    clocks = {"deterministic16": [], "deterministic48": [], "stochastic16": [], "stochastic48": []}
    identities = []
    for offset in (0, 24, 48, 72):
        shifted = shifted_windows(scaled, idx[large], offset, idx)
        window_identity(shifted, dt.datetime.fromisoformat(str(arrays.anchors[idx[0]])),
            dt.datetime.fromisoformat(str(arrays.anchors[idx[-1]])) + dt.timedelta(days=1))
        values, audit = engine.core.normal_predictions(runtime, shifted, task["spec"], fit,
            idx[large] * 96 + offset, runtime.BASE.deterministic_seed(seed, "clock", offset),
            paths=100, observe=lambda v: heartbeat(dict(v, clock_offset_steps=offset)))
        deterministic = deterministic_predictions(runtime, shifted, task["spec"], fit)
        numerical_threadpools()
        for label, selection in (("48", np.arange(len(large))), ("16", take)):
            dm = common_metrics(shifted.response[selection], deterministic[selection])
            sm = common_metrics(shifted.response[selection], values[selection])
            clocks["deterministic" + label].append(scaled_metric(dm, scaler["price_scale"]))
            clocks["stochastic" + label].append(scaled_metric(sm, scaler["price_scale"]))
        identities.append(dict(clock_offset_steps=offset,
            daily_origin_positions_large=idx[large].tolist(), daily_origin_positions_small=idx[small].tolist(),
            stable_rng_origin_keys=(idx[large] * 96 + offset).tolist(),
            large_origin_timestamps=[dt.datetime.fromisoformat(str(a)).isoformat() for a in shifted.anchors],
            small_origin_timestamps=[dt.datetime.fromisoformat(str(shifted.anchors[i])).isoformat() for i in take],
            panel_identity_sha256=task["panels"]["panel_identity_sha256"],
            large_prediction_sha256=hashlib.sha256(values.tobytes()).hexdigest(),
            small_prediction_sha256=hashlib.sha256(values[take].tobytes()).hexdigest(),
            deterministic_small_prediction_sha256=hashlib.sha256(deterministic[take].tobytes()).hexdigest(),
            small_reused_from_large=True, sampler_audit=audit))
    # Reading/scoring must leave retained posterior and original provenance untouched.
    verify_hashes(task["parent_input_sha256"])
    metrics = {name: {k: float(np.mean([v[k] for v in rows]))
                     for k in ("AQL", "median_MAE", "coverage_80", "width_80")}
               for name, rows in clocks.items()}
    return dict(certified=True, kind="cached_rhs_rescore", candidate_id=task["candidate_id"],
        split=task["split"], tau0=task["tau0"], metrics=metrics, clock_metrics=clocks,
        origin_identities=identities, units="EUR/MWh", paths=100, test_opened=False,
        posterior_updated=False, new_model_fits=0, original_cached_moments_unchanged=True,
        numerical_threadpools=numerical_threadpools(),
        semantics=preparation["scoring_semantics"])


def worker(name, cpu):
    if cpu not in range(30):
        raise ValueError("R148 worker CPU must be in approved physical set0-29")
    os.sched_setaffinity(0, {cpu})
    guarded_runtime(cpu)
    preparation = read_preparation()
    task = next((t for t in preparation["tasks"] if t["name"] == name), None)
    if task is None or task["kind"] != "cached_rhs_rescore":
        raise ValueError("only a frozen cached_rhs_rescore task may execute")
    if read(OUT / "tasks" / (name + ".json")) != task:
        raise RuntimeError("task descriptor changed")
    locks = OUT / "locks"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks / (name + ".lock")).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if task_complete(name):
            return dict(status="already_complete", name=name)
        verify_hashes(preparation["source_sha256"])
        config = validate_config(read(CONFIG))
        engine = load_engine(config)
        runtime = engine.setup(Path(preparation["dependency"]))
        if (git(preparation["dependency"], "rev-parse", "HEAD") != preparation["dependency_head"]
                or git(preparation["dependency"], "status", "--porcelain")):
            raise RuntimeError("frozen numerical dependency changed")
        attempt = OUT / "attempts" / name / (str(int(time.time())) + "." + uuid.uuid4().hex)
        attempt.mkdir(parents=True)
        started = time.time()
        last_beat = [0.0]
        def beat(value):
            now = time.time()
            if now - last_beat[0] >= 5 or value.get("status") in ("running", "completed"):
                write(OUT / "heartbeats" / (name + ".json"), dict(value, epoch=now))
                last_beat[0] = now
        beat(dict(status="running", task=name, cpu=cpu, pid=os.getpid()))
        result = score_cached(engine, runtime, preparation, task, beat)
        validate_result(result, task)
        write(attempt / "result.json", result)
        write(attempt / "completed_evidence.json", dict(
            artifacts={"result.json": digest(attempt / "result.json")},
            metadata=dict(source_head=preparation["source"]["head"], task_sha256=fingerprint_file_task(name),
                certified=True, elapsed_seconds=time.time() - started, cpu=cpu,
                prior_source=task["parent_source"], posterior_updated=False, new_model_fits=0,
                numerical_threadpools=result["numerical_threadpools"])))
        destination = OUT / "tasks_done" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise RuntimeError("unsealed canonical R148 result requires review")
        os.rename(attempt, destination)
        beat(dict(status="completed", task=name, cpu=cpu, pid=os.getpid()))
        if not pending_task_names():
            write_closeout("all_18_cached_rescoring_tasks_complete")
        return result


def fingerprint_file_task(name):
    return digest(OUT / "tasks" / (name + ".json"))


def status():
    preparation = read_preparation()
    completed = [t for t in preparation["tasks"] if task_complete(t["name"])]
    groups = {}
    for task in completed:
        result = read(OUT / "tasks_done" / task["name"] / "result.json")
        groups.setdefault(task["candidate_id"], []).append(result)
    summaries = {}
    per_split = {}
    for candidate, results in groups.items():
        if {v["split"] for v in results} != {1, 2, 3}:
            continue
        summaries[candidate] = {variant: sum(v["metrics"][variant]["AQL"] for v in results) / 3
                               for variant in results[0]["metrics"]}
        per_split[candidate] = [{"split": v["split"], "AQL": {k: m["AQL"] for k, m in v["metrics"].items()},
            "stochastic_minus_deterministic16": v["metrics"]["stochastic16"]["AQL"] - v["metrics"]["deterministic16"]["AQL"],
            "stochastic_minus_deterministic48": v["metrics"]["stochastic48"]["AQL"] - v["metrics"]["deterministic48"]["AQL"],
            "large_minus_small_deterministic": v["metrics"]["deterministic48"]["AQL"] - v["metrics"]["deterministic16"]["AQL"],
            "large_minus_small_stochastic": v["metrics"]["stochastic48"]["AQL"] - v["metrics"]["stochastic16"]["AQL"]}
            for v in sorted(results, key=lambda r: r["split"])]
    control = read(CONFIG)["expected_selected_ids"][0]
    control_differences = {} if control not in summaries else {
        candidate: {k: value - summaries[control][k] for k, value in metrics.items()}
        for candidate, metrics in summaries.items()}
    rank_fidelity = {}
    if len(summaries) >= 2:
        ids = sorted(summaries)
        for a, b in (("deterministic16", "stochastic16"), ("deterministic48", "stochastic48"),
                     ("deterministic16", "deterministic48"), ("stochastic16", "stochastic48")):
            rank_fidelity[a + "_vs_" + b] = spearman([summaries[i][a] for i in ids],
                                                                   [summaries[i][b] for i in ids])
    return dict(status="R148_CACHED_SCORING_COMPLETE_NOT_PROMOTED" if len(completed) == 18
                else "R148_PARTIAL_CACHED_SCORING_NOT_PROMOTED", source=preparation["source"],
        completed=len(completed), total=18, pending=18 - len(completed),
        complete_three_split_geometry_scores=summaries, per_geometry_split_paired_scores=per_split,
        completed_split_records={candidate: [{"split": r["split"], "metrics": r["metrics"]}
            for r in sorted(results, key=lambda v: v["split"])] for candidate, results in groups.items()},
        candidate_minus_actual_frozen_control=control_differences, Normal_policy_rank_fidelity=rank_fidelity,
        cached_control_candidate=control, unranked_incomplete_geometries=[i for i in groups if i not in summaries],
        uncertainty_limits=["100_paths_single_MC_seed_no_MC_uncertainty_estimate",
            "six_preselected_cached_geometries_not_unbiased_geometry_search",
            "paired_Normal_policy_comparison_not_original_Ridge_vs_RHS_causal_effect",
            "new_nested48_grid_may_differ_from_historical_RHS48",
            "training_only_exploration_no_official_test_confirmation"],
        new_model_fits=0, new_Ridge_geometries=0, official_evaluation_authorized=False,
        future_AL_requires_separate_gate=True)


def spearman(x, y):
    def ranks(values):
        return [1 + sum(z < v for z in values) + (sum(z == v for z in values) - 1) / 2 for v in values]
    a, b = ranks(x), ranks(y)
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    va, vb = sum((v - ma) ** 2 for v in a), sum((v - mb) ** 2 for v in b)
    return None if va == 0 or vb == 0 else sum((v - ma) * (w - mb) for v, w in zip(a, b)) / math.sqrt(va * vb)


def write_closeout(reason, details=None):
    summary = dict(status(), reason=reason, resource_details=details, epoch=time.time())
    write(OUT / "closeout" / "assessment.json", summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "status", "worker", "closeout"))
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--name")
    parser.add_argument("--reason", default="bounded_resource_lease_end")
    args = parser.parse_args()
    if args.action in ("prepare", "worker"):
        if args.cpu not in range(30):
            parser.error("guarded prepare/worker requires --cpu in0-29")
        os.sched_setaffinity(0, {args.cpu})
    if args.action == "prepare":
        prep = prepare()
        value = dict(status=prep["status"], tasks=prep["task_count"], new_model_fits=0)
    elif args.action == "worker":
        if not args.name:
            parser.error("worker requires --name")
        value = worker(args.name, args.cpu)
    elif args.action == "closeout":
        value = write_closeout(args.reason)
    else:
        value = status()
    print(json.dumps(value, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
