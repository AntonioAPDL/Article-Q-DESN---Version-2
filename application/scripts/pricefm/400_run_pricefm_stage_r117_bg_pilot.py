#!/usr/bin/env python3
"""Run and automatically advance the resumable PriceFM R117 BG pilot."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
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

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json
from pricefm_r117_engine import (
    HORIZONS, QUANTILES, corrected_arrays, feature_names, fingerprint,
    fit_scaled_ridge, internal_splits, load_normal_fit, load_quantile_fit,
    load_windows, normalize_spec, prediction_metrics, recursive_normal_score,
    recursive_quantile_forecast, teacher_forced_design,
    teacher_forced_statistics, write_stats_packet,
)


DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)
WARM_ORDER = (0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90)
WARM_PARENT = {0.50: None, 0.45: 0.50, 0.55: 0.50, 0.25: 0.45, 0.75: 0.55, 0.10: 0.25, 0.90: 0.75}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=("controller", "ridge-cell", "rhs-score", "full-design", "forecast"), default="controller")
    p.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    p.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    p.add_argument("--prep-dir", type=Path)
    p.add_argument("--campaign-root", type=Path)
    p.add_argument("--workers", type=int, default=15)
    p.add_argument("--cpu-list", default="0-14")
    p.add_argument("--candidate-id")
    p.add_argument("--fit-dir", type=Path)
    p.add_argument("--split", type=int)
    p.add_argument("--fold", type=int)
    p.add_argument("--family", choices=("al", "exal"))
    p.add_argument("--variant", choices=("pure", "extended"), default="pure")
    p.add_argument("--minimum-free-gib", type=float, default=120.0)
    p.add_argument("--minimum-memory-gib", type=float, default=80.0)
    p.add_argument("--maximum-cpu-percent", type=float, default=30.0)
    p.add_argument("--preflight-only", action="store_true")
    return p


def _paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    artifact = args.artifact_repo.resolve()
    data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    return artifact, data, prep, campaign


def _variant_root(campaign: Path, variant: str) -> Path:
    return campaign if str(variant) == "pure" else campaign / "extended"


def _winner_path(campaign: Path, variant: str) -> Path:
    name = "winner.json" if str(variant) == "pure" else "extended_winner.json"
    return campaign / "winner" / name


def parse_cpus(value: str) -> list[int]:
    result = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lo, hi = token.split("-", 1)
            result.extend(range(int(lo), int(hi) + 1))
        else:
            result.append(int(token))
    if not result or len(result) != len(set(result)) or min(result) < 0 or max(result) >= (os.cpu_count() or 0):
        raise ValueError("invalid CPU list")
    return result


def _physical_core(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())


def _physical_core_max_usage(cpu: int, usage: dict[int, float]) -> float:
    identity = _physical_core(cpu)
    siblings = [value for logical, value in usage.items() if _physical_core(logical) == identity]
    if not siblings:
        raise RuntimeError(f"cannot resolve physical-core siblings for CPU {cpu}")
    return max(siblings)


def _cpu_snapshot(interval: float = 0.6) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        values = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(value) for value in fields[1:]]
                values[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
        return values
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100.0 * (1.0 - (after[cpu][1] - idle) / max(1, after[cpu][0] - total))
        for cpu, (total, idle) in before.items()
    }


def _command(command: list[str], cwd: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command] if cpu is not None else command
    with log.open("a") as handle:
        handle.write("$ {}\n".format(" ".join(map(str, actual))))
        handle.flush()
        process = subprocess.run(actual, cwd=str(cwd), env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if process.returncode:
        raise RuntimeError(f"command failed ({process.returncode}): {' '.join(command)}")


def _atomic_directory(output: Path, writer: Callable[[Path], None]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.parent / f"{output.name}.tmp.{os.getpid()}"
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir()
    try:
        writer(temporary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def _read_control(prep: Path) -> dict[str, Any]:
    return json.loads((prep / "launch_control.json").read_text())


def _candidate(prep: Path, candidate_id: str) -> tuple[pd.Series, dict[str, Any]]:
    manifest = pd.read_csv(prep / "pricefm_stage_r117_candidate_manifest.csv")
    selected = manifest[manifest.candidate_id.astype(str).eq(str(candidate_id))]
    if len(selected) != 1:
        raise RuntimeError("candidate_id must identify exactly one R117 row")
    row = selected.iloc[0]
    return row, normalize_spec(json.loads(str(row.spec_json)))


def _ridge_terminal(path: Path) -> bool:
    terminal = path / "terminal.json"
    if not terminal.is_file():
        return False
    try:
        value = json.loads(terminal.read_text())
    except Exception:
        return False
    return value.get("status") == "completed_r117_ridge_cell" and not value.get("test_opened", True)


def ridge_cell(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args)
    row, spec = _candidate(prep, str(args.candidate_id))
    output = campaign / "ridge_runs" / str(row.candidate_id)
    if _ridge_terminal(output):
        return json.loads((output / "terminal.json").read_text())
    control = _read_control(prep)
    windows = load_windows(Path(control["runtime_processed"]), 1, "train", spec)
    arrays = corrected_arrays(windows, spec)
    splits = internal_splits(len(arrays.response))
    groups = {f"train_{item['split']}": item["train"] for item in splits}
    stats, _, _ = teacher_forced_statistics(arrays, spec, groups)
    fits = {name: fit_scaled_ridge(value) for name, value in stats.items()}
    metrics = []
    for item in splits:
        split_id = int(item["split"])
        score = recursive_normal_score(
            arrays, spec, fits[f"train_{split_id}"], item["validation"], maximum_origins=48
        )
        metrics.append({"split": split_id, **{key: value for key, value in score.items() if key != "horizon_blocks"}})

    def write(temp: Path) -> None:
        payload = {}
        for split_id in (1, 2, 3):
            value = stats[f"train_{split_id}"]
            payload[f"split{split_id}_XtX"] = value["XtX"]
            payload[f"split{split_id}_Xty"] = value["Xty"]
            payload[f"split{split_id}_yty"] = np.asarray([value["yty"]])
            payload[f"split{split_id}_n"] = np.asarray([value["n"]], dtype=np.int64)
        np.savez_compressed(temp / "training_statistics.npz", **payload)
        pd.DataFrame(metrics).to_csv(temp / "validation_metrics.csv", index=False)
        write_json(temp / "contract.json", {
            "candidate_id": str(row.candidate_id), "spec": spec,
            "semantic_sha256": str(row.semantic_sha256),
            "feature_names": feature_names(spec, arrays.input_names),
            "input_names": list(arrays.input_names), "source_manifest": list(arrays.source_manifest),
            "selection_split": str(row.selection_split), "test_opened": False,
        })
        artifacts = {}
        for name in ("training_statistics.npz", "validation_metrics.csv", "contract.json"):
            artifacts[name] = {"bytes": (temp / name).stat().st_size, "sha256": sha256_file(temp / name)}
        write_json(temp / "terminal.json", {
            "status": "completed_r117_ridge_cell", "stage": "R117A",
            "candidate_id": str(row.candidate_id), "p": len(feature_names(spec, arrays.input_names)),
            "mean_AQL": float(np.mean([value["AQL"] for value in metrics])),
            "mean_late_AQL": float(np.mean([value["late_AQL"] for value in metrics])),
            "artifacts": artifacts, "test_opened": False,
        })
    _atomic_directory(output, write)
    return json.loads((output / "terminal.json").read_text())


def _stats_from_ridge(path: Path, split: int) -> dict[str, Any]:
    with np.load(path / "training_statistics.npz") as packet:
        xtx = np.asarray(packet[f"split{split}_XtX"], dtype=float)
        return {
            "n": int(packet[f"split{split}_n"][0]), "p": int(xtx.shape[0]),
            "XtX": xtx, "Xty": np.asarray(packet[f"split{split}_Xty"], dtype=float),
            "yty": float(packet[f"split{split}_yty"][0]),
        }


def rhs_score(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args)
    row, spec = _candidate(prep, str(args.candidate_id))
    split = int(args.split)
    fit_dir = Path(args.fit_dir).resolve()
    output = fit_dir / "validation_score.json"
    if output.is_file():
        return json.loads(output.read_text())
    control = _read_control(prep)
    arrays = corrected_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    selection = internal_splits(len(arrays.response))[split - 1]
    score = recursive_normal_score(arrays, spec, load_normal_fit(fit_dir), selection["validation"], maximum_origins=96)
    result = {
        "status": "completed_r117_rhs_validation_score", "candidate_id": str(row.candidate_id),
        "split": split, "fit_dir": str(fit_dir), **score, "test_opened": False,
    }
    write_json(output, result)
    return result


def _write_design(path: Path, design: np.ndarray, response: np.ndarray, meta: dict[str, Any]) -> None:
    def write(temp: Path) -> None:
        np.asarray(design, dtype="<f8").tofile(temp / "X.bin")
        np.asarray(response, dtype="<f8").tofile(temp / "y.bin")
        write_json(temp / "design.json", {"n": len(response), "p": design.shape[1], **meta, "test_opened": False})
        files = {name: {"bytes": (temp / name).stat().st_size, "sha256": sha256_file(temp / name)} for name in ("X.bin", "y.bin", "design.json")}
        write_json(temp / "terminal.json", {"status": "completed_r117_quantile_design", "stage": "R117C", "files": files, "test_opened": False})
    _atomic_directory(path, write)


def full_design(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args)
    variant = str(args.variant)
    winner = json.loads(_winner_path(campaign, variant).read_text())
    spec = normalize_spec(winner["spec"])
    fold = int(args.fold)
    output = _variant_root(campaign, variant) / f"full_folds/fold={fold}"
    terminal = output / "design_terminal.json"
    if terminal.is_file():
        return json.loads(terminal.read_text())
    control = _read_control(prep)
    arrays = corrected_arrays(load_windows(Path(control["runtime_processed"]), fold, "train", spec), spec)
    stats, _, _ = teacher_forced_statistics(arrays, spec, {"full": np.arange(len(arrays.response))})
    design, response, _, _ = teacher_forced_design(arrays, spec)
    output.mkdir(parents=True, exist_ok=True)
    write_stats_packet(output / "normal_stats", stats["full"], {
        "fold": fold, "variant": variant, "candidate_id": winner["candidate_id"], "feature_names": feature_names(spec, arrays.input_names),
    })
    _write_design(output / "quantile_design", design, response, {
        "fold": fold, "variant": variant, "candidate_id": winner["candidate_id"], "feature_names": feature_names(spec, arrays.input_names),
        "source_manifest": list(arrays.source_manifest),
    })
    result = {"status": "completed_r117_full_fold_design", "variant": variant, "fold": fold, "n": len(response), "p": design.shape[1], "test_opened": False}
    write_json(terminal, result)
    return result


def _inverse_scale(values: np.ndarray, scaler: Any) -> np.ndarray:
    array = np.asarray(values, dtype=float)
    return scaler.inverse_transform(array.reshape(-1, 1)).reshape(array.shape)


def forecast(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args)
    variant = str(args.variant)
    winner = json.loads(_winner_path(campaign, variant).read_text())
    spec = normalize_spec(winner["spec"])
    fold, family = int(args.fold), str(args.family)
    root = _variant_root(campaign, variant)
    output = root / f"forecasts/fold={fold}/family={family}"
    terminal = output / "terminal.json"
    if terminal.is_file():
        return json.loads(terminal.read_text())
    control = _read_control(prep)
    arrays = corrected_arrays(load_windows(Path(control["runtime_processed"]), fold, "val", spec), spec)
    normal = load_normal_fit(root / f"full_folds/fold={fold}/normal_rhs")
    qfits = {
        float(tau): load_quantile_fit(root / f"full_folds/fold={fold}/quantiles/{family}/tau={tau:.2f}")
        for tau in QUANTILES
    }
    values = recursive_quantile_forecast(
        arrays, spec, normal, qfits, paths=int(control["posterior_paths"]),
        seed=2026092501 + fold * 100 + (0 if family == "al" else 50),
    )
    scaler_path = Path(control["runtime_processed"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
    rows = []
    for operator in ("path_specific", "mean_feature", "normal_driver"):
        scaled = prediction_metrics(values["truth"], values[operator])
        original = prediction_metrics(_inverse_scale(values["truth"], scaler), _inverse_scale(values[operator], scaler))
        rows.append({"variant": variant, "fold": fold, "family": family, "operator": operator, **{f"scaled_{k}": v for k, v in scaled.items()}, **{k: v for k, v in original.items()}})
    def write(temp: Path) -> None:
        np.savez_compressed(temp / "predictions.npz", anchors=arrays.anchors, quantiles=np.asarray(QUANTILES), **values)
        pd.DataFrame(rows).to_csv(temp / "metrics.csv", index=False)
        files = {name: {"bytes": (temp / name).stat().st_size, "sha256": sha256_file(temp / name)} for name in ("predictions.npz", "metrics.csv")}
        write_json(temp / "terminal.json", {"status": "completed_r117_recursive_forecast", "variant": variant, "fold": fold, "family": family, "paths": int(control["posterior_paths"]), "files": files, "test_opened": False})
    _atomic_directory(output, write)
    return json.loads((output / "terminal.json").read_text())


def _run_queue(
    tasks: list[tuple[str, list[str], Path]], cpus: list[int], cwd: Path,
    progress: Path, *, fail_fast: bool = True,
) -> dict[str, Any]:
    pending = list(tasks)
    state = {
        "total": len(tasks), "complete": 0, "failed": 0,
        "failed_task_ids": [], "updated_at_epoch": time.time(),
    }
    lock = threading.Lock()
    buckets = [[] for _ in cpus]
    for index, task in enumerate(pending):
        buckets[index % len(cpus)].append(task)
    def worker(cpu: int, bucket: list[tuple[str, list[str], Path]]) -> None:
        for task_id, command, log in bucket:
            ok = True
            try:
                _command(command, cwd, log, cpu)
            except Exception:
                ok = False
            with lock:
                state["complete" if ok else "failed"] += 1
                if not ok:
                    state["failed_task_ids"].append(task_id)
                state["updated_at_epoch"] = time.time()
                write_json(progress, state)
            if not ok and fail_fast:
                raise RuntimeError(f"R117 task failed: {task_id}")
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures):
            future.result()
    if not tasks:
        write_json(progress, state)
    if fail_fast and state["failed"]:
        raise RuntimeError(
            f"R117 queue failed {state['failed']}/{state['total']} tasks: "
            f"{state['failed_task_ids'][:10]}"
        )
    return state


def _valid_normal_terminal(output: Path) -> bool:
    path = output / "terminal.json"
    if not path.is_file():
        return False
    try:
        value = json.loads(path.read_text())
    except Exception:
        return False
    return (
        value.get("status") == "completed_recursive_normal_fit"
        and value.get("converged") is True
        and value.get("test_opened") is False
    )


def _complete_screening_groups(
    cells: pd.DataFrame, group_columns: list[str], expected_splits: tuple[int, ...] = (1, 2, 3),
) -> pd.DataFrame:
    if cells.empty:
        return cells.copy()
    expected = set(expected_splits)
    eligible_keys = []
    for key, group in cells.groupby(group_columns, sort=False, dropna=False):
        key_tuple = key if isinstance(key, tuple) else (key,)
        if set(group["split"].astype(int)) == expected and len(group) == len(expected):
            eligible_keys.append(key_tuple)
    if not eligible_keys:
        return cells.iloc[0:0].copy()
    key_frame = pd.DataFrame(eligible_keys, columns=group_columns)
    return cells.merge(key_frame, on=group_columns, how="inner", validate="many_to_one")


def _preflight(args: argparse.Namespace, prep: Path, campaign: Path, cpus: list[int]) -> dict[str, Any]:
    summary = json.loads((prep / "summary.json").read_text())
    if not summary.get("launch_authorized") or summary.get("test_opened"):
        raise RuntimeError("R117 preparation is not launch-authorized")
    sources = pd.read_csv(prep / "source_manifest.csv")
    changed = [row.path for row in sources.itertuples(index=False) if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256)]
    if changed:
        raise RuntimeError(f"R117 source hash mismatch: {changed}")
    if args.workers != 15 or len(cpus) != 15 or len({_physical_core(cpu) for cpu in cpus}) != 15:
        raise RuntimeError("R117 requires 15 workers on 15 distinct physical cores")
    usage = _cpu_snapshot()
    physical_usage = {cpu: _physical_core_max_usage(cpu, usage) for cpu in cpus}
    disk = shutil.disk_usage(campaign.parent)
    memory_kib = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:"))
    control = _read_control(prep)
    rscript = Path(control["rscript"])
    adapter = args.code_root.resolve() / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"
    r_expression = (
        f"stopifnot(as.character(getRversion()) == {json.dumps(control['r_version'])}); "
        f"source({json.dumps(str(adapter))}); "
        f"x <- r67_assert_cran_package({json.dumps(control['cran_library'])}, expected_version='1.1.1'); "
        "stopifnot(identical(x$repository, 'CRAN'))"
    )
    r_runtime = subprocess.run(
        [str(rscript), "--vanilla", "-e", r_expression], capture_output=True, text=True,
        env={**os.environ, **{name: "1" for name in THREAD_ENV}}, check=False,
    ) if rscript.is_file() else None
    checks = {
        "sources": not changed,
        "disk": disk.free / 2**30 >= args.minimum_free_gib,
        "memory": memory_kib / 2**20 >= args.minimum_memory_gib,
        "cpus": all(physical_usage[cpu] <= args.maximum_cpu_percent for cpu in cpus),
        "r_runtime": r_runtime is not None and r_runtime.returncode == 0,
    }
    result = {
        "status": "preflight_passed" if all(checks.values()) else "preflight_blocked",
        "checks": checks, "workers": len(cpus), "cpus": cpus,
        "cpu_percent": {str(cpu): usage[cpu] for cpu in cpus},
        "physical_core_max_percent": {str(cpu): physical_usage[cpu] for cpu in cpus},
        "rscript": str(rscript), "r_version": control["r_version"],
        "r_runtime_stderr": "" if r_runtime is None else r_runtime.stderr.strip(),
        "free_disk_gib": disk.free / 2**30, "available_memory_gib": memory_kib / 2**20,
        "test_opened": False,
    }
    campaign.mkdir(parents=True, exist_ok=True)
    write_json(campaign / "launch_preflight.json", result)
    if not all(checks.values()):
        raise RuntimeError(f"R117 preflight blocked: {[key for key, value in checks.items() if not value]}")
    return result


def _prepare_processed(control: dict[str, Any], campaign: Path, prep: Path, code_root: Path, cpus: list[int], folds: str = "1") -> None:
    runtime = Path(control["runtime_processed"])
    source = Path(control["source_processed"])
    runtime.mkdir(parents=True, exist_ok=True)
    for name in ("splits_scaled", "scalers"):
        destination = runtime / name
        if destination.is_symlink():
            if destination.resolve() != (source / name).resolve():
                raise RuntimeError("R117 processed dependency changed")
        elif not destination.exists():
            destination.symlink_to(source / name, target_is_directory=True)
        else:
            raise RuntimeError("R117 processed dependency is not a symlink")
    from pricefm_r117_engine import active_regions
    candidates = pd.read_csv(prep / "pricefm_stage_r117_candidate_manifest.csv")
    specs = [normalize_spec(json.loads(value)) for value in candidates.spec_json]
    regions = sorted(set(region for spec in specs for region in active_regions(spec)))
    python = str(Path(control["source_processed"]).parents[2] / "venv/bin/python")
    for index, lag in enumerate(sorted(candidates.lag_window.astype(int).unique())):
        _command([
            python, str(code_root / "application/scripts/pricefm/05_build_windows.py"),
            "--config", str(control["data_configs"][str(lag)]), "--pilot-only", "false",
            "--regions", ",".join(regions), "--folds", folds, "--resume", "true", "--force", "false",
        ], code_root, campaign / f"logs/windows_L{lag}_folds_{folds.replace(',', '_')}.log", cpus[index % len(cpus)])


def _ridge_closeout(prep: Path, campaign: Path) -> pd.DataFrame:
    candidates = pd.read_csv(prep / "pricefm_stage_r117_candidate_manifest.csv")
    rows = []
    for row in candidates.itertuples(index=False):
        root = campaign / "ridge_runs" / str(row.candidate_id)
        if not _ridge_terminal(root):
            raise RuntimeError(f"incomplete R117 Ridge cell: {row.candidate_id}")
        metric = pd.read_csv(root / "validation_metrics.csv")
        rows.append({
            "candidate_id": row.candidate_id, "semantic_sha256": row.semantic_sha256,
            "feature_policy": row.feature_policy, "calendar": row.calendar,
            "units": row.units, "lag_window": row.lag_window, "alpha": row.alpha,
            "rho": row.rho, "input_scale": row.input_scale, "recurrent_sparsity": row.recurrent_sparsity,
            "mean_AQL": metric.AQL.mean(), "worst_AQL": metric.AQL.max(),
            "mean_late_AQL": metric.late_AQL.mean(), "mean_coverage": metric.interval_80_coverage.mean(),
            "p": json.loads((root / "terminal.json").read_text())["p"],
        })
    ranking = pd.DataFrame(rows).sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "p", "candidate_id"], kind="mergesort"
    ).reset_index(drop=True)
    ranking.insert(0, "ridge_rank", np.arange(1, len(ranking) + 1))
    closeout = campaign / "ridge_closeout"
    closeout.mkdir(exist_ok=True)
    ranking.to_csv(closeout / "ranking.csv", index=False)
    ranking.head(50).to_csv(closeout / "top50.csv", index=False)
    write_json(closeout / "summary.json", {"status": "completed_r117_ridge_closeout", "cells": len(ranking), "top_k": 50, "test_opened": False})
    return ranking.head(50)


def _normal_contract(
    fit_id: str, stats_dir: Path, output_dir: Path, tau0: float, control: dict[str, Any],
    code_root: Path, *, max_iter: int = 500,
) -> dict[str, Any]:
    return {
        "fit_id": fit_id, "stats_dir": str(stats_dir), "output_dir": str(output_dir),
        "prior_type": "rhs_ns", "tau0": float(tau0),
        "package_path": control["normal_runtime"],
        "helper_path": str(code_root / "application/R/pricefm_recursive_normal_fit.R"),
        "max_iter": int(max_iter), "min_iter": 100, "tol": 1e-5,
        "convergence_mode": "predictive_fixed_point", "stability_window": 10,
        "predictive_tol": 1e-7, "relative_beta_tol": 1e-6,
        "sigma_relative_tol": 1e-8, "prior_rms_log_precision_tol": 1e-6,
        "posterior_target_sha256": fingerprint({"fit_id": fit_id, "tau0": tau0, "stats": sha256_file(stats_dir / "terminal.json")}),
        "selection_split": "train_validation_only", "test_access_authorized": False,
    }


def _rhs_stage(args: argparse.Namespace, prep: Path, campaign: Path, code_root: Path, cpus: list[int], top: pd.DataFrame) -> pd.DataFrame:
    control = _read_control(prep)
    contracts = campaign / "rhs_contracts"
    tasks = []
    records = []
    rscript = str(control["rscript"])
    for row in top.itertuples(index=False):
        ridge = campaign / "ridge_runs" / str(row.candidate_id)
        for split in (1, 2, 3):
            stats = _stats_from_ridge(ridge, split)
            stats_dir = campaign / f"rhs_stats/{row.candidate_id}/split={split}"
            if not (stats_dir / "terminal.json").is_file():
                write_stats_packet(stats_dir, stats, {"candidate_id": row.candidate_id, "split": split})
            reference = float(control["rhs_tau_reference"]) * math.sqrt(float(control["rhs_tau_reference_dimension"]) / stats["p"])
            for multiplier in control["rhs_tau_multipliers"]:
                tau0 = reference * float(multiplier)
                fit_id = f"{row.candidate_id}_s{split}_m{multiplier:g}"
                output = campaign / f"rhs_fits/{fit_id}"
                output.parent.mkdir(parents=True, exist_ok=True)
                contract = _normal_contract(fit_id, stats_dir, output, tau0, control, code_root)
                contract_path = contracts / f"{fit_id}.json"
                contract_path.parent.mkdir(parents=True, exist_ok=True)
                write_json(contract_path, contract)
                if not _valid_normal_terminal(output):
                    tasks.append((fit_id, [rscript, str(code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)], campaign / f"logs/rhs_fit/{fit_id}.log"))
                records.append({"fit_id": fit_id, "candidate_id": row.candidate_id, "split": split, "tau0": tau0, "multiplier": multiplier, "output_dir": str(output)})
    _run_queue(
        tasks, cpus, code_root, campaign / "rhs_fit_progress.json",
        fail_fast=False,
    )
    score_tasks = []
    python = sys.executable
    for record in records:
        fit_dir = Path(record["output_dir"])
        if _valid_normal_terminal(fit_dir) and not (fit_dir / "validation_score.json").is_file():
            score_tasks.append((record["fit_id"], [python, str(Path(__file__).resolve()), "--mode", "rhs-score", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code_root), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--candidate-id", record["candidate_id"], "--split", str(record["split"]), "--fit-dir", str(fit_dir)], campaign / f"logs/rhs_score/{record['fit_id']}.log"))
    _run_queue(
        score_tasks, cpus, code_root, campaign / "rhs_score_progress.json",
        fail_fast=False,
    )
    rows = []
    completion = []
    for record in records:
        fit_dir = Path(record["output_dir"])
        fit_completed = _valid_normal_terminal(fit_dir)
        score_path = fit_dir / "validation_score.json"
        score_completed = fit_completed and score_path.is_file()
        completion.append({
            **record, "fit_completed": fit_completed,
            "score_completed": score_completed,
            "cell_eligible": score_completed,
        })
        if score_completed:
            score = json.loads(score_path.read_text())
            rows.append({**record, "AQL": score["AQL"], "late_AQL": score["late_AQL"], "coverage": score["interval_80_coverage"]})
    cells = pd.DataFrame(rows)
    complete_cells = _complete_screening_groups(
        cells, ["candidate_id", "tau0", "multiplier"],
    )
    if complete_cells.empty:
        raise RuntimeError("R117 RHS screening produced no complete three-split candidate/tau0 group")
    pooled = complete_cells.groupby(["candidate_id", "tau0", "multiplier"], as_index=False).agg(mean_AQL=("AQL", "mean"), worst_AQL=("AQL", "max"), mean_late_AQL=("late_AQL", "mean"), mean_coverage=("coverage", "mean"))
    pooled = pooled.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"], kind="mergesort").reset_index(drop=True)
    pooled.insert(0, "rhs_rank", np.arange(1, len(pooled) + 1))
    closeout = campaign / "rhs_closeout"
    closeout.mkdir(exist_ok=True)
    cells.to_csv(closeout / "cell_metrics.csv", index=False)
    complete_cells.to_csv(closeout / "eligible_complete_group_cells.csv", index=False)
    pd.DataFrame(completion).to_csv(closeout / "completion_manifest.csv", index=False)
    pooled.to_csv(closeout / "ranking.csv", index=False)
    write_json(closeout / "summary.json", {
        "status": "completed_r117_rhs_screening_closeout",
        "planned_cells": len(records),
        "fit_completed_cells": sum(item["fit_completed"] for item in completion),
        "scored_cells": len(cells),
        "eligible_complete_groups": len(pooled),
        "incomplete_or_failed_cells": sum(not item["score_completed"] for item in completion),
        "test_opened": False,
    })
    winner = pooled.iloc[0]
    _, spec = _candidate(prep, str(winner.candidate_id))
    winner_payload = {"status": "frozen_r117_normal_rhs_winner", "candidate_id": str(winner.candidate_id), "tau0": float(winner.tau0), "spec": spec, "selection_mean_AQL": float(winner.mean_AQL), "test_opened": False}
    winner_dir = campaign / "winner"
    winner_dir.mkdir(exist_ok=True)
    write_json(winner_dir / "winner.json", winner_payload)
    return pooled


def _fit_extended_tau0(
    args: argparse.Namespace, prep: Path, campaign: Path, code_root: Path, cpus: list[int],
) -> dict[str, Any]:
    winner_path = _winner_path(campaign, "extended")
    if winner_path.is_file():
        return json.loads(winner_path.read_text())
    control = _read_control(prep)
    pure_winner = json.loads(_winner_path(campaign, "pure").read_text())
    spec = normalize_spec({**pure_winner["spec"], "readout": "extended_all_layers"})
    arrays = corrected_arrays(
        load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec,
    )
    splits = internal_splits(len(arrays.response))
    groups = {f"train_{item['split']}": item["train"] for item in splits}
    statistics, _, _ = teacher_forced_statistics(arrays, spec, groups)
    pure_dimension = 1 + sum(spec["units"])
    extended_dimension = int(next(iter(statistics.values()))["p"])
    reference = float(pure_winner["tau0"]) * math.sqrt(pure_dimension / extended_dimension)
    rscript = str(control["rscript"])
    tasks = []
    records = []
    for split in (1, 2, 3):
        stats_dir = campaign / f"extended/tau0_stats/split={split}"
        if not (stats_dir / "terminal.json").is_file():
            write_stats_packet(stats_dir, statistics[f"train_{split}"], {
                "variant": "extended", "candidate_id": pure_winner["candidate_id"],
                "split": split, "pure_dimension": pure_dimension,
                "extended_dimension": extended_dimension,
            })
        for multiplier in control["rhs_tau_multipliers"]:
            tau0 = reference * float(multiplier)
            fit_id = f"r117_extended_s{split}_m{multiplier:g}"
            output = campaign / f"extended/tau0_fits/{fit_id}"
            output.parent.mkdir(parents=True, exist_ok=True)
            contract = _normal_contract(fit_id, stats_dir, output, tau0, control, code_root)
            contract_path = campaign / f"extended/tau0_contracts/{fit_id}.json"
            contract_path.parent.mkdir(parents=True, exist_ok=True)
            write_json(contract_path, contract)
            if not _valid_normal_terminal(output):
                tasks.append((fit_id, [
                    rscript,
                    str(code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"),
                    "--contract", str(contract_path),
                ], campaign / f"logs/extended_tau0_fit/{fit_id}.log"))
            records.append({
                "fit_id": fit_id, "split": split, "tau0": tau0,
                "multiplier": multiplier, "output_dir": str(output),
            })
    _run_queue(
        tasks, cpus, code_root, campaign / "extended/tau0_fit_progress.json",
        fail_fast=False,
    )
    rows = []
    completion = []
    for record in records:
        fit_completed = _valid_normal_terminal(Path(record["output_dir"]))
        scored = False
        if fit_completed:
            try:
                selection = splits[int(record["split"]) - 1]
                score = recursive_normal_score(
                    arrays, spec, load_normal_fit(Path(record["output_dir"])),
                    selection["validation"], maximum_origins=96,
                )
                rows.append({
                    **record, "AQL": score["AQL"], "late_AQL": score["late_AQL"],
                    "coverage": score["interval_80_coverage"],
                })
                scored = True
            except Exception:
                scored = False
        completion.append({
            **record, "fit_completed": fit_completed,
            "score_completed": scored, "cell_eligible": scored,
        })
    cells = pd.DataFrame(rows)
    complete_cells = _complete_screening_groups(cells, ["tau0", "multiplier"])
    if complete_cells.empty:
        raise RuntimeError("R117 extended tau0 screening produced no complete three-split group")
    pooled = complete_cells.groupby(["tau0", "multiplier"], as_index=False).agg(
        mean_AQL=("AQL", "mean"), worst_AQL=("AQL", "max"),
        mean_late_AQL=("late_AQL", "mean"), mean_coverage=("coverage", "mean"),
    ).sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "tau0"], kind="mergesort",
    ).reset_index(drop=True)
    pooled.insert(0, "rank", np.arange(1, len(pooled) + 1))
    closeout = campaign / "extended/tau0_closeout"
    closeout.mkdir(parents=True, exist_ok=True)
    cells.to_csv(closeout / "cell_metrics.csv", index=False)
    complete_cells.to_csv(closeout / "eligible_complete_group_cells.csv", index=False)
    pd.DataFrame(completion).to_csv(closeout / "completion_manifest.csv", index=False)
    pooled.to_csv(closeout / "ranking.csv", index=False)
    write_json(closeout / "summary.json", {
        "status": "completed_r117_extended_tau0_closeout",
        "planned_cells": len(records),
        "fit_completed_cells": sum(item["fit_completed"] for item in completion),
        "scored_cells": len(cells),
        "eligible_complete_groups": len(pooled),
        "incomplete_or_failed_cells": sum(not item["score_completed"] for item in completion),
        "test_opened": False,
    })
    selected = pooled.iloc[0]
    payload = {
        "status": "frozen_r117_extended_rhs_winner",
        "variant": "extended", "candidate_id": pure_winner["candidate_id"],
        "tau0": float(selected.tau0), "spec": spec,
        "selection_mean_AQL": float(selected.mean_AQL),
        "geometry_source": "frozen_pure_r117_winner",
        "tau0_recalibration_only": True, "test_opened": False,
    }
    winner_path.parent.mkdir(exist_ok=True)
    write_json(winner_path, payload)
    return payload


def _fit_full_normal(
    args: argparse, prep: Path, campaign: Path, code_root: Path, cpus: list[int], variant: str,
) -> None:
    control = _read_control(prep)
    winner = json.loads(_winner_path(campaign, variant).read_text())
    variant_root = _variant_root(campaign, variant)
    python = sys.executable
    design_tasks = []
    for fold in (1, 2, 3):
        if not (variant_root / f"full_folds/fold={fold}/design_terminal.json").is_file():
            design_tasks.append((f"{variant}_full_design_f{fold}", [python, str(Path(__file__).resolve()), "--mode", "full-design", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code_root), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--variant", variant, "--fold", str(fold)], campaign / f"logs/{variant}_full_design/fold={fold}.log"))
    _run_queue(design_tasks, cpus, code_root, variant_root / "full_design_progress.json")
    rscript = str(control["rscript"])
    fit_tasks = []
    for fold in (1, 2, 3):
        root = variant_root / f"full_folds/fold={fold}"
        output = root / "normal_rhs"
        contract = _normal_contract(
            f"r117_{variant}_full_f{fold}", root / "normal_stats", output,
            float(winner["tau0"]), control, code_root, max_iter=1000,
        )
        contract_path = root / "normal_contract.json"
        write_json(contract_path, contract)
        if not (output / "terminal.json").is_file():
            fit_tasks.append((f"{variant}_normal_f{fold}", [rscript, str(code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)], campaign / f"logs/{variant}_full_normal/fold={fold}.log"))
    _run_queue(fit_tasks, cpus, code_root, variant_root / "full_normal_progress.json")


def _quantile_atom_config(control: dict[str, Any], campaign: Path, code_root: Path, variant: str, fold: int, family: str, tau: float) -> tuple[Path, Path]:
    winner = json.loads(_winner_path(campaign, variant).read_text())
    root = _variant_root(campaign, variant) / f"full_folds/fold={fold}"
    output = root / f"quantiles/{family}/tau={tau:.2f}"
    if family == "exal":
        parent = root / f"quantiles/al/tau={tau:.2f}"
        parent_label = f"al_tau_{tau:.2f}"
    elif WARM_PARENT[tau] is None:
        parent = root / "normal_rhs"
        parent_label = "normal_rhs"
    else:
        parent_tau = float(WARM_PARENT[tau])
        parent = root / f"quantiles/al/tau={parent_tau:.2f}"
        parent_label = f"al_tau_{parent_tau:.2f}"
    atom_id = f"r117_{variant}_f{fold}_{family}_tau{tau:.2f}"
    config = {
        "stage": "R117", "atom_id": atom_id, "variant": variant, "fold": fold, "family": family, "tau": tau,
        "tau0": float(winner["tau0"]), "design_dir": str(root / "quantile_design"),
        "parent_dir": str(parent), "parent_label": parent_label, "output_dir": str(output),
        "cran_library": control["cran_library"], "cran_manifest": control["cran_manifest"],
        "cran_manifest_sha256": sha256_file(control["cran_manifest"]),
        "cran_adapter": str(code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"),
        "max_iter": 500, "tol": 1e-5, "n_samp_xi": 200, "n_samp": 200,
        "seed": 2026092501 + fold * 1000 + int(round(tau * 100)) + (500 if family == "exal" else 0),
        "training_split": "train_only_corrected_teacher_forced",
        "posterior_target_sha256": fingerprint({"variant": variant, "fold": fold, "family": family, "tau": tau, "tau0": winner["tau0"], "design": sha256_file(root / "quantile_design/terminal.json")}),
        "test_access_authorized": False, "joint_model_authorized": False, "mcmc_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    config_path = root / f"quantile_contracts/{family}_tau={tau:.2f}.json"
    write_json(config_path, config)
    return config_path, output


def _fit_quantiles(prep: Path, campaign: Path, code_root: Path, cpus: list[int], variant: str) -> list[str]:
    control = _read_control(prep)
    rscript = str(control["rscript"])
    variant_root = _variant_root(campaign, variant)
    def fold_worker(fold: int, cpu: int) -> None:
        for tau in WARM_ORDER:
            for family in ("al", "exal"):
                config, output = _quantile_atom_config(control, campaign, code_root, variant, fold, family, tau)
                if (output / "terminal.json").is_file():
                    continue
                _command([rscript, str(code_root / "application/scripts/pricefm/401_fit_pricefm_stage_r117_quantile_atom.R"), "--config", str(config)], code_root, campaign / f"logs/{variant}_quantiles/fold={fold}_{family}_tau={tau:.2f}.log", cpu)
                terminal = json.loads((output / "terminal.json").read_text())
                if not terminal.get("finite_core"):
                    raise RuntimeError(f"non-finite R117 quantile atom: variant={variant} fold={fold} {family} {tau}")
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(fold_worker, fold, cpus[fold - 1]) for fold in (1, 2, 3)]
        for future in as_completed(futures):
            future.result()
    rows = []
    for family in ("al", "exal"):
        for fold in (1, 2, 3):
            terminals = [
                json.loads((variant_root / f"full_folds/fold={fold}/quantiles/{family}/tau={tau:.2f}/terminal.json").read_text())
                for tau in QUANTILES
            ]
            rows.append({
                "variant": variant, "family": family, "fold": fold,
                "atoms_complete": len(terminals),
                "atoms_eligible": sum(bool(value.get("numerically_eligible")) for value in terminals),
                "family_fold_eligible": all(bool(value.get("numerically_eligible")) for value in terminals),
            })
    eligibility = pd.DataFrame(rows)
    eligible = [
        family for family in ("al", "exal")
        if eligibility[eligibility.family.eq(family)].family_fold_eligible.all()
    ]
    eligibility.to_csv(variant_root / "quantile_family_eligibility.csv", index=False)
    write_json(variant_root / "quantile_fit_progress.json", {
        "total": 42, "complete": 42, "failed": 0, "eligible_families": eligible,
        "test_opened": False,
    })
    if not eligible:
        raise RuntimeError(f"R117 {variant} has no complete numerically eligible quantile family")
    return eligible


def _forecast_closeout(
    args: argparse.Namespace, prep: Path, campaign: Path, code_root: Path,
    cpus: list[int], variant: str, families: list[str],
) -> dict[str, Any]:
    variant_root = _variant_root(campaign, variant)
    tasks = []
    python = sys.executable
    for fold in (1, 2, 3):
        for family in families:
            output = variant_root / f"forecasts/fold={fold}/family={family}/terminal.json"
            if not output.is_file():
                tasks.append((f"{variant}_forecast_f{fold}_{family}", [python, str(Path(__file__).resolve()), "--mode", "forecast", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code_root), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--variant", variant, "--fold", str(fold), "--family", family], campaign / f"logs/{variant}_forecasts/fold={fold}_{family}.log"))
    _run_queue(tasks, cpus, code_root, variant_root / "forecast_progress.json")
    frames = [pd.read_csv(variant_root / f"forecasts/fold={fold}/family={family}/metrics.csv") for fold in (1, 2, 3) for family in families]
    metrics = pd.concat(frames, ignore_index=True)
    eligible = metrics[(metrics.fold == 1) & metrics.operator.isin(["path_specific", "mean_feature"])]
    selection = eligible.sort_values(["AQL", "late_AQL", "family", "operator"], kind="mergesort").iloc[0]
    frozen = metrics[(metrics.family == selection.family) & (metrics.operator == selection.operator)].copy()
    closeout = variant_root / "closeout"
    closeout.mkdir(exist_ok=True)
    metrics.to_csv(closeout / "all_metrics.csv", index=False)
    frozen.to_csv(closeout / "frozen_family_operator_metrics.csv", index=False)
    summary = {
        "stage": "R117", "status": "completed_bg_variant_not_promoted", "variant": variant,
        "selected_family": str(selection.family), "selected_operator": str(selection.operator),
        "fold1_selection_AQL": float(selection.AQL), "three_fold_mean_AQL": float(frozen.AQL.mean()),
        "ridge_candidates": 240 if variant == "pure" else 0,
        "rhs_candidates": 50 if variant == "pure" else 3,
        "quantile_atoms": 42, "eligible_families": families,
        "posterior_paths": 500, "test_opened": False, "registry_mutated": False,
        "article_mutated": False, "joint_model_fitted": False, "mcmc_fitted": False,
        "next_gate": "read_only_comparison_against_R98_R111B_R116_and_cached_PriceFM",
    }
    write_json(closeout / "summary.json", summary)
    write_json(variant_root / "variant_terminal.json", summary)
    return summary


def _campaign_closeout(campaign: Path, summaries: list[dict[str, Any]]) -> dict[str, Any]:
    rows = []
    for summary in summaries:
        metrics = pd.read_csv(_variant_root(campaign, summary["variant"]) / "closeout/all_metrics.csv")
        rows.append(metrics)
    all_metrics = pd.concat(rows, ignore_index=True)
    eligible = all_metrics[
        all_metrics.fold.eq(1) & all_metrics.operator.isin(["path_specific", "mean_feature"])
    ]
    selected = eligible.sort_values(
        ["AQL", "late_AQL", "variant", "family", "operator"], kind="mergesort",
    ).iloc[0]
    frozen = all_metrics[
        all_metrics.variant.eq(selected.variant)
        & all_metrics.family.eq(selected.family)
        & all_metrics.operator.eq(selected.operator)
    ].copy()
    closeout = campaign / "closeout"
    closeout.mkdir(exist_ok=True)
    all_metrics.to_csv(closeout / "all_variant_metrics.csv", index=False)
    frozen.to_csv(closeout / "overall_frozen_choice_metrics.csv", index=False)
    result = {
        "stage": "R117", "status": "completed_bg_pilot_not_promoted",
        "selected_variant": str(selected.variant),
        "selected_family": str(selected.family),
        "selected_operator": str(selected.operator),
        "fold1_selection_AQL": float(selected.AQL),
        "three_fold_mean_AQL": float(frozen.AQL.mean()),
        "ridge_candidates": 240, "rhs_screen_fits": 450,
        "extended_tau0_fits": 9, "quantile_atoms": 84,
        "posterior_paths": 500, "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
        "joint_model_fitted": False, "mcmc_fitted": False,
        "next_gate": "read_only_comparison_against_R98_R111B_R116_and_cached_PriceFM",
    }
    write_json(closeout / "summary.json", result)
    write_json(campaign / "campaign_terminal.json", result)
    return result


def controller(args: argparse.Namespace) -> dict[str, Any]:
    _, data, prep, campaign = _paths(args)
    code_root = args.code_root.resolve()
    cpus = parse_cpus(args.cpu_list)
    audit = _preflight(args, prep, campaign, cpus)
    if args.preflight_only:
        return audit
    control = _read_control(prep)
    _prepare_processed(control, campaign, prep, code_root, cpus, folds="1")
    manifest = pd.read_csv(prep / "pricefm_stage_r117_candidate_manifest.csv")
    python = str(data / "venv/bin/python")
    tasks = []
    for row in manifest.itertuples(index=False):
        output = campaign / "ridge_runs" / str(row.candidate_id)
        if not _ridge_terminal(output):
            tasks.append((str(row.candidate_id), [python, str(Path(__file__).resolve()), "--mode", "ridge-cell", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code_root), "--prep-dir", str(prep), "--campaign-root", str(campaign), "--candidate-id", str(row.candidate_id)], campaign / f"logs/ridge/{row.candidate_id}.log"))
    _run_queue(tasks, cpus, code_root, campaign / "ridge_progress.json")
    top = _ridge_closeout(prep, campaign)
    _rhs_stage(args, prep, campaign, code_root, cpus, top)
    _fit_extended_tau0(args, prep, campaign, code_root, cpus)
    _prepare_processed(control, campaign, prep, code_root, cpus, folds="1,2,3")
    summaries = []
    for variant in ("pure", "extended"):
        _fit_full_normal(args, prep, campaign, code_root, cpus, variant)
        families = _fit_quantiles(prep, campaign, code_root, cpus, variant)
        summaries.append(_forecast_closeout(args, prep, campaign, code_root, cpus, variant, families))
    return _campaign_closeout(campaign, summaries)


def main() -> int:
    args = parser().parse_args()
    args.artifact_repo = args.artifact_repo.resolve()
    args.code_root = args.code_root.resolve()
    _, _, _, campaign = _paths(args)
    if args.mode == "ridge-cell":
        result = ridge_cell(args)
    elif args.mode == "rhs-score":
        result = rhs_score(args)
    elif args.mode == "full-design":
        result = full_design(args)
    elif args.mode == "forecast":
        result = forecast(args)
    else:
        campaign.mkdir(parents=True, exist_ok=True)
        lock = (campaign / "controller.lock").open("a+")
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("another R117 controller owns this campaign") from error
        try:
            result = controller(args)
        finally:
            lock.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
