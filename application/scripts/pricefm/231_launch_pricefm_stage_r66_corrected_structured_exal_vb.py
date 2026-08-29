#!/usr/bin/env python3
"""Launch R66 only after its first real production case passes the mechanism gate."""

from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r66_corrected_structured_exal_vb_20260829"
MANIFEST = DATA / "experiment_grids" / TAG / "case_manifest.csv"
PYTHON = DATA / "venv/bin/python"
METHODS = {
    "qdesn_al_rhs_ns_exact_chunked_r66_parity",
    "qdesn_exal_rhs_ns_exact_chunked_structured_corrected_r66",
}
METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r66_parity"
METHOD_EXAL = "qdesn_exal_rhs_ns_exact_chunked_structured_corrected_r66"
TAUS = {0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--minimum-free-gib", type=float, default=150.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=100.0)
    p.add_argument("--gate-max-exal-al-ratio", type=float, default=1.5)
    p.add_argument("--gate-max-crossing-rate", type=float, default=0.20)
    p.add_argument("--gate-max-crossing-increase", type=float, default=0.10)
    p.add_argument("--authorize", type=parse_bool, default=False)
    return p


def parse_cpus(value: str) -> list[int]:
    cpus = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            low, high = token.split("-", 1)
            cpus.extend(range(int(low), int(high) + 1))
        else:
            cpus.append(int(token))
    if not cpus or len(cpus) != len(set(cpus)):
        raise ValueError("CPU list must contain unique CPU IDs")
    online = set(range(os.cpu_count() or 0))
    if not set(cpus).issubset(online):
        raise ValueError(f"CPU list is outside online CPUs: {sorted(set(cpus) - online)}")
    return cpus


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def boolish_series(series: pd.Series) -> pd.Series:
    return series.map(lambda value: str(value).strip().lower() in {"1", "true", "yes", "y"})


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict:
    if not args.authorize:
        raise RuntimeError("Production R66 launch requires --authorize true")
    if len(manifest) != args.expected_cases or manifest.duplicated(["region", "fold"]).any():
        raise RuntimeError(f"Expected {args.expected_cases} unique R66 cases")
    if "production_gate_case" not in manifest or int(
        manifest.production_gate_case.map(lambda value: str(value).lower() == "true").sum()
    ) != 1:
        raise RuntimeError("R66 requires exactly one real production gate case")
    blocked = [
        "launch_authorized",
        "test_access_authorized",
        "registry_mutation_authorized",
        "article_mutation_authorized",
        "joint_model_authorized",
        "mcmc_authorized",
    ]
    for column in blocked:
        if manifest[column].map(lambda value: str(value).lower() == "true").any():
            raise RuntimeError(f"Prepared manifest must keep {column} declaratively false")
    if args.workers < 20:
        raise RuntimeError("The authorized R66 production launch requires at least 20 workers")
    if len(cpus) < args.workers:
        raise RuntimeError("Need one unique logical CPU per worker")
    usage = shutil.disk_usage(DATA)
    free_gib = usage.free / 1024**3
    memory_gib = available_memory_gib()
    if free_gib < args.minimum_free_gib:
        raise RuntimeError(f"Only {free_gib:.1f} GiB free; R66 requires {args.minimum_free_gib:.1f} GiB")
    if memory_gib < args.minimum_available_memory_gib:
        raise RuntimeError(
            f"Only {memory_gib:.1f} GiB available memory; R66 requires {args.minimum_available_memory_gib:.1f} GiB"
        )
    return {
        "manifest_cases": len(manifest),
        "workers": args.workers,
        "cpu_ids": cpus[: args.workers],
        "free_disk_gib": round(free_gib, 3),
        "available_memory_gib": round(memory_gib, 3),
        "one_process_per_cpu": True,
        "numerical_threads_per_process": 1,
        "test_access": False,
        "broad_launch_requires_real_case_gate": True,
    }


def completion_state(output: Path) -> str | None:
    required = [
        output / "r66_case_fit_summary.json",
        output / "run_manifest.json",
        output / "r66_component_status.csv",
        output / "model_predictions_scaled.csv",
        output / "model_method_summary.csv",
        output / "metric_summary.csv",
    ]
    if not all(path.is_file() for path in required):
        return None
    summary = json.loads((output / "r66_case_fit_summary.json").read_text())
    if int(summary.get("terminal_components", -1)) != 7 or bool(summary.get("test_loaded")):
        return None
    predictions = pd.read_csv(output / "model_predictions_scaled.csv", usecols=["method_id", "split", "tau"])
    if set(predictions.method_id.astype(str)) != METHODS or set(predictions.split.astype(str)) != {"val"}:
        return None
    for method, group in predictions.groupby("method_id"):
        if {round(float(value), 12) for value in group.tau.unique()} != TAUS:
            return None
    metrics = pd.read_csv(output / "metric_summary.csv")
    selected = metrics[
        metrics.method_id.astype(str).isin(METHODS)
        & metrics.split.astype(str).eq("val")
        & metrics.unit.astype(str).eq("original")
    ]
    if set(selected.method_id.astype(str)) != METHODS or len(selected) != 2:
        return None
    return "completed" if int(summary.get("eligible_components", -1)) == 7 else "completed_with_quarantine"


def crossing_rate(predictions: pd.DataFrame, method: str) -> float:
    selected = predictions[predictions.method_id.astype(str).eq(method)].copy()
    wide = selected.pivot_table(
        index=["origin_id", "horizon"], columns="tau", values="pred_scaled", aggfunc="first"
    ).sort_index(axis=1)
    if list(round(float(value), 12) for value in wide.columns) != sorted(TAUS):
        raise RuntimeError(f"Incomplete seven-quantile surface for {method}")
    values = wide.to_numpy()
    return float((values[:, 1:] < values[:, :-1]).mean())


def evaluate_production_gate(output: Path, args: argparse.Namespace) -> tuple[pd.DataFrame, dict]:
    component = pd.read_csv(output / "r66_component_status.csv").sort_values("tau")
    metric = pd.read_csv(output / "metric_summary.csv")
    predictions = pd.read_csv(output / "model_predictions_scaled.csv")
    if len(component) != 7 or set(round(float(value), 12) for value in component.tau) != TAUS:
        raise RuntimeError("R66 production gate lacks seven terminal components")
    if set(predictions.split.astype(str)) != {"val"}:
        raise RuntimeError("R66 production gate prediction firewall failed")

    def metric_value(method: str) -> float:
        selected = metric[
            metric.method_id.astype(str).eq(method)
            & metric.split.astype(str).eq("val")
            & metric.unit.astype(str).eq("original")
        ]
        if len(selected) != 1:
            raise RuntimeError(f"Missing gate metric for {method}")
        return float(selected.iloc[0].AQL)

    al_aql = metric_value(METHOD_AL)
    exal_aql = metric_value(METHOD_EXAL)
    al_crossing = crossing_rate(predictions, METHOD_AL)
    exal_crossing = crossing_rate(predictions, METHOD_EXAL)
    gamma = component.set_index(component.tau.round(12)).gamma.astype(float).to_dict()
    orientation = bool(gamma[0.10] > gamma[0.90] and gamma[0.25] > gamma[0.75])
    rows = [
        {"gate": "seven_components_converged", "required": True, "passed": boolish_series(component.al_converged).all() and boolish_series(component.exal_converged).all(), "observed": int(boolish_series(component.exal_converged).sum()), "threshold": 7},
        {"gate": "corrected_structured_telemetry", "required": True, "passed": boolish_series(component.structured_telemetry_pass).all(), "observed": int(boolish_series(component.structured_telemetry_pass).sum()), "threshold": 7},
        {"gate": "exact_conditional_gig_final_moments", "required": True, "passed": boolish_series(component.exact_conditional_gig_moment_pass).all() and set(component.moment_source.astype(str)) == {"conditional_gig_exact"}, "observed": int(boolish_series(component.exact_conditional_gig_moment_pass).sum()), "threshold": 7},
        {"gate": "continuation_start_no_fallback", "required": True, "passed": boolish_series(component.continuation_start_pass).all() and not boolish_series(component.optimizer_used_fallback).any(), "observed": int(boolish_series(component.continuation_start_pass).sum()), "threshold": 7},
        {"gate": "minimum_exact_commits", "required": True, "passed": (component.exact_commit_count.astype(int) >= 5).all(), "observed": int(component.exact_commit_count.astype(int).min()), "threshold": 5},
        {"gate": "finite_interior_gamma_sigma", "required": True, "passed": component.gamma.notna().all() and component.sigma.notna().all() and (component.sigma.astype(float) > 0).all() and (component.gamma_relative_boundary_margin.astype(float) >= 1e-6).all(), "observed": float(component.gamma_relative_boundary_margin.astype(float).min()), "threshold": 1e-6},
        {"gate": "bounded_validation_aql_harm", "required": True, "passed": exal_aql / al_aql <= args.gate_max_exal_al_ratio, "observed": exal_aql / al_aql, "threshold": args.gate_max_exal_al_ratio},
        {"gate": "bounded_quantile_crossing", "required": True, "passed": exal_crossing <= args.gate_max_crossing_rate and exal_crossing - al_crossing <= args.gate_max_crossing_increase, "observed": exal_crossing, "threshold": args.gate_max_crossing_rate},
        {"gate": "tail_gamma_orientation_diagnostic", "required": False, "passed": orientation, "observed": f"g.1={gamma[0.10]:.6g};g.9={gamma[0.90]:.6g}", "threshold": "lower-tail gamma exceeds upper-tail gamma"},
        {"gate": "test_firewall", "required": True, "passed": set(predictions.split.astype(str)) == {"val"}, "observed": "val", "threshold": "val only"},
    ]
    frame = pd.DataFrame(rows)
    required = boolish_series(frame.required)
    passed = bool(boolish_series(frame.loc[required, "passed"]).all())
    summary = {
        "status": "production_gate_passed" if passed else "production_gate_blocked",
        "passed": passed,
        "al_validation_AQL": al_aql,
        "corrected_exal_validation_AQL": exal_aql,
        "corrected_exal_to_al_AQL_ratio": exal_aql / al_aql,
        "al_crossing_rate": al_crossing,
        "corrected_exal_crossing_rate": exal_crossing,
        "tail_gamma_orientation_diagnostic": orientation,
        "test_opened": False,
        "broad_launch_authorized_by_gate": passed,
    }
    return frame, summary


def run_one(row: dict, cpu: int, code_root: Path, python_bin: Path) -> dict:
    output = Path(row["output_dir"])
    case_root = output.parent
    log = case_root / "worker.log"
    case_root.mkdir(parents=True, exist_ok=True)
    existing = completion_state(output)
    if existing:
        return {
            **row,
            "cpu": cpu,
            "status": f"skipped_{existing}",
            "returncode": 0,
            "elapsed_seconds": 0.0,
            "worker_log": str(log),
        }

    env = dict(os.environ)
    for key in (
        "OMP_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS",
        "RCPP_PARALLEL_NUM_THREADS",
        "BLIS_NUM_THREADS",
    ):
        env[key] = "1"
    commands = [
        [
            "taskset",
            "-c",
            str(cpu),
            "Rscript",
            str(code_root / "application/scripts/pricefm/230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R"),
            "--case-config",
            row["config"],
            "--force",
            "false",
        ],
        [
            "taskset",
            "-c",
            str(cpu),
            str(python_bin),
            str(code_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
            "--smoke-config",
            row["config"],
            "--run-dir",
            row["output_dir"],
        ],
    ]
    started = time.time()
    returncode = 0
    with log.open("a") as handle:
        handle.write(f"START stage=R66 case={row['case_id']} cpu={cpu} time={time.time()}\n")
        handle.flush()
        for command in commands:
            handle.write("COMMAND " + " ".join(command) + "\n")
            handle.flush()
            result = subprocess.run(
                command,
                cwd=code_root,
                env=env,
                stdout=handle,
                stderr=subprocess.STDOUT,
            )
            returncode = int(result.returncode)
            if returncode:
                break
        state = completion_state(output)
        handle.write(f"END returncode={returncode} state={state} time={time.time()}\n")
    status = state if returncode == 0 and state else "failed"
    return {
        **row,
        "cpu": cpu,
        "status": status,
        "returncode": returncode,
        "elapsed_seconds": round(time.time() - started, 3),
        "worker_log": str(log),
    }


def write_status(path: Path, rows: list[dict], lock: threading.Lock) -> None:
    with lock:
        frame = pd.DataFrame(rows).sort_values(["region", "fold"])
        temp = path.with_suffix(path.suffix + ".tmp")
        frame.to_csv(temp, index=False)
        temp.replace(path)


def status_counts(rows: list[dict]) -> dict[str, int]:
    return {
        str(status): int(count)
        for status, count in pd.Series([row["status"] for row in rows]).value_counts().sort_index().items()
    }


def run(args: argparse.Namespace) -> dict:
    code_root = args.code_root.resolve()
    manifest_path = args.manifest.resolve()
    manifest = pd.read_csv(manifest_path).sort_values(["region", "fold"]).reset_index(drop=True)
    cpus = parse_cpus(args.cpu_list)
    audit = preflight(manifest, args, cpus)
    status_path = manifest_path.parent / "launch_status.csv"
    write_json(manifest_path.parent / "launch_preflight.json", audit)
    results = []
    lock = threading.Lock()
    gate_mask = boolish_series(manifest.production_gate_case)
    gate_row = manifest.loc[gate_mask].iloc[0].to_dict()
    gate_result = run_one(gate_row, cpus[0], code_root, args.python_bin.absolute())
    results.append(gate_result)
    write_status(status_path, results, lock)
    gate_output = Path(gate_row["output_dir"])
    if gate_result["returncode"] == 0 and completion_state(gate_output):
        gate_frame, gate_summary = evaluate_production_gate(gate_output, args)
    else:
        gate_frame = pd.DataFrame([{
            "gate": "real_production_case_completed",
            "required": True,
            "passed": False,
            "observed": gate_result["status"],
            "threshold": "completed",
        }])
        gate_summary = {
            "status": "production_gate_blocked",
            "passed": False,
            "test_opened": False,
            "broad_launch_authorized_by_gate": False,
        }
    gate_frame.to_csv(manifest_path.parent / "production_gate.csv", index=False)
    write_json(manifest_path.parent / "production_gate.json", gate_summary)
    if not gate_summary["passed"]:
        result = {
            "status": "broad_launch_blocked_by_real_case_gate",
            **audit,
            "production_gate_case": gate_row["case_id"],
            "production_gate": gate_summary,
            "status_counts": status_counts(results),
            "test_opened": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        }
        write_json(manifest_path.parent / "launch_summary.json", result)
        raise RuntimeError(f"R66 broad launch blocked by the real-case gate: {gate_summary}")

    pending_rows = iter(manifest.loc[~gate_mask].to_dict("records"))
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {}

        def submit_next(cpu: int) -> bool:
            try:
                row = next(pending_rows)
            except StopIteration:
                return False
            future = pool.submit(
                run_one,
                row,
                cpu,
                code_root,
                args.python_bin.absolute(),
            )
            futures[future] = (row, cpu)
            return True

        for cpu in cpus[: args.workers]:
            submit_next(cpu)

        while futures:
            done, _ = wait(futures, return_when=FIRST_COMPLETED)
            for future in done:
                row, cpu = futures.pop(future)
                try:
                    results.append(future.result())
                except Exception as exc:
                    results.append({
                        **row,
                        "cpu": cpu,
                        "status": "launcher_exception",
                        "returncode": 99,
                        "error": repr(exc),
                    })
                write_status(status_path, results, lock)
                submit_next(cpu)

    counts = status_counts(results)
    failures = sum(count for status, count in counts.items() if status in {"failed", "launcher_exception"})
    result = {
        "status": "completed" if not failures else "completed_with_failures",
        **audit,
        "production_gate_case": gate_row["case_id"],
        "production_gate": gate_summary,
        "status_counts": counts,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(manifest_path.parent / "launch_summary.json", result)
    if failures:
        raise RuntimeError(f"R66 completed with {failures} failed case jobs: {counts}")
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
