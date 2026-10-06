#!/usr/bin/env python3
"""Run the bounded, resumable R122 Stage-0B AL proxy confirmation."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json
from pricefm_r120_engine import QUANTILES, explicit_arrays, internal_splits, load_windows, standardize_from_training_origins
from pricefm_r121_engine import QUANTILE_ORDER, SEEDS, subset_arrays
from pricefm_r122_engine import paired_cap_predictive_stability, stage0_proxy_decision


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_stage0b_complete_proxy_confirmation_20260930"
THREAD_ENV = ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
              "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_THREADS")


def _load_r121() -> Any:
    path = SCRIPT_DIR / "418_run_pricefm_stage_r121_targeted_dense_refinement.py"
    spec = importlib.util.spec_from_file_location("pricefm_r121_runner_for_r122", path)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader
    spec.loader.exec_module(module); return module


R121 = _load_r121()
PARENT = {0.50: None, 0.45: 0.50, 0.55: 0.50, 0.25: 0.45, 0.75: 0.55, 0.10: 0.25, 0.90: 0.75}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--prep-dir", type=Path); value.add_argument("--campaign-root", type=Path)
    value.add_argument("--cpu-list", required=True); value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--maximum-cpu-percent", type=float, default=20.0)
    return value


def _cpus(value: str) -> list[int]:
    result = [int(item.strip()) for item in value.split(",") if item.strip()]
    if len(result) != 9 or len(set(result)) != 9:
        raise ValueError("R122 Stage-0B requires exactly nine distinct logical CPUs representing nine physical cores")
    physical = []
    for cpu in result:
        root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
        physical.append((int((root / "physical_package_id").read_text()), int((root / "core_id").read_text())))
    if len(set(physical)) != 9:
        raise ValueError("R122 Stage-0B CPU list contains SMT siblings")
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


def _paths(args: argparse.Namespace) -> tuple[Path, Path, Path, Path]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    return artifact, args.code_root.resolve(), (args.prep_dir or data / "launch_prep" / TAG).resolve(), (args.campaign_root or data / "campaigns" / TAG).resolve()


def _command(command: list[str], code: Path, log: Path, cpu: int) -> None:
    log.parent.mkdir(parents=True, exist_ok=True); env = dict(os.environ); env.update({name: "1" for name in THREAD_ENV})
    actual = ["taskset", "-c", str(cpu), *command]
    with log.open("a") as handle:
        handle.write("$ " + " ".join(actual) + "\n"); handle.flush()
        result = subprocess.run(actual, cwd=str(code), env=env, stdout=handle, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError(f"R122 Stage-0B atom failed ({result.returncode})")


def _valid_output(path: Path, expected_target: str) -> bool:
    try:
        value = json.loads((path / "terminal.json").read_text())
        return value.get("status") == "completed_r121_quantile_atom" and value.get("test_opened") is False and value.get("posterior_target_sha256") == expected_target
    except (OSError, json.JSONDecodeError):
        return False


def _contract(control: dict[str, Any], code: Path, candidate: str, split: int, tau: float, tau0: float,
              design: Path, parent: Path, parent_type: str, output: Path, max_iter: int) -> dict[str, Any]:
    sources = pd.read_csv(Path(control["r121b_prep"]) / "source_manifest.csv")
    adapter = Path(sources[sources.path.str.endswith("pricefm_stage_r67_cran111_adapter.R")].iloc[0].path)
    manifest = Path(control["cran_manifest"]); design_hash = sha256_file(design / "terminal.json")
    return {"stage": "R122_internal_selection", "tag": TAG,
        "atom_id": f"r122_stage0b_{candidate}_s{split}_q{tau:.2f}_i{max_iter}",
        "candidate_id": candidate, "readout": "pure_all_layers", "fold": 1, "split": split,
        "family": "al", "tau": tau, "tau0": tau0, "design_dir": str(design), "output_dir": str(output),
        "parent_dir": str(parent), "parent_type": parent_type, "parent_label": parent.name,
        "cran_library": control["cran_library"], "cran_manifest": str(manifest), "cran_manifest_sha256": sha256_file(manifest),
        "cran_adapter": str(adapter), "cran_adapter_sha256": sha256_file(adapter),
        "design_terminal_sha256": design_hash, "parent_terminal_sha256": sha256_file(parent / "terminal.json"),
        "training_split": "fold1_internal_training_only", "max_iter": max_iter, "tol": 1e-5,
        "n_samp_xi": 20, "n_samp": 20, "seed": int(SEEDS[0] + 1000 + split * 100 + round(tau * 100)),
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
        "posterior_target_sha256": design_hash + f":tau={tau:.2f}:tau0={tau0:.17g}"}


def _write_contract(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and json.loads(path.read_text()) != value:
        raise RuntimeError(f"immutable R122 Stage-0B contract changed: {path}")
    write_json(path, value)


def _ladder(row: Any, control: dict[str, Any], code: Path, campaign: Path, cpu: int) -> dict[str, Any]:
    candidate, split, tau0 = str(row.candidate_id), int(row.split), float(row.tau0)
    design, normal = Path(row.design_dir), Path(row.normal_parent_dir)
    root = campaign / f"ladders/{candidate}/split={split}"
    metric_path = root / "metrics.json"
    if metric_path.is_file():
        return json.loads(metric_path.read_text())
    accepted: list[dict[str, Any]] = []
    for tau in QUANTILE_ORDER:
        tau = float(tau); parent_tau = PARENT[tau]
        parent = normal if parent_tau is None else root / f"quantiles/al/tau={parent_tau:.2f}"
        parent_type = "normal_rhs" if parent_tau is None else "quantile"
        final = root / f"quantiles/al/tau={tau:.2f}"
        final_contract = _contract(control, code, candidate, split, tau, tau0, design, parent, parent_type, final, 1000)
        final_contract_path = root / f"contracts/final/tau={tau:.2f}.json"; _write_contract(final_contract_path, final_contract)
        if not _valid_output(final, final_contract["posterior_target_sha256"]):
            _command([control["rscript"], str(code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                      "--config", str(final_contract_path)], code, root / f"logs/final_tau={tau:.2f}.log", cpu)
        diagnostics = json.loads((final / "diagnostics.json").read_text())
        method, pair = "raw_external_gate", None
        passed = bool(diagnostics["external_gate_passed"])
        if not passed:
            companion = root / f"companions/cap=750/tau={tau:.2f}"
            companion_contract = _contract(control, code, candidate, split, tau, tau0, design, parent, parent_type, companion, 750)
            companion_contract_path = root / f"contracts/companions/tau={tau:.2f}.json"; _write_contract(companion_contract_path, companion_contract)
            if not _valid_output(companion, companion_contract["posterior_target_sha256"]):
                _command([control["rscript"], str(code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"),
                          "--config", str(companion_contract_path)], code, root / f"logs/companion_tau={tau:.2f}.log", cpu)
            pair = paired_cap_predictive_stability(design, companion, final); passed = bool(pair["passed"]); method = "paired_cap_fitted_function_gate_v1"
            (root / "paired_cap").mkdir(parents=True, exist_ok=True)
            write_json(root / f"paired_cap/tau={tau:.2f}.json", pair)
        accepted.append({"tau": tau, "accepted": passed, "acceptance_method": method,
                         "raw_external_gate_passed": bool(diagnostics["external_gate_passed"]),
                         "pair_classification": None if pair is None else pair["classification"]})
        if not passed:
            result = {"candidate_id": candidate, "tau0": tau0, "split": split, "eligible": False,
                      "invalid_quantiles": 1, "accepted_quantiles": accepted, "test_opened": False}
            root.mkdir(parents=True, exist_ok=True); write_json(metric_path, result); return result

    prep = Path(control["r121b_prep"]); _, spec = R121._candidate(prep, candidate)
    arrays = explicit_arrays(load_windows(Path(control["runtime_processed"]), 1, "train", spec), spec)
    item = internal_splits(len(arrays.response))[split - 1]
    scaled, scaler = standardize_from_training_origins(arrays, item["train"])
    score = R121._score_family(subset_arrays(scaled, item["validation"]), spec, normal, root,
                               float(scaler["price_scale"]), float(scaler["price_mean"]), SEEDS[0] + split)
    result = {"candidate_id": candidate, "tau0": tau0, "split": split, "eligible": True,
              "invalid_quantiles": 0, **score, "accepted_quantiles": accepted,
              "test_opened": False, "score_scope": "fold1_training_internal_validation_only"}
    write_json(metric_path, result); return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact, code, prep, campaign = _paths(args); control = json.loads((prep / "launch_control.json").read_text())
    cpus = _cpus(args.cpu_list); sources = pd.read_csv(prep / "source_manifest.csv")
    changed = [str(row.path) for row in sources.itertuples(index=False) if not Path(row.path).is_file() or sha256_file(Path(row.path)) != str(row.sha256)]
    usage = _cpu_snapshot(); core_usage = {cpu: max(value for sibling, value in usage.items() if _physical(sibling) == _physical(cpu)) for cpu in cpus}
    free_gib = shutil.disk_usage(campaign.parent).free / 2**30
    available_kib = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:"))
    checks = {"source_hashes": not changed, "nine_cpus": len(cpus) == 9,
              "python_runtime": Path(sys.executable).absolute() == Path(control["python_executable"]) and
                                Path(sys.prefix).absolute() == Path(control["python_prefix"]),
              "selected_physical_cores_idle": max(core_usage.values()) <= float(args.maximum_cpu_percent),
              "memory_floor": available_kib / 2**20 >= float(control["minimum_memory_gib"]),
              "disk_floor": free_gib >= float(control["minimum_free_gib"]),
              "test_firewall": control["test_access_authorized"] is False}
    preflight = {"status": "R122_STAGE0B_PREFLIGHT_PASS" if all(checks.values()) else "R122_STAGE0B_PREFLIGHT_BLOCKED",
                 "checks": checks, "changed_sources": changed, "cpus": cpus,
                 "physical_core_max_percent": core_usage,
                 "available_memory_gib": available_kib / 2**20, "free_disk_gib": free_gib, "test_opened": False}
    campaign.mkdir(parents=True, exist_ok=True); write_json(campaign / "launch_preflight.json", preflight)
    if not all(checks.values()): raise RuntimeError(f"R122 Stage-0B preflight blocked: {preflight}")
    if args.preflight_only: return preflight

    ladders = pd.read_csv(prep / "ladder_manifest.csv"); records: list[dict[str, Any]] = []
    lock = threading.Lock(); progress = {"total": len(ladders), "complete": 0, "failed": 0, "updated_at_epoch": time.time()}
    def one(index: int, row: Any) -> dict[str, Any]:
        try:
            result = _ladder(row, control, code, campaign, cpus[index])
            ok = bool(result.get("eligible"))
        except Exception as error:
            result = {"candidate_id": str(row.candidate_id), "split": int(row.split), "eligible": False,
                      "error_type": type(error).__name__, "error": str(error), "test_opened": False}; ok = False
        with lock:
            progress["complete" if ok else "failed"] += 1; progress["updated_at_epoch"] = time.time()
            write_json(campaign / "progress.json", progress)
        return result
    with ThreadPoolExecutor(max_workers=9) as pool:
        futures = [pool.submit(one, index, row) for index, row in enumerate(ladders.itertuples(index=False))]
        for future in as_completed(futures): records.append(future.result())
    cells = pd.DataFrame(records).sort_values(["candidate_id", "split"]); closeout = campaign / "closeout"; closeout.mkdir(exist_ok=True)
    cells.to_csv(closeout / "cell_metrics.csv", index=False)
    eligible = cells[cells.eligible.astype(bool)].copy()
    ranking = eligible.groupby(["candidate_id", "tau0"], as_index=False).filter(lambda group: set(group.split) == {1, 2, 3})
    if len(ranking):
        ranking = ranking.groupby(["candidate_id", "tau0"], as_index=False).agg(
            mean_AQL=("AQL", "mean"), mean_late_AQL=("late_AQL", "mean"), worst_AQL=("AQL", "max"),
            mean_coverage=("interval_80_coverage", "mean"), mean_width=("interval_80_width", "mean"),
            mean_crossing=("crossing_rate", "mean")).sort_values(["mean_AQL", "mean_late_AQL", "worst_AQL", "candidate_id"])
    ranking.to_csv(closeout / "ranking.csv", index=False)
    normal = pd.read_csv(prep / "normal_shortlist.csv")
    decision = stage0_proxy_decision(normal, cells) if len(cells) == 9 and cells.eligible.astype(bool).all() else {
        "status": "R122_STAGE0B_INCOMPLETE", "passed": False, "completed_eligible_ladders": int(cells.eligible.astype(bool).sum())}
    write_json(closeout / "proxy_decision.json", decision)
    terminal = {"stage": "R122_stage0B", "tag": TAG,
                "status": "R122_STAGE0B_PROXY_AUTHORIZED" if decision.get("passed") else "R122_STAGE0B_PROXY_REJECTED",
                "proxy_authorized": bool(decision.get("passed")), "eligible_ladders": int(cells.eligible.astype(bool).sum()),
                "total_ladders": 9, "final_max_iter": 1000, "test_opened": False,
                "article_mutated": False, "registry_mutated": False, "joint_model_fitted": False,
                "mcmc_fitted": False, "exal_fitted": False}
    write_json(campaign / "terminal.json", terminal); return terminal


def main() -> int:
    try:
        print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0
    except Exception as error:
        print(json.dumps({"status": "R122_STAGE0B_CONTROLLER_FAILED", "error_type": type(error).__name__, "error": str(error)}, indent=2)); return 1


if __name__ == "__main__":
    raise SystemExit(main())
