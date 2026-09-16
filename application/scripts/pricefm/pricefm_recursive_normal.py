"""Causal Normal-DESN helpers for the PriceFM R102 workflow."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Mapping, Sequence

import numpy as np

from pricefm_common import sha256_file, write_json
from pricefm_desn_adapter import (
    horizon_features,
    make_reservoir_matrices,
    normalize_reservoir_config,
)
from pricefm_recursive_adapter import build_policy_features, normalize_spec


HORIZONS = tuple(range(1, 97))
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def _block(window: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "X_lag": np.asarray(window["X_lag"], dtype=float),
        "lag_cols": [str(x) for x in window["lag_cols"]],
        "X_lead": np.asarray(window["X_lead"], dtype=float),
        "lead_cols": [str(x) for x in window["lead_cols"]],
    }


def _future_block(window: Mapping[str, Any], region: str) -> dict[str, Any]:
    lead = np.asarray(window["X_lead"], dtype=float)
    response = np.asarray(window["Y"], dtype=float)
    if response.shape != lead.shape[:2]:
        raise ValueError("response and lead arrays must share origin/horizon dimensions")
    lag_cols = [str(x) for x in window["lag_cols"]]
    label = "{}-price".format(region)
    if label not in lag_cols:
        raise ValueError("recursive target-price column is absent for {}".format(region))
    return {
        "X_lag": np.concatenate([response[..., None], lead], axis=-1),
        "lag_cols": [label] + [str(x) for x in window["lead_cols"]],
        "X_lead": lead,
        "lead_cols": [str(x) for x in window["lead_cols"]],
    }


def _validate_windows(
    windows: Mapping[str, Mapping[str, Any]],
    target_region: str,
    active_regions: Sequence[str],
) -> None:
    if set(windows) != set(active_regions):
        raise ValueError("raw windows must contain exactly the active regions")
    target = windows[target_region]
    anchors = np.asarray(target["anchors"])
    shape = np.asarray(target["Y"]).shape
    if len(shape) != 2 or shape[1] != len(HORIZONS):
        raise ValueError("R102 requires 96-horizon PriceFM windows")
    for region in active_regions:
        window = windows[region]
        if not np.array_equal(anchors, np.asarray(window["anchors"])):
            raise ValueError("active-region windows must have identical anchors")
        if np.asarray(window["Y"]).shape != shape:
            raise ValueError("active-region response windows must be aligned")
        lag = np.asarray(window["X_lag"])
        lead = np.asarray(window["X_lead"])
        if lag.shape[:2] != (shape[0], lag.shape[1]) or lead.shape[:2] != shape:
            raise ValueError("active-region lag/lead windows are not aligned")
        if lag.shape[-1] != 4 or lead.shape[-1] != 3:
            raise ValueError("PriceFM requires price/load/solar/wind lags and three lead covariates")
        if not np.all(np.isfinite(lag)) or not np.all(np.isfinite(lead)) or not np.all(np.isfinite(window["Y"])):
            raise ValueError("R102 windows must be finite")


def reservoir_step(
    states: list[np.ndarray],
    values: np.ndarray,
    reservoir: Mapping[str, Any],
    config: Mapping[str, Any],
) -> list[np.ndarray]:
    layer_input = np.asarray(values, dtype=float)
    updated: list[np.ndarray] = []
    for layer_id, layer in enumerate(reservoir["layers"]):
        previous = states[layer_id]
        pre = layer_input @ layer["input"] + previous @ layer["recurrent"] + layer["bias"]
        alpha = float(config["alpha"][layer_id])
        state = (1.0 - alpha) * previous + alpha * np.tanh(pre)
        updated.append(state)
        layer_input = state
    return updated


def reservoir_output(states: Sequence[np.ndarray], config: Mapping[str, Any]) -> np.ndarray:
    if str(config["state_output"]) == "concat_layers":
        return np.column_stack(states)
    return np.asarray(states[-1])


def causal_teacher_forced_statistics(
    windows: Mapping[str, Mapping[str, Any]],
    spec: Mapping[str, Any],
    input_regions: Sequence[str],
) -> dict[str, Any]:
    """Build exact sufficient statistics for the R102 one-step design.

    The implementation processes one horizon block at a time, so memory is
    bounded by the number of daily origins rather than origins times 96.
    """

    normalized = normalize_spec(spec)
    target = str(normalized["region"])
    policy = str(normalized["feature_policy"])
    spatial = dict(normalized["spatial"])
    initial = build_policy_features(
        target,
        {region: _block(window) for region, window in windows.items()},
        policy,
        spatial,
        input_regions=input_regions,
    )
    active = list(initial["feature_policy_manifest"]["active_regions"])
    _validate_windows(windows, target, active)
    future = build_policy_features(
        target,
        {region: _future_block(window, region) for region, window in windows.items()},
        policy,
        spatial,
        input_regions=input_regions,
    )

    target_window = windows[target]
    y = np.asarray(target_window["Y"], dtype=float)
    x_lag = np.asarray(initial["X_lag"], dtype=float)
    x_lead = np.asarray(initial["X_lead"], dtype=float)
    future_lag = np.asarray(future["X_lag"], dtype=float)
    if x_lag.shape[1] != int(normalized["lag_window"]):
        raise ValueError("window lag length disagrees with the frozen contract")
    if x_lead.shape[:2] != y.shape or future_lag.shape[:2] != y.shape:
        raise ValueError("policy-transformed recursive arrays are not aligned")

    reservoir_config = normalize_reservoir_config(
        {
            "depth": normalized["depth"],
            "units": normalized["units"],
            "alpha": normalized["alpha"],
            "rho": normalized["rho"],
            "input_scale": normalized["input_scale"],
            "recurrent_sparsity": 0.05,
            "bias_scale": 0.0,
            "reservoir_activation": "tanh",
            "state_output": normalized["state_output"],
        },
        int(normalized["units"][-1]),
    )
    reservoir = make_reservoir_matrices(x_lag.shape[-1], reservoir_config, int(normalized["seed"]))
    n_origins = y.shape[0]
    states = [np.zeros((n_origins, int(units)), dtype=float) for units in reservoir_config["units"]]
    for lag_index in range(x_lag.shape[1] - 1):
        states = reservoir_step(states, x_lag[:, lag_index, :], reservoir, reservoir_config)

    horizon_basis = horizon_features(np.asarray(HORIZONS), list(HORIZONS))
    state_dim = sum(reservoir_config["units"]) if reservoir_config["state_output"] == "concat_layers" else reservoir_config["units"][-1]
    p = 1 + int(state_dim) + x_lead.shape[-1] + horizon_basis.shape[-1]
    xtx = np.zeros((p, p), dtype=float)
    xty = np.zeros(p, dtype=float)
    yty = 0.0
    horizon_one_design = None
    for horizon_index in range(len(HORIZONS)):
        transition = x_lag[:, -1, :] if horizon_index == 0 else future_lag[:, horizon_index - 1, :]
        states = reservoir_step(states, transition, reservoir, reservoir_config)
        state_value = reservoir_output(states, reservoir_config)
        basis = np.repeat(horizon_basis[horizon_index : horizon_index + 1], n_origins, axis=0)
        design = np.column_stack([
            np.ones(n_origins, dtype=float),
            state_value,
            x_lead[:, horizon_index, :],
            basis,
        ])
        response = y[:, horizon_index]
        xtx += design.T @ design
        xty += design.T @ response
        yty += float(response @ response)
        if horizon_index == 0:
            horizon_one_design = design.copy()

    # A direct horizon-one row consumes all L observed lag rows and must be
    # numerically identical to the first causal recursive row.
    direct_states = [np.zeros((n_origins, int(units)), dtype=float) for units in reservoir_config["units"]]
    for lag_index in range(x_lag.shape[1]):
        direct_states = reservoir_step(direct_states, x_lag[:, lag_index, :], reservoir, reservoir_config)
    direct_h1 = np.column_stack([
        np.ones(n_origins, dtype=float),
        reservoir_output(direct_states, reservoir_config),
        x_lead[:, 0, :],
        np.repeat(horizon_basis[0:1], n_origins, axis=0),
    ])
    parity_error = float(np.max(np.abs(direct_h1 - horizon_one_design)))
    if parity_error > 1e-12:
        raise RuntimeError("causal horizon-one design does not match the frozen direct design")

    feature_names = (
        ["intercept"]
        + ["state_{:04d}".format(i + 1) for i in range(int(state_dim))]
        + ["lead::{}".format(name) for name in initial["lead_cols"]]
        + ["horizon_{:03d}".format(i + 1) for i in range(horizon_basis.shape[-1])]
    )
    return {
        "n": int(n_origins * len(HORIZONS)),
        "p": int(p),
        "XtX": xtx,
        "Xty": xty,
        "yty": float(yty),
        "feature_names": feature_names,
        "anchors": [str(x) for x in np.asarray(target_window["anchors"]).tolist()],
        "horizon_one_parity_max_abs": parity_error,
        "reservoir": reservoir,
        "reservoir_config": reservoir_config,
        "feature_policy_manifest": initial["feature_policy_manifest"],
        "contract": normalized,
        "training_timing": "initialize_L_minus_1_then_predict_transition_observe_update",
        "test_opened": False,
    }


def _write_float64(path: Path, values: np.ndarray) -> None:
    np.asarray(values, dtype="<f8").tofile(path)


def write_statistics(output_dir: Path, result: Mapping[str, Any], force: bool = False) -> dict[str, Any]:
    output_dir = Path(output_dir).resolve()
    if output_dir.exists() and any(output_dir.iterdir()) and not force:
        raise FileExistsError(output_dir)
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_dir.name + ".tmp.", dir=output_dir.parent))
    try:
        _write_float64(temporary / "XtX.bin", np.asarray(result["XtX"]))
        _write_float64(temporary / "Xty.bin", np.asarray(result["Xty"]))
        arrays: dict[str, np.ndarray] = {}
        for layer_id, layer in enumerate(result["reservoir"]["layers"], start=1):
            arrays["input_{}".format(layer_id)] = np.asarray(layer["input"], dtype=float)
            arrays["recurrent_{}".format(layer_id)] = np.asarray(layer["recurrent"], dtype=float)
            arrays["bias_{}".format(layer_id)] = np.asarray(layer["bias"], dtype=float)
        np.savez_compressed(temporary / "reservoir.npz", **arrays)
        meta = {
            key: result[key]
            for key in (
                "n", "p", "yty", "feature_names", "anchors",
                "horizon_one_parity_max_abs", "reservoir_config",
                "feature_policy_manifest", "contract", "training_timing", "test_opened",
            )
        }
        write_json(temporary / "statistics.json", meta)
        files = ["XtX.bin", "Xty.bin", "reservoir.npz", "statistics.json"]
        terminal = {
            "status": "completed_causal_sufficient_statistics",
            "n": int(result["n"]),
            "p": int(result["p"]),
            "horizon_one_parity_max_abs": float(result["horizon_one_parity_max_abs"]),
            "files": {name: {"bytes": (temporary / name).stat().st_size, "sha256": sha256_file(temporary / name)} for name in files},
            "test_opened": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output_dir.exists():
            shutil.rmtree(output_dir)
        temporary.rename(output_dir)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def read_float64(path: Path, shape: Sequence[int]) -> np.ndarray:
    values = np.fromfile(path, dtype="<f8")
    if values.size != int(np.prod(shape)):
        raise ValueError("binary array size does not match declared shape")
    return values.reshape(tuple(shape))


def posterior_target_hash(
    stats_sha256: str,
    prior_type: str,
    tau0: float | None,
    omega_prior: Mapping[str, float] | None = None,
) -> str:
    payload = {
        "likelihood": "normal",
        "statistics_sha256": str(stats_sha256),
        "prior_type": str(prior_type),
        "tau0": None if tau0 is None else float(tau0),
        "shrink_intercept": False if str(prior_type) == "rhs_ns" else None,
        "omega_prior": dict(omega_prior or {"a": 2.0, "b": 1.0}),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()
