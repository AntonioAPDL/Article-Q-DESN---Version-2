#!/usr/bin/env python3
"""Run the authorized R93 validation ladder and stop before any test audit."""

from __future__ import annotations

import argparse
import csv
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import validate_pretest_firewall


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PYTHON = DATA / "venv/bin/python"
R_SCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
RIDGE_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_ridge_20260906"
RHS_PREP = DATA / "authoritative/pricefm_stage_r93_ridge_closeout_rhs_prep_20260906"
RHS_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_rhs_20260906"
REFINE_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_rhs_refinement_20260906"
OUTER_GENERATED = DATA / "experiment_grids/pricefm_stage_r93_region_frozen_outer_normal_20260906"
OUTPUT = DATA / "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906"
LOG = DATA / "logs/pricefm_stage_r93_overnight_validation_ladder_20260906.log"
ADVANCE = Path(__file__).with_name("294_advance_pricefm_stage_r93_validation_ladder.py")
QUANTILE_RUNNER = Path(__file__).with_name("295_run_pricefm_stage_r93_quantile_ladder.R")
GRID_LAUNCHER = Path(__file__).with_name("13_run_desn_experiment_grid.py")
RIDGE_TO_RHS = Path(__file__).with_name("292_advance_pricefm_stage_r93_ridge_to_rhs.py")
ADAPTER = Path(__file__).with_name("07_build_desn_direct_horizon_adapter.py")
SUMMARIZER = Path(__file__).with_name("09_summarize_desn_model_smoke.py")
APPROVAL_TOKEN = "RUN_PRICEFM_R93_VALIDATION_LADDER"
SUCCESS = {"completed", "skipped_complete"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--approval-token", required=True)
    p.add_argument("--cpu-list", default="20,22-30")
    p.add_argument("--workers", type=int, default=10)
    p.add_argument("--poll-seconds", type=int, default=60)
    p.add_argument("--stall-seconds", type=int, default=4 * 60 * 60)
    p.add_argument("--maximum-cpu-percent", type=float, default=35.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=32.0)
    p.add_argument("--resource-wait-seconds", type=int, default=15)
    p.add_argument("--resource-timeout-seconds", type=int, default=30 * 60)
    p.add_argument("--code-root", type=Path, default=Path.cwd())
    p.add_argument("--expected-code-head", required=True)
    p.add_argument(
        "--accept-coarse-winner-without-refinement",
        action="store_true",
    )
    p.add_argument("--expected-coarse-winner-id", default="")
    p.add_argument("--expected-coarse-winner-tau0", type=float)
    p.add_argument("--output-root", type=Path, default=OUTPUT)
    p.add_argument("--log", type=Path, default=LOG)
    return p


def parse_cpu_list(value: str) -> list[int]:
    cpus: list[int] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if part.startswith("-") and part[1:].isdigit():
            cpus.append(int(part))
        elif "-" in part:
            low, high = map(int, part.split("-", 1))
            cpus.extend(range(low, high + 1))
        else:
            cpus.append(int(part))
    if not cpus or len(cpus) != len(set(cpus)) or any(cpu < 0 for cpu in cpus):
        raise ValueError("CPU list must be nonempty, unique, and nonnegative")
    return cpus


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def available_memory_gib() -> float:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values.get("MemAvailable", 0) / 1024**2


def cpu_snapshot(interval: float = 0.5) -> dict[int, float]:
    def read() -> dict[int, tuple[int, int]]:
        result: dict[int, tuple[int, int]] = {}
        for line in Path("/proc/stat").read_text().splitlines():
            fields = line.split()
            if not fields or not fields[0].startswith("cpu") or fields[0] == "cpu":
                continue
            cpu = int(fields[0][3:])
            ticks = [int(value) for value in fields[1:]]
            idle = ticks[3] + (ticks[4] if len(ticks) > 4 else 0)
            result[cpu] = (sum(ticks), idle)
        return result

    first = read()
    time.sleep(interval)
    second = read()
    usage: dict[int, float] = {}
    for cpu, (total2, idle2) in second.items():
        total1, idle1 = first[cpu]
        delta_total = total2 - total1
        usage[cpu] = 0.0 if delta_total <= 0 else 100.0 * (1 - (idle2 - idle1) / delta_total)
    return usage


class Controller:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.code_root = args.code_root.resolve()
        self.output = args.output_root.resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.state_path = self.output / "orchestrator/state.json"
        self.lock_path = self.output / "orchestrator/lock"
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        self.args.log.parent.mkdir(parents=True, exist_ok=True)
        self.log_handle = self.args.log.open("a", buffering=1)
        self.lock_handle = self.lock_path.open("w")
        try:
            fcntl.flock(self.lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("another R93 overnight controller holds the lock") from exc
        self.state: dict[str, Any] = {
            "status": "starting", "phase": "preflight", "pid": os.getpid(),
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "code_root": str(self.code_root), "expected_code_head": args.expected_code_head,
            "cpu_ids": parse_cpu_list(args.cpu_list), "workers": args.workers,
            "accept_coarse_winner_without_refinement": bool(
                args.accept_coarse_winner_without_refinement
            ),
            "expected_coarse_winner_id": str(args.expected_coarse_winner_id),
            "expected_coarse_winner_tau0": args.expected_coarse_winner_tau0,
            "test_opened": False, "registry_mutated": False,
            "article_mutated": False, "joint_or_mcmc_authorized": False,
            "history": [],
        }
        self.save()

    def log(self, message: str) -> None:
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        line = f"[{stamp}] {message}"
        self.log_handle.write(line + "\n")
        print(line, flush=True)

    def save(self) -> None:
        atomic_json(self.state_path, self.state)

    def phase(self, name: str, **details: Any) -> None:
        self.state["phase"] = name
        self.state.update(details)
        self.state["history"].append({
            "phase": name,
            "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            **details,
        })
        self.save()
        self.log(f"phase={name} {json.dumps(details, sort_keys=True)}")

    def command(self, label: str, cmd: list[Any]) -> None:
        command_log = self.output / "orchestrator/logs" / f"{label}.log"
        command_log.parent.mkdir(parents=True, exist_ok=True)
        self.log(f"run {label}: {' '.join(map(str, cmd))}")
        env = os.environ.copy()
        env.update({
            "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1", "VECLIB_MAXIMUM_THREADS": "1",
            "NUMEXPR_NUM_THREADS": "1", "RCPP_PARALLEL_NUM_THREADS": "1",
            "BLIS_NUM_THREADS": "1",
        })
        with command_log.open("a") as handle:
            handle.write("$ " + " ".join(map(str, cmd)) + "\n\n")
            handle.flush()
            result = subprocess.run(
                [str(item) for item in cmd], cwd=self.code_root, env=env,
                stdout=handle, stderr=subprocess.STDOUT, check=False,
            )
        if result.returncode != 0:
            raise RuntimeError(f"{label} failed with return code {result.returncode}: {command_log}")

    def quarantine_partial(self, path: Path, label: str) -> None:
        if not path.exists() or not any(path.iterdir()):
            return
        stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        quarantine = self.output / "orchestrator/quarantine" / f"{label}_{stamp}"
        quarantine.parent.mkdir(parents=True, exist_ok=True)
        path.rename(quarantine)
        self.log(f"preserved incomplete {label} output at {quarantine}")

    def wait_for_resources(self, label: str, cpus: list[int]) -> None:
        deadline = time.monotonic() + self.args.resource_timeout_seconds
        good_samples = 0
        while True:
            usage = cpu_snapshot()
            selected = {cpu: round(usage.get(cpu, 100.0), 1) for cpu in cpus}
            memory = available_memory_gib()
            free_disk = shutil.disk_usage(DATA).free / 1024**3
            passed = (
                all(value <= self.args.maximum_cpu_percent for value in selected.values())
                and memory >= self.args.minimum_available_memory_gib
                and free_disk >= 100
            )
            good_samples = good_samples + 1 if passed else 0
            self.state["resource_gate"] = {
                "label": label, "selected_cpu_percent": selected,
                "maximum_cpu_percent": self.args.maximum_cpu_percent,
                "available_memory_gib": round(memory, 3),
                "minimum_available_memory_gib": self.args.minimum_available_memory_gib,
                "free_disk_gib": round(free_disk, 3),
                "consecutive_passes": good_samples,
            }
            self.save()
            if good_samples >= 2:
                self.log(
                    f"resource gate passed for {label}: cpus={selected}; "
                    f"memory={memory:.1f} GiB; disk={free_disk:.1f} GiB"
                )
                return
            if time.monotonic() >= deadline:
                raise RuntimeError(f"resource gate timed out before {label}")
            time.sleep(self.args.resource_wait_seconds)

    def preflight(self) -> None:
        if self.args.approval_token != APPROVAL_TOKEN:
            raise RuntimeError("explicit R93 validation-ladder approval token is absent")
        cpus = self.state["cpu_ids"]
        if self.args.workers < 1 or len(cpus) < self.args.workers:
            raise RuntimeError("one unique CPU is required per concurrent model")
        total = os.cpu_count() or 0
        if any(cpu >= total for cpu in cpus):
            raise RuntimeError(f"selected CPU exceeds host count {total}")
        if not PYTHON.is_file() or not R_SCRIPT.is_file():
            raise FileNotFoundError("pinned PriceFM Python or Rscript is absent")
        if self.args.accept_coarse_winner_without_refinement and (
            not self.args.expected_coarse_winner_id
            or self.args.expected_coarse_winner_tau0 is None
        ):
            raise RuntimeError(
                "coarse-winner acceptance requires the expected winner ID and tau0"
            )
        head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.code_root, text=True
        ).strip()
        dirty = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=self.code_root, text=True
        ).strip()
        if head != self.args.expected_code_head or dirty:
            raise RuntimeError(f"code freeze failed: head={head}, dirty={bool(dirty)}")
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"], cwd=self.code_root, text=True
        ).strip()
        if not branch.startswith("work/pricefm-r93-"):
            raise RuntimeError(f"unexpected task branch: {branch}")
        free_gib = shutil.disk_usage(DATA).free / 1024**3
        if free_gib < 100:
            raise RuntimeError(f"R93 requires at least 100 GiB free; observed {free_gib:.1f}")
        memory = available_memory_gib()
        if memory < self.args.minimum_available_memory_gib:
            raise RuntimeError(
                f"R93 requires {self.args.minimum_available_memory_gib:.1f} GiB available memory; "
                f"observed {memory:.1f}"
            )
        self.state.update({
            "code_head": head, "branch": branch, "free_disk_gib": free_gib,
            "available_memory_gib": memory,
        })
        self.phase("waiting_for_ridge")

    @staticmethod
    def grid_counts(generated_root: Path) -> dict[str, int]:
        status = generated_root / "launch_status.csv"
        counts: dict[str, int] = {}
        if not status.is_file():
            return counts
        with status.open(newline="") as handle:
            for row in csv.DictReader(handle):
                if row.get("kind") != "experiment":
                    continue
                key = str(row.get("status", "unknown"))
                counts[key] = counts.get(key, 0) + 1
        return counts

    @staticmethod
    def matching_processes(token: str) -> int:
        result = subprocess.run(
            ["pgrep", "-af", token], text=True, capture_output=True, check=False
        )
        lines = [line for line in result.stdout.splitlines() if str(os.getpid()) not in line]
        return len(lines)

    def wait_grid(self, label: str, root: Path, expected: int, token: str) -> None:
        last_complete = -1
        last_progress = time.monotonic()
        absent_polls = 0
        while True:
            counts = self.grid_counts(root)
            failed = sum(value for key, value in counts.items() if key not in SUCCESS)
            complete = sum(value for key, value in counts.items() if key in SUCCESS)
            active = self.matching_processes(token)
            self.state["live"] = {
                "label": label, "expected": expected, "complete": complete,
                "remaining": max(0, expected - complete), "failed": failed,
                "matching_processes": active,
            }
            self.save()
            if failed:
                raise RuntimeError(f"{label} has {failed} failed experiment rows: {root}")
            if complete == expected:
                self.log(f"{label} complete: {complete}/{expected}")
                return
            if complete > expected:
                raise RuntimeError(f"{label} status exceeds expected count")
            if complete != last_complete:
                self.log(f"{label} progress: {complete}/{expected}; active={active}")
                last_complete = complete
                last_progress = time.monotonic()
            if active == 0:
                absent_polls += 1
                if absent_polls >= 2:
                    raise RuntimeError(f"{label} is incomplete with no matching process")
            else:
                absent_polls = 0
            if time.monotonic() - last_progress > self.args.stall_seconds:
                raise RuntimeError(f"{label} made no status progress for the stall interval")
            time.sleep(self.args.poll_seconds)

    def run_advance(self, action: str) -> dict[str, Any]:
        stage_dir = {
            "close-rhs": "rhs_coarse_closeout",
            "close-refinement": "rhs_refinement_closeout",
            "close-outer": "outer_normal_closeout",
            "close-quantile": "quantile_validation_closeout",
        }[action]
        summary_path = self.output / stage_dir / "summary.json"
        if not summary_path.is_file():
            self.quarantine_partial(self.output / stage_dir, action)
            command = [PYTHON, ADVANCE, action, "--output-root", self.output]
            if action == "close-rhs" and self.args.accept_coarse_winner_without_refinement:
                command.extend([
                    "--accept-coarse-winner-without-refinement", "true",
                    "--expected-coarse-winner-id",
                    self.args.expected_coarse_winner_id,
                    "--expected-coarse-winner-tau0",
                    self.args.expected_coarse_winner_tau0,
                ])
            self.command(
                action,
                command,
            )
        summary = json.loads(summary_path.read_text())
        if not str(summary.get("status", "")).startswith(("completed", "validation_family_frozen")):
            raise RuntimeError(f"invalid {action} summary: {summary_path}")
        validate_pretest_firewall(summary, label=action)
        return summary

    def launch_grid(self, label: str, grid: Path, expected: int, root: Path) -> None:
        existing = self.grid_counts(root)
        completed = sum(value for key, value in existing.items() if key in SUCCESS)
        failed = sum(value for key, value in existing.items() if key not in SUCCESS)
        if failed:
            raise RuntimeError(f"{label} has prior failed status rows")
        if completed != expected:
            jobs = min(self.args.workers, expected)
            cpus = self.state["cpu_ids"][:jobs]
            self.wait_for_resources(label, cpus)
            self.command(
                f"launch_{label}",
                [
                    PYTHON, GRID_LAUNCHER, "--grid-config", grid,
                    "--priorities", "0", "--experiment-jobs", jobs,
                    "--cell-jobs", "1", "--prepare-data", "true",
                    "--build-windows", "true", "--resume", "true",
                    "--force", "false", "--dry-run", "false",
                    "--cpu-list", self.args.cpu_list,
                ],
            )
        self.wait_grid(label, root, expected, root.name)

    def launch_quantiles(self, prep: dict[str, Any]) -> None:
        task = Path(prep["quantile_task"])
        config = Path(prep["quantile_config"])
        model = Path(prep["quantile_output_dir"])
        summary = model / "pricefm_stage_r93_quantile_run_summary.json"
        if summary.is_file():
            payload = json.loads(summary.read_text())
            if payload.get("status") == "completed_validation_surface" and payload.get("test_loaded") is False:
                self.log("quantile validation surface already complete; reusing it")
                return
        self.wait_for_resources("quantile_ladder", [self.state["cpu_ids"][0]])
        self.command("quantile_adapter", [PYTHON, ADAPTER, "--smoke-config", config, "--force", "true"])
        self.command(
            "quantile_ladder",
            ["taskset", "-c", self.state["cpu_ids"][0], R_SCRIPT, QUANTILE_RUNNER, "--task", task],
        )
        self.command("quantile_summary", [PYTHON, SUMMARIZER, "--smoke-config", config])
        for path in Path(json.loads(task.read_text())["adapter_dir"]).glob("X_*.csv"):
            path.unlink()
        payload = json.loads(summary.read_text())
        if payload.get("status") != "completed_validation_surface" or payload.get("test_loaded") is not False:
            raise RuntimeError("quantile validation runner did not produce a valid sealed summary")

    def run(self) -> dict[str, Any]:
        self.preflight()
        self.wait_grid("ridge", RIDGE_GENERATED, 240, "pricefm_stage_r93_region_frozen_ridge_20260906")

        self.phase("closing_ridge_and_preparing_rhs")
        rhs_summary = RHS_PREP / "summary.json"
        if not rhs_summary.is_file():
            self.quarantine_partial(RHS_PREP, "ridge_to_rhs")
            self.command("ridge_to_rhs", [PYTHON, RIDGE_TO_RHS])
        rhs = json.loads(rhs_summary.read_text())
        if rhs.get("status") != "completed_rhs_prepared_not_launched" or rhs.get("test_opened", False):
            raise RuntimeError("Ridge-to-RHS handoff is invalid")

        self.phase("running_coarse_rhs")
        self.launch_grid(
            "coarse_rhs", RHS_PREP / "pricefm_stage_r93_rhs_grid.yaml", 90, RHS_GENERATED
        )
        self.phase("closing_coarse_rhs")
        coarse = self.run_advance("close-rhs")

        if coarse["refinement"]["refinement_required"]:
            self.phase("running_conditional_rhs_refinement", reason=coarse["refinement"]["reason"])
            self.launch_grid(
                "rhs_refinement", Path(coarse["next_grid"]), 3, REFINE_GENERATED
            )
            self.phase("closing_rhs_refinement")
            frozen_rhs = self.run_advance("close-refinement")
        else:
            frozen_rhs = coarse

        self.phase("running_outer_normal_confirmation", winner_tau0=frozen_rhs["winner_tau0"])
        self.launch_grid(
            "outer_normal", Path(frozen_rhs["next_grid"]), 1, OUTER_GENERATED
        )
        self.phase("closing_outer_and_preparing_quantiles")
        quantile_prep = self.run_advance("close-outer")

        self.phase("running_seven_quantile_validation")
        self.launch_quantiles(quantile_prep)
        self.phase("closing_quantile_validation")
        final = self.run_advance("close-quantile")
        self.state.update({
            "status": "completed_waiting_for_test_audit_authorization",
            "phase": "stopped_before_test_audit",
            "completed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "final_summary": str(self.output / "quantile_validation_closeout/summary.json"),
            "selected_family": final["selected_family"],
            "selected_validation_AQL_original": final["selected_validation_AQL_original"],
            "live": {},
        })
        self.save()
        self.log("R93 validation ladder complete; stopped before test, registry, article, joint, or MCMC work")
        return self.state


def main() -> int:
    args = parser().parse_args()
    controller: Controller | None = None
    try:
        controller = Controller(args)
        result = controller.run()
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        if controller is not None:
            controller.state.update({
                "status": "failed_closed", "error_type": type(exc).__name__,
                "error": str(exc),
                "failed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "test_opened": False, "registry_mutated": False,
                "article_mutated": False, "joint_or_mcmc_authorized": False,
            })
            controller.save()
            controller.log(f"FAILED CLOSED: {type(exc).__name__}: {exc}")
        raise


if __name__ == "__main__":
    raise SystemExit(main())
