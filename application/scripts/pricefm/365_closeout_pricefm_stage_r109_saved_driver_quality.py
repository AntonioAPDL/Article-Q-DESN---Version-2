#!/usr/bin/env python3
"""Close out saved PriceFM driver quality without fitting or test access."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Mapping

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, sha256_file
from pricefm_recursive_quantile import QUANTILES


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
R102B_TAG = "pricefm_stage_r102b_recursive_validation_20260916"
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R104_TAG = "pricefm_stage_r104_forecast_operator_diagnosis_20260918"
R108_TAG = "pricefm_stage_r108_recursive_driver_decomposition_20260920"
PRICEFM_CACHE_TAG = "pricefm_stage_r108_pricefm_validation_driver_cache_20260920"
OUTPUT_TAG = "pricefm_stage_r109_saved_driver_quality_20260921"
REGIONS = ("AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES")
NORMAL_METHODS = {
    "rhs_ns": "normal_rhs_paths",
    "scaled_ridge": "normal_ridge_paths",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / OUTPUT_TAG,
    )
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


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


def published_artifact_record(
    role: str,
    source: Path,
    published: Path,
    **extra: Any,
) -> dict[str, Any]:
    """Hash a temporary artifact while recording its stable published path."""
    record = artifact_record(role, source, **extra)
    record["path"] = str(Path(published).resolve())
    return record


def validate_record(path: Path, expected: str, role: str) -> dict[str, Any]:
    if not path.is_file() or sha256_file(path) != str(expected):
        raise RuntimeError("changed {} artifact: {}".format(role, path))
    return artifact_record(role, path)


def load_case_context(
    data_root: Path,
    region: str,
    fold: int,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    case = (
        data_root / "authoritative" / R108_TAG / "cases"
        / "region={}".format(region) / "fold={}".format(fold)
    )
    terminal_path = case / "terminal.json"
    terminal = read_json(terminal_path)
    if (
        terminal.get("status") != "completed_recursive_driver_decomposition_case"
        or terminal.get("test_opened") is not False
        or int(terminal.get("posterior_paths", -1)) != 500
    ):
        raise RuntimeError("invalid R108 case terminal: {}".format(terminal_path))
    artifact = next(
        record for record in terminal["artifacts"]
        if Path(record["path"]).name == "validation_predictions.npz"
    )
    prediction_path = Path(artifact["path"])
    evidence = [
        artifact_record("r108_case_terminal", terminal_path, region=region, fold=fold),
        validate_record(
            prediction_path,
            artifact["sha256"],
            "r108_validation_truth",
        ),
    ]
    with np.load(prediction_path, allow_pickle=False) as archive:
        truth_scaled = np.asarray(archive["truth_scaled"], dtype=float)
        anchors = np.asarray(archive["anchors"], dtype=str)
        quantiles = np.asarray(archive["quantiles"], dtype=float)
    if truth_scaled.shape != (len(anchors), 96) or not np.allclose(quantiles, QUANTILES):
        raise RuntimeError("R108 truth geometry changed for {} fold {}".format(region, fold))

    config_path = (
        data_root / "launch_prep" / R103_TAG / "cases"
        / "r103_{}_f{}.json".format(region.lower(), fold)
    )
    config = read_json(config_path)
    data_config_path = Path(config["data_config_path"])
    data_config = load_config(data_config_path)
    scaler_path = (
        Path(data_config["pricefm"]["processed_dir"])
        / "scalers" / "fold_{}".format(fold)
        / "per_region_separate_xy_scalers.joblib"
    )
    scaler = joblib.load(scaler_path)[region]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    truth = truth_scaled * scale + center
    evidence.extend([
        artifact_record("r103_case_config", config_path, region=region, fold=fold),
        artifact_record("r103_data_config", data_config_path, region=region, fold=fold),
        artifact_record("fold_response_scaler", scaler_path, region=region, fold=fold),
    ])
    return {
        "region": region,
        "fold": fold,
        "truth": truth,
        "truth_scaled": truth_scaled,
        "anchors": anchors,
        "center": center,
        "scale": scale,
        "selected_family": str(terminal["selected_family"]),
    }, evidence


def score_driver_arrays(
    region: str,
    fold: int,
    method: str,
    truth: np.ndarray,
    prediction: np.ndarray,
    center_prediction: np.ndarray,
    center_role: str,
) -> tuple[dict[str, Any], pd.DataFrame]:
    observed = np.asarray(truth, dtype=float)
    curves = np.asarray(prediction, dtype=float)
    center = np.asarray(center_prediction, dtype=float)
    if (
        curves.shape != observed.shape + (len(QUANTILES),)
        or center.shape != observed.shape
        or not np.isfinite(observed).all()
        or not np.isfinite(curves).all()
        or not np.isfinite(center).all()
    ):
        raise ValueError("driver arrays are incomplete or non-finite")
    tau = np.asarray(QUANTILES, dtype=float).reshape(1, 1, -1)
    error = observed[..., None] - curves
    loss = np.maximum(tau * error, (tau - 1.0) * error)
    center_error = center - observed
    crossing = curves[..., :-1] > curves[..., 1:]
    row = {
        "region": region,
        "fold": int(fold),
        "driver_method": method,
        "AQL": float(loss.mean()),
        "AQCR": float(crossing.mean()),
        "coverage_10_90": float(
            np.mean((observed >= curves[..., 0]) & (observed <= curves[..., -1]))
        ),
        "mean_width_10_90": float(np.mean(curves[..., -1] - curves[..., 0])),
        "median_MAE": float(np.mean(np.abs(observed - curves[..., 3]))),
        "center_MAE": float(np.mean(np.abs(center_error))),
        "center_RMSE": float(np.sqrt(np.mean(center_error ** 2))),
        "center_bias": float(np.mean(center_error)),
        "center_role": center_role,
        "n_origins": int(observed.shape[0]),
        "n_points": int(observed.size),
        "n_loss_atoms": int(loss.size),
        "posterior_paths": 500 if method.startswith("normal_") else np.nan,
        "selection_split": "validation_only",
        "test_opened": False,
    }
    horizon = pd.DataFrame({
        "region": region,
        "fold": int(fold),
        "driver_method": method,
        "horizon": np.arange(1, 97),
        "AQL": loss.mean(axis=(0, 2)),
        "coverage_10_90": (
            (observed >= curves[..., 0]) & (observed <= curves[..., -1])
        ).mean(axis=0),
        "mean_width_10_90": (curves[..., -1] - curves[..., 0]).mean(axis=0),
        "center_MAE": np.abs(center_error).mean(axis=0),
        "center_bias": center_error.mean(axis=0),
        "n_origins": int(observed.shape[0]),
    })
    return row, horizon


def validate_surface(
    surface: Path,
    prior_type: str,
    fold: int,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    terminal_path = surface / "terminal.json"
    terminal = read_json(terminal_path)
    if (
        terminal.get("status") != "completed_recursive_validation_surface"
        or terminal.get("panel") != "r98_control"
        or terminal.get("prior_type") != prior_type
        or int(terminal.get("fold", -1)) != int(fold)
        or int(terminal.get("posterior_paths", -1)) != 500
        or terminal.get("test_opened") is not False
    ):
        raise RuntimeError("invalid R102B saved surface: {}".format(surface))
    evidence = [artifact_record("r102b_surface_terminal", terminal_path)]
    for record in terminal["artifacts"]:
        path = surface / record["path"]
        evidence.append(validate_record(path, record["sha256"], "r102b_surface_artifact"))
    manifest_path = surface / "origin_manifest.csv"
    manifest = pd.read_csv(manifest_path).sort_values("origin_index").reset_index(drop=True)
    if len(manifest) == 0 or not np.array_equal(
        manifest.origin_index.to_numpy(dtype=int), np.arange(len(manifest))
    ):
        raise RuntimeError("R102B origin manifest is incomplete")
    return manifest, evidence


def score_normal_surface(
    data_root: Path,
    prior_type: str,
    fold: int,
    contexts: Mapping[str, Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], list[pd.DataFrame], list[dict[str, Any]]]:
    method = NORMAL_METHODS[prior_type]
    surface = (
        data_root / "campaigns" / R102B_TAG / "surfaces" / "r98_control"
        / prior_type / "fold_{}".format(fold)
    )
    manifest, evidence = validate_surface(surface, prior_type, fold)
    n_origins = len(manifest)
    predictions = {
        region: np.empty((n_origins, 96, len(QUANTILES)), dtype=float)
        for region in REGIONS
    }
    centers = {
        region: np.empty((n_origins, 96), dtype=float)
        for region in REGIONS
    }
    expected_anchors = np.asarray(contexts[REGIONS[0]]["anchors"], dtype=str)
    if len(expected_anchors) != n_origins:
        raise RuntimeError("R102B and R108 origin counts disagree")
    for row in manifest.itertuples(index=False):
        path = Path(row.path)
        marker = Path(row.terminal_path)
        evidence.append(validate_record(path, row.sha256, "r102b_saved_paths"))
        evidence.append(validate_record(marker, row.terminal_sha256, "r102b_origin_marker"))
        with np.load(path, allow_pickle=False) as archive:
            draws = np.asarray(archive["response_draws"], dtype=float)
            regions = [str(value) for value in archive["regions"].tolist()]
            anchor = str(archive["anchor"].tolist()[0])
        if (
            draws.shape != (500, 96, len(regions))
            or anchor != str(expected_anchors[int(row.origin_index)])
            or not np.isfinite(draws).all()
        ):
            raise RuntimeError("R102B saved path geometry changed: {}".format(path))
        indices = [regions.index(region) for region in REGIONS]
        selected = draws[:, :, indices]
        curves = np.quantile(selected, QUANTILES, axis=0, method="linear").transpose(2, 1, 0)
        means = selected.mean(axis=0).T
        for region_index, region in enumerate(REGIONS):
            context = contexts[region]
            predictions[region][int(row.origin_index)] = (
                curves[region_index] * float(context["scale"]) + float(context["center"])
            )
            centers[region][int(row.origin_index)] = (
                means[region_index] * float(context["scale"]) + float(context["center"])
            )
    metric_rows = []
    horizon_frames = []
    for region in REGIONS:
        row, horizon = score_driver_arrays(
            region,
            fold,
            method,
            np.asarray(contexts[region]["truth"], dtype=float),
            predictions[region],
            centers[region],
            "saved_predictive_path_mean",
        )
        metric_rows.append(row)
        horizon_frames.append(horizon)
    return metric_rows, horizon_frames, evidence


def score_pricefm_cache(
    data_root: Path,
    fold: int,
    contexts: Mapping[str, Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], list[pd.DataFrame], list[dict[str, Any]]]:
    cache = data_root / "diagnostics" / PRICEFM_CACHE_TAG
    summary_path = cache / "summary.json"
    summary = read_json(summary_path)
    if (
        summary.get("status") != "completed_pricefm_validation_driver_cache"
        or summary.get("split") != "validation_only"
        or summary.get("test_opened") is not False
    ):
        raise RuntimeError("invalid PriceFM validation driver cache")
    records = {
        (str(record["region"]), int(record["fold"])): record
        for record in summary["artifacts"]
    }
    evidence = [artifact_record("pricefm_driver_cache_summary", summary_path)]
    metric_rows = []
    horizon_frames = []
    for region in REGIONS:
        record = records[(region, fold)]
        path = Path(record["path"])
        evidence.append(validate_record(path, record["sha256"], "pricefm_validation_quantiles"))
        with np.load(path, allow_pickle=False) as archive:
            prediction_scaled = np.asarray(archive["prediction_scaled"], dtype=float)
            truth_scaled = np.asarray(archive["truth_scaled"], dtype=float)
            anchors = np.asarray(archive["anchors"], dtype=str)
            quantiles = np.asarray(archive["quantiles"], dtype=float)
        context = contexts[region]
        if (
            prediction_scaled.shape != context["truth_scaled"].shape + (len(QUANTILES),)
            or not np.allclose(quantiles, QUANTILES)
            or not np.array_equal(anchors, context["anchors"])
            or not np.allclose(truth_scaled, context["truth_scaled"], atol=1e-6, rtol=1e-6)
        ):
            raise RuntimeError("PriceFM and R108 validation evidence disagree")
        prediction = prediction_scaled * float(context["scale"]) + float(context["center"])
        row, horizon = score_driver_arrays(
            region,
            fold,
            "cached_pricefm_quantiles",
            np.asarray(context["truth"], dtype=float),
            prediction,
            prediction[..., 3],
            "released_median_quantile",
        )
        row["posterior_paths"] = np.nan
        metric_rows.append(row)
        horizon_frames.append(horizon)
    return metric_rows, horizon_frames, evidence


def weighted_driver_aggregates(
    cases: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    weighted_columns = (
        "AQL", "AQCR", "coverage_10_90", "mean_width_10_90", "median_MAE",
        "center_MAE", "center_RMSE", "center_bias",
    )
    region_rows = []
    for (region, method), group in cases.groupby(["region", "driver_method"], sort=True):
        weights = group.n_loss_atoms.to_numpy(dtype=float)
        row = {
            "region": region,
            "driver_method": method,
            "folds": int(group.fold.nunique()),
            "cases": int(len(group)),
            "n_loss_atoms": int(weights.sum()),
        }
        for column in weighted_columns:
            row[column] = float(np.average(group[column], weights=weights))
        region_rows.append(row)
    regions = pd.DataFrame(region_rows)
    overall_rows = []
    for method, group in cases.groupby("driver_method", sort=True):
        weights = group.n_loss_atoms.to_numpy(dtype=float)
        row = {
            "driver_method": method,
            "regions": int(group.region.nunique()),
            "folds": int(group[["region", "fold"]].drop_duplicates().shape[0]),
            "n_loss_atoms": int(weights.sum()),
        }
        for column in weighted_columns:
            row[column] = float(np.average(group[column], weights=weights))
        overall_rows.append(row)
    return regions, pd.DataFrame(overall_rows).sort_values("AQL")


def aggregate_horizons(horizons: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (method, horizon), group in horizons.groupby(["driver_method", "horizon"], sort=True):
        weights = group.n_origins.to_numpy(dtype=float)
        rows.append({
            "driver_method": method,
            "horizon": int(horizon),
            "AQL": float(np.average(group.AQL, weights=weights)),
            "coverage_10_90": float(np.average(group.coverage_10_90, weights=weights)),
            "mean_width_10_90": float(np.average(group.mean_width_10_90, weights=weights)),
            "center_MAE": float(np.average(group.center_MAE, weights=weights)),
            "center_bias": float(np.average(group.center_bias, weights=weights)),
            "n_origins": int(weights.sum()),
        })
    return pd.DataFrame(rows)


def selected_family_from_r108_terminal(terminal: Mapping[str, Any]) -> str:
    if (
        terminal.get("status") != "completed_recursive_driver_decomposition_case"
        or terminal.get("test_opened") is not False
        or terminal.get("selection_split") != "validation_only"
    ):
        raise RuntimeError("invalid R108 case selection authority")
    family = str(terminal.get("selected_family", ""))
    if family not in {"al", "exal"}:
        raise RuntimeError("invalid R108 selected family: {}".format(family))
    return family


def candidate_gates(
    overall: pd.DataFrame,
    regions: pd.DataFrame,
    horizons: pd.DataFrame,
) -> pd.DataFrame:
    by_method = overall.set_index("driver_method")
    rhs = by_method.loc["normal_rhs_paths"]
    pricefm = by_method.loc["cached_pricefm_quantiles"]
    late = horizons[horizons.horizon.between(73, 96)].groupby("driver_method").apply(
        lambda group: np.average(group.AQL, weights=group.n_origins),
        include_groups=False,
    )
    rows = []
    for method in ("normal_rhs_paths", "normal_ridge_paths"):
        candidate = by_method.loc[method]
        region_candidate = regions[regions.driver_method.eq(method)].set_index("region")
        region_rhs = regions[regions.driver_method.eq("normal_rhs_paths")].set_index("region")
        max_harm = float(
            (region_candidate.AQL / region_rhs.AQL - 1.0).replace([np.inf, -np.inf], np.nan).max()
        )
        checks = (
            ("complete_27_cases", int(candidate.folds) == 27, int(candidate.folds), 27),
            (
                "aql_improvement_vs_rhs_at_least_30pct",
                1.0 - float(candidate.AQL) / float(rhs.AQL) >= 0.30,
                1.0 - float(candidate.AQL) / float(rhs.AQL),
                0.30,
            ),
            (
                "aql_no_more_than_25pct_above_pricefm",
                float(candidate.AQL) <= 1.25 * float(pricefm.AQL),
                float(candidate.AQL) / float(pricefm.AQL) - 1.0,
                0.25,
            ),
            (
                "late_horizon_improvement_vs_rhs_at_least_30pct",
                1.0 - float(late[method]) / float(late["normal_rhs_paths"]) >= 0.30,
                1.0 - float(late[method]) / float(late["normal_rhs_paths"]),
                0.30,
            ),
            (
                "coverage_distance_harm_at_most_0p02",
                abs(float(candidate.coverage_10_90) - 0.80)
                <= abs(float(rhs.coverage_10_90) - 0.80) + 0.02,
                abs(float(candidate.coverage_10_90) - 0.80)
                - abs(float(rhs.coverage_10_90) - 0.80),
                0.02,
            ),
            (
                "maximum_region_aql_harm_at_most_10pct",
                max_harm <= 0.10,
                max_harm,
                0.10,
            ),
        )
        for gate, passed, observed, threshold in checks:
            rows.append({
                "candidate": method,
                "gate": gate,
                "passed": bool(passed),
                "observed": observed,
                "threshold": threshold,
            })
    result = pd.DataFrame(rows)
    decision = result.groupby("candidate").passed.all().rename("all_gates_passed")
    return result.merge(decision, on="candidate", how="left")


def downstream_evidence(data_root: Path) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    evidence = []
    rows = []
    r108_path = data_root / "authoritative" / R108_TAG / "pricefm_stage_r108_overall_policy_metrics.csv"
    r108_summary_path = data_root / "authoritative" / R108_TAG / "summary.json"
    r108_summary = read_json(r108_summary_path)
    if (
        r108_summary.get("status") != "completed_recursive_driver_decomposition"
        or r108_summary.get("selection_split") != "validation_only"
        or r108_summary.get("test_opened") is not False
    ):
        raise RuntimeError("invalid R108 downstream authority")
    record = next(item for item in r108_summary["outputs"] if Path(item["path"]).name == r108_path.name)
    evidence.extend([
        artifact_record("r108_summary", r108_summary_path),
        validate_record(r108_path, record["sha256"], "r108_overall_policy_metrics"),
    ])
    r108 = pd.read_csv(r108_path)
    for row in r108.itertuples(index=False):
        rows.append({
            "source_stage": "R108",
            "evidence_scope": "nine_regions_27_cases_validation",
            "region": "ALL_9",
            "policy": str(row.policy),
            "AQL": float(row.AQL),
            "coverage_10_90": float(row.coverage_10_90),
            "mean_width_10_90": float(row.mean_width_10_90),
            "n_loss_atoms": int(row.n_loss_atoms),
            "complete_cases": int(row.folds),
            "interpretation": "complete_saved_fit_driver_decomposition",
        })

    r103_rows = []
    for region in REGIONS:
        for fold in (1, 2, 3):
            case = (
                data_root / "campaigns" / R103_TAG / "cases"
                / "region={}".format(region) / "fold={}".format(fold)
            )
            terminal_path = case / "terminal.json"
            terminal = read_json(terminal_path)
            metric_path = case / "family_validation_metrics.csv"
            if (
                terminal.get("status") != "completed_recursive_quantile_case"
                or terminal.get("selection_split") != "validation_only"
                or terminal.get("test_opened") is not False
            ):
                raise RuntimeError("incomplete R103 case: {}".format(case))
            metric_record = next(
                (
                    item for item in terminal.get("artifacts", [])
                    if Path(item["path"]).name == metric_path.name
                ),
                None,
            )
            if metric_record is None:
                raise RuntimeError("R103 metric is absent from terminal: {}".format(case))
            r108_terminal_path = (
                data_root / "authoritative" / R108_TAG / "cases"
                / "region={}".format(region) / "fold={}".format(fold)
                / "terminal.json"
            )
            r108_case_terminal = read_json(r108_terminal_path)
            selected = selected_family_from_r108_terminal(r108_case_terminal)
            metric = pd.read_csv(metric_path)
            chosen = metric[metric.family.astype(str).eq(selected)]
            if len(chosen) != 1 or bool(chosen.test_opened.iloc[0]):
                raise RuntimeError("invalid R103 selected-family metric")
            r103_rows.append(chosen.iloc[0].to_dict())
            evidence.extend([
                artifact_record("r103_case_terminal", terminal_path),
                artifact_record("r108_case_terminal", r108_terminal_path),
                validate_record(
                    metric_path,
                    metric_record["sha256"],
                    "r103_family_validation_metrics",
                ),
            ])
    r103 = pd.DataFrame(r103_rows)
    weights = r103.n_loss_atoms.to_numpy(dtype=float)
    rows.append({
        "source_stage": "R103",
        "evidence_scope": "nine_regions_27_cases_validation",
        "region": "ALL_9",
        "policy": "normal_rhs_all_active_paths",
        "AQL": float(np.average(r103.validation_AQL_original, weights=weights)),
        "coverage_10_90": np.nan,
        "mean_width_10_90": np.nan,
        "n_loss_atoms": int(weights.sum()),
        "complete_cases": int(len(r103)),
        "interpretation": "complete_downstream_control_from_saved_r103_predictions",
    })

    r104_root = data_root / "authoritative" / R104_TAG
    r104_path = r104_root / "pricefm_stage_r104_operator_aggregate_metrics.csv"
    r104_summary_path = r104_root / "summary.json"
    r104_summary = read_json(r104_summary_path)
    if (
        r104_summary.get("status")
        != "completed_validation_only_forecast_operator_diagnosis"
        or r104_summary.get("test_opened") is not False
    ):
        raise RuntimeError("invalid R104 downstream authority")
    r104_record = next(
        (
            item for item in r104_summary.get("outputs", [])
            if Path(item["path"]).name == r104_path.name
        ),
        None,
    )
    if r104_record is None:
        raise RuntimeError("R104 aggregate metric is absent from summary")
    r104 = pd.read_csv(r104_path)
    evidence.extend([
        artifact_record("r104_summary", r104_summary_path),
        validate_record(
            r104_path,
            r104_record["sha256"],
            "r104_focused_operator_metrics",
        ),
    ])
    for row in r104.itertuples(index=False):
        rows.append({
            "source_stage": "R104",
            "evidence_scope": "focused_region_three_fold_validation",
            "region": str(row.region),
            "policy": str(row.policy),
            "AQL": float(row.AQL),
            "coverage_10_90": float(row.coverage_10_90),
            "mean_width_10_90": float(row.mean_width_10_90),
            "n_loss_atoms": int(row.n_loss_atoms),
            "complete_cases": int(row.folds),
            "interpretation": "focused_saved_driver_operator_diagnostic",
        })
    return pd.DataFrame(rows), evidence


def write_pdf(
    path: Path,
    overall: pd.DataFrame,
    regions: pd.DataFrame,
    horizon_overall: pd.DataFrame,
    downstream: pd.DataFrame,
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    order = ["normal_rhs_paths", "normal_ridge_paths", "cached_pricefm_quantiles"]
    labels = {"normal_rhs_paths": "Normal RHS", "normal_ridge_paths": "Normal Ridge", "cached_pricefm_quantiles": "Cached PriceFM"}
    colors = {"normal_rhs_paths": "#C44E52", "normal_ridge_paths": "#4C72B0", "cached_pricefm_quantiles": "#2A7F62"}
    with PdfPages(path) as pdf:
        frame = overall.set_index("driver_method").loc[order]
        fig, axes = plt.subplots(1, 2, figsize=(13, 5))
        axes[0].bar(labels.values(), frame.AQL, color=[colors[item] for item in order])
        axes[0].set_title("Full predictive distribution")
        axes[0].set_ylabel("Validation AQL (lower is better)")
        axes[1].bar(labels.values(), frame.center_MAE, color=[colors[item] for item in order])
        axes[1].set_title("Central trajectory")
        axes[1].set_ylabel("Validation MAE (lower is better)")
        for axis in axes:
            axis.grid(axis="y", alpha=0.2)
            axis.tick_params(axis="x", rotation=12)
        fig.suptitle("R109 saved future-price driver quality: nine-region panel")
        fig.tight_layout(rect=(0, 0, 1, 0.94))
        pdf.savefig(fig)
        plt.close(fig)

        fig, axis = plt.subplots(figsize=(13, 6))
        pivot = regions.pivot(index="region", columns="driver_method", values="AQL").loc[list(REGIONS), order]
        x = np.arange(len(pivot))
        width = 0.25
        for index, method in enumerate(order):
            axis.bar(x + (index - 1) * width, pivot[method], width, label=labels[method], color=colors[method])
        axis.set_xticks(x, pivot.index)
        axis.set_ylabel("Validation AQL")
        axis.set_title("Saved-driver AQL by region, pooled over folds")
        axis.grid(axis="y", alpha=0.2)
        axis.legend(frameon=False)
        fig.tight_layout()
        pdf.savefig(fig)
        plt.close(fig)

        fig, axis = plt.subplots(figsize=(12, 5))
        for method in order:
            frame = horizon_overall[horizon_overall.driver_method.eq(method)]
            axis.plot(frame.horizon, frame.AQL, label=labels[method], color=colors[method], linewidth=2)
        axis.set_xlabel("Forecast horizon")
        axis.set_ylabel("Validation AQL")
        axis.set_title("Saved-driver horizon deterioration")
        axis.grid(alpha=0.2)
        axis.legend(frameon=False)
        fig.tight_layout()
        pdf.savefig(fig)
        plt.close(fig)

        selected = downstream[
            (downstream.region.eq("ALL_9"))
            & downstream.policy.isin([
                "oracle_all_active", "oracle_target_l0p00_rhs_neighbors",
                "r97_direct_reference", "pricefm_quantile_paths_all_active",
                "self_rhs_neighbors", "normal_rhs_all_active_paths",
            ])
        ].sort_values("AQL")
        fig, axis = plt.subplots(figsize=(12, 5))
        axis.barh(selected.policy.str.replace("_", " "), selected.AQL, color="#5B6472")
        axis.invert_yaxis()
        axis.set_xlabel("Validation AQL")
        axis.set_title("Existing downstream evidence (frozen Q-DESN readouts)")
        axis.grid(axis="x", alpha=0.2)
        fig.tight_layout()
        pdf.savefig(fig)
        plt.close(fig)


def prepare_output(output: Path, force: bool) -> tuple[Path, Path | None]:
    quarantined = None
    if output.exists():
        if not force:
            raise FileExistsError(output)
        quarantine = output.parent / "quarantine"
        quarantine.mkdir(parents=True, exist_ok=True)
        index = 1
        candidate = quarantine / "{}.replaced_{:02d}".format(output.name, index)
        while candidate.exists():
            index += 1
            candidate = quarantine / "{}.replaced_{:02d}".format(output.name, index)
        output.rename(candidate)
        quarantined = candidate
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    return temporary, quarantined


def run(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    output = args.output_dir.resolve()
    temporary, quarantined = prepare_output(output, bool(args.force))
    try:
        contexts_by_fold = {}
        evidence = [artifact_record("r109_executed_source", Path(__file__))]
        for fold in (1, 2, 3):
            contexts = {}
            for region in REGIONS:
                context, records = load_case_context(data_root, region, fold)
                contexts[region] = context
                evidence.extend(records)
            contexts_by_fold[fold] = contexts

        metric_rows = []
        horizon_frames = []
        for fold in (1, 2, 3):
            contexts = contexts_by_fold[fold]
            for prior_type in ("rhs_ns", "scaled_ridge"):
                rows, horizons, records = score_normal_surface(
                    data_root, prior_type, fold, contexts
                )
                metric_rows.extend(rows)
                horizon_frames.extend(horizons)
                evidence.extend(records)
            rows, horizons, records = score_pricefm_cache(data_root, fold, contexts)
            metric_rows.extend(rows)
            horizon_frames.extend(horizons)
            evidence.extend(records)

        cases = pd.DataFrame(metric_rows).sort_values(["region", "fold", "driver_method"])
        horizons = pd.concat(horizon_frames, ignore_index=True).sort_values(
            ["region", "fold", "driver_method", "horizon"]
        )
        if (
            len(cases) != len(REGIONS) * 3 * 3
            or cases.duplicated(["region", "fold", "driver_method"]).any()
            or set(cases.selection_split) != {"validation_only"}
            or cases.test_opened.astype(bool).any()
        ):
            raise RuntimeError("R109 driver case contract is incomplete")
        regions, overall = weighted_driver_aggregates(cases)
        horizon_overall = aggregate_horizons(horizons)
        gates = candidate_gates(overall, regions, horizon_overall)
        downstream, records = downstream_evidence(data_root)
        evidence.extend(records)
        decision = bool(
            gates.groupby("candidate").all_gates_passed.first().any()
        )

        cases.to_csv(temporary / "pricefm_stage_r109_driver_case_metrics.csv", index=False)
        horizons.to_csv(temporary / "pricefm_stage_r109_driver_horizon_metrics.csv", index=False)
        regions.to_csv(temporary / "pricefm_stage_r109_driver_region_metrics.csv", index=False)
        overall.to_csv(temporary / "pricefm_stage_r109_driver_overall_metrics.csv", index=False)
        downstream.to_csv(temporary / "pricefm_stage_r109_downstream_evidence.csv", index=False)
        gates.to_csv(temporary / "pricefm_stage_r109_candidate_gates.csv", index=False)
        source_manifest = pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"])
        source_manifest.sort_values(["role", "path"]).to_csv(
            temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL
        )
        write_pdf(
            temporary / "pricefm_stage_r109_saved_driver_quality.pdf",
            overall,
            regions,
            horizon_overall,
            downstream,
        )

        rhs = overall[overall.driver_method.eq("normal_rhs_paths")].iloc[0]
        ridge = overall[overall.driver_method.eq("normal_ridge_paths")].iloc[0]
        pricefm = overall[overall.driver_method.eq("cached_pricefm_quantiles")].iloc[0]
        lines = [
            "# PriceFM Stage-R109 saved-driver quality closeout",
            "",
            "R109 reads frozen validation-only predictions and performs no fitting or downstream replay.",
            "",
            "## Saved-driver metrics",
            "",
            overall.to_markdown(index=False, floatfmt=".5f"),
            "",
            "## Candidate gates",
            "",
            gates.to_markdown(index=False, floatfmt=".5f"),
            "",
            "## Diagnosis",
            "",
            "- Normal RHS validation driver AQL: `{:.5f}`.".format(rhs.AQL),
            "- Normal Ridge validation driver AQL: `{:.5f}`.".format(ridge.AQL),
            "- Cached PriceFM validation driver AQL: `{:.5f}`.".format(pricefm.AQL),
            "- Full downstream replay authorized: `{}`.".format(decision),
            "",
            "A failed saved-driver gate directs the project to the bounded R110 training-only driver redesign. It does not authorize DESN/tau0 rescreening, test access, registry mutation, or article changes.",
            "",
        ]
        (temporary / "pricefm_stage_r109_saved_driver_quality.md").write_text("\n".join(lines))

        outputs = []
        for path in sorted(temporary.iterdir()):
            if path.is_file() and path.name != "summary.json":
                outputs.append(
                    published_artifact_record(
                        "r109_output",
                        path,
                        output / path.name,
                    )
                )
        summary = {
            "stage": "R109",
            "status": "completed_saved_driver_quality_closeout",
            "regions": list(REGIONS),
            "cases_complete": int(len(cases)),
            "cases_expected": 81,
            "normal_posterior_paths": 500,
            "selection_split": "validation_only",
            "test_opened": False,
            "model_fit_started": False,
            "downstream_replay_started": False,
            "full_downstream_replay_authorized": decision,
            "next_stage": (
                "bounded_R110_standalone_driver_redesign"
                if not decision else "bounded_27_case_saved_driver_replay"
            ),
            "registry_mutated": False,
            "article_mutated": False,
            "launch_yaml_written": False,
            "quarantined_previous_output": (
                None if quarantined is None else str(quarantined.resolve())
            ),
            "outputs": outputs,
        }
        write_json(temporary / "summary.json", summary)
        temporary.rename(output)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
