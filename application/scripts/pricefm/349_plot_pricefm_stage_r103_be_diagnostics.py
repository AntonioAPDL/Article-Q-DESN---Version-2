#!/usr/bin/env python3
"""Build reproducible BE diagnostic PDFs for the PriceFM R103 campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from typing import Any, Iterable

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, sha256_file
from pricefm_desn_adapter import load_window
from pricefm_operational_fullshot import (
    inverse_scale_y,
    load_scaler,
    pack_target,
    read_json,
    stack_regional_inputs,
)


QUANTILES = np.asarray([0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90])
METHOD_ORDER = ("r103", "r98", "pricefm")
METHOD_LABELS = {
    "r103": "R103 recursive exAL Q-DESN",
    "r98": "R98 direct exAL Q-DESN",
    "pricefm": "Operational PriceFM reproduction",
}
COLORS = {"r103": "#C44E52", "r98": "#2A6FBB", "pricefm": "#2F855A"}
TRUTH_COLOR = "#202428"
BACKGROUND = "#FBFBF8"
DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
DEFAULT_UPSTREAM = DEFAULT_DATA_ROOT / "external/PriceFM"
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R97_TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
OPERATIONAL_TAG = "pricefm_operational_public_architecture_fullshot_20260812"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument("--upstream-root", type=Path, default=DEFAULT_UPSTREAM)
    value.add_argument("--region", default="BE")
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "figures/pricefm_stage_r103_be_diagnostics_20260917",
    )
    value.add_argument("--batch-size", type=int, default=128)
    return value


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(payload.encode()).hexdigest()


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")
    temporary.replace(path)


def atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    temporary.replace(path)


def validate_surface(surface: dict[str, Any]) -> dict[str, Any]:
    truth = np.asarray(surface["truth"], dtype=float)
    prediction = np.asarray(surface["prediction"], dtype=float)
    quantiles = np.asarray(surface["quantiles"], dtype=float)
    anchors = np.asarray(surface["anchors"])
    if truth.ndim != 2 or truth.shape[1] != 96:
        raise ValueError("truth must have shape (origins, 96)")
    if prediction.shape != truth.shape + (quantiles.size,):
        raise ValueError("prediction geometry does not match truth and quantiles")
    if anchors.shape != (truth.shape[0],):
        raise ValueError("anchor count does not match truth")
    if quantiles.shape != QUANTILES.shape or not np.allclose(quantiles, QUANTILES, rtol=0, atol=1e-12):
        raise ValueError("unexpected quantile grid")
    if not np.isfinite(truth).all() or not np.isfinite(prediction).all():
        raise ValueError("surface contains non-finite values")
    surface = dict(surface)
    surface.update({"truth": truth, "prediction": prediction, "quantiles": quantiles})
    return surface


def pinball_array(truth: np.ndarray, prediction: np.ndarray, quantiles: np.ndarray) -> np.ndarray:
    error = np.asarray(truth, dtype=float)[..., None] - np.asarray(prediction, dtype=float)
    q = np.asarray(quantiles, dtype=float).reshape(1, 1, -1)
    return np.maximum(q * error, (q - 1.0) * error)


def surface_metrics(surface: dict[str, Any]) -> dict[str, float]:
    surface = validate_surface(surface)
    truth = surface["truth"]
    prediction = surface["prediction"]
    pinball = pinball_array(truth, prediction, surface["quantiles"])
    median = prediction[..., int(np.argmin(np.abs(surface["quantiles"] - 0.5)))]
    crossing = prediction[..., :-1] > prediction[..., 1:]
    return {
        "AQL": float(pinball.mean()),
        "AQCR": float(crossing.mean()),
        "median_MAE": float(np.mean(np.abs(truth - median))),
        "median_RMSE": float(np.sqrt(np.mean((truth - median) ** 2))),
        "coverage_10_90": float(np.mean((truth >= prediction[..., 0]) & (truth <= prediction[..., -1]))),
    }


def horizon_aql(surface: dict[str, Any]) -> np.ndarray:
    surface = validate_surface(surface)
    return pinball_array(surface["truth"], surface["prediction"], surface["quantiles"]).mean(axis=(0, 2))


def representative_origin_index(n_origins: int) -> int:
    if n_origins < 1:
        raise ValueError("at least one origin is required")
    return (int(n_origins) - 1) // 2


def anchor_nanoseconds(anchors: Any) -> np.ndarray:
    values = np.asarray(anchors)
    if np.issubdtype(values.dtype, np.number):
        parsed = pd.to_datetime(values.astype(np.int64), unit="ns", utc=True)
    else:
        parsed = pd.to_datetime(values, utc=True, format="mixed")
    return np.asarray(parsed.astype("int64"), dtype=np.int64)


def anchor_label(anchor: Any) -> str:
    values = np.asarray([anchor])
    if np.issubdtype(values.dtype, np.number):
        parsed = pd.to_datetime(int(values[0]), unit="ns", utc=True)
    else:
        parsed = pd.to_datetime(str(values[0]), utc=True)
    return parsed.strftime("%Y-%m-%d")


def strict_anchor_alignment(surfaces: Iterable[dict[str, Any]]) -> None:
    items = list(surfaces)
    if not items:
        raise ValueError("no surfaces supplied")
    reference = validate_surface(items[0])
    for candidate in items[1:]:
        candidate = validate_surface(candidate)
        try:
            aligned = np.array_equal(
                anchor_nanoseconds(reference["anchors"]),
                anchor_nanoseconds(candidate["anchors"]),
            )
        except (TypeError, ValueError) as error:
            raise ValueError("forecast-origin anchors are invalid") from error
        if not aligned:
            raise ValueError("forecast-origin anchors are not aligned")
        if not np.allclose(reference["truth"], candidate["truth"], rtol=0, atol=2e-4):
            raise ValueError("observed responses are not aligned")


def _r103_paths(data_root: Path, region: str, fold: int) -> tuple[Path, Path]:
    config = data_root / "launch_prep" / R103_TAG / "cases" / f"r103_{region.lower()}_f{fold}.json"
    output = data_root / "campaigns" / R103_TAG / "cases" / f"region={region}" / f"fold={fold}"
    return config, output


def load_r103_surface(data_root: Path, region: str, fold: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    config_path, output = _r103_paths(data_root, region, fold)
    config = json.loads(config_path.read_text())
    terminal = json.loads((output / "terminal.json").read_text())
    if terminal.get("status") != "completed_recursive_quantile_case":
        raise RuntimeError(f"R103 case is not complete: {output}")
    metrics = pd.read_csv(output / "family_validation_metrics.csv")
    selected_family = "exal"
    row = metrics.loc[metrics.family.eq(selected_family)].iloc[0]
    prediction_path = Path(row.prediction_path)
    if sha256_file(prediction_path) != row.prediction_sha256:
        raise RuntimeError(f"R103 prediction hash mismatch: {prediction_path}")
    with np.load(prediction_path, allow_pickle=False) as archive:
        prediction_scaled = np.asarray(archive["prediction_scaled"], dtype=float).transpose(1, 2, 0)
        quantiles = np.asarray(archive["quantiles"], dtype=float)
        anchors = np.asarray(archive["anchors"], dtype=str)
    data_config = load_config(config["data_config_path"])
    window = load_window(data_config, fold, region, "val")
    scaler_path = (
        Path(data_config["pricefm"]["processed_dir"])
        / "scalers"
        / f"fold_{fold}"
        / "per_region_separate_xy_scalers.joblib"
    )
    scaler = joblib.load(scaler_path)[region]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    surface = validate_surface({
        "method": "r103",
        "fold": fold,
        "split": "validation",
        "anchors": anchors,
        "truth": inverse_scale_y(window["Y"], center, scale),
        "prediction": inverse_scale_y(prediction_scaled, center, scale),
        "quantiles": quantiles,
        "selection": "exAL retained from fold-1 validation for the full region",
    })
    observed = surface_metrics(surface)["AQL"]
    if not np.isclose(observed, float(row.validation_AQL_original), rtol=1e-7, atol=1e-7):
        raise RuntimeError(f"R103 AQL does not reproduce its frozen metric: {fold}")
    sources = [
        source_record("r103_case_config", config_path),
        source_record("r103_terminal", output / "terminal.json"),
        source_record("r103_prediction", prediction_path),
        source_record("r103_validation_window", Path(window["path"])),
        source_record("r103_scaler", scaler_path),
    ]
    return surface, sources


def _matrix_from_long(frame: pd.DataFrame, value: str) -> np.ndarray:
    ordered = frame.sort_values(["origin_id", "horizon"])
    n_origins = int(ordered.origin_id.nunique())
    if len(ordered) != n_origins * 96:
        raise ValueError("long prediction table is not a complete 96-horizon rectangle")
    matrix = ordered[value].to_numpy(dtype=float).reshape(n_origins, 96)
    return matrix


def load_r98_validation_surface(
    data_root: Path, region: str, fold: int
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    closeout = data_root / "campaigns" / R97_TAG / "region_closeouts" / region
    manifest_path = closeout / "pricefm_stage_r97_selected_atom_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    rows = manifest.loc[manifest.fold.eq(fold)].sort_values("tau")
    if len(rows) != len(QUANTILES) or not np.allclose(rows.tau, QUANTILES):
        raise RuntimeError("R98 selected manifest does not contain the seven quantiles")
    predictions = []
    sources = [source_record("r98_selected_atom_manifest", manifest_path)]
    for row in rows.itertuples(index=False):
        path = Path(row.prediction_path)
        if sha256_file(path) != row.prediction_sha256:
            raise RuntimeError(f"R98 prediction hash mismatch: {path}")
        predictions.append(_matrix_from_long(pd.read_csv(path), "pred_scaled"))
        sources.append(source_record(f"r98_validation_prediction_q{row.tau:.2f}", path))
    rows_path = Path(rows.iloc[0].rows_val_path)
    scaler_path = Path(rows.iloc[0].scaler_path)
    observations = pd.read_csv(rows_path)
    truth_scaled = _matrix_from_long(observations, "y_scaled")
    anchors = (
        observations.sort_values(["origin_id", "horizon"])
        .groupby("origin_id", sort=True)["origin_market_time"]
        .first()
        .to_numpy(dtype=str)
    )
    scaler = joblib.load(scaler_path)[region]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    surface = validate_surface({
        "method": "r98",
        "fold": fold,
        "split": "validation",
        "anchors": anchors,
        "truth": inverse_scale_y(truth_scaled, center, scale),
        "prediction": inverse_scale_y(np.stack(predictions, axis=-1), center, scale),
        "quantiles": QUANTILES,
        "selection": "region-frozen exAL family; quantile atoms selected without test",
    })
    sources.extend([source_record("r98_validation_rows", rows_path), source_record("r98_scaler", scaler_path)])
    return surface, sources


def load_r98_test_surface(
    data_root: Path, region: str, fold: int
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    run = data_root / "campaigns" / R97_TAG / "global_scoring" / "runs" / f"region={region}" / f"fold={fold}"
    prediction_path = run / "score/test_predictions_scaled.csv"
    rows_path = run / "adapter/rows_test.csv"
    prediction_rows = pd.read_csv(prediction_path)
    quantile_matrices = [
        _matrix_from_long(prediction_rows.loc[np.isclose(prediction_rows.tau, tau)], "pred_scaled")
        for tau in QUANTILES
    ]
    observations = pd.read_csv(rows_path)
    truth_scaled = _matrix_from_long(observations, "y_scaled")
    anchors = (
        observations.sort_values(["origin_id", "horizon"])
        .groupby("origin_id", sort=True)["origin_market_time"]
        .first()
        .to_numpy(dtype=str)
    )
    selected_manifest = (
        data_root / "campaigns" / R97_TAG / "region_closeouts" / region
        / "pricefm_stage_r97_selected_atom_manifest.csv"
    )
    selected = pd.read_csv(selected_manifest)
    scaler_path = Path(selected.loc[selected.fold.eq(fold), "scaler_path"].iloc[0])
    scaler = joblib.load(scaler_path)[region]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    surface = validate_surface({
        "method": "r98",
        "fold": fold,
        "split": "outer_test",
        "anchors": anchors,
        "truth": inverse_scale_y(truth_scaled, center, scale),
        "prediction": inverse_scale_y(np.stack(quantile_matrices, axis=-1), center, scale),
        "quantiles": QUANTILES,
        "selection": "frozen before outer-test scoring",
    })
    return surface, [
        source_record("r98_test_predictions", prediction_path),
        source_record("r98_test_rows", rows_path),
        source_record("r98_scaler", scaler_path),
    ]


def operational_validation_fingerprint(
    root: Path, row: pd.Series, fold: int, regions: list[str]
) -> tuple[str, list[dict[str, Any]]]:
    paths = [
        ("operational_protocol", root / "provenance/protocol.json"),
        ("operational_winner_freeze", root / "selection/winner_freeze.json"),
        ("operational_cell_winners", root / "selection/cell_specific_winners.csv"),
        ("operational_checkpoint", Path(row.checkpoint)),
        ("operational_scaler", root / f"data/scalers/fold_{fold}/region={row.region}.npz"),
    ]
    paths.extend(
        (f"operational_validation_window_{region}", root / f"data/windows/fold_{fold}/region={region}/val.npz")
        for region in regions
    )
    records = [source_record(role, path) for role, path in paths]
    signature = canonical_hash([(item["role"], item["path"], item["sha256"]) for item in records])
    return signature, records


def load_or_predict_operational_validation(
    data_root: Path,
    upstream_root: Path,
    output_dir: Path,
    region: str,
    fold: int,
    batch_size: int,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    root = data_root / "benchmarks" / OPERATIONAL_TAG
    freeze = read_json(root / "selection/winner_freeze.json")
    if freeze.get("status") != "frozen_before_test" or freeze.get("selection_reads_test") is not False:
        raise RuntimeError("operational PriceFM selection is not validation-only and frozen")
    winners = pd.read_csv(root / "selection/cell_specific_winners.csv")
    selected = winners.loc[winners.fold.eq(fold) & winners.region.eq(region)]
    if len(selected) != 1:
        raise RuntimeError("expected exactly one operational PriceFM winner")
    row = selected.iloc[0]
    if sha256_file(Path(row.checkpoint)) != row.checkpoint_sha256:
        raise RuntimeError("operational PriceFM checkpoint hash mismatch")
    protocol = read_json(root / "provenance/protocol.json")
    regions = list(protocol["regions"])
    signature, sources = operational_validation_fingerprint(root, row, fold, regions)
    cache = output_dir / "inference" / f"operational_pricefm_{region}_fold{fold}_validation.npz"
    metadata_path = cache.with_suffix(".json")
    use_cache = False
    if cache.is_file() and metadata_path.is_file():
        metadata = read_json(metadata_path)
        use_cache = metadata.get("source_fingerprint") == signature and metadata.get("cache_sha256") == sha256_file(cache)
    if not use_cache:
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
        os.environ.setdefault("TF_DETERMINISTIC_OPS", "1")
        sys.path.insert(0, str(upstream_root))
        import tensorflow as tf
        import PriceFM.model  # noqa: F401

        tf.keras.utils.set_random_seed(int(row.seed))
        try:
            tf.config.threading.set_intra_op_parallelism_threads(1)
            tf.config.threading.set_inter_op_parallelism_threads(1)
        except RuntimeError:
            pass
        model = tf.keras.models.load_model(Path(row.checkpoint), compile=False, safe_mode=True)
        x_lag, x_lead, targets, anchors = stack_regional_inputs(root, fold, "val", regions)
        mask = [int(value) for value in json.loads(row.mask_json)]
        x1, x2, gate, truth_scaled = pack_target(x_lag, x_lead, targets, region, mask)
        prediction_scaled = model.predict(
            {"X_lag_all": x1, "X_lead_all": x2, "graph_gate": gate},
            batch_size=int(batch_size),
            verbose=0,
        )
        cache.parent.mkdir(parents=True, exist_ok=True)
        temporary = cache.with_suffix(".tmp.npz")
        np.savez_compressed(
            temporary,
            anchors=np.asarray(anchors),
            truth_scaled=np.asarray(truth_scaled, dtype=np.float32),
            prediction_scaled=np.asarray(prediction_scaled, dtype=np.float32),
            quantiles=QUANTILES,
        )
        temporary.replace(cache)
        atomic_json(metadata_path, {
            "status": "completed_inference_only",
            "source_fingerprint": signature,
            "cache_sha256": sha256_file(cache),
            "checkpoint": str(row.checkpoint),
            "checkpoint_sha256": row.checkpoint_sha256,
            "selected_on_split": row.selected_on_split,
            "selection_reads_test": bool(row.selection_reads_test),
            "fit_performed": False,
        })
        tf.keras.backend.clear_session()
    with np.load(cache, allow_pickle=False) as archive:
        anchors = np.asarray(archive["anchors"])
        truth_scaled = np.asarray(archive["truth_scaled"], dtype=float)
        prediction_scaled = np.asarray(archive["prediction_scaled"], dtype=float)
        quantiles = np.asarray(archive["quantiles"], dtype=float)
    scaler = load_scaler(root, fold, region)
    center = float(np.asarray(scaler["y_center"]).reshape(-1)[0])
    scale = float(np.asarray(scaler["y_scale"]).reshape(-1)[0])
    surface = validate_surface({
        "method": "pricefm",
        "fold": fold,
        "split": "validation",
        "anchors": anchors,
        "truth": inverse_scale_y(truth_scaled, center, scale),
        "prediction": inverse_scale_y(prediction_scaled, center, scale),
        "quantiles": quantiles,
        "selection": "cell-specific checkpoint selected on validation only",
    })
    if not np.isclose(surface_metrics(surface)["AQL"], float(row.validation_AQL), rtol=2e-6, atol=2e-6):
        raise RuntimeError("operational PriceFM validation AQL does not reproduce frozen selection")
    sources.extend([source_record("operational_validation_inference_cache", cache)])
    return surface, sources


def load_operational_test_surface(
    data_root: Path, region: str, fold: int
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    root = data_root / "benchmarks" / OPERATIONAL_TAG
    manifest_path = root / "test/trial_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    row = manifest.loc[manifest.fold.eq(fold) & manifest.region.eq(region)].iloc[0]
    prediction_path = Path(row.task_dir) / "predictions.npz"
    with np.load(prediction_path, allow_pickle=False) as archive:
        surface = validate_surface({
            "method": "pricefm",
            "fold": fold,
            "split": "outer_test",
            "anchors": np.asarray(archive["anchors_ns"]),
            "truth": np.asarray(archive["y_true"], dtype=float),
            "prediction": np.asarray(archive["y_pred"], dtype=float),
            "quantiles": QUANTILES,
            "selection": "frozen validation winner scored once on outer test",
        })
    return surface, [
        source_record("operational_test_manifest", manifest_path),
        source_record("operational_test_predictions", prediction_path),
    ]


def source_record(role: str, path: Path) -> dict[str, Any]:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    return {"role": role, "path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def configure_plotting() -> None:
    import matplotlib as mpl

    mpl.rcParams.update({
        "figure.facecolor": BACKGROUND,
        "axes.facecolor": BACKGROUND,
        "savefig.facecolor": BACKGROUND,
        "font.family": "DejaVu Sans",
        "font.size": 9.0,
        "axes.titlesize": 10.5,
        "axes.labelsize": 9.0,
        "axes.edgecolor": "#B8BDC2",
        "axes.linewidth": 0.7,
        "axes.grid": True,
        "grid.color": "#D9DCDE",
        "grid.linewidth": 0.55,
        "grid.alpha": 0.75,
        "legend.frameon": False,
        "xtick.color": "#4C5359",
        "ytick.color": "#4C5359",
        "text.color": TRUTH_COLOR,
        "axes.titlecolor": TRUTH_COLOR,
        "axes.labelcolor": TRUTH_COLOR,
        "pdf.fonttype": 42,
    })


def draw_path(ax: Any, surface: dict[str, Any], origin_index: int, show_truth: bool = True) -> None:
    prediction = surface["prediction"][origin_index]
    truth = surface["truth"][origin_index]
    x = np.arange(1, 97) / 4.0
    color = COLORS[surface["method"]]
    ax.fill_between(x, prediction[:, 0], prediction[:, 6], color=color, alpha=0.12, linewidth=0)
    ax.fill_between(x, prediction[:, 1], prediction[:, 5], color=color, alpha=0.22, linewidth=0)
    ax.plot(x, prediction[:, 3], color=color, linewidth=1.45, label="Median forecast")
    if show_truth:
        ax.plot(x, truth, color=TRUTH_COLOR, linewidth=1.2, label="Observed price", zorder=4)
    ax.set_xlim(0.25, 24.0)
    ax.set_xticks([1, 6, 12, 18, 24])
    ax.set_xlabel("Hours ahead")
    ax.set_ylabel("EUR/MWh")


def representative_figure(validation: dict[int, dict[str, dict[str, Any]]], region: str) -> Any:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(3, 3, figsize=(13.2, 8.8), sharex=True)
    for row_index, fold in enumerate((1, 2, 3)):
        n = validation[fold]["r103"]["truth"].shape[0]
        origin_index = representative_origin_index(n)
        for column_index, method in enumerate(METHOD_ORDER):
            surface = validation[fold][method]
            ax = axes[row_index, column_index]
            draw_path(ax, surface, origin_index)
            metric = surface_metrics(surface)["AQL"]
            ax.set_title(f"{METHOD_LABELS[method]}\nFold {fold} | validation AQL {metric:.2f}")
            if column_index:
                ax.set_ylabel("")
            ax.text(
                0.02,
                0.04,
                f"Origin: {anchor_label(surface['anchors'][origin_index])}",
                transform=ax.transAxes,
                fontsize=8,
                color="#5C6268",
            )
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 0.955), ncol=2)
    fig.suptitle(
        f"{region}: representative 24-hour validation forecasts",
        fontsize=16,
        fontweight="bold",
        y=0.995,
    )
    fig.text(0.5, 0.918, "Midpoint origin in each fold; darker band is 50%, lighter band is 80%.", ha="center")
    fig.tight_layout(rect=(0.02, 0.02, 0.99, 0.875))
    return fig


def horizon_figure(surfaces: dict[int, dict[str, dict[str, Any]]], methods: tuple[str, ...], title: str) -> Any:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 3, figsize=(13.4, 4.2), sharey=True)
    x = np.arange(1, 97) / 4.0
    for ax, fold in zip(axes, (1, 2, 3)):
        for method in methods:
            values = horizon_aql(surfaces[fold][method])
            ax.plot(x, values, color=COLORS[method], linewidth=1.65, label=METHOD_LABELS[method])
        ax.set_title(f"Fold {fold}")
        ax.set_xlabel("Hours ahead")
        ax.set_xlim(0.25, 24.0)
        ax.set_xticks([1, 6, 12, 18, 24])
    axes[0].set_ylabel("Average quantile loss (EUR/MWh)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 0.93), ncol=len(methods))
    fig.suptitle(title, fontsize=15.5, fontweight="bold", y=1.00)
    fig.tight_layout(rect=(0.02, 0.02, 0.99, 0.84))
    return fig


def timeline_figure(fold_surfaces: dict[str, dict[str, Any]], methods: tuple[str, ...], title: str) -> Any:
    import matplotlib.dates as mdates
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(methods), 1, figsize=(13.4, 7.8), sharex=True, sharey=True)
    axes = np.atleast_1d(axes)
    for ax, method in zip(axes, methods):
        surface = fold_surfaces[method]
        anchor_values = np.asarray(surface["anchors"])
        if np.issubdtype(anchor_values.dtype, np.number):
            anchors = pd.to_datetime(anchor_values.astype(np.int64), unit="ns", utc=True)
        else:
            anchors = pd.to_datetime(anchor_values, utc=True)
        timestamps = np.concatenate([
            pd.date_range(anchor, periods=96, freq="15min").to_numpy()
            for anchor in anchors
        ])
        truth = surface["truth"].reshape(-1)
        prediction = surface["prediction"].reshape(-1, len(QUANTILES))
        color = COLORS[method]
        ax.fill_between(timestamps, prediction[:, 0], prediction[:, 6], color=color, alpha=0.10, linewidth=0)
        ax.fill_between(timestamps, prediction[:, 1], prediction[:, 5], color=color, alpha=0.18, linewidth=0)
        ax.plot(timestamps, prediction[:, 3], color=color, linewidth=0.55, label="Median forecast")
        ax.plot(timestamps, truth, color=TRUTH_COLOR, linewidth=0.45, alpha=0.82, label="Observed price")
        metric = surface_metrics(surface)["AQL"]
        ax.set_title(f"{METHOD_LABELS[method]} | AQL {metric:.2f}", loc="left", fontweight="bold")
        ax.set_ylabel("EUR/MWh")
        ax.xaxis.set_major_locator(mdates.MonthLocator())
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    axes[-1].set_xlabel("Forecast response time (UTC)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", bbox_to_anchor=(0.975, 0.965), ncol=2)
    fig.suptitle(title, fontsize=15.5, fontweight="bold", y=0.992)
    fig.tight_layout(rect=(0.02, 0.02, 0.99, 0.94))
    return fig


def summary_figure(metrics: pd.DataFrame, region: str) -> Any:
    import matplotlib.pyplot as plt

    validation = metrics.loc[metrics.split.eq("validation")].copy()
    table = validation.pivot(index="fold", columns="method_label", values="AQL")
    table = table[[METHOD_LABELS[method] for method in METHOD_ORDER]]
    table.loc["Weighted mean"] = {
        label: np.average(
            validation.loc[validation.method_label.eq(label), "AQL"],
            weights=validation.loc[validation.method_label.eq(label), "n_origins"],
        )
        for label in table.columns
    }
    fig = plt.figure(figsize=(13.4, 7.5))
    ax = fig.add_axes([0.06, 0.10, 0.88, 0.79])
    ax.axis("off")
    fig.suptitle(f"PriceFM Stage-R103 diagnostic book: {region}", fontsize=20, fontweight="bold", y=0.96)
    fig.text(
        0.06,
        0.885,
        "Aligned validation evidence across three rolling folds",
        fontsize=12,
        color="#4C5359",
    )
    display = table.reset_index().copy()
    display.columns = ["Fold"] + [str(column) for column in display.columns[1:]]
    for column in display.columns[1:]:
        display[column] = display[column].map(lambda value: f"{value:.3f}")
    tab = ax.table(
        cellText=display.values,
        colLabels=display.columns,
        cellLoc="center",
        colLoc="center",
        bbox=[0.0, 0.48, 1.0, 0.34],
    )
    tab.auto_set_font_size(False)
    tab.set_fontsize(9)
    for (row, column), cell in tab.get_celld().items():
        cell.set_edgecolor("#D4D8DA")
        cell.set_linewidth(0.6)
        if row == 0:
            cell.set_facecolor("#E9ECEB")
            cell.set_text_props(weight="bold")
        elif row == len(display):
            cell.set_facecolor("#F1F3F2")
            cell.set_text_props(weight="bold")
        else:
            cell.set_facecolor(BACKGROUND)
    notes = [
        "R103 uses recursive endogenous-price paths driven by the Normal-RHS model.",
        "R98 is the earlier direct-horizon Q-DESN authority and answers a different forecasting question.",
        "Operational PriceFM is the public-architecture reproduction selected on validation only.",
        "Outer-test pages compare R98 with PriceFM only; R103 test data remain unopened.",
        "AQL is lower-is-better and averages seven quantiles, 96 horizons, and all daily origins.",
    ]
    for index, note in enumerate(notes):
        ax.text(0.0, 0.39 - 0.064 * index, f"{index + 1}. {note}", fontsize=10.5, va="top")
    return fig


def representative_test_figure(test: dict[int, dict[str, dict[str, Any]]], region: str) -> Any:
    import matplotlib.pyplot as plt

    methods = ("r98", "pricefm")
    fig, axes = plt.subplots(3, 2, figsize=(11.2, 9.0), sharex=True)
    for row_index, fold in enumerate((1, 2, 3)):
        index = representative_origin_index(test[fold]["r98"]["truth"].shape[0])
        for column_index, method in enumerate(methods):
            surface = test[fold][method]
            ax = axes[row_index, column_index]
            draw_path(ax, surface, index)
            ax.set_title(f"{METHOD_LABELS[method]}\nFold {fold} | outer-test AQL {surface_metrics(surface)['AQL']:.2f}")
            if column_index:
                ax.set_ylabel("")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 0.952), ncol=2)
    fig.suptitle(f"{region}: frozen outer-test comparison", fontsize=16, fontweight="bold", y=0.995)
    fig.tight_layout(rect=(0.02, 0.02, 0.99, 0.895))
    return fig


def save_figure(fig: Any, individual: Any, book: Any) -> None:
    individual.savefig(fig, bbox_inches="tight")
    book.savefig(fig, bbox_inches="tight")


def write_pdfs(
    output_dir: Path,
    region: str,
    validation: dict[int, dict[str, dict[str, Any]]],
    test: dict[int, dict[str, dict[str, Any]]],
    metrics: pd.DataFrame,
) -> list[Path]:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    configure_plotting()
    output_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "book": output_dir / f"pricefm_r103_{region.lower()}_diagnostic_book.pdf",
        "representative": output_dir / f"pricefm_r103_{region.lower()}_validation_representative_origins.pdf",
        "horizon": output_dir / f"pricefm_r103_{region.lower()}_validation_horizon_aql.pdf",
        "timeline": output_dir / f"pricefm_r103_{region.lower()}_validation_timelines.pdf",
        "test": output_dir / f"pricefm_{region.lower()}_outer_test_direct_comparison.pdf",
    }
    metadata = {"Title": f"PriceFM R103 {region} diagnostics", "Author": "Article Q-DESN reproducibility pipeline"}
    with PdfPages(paths["book"], metadata=metadata) as book:
        figure = summary_figure(metrics, region)
        book.savefig(figure, bbox_inches="tight")
        plt.close(figure)
        with PdfPages(paths["horizon"], metadata=metadata) as individual:
            figure = horizon_figure(
                validation,
                METHOD_ORDER,
                f"{region}: validation AQL by forecast horizon",
            )
            save_figure(figure, individual, book)
            plt.close(figure)
        with PdfPages(paths["representative"], metadata=metadata) as individual:
            figure = representative_figure(validation, region)
            save_figure(figure, individual, book)
            plt.close(figure)
        with PdfPages(paths["timeline"], metadata=metadata) as individual:
            for fold in (1, 2, 3):
                figure = timeline_figure(
                    validation[fold],
                    METHOD_ORDER,
                    f"{region}: complete validation window, fold {fold}",
                )
                save_figure(figure, individual, book)
                plt.close(figure)
        with PdfPages(paths["test"], metadata=metadata) as individual:
            figure = horizon_figure(
                test,
                ("r98", "pricefm"),
                f"{region}: frozen outer-test AQL by forecast horizon",
            )
            save_figure(figure, individual, book)
            plt.close(figure)
            figure = representative_test_figure(test, region)
            save_figure(figure, individual, book)
            plt.close(figure)
            for fold in (1, 2, 3):
                figure = timeline_figure(
                    test[fold],
                    ("r98", "pricefm"),
                    f"{region}: complete outer-test window, fold {fold}",
                )
                save_figure(figure, individual, book)
                plt.close(figure)
    return list(paths.values())


def metric_tables(
    validation: dict[int, dict[str, dict[str, Any]]],
    test: dict[int, dict[str, dict[str, Any]]],
) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows = []
    horizons = []
    for split, collection in (("validation", validation), ("outer_test", test)):
        for fold, methods in collection.items():
            for method, surface in methods.items():
                result = surface_metrics(surface)
                rows.append({
                    "split": split,
                    "fold": fold,
                    "method": method,
                    "method_label": METHOD_LABELS[method],
                    "n_origins": surface["truth"].shape[0],
                    "n_horizons": surface["truth"].shape[1],
                    **result,
                })
                horizons.extend({
                    "split": split,
                    "fold": fold,
                    "method": method,
                    "method_label": METHOD_LABELS[method],
                    "horizon": index + 1,
                    "hours_ahead": (index + 1) / 4.0,
                    "AQL": float(value),
                } for index, value in enumerate(horizon_aql(surface)))
    return pd.DataFrame(rows), pd.DataFrame(horizons)


def write_report(output_dir: Path, region: str, metrics: pd.DataFrame, pdfs: list[Path]) -> Path:
    path = output_dir / "README.md"
    validation = metrics.loc[metrics.split.eq("validation")]
    test = metrics.loc[metrics.split.eq("outer_test")]

    def markdown_table(frame: pd.DataFrame) -> str:
        columns = list(frame.columns)
        rendered = []
        for row in frame.itertuples(index=False, name=None):
            rendered.append([
                f"{value:.4f}" if isinstance(value, (float, np.floating)) else str(value)
                for value in row
            ])
        lines = [
            "| " + " | ".join(columns) + " |",
            "| " + " | ".join("---" for _ in columns) + " |",
        ]
        lines.extend("| " + " | ".join(row) + " |" for row in rendered)
        return "\n".join(lines)

    lines = [
        f"# PriceFM R103 {region} diagnostic package",
        "",
        "## Scope",
        "",
        "This package compares aligned validation forecasts from R103 recursive exAL Q-DESN, "
        "R98 direct exAL Q-DESN, and the operational PriceFM reproduction. The outer-test "
        "comparison contains R98 and PriceFM only because R103 remains validation-only.",
        "",
        "## Validation AQL",
        "",
        markdown_table(validation[["fold", "method_label", "AQL", "AQCR", "coverage_10_90"]]),
        "",
        "## Outer-test AQL",
        "",
        markdown_table(test[["fold", "method_label", "AQL", "AQCR", "coverage_10_90"]]),
        "",
        "## PDFs",
        "",
    ]
    lines.extend(f"- `{pdf.name}`" for pdf in pdfs)
    lines.extend([
        "",
        "## Interpretation guard",
        "",
        "R103 and R98 answer different forecasting questions: R103 recursively propagates "
        "endogenous prices, while R98 uses the prior direct-horizon construction. Their AQLs "
        "are diagnostically comparable on aligned observations, but the difference is not an "
        "apples-to-apples model upgrade. No R103 test prediction is generated here.",
        "",
    ])
    path.write_text("\n".join(lines))
    return path


def main() -> int:
    args = parser().parse_args()
    if args.batch_size < 1:
        raise ValueError("batch size must be positive")
    output_dir = args.output_dir.resolve()
    validation: dict[int, dict[str, dict[str, Any]]] = {}
    test: dict[int, dict[str, dict[str, Any]]] = {}
    sources: list[dict[str, Any]] = []
    for fold in (1, 2, 3):
        r103, records = load_r103_surface(args.data_root, args.region, fold)
        sources.extend(records)
        r98, records = load_r98_validation_surface(args.data_root, args.region, fold)
        sources.extend(records)
        pricefm, records = load_or_predict_operational_validation(
            args.data_root,
            args.upstream_root,
            output_dir,
            args.region,
            fold,
            args.batch_size,
        )
        sources.extend(records)
        validation[fold] = {"r103": r103, "r98": r98, "pricefm": pricefm}
        strict_anchor_alignment(validation[fold].values())
        r98_test, records = load_r98_test_surface(args.data_root, args.region, fold)
        sources.extend(records)
        pricefm_test, records = load_operational_test_surface(args.data_root, args.region, fold)
        sources.extend(records)
        test[fold] = {"r98": r98_test, "pricefm": pricefm_test}
        strict_anchor_alignment(test[fold].values())
    metrics, horizons = metric_tables(validation, test)
    atomic_csv(output_dir / "metrics.csv", metrics)
    atomic_csv(output_dir / "horizon_metrics.csv", horizons)
    source_frame = pd.DataFrame(sources).drop_duplicates(subset=["role", "path", "sha256"])
    atomic_csv(output_dir / "source_manifest.csv", source_frame)
    pdfs = write_pdfs(output_dir, args.region, validation, test, metrics)
    report = write_report(output_dir, args.region, metrics, pdfs)
    outputs = [output_dir / "metrics.csv", output_dir / "horizon_metrics.csv", output_dir / "source_manifest.csv", report, *pdfs]
    summary = {
        "status": "complete",
        "region": args.region,
        "validation_methods": list(METHOD_ORDER),
        "outer_test_methods": ["r98", "pricefm"],
        "r103_test_opened": False,
        "operational_pricefm_action": "inference_only_from_frozen_validation_selected_checkpoints",
        "fit_performed": False,
        "outputs": [source_record("output", path) for path in outputs],
        "source_manifest_sha256": sha256_file(output_dir / "source_manifest.csv"),
    }
    atomic_json(output_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
