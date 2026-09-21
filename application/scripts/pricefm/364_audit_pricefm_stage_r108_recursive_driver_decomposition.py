#!/usr/bin/env python3
"""Run the no-refit R108 validation-only recursive-driver decomposition."""

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
from typing import Any, Iterable, Mapping

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, sha256_file
from pricefm_desn_adapter import load_window
from pricefm_graph import graph_adj_matrix
from pricefm_recursive_driver_diagnostics import (
    ORACLE_LAMBDAS,
    quantile_curve_driver_paths,
    recursive_quantile_driver_forecast,
    repeat_driver,
    state_support,
)
from pricefm_recursive_normal import deterministic_seed
from pricefm_recursive_quantile import QUANTILES, causal_teacher_forced_design
from pricefm_recursive_quantile_marginal import stratified_uniforms


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R97_TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
PRICEFM_CACHE_TAG = "pricefm_stage_r108_pricefm_validation_driver_cache_20260920"
OUTPUT_TAG = "pricefm_stage_r108_recursive_driver_decomposition_20260920"
R98_CLOSEOUT_TAG = "pricefm_stage_r98_validity_first_authority_closeout_20260913"
COMPLETE_REGIONS = ("AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES")
POLICIES = (
    "r97_direct_reference",
    "self_rhs_neighbors",
    "oracle_target_l0p00_rhs_neighbors",
    "oracle_target_l0p25_rhs_neighbors",
    "oracle_target_l0p50_rhs_neighbors",
    "oracle_target_l0p75_rhs_neighbors",
    "oracle_target_l1p00_rhs_neighbors",
    "oracle_all_active",
    "pricefm_median_target_rhs_neighbors",
    "pricefm_median_all_active",
    "pricefm_quantile_paths_all_active",
)
DIAGNOSTIC_COLUMNS = (
    "state_norm_mean",
    "state_norm_p95",
    "state_saturation_rate",
    "state_outside_training_envelope_rate",
    "state_component_outside_rate",
    "state_robust_distance_mean",
    "state_robust_distance_p95",
    "direct_design_distance_mean",
    "direct_design_distance_p95",
    "pre_rearrangement_crossing_rate",
    "rearrangement_mean_abs",
    "rearrangement_max_abs",
    "conditional_median_variance",
    "recursive_innovation_variance",
    "target_driver_variance",
    "neighbor_driver_variance_mean",
    "lower_tail_clipped_rate",
    "upper_tail_clipped_rate",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--pricefm-cache",
        type=Path,
        default=DEFAULT_DATA_ROOT / "diagnostics" / PRICEFM_CACHE_TAG,
    )
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / OUTPUT_TAG,
    )
    value.add_argument(
        "--r98-registry",
        type=Path,
        default=(
            DEFAULT_DATA_ROOT / "authoritative" / R98_CLOSEOUT_TAG
            / "pricefm_stage_r98_authoritative_registry.csv"
        ),
    )
    value.add_argument("--mode", choices=("all", "case", "finalize"), default="all")
    value.add_argument("--region", choices=COMPLETE_REGIONS)
    value.add_argument("--fold", type=int, choices=(1, 2, 3))
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--workers", type=int, default=30)
    value.add_argument("--force", action="store_true")
    return value


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load script: {}".format(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SCRIPTS = Path(__file__).resolve().parent
R104 = load_script(SCRIPTS / "350_audit_pricefm_stage_r104_forecast_operator.py", "r108_r104")
CASE_RUNNER = R104.CASE_RUNNER


def write_json(path: Path, value: Any) -> None:
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


def case_id(region: str, fold: int) -> str:
    return "r108_{}_f{}".format(region.lower(), int(fold))


def case_dir(output: Path, region: str, fold: int) -> Path:
    return output / "cases" / "region={}".format(region) / "fold={}".format(int(fold))


def active_pricefm_fit_processes() -> list[dict[str, Any]]:
    blocked_tokens = (
        "345_run_pricefm_stage_r103_quantile_case.py",
        "pricefm_stage_r103_recursive_quantile",
        "pricefm_stage_r106_exact500",
    )
    records = []
    for item in Path("/proc").glob("[0-9]*"):
        try:
            command = (item / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(token in command for token in blocked_tokens) and "364_audit_pricefm" not in command:
            records.append({"pid": int(item.name), "command": command.strip()})
    return sorted(records, key=lambda row: row["pid"])


def validate_pricefm_cache(cache: Path) -> dict[str, Any]:
    summary_path = cache / "summary.json"
    summary = json.loads(summary_path.read_text())
    if (
        summary.get("status") != "completed_pricefm_validation_driver_cache"
        or summary.get("split") != "validation_only"
        or summary.get("test_opened") is not False
    ):
        raise RuntimeError("R108 PriceFM cache is not validation-only and complete")
    for record in summary["artifacts"] + summary.get("source_windows", []):
        path = Path(record["path"])
        if not path.is_file() or sha256_file(path) != record["sha256"]:
            raise RuntimeError("R108 PriceFM cache artifact changed: {}".format(path))
    return summary


def valid_case(path: Path) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") != "completed_recursive_driver_decomposition_case":
            return False
        return all(
            Path(record["path"]).is_file()
            and sha256_file(record["path"]) == record["sha256"]
            for record in terminal["artifacts"]
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def selected_family(data_root: Path, region: str) -> str:
    frames = []
    for fold in (1, 2, 3):
        frames.append(pd.read_csv(
            data_root / "campaigns" / R103_TAG / "cases"
            / "region={}".format(region) / "fold={}".format(fold)
            / "family_validation_metrics.csv"
        ))
    return R104.selected_family(pd.concat(frames, ignore_index=True))


def load_r97_reference(
    data_root: Path,
    region: str,
    fold: int,
    anchors: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, list[dict[str, Any]], dict[str, Any]]:
    closeout = data_root / "campaigns" / R97_TAG / "region_closeouts" / region
    manifest_path = closeout / "pricefm_stage_r97_selected_atom_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    selected = manifest[manifest.fold.astype(int).eq(int(fold))].sort_values("tau")
    if len(selected) != len(QUANTILES) or not np.allclose(selected.tau, QUANTILES):
        raise RuntimeError("R97 selected surface is incomplete for {} fold {}".format(region, fold))
    evidence = [artifact_record("r97_selected_manifest", manifest_path)]
    for row in selected.itertuples(index=False):
        for path_field, hash_field, role in (
            ("prediction_path", "prediction_sha256", "r97_direct_prediction"),
            ("terminal_path", "terminal_sha256", "r97_atom_terminal"),
        ):
            path = Path(getattr(row, path_field))
            if sha256_file(path) != getattr(row, hash_field):
                raise RuntimeError("R97 artifact changed: {}".format(path))
            evidence.append(artifact_record(role, path, tau=float(row.tau)))
    common = selected.iloc[0]
    for path_field, hash_field, role in (
        ("x_val_path", "x_val_sha256", "r97_direct_validation_design"),
        ("rows_val_path", "rows_val_sha256", "r97_direct_validation_rows"),
        ("scaler_path", "scaler_sha256", "r97_validation_scaler"),
    ):
        path = Path(common[path_field])
        if sha256_file(path) != common[hash_field]:
            raise RuntimeError("R97 common artifact changed: {}".format(path))
        evidence.append(artifact_record(role, path))

    rows = pd.read_csv(common.rows_val_path)
    if set(rows.split.astype(str)) != {"val"}:
        raise RuntimeError("R97 reference includes a non-validation split")
    rows = rows.sort_values(["origin_id", "horizon"]).reset_index(drop=True)
    n_origins = len(anchors)
    if len(rows) != n_origins * 96:
        raise RuntimeError("R97 reference row geometry changed")
    row_anchors = rows.groupby("origin_id", sort=True).origin_market_time.first().astype(str).to_numpy()
    if not np.array_equal(row_anchors, np.asarray(anchors, dtype=str)):
        raise RuntimeError("R97 and R103 validation anchors do not align")
    design = pd.read_csv(common.x_val_path, header=None).to_numpy(dtype=float)
    design = design.reshape(n_origins, 96, design.shape[1])

    prediction = np.empty((len(QUANTILES), n_origins, 96), dtype=float)
    for tau_index, row in enumerate(selected.itertuples(index=False)):
        frame = pd.read_csv(row.prediction_path).sort_values(["origin_id", "horizon"])
        if set(frame.split.astype(str)) != {"val"}:
            raise RuntimeError("R97 prediction includes a non-validation split")
        prediction[tau_index] = frame.pred_scaled.to_numpy(dtype=float).reshape(n_origins, 96)
    scaler = joblib.load(common.scaler_path)[region]["y_scaler"]
    return prediction, design, evidence, {
        "family": str(common.selected_family),
        "center": float(np.asarray(scaler.center_).reshape(-1)[0]),
        "scale": float(np.asarray(scaler.scale_).reshape(-1)[0]),
    }


def training_support(config: Mapping[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data_config_path = Path(config["data_config_path"])
    data_config = load_config(data_config_path)
    windows = {
        region: load_window(data_config, int(config["fold"]), region, "train")
        for region in config["active_regions"]
    }
    design = causal_teacher_forced_design(
        windows,
        json.loads(config["spec_json"]),
        list(graph_adj_matrix()),
    )
    reservoir_config = design["reservoir_config"]
    state_dim = (
        int(sum(reservoir_config["units"]))
        if reservoir_config["state_output"] == "concat_layers"
        else int(reservoir_config["units"][-1])
    )
    support = state_support(np.asarray(design["X"][:, 1 : 1 + state_dim], dtype=float))
    terminal_path = Path(config["statistics_dir"]) / "terminal.json"
    return support, [
        artifact_record("r103_data_config", data_config_path),
        artifact_record("r103_statistics_terminal", terminal_path),
    ]


def pricefm_case_drivers(
    cache: Path,
    context: Mapping[str, Any],
    fold: int,
    n_paths: int,
    seed: int,
) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray], list[dict[str, Any]], list[dict[str, Any]]]:
    medians: dict[str, np.ndarray] = {}
    paths: dict[str, np.ndarray] = {}
    evidence = []
    diagnostics = []
    driver_uniforms = stratified_uniforms(n_paths, 96, int(seed))
    anchors = np.asarray(context["anchors"], dtype=str)
    for region in context["active_regions"]:
        path = cache / "fold_{}".format(fold) / "region={}.npz".format(region)
        with np.load(path, allow_pickle=False) as archive:
            curves = np.asarray(archive["prediction_scaled"], dtype=float)
            stored_anchors = np.asarray(archive["anchors"], dtype=str)
            quantiles = np.asarray(archive["quantiles"], dtype=float)
        if not np.array_equal(stored_anchors, anchors) or not np.allclose(quantiles, QUANTILES):
            raise RuntimeError("PriceFM driver cache does not align for {}".format(region))
        medians[region] = np.repeat(
            curves[None, :, :, 3], int(n_paths), axis=0
        )
        region_paths = np.empty((n_paths, len(anchors), 96), dtype=float)
        region_diag = []
        for origin_index in range(len(anchors)):
            result = quantile_curve_driver_paths(
                curves[origin_index], n_paths, seed, uniforms=driver_uniforms
            )
            region_paths[:, origin_index] = result["paths"]
            region_diag.append(result)
        paths[region] = region_paths
        evidence.append(artifact_record("pricefm_driver_cache", path, region=region, fold=fold))
        diagnostics.append({
            "region": region,
            "fold": fold,
            "pre_rearrangement_crossing_rate": float(np.mean([
                item["pre_rearrangement_crossing_rate"] for item in region_diag
            ])),
            "rearrangement_mean_abs": float(np.mean([
                item["rearrangement_mean_abs"] for item in region_diag
            ])),
            "tail_rule": region_diag[0]["tail_rule"],
            "rank_coupling": region_diag[0]["rank_coupling"],
        })
    return medians, paths, evidence, diagnostics


def map_driver(draws: np.ndarray, regions: Iterable[str]) -> dict[str, np.ndarray]:
    names = [str(value) for value in regions]
    if draws.ndim != 3 or draws.shape[2] != len(names):
        raise RuntimeError("Normal driver dimensions changed")
    return {region: np.asarray(draws[:, :, index], dtype=float) for index, region in enumerate(names)}


def aggregate_diagnostics(rows: list[dict[str, Any]]) -> pd.DataFrame:
    frame = pd.DataFrame(rows)
    grouped = frame.groupby(["region", "fold", "family", "policy", "horizon"], sort=True)
    result = grouped[list(DIAGNOSTIC_COLUMNS)].mean().reset_index()
    result["n_origins"] = grouped.size().to_numpy()
    return result


def run_case(
    data_root_value: str,
    cache_value: str,
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
    cache = Path(cache_value).resolve()
    output = Path(output_value).resolve()
    destination = case_dir(output, region, fold)
    if valid_case(destination) and not force:
        return json.loads((destination / "terminal.json").read_text())
    config_path = (
        data_root / "launch_prep" / R103_TAG / "cases"
        / "r103_{}_f{}.json".format(region.lower(), fold)
    )
    config = json.loads(config_path.read_text())
    if int(config["posterior_paths"]) != int(n_paths):
        raise RuntimeError("R108 must preserve the frozen posterior path count")
    family = selected_family(data_root, region)
    context, scaler = CASE_RUNNER.validation_context(config)
    beta, evidence = R104.read_beta_draws(config, family, n_paths)
    evidence.append(artifact_record("r103_case_config", config_path))
    for source in (
        Path(__file__),
        SCRIPTS / "pricefm_recursive_driver_diagnostics.py",
        SCRIPTS / "pricefm_recursive_quantile_marginal.py",
        SCRIPTS / "pricefm_recursive_quantile.py",
        SCRIPTS / "pricefm_recursive_normal.py",
        SCRIPTS / "350_audit_pricefm_stage_r104_forecast_operator.py",
        SCRIPTS / "345_run_pricefm_stage_r103_quantile_case.py",
    ):
        evidence.append(artifact_record("executed_source", source))
    support, records = training_support(config)
    evidence.extend(records)
    direct_prediction, direct_design, records, direct_meta = load_r97_reference(
        data_root, region, fold, np.asarray(context["anchors"], dtype=str)
    )
    evidence.extend(records)
    if not np.isclose(direct_meta["center"], scaler["center"]) or not np.isclose(
        direct_meta["scale"], scaler["scale"]
    ):
        raise RuntimeError("R97 and R103 response scalers disagree")
    direct_design_comparable = int(direct_design.shape[2]) == int(next(iter(beta.values())).shape[1])

    data_config = load_config(config["data_config_path"])
    validation_windows = {
        active: load_window(data_config, fold, active, "val")
        for active in context["active_regions"]
    }
    truth_by_region = {
        active: np.asarray(window["Y"], dtype=float)
        for active, window in validation_windows.items()
    }
    pricefm_medians, pricefm_paths, records, pricefm_diagnostics = pricefm_case_drivers(
        cache,
        context,
        fold,
        n_paths,
        deterministic_seed(case_id(region, fold), "pricefm_driver_uniforms"),
    )
    evidence.extend(records)

    n_origins = len(context["anchors"])
    predictions = {
        policy: np.empty((len(QUANTILES), n_origins, 96), dtype=float)
        for policy in POLICIES
    }
    predictions["r97_direct_reference"][:] = direct_prediction
    diagnostic_rows: list[dict[str, Any]] = []
    origin_metric_rows: list[dict[str, Any]] = []
    rhs_surface = Path(config["normal_driver_surface"])
    evidence.append(artifact_record("rhs_driver_terminal", rhs_surface / "terminal.json"))
    truth_target = truth_by_region[region]

    for origin_index, anchor in enumerate(context["anchors"]):
        rhs_draws, rhs_regions, records = R104.read_driver(rhs_surface, origin_index, str(anchor))
        evidence.extend(records)
        rhs = map_driver(rhs_draws, rhs_regions)
        rhs_neighbors = {
            active: rhs[active]
            for active in context["active_regions"]
            if active != region
        }
        oracle_all = {
            active: repeat_driver(truth_by_region[active][origin_index], n_paths)
            for active in context["active_regions"]
            if active != region
        }
        pricefm_median_neighbors = {
            active: pricefm_medians[active][:, origin_index]
            for active in context["active_regions"]
            if active != region
        }
        pricefm_path_neighbors = {
            active: pricefm_paths[active][:, origin_index]
            for active in context["active_regions"]
            if active != region
        }
        uniforms = stratified_uniforms(
            n_paths,
            96,
            deterministic_seed(case_id(region, fold), family, origin_index, "paired_qdesn_uniforms"),
        )
        design_reference = direct_design[origin_index] if direct_design_comparable else None
        jobs: list[tuple[str, dict[str, Any]]] = [
            ("self_rhs_neighbors", {
                "external_panel": rhs_neighbors,
                "target_mode": "self",
            }),
        ]
        for value in ORACLE_LAMBDAS:
            label = "oracle_target_l{:0.2f}_rhs_neighbors".format(value).replace(".", "p")
            jobs.append((label, {
                "external_panel": rhs_neighbors,
                "target_mode": "oracle_bridge",
                "target_truth": truth_target[origin_index],
                "oracle_lambda": value,
            }))
        jobs.extend([
            ("oracle_all_active", {
                "external_panel": oracle_all,
                "target_mode": "external",
                "target_external": repeat_driver(truth_target[origin_index], n_paths),
            }),
            ("pricefm_median_target_rhs_neighbors", {
                "external_panel": rhs_neighbors,
                "target_mode": "external",
                "target_external": pricefm_medians[region][:, origin_index],
            }),
            ("pricefm_median_all_active", {
                "external_panel": pricefm_median_neighbors,
                "target_mode": "external",
                "target_external": pricefm_medians[region][:, origin_index],
            }),
            ("pricefm_quantile_paths_all_active", {
                "external_panel": pricefm_path_neighbors,
                "target_mode": "external",
                "target_external": pricefm_paths[region][:, origin_index],
            }),
        ])
        for policy, options in jobs:
            result = recursive_quantile_driver_forecast(
                context,
                origin_index=origin_index,
                beta_draws=beta,
                seed=deterministic_seed(case_id(region, fold), policy, origin_index),
                support=support,
                direct_design=design_reference,
                uniforms=uniforms,
                **options,
            )
            predictions[policy][:, origin_index] = result["prediction"]
            for row in result["diagnostics"]:
                diagnostic_rows.append({
                    "region": region,
                    "fold": fold,
                    "family": family,
                    "policy": policy,
                    "origin_index": origin_index,
                    **row,
                })

    truth_original = R104.scaled_to_original(truth_target, scaler["center"], scaler["scale"])
    metric_rows = []
    horizon_frames = []
    for policy in POLICIES:
        prediction_original = R104.scaled_to_original(
            predictions[policy], scaler["center"], scaler["scale"]
        )
        metric_rows.append({
            "region": region,
            "fold": fold,
            "family": family if policy != "r97_direct_reference" else direct_meta["family"],
            "policy": policy,
            **R104.score_surface(truth_original, prediction_original),
            "selection_split": "validation_only",
            "test_opened": False,
        })
        horizon_frames.append(R104.horizon_metrics(
            region,
            fold,
            family,
            policy,
            truth_original,
            prediction_original,
        ))
        for origin_index in range(n_origins):
            origin_metric_rows.append({
                "region": region,
                "fold": fold,
                "family": family,
                "policy": policy,
                "origin_index": origin_index,
                "anchor": str(context["anchors"][origin_index]),
                **R104.score_surface(
                    truth_original[origin_index : origin_index + 1],
                    prediction_original[:, origin_index : origin_index + 1],
                ),
            })

    diagnostics = aggregate_diagnostics(diagnostic_rows)
    temporary_parent = destination.parent
    temporary_parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".tmp.", dir=temporary_parent))
    try:
        pd.DataFrame(metric_rows).to_csv(temporary / "metrics.csv", index=False)
        pd.concat(horizon_frames, ignore_index=True).to_csv(
            temporary / "horizon_metrics.csv", index=False
        )
        pd.DataFrame(origin_metric_rows).to_csv(temporary / "origin_metrics.csv", index=False)
        diagnostics.to_csv(temporary / "driver_state_diagnostics.csv", index=False)
        pd.DataFrame(pricefm_diagnostics).to_csv(
            temporary / "pricefm_driver_diagnostics.csv", index=False
        )
        manifest = pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"])
        manifest.sort_values(["role", "path"]).to_csv(
            temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL
        )
        np.savez_compressed(
            temporary / "validation_predictions.npz",
            predictions_scaled=np.stack([predictions[policy] for policy in POLICIES]).astype(np.float32),
            truth_scaled=np.asarray(truth_target, dtype=np.float32),
            policies=np.asarray(POLICIES, dtype=str),
            quantiles=np.asarray(QUANTILES),
            anchors=np.asarray(context["anchors"], dtype=str),
        )
        artifacts = []
        for path in sorted(temporary.iterdir()):
            if path.is_file() and path.name != "terminal.json":
                artifacts.append({
                    "path": str((destination / path.name).resolve()),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        terminal = {
            "stage": "R108",
            "status": "completed_recursive_driver_decomposition_case",
            "case_id": case_id(region, fold),
            "region": region,
            "fold": fold,
            "selected_family": family,
            "r97_direct_family": direct_meta["family"],
            "posterior_paths": n_paths,
            "n_origins": n_origins,
            "policies": list(POLICIES),
            "direct_design_comparable": direct_design_comparable,
            "selection_split": "validation_only",
            "pricefm_driver_classification": "oracle_strength_hybrid_diagnostic",
            "test_opened": False,
            "model_fit_started": False,
            "registry_mutated": False,
            "article_mutated": False,
            "launch_yaml_written": False,
            "artifacts": artifacts,
        }
        write_json(temporary / "terminal.json", terminal)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.rename(destination)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def weighted_aggregate(metrics: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    for (region, policy), group in metrics.groupby(["region", "policy"], sort=True):
        weights = group.n_loss_atoms.to_numpy(dtype=float)
        rows.append({
            "region": region,
            "policy": policy,
            "folds": int(group.fold.nunique()),
            "AQL": float(np.average(group.AQL, weights=weights)),
            "coverage_10_90": float(np.average(group.coverage_10_90, weights=weights)),
            "mean_width_10_90": float(np.average(group.mean_width_10_90, weights=weights)),
            "median_MAE": float(np.average(group.median_MAE, weights=weights)),
            "n_loss_atoms": int(weights.sum()),
        })
    region = pd.DataFrame(rows)
    overall_rows = []
    for policy, group in metrics.groupby("policy", sort=True):
        weights = group.n_loss_atoms.to_numpy(dtype=float)
        overall_rows.append({
            "policy": policy,
            "regions": int(group.region.nunique()),
            "folds": int(group[["region", "fold"]].drop_duplicates().shape[0]),
            "AQL": float(np.average(group.AQL, weights=weights)),
            "coverage_10_90": float(np.average(group.coverage_10_90, weights=weights)),
            "mean_width_10_90": float(np.average(group.mean_width_10_90, weights=weights)),
            "median_MAE": float(np.average(group.median_MAE, weights=weights)),
            "n_loss_atoms": int(weights.sum()),
        })
    return region, pd.DataFrame(overall_rows).sort_values("AQL")


def load_external_test_references(path: Path) -> pd.DataFrame:
    registry = pd.read_csv(path)
    required = {
        "region", "fold", "qdesn_AQL", "pricefm_AQL", "test_metrics_role",
        "selection_is_validation_only", "test_driven_case_mixing_used",
    }
    missing = sorted(required.difference(registry.columns))
    if missing:
        raise RuntimeError("R98 reference registry is missing columns: {}".format(missing))
    references = registry[registry.region.isin(COMPLETE_REGIONS)].copy()
    if (
        len(references) != len(COMPLETE_REGIONS) * 3
        or references.duplicated(["region", "fold"]).any()
        or set(references.region.astype(str)) != set(COMPLETE_REGIONS)
        or set(references.fold.astype(int)) != {1, 2, 3}
    ):
        raise RuntimeError("R98 reference registry does not cover the R108 panel exactly")
    if (
        not references.selection_is_validation_only.map(
            lambda value: str(value).strip().lower() == "true"
        ).all()
        or references.test_driven_case_mixing_used.map(
            lambda value: str(value).strip().lower() == "true"
        ).any()
        or set(references.test_metrics_role.astype(str)) != {"audit_and_reporting_only"}
    ):
        raise RuntimeError("R98 reference registry violates the frozen authority contract")
    references = references[["region", "fold", "qdesn_AQL", "pricefm_AQL"]].rename(
        columns={
            "qdesn_AQL": "current_authoritative_qdesn_AQL",
            "pricefm_AQL": "cached_pricefm_AQL",
        }
    )
    references["reference_split"] = "outer_test"
    references["comparison_role"] = "context_only_not_ranked_with_r108_validation"
    return references.sort_values(["region", "fold"]).reset_index(drop=True)


def write_pdf(
    path: Path,
    metrics: pd.DataFrame,
    aggregate: pd.DataFrame,
    horizons: pd.DataFrame,
    references: pd.DataFrame,
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    selected = [
        "r97_direct_reference",
        "self_rhs_neighbors",
        "oracle_target_l0p00_rhs_neighbors",
        "oracle_all_active",
        "pricefm_median_all_active",
        "pricefm_quantile_paths_all_active",
    ]
    colors = dict(zip(selected, ("#222222", "#C44E52", "#4C72B0", "#2F855A", "#CC8A00", "#8A5A9E")))
    display_labels = {
        "r97_direct_reference": "R97 direct",
        "self_rhs_neighbors": "Self recursive",
        "oracle_target_l0p00_rhs_neighbors": "Exact target oracle",
        "oracle_all_active": "Exact all-active oracle",
        "pricefm_median_all_active": "PriceFM median driver",
        "pricefm_quantile_paths_all_active": "PriceFM quantile-path driver",
    }
    with PdfPages(path) as pdf:
        fig, axes = plt.subplots(1, 2, figsize=(15, 6))
        frame = aggregate[aggregate.policy.isin(selected)].copy()
        x = np.arange(len(frame))
        axes[0].bar(x, frame.AQL, color=[colors[value] for value in frame.policy])
        axes[0].set_xticks(
            x, [display_labels[value].replace(" ", "\n") for value in frame.policy], fontsize=8
        )
        axes[0].set_ylabel("AQL (lower is better)")
        axes[0].set_title("R108 policies: validation only")
        axes[0].grid(axis="y", alpha=0.25)
        reference_means = [
            references.current_authoritative_qdesn_AQL.mean(),
            references.cached_pricefm_AQL.mean(),
        ]
        axes[1].bar(
            np.arange(2), reference_means, color=("#2457A6", "#2A7F62"), width=0.62
        )
        axes[1].set_xticks(
            np.arange(2), ("Current authoritative\nR98 Q-DESN", "Cached PriceFM"), fontsize=9
        )
        axes[1].set_ylabel("AQL (lower is better)")
        axes[1].set_title("Same 9 regions: outer-test context")
        axes[1].grid(axis="y", alpha=0.25)
        for index, value in enumerate(reference_means):
            axes[1].text(index, value, "{:.3f}".format(value), ha="center", va="bottom")
        fig.suptitle("R108 recursive-driver diagnosis with frozen external references")
        fig.text(
            0.5, 0.015,
            "Validation policies and outer-test references are shown in separate panels and must not be ranked as one sample.",
            ha="center", fontsize=9,
        )
        fig.tight_layout(rect=(0, 0.05, 1, 0.94))
        pdf.savefig(fig)
        plt.close(fig)

        for region in COMPLETE_REGIONS:
            fig, axes = plt.subplots(1, 3, figsize=(18, 6))
            subset = metrics[metrics.region.eq(region) & metrics.policy.isin(selected)]
            for policy in selected:
                values = subset[subset.policy.eq(policy)].sort_values("fold")
                axes[0].plot(
                    values.fold, values.AQL, marker="o", color=colors[policy],
                    label=display_labels[policy],
                )
                horizon = horizons[horizons.region.eq(region) & horizons.policy.eq(policy)]
                horizon = horizon.groupby("horizon", as_index=False).AQL.mean()
                axes[1].plot(horizon.horizon, horizon.AQL, color=colors[policy], label=policy)
            axes[0].set_title("AQL by fold")
            axes[0].set_xticks([1, 2, 3])
            axes[1].set_title("Mean validation AQL by horizon")
            axes[1].set_xlabel("Horizon")
            reference = references[references.region.eq(region)].sort_values("fold")
            axes[2].plot(
                reference.fold,
                reference.current_authoritative_qdesn_AQL,
                marker="s", linewidth=2, color="#2457A6", label="R98 Q-DESN",
            )
            axes[2].plot(
                reference.fold,
                reference.cached_pricefm_AQL,
                marker="o", linewidth=2, color="#2A7F62", label="Cached PriceFM",
            )
            axes[2].set_title("Outer-test context by fold")
            axes[2].set_xticks([1, 2, 3])
            axes[2].set_xlabel("Fold")
            axes[2].set_ylabel("Test AQL")
            for axis in axes:
                axis.grid(alpha=0.2)
            handles, policy_labels = axes[0].get_legend_handles_labels()
            ref_handles, ref_labels = axes[2].get_legend_handles_labels()
            fig.legend(
                handles + ref_handles, policy_labels + ref_labels,
                loc="lower center", bbox_to_anchor=(0.5, 0.055),
                ncol=4, frameon=False, fontsize=8,
            )
            fig.suptitle("{}: validation mechanisms and outer-test references".format(region))
            fig.text(
                0.5, 0.015,
                "Left/middle: R108 validation. Right: frozen R98/PriceFM outer test; contextual only.",
                ha="center", fontsize=8,
            )
            fig.tight_layout(rect=(0, 0.18, 1, 0.94))
            pdf.savefig(fig)
            plt.close(fig)


def finalize(
    output: Path,
    cache_summary: Mapping[str, Any],
    r98_registry: Path,
) -> dict[str, Any]:
    terminals = []
    metric_frames = []
    horizon_frames = []
    origin_frames = []
    diagnostic_frames = []
    source_frames = []
    for region in COMPLETE_REGIONS:
        for fold in (1, 2, 3):
            path = case_dir(output, region, fold)
            if not valid_case(path):
                raise RuntimeError("R108 case is incomplete: {}".format(case_id(region, fold)))
            terminals.append(json.loads((path / "terminal.json").read_text()))
            metric_frames.append(pd.read_csv(path / "metrics.csv"))
            horizon_frames.append(pd.read_csv(path / "horizon_metrics.csv"))
            origin_frames.append(pd.read_csv(path / "origin_metrics.csv"))
            diagnostic_frames.append(pd.read_csv(path / "driver_state_diagnostics.csv"))
            source_frames.append(pd.read_csv(path / "source_manifest.csv"))
    metrics = pd.concat(metric_frames, ignore_index=True)
    horizons = pd.concat(horizon_frames, ignore_index=True)
    origins = pd.concat(origin_frames, ignore_index=True)
    diagnostics = pd.concat(diagnostic_frames, ignore_index=True)
    sources = pd.concat(source_frames, ignore_index=True).drop_duplicates(subset=["path", "sha256"])
    references = load_external_test_references(r98_registry)
    sources = pd.concat([
        sources,
        pd.DataFrame([artifact_record("r98_outer_test_reference_registry", r98_registry)]),
        pd.DataFrame([artifact_record("r108_report_generator_source", Path(__file__))]),
    ], ignore_index=True).drop_duplicates(subset=["path", "sha256"])
    region_aggregate, overall = weighted_aggregate(metrics)
    metrics.to_csv(output / "pricefm_stage_r108_case_metrics.csv", index=False)
    horizons.to_csv(output / "pricefm_stage_r108_horizon_metrics.csv", index=False)
    origins.to_csv(output / "pricefm_stage_r108_origin_metrics.csv", index=False)
    diagnostics.to_csv(output / "pricefm_stage_r108_driver_state_diagnostics.csv", index=False)
    region_aggregate.to_csv(output / "pricefm_stage_r108_region_policy_metrics.csv", index=False)
    overall.to_csv(output / "pricefm_stage_r108_overall_policy_metrics.csv", index=False)
    references.to_csv(output / "pricefm_stage_r108_external_test_references.csv", index=False)
    sources.sort_values(["role", "path"]).to_csv(output / "source_manifest.csv", index=False)
    write_pdf(
        output / "pricefm_stage_r108_recursive_driver_decomposition.pdf",
        metrics,
        overall,
        horizons,
        references,
    )

    self_row = overall[overall.policy.eq("self_rhs_neighbors")].iloc[0]
    direct_row = overall[overall.policy.eq("r97_direct_reference")].iloc[0]
    oracle_row = overall[overall.policy.eq("oracle_all_active")].iloc[0]
    reference_region = references.groupby("region", as_index=False).agg(
        current_authoritative_qdesn_AQL=("current_authoritative_qdesn_AQL", "mean"),
        cached_pricefm_AQL=("cached_pricefm_AQL", "mean"),
    )
    reference_overall = {
        "current_authoritative_qdesn_AQL": float(
            references.current_authoritative_qdesn_AQL.mean()
        ),
        "cached_pricefm_AQL": float(references.cached_pricefm_AQL.mean()),
    }
    lines = [
        "# PriceFM Stage-R108 recursive-driver decomposition",
        "",
        "R108 reuses frozen R103 independent AL/exAL posteriors. It performs no fit, opens no test data, and changes only the validation-time endogenous driver.",
        "",
        "## Pooled validation results",
        "",
        overall.to_markdown(index=False, floatfmt=".5f"),
        "",
        "## Frozen outer-test references for the same nine regions",
        "",
        "These values use the outer-test split, whereas every R108 policy above uses validation. They are contextual anchors and must not be ranked directly with the R108 rows.",
        "",
        "- Current authoritative R98 Q-DESN mean AQL: `{:.5f}`.".format(
            reference_overall["current_authoritative_qdesn_AQL"]
        ),
        "- Cached PriceFM mean AQL: `{:.5f}`.".format(
            reference_overall["cached_pricefm_AQL"]
        ),
        "",
        reference_region.to_markdown(index=False, floatfmt=".5f"),
        "",
        "## Primary diagnosis",
        "",
        "- Direct R97 validation AQL: `{:.5f}`.".format(direct_row.AQL),
        "- Self-recursive Q-DESN with frozen Normal-RHS neighbors: `{:.5f}`.".format(self_row.AQL),
        "- Exact-oracle endogenous drivers for all active regions: `{:.5f}`.".format(oracle_row.AQL),
        "- PriceFM-driven rows are hybrid oracle-strength diagnostics because the frozen public checkpoint's complete training provenance is unavailable.",
        "- No result in this packet authorizes registry, article, test, joint, MCMC, or refit work.",
        "",
        "## Decision rule",
        "",
        "If exact oracle recursion remains materially worse than the direct reference, the dominant gap is state-distribution/forecast-operator mismatch rather than driver forecast quality alone. If oracle recursion closes most of the gap, future endogenous-driver quality is the leading mechanism. The noisy-oracle ladder separates these cases without model refitting.",
        "",
    ]
    (output / "pricefm_stage_r108_recursive_driver_decomposition.md").write_text("\n".join(lines))
    output_records = []
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "summary.json":
            output_records.append(artifact_record("r108_output", path))
    summary = {
        "stage": "R108",
        "status": "completed_recursive_driver_decomposition",
        "cases_complete": len(terminals),
        "cases_expected": 27,
        "regions": list(COMPLETE_REGIONS),
        "posterior_paths": 500,
        "policies": list(POLICIES),
        "pricefm_cache_model_sha256": cache_summary["model_sha256"],
        "external_reference_split": "outer_test_context_only",
        "external_reference_cases": int(len(references)),
        "external_reference_means": reference_overall,
        "selection_split": "validation_only",
        "test_opened": False,
        "model_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "launch_yaml_written": False,
        "promotion_authorized": False,
        "outputs": output_records,
    }
    write_json(output / "summary.json", summary)
    return summary


def run(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    cache = args.pricefm_cache.resolve()
    output = args.output_dir.resolve()
    if int(args.posterior_paths) != 500:
        raise ValueError("R108 must preserve the frozen 500 posterior paths")
    if not 1 <= int(args.workers) <= 30:
        raise ValueError("R108 workers must be between 1 and 30")
    processes = active_pricefm_fit_processes()
    if processes:
        raise RuntimeError("active PriceFM fitting processes prevent a frozen R108 audit")
    cache_summary = validate_pricefm_cache(cache)
    output.mkdir(parents=True, exist_ok=True)

    if args.mode == "case":
        if args.region is None or args.fold is None:
            raise ValueError("case mode requires region and fold")
        return run_case(
            str(data_root), str(cache), str(output), args.region, args.fold,
            int(args.posterior_paths), bool(args.force),
        )
    if args.mode == "finalize":
        summary = finalize(output, cache_summary, args.r98_registry.resolve())
        print(json.dumps(summary, indent=2, sort_keys=True))
        return summary

    tasks = [(region, fold) for region in COMPLETE_REGIONS for fold in (1, 2, 3)]
    failures = []
    with ProcessPoolExecutor(max_workers=int(args.workers)) as executor:
        future_map = {
            executor.submit(
                run_case,
                str(data_root), str(cache), str(output), region, fold,
                int(args.posterior_paths), bool(args.force),
            ): (region, fold)
            for region, fold in tasks
        }
        for future in as_completed(future_map):
            region, fold = future_map[future]
            try:
                terminal = future.result()
                print(json.dumps({
                    "case_id": terminal["case_id"],
                    "status": terminal["status"],
                }), flush=True)
            except Exception as error:  # pragma: no cover - integration failure ledger
                failures.append({"region": region, "fold": fold, "error": repr(error)})
                print(json.dumps(failures[-1]), file=sys.stderr, flush=True)
    if failures:
        failure_path = output / "failures.json"
        write_json(failure_path, failures)
        raise RuntimeError("{} R108 cases failed; see {}".format(len(failures), failure_path))
    summary = finalize(output, cache_summary, args.r98_registry.resolve())
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
