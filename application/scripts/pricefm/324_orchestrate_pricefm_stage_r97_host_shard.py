#!/usr/bin/env python3
"""Resume an exclusive host shard of the R97 validation-only campaign."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sys
import threading
import time
from types import SimpleNamespace
from typing import Any, Callable

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import (
    controller_lock_available,
    firewall,
    valid_compaction_marker,
    validate_firewall,
    verify_seal,
    write_sealed,
)
from pricefm_region_frozen_contract import (
    atomic_write_json,
    git_identity,
    sha256_file,
    validate_git_identity,
    verify_file_record,
)


APPROVAL_TOKEN = "RUN_PRICEFM_R97_DISTRIBUTED_VALIDATION_SHARD"
ARTIFACT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_ROOT / "application/data_local/pricefm"
DEFAULT_PREP = DATA_ROOT / "authoritative/pricefm_stage_r97_global_region_frozen_campaign_20260908_prep"
DEFAULT_CAMPAIGN = DATA_ROOT / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"


def load_original_controller():
    path = SCRIPT_DIR / "319_orchestrate_pricefm_stage_r97_global_campaign.py"
    spec = importlib.util.spec_from_file_location("pricefm_r97_original_controller", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


ORIGINAL = load_original_controller()


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--shard-contract", type=Path, required=True)
    value.add_argument("--campaign-root", type=Path, default=DEFAULT_CAMPAIGN)
    value.add_argument("--prep-dir", type=Path, default=DEFAULT_PREP)
    value.add_argument("--host", choices=("muscat", "jerez"), required=True)
    value.add_argument("--workers", type=int, required=True)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    value.add_argument("--minimum-free-gib", type=float, default=250.0)
    value.add_argument("--throttle-admission-free-gib", type=float, default=270.0)
    value.add_argument("--pause-admission-free-gib", type=float, default=260.0)
    value.add_argument("--minimum-available-memory-gib", type=float, default=64.0)
    value.add_argument("--poll-seconds", type=float, default=10.0)
    value.add_argument("--approval-token", default="")
    value.add_argument("--preflight-only", action="store_true")
    return value


def free_gib(path: Path) -> float:
    return shutil.disk_usage(path).free / 1024**3


def memory_gib() -> float:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def load_contract(args: argparse.Namespace) -> dict[str, Any]:
    payload = json.loads(args.shard_contract.read_text())
    verify_seal(payload, "shard_contract_sha256", label="R97 host shard contract")
    validate_firewall(payload, label="R97 host shard contract")
    if payload.get("mode") != "freeze":
        raise RuntimeError("only a frozen shard contract can run")
    if payload.get("host") != args.host:
        raise RuntimeError("requested host differs from the shard contract")
    if int(payload.get("workers", -1)) != int(args.workers):
        raise RuntimeError("worker count differs from the frozen shard contract")
    if Path(payload["campaign_root"]).resolve() != args.campaign_root.resolve():
        raise RuntimeError("campaign root differs from the frozen shard contract")
    for name in ("parent_campaign_contract", "checkpoint", "assignment"):
        verify_file_record(payload[name], label=f"R97 shard {name}")
    assignment = pd.read_csv(payload["assignment"]["path"])
    owned = assignment.loc[assignment.assigned_host.astype(str).eq(args.host), "region"].astype(str).tolist()
    if owned != list(payload["regions"]) or len(owned) != len(set(owned)):
        raise RuntimeError("shard region ownership differs from the sealed assignment")
    return payload


def preflight(args: argparse.Namespace) -> tuple[dict[str, Any], list[int]]:
    contract = load_contract(args)
    if not controller_lock_available(args.campaign_root):
        raise RuntimeError("the original R97 global controller still owns the campaign")
    if not 1 <= args.workers <= 50:
        raise RuntimeError("host shard requires 1--50 one-core workers")
    if args.host == "muscat" and args.workers > 20:
        raise RuntimeError("Muscat shard is capped at 20 workers")
    if not args.minimum_free_gib <= args.pause_admission_free_gib <= args.throttle_admission_free_gib:
        raise RuntimeError("disk gates must satisfy minimum <= pause <= throttle")
    cpus, usage = (
        (ORIGINAL.parse_cpus(args.cpu_list), ORIGINAL.cpu_snapshot())
        if args.cpu_list else ORIGINAL.choose_cpus(args.workers, args.maximum_cpu_percent, "")
    )
    if len(cpus) != args.workers:
        raise RuntimeError("host shard requires exactly one distinct CPU per worker")
    identity = validate_git_identity(args.code_root, contract["code_git_identity"], require_clean=True)
    disk = free_gib(args.campaign_root)
    memory = memory_gib()
    required_start_disk = max(args.minimum_free_gib, 300.0 if args.host == "jerez" else args.minimum_free_gib)
    if disk < required_start_disk or memory < args.minimum_available_memory_gib:
        raise RuntimeError("host shard disk or memory floor failed")
    audit = {
        "status": "preflight_passed_not_launched",
        "host": args.host,
        "regions": list(contract["regions"]),
        "region_count": len(contract["regions"]),
        "workers": args.workers,
        "cpu_ids": cpus,
        "one_model_process_per_cpu": True,
        "threads_per_model": 1,
        "free_disk_gib": round(disk, 3),
        "required_start_free_disk_gib": round(required_start_disk, 3),
        "available_memory_gib": round(memory, 3),
        "git_identity": identity.to_dict(),
        "launch_invoked": False,
        "global_test_scoring_invoked": False,
        **firewall(),
    }
    root = args.campaign_root / "distributed" / args.host
    atomic_write_json(root / "launch_preflight.json", audit)
    return contract, cpus


class HostShard:
    def __init__(self, args: argparse.Namespace, contract: dict[str, Any], cpus: list[int]):
        self.args = args
        self.contract = contract
        self.cpus = cpus
        self.regions = list(contract["regions"])
        self.root = args.campaign_root / "distributed" / args.host
        self.root.mkdir(parents=True, exist_ok=True)
        self.drain = self.root / "DRAIN"
        original_args = SimpleNamespace(
            code_root=args.code_root.resolve(), prep_dir=args.prep_dir.resolve(),
            campaign_root=args.campaign_root.resolve(), workers=args.workers,
        )
        self.campaign = ORIGINAL.Campaign(original_args, cpus)
        self.state_lock = threading.Lock()

    def update(self, **values: Any) -> None:
        with self.state_lock:
            path = self.root / "controller_state.json"
            payload = json.loads(path.read_text()) if path.is_file() else {}
            payload.update(values)
            payload["updated_at_epoch"] = time.time()
            atomic_write_json(path, payload)

    def admission_open(self) -> bool:
        if self.drain.exists():
            return False
        if free_gib(self.args.campaign_root) < self.args.pause_admission_free_gib:
            self.drain.write_text("automatic disk admission pause\n")
            self.update(status="draining_disk_floor")
            return False
        return True

    def per_region_limit(self) -> int:
        return 1 if free_gib(self.args.campaign_root) < self.args.throttle_admission_free_gib else 2

    def screening_task(self, region: str, row: Any, cpu: int, phase: str) -> dict[str, Any]:
        marker = Path(row.run_dir) / "r97_compaction_terminal.json"
        if valid_compaction_marker(marker):
            return {"region": region, "id": row.id, "phase": phase, "status": "skipped_complete", "cpu": cpu}
        folds = [int(value) for value in json.loads(row.folds)]
        log = self.campaign.paths(region)["root"] / "logs" / phase / f"{row.id}.log"
        started = time.time()
        ORIGINAL.command([
            ORIGINAL.PYTHON, ORIGINAL.RUN_MODEL, "--config", row.full_config,
            "--jobs", "1", "--resume", "true", "--force", "false",
            "--dry-run", "false", "--regions", region,
            "--folds", ",".join(map(str, folds)),
        ], cwd=self.args.code_root.resolve(), log=log, cpu=cpu)
        ORIGINAL.compact_experiment(row, region, folds)
        return {
            "region": region, "id": row.id, "phase": phase, "status": "completed",
            "cpu": cpu, "elapsed_seconds": round(time.time() - started, 3),
        }

    def run_screening_phase(self, manifest_key: str, phase: str) -> bool:
        queues: dict[str, list[Any]] = {}
        for region in self.regions:
            path = self.campaign.paths(region)[manifest_key] / "manifest.csv"
            if not path.is_file():
                queues[region] = []
                continue
            frame = pd.read_csv(path)
            queues[region] = [
                row for row in frame.itertuples(index=False)
                if not valid_compaction_marker(Path(row.run_dir) / "r97_compaction_terminal.json")
            ]
        active_by_region = {region: 0 for region in self.regions}
        available = list(self.cpus)
        running: dict[Any, tuple[str, int]] = {}
        completed: list[dict[str, Any]] = []
        with ThreadPoolExecutor(max_workers=len(self.cpus)) as pool:
            while any(queues.values()) or running:
                admitted = False
                if self.admission_open():
                    for region in sorted(self.regions, key=lambda name: (-len(queues[name]), name)):
                        while available and queues[region] and active_by_region[region] < self.per_region_limit():
                            cpu = available.pop(0)
                            row = queues[region].pop(0)
                            future = pool.submit(self.screening_task, region, row, cpu, phase)
                            running[future] = (region, cpu)
                            active_by_region[region] += 1
                            admitted = True
                if running:
                    done, _ = wait(running, return_when=FIRST_COMPLETED)
                    for future in done:
                        region, cpu = running.pop(future)
                        active_by_region[region] -= 1
                        available.append(cpu)
                        available.sort()
                        completed.append(future.result())
                    pd.DataFrame(completed).to_csv(self.root / f"{phase}_status.csv", index=False)
                    self.update(
                        status="running", phase=phase, completed_this_phase=len(completed),
                        remaining_this_phase=sum(map(len, queues.values())), active=len(running),
                    )
                elif any(queues.values()) and not admitted:
                    self.update(status="drained", phase=phase, remaining_this_phase=sum(map(len, queues.values())))
                    return False
        return True

    def prepare_ridges(self) -> None:
        for region in self.regions:
            paths = self.campaign.paths(region)
            paths["root"].mkdir(parents=True, exist_ok=True)
            self.campaign.prepare_ridge(region, paths)

    def prepare_rhs(self) -> None:
        for region in self.regions:
            self.campaign.prepare_rhs(region, self.campaign.paths(region))

    def prepare_refinements(self) -> dict[str, Path]:
        selected: dict[str, Path] = {}
        for region in self.regions:
            paths = self.campaign.paths(region)
            coarse_summary = paths["ladder"] / "rhs_coarse_closeout/summary.json"
            if not coarse_summary.is_file():
                ORIGINAL.command(
                    [ORIGINAL.PYTHON, ORIGINAL.ADVANCE_RHS, "close-rhs", *self.campaign.advance_args(region, paths)],
                    cwd=self.args.code_root.resolve(), log=paths["root"] / "logs/close_rhs.log",
                )
            coarse = json.loads(coarse_summary.read_text())
            if coarse["refinement"]["refinement_required"]:
                grid = Path(coarse["next_grid"])
                ORIGINAL.materialize_grid(grid, paths["refine_generated"], self.args.code_root.resolve(), paths["root"] / "logs/materialize_refinement.log")
            else:
                if coarse.get("next_action") != "launch_outer_normal_confirmation":
                    raise RuntimeError(f"R97 coarse normal selection is not launch-grade for {region}")
                selected[region] = Path(coarse["next_manifest"])
        return selected

    def freeze_selected_normals(self, selected: dict[str, Path]) -> dict[str, Path]:
        for region in self.regions:
            if region in selected:
                continue
            paths = self.campaign.paths(region)
            refined_summary = paths["ladder"] / "rhs_refinement_closeout/summary.json"
            if not refined_summary.is_file():
                ORIGINAL.command(
                    [ORIGINAL.PYTHON, ORIGINAL.ADVANCE_RHS, "close-refinement", *self.campaign.advance_args(region, paths)],
                    cwd=self.args.code_root.resolve(), log=paths["root"] / "logs/close_refinement.log",
                )
            payload = json.loads(refined_summary.read_text())
            if payload.get("next_action") != "launch_outer_normal_confirmation":
                raise RuntimeError(f"R97 refined normal selection is not launch-grade for {region}")
            selected[region] = Path(payload["next_manifest"])
        for region, path in selected.items():
            if not path.is_file():
                raise RuntimeError(f"R97 did not freeze a selected normal contract for {region}")
        return selected

    def prepare_surfaces(self, selected: dict[str, Path]) -> dict[str, dict[str, Any]]:
        surfaces: dict[str, dict[str, Any]] = {}
        for region in self.regions:
            paths = self.campaign.paths(region)
            summary_path = paths["surface_prep"] / "summary.json"
            if not summary_path.is_file():
                ORIGINAL.command([
                    ORIGINAL.PYTHON, ORIGINAL.PREP_SURFACE,
                    "--selected-normal-contract", selected[region],
                    "--source-data-config", self.campaign.data_config,
                    "--processed-dir", self.args.campaign_root / "processed_validation",
                    "--grid-dir", paths["surface_grid"], "--run-dir", paths["surface_runs"],
                    "--output-dir", paths["surface_prep"], "--code-root", self.args.code_root.resolve(),
                    "--workers", "2",
                ], cwd=self.args.code_root.resolve(), log=paths["root"] / "logs/prepare_surface.log")
            self.campaign.preprocessing_terminal(paths)
            surfaces[region] = json.loads(summary_path.read_text())
        return surfaces

    def launch_surface(self, region: str, surface: dict[str, Any], cpus: list[int]) -> dict[str, Any]:
        paths = self.campaign.paths(region)
        ORIGINAL.command([
            ORIGINAL.PYTHON, ORIGINAL.LAUNCH_SURFACE, "--code-root", self.args.code_root.resolve(),
            "--region-contract", surface["region_contract"],
            "--pipeline-contract", surface["pipeline_contract"], "--manifest", surface["manifest"],
            "--launch-control", surface["launch_control"],
            "--preprocessing-terminal", surface["preprocessing_terminal"],
            "--workers", str(len(cpus)), "--cpu-list", ",".join(map(str, cpus)),
            "--maximum-cpu-snapshot-percent", "100",
            "--approval-token", "RUN_PRICEFM_REGION_FROZEN_ALLFOLD_VALIDATION",
        ], cwd=self.args.code_root.resolve(), log=paths["root"] / "logs/launch_surface.log")
        if not (paths["surface_closeout"] / "summary.json").is_file():
            ORIGINAL.command([
                ORIGINAL.PYTHON, ORIGINAL.CLOSE_SURFACE, "--manifest", surface["manifest"],
                "--pipeline-contract", surface["pipeline_contract"],
                "--output-dir", paths["surface_closeout"],
            ], cwd=self.args.code_root.resolve(), log=paths["root"] / "logs/close_surface.log")
        summary = json.loads((paths["surface_closeout"] / "summary.json").read_text())
        return {"region": region, "status": "completed_validation_frozen", "selected_family": summary["selected_family"]}

    def run_surfaces(self, surfaces: dict[str, dict[str, Any]]) -> bool:
        queue = [region for region in self.regions if not (self.campaign.paths(region)["surface_closeout"] / "summary.json").is_file()]
        width = 2 if len(self.cpus) >= 2 else 1
        pairs = [self.cpus[index:index + width] for index in range(0, len(self.cpus), width)]
        available = list(pairs)
        running: dict[Any, list[int]] = {}
        completed: list[dict[str, Any]] = []
        with ThreadPoolExecutor(max_workers=len(pairs)) as pool:
            while queue or running:
                while queue and available and self.admission_open():
                    cpus = available.pop(0)
                    region = queue.pop(0)
                    running[pool.submit(self.launch_surface, region, surfaces[region], cpus)] = cpus
                if running:
                    done, _ = wait(running, return_when=FIRST_COMPLETED)
                    for future in done:
                        available.append(running.pop(future))
                        completed.append(future.result())
                    atomic_write_json(self.root / "surface_status.json", {"completed": completed, "remaining": queue, **firewall()})
                elif queue:
                    self.update(status="drained", phase="quantile_surface", remaining_regions=queue)
                    return False
        return True

    def run(self) -> dict[str, Any]:
        self.update(status="running", phase="ridge_preparation")
        self.prepare_ridges()
        if not self.run_screening_phase("ridge_generated", "ridge"):
            return self.finish("drained_incomplete")
        self.update(phase="rhs_preparation")
        self.prepare_rhs()
        if not self.run_screening_phase("rhs_generated", "rhs"):
            return self.finish("drained_incomplete")
        self.update(phase="normal_selection")
        selected = self.prepare_refinements()
        if not self.run_screening_phase("refine_generated", "refinement"):
            return self.finish("drained_incomplete")
        selected = self.freeze_selected_normals(selected)
        self.update(phase="surface_preparation")
        surfaces = self.prepare_surfaces(selected)
        self.update(phase="allfold_AL_exAL_validation")
        if not self.run_surfaces(surfaces):
            return self.finish("drained_incomplete")
        return self.finish("completed_validation_shard")

    def finish(self, status: str, *, error: str | None = None) -> dict[str, Any]:
        completed = [
            region for region in self.regions
            if (self.campaign.paths(region)["surface_closeout"] / "summary.json").is_file()
        ]
        payload = {
            "schema_version": 1,
            "stage": "R97-distributed-continuation",
            "status": status,
            "host": self.args.host,
            "regions_assigned": self.regions,
            "regions_completed": completed,
            "completed_count": len(completed),
            "remaining_count": len(self.regions) - len(completed),
            "global_test_scoring_invoked": False,
            "registry_mutated": False,
            "article_mutated": False,
            **firewall(),
        }
        if error:
            payload["error"] = error
        return write_sealed(self.root / "shard_terminal.json", payload, "shard_terminal_sha256")


def main() -> int:
    args = parser().parse_args()
    contract, cpus = preflight(args)
    if args.preflight_only:
        print(json.dumps(json.loads((args.campaign_root / "distributed" / args.host / "launch_preflight.json").read_text()), indent=2, sort_keys=True))
        return 0
    if args.approval_token != APPROVAL_TOKEN:
        raise RuntimeError(f"launch requires --approval-token {APPROVAL_TOKEN}")
    lock_path = args.campaign_root / "distributed" / args.host / "controller.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    handle = lock_path.open("a+")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        handle.close()
        raise RuntimeError(f"another {args.host} R97 shard controller is active") from error
    try:
        shard = HostShard(args, contract, cpus)
        try:
            result = shard.run()
        except Exception as error:
            shard.finish("failed_closed", error=repr(error))
            raise
    finally:
        handle.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] in {"completed_validation_shard", "drained_incomplete"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
