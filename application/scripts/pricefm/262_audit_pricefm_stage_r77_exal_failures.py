#!/usr/bin/env python3
"""Build a read-only failure atlas for the completed R76 exAL surface."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r76_repaired_exal_surface_20260902"
GRID = DATA / "experiment_grids" / TAG
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
OUTPUT = DATA / "authoritative/pricefm_stage_r77_exal_failure_atlas_20260904"
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "task_manifest.csv")
    p.add_argument("--status", type=Path, default=GRID / "launch_status.csv")
    p.add_argument("--launch-summary", type=Path, default=GRID / "launch_summary.json")
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(message: str) -> str:
    if "no finite gamma grid" in message.lower():
        return "structured_gamma_grid_nonfinite"
    if "finite-output or structured-update contract" in message.lower():
        return "aggregate_terminal_contract_unresolved"
    return "fit_exception_other"


def prepare(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    status = pd.read_csv(args.status)
    launch = json.loads(args.launch_summary.read_text())
    if len(manifest) != 294 or len(status) != 294 or set(manifest.task_id) != set(status.task_id):
        raise RuntimeError("R76 terminal surface is not the registered 294-task campaign")
    if launch.get("completed") != 280 or launch.get("failed") != 14:
        raise RuntimeError("R76 launch summary does not match the frozen terminal state")

    status_by_id = status.set_index("task_id")
    ledger: list[dict[str, Any]] = []
    neighbors: list[dict[str, Any]] = []
    sources = [Path(__file__).resolve(), args.manifest.resolve(), args.status.resolve(),
               args.launch_summary.resolve()]
    for task in manifest.itertuples(index=False):
        state = str(status_by_id.loc[task.task_id, "status"])
        output = Path(task.output_dir)
        terminal_path = output / "terminal.json"
        terminal = json.loads(terminal_path.read_text())
        sources.extend([terminal_path, output / "worker.log"])
        if state != "failed":
            continue
        message = str(terminal.get("error_message", ""))
        worker = (output / "worker.log").read_text()
        started = json.loads((output / "started.json").read_text())
        sources.append(output / "started.json")
        ledger.append({
            "task_id": task.task_id, "case_id": task.case_id, "region": task.region,
            "fold": int(task.fold), "tau": float(task.tau),
            "mechanism_class": classify(message), "error_message": message,
            "depth_D": int(task.depth_D), "units_json": task.units_json,
            "lag_window": int(task.lag_window), "feature_policy": task.feature_policy,
            "alpha": float(task.alpha), "rho": float(task.rho),
            "input_scale": float(task.input_scale), "rhs_tau0": float(task.rhs_tau0),
            "max_iter": int(task.max_iter), "structured_grid_size": int(task.structured_grid_size),
            "structured_span_sd": float(task.structured_span_sd),
            "output_dir": str(output), "terminal_sha256": sha256(terminal_path),
            "worker_log_sha256": sha256(output / "worker.log"),
            "started_pid": int(started["pid"]), "worker_log_bytes": len(worker.encode()),
            "test_opened": False,
        })
        case_rows = manifest[(manifest.case_id == task.case_id) & (manifest.task_id != task.task_id)]
        for other in case_rows.itertuples(index=False):
            other_state = str(status_by_id.loc[other.task_id, "status"])
            if other_state != "completed":
                continue
            other_output = Path(other.output_dir)
            method = pd.read_csv(other_output / "method_summary.csv").iloc[0]
            parameter = pd.read_csv(other_output / "parameter_summary.csv").iloc[0]
            trace = pd.read_csv(other_output / "vb_trace.csv")
            sources.extend([other_output / "method_summary.csv", other_output / "parameter_summary.csv",
                            other_output / "vb_trace.csv"])
            neighbors.append({
                "failed_task_id": task.task_id, "case_id": task.case_id,
                "failed_tau": float(task.tau), "neighbor_tau": float(other.tau),
                "tau_distance": abs(float(task.tau) - float(other.tau)),
                "neighbor_converged": bool(method["converged"]),
                "neighbor_iter": int(method["iter"]),
                "neighbor_structured_updates": int(method["structured_updates"]),
                "neighbor_sigma": float(parameter["sigma"]),
                "neighbor_gamma": float(parameter["gamma"]),
                "neighbor_final_delta_state": float(trace["delta_state"].iloc[-1]),
            })

    failed = pd.DataFrame(ledger).sort_values(["tau", "region", "fold"])
    near = pd.DataFrame(neighbors).sort_values(["failed_task_id", "tau_distance", "neighbor_tau"])
    if len(failed) != 14:
        raise RuntimeError(f"Expected 14 frozen failures, observed {len(failed)}")
    nearest = near.groupby("failed_task_id", as_index=False).first()
    retry = failed.merge(nearest[["failed_task_id", "neighbor_sigma", "neighbor_gamma",
                                  "neighbor_converged", "neighbor_final_delta_state"]],
                         left_on="task_id", right_on="failed_task_id", how="left")
    retry["diagnosis_sufficient_for_retry"] = retry.mechanism_class.ne(
        "aggregate_terminal_contract_unresolved"
    )
    retry["retry_eligible"] = False
    retry["retry_block_reason"] = np.where(
        retry.diagnosis_sufficient_for_retry,
        "mechanism_repair_not_yet_validated",
        "failure_component_not_observed",
    )
    mechanism = (failed.groupby(["mechanism_class", "tau"], as_index=False)
                 .agg(failed_atoms=("task_id", "count"), cases=("case_id", "nunique")))
    gates = pd.DataFrame([
        {"gate": "r76_terminal_state_frozen", "passed": True, "observed": "280 completed; 14 failed"},
        {"gate": "all_failures_classified", "passed": failed.mechanism_class.notna().all(),
         "observed": failed.mechanism_class.value_counts().to_dict()},
        {"gate": "failure_components_observed", "passed": retry.diagnosis_sufficient_for_retry.all(),
         "observed": int(retry.diagnosis_sufficient_for_retry.sum())},
        {"gate": "general_numerical_repair_validated", "passed": False, "observed": "not yet"},
        {"gate": "bounded_retry_authorized", "passed": False, "observed": 0},
        {"gate": "test_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    output = prepare(args.output_dir, args.force)
    failed.to_csv(output / "pricefm_stage_r77_failed_atom_ledger.csv", index=False)
    near.to_csv(output / "pricefm_stage_r77_neighbor_comparison.csv", index=False)
    mechanism.to_csv(output / "pricefm_stage_r77_failure_mechanism_summary.csv", index=False)
    retry.to_csv(output / "pricefm_stage_r77_retry_eligibility.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r77_gates.csv", index=False)
    unique_sources = list(dict.fromkeys(path.resolve() for path in sources))
    pd.DataFrame([{"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
                  for path in unique_sources]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "failure_atlas_complete_retry_blocked",
        "r76_tasks": 294, "completed_atoms": 280, "failed_atoms": 14,
        "failed_cases": int(failed.case_id.nunique()),
        "failures_tau_0p25": int((failed.tau == 0.25).sum()),
        "failures_tau_0p75": int((failed.tau == 0.75).sum()),
        "explicit_gamma_grid_failures": int((failed.mechanism_class == "structured_gamma_grid_nonfinite").sum()),
        "unresolved_aggregate_contract_failures": int((failed.mechanism_class == "aggregate_terminal_contract_unresolved").sum()),
        "retry_atoms_authorized": 0, "test_opened": False,
        "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r77_failure_atlas_report.md").write_text(
        "# PriceFM Stage-R77 exAL Failure Atlas\n\n"
        "R76 ended with 280 completed and 14 failed atoms. Failures are confined to tau 0.25 "
        "and 0.75. One failure identifies a non-finite structured gamma grid; thirteen terminate "
        "at an aggregate finite-output contract that does not identify the failed field. Therefore "
        "no retry is authorized until field-level failure observability and a general numerical "
        "repair are validated. Test, registry, and article gates remain closed.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
