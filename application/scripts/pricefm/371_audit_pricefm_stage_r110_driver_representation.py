#!/usr/bin/env python3
"""Compare no-refit R110 target-driver representations through frozen Q-DESN."""

from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import csv
import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any

import numpy as np
import pandas as pd


SCRIPTS = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file  # noqa: E402
from pricefm_recursive_normal import deterministic_seed  # noqa: E402
from pricefm_recursive_quantile import QUANTILES  # noqa: E402
from pricefm_recursive_quantile_marginal import stratified_uniforms  # noqa: E402


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load script: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


REPLAY = load_script(
    SCRIPTS / "370_audit_pricefm_stage_r110_frozen_qdesn_replay.py",
    "r110_representation_replay",
)
R108 = REPLAY.R108
R104 = REPLAY.R104
CASE_RUNNER = REPLAY.CASE_RUNNER
DEFAULT_DATA_ROOT = REPLAY.DEFAULT_DATA_ROOT
R108_TAG = REPLAY.R108_TAG
R110_TAG = REPLAY.R110_TAG
REGIONS = REPLAY.REGIONS
FOLDS = REPLAY.FOLDS
RAW_POLICY = REPLAY.POLICY
OUTPUT_TAG = "pricefm_stage_r110_driver_representation_20260921"
MODES = ("analytic_median", "analytic_quantile_curve")


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--driver-root", type=Path, default=DEFAULT_DATA_ROOT / "campaigns" / R110_TAG
    )
    value.add_argument(
        "--raw-replay-root",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / REPLAY.OUTPUT_TAG,
    )
    value.add_argument(
        "--r108-root",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / R108_TAG,
    )
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / OUTPUT_TAG,
    )
    value.add_argument("--workers", type=int, default=30)
    value.add_argument(
        "--cpu-list",
        default="",
        help="Optional comma-separated logical CPUs; one is assigned to each worker.",
    )
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--force", action="store_true")
    return value


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")
    temporary.replace(path)


def artifact_record(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    value = Path(path).resolve()
    return {
        "role": role,
        "path": str(value),
        "bytes": value.stat().st_size,
        "sha256": sha256_file(value),
        **extra,
    }


def case_dir(output: Path, mode: str, region: str, fold: int) -> Path:
    return output / "cases" / f"mode={mode}" / f"region={region}" / f"fold={fold}"


def parse_cpu_list(value: str) -> list[int]:
    if not value.strip():
        return []
    cpus = [int(item.strip()) for item in value.split(",") if item.strip()]
    if len(cpus) != len(set(cpus)) or any(cpu < 0 for cpu in cpus):
        raise ValueError("cpu-list must contain distinct nonnegative CPU identifiers")
    return cpus


def initialize_worker(cpu_queue: Any) -> None:
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ[name] = "1"
    if cpu_queue is not None:
        cpu = int(cpu_queue.get())
        os.sched_setaffinity(0, {cpu})


def valid_case(
    path: Path,
    mode: str | None = None,
    region: str | None = None,
    fold: int | None = None,
) -> bool:
    try:
        terminal = REPLAY.verify_relative_terminal(
            path, "completed_r110_driver_representation_case"
        )
        return (
            terminal.get("stage") == "R110C"
            and (mode is None or terminal.get("mode") == mode)
            and (region is None or terminal.get("region") == region)
            and (fold is None or int(terminal.get("fold")) == int(fold))
            and terminal.get("model_fit_started") is False
            and terminal.get("posterior_paths") == 500
            and terminal.get("test_opened") is False
        )
    except (OSError, KeyError, ValueError, json.JSONDecodeError, RuntimeError):
        return False


def read_analytic_paths(
    driver_root: Path,
    region: str,
    fold: int,
    context: dict[str, Any],
    n_paths: int,
    mode: str,
) -> tuple[np.ndarray, list[dict[str, Any]]]:
    if mode not in MODES:
        raise ValueError(f"unsupported representation: {mode}")
    output = driver_root / "runs" / "outer_validation" / region / f"fold={fold}"
    terminal = REPLAY.verify_relative_terminal(output, "completed_r110_case")
    if (
        terminal.get("phase") != "outer_validation"
        or terminal.get("region") != region
        or int(terminal.get("outer_fold")) != int(fold)
        or int(terminal.get("paths")) != int(n_paths)
    ):
        raise RuntimeError("R110 analytic driver identity mismatch")
    rows_path = output / "evaluation_rows.csv"
    quantile_path = output / "prediction_quantiles_scaled.csv"
    rows = pd.read_csv(rows_path)
    quantile_frame = pd.read_csv(quantile_path)
    columns = [f"q{value:g}" for value in QUANTILES]
    if (
        set(rows.split.astype(str)) != {"val"}
        or list(quantile_frame.columns[1:]) != columns
        or len(quantile_frame) != len(rows)
    ):
        raise RuntimeError("R110 analytic quantile geometry changed")
    n_origins = len(context["anchors"])
    if len(rows) != n_origins * 96:
        raise RuntimeError("R110 analytic rows do not align with R103")
    expected_origin = np.repeat(np.arange(n_origins), 96)
    expected_horizon = np.tile(np.arange(1, 97), n_origins)
    if (
        not np.array_equal(rows.origin_id.to_numpy(dtype=int), expected_origin)
        or not np.array_equal(rows.horizon.to_numpy(dtype=int), expected_horizon)
    ):
        raise RuntimeError("R110 analytic rows are not origin-major and horizon-minor")
    if not np.array_equal(
        REPLAY.normalized_times(rows.groupby("origin_id", sort=True).origin_market_time.first()),
        REPLAY.normalized_times(context["anchors"]),
    ):
        raise RuntimeError("R110 analytic anchors do not align with R103")
    if not np.allclose(
        rows.y_scaled.to_numpy(dtype=float),
        np.asarray(context["truth"], dtype=float).reshape(-1),
        rtol=0.0,
        atol=5e-7,
    ):
        raise RuntimeError("R110 analytic responses do not align with R103")
    curves = quantile_frame[columns].to_numpy(dtype=float).reshape(n_origins, 96, len(QUANTILES))
    if not np.all(np.isfinite(curves)):
        raise RuntimeError("R110 analytic quantiles are nonfinite")
    if mode == "analytic_median":
        paths = np.repeat(curves[None, :, :, 3], n_paths, axis=0)
    else:
        uniforms = stratified_uniforms(
            n_paths,
            96,
            deterministic_seed("r110_analytic_quantile_curve", region, fold),
        )
        paths = np.empty((n_paths, n_origins, 96), dtype=float)
        for origin_index in range(n_origins):
            result = R108.quantile_curve_driver_paths(
                curves[origin_index],
                n_paths,
                deterministic_seed("r110_analytic_quantile_curve", region, fold, origin_index),
                uniforms=uniforms,
            )
            paths[:, origin_index] = result["paths"]
    evidence = [
        artifact_record("r110_driver_terminal", output / "terminal.json"),
        artifact_record("r110_driver_rows", rows_path),
        artifact_record("r110_driver_analytic_quantiles", quantile_path),
    ]
    return paths, evidence


def run_case(
    data_root_value: str,
    driver_root_value: str,
    output_value: str,
    mode: str,
    region: str,
    fold: int,
    n_paths: int,
    force: bool,
) -> dict[str, Any]:
    for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ[name] = "1"
    data_root = Path(data_root_value).resolve()
    driver_root = Path(driver_root_value).resolve()
    output = Path(output_value).resolve()
    destination = case_dir(output, mode, region, fold)
    if valid_case(destination, mode, region, fold) and not force:
        return json.loads((destination / "terminal.json").read_text())
    REPLAY.validate_driver_campaign(driver_root)
    config_path, config = REPLAY.r103_config(data_root, region, fold)
    if int(config["posterior_paths"]) != n_paths:
        raise RuntimeError("representation audit must preserve 500 R103 paths")
    family = R108.selected_family(data_root, region)
    context, scaler = CASE_RUNNER.validation_context(config)
    beta, evidence = R104.read_beta_draws(config, family, n_paths)
    support, records = R108.training_support(config)
    evidence.extend(records)
    target_paths, records = read_analytic_paths(
        driver_root, region, fold, context, n_paths, mode
    )
    evidence.extend(records)
    evidence.extend([
        artifact_record("r103_case_config", config_path),
        artifact_record("executed_source", Path(__file__)),
        artifact_record("executed_source", SCRIPTS / "370_audit_pricefm_stage_r110_frozen_qdesn_replay.py"),
    ])
    rhs_surface = Path(config["normal_driver_surface"])
    evidence.append(artifact_record("rhs_neighbor_driver_terminal", rhs_surface / "terminal.json"))
    n_origins = len(context["anchors"])
    prediction = np.empty((len(QUANTILES), n_origins, 96), dtype=float)
    diagnostic_rows = []
    policy = f"r110_{mode}_target_rhs_neighbors"
    for origin_index, anchor in enumerate(context["anchors"]):
        rhs_draws, rhs_regions, records = R104.read_driver(
            rhs_surface, origin_index, str(anchor)
        )
        evidence.extend(records)
        rhs = R108.map_driver(rhs_draws, rhs_regions)
        neighbors = {
            active: rhs[active]
            for active in context["active_regions"]
            if active != region
        }
        result = R108.recursive_quantile_driver_forecast(
            context,
            origin_index=origin_index,
            beta_draws=beta,
            seed=deterministic_seed("r110_representation", mode, region, fold, origin_index),
            support=support,
            direct_design=None,
            uniforms=stratified_uniforms(
                n_paths,
                96,
                deterministic_seed("r110_representation_uniforms", mode, region, fold, origin_index),
            ),
            external_panel=neighbors,
            target_mode="external",
            target_external=target_paths[:, origin_index],
        )
        prediction[:, origin_index] = result["prediction"]
        diagnostic_rows.extend({
            "region": region,
            "fold": fold,
            "family": family,
            "policy": policy,
            "origin_index": origin_index,
            **row,
        } for row in result["diagnostics"])
    truth = R104.scaled_to_original(context["truth"], scaler["center"], scaler["scale"])
    prediction_original = R104.scaled_to_original(prediction, scaler["center"], scaler["scale"])
    metric = pd.DataFrame([{
        "mode": mode,
        "region": region,
        "fold": fold,
        "family": family,
        "policy": policy,
        **R104.score_surface(truth, prediction_original),
        "posterior_paths": n_paths,
        "selection_split": "validation_only_representation_diagnosis",
        "test_opened": False,
    }])
    horizons = R104.horizon_metrics(region, fold, family, policy, truth, prediction_original)
    horizons.insert(0, "mode", mode)
    diagnostics = R108.aggregate_diagnostics(diagnostic_rows)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".tmp.", dir=destination.parent))
    try:
        metric.to_csv(temporary / "metrics.csv", index=False)
        horizons.to_csv(temporary / "horizon_metrics.csv", index=False)
        diagnostics.to_csv(temporary / "driver_state_diagnostics.csv", index=False)
        pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(
            ["role", "path"]
        ).to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        np.savez_compressed(
            temporary / "validation_predictions.npz",
            prediction_scaled=prediction.astype(np.float32),
            quantiles=np.asarray(QUANTILES),
            anchors=np.asarray(context["anchors"], dtype=str),
        )
        artifacts = [artifact_record("representation_case_output", path) for path in temporary.iterdir()]
        for record in artifacts:
            record["path"] = str((destination / Path(record["path"]).name).resolve())
        terminal = {
            "stage": "R110C",
            "status": "completed_r110_driver_representation_case",
            "mode": mode,
            "region": region,
            "fold": fold,
            "posterior_paths": n_paths,
            "model_fit_started": False,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "artifacts": artifacts,
        }
        atomic_json(temporary / "terminal.json", terminal)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.rename(destination)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def weighted(frame: pd.DataFrame, column: str = "AQL") -> float:
    return float(np.average(frame[column], weights=frame.n_loss_atoms))


def select_and_gate(metrics: pd.DataFrame, references: pd.DataFrame) -> tuple[str, pd.DataFrame]:
    fold1 = metrics[metrics.fold.eq(1)]
    selection = []
    for mode, frame in fold1.groupby("mode"):
        selection.append({"mode": mode, "fold1_AQL": weighted(frame)})
    selected = str(pd.DataFrame(selection).sort_values(["fold1_AQL", "mode"]).iloc[0]["mode"])
    candidate = metrics[metrics["mode"].eq(selected) & metrics.fold.isin((2, 3))]
    self_rows = references[
        references.policy.eq("self_rhs_neighbors") & references.fold.isin((2, 3))
    ]
    direct_rows = references[
        references.policy.eq("r97_direct_reference") & references.fold.isin((2, 3))
    ]
    candidate_aql, self_aql, direct_aql = map(weighted, (candidate, self_rows, direct_rows))
    region_harm = (
        candidate.groupby("region").apply(weighted)
        / self_rows.groupby("region").apply(weighted)
        - 1.0
    )
    gates = pd.DataFrame([
        {"gate": "selection_uses_fold1_only", "passed": True, "observed": 1.0},
        {"gate": "confirmation_complete_6_of_6", "passed": len(candidate) == 6, "observed": float(len(candidate))},
        {"gate": "confirmation_exactly_500_paths", "passed": bool((candidate.posterior_paths == 500).all()), "observed": float(candidate.posterior_paths.min())},
        {"gate": "confirmation_gain_at_least_20pct_vs_self", "passed": (self_aql - candidate_aql) / self_aql >= 0.20, "observed": (self_aql - candidate_aql) / self_aql},
        {"gate": "confirmation_at_most_10pct_above_direct", "passed": candidate_aql / direct_aql - 1.0 <= 0.10, "observed": candidate_aql / direct_aql - 1.0},
        {"gate": "confirmation_no_region_harm_vs_self", "passed": float(region_harm.max()) <= 0.0, "observed": float(region_harm.max())},
    ])
    return selected, gates


def finalize(
    output: Path,
    raw_root: Path,
    r108_root: Path,
    driver_root: Path,
    workers_requested: int,
    workers_used: int,
    worker_cpus: list[int],
) -> dict[str, Any]:
    REPLAY.validate_driver_campaign(driver_root)
    paths = [
        case_dir(output, mode, region, fold)
        for mode in MODES for region in REGIONS for fold in FOLDS
    ]
    identities = [
        (mode, region, fold)
        for mode in MODES for region in REGIONS for fold in FOLDS
    ]
    if not all(
        valid_case(path, mode, region, fold)
        for path, (mode, region, fold) in zip(paths, identities)
    ):
        raise RuntimeError("R110 representation cases are incomplete")
    metrics = pd.concat([pd.read_csv(path / "metrics.csv") for path in paths], ignore_index=True)
    horizons = pd.concat([pd.read_csv(path / "horizon_metrics.csv") for path in paths], ignore_index=True)
    if (
        len(metrics) != 18
        or set(metrics["mode"]) != set(MODES)
        or set(metrics.region) != set(REGIONS)
        or set(metrics.fold.astype(int)) != set(FOLDS)
        or metrics.duplicated(["mode", "region", "fold"]).any()
        or metrics.test_opened.astype(bool).any()
    ):
        raise RuntimeError("R110 representation metric surface is incomplete or contaminated")
    raw_summary = json.loads((raw_root / "summary.json").read_text())
    if raw_summary.get("status") != "completed_frozen_qdesn_replay_closeout":
        raise RuntimeError("raw R110 replay is unavailable")
    raw = pd.read_csv(raw_root / "pricefm_stage_r110_replay_case_metrics.csv").copy()
    if (
        len(raw) != 9
        or set(raw.region) != set(REGIONS)
        or set(raw.fold.astype(int)) != set(FOLDS)
        or raw.duplicated(["region", "fold"]).any()
        or raw.test_opened.astype(bool).any()
    ):
        raise RuntimeError("raw R110 replay surface is incomplete or contaminated")
    raw.insert(0, "mode", "raw_posterior_paths")
    metrics = pd.concat([raw[metrics.columns], metrics], ignore_index=True)
    references = pd.read_csv(r108_root / "pricefm_stage_r108_case_metrics.csv")
    references = references[
        references.region.isin(REGIONS)
        & references.policy.isin(("self_rhs_neighbors", "r97_direct_reference"))
    ].copy()
    if (
        len(references) != 18
        or references.duplicated(["region", "fold", "policy"]).any()
        or set(references.region) != set(REGIONS)
        or set(references.fold.astype(int)) != set(FOLDS)
    ):
        raise RuntimeError("R108 replay references are incomplete")
    selected, gates = select_and_gate(metrics, references)
    passed = bool(gates.passed.all()) and selected != "raw_posterior_paths"
    selection_rows = []
    for mode, frame in metrics.groupby("mode"):
        selection_rows.append({
            "mode": mode,
            "fold1_AQL": weighted(frame[frame.fold.eq(1)]),
            "confirmation_folds_2_3_AQL": weighted(frame[frame.fold.isin((2, 3))]),
            "all_fold_AQL": weighted(frame),
            "selected_on_fold1": mode == selected,
        })
    selection = pd.DataFrame(selection_rows).sort_values("fold1_AQL")
    output.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output / "pricefm_stage_r110_representation_case_metrics.csv", index=False)
    horizons.to_csv(output / "pricefm_stage_r110_representation_horizon_metrics.csv", index=False)
    selection.to_csv(output / "pricefm_stage_r110_representation_selection.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r110_representation_gates.csv", index=False)
    source_rows = []
    for path, (mode, region, fold) in zip(paths, identities):
        source_rows.append(
            artifact_record(
                "representation_case_terminal",
                path / "terminal.json",
                mode=mode,
                region=region,
                fold=fold,
            )
        )
        source_rows.extend(pd.read_csv(path / "source_manifest.csv").to_dict("records"))
    source_rows.extend([
        artifact_record("r110_driver_summary", driver_root / "summary.json"),
        artifact_record("raw_replay_summary", raw_root / "summary.json"),
        artifact_record(
            "raw_replay_case_metrics",
            raw_root / "pricefm_stage_r110_replay_case_metrics.csv",
        ),
        artifact_record(
            "r108_case_metrics",
            r108_root / "pricefm_stage_r108_case_metrics.csv",
        ),
        artifact_record("executed_source", Path(__file__)),
        artifact_record(
            "executed_source",
            SCRIPTS / "370_audit_pricefm_stage_r110_frozen_qdesn_replay.py",
        ),
    ])
    source_manifest_path = output / "source_manifest.csv"
    pd.DataFrame(source_rows).drop_duplicates(subset=["path", "sha256"]).sort_values(
        ["role", "path"]
    ).to_csv(source_manifest_path, index=False, quoting=csv.QUOTE_MINIMAL)
    report = [
        "# PriceFM Stage-R110 target-driver representation diagnosis",
        "",
        "Selection uses fold 1 only; folds 2--3 are confirmation only. No model is refitted.",
        "",
        "## Representation AQL",
        "",
        selection.to_markdown(index=False),
        "",
        f"Fold-1-selected representation: `{selected}`.",
        f"Prospective confirmation gate: `{'PASS' if passed else 'FAIL'}`.",
        "",
        "## Gates",
        "",
        gates.to_markdown(index=False),
        "",
        "Test, registry, article, joint-model, and MCMC work remain blocked.",
    ]
    (output / "pricefm_stage_r110_driver_representation_closeout.md").write_text(
        "\n".join(report) + "\n"
    )
    summary = {
        "stage": "R110C",
        "status": "completed_driver_representation_diagnosis",
        "cases_complete": 18,
        "cases_expected": 18,
        "selected_representation": selected,
        "confirmation_gates_passed": passed,
        "all_region_direct_driver_selection_authorized": passed,
        "next_stage": "R111_training_only_all_region_direct_driver_selection" if passed else "bounded_focus_driver_readout_diagnosis",
        "workers_requested": workers_requested,
        "workers_used": workers_used,
        "worker_cpus": worker_cpus,
        "one_logical_cpu_per_worker": bool(worker_cpus) and len(worker_cpus) == workers_used,
        "source_manifest": str(source_manifest_path.resolve()),
        "source_manifest_sha256": sha256_file(source_manifest_path),
        "model_fit_started": False,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_json(output / "summary.json", summary)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    if int(args.posterior_paths) != 500:
        raise RuntimeError("R110 representation audit requires exactly 500 paths")
    REPLAY.validate_driver_campaign(args.driver_root.resolve())
    tasks = [
        (mode, region, fold)
        for mode in MODES for region in REGIONS for fold in FOLDS
    ]
    workers = min(int(args.workers), len(tasks))
    if workers < 1:
        raise ValueError("workers must be positive")
    cpu_ids = parse_cpu_list(str(args.cpu_list))
    if cpu_ids and len(cpu_ids) < workers:
        raise ValueError("cpu-list must provide at least one CPU per worker")
    worker_cpus = cpu_ids[:workers]
    manager = multiprocessing.Manager() if worker_cpus else None
    cpu_queue = manager.Queue() if manager is not None else None
    if cpu_queue is not None:
        for cpu in worker_cpus:
            cpu_queue.put(cpu)
    failures = []
    try:
        with ProcessPoolExecutor(
            max_workers=workers,
            initializer=initialize_worker,
            initargs=(cpu_queue,),
        ) as executor:
            futures = {
                executor.submit(
                    run_case,
                    str(args.data_root.resolve()),
                    str(args.driver_root.resolve()),
                    str(args.output_dir.resolve()),
                    mode,
                    region,
                    fold,
                    int(args.posterior_paths),
                    bool(args.force),
                ): (mode, region, fold)
                for mode, region, fold in tasks
            }
            for future in as_completed(futures):
                identity = futures[future]
                try:
                    future.result()
                except Exception as error:  # pragma: no cover - integration path
                    failures.append(f"{identity}: {error}")
    finally:
        if manager is not None:
            manager.shutdown()
    if failures:
        raise RuntimeError("R110 representation failures: " + "; ".join(failures))
    return finalize(
        args.output_dir.resolve(),
        args.raw_replay_root.resolve(),
        args.r108_root.resolve(),
        args.driver_root.resolve(),
        int(args.workers),
        workers,
        worker_cpus,
    )


def main() -> None:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
