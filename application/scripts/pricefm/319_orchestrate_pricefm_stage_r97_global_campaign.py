#!/usr/bin/env python3
"""Run the complete R97 region-specific campaign and its global scoring audit."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import json
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

from pricefm_desn_adapter import window_npz_path
from pricefm_region_frozen_contract import (
    atomic_write_json,
    canonical_sha256,
    file_record,
    git_identity,
    sha256_file,
    verify_file_record,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
PREP = DATA / f"authoritative/{TAG}_prep"
CAMPAIGN = DATA / "campaigns" / TAG
APPROVAL_TOKEN = "RUN_PRICEFM_R97_COMPLETE_114_CASE_CAMPAIGN"
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)
PREP_RIDGE = SCRIPT_DIR / "291_prepare_pricefm_stage_r93_region_frozen_ladder.py"
MATERIALIZE_GRID = SCRIPT_DIR / "12_prepare_desn_experiment_grid.py"
RUN_MODEL = SCRIPT_DIR / "10_run_desn_model_full.py"
RIDGE_TO_RHS = SCRIPT_DIR / "292_advance_pricefm_stage_r93_ridge_to_rhs.py"
ADVANCE_RHS = SCRIPT_DIR / "294_advance_pricefm_stage_r93_validation_ladder.py"
PREP_SURFACE = SCRIPT_DIR / "317_prepare_pricefm_stage_r97_region_quantile_surface.py"
LAUNCH_SURFACE = SCRIPT_DIR / "315_launch_pricefm_region_frozen_allfold.py"
CLOSE_SURFACE = SCRIPT_DIR / "318_closeout_pricefm_stage_r97_region_quantile_surface.py"
PREP_SCORING = SCRIPT_DIR / "321_prepare_pricefm_stage_r97_global_scoring.py"
SCORE_CASE = SCRIPT_DIR / "320_score_pricefm_stage_r97_frozen_case.py"
CLOSE_GLOBAL = SCRIPT_DIR / "322_closeout_pricefm_stage_r97_global_surface.py"
MAKE_SPLITS = SCRIPT_DIR / "03_make_splits.py"
FIT_SCALERS = SCRIPT_DIR / "04_fit_scalers.py"
BUILD_WINDOWS = SCRIPT_DIR / "05_build_windows.py"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    value.add_argument("--workers", type=int, default=20)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    value.add_argument("--minimum-free-gib", type=float, default=250.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=64.0)
    value.add_argument("--approval-token", required=True)
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--poll-seconds", type=float, default=10.0)
    return value


def environment() -> dict[str, str]:
    result = dict(os.environ)
    for name in THREAD_ENV:
        result[name] = "1"
    return result


def command(cmd: list[Any], *, cwd: Path, log: Path, cpu: int | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    values = [str(item) for item in cmd]
    if cpu is not None:
        values = ["taskset", "-c", str(cpu), *values]
    with log.open("a") as handle:
        handle.write("$ " + " ".join(values) + "\n")
        handle.flush()
        result = subprocess.run(values, cwd=cwd, env=environment(), stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed with return code {result.returncode}: {log}")


def parse_cpus(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = map(int, token.split("-", 1))
            result.extend(range(lower, upper + 1))
        else:
            result.append(int(token))
    if len(result) != len(set(result)) or any(cpu < 0 or cpu >= (os.cpu_count() or 0) for cpu in result):
        raise RuntimeError("CPU list is duplicated or outside the online CPU range")
    return result


def cpu_snapshot(interval: float = 1.0) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        result = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith("cpu") and fields[0][3:].isdigit():
                ticks = [int(value) for value in fields[1:]]
                result[int(fields[0][3:])] = (sum(ticks), ticks[3] + (ticks[4] if len(ticks) > 4 else 0))
        return result
    before = read()
    time.sleep(interval)
    after = read()
    return {
        cpu: 100.0 * (1 - (after[cpu][1] - idle) / (after[cpu][0] - total))
        if after[cpu][0] > total else 100.0
        for cpu, (total, idle) in before.items()
    }


def choose_cpus(workers: int, maximum: float, explicit: str) -> tuple[list[int], dict[int, float]]:
    first = cpu_snapshot()
    second = cpu_snapshot()
    usage = {cpu: max(first[cpu], second[cpu]) for cpu in first}
    cpus = parse_cpus(explicit) if explicit else [
        cpu for cpu, observed in sorted(usage.items(), key=lambda item: (item[1], -item[0]))
        if observed <= maximum
    ][:workers]
    if len(cpus) < workers:
        raise RuntimeError(f"only {len(cpus)} CPUs satisfy the R97 resource gate")
    if any(usage[cpu] > maximum for cpu in cpus[:workers]):
        raise RuntimeError("an explicitly selected R97 CPU is currently busy")
    return cpus[:workers], usage


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def valid_marker(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        payload = json.loads(path.read_text())
        return payload.get("status") == "completed_compacted" and all(
            Path(record["path"]).is_file() and sha256_file(record["path"]) == record["sha256"]
            for record in payload.get("retained") or []
        )
    except (OSError, json.JSONDecodeError, KeyError):
        return False


def compact_experiment(row: Any, region: str, folds: list[int]) -> None:
    run_dir = Path(row.run_dir)
    retained = []
    for fold in folds:
        cell = run_dir / "cells" / f"region={region}" / f"fold={fold}"
        model = cell / "model"
        for name, role in (("metric_summary.csv", "selection_metric"), ("model_method_summary.csv", "method_summary")):
            retained.append(file_record(model / name, f"fold{fold}_{role}"))
        adapter = cell / "adapter"
        if adapter.exists():
            shutil.rmtree(adapter)
        for path in list(model.iterdir()):
            if path.name not in {"metric_summary.csv", "model_method_summary.csv"}:
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
    atomic_write_json(run_dir / "r97_compaction_terminal.json", {
        "status": "completed_compacted", "experiment_id": row.id,
        "region": region, "folds": folds, "retained": retained,
        "binary_model_artifacts_retained": False,
    })


def run_grid_serial(manifest_path: Path, region: str, cpu: int, code_root: Path, logs: Path) -> dict[str, int]:
    manifest = pd.read_csv(manifest_path)
    complete = 0
    for index, row in enumerate(manifest.itertuples(index=False), start=1):
        folds = [int(value) for value in json.loads(row.folds)]
        marker = Path(row.run_dir) / "r97_compaction_terminal.json"
        if valid_marker(marker):
            complete += 1
            continue
        command([
            PYTHON, RUN_MODEL, "--config", row.full_config, "--jobs", "1",
            "--resume", "true", "--force", "false", "--dry-run", "false",
            "--regions", region, "--folds", ",".join(map(str, folds)),
        ], cwd=code_root, log=logs / f"{row.id}.log", cpu=cpu)
        compact_experiment(row, region, folds)
        complete += 1
        atomic_write_json(logs.parent / "progress.json", {
            "region": region, "complete": complete, "total": len(manifest),
            "current_stage_manifest": str(manifest_path), "updated_at_epoch": time.time(),
        })
    return {"complete": complete, "total": len(manifest)}


def materialize_grid(grid: Path, generated: Path, code_root: Path, log: Path) -> None:
    manifest = generated / "manifest.csv"
    if manifest.is_file():
        return
    command([PYTHON, MATERIALIZE_GRID, "--grid-config", grid, "--write", "--output-root", generated], cwd=code_root, log=log)


def prepare_shared_data(
    configs: list[Path], regions: list[str], folds: list[int], code_root: Path,
    root: Path, *, shared_base_root: Path | None = None,
) -> None:
    marker = root / "preprocessing_complete.json"
    if marker.is_file():
        return
    by_lag = {}
    for path in configs:
        lag = int(yaml.safe_load(path.read_text())["pricefm"]["windows"]["lag_window"])
        by_lag.setdefault(lag, path)
    first = next(iter(by_lag.values()))
    base_root = shared_base_root or root
    base_marker = base_root / "base_preprocessing_complete.json"
    if not base_marker.is_file():
        command([PYTHON, MAKE_SPLITS, "--config", first, "--force", "false"], cwd=code_root, log=base_root / "logs/make_splits.log")
        command([PYTHON, FIT_SCALERS, "--config", first, "--force", "false"], cwd=code_root, log=base_root / "logs/fit_scalers.log")
        atomic_write_json(base_marker, {
            "status": "completed", "source_config": file_record(first, "preprocessing_config"),
        })
    for lag, path in sorted(by_lag.items()):
        command([
            PYTHON, BUILD_WINDOWS, "--config", path, "--pilot-only", "true",
            "--regions", ",".join(regions), "--folds", ",".join(map(str, folds)),
            "--resume", "true", "--force", "false",
        ], cwd=code_root, log=root / f"logs/build_windows_lag{lag}.log")
    atomic_write_json(marker, {"status": "completed", "lags": sorted(by_lag), "regions": regions, "folds": folds})


class Campaign:
    def __init__(self, args: argparse.Namespace, cpus: list[int]):
        self.args = args
        self.code_root = args.code_root.resolve()
        self.root = args.campaign_root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.cpus = cpus
        self.preprocess_lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.contract_path = args.prep_dir / "pricefm_stage_r97_campaign_contract.json"
        self.controls_path = args.prep_dir / "pricefm_stage_r97_authoritative_spec_controls.csv"
        self.contract = json.loads(self.contract_path.read_text())
        self.regions = list(self.contract["regions_to_fit"])
        self.authority = Path(self.contract["authority_registry"]["path"])
        self.data_config = Path(self.contract["source_data_config"]["path"])

    def update(self, region: str, **values: Any) -> None:
        path = self.root / "controller_state.json"
        with self.state_lock:
            payload = json.loads(path.read_text()) if path.is_file() else {"regions": {}}
            payload["regions"].setdefault(region, {}).update(values)
            payload["updated_at_epoch"] = time.time()
            atomic_write_json(path, payload)

    def paths(self, region: str) -> dict[str, Path]:
        root = self.root / "regions" / region
        return {
            "root": root,
            "ridge_prep": root / "ridge_prep", "ridge_generated": root / "ridge_generated",
            "ridge_runs": root / "ridge_runs", "rhs_prep": root / "rhs_prep",
            "rhs_generated": root / "rhs_generated", "rhs_runs": root / "rhs_runs",
            "ladder": root / "normal_selection", "refine_generated": root / "refine_generated",
            "refine_runs": root / "refine_runs", "surface_grid": root / "surface_grid",
            "outer_generated": root / "outer_generated", "outer_runs": root / "outer_runs",
            "outer_processed": root / "outer_processed",
            "surface_runs": root / "surface_runs", "surface_prep": root / "surface_prep",
            "surface_closeout": self.root / "region_closeouts" / region,
        }

    def prepare_ridge(self, region: str, paths: dict[str, Path]) -> None:
        summary = paths["ridge_prep"] / "summary.json"
        grid = paths["ridge_prep"] / "ridge_grid.yaml"
        if not summary.is_file():
            command([
                PYTHON, PREP_RIDGE,
                "--r92-registry", self.authority,
                "--control-registry", self.controls_path,
                "--expected-r92-sha256", sha256_file(self.authority),
                "--expected-control-sha256", sha256_file(self.controls_path),
                "--output-dir", paths["ridge_prep"], "--grid-config", grid,
                "--generated-root", paths["ridge_generated"], "--run-root", paths["ridge_runs"],
                "--processed-root", self.root / "processed_inner", "--target-region", region,
                "--write-grid", "true", "--force", "false",
            ], cwd=self.code_root, log=paths["root"] / "logs/prepare_ridge.log")
        materialize_grid(grid, paths["ridge_generated"], self.code_root, paths["root"] / "logs/materialize_ridge.log")

    def prepare_rhs(self, region: str, paths: dict[str, Path]) -> None:
        ridge_grid = paths["ridge_prep"] / "ridge_grid.yaml"
        if not ridge_grid.is_file() or ridge_grid.stat().st_size == 0:
            raise RuntimeError(f"R97 Ridge grid is missing or empty for {region}: {ridge_grid}")
        if not (paths["rhs_prep"] / "summary.json").is_file():
            command([
                PYTHON, RIDGE_TO_RHS,
                "--prep-dir", paths["ridge_prep"], "--ridge-generated-root", paths["ridge_generated"],
                "--ridge-grid", ridge_grid,
                "--output-dir", paths["rhs_prep"], "--rhs-generated-root", paths["rhs_generated"],
                "--rhs-run-root", paths["rhs_runs"], "--target-region", region,
            ], cwd=self.code_root, log=paths["root"] / "logs/prepare_rhs.log")
        grid = paths["rhs_prep"] / "pricefm_stage_r93_rhs_grid.yaml"
        materialize_grid(grid, paths["rhs_generated"], self.code_root, paths["root"] / "logs/materialize_rhs.log")

    def advance_args(self, region: str, paths: dict[str, Path]) -> list[Any]:
        return [
            "--rhs-prep-dir", paths["rhs_prep"], "--rhs-generated-root", paths["rhs_generated"],
            "--output-root", paths["ladder"], "--refinement-generated-root", paths["refine_generated"],
            "--refinement-run-root", paths["refine_runs"], "--target-region", region,
            "--outer-generated-root", paths["outer_generated"],
            "--outer-run-root", paths["outer_runs"],
            "--outer-processed-root", paths["outer_processed"],
        ]

    def select_normal(self, region: str, paths: dict[str, Path], cpu: int) -> Path:
        coarse_summary = paths["ladder"] / "rhs_coarse_closeout/summary.json"
        if not coarse_summary.is_file():
            command([PYTHON, ADVANCE_RHS, "close-rhs", *self.advance_args(region, paths)], cwd=self.code_root, log=paths["root"] / "logs/close_rhs.log")
        coarse = json.loads(coarse_summary.read_text())
        if coarse["refinement"]["refinement_required"]:
            grid = Path(coarse["next_grid"])
            materialize_grid(grid, paths["refine_generated"], self.code_root, paths["root"] / "logs/materialize_refinement.log")
            run_grid_serial(paths["refine_generated"] / "manifest.csv", region, cpu, self.code_root, paths["root"] / "logs/refinement")
            refined_summary = paths["ladder"] / "rhs_refinement_closeout/summary.json"
            if not refined_summary.is_file():
                command([PYTHON, ADVANCE_RHS, "close-refinement", *self.advance_args(region, paths)], cwd=self.code_root, log=paths["root"] / "logs/close_refinement.log")
            final = json.loads(refined_summary.read_text())
        else:
            final = coarse
        contract = Path(final["next_manifest"])
        if final.get("next_action") != "launch_outer_normal_confirmation" or not contract.is_file():
            raise RuntimeError(f"R97 failed to freeze a normal DESN/tau0 contract for {region}")
        return contract

    def preprocessing_terminal(self, paths: dict[str, Path]) -> None:
        pipeline_path = paths["surface_grid"] / "pipeline_contract.json"
        pipeline = json.loads(pipeline_path.read_text())
        pipeline_hash = pipeline.get("pipeline_contract_sha256")
        unhashed_pipeline = {
            key: value for key, value in pipeline.items()
            if key != "pipeline_contract_sha256"
        }
        if not isinstance(pipeline_hash, str) or canonical_sha256(unhashed_pipeline) != pipeline_hash:
            raise RuntimeError("R97 preprocessing pipeline contract hash is invalid")
        for name in (
            "test_opened", "test_access_authorized", "registry_mutation_authorized",
            "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
        ):
            if pipeline.get(name) is not False:
                raise RuntimeError(f"R97 preprocessing firewall is open: {name}")

        terminal_path = paths["surface_grid"] / "preprocessing_terminal.json"
        verify_file_record(
            pipeline["generated_data_config"],
            label="R97 generated train/validation data contract",
        )
        data_path = Path(pipeline["generated_data_config"]["path"])
        data = yaml.safe_load(data_path.read_text())
        if not isinstance(data, dict) or not isinstance(data.get("pricefm"), dict):
            raise RuntimeError("R97 generated data contract lacks the top-level pricefm block")
        spec = data["pricefm"]
        splits = spec.get("splits")
        if not isinstance(splits, list) or not splits:
            raise RuntimeError("R97 generated data contract has no validation splits")
        allowed_split_fields = {"fold", "train", "val"}
        if any(set(item) != allowed_split_fields for item in splits):
            raise RuntimeError("R97 generated data contract must expose train/val splits only")
        folds = [int(value) for value in pipeline.get("fit_folds", [])]
        if folds != [1, 2, 3] or {int(item["fold"]) for item in splits} != set(folds):
            raise RuntimeError("R97 preprocessing folds differ from the frozen three-fold surface")
        regions = [str(value) for value in pipeline.get("active_window_regions", [])]
        if not regions or len(regions) != len(set(regions)):
            raise RuntimeError("R97 preprocessing active regions are empty or duplicated")
        if not set(regions).issubset({str(value) for value in spec.get("regions", [])}):
            raise RuntimeError("R97 preprocessing active regions are absent from the data contract")
        processed = Path(spec["processed_dir"])
        if processed.resolve() != Path(pipeline["processed_dir"]).resolve():
            raise RuntimeError("R97 preprocessing output root differs from the pipeline contract")

        expected: list[tuple[Path, str]] = []
        for fold in folds:
            expected.append((
                processed / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib",
                f"fold{fold}_scaler",
            ))
            for region in regions:
                for split in ("train", "val"):
                    expected.append((
                        window_npz_path(data, fold, region, split),
                        f"fold{fold}_{region}_{split}_window",
                    ))

        def verify_terminal() -> None:
            terminal = json.loads(terminal_path.read_text())
            if (
                terminal.get("status") != "completed"
                or terminal.get("pipeline_contract_sha256") != pipeline_hash
                or terminal.get("test_opened") is not False
            ):
                raise RuntimeError("R97 preprocessing terminal metadata is invalid")
            records = terminal.get("artifacts")
            if not isinstance(records, list) or len(records) != len(expected):
                raise RuntimeError("R97 preprocessing terminal artifact count is invalid")
            by_role = {str(record.get("role")): record for record in records}
            if len(by_role) != len(records) or set(by_role) != {role for _, role in expected}:
                raise RuntimeError("R97 preprocessing terminal artifact roles are invalid")
            for path, role in expected:
                record = by_role[role]
                if Path(record.get("path", "")).resolve() != path.resolve():
                    raise RuntimeError(f"R97 preprocessing artifact path differs for {role}")
                verify_file_record(record, label=f"R97 preprocessing {role}")

        if terminal_path.is_file():
            verify_terminal()
            return
        with self.preprocess_lock:
            prepare_shared_data(
                [data_path], regions, folds,
                self.code_root, self.root / "validation_preprocessing" / pipeline["region"],
                shared_base_root=self.root / "validation_preprocessing",
            )
        verify_file_record(
            pipeline["generated_data_config"],
            label="R97 generated train/validation data contract after preprocessing",
        )
        artifacts = [file_record(path, role) for path, role in expected]
        atomic_write_json(terminal_path, {
            "status": "completed", "pipeline_contract_sha256": pipeline_hash,
            "artifacts": artifacts, "test_opened": False,
        })
        verify_terminal()

    def region(self, region: str, cpu: int) -> dict[str, Any]:
        paths = self.paths(region)
        paths["root"].mkdir(parents=True, exist_ok=True)
        self.update(region, status="running", cpu=cpu, phase="preparing_ridge")
        self.prepare_ridge(region, paths)
        self.update(region, phase="ridge_screen")
        run_grid_serial(paths["ridge_generated"] / "manifest.csv", region, cpu, self.code_root, paths["root"] / "logs/ridge")
        self.prepare_rhs(region, paths)
        self.update(region, phase="normal_rhs_screen")
        run_grid_serial(paths["rhs_generated"] / "manifest.csv", region, cpu, self.code_root, paths["root"] / "logs/rhs")
        self.update(region, phase="normal_rhs_selection")
        selected_contract = self.select_normal(region, paths, cpu)
        if not (paths["surface_prep"] / "summary.json").is_file():
            command([
                PYTHON, PREP_SURFACE, "--selected-normal-contract", selected_contract,
                "--source-data-config", self.data_config, "--processed-dir", self.root / "processed_validation",
                "--grid-dir", paths["surface_grid"], "--run-dir", paths["surface_runs"],
                "--output-dir", paths["surface_prep"], "--code-root", self.code_root,
                "--workers", "1",
            ], cwd=self.code_root, log=paths["root"] / "logs/prepare_surface.log")
        self.preprocessing_terminal(paths)
        surface = json.loads((paths["surface_prep"] / "summary.json").read_text())
        self.update(region, phase="allfold_AL_exAL_validation")
        command([
            PYTHON, LAUNCH_SURFACE, "--code-root", self.code_root,
            "--region-contract", surface["region_contract"],
            "--pipeline-contract", surface["pipeline_contract"], "--manifest", surface["manifest"],
            "--launch-control", surface["launch_control"],
            "--preprocessing-terminal", surface["preprocessing_terminal"],
            "--workers", "1", "--cpu-list", str(cpu), "--maximum-cpu-snapshot-percent", "100",
            "--approval-token", "RUN_PRICEFM_REGION_FROZEN_ALLFOLD_VALIDATION",
        ], cwd=self.code_root, log=paths["root"] / "logs/launch_surface.log")
        if not (paths["surface_closeout"] / "summary.json").is_file():
            command([
                PYTHON, CLOSE_SURFACE, "--manifest", surface["manifest"],
                "--pipeline-contract", surface["pipeline_contract"],
                "--output-dir", paths["surface_closeout"],
            ], cwd=self.code_root, log=paths["root"] / "logs/close_surface.log")
        summary = json.loads((paths["surface_closeout"] / "summary.json").read_text())
        self.update(region, status="completed_validation_frozen", phase="waiting_for_global_test_gate", selected_family=summary["selected_family"])
        return summary

    def prepare_all_ridges_and_data(self) -> None:
        for region in self.regions:
            self.prepare_ridge(region, self.paths(region))
        manifests = [pd.read_csv(self.paths(region)["ridge_generated"] / "manifest.csv") for region in self.regions]
        combined = pd.concat(manifests, ignore_index=True)
        configs = [Path(row.data_config) for row in combined.drop_duplicates("lag_window").itertuples(index=False)]
        prepare_shared_data(configs, list(self.contract["regions"]), [101, 102, 103], self.code_root, self.root / "inner_preprocessing")

    def score(self) -> dict[str, Any]:
        scoring = self.root / "global_scoring"
        prep = scoring / "prep"
        grid = scoring / "grid"
        runs = scoring / "runs"
        processed = self.root / "processed_scoring"
        if not (prep / "summary.json").is_file():
            command([
                PYTHON, PREP_SCORING, "--campaign-contract", self.contract_path,
                "--authority-registry", self.authority,
                "--region-closeout-root", self.root / "region_closeouts",
                "--source-data-config", self.data_config, "--processed-dir", processed,
                "--grid-dir", grid, "--run-dir", runs, "--output-dir", prep,
                "--code-root", self.code_root,
            ], cwd=self.code_root, log=scoring / "logs/prepare.log")
        manifest = pd.read_csv(grid / "task_manifest.csv")
        configs = [Path(json.loads(Path(row.task_config).read_text())["case_config"]) for row in manifest.itertuples(index=False)]
        data_configs = []
        for config in configs:
            smoke = yaml.safe_load(config.read_text())["pricefm_desn_smoke"]
            data_configs.append(Path(smoke["data_config"]))
        prepare_shared_data(data_configs, list(self.contract["regions"]), [1, 2, 3], self.code_root, scoring / "preprocessing")

        def score_one(row: Any, cpu: int) -> dict[str, Any]:
            terminal = Path(row.output_dir) / "terminal.json"
            if terminal.is_file() and json.loads(terminal.read_text()).get("status") == "completed":
                return {"task_id": row.task_id, "status": "skipped_complete"}
            command([PYTHON, SCORE_CASE, "--task-config", row.task_config, "--code-root", self.code_root], cwd=self.code_root, log=scoring / f"logs/{row.task_id}.log", cpu=cpu)
            return {"task_id": row.task_id, "status": "completed"}

        queue = list(manifest.itertuples(index=False))
        results = []
        buckets = [queue[index::len(self.cpus)] for index in range(len(self.cpus))]
        def score_bucket(cpu: int, rows: list[Any]) -> list[dict[str, Any]]:
            return [score_one(row, cpu) for row in rows]
        with ThreadPoolExecutor(max_workers=len(self.cpus)) as pool:
            futures = [pool.submit(score_bucket, cpu, bucket) for cpu, bucket in zip(self.cpus, buckets)]
            for future in as_completed(futures):
                results.extend(future.result())
                pd.DataFrame(results).to_csv(grid / "scoring_status.csv", index=False)
        closeout = scoring / "closeout"
        command([
            PYTHON, CLOSE_GLOBAL, "--scoring-manifest", grid / "task_manifest.csv",
            "--campaign-contract", self.contract_path, "--authority-registry", self.authority,
            "--se2-comparison", self.contract["se2_reuse"]["path"], "--output-dir", closeout,
        ], cwd=self.code_root, log=scoring / "logs/closeout.log")
        return json.loads((closeout / "summary.json").read_text())

    def run(self) -> dict[str, Any]:
        self.prepare_all_ridges_and_data()
        results = []
        buckets = [self.regions[index::len(self.cpus)] for index in range(len(self.cpus))]
        def region_bucket(cpu: int, regions: list[str]) -> list[dict[str, Any]]:
            completed = []
            for region in regions:
                try:
                    completed.append(self.region(region, cpu))
                except Exception as error:
                    self.update(region, status="failed_closed", error=repr(error))
                    raise
            return completed
        with ThreadPoolExecutor(max_workers=len(self.cpus)) as pool:
            futures = [pool.submit(region_bucket, cpu, bucket) for cpu, bucket in zip(self.cpus, buckets)]
            for future in as_completed(futures):
                results.extend(future.result())
        if len(results) != 37:
            raise RuntimeError("R97 validation campaign did not freeze all 37 new regions")
        closeout = self.score()
        atomic_write_json(self.root / "campaign_terminal.json", {
            "status": "completed_global_closeout", "regions_fitted": 37,
            "SE_2_reused": True, "cases": 114, "global_closeout": closeout,
            "registry_mutated": False, "article_mutated": False,
        })
        return closeout


def preflight(args: argparse.Namespace) -> tuple[list[int], dict[str, Any]]:
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"R97 launch requires --approval-token {APPROVAL_TOKEN}")
    if not 1 <= args.workers <= 20:
        raise RuntimeError("R97 permits 1--20 one-core model workers")
    identity = git_identity(args.code_root)
    if not identity.clean or identity.head != identity.upstream_head or not identity.branch.startswith("work/pricefm-"):
        raise RuntimeError("R97 launch requires a clean synchronized PriceFM task branch")
    contract_path = args.prep_dir / "pricefm_stage_r97_campaign_contract.json"
    contract = json.loads(contract_path.read_text())
    unhashed = {key: value for key, value in contract.items() if key != "campaign_contract_sha256"}
    if canonical_sha256(unhashed) != contract.get("campaign_contract_sha256"):
        raise RuntimeError("R97 campaign contract hash changed")
    if args.campaign_root.resolve() != Path(contract["campaign_root"]).resolve():
        raise RuntimeError("R97 campaign root differs from the frozen contract")
    if int(args.workers) != int(contract["workers"]):
        raise RuntimeError("R97 worker count differs from the frozen contract")
    for name in ("authority_registry", "resolved_controls", "se2_reuse", "source_data_config"):
        verify_file_record(contract[name], label=f"R97 {name}")
    cpus, usage = choose_cpus(args.workers, args.maximum_cpu_percent, args.cpu_list)
    free_gib = shutil.disk_usage(DATA).free / 1024**3
    memory = available_memory_gib()
    if free_gib < args.minimum_free_gib or memory < args.minimum_available_memory_gib:
        raise RuntimeError("R97 disk or memory resource floor failed")
    audit = {
        "status": "preflight_passed_not_launched" if args.preflight_only else "preflight_passed",
        "stage": "R97", "regions_to_fit": 37, "reused_regions": 1, "cases": 114,
        "workers": args.workers, "cpu_ids": cpus,
        "selected_cpu_percent": {str(cpu): round(usage[cpu], 3) for cpu in cpus},
        "one_model_process_per_cpu": True, "free_disk_gib": round(free_gib, 3),
        "available_memory_gib": round(memory, 3), "git_identity": identity.to_dict(),
        "overall_mean_decision": True, "per_case_dual_comparator_veto": False,
    }
    atomic_write_json(args.campaign_root / "launch_preflight.json", audit)
    return cpus, audit


def main() -> int:
    args = parser().parse_args()
    lock_path = args.campaign_root / "controller.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock = lock_path.open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R97 global controller owns this campaign") from error
    try:
        cpus, audit = preflight(args)
        if args.preflight_only:
            print(json.dumps(audit, indent=2, sort_keys=True))
            return 0
        try:
            result = Campaign(args, cpus).run()
        except Exception as error:
            atomic_write_json(args.campaign_root / "campaign_terminal.json", {
                "status": "failed_closed", "stage": "R97", "error": repr(error),
                "registry_mutated": False, "article_mutated": False,
            })
            raise
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    finally:
        lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
