#!/usr/bin/env python3
"""Explicit-lag, all-layer DESN helpers for PriceFM Stage R120.

R120 is intentionally separate from R117/R119.  It distinguishes target and
exogenous lag orders and uses a fixed 240-transition reservoir warm-up backed
by a 970-row source window (730 maximum lag plus 240 warm-up rows).
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from statistics import NormalDist
from typing import Any, Mapping, Sequence

import numpy as np
from scipy import sparse
from scipy.sparse import linalg as sparse_linalg

from pricefm_common import sha256_file, write_json
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
READOUTS = ("pure_all_layers", "extended_all_layers")
CALENDARS = ("none", "compact3")
MAX_EXPLICIT_LAG = 730
WARMUP_STEPS = 240
SOURCE_WINDOW = MAX_EXPLICIT_LAG + WARMUP_STEPS
_RESERVOIR_CACHE: dict[tuple[str, int], tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = {}


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
    out = {
        "region": str(spec.get("region", "BG")),
        "feature_policy": str(spec["feature_policy"]),
        "calendar": str(spec.get("calendar", "compact3")),
        "readout": str(spec.get("readout", "pure_all_layers")),
        "m_y": int(spec["m_y"]),
        "m_x": int(spec["m_x"]),
        "source_window": int(spec.get("source_window", SOURCE_WINDOW)),
        "warmup_steps": int(spec.get("warmup_steps", WARMUP_STEPS)),
        "depth": depth,
        "units": units,
        "alpha": float(spec["alpha"]),
        "rho": float(spec["rho"]),
        "input_scale": float(spec["input_scale"]),
        "input_fan_in": int(spec["input_fan_in"]),
        "recurrent_sparsity": float(spec["recurrent_sparsity"]),
        "seed": int(spec["seed"]),
    }
    if depth != len(units) or depth < 1 or any(value < 1 for value in units):
        raise ValueError("depth must equal the positive layer-width count")
    if out["feature_policy"] not in POLICIES:
        raise ValueError("unsupported R120 feature policy")
    if out["calendar"] not in CALENDARS or out["readout"] not in READOUTS:
        raise ValueError("unsupported R120 calendar or readout")
    if out["m_y"] < 1 or out["m_y"] > MAX_EXPLICIT_LAG:
        raise ValueError("m_y must be in [1, 730]")
    if out["m_x"] < 0 or out["m_x"] > MAX_EXPLICIT_LAG:
        raise ValueError("m_x must be in [0, 730]")
    if out["source_window"] != SOURCE_WINDOW or out["warmup_steps"] != WARMUP_STEPS:
        raise ValueError("R120 freezes source_window=970 and warmup_steps=240")
    if not 0 < out["alpha"] <= 1 or out["rho"] < 0 or out["input_scale"] <= 0:
        raise ValueError("invalid reservoir dynamics")
    if out["input_fan_in"] < 1 or not 0 < out["recurrent_sparsity"] <= 1:
        raise ValueError("invalid reservoir connectivity")
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


def window_path(processed: Path, fold: int, region: str, split: str) -> Path:
    boundary = "contained_half_open" if split == "train" else "operational_half_open"
    return (
        Path(processed) / "windows" / f"fold_{int(fold)}" / f"region={region}"
        / f"{split}_L{SOURCE_WINDOW}_H96_{boundary}.npz"
    )


def load_window(processed: Path, fold: int, region: str, split: str) -> dict[str, Any]:
    path = window_path(processed, fold, region, split)
    manifest = path.with_suffix(".manifest.json")
    if not path.is_file() or not manifest.is_file():
        raise FileNotFoundError(path)
    with np.load(path, allow_pickle=True) as packet:
        result = {
            "X_lag": np.asarray(packet["X_lag"], dtype=float),
            "X_lead": np.asarray(packet["X_lead"], dtype=float),
            "Y": np.asarray(packet["Y"], dtype=float),
            "anchors": np.asarray(packet["anchors"], dtype=str),
            "lag_cols": [str(value) for value in packet["lag_cols"]],
            "lead_cols": [str(value) for value in packet["lead_cols"]],
            "path": str(path.resolve()),
            "sha256": sha256_file(path),
            "manifest_path": str(manifest.resolve()),
            "manifest_sha256": sha256_file(manifest),
        }
    return result


def load_windows(
    processed: Path, fold: int, split: str, spec: Mapping[str, Any]
) -> dict[str, dict[str, Any]]:
    normalized = normalize_spec(spec)
    windows = {
        region: load_window(processed, fold, region, split)
        for region in active_regions(normalized)
    }
    target = windows[normalized["region"]]
    for region, window in windows.items():
        if not np.array_equal(target["anchors"], window["anchors"]):
            raise ValueError(f"unaligned R120 anchors for {region}")
        if window["X_lag"].shape[:2] != target["X_lag"].shape[:2]:
            raise ValueError(f"unaligned R120 history for {region}")
        if window["X_lead"].shape[:2] != target["X_lead"].shape[:2]:
            raise ValueError(f"unaligned R120 future exogenous block for {region}")
    return windows


@dataclass(frozen=True)
class ExplicitArrays:
    price_history: np.ndarray
    exog_history: np.ndarray
    exog_future: np.ndarray
    response: np.ndarray
    anchors: np.ndarray
    exog_names: tuple[str, ...]
    source_manifest: tuple[dict[str, str], ...]


def standardize_from_training_origins(
    arrays: ExplicitArrays, training_indices: Sequence[int]
) -> tuple[ExplicitArrays, dict[str, Any]]:
    """Fit deterministic preprocessing on one internal training block only."""
    idx = np.asarray(training_indices, dtype=int)
    if not len(idx):
        raise ValueError("R120 standardization requires training origins")
    price_values = np.concatenate((arrays.price_history[idx].reshape(-1), arrays.response[idx].reshape(-1)))
    price_mean = float(np.mean(price_values)); price_scale = float(np.std(price_values))
    if not np.isfinite(price_scale) or price_scale <= np.finfo(float).eps: price_scale = 1.0
    exog_values = np.concatenate(
        (arrays.exog_history[idx].reshape(-1, arrays.exog_history.shape[-1]),
         arrays.exog_future[idx].reshape(-1, arrays.exog_future.shape[-1])), axis=0,
    )
    exog_mean = np.mean(exog_values, axis=0); exog_scale = np.std(exog_values, axis=0)
    exog_scale = np.where(np.isfinite(exog_scale) & (exog_scale > np.finfo(float).eps), exog_scale, 1.0)
    transformed = ExplicitArrays(
        (arrays.price_history - price_mean) / price_scale,
        (arrays.exog_history - exog_mean[None, None, :]) / exog_scale[None, None, :],
        (arrays.exog_future - exog_mean[None, None, :]) / exog_scale[None, None, :],
        (arrays.response - price_mean) / price_scale,
        arrays.anchors, arrays.exog_names, arrays.source_manifest,
    )
    return transformed, {
        "price_mean": price_mean, "price_scale": price_scale,
        "exog_mean": exog_mean.tolist(), "exog_scale": exog_scale.tolist(),
        "training_origin_count": int(len(idx)),
    }


def explicit_arrays(
    windows: Mapping[str, Mapping[str, Any]], spec: Mapping[str, Any]
) -> ExplicitArrays:
    normalized = normalize_spec(spec)
    target = normalized["region"]
    if set(windows) != set(active_regions(normalized)):
        raise ValueError("R120 windows do not match the declared graph scope")
    target_window = windows[target]
    lag = np.asarray(target_window["X_lag"], dtype=float)
    lead = np.asarray(target_window["X_lead"], dtype=float)
    response = np.asarray(target_window["Y"], dtype=float)
    if lag.shape[1:] != (SOURCE_WINDOW, 4) or lead.shape[1:] != (96, 3):
        raise ValueError("R120 requires 970 rows of price/load/solar/wind history")
    base_names = [str(name).split("-", 1)[-1] for name in target_window["lead_cols"]]
    history_parts = [lag[:, :, 1:]]
    future_parts = [lead]
    names = [f"{target}::{name}" for name in base_names]
    neighbors = [region for region in windows if region != target]
    policy = normalized["feature_policy"]
    if policy in ("graph_summary_mean", "graph_summary_mean_std"):
        hist = np.stack([np.asarray(windows[r]["X_lag"], dtype=float)[:, :, 1:] for r in neighbors])
        fut = np.stack([np.asarray(windows[r]["X_lead"], dtype=float) for r in neighbors])
        history_parts.append(np.mean(hist, axis=0))
        future_parts.append(np.mean(fut, axis=0))
        names.extend(f"neighbors::mean::{name}" for name in base_names)
        if policy == "graph_summary_mean_std":
            history_parts.append(np.std(hist, axis=0))
            future_parts.append(np.std(fut, axis=0))
            names.extend(f"neighbors::sd::{name}" for name in base_names)
    elif policy == "graph_neighbor_exogenous":
        for region in neighbors:
            history_parts.append(np.asarray(windows[region]["X_lag"], dtype=float)[:, :, 1:])
            future_parts.append(np.asarray(windows[region]["X_lead"], dtype=float))
            names.extend(f"{region}::{name}" for name in base_names)
    elif policy != "target_only":
        raise ValueError("unhandled R120 policy")
    exog_history = np.concatenate(history_parts, axis=2)
    exog_future = np.concatenate(future_parts, axis=2)
    if exog_history.shape[-1] != len(names) or exog_future.shape[-1] != len(names):
        raise ValueError("R120 exogenous names and arrays disagree")
    arrays = (lag[:, :, 0], exog_history, exog_future, response)
    if any(not np.isfinite(value).all() for value in arrays):
        raise ValueError("R120 arrays must be finite")
    sources = tuple({
        "region": region,
        "window_path": str(window["path"]),
        "window_sha256": str(window["sha256"]),
        "manifest_path": str(window["manifest_path"]),
        "manifest_sha256": str(window["manifest_sha256"]),
    } for region, window in windows.items())
    return ExplicitArrays(
        lag[:, :, 0], exog_history, exog_future, response,
        np.asarray(target_window["anchors"], dtype=str), tuple(names), sources,
    )


def compact_calendar(offset: int, n: int) -> np.ndarray:
    quarter = float(offset % 96)
    phase = 2.0 * np.pi * quarter / 96.0
    row = np.asarray((quarter / 95.0, np.sin(phase), np.cos(phase)), dtype=float)
    return np.repeat(row[None, :], int(n), axis=0)


def input_names(spec: Mapping[str, Any], exog_names: Sequence[str]) -> list[str]:
    normalized = normalize_spec(spec)
    names = [f"target::price_lag_{lag}" for lag in range(1, normalized["m_y"] + 1)]
    for lag in range(0, normalized["m_x"] + 1):
        suffix = "current" if lag == 0 else f"lag_{lag}"
        names.extend(f"{name}::{suffix}" for name in exog_names)
    if normalized["calendar"] == "compact3":
        names.extend(("calendar::quarter_scaled", "calendar::sin_day", "calendar::cos_day"))
    return names


def explicit_input(
    arrays: ExplicitArrays,
    spec: Mapping[str, Any],
    indices: Sequence[int],
    relative_time: int,
    generated: np.ndarray | None = None,
) -> np.ndarray:
    """Build u_t at a relative time; zero is the first forecast horizon.

    Negative times are warm-up transitions.  At nonnegative times, generated
    target values replace only target lags already inside the active forecast.
    If ``generated`` is absent, observed training responses provide those lags.
    """
    normalized = normalize_spec(spec)
    idx = np.asarray(indices, dtype=int)
    absolute = SOURCE_WINDOW + int(relative_time)
    price_positions = absolute - np.arange(1, normalized["m_y"] + 1)
    price = np.empty((len(idx), len(price_positions)), dtype=float)
    historical = price_positions < SOURCE_WINDOW
    if historical.any():
        price[:, historical] = arrays.price_history[idx[:, None], price_positions[historical][None, :]]
    if (~historical).any():
        horizons = price_positions[~historical] - SOURCE_WINDOW
        source = arrays.response[idx] if generated is None else np.asarray(generated, dtype=float)
        if horizons.min(initial=0) < 0 or horizons.max(initial=-1) >= source.shape[1]:
            raise ValueError("R120 target lag is unavailable at this forecast horizon")
        price[:, ~historical] = source[:, horizons]
    exog_positions = absolute - np.arange(0, normalized["m_x"] + 1)
    exog = np.empty((len(idx), len(exog_positions), arrays.exog_history.shape[-1]), dtype=float)
    historical = exog_positions < SOURCE_WINDOW
    if historical.any():
        exog[:, historical, :] = arrays.exog_history[idx[:, None], exog_positions[historical][None, :], :]
    if (~historical).any():
        horizons = exog_positions[~historical] - SOURCE_WINDOW
        if horizons.min(initial=0) < 0 or horizons.max(initial=-1) >= arrays.exog_future.shape[1]:
            raise ValueError("R120 exogenous lag is unavailable")
        exog[:, ~historical, :] = arrays.exog_future[idx[:, None], horizons[None, :], :]
    parts = [price, exog.reshape(len(idx), -1)]
    if normalized["calendar"] == "compact3":
        parts.append(compact_calendar(relative_time, len(idx)))
    result = np.column_stack(parts)
    if result.shape[1] != len(input_names(normalized, arrays.exog_names)):
        raise ValueError("R120 explicit input dimension changed")
    if not np.isfinite(result).all():
        raise ValueError("R120 explicit input contains non-finite values")
    return result


def _scaled_recurrent_matrix(
    rng: np.random.Generator, units: int, density: float, rho: float
) -> tuple[sparse.csr_matrix, float, float]:
    mask = rng.random((units, units)) < float(density)
    if not np.any(mask) or rho == 0:
        return sparse.csr_matrix((units, units), dtype=float), 0.0, 0.0
    matrix = sparse.csr_matrix(
        rng.normal(0.0, 1.0 / np.sqrt(max(1.0, units * density)), (units, units)) * mask
    )
    if units <= 2:
        radius = float(np.max(np.abs(np.linalg.eigvals(matrix.toarray()))))
    else:
        try:
            eigenvalue = sparse_linalg.eigs(
                matrix, k=1, which="LM", return_eigenvectors=False,
                v0=np.ones(units), maxiter=max(1000, units * 10), tol=1e-10,
            )
            radius = float(np.max(np.abs(eigenvalue)))
        except Exception:
            radius = float(np.max(np.abs(np.linalg.eigvals(matrix.toarray()))))
    if not np.isfinite(radius) or radius <= 0:
        return sparse.csr_matrix((units, units), dtype=float), 0.0, radius
    return matrix * (float(rho) / radius), float(rho), radius


def make_reservoir(
    spec: Mapping[str, Any], input_dimension: int
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    normalized = normalize_spec(spec)
    cache_key = (fingerprint(normalized), int(input_dimension))
    if cache_key in _RESERVOIR_CACHE:
        return _RESERVOIR_CACHE[cache_key]
    rng = np.random.default_rng(normalized["seed"])
    layers, arrays = [], {}
    previous = int(input_dimension)
    realized = []
    for layer_index, units in enumerate(normalized["units"]):
        units = int(units)
        if layer_index == 0:
            fan = min(previous, normalized["input_fan_in"])
            row_indices, column_indices, values = [], [], []
            for unit in range(units):
                selected = rng.choice(previous, size=fan, replace=False)
                row_indices.extend(selected.tolist()); column_indices.extend([unit] * fan)
                values.extend(rng.normal(0.0, normalized["input_scale"] / np.sqrt(max(1, fan)), size=fan).tolist())
            matrix = sparse.csr_matrix((values, (row_indices, column_indices)), shape=(previous, units))
        else:
            fan = previous
            matrix = rng.normal(
                0.0, normalized["input_scale"] / np.sqrt(max(1, previous)),
                size=(previous, units),
            )
        recurrent, realized_radius, unscaled_radius = _scaled_recurrent_matrix(
            rng, units, normalized["recurrent_sparsity"], normalized["rho"]
        )
        bias = np.zeros(units, dtype=float)
        layers.append({"input": matrix, "recurrent": recurrent, "bias": bias})
        arrays[f"layer{layer_index + 1}_input"] = matrix
        arrays[f"layer{layer_index + 1}_recurrent"] = recurrent
        arrays[f"layer{layer_index + 1}_bias"] = bias
        realized.append({
            "layer": layer_index + 1, "input_nonzero": int(matrix.nnz if sparse.issparse(matrix) else np.count_nonzero(matrix)),
            "input_total": int(matrix.shape[0] * matrix.shape[1]), "input_fan_in": int(fan),
            "recurrent_nonzero": int(recurrent.nnz),
            "recurrent_total": int(recurrent.shape[0] * recurrent.shape[1]),
            "requested_spectral_radius": normalized["rho"],
            "realized_spectral_radius": realized_radius,
            "unscaled_spectral_radius": unscaled_radius,
        })
        previous = units
    config = {
        "depth": normalized["depth"], "units": normalized["units"],
        "alpha": [normalized["alpha"]] * normalized["depth"],
        "rho": [normalized["rho"]] * normalized["depth"],
        "input_scale": [normalized["input_scale"]] * normalized["depth"],
        "recurrent_sparsity": [normalized["recurrent_sparsity"]] * normalized["depth"],
        "bias_scale": [0.0] * normalized["depth"],
        "reservoir_activation": "tanh", "state_output": "concat_layers",
    }
    digest = hashlib.sha256()
    for name in sorted(arrays):
        value = arrays[name]; digest.update(name.encode("utf-8"))
        if sparse.issparse(value):
            canonical = value.tocsr(); digest.update(canonical.data.tobytes()); digest.update(canonical.indices.tobytes()); digest.update(canonical.indptr.tobytes())
        else:
            digest.update(np.ascontiguousarray(value).tobytes())
    reservoir = {"input_dim": int(input_dimension), "config": config, "layers": layers, "arrays": arrays, "sha256": digest.hexdigest()}
    result = (reservoir, config, {"layers": realized, "reservoir_sha256": reservoir["sha256"]})
    _RESERVOIR_CACHE[cache_key] = result
    return result


def readout_rows(states: Sequence[np.ndarray], transition: np.ndarray, mode: str) -> np.ndarray:
    if mode not in READOUTS:
        raise ValueError("unsupported R120 readout")
    layers = [np.asarray(value, dtype=float) for value in states]
    parts = [np.ones((layers[0].shape[0], 1), dtype=float)]
    if mode == "extended_all_layers":
        parts.append(np.asarray(transition, dtype=float))
    parts.extend(layers)
    return np.column_stack(parts)


def feature_names(spec: Mapping[str, Any], explicit_names: Sequence[str]) -> list[str]:
    normalized = normalize_spec(spec)
    names = ["intercept"]
    if normalized["readout"] == "extended_all_layers":
        names.extend(f"input::{name}" for name in explicit_names)
    for layer, width in enumerate(normalized["units"], start=1):
        names.extend(f"layer{layer}::state_{position:04d}" for position in range(1, width + 1))
    return names


def initialize_states(
    arrays: ExplicitArrays, spec: Mapping[str, Any], reservoir: Mapping[str, Any],
    config: Mapping[str, Any], indices: Sequence[int],
) -> list[np.ndarray]:
    idx = np.asarray(indices, dtype=int)
    states = [np.zeros((len(idx), int(width)), dtype=float) for width in config["units"]]
    for relative_time in range(-WARMUP_STEPS, 0):
        transition = explicit_input(arrays, spec, idx, relative_time)
        states = reservoir_step(states, transition, reservoir, config)
    return states


def internal_splits(n_origins: int) -> list[dict[str, Any]]:
    n = int(n_origins)
    if n < 60:
        raise ValueError("R120 requires at least 60 Fold-1 training origins")
    result = []
    for split, (train_fraction, stop_fraction) in enumerate(((0.55, 0.68), (0.68, 0.82), (0.82, 1.0)), 1):
        train_stop = int(np.floor(n * train_fraction))
        stop = n if stop_fraction == 1 else int(np.floor(n * stop_fraction))
        result.append({"split": split, "train": np.arange(train_stop), "validation": np.arange(train_stop, stop)})
    return result


def _empty_stats(p: int) -> dict[str, Any]:
    return {"n": 0, "p": int(p), "XtX": np.zeros((p, p)), "Xty": np.zeros(p), "yty": 0.0}


def teacher_forced_statistics(
    arrays: ExplicitArrays, spec: Mapping[str, Any], origin_groups: Mapping[str, np.ndarray]
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    normalized = normalize_spec(spec)
    explicit_names = input_names(normalized, arrays.exog_names)
    reservoir, config, audit = make_reservoir(normalized, len(explicit_names))
    if not origin_groups:
        raise ValueError("R120 statistics require at least one origin group")
    indices = np.unique(np.concatenate([np.asarray(value, dtype=int) for value in origin_groups.values()]))
    if not len(indices) or indices.min() < 0 or indices.max() >= len(arrays.response):
        raise ValueError("R120 statistics origin group is invalid")
    global_to_local = np.full(len(arrays.response), -1, dtype=int)
    global_to_local[indices] = np.arange(len(indices))
    local_groups = {name: global_to_local[np.asarray(value, dtype=int)] for name, value in origin_groups.items()}
    states = initialize_states(arrays, normalized, reservoir, config, indices)
    p = len(feature_names(normalized, explicit_names))
    stats = {name: _empty_stats(p) for name in origin_groups}
    for horizon in range(96):
        transition = explicit_input(arrays, normalized, indices, horizon)
        states = reservoir_step(states, transition, reservoir, config)
        design = readout_rows(states, transition, normalized["readout"])
        response = arrays.response[indices, horizon]
        for name, selected in local_groups.items():
            block, y = design[selected], response[selected]
            stats[name]["n"] += len(y)
            stats[name]["XtX"] += block.T @ block
            stats[name]["Xty"] += block.T @ y
            stats[name]["yty"] += float(y @ y)
    return stats, audit


def teacher_forced_design(
    arrays: ExplicitArrays, spec: Mapping[str, Any]
) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    normalized = normalize_spec(spec)
    names = input_names(normalized, arrays.exog_names)
    reservoir, config, audit = make_reservoir(normalized, len(names))
    indices = np.arange(len(arrays.response), dtype=int)
    states = initialize_states(arrays, normalized, reservoir, config, indices)
    p = len(feature_names(normalized, names))
    design = np.empty((len(indices) * 96, p), dtype=float)
    response = np.empty(len(indices) * 96, dtype=float)
    for horizon in range(96):
        transition = explicit_input(arrays, normalized, indices, horizon)
        states = reservoir_step(states, transition, reservoir, config)
        start, stop = horizon * len(indices), (horizon + 1) * len(indices)
        design[start:stop] = readout_rows(states, transition, normalized["readout"])
        response[start:stop] = arrays.response[:, horizon]
    return design, response, audit


def fit_scaled_ridge(stats: Mapping[str, Any], ridge_variance: float = 1e4) -> dict[str, Any]:
    p = int(stats["p"])
    prior = np.full(p, 1.0 / float(ridge_variance)); prior[0] = 1e-6
    precision = 0.5 * (np.asarray(stats["XtX"]) + np.asarray(stats["XtX"]).T) + np.diag(prior)
    try:
        chol = np.linalg.cholesky(precision)
    except np.linalg.LinAlgError:
        jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.mean(np.diag(precision))))
        chol = np.linalg.cholesky(precision + np.eye(p) * jitter)
    mean = np.linalg.solve(chol.T, np.linalg.solve(chol, np.asarray(stats["Xty"])))
    inverse = np.linalg.solve(chol.T, np.linalg.solve(chol, np.eye(p)))
    shape = 2.0 + float(stats["n"]) / 2.0
    rate = max(1.0 + 0.5 * (float(stats["yty"]) - float(mean @ precision @ mean)), np.finfo(float).eps)
    return {
        "beta_mean": mean, "beta_cov": rate / max(shape - 1.0, 1.0) * inverse,
        "omega_shape": shape, "omega_rate": rate,
        "omega_mean": rate / max(shape - 1.0, 1.0), "prior_type": "scaled_ridge",
    }


def _normal_quantiles(mean: np.ndarray, variance: np.ndarray) -> np.ndarray:
    z = np.asarray([NormalDist().inv_cdf(value) for value in QUANTILES])
    return mean[:, None] + np.sqrt(np.maximum(variance, np.finfo(float).eps))[:, None] * z[None, :]


def recursive_normal_score(
    arrays: ExplicitArrays, spec: Mapping[str, Any], fit: Mapping[str, Any],
    validation_indices: Sequence[int], maximum_origins: int | None = None,
) -> dict[str, Any]:
    normalized = normalize_spec(spec)
    idx = np.asarray(validation_indices, dtype=int)
    if maximum_origins is not None and len(idx) > int(maximum_origins):
        positions = np.linspace(0, len(idx) - 1, int(maximum_origins)).round().astype(int)
        idx = idx[np.unique(positions)]
    names = input_names(normalized, arrays.exog_names)
    reservoir, config, _ = make_reservoir(normalized, len(names))
    states = initialize_states(arrays, normalized, reservoir, config, idx)
    beta = np.asarray(fit["beta_mean"]); covariance = np.asarray(fit["beta_cov"])
    generated = np.empty((len(idx), 96), dtype=float)
    predictions = np.empty((len(idx), 96, len(QUANTILES)), dtype=float)
    for horizon in range(96):
        transition = explicit_input(arrays, normalized, idx, horizon, generated[:, :horizon])
        states = reservoir_step(states, transition, reservoir, config)
        design = readout_rows(states, transition, normalized["readout"])
        location = design @ beta
        variance = float(fit["omega_mean"]) + np.einsum("ij,jk,ik->i", design, covariance, design, optimize=True)
        predictions[:, horizon] = _normal_quantiles(location, variance)
        generated[:, horizon] = location
    truth = arrays.response[idx]
    return {
        "AQL": average_quantile_loss(truth, predictions, QUANTILES),
        "late_AQL": average_quantile_loss(truth[:, 72:], predictions[:, 72:], QUANTILES),
        "median_MAE": float(np.mean(np.abs(truth - predictions[:, :, 3]))),
        "interval_80_coverage": float(np.mean((truth >= predictions[:, :, 0]) & (truth <= predictions[:, :, -1]))),
        "interval_80_width": float(np.mean(predictions[:, :, -1] - predictions[:, :, 0])),
        "origins_scored": int(len(idx)),
    }


def resource_estimate(spec: Mapping[str, Any], exog_dimension: int) -> dict[str, Any]:
    normalized = normalize_spec(spec)
    input_dimension = normalized["m_y"] + (normalized["m_x"] + 1) * int(exog_dimension)
    if normalized["calendar"] == "compact3":
        input_dimension += 3
    readout_dimension = 1 + sum(normalized["units"])
    if normalized["readout"] == "extended_all_layers":
        readout_dimension += input_dimension
    first_nonzero = min(input_dimension, normalized["input_fan_in"]) * normalized["units"][0]
    recurrent_nonzero = sum(
        int(np.ceil(width * width * normalized["recurrent_sparsity"])) for width in normalized["units"]
    )
    covariance_bytes = readout_dimension * readout_dimension * 8
    return {
        "input_dimension": input_dimension, "readout_dimension": readout_dimension,
        "first_layer_input_nonzeros": first_nonzero,
        "recurrent_nonzeros_estimate": recurrent_nonzero,
        "sufficient_statistics_bytes": covariance_bytes,
        "posterior_covariance_bytes": covariance_bytes,
        "extended_memory_gate_gib": 2.0 * covariance_bytes / 2**30,
    }


def write_stats_packet(path: Path, stats: Mapping[str, Any], metadata: Mapping[str, Any]) -> None:
    path = Path(path); path.mkdir(parents=True, exist_ok=True)
    np.asarray(stats["XtX"], dtype="<f8").tofile(path / "XtX.bin")
    np.asarray(stats["Xty"], dtype="<f8").tofile(path / "Xty.bin")
    write_json(path / "statistics.json", {
        "n": int(stats["n"]), "p": int(stats["p"]), "yty": float(stats["yty"]),
        "test_opened": False, **dict(metadata),
    })
    files = {name: {"bytes": (path / name).stat().st_size, "sha256": sha256_file(path / name)} for name in ("XtX.bin", "Xty.bin", "statistics.json")}
    write_json(path / "terminal.json", {"status": "completed_causal_sufficient_statistics", "stage": "R120", "files": files, "test_opened": False})


def load_normal_fit(path: Path) -> dict[str, Any]:
    path = Path(path); terminal = json.loads((path / "terminal.json").read_text()); p = int(terminal["p"])
    beta = np.fromfile(path / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(path / "beta_cov.bin", dtype="<f8").reshape(p, p)
    if beta.size != p or not np.isfinite(beta).all() or not np.isfinite(covariance).all():
        raise ValueError("invalid R120 Normal posterior packet")
    return {
        "beta_mean": beta, "beta_cov": covariance,
        "omega_shape": float(terminal["omega_shape"]), "omega_rate": float(terminal["omega_rate"]),
        "omega_mean": float(terminal["omega_rate"]) / max(float(terminal["omega_shape"]) - 1.0, 1.0),
        "prior_type": str(terminal["prior_type"]),
    }


def load_quantile_fit(path: Path) -> dict[str, Any]:
    path = Path(path); terminal = json.loads((path / "terminal.json").read_text()); p = int(terminal["p"])
    beta = np.fromfile(path / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(path / "beta_cov.bin", dtype="<f8").reshape(p, p)
    if beta.size != p or not np.isfinite(beta).all() or not np.isfinite(covariance).all():
        raise ValueError("invalid R120 quantile posterior packet")
    return {"beta_mean": beta, "beta_cov": covariance, "terminal": terminal}


def _draw_gaussian(mean: np.ndarray, covariance: np.ndarray, paths: int, seed: int) -> np.ndarray:
    covariance = np.asarray(covariance, dtype=float)
    jitter = np.sqrt(np.finfo(float).eps) * max(1.0, float(np.mean(np.diag(covariance))))
    chol = np.linalg.cholesky(0.5 * (covariance + covariance.T) + np.eye(len(covariance)) * jitter)
    rng = np.random.default_rng(seed)
    return np.asarray(mean)[None, :] + rng.standard_normal((int(paths), len(covariance))) @ chol.T


def recursive_quantile_forecast(
    arrays: ExplicitArrays, spec: Mapping[str, Any], normal_fit: Mapping[str, Any],
    quantile_fits: Mapping[float, Mapping[str, Any]], paths: int = 500,
    seed: int = 2026092501,
) -> dict[str, np.ndarray]:
    normalized = normalize_spec(spec)
    if sorted(float(value) for value in quantile_fits) != list(QUANTILES):
        raise ValueError("R120 requires all seven quantile fits")
    names = input_names(normalized, arrays.exog_names)
    reservoir, config, _ = make_reservoir(normalized, len(names))
    normal_beta = _draw_gaussian(
        np.asarray(normal_fit["beta_mean"]), np.asarray(normal_fit["beta_cov"]), paths,
        deterministic_seed(seed, "normal_beta"),
    )
    sigma_rng = np.random.default_rng(deterministic_seed(seed, "normal_sigma"))
    omega = 1.0 / sigma_rng.gamma(
        shape=float(normal_fit["omega_shape"]),
        scale=1.0 / float(normal_fit["omega_rate"]), size=int(paths),
    )
    quantile_beta = {
        tau: _draw_gaussian(
            np.asarray(fit["beta_mean"]), np.asarray(fit["beta_cov"]), paths,
            deterministic_seed(seed, "quantile_beta", tau),
        ) for tau, fit in quantile_fits.items()
    }
    n_origins = len(arrays.response)
    path_specific = np.empty((n_origins, 96, len(QUANTILES)))
    mean_feature = np.empty_like(path_specific)
    normal_driver = np.empty_like(path_specific)
    for origin in range(n_origins):
        repeated = np.repeat(origin, int(paths))
        states = initialize_states(arrays, normalized, reservoir, config, np.asarray([origin]))
        states = [np.repeat(layer, int(paths), axis=0) for layer in states]
        generated = np.empty((int(paths), 96), dtype=float)
        for horizon in range(96):
            transition = explicit_input(arrays, normalized, repeated, horizon, generated[:, :horizon])
            states = reservoir_step(states, transition, reservoir, config)
            design = readout_rows(states, transition, normalized["readout"])
            location = np.einsum("sp,sp->s", design, normal_beta, optimize=True)
            innovation = np.random.default_rng(
                deterministic_seed(seed, "innovation", origin, horizon)
            ).standard_normal(int(paths))
            generated[:, horizon] = location + np.sqrt(omega) * innovation
            normal_driver[origin, horizon] = np.quantile(generated[:, horizon], QUANTILES)
            averaged = np.mean(design, axis=0)
            for position, tau in enumerate(QUANTILES):
                beta = quantile_beta[float(tau)]
                path_specific[origin, horizon, position] = float(
                    np.mean(np.einsum("sp,sp->s", design, beta, optimize=True))
                )
                mean_feature[origin, horizon, position] = float(np.mean(beta @ averaged))
    return {
        "path_specific": path_specific, "mean_feature": mean_feature,
        "normal_driver": normal_driver, "truth": np.asarray(arrays.response),
    }


def prediction_metrics(truth: np.ndarray, prediction: np.ndarray) -> dict[str, Any]:
    truth = np.asarray(truth, dtype=float); prediction = np.asarray(prediction, dtype=float)
    return {
        "AQL": average_quantile_loss(truth, prediction, QUANTILES),
        "late_AQL": average_quantile_loss(truth[:, 72:], prediction[:, 72:], QUANTILES),
        "median_MAE": float(np.mean(np.abs(truth - prediction[:, :, 3]))),
        "interval_80_coverage": float(np.mean((truth >= prediction[:, :, 0]) & (truth <= prediction[:, :, -1]))),
        "interval_80_width": float(np.mean(prediction[:, :, -1] - prediction[:, :, 0])),
        "crossing_rate": float(np.mean(prediction[:, :, :-1] > prediction[:, :, 1:])),
    }
