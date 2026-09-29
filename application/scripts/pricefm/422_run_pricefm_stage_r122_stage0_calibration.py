#!/usr/bin/env python3
"""Run the isolated, score-blind R122 Stage-0A convergence calibration."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_stage0a_convergence_calibration_20260929"
ALLOWED_SOURCE_OVERRIDES = {"tag", "atom_id", "max_iter", "output_dir"}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--prep-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--cpu-list", required=True)
    value.add_argument("--preflight-only", action="store_true")
    return value


def _json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _cpus(value: str) -> list[int]:
    cpus = [int(item.strip()) for item in value.split(",") if item.strip()]
    if not cpus or len(cpus) != len(set(cpus)):
        raise ValueError("R122 Stage-0A requires distinct CPU IDs")
    return cpus


def _physical_key(cpu: int) -> tuple[int, int]:
    root = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
    return (int((root / "physical_package_id").read_text()), int((root / "core_id").read_text()))


def _cpu_ticks() -> dict[int, tuple[int, int]]:
    result = {}
    for line in Path("/proc/stat").read_text().splitlines():
        if not line.startswith("cpu") or line[:4] == "cpu ":
            continue
        fields = line.split(); cpu = int(fields[0][3:]); values = [int(value) for value in fields[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        result[cpu] = (sum(values), idle)
    return result


def _utilization(cpus: list[int], seconds: float = 2.0) -> dict[int, float]:
    before = _cpu_ticks(); time.sleep(seconds); after = _cpu_ticks(); result = {}
    for cpu in cpus:
        total = after[cpu][0] - before[cpu][0]; idle = after[cpu][1] - before[cpu][1]
        result[cpu] = 0.0 if total <= 0 else 100 * (total - idle) / total
    return result


def _memory_available_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1); values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024 ** 2


def _verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = _json(prep / "summary.json")
    if summary.get("tag") != TAG or not summary.get("launch_authorized"):
        raise RuntimeError("R122 Stage-0A preparation is not launch-authorized")
    for name, expected in summary["output_sha256"].items():
        if sha256_file(prep / name) != expected:
            raise RuntimeError(f"R122 Stage-0A preparation hash mismatch: {name}")
    manifest = pd.read_csv(prep / "contract_manifest.csv")
    for row in manifest.itertuples(index=False):
        if sha256_file(Path(row.contract)) != row.contract_sha256:
            raise RuntimeError(f"R122 Stage-0A contract hash mismatch: {row.contract}")
        contract = _json(Path(row.contract)); source = _json(Path(contract["calibration_source_contract"]))
        if sha256_file(Path(contract["calibration_source_contract"])) != contract["calibration_source_contract_sha256"]:
            raise RuntimeError("R122 Stage-0A source contract changed")
        for key, value in source.items():
            if key not in ALLOWED_SOURCE_OVERRIDES and contract.get(key) != value:
                raise RuntimeError(f"R122 Stage-0A altered posterior field: {key}")
        if contract["posterior_target_sha256"] != source["posterior_target_sha256"]:
            raise RuntimeError("R122 Stage-0A changed posterior target identity")
        required_false = ("score_access_authorized", "selection_authorized", "test_access_authorized",
                          "registry_mutation_authorized", "article_mutation_authorized",
                          "joint_model_authorized", "mcmc_authorized", "exal_authorized")
        if any(contract.get(key) is not False for key in required_false):
            raise RuntimeError("R122 Stage-0A firewall violation")
    return summary, manifest


def preflight(prep: Path, campaign: Path, cpus: list[int]) -> dict[str, Any]:
    summary, manifest = _verify_prep(prep)
    needed = int(manifest[manifest.cap.eq(750)].shape[0])
    if len(cpus) < needed:
        raise RuntimeError(f"R122 Stage-0A needs at least {needed} physical cores")
    keys = [_physical_key(cpu) for cpu in cpus]
    if len(keys) != len(set(keys)):
        raise RuntimeError("R122 Stage-0A CPU list contains logical siblings")
    memory = _memory_available_gib(); disk = shutil.disk_usage(campaign.parent).free / 1024 ** 3
    if memory < float(summary["minimum_memory_gib"]) or disk < float(summary["minimum_free_gib"]):
        raise RuntimeError("R122 Stage-0A resource floor failed")
    usage = _utilization(cpus)
    if any(value > 20 for value in usage.values()):
        raise RuntimeError(f"R122 Stage-0A selected CPU is busy: {usage}")
    result = {"status": "R122_STAGE0A_PREFLIGHT_PASS", "cpus": cpus,
              "physical_keys": [list(value) for value in keys], "cpu_utilization_percent": usage,
              "memory_available_gib": memory, "disk_free_gib": disk,
              "atom_count": needed, "test_opened": False,
              "registry_mutated": False, "article_mutated": False}
    campaign.mkdir(parents=True, exist_ok=True); write_json(campaign / "resource_preflight.json", result)
    return result


def _valid_output(contract: dict[str, Any]) -> bool:
    root = Path(contract["output_dir"]); terminal = root / "terminal.json"; diagnostics = root / "diagnostics.json"
    if not terminal.is_file() or not diagnostics.is_file():
        return False
    value = _json(terminal)
    return (value.get("status") == "completed_r121_quantile_atom"
            and value.get("atom_id") == contract["atom_id"]
            and value.get("posterior_target_sha256") == contract["posterior_target_sha256"]
            and value.get("test_opened") is False)


def _run_atom(contract_path: Path, atom_script: Path, rscript: str, cpu: int, logs: Path) -> dict[str, Any]:
    contract = _json(contract_path)
    if _valid_output(contract):
        return {"contract": str(contract_path), "cpu": cpu, "returncode": 0, "resumed": True}
    environment = os.environ.copy()
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
                 "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "R_DATATABLE_NUM_PROCS"):
        environment[name] = "1"
    logs.mkdir(parents=True, exist_ok=True); log = logs / f"{contract['atom_id']}.log"
    command = ["taskset", "-c", str(cpu), rscript, str(atom_script), "--config", str(contract_path)]
    with log.open("w") as handle:
        handle.write("$ " + " ".join(command) + "\n"); handle.flush()
        completed = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, env=environment, check=False)
    if completed.returncode != 0 or not _valid_output(contract):
        raise RuntimeError(f"R122 Stage-0A atom failed: {contract['atom_id']}")
    return {"contract": str(contract_path), "cpu": cpu, "returncode": 0, "resumed": False}


def _cap(prep: Path, campaign: Path, control: dict[str, Any], manifest: pd.DataFrame,
         cap: int, cpus: list[int]) -> pd.DataFrame:
    rows = manifest[manifest.cap.eq(cap)].sort_values(["candidate_id", "split", "tau"], kind="mergesort")
    futures = []
    with ThreadPoolExecutor(max_workers=len(rows)) as pool:
        for index, row in enumerate(rows.itertuples(index=False)):
            futures.append(pool.submit(_run_atom, Path(row.contract), Path(control["atom_script"]),
                                       control["rscript"], cpus[index], campaign / "logs" / f"cap={cap}"))
        for future in as_completed(futures):
            future.result()
    records = []
    for row in rows.itertuples(index=False):
        contract = _json(Path(row.contract)); diagnostics = _json(Path(contract["output_dir"]) / "diagnostics.json")
        terminal = _json(Path(contract["output_dir"]) / "terminal.json")
        records.append({"cap": cap, "candidate_id": row.candidate_id, "split": int(row.split),
                        "tau": float(row.tau), "atom_id": contract["atom_id"],
                        "posterior_target_sha256": contract["posterior_target_sha256"],
                        "formal_converged": bool(diagnostics["formal_converged"]),
                        "external_gate_passed": bool(diagnostics["external_gate_passed"]),
                        "finite_core": bool(diagnostics["finite_core"]),
                        "absolute_state_tail_max": float(diagnostics["absolute_state_tail_max"]),
                        "relative_state_tail_max": float(diagnostics["relative_state_tail_max"]),
                        "relative_sigma_tail_max": float(diagnostics["relative_sigma_tail_max"]),
                        "relative_elbo_tail_max": float(diagnostics["relative_elbo_tail_max"]),
                        "iterations": int(terminal["iterations"]), "score_opened": False,
                        "test_opened": bool(terminal["test_opened"])})
    result = pd.DataFrame(records)
    result.to_csv(campaign / f"cap={cap}_diagnostics.csv", index=False)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve(); data = artifact / "application/data_local/pricefm"
    prep = (args.prep_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    cpus = _cpus(args.cpu_list); audit = preflight(prep, campaign, cpus)
    if args.preflight_only:
        return audit
    control, manifest = _verify_prep(prep)
    lock = (campaign / "controller.lock").open("a+")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise RuntimeError("another R122 Stage-0A controller owns this campaign") from error
    try:
        all_records = []
        first = _cap(prep, campaign, control, manifest, 750, cpus); all_records.append(first)
        frozen = 750 if first.external_gate_passed.all() else None
        if frozen is None:
            second = _cap(prep, campaign, control, manifest, 1000, cpus); all_records.append(second)
            if second.external_gate_passed.all():
                frozen = 1000
        ledger = pd.concat(all_records, ignore_index=True)
        ledger.to_csv(campaign / "calibration_ledger.csv", index=False)
        status = "R122_STAGE0A_CALIBRATION_PASS" if frozen is not None else "R122_STAGE0A_CALIBRATION_UNRESOLVED"
        policy = {"status": status, "frozen_max_iter": frozen,
                  "eligibility_policy": "r119_scale_aware_external_gate_v1",
                  "candidate_specific_retries": False, "score_opened": False,
                  "test_opened": False, "posterior_target_changed": False}
        write_json(campaign / "frozen_policy.json", policy)
        terminal = {**policy, "stage": "R122_stage0A", "tag": TAG,
                    "atom_count_per_cap": int(manifest[manifest.cap.eq(750)].shape[0]),
                    "caps_run": sorted(int(value) for value in ledger.cap.unique()),
                    "registry_mutated": False, "article_mutated": False,
                    "joint_model_fitted": False, "mcmc_fitted": False, "exal_fitted": False}
        write_json(campaign / "terminal.json", terminal)
        return terminal
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN); lock.close()


def main() -> int:
    try:
        result = run(parser().parse_args())
    except Exception as error:
        print(json.dumps({"status": "R122_STAGE0A_CONTROLLER_FAILED", "error_type": type(error).__name__,
                          "error": str(error)}, indent=2, sort_keys=True))
        return 1
    print(json.dumps(result, indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
