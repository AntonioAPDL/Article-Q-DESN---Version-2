#!/usr/bin/env python3
"""Launch the authorized Stage-R70 CRAN 1.1.1 independent VB refit campaign."""

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
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
MANIFEST = DATA / "experiment_grids" / TAG / "case_manifest.csv"
PYTHON = DATA / "venv/bin/python"
METHOD_AL = "qdesn_al_rhs_ns_cran111_r69b"
METHOD_EXAL = "qdesn_exal_rhs_ns_cran111_r69b"
METHODS = {METHOD_AL, METHOD_EXAL}
TAUS = {0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90}
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
BLOCKED_COLUMNS = [
    "launch_authorized",
    "launcher_invoked_by_prep",
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, required=True)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--cpu-list", default="")
    p.add_argument("--expected-cases", type=int, default=56)
    p.add_argument("--minimum-free-gib", type=float, default=75.0)
    p.add_argument("--minimum-available-memory-gib", type=float, default=60.0)
    p.add_argument("--authorize", type=parse_bool, default=False)
    p.add_argument("--preflight-only", type=parse_bool, default=False)
    return p


def parse_cpus(value: str) -> list[int]:
    cpus: list[int] = []
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


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def available_memory_gib() -> float:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.strip().split()[0])
    return values["MemAvailable"] / 1024**2


def cpu_usage_snapshot() -> dict[int, float]:
    result = subprocess.run(
        ["ps", "-e", "-o", "psr=,pcpu="],
        text=True,
        capture_output=True,
        check=False,
    )
    usage = {cpu: 0.0 for cpu in range(os.cpu_count() or 0)}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            cpu = int(parts[0])
            pcpu = float(parts[1])
        except ValueError:
            continue
        if cpu in usage:
            usage[cpu] += pcpu
    return usage


def least_busy_cpus(n: int) -> list[int]:
    usage = cpu_usage_snapshot()
    if len(usage) < n:
        raise RuntimeError(f"Only {len(usage)} online CPUs are visible; need {n}")
    return [cpu for cpu, _ in sorted(usage.items(), key=lambda item: (item[1], item[0]))[:n]]


def load_case_config(path: Path) -> dict[str, Any]:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict):
        raise RuntimeError(f"Case config did not parse as a mapping: {path}")
    return payload


def config_firewall(path: Path, row: pd.Series) -> None:
    payload = load_case_config(path)
    smoke = payload.get("pricefm_desn_smoke") or {}
    stage = payload.get("pricefm_stage_r69b") or {}
    if smoke.get("splits") != ["train", "val"]:
        raise RuntimeError(f"R70 config is not train/validation only: {path}")
    taus = {round(float(value), 12) for value in smoke.get("quantiles", [])}
    if taus != TAUS:
        raise RuntimeError(f"R70 config quantiles changed: {path}")
    if smoke.get("package_authority") != "exact_CRAN_exdqlm_1.1.1_public_API":
        raise RuntimeError(f"R70 config lacks CRAN 1.1.1 authority: {path}")
    qcfg = smoke.get("qdesn_vb") or {}
    if qcfg.get("public_api") != "exalStaticLDVB":
        raise RuntimeError(f"R70 config is not pinned to exalStaticLDVB: {path}")
    if qcfg.get("fork_only_namespace_calls_authorized") is not False:
        raise RuntimeError(f"R70 config permits fork-only namespace calls: {path}")
    if stage.get("case_id") != row["case_id"]:
        raise RuntimeError(f"R70 config case_id mismatch: {path}")
    for name in BLOCKED_COLUMNS:
        if boolish(stage.get(name, False)):
            raise RuntimeError(f"R70 config must keep {name} false: {path}")


def preflight(manifest: pd.DataFrame, args: argparse.Namespace, cpus: list[int]) -> dict[str, Any]:
    if not args.authorize:
        raise RuntimeError("Production R70 launch requires --authorize true")
    if len(manifest) != args.expected_cases:
        raise RuntimeError(f"Expected {args.expected_cases} R70 cases, observed {len(manifest)}")
    if manifest.duplicated(["region", "fold"]).any() or manifest.duplicated(["case_id"]).any():
        raise RuntimeError("R70 manifest must be unique by case_id and region/fold")
    if args.workers < 1:
        raise RuntimeError("R70 requires at least one worker")
    if len(cpus) < args.workers:
        raise RuntimeError("Need one unique logical CPU per worker")
    for column in BLOCKED_COLUMNS:
        if column not in manifest:
            raise RuntimeError(f"R70 manifest lacks blocked column {column}")
        if manifest[column].map(boolish).any():
            raise RuntimeError(f"Prepared manifest must keep {column} declaratively false")
    if set(manifest["expected_al_method_id"].astype(str)) != {METHOD_AL}:
        raise RuntimeError("R70 AL method id changed")
    if set(manifest["expected_exal_method_id"].astype(str)) != {METHOD_EXAL}:
        raise RuntimeError("R70 exAL method id changed")
    if set(manifest["package_authority"].astype(str)) != {"exact_CRAN_exdqlm_1.1.1_public_API"}:
        raise RuntimeError("R70 package authority changed")
    if set(manifest["cran111_version"].astype(str)) != {"1.1.1"}:
        raise RuntimeError("R70 CRAN version changed")
    if set(manifest["selection_split"].astype(str)) != {"val"}:
        raise RuntimeError("R70 selection split must remain validation")
    if not manifest["selection_is_validation_only"].map(boolish).all():
        raise RuntimeError("R70 selection must be validation-only")
    for row in manifest.itertuples(index=False):
        config = Path(row.config)
        if not config.is_file():
            raise FileNotFoundError(config)
        config_firewall(config, pd.Series(row._asdict()))
    usage = shutil.disk_usage(DATA)
    free_gib = usage.free / 1024**3
    memory_gib = available_memory_gib()
    if free_gib < args.minimum_free_gib:
        raise RuntimeError(f"Only {free_gib:.1f} GiB free; R70 requires {args.minimum_free_gib:.1f} GiB")
    if memory_gib < args.minimum_available_memory_gib:
        raise RuntimeError(
            f"Only {memory_gib:.1f} GiB available memory; R70 requires {args.minimum_available_memory_gib:.1f} GiB"
        )
    return {
        "manifest_cases": int(len(manifest)),
        "expected_quantile_components": int(len(manifest) * len(TAUS)),
        "expected_atomic_fits": int(len(manifest) * len(TAUS) * len(METHODS)),
        "workers": int(args.workers),
        "cpu_ids": cpus[: args.workers],
        "free_disk_gib": round(free_gib, 3),
        "available_memory_gib": round(memory_gib, 3),
        "one_process_per_cpu": True,
        "numerical_threads_per_process": 1,
        "test_access": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }


def completion_state(output: Path) -> str | None:
    required = [
        output / "r70_case_fit_summary.json",
        output / "run_manifest.json",
        output / "r70_component_status.csv",
        output / "model_predictions_scaled.csv",
        output / "model_method_summary.csv",
        output / "model_beta_mean.csv",
        output / "metric_summary.csv",
    ]
    if not all(path.is_file() for path in required):
        return None
    summary = json.loads((output / "r70_case_fit_summary.json").read_text())
    if int(summary.get("terminal_components", -1)) != len(TAUS) or bool(summary.get("test_loaded")):
        return None
    if bool(summary.get("binary_model_artifacts_written")):
        return None
    if any(path.suffix in BINARY_SUFFIXES for path in output.rglob("*") if path.is_file()):
        return None
    predictions = pd.read_csv(output / "model_predictions_scaled.csv", usecols=["method_id", "split", "tau"])
    if set(predictions.method_id.astype(str)) != METHODS or set(predictions.split.astype(str)) != {"val"}:
        return None
    for _, group in predictions.groupby("method_id"):
        if {round(float(value), 12) for value in group.tau.unique()} != TAUS:
            return None
    metrics = pd.read_csv(output / "metric_summary.csv")
    selected = metrics[
        metrics.method_id.astype(str).isin(METHODS)
        & metrics.split.astype(str).eq("val")
        & metrics.unit.astype(str).eq("original")
    ]
    if set(selected.method_id.astype(str)) != METHODS or len(selected) != len(METHODS):
        return None
    return "completed" if int(summary.get("eligible_components", -1)) == len(TAUS) else "completed_with_quarantine"


def run_one(row: dict[str, Any], cpu: int, code_root: Path, python_bin: Path) -> dict[str, Any]:
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
            str(code_root / "application/scripts/pricefm/238_run_pricefm_stage_r70_cran111_independent_vb_case.R"),
            "--case-config",
            row["config"],
            "--python-bin",
            str(python_bin),
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
        handle.write(f"START stage=R70 case={row['case_id']} cpu={cpu} time={time.time()}\n")
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


def write_status(path: Path, rows: list[dict[str, Any]], lock: threading.Lock) -> None:
    with lock:
        frame = pd.DataFrame(rows).sort_values(["region", "fold"])
        temp = path.with_suffix(path.suffix + ".tmp")
        frame.to_csv(temp, index=False)
        temp.replace(path)


def status_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    return {
        str(status): int(count)
        for status, count in pd.Series([row["status"] for row in rows]).value_counts().sort_index().items()
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    code_root = args.code_root.resolve()
    manifest_path = args.manifest.resolve()
    manifest = pd.read_csv(manifest_path).sort_values(["region", "fold"]).reset_index(drop=True)
    cpus = parse_cpus(args.cpu_list) if args.cpu_list else least_busy_cpus(args.workers)
    audit = preflight(manifest, args, cpus)
    status_path = manifest_path.parent / "launch_status.csv"
    write_json(manifest_path.parent / "launch_preflight.json", audit)
    if args.preflight_only:
        result = {
            "status": "preflight_passed_no_launch",
            **audit,
            "test_opened": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
            "binary_model_artifacts_written": False,
        }
        write_json(manifest_path.parent / "launch_preflight_only_summary.json", result)
        return result
    results: list[dict[str, Any]] = []
    lock = threading.Lock()
    pending_rows = iter(manifest.to_dict("records"))
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
        "status_counts": counts,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "binary_model_artifacts_written": False,
    }
    write_json(manifest_path.parent / "launch_summary.json", result)
    if failures:
        raise RuntimeError(f"R70 completed with {failures} failed case jobs: {counts}")
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
