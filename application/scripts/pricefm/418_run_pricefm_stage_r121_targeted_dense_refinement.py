#!/usr/bin/env python3
"""Run the resumable, gate-driven PriceFM Stage R121 campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any, Callable, Mapping

import joblib
import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r120_engine import (
    QUANTILES, explicit_arrays, feature_names, fit_scaled_ridge, input_names,
    internal_splits, load_normal_fit, load_quantile_fit, load_windows,
    normalize_spec, prediction_metrics, recursive_normal_score,
    recursive_quantile_forecast, standardize_from_training_origins,
    teacher_forced_design, teacher_forced_statistics, write_stats_packet,
)
from pricefm_r121_engine import (
    QUANTILE_ORDER, R120_TAG, SEEDS, TAG, bridge_decision, candidate_manifest,
    fold1_gate, manifest_row, normal_gate, subset_arrays, tau_center,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
THREAD_ENV = ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
              "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS")
_ATOMIC_LOCKS: dict[str, threading.Lock] = {}
_ATOMIC_LOCKS_GUARD = threading.Lock()


def _load_r120() -> Any:
    path = SCRIPT_DIR / "414_run_pricefm_stage_r120_explicit_lag_search.py"
    spec = importlib.util.spec_from_file_location("pricefm_r120_runner_for_r121", path)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


R120 = _load_r120()


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--mode", choices=("controller", "ridge-cell", "rhs-score", "bridge-family"), default="controller")
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--prep-dir", type=Path); value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, choices=(5, 10, 15), default=10)
    value.add_argument("--cpu-list", required=True)
    value.add_argument("--candidate-id"); value.add_argument("--fit-dir", type=Path)
    value.add_argument("--split", type=int); value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--maximum-cpu-percent", type=float, default=45.0)
    return value


def _paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    return artifact, data, prep, campaign


def _control(prep: Path) -> dict[str, Any]:
    return json.loads((prep / "launch_control.json").read_text())


def _parse_cpus(value: str) -> list[int]:
    result: list[int] = []
    for block in value.split(","):
        block = block.strip()
        if not block:
            continue
        if "-" in block:
            first, last = (int(item) for item in block.split("-", 1)); result.extend(range(first, last + 1))
        else:
            result.append(int(block))
    if not result or len(result) != len(set(result)):
        raise ValueError("R121 requires an explicit unique CPU list")
    return result


def _physical(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())


def _cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        rows = {}
        for line in Path("/proc/stat").read_text().splitlines():
            if not line.startswith("cpu") or line.startswith("cpu "):
                continue
            fields = line.split(); values = [int(item) for item in fields[1:]]
            rows[int(fields[0][3:])] = (sum(values), values[3] + values[4])
        return rows
    before = read(); time.sleep(interval); after = read()
    return {cpu: 100 * (1 - (after[cpu][1] - idle) / max(1, after[cpu][0] - total))
            for cpu, (total, idle) in before.items()}


def _command(command: list[str], cwd: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True); env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command] if cpu is not None else command
    with log.open("a") as handle:
        handle.write("$ " + " ".join(map(str, actual)) + "\n"); handle.flush()
        result = subprocess.run(actual, cwd=str(cwd), env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}")


def _atomic(output: Path, writer: Callable[[Path], None]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    key = str(output.resolve())
    with _ATOMIC_LOCKS_GUARD:
        lock = _ATOMIC_LOCKS.setdefault(key, threading.Lock())
    with lock:
        temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.tmp.", dir=output.parent))
        try:
            writer(temporary)
            if output.exists(): shutil.rmtree(output)
            temporary.rename(output)
        finally:
            if temporary.exists(): shutil.rmtree(temporary)


def _run_queue(tasks: list[tuple[str, list[str], Path]], cpus: list[int], cwd: Path, progress: Path,
               fail_fast: bool = False) -> dict[str, Any]:
    state = {"total": len(tasks), "complete": 0, "failed": 0, "failed_task_ids": [], "updated_at_epoch": time.time()}
    lock = threading.Lock(); buckets = [[] for _ in cpus]
    for index, task in enumerate(tasks): buckets[index % len(cpus)].append(task)
    def worker(cpu: int, bucket: list[tuple[str, list[str], Path]]) -> None:
        for task_id, command, log in bucket:
            ok = True
            try: _command(command, cwd, log, cpu)
            except Exception: ok = False
            with lock:
                state["complete" if ok else "failed"] += 1
                if not ok: state["failed_task_ids"].append(task_id)
                state["updated_at_epoch"] = time.time(); progress.parent.mkdir(parents=True, exist_ok=True); write_json(progress, state)
            if fail_fast and not ok: raise RuntimeError(f"R121 task failed: {task_id}")
    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures): future.result()
    if not tasks:
        progress.parent.mkdir(parents=True, exist_ok=True); write_json(progress, state)
    return state


def _preflight(args: argparse.Namespace, prep: Path, campaign: Path, cpus: list[int]) -> dict[str, Any]:
    summary = json.loads((prep / "summary.json").read_text()); sources = pd.read_csv(prep / "source_manifest.csv")
    changed = [str(row.path) for row in sources.itertuples(index=False)
               if not Path(row.path).is_file() or sha256_file(Path(row.path)) != str(row.sha256)]
    imported = prep / "screening_import_manifest.csv"
    changed_imports: list[str] = []
    if imported.is_file():
        imports = pd.read_csv(imported)
        changed_imports = [str(row.path) for row in imports.itertuples(index=False)
                           if not Path(row.path).is_file() or sha256_file(Path(row.path)) != str(row.sha256)]
    usage = _cpu_snapshot(); core_usage = {cpu: max(usage[sibling] for sibling in usage if _physical(sibling) == _physical(cpu)) for cpu in cpus}
    available_kib = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:"))
    free_gib = shutil.disk_usage(campaign.parent).free / 2**30
    checks = {
        "launch_authorized": summary.get("launch_authorized") is True,
        "sources_unchanged": not changed,
        "screening_imports_unchanged": not changed_imports,
        "worker_count": len(cpus) == int(args.workers) == int(summary["workers"]),
        "distinct_physical": len({_physical(cpu) for cpu in cpus}) == len(cpus),
        "cpu_idle": all(value <= args.maximum_cpu_percent for value in core_usage.values()),
        "memory": available_kib / 2**20 >= float(summary["minimum_memory_gib"]),
        "disk": free_gib >= float(summary["minimum_free_gib"]),
    }
    result = {"status": "preflight_passed" if all(checks.values()) else "preflight_blocked", "checks": checks,
              "changed_sources": changed, "changed_screening_imports": changed_imports,
              "cpus": cpus, "physical_core_max_percent": core_usage,
              "available_memory_gib": available_kib / 2**20, "free_disk_gib": free_gib, "test_opened": False}
    campaign.mkdir(parents=True, exist_ok=True); write_json(campaign / "launch_preflight.json", result)
    if not all(checks.values()): raise RuntimeError(f"R121 preflight blocked: {checks}")
    return result


def _candidate(prep: Path, candidate_id: str, campaign: Path | None = None) -> tuple[pd.Series, dict[str, Any]]:
    frames = [pd.read_csv(prep / "candidate_manifest.csv")]
    for name in ("bridge_panel.csv",):
        frames.append(pd.read_csv(prep / name))
    if campaign is not None and (campaign / "ridge/seed_manifest.csv").is_file():
        frames.append(pd.read_csv(campaign / "ridge/seed_manifest.csv"))
    found = pd.concat(frames, ignore_index=True).drop_duplicates("candidate_id")
    row = found[found.candidate_id.astype(str).eq(str(candidate_id))]
    if len(row) != 1: raise ValueError(f"R121 candidate not uniquely identified: {candidate_id}")
    value = row.iloc[0]; return value, normalize_spec(json.loads(str(value.spec_json)))


def _ridge_root(campaign: Path, stage: str, candidate_id: str) -> Path:
    return campaign / stage / "ridge_runs" / candidate_id


def _ridge_valid(path: Path) -> bool:
    try: value = json.loads((path / "terminal.json").read_text())
    except (OSError, json.JSONDecodeError): return False
    return value.get("status") == "completed_r121_ridge_cell" and value.get("test_opened") is False


def ridge_cell(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); row, spec = _candidate(prep, str(args.candidate_id), campaign)
    stage = "primary" if int(spec["seed"]) == SEEDS[0] else "seed"
    output = _ridge_root(campaign, stage, str(row.candidate_id))
    if _ridge_valid(output): return json.loads((output / "terminal.json").read_text())
    control = _control(prep); arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    stats, preprocessing, audits, metrics = {}, {}, {}, []
    for item in internal_splits(len(arrays.response)):
        split = int(item["split"]); scaled, scaler = standardize_from_training_origins(arrays, item["train"])
        split_stats, audit = teacher_forced_statistics(scaled, spec, {"train": item["train"]})
        stats[f"train_{split}"] = split_stats["train"]; preprocessing[str(split)] = scaler; audits[str(split)] = audit
        score = recursive_normal_score(scaled, spec, fit_scaled_ridge(split_stats["train"]), item["validation"], maximum_origins=48)
        for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"): score[metric] *= float(scaler["price_scale"])
        metrics.append({"split": split, **score})
    names = input_names(spec, arrays.exog_names); features = feature_names(spec, names)
    def write(temp: Path) -> None:
        payload = {}
        for split in (1, 2, 3):
            value = stats[f"train_{split}"]
            for name in ("XtX", "Xty"): payload[f"split{split}_{name}"] = value[name]
            payload[f"split{split}_yty"] = np.asarray([value["yty"]]); payload[f"split{split}_n"] = np.asarray([value["n"]], dtype=np.int64)
        np.savez_compressed(temp / "training_statistics.npz", **payload)
        pd.DataFrame(metrics).to_csv(temp / "validation_metrics.csv", index=False)
        write_json(temp / "contract.json", {"candidate_id": row.candidate_id, "spec": spec, "feature_names": features,
            "input_names": names, "source_manifest": list(arrays.source_manifest), "split_preprocessing": preprocessing,
            "reservoir_audit": audits, "test_opened": False})
        write_json(temp / "terminal.json", {"status": "completed_r121_ridge_cell", "stage": stage,
            "candidate_id": row.candidate_id, "p": len(features), "input_dimension": len(names),
            "mean_AQL": float(np.mean([item["AQL"] for item in metrics])),
            "mean_late_AQL": float(np.mean([item["late_AQL"] for item in metrics])), "test_opened": False})
    _atomic(output, write); return json.loads((output / "terminal.json").read_text())


def _stats_from_ridge(path: Path, split: int) -> dict[str, Any]:
    with np.load(path / "training_statistics.npz") as packet:
        xtx = np.asarray(packet[f"split{split}_XtX"])
        return {"n": int(packet[f"split{split}_n"][0]), "p": len(xtx), "XtX": xtx,
                "Xty": np.asarray(packet[f"split{split}_Xty"]), "yty": float(packet[f"split{split}_yty"][0])}


def _ranking(campaign: Path, manifest: pd.DataFrame, stage: str) -> pd.DataFrame:
    rows = []
    for row in manifest.itertuples(index=False):
        root = _ridge_root(campaign, stage, str(row.candidate_id))
        if not _ridge_valid(root): continue
        scores = pd.read_csv(root / "validation_metrics.csv")
        rows.append({**row._asdict(), "mean_AQL": float(scores.AQL.mean()), "mean_late_AQL": float(scores.late_AQL.mean()),
                     "worst_AQL": float(scores.AQL.max()), "mean_coverage": float(scores.interval_80_coverage.mean())})
    result = pd.DataFrame(rows)
    if result.empty: return result
    return result.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "readout_dimension", "candidate_id"], kind="mergesort").reset_index(drop=True)


def _ridge_tasks(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, manifest: pd.DataFrame, stage: str) -> list[tuple[str, list[str], Path]]:
    tasks = []
    for row in manifest.sort_values(["readout_dimension", "input_dimension", "candidate_id"], ascending=[False, False, True], kind="mergesort").itertuples(index=False):
        if not _ridge_valid(_ridge_root(campaign, stage, str(row.candidate_id))):
            tasks.append((str(row.candidate_id), [sys.executable, str(Path(__file__).resolve()), "--mode", "ridge-cell",
                "--artifact-repo", str(args.artifact_repo), "--code-root", str(code), "--prep-dir", str(prep),
                "--campaign-root", str(campaign), "--workers", str(args.workers), "--cpu-list", args.cpu_list,
                "--candidate-id", str(row.candidate_id)], campaign / f"logs/{stage}_ridge/{row.candidate_id}.log"))
    return tasks


def _write_design(path: Path, design: np.ndarray, response: np.ndarray, metadata: Mapping[str, Any]) -> None:
    def write(temp: Path) -> None:
        np.asarray(design, dtype="<f8").tofile(temp / "X.bin"); np.asarray(response, dtype="<f8").tofile(temp / "y.bin")
        write_json(temp / "design.json", {"n": len(response), "p": design.shape[1], **dict(metadata), "test_opened": False})
        write_json(temp / "terminal.json", {"status": "completed_r121_quantile_design", "stage": "R121",
            "X_sha256": sha256_file(temp / "X.bin"), "y_sha256": sha256_file(temp / "y.bin"), "test_opened": False})
    if not (path / "terminal.json").is_file(): _atomic(path, write)


def _normal_valid(path: Path) -> bool:
    try: value = json.loads((path / "terminal.json").read_text())
    except (OSError, json.JSONDecodeError): return False
    return value.get("status") == "completed_recursive_normal_fit" and value.get("converged") is True and value.get("test_opened") is False


def _normal_contract(fit_id: str, stats: Path, output: Path, tau0: float, control: Mapping[str, Any], code: Path) -> dict[str, Any]:
    return {"fit_id": fit_id, "stats_dir": str(stats), "output_dir": str(output), "prior_type": "rhs_ns",
        "tau0": float(tau0), "package_path": control["normal_runtime"],
        "helper_path": str(code / "application/R/pricefm_recursive_normal_fit.R"), "max_iter": 500, "min_iter": 100,
        "tol": 1e-5, "convergence_mode": "predictive_fixed_point", "stability_window": 10, "predictive_tol": 1e-7,
        "relative_beta_tol": 1e-6, "sigma_relative_tol": 1e-8, "prior_rms_log_precision_tol": 1e-6,
        "posterior_target_sha256": sha256_file(stats / "terminal.json") + f":tau0={tau0:.17g}",
        "selection_split": "train_validation_only", "test_access_authorized": False}


def _quantile_valid(path: Path) -> bool:
    try: value = json.loads((path / "terminal.json").read_text())
    except (OSError, json.JSONDecodeError): return False
    return value.get("status") == "completed_r121_quantile_atom" and value.get("numerically_eligible") is True and value.get("test_opened") is False


def _quantile_contract(prep: Path, design: Path, output: Path, parent: Path, parent_type: str,
                       candidate_id: str, tau: float, tau0: float, fold: int, split: int, stage: str) -> Path:
    control = _control(prep); sources = pd.read_csv(prep / "source_manifest.csv")
    adapter = Path(sources[sources.path.str.endswith("pricefm_stage_r67_cran111_adapter.R")].iloc[0].path)
    manifest = Path(control["cran_manifest"])
    value = {"stage": stage, "tag": str(control.get("tag", TAG)),
        "atom_id": f"{candidate_id}_f{fold}_s{split}_al_{tau:.2f}",
        "candidate_id": candidate_id, "readout": "pure_all_layers", "fold": fold, "split": split,
        "family": "al", "tau": tau, "tau0": tau0, "design_dir": str(design), "output_dir": str(output),
        "parent_dir": str(parent), "parent_type": parent_type, "parent_label": parent.name,
        "cran_library": control["cran_library"], "cran_manifest": str(manifest), "cran_manifest_sha256": sha256_file(manifest),
        "cran_adapter": str(adapter), "cran_adapter_sha256": sha256_file(adapter),
        "design_terminal_sha256": sha256_file(design / "terminal.json"), "parent_terminal_sha256": sha256_file(parent / "terminal.json"),
        "training_split": "outer_fold_training_only" if stage == "R121_outer" else "fold1_internal_training_only",
        "max_iter": 500, "tol": 1e-5, "n_samp_xi": 20, "n_samp": 20,
        "seed": int(SEEDS[0] + fold * 1000 + split * 100 + round(tau * 100)),
        "test_access_authorized": False, "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "joint_model_authorized": False, "mcmc_authorized": False, "exal_authorized": False,
        "posterior_target_sha256": sha256_file(design / "terminal.json") + f":tau={tau:.2f}:tau0={tau0:.17g}"}
    path = output.parent.parent / "contracts" / f"tau={tau:.2f}.json"; path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and json.loads(path.read_text()) != value: raise RuntimeError(f"R121 immutable quantile contract changed: {path}")
    write_json(path, value); return path


def _fit_family(prep: Path, code: Path, root: Path, candidate_id: str, design: Path, normal: Path,
                tau0: float, fold: int, split: int, stage: str, cpu: int | None = None) -> tuple[bool, int]:
    control = _control(prep); invalid = 0
    for tau in QUANTILE_ORDER:
        output = root / f"quantiles/al/tau={tau:.2f}"
        parent_tau = R120._parent_tau(tau)
        parent = normal if parent_tau is None else root / f"quantiles/al/tau={parent_tau:.2f}"
        parent_type = "normal_rhs" if parent_tau is None else "quantile"
        if not _quantile_valid(output):
            contract = _quantile_contract(prep, design, output, parent, parent_type, candidate_id, tau, tau0, fold, split, stage)
            try: _command([control["rscript"], str(code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                           "--config", str(contract)], code, root / f"logs/al_tau={tau:.2f}.log", cpu)
            except Exception: invalid += 1; break
        if not _quantile_valid(output): invalid += 1; break
    invalid += sum(not _quantile_valid(root / f"quantiles/al/tau={tau:.2f}") for tau in QUANTILES)
    return invalid == 0, invalid


def _score_family(arrays: Any, spec: Mapping[str, Any], normal_path: Path, family_root: Path,
                  scale: float, mean: float, seed: int) -> dict[str, float]:
    normal = load_normal_fit(normal_path)
    qfits = {tau: load_quantile_fit(family_root / f"quantiles/al/tau={tau:.2f}") for tau in QUANTILES}
    values = recursive_quantile_forecast(arrays, spec, normal, qfits, 500, seed)
    truth = values["truth"] * scale + mean; prediction = values["mean_feature"] * scale + mean
    return prediction_metrics(truth, prediction)


def bridge_family(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); control = _control(prep); row, spec = _candidate(prep, str(args.candidate_id), campaign)
    root = campaign / "bridge" / str(row.candidate_id); metric = root / "metrics.json"
    if metric.is_file(): return json.loads(metric.read_text())
    arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    item = internal_splits(len(arrays.response))[-1]; scaled, scaler = standardize_from_training_origins(arrays, item["train"])
    design_array, response, audit = teacher_forced_design(subset_arrays(scaled, item["train"]), spec)
    names = input_names(spec, arrays.exog_names); design = root / "design"
    _write_design(design, design_array, response, {"candidate_id": row.candidate_id, "fold": 1, "split": 3,
        "feature_names": feature_names(spec, names), "input_names": names, "depth": spec["depth"],
        "reservoir_audit": audit, "selection_boundary": "fold1_internal_training_only"})
    r120 = Path(control["r120_campaign"]); multiplier = float(row.multiplier)
    r120_cells = pd.read_csv(r120 / "stage_d/closeout/cell_metrics.csv")
    matched = r120_cells[
        r120_cells.candidate_id.astype(str).eq(str(row.candidate_id))
        & r120_cells.split.astype(int).eq(3)
        & np.isclose(r120_cells.tau0.astype(float), float(row.tau0), rtol=1e-10, atol=0)
    ]
    if len(matched) != 1:
        raise RuntimeError(f"R121 bridge parent is not unique for {row.candidate_id}")
    normal = Path(matched.iloc[0].output_dir)
    eligible, invalid = _fit_family(prep, args.code_root.resolve(), root, str(row.candidate_id), design, normal,
                                    float(row.tau0), 1, 3, "R121_bridge")
    score = {key: float("nan") for key in ("AQL", "late_AQL", "interval_80_coverage", "interval_80_width", "crossing_rate")}
    if eligible:
        score = _score_family(subset_arrays(scaled, item["validation"]), spec, normal, root,
                              float(scaler["price_scale"]), float(scaler["price_mean"]), SEEDS[0])
    result = {"status": "completed_r121_bridge_family", "candidate_id": row.candidate_id,
        "normal_AQL": float(matched.iloc[0].AQL), "al_AQL": float(score["AQL"]), "al_late_AQL": float(score["late_AQL"]),
        "family_eligible": eligible, "invalid_quantiles": int(invalid), "tau0": float(row.tau0),
        "validation_origin_count": len(item["validation"]), "test_opened": False}
    root.mkdir(parents=True, exist_ok=True); write_json(metric, result); return result


def _bridge(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int]) -> dict[str, Any]:
    panel = pd.read_csv(prep / "bridge_panel.csv"); tasks = []
    for row in panel.itertuples(index=False):
        metric = campaign / f"bridge/{row.candidate_id}/metrics.json"
        if not metric.is_file(): tasks.append((str(row.candidate_id), [sys.executable, str(Path(__file__).resolve()),
            "--mode", "bridge-family", "--artifact-repo", str(args.artifact_repo), "--code-root", str(code),
            "--prep-dir", str(prep), "--campaign-root", str(campaign), "--workers", str(args.workers),
            "--cpu-list", args.cpu_list, "--candidate-id", str(row.candidate_id)],
            campaign / f"logs/bridge/{row.candidate_id}.log"))
    _run_queue(tasks, cpus, code, campaign / "bridge/progress.json")
    records = [json.loads((campaign / f"bridge/{row.candidate_id}/metrics.json").read_text())
               for row in panel.itertuples(index=False) if (campaign / f"bridge/{row.candidate_id}/metrics.json").is_file()]
    metrics = pd.DataFrame(records); metrics.to_csv(campaign / "bridge/metrics.csv", index=False)
    decision = bridge_decision(metrics) if len(metrics) == 6 else {"status": "NORMAL_PROXY_NOT_VALIDATED", "passed": False,
        "reason": "incomplete_bridge", "completed": len(metrics), "test_opened": False}
    write_json(campaign / "bridge/terminal.json", decision); return decision


def rhs_score(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); row, spec = _candidate(prep, str(args.candidate_id), campaign); split = int(args.split)
    output = args.fit_dir / "validation_score.json"
    if output.is_file(): return json.loads(output.read_text())
    arrays = explicit_arrays(load_windows(Path(_control(prep)["runtime_processed"]), 1, "train", spec), spec)
    item = internal_splits(len(arrays.response))[split - 1]; scaled, scaler = standardize_from_training_origins(arrays, item["train"])
    score = recursive_normal_score(scaled, spec, load_normal_fit(args.fit_dir), item["validation"], 64)
    for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"): score[metric] *= float(scaler["price_scale"])
    result = {"status": "completed_r121_rhs_validation_score", "candidate_id": row.candidate_id,
              "split": split, **score, "test_opened": False}; write_json(output, result); return result


def _rhs_cells(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int],
               candidates: pd.DataFrame, levels: Mapping[str, list[float]], label: str) -> pd.DataFrame:
    control = _control(prep); records, tasks = [], []
    for row in candidates.itertuples(index=False):
        ridge = _ridge_root(campaign, "primary", str(row.candidate_id))
        for split in (1, 2, 3):
            stats = _stats_from_ridge(ridge, split); stats_dir = campaign / f"rhs/{label}/stats/{row.candidate_id}/split={split}"
            if not (stats_dir / "terminal.json").is_file(): write_stats_packet(stats_dir, stats, {"candidate_id": row.candidate_id, "split": split})
            for tau0 in levels[str(row.candidate_id)]:
                fit_id = f"{row.candidate_id}_s{split}_t{tau0:.8e}"; output = campaign / f"rhs/{label}/fits/{fit_id}"
                contract = _normal_contract(fit_id, stats_dir, output, tau0, control, code)
                contract_path = campaign / f"rhs/{label}/contracts/{fit_id}.json"; contract_path.parent.mkdir(parents=True, exist_ok=True); write_json(contract_path, contract)
                if not _normal_valid(output): tasks.append((fit_id, [control["rscript"], str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"),
                    "--contract", str(contract_path)], campaign / f"logs/rhs_{label}_fit/{fit_id}.log"))
                records.append({"candidate_id": row.candidate_id, "split": split, "tau0": tau0, "fit_id": fit_id, "output_dir": str(output)})
    _run_queue(tasks, cpus, code, campaign / f"rhs/{label}/fit_progress.json")
    score_tasks = []
    for record in records:
        output = Path(record["output_dir"])
        if _normal_valid(output) and not (output / "validation_score.json").is_file():
            score_tasks.append((record["fit_id"], [sys.executable, str(Path(__file__).resolve()), "--mode", "rhs-score",
                "--artifact-repo", str(args.artifact_repo), "--code-root", str(code), "--prep-dir", str(prep),
                "--campaign-root", str(campaign), "--workers", str(args.workers), "--cpu-list", args.cpu_list,
                "--candidate-id", record["candidate_id"], "--split", str(record["split"]), "--fit-dir", str(output)],
                campaign / f"logs/rhs_{label}_score/{record['fit_id']}.log"))
    _run_queue(score_tasks, cpus, code, campaign / f"rhs/{label}/score_progress.json")
    rows = []
    for record in records:
        path = Path(record["output_dir"]) / "validation_score.json"
        if _normal_valid(Path(record["output_dir"])) and path.is_file(): rows.append({**record, **json.loads(path.read_text())})
    frame = pd.DataFrame(rows); root = campaign / f"rhs/{label}"; root.mkdir(parents=True, exist_ok=True); frame.to_csv(root / "cell_metrics.csv", index=False)
    return frame


def _complete_rhs(cells: pd.DataFrame) -> pd.DataFrame:
    complete = cells.groupby(["candidate_id", "tau0"], as_index=False).filter(lambda group: set(group.split) == {1, 2, 3} and len(group) == 3)
    if complete.empty: return complete
    return complete.groupby(["candidate_id", "tau0"], as_index=False).agg(
        mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"), worst_AQL=("AQL", "max"), mean_coverage=("interval_80_coverage", "mean"))


def _seed_manifest(primary: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for base in primary.head(200).itertuples(index=False):
        spec = json.loads(str(base.spec_json))
        for seed in SEEDS[1:]:
            spec_seed = normalize_spec({**spec, "seed": seed}); row = manifest_row(spec_seed, "top200_seed_robustness", str(base.candidate_id))
            row["base_candidate_id"] = str(base.candidate_id); rows.append(row)
    return pd.DataFrame(rows)


def _seed_closeout(primary: pd.DataFrame, seeds: pd.DataFrame) -> pd.DataFrame:
    seed_rank = seeds.copy()
    records = []
    for row in primary.itertuples(index=False):
        values = [float(row.mean_AQL)]; late = [float(row.mean_late_AQL)]; worst = [float(row.worst_AQL)]
        matched = seed_rank[seed_rank.base_candidate_id.astype(str).eq(str(row.candidate_id))]
        if len(matched):
            values += matched.mean_AQL.astype(float).tolist(); late += matched.mean_late_AQL.astype(float).tolist(); worst += matched.worst_AQL.astype(float).tolist()
        records.append({**row._asdict(), "seed_count": len(values), "robust_mean_AQL": float(np.mean(values)),
            "seed_sd_AQL": float(np.std(values)), "robust_late_AQL": float(np.mean(late)), "robust_worst_AQL": float(np.max(worst))})
    return pd.DataFrame(records).sort_values(["robust_mean_AQL", "robust_late_AQL", "robust_worst_AQL", "seed_sd_AQL", "candidate_id"], kind="mergesort").reset_index(drop=True)


def _normal_stage(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int], top50: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    centers = {str(row.candidate_id): [tau_center(int(row.readout_dimension),
        _stats_from_ridge(_ridge_root(campaign, "primary", str(row.candidate_id)), 3)["n"])] for row in top50.itertuples(index=False)}
    center_cells = _rhs_cells(args, prep, campaign, code, cpus, top50, centers, "center")
    center = _complete_rhs(center_cells).sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"], kind="mergesort")
    if len(center) < 20: raise RuntimeError(f"R121 has too few complete center RHS groups: {len(center)}")
    top5_ids = center.head(5).candidate_id.astype(str).tolist(); top5 = top50[top50.candidate_id.astype(str).isin(top5_ids)]
    pilot_levels = {cid: [centers[cid][0] * factor for factor in (0.01, 0.1, 10.0, 100.0)] for cid in top5_ids}
    pilot_cells = _rhs_cells(args, prep, campaign, code, cpus, top5, pilot_levels, "pilot")
    pilot = _complete_rhs(pilot_cells)
    active = False; diagnostics = []
    for cid in top5_ids:
        values = pd.concat([center[center.candidate_id.astype(str).eq(cid)], pilot[pilot.candidate_id.astype(str).eq(cid)]])
        central = float(center[center.candidate_id.astype(str).eq(cid)].iloc[0].mean_AQL)
        aql_range = float(values.mean_AQL.max() - values.mean_AQL.min()) if len(values) else 0.0
        coverage_range = float(values.mean_coverage.max() - values.mean_coverage.min()) if len(values) else 0.0
        center_tau = centers[cid][0]
        center_path = campaign / f"rhs/center/fits/{cid}_s3_t{center_tau:.8e}/beta_mean.bin"
        center_beta = np.fromfile(center_path, dtype="<f8")
        relative_changes = []
        for tau0 in pilot_levels[cid]:
            beta_path = campaign / f"rhs/pilot/fits/{cid}_s3_t{tau0:.8e}/beta_mean.bin"
            if beta_path.is_file():
                beta = np.fromfile(beta_path, dtype="<f8")
                if beta.shape == center_beta.shape:
                    relative_changes.append(float(np.linalg.norm(beta - center_beta) / max(np.linalg.norm(center_beta), 1e-12)))
        max_beta_change = max(relative_changes, default=0.0)
        activated = aql_range > max(1e-4, .001 * central) or coverage_range > .005 or max_beta_change > 1e-3
        active = active or activated; diagnostics.append({"candidate_id": cid, "aql_range": aql_range,
            "coverage_range": coverage_range, "max_beta_relative_l2": max_beta_change, "activated": activated})
    write_json(campaign / "rhs/tau_activation.json", {"status": "completed_r121_tau_activation", "active": active,
        "diagnostics": diagnostics, "coefficient_threshold": 1e-3, "test_opened": False})
    all_cells = [center_cells, pilot_cells]
    if active:
        top20_ids = center.head(20).candidate_id.astype(str).tolist(); top20 = top50[top50.candidate_id.astype(str).isin(top20_ids)]
        expansion = {cid: [centers[cid][0] * factor for factor in (0.1, 10.0)] for cid in top20_ids}
        all_cells.append(_rhs_cells(args, prep, campaign, code, cpus, top20, expansion, "expansion"))
    pooled = _complete_rhs(pd.concat(all_cells, ignore_index=True).drop_duplicates(["candidate_id", "split", "tau0"], keep="first"))
    pooled = pooled.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"], kind="mergesort").reset_index(drop=True)
    r120 = pd.read_csv(Path(_control(prep)["r120_campaign"]) / "stage_d/closeout/ranking.csv").iloc[0]
    control_metrics = {"mean_AQL": float(r120.mean_AQL), "mean_late_AQL": float(r120.mean_late_AQL), "worst_AQL": float(r120.worst_AQL)}
    gates = []
    for row in pooled.itertuples(index=False): gates.append({"candidate_id": row.candidate_id, "tau0": row.tau0,
        **normal_gate(row._asdict(), control_metrics), **row._asdict()})
    gate_frame = pd.DataFrame(gates)
    passed = select_unique_normal_shortlist(gate_frame, center_cells, retain_center=not active, maximum=3)
    root = campaign / "rhs/closeout"; root.mkdir(parents=True, exist_ok=True); pooled.to_csv(root / "ranking.csv", index=False); gate_frame.to_csv(root / "normal_gates.csv", index=False)
    if passed.empty: return pooled, passed
    return pooled, passed


def select_unique_normal_shortlist(gates: pd.DataFrame, center_cells: pd.DataFrame,
                                   retain_center: bool, maximum: int = 3) -> pd.DataFrame:
    """Select distinct candidates and, when tau is inactive, their center tau."""
    passed = gates[gates.passed.astype(bool)].copy()
    selected: list[pd.Series] = []
    for candidate_id in passed.candidate_id.astype(str).drop_duplicates():
        rows = passed[passed.candidate_id.astype(str).eq(candidate_id)]
        if retain_center:
            center = center_cells[center_cells.candidate_id.astype(str).eq(candidate_id)]
            levels = np.unique(center.tau0.astype(float))
            if len(levels) != 1:
                continue
            rows = rows[np.isclose(rows.tau0.astype(float), float(levels[0]), rtol=1e-10, atol=0)]
        if rows.empty:
            continue
        selected.append(rows.iloc[0])
        if len(selected) == maximum:
            break
    result = pd.DataFrame([row.to_dict() for row in selected])
    if not result.empty and result.candidate_id.astype(str).duplicated().any():
        raise RuntimeError("R121 shortlist must contain unique candidates")
    return result


def _prepare_internal(prep: Path, campaign: Path, candidate_id: str, tau0: float, split: int,
                      code: Path, normal_campaign: Path | None = None) -> tuple[Path, Path, Any, dict[str, Any], dict[str, Any]]:
    row, spec = _candidate(prep, candidate_id, campaign); control = _control(prep)
    arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    item = internal_splits(len(arrays.response))[split - 1]; scaled, scaler = standardize_from_training_origins(arrays, item["train"])
    root = campaign / f"al_internal/{candidate_id}/split={split}"; design = root / "design"
    values, response, audit = teacher_forced_design(subset_arrays(scaled, item["train"]), spec)
    names = input_names(spec, arrays.exog_names); _write_design(design, values, response, {"candidate_id": candidate_id,
        "fold": 1, "split": split, "feature_names": feature_names(spec, names), "input_names": names,
        "depth": spec["depth"], "reservoir_audit": audit, "selection_boundary": "fold1_internal_training_only"})
    normal_root = normal_campaign or campaign
    normal_candidates = list((normal_root / "rhs").glob(f"*/fits/{candidate_id}_s{split}_t{tau0:.8e}"))
    if len(normal_candidates) != 1 or not _normal_valid(normal_candidates[0]): raise RuntimeError("R121 selected Normal parent missing")
    return root, normal_candidates[0], subset_arrays(scaled, item["validation"]), scaler, spec


def _internal_al(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpus: list[int],
                 shortlist: pd.DataFrame, normal_campaign: Path | None = None) -> pd.DataFrame:
    if shortlist.empty or shortlist.candidate_id.astype(str).duplicated().any():
        raise RuntimeError("R121 internal AL requires a nonempty unique-candidate shortlist")
    tasks = []
    def one(candidate_id: str, tau0: float, split: int, cpu: int) -> dict[str, Any]:
        root, normal, validation, scaler, spec = _prepare_internal(
            prep, campaign, candidate_id, tau0, split, code, normal_campaign=normal_campaign)
        eligible, invalid = _fit_family(prep, code, root, candidate_id, root / "design", normal, tau0, 1, split, "R121_internal_selection", cpu)
        score = _score_family(validation, spec, normal, root, float(scaler["price_scale"]), float(scaler["price_mean"]), SEEDS[0] + split) if eligible else {}
        result = {"candidate_id": candidate_id, "tau0": tau0, "split": split, "eligible": eligible,
                  "invalid_quantiles": invalid, **score}; write_json(root / "metrics.json", result); return result
    with ThreadPoolExecutor(max_workers=min(len(cpus), 9)) as pool:
        futures = []
        for position, row in enumerate(shortlist.itertuples(index=False)):
            for split in (1, 2, 3):
                futures.append(pool.submit(one, str(row.candidate_id), float(row.tau0), split, cpus[(position * 3 + split - 1) % len(cpus)]))
        records = [future.result() for future in as_completed(futures)]
    cells = pd.DataFrame(records); complete = cells.groupby(["candidate_id", "tau0"], as_index=False).filter(lambda group: len(group) == 3 and group.eligible.all())
    if complete.empty: return complete
    ranking = complete.groupby(["candidate_id", "tau0"], as_index=False).agg(mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"),
        worst_AQL=("AQL", "max"), mean_coverage=("interval_80_coverage", "mean"), mean_width=("interval_80_width", "mean"),
        mean_crossing=("crossing_rate", "mean"))
    ranking = ranking.sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "mean_crossing", "candidate_id"], kind="mergesort")
    root = campaign / "al_internal/closeout"; root.mkdir(parents=True, exist_ok=True); cells.to_csv(root / "cell_metrics.csv", index=False); ranking.to_csv(root / "ranking.csv", index=False)
    return ranking


def _outer_fold(args: argparse.Namespace, prep: Path, campaign: Path, code: Path, cpu: int,
                candidate_id: str, tau0: float, fold: int) -> pd.DataFrame:
    root = campaign / f"outer/fold={fold}"; metric = root / "metrics.csv"
    if metric.is_file(): return pd.read_csv(metric)
    _, spec = _candidate(prep, candidate_id, campaign); control = _control(prep)
    arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), fold, "train", spec), spec)
    stats, audit = teacher_forced_statistics(arrays, spec, {"full": np.arange(len(arrays.response))})
    design_values, response, design_audit = teacher_forced_design(arrays, spec); names = input_names(spec, arrays.exog_names)
    write_stats_packet(root / "normal_stats", stats["full"], {"candidate_id": candidate_id, "fold": fold})
    _write_design(root / "design", design_values, response, {"candidate_id": candidate_id, "fold": fold, "split": 0,
        "feature_names": feature_names(spec, names), "input_names": names, "depth": spec["depth"],
        "reservoir_audit": audit, "design_reservoir_audit": design_audit, "selection_boundary": "outer_fold_training_only"})
    normal = root / "normal_rhs"; contract = _normal_contract(f"r121_outer_f{fold}", root / "normal_stats", normal, tau0, control, code)
    contract_path = root / "normal_contract.json"; write_json(contract_path, contract)
    if not _normal_valid(normal): _command([control["rscript"], str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"), "--contract", str(contract_path)], code, root / "logs/normal.log", cpu)
    eligible, invalid = _fit_family(prep, code, root, candidate_id, root / "design", normal, tau0, fold, 0, "R121_outer", cpu)
    if not eligible: raise RuntimeError(f"R121 outer Fold {fold} AL family ineligible ({invalid})")
    validation = explicit_arrays(load_windows(Path(control["runtime_processed"]), fold, "val", spec), spec)
    qfits = {tau: load_quantile_fit(root / f"quantiles/al/tau={tau:.2f}") for tau in QUANTILES}
    values = recursive_quantile_forecast(validation, spec, load_normal_fit(normal), qfits, 500, SEEDS[0] + fold * 100)
    scaler = joblib.load(Path(control["runtime_processed"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib")["BG"]["y_scaler"]
    def inverse(value: np.ndarray) -> np.ndarray: return scaler.inverse_transform(np.asarray(value).reshape(-1, 1)).reshape(np.asarray(value).shape)
    rows = []
    for operator in ("mean_feature", "path_specific", "normal_driver"):
        score = prediction_metrics(inverse(values["truth"]), inverse(values[operator])); rows.append({"fold": fold, "operator": operator, **score})
    root.mkdir(parents=True, exist_ok=True); pd.DataFrame(rows).to_csv(metric, index=False)
    np.savez_compressed(root / "predictions.npz", anchors=validation.anchors, quantiles=np.asarray(QUANTILES), **values)
    write_json(root / "terminal.json", {"status": "completed_r121_outer_fold", "fold": fold, "candidate_id": candidate_id,
        "tau0": tau0, "family": "al", "operator": "mean_feature", "test_opened": False})
    return pd.DataFrame(rows)


def controller(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); code = args.code_root.resolve(); cpus = _parse_cpus(args.cpu_list)
    audit = _preflight(args, prep, campaign, cpus)
    if args.preflight_only: return audit
    control = _control(prep)
    screening_campaign = Path(control.get("screening_campaign", campaign)).resolve()
    if screening_campaign != campaign:
        bridge = json.loads((screening_campaign / "bridge/terminal.json").read_text())
        tau = json.loads((screening_campaign / "rhs/tau_activation.json").read_text())
        gates = pd.read_csv(screening_campaign / "rhs/closeout/normal_gates.csv")
        centers = pd.read_csv(screening_campaign / "rhs/center/cell_metrics.csv")
        shortlist = select_unique_normal_shortlist(gates, centers, retain_center=not bool(tau["active"]), maximum=3)
        imported = campaign / "imported_screening"
        imported.mkdir(parents=True, exist_ok=True)
        shortlist.to_csv(imported / "unique_normal_shortlist.csv", index=False)
        write_json(imported / "terminal.json", {"status": "completed_r121_screening_import",
            "source_campaign": str(screening_campaign), "candidate_count": len(shortlist),
            "test_opened": False})
    else:
        bridge = _bridge(args, prep, campaign, code, cpus)
        if not bridge.get("passed"):
            result = {"stage": "R121", "status": "NORMAL_PROXY_NOT_VALIDATED", "bridge": bridge,
                      "test_opened": False, "registry_mutated": False, "article_mutated": False}
            write_json(campaign / "campaign_terminal.json", result); return result

        manifest = pd.read_csv(prep / "candidate_manifest.csv")
        _run_queue(_ridge_tasks(args, prep, campaign, code, manifest, "primary"), cpus, code, campaign / "ridge/primary_progress.json")
        primary = _ranking(campaign, manifest, "primary")
        if len(primary) < 50: raise RuntimeError(f"R121 has fewer than 50 complete primary Ridge cells: {len(primary)}")
        seed_manifest = _seed_manifest(primary); seed_root = campaign / "ridge"; seed_root.mkdir(parents=True, exist_ok=True); seed_manifest.to_csv(seed_root / "seed_manifest.csv", index=False)
        _run_queue(_ridge_tasks(args, prep, campaign, code, seed_manifest, "seed"), cpus, code, campaign / "ridge/seed_progress.json")
        seed_rank = _ranking(campaign, seed_manifest, "seed")
        robust = _seed_closeout(primary, seed_rank); primary.to_csv(seed_root / "primary_ranking.csv", index=False); seed_rank.to_csv(seed_root / "seed_ranking.csv", index=False); robust.to_csv(seed_root / "robust_ranking.csv", index=False)
        top50 = robust.head(50).copy(); top50.to_csv(seed_root / "top50.csv", index=False)
        _, shortlist = _normal_stage(args, prep, campaign, code, cpus, top50)
    if shortlist.empty:
        result = {"stage": "R121", "status": "NO_NORMAL_REFINEMENT_GAIN", "test_opened": False,
                  "registry_mutated": False, "article_mutated": False}; write_json(campaign / "campaign_terminal.json", result); return result
    al = _internal_al(args, prep, campaign, code, cpus, shortlist, normal_campaign=screening_campaign)
    if al.empty:
        result = {"stage": "R121", "status": "NO_COMPLETE_INTERNAL_AL_FAMILY", "test_opened": False,
                  "registry_mutated": False, "article_mutated": False}; write_json(campaign / "campaign_terminal.json", result); return result
    winner = al.iloc[0]; frozen = {"candidate_id": str(winner.candidate_id), "tau0": float(winner.tau0), "family": "al",
        "operator": "mean_feature", "internal_mean_AQL": float(winner.mean_AQL), "test_opened": False}
    write_json(campaign / "frozen_choice.json", frozen)
    fold1 = _outer_fold(args, prep, campaign, code, cpus[0], frozen["candidate_id"], frozen["tau0"], 1)
    metric1 = fold1[fold1.operator.eq("mean_feature")].iloc[0].to_dict()
    ledger = pd.read_csv(prep / "comparator_ledger.csv")
    pricefm_width = float(ledger[(ledger.method == "pricefm") & (ledger.fold == 1)].iloc[0].mean_width_10_90)
    gate = fold1_gate(metric1, 20.188155973663797, pricefm_width); write_json(campaign / "fold1_development_gate.json", gate)
    if not gate["passed"]:
        result = {"stage": "R121", "status": "FOLD1_DEVELOPMENT_GATE_FAILED", "frozen_choice": frozen,
                  "fold1_metrics": metric1, "gate": gate, "test_opened": False, "registry_mutated": False, "article_mutated": False}
        write_json(campaign / "campaign_terminal.json", result); return result
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [_outer_fold and pool.submit(_outer_fold, args, prep, campaign, code, cpus[index + 1], frozen["candidate_id"], frozen["tau0"], fold)
                   for index, fold in enumerate((2, 3))]
        frames = [fold1] + [future.result() for future in futures]
    all_metrics = pd.concat(frames, ignore_index=True); all_metrics.to_csv(campaign / "outer/all_metrics.csv", index=False)
    closeout = code / "application/scripts/pricefm/419_closeout_pricefm_stage_r121_targeted_dense_refinement.py"
    _command([sys.executable, str(closeout), "--artifact-repo", str(args.artifact_repo), "--prep-dir", str(prep),
              "--campaign-root", str(campaign)], code, campaign / "logs/closeout.log", cpus[0])
    return json.loads((campaign / "campaign_terminal.json").read_text())


def main() -> int:
    args = parser().parse_args(); args.artifact_repo = args.artifact_repo.resolve(); args.code_root = args.code_root.resolve()
    _, _, _, campaign = _paths(args)
    if args.mode == "ridge-cell": result = ridge_cell(args)
    elif args.mode == "rhs-score": result = rhs_score(args)
    elif args.mode == "bridge-family": result = bridge_family(args)
    else:
        campaign.mkdir(parents=True, exist_ok=True); lock = (campaign / "controller.lock").open("a+")
        try: fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error: raise RuntimeError("another R121 controller owns this campaign") from error
        try:
            result = controller(args)
        except Exception as error:
            write_json(campaign / "campaign_failure.json", {"stage": "R121", "status": "R121_CONTROLLER_FAILED",
                "error_type": type(error).__name__, "error": str(error), "test_opened": False,
                "registry_mutated": False, "article_mutated": False})
            raise
        finally: lock.close()
    print(json.dumps(result, indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
