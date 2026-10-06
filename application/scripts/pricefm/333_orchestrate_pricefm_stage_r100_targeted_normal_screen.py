#!/usr/bin/env python3
"""Run the resumable R100 targeted normal Ridge-to-RHS campaign."""

from __future__ import annotations

import argparse
import copy
from concurrent.futures import ThreadPoolExecutor, as_completed
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
import threading
import time
from typing import Any

import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file
from pricefm_region_frozen_contract import atomic_write_json, git_identity


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
PREP = DATA / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
MATERIALIZE = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
RUN_MODEL = SCRIPT_DIR / "10_run_desn_model_full.py"
BUILD_WINDOWS = SCRIPT_DIR / "05_build_windows.py"
APPROVAL = "RUN_PRICEFM_R100_TARGETED_NORMAL_RECOVERY"
DEFAULT_CPUS = list(range(0, 25)) + list(range(32, 57))
DEFAULT_MINIMUM_FREE_GIB = 250.0
DEFAULT_MINIMUM_MEMORY_GIB = 64.0
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)
GRID_BLOCK = "pricefm_desn_experiment_grid"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--workers", type=int, default=50)
    p.add_argument("--cpu-list", default="0-24,32-56")
    p.add_argument("--approval-token", required=True)
    p.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    p.add_argument("--minimum-free-gib", type=float, default=DEFAULT_MINIMUM_FREE_GIB)
    p.add_argument("--minimum-memory-gib", type=float, default=DEFAULT_MINIMUM_MEMORY_GIB)
    p.add_argument("--preflight-only", action="store_true")
    return p


def _load(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_cpus(value: str) -> list[int]:
    cpus = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lo, hi = (int(x) for x in token.split("-", 1))
            cpus.extend(range(lo, hi + 1))
        else:
            cpus.append(int(token))
    if len(cpus) != len(set(cpus)) or any(x < 0 or x >= (os.cpu_count() or 0) for x in cpus):
        raise RuntimeError("CPU list is duplicated or outside the online CPU range")
    return cpus


def physical_core(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())


def validate_physical_pairing(cpus: list[int]) -> dict[str, Any]:
    counts: dict[tuple[int, int], int] = {}
    for cpu in cpus:
        counts[physical_core(cpu)] = counts.get(physical_core(cpu), 0) + 1
    if len(counts) != 25 or set(counts.values()) != {2}:
        raise RuntimeError("R100 requires both logical siblings from exactly 25 physical cores")
    return {f"package{package}_core{core}": count for (package, core), count in sorted(counts.items())}


def cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        out = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(x) for x in fields[1:]]
                out[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
        return out
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100 * (1 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        if after[cpu][0] > total else 100.0
        for cpu, (total, idle) in before.items()
    }


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def ensure_runtime_capacity(
    minimum_free_gib: float = DEFAULT_MINIMUM_FREE_GIB,
    minimum_memory_gib: float = DEFAULT_MINIMUM_MEMORY_GIB,
) -> dict[str, float]:
    free_disk_gib = shutil.disk_usage(DATA).free / 1024**3
    available_gib = available_memory_gib()
    if free_disk_gib < minimum_free_gib or available_gib < minimum_memory_gib:
        raise RuntimeError(
            "R100 runtime resource floor failed: "
            f"disk={free_disk_gib:.1f} GiB, memory={available_gib:.1f} GiB"
        )
    return {"free_disk_gib": free_disk_gib, "available_memory_gib": available_gib}


def environment() -> dict[str, str]:
    env = dict(os.environ)
    for name in THREAD_ENV:
        env[name] = "1"
    return env


def command(values: list[Any], *, cwd: Path, log: Path, cpu: int | None = None) -> None:
    args = [str(x) for x in values]
    if cpu is not None:
        args = ["taskset", "-c", str(cpu), *args]
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as handle:
        handle.write("$ " + " ".join(args) + "\n")
        handle.flush()
        result = subprocess.run(args, cwd=cwd, env=environment(), stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}); see {log}")


def valid_marker(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text())
        return data.get("status") == "completed_compacted" and all(
            Path(row["path"]).is_file() and sha256_file(row["path"]) == row["sha256"]
            for row in data.get("retained", [])
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def _record(path: Path, role: str) -> dict[str, Any]:
    return {"role": role, "path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def compact(row: Any, region: str, folds: list[int]) -> None:
    run_dir = Path(row.run_dir)
    retained = []
    for fold in folds:
        cell = run_dir / f"cells/region={region}/fold={fold}"
        model = cell / "model"
        metric = model / "metric_summary.csv"
        method = model / "model_method_summary.csv"
        for path in (metric, method):
            if not path.is_file() or path.stat().st_size == 0:
                raise RuntimeError(f"missing screening result: {path}")
        metrics = pd.read_csv(metric)
        if metrics.split.astype(str).str.lower().eq("test").any():
            raise RuntimeError(f"test row entered R100: {metric}")
        retained.extend([_record(metric, f"fold{fold}_metric"), _record(method, f"fold{fold}_method")])
        adapter = cell / "adapter"
        if adapter.exists():
            shutil.rmtree(adapter)
        for path in list(model.iterdir()):
            if path.name not in {"metric_summary.csv", "model_method_summary.csv"}:
                shutil.rmtree(path) if path.is_dir() else path.unlink()
    atomic_write_json(run_dir / "r100_compaction_terminal.json", {
        "status": "completed_compacted", "experiment_id": str(row.id),
        "region": region, "folds": folds, "retained": retained,
        "binary_model_artifacts_retained": False, "test_opened": False,
    })


def materialize_all(launch: pd.DataFrame, code_root: Path, campaign: Path) -> pd.DataFrame:
    manifests = []
    for row in launch.itertuples(index=False):
        generated = Path(row.generated_root)
        manifest = generated / "manifest.csv"
        if not manifest.is_file():
            command([PYTHON, MATERIALIZE, "--grid-config", row.grid_path, "--write", "--output-root", generated], cwd=code_root, log=campaign / f"logs/materialize_ridge_{row.region}.log")
        frame = pd.read_csv(manifest)
        frame["campaign_region"] = str(row.region)
        manifests.append(frame)
    return pd.concat(manifests, ignore_index=True)


def verify_or_build_windows(manifest: pd.DataFrame, code_root: Path, campaign: Path) -> None:
    marker = campaign / "preprocessing_reuse_terminal.json"
    if marker.is_file():
        return
    configs = manifest.drop_duplicates("lag_window").sort_values("lag_window")
    first_data = yaml.safe_load(Path(manifest.iloc[0].data_config).read_text())
    regions = [str(x) for x in first_data["pricefm"]["regions"]]
    for row in configs.itertuples(index=False):
        command([
            PYTHON, BUILD_WINDOWS, "--config", row.data_config,
            "--pilot-only", "true", "--regions", ",".join(regions),
            "--folds", "101,102,103", "--resume", "true", "--force", "false",
        ], cwd=code_root, log=campaign / f"logs/verify_windows_lag{int(row.lag_window)}.log")
    atomic_write_json(marker, {
        "status": "completed", "mode": "hashable_R97_processed_inner_reuse",
        "lags": sorted(manifest.lag_window.astype(int).unique().tolist()),
        "regions": regions, "test_opened": False,
    })


def run_queue(manifest: pd.DataFrame, cpus: list[int], code_root: Path, campaign: Path, stage: str) -> dict[str, int]:
    tasks = []
    for row in manifest.itertuples(index=False):
        region = str(row.campaign_region)
        folds = [int(x) for x in json.loads(row.folds)]
        marker = Path(row.run_dir) / "r100_compaction_terminal.json"
        if valid_marker(marker):
            continue
        tasks.append((row, region, folds))
    state_lock = threading.Lock()
    complete = int(len(manifest) - len(tasks))
    failures = 0
    progress = {"complete": complete, "failed": 0}

    buckets = [[] for _ in cpus]
    for index, task in enumerate(tasks):
        buckets[index % len(cpus)].append(task)

    def worker(cpu: int, bucket: list[Any]) -> tuple[int, int]:
        local_complete = 0
        local_failures = 0
        for row, region, folds in bucket:
            log = campaign / f"logs/{stage}/{region}/{row.id}.log"
            try:
                ensure_runtime_capacity()
                command([
                    PYTHON, RUN_MODEL, "--config", row.full_config, "--jobs", "1",
                    "--resume", "true", "--force", "false", "--dry-run", "false",
                    "--regions", region, "--folds", ",".join(map(str, folds)),
                ], cwd=code_root, log=log, cpu=cpu)
                compact(row, region, folds)
                local_complete += 1
            except Exception as error:
                local_failures += 1
                run_dir = Path(row.run_dir)
                run_dir.mkdir(parents=True, exist_ok=True)
                atomic_write_json(run_dir / "r100_failure_terminal.json", {
                    "status": "failed_closed", "experiment_id": str(row.id),
                    "region": region, "error": repr(error), "log": str(log),
                })
            with state_lock:
                if valid_marker(Path(row.run_dir) / "r100_compaction_terminal.json"):
                    progress["complete"] += 1
                else:
                    progress["failed"] += 1
                atomic_write_json(campaign / f"{stage}_progress.json", {
                    "stage": stage, "completed_before_resume": complete,
                    "complete": progress["complete"], "failed": progress["failed"],
                    "total": len(manifest), "updated_at_epoch": time.time(),
                })
        return local_complete, local_failures

    with ThreadPoolExecutor(max_workers=len(cpus)) as pool:
        futures = [pool.submit(worker, cpu, bucket) for cpu, bucket in zip(cpus, buckets) if bucket]
        for future in as_completed(futures):
            done, failed = future.result()
            complete += done
            failures += failed
    actual = sum(valid_marker(Path(path) / "r100_compaction_terminal.json") for path in manifest.run_dir)
    return {"complete": int(actual), "failed": int(failures), "total": int(len(manifest))}


def tau_reference(r98_tau0: float, r98_features: int, candidate_features: int) -> float:
    if min(r98_tau0, r98_features, candidate_features) <= 0:
        raise ValueError("tau reference inputs must be positive")
    return float(r98_tau0 * math.sqrt(r98_features / candidate_features))


def prepare_rhs(launch: pd.DataFrame, code_root: Path, campaign: Path) -> pd.DataFrame:
    advance = _load(SCRIPT_DIR / "292_advance_pricefm_stage_r93_ridge_to_rhs.py", "r100_ridge_reader")
    all_manifests = []
    for launch_row in launch.itertuples(index=False):
        region = str(launch_row.region)
        prep = Path(launch_row.candidate_manifest).parent
        candidates = pd.read_csv(launch_row.candidate_manifest)
        ridge_manifest = pd.read_csv(Path(launch_row.generated_root) / "manifest.csv")
        cells, _ = advance.collect_ridge_results(candidates, ridge_manifest, [101, 102, 103], region)
        ranked = advance.rank_candidates(candidates, cells)
        selected = ranked.head(int(launch_row.ridge_top_k)).copy()
        closeout = campaign / f"regions/{region}/ridge_closeout"
        closeout.mkdir(parents=True, exist_ok=True)
        cells.to_csv(closeout / "pricefm_stage_r100_ridge_cell_metrics.csv", index=False)
        ranked.to_csv(closeout / "pricefm_stage_r100_ridge_ranking.csv", index=False)
        selected.to_csv(closeout / "pricefm_stage_r100_ridge_top30.csv", index=False)

        source_grid = yaml.safe_load(Path(launch_row.grid_path).read_text())
        experiments = {str(x["id"]): x for x in source_grid[GRID_BLOCK]["experiments"]}
        base_data = yaml.safe_load(Path(source_grid[GRID_BLOCK]["base"]["data_config"]).read_text())
        base_full = yaml.safe_load(Path(source_grid[GRID_BLOCK]["base"]["full_config"]).read_text())
        rhs_prep = campaign / f"regions/{region}/rhs_prep"
        rhs_generated = campaign / f"regions/{region}/rhs_generated"
        rhs_runs = campaign / f"regions/{region}/rhs_runs"
        rhs_prep.mkdir(parents=True, exist_ok=True)
        data_path = rhs_prep / "data.yaml"
        full_path = rhs_prep / "full.yaml"
        with data_path.open("w") as handle:
            yaml.safe_dump(base_data, handle, sort_keys=False)
        full = base_full["pricefm_desn_full"]
        full["data_config"] = str(data_path)
        full["normal"].update({"enabled": True, "prior_types": ["rhs_ns"], "predictive_quantile_mode": "analytic_normal"})
        full["qdesn_vb"]["enabled"] = False
        with full_path.open("w") as handle:
            yaml.safe_dump(base_full, handle, sort_keys=False)

        arms = []
        rhs_experiments = []
        for item in selected.itertuples(index=False):
            tau_ref = tau_reference(float(launch_row.r98_tau0), int(launch_row.r98_observed_readout_features), int(item.n_state_features))
            for multiplier in (0.25, 1.0, 4.0):
                tau0 = tau_ref * multiplier
                fingerprint = hashlib.sha256(f"{item.candidate_id}|{tau0:.17g}".encode()).hexdigest()
                experiment_id = f"r100_{region.lower().replace('_', '')}_rhs_r{int(item.ridge_rank):02d}_m{multiplier:g}_{fingerprint[:10]}"
                exp = copy.deepcopy(experiments[str(item.candidate_id)])
                exp.update({
                    "id": experiment_id, "stage": "pricefm_stage_r100_targeted_normal_rhs",
                    "tau0": tau0,
                    "normal": {"enabled": True, "prior_types": ["rhs_ns"], "predictive_quantile_mode": "analytic_normal"},
                    "qdesn_vb": {"enabled": False}, "exact_equivalence": {"enabled": False},
                    "stage_r93_parent_ridge_candidate_id": str(item.candidate_id),
                    "stage_r93_ridge_rank": int(item.ridge_rank),
                    "stage_r93_rhs_tau0_phase": "design_size_adjusted_coarse",
                    "rationale": "R100 design-size-adjusted normal RHS screen on inner validation only.",
                })
                rhs_experiments.append(exp)
                arms.append({
                    "experiment_id": experiment_id, "parent_ridge_candidate_id": item.candidate_id,
                    "region": region, "ridge_rank": int(item.ridge_rank),
                    "feature_policy": item.feature_policy, "lag_window": int(item.lag_window),
                    "depth": int(item.depth), "units": item.units, "alpha": float(item.alpha),
                    "rho": float(item.rho), "input_scale": float(item.input_scale),
                    "state_output": item.state_output, "seed": int(item.seed),
                    "candidate_readout_features": int(item.n_state_features),
                    "r98_readout_features": int(launch_row.r98_observed_readout_features),
                    "r98_tau0": float(launch_row.r98_tau0), "tau_multiplier": multiplier,
                    "tau_ref": tau_ref, "tau0": tau0, "test_access_authorized": False,
                })
        grid = copy.deepcopy(source_grid)
        block = grid[GRID_BLOCK]
        block["grid_id"] = f"pricefm_stage_r100_targeted_normal_rhs_{region.lower()}_20260913"
        block["purpose"] = "Ridge-top30 design-size-adjusted normal RHS screen; train/validation only."
        block["base"] = {"data_config": str(data_path), "full_config": str(full_path), "generated_root": str(rhs_generated), "run_root": str(rhs_runs)}
        block["fixed"]["normal"] = {"enabled": True, "prior_types": ["rhs_ns"], "predictive_quantile_mode": "analytic_normal"}
        block["fixed"]["qdesn_vb"] = {"enabled": False}
        block["experiments"] = rhs_experiments
        block["experiment_blocks"] = []
        grid_path = rhs_prep / "pricefm_stage_r100_rhs_grid.yaml"
        with grid_path.open("w") as handle:
            yaml.safe_dump(grid, handle, sort_keys=False)
        pd.DataFrame(arms).to_csv(rhs_prep / "pricefm_stage_r100_rhs_manifest.csv", index=False)
        manifest_path = rhs_generated / "manifest.csv"
        if not manifest_path.is_file():
            command([PYTHON, MATERIALIZE, "--grid-config", grid_path, "--write", "--output-root", rhs_generated], cwd=code_root, log=campaign / f"logs/materialize_rhs_{region}.log")
        manifest = pd.read_csv(manifest_path)
        manifest["campaign_region"] = region
        all_manifests.append(manifest)
    return pd.concat(all_manifests, ignore_index=True)


def close_rhs(launch: pd.DataFrame, rhs_manifest: pd.DataFrame, campaign: Path) -> dict[str, int]:
    winners = []
    failures = []
    for launch_row in launch.itertuples(index=False):
        region = str(launch_row.region)
        rows = rhs_manifest[rhs_manifest.campaign_region.eq(region)]
        arms = pd.read_csv(campaign / f"regions/{region}/rhs_prep/pricefm_stage_r100_rhs_manifest.csv")
        metrics = []
        for row in rows.itertuples(index=False):
            fold_values = []
            converged = True
            n_features = 0
            for fold in (101, 102, 103):
                model = Path(row.run_dir) / f"cells/region={region}/fold={fold}/model"
                metric = pd.read_csv(model / "metric_summary.csv")
                method = pd.read_csv(model / "model_method_summary.csv")
                selected = metric[(metric.method_id == "normal_rhs_ns") & (metric.split == "val") & (metric.unit == "original")]
                fitted = method[method.method_id == "normal_rhs_ns"]
                if len(selected) != 1 or len(fitted) != 1:
                    converged = False
                    break
                value = float(selected.iloc[0].AQL)
                converged = converged and str(fitted.iloc[0].converged).lower() in {"true", "1"} and math.isfinite(value)
                fold_values.append(value)
                n_features = max(n_features, int(fitted.iloc[0].n_features))
            metrics.append({
                "experiment_id": str(row.id), "region": region,
                "median_validation_AQL": float(pd.Series(fold_values).median()) if fold_values else math.nan,
                "max_validation_AQL": max(fold_values) if fold_values else math.nan,
                "sd_validation_AQL": float(pd.Series(fold_values).std()) if len(fold_values) == 3 else math.nan,
                "n_features": n_features, "n_inner_folds": len(fold_values), "converged": converged,
            })
        ranked = pd.DataFrame(metrics).merge(arms, on=["experiment_id", "region"], validate="one_to_one")
        ranked["eligible"] = ranked.converged & ranked.n_inner_folds.eq(3) & ranked.median_validation_AQL.map(math.isfinite)
        ranked = ranked.sort_values(["eligible", "median_validation_AQL", "max_validation_AQL", "sd_validation_AQL", "n_features", "experiment_id"], ascending=[False, True, True, True, True, True], kind="stable")
        ranked.insert(0, "rhs_rank", range(1, len(ranked) + 1))
        closeout = campaign / f"regions/{region}/rhs_closeout"
        closeout.mkdir(parents=True, exist_ok=True)
        ranked.to_csv(closeout / "pricefm_stage_r100_rhs_ranking.csv", index=False)
        eligible = ranked[ranked.eligible]
        if eligible.empty:
            failures.append(region)
            continue
        winner = eligible.iloc[0].to_dict()
        winner.update({
            "status": "provisional_normal_winner_frozen", "stage": "R100",
            "selection_uses_test": False, "quantile_fit_authorized": False,
            "test_scoring_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
        contract = closeout / "pricefm_stage_r100_frozen_normal_contract.json"
        write = {k: (v.item() if hasattr(v, "item") else v) for k, v in winner.items()}
        atomic_write_json(contract, write)
        winners.append({"region": region, "contract": str(contract), "experiment_id": winner["experiment_id"], "validation_AQL": winner["median_validation_AQL"], "tau0": winner["tau0"]})
    pd.DataFrame(winners).to_csv(campaign / "pricefm_stage_r100_frozen_normal_winners.csv", index=False)
    atomic_write_json(campaign / "campaign_terminal.json", {
        "stage": "R100", "status": "completed_normal_winners_frozen" if not failures else "completed_with_region_failures",
        "regions_complete": len(winners), "regions_failed": failures,
        "test_opened": False, "quantile_fit_started": False,
        "registry_mutated": False, "article_mutated": False,
    })
    return {"regions_complete": len(winners), "regions_failed": len(failures)}


def preflight(args: argparse.Namespace) -> tuple[list[int], pd.DataFrame, dict[str, Any]]:
    if args.approval_token != APPROVAL:
        raise RuntimeError(f"R100 requires --approval-token {APPROVAL}")
    cpus = parse_cpus(args.cpu_list)
    if args.workers != 50 or cpus != DEFAULT_CPUS:
        raise RuntimeError("R100 production launch requires CPU set 0-24,32-56 and 50 workers")
    pairing = validate_physical_pairing(cpus)
    identity = git_identity(args.code_root.resolve())
    if not identity.clean or identity.head != identity.upstream_head or not identity.branch.startswith("work/pricefm-"):
        raise RuntimeError("R100 launch requires a clean synchronized PriceFM task branch")
    control_path = args.prep_dir / "pricefm_stage_r100_launch_control.json"
    control = json.loads(control_path.read_text())
    if control.get("approval_token") != APPROVAL or control.get("workers") != 50:
        raise RuntimeError("R100 launch control changed")
    source = pd.read_csv(args.prep_dir / "source_manifest.csv")
    for row in source.itertuples(index=False):
        if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256):
            raise RuntimeError(f"R100 source changed: {row.path}")
    launch = pd.read_csv(args.prep_dir / "pricefm_stage_r100_ridge_launch_manifest.csv")
    first = cpu_snapshot()
    second = cpu_snapshot()
    usage = {cpu: max(first[cpu], second[cpu]) for cpu in cpus}
    if any(value > args.maximum_cpu_percent for value in usage.values()):
        busy = {cpu: value for cpu, value in usage.items() if value > args.maximum_cpu_percent}
        raise RuntimeError(f"selected R100 CPUs are busy: {busy}")
    resources = ensure_runtime_capacity(args.minimum_free_gib, args.minimum_memory_gib)
    audit = {
        "stage": "R100", "status": "preflight_passed_not_launched" if args.preflight_only else "preflight_passed",
        "workers": 50, "logical_cpus": cpus, "physical_cores": 25,
        "physical_pairing": pairing, "selected_cpu_percent": usage,
        **resources,
        "git_identity": identity.to_dict(), "regions": len(launch),
        "ridge_experiments": int(launch.candidate_count.sum()),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(args.campaign_root / "launch_preflight.json", audit)
    return cpus, launch, audit


def run(args: argparse.Namespace) -> dict[str, Any]:
    cpus, launch, audit = preflight(args)
    if args.preflight_only:
        return audit
    code_root = args.code_root.resolve()
    campaign = args.campaign_root.resolve()
    ridge = materialize_all(launch, code_root, campaign)
    if len(ridge) != 4080 or ridge.id.duplicated().any():
        raise RuntimeError("R100 Ridge materialization is incomplete")
    verify_or_build_windows(ridge, code_root, campaign)
    ridge_result = run_queue(ridge, cpus, code_root, campaign, "ridge")
    if ridge_result["complete"] != ridge_result["total"]:
        atomic_write_json(campaign / "campaign_terminal.json", {"stage": "R100", "status": "failed_closed_ridge", **ridge_result})
        raise RuntimeError(f"R100 Ridge queue incomplete: {ridge_result}")
    rhs = prepare_rhs(launch, code_root, campaign)
    if len(rhs) != 1530 or rhs.id.duplicated().any():
        raise RuntimeError("R100 RHS materialization is incomplete")
    rhs_result = run_queue(rhs, cpus, code_root, campaign, "rhs")
    if rhs_result["complete"] != rhs_result["total"]:
        atomic_write_json(campaign / "campaign_terminal.json", {"stage": "R100", "status": "failed_closed_rhs", **rhs_result})
        raise RuntimeError(f"R100 RHS queue incomplete: {rhs_result}")
    closeout = close_rhs(launch, rhs, campaign)
    return {"stage": "R100", "status": "controller_complete", "ridge": ridge_result, "rhs": rhs_result, **closeout}


def main() -> int:
    args = parser().parse_args()
    args.campaign_root.mkdir(parents=True, exist_ok=True)
    lock = (args.campaign_root / "controller.lock").open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R100 controller owns this campaign") from error
    try:
        print(json.dumps(run(args), indent=2, sort_keys=True))
        return 0
    except Exception as error:
        atomic_write_json(args.campaign_root / "campaign_terminal.json", {
            "stage": "R100", "status": "failed_closed", "error": repr(error),
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
        })
        raise
    finally:
        lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
