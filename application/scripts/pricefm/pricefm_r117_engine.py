#!/usr/bin/env python3
"""Corrected pure all-layer recursive DESN helpers for PriceFM Stage R117.

R117 deliberately does not alter the frozen R97--R116 implementations.  The
transition predicting ``y_t`` combines the target price at ``t-1`` with
exogenous information at ``t``.  Neighboring regions contribute exogenous
variables only, so an outer forecast never reads an unobserved future price.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from statistics import NormalDist
from typing import Any, Iterable, Mapping, Sequence

import numpy as np

from pricefm_common import sha256_file, write_json
from pricefm_desn_adapter import make_reservoir_matrices, normalize_reservoir_config
from pricefm_graph import graph_adj_matrix
from pricefm_metrics import average_quantile_loss
from pricefm_recursive_normal import deterministic_seed, reservoir_step


HORIZONS = tuple(range(1, 97))
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
POLICIES = (
    "target_only",
    "graph_summary_mean",
    "graph_summary_mean_std",
    "graph_neighbor_exogenous",
)
CALENDARS = ("none", "compact3")
READOUTS = ("pure_all_layers", "extended_all_layers")


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def fingerprint(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def normalize_spec(spec: Mapping[str, Any]) -> dict[str, Any]:
    units_value = spec["units"]
    if isinstance(units_value, str):
        units_value = json.loads(units_value)
    units = [int(value) for value in units_value]
    depth = int(spec.get("depth", len(units)))
    if depth != len(units) or depth < 1:
        raise ValueError("depth must equal the number of layer widths")
    policy = str(spec["feature_policy"])
    calendar = str(spec.get("calendar", "none"))
    readout = str(spec.get("readout", "pure_all_layers"))
    if policy not in POLICIES:
        raise ValueError(f"unsupported R117 feature policy: {policy}")
    if calendar not in CALENDARS:
        raise ValueError(f"unsupported R117 calendar: {calendar}")
    if readout not in READOUTS:
        raise ValueError(f"unsupported R117 readout: {readout}")
    out = {
        "region": str(spec["region"]),
        "feature_policy": policy,
        "calendar": calendar,
        "readout": readout,
        "lag_window": int(spec["lag_window"]),
        "depth": depth,
        "units": units,
        "alpha": float(spec["alpha"]),
        "rho": float(spec["rho"]),
        "input_scale": float(spec["input_scale"]),
        "recurrent_sparsity": float(spec["recurrent_sparsity"]),
        "seed": int(spec["seed"]),
    }
    if out["lag_window"] < 2 or any(value < 1 for value in units):
        raise ValueError("lag_window and layer widths must be positive")
    if not 0 < out["alpha"] <= 1 or out["rho"] < 0:
        raise ValueError("invalid leaking rate or spectral radius")
    if out["input_scale"] <= 0 or not 0 < out["recurrent_sparsity"] <= 1:
        raise ValueError("invalid input scale or recurrent sparsity")
    return out


def active_regions(spec: Mapping[str, Any]) -> list[str]:
    normalized = normalize_spec(spec)
    target = normalized["region"]
    if normalized["feature_policy"] == "target_only":
        return [target]
    adjacency = graph_adj_matrix()
    neighbors = sorted(str(region) for region in adjacency[target] if str(region) != target)
    if not neighbors:
        raise ValueError(f"graph policy requested for isolated region {target}")
    return [target] + neighbors


def window_path(processed: Path, fold: int, region: str, split: str, lag: int) -> Path:
    boundary = "contained_half_open" if split == "train" else "operational_half_open"
    return (
        Path(processed)
        / "windows"
        / f"fold_{int(fold)}"
        / f"region={region}"
        / f"{split}_L{int(lag)}_H96_{boundary}.npz"
    )


def load_window(processed: Path, fold: int, region: str, split: str, lag: int) -> dict[str, Any]:
    path = window_path(processed, fold, region, split, lag)
    manifest_path = path.with_suffix(".manifest.json")
    if not path.is_file() or not manifest_path.is_file():
        raise FileNotFoundError(path)
    with np.load(path, allow_pickle=True) as packet:
        result = {
            "X_lag": np.asarray(packet["X_lag"], dtype=float),
            "X_lead": np.asarray(packet["X_lead"], dtype=float),
            "Y": np.asarray(packet["Y"], dtype=float),
            "anchors": np.asarray(packet["anchors"], dtype=str),
            "lag_cols": [str(value) for value in packet["lag_cols"]],
            "lead_cols": [str(value) for value in packet["lead_cols"]],
        }
    result.update({
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "manifest_path": str(manifest_path.resolve()),
        "manifest_sha256": sha256_file(manifest_path),
    })
    return result


def load_windows(processed: Path, fold: int, split: str, spec: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    normalized = normalize_spec(spec)
    windows = {
        region: load_window(processed, fold, region, split, normalized["lag_window"])
        for region in active_regions(normalized)
    }
    target = windows[normalized["region"]]
    for region, window in windows.items():
        if not np.array_equal(target["anchors"], window["anchors"]):
            raise ValueError(f"unaligned R117 anchors for {region}")
        if window["X_lag"].shape[:2] != target["X_lag"].shape[:2]:
            raise ValueError(f"unaligned R117 history for {region}")
        if window["X_lead"].shape[:2] != target["X_lead"].shape[:2]:
            raise ValueError(f"unaligned R117 future exogenous block for {region}")
    return windows


def compact_calendar(offsets: Sequence[int], n_origins: int) -> np.ndarray:
    quarter = np.mod(np.asarray(offsets, dtype=float), 96.0)
    phase = 2.0 * np.pi * quarter / 96.0
    block = np.column_stack((quarter / 95.0, np.sin(phase), np.cos(phase)))
    return np.repeat(block[None, :, :], int(n_origins), axis=0)


def _exogenous_history(window: Mapping[str, Any]) -> np.ndarray:
    lag = np.asarray(window["X_lag"], dtype=float)
    return lag[:, 1:, 1:]


def _exogenous_future(window: Mapping[str, Any]) -> np.ndarray:
    return np.asarray(window["X_lead"], dtype=float)


def _neighbor_parts(
    windows: Mapping[str, Mapping[str, Any]],
    target: str,
    history: bool,
) -> tuple[list[np.ndarray], list[str]]:
    extractor = _exogenous_history if history else _exogenous_future
    values = [extractor(windows[region]) for region in windows if region != target]
    names = [str(name).split("-", 1)[-1] for name in windows[target]["lead_cols"]]
    if not values:
        return [], names
    if any(value.shape != values[0].shape for value in values):
        raise ValueError("neighbor exogenous arrays must be aligned")
    return values, names


@dataclass(frozen=True)
class CorrectedArrays:
    history: np.ndarray
    future_teacher: np.ndarray
    response: np.ndarray
    anchors: np.ndarray
    input_names: tuple[str, ...]
    source_manifest: tuple[dict[str, str], ...]


def corrected_arrays(windows: Mapping[str, Mapping[str, Any]], spec: Mapping[str, Any]) -> CorrectedArrays:
    normalized = normalize_spec(spec)
    target = normalized["region"]
    if target not in windows or set(windows) != set(active_regions(normalized)):
        raise ValueError("R117 windows do not match the declared graph scope")
    target_window = windows[target]
    lag = np.asarray(target_window["X_lag"], dtype=float)
    lead = np.asarray(target_window["X_lead"], dtype=float)
    response = np.asarray(target_window["Y"], dtype=float)
    if lag.shape[1] != normalized["lag_window"] or response.shape[1] != len(HORIZONS):
        raise ValueError("R117 window geometry changed")
    if lag.shape[-1] != 4 or lead.shape[-1] != 3:
        raise ValueError("R117 expects price plus load/solar/wind")

    target_history = np.concatenate((lag[:, :-1, 0:1], lag[:, 1:, 1:]), axis=2)
    previous_truth = np.concatenate((lag[:, -1:, 0], response[:, :-1]), axis=1)
    target_future = np.concatenate((previous_truth[:, :, None], lead), axis=2)
    names = [f"{target}::price_lag1"] + [
        f"{target}::{str(name).split('-', 1)[-1]}_current" for name in target_window["lead_cols"]
    ]

    policy = normalized["feature_policy"]
    neighbor_history, neighbor_names = _neighbor_parts(windows, target, history=True)
    neighbor_future, _ = _neighbor_parts(windows, target, history=False)
    history_parts = [target_history]
    future_parts = [target_future]
    if policy == "graph_summary_mean":
        history_parts.append(np.mean(np.stack(neighbor_history), axis=0))
        future_parts.append(np.mean(np.stack(neighbor_future), axis=0))
        names.extend(f"neighbors::mean::{name}_current" for name in neighbor_names)
    elif policy == "graph_summary_mean_std":
        history_stack = np.stack(neighbor_history)
        future_stack = np.stack(neighbor_future)
        history_parts.extend((np.mean(history_stack, axis=0), np.std(history_stack, axis=0)))
        future_parts.extend((np.mean(future_stack, axis=0), np.std(future_stack, axis=0)))
        names.extend(f"neighbors::mean::{name}_current" for name in neighbor_names)
        names.extend(f"neighbors::sd::{name}_current" for name in neighbor_names)
    elif policy == "graph_neighbor_exogenous":
        for region in windows:
            if region == target:
                continue
            history_parts.append(_exogenous_history(windows[region]))
            future_parts.append(_exogenous_future(windows[region]))
            names.extend(f"{region}::{name}_current" for name in neighbor_names)
    elif policy != "target_only":
        raise ValueError(f"unhandled R117 policy: {policy}")

    history = np.concatenate(history_parts, axis=2)
    future = np.concatenate(future_parts, axis=2)
    if normalized["calendar"] == "compact3":
        history_offsets = np.arange(-normalized["lag_window"] + 1, 0)
        future_offsets = np.arange(0, len(HORIZONS))
        history = np.concatenate((history, compact_calendar(history_offsets, len(response))), axis=2)
        future = np.concatenate((future, compact_calendar(future_offsets, len(response))), axis=2)
        names.extend(("calendar::quarter_scaled", "calendar::sin_day", "calendar::cos_day"))

    if history.shape[1] != normalized["lag_window"] - 1 or future.shape[:2] != response.shape:
        raise ValueError("corrected R117 transition arrays are misaligned")
    if history.shape[-1] != len(names) or future.shape[-1] != len(names):
        raise ValueError("R117 transition names and dimensions disagree")
    if not np.isfinite(history).all() or not np.isfinite(future).all() or not np.isfinite(response).all():
        raise ValueError("R117 arrays must be finite")
    sources = tuple({
        "region": region,
        "window_path": str(window["path"]),
        "window_sha256": str(window["sha256"]),
        "manifest_path": str(window["manifest_path"]),
        "manifest_sha256": str(window["manifest_sha256"]),
    } for region, window in windows.items())
    return CorrectedArrays(history, future, response, target_window["anchors"], tuple(names), sources)


def make_reservoir(spec: Mapping[str, Any], input_dimension: int) -> tuple[dict[str, Any], dict[str, Any]]:
    normalized = normalize_spec(spec)
    config = normalize_reservoir_config({
        "depth": normalized["depth"],
        "units": normalized["units"],
        "alpha": normalized["alpha"],
        "rho": normalized["rho"],
        "input_scale": normalized["input_scale"],
        "recurrent_sparsity": normalized["recurrent_sparsity"],
        "bias_scale": 0.0,
        "reservoir_activation": "tanh",
        "state_output": "concat_layers",
    }, normalized["units"][-1])
    return make_reservoir_matrices(int(input_dimension), config, normalized["seed"]), config


def initialize_states(
    arrays: CorrectedArrays,
    reservoir: Mapping[str, Any],
    config: Mapping[str, Any],
    indices: np.ndarray,
) -> list[np.ndarray]:
    indices = np.asarray(indices, dtype=int)
    states = [np.zeros((len(indices), int(width)), dtype=float) for width in config["units"]]
    for position in range(arrays.history.shape[1]):
        states = reservoir_step(states, arrays.history[indices, position], reservoir, config)
    return states


def readout_rows(states: Sequence[np.ndarray], transition: np.ndarray, mode: str) -> np.ndarray:
    mode = str(mode)
    if mode not in READOUTS:
        raise ValueError(f"unsupported R117 readout: {mode}")
    layers = [np.asarray(value, dtype=float) for value in states]
    if not layers or any(value.ndim != 2 or value.shape[0] != layers[0].shape[0] for value in layers):
        raise ValueError("R117 layers must be aligned matrices")
    parts = [np.ones((layers[0].shape[0], 1), dtype=float)]
    if mode == "extended_all_layers":
        parts.append(np.asarray(transition, dtype=float))
    parts.extend(layers)
    result = np.column_stack(parts)
    if not np.isfinite(result).all():
        raise ValueError("R117 readout contains non-finite values")
    return result


def feature_names(spec: Mapping[str, Any], input_names: Sequence[str]) -> list[str]:
    normalized = normalize_spec(spec)
    names = ["intercept"]
    if normalized["readout"] == "extended_all_layers":
        names.extend(f"input::{name}" for name in input_names)
    for layer, width in enumerate(normalized["units"], start=1):
        names.extend(f"layer{layer}::state_{index:04d}" for index in range(1, width + 1))
    return names


def internal_splits(n_origins: int) -> list[dict[str, Any]]:
    n = int(n_origins)
    if n < 60:
        raise ValueError("R117 requires at least 60 Fold-1 training origins")
    boundaries = ((0.55, 0.68), (0.68, 0.82), (0.82, 1.00))
    result = []
    for split_id, (train_stop_fraction, val_stop_fraction) in enumerate(boundaries, start=1):
        train_stop = int(np.floor(n * train_stop_fraction))
        val_stop = n if val_stop_fraction == 1 else int(np.floor(n * val_stop_fraction))
        train = np.arange(0, train_stop, dtype=int)
        validation = np.arange(train_stop, val_stop, dtype=int)
        if not len(train) or not len(validation) or train[-1] >= validation[0]:
            raise ValueError("invalid R117 temporal split")
        result.append({"split": split_id, "train": train, "validation": validation})
    return result


def _empty_stats(p: int) -> dict[str, Any]:
    return {"n": 0, "p": int(p), "XtX": np.zeros((p, p)), "Xty": np.zeros(p), "yty": 0.0}


def teacher_forced_statistics(
    arrays: CorrectedArrays,
    spec: Mapping[str, Any],
    origin_groups: Mapping[str, np.ndarray],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any], dict[str, Any]]:
    normalized = normalize_spec(spec)
    reservoir, config = make_reservoir(normalized, arrays.history.shape[-1])
    all_indices = np.arange(len(arrays.response), dtype=int)
    states = initialize_states(arrays, reservoir, config, all_indices)
    p = len(feature_names(normalized, arrays.input_names))
    stats = {name: _empty_stats(p) for name in origin_groups}
    for horizon_index in range(len(HORIZONS)):
        transition = arrays.future_teacher[:, horizon_index]
        states = reservoir_step(states, transition, reservoir, config)
        design = readout_rows(states, transition, normalized["readout"])
        response = arrays.response[:, horizon_index]
        if design.shape[1] != p:
            raise ValueError("R117 readout dimension changed")
        for name, indices in origin_groups.items():
            block = design[np.asarray(indices, dtype=int)]
            y = response[np.asarray(indices, dtype=int)]
            target = stats[name]
            target["n"] += len(y)
            target["XtX"] += block.T @ block
            target["Xty"] += block.T @ y
            target["yty"] += float(y @ y)
    return stats, reservoir, config


def teacher_forced_design(arrays: CorrectedArrays, spec: Mapping[str, Any]) -> tuple[np.ndarray, np.ndarray, dict[str, Any], dict[str, Any]]:
    normalized = normalize_spec(spec)
    reservoir, config = make_reservoir(normalized, arrays.history.shape[-1])
    indices = np.arange(len(arrays.response), dtype=int)
    states = initialize_states(arrays, reservoir, config, indices)
    p = len(feature_names(normalized, arrays.input_names))
    design = np.empty((len(indices) * len(HORIZONS), p), dtype=float)
    response = np.empty(len(indices) * len(HORIZONS), dtype=float)
    for horizon_index in range(len(HORIZONS)):
        transition = arrays.future_teacher[:, horizon_index]
        states = reservoir_step(states, transition, reservoir, config)
        rows = readout_rows(states, transition, normalized["readout"])
        start = horizon_index * len(indices)
        stop = start + len(indices)
        design[start:stop] = rows
        response[start:stop] = arrays.response[:, horizon_index]
    return design, response, reservoir, config


def fit_scaled_ridge(stats: Mapping[str, Any], ridge_variance: float = 1e4) -> dict[str, Any]:
    p = int(stats["p"])
    precision0 = np.full(p, 1.0 / float(ridge_variance), dtype=float)
    precision0[0] = 1e-6
    precision = np.asarray(stats["XtX"], dtype=float) + np.diag(precision0)
    precision = 0.5 * (precision + precision.T)
    try:
        chol = np.linalg.cholesky(precision)
    except np.linalg.LinAlgError:
        jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.mean(np.diag(precision))))
        precision = precision + np.eye(p) * jitter
        chol = np.linalg.cholesky(precision)
    mean = np.linalg.solve(chol.T, np.linalg.solve(chol, np.asarray(stats["Xty"], dtype=float)))
    inverse = np.linalg.solve(chol.T, np.linalg.solve(chol, np.eye(p)))
    shape = 2.0 + float(stats["n"]) / 2.0
    rate = 1.0 + 0.5 * (float(stats["yty"]) - float(mean @ precision @ mean))
    rate = max(rate, np.finfo(float).eps)
    return {
        "beta_mean": mean,
        "beta_cov": (rate / max(shape - 1.0, 1.0)) * inverse,
        "precision_inverse": inverse,
        "omega_shape": shape,
        "omega_rate": rate,
        "omega_mean": rate / max(shape - 1.0, 1.0),
        "prior_type": "scaled_ridge",
    }


def _normal_quantiles(mean: np.ndarray, variance: np.ndarray) -> np.ndarray:
    z = np.asarray([NormalDist().inv_cdf(value) for value in QUANTILES])
    return mean[:, None] + np.sqrt(np.maximum(variance, np.finfo(float).eps))[:, None] * z[None, :]


def recursive_normal_score(
    arrays: CorrectedArrays,
    spec: Mapping[str, Any],
    fit: Mapping[str, Any],
    validation_indices: Sequence[int],
    maximum_origins: int | None = None,
) -> dict[str, Any]:
    normalized = normalize_spec(spec)
    indices = np.asarray(validation_indices, dtype=int)
    if maximum_origins is not None and len(indices) > int(maximum_origins):
        positions = np.linspace(0, len(indices) - 1, int(maximum_origins)).round().astype(int)
        indices = indices[np.unique(positions)]
    reservoir, config = make_reservoir(normalized, arrays.history.shape[-1])
    states = initialize_states(arrays, reservoir, config, indices)
    beta = np.asarray(fit["beta_mean"], dtype=float)
    covariance = np.asarray(fit["beta_cov"], dtype=float)
    omega = float(fit["omega_mean"])
    predictions = np.empty((len(indices), len(HORIZONS), len(QUANTILES)), dtype=float)
    previous = None
    for horizon_index in range(len(HORIZONS)):
        transition = np.array(arrays.future_teacher[indices, horizon_index], copy=True)
        if horizon_index > 0:
            transition[:, 0] = previous
        states = reservoir_step(states, transition, reservoir, config)
        design = readout_rows(states, transition, normalized["readout"])
        location = design @ beta
        variance = omega + np.einsum("ij,jk,ik->i", design, covariance, design, optimize=True)
        predictions[:, horizon_index] = _normal_quantiles(location, variance)
        previous = location
    truth = arrays.response[indices]
    block_rows = []
    for start in (1, 25, 49, 73):
        stop = start + 23
        block_rows.append({
            "horizon_start": start,
            "horizon_stop": stop,
            "AQL": average_quantile_loss(truth[:, start - 1:stop], predictions[:, start - 1:stop], QUANTILES),
        })
    return {
        "AQL": average_quantile_loss(truth, predictions, QUANTILES),
        "late_AQL": average_quantile_loss(truth[:, 72:], predictions[:, 72:], QUANTILES),
        "median_MAE": float(np.mean(np.abs(truth - predictions[:, :, 3]))),
        "interval_80_coverage": float(np.mean((truth >= predictions[:, :, 0]) & (truth <= predictions[:, :, -1]))),
        "interval_80_width": float(np.mean(predictions[:, :, -1] - predictions[:, :, 0])),
        "origins_scored": int(len(indices)),
        "horizon_blocks": block_rows,
    }


def write_stats_packet(path: Path, stats: Mapping[str, Any], metadata: Mapping[str, Any]) -> None:
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    np.asarray(stats["XtX"], dtype="<f8").tofile(path / "XtX.bin")
    np.asarray(stats["Xty"], dtype="<f8").tofile(path / "Xty.bin")
    meta = {
        "n": int(stats["n"]), "p": int(stats["p"]), "yty": float(stats["yty"]),
        "test_opened": False, **dict(metadata),
    }
    write_json(path / "statistics.json", meta)
    files = {}
    for name in ("XtX.bin", "Xty.bin", "statistics.json"):
        files[name] = {"bytes": (path / name).stat().st_size, "sha256": sha256_file(path / name)}
    write_json(path / "terminal.json", {
        "status": "completed_causal_sufficient_statistics",
        "stage": "R117", "files": files, "test_opened": False,
    })


def load_normal_fit(path: Path) -> dict[str, Any]:
    path = Path(path)
    terminal = json.loads((path / "terminal.json").read_text())
    p = int(terminal["p"])
    beta = np.fromfile(path / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(path / "beta_cov.bin", dtype="<f8").reshape(p, p)
    if beta.size != p or not np.isfinite(beta).all() or not np.isfinite(covariance).all():
        raise ValueError("invalid R117 Normal posterior packet")
    return {
        "beta_mean": beta,
        "beta_cov": covariance,
        "omega_shape": float(terminal["omega_shape"]),
        "omega_rate": float(terminal["omega_rate"]),
        "omega_mean": float(terminal["omega_rate"]) / max(float(terminal["omega_shape"]) - 1.0, 1.0),
        "prior_type": str(terminal["prior_type"]),
    }


def draw_normal_fit(fit: Mapping[str, Any], paths: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    covariance = np.asarray(fit["beta_cov"], dtype=float)
    jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.mean(np.diag(covariance))))
    chol = np.linalg.cholesky(0.5 * (covariance + covariance.T) + np.eye(len(covariance)) * jitter)
    beta_rng = np.random.default_rng(deterministic_seed(seed, "normal_beta"))
    sigma_rng = np.random.default_rng(deterministic_seed(seed, "normal_sigma"))
    beta = np.asarray(fit["beta_mean"])[None, :] + beta_rng.standard_normal((int(paths), len(covariance))) @ chol.T
    omega = 1.0 / sigma_rng.gamma(
        shape=float(fit["omega_shape"]),
        scale=1.0 / float(fit["omega_rate"]),
        size=int(paths),
    )
    return beta, omega


def load_quantile_fit(path: Path) -> dict[str, Any]:
    path = Path(path)
    terminal = json.loads((path / "terminal.json").read_text())
    p = int(terminal["p"])
    beta = np.fromfile(path / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(path / "beta_cov.bin", dtype="<f8").reshape(p, p)
    if beta.size != p or not np.isfinite(beta).all() or not np.isfinite(covariance).all():
        raise ValueError("invalid R117 quantile posterior packet")
    return {"beta_mean": beta, "beta_cov": covariance, "terminal": terminal}


def draw_quantile_beta(fit: Mapping[str, Any], paths: int, seed: int) -> np.ndarray:
    covariance = np.asarray(fit["beta_cov"], dtype=float)
    jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.mean(np.diag(covariance))))
    chol = np.linalg.cholesky(0.5 * (covariance + covariance.T) + np.eye(len(covariance)) * jitter)
    rng = np.random.default_rng(deterministic_seed(seed, "quantile_beta"))
    return np.asarray(fit["beta_mean"])[None, :] + rng.standard_normal((int(paths), len(covariance))) @ chol.T


def recursive_quantile_forecast(
    arrays: CorrectedArrays,
    spec: Mapping[str, Any],
    normal_fit: Mapping[str, Any],
    quantile_fits: Mapping[float, Mapping[str, Any]],
    paths: int = 500,
    seed: int = 2026092501,
) -> dict[str, np.ndarray]:
    normalized = normalize_spec(spec)
    if sorted(float(value) for value in quantile_fits) != list(QUANTILES):
        raise ValueError("R117 requires all seven quantile fits")
    reservoir, config = make_reservoir(normalized, arrays.history.shape[-1])
    normal_beta, omega = draw_normal_fit(normal_fit, paths, seed)
    quantile_beta = {
        float(tau): draw_quantile_beta(fit, paths, deterministic_seed(seed, "tau", tau))
        for tau, fit in quantile_fits.items()
    }
    n_origins = len(arrays.response)
    path_specific = np.empty((n_origins, len(HORIZONS), len(QUANTILES)), dtype=float)
    mean_feature = np.empty_like(path_specific)
    normal_predictions = np.empty_like(path_specific)
    normal_z = np.asarray([NormalDist().inv_cdf(value) for value in QUANTILES])
    for origin in range(n_origins):
        states = initialize_states(arrays, reservoir, config, np.asarray([origin]))
        states = [np.repeat(layer, int(paths), axis=0) for layer in states]
        previous = None
        for horizon_index in range(len(HORIZONS)):
            transition = np.repeat(
                arrays.future_teacher[origin : origin + 1, horizon_index], int(paths), axis=0
            )
            if horizon_index > 0:
                transition[:, 0] = previous
            states = reservoir_step(states, transition, reservoir, config)
            design = readout_rows(states, transition, normalized["readout"])
            location = np.einsum("sp,sp->s", design, normal_beta, optimize=True)
            innovation = np.random.default_rng(
                deterministic_seed(seed, "innovation", origin, horizon_index)
            ).standard_normal(int(paths))
            response = location + np.sqrt(omega) * innovation
            previous = response
            normal_predictions[origin, horizon_index] = np.quantile(response, QUANTILES)
            averaged = np.mean(design, axis=0)
            for position, tau in enumerate(QUANTILES):
                beta = quantile_beta[float(tau)]
                path_specific[origin, horizon_index, position] = float(
                    np.mean(np.einsum("sp,sp->s", design, beta, optimize=True))
                )
                mean_feature[origin, horizon_index, position] = float(np.mean(beta @ averaged))
    return {
        "path_specific": path_specific,
        "mean_feature": mean_feature,
        "normal_driver": normal_predictions,
        "truth": np.asarray(arrays.response, dtype=float),
    }


def prediction_metrics(truth: np.ndarray, prediction: np.ndarray) -> dict[str, Any]:
    truth = np.asarray(truth, dtype=float)
    prediction = np.asarray(prediction, dtype=float)
    return {
        "AQL": average_quantile_loss(truth, prediction, QUANTILES),
        "late_AQL": average_quantile_loss(truth[:, 72:], prediction[:, 72:], QUANTILES),
        "median_MAE": float(np.mean(np.abs(truth - prediction[:, :, 3]))),
        "interval_80_coverage": float(np.mean((truth >= prediction[:, :, 0]) & (truth <= prediction[:, :, -1]))),
        "interval_80_width": float(np.mean(prediction[:, :, -1] - prediction[:, :, 0])),
        "crossing_rate": float(np.mean(prediction[:, :, :-1] > prediction[:, :, 1:])),
    }
