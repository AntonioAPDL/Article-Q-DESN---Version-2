#!/usr/bin/env python3
"""Dependency-ordered controller for the PriceFM R113--R116 BG campaign."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_CAMPAIGN = DATA / "campaigns/pricefm_stage_r113_r116_rolled_state_driver_20260922"
R111B = DATA / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def _cpu_counters() -> dict[int, tuple[int, int]]:
    result = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if not fields or not fields[0].startswith("cpu") or not fields[0][3:].isdigit():
            continue
        values = [int(value) for value in fields[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        result[int(fields[0][3:])] = (sum(values), idle)
    return result


def cpu_percent_snapshot(interval: float = 1.0) -> list[float]:
    first = _cpu_counters()
    time.sleep(float(interval))
    second = _cpu_counters()
    values = []
    for cpu in sorted(second):
        total = second[cpu][0] - first[cpu][0]
        idle = second[cpu][1] - first[cpu][1]
        values.append(0.0 if total <= 0 else 100.0 * (total - idle) / total)
    return values


def available_memory_gib() -> float:
    fields = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        fields[key] = float(value.strip().split()[0])
    return fields.get("MemAvailable", 0.0) / 2**20


def physical_cpu_pool(max_workers: int, maximum_percent: float = 20.0) -> dict[str, Any]:
    usage = cpu_percent_snapshot(1.0)
    groups: dict[tuple[str, str], list[int]] = {}
    for cpu in range(os.cpu_count() or 1):
        base = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
        try:
            key = ((base / "physical_package_id").read_text().strip(), (base / "core_id").read_text().strip())
        except OSError:
            key = ("logical", str(cpu))
        groups.setdefault(key, []).append(cpu)
    available = []
    excluded = []
    for key, siblings in sorted(groups.items(), key=lambda item: min(item[1])):
        peak = max(usage[cpu] for cpu in siblings)
        record = {"physical_core": ":".join(key), "siblings": siblings, "peak_cpu_percent": peak}
        if peak <= float(maximum_percent):
            available.append((siblings[0], record))
        else:
            excluded.append(record)
    count = min(int(max_workers), max(0, len(available) - 1))
    selected = [cpu for cpu, _ in available[:count]]
    if not selected:
        raise RuntimeError("no idle physical CPU remains after the required reserve")
    return {
        "logical_cpu_count": len(usage), "physical_core_count": len(groups),
        "maximum_observed_cpu_percent": maximum_percent,
        "selected_logical_cpus": selected, "selected_physical_core_count": len(selected),
        "reserve_physical_cores": max(1, len(available) - len(selected)),
        "excluded_busy_physical_cores": excluded,
    }


def atomic_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    pd.DataFrame(rows).to_csv(temporary, index=False)
    temporary.replace(path)


def run_one(task: dict[str, Any], cpu: int) -> dict[str, Any]:
    log = Path(task["log_path"])
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    started = time.time()
    with log.open("a") as handle:
        handle.write(f"\n[{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}] CPU {cpu}: {' '.join(task['command'])}\n")
        handle.flush()
        result = subprocess.run(
            ["taskset", "-c", str(cpu), *task["command"]],
            stdout=handle, stderr=subprocess.STDOUT, env=env, check=False,
        )
    return {
        "task_id": task["task_id"], "cpu": cpu, "returncode": result.returncode,
        "elapsed_seconds": time.time() - started, "log_path": str(log),
    }


def run_parallel(tasks: list[dict[str, Any]], cpus: list[int], status_path: Path) -> list[dict[str, Any]]:
    if not tasks:
        return []
    count = min(len(tasks), len(cpus))
    queued = iter(tasks)
    results: list[dict[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool:
        future_map: dict[concurrent.futures.Future, int] = {}
        for cpu in cpus[:count]:
            task = next(queued, None)
            if task is not None:
                future_map[pool.submit(run_one, task, cpu)] = cpu
        while future_map:
            completed, _ = concurrent.futures.wait(
                future_map, return_when=concurrent.futures.FIRST_COMPLETED
            )
            for future in completed:
                cpu = future_map.pop(future)
                results.append(future.result())
                atomic_csv(status_path, sorted(results, key=lambda row: row["task_id"]))
                task = next(queued, None)
                if task is not None:
                    future_map[pool.submit(run_one, task, cpu)] = cpu
    failures = [row for row in results if int(row["returncode"]) != 0]
    if failures:
        raise RuntimeError("campaign phase failed: " + ", ".join(row["task_id"] for row in failures))
    return results


def valid_terminal(path: Path, status: str) -> bool:
    try:
        value = json.loads((path / "terminal.json").read_text())
        return value.get("status") == status and value.get("test_opened") is False
    except (OSError, json.JSONDecodeError):
        return False


def verify_source_manifest(campaign: Path, contract: dict[str, Any]) -> None:
    manifest_path = campaign / "source_manifest.csv"
    if sha256_file(manifest_path) != str(contract["source_manifest_sha256"]):
        raise RuntimeError("frozen source manifest changed after campaign preparation")
    for row in pd.read_csv(manifest_path).itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError(f"frozen source/evidence changed: {path}")


def verify_reuse_manifest(campaign: Path, contract: dict[str, Any]) -> None:
    name = contract.get("r114_reuse_manifest")
    expected = contract.get("r114_reuse_manifest_sha256")
    if name is None and expected is None:
        return
    if not name or not expected:
        raise RuntimeError("R114 recovery reuse manifest contract is incomplete")
    path = campaign / str(name)
    if not path.is_file() or sha256_file(path) != str(expected):
        raise RuntimeError("R114 recovery reuse manifest changed")
    rows = pd.read_csv(path)
    required = {"path", "bytes", "sha256"}
    if rows.empty or not required.issubset(rows):
        raise RuntimeError("R114 recovery reuse manifest is invalid")
    for row in rows.itertuples(index=False):
        artifact = Path(row.path)
        if (
            not artifact.is_file()
            or artifact.stat().st_size != int(row.bytes)
            or sha256_file(artifact) != str(row.sha256)
        ):
            raise RuntimeError(f"reused R114 artifact changed: {artifact}")


def verify_aligned_neighbor_drivers(campaign: Path) -> None:
    outputs = [
        campaign / f"runs/r114_normal_driver/region={region}/inner={inner}"
        for region in ("GR", "RO") for inner in (1, 2, 3)
    ]
    for output in outputs:
        terminal = json.loads((output / "terminal.json").read_text())
        inner = int(output.name.split("=", 1)[1])
        shared_path = campaign / f"shared_calendars/inner_fold_{inner}.csv"
        if (
            terminal.get("status") != "completed_r114_normal_driver"
            or terminal.get("calendar_alignment_mode") != "reference_region_shared_origin_times"
            or terminal.get("reference_region") != "BG"
            or terminal.get("calendar_key") != "origin_market_time_utc"
            or terminal.get("shared_calendar_sha256") != sha256_file(shared_path)
            or terminal.get("test_opened") is not False
        ):
            raise RuntimeError(f"neighbor Normal driver lacks a valid calendar contract: {output}")
        shared = pd.read_csv(shared_path)
        expected = pd.DatetimeIndex(pd.to_datetime(
            shared.loc[shared.split.eq("validation"), "origin_market_time"], utc=True,
        )).asi8
        observed_rows = pd.read_csv(output / "evaluation_rows.csv")
        observed = pd.DatetimeIndex(pd.to_datetime(
            observed_rows.origin_market_time.drop_duplicates(), utc=True,
        )).asi8
        alignment = pd.read_csv(output / "calendar_alignment_manifest.csv")
        if (
            not np.array_equal(observed, expected)
            or len(observed_rows) != len(expected) * 96
            or not alignment.exact_match.astype(bool).all()
            or not alignment.requested_origins.eq(alignment.matched_origins).all()
        ):
            raise RuntimeError(f"neighbor Normal driver calendar verification failed: {output}")


def preflight(campaign: Path, code_root: Path, workers: int) -> tuple[dict[str, Any], list[int]]:
    contract = json.loads((campaign / "campaign_contract.json").read_text())
    expected_hash = str(contract.get("campaign_contract_sha256", ""))
    unhashed = {key: value for key, value in contract.items() if key != "campaign_contract_sha256"}
    if (
        contract.get("stage") != "R113_R116"
        or contract.get("status") not in {
            "prepared_training_only_not_launched", "prepared_recovery_not_launched",
            "prepared_calendar_recovery_not_launched",
            "prepared_convergence_recovery_not_launched",
            "prepared_calendar_index_recovery_not_launched",
        }
        or not expected_hash
        or canonical_hash(unhashed) != expected_hash
        or contract.get("test_access_authorized") is not False
        or contract.get("registry_mutation_authorized") is not False
        or contract.get("article_mutation_authorized") is not False
    ):
        raise RuntimeError("invalid R113--R116 campaign contract")
    head = subprocess.check_output(["git", "-C", str(code_root), "rev-parse", "HEAD"], text=True).strip()
    status = subprocess.check_output(["git", "-C", str(code_root), "status", "--porcelain"], text=True).strip()
    if head != contract["head"] or status:
        raise RuntimeError("Jerez launch worktree must be clean at the frozen campaign HEAD")
    verify_source_manifest(campaign, contract)
    verify_reuse_manifest(campaign, contract)
    memory_gib = available_memory_gib()
    disk_gib = shutil.disk_usage("/data").free / 2**30
    if memory_gib < 80 or disk_gib < 150:
        raise RuntimeError(f"resource floor failed: memory={memory_gib:.1f} GiB disk={disk_gib:.1f} GiB")
    resources = physical_cpu_pool(workers)
    resources.update({
        "host": os.uname().nodename, "memory_available_gib": memory_gib,
        "data_free_gib": disk_gib, "observed_at_epoch": time.time(),
    })
    write_json(campaign / "resource_allocation.json", resources)
    return contract, list(resources["selected_logical_cpus"])


def r114_family_eligibility(
    campaign: Path, worker_module: Any, families: list[str],
) -> tuple[pd.DataFrame, list[str]]:
    rows = []
    for family in families:
        for inner in (1, 2, 3):
            root = campaign / f"runs/r114_fit/family={family}/inner={inner}"
            rows.append(worker_module.quantile_family_eligibility(
                root, family,
                family_status="completed_r114_quantile_family_fit",
                atom_status="completed_r114_quantile_atom",
                axis_name="inner_fold", axis_value=inner,
            ))
    detail = pd.DataFrame(rows)
    detail.to_csv(campaign / "r114_family_eligibility.csv", index=False)
    summary = detail.groupby("family", as_index=False).agg(
        complete_inner_folds=("axis_value", "nunique"),
        all_inner_folds_eligible=("eligible", "all"),
        atoms_complete=("atoms_complete", "sum"),
        atoms_eligible=("atoms_eligible", "sum"),
    )
    summary["eligible"] = (
        summary.complete_inner_folds.eq(3)
        & summary.all_inner_folds_eligible
        & summary.atoms_complete.eq(3 * 7)
        & summary.atoms_eligible.eq(3 * 7)
    )
    summary["decision"] = np.where(
        summary.eligible, "score_training_only", "exclude_before_validation_scoring"
    )
    summary.to_csv(campaign / "r114_family_eligibility_summary.csv", index=False)
    eligible = summary.loc[summary.eligible, "family"].astype(str).tolist()
    if not eligible:
        raise RuntimeError("R114 has no complete eligible seven-quantile family")
    return detail, eligible


def select_r114(
    campaign: Path, worker_module: Any, eligible_families: list[str],
) -> dict[str, Any]:
    rows = []
    horizons = []
    for family in eligible_families:
        for inner in (1, 2, 3):
            root = campaign / f"runs/r114_score/family={family}/inner={inner}"
            if not valid_terminal(root, "completed_r114_driver_score"):
                raise RuntimeError(f"R114 eligible family score is incomplete: {family} inner={inner}")
            rows.append(pd.read_csv(root / "driver_metrics.csv"))
            horizons.append(pd.read_csv(root / "driver_horizon_metrics.csv"))
    for inner in (1, 2, 3):
        root = campaign / f"runs/r114_normal_driver/region=BG/inner={inner}"
        terminal = json.loads((root / "terminal.json").read_text())
        n_rows = int(terminal["n_rows"])
        raw = np.fromfile(root / "prediction_paths_scaled.bin", dtype="<f8").reshape(n_rows, 500)
        meta = pd.read_csv(root / "evaluation_rows.csv")
        truth = pd.read_csv(root / "truth_scaled.csv").iloc[:, 0].to_numpy()
        order = np.lexsort((meta.horizon.to_numpy(), meta.origin_id.to_numpy()))
        origin_ids = np.sort(meta.origin_id.unique())
        samples = raw[order].reshape(len(origin_ids), 96, 500).transpose(0, 2, 1)
        truth_cube = truth[order].reshape(len(origin_ids), 96)
        summary, block = worker_module.driver_metrics(
            samples, truth_cube, "normal_rhs", "independent_normal", inner
        )
        rows.append(pd.DataFrame([summary])); horizons.append(block)
    metrics = pd.concat(rows, ignore_index=True)
    horizon_metrics = pd.concat(horizons, ignore_index=True)
    metrics.to_csv(campaign / "r114_driver_metrics.csv", index=False)
    horizon_metrics.to_csv(campaign / "r114_driver_horizon_metrics.csv", index=False)
    ranking = metrics.groupby(["family", "rank_policy"], as_index=False).agg(
        median_CRPS_scaled=("CRPS_scaled", "median"),
        worst_late_CRPS_scaled=("late_CRPS_scaled", "max"),
        mean_coverage_10_90=("coverage_10_90", "mean"),
        complete_inner_folds=("inner_fold", "nunique"),
    )
    ranking["coverage_error"] = (ranking.mean_coverage_10_90 - 0.8).abs()
    ranking = ranking[ranking.complete_inner_folds.eq(3)].copy()
    if ranking.empty:
        raise RuntimeError("R114 has no candidate with three complete training-only folds")
    ranking = ranking.sort_values(
        ["median_CRPS_scaled", "worst_late_CRPS_scaled", "coverage_error", "family", "rank_policy"],
        kind="mergesort",
    ).reset_index(drop=True)
    ranking.insert(0, "driver_rank", np.arange(1, len(ranking) + 1))
    ranking.to_csv(campaign / "r114_driver_ranking.csv", index=False)
    winner = ranking.iloc[0]
    selected = {
        "stage": "R114", "status": "selected_training_only_driver",
        "family": str(winner.family), "rank_policy": str(winner.rank_policy),
        "driver_rank": 1, "median_CRPS_scaled": float(winner.median_CRPS_scaled),
        "worst_late_CRPS_scaled": float(winner.worst_late_CRPS_scaled),
        "mean_coverage_10_90": float(winner.mean_coverage_10_90),
        "complete_inner_folds": int(winner.complete_inner_folds),
        "eligible_quantile_families": eligible_families,
        "excluded_quantile_families": sorted(set(("al", "exal")) - set(eligible_families)),
        "selection_split": "BG_fold1_training_nested_temporal_only",
        "test_opened": False,
    }
    write_json(campaign / "r114_selected_driver.json", selected)
    return selected


def materialize_rhs(campaign: Path, code_root: Path) -> pd.DataFrame:
    metrics = []
    for path in campaign.glob("runs/r115_ridge/candidate=*/ridge_metrics.csv"):
        metrics.append(pd.read_csv(path))
    ridge = pd.concat(metrics, ignore_index=True)
    summary = ridge.groupby(["candidate_id", "readout_mode"], as_index=False).agg(
        median_AQL_original=("AQL_original", "median"),
        worst_late_AQL_scaled=("late_AQL_scaled", "max"),
        mean_coverage_10_90=("coverage_10_90", "mean"),
        complete_inner_folds=("inner_fold", "nunique"),
        p=("p", "first"),
    )
    summary = summary[summary.complete_inner_folds.eq(3)].copy()
    summary = summary.sort_values(
        ["readout_mode", "median_AQL_original", "worst_late_AQL_scaled", "candidate_id"],
        kind="mergesort",
    )
    top = summary.groupby("readout_mode", group_keys=False).head(30).reset_index(drop=True)
    ridge.to_csv(campaign / "r115_ridge_cell_metrics.csv", index=False)
    summary.to_csv(campaign / "r115_ridge_ranking.csv", index=False)
    top.to_csv(campaign / "r115_ridge_top30.csv", index=False)
    contracts = campaign / "contracts/r115_rhs"
    contracts.mkdir(parents=True, exist_ok=True)
    rows = []
    package_path = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
    helper = code_root / "application/R/pricefm_recursive_normal_fit.R"
    for item in top.itertuples(index=False):
        candidate_root = campaign / f"runs/r115_ridge/candidate={item.candidate_id}"
        response_scale = float(
            ridge[(ridge.candidate_id == item.candidate_id) & (ridge.readout_mode == item.readout_mode)]
            .eval("AQL_original / AQL_scaled").median()
        )
        for inner in (1, 2, 3):
            archive_path = candidate_root / f"stats__{item.readout_mode}__inner{inner}.npz"
            archive = np.load(archive_path)
            stats_root = campaign / f"r115_rhs_stats/candidate={item.candidate_id}/{item.readout_mode}/inner={inner}"
            stats_root.mkdir(parents=True, exist_ok=True)
            arrays = {
                "XtX.bin": np.asarray(archive["XtX"], dtype="<f8"),
                "Xty.bin": np.asarray(archive["Xty"], dtype="<f8"),
                "yty.bin": np.asarray(archive["yty"], dtype="<f8"),
                "X_eval.bin": np.asarray(archive["X_eval"], dtype="<f8"),
                "y_eval.bin": np.asarray(archive["y_eval"], dtype="<f8"),
            }
            for name, value in arrays.items():
                value.tofile(stats_root / name)
            meta = {
                "stage": "R115", "candidate_id": item.candidate_id,
                "readout_mode": item.readout_mode, "inner_fold": inner,
                "n": int(archive["n"][0]), "p": int(archive["p"][0]),
                "n_eval": int(len(archive["y_eval"])),
                "files": {
                    name: {"bytes": (stats_root / name).stat().st_size, "sha256": sha256_file(stats_root / name)}
                    for name in arrays
                },
                "test_opened": False,
            }
            write_json(stats_root / "manifest.json", meta)
            for multiplier in (0.25, 1.0, 4.0):
                tau0 = 1e-4 * np.sqrt(143.0 / int(item.p)) * multiplier
                token = str(multiplier).replace(".", "p")
                task_id = f"r115_rhs__{item.candidate_id}__{item.readout_mode}__inner{inner}__m{token}"
                output = campaign / f"runs/r115_rhs/candidate={item.candidate_id}/{item.readout_mode}/inner={inner}/multiplier={token}"
                contract = {
                    "stage": "R115", "phase": "normal_rhs_pruning", "task_id": task_id,
                    "candidate_id": item.candidate_id, "readout_mode": item.readout_mode,
                    "inner_fold": inner, "tau_multiplier": multiplier, "tau0": tau0,
                    "response_scale": response_scale,
                    "stats_manifest_path": str((stats_root / "manifest.json").resolve()),
                    "stats_manifest_sha256": sha256_file(stats_root / "manifest.json"),
                    "output_dir": str(output.resolve()), "helper_path": str(helper.resolve()),
                    "package_path": str(package_path.resolve()),
                    "max_iter": 1500, "min_iter": 50, "tol": 1e-5,
                    "selection_split": "BG_fold1_training_nested_temporal_only",
                    "test_access_authorized": False, "registry_mutation_authorized": False,
                    "article_mutation_authorized": False,
                }
                contract["task_contract_sha256"] = canonical_hash(contract)
                path = contracts / f"{task_id}.json"
                write_json(path, contract)
                rows.append({
                    "task_id": task_id, "candidate_id": item.candidate_id,
                    "readout_mode": item.readout_mode, "inner_fold": inner,
                    "tau_multiplier": multiplier, "tau0": tau0,
                    "contract_path": str(path), "output_dir": str(output),
                })
    result = pd.DataFrame(rows)
    result.to_csv(campaign / "r115_rhs_manifest.csv", index=False)
    return result


def select_r115(campaign: Path) -> dict[str, Any]:
    rows = []
    for path in campaign.glob("runs/r115_rhs/**/metric_summary.csv"):
        rows.append(pd.read_csv(path))
    cells = pd.concat(rows, ignore_index=True)
    summary = cells.groupby(
        ["candidate_id", "readout_mode", "tau_multiplier", "tau0"], as_index=False
    ).agg(
        median_AQL_original=("AQL_original", "median"),
        worst_late_AQL_scaled=("late_AQL_scaled", "max"),
        mean_coverage_10_90=("coverage_10_90", "mean"),
        complete_inner_folds=("inner_fold", "nunique"),
        all_converged=("converged", "all"),
    )
    eligible = summary[summary.complete_inner_folds.eq(3) & summary.all_converged].copy()
    eligible["coverage_error"] = (eligible.mean_coverage_10_90 - 0.8).abs()
    eligible = eligible.sort_values(
        ["median_AQL_original", "worst_late_AQL_scaled", "coverage_error", "candidate_id"],
        kind="mergesort",
    ).reset_index(drop=True)
    if eligible.empty:
        raise RuntimeError("R115 has no complete converged RHS candidate")
    cells.to_csv(campaign / "r115_rhs_cell_metrics.csv", index=False)
    eligible.to_csv(campaign / "r115_rhs_ranking.csv", index=False)
    winner = eligible.iloc[0]
    selected = {
        "stage": "R115", "status": "selected_training_only_no_bypass",
        "candidate_id": str(winner.candidate_id), "readout_mode": str(winner.readout_mode),
        "tau_multiplier": float(winner.tau_multiplier), "tau0": float(winner.tau0),
        "median_AQL_original": float(winner.median_AQL_original),
        "worst_late_AQL_scaled": float(winner.worst_late_AQL_scaled),
        "mean_coverage_10_90": float(winner.mean_coverage_10_90),
        "selection_split": "BG_fold1_training_nested_temporal_only",
        "test_opened": False,
        "next_stage": "R116_likelihood_screen_then_frozen_factorial_transfer",
    }
    write_json(campaign / "r115_selected_no_bypass.json", selected)
    return selected


def quantile_contract(
    campaign: Path,
    code_root: Path,
    *,
    stage: str,
    phase: str,
    task_id: str,
    family: str,
    design_dir: Path,
    split_csv_path: Path,
    output_dir: Path,
    tau0: float,
    seed: int,
    selection_split: str,
    al_initializer_dir: Path | None,
    axis_name: str,
    axis_value: int,
) -> dict[str, Any]:
    runtime = DATA / "runtime_libraries/exdqlm_cran_1p1p1"
    runtime_manifest = runtime / "pricefm_r67_cran111_install_manifest.json"
    value: dict[str, Any] = {
        "stage": stage, "phase": phase, "task_id": task_id, "family": family,
        axis_name: int(axis_value), "quantiles": [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90],
        "design_dir": str(design_dir.resolve()),
        "split_csv_path": str(split_csv_path.resolve()),
        "split_csv_sha256": sha256_file(split_csv_path),
        "al_initializer_dir": None if al_initializer_dir is None else str(al_initializer_dir.resolve()),
        "output_dir": str(output_dir.resolve()), "runtime_library": str(runtime.resolve()),
        "runtime_manifest": str(runtime_manifest.resolve()),
        "runtime_manifest_sha256": sha256_file(runtime_manifest),
        "adapter_path": str((code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R").resolve()),
        "rhs": {"tau0": float(tau0), "shrink_intercept": False, "freeze_tau_iters": 50, "freeze_tau_warmup_iters": 50},
        "vb": {
            "max_iter": 500, "tol": 1e-4, "n_samp": 200, "n_samp_xi": 200,
            "prior_sigma": {"a": 1, "b": 1}, "prior_gamma": {"mu0": 0, "s20": 10},
            "structured_sigmagam": {
                "factorization": "structured", "structured_grid_size": 151,
                "structured_span_sd": 6, "freeze_warmup_iters": 0,
                "force_after_warmup": True, "postwarmup_damping": 0.2,
                "postwarmup_damping_iters": 30, "min_postwarmup_updates": 35,
            },
        },
        "seed": int(seed), "selection_split": selection_split,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "mcmc_authorized": False,
        "joint_model_authorized": False,
    }
    value["task_contract_sha256"] = canonical_hash(value)
    return value


def materialize_r116_family(
    campaign: Path, code_root: Path, families: list[str] | None = None,
) -> pd.DataFrame:
    families = [str(value) for value in (families or ["al", "exal"])]
    if not families or any(value not in {"al", "exal"} for value in families):
        raise RuntimeError("R116 likelihood-family contract is invalid")
    if "exal" in families and "al" not in families:
        raise RuntimeError("R116 exAL requires the matching AL initializer family")
    design = campaign / "runs/r116_family_design/design"
    selected = json.loads((campaign / "r115_selected_no_bypass.json").read_text())
    contracts = campaign / "contracts/r116_family_fit"
    contracts.mkdir(parents=True, exist_ok=True)
    rows = []
    for family in families:
        for inner in (1, 2, 3):
            task_id = f"r116_family__{family}__inner{inner}"
            output = campaign / f"runs/r116_family_fit/family={family}/inner={inner}"
            al_output = campaign / f"runs/r116_family_fit/family=al/inner={inner}"
            contract = quantile_contract(
                campaign, code_root, stage="R116", phase="training_only_likelihood_fit",
                task_id=task_id, family=family, design_dir=design,
                split_csv_path=campaign / f"runs/r116_family_design/split_inner_{inner}.csv",
                output_dir=output, tau0=float(selected["tau0"]),
                seed=2026093000 + 100 * (family == "exal") + inner,
                selection_split="BG_fold1_training_nested_temporal_only",
                al_initializer_dir=al_output if family == "exal" else None,
                axis_name="inner_fold", axis_value=inner,
            )
            path = contracts / f"{task_id}.json"
            write_json(path, contract)
            rows.append({
                "task_id": task_id, "family": family, "inner_fold": inner,
                "contract_path": str(path), "output_dir": str(output), "fit_cells": 7,
            })
    result = pd.DataFrame(rows)
    result.to_csv(campaign / "r116_family_fit_manifest.csv", index=False)
    return result


def select_r116_family(campaign: Path) -> dict[str, Any]:
    rows = []
    for path in campaign.glob("runs/r116_family_score/family=*/inner=*/metrics.csv"):
        rows.append(pd.read_csv(path))
    metrics = pd.concat(rows, ignore_index=True)
    metrics.to_csv(campaign / "r116_family_metrics.csv", index=False)
    summary = metrics.groupby("family", as_index=False).agg(
        complete_inner_folds=("inner_fold", "nunique"), all_eligible=("eligible", "all"),
        median_AQL_scaled=("AQL_scaled", "median"),
        worst_late_AQL_scaled=("late_AQL_scaled", "max"),
        mean_coverage_10_90=("coverage_10_90", "mean"),
        mean_crossing_rate=("crossing_rate", "mean"),
    )
    summary["coverage_error"] = (summary.mean_coverage_10_90 - 0.8).abs()
    eligible = summary[summary.complete_inner_folds.eq(3) & summary.all_eligible].copy()
    eligible = eligible.sort_values(
        ["median_AQL_scaled", "worst_late_AQL_scaled", "coverage_error", "mean_crossing_rate", "family"],
        kind="mergesort",
    ).reset_index(drop=True)
    summary.to_csv(campaign / "r116_family_ranking.csv", index=False)
    if eligible.empty:
        raise RuntimeError("R116 has no complete eligible likelihood family")
    winner = eligible.iloc[0]
    selected = {
        "stage": "R116", "status": "selected_training_only_likelihood_family",
        "family": str(winner.family), "median_AQL_scaled": float(winner.median_AQL_scaled),
        "worst_late_AQL_scaled": float(winner.worst_late_AQL_scaled),
        "mean_coverage_10_90": float(winner.mean_coverage_10_90),
        "mean_crossing_rate": float(winner.mean_crossing_rate),
        "selection_split": "BG_fold1_training_nested_temporal_only",
        "selection_frozen_before_outer_validation": True, "test_opened": False,
    }
    write_json(campaign / "r116_selected_family.json", selected)
    return selected


def materialize_r116_outer(campaign: Path, code_root: Path) -> pd.DataFrame:
    selected_family = json.loads((campaign / "r116_selected_family.json").read_text())["family"]
    selected_driver = json.loads((campaign / "r114_selected_driver.json").read_text())["family"]
    selected_readout = json.loads((campaign / "r115_selected_no_bypass.json").read_text())
    contracts = campaign / "contracts/r116_outer_fit"
    contracts.mkdir(parents=True, exist_ok=True)
    rows = []
    for readout_id in ("current_lead", "selected_no_bypass"):
        needed = {"al", selected_family}
        if readout_id == "current_lead" and selected_driver in {"al", "exal"}:
            needed.add(selected_driver)
        for family in sorted(needed, key=lambda value: (value != "al", value)):
            for fold in (1, 2, 3):
                design_root = campaign / f"runs/r116_outer_design/fold={fold}/{readout_id}"
                task_id = f"r116_outer__{readout_id}__{family}__fold{fold}"
                output = campaign / f"runs/r116_outer_fit/readout={readout_id}/family={family}/fold={fold}"
                al_output = campaign / f"runs/r116_outer_fit/readout={readout_id}/family=al/fold={fold}"
                tau0 = 1e-4 if readout_id == "current_lead" else float(selected_readout["tau0"])
                contract = quantile_contract(
                    campaign, code_root, stage="R116", phase="outer_transfer_readout_fit",
                    task_id=task_id, family=family, design_dir=design_root / "design",
                    split_csv_path=design_root / "full_training_split.csv", output_dir=output,
                    tau0=tau0, seed=2026093100 + 1000 * (readout_id == "selected_no_bypass")
                    + 100 * (family == "exal") + fold,
                    selection_split="BG_outer_fold_training_only",
                    al_initializer_dir=al_output if family == "exal" else None,
                    axis_name="fold", axis_value=fold,
                )
                path = contracts / f"{task_id}.json"
                write_json(path, contract)
                rows.append({
                    "task_id": task_id, "readout_id": readout_id, "family": family,
                    "fold": fold, "contract_path": str(path), "output_dir": str(output),
                    "fit_cells": 7,
                })
    result = pd.DataFrame(rows)
    result.to_csv(campaign / "r116_outer_fit_manifest.csv", index=False)
    return result


def load_r111b_contextual_references(root: Path | None = None) -> pd.DataFrame:
    root = R111B if root is None else root
    case_path = root / "pricefm_stage_r111b_bg_case_metrics.csv"
    reference_path = root / "pricefm_stage_r111b_bg_references.csv"
    missing = [str(path) for path in (case_path, reference_path) if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"missing frozen R111B contextual evidence: {missing}")
    cases = pd.read_csv(case_path).assign(reference="R111B")
    references = pd.read_csv(reference_path)
    if "policy" not in references.columns:
        raise RuntimeError(f"R111B reference table has no policy column: {reference_path}")
    return pd.concat([
        cases,
        references.assign(reference=references["policy"]),
    ], ignore_index=True, sort=False)


def closeout_r116(campaign: Path) -> dict[str, Any]:
    metrics = pd.concat([
        pd.read_csv(campaign / f"runs/r116_outer_score/fold={fold}/metrics.csv")
        for fold in (1, 2, 3)
    ], ignore_index=True)
    horizons = pd.concat([
        pd.read_csv(campaign / f"runs/r116_outer_score/fold={fold}/horizon_metrics.csv")
        for fold in (1, 2, 3)
    ], ignore_index=True)
    metrics.to_csv(campaign / "r116_factorial_metrics.csv", index=False)
    horizons.to_csv(campaign / "r116_factorial_horizon_metrics.csv", index=False)
    pooled = metrics.groupby("cell", as_index=False).apply(
        lambda frame: pd.Series({
            "AQL": np.average(frame.AQL, weights=frame.n_loss_atoms),
            "AQCR": np.average(frame.AQCR, weights=frame.n_loss_atoms),
            "coverage_10_90": np.average(frame.coverage_10_90, weights=frame.n_loss_atoms),
            "width_10_90": np.average(frame.width_10_90, weights=frame.n_loss_atoms),
            "n_loss_atoms": frame.n_loss_atoms.sum(),
        }), include_groups=False,
    ).reset_index(drop=True)
    pooled.to_csv(campaign / "r116_factorial_pooled_metrics.csv", index=False)
    a = float(pooled.loc[pooled.cell.eq("A"), "AQL"].iloc[0])
    d = float(pooled.loc[pooled.cell.eq("D"), "AQL"].iloc[0])
    fold_wins = int(sum(
        metrics.loc[metrics.fold.eq(fold) & metrics.cell.eq("D"), "AQL"].iloc[0]
        < metrics.loc[metrics.fold.eq(fold) & metrics.cell.eq("A"), "AQL"].iloc[0]
        for fold in (1, 2, 3)
    ))
    late = horizons[horizons.horizon_block.eq("73-96")]
    late_a = float(np.average(late.loc[late.cell.eq("A"), "AQL"], weights=late.loc[late.cell.eq("A"), "n_loss_atoms"]))
    late_d = float(np.average(late.loc[late.cell.eq("D"), "AQL"], weights=late.loc[late.cell.eq("D"), "n_loss_atoms"]))
    coverage_a = float(pooled.loc[pooled.cell.eq("A"), "coverage_10_90"].iloc[0])
    coverage_d = float(pooled.loc[pooled.cell.eq("D"), "coverage_10_90"].iloc[0])
    width_a = float(pooled.loc[pooled.cell.eq("A"), "width_10_90"].iloc[0])
    width_d = float(pooled.loc[pooled.cell.eq("D"), "width_10_90"].iloc[0])
    gates = pd.DataFrame([
        {"gate": "pooled_D_beats_A", "passed": d < a, "value": d - a, "threshold": 0.0},
        {"gate": "D_beats_A_in_two_folds", "passed": fold_wins >= 2, "value": fold_wins, "threshold": 2},
        {"gate": "late_73_96_no_more_than_2pct_worse", "passed": late_d <= 1.02 * late_a, "value": late_d / late_a - 1, "threshold": 0.02},
        {"gate": "coverage_error_not_worse_by_2pp", "passed": abs(coverage_d - 0.8) <= abs(coverage_a - 0.8) + 0.02, "value": abs(coverage_d - 0.8) - abs(coverage_a - 0.8), "threshold": 0.02},
        {"gate": "interval_width_not_collapsed", "passed": width_d >= 0.8 * width_a, "value": width_d / width_a, "threshold": 0.8},
    ])
    gates.to_csv(campaign / "r116_transfer_gates.csv", index=False)
    references = load_r111b_contextual_references()
    references.to_csv(campaign / "r116_contextual_references.csv", index=False)
    authorized = bool(gates.passed.all())
    selected = json.loads((campaign / "r116_selected_family.json").read_text())
    selected_driver = json.loads((campaign / "r114_selected_driver.json").read_text())["family"]
    driver_contrast_identifiable = selected_driver != "normal_rhs"
    if not driver_contrast_identifiable:
        metric_columns = ["AQL", "AQCR", "coverage_10_90", "width_10_90"]
        indexed = metrics.set_index(["fold", "cell"])
        for left, right in (("A", "B"), ("C", "D")):
            left_values = indexed.xs(left, level="cell")[metric_columns].sort_index().to_numpy()
            right_values = indexed.xs(right, level="cell")[metric_columns].sort_index().to_numpy()
            if not np.allclose(left_values, right_values, rtol=0.0, atol=1e-12):
                raise RuntimeError(
                    f"selected Normal RHS driver requires {left}={right}, but metrics differ"
                )
    summary = {
        "stage": "R116", "status": "completed_r116_factorial_closeout",
        "selected_family": selected["family"], "cell_A_pooled_AQL": a,
        "cell_D_pooled_AQL": d, "cell_D_minus_A": d - a,
        "cell_D_fold_wins": fold_wins,
        "transfer_gates_passed": int(gates.passed.sum()),
        "transfer_gates_total": int(len(gates)),
        "all_transfer_gates_passed": authorized,
        "selected_driver_family": selected_driver,
        "driver_contrast_identifiable": driver_contrast_identifiable,
        "mechanism_interpretation": (
            "driver_and_readout_factorial"
            if driver_contrast_identifiable else "readout_only_driver_axis_degenerate"
        ),
        "r117_preparation_authorized": authorized, "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
        "mcmc_fitted": False, "joint_model_fitted": False,
    }
    write_json(campaign / "r116_closeout_summary.json", summary)
    report = [
        "# PriceFM Stage R116 closeout", "",
        f"- Selected likelihood: `{selected['family']}`.",
        f"- Frozen control Cell A pooled AQL: `{a:.6f}`.",
        f"- Prespecified bridge Cell D pooled AQL: `{d:.6f}`.",
        f"- Cell D minus Cell A: `{d - a:.6f}`.",
        f"- Fold wins for Cell D: `{fold_wins}/3`.",
        f"- Transfer gates passed: `{int(gates.passed.sum())}/{len(gates)}`.",
        f"- All transfer gates passed: `{str(authorized).lower()}`.",
        f"- Selected driver family: `{selected_driver}`.",
        f"- Driver contrast identifiable: `{str(driver_contrast_identifiable).lower()}`.",
        "- When the selected driver is Normal RHS, A=B and C=D; the realized contrast is readout-only.",
        "- Registry, article, MCMC, joint-model, and all-region work remained blocked.",
    ]
    (campaign / "r116_closeout.md").write_text("\n".join(report) + "\n")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_CAMPAIGN)
    parser.add_argument("--code-root", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=30)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()
    campaign = args.campaign_root.resolve(); code_root = args.code_root.resolve()
    contract, cpus = preflight(campaign, code_root, args.workers)
    if args.preflight_only:
        write_json(campaign / "preflight_terminal.json", {
            "stage": "R113_R116", "status": "preflight_passed_not_launched",
            "workers": len(cpus), "selected_logical_cpus": cpus, "test_opened": False,
        })
        return 0
    worker_module_path = code_root / "application/scripts/pricefm/391_run_pricefm_stage_r113_r116_campaign.py"
    spec = importlib.util.spec_from_file_location("r113_worker", worker_module_path)
    if spec is None or spec.loader is None:
        raise ImportError(worker_module_path)
    worker_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker_module)
    python = sys.executable

    resume_mode = contract.get("resume_mode")
    reuse_completed_r114 = resume_mode in {
        "reuse_completed_r114_fits", "reuse_completed_calendar_aligned_R114",
    }
    calendar_recovery = resume_mode == "reuse_R114_then_refit_aligned_neighbors"
    if not reuse_completed_r114:
        normal_tasks = []
        for row in pd.read_csv(campaign / "r114_normal_driver_manifest.csv").itertuples(index=False):
            output = Path(row.output_dir)
            if not valid_terminal(output, "completed_r114_normal_driver"):
                normal_tasks.append({
                    "task_id": row.task_id,
                    "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/390_run_pricefm_stage_r114_normal_driver.R"), "--contract", row.contract_path],
                    "log_path": campaign / f"logs/r114_normal/{row.task_id}.log",
                })
        al_tasks = []
        if not calendar_recovery:
            fit_manifest = pd.read_csv(campaign / "r114_fit_manifest.csv")
            for row in fit_manifest[fit_manifest.family.eq("al")].itertuples(index=False):
                if not valid_terminal(Path(row.output_dir), "completed_r114_quantile_family_fit"):
                    al_tasks.append({
                        "task_id": row.task_id,
                        "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R"), "--contract", row.contract_path],
                        "log_path": campaign / f"logs/r114_fit/{row.task_id}.log",
                    })
        run_parallel(normal_tasks + al_tasks, cpus, campaign / "r114_batch1_status.csv")

        if not calendar_recovery:
            exal_tasks = []
            for row in fit_manifest[fit_manifest.family.eq("exal")].itertuples(index=False):
                if not valid_terminal(Path(row.output_dir), "completed_r114_quantile_family_fit"):
                    exal_tasks.append({
                        "task_id": row.task_id,
                        "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R"), "--contract", row.contract_path],
                        "log_path": campaign / f"logs/r114_fit/{row.task_id}.log",
                    })
            run_parallel(exal_tasks, cpus, campaign / "r114_batch2_status.csv")
    if calendar_recovery or resume_mode == "reuse_completed_calendar_aligned_R114":
        verify_aligned_neighbor_drivers(campaign)

    _, eligible_families = r114_family_eligibility(
        campaign, worker_module, [str(value) for value in contract.get("families", ["al", "exal"])],
    )
    contracted_score_families = contract.get("r114_score_families")
    if contracted_score_families is not None and eligible_families != list(contracted_score_families):
        raise RuntimeError(
            f"R114 eligible families differ from recovery contract: "
            f"observed={eligible_families} expected={contracted_score_families}"
        )

    score_tasks = []
    for family in eligible_families:
        for inner in (1, 2, 3):
            output = campaign / f"runs/r114_score/family={family}/inner={inner}"
            if not valid_terminal(output, "completed_r114_driver_score"):
                task_id = f"r114_score__{family}__inner{inner}"
                score_tasks.append({
                    "task_id": task_id,
                    "command": [python, str(worker_module_path), "r114-score", "--campaign-root", str(campaign), "--family", family, "--inner-fold", str(inner)],
                    "log_path": campaign / f"logs/r114_score/{task_id}.log",
                })
    run_parallel(score_tasks, cpus, campaign / "r114_score_status.csv")
    selected_driver = select_r114(campaign, worker_module, eligible_families)

    ridge_tasks = []
    for candidate_id in pd.read_csv(campaign / "r115_candidate_bank.csv").candidate_id.astype(str):
        output = campaign / f"runs/r115_ridge/candidate={candidate_id}"
        if not valid_terminal(output, "completed_r115_ridge_candidate"):
            ridge_tasks.append({
                "task_id": f"r115_ridge__{candidate_id}",
                "command": [python, str(worker_module_path), "r115-ridge", "--campaign-root", str(campaign), "--candidate-id", candidate_id],
                "log_path": campaign / f"logs/r115_ridge/{candidate_id}.log",
            })
    run_parallel(ridge_tasks, cpus, campaign / "r115_ridge_status.csv")
    rhs_manifest = materialize_rhs(campaign, code_root)
    rhs_tasks = []
    for row in rhs_manifest.itertuples(index=False):
        if not valid_terminal(Path(row.output_dir), "completed_r115_rhs_cell"):
            rhs_tasks.append({
                "task_id": row.task_id,
                "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/393_run_pricefm_stage_r115_rhs_cell.R"), "--contract", row.contract_path],
                "log_path": campaign / f"logs/r115_rhs/{row.task_id}.log",
            })
    run_parallel(rhs_tasks, cpus, campaign / "r115_rhs_status.csv")
    selected_readout = select_r115(campaign)

    family_design = campaign / "runs/r116_family_design"
    family_design_tasks = []
    if not valid_terminal(family_design, "completed_r116_family_design"):
        family_design_tasks.append({
            "task_id": "r116_family_design",
            "command": [python, str(worker_module_path), "r116-family-design", "--campaign-root", str(campaign)],
            "log_path": campaign / "logs/r116_family/r116_family_design.log",
        })
    run_parallel(family_design_tasks, cpus, campaign / "r116_family_design_status.csv")
    r116_families = [str(value) for value in contract.get("r116_families", ["al", "exal"])]
    family_manifest = materialize_r116_family(campaign, code_root, r116_families)
    for family in r116_families:
        tasks = []
        for row in family_manifest[family_manifest.family.eq(family)].itertuples(index=False):
            if not valid_terminal(Path(row.output_dir), "completed_r116_quantile_family_fit"):
                tasks.append({
                    "task_id": row.task_id,
                    "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R"), "--contract", row.contract_path],
                    "log_path": campaign / f"logs/r116_family/{row.task_id}.log",
                })
        run_parallel(tasks, cpus, campaign / f"r116_family_{family}_status.csv")
    family_score_tasks = []
    for family in r116_families:
        for inner in (1, 2, 3):
            output = campaign / f"runs/r116_family_score/family={family}/inner={inner}"
            if not valid_terminal(output, "completed_r116_family_score"):
                task_id = f"r116_family_score__{family}__inner{inner}"
                family_score_tasks.append({
                    "task_id": task_id,
                    "command": [python, str(worker_module_path), "r116-family-score", "--campaign-root", str(campaign), "--family", family, "--inner-fold", str(inner)],
                    "log_path": campaign / f"logs/r116_family/{task_id}.log",
                })
    run_parallel(family_score_tasks, cpus, campaign / "r116_family_score_status.csv")
    selected_family = select_r116_family(campaign)

    outer_design_tasks = []
    for fold in (1, 2, 3):
        output = campaign / f"runs/r116_outer_design/fold={fold}"
        if not valid_terminal(output, "completed_r116_outer_design"):
            task_id = f"r116_outer_design__fold{fold}"
            outer_design_tasks.append({
                "task_id": task_id,
                "command": [python, str(worker_module_path), "r116-outer-design", "--campaign-root", str(campaign), "--fold", str(fold)],
                "log_path": campaign / f"logs/r116_outer/{task_id}.log",
            })
    run_parallel(outer_design_tasks, cpus, campaign / "r116_outer_design_status.csv")
    outer_manifest = materialize_r116_outer(campaign, code_root)
    for family in outer_manifest.family.astype(str).drop_duplicates().tolist():
        tasks = []
        for row in outer_manifest[outer_manifest.family.eq(family)].itertuples(index=False):
            if not valid_terminal(Path(row.output_dir), "completed_r116_quantile_family_fit"):
                tasks.append({
                    "task_id": row.task_id,
                    "command": [str(RSCRIPT), str(code_root / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R"), "--contract", row.contract_path],
                    "log_path": campaign / f"logs/r116_outer/{row.task_id}.log",
                })
        run_parallel(tasks, cpus, campaign / f"r116_outer_{family}_status.csv")
    outer_score_tasks = []
    for fold in (1, 2, 3):
        output = campaign / f"runs/r116_outer_score/fold={fold}"
        if not valid_terminal(output, "completed_r116_outer_score"):
            task_id = f"r116_outer_score__fold{fold}"
            outer_score_tasks.append({
                "task_id": task_id,
                "command": [python, str(worker_module_path), "r116-outer-score", "--campaign-root", str(campaign), "--fold", str(fold)],
                "log_path": campaign / f"logs/r116_outer/{task_id}.log",
            })
    run_parallel(outer_score_tasks, cpus, campaign / "r116_outer_score_status.csv")
    closeout = closeout_r116(campaign)
    terminal = {
        "stage": "R113_R116", "status": "completed_r116_factorial_closeout",
        "selected_driver": selected_driver, "selected_readout": selected_readout,
        "selected_family": selected_family, "r116_closeout": closeout,
        "workers": len(cpus), "test_opened": False, "registry_mutated": False,
        "article_mutated": False, "mcmc_fitted": False, "joint_model_fitted": False,
    }
    write_json(campaign / "controller_terminal.json", terminal)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
