#!/usr/bin/env python3
"""Run the resumable, training-only PriceFM R122 long-memory pipeline."""

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
import tempfile
import threading
import time
from typing import Any, Callable, Mapping

# The controller also evaluates forecasts in-process, before starting R children.
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS",
)
for _thread_variable in THREAD_ENV:
    os.environ[_thread_variable] = "1"

import numpy as np
import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r121_engine import QUANTILE_ORDER
from pricefm_r122_engine import RESERVOIR_SEEDS, fingerprint, paired_cap_predictive_stability
import pricefm_r122_runtime as RT


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_bg_long_memory_screen_20261001"
PARENT = {0.50: None, 0.45: 0.50, 0.55: 0.50, 0.25: 0.45, 0.75: 0.55, 0.10: 0.25, 0.90: 0.75}
_LOCKS: dict[str, threading.Lock] = {}
_LOCKS_GUARD = threading.Lock()


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--mode", choices=("controller", "ridge-cell", "rhs-score"), default="controller")
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--prep-dir", type=Path); value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, default=15); value.add_argument("--cpu-list", required=True)
    value.add_argument("--fit-id"); value.add_argument("--candidate-id")
    value.add_argument("--split", type=int); value.add_argument("--fit-dir", type=Path)
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--prepare-only", action="store_true")
    value.add_argument("--resume-plan-only", action="store_true")
    value.add_argument("--maximum-cpu-percent", type=float, default=35.0)
    return value


def _paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    return artifact, args.code_root.resolve(), prep, campaign


def _json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _split_is_test(value: Any) -> bool:
    """Identify an actual test split without rejecting harmless key names."""
    if not isinstance(value, Mapping):
        return False
    for key in ("name", "split", "role", "partition", "set", "id"):
        if key not in value:
            continue
        label = str(value[key]).strip().lower().replace("-", "_")
        if label == "test" or label.startswith("test_") or label.endswith("_test"):
            return True
    return False


def _same_utc_instant(left: Any, right: Any) -> bool:
    def normalize(value: Any) -> pd.Timestamp:
        timestamp = pd.Timestamp(str(value))
        return timestamp.tz_localize("UTC") if timestamp.tzinfo is None else timestamp.tz_convert("UTC")
    return normalize(left) == normalize(right)


def _write_immutable_csv(frame: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = frame.to_csv(index=False)
    if path.is_file():
        if path.read_text() != serialized:
            raise RuntimeError(f"R122 immutable manifest changed: {path}")
        return
    path.write_text(serialized)


def _control(prep: Path) -> dict[str, Any]:
    return _json(prep / "launch_control.json")


def _cpus(value: str, expected: int) -> list[int]:
    result: list[int] = []
    for block in str(value).split(","):
        block = block.strip()
        if not block:
            continue
        if "-" in block:
            first, last = (int(item) for item in block.split("-", 1)); result.extend(range(first, last + 1))
        else:
            result.append(int(block))
    if len(result) != expected or len(result) != len(set(result)):
        raise ValueError(f"R122 requires exactly {expected} distinct logical CPUs")
    if len({_physical(cpu) for cpu in result}) != len(result):
        raise ValueError("R122 CPU list contains SMT siblings")
    return result


def _physical(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())


def _cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        rows: dict[int, tuple[int, int]] = {}
        for line in Path("/proc/stat").read_text().splitlines():
            if not line.startswith("cpu") or line.startswith("cpu "):
                continue
            fields = line.split(); values = [int(value) for value in fields[1:]]
            rows[int(fields[0][3:])] = (sum(values), values[3] + values[4])
        return rows
    before = read(); time.sleep(interval); after = read()
    return {
        cpu: 100 * (1 - (after[cpu][1] - idle) / max(1, after[cpu][0] - total))
        for cpu, (total, idle) in before.items()
    }


def _command(command: list[str], code: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True); env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command] if cpu is not None else command
    with log.open("a") as handle:
        handle.write("$ " + " ".join(map(str, actual)) + "\n"); handle.flush()
        result = subprocess.run(actual, cwd=str(code), env=env, stdout=handle,
                                stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}")


def _atomic(output: Path, writer: Callable[[Path], None]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True); key = str(output.resolve())
    with _LOCKS_GUARD:
        lock = _LOCKS.setdefault(key, threading.Lock())
    with lock:
        temporary = Path(tempfile.mkdtemp(prefix=f"{output.name}.tmp.", dir=output.parent))
        try:
            writer(temporary)
            if output.exists():
                shutil.rmtree(output)
            temporary.rename(output)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)


def _run_queue(tasks: list[tuple[str, list[str], Path]], cpus: list[int], code: Path,
               progress_path: Path, expected_total: int, fail_fast: bool = False) -> dict[str, Any]:
    state: dict[str, Any] = {
        "expected_total": int(expected_total), "scheduled_this_resume": len(tasks),
        "complete_this_resume": 0, "failed_this_resume": 0,
        "failed_task_ids": [], "updated_at_epoch": time.time(),
        "failures": [],
    }
    lock = threading.Lock(); buckets = [[] for _ in cpus]
    for index, task in enumerate(tasks):
        buckets[index % len(cpus)].append(task)

    def worker(cpu: int, bucket: list[tuple[str, list[str], Path]]) -> None:
        for task_id, command, log in bucket:
            ok = True
            try:
                _command(command, code, log, cpu)
            except Exception as error:
                ok = False
                failure = {"task_id": task_id, "error": str(error), "log": str(log)}
            with lock:
                state["complete_this_resume" if ok else "failed_this_resume"] += 1
                if not ok:
                    state["failed_task_ids"].append(task_id)
                    state["failures"].append(failure)
                state["updated_at_epoch"] = time.time(); progress_path.parent.mkdir(parents=True, exist_ok=True)
                write_json(progress_path, state)
            if fail_fast and not ok:
                raise RuntimeError(f"R122 task failed: {task_id}")

    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures):
            future.result()
    if not tasks:
        progress_path.parent.mkdir(parents=True, exist_ok=True); write_json(progress_path, state)
    if fail_fast and state["failed_this_resume"]:
        raise RuntimeError(f"R122 queue failed: {state['failed_task_ids'][:10]}")
    return state


def _preflight(args: argparse.Namespace, prep: Path, campaign: Path, cpus: list[int]) -> dict[str, Any]:
    summary = _json(prep / "summary.json"); sources = pd.read_csv(prep / "source_manifest.csv")
    control = _control(prep)
    changed_sources = [
        str(row.path) for row in sources.itertuples(index=False)
        if not Path(row.path).is_file() or sha256_file(Path(row.path)) != str(row.sha256)
    ]
    changed_outputs = [
        name for name, expected in summary["output_sha256"].items()
        if not (prep / name).is_file() or sha256_file(prep / name) != expected
    ]
    audit_seconds = float(control["cpu_audit_seconds"])
    usage = _cpu_snapshot(audit_seconds)
    physical_usage = {
        cpu: max(value for sibling, value in usage.items() if _physical(sibling) == _physical(cpu))
        for cpu in cpus
    }
    selected_mean_percent = float(np.mean(list(physical_usage.values())))
    selected_peak_percent = float(np.max(list(physical_usage.values())))
    available_kib = next(
        int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
        if line.startswith("MemAvailable:")
    )
    free_gib = shutil.disk_usage(campaign.parent).free / 2**30
    config = yaml.safe_load(Path(control["data_config"]).read_text())
    configured_splits = config.get("pricefm", {}).get("splits", [])
    reuse_changes = _reuse_inventory_changes(prep, campaign)
    checks = {
        "launch_authorized": summary.get("status") == "R122_LONG_MEMORY_LAUNCH_READY" and summary.get("launch_authorized") is True,
        "source_hashes": not changed_sources, "preparation_hashes": not changed_outputs,
        "frozen_reused_outputs": not reuse_changes,
        "controller_thread_bounds": all(os.environ.get(name) == "1" for name in THREAD_ENV),
        "worker_count": len(cpus) == int(args.workers) == int(control["workers"]) == 15,
        "distinct_physical_cores": len({_physical(cpu) for cpu in cpus}) == 15,
        "selected_capacity_available": selected_mean_percent <= float(args.maximum_cpu_percent),
        "no_sustained_selected_core_saturation":
            selected_peak_percent <= float(control["maximum_selected_core_peak_percent"]),
        "memory_floor": available_kib / 2**20 >= float(control["minimum_memory_gib"]),
        "disk_floor": free_gib >= float(control["minimum_free_gib"]),
        "python_runtime": Path(sys.executable).absolute() == Path(control["python_executable"]).absolute()
                          and sys.prefix == control["python_prefix"],
        "test_firewall": control["test_access_authorized"] is False and
                         control["official_test_scoring_authorized"] is False and
                         configured_splits and not any(_split_is_test(item) for item in configured_splits),
    }
    result = {
        "status": "R122_LONG_MEMORY_PREFLIGHT_PASS" if all(checks.values()) else "R122_LONG_MEMORY_PREFLIGHT_BLOCKED",
        "checks": checks, "changed_sources": changed_sources, "changed_preparation_outputs": changed_outputs,
        "changed_reused_outputs": reuse_changes,
        "cpus": cpus, "physical_core_max_percent": physical_usage,
        "cpu_audit_seconds": audit_seconds,
        "selected_mean_percent": selected_mean_percent,
        "selected_peak_percent": selected_peak_percent,
        "maximum_selected_mean_percent": float(args.maximum_cpu_percent),
        "maximum_selected_peak_percent": float(control["maximum_selected_core_peak_percent"]),
        "available_memory_gib": available_kib / 2**20, "free_disk_gib": free_gib,
        "test_opened": False,
    }
    campaign.mkdir(parents=True, exist_ok=True); write_json(campaign / "launch_preflight.json", result)
    if not all(checks.values()):
        raise RuntimeError(f"R122 preflight blocked: {checks}")
    return result


def _prepare_processed(control: Mapping[str, Any], campaign: Path, code: Path, cpu: int) -> dict[str, Any]:
    runtime = Path(control["runtime_processed"]); source = Path(control["source_processed"])
    runtime.mkdir(parents=True, exist_ok=True)
    for name in ("splits_scaled", "scalers"):
        destination = runtime / name; expected = (source / name).resolve()
        if destination.is_symlink():
            if destination.resolve() != expected:
                raise RuntimeError(f"R122 processed dependency changed: {name}")
        elif not destination.exists():
            destination.symlink_to(expected, target_is_directory=True)
        else:
            raise RuntimeError(f"R122 processed dependency is not a symlink: {name}")
    probe = RT.normalize_spec({
        "region": "BG", "feature_policy": "graph_neighbor_exogenous", "calendar": "none",
        "readout": "pure_all_layers", "m_y": 2880, "m_x": 96,
        "source_window": 3120, "warmup_steps": 240, "depth": 2, "units": [128, 128],
        "alpha": .1, "rho": .82, "input_scale": .05, "input_fan_in": 32,
        "recurrent_sparsity": .02, "seed": int(RESERVOIR_SEEDS[0]),
    })
    regions = ",".join(RT.active_regions(probe))
    _command([
        str(Path(control["python_executable"])), str(code / "application/scripts/pricefm/05_build_windows.py"),
        "--config", str(control["data_config"]), "--pilot-only", "false", "--regions", regions,
        "--folds", "1", "--resume", "true", "--force", "false",
    ], code, campaign / "logs/build_windows_fold1.log", cpu)
    target = _json(Path(control["data_config"]).parent.parent / "target_contract.json")
    raw_arrays = RT.explicit_arrays(RT.load_windows(runtime, 1, "train", probe), probe)
    arrays, support_audit = RT.contract_support(
        raw_arrays, target["expected_first_origin_utc"], target["expected_origin_count"],
    )
    splits = RT.internal_splits(len(arrays.response))
    checks = {
        "origin_count_940": len(arrays.response) == 940,
        "first_origin": _same_utc_instant(arrays.anchors[0], target["expected_first_origin_utc"]),
        "split_counts": all(
            len(item["train"]) == int(target["expected_internal_counts"][str(item["split"])]["train"])
            and len(item["validation"]) == int(target["expected_internal_counts"][str(item["split"])]["validation"])
            for item in splits
        ),
        "source_window": arrays.price_history.shape[1] == 3120,
        "finite": all(np.isfinite(value).all() for value in (
            arrays.price_history, arrays.exog_history, arrays.exog_future, arrays.response,
        )),
    }
    result = {"status": "R122_PROCESSED_PACKET_READY" if all(checks.values()) else "R122_PROCESSED_PACKET_INVALID",
              "checks": checks, "regions": regions.split(","), "origin_count": len(arrays.response),
              "first_origin": str(arrays.anchors[0]), "support_audit": support_audit,
              "test_opened": False}
    write_json(campaign / "processed_audit.json", result)
    if not all(checks.values()):
        raise RuntimeError(f"R122 processed packet failed: {checks}")
    return result


def _execution(prep: Path) -> pd.DataFrame:
    return pd.read_csv(prep / "execution_manifest.csv")


def _candidate_manifest(prep: Path) -> pd.DataFrame:
    return pd.read_csv(prep / "candidate_manifest.csv")


def _ridge_worker_manifest(prep: Path, campaign: Path) -> pd.DataFrame:
    broad = _execution(prep)
    if not broad.role.isin(["search", "external_control"]).all():
        raise ValueError("R122 broad manifest has an invalid role")
    seed_path = campaign / "seed3/manifest.csv"
    if seed_path.is_file():
        seed3 = pd.read_csv(seed_path)
        if not seed3.role.eq("seed3").all():
            raise ValueError("R122 third-seed manifest has an invalid role")
        broad = pd.concat([broad, seed3], ignore_index=True, sort=False)
    if broad.fit_id.astype(str).duplicated().any():
        raise ValueError("R122 worker manifests contain duplicate fit IDs")
    return broad


def _ridge_row(prep: Path, campaign: Path, fit_id: str,
               manifest: pd.DataFrame | None = None,
               candidates: pd.DataFrame | None = None) -> pd.Series:
    rows = _ridge_worker_manifest(prep, campaign) if manifest is None else manifest
    selected = rows[rows.fit_id.astype(str).eq(fit_id)]
    if len(selected) != 1:
        raise ValueError(f"R122 worker fit ID has {len(selected)} matches: {fit_id}")
    row = selected.iloc[0]
    if str(row.test_access_authorized).lower() != "false":
        raise ValueError(f"R122 worker test access is not false: {fit_id}")
    seed = int(row.reservoir_seed)
    allowed = RESERVOIR_SEEDS[2:] if row.role == "seed3" else RESERVOIR_SEEDS[:2]
    if seed not in allowed:
        raise ValueError(f"R122 worker reservoir seed is invalid: {fit_id}")
    expected_hash = fingerprint({"structural_sha256": str(row.structural_sha256), "reservoir_seed": seed})
    if str(row.fit_sha256) != expected_hash or fit_id != f"r122f_{expected_hash[:16]}":
        raise ValueError(f"R122 worker fit fingerprint differs: {fit_id}")
    if candidates is None:
        candidates = pd.concat([
            _candidate_manifest(prep), pd.read_csv(prep / "control_manifest.csv"),
        ], ignore_index=True, sort=False)
    candidate = candidates[candidates.candidate_id.astype(str).eq(str(row.candidate_id))]
    if len(candidate) != 1:
        raise ValueError(f"R122 worker candidate has {len(candidate)} matches: {fit_id}")
    anchor = candidate.iloc[0]
    spec = json.loads(str(row.spec_json))
    if (spec != json.loads(str(anchor.spec_json)) or fingerprint(spec) != str(row.structural_sha256)
            or str(anchor.structural_sha256) != str(row.structural_sha256)):
        raise ValueError(f"R122 worker structural specification differs: {fit_id}")
    for key in ("input_dimension", "readout_dimension"):
        if int(row[key]) != int(anchor[key]):
            raise ValueError(f"R122 worker {key} differs: {fit_id}")
    is_control = str(row.candidate_id) in set(pd.read_csv(prep / "control_manifest.csv").candidate_id.astype(str))
    if is_control != (row.role == "external_control"):
        raise ValueError(f"R122 worker candidate role differs: {fit_id}")
    _spec_from_row(row)
    return row


def _reuse_inventory_changes(prep: Path, campaign: Path) -> list[str]:
    control = _control(prep)
    if "continuation" not in control:
        return []
    changed = []
    for row in pd.read_csv(prep / "reused_output_inventory.csv").itertuples(index=False):
        path = (campaign / str(row.path)).resolve()
        if (not path.is_relative_to((campaign / "ridge/fits").resolve())
                or not path.is_file() or path.stat().st_size != int(row.bytes)
                or sha256_file(path) != str(row.sha256)):
            changed.append(str(row.path))
    return changed


def _spec_from_row(row: Any) -> dict[str, Any]:
    value = json.loads(str(row.spec_json)); value["seed"] = int(row.reservoir_seed)
    return RT.normalize_spec(value)


def _selection_arrays(control: Mapping[str, Any], spec: Mapping[str, Any]) -> Any:
    target = _json(Path(control["data_config"]).parent.parent / "target_contract.json")
    raw = RT.explicit_arrays(
        RT.load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec,
    )
    arrays, _ = RT.contract_support(
        raw, target["expected_first_origin_utc"], target["expected_origin_count"],
    )
    return arrays


def _fit_root(campaign: Path, fit_id: str) -> Path:
    return campaign / "ridge/fits" / str(fit_id)


def _ridge_valid(path: Path, expected_hash: str | None = None) -> bool:
    try:
        value = _json(path / "terminal.json")
    except (OSError, json.JSONDecodeError):
        return False
    return value.get("status") == "completed_r122_ridge_cell" and value.get("test_opened") is False \
        and (expected_hash is None or value.get("fit_sha256") == expected_hash)


def ridge_cell(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); fit_id = str(args.fit_id)
    row = _ridge_row(prep, campaign, fit_id); output = _fit_root(campaign, fit_id)
    if _ridge_valid(output, str(row.fit_sha256)):
        return _json(output / "terminal.json")
    spec = _spec_from_row(row); control = _control(prep)
    arrays = _selection_arrays(control, spec)
    splits = RT.internal_splits(len(arrays.response)); metrics: list[dict[str, Any]] = []
    stats: dict[str, dict[str, Any]] = {}; preprocessing: dict[str, Any] = {}; audits: dict[str, Any] = {}
    for item in splits:
        split = int(item["split"]); scaled, scaler = RT.standardize_from_training_origins(arrays, item["train"])
        packet, audit = RT.teacher_forced_statistics(scaled, spec, {"train": item["train"]})
        stats[str(split)] = packet["train"]; preprocessing[str(split)] = scaler; audits[str(split)] = audit
        score = RT.recursive_normal_score(
            scaled, spec, RT.fit_scaled_ridge(packet["train"]), item["validation"],
            maximum_origins=int(control["broad_score_max_origins_per_split"]),
        )
        for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"):
            score[metric] *= float(scaler["price_scale"])
        metrics.append({"split": split, **score})
    names = RT.input_names(spec, arrays.exog_names); features = RT.feature_names(spec, names)

    def write(temp: Path) -> None:
        payload: dict[str, np.ndarray] = {}
        for split in (1, 2, 3):
            value = stats[str(split)]
            payload[f"split{split}_XtX"] = value["XtX"]; payload[f"split{split}_Xty"] = value["Xty"]
            payload[f"split{split}_yty"] = np.asarray([value["yty"]])
            payload[f"split{split}_n"] = np.asarray([value["n"]], dtype=np.int64)
        np.savez_compressed(temp / "training_statistics.npz", **payload)
        pd.DataFrame(metrics).to_csv(temp / "validation_metrics.csv", index=False)
        write_json(temp / "contract.json", {
            "stage": "R122_broad_normal", "fit_id": fit_id, "candidate_id": str(row.candidate_id),
            "fit_sha256": str(row.fit_sha256), "structural_sha256": str(row.structural_sha256),
            "reservoir_seed": int(row.reservoir_seed), "role": str(row.role), "spec": spec,
            "feature_names": features, "input_names": names,
            "source_manifest": list(arrays.source_manifest), "split_preprocessing": preprocessing,
            "reservoir_audit": audits, "selection_scope": control["selection_scope"], "test_opened": False,
            "execution_provenance": {"code_head": control["code_head"],
                "source_manifest_sha256": sha256_file(prep / "source_manifest.csv")},
        })
        write_json(temp / "terminal.json", {
            "status": "completed_r122_ridge_cell", "stage": "R122_broad_normal",
            "fit_id": fit_id, "candidate_id": str(row.candidate_id), "fit_sha256": str(row.fit_sha256),
            "reservoir_seed": int(row.reservoir_seed), "role": str(row.role),
            "p": len(features), "input_dimension": len(names),
            "mean_AQL": float(np.mean([value["AQL"] for value in metrics])),
            "mean_late_AQL": float(np.mean([value["late_AQL"] for value in metrics])),
            "worst_AQL": float(np.max([value["AQL"] for value in metrics])),
            "test_opened": False,
        })
    _atomic(output, write)
    return _json(output / "terminal.json")


def _ridge_tasks(args: argparse.Namespace, prep: Path, campaign: Path, code: Path,
                 manifest: pd.DataFrame, label: str) -> list[tuple[str, list[str], Path]]:
    ordered = manifest.sort_values(
        ["input_dimension", "readout_dimension", "fit_id"],
        ascending=[False, False, True], kind="mergesort",
    ) if {"input_dimension", "readout_dimension"}.issubset(manifest.columns) else manifest.sort_values("fit_id")
    tasks = []
    lookup = _ridge_worker_manifest(prep, campaign)
    candidates = pd.concat([
        _candidate_manifest(prep), pd.read_csv(prep / "control_manifest.csv"),
    ], ignore_index=True, sort=False)
    for row in ordered.itertuples(index=False):
        if not _ridge_valid(_fit_root(campaign, str(row.fit_id)), str(row.fit_sha256)):
            resolved = _ridge_row(prep, campaign, str(row.fit_id), lookup, candidates)
            for key in ("fit_sha256", "spec_json", "candidate_id", "role", "reservoir_seed"):
                if str(getattr(row, key)) != str(resolved[key]):
                    raise ValueError(f"R122 queued {key} differs: {row.fit_id}")
            tasks.append((str(row.fit_id), [
                sys.executable, str(Path(__file__).resolve()), "--mode", "ridge-cell",
                "--artifact-repo", str(args.artifact_repo), "--code-root", str(code),
                "--prep-dir", str(prep), "--campaign-root", str(campaign),
                "--workers", str(args.workers), "--cpu-list", args.cpu_list,
                "--fit-id", str(row.fit_id),
            ], campaign / f"logs/{label}/{row.fit_id}.log"))
    return tasks


def _fit_metrics(campaign: Path, manifest: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for row in manifest.itertuples(index=False):
        root = _fit_root(campaign, str(row.fit_id))
        if not _ridge_valid(root, str(row.fit_sha256)):
            continue
        metrics = pd.read_csv(root / "validation_metrics.csv")
        rows.append({
            **row._asdict(), "mean_AQL": float(metrics.AQL.mean()),
            "mean_late_AQL": float(metrics.late_AQL.mean()),
            "worst_AQL": float(metrics.AQL.max()),
            "mean_coverage": float(metrics.interval_80_coverage.mean()),
            "mean_width": float(metrics.interval_80_width.mean()),
        })
    return pd.DataFrame(rows)


def _structural_ranking(fits: pd.DataFrame, expected_seeds: int) -> pd.DataFrame:
    complete = fits.groupby("candidate_id", as_index=False).filter(
        lambda group: len(group) == expected_seeds and group.reservoir_seed.nunique() == expected_seeds
    )
    if complete.empty:
        return complete
    ranking = complete.groupby("candidate_id", as_index=False).agg(
        structural_sha256=("structural_sha256", "first"), role=("role", "first"),
        seed_count=("reservoir_seed", "nunique"), mean_AQL=("mean_AQL", "mean"),
        seed_sd_AQL=("mean_AQL", "std"), mean_late_AQL=("mean_late_AQL", "mean"),
        worst_AQL=("worst_AQL", "max"), mean_coverage=("mean_coverage", "mean"),
        mean_width=("mean_width", "mean"),
    )
    ranking["seed_sd_AQL"] = ranking.seed_sd_AQL.fillna(0.0)
    ranking = ranking.sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "seed_sd_AQL", "candidate_id"],
        kind="mergesort",
    ).reset_index(drop=True)
    ranking.insert(0, "rank", np.arange(1, len(ranking) + 1))
    return ranking


def _broad_closeout(prep: Path, campaign: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    manifest = _execution(prep); metrics = _fit_metrics(campaign, manifest)
    search = _structural_ranking(metrics[metrics.role.eq("search")], 2)
    control = _structural_ranking(metrics[metrics.role.eq("external_control")], 2)
    if len(search) != 3199 or len(control) != 1:
        raise RuntimeError(f"R122 broad closeout incomplete: search={len(search)}, control={len(control)}")
    root = campaign / "broad/closeout"; root.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(root / "fit_metrics.csv", index=False); search.to_csv(root / "structural_ranking.csv", index=False)
    control.to_csv(root / "control_ranking.csv", index=False)
    write_json(root / "summary.json", {
        "status": "R122_BROAD_SCREEN_COMPLETE", "fit_count": len(metrics),
        "search_structure_count": len(search), "control_structure_count": len(control),
        "test_opened": False,
    })
    return search, metrics


def _third_seed_manifest(prep: Path, campaign: Path, broad: pd.DataFrame) -> pd.DataFrame:
    path = campaign / "seed3/manifest.csv"; candidates = _candidate_manifest(prep)
    rows = []
    for rank in broad.head(320).itertuples(index=False):
        candidate = candidates[candidates.candidate_id.astype(str).eq(str(rank.candidate_id))]
        if len(candidate) != 1:
            raise RuntimeError(f"R122 seed3 candidate missing: {rank.candidate_id}")
        row = candidate.iloc[0]; seed = int(RESERVOIR_SEEDS[2])
        fit_hash = fingerprint({"structural_sha256": row.structural_sha256, "reservoir_seed": seed})
        rows.append({
            "fit_id": f"r122f_{fit_hash[:16]}", "candidate_id": row.candidate_id,
            "structural_sha256": row.structural_sha256, "reservoir_seed": seed,
            "fit_sha256": fit_hash, "canonical_seed": False, "role": "seed3",
            "test_access_authorized": False, "spec_json": row.spec_json,
            "input_dimension": row.input_dimension, "readout_dimension": row.readout_dimension,
        })
    result = pd.DataFrame(rows).sort_values("candidate_id").reset_index(drop=True)
    if len(result) != 320 or result.fit_id.duplicated().any():
        raise RuntimeError("R122 third-seed manifest contract failed")
    _write_immutable_csv(result, path)
    return result


def _third_seed_closeout(prep: Path, campaign: Path, broad_metrics: pd.DataFrame,
                         seed_manifest: pd.DataFrame) -> pd.DataFrame:
    seed_metrics = _fit_metrics(campaign, seed_manifest)
    top_ids = set(seed_manifest.candidate_id.astype(str))
    combined = pd.concat([
        broad_metrics[broad_metrics.candidate_id.astype(str).isin(top_ids) & broad_metrics.role.eq("search")],
        seed_metrics,
    ], ignore_index=True, sort=False)
    combined["role"] = "seed_robustness"
    ranking = _structural_ranking(combined, 3)
    if len(ranking) != 320:
        raise RuntimeError(f"R122 third-seed closeout incomplete: {len(ranking)}/320")
    root = campaign / "seed3/closeout"; root.mkdir(parents=True, exist_ok=True)
    seed_metrics.to_csv(root / "seed3_fit_metrics.csv", index=False)
    ranking.to_csv(root / "robust_ranking.csv", index=False)
    ranking.head(96).to_csv(root / "top96.csv", index=False)
    write_json(root / "summary.json", {
        "status": "R122_THIRD_SEED_COMPLETE", "candidate_count": len(ranking),
        "rhs_shortlist_count": 96, "test_opened": False,
    })
    return ranking


def _stats_from_ridge(path: Path, split: int) -> dict[str, Any]:
    with np.load(path / "training_statistics.npz") as packet:
        xtx = np.asarray(packet[f"split{split}_XtX"])
        return {"n": int(packet[f"split{split}_n"][0]), "p": len(xtx), "XtX": xtx,
                "Xty": np.asarray(packet[f"split{split}_Xty"]), "yty": float(packet[f"split{split}_yty"][0])}


def _canonical_fit(prep: Path, campaign: Path, candidate_id: str) -> Path:
    manifest = _execution(prep)
    row = manifest[
        manifest.candidate_id.astype(str).eq(str(candidate_id))
        & manifest.reservoir_seed.astype(int).eq(int(RESERVOIR_SEEDS[0]))
    ]
    if len(row) != 1:
        raise RuntimeError(f"R122 canonical fit missing: {candidate_id}")
    return _fit_root(campaign, str(row.iloc[0].fit_id))


def _tau_center(readout_dimension: int, n_ref: int) -> float:
    r = int(readout_dimension) - 1
    if r <= 5 or n_ref <= 0:
        raise ValueError("R122 tau center requires r>5 and n_ref>0")
    m0 = min(20, max(5, round(math.sqrt(r))))
    return float((m0 / (r - m0)) / math.sqrt(n_ref))


def _normal_contract(fit_id: str, stats: Path, output: Path, tau0: float,
                     control: Mapping[str, Any], code: Path) -> dict[str, Any]:
    return {
        "fit_id": fit_id, "stats_dir": str(stats), "output_dir": str(output),
        "prior_type": "rhs_ns", "tau0": float(tau0), "package_path": control["normal_runtime"],
        "helper_path": str(code / "application/R/pricefm_recursive_normal_fit.R"),
        "max_iter": int(control["rhs_max_iter"]), "min_iter": 100, "tol": 1e-5,
        "convergence_mode": "predictive_fixed_point", "stability_window": 10,
        "predictive_tol": 1e-7, "relative_beta_tol": 1e-6, "sigma_relative_tol": 1e-8,
        "prior_rms_log_precision_tol": 1e-6,
        "posterior_target_sha256": sha256_file(stats / "terminal.json") + f":tau0={tau0:.17g}",
        "selection_split": "fold1_training_internal_validation_only", "test_access_authorized": False,
    }


def _normal_valid(path: Path) -> bool:
    try:
        value = _json(path / "terminal.json")
    except (OSError, json.JSONDecodeError):
        return False
    return value.get("status") == "completed_recursive_normal_fit" and value.get("converged") is True \
        and value.get("test_opened") is False


def _ordered_candidates(prep: Path, ranking: pd.DataFrame, count: int) -> pd.DataFrame:
    candidates = _candidate_manifest(prep).set_index("candidate_id", drop=False)
    identifiers = ranking.head(count).candidate_id.astype(str).tolist()
    missing = [value for value in identifiers if value not in candidates.index]
    if missing:
        raise RuntimeError(f"R122 shortlisted candidates are missing: {missing[:5]}")
    return candidates.loc[identifiers].reset_index(drop=True)


def _rhs_cells(args: argparse.Namespace, prep: Path, campaign: Path, code: Path,
               cpus: list[int], candidates: pd.DataFrame,
               levels: Mapping[str, list[float]], label: str) -> pd.DataFrame:
    control = _control(prep); records: list[dict[str, Any]] = []
    tasks: list[tuple[str, list[str], Path]] = []
    for row in candidates.itertuples(index=False):
        candidate_id = str(row.candidate_id)
        ridge = _canonical_fit(prep, campaign, candidate_id)
        for split in (1, 2, 3):
            stats = _stats_from_ridge(ridge, split)
            stats_dir = campaign / f"rhs/stats/{candidate_id}/split={split}"
            if not (stats_dir / "terminal.json").is_file():
                RT.write_stats_packet(stats_dir, stats, {
                    "stage": "R122_rhs", "candidate_id": candidate_id, "split": split,
                })
            for tau0 in levels[candidate_id]:
                fit_id = f"r122rhs_{candidate_id}_s{split}_t{tau0:.8e}"
                output = campaign / f"rhs/{label}/fits/{fit_id}"
                contract = _normal_contract(fit_id, stats_dir, output, tau0, control, code)
                contract_path = campaign / f"rhs/{label}/contracts/{fit_id}.json"
                contract_path.parent.mkdir(parents=True, exist_ok=True)
                if contract_path.is_file() and _json(contract_path) != contract:
                    raise RuntimeError(f"R122 immutable RHS contract changed: {contract_path}")
                write_json(contract_path, contract)
                record = {
                    "candidate_id": candidate_id, "split": split, "tau0": float(tau0),
                    "fit_id": fit_id, "contract_path": str(contract_path),
                    "output_dir": str(output), "stage_label": label,
                }
                records.append(record)
                if not _normal_valid(output):
                    tasks.append((fit_id, [
                        control["rscript"],
                        str(code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R"),
                        "--contract", str(contract_path),
                    ], campaign / f"logs/rhs_{label}_fit/{fit_id}.log"))
    manifest = pd.DataFrame(records)
    _write_immutable_csv(manifest, campaign / f"rhs/{label}/manifest.csv")
    _run_queue(
        tasks, cpus, code, campaign / f"rhs/{label}/fit_progress.json", len(manifest),
    )
    score_tasks: list[tuple[str, list[str], Path]] = []
    for record in records:
        output = Path(record["output_dir"])
        if _normal_valid(output) and not (output / "validation_score.json").is_file():
            score_tasks.append((record["fit_id"], [
                sys.executable, str(Path(__file__).resolve()), "--mode", "rhs-score",
                "--artifact-repo", str(args.artifact_repo), "--code-root", str(code),
                "--prep-dir", str(prep), "--campaign-root", str(campaign),
                "--workers", str(args.workers), "--cpu-list", args.cpu_list,
                "--candidate-id", record["candidate_id"], "--split", str(record["split"]),
                "--fit-dir", record["output_dir"],
            ], campaign / f"logs/rhs_{label}_score/{record['fit_id']}.log"))
    _run_queue(
        score_tasks, cpus, code, campaign / f"rhs/{label}/score_progress.json", len(manifest),
    )
    rows = []
    for record in records:
        output = Path(record["output_dir"]); score = output / "validation_score.json"
        if _normal_valid(output) and score.is_file():
            rows.append({**record, **_json(score)})
    cells = pd.DataFrame(rows)
    cells.to_csv(campaign / f"rhs/{label}/cell_metrics.csv", index=False)
    return cells


def _complete_rhs(cells: pd.DataFrame) -> pd.DataFrame:
    if cells.empty:
        return cells
    complete = cells.groupby(["candidate_id", "tau0"], as_index=False).filter(
        lambda group: len(group) == 3 and set(group.split.astype(int)) == {1, 2, 3}
    )
    if complete.empty:
        return complete
    return complete.groupby(["candidate_id", "tau0"], as_index=False).agg(
        mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"),
        worst_AQL=("AQL", "max"), mean_coverage=("interval_80_coverage", "mean"),
        mean_width=("interval_80_width", "mean"),
    )


def _tau_activation(campaign: Path, centers: Mapping[str, float],
                    center: pd.DataFrame, pilot: pd.DataFrame,
                    top_ids: list[str]) -> dict[str, Any]:
    diagnostics = []; active = False
    for candidate_id in top_ids:
        rows = pd.concat([
            center[center.candidate_id.astype(str).eq(candidate_id)],
            pilot[pilot.candidate_id.astype(str).eq(candidate_id)],
        ], ignore_index=True)
        central = float(center[center.candidate_id.astype(str).eq(candidate_id)].iloc[0].mean_AQL)
        aql_range = float(rows.mean_AQL.max() - rows.mean_AQL.min())
        coverage_range = float(rows.mean_coverage.max() - rows.mean_coverage.min())
        center_path = campaign / f"rhs/center/fits/r122rhs_{candidate_id}_s3_t{centers[candidate_id]:.8e}/beta_mean.bin"
        center_beta = np.fromfile(center_path, dtype="<f8")
        changes = []
        for tau0 in rows.tau0.astype(float):
            if np.isclose(tau0, centers[candidate_id], rtol=1e-10, atol=0):
                continue
            path = campaign / f"rhs/pilot/fits/r122rhs_{candidate_id}_s3_t{tau0:.8e}/beta_mean.bin"
            beta = np.fromfile(path, dtype="<f8")
            if beta.shape != center_beta.shape:
                raise RuntimeError(f"R122 tau probe coefficient shape changed: {candidate_id}")
            changes.append(float(np.linalg.norm(beta - center_beta) / max(np.linalg.norm(center_beta), 1e-12)))
        max_beta_change = max(changes, default=0.0)
        activated = aql_range > max(1e-4, .001 * central) or coverage_range > .005 or max_beta_change > 1e-3
        active = active or activated
        diagnostics.append({
            "candidate_id": candidate_id, "center_tau0": centers[candidate_id],
            "aql_range": aql_range, "coverage_range": coverage_range,
            "max_beta_relative_l2": max_beta_change, "activated": activated,
        })
    result = {
        "status": "R122_TAU_ACTIVATION_COMPLETE", "active": bool(active),
        "diagnostics": diagnostics, "aql_relative_threshold": .001,
        "coverage_threshold": .005, "coefficient_threshold": 1e-3,
        "test_opened": False,
    }
    write_json(campaign / "rhs/tau_activation.json", result)
    return result


def _unique_al_shortlist(ranking: pd.DataFrame, maximum: int = 3) -> pd.DataFrame:
    selected = ranking.drop_duplicates("candidate_id", keep="first").head(maximum).copy()
    if len(selected) != maximum or selected.candidate_id.astype(str).duplicated().any():
        raise RuntimeError("R122 AL shortlist requires three distinct DESN structures")
    return selected.reset_index(drop=True)


def rhs_score(args: argparse.Namespace) -> dict[str, Any]:
    _, _, prep, campaign = _paths(args); candidate_id = str(args.candidate_id); split = int(args.split)
    output = args.fit_dir / "validation_score.json"
    if output.is_file():
        return _json(output)
    candidates = _candidate_manifest(prep); row = candidates[candidates.candidate_id.astype(str).eq(candidate_id)]
    if len(row) != 1:
        raise ValueError(f"R122 RHS candidate missing: {candidate_id}")
    spec_value = json.loads(str(row.iloc[0].spec_json)); spec_value["seed"] = int(RESERVOIR_SEEDS[0])
    spec = RT.normalize_spec(spec_value); control = _control(prep)
    arrays = _selection_arrays(control, spec)
    item = RT.internal_splits(len(arrays.response))[split - 1]
    scaled, scaler = RT.standardize_from_training_origins(arrays, item["train"])
    score = RT.recursive_normal_score(
        scaled, spec, RT.load_normal_fit(args.fit_dir), item["validation"],
        maximum_origins=int(control["rhs_score_max_origins_per_split"]),
    )
    for metric in ("AQL", "late_AQL", "median_MAE", "interval_80_width"):
        score[metric] *= float(scaler["price_scale"])
    result = {"status": "completed_r122_rhs_validation_score", "candidate_id": candidate_id,
              "split": split, **score, "test_opened": False}
    write_json(output, result); return result


def _run_rhs(args: argparse.Namespace, prep: Path, campaign: Path, code: Path,
             cpus: list[int], robust: pd.DataFrame) -> pd.DataFrame:
    control = _control(prep)
    top96 = _ordered_candidates(prep, robust, int(control["rhs_top_k"]))
    centers = {
        str(row.candidate_id): _tau_center(
            int(row.readout_dimension),
            int(_stats_from_ridge(
                _canonical_fit(prep, campaign, str(row.candidate_id)), 3,
            )["n"]),
        ) for row in top96.itertuples(index=False)
    }
    center_cells = _rhs_cells(
        args, prep, campaign, code, cpus, top96,
        {candidate: [value] for candidate, value in centers.items()}, "center",
    )
    center = _complete_rhs(center_cells).sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"],
        kind="mergesort",
    ).reset_index(drop=True)
    if len(center) != int(control["rhs_top_k"]):
        raise RuntimeError(f"R122 center RHS incomplete: {len(center)}/{control['rhs_top_k']}")

    pilot_count = int(control["rhs_tau_pilot_top_k"])
    pilot_ids = center.head(pilot_count).candidate_id.astype(str).tolist()
    pilot_candidates = top96[top96.candidate_id.astype(str).isin(pilot_ids)].copy()
    pilot_levels = {
        candidate: [
            centers[candidate] * float(multiplier)
            for multiplier in control["rhs_tau_pilot_multipliers"]
        ] for candidate in pilot_ids
    }
    pilot_cells = _rhs_cells(
        args, prep, campaign, code, cpus, pilot_candidates, pilot_levels, "pilot",
    )
    pilot = _complete_rhs(pilot_cells)
    expected_pilot = pilot_count * len(control["rhs_tau_pilot_multipliers"])
    if len(pilot) != expected_pilot:
        raise RuntimeError(f"R122 tau pilot incomplete: {len(pilot)}/{expected_pilot}")
    activation = _tau_activation(campaign, centers, center, pilot, pilot_ids)

    frames = [center, pilot]
    if activation["active"]:
        expansion_ids = center.head(
            int(control["rhs_tau_expansion_top_k"])
        ).candidate_id.astype(str).tolist()
        expansion_ids = [value for value in expansion_ids if value not in set(pilot_ids)]
        expansion_candidates = top96[
            top96.candidate_id.astype(str).isin(expansion_ids)
        ].copy()
        expansion_levels = {
            candidate: [
                centers[candidate] * float(multiplier)
                for multiplier in control["rhs_tau_expansion_multipliers"]
            ] for candidate in expansion_ids
        }
        expansion_cells = _rhs_cells(
            args, prep, campaign, code, cpus, expansion_candidates,
            expansion_levels, "expansion",
        )
        expansion = _complete_rhs(expansion_cells)
        expected_expansion = (
            len(expansion_ids) * len(control["rhs_tau_expansion_multipliers"])
        )
        if len(expansion) != expected_expansion:
            raise RuntimeError(
                f"R122 tau expansion incomplete: {len(expansion)}/{expected_expansion}"
            )
        frames.append(expansion)

    ranking = pd.concat(frames, ignore_index=True).drop_duplicates(
        ["candidate_id", "tau0"], keep="first",
    ).sort_values(
        ["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id", "tau0"],
        kind="mergesort",
    ).reset_index(drop=True)
    if not activation["active"]:
        ranking = center.copy()
    shortlist = _unique_al_shortlist(ranking, int(control["al_shortlist_k"]))
    root = campaign / "rhs/closeout"; root.mkdir(parents=True, exist_ok=True)
    rhs_manifests = [
        pd.read_csv(path) for path in sorted((campaign / "rhs").glob("*/manifest.csv"))
    ]
    consolidated_manifest = pd.concat(rhs_manifests, ignore_index=True).drop_duplicates(
        ["candidate_id", "split", "tau0"], keep="first",
    ).sort_values(
        ["candidate_id", "tau0", "split"], kind="mergesort",
    ).reset_index(drop=True)
    _write_immutable_csv(consolidated_manifest, campaign / "rhs/manifest.csv")
    pd.concat([center_cells, pilot_cells], ignore_index=True).to_csv(
        root / "evaluated_cells_without_expansion.csv", index=False,
    )
    ranking.to_csv(root / "ranking.csv", index=False)
    shortlist.to_csv(root / "al_shortlist.csv", index=False)
    write_json(root / "summary.json", {
        "status": "R122_RHS_COMPLETE", "center_candidates": len(center),
        "tau_probe_active": bool(activation["active"]),
        "ranked_candidate_tau_pairs": len(ranking),
        "al_shortlist_count": len(shortlist),
        "al_shortlist_distinct_candidates": True, "test_opened": False,
    })
    return shortlist


def _write_design(path: Path, design: np.ndarray, response: np.ndarray,
                  metadata: Mapping[str, Any]) -> None:
    if (path / "terminal.json").is_file():
        return
    def write(temp: Path) -> None:
        np.asarray(design, dtype="<f8").tofile(temp / "X.bin")
        np.asarray(response, dtype="<f8").tofile(temp / "y.bin")
        write_json(temp / "design.json", {"n": len(response), "p": design.shape[1], **dict(metadata), "test_opened": False})
        write_json(temp / "terminal.json", {"status": "completed_r121_quantile_design", "stage": "R122",
            "X_sha256": sha256_file(temp / "X.bin"), "y_sha256": sha256_file(temp / "y.bin"), "test_opened": False})
    _atomic(path, write)


def _quantile_output_valid(path: Path, target: str) -> bool:
    try:
        value = _json(path / "terminal.json")
    except (OSError, json.JSONDecodeError):
        return False
    return value.get("status") == "completed_r121_quantile_atom" and value.get("test_opened") is False \
        and value.get("posterior_target_sha256") == target


def _quantile_contract(prep: Path, control: Mapping[str, Any], candidate: str, split: int,
                       tau: float, tau0: float, design: Path, parent: Path,
                       parent_type: str, output: Path, max_iter: int) -> dict[str, Any]:
    sources = pd.read_csv(prep / "source_manifest.csv")
    adapter = Path(sources[sources.path.str.endswith("pricefm_stage_r67_cran111_adapter.R")].iloc[0].path)
    manifest = Path(control["cran_manifest"]); design_hash = sha256_file(design / "terminal.json")
    return {
        "stage": "R122_internal_selection", "tag": TAG,
        "atom_id": f"r122_{candidate}_s{split}_q{tau:.2f}_i{max_iter}",
        "candidate_id": candidate, "readout": "pure_all_layers", "fold": 1, "split": split,
        "family": "al", "tau": tau, "tau0": tau0, "design_dir": str(design),
        "output_dir": str(output), "parent_dir": str(parent), "parent_type": parent_type,
        "parent_label": parent.name, "cran_library": control["cran_library"],
        "cran_manifest": str(manifest), "cran_manifest_sha256": sha256_file(manifest),
        "cran_adapter": str(adapter), "cran_adapter_sha256": sha256_file(adapter),
        "design_terminal_sha256": design_hash, "parent_terminal_sha256": sha256_file(parent / "terminal.json"),
        "training_split": "fold1_internal_training_only", "max_iter": max_iter, "tol": 1e-5,
        "n_samp_xi": 20, "n_samp": 20,
        "seed": int(RESERVOIR_SEEDS[0] + 1000 + split * 100 + round(tau * 100)),
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
        "posterior_target_sha256": design_hash + f":tau={tau:.2f}:tau0={tau0:.17g}",
    }


def _al_ladder(prep: Path, campaign: Path, code: Path, control: Mapping[str, Any],
               candidate: str, tau0: float, split: int, cpu: int) -> dict[str, Any]:
    os.sched_setaffinity(0, {cpu})
    root = campaign / f"al_internal/{candidate}/split={split}"; metric = root / "metrics.json"
    if metric.is_file():
        return _json(metric)
    candidates = _candidate_manifest(prep); row = candidates[candidates.candidate_id.astype(str).eq(candidate)]
    if len(row) != 1:
        raise RuntimeError(f"R122 AL candidate missing: {candidate}")
    spec_value = json.loads(str(row.iloc[0].spec_json)); spec_value["seed"] = int(RESERVOIR_SEEDS[0])
    spec = RT.normalize_spec(spec_value)
    arrays = _selection_arrays(control, spec)
    item = RT.internal_splits(len(arrays.response))[split - 1]
    scaled, scaler = RT.standardize_from_training_origins(arrays, item["train"])
    design_values, response, audit = RT.teacher_forced_design(RT.subset_arrays(scaled, item["train"]), spec)
    names = RT.input_names(spec, arrays.exog_names); design = root / "design"
    _write_design(design, design_values, response, {"candidate_id": candidate, "fold": 1, "split": split,
        "feature_names": RT.feature_names(spec, names), "input_names": names, "depth": spec["depth"],
        "reservoir_audit": audit, "selection_boundary": "fold1_internal_training_only"})
    rhs_rows = pd.read_csv(campaign / "rhs/manifest.csv")
    matched = rhs_rows[
        rhs_rows.candidate_id.astype(str).eq(candidate) & rhs_rows.split.astype(int).eq(split)
        & np.isclose(rhs_rows.tau0.astype(float), tau0, rtol=1e-10, atol=0)
    ]
    if len(matched) != 1 or not _normal_valid(Path(matched.iloc[0].output_dir)):
        raise RuntimeError(f"R122 AL Normal parent missing: {candidate} split {split}")
    normal = Path(matched.iloc[0].output_dir); accepted: list[dict[str, Any]] = []
    for tau_value in QUANTILE_ORDER:
        tau = float(tau_value); parent_tau = PARENT[tau]
        parent = normal if parent_tau is None else root / f"quantiles/al/tau={parent_tau:.2f}"
        parent_type = "normal_rhs" if parent_tau is None else "quantile"
        final = root / f"quantiles/al/tau={tau:.2f}"
        contract = _quantile_contract(prep, control, candidate, split, tau, tau0, design, parent,
                                      parent_type, final, int(control["al_final_max_iter"]))
        contract_path = root / f"contracts/final/tau={tau:.2f}.json"; contract_path.parent.mkdir(parents=True, exist_ok=True)
        if contract_path.is_file() and _json(contract_path) != contract:
            raise RuntimeError(f"R122 immutable AL contract changed: {contract_path}")
        write_json(contract_path, contract)
        if not _quantile_output_valid(final, contract["posterior_target_sha256"]):
            _command([control["rscript"], str(code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                      "--config", str(contract_path)], code, root / f"logs/final_tau={tau:.2f}.log", cpu)
        diagnostics = _json(final / "diagnostics.json"); passed = bool(diagnostics["external_gate_passed"])
        method, pair = "raw_external_gate", None
        if not passed:
            companion = root / f"companions/cap={int(control['al_companion_max_iter'])}/tau={tau:.2f}"
            companion_contract = _quantile_contract(
                prep, control, candidate, split, tau, tau0, design, parent, parent_type,
                companion, int(control["al_companion_max_iter"]),
            )
            companion_path = root / f"contracts/companions/tau={tau:.2f}.json"; companion_path.parent.mkdir(parents=True, exist_ok=True)
            if companion_path.is_file() and _json(companion_path) != companion_contract:
                raise RuntimeError(f"R122 immutable AL companion changed: {companion_path}")
            write_json(companion_path, companion_contract)
            if not _quantile_output_valid(companion, companion_contract["posterior_target_sha256"]):
                _command([control["rscript"], str(code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                          "--config", str(companion_path)], code, root / f"logs/companion_tau={tau:.2f}.log", cpu)
            pair = paired_cap_predictive_stability(design, companion, final)
            passed = bool(pair["passed"]); method = "paired_cap_fitted_function_gate_v1"
            (root / "paired_cap").mkdir(parents=True, exist_ok=True)
            write_json(root / f"paired_cap/tau={tau:.2f}.json", pair)
        accepted.append({"tau": tau, "accepted": passed, "acceptance_method": method,
                         "raw_external_gate_passed": bool(diagnostics["external_gate_passed"]),
                         "pair_classification": None if pair is None else pair["classification"]})
        if not passed:
            result = {"candidate_id": candidate, "tau0": tau0, "split": split,
                      "eligible": False, "invalid_quantiles": 1,
                      "accepted_quantiles": accepted, "test_opened": False}
            root.mkdir(parents=True, exist_ok=True); write_json(metric, result); return result
    normal_fit = RT.load_normal_fit(normal)
    qfits = {tau: RT.load_quantile_fit(root / f"quantiles/al/tau={tau:.2f}") for tau in RT.QUANTILES}
    values = RT.recursive_quantile_forecast(
        RT.subset_arrays(scaled, item["validation"]), spec, normal_fit, qfits,
        int(control["posterior_paths"]), int(RESERVOIR_SEEDS[0] + split),
    )
    truth = values["truth"] * float(scaler["price_scale"]) + float(scaler["price_mean"])
    prediction = values["mean_feature"] * float(scaler["price_scale"]) + float(scaler["price_mean"])
    score = RT.prediction_metrics(truth, prediction)
    result = {"candidate_id": candidate, "tau0": tau0, "split": split,
              "eligible": True, "invalid_quantiles": 0, **score,
              "accepted_quantiles": accepted, "test_opened": False,
              "score_scope": "fold1_training_internal_validation_only"}
    write_json(metric, result); return result


def _run_al(prep: Path, campaign: Path, code: Path, cpus: list[int], rhs: pd.DataFrame) -> pd.DataFrame:
    shortlist = rhs.head(3).copy(); shortlist.to_csv(campaign / "rhs/closeout/al_shortlist.csv", index=False)
    jobs = [(str(row.candidate_id), float(row.tau0), split) for row in shortlist.itertuples(index=False) for split in (1, 2, 3)]
    records: list[dict[str, Any]] = []; lock = threading.Lock()
    progress = {"total": 9, "complete": 0, "failed": 0, "updated_at_epoch": time.time()}
    control = _control(prep)
    def one(index: int, job: tuple[str, float, int]) -> dict[str, Any]:
        candidate, tau0, split = job
        try:
            result = _al_ladder(prep, campaign, code, control, candidate, tau0, split, cpus[index])
            ok = bool(result.get("eligible"))
        except Exception as error:
            result = {"candidate_id": candidate, "tau0": tau0, "split": split, "eligible": False,
                      "error_type": type(error).__name__, "error": str(error), "test_opened": False}; ok = False
        with lock:
            progress["complete" if ok else "failed"] += 1; progress["updated_at_epoch"] = time.time()
            write_json(campaign / "al_internal/progress.json", progress)
        return result
    with ThreadPoolExecutor(max_workers=9) as pool:
        futures = [pool.submit(one, index, job) for index, job in enumerate(jobs)]
        for future in as_completed(futures):
            records.append(future.result())
    cells = pd.DataFrame(records); complete = cells.groupby(["candidate_id", "tau0"], as_index=False).filter(
        lambda group: len(group) == 3 and group.eligible.astype(bool).all()
    )
    if complete.empty:
        ranking = pd.DataFrame(columns=[
            "candidate_id", "tau0", "mean_AQL", "mean_late_AQL", "worst_AQL",
            "mean_coverage", "mean_width", "mean_crossing",
        ])
    else:
        ranking = complete.groupby(["candidate_id", "tau0"], as_index=False).agg(
            mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"),
            worst_AQL=("AQL", "max"), mean_coverage=("interval_80_coverage", "mean"),
            mean_width=("interval_80_width", "mean"), mean_crossing=("crossing_rate", "mean"),
        ).sort_values(
            ["mean_AQL", "mean_late_AQL", "worst_AQL", "mean_crossing", "candidate_id"],
            kind="mergesort",
        )
    root = campaign / "al_internal/closeout"; root.mkdir(parents=True, exist_ok=True)
    cells.to_csv(root / "cell_metrics.csv", index=False); ranking.to_csv(root / "ranking.csv", index=False)
    if len(ranking) != 3:
        write_json(root / "summary.json", {
            "status": "R122_AL_INTERNAL_INCOMPLETE",
            "complete_families": len(ranking), "required_families": 3,
            "test_opened": False,
        })
        raise RuntimeError(f"R122 AL transfer panel incomplete: {len(ranking)}/3")
    winner = ranking.iloc[0]; candidate = _candidate_manifest(prep)
    spec = json.loads(str(candidate[candidate.candidate_id.astype(str).eq(str(winner.candidate_id))].iloc[0].spec_json))
    frozen = {"status": "R122_INTERNAL_SPECIFICATION_FROZEN", "candidate_id": str(winner.candidate_id),
              "tau0": float(winner.tau0), "family": "al", "operator": "mean_feature",
              "spec": spec, "internal_mean_AQL": float(winner.mean_AQL),
              "internal_late_AQL": float(winner.mean_late_AQL), "internal_worst_AQL": float(winner.worst_AQL),
              "official_test_scoring_authorized": False, "test_opened": False}
    write_json(campaign / "frozen_internal_choice.json", frozen)
    write_json(root / "summary.json", {"status": "R122_AL_INTERNAL_COMPLETE", "complete_families": len(ranking),
        "winner": frozen, "test_opened": False})
    return ranking


def controller(args: argparse.Namespace) -> dict[str, Any]:
    _, code, prep, campaign = _paths(args); cpus = _cpus(args.cpu_list, int(args.workers))
    os.sched_setaffinity(0, set(cpus))
    preflight = _preflight(args, prep, campaign, cpus)
    if args.preflight_only:
        return preflight
    control = _control(prep)
    if args.resume_plan_only:
        execution = _execution(prep)
        seed_path = campaign / "seed3/manifest.csv"
        if not seed_path.is_file():
            raise RuntimeError("R122 resume planning requires a frozen third-seed manifest")
        seed_manifest = pd.read_csv(seed_path)
        result = {"status": "R122_RESUME_PLAN_READY", "test_opened": False,
            "broad_tasks": len(_ridge_tasks(args, prep, campaign, code, execution, "broad_ridge")),
            "third_seed_tasks": len(_ridge_tasks(args, prep, campaign, code, seed_manifest, "seed3_ridge")),
            "broad_expected": len(execution), "third_seed_expected": len(seed_manifest),
            "preparation_sha256": sha256_file(prep / "summary.json")}
        write_json(campaign / "resume_plan.json", result)
        return result
    processed = _prepare_processed(control, campaign, code, cpus[0])
    if args.prepare_only:
        return {
            "status": "R122_LONG_MEMORY_PROCESSED_READY",
            "preflight": preflight, "processed": processed, "test_opened": False,
        }
    execution = _execution(prep)
    _run_queue(_ridge_tasks(args, prep, campaign, code, execution, "broad_ridge"), cpus, code,
               campaign / "broad/progress.json", int(control["total_fit_count"]))
    broad, broad_metrics = _broad_closeout(prep, campaign)
    seed_manifest = _third_seed_manifest(prep, campaign, broad)
    _run_queue(_ridge_tasks(args, prep, campaign, code, seed_manifest, "seed3_ridge"), cpus, code,
               campaign / "seed3/progress.json", int(control["third_seed_top_k"]))
    robust = _third_seed_closeout(prep, campaign, broad_metrics, seed_manifest)
    rhs = _run_rhs(args, prep, campaign, code, cpus, robust)
    al = _run_al(prep, campaign, code, cpus, rhs)
    frozen = _json(campaign / "frozen_internal_choice.json")
    rhs_fit_count = sum(
        len(pd.read_csv(path)) for path in (campaign / "rhs").glob("*/manifest.csv")
    )
    terminal = {
        "stage": "R122", "tag": TAG,
        "status": "R122_INTERNAL_SPECIFICATION_FROZEN_TEST_BLOCKED",
        "broad_fit_count": int(control["total_fit_count"]),
        "third_seed_fit_count": int(control["third_seed_top_k"]),
        "rhs_split_fit_count": rhs_fit_count,
        "complete_al_families": len(al), "frozen_choice": frozen,
        "test_opened": False, "article_mutated": False, "registry_mutated": False,
        "joint_model_fitted": False, "mcmc_fitted": False, "exal_fitted": False,
    }
    write_json(campaign / "terminal.json", terminal)
    return terminal


def main() -> int:
    args = parser().parse_args(); args.artifact_repo = args.artifact_repo.resolve(); args.code_root = args.code_root.resolve()
    _, _, _, campaign = _paths(args)
    if args.mode == "ridge-cell":
        result = ridge_cell(args)
    elif args.mode == "rhs-score":
        result = rhs_score(args)
    else:
        campaign.mkdir(parents=True, exist_ok=True); lock = (campaign / "controller.lock").open("a+")
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("another R122 long-memory controller owns this campaign") from error
        try:
            running = not (args.preflight_only or args.prepare_only or args.resume_plan_only)
            if running:
                _, _, prep, _ = _paths(args)
                control = _control(prep)
                write_json(campaign / "continuation_status.json", {
                    "status": "R122_CONTROLLER_RUNNING", "pid": os.getpid(), "code_head": control["code_head"],
                    "preparation": str(prep), "started_at_epoch": time.time(),
                    "cpu_list": args.cpu_list, "workers": args.workers, "test_opened": False,
                })
            result = controller(args)
            if running:
                write_json(campaign / "continuation_status.json", {
                    "status": result["status"], "pid": os.getpid(), "code_head": control["code_head"],
                    "preparation": str(prep), "finished_at_epoch": time.time(), "test_opened": False,
                })
        except Exception as error:
            write_json(campaign / "campaign_failure.json", {
                "stage": "R122", "status": "R122_LONG_MEMORY_CONTROLLER_FAILED",
                "error_type": type(error).__name__, "error": str(error),
                "test_opened": False, "registry_mutated": False, "article_mutated": False,
            })
            if running:
                write_json(campaign / "continuation_status.json", {
                    "status": "R122_CONTROLLER_FAILED", "pid": os.getpid(), "error": str(error),
                    "failed_at_epoch": time.time(), "test_opened": False,
                })
            raise
        finally:
            lock.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
