#!/usr/bin/env python3
"""Run the resumable validation-only PriceFM R120 explicit-lag campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import itertools
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from typing import Any, Callable

import joblib
import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r120_engine import (
    CALENDARS, POLICIES, QUANTILES, SOURCE_WINDOW, explicit_arrays, feature_names,
    fingerprint, fit_scaled_ridge, input_names, internal_splits, load_normal_fit,
    load_quantile_fit, load_windows, normalize_spec, prediction_metrics,
    recursive_normal_score, recursive_quantile_forecast, resource_estimate,
    standardize_from_training_origins, teacher_forced_design,
    teacher_forced_statistics, write_stats_packet,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"
THREAD_ENV = ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS")
GEOMETRIES = (
    (96,), (128,), (192,), (256,), (384,), (512,), (640,),
    (96, 96), (128, 128), (192, 192), (256, 256), (384, 384),
    (256, 128), (384, 192), (512, 256), (640, 320),
    (96, 64, 48), (96, 96, 96), (128, 128, 128), (192, 128, 96),
    (256, 192, 128), (256, 256, 256), (384, 256, 128),
    (512, 256, 128), (640, 320, 160),
    (96, 96, 96, 96), (128, 128, 128, 128), (192, 128, 96, 64),
    (256, 192, 128, 64), (384, 256, 128, 64), (512, 256, 128, 64),
    (640, 320, 160, 80),
)
ALPHAS = (0.10, 0.20, 0.35, 0.50, 0.70, 0.90)
RHOS = (0.70, 0.82, 0.90, 0.95, 0.99)
INPUT_SCALES = (0.05, 0.10, 0.15, 0.25, 0.35, 0.50)
INPUT_FAN_INS = (16, 32, 64, 128, 256)
SPARSITIES = (0.02, 0.05, 0.10, 0.20)
SEEDS = (2026092501, 2026092602, 2026092703)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--mode", choices=("controller", "ridge-cell", "rhs-score", "full-design", "forecast"), default="controller")
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--prep-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, default=15)
    value.add_argument("--cpu-list", required=True)
    value.add_argument("--candidate-id"); value.add_argument("--fit-dir", type=Path)
    value.add_argument("--split", type=int); value.add_argument("--fold", type=int)
    value.add_argument("--variant", choices=("pure", "extended"), default="pure")
    value.add_argument("--family", choices=("al", "exal"))
    value.add_argument("--minimum-free-gib", type=float, default=100.0)
    value.add_argument("--minimum-memory-gib", type=float, default=64.0)
    value.add_argument("--maximum-cpu-percent", type=float, default=35.0)
    value.add_argument("--preflight-only", action="store_true")
    return value


def _paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    return artifact, data, prep, campaign


def parse_cpus(value: str) -> list[int]:
    cpus = []
    for block in str(value).split(","):
        block = block.strip()
        if not block: continue
        if "-" in block:
            start, stop = (int(item) for item in block.split("-", 1)); cpus.extend(range(start, stop + 1))
        else: cpus.append(int(block))
    if not cpus or len(cpus) != len(set(cpus)):
        raise ValueError("CPU list must be explicit and unique")
    return cpus


def _physical_core(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())


def _cpu_snapshot(interval: float = 0.6) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        rows = {}
        for line in Path("/proc/stat").read_text().splitlines():
            if not line.startswith("cpu") or line.startswith("cpu "): continue
            fields = line.split(); cpu = int(fields[0][3:]); values = [int(value) for value in fields[1:]]
            rows[cpu] = (sum(values), values[3] + (values[4] if len(values) > 4 else 0))
        return rows
    before = read(); time.sleep(interval); after = read()
    return {cpu: 100.0 * (1.0 - (after[cpu][1] - idle) / max(1, after[cpu][0] - total)) for cpu, (total, idle) in before.items()}


def _command(command: list[str], cwd: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True); env = dict(os.environ); env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command] if cpu is not None else command
    with log.open("a") as handle:
        handle.write("$ " + " ".join(map(str, actual)) + "\n"); handle.flush()
        result = subprocess.run(actual, cwd=str(cwd), env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode: raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}")


def _atomic_directory(output: Path, writer: Callable[[Path], None]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True); temporary = output.parent / f"{output.name}.tmp.{os.getpid()}"
    if temporary.exists(): shutil.rmtree(temporary)
    temporary.mkdir()
    try:
        writer(temporary)
        if output.exists(): shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists(): shutil.rmtree(temporary)


def _read_control(prep: Path) -> dict[str, Any]:
    return json.loads((prep / "launch_control.json").read_text())


def _manifest_paths(prep: Path, campaign: Path) -> list[Path]:
    return [path for path in (
        prep / "pricefm_stage_r120b_candidate_manifest.csv",
        campaign / "stage_c/pricefm_stage_r120c_candidate_manifest.csv",
        campaign / "stage_c/pricefm_stage_r120c_seed_manifest.csv",
        campaign / "stage_e/pricefm_stage_r120e_candidate_manifest.csv",
    ) if path.is_file()]


def _candidate(prep: Path, campaign: Path, candidate_id: str) -> tuple[pd.Series, dict[str, Any]]:
    found = []
    for path in _manifest_paths(prep, campaign):
        frame = pd.read_csv(path); selected = frame[frame.candidate_id.astype(str).eq(str(candidate_id))]
        if len(selected): found.append(selected.iloc[0])
    if len(found) != 1: raise RuntimeError(f"candidate_id must identify one R120 row: {candidate_id}")
    return found[0], normalize_spec(json.loads(str(found[0].spec_json)))


def _ridge_root(campaign: Path, stage: str, candidate_id: str) -> Path:
    return campaign / f"{str(stage).lower()}_ridge_runs" / str(candidate_id)


def _ridge_terminal(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file(): return False
    try: value = json.loads(terminal.read_text())
    except Exception: return False
    return value.get("status") == "completed_r120_ridge_cell" and value.get("test_opened") is False


def ridge_cell(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); row, spec = _candidate(prep, campaign, str(args.candidate_id))
    output = _ridge_root(campaign, str(row.stage), str(row.candidate_id))
    if _ridge_terminal(output): return json.loads((output / "terminal.json").read_text())
    control = _read_control(prep)
    arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    splits = internal_splits(len(arrays.response)); stats, preprocessing, audits, metrics = {}, {}, {}, []
    maximum = 32 if str(row.stage) == "R120B" else 48
    for item in splits:
        split = int(item["split"])
        scaled, scaler = standardize_from_training_origins(arrays, item["train"])
        split_stats, audit = teacher_forced_statistics(scaled, spec, {"train": item["train"]})
        stats[f"train_{split}"] = split_stats["train"]; preprocessing[str(split)] = scaler; audits[str(split)] = audit
        score = recursive_normal_score(scaled, spec, fit_scaled_ridge(split_stats["train"]), item["validation"], maximum_origins=maximum)
        for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"):
            score[metric] *= float(scaler["price_scale"])
        metrics.append({"split": split, **score})
    explicit_names = input_names(spec, arrays.exog_names); features = feature_names(spec, explicit_names)
    def write(temp: Path) -> None:
        payload = {}
        for split in (1, 2, 3):
            value = stats[f"train_{split}"]
            for name in ("XtX", "Xty"): payload[f"split{split}_{name}"] = value[name]
            payload[f"split{split}_yty"] = np.asarray([value["yty"]]); payload[f"split{split}_n"] = np.asarray([value["n"]], dtype=np.int64)
        np.savez_compressed(temp / "training_statistics.npz", **payload)
        pd.DataFrame(metrics).to_csv(temp / "validation_metrics.csv", index=False)
        write_json(temp / "contract.json", {
            "candidate_id": str(row.candidate_id), "stage": str(row.stage), "spec": spec,
            "semantic_sha256": str(row.semantic_sha256), "feature_names": features,
            "input_names": explicit_names, "source_manifest": list(arrays.source_manifest),
            "split_preprocessing": preprocessing, "reservoir_audit": audits,
            "selection_split": str(row.selection_split), "test_opened": False,
        })
        write_json(temp / "terminal.json", {
            "status": "completed_r120_ridge_cell", "stage": str(row.stage), "candidate_id": str(row.candidate_id),
            "p": len(features), "input_dimension": len(explicit_names),
            "mean_AQL": float(np.mean([value["AQL"] for value in metrics])),
            "mean_late_AQL": float(np.mean([value["late_AQL"] for value in metrics])), "test_opened": False,
        })
    _atomic_directory(output, write)
    return json.loads((output / "terminal.json").read_text())


def _stats_from_ridge(path: Path, split: int) -> dict[str, Any]:
    with np.load(path / "training_statistics.npz") as packet:
        xtx = np.asarray(packet[f"split{split}_XtX"], dtype=float)
        return {"n": int(packet[f"split{split}_n"][0]), "p": int(xtx.shape[0]), "XtX": xtx,
                "Xty": np.asarray(packet[f"split{split}_Xty"], dtype=float), "yty": float(packet[f"split{split}_yty"][0])}


def rhs_score(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); row, spec = _candidate(prep, campaign, str(args.candidate_id))
    output = args.fit_dir.resolve() / "validation_score.json"
    if output.is_file(): return json.loads(output.read_text())
    control = _read_control(prep); arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    selection = internal_splits(len(arrays.response))[int(args.split) - 1]
    arrays, scaler = standardize_from_training_origins(arrays, selection["train"])
    score = recursive_normal_score(arrays, spec, load_normal_fit(args.fit_dir), selection["validation"], 64)
    for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"):
        score[metric] *= float(scaler["price_scale"])
    result = {"status": "completed_r120_rhs_validation_score", "candidate_id": str(row.candidate_id),
              "split": int(args.split), **score,
              "test_opened": False}
    write_json(output, result); return result


def _run_queue(tasks: list[tuple[str, list[str], Path]], cpus: list[int], cwd: Path, progress: Path, fail_fast: bool = True) -> dict[str, Any]:
    state = {"total": len(tasks), "complete": 0, "failed": 0, "failed_task_ids": [], "updated_at_epoch": time.time()}
    lock = threading.Lock(); buckets = [[] for _ in cpus]
    # Largest/highest-memory cells first to reduce the serial tail.
    for index, task in enumerate(tasks): buckets[index % len(cpus)].append(task)
    def worker(cpu: int, bucket: list[tuple[str, list[str], Path]]) -> None:
        for task_id, command, log in bucket:
            ok = True
            try: _command(command, cwd, log, cpu)
            except Exception: ok = False
            with lock:
                state["complete" if ok else "failed"] += 1
                if not ok: state["failed_task_ids"].append(task_id)
                state["updated_at_epoch"] = time.time(); write_json(progress, state)
            if not ok and fail_fast: raise RuntimeError(f"R120 task failed: {task_id}")
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures): future.result()
    if not tasks: write_json(progress, state)
    if fail_fast and state["failed"]: raise RuntimeError(f"R120 queue failed: {state['failed_task_ids'][:10]}")
    return state


def _valid_normal(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file(): return False
    try: value = json.loads(terminal.read_text())
    except Exception: return False
    return value.get("status") == "completed_recursive_normal_fit" and value.get("converged") is True and value.get("test_opened") is False


def _prepare_processed(control: dict[str, Any], campaign: Path, code: Path, cpu: int, folds: str) -> None:
    runtime = Path(control["runtime_processed"]); source = Path(control["source_processed"]); runtime.mkdir(parents=True, exist_ok=True)
    for name in ("splits_scaled", "scalers"):
        destination = runtime / name
        if destination.is_symlink():
            if destination.resolve() != (source / name).resolve(): raise RuntimeError("R120 processed dependency changed")
        elif not destination.exists(): destination.symlink_to(source / name, target_is_directory=True)
        else: raise RuntimeError("R120 processed dependency is not a symlink")
    # Every R120 policy needs BG and its degree-one graph neighbors.
    control_spec = normalize_spec({"region": "BG", "feature_policy": "graph_neighbor_exogenous", "calendar": "compact3", "readout": "pure_all_layers", "m_y": 32, "m_x": 0, "units": [96], "alpha": .5, "rho": .82, "input_scale": .15, "input_fan_in": 64, "recurrent_sparsity": .05, "seed": SEEDS[0]})
    from pricefm_r120_engine import active_regions
    regions = ",".join(active_regions(control_spec)); python = str(Path(control["source_processed"]).parents[2] / "venv/bin/python")
    _command([python, str(code / "application/scripts/pricefm/05_build_windows.py"), "--config", control["data_config"],
              "--pilot-only", "false", "--regions", regions, "--folds", folds, "--resume", "true", "--force", "false"],
             code, campaign / f"logs/windows_L{SOURCE_WINDOW}_folds_{folds.replace(',', '_')}.log", cpu)


def _preflight(args: argparse.Namespace, prep: Path, campaign: Path, cpus: list[int]) -> dict[str, Any]:
    summary = json.loads((prep / "summary.json").read_text()); sources = pd.read_csv(prep / "source_manifest.csv")
    changed = [row.path for row in sources.itertuples(index=False) if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256)]
    usage = _cpu_snapshot(); physical = {cpu: max(usage[sibling] for sibling in usage if _physical_core(sibling) == _physical_core(cpu)) for cpu in cpus}
    disk = shutil.disk_usage(campaign.parent); available_kib = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:"))
    checks = {
        "launch_authorized": summary.get("launch_authorized") is True and summary.get("test_opened") is False,
        "source_hashes": not changed, "worker_count": args.workers == 15 and len(cpus) == 15,
        "distinct_physical_cores": len({_physical_core(cpu) for cpu in cpus}) == 15,
        "cpu_idle": all(value <= args.maximum_cpu_percent for value in physical.values()),
        "disk": disk.free / 2**30 >= args.minimum_free_gib, "memory": available_kib / 2**20 >= args.minimum_memory_gib,
    }
    result = {"status": "preflight_passed" if all(checks.values()) else "preflight_blocked", "checks": checks,
              "cpus": cpus, "physical_core_max_percent": physical, "free_disk_gib": disk.free / 2**30,
              "available_memory_gib": available_kib / 2**20, "test_opened": False}
    campaign.mkdir(parents=True, exist_ok=True); write_json(campaign / "launch_preflight.json", result)
    if not all(checks.values()): raise RuntimeError(f"R120 preflight blocked: {[key for key, value in checks.items() if not value]}")
    return result


def _ridge_tasks(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, manifest: pd.DataFrame, stage: str) -> list[tuple[str, list[str], Path]]:
    python = sys.executable; tasks = []
    # Descending estimated footprint is a deterministic longest-processing-time heuristic.
    ordered = manifest.sort_values(["input_dimension", "readout_dimension", "candidate_id"], ascending=[False, False, True], kind="mergesort")
    for row in ordered.itertuples(index=False):
        output = _ridge_root(campaign, stage, str(row.candidate_id))
        if not _ridge_terminal(output):
            tasks.append((str(row.candidate_id), [python, str(Path(__file__).resolve()), "--mode", "ridge-cell",
                "--artifact-repo", str(args.artifact_repo), "--code-root", str(code), "--prep-dir", str(prep),
                "--campaign-root", str(campaign), "--cpu-list", args.cpu_list, "--candidate-id", str(row.candidate_id)],
                campaign / f"logs/{stage.lower()}_ridge/{row.candidate_id}.log"))
    return tasks


def _ridge_ranking(campaign: Path, manifest: pd.DataFrame, stage: str) -> pd.DataFrame:
    rows = []
    for row in manifest.itertuples(index=False):
        root = _ridge_root(campaign, stage, str(row.candidate_id))
        if not _ridge_terminal(root): continue
        metrics = pd.read_csv(root / "validation_metrics.csv")
        rows.append({
            **row._asdict(), "mean_AQL": float(metrics.AQL.mean()), "worst_AQL": float(metrics.AQL.max()),
            "mean_late_AQL": float(metrics.late_AQL.mean()),
            "mean_coverage": float(metrics.interval_80_coverage.mean()),
        })
    ranking = pd.DataFrame(rows)
    if ranking.empty: return ranking
    ranking = ranking.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "readout_dimension", "candidate_id"], kind="mergesort").reset_index(drop=True)
    ranking.insert(0, "ridge_rank", np.arange(1, len(ranking) + 1)); return ranking


def _memory_band(m_y: int, m_x: int) -> str:
    value = max(int(m_y), int(m_x))
    if value <= 48: return "short"
    if value <= 96: return "daily"
    if value <= 480: return "multi_day"
    return "weekly"


def _stage_b_closeout(campaign: Path, manifest: pd.DataFrame) -> pd.DataFrame:
    ranking = _ridge_ranking(campaign, manifest, "R120B")
    if len(ranking) != len(manifest): raise RuntimeError(f"R120B incomplete: {len(ranking)}/{len(manifest)}")
    root = campaign / "stage_b"; root.mkdir(exist_ok=True)
    ranking.to_csv(root / "ranking.csv", index=False)
    best_geometry = ranking.sort_values(["mean_AQL", "mean_late_AQL", "candidate_id"], kind="mergesort").groupby(
        ["feature_policy", "m_y", "m_x"], as_index=False, sort=False
    ).first()
    best_geometry["memory_band"] = [_memory_band(y, x) for y, x in zip(best_geometry.m_y, best_geometry.m_x)]
    selected = []
    # One best lag pair in every policy x memory band cell gives an auditable 16-row diverse frontier.
    for policy, band in itertools.product(POLICIES, ("short", "daily", "multi_day", "weekly")):
        cell = best_geometry[(best_geometry.feature_policy == policy) & (best_geometry.memory_band == band)]
        if cell.empty: raise RuntimeError(f"R120B diversity cell missing: {policy}/{band}")
        selected.append(cell.sort_values(["mean_AQL", "mean_late_AQL", "candidate_id"], kind="mergesort").iloc[0])
    retained = pd.DataFrame(selected).sort_values(["mean_AQL", "feature_policy", "memory_band"], kind="mergesort").reset_index(drop=True)
    retained.insert(0, "retained_rank", np.arange(1, len(retained) + 1)); retained.to_csv(root / "retained_lag_policy16.csv", index=False)
    write_json(root / "summary.json", {"status": "completed_r120b_lag_policy_closeout", "cells": len(ranking),
        "retained": len(retained), "diversity_rule": "best_per_policy_x_memory_band", "test_opened": False})
    return retained


def _stage_c_manifest(campaign: Path, retained: pd.DataFrame) -> pd.DataFrame:
    path = campaign / "stage_c/pricefm_stage_r120c_candidate_manifest.csv"
    if path.is_file(): return pd.read_csv(path)
    rows = []
    controls = {"units": (96, 64, 48), "alpha": .50, "rho": .82, "input_scale": .15, "input_fan_in": 64, "recurrent_sparsity": .05, "calendar": "compact3"}
    for anchor_position, anchor in enumerate(retained.itertuples(index=False)):
        # Coprime strides make each 40-row block cover every one-dimensional margin.
        offset = int(fingerprint({"m_y": int(anchor.m_y), "m_x": int(anchor.m_x), "policy": anchor.feature_policy})[:8], 16)
        combinations = [controls]
        for position in range(1, 40):
            combinations.append({
                "units": GEOMETRIES[(offset + position) % len(GEOMETRIES)],
                "alpha": ALPHAS[(offset + position * 5) % len(ALPHAS)],
                "rho": RHOS[(offset + position * 3) % len(RHOS)],
                "input_scale": INPUT_SCALES[(offset + position * 7) % len(INPUT_SCALES)],
                "input_fan_in": INPUT_FAN_INS[(offset + position * 2) % len(INPUT_FAN_INS)],
                "recurrent_sparsity": SPARSITIES[(offset + position * 3) % len(SPARSITIES)],
                "calendar": CALENDARS[(offset + position) % len(CALENDARS)],
            })
        seen = set()
        for position, values in enumerate(combinations):
            spec = normalize_spec({
                "region": "BG", "feature_policy": str(anchor.feature_policy), "calendar": values["calendar"],
                "readout": "pure_all_layers", "m_y": int(anchor.m_y), "m_x": int(anchor.m_x),
                "units": list(values["units"]), "alpha": values["alpha"], "rho": values["rho"],
                "input_scale": values["input_scale"], "input_fan_in": values["input_fan_in"],
                "recurrent_sparsity": values["recurrent_sparsity"], "seed": SEEDS[0],
            })
            identity = fingerprint(spec)
            if identity in seen: raise RuntimeError("R120C deterministic design generated a duplicate")
            seen.add(identity)
            from pricefm_r120_engine import active_regions
            exog_dim = 3 if spec["feature_policy"] == "target_only" else 6 if spec["feature_policy"] == "graph_summary_mean" else 9 if spec["feature_policy"] == "graph_summary_mean_std" else 3 * len(active_regions(spec))
            resources = resource_estimate(spec, exog_dim)
            rows.append({"candidate_id": f"r120c_{identity[:16]}", "stage": "R120C",
                "anchor_id": f"anchor_{anchor_position + 1:02d}", "candidate_role": "balanced_geometry_dynamics",
                "semantic_sha256": identity, "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
                **{key: value for key, value in spec.items() if key != "units"}, "units": json.dumps(spec["units"], separators=(",", ":")),
                "exog_dimension": exog_dim, **resources, "selection_split": "fold1_train_internal_expanding_validation", "test_access_authorized": False})
    frame = pd.DataFrame(rows)
    if len(frame) != 640 or frame.semantic_sha256.duplicated().any(): raise RuntimeError("R120C 640-row design failed")
    # Global marginal coverage is a hard design gate.
    required = {"units": len(GEOMETRIES), "alpha": len(ALPHAS), "rho": len(RHOS), "input_scale": len(INPUT_SCALES),
                "input_fan_in": len(INPUT_FAN_INS), "recurrent_sparsity": len(SPARSITIES), "calendar": len(CALENDARS)}
    observed = {field: int(frame[field].nunique()) for field in required}
    if any(observed[field] != count for field, count in required.items()): raise RuntimeError(f"R120C marginal coverage failed: {observed}")
    path.parent.mkdir(parents=True, exist_ok=True); frame.to_csv(path, index=False)
    write_json(path.parent / "design_audit.json", {"status": "frozen_r120c_balanced_design", "rows": len(frame), "required_levels": required, "observed_levels": observed, "test_opened": False})
    return frame


def _stage_c_seed_robustness(campaign: Path, ranking: pd.DataFrame) -> pd.DataFrame:
    path = campaign / "stage_c/pricefm_stage_r120c_seed_manifest.csv"
    if path.is_file(): return pd.read_csv(path)
    rows = []
    for row in ranking.head(10).itertuples(index=False):
        base = normalize_spec(json.loads(str(row.spec_json)))
        for seed in SEEDS[1:]:
            spec = normalize_spec({**base, "seed": seed}); identity = fingerprint(spec)
            values = row._asdict(); values.update({"candidate_id": f"r120cseed_{identity[:16]}", "stage": "R120CSEED",
                "candidate_role": "top10_seed_robustness", "semantic_sha256": identity,
                "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")), "seed": seed})
            rows.append(values)
    frame = pd.DataFrame(rows); path.parent.mkdir(parents=True, exist_ok=True); frame.to_csv(path, index=False); return frame


def _stage_c_closeout(campaign: Path, manifest: pd.DataFrame, seed_manifest: pd.DataFrame) -> pd.DataFrame:
    primary = _ridge_ranking(campaign, manifest, "R120C")
    seeds = _ridge_ranking(campaign, seed_manifest, "R120CSEED")
    if len(primary) != 640 or len(seeds) != 20: raise RuntimeError(f"R120C incomplete: primary={len(primary)} seed={len(seeds)}")
    robust_rows = []
    for row in primary.head(10).itertuples(index=False):
        base_spec = normalize_spec(json.loads(str(row.spec_json))); group = [{"mean_AQL": row.mean_AQL, "mean_late_AQL": row.mean_late_AQL, "worst_AQL": row.worst_AQL}]
        matched = seeds[(seeds.m_y == row.m_y) & (seeds.m_x == row.m_x) & (seeds.feature_policy == row.feature_policy) & (seeds.units == row.units) & (seeds.alpha == row.alpha) & (seeds.rho == row.rho) & (seeds.input_scale == row.input_scale) & (seeds.input_fan_in == row.input_fan_in) & (seeds.recurrent_sparsity == row.recurrent_sparsity) & (seeds.calendar == row.calendar)]
        if len(matched) != 2: raise RuntimeError(f"R120C seed group incomplete for {row.candidate_id}")
        group.extend(matched[["mean_AQL", "mean_late_AQL", "worst_AQL"]].to_dict("records"))
        robust_rows.append({"candidate_id": row.candidate_id, "robust_mean_AQL": float(np.mean([x["mean_AQL"] for x in group])),
            "robust_mean_late_AQL": float(np.mean([x["mean_late_AQL"] for x in group])), "robust_worst_AQL": float(np.max([x["worst_AQL"] for x in group]))})
    robust = pd.DataFrame(robust_rows); final = primary.merge(robust, on="candidate_id", how="left")
    for target, source in (("selection_AQL", "mean_AQL"), ("selection_late_AQL", "mean_late_AQL"), ("selection_worst_AQL", "worst_AQL")):
        final[target] = final[source]
    mask = final.robust_mean_AQL.notna(); final.loc[mask, "selection_AQL"] = final.loc[mask, "robust_mean_AQL"]
    final.loc[mask, "selection_late_AQL"] = final.loc[mask, "robust_mean_late_AQL"]; final.loc[mask, "selection_worst_AQL"] = final.loc[mask, "robust_worst_AQL"]
    final = final.sort_values(["selection_AQL", "selection_late_AQL", "selection_worst_AQL", "readout_dimension", "candidate_id"], kind="mergesort").reset_index(drop=True)
    final.insert(0, "selection_rank", np.arange(1, len(final) + 1)); root = campaign / "stage_c"
    primary.to_csv(root / "primary_ranking.csv", index=False); seeds.to_csv(root / "seed_cell_ranking.csv", index=False)
    robust.to_csv(root / "top10_seed_aggregate.csv", index=False); final.to_csv(root / "robust_ranking.csv", index=False); final.head(50).to_csv(root / "top50.csv", index=False)
    write_json(root / "summary.json", {"status": "completed_r120c_geometry_dynamics_closeout", "primary_cells": 640, "additional_seed_cells": 20, "rhs_top_k": 50, "test_opened": False})
    return final.head(50)


def _normal_contract(fit_id: str, stats: Path, output: Path, tau0: float, control: dict[str, Any], code: Path, max_iter: int = 500) -> dict[str, Any]:
    return {"fit_id": fit_id, "stats_dir": str(stats), "output_dir": str(output), "prior_type": "rhs_ns", "tau0": float(tau0),
        "package_path": control["normal_runtime"], "helper_path": str(code / "application/R/pricefm_recursive_normal_fit.R"),
        "max_iter": int(max_iter), "min_iter": 100, "tol": 1e-5, "convergence_mode": "predictive_fixed_point", "stability_window": 10,
        "predictive_tol": 1e-7, "relative_beta_tol": 1e-6, "sigma_relative_tol": 1e-8, "prior_rms_log_precision_tol": 1e-6,
        "posterior_target_sha256": fingerprint({"fit_id": fit_id, "tau0": tau0, "stats": sha256_file(stats / "terminal.json")}),
        "selection_split": "train_validation_only", "test_access_authorized": False}


def _complete_groups(cells: pd.DataFrame, keys: list[str]) -> pd.DataFrame:
    if cells.empty: return cells.copy()
    keep = []
    for key, group in cells.groupby(keys, sort=False, dropna=False):
        key = key if isinstance(key, tuple) else (key,)
        if set(group.split.astype(int)) == {1, 2, 3} and len(group) == 3: keep.append(key)
    return cells.iloc[:0] if not keep else cells.merge(pd.DataFrame(keep, columns=keys), on=keys, how="inner", validate="many_to_one")


def _rhs_stage(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int], top: pd.DataFrame, label: str = "stage_d") -> pd.DataFrame:
    control = _read_control(prep); records, tasks = [], []; contracts = campaign / label / "contracts"; rscript = str(control["rscript"])
    for row in top.itertuples(index=False):
        ridge = _ridge_root(campaign, str(row.stage), str(row.candidate_id))
        for split in (1, 2, 3):
            stats = _stats_from_ridge(ridge, split); stats_dir = campaign / label / f"stats/{row.candidate_id}/split={split}"
            if not (stats_dir / "terminal.json").is_file(): write_stats_packet(stats_dir, stats, {"candidate_id": row.candidate_id, "split": split})
            reference = float(control["rhs_tau_reference"]) * math.sqrt(float(control["rhs_tau_reference_dimension"]) / stats["p"])
            for multiplier in control["rhs_tau_multipliers"]:
                tau0 = reference * float(multiplier); fit_id = f"{row.candidate_id}_s{split}_m{multiplier:g}"; output = campaign / label / f"fits/{fit_id}"
                contract = _normal_contract(fit_id, stats_dir, output, tau0, control, code); contract_path = contracts / f"{fit_id}.json"
                contract_path.parent.mkdir(parents=True, exist_ok=True); write_json(contract_path, contract)
                if not _valid_normal(output): tasks.append((fit_id, [rscript, str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)], campaign / f"logs/{label}_fit/{fit_id}.log"))
                records.append({"fit_id": fit_id, "candidate_id": row.candidate_id, "split": split, "tau0": tau0, "multiplier": multiplier, "output_dir": str(output)})
    _run_queue(tasks, cpus, code, campaign / label / "fit_progress.json", fail_fast=False)
    score_tasks = []
    for record in records:
        output = Path(record["output_dir"])
        if _valid_normal(output) and not (output / "validation_score.json").is_file():
            score_tasks.append((record["fit_id"], [sys.executable, str(Path(__file__).resolve()), "--mode", "rhs-score", "--artifact-repo", str(args.artifact_repo),
                "--code-root", str(code), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--cpu-list", args.cpu_list,
                "--candidate-id", record["candidate_id"], "--split", str(record["split"]), "--fit-dir", str(output)], campaign / f"logs/{label}_score/{record['fit_id']}.log"))
    _run_queue(score_tasks, cpus, code, campaign / label / "score_progress.json", fail_fast=False)
    rows, completion = [], []
    for record in records:
        output = Path(record["output_dir"]); valid = _valid_normal(output); score = output / "validation_score.json"; complete = valid and score.is_file()
        completion.append({**record, "fit_completed": valid, "score_completed": complete})
        if complete:
            value = json.loads(score.read_text()); rows.append({**record, "AQL": value["AQL"], "late_AQL": value["late_AQL"], "coverage": value["interval_80_coverage"]})
    cells = pd.DataFrame(rows); eligible = _complete_groups(cells, ["candidate_id", "tau0", "multiplier"])
    if eligible.empty: raise RuntimeError(f"R120 {label} has no complete RHS group")
    pooled = eligible.groupby(["candidate_id", "tau0", "multiplier"], as_index=False).agg(mean_AQL=("AQL", "mean"), worst_AQL=("AQL", "max"), mean_late_AQL=("late_AQL", "mean"), mean_coverage=("coverage", "mean"))
    pooled = pooled.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"], kind="mergesort").reset_index(drop=True); pooled.insert(0, "rhs_rank", np.arange(1, len(pooled) + 1))
    root = campaign / label / "closeout"; root.mkdir(parents=True, exist_ok=True); cells.to_csv(root / "cell_metrics.csv", index=False); pd.DataFrame(completion).to_csv(root / "completion_manifest.csv", index=False); pooled.to_csv(root / "ranking.csv", index=False)
    write_json(root / "summary.json", {"status": "completed_r120_rhs_closeout", "label": label, "planned_cells": len(records), "scored_cells": len(cells), "eligible_groups": len(pooled), "test_opened": False})
    return pooled


def _freeze_pure_winner(prep: Path, campaign: Path, ranking: pd.DataFrame) -> dict[str, Any]:
    row = ranking.iloc[0]; candidate, spec = _candidate(prep, campaign, str(row.candidate_id))
    value = {"status": "frozen_r120_normal_rhs_winner", "variant": "pure", "candidate_id": str(row.candidate_id),
        "tau0": float(row.tau0), "spec": spec, "selection_mean_AQL": float(row.mean_AQL), "test_opened": False}
    root = campaign / "winners"; root.mkdir(exist_ok=True); write_json(root / "pure.json", value); return value


def _stage_e_extended(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int], pure: dict[str, Any]) -> dict[str, Any] | None:
    path = campaign / "stage_e/pricefm_stage_r120e_candidate_manifest.csv"
    spec = normalize_spec({**pure["spec"], "readout": "extended_all_layers"}); from pricefm_r120_engine import active_regions
    exog_dim = 3 if spec["feature_policy"] == "target_only" else 6 if spec["feature_policy"] == "graph_summary_mean" else 9 if spec["feature_policy"] == "graph_summary_mean_std" else 3 * len(active_regions(spec))
    resources = resource_estimate(spec, exog_dim)
    if resources["extended_memory_gate_gib"] > 8.0:
        path.parent.mkdir(parents=True, exist_ok=True); write_json(path.parent / "blocked.json", {"status": "r120e_blocked_by_frozen_memory_gate", "threshold_gib": 8.0, **resources, "test_opened": False}); return None
    identity = fingerprint(spec); row = {"candidate_id": f"r120e_{identity[:16]}", "stage": "R120E", "candidate_role": "frozen_pure_reservoir_extended_ablation",
        "semantic_sha256": identity, "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
        **{key: value for key, value in spec.items() if key != "units"}, "units": json.dumps(spec["units"], separators=(",", ":")), "exog_dimension": exog_dim, **resources,
        "selection_split": "fold1_train_internal_expanding_validation", "test_access_authorized": False}
    frame = pd.DataFrame([row]); path.parent.mkdir(parents=True, exist_ok=True); frame.to_csv(path, index=False)
    tasks = _ridge_tasks(args, prep, campaign, code, frame, "R120E"); _run_queue(tasks, cpus, code, campaign / "stage_e/ridge_progress.json")
    rhs = _rhs_stage(args, prep, campaign, code, cpus, frame, "stage_e_rhs"); winner = rhs.iloc[0]
    value = {"status": "frozen_r120_normal_rhs_winner", "variant": "extended", "candidate_id": str(winner.candidate_id),
        "tau0": float(winner.tau0), "spec": spec, "selection_mean_AQL": float(winner.mean_AQL), "test_opened": False}
    write_json(campaign / "winners/extended.json", value); return value


def _write_design(path: Path, design: np.ndarray, response: np.ndarray, metadata: dict[str, Any]) -> None:
    def write(temp: Path) -> None:
        np.asarray(design, dtype="<f8").tofile(temp / "X.bin"); np.asarray(response, dtype="<f8").tofile(temp / "y.bin")
        write_json(temp / "design.json", {"n": len(response), "p": design.shape[1], **metadata, "test_opened": False})
        files = {name: {"bytes": (temp / name).stat().st_size, "sha256": sha256_file(temp / name)} for name in ("X.bin", "y.bin", "design.json")}
        write_json(temp / "terminal.json", {"status": "completed_r120_quantile_design", "stage": "R120F", "files": files, "test_opened": False})
    _atomic_directory(path, write)


def _winner(campaign: Path, variant: str) -> dict[str, Any]: return json.loads((campaign / f"winners/{variant}.json").read_text())
def _variant_root(campaign: Path, variant: str) -> Path: return campaign / f"variant_{variant}"


def full_design(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); winner = _winner(campaign, args.variant); spec = normalize_spec(winner["spec"]); fold = int(args.fold)
    output = _variant_root(campaign, args.variant) / f"full_folds/fold={fold}"; terminal = output / "design_terminal.json"
    if terminal.is_file(): return json.loads(terminal.read_text())
    control = _read_control(prep); arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), fold, "train", spec), spec)
    stats, audit = teacher_forced_statistics(arrays, spec, {"full": np.arange(len(arrays.response))}); design, response, design_audit = teacher_forced_design(arrays, spec)
    names = input_names(spec, arrays.exog_names); features = feature_names(spec, names); output.mkdir(parents=True, exist_ok=True)
    write_stats_packet(output / "normal_stats", stats["full"], {"fold": fold, "variant": args.variant, "candidate_id": winner["candidate_id"], "feature_names": features})
    _write_design(output / "quantile_design", design, response, {"fold": fold, "variant": args.variant, "candidate_id": winner["candidate_id"],
        "feature_names": features, "input_names": names, "depth": spec["depth"], "source_manifest": list(arrays.source_manifest), "reservoir_audit": audit, "design_reservoir_audit": design_audit})
    result = {"status": "completed_r120_full_fold_design", "variant": args.variant, "fold": fold, "n": len(response), "p": design.shape[1], "test_opened": False}; write_json(terminal, result); return result


def _fit_full_normal(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int], variant: str, folds: tuple[int, ...]) -> None:
    control = _read_control(prep); winner = _winner(campaign, variant); tasks = []
    for index, fold in enumerate(folds):
        root = _variant_root(campaign, variant) / f"full_folds/fold={fold}"; design_terminal = root / "design_terminal.json"
        if not design_terminal.is_file():
            _command([sys.executable, str(Path(__file__).resolve()), "--mode", "full-design", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code),
                "--prep-dir", str(prep), "--campaign-root", str(campaign), "--cpu-list", args.cpu_list, "--variant", variant, "--fold", str(fold)], code, campaign / f"logs/{variant}_full_design/fold={fold}.log", cpus[index % len(cpus)])
        output = root / "normal_rhs"; fit_id = f"r120_{variant}_full_f{fold}"; contract = _normal_contract(fit_id, root / "normal_stats", output, float(winner["tau0"]), control, code, 750)
        contract_path = campaign / f"contracts/full_normal/{variant}_fold={fold}.json"; contract_path.parent.mkdir(parents=True, exist_ok=True); write_json(contract_path, contract)
        if not _valid_normal(output): tasks.append((fit_id, [control["rscript"], str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)], campaign / f"logs/{variant}_full_normal/fold={fold}.log"))
    _run_queue(tasks, cpus, code, campaign / f"variant_{variant}/full_normal_progress.json")


def _parent_tau(tau: float) -> float | None:
    return {0.50: None, 0.45: 0.50, 0.55: 0.50, 0.25: 0.45, 0.75: 0.55, 0.10: 0.25, 0.90: 0.75}[round(float(tau), 2)]


def _quantile_contract(prep: Path, campaign: Path, variant: str, fold: int, family: str, tau: float) -> tuple[Path, Path]:
    control = _read_control(prep); winner = _winner(campaign, variant); root = _variant_root(campaign, variant) / f"full_folds/fold={fold}"
    output = root / f"quantiles/{family}/tau={tau:.2f}"; parent_tau = _parent_tau(tau)
    if family == "exal": parent = root / f"quantiles/al/tau={tau:.2f}"; parent_type = "quantile"; parent_label = f"al_tau_{tau:.2f}"
    elif parent_tau is None: parent = root / "normal_rhs"; parent_type = "normal_rhs"; parent_label = "normal_rhs"
    else: parent = root / f"quantiles/al/tau={parent_tau:.2f}"; parent_type = "quantile"; parent_label = f"al_tau_{parent_tau:.2f}"
    adapter = Path(control["campaign_root"]).parents[2] / "scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"
    # campaign_root is under data_local, so use the tracked path recorded in source manifest instead.
    source_manifest = pd.read_csv(prep / "source_manifest.csv"); adapter_rows = source_manifest[source_manifest.path.str.endswith("pricefm_stage_r67_cran111_adapter.R")]
    if len(adapter_rows) != 1: raise RuntimeError("R120 CRAN adapter source identity missing")
    adapter = Path(adapter_rows.iloc[0].path); manifest = Path(control["cran_manifest"]); design = root / "quantile_design"
    value = {"stage": "R120_production", "tag": TAG, "atom_id": f"{variant}_f{fold}_{family}_{tau:.2f}", "variant": variant,
        "readout": winner["spec"]["readout"], "fold": fold, "family": family, "tau": tau, "tau0": float(winner["tau0"]),
        "design_dir": str(design), "output_dir": str(output), "parent_dir": str(parent), "parent_type": parent_type, "parent_label": parent_label,
        "cran_library": control["cran_library"], "cran_manifest": str(manifest), "cran_manifest_sha256": sha256_file(manifest),
        "cran_adapter": str(adapter), "cran_adapter_sha256": sha256_file(adapter), "design_terminal_sha256": sha256_file(design / "terminal.json"),
        "parent_terminal_sha256": sha256_file(parent / "terminal.json"), "training_split": "train_only_explicit_lag_teacher_forced",
        "max_iter": 500, "tol": 1e-5, "n_samp_xi": 20, "n_samp": 20, "seed": int(SEEDS[0] + fold * 1000 + int(tau * 100) + (500 if family == "exal" else 0)),
        "test_access_authorized": False, "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False,
        "posterior_target_sha256": fingerprint({"variant": variant, "fold": fold, "family": family, "tau": tau, "tau0": winner["tau0"], "design": sha256_file(design / "terminal.json")})}
    path = campaign / f"contracts/quantile/{variant}/fold={fold}/{family}_tau={tau:.2f}.json"; path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and json.loads(path.read_text()) != value: raise RuntimeError(f"R120 quantile contract changed: {path}")
    write_json(path, value); return path, output


def _valid_quantile(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file(): return False
    try: value = json.loads(terminal.read_text())
    except Exception: return False
    return value.get("status") == "completed_r120_quantile_atom" and value.get("finite_core") is True and value.get("test_opened") is False


def _fit_quantiles(prep: Path, campaign: Path, code: Path, cpus: list[int], variant: str, folds: tuple[int, ...], families: tuple[str, ...] = ("al", "exal")) -> dict[int, list[str]]:
    control = _read_control(prep); order = (0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90); runner = code / "application/scripts/pricefm/415_fit_pricefm_stage_r120_quantile_atom.R"
    eligible: dict[int, list[str]] = {}
    for fold_position, fold in enumerate(folds):
        eligible[fold] = []
        for family in families:
            failed = False
            for tau in order:
                contract, output = _quantile_contract(prep, campaign, variant, fold, family, tau)
                if not _valid_quantile(output):
                    try: _command([control["rscript"], str(runner), "--config", str(contract)], code, campaign / f"logs/{variant}_quantiles/fold={fold}_{family}_{tau:.2f}.log", cpus[(fold_position + int(tau * 100)) % len(cpus)])
                    except Exception: failed = True; break
                if not _valid_quantile(output): failed = True; break
            if not failed: eligible[fold].append(family)
        write_json(_variant_root(campaign, variant) / f"full_folds/fold={fold}/quantile_eligibility.json", {"status": "completed_r120_quantile_family_gate", "fold": fold, "eligible_families": eligible[fold], "test_opened": False})
    return eligible


def _inverse_scale(values: np.ndarray, scaler: Any) -> np.ndarray:
    array = np.asarray(values, dtype=float); return scaler.inverse_transform(array.reshape(-1, 1)).reshape(array.shape)


def forecast(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); winner = _winner(campaign, args.variant); spec = normalize_spec(winner["spec"]); fold = int(args.fold); family = str(args.family)
    root = _variant_root(campaign, args.variant); output = root / f"forecasts/fold={fold}/family={family}"; terminal = output / "terminal.json"
    if terminal.is_file(): return json.loads(terminal.read_text())
    control = _read_control(prep); arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), fold, "val", spec), spec)
    normal = load_normal_fit(root / f"full_folds/fold={fold}/normal_rhs"); qfits = {tau: load_quantile_fit(root / f"full_folds/fold={fold}/quantiles/{family}/tau={tau:.2f}") for tau in QUANTILES}
    values = recursive_quantile_forecast(arrays, spec, normal, qfits, int(control["posterior_paths"]), SEEDS[0] + fold * 100 + (50 if family == "exal" else 0))
    scaler = joblib.load(Path(control["runtime_processed"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib")["BG"]["y_scaler"]
    rows = []
    for operator in ("path_specific", "mean_feature", "normal_driver"):
        scaled = prediction_metrics(values["truth"], values[operator]); original = prediction_metrics(_inverse_scale(values["truth"], scaler), _inverse_scale(values[operator], scaler))
        rows.append({"variant": args.variant, "fold": fold, "family": family, "operator": operator, **{f"scaled_{key}": value for key, value in scaled.items()}, **original})
    def write(temp: Path) -> None:
        np.savez_compressed(temp / "predictions.npz", anchors=arrays.anchors, quantiles=np.asarray(QUANTILES), **values); pd.DataFrame(rows).to_csv(temp / "metrics.csv", index=False)
        write_json(temp / "terminal.json", {"status": "completed_r120_recursive_forecast", "variant": args.variant, "fold": fold, "family": family, "paths": int(control["posterior_paths"]), "test_opened": False})
    _atomic_directory(output, write); return json.loads((output / "terminal.json").read_text())


def _forecast_one(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpu: int, variant: str, fold: int, family: str) -> pd.DataFrame:
    output = _variant_root(campaign, variant) / f"forecasts/fold={fold}/family={family}"
    if not (output / "terminal.json").is_file(): _command([sys.executable, str(Path(__file__).resolve()), "--mode", "forecast", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--cpu-list", args.cpu_list, "--variant", variant, "--fold", str(fold), "--family", family], code, campaign / f"logs/{variant}_forecast/fold={fold}_{family}.log", cpu)
    return pd.read_csv(output / "metrics.csv")


def _production_stage(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int], variants: list[str]) -> dict[str, Any]:
    # Fold 1 alone selects variant, likelihood family, and recursive summary operator.
    fold1_frames = []
    for variant in variants:
        _fit_full_normal(args, prep, campaign, code, cpus, variant, (1,)); eligible = _fit_quantiles(prep, campaign, code, cpus, variant, (1,))[1]
        for family in eligible: fold1_frames.append(_forecast_one(args, prep, campaign, code, cpus[len(fold1_frames) % len(cpus)], variant, 1, family))
    fold1 = pd.concat(fold1_frames, ignore_index=True); choices = fold1[fold1.operator.isin(["path_specific", "mean_feature"])]
    if choices.empty: raise RuntimeError("R120 has no eligible Fold-1 quantile choice")
    selected = choices.sort_values(["AQL", "late_AQL", "variant", "family", "operator"], kind="mergesort").iloc[0]
    frozen = {"variant": str(selected.variant), "family": str(selected.family), "operator": str(selected.operator), "fold1_AQL": float(selected.AQL)}
    root = campaign / "stage_f"; root.mkdir(exist_ok=True); fold1.to_csv(root / "fold1_choice_metrics.csv", index=False); write_json(root / "frozen_choice.json", {"status": "frozen_r120_fold1_choice", **frozen, "test_opened": False})
    variant, family = frozen["variant"], frozen["family"]
    _fit_full_normal(args, prep, campaign, code, cpus, variant, (2, 3)); eligibility = _fit_quantiles(prep, campaign, code, cpus, variant, (2, 3), (family,))
    if any(family not in eligibility[fold] for fold in (2, 3)): raise RuntimeError("R120 frozen family failed on an evaluation fold")
    frames = [fold1[(fold1.variant == variant) & (fold1.family == family)]]
    for fold in (2, 3): frames.append(_forecast_one(args, prep, campaign, code, cpus[fold], variant, fold, family))
    all_metrics = pd.concat(frames, ignore_index=True); final = all_metrics[all_metrics.operator == frozen["operator"]]
    all_metrics.to_csv(root / "all_metrics.csv", index=False); final.to_csv(root / "frozen_choice_metrics.csv", index=False)
    result = {"stage": "R120", "status": "completed_bg_pilot_not_promoted", **frozen, "three_fold_mean_AQL": float(final.AQL.mean()),
        "posterior_paths": 500, "test_opened": False, "registry_mutated": False, "article_mutated": False, "joint_model_fitted": False, "mcmc_fitted": False}
    write_json(root / "summary.json", result); write_json(campaign / "campaign_terminal.json", result); return result


def controller(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); code = args.code_root.resolve(); cpus = parse_cpus(args.cpu_list)
    audit = _preflight(args, prep, campaign, cpus)
    if args.preflight_only: return audit
    control = _read_control(prep); _prepare_processed(control, campaign, code, cpus[0], "1")
    stage_b = pd.read_csv(prep / "pricefm_stage_r120b_candidate_manifest.csv")
    _run_queue(_ridge_tasks(args, prep, campaign, code, stage_b, "R120B"), cpus, code, campaign / "stage_b/ridge_progress.json")
    retained = _stage_b_closeout(campaign, stage_b); stage_c = _stage_c_manifest(campaign, retained)
    _run_queue(_ridge_tasks(args, prep, campaign, code, stage_c, "R120C"), cpus, code, campaign / "stage_c/ridge_progress.json")
    primary = _ridge_ranking(campaign, stage_c, "R120C"); seeds = _stage_c_seed_robustness(campaign, primary)
    _run_queue(_ridge_tasks(args, prep, campaign, code, seeds, "R120CSEED"), cpus, code, campaign / "stage_c/seed_progress.json")
    top50 = _stage_c_closeout(campaign, stage_c, seeds); rhs = _rhs_stage(args, prep, campaign, code, cpus, top50); pure = _freeze_pure_winner(prep, campaign, rhs)
    extended = _stage_e_extended(args, prep, campaign, code, cpus, pure)
    _prepare_processed(control, campaign, code, cpus[0], "1,2,3")
    return _production_stage(args, prep, campaign, code, cpus, ["pure"] + (["extended"] if extended else []))


def main() -> int:
    args = parser().parse_args(); args.artifact_repo = args.artifact_repo.resolve(); args.code_root = args.code_root.resolve(); _, _, _, campaign = _paths(args)
    if args.mode == "ridge-cell": result = ridge_cell(args)
    elif args.mode == "rhs-score": result = rhs_score(args)
    elif args.mode == "full-design": result = full_design(args)
    elif args.mode == "forecast": result = forecast(args)
    else:
        campaign.mkdir(parents=True, exist_ok=True); lock = (campaign / "controller.lock").open("a+")
        try: fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error: raise RuntimeError("another R120 controller owns this campaign") from error
        try: result = controller(args)
        finally: lock.close()
    print(json.dumps(result, indent=2, sort_keys=True)); return 0


if __name__ == "__main__": raise SystemExit(main())
