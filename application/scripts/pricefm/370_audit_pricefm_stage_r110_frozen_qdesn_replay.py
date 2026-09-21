#!/usr/bin/env python3
"""Replay frozen R103 Q-DESN readouts with the validated R110 target driver."""

from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Mapping

import numpy as np
import pandas as pd


SCRIPTS = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file  # noqa: E402
from pricefm_recursive_normal import deterministic_seed  # noqa: E402
from pricefm_recursive_quantile import QUANTILES  # noqa: E402
from pricefm_recursive_quantile_marginal import stratified_uniforms  # noqa: E402


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R108_TAG = "pricefm_stage_r108_recursive_driver_decomposition_20260920"
R110_TAG = "pricefm_stage_r110_direct_driver_20260921"
OUTPUT_TAG = "pricefm_stage_r110_frozen_qdesn_replay_20260921"
REGIONS = ("BG", "EE", "BE")
FOLDS = (1, 2, 3)
POLICY = "r110_direct_target_rhs_neighbors"


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load script: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R108 = load_script(
    SCRIPTS / "364_audit_pricefm_stage_r108_recursive_driver_decomposition.py",
    "r110_replay_r108",
)
R104 = R108.R104
CASE_RUNNER = R108.CASE_RUNNER


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--driver-root",
        type=Path,
        default=DEFAULT_DATA_ROOT / "campaigns" / R110_TAG,
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
    value.add_argument("--mode", choices=("all", "case", "finalize"), default="all")
    value.add_argument("--region", choices=REGIONS)
    value.add_argument("--fold", type=int, choices=FOLDS)
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--workers", type=int, default=30)
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


def verify_relative_terminal(output: Path, expected_status: str) -> dict[str, Any]:
    terminal_path = output / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if terminal.get("status") != expected_status or terminal.get("test_opened") is not False:
        raise RuntimeError(f"invalid terminal: {terminal_path}")
    for record in terminal.get("artifacts", []):
        path = Path(record["path"])
        if not path.is_absolute():
            path = output / path
        if not path.is_file() or sha256_file(path) != record["sha256"]:
            raise RuntimeError(f"changed terminal artifact: {path}")
    return terminal


def validate_driver_campaign(driver_root: Path) -> dict[str, Any]:
    summary_path = driver_root / "summary.json"
    summary = json.loads(summary_path.read_text())
    if (
        summary.get("status") != "completed_direct_driver_closeout"
        or summary.get("all_gates_passed") is not True
        or summary.get("downstream_replay_authorized") is not True
        or summary.get("cases_complete") != 9
        or summary.get("posterior_paths") != 500
        or summary.get("test_opened") is not False
    ):
        raise RuntimeError("R110 direct-driver campaign did not authorize replay")
    terminal = json.loads((driver_root / "orchestrator_terminal.json").read_text())
    if terminal.get("status") != "completed_r110_orchestration" or terminal.get("test_opened") is not False:
        raise RuntimeError("R110 orchestration terminal is invalid")
    manifest = pd.read_csv(driver_root / "final_source_manifest.csv")
    if len(manifest) != 9 * 9:
        raise RuntimeError("R110 final source manifest is incomplete")
    for row in manifest.itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != row.sha256:
            raise RuntimeError(f"R110 final artifact changed: {path}")
    return summary


def r103_config(data_root: Path, region: str, fold: int) -> tuple[Path, dict[str, Any]]:
    path = (
        data_root / "launch_prep" / R103_TAG / "cases"
        / f"r103_{region.lower()}_f{fold}.json"
    )
    return path, json.loads(path.read_text())


def normalized_times(values: Any) -> np.ndarray:
    return pd.to_datetime(np.asarray(values), utc=True).astype(str).to_numpy()


def read_r110_paths(
    driver_root: Path,
    region: str,
    fold: int,
    context: Mapping[str, Any],
    n_paths: int,
) -> tuple[np.ndarray, list[dict[str, Any]]]:
    output = driver_root / "runs" / "outer_validation" / region / f"fold={fold}"
    terminal = verify_relative_terminal(output, "completed_r110_case")
    if (
        terminal.get("phase") != "outer_validation"
        or terminal.get("region") != region
        or int(terminal.get("outer_fold")) != int(fold)
        or int(terminal.get("paths")) != int(n_paths)
    ):
        raise RuntimeError("R110 target-driver identity mismatch")

    rows_path = output / "evaluation_rows.csv"
    manifest_path = output / "prediction_paths_manifest.json"
    binary_path = output / "prediction_paths_scaled.bin"
    rows = pd.read_csv(rows_path)
    manifest = json.loads(manifest_path.read_text())
    n_origins = len(context["anchors"])
    n_rows = n_origins * 96
    if (
        set(rows.split.astype(str)) != {"val"}
        or len(rows) != n_rows
        or int(manifest.get("n_rows", -1)) != n_rows
        or int(manifest.get("n_paths", -1)) != int(n_paths)
        or manifest.get("storage_order") != "R_column_major"
        or manifest.get("dtype") != "float64_little_endian"
    ):
        raise RuntimeError("R110 path manifest geometry changed")
    expected_origin = np.repeat(np.arange(n_origins), 96)
    expected_horizon = np.tile(np.arange(1, 97), n_origins)
    if (
        not np.array_equal(rows.origin_id.to_numpy(dtype=int), expected_origin)
        or not np.array_equal(rows.horizon.to_numpy(dtype=int), expected_horizon)
    ):
        raise RuntimeError("R110 path rows are not origin-major and horizon-minor")
    stored_anchors = normalized_times(rows.groupby("origin_id", sort=True).origin_market_time.first())
    context_anchors = normalized_times(context["anchors"])
    if not np.array_equal(stored_anchors, context_anchors):
        raise RuntimeError("R110 and R103 validation anchors disagree")
    truth = np.asarray(context["truth"], dtype=float)
    if truth.shape != (n_origins, 96) or not np.allclose(
        rows.y_scaled.to_numpy(dtype=float), truth.reshape(-1), rtol=0.0, atol=5e-7
    ):
        raise RuntimeError("R110 and R103 scaled validation responses disagree")

    flat = np.fromfile(binary_path, dtype="<f8")
    if flat.size != n_rows * n_paths:
        raise RuntimeError("R110 binary path size changed")
    matrix = flat.reshape((n_rows, n_paths), order="F")
    paths = matrix.T.reshape(n_paths, n_origins, 96)
    if not np.all(np.isfinite(paths)):
        raise RuntimeError("R110 target-driver paths are nonfinite")
    evidence = [
        artifact_record("r110_driver_terminal", output / "terminal.json", region=region, fold=fold),
        artifact_record("r110_driver_rows", rows_path, region=region, fold=fold),
        artifact_record("r110_driver_path_manifest", manifest_path, region=region, fold=fold),
        artifact_record("r110_driver_paths", binary_path, region=region, fold=fold),
    ]
    return paths, evidence


def case_dir(output: Path, region: str, fold: int) -> Path:
    return output / "cases" / f"region={region}" / f"fold={fold}"


def valid_case(path: Path) -> bool:
    try:
        terminal = verify_relative_terminal(path, "completed_r110_frozen_qdesn_replay_case")
        return (
            terminal.get("model_fit_started") is False
            and terminal.get("posterior_paths") == 500
            and terminal.get("test_opened") is False
        )
    except (OSError, KeyError, ValueError, json.JSONDecodeError, RuntimeError):
        return False


def run_case(
    data_root_value: str,
    driver_root_value: str,
    output_value: str,
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
    destination = case_dir(output, region, fold)
    if valid_case(destination) and not force:
        return json.loads((destination / "terminal.json").read_text())

    validate_driver_campaign(driver_root)
    config_path, config = r103_config(data_root, region, fold)
    if int(config["posterior_paths"]) != int(n_paths):
        raise RuntimeError("R110 replay must preserve the frozen R103 posterior path count")
    family = R108.selected_family(data_root, region)
    context, scaler = CASE_RUNNER.validation_context(config)
    beta, evidence = R104.read_beta_draws(config, family, n_paths)
    support, records = R108.training_support(config)
    evidence.extend(records)
    evidence.extend([
        artifact_record("r103_case_config", config_path),
        artifact_record("r103_scaler", scaler["scaler_path"]),
        artifact_record("r110_driver_summary", driver_root / "summary.json"),
        artifact_record("executed_source", Path(__file__)),
        artifact_record("executed_source", SCRIPTS / "364_audit_pricefm_stage_r108_recursive_driver_decomposition.py"),
        artifact_record("executed_source", SCRIPTS / "pricefm_recursive_driver_diagnostics.py"),
        artifact_record("executed_source", SCRIPTS / "pricefm_recursive_quantile.py"),
        artifact_record("executed_source", SCRIPTS / "pricefm_recursive_quantile_marginal.py"),
    ])
    target_paths, records = read_r110_paths(
        driver_root, region, fold, context, n_paths
    )
    evidence.extend(records)

    rhs_surface = Path(config["normal_driver_surface"])
    evidence.append(artifact_record("rhs_neighbor_driver_terminal", rhs_surface / "terminal.json"))
    n_origins = len(context["anchors"])
    prediction = np.empty((len(QUANTILES), n_origins, 96), dtype=float)
    diagnostic_rows: list[dict[str, Any]] = []
    origin_rows: list[dict[str, Any]] = []
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
        uniforms = stratified_uniforms(
            n_paths,
            96,
            deterministic_seed(
                f"r110_replay_{region}_f{fold}", family, origin_index, "paired_qdesn_uniforms"
            ),
        )
        result = R108.recursive_quantile_driver_forecast(
            context,
            origin_index=origin_index,
            beta_draws=beta,
            seed=deterministic_seed(f"r110_replay_{region}_f{fold}", origin_index),
            support=support,
            direct_design=None,
            uniforms=uniforms,
            external_panel=neighbors,
            target_mode="external",
            target_external=target_paths[:, origin_index, :],
        )
        prediction[:, origin_index] = result["prediction"]
        for row in result["diagnostics"]:
            diagnostic_rows.append({
                "region": region,
                "fold": fold,
                "family": family,
                "policy": POLICY,
                "origin_index": origin_index,
                **row,
            })

    truth_original = R104.scaled_to_original(
        context["truth"], scaler["center"], scaler["scale"]
    )
    prediction_original = R104.scaled_to_original(
        prediction, scaler["center"], scaler["scale"]
    )
    metric = pd.DataFrame([{
        "region": region,
        "fold": fold,
        "family": family,
        "policy": POLICY,
        **R104.score_surface(truth_original, prediction_original),
        "posterior_paths": n_paths,
        "selection_split": "validation_only_frozen_r103_readout",
        "evaluation_split": "outer_validation",
        "test_opened": False,
    }])
    horizons = R104.horizon_metrics(
        region, fold, family, POLICY, truth_original, prediction_original
    )
    for origin_index, anchor in enumerate(context["anchors"]):
        origin_rows.append({
            "region": region,
            "fold": fold,
            "family": family,
            "policy": POLICY,
            "origin_index": origin_index,
            "anchor": str(anchor),
            **R104.score_surface(
                truth_original[origin_index : origin_index + 1],
                prediction_original[:, origin_index : origin_index + 1],
            ),
        })
    diagnostics = R108.aggregate_diagnostics(diagnostic_rows)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".tmp.", dir=destination.parent))
    try:
        metric.to_csv(temporary / "metrics.csv", index=False)
        horizons.to_csv(temporary / "horizon_metrics.csv", index=False)
        pd.DataFrame(origin_rows).to_csv(temporary / "origin_metrics.csv", index=False)
        diagnostics.to_csv(temporary / "driver_state_diagnostics.csv", index=False)
        pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(
            ["role", "path"]
        ).to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        np.savez_compressed(
            temporary / "validation_predictions.npz",
            prediction_scaled=prediction.astype(np.float32),
            truth_scaled=np.asarray(context["truth"], dtype=np.float32),
            target_driver_scaled=target_paths.astype(np.float32),
            quantiles=np.asarray(QUANTILES, dtype=float),
            anchors=np.asarray(context["anchors"], dtype=str),
        )
        artifacts = [
            artifact_record("r110_replay_case_output", path)
            for path in sorted(temporary.iterdir())
            if path.is_file() and path.name != "terminal.json"
        ]
        for record in artifacts:
            record["path"] = str((destination / Path(record["path"]).name).resolve())
        terminal = {
            "stage": "R110B",
            "status": "completed_r110_frozen_qdesn_replay_case",
            "region": region,
            "fold": fold,
            "selected_family": family,
            "policy": POLICY,
            "posterior_paths": n_paths,
            "n_origins": n_origins,
            "selection_split": "validation_only_frozen_r103_readout",
            "evaluation_split": "outer_validation",
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


def weighted_value(frame: pd.DataFrame, column: str = "AQL") -> float:
    return float(np.average(frame[column], weights=frame.n_loss_atoms))


def evaluate_gates(candidate: pd.DataFrame, references: pd.DataFrame) -> pd.DataFrame:
    self_rows = references[references.policy.eq("self_rhs_neighbors")]
    direct_rows = references[references.policy.eq("r97_direct_reference")]
    candidate_aql = weighted_value(candidate)
    self_aql = weighted_value(self_rows)
    direct_aql = weighted_value(direct_rows)
    candidate_region = candidate.groupby("region").apply(weighted_value)
    self_region = self_rows.groupby("region").apply(weighted_value)
    max_region_harm = float((candidate_region / self_region - 1.0).max())
    rows = [
        {"gate": "complete_9_of_9", "passed": len(candidate) == 9, "observed": float(len(candidate))},
        {
            "gate": "exactly_500_paths_per_case",
            "passed": bool((candidate.posterior_paths == 500).all()),
            "observed": float(candidate.posterior_paths.min()),
        },
        {
            "gate": "pooled_aql_gain_at_least_20pct_vs_r108_self",
            "passed": (self_aql - candidate_aql) / self_aql >= 0.20,
            "observed": (self_aql - candidate_aql) / self_aql,
        },
        {
            "gate": "pooled_aql_at_most_10pct_above_r97_direct",
            "passed": candidate_aql / direct_aql - 1.0 <= 0.10,
            "observed": candidate_aql / direct_aql - 1.0,
        },
        {
            "gate": "no_region_harm_vs_r108_self",
            "passed": max_region_harm <= 0.0,
            "observed": max_region_harm,
        },
        {
            "gate": "all_metrics_finite",
            "passed": bool(np.isfinite(candidate.select_dtypes(include=[np.number])).all().all()),
            "observed": float(np.isfinite(candidate.select_dtypes(include=[np.number])).all().all()),
        },
    ]
    return pd.DataFrame(rows)


def finalize(output: Path, r108_root: Path, driver_root: Path) -> dict[str, Any]:
    validate_driver_campaign(driver_root)
    case_paths = [case_dir(output, region, fold) for region in REGIONS for fold in FOLDS]
    if not all(valid_case(path) for path in case_paths):
        raise RuntimeError("R110 replay cannot close with incomplete cases")
    metrics = pd.concat([pd.read_csv(path / "metrics.csv") for path in case_paths], ignore_index=True)
    horizons = pd.concat(
        [pd.read_csv(path / "horizon_metrics.csv") for path in case_paths], ignore_index=True
    )
    origins = pd.concat(
        [pd.read_csv(path / "origin_metrics.csv") for path in case_paths], ignore_index=True
    )
    diagnostics = pd.concat(
        [pd.read_csv(path / "driver_state_diagnostics.csv") for path in case_paths],
        ignore_index=True,
    )
    if (
        len(metrics) != 9
        or set(metrics.region) != set(REGIONS)
        or set(metrics.fold.astype(int)) != set(FOLDS)
        or metrics.duplicated(["region", "fold"]).any()
        or metrics.test_opened.astype(bool).any()
    ):
        raise RuntimeError("R110 replay metric surface is incomplete or contaminated")

    r108_metrics_path = r108_root / "pricefm_stage_r108_case_metrics.csv"
    r108 = pd.read_csv(r108_metrics_path)
    references = r108[
        r108.region.isin(REGIONS)
        & r108.policy.isin(("self_rhs_neighbors", "r97_direct_reference"))
    ].copy()
    if len(references) != 18:
        raise RuntimeError("R108 replay references are incomplete")
    gates = evaluate_gates(metrics, references)
    passed = bool(gates.passed.all())

    combined = pd.concat([
        references[["region", "fold", "policy", "AQL", "coverage_10_90", "mean_width_10_90", "median_MAE", "n_loss_atoms"]],
        metrics[["region", "fold", "policy", "AQL", "coverage_10_90", "mean_width_10_90", "median_MAE", "n_loss_atoms"]],
    ], ignore_index=True)
    region_rows = []
    overall_rows = []
    for (region, policy), frame in combined.groupby(["region", "policy"], sort=True):
        region_rows.append({
            "region": region,
            "policy": policy,
            "folds": int(frame.fold.nunique()),
            "AQL": weighted_value(frame),
            "coverage_10_90": weighted_value(frame, "coverage_10_90"),
            "mean_width_10_90": weighted_value(frame, "mean_width_10_90"),
            "median_MAE": weighted_value(frame, "median_MAE"),
            "n_loss_atoms": int(frame.n_loss_atoms.sum()),
        })
    for policy, frame in combined.groupby("policy", sort=True):
        overall_rows.append({
            "policy": policy,
            "regions": int(frame.region.nunique()),
            "folds": int(frame[["region", "fold"]].drop_duplicates().shape[0]),
            "AQL": weighted_value(frame),
            "coverage_10_90": weighted_value(frame, "coverage_10_90"),
            "mean_width_10_90": weighted_value(frame, "mean_width_10_90"),
            "median_MAE": weighted_value(frame, "median_MAE"),
            "n_loss_atoms": int(frame.n_loss_atoms.sum()),
        })
    region = pd.DataFrame(region_rows).sort_values(["region", "AQL"])
    overall = pd.DataFrame(overall_rows).sort_values("AQL")

    output.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output / "pricefm_stage_r110_replay_case_metrics.csv", index=False)
    horizons.to_csv(output / "pricefm_stage_r110_replay_horizon_metrics.csv", index=False)
    origins.to_csv(output / "pricefm_stage_r110_replay_origin_metrics.csv", index=False)
    diagnostics.to_csv(output / "pricefm_stage_r110_replay_state_diagnostics.csv", index=False)
    references.to_csv(output / "pricefm_stage_r110_replay_r108_references.csv", index=False)
    region.to_csv(output / "pricefm_stage_r110_replay_region_metrics.csv", index=False)
    overall.to_csv(output / "pricefm_stage_r110_replay_overall_metrics.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r110_replay_gates.csv", index=False)

    source_rows = []
    for path in case_paths:
        source_rows.append(artifact_record("r110_replay_case_terminal", path / "terminal.json"))
        source_rows.extend(pd.read_csv(path / "source_manifest.csv").to_dict("records"))
    source_rows.extend([
        artifact_record("r110_driver_summary", driver_root / "summary.json"),
        artifact_record("r108_case_metrics", r108_metrics_path),
        artifact_record("executed_source", Path(__file__)),
    ])
    pd.DataFrame(source_rows).drop_duplicates(subset=["path", "sha256"]).sort_values(
        ["role", "path"]
    ).to_csv(output / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)

    by_policy = overall.set_index("policy")
    report = [
        "# PriceFM Stage-R110 frozen Q-DESN replay closeout",
        "",
        "This validation-only stage reuses frozen R103 Q-DESN readouts and changes only the target-price driver.",
        "Existing Normal-RHS neighbor paths remain fixed. No model was refitted.",
        "",
        "## Pooled AQL",
        "",
        f"- R110 direct-target replay: `{by_policy.loc[POLICY, 'AQL']:.5f}`.",
        f"- R108 self recursion: `{by_policy.loc['self_rhs_neighbors', 'AQL']:.5f}`.",
        f"- R97 direct reference: `{by_policy.loc['r97_direct_reference', 'AQL']:.5f}`.",
        f"- Replay gate: `{'PASS' if passed else 'FAIL'}`.",
        "",
        "## Gate ledger",
        "",
        gates.to_markdown(index=False),
        "",
        "A pass authorizes training-only all-region direct-driver selection. Test, registry, article, joint-model, and MCMC work remain blocked.",
    ]
    (output / "pricefm_stage_r110_frozen_qdesn_replay_closeout.md").write_text(
        "\n".join(report) + "\n"
    )
    summary = {
        "stage": "R110B",
        "status": "completed_frozen_qdesn_replay_closeout",
        "regions": list(REGIONS),
        "cases_expected": 9,
        "cases_complete": 9,
        "posterior_paths": 500,
        "model_fit_started": False,
        "all_gates_passed": passed,
        "all_region_direct_driver_selection_authorized": passed,
        "next_stage": "R111_training_only_all_region_direct_driver_selection" if passed else "stop_and_diagnose_r110_replay",
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_json(output / "summary.json", summary)
    return summary


def run_all(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    driver_root = args.driver_root.resolve()
    output = args.output_dir.resolve()
    validate_driver_campaign(driver_root)
    tasks = [(region, fold) for region in REGIONS for fold in FOLDS]
    workers = min(int(args.workers), len(tasks))
    if workers < 1:
        raise RuntimeError("workers must be positive")
    failures = []
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                run_case,
                str(data_root),
                str(driver_root),
                str(output),
                region,
                fold,
                int(args.posterior_paths),
                bool(args.force),
            ): (region, fold)
            for region, fold in tasks
        }
        for future in as_completed(futures):
            region, fold = futures[future]
            try:
                future.result()
            except Exception as error:  # pragma: no cover - surfaced by integration launch
                failures.append(f"{region}/fold{fold}: {error}")
    if failures:
        raise RuntimeError("R110 replay failures: " + "; ".join(failures))
    return finalize(output, args.r108_root.resolve(), driver_root)


def main() -> None:
    args = parser().parse_args()
    if int(args.posterior_paths) != 500:
        raise RuntimeError("R110 replay requires exactly 500 paths")
    if args.mode == "case":
        if args.region is None or args.fold is None:
            raise RuntimeError("case mode requires --region and --fold")
        result = run_case(
            str(args.data_root.resolve()),
            str(args.driver_root.resolve()),
            str(args.output_dir.resolve()),
            args.region,
            int(args.fold),
            int(args.posterior_paths),
            bool(args.force),
        )
    elif args.mode == "finalize":
        result = finalize(
            args.output_dir.resolve(), args.r108_root.resolve(), args.driver_root.resolve()
        )
    else:
        result = run_all(args)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
