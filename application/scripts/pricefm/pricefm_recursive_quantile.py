"""Causal independent-quantile helpers for PriceFM Stage R103."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Mapping, Sequence

import numpy as np

from pricefm_common import sha256_file, write_json
from pricefm_desn_adapter import horizon_features, make_reservoir_matrices, normalize_reservoir_config
from pricefm_recursive_adapter import build_policy_features, normalize_spec
from pricefm_recursive_normal import (
    HORIZONS,
    _block,
    _future_block,
    _stable_cholesky,
    _validate_windows,
    deterministic_seed,
    precompute_initial_states,
    reservoir_output,
    reservoir_step,
    recursive_transition_features,
)
from pricefm_recursive_readout import (
    build_readout_rows,
    readout_dimension,
    readout_feature_names,
)


QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
WARM_ORDER = (0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90)
WARM_PARENT = {
    0.50: ("normal_rhs", None),
    0.45: ("al", 0.50),
    0.25: ("al", 0.45),
    0.10: ("al", 0.25),
    0.55: ("al", 0.50),
    0.75: ("al", 0.55),
    0.90: ("al", 0.75),
}


def causal_teacher_forced_design(
    windows: Mapping[str, Mapping[str, Any]],
    spec: Mapping[str, Any],
    input_regions: Sequence[str],
    readout_mode: str = "state_lead_horizon",
) -> dict[str, Any]:
    """Materialize the exact R102 causal design for an AL/exAL refit."""

    normalized = normalize_spec(spec)
    target = str(normalized["region"])
    initial = build_policy_features(
        target,
        {region: _block(window) for region, window in windows.items()},
        normalized["feature_policy"],
        normalized["spatial"],
        input_regions=input_regions,
    )
    active = list(initial["feature_policy_manifest"]["active_regions"])
    _validate_windows(windows, target, active)
    future = build_policy_features(
        target,
        {region: _future_block(window, region) for region, window in windows.items()},
        normalized["feature_policy"],
        normalized["spatial"],
        input_regions=input_regions,
    )
    target_window = windows[target]
    response = np.asarray(target_window["Y"], dtype=float)
    lag = np.asarray(initial["X_lag"], dtype=float)
    lead = np.asarray(initial["X_lead"], dtype=float)
    future_lag = np.asarray(future["X_lag"], dtype=float)
    if lag.shape[1] != int(normalized["lag_window"]):
        raise ValueError("window lag length disagrees with the frozen contract")
    if lead.shape[:2] != response.shape or future_lag.shape[:2] != response.shape:
        raise ValueError("causal quantile design arrays are not aligned")

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
    reservoir = make_reservoir_matrices(lag.shape[-1], reservoir_config, int(normalized["seed"]))
    n_origins = response.shape[0]
    states = [
        np.zeros((n_origins, int(units)), dtype=float)
        for units in reservoir_config["units"]
    ]
    for lag_index in range(lag.shape[1] - 1):
        states = reservoir_step(states, lag[:, lag_index, :], reservoir, reservoir_config)

    basis = horizon_features(np.asarray(HORIZONS), list(HORIZONS))
    state_dim = (
        sum(reservoir_config["units"])
        if reservoir_config["state_output"] == "concat_layers"
        else reservoir_config["units"][-1]
    )
    p = readout_dimension(state_dim, lead.shape[-1], basis.shape[-1], readout_mode)
    design = np.empty((n_origins * len(HORIZONS), p), dtype=float)
    y = np.empty(n_origins * len(HORIZONS), dtype=float)
    horizon_one = None
    for horizon_index in range(len(HORIZONS)):
        transition = lag[:, -1, :] if horizon_index == 0 else future_lag[:, horizon_index - 1, :]
        states = reservoir_step(states, transition, reservoir, reservoir_config)
        state_value = reservoir_output(states, reservoir_config)
        block = build_readout_rows(
            state_value,
            lead[:, horizon_index, :],
            np.repeat(basis[horizon_index : horizon_index + 1], n_origins, axis=0),
            readout_mode,
        )
        start = horizon_index * n_origins
        stop = start + n_origins
        design[start:stop] = block
        y[start:stop] = response[:, horizon_index]
        if horizon_index == 0:
            horizon_one = block.copy()

    direct_states = [
        np.zeros((n_origins, int(units)), dtype=float)
        for units in reservoir_config["units"]
    ]
    for lag_index in range(lag.shape[1]):
        direct_states = reservoir_step(direct_states, lag[:, lag_index, :], reservoir, reservoir_config)
    direct_h1 = build_readout_rows(
        reservoir_output(direct_states, reservoir_config),
        lead[:, 0, :],
        np.repeat(basis[0:1], n_origins, axis=0),
        readout_mode,
    )
    parity = float(np.max(np.abs(direct_h1 - horizon_one)))
    if parity > 1e-12:
        raise RuntimeError("causal quantile horizon-one parity failed")
    if not np.all(np.isfinite(design)) or not np.all(np.isfinite(y)):
        raise ValueError("causal quantile design must be finite")

    feature_names = readout_feature_names(
        state_dim, initial["lead_cols"], basis.shape[-1], readout_mode
    )
    return {
        "X": design,
        "y": y,
        "n": int(design.shape[0]),
        "p": int(design.shape[1]),
        "feature_names": feature_names,
        "anchors": [str(x) for x in np.asarray(target_window["anchors"]).tolist()],
        "horizon_one_parity_max_abs": parity,
        "reservoir": reservoir,
        "reservoir_config": reservoir_config,
        "feature_policy_manifest": initial["feature_policy_manifest"],
        "contract": normalized,
        "training_timing": "initialize_L_minus_1_then_predict_transition_observe_update",
        "readout_mode": str(readout_mode),
        "test_opened": False,
    }


def write_design(output_dir: Path, result: Mapping[str, Any], force: bool = False) -> dict[str, Any]:
    """Atomically write a float64 causal design and its provenance."""

    output_dir = Path(output_dir).resolve()
    if output_dir.exists() and any(output_dir.iterdir()) and not force:
        raise FileExistsError(output_dir)
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_dir.name + ".tmp.", dir=output_dir.parent))
    try:
        np.asarray(result["X"], dtype="<f8").tofile(temporary / "X.bin")
        np.asarray(result["y"], dtype="<f8").tofile(temporary / "y.bin")
        meta = {
            key: result[key]
            for key in (
                "n", "p", "feature_names", "anchors", "horizon_one_parity_max_abs",
                "reservoir_config", "feature_policy_manifest", "contract",
                "training_timing", "readout_mode", "test_opened",
            )
        }
        write_json(temporary / "design.json", meta)
        files = ("X.bin", "y.bin", "design.json")
        terminal = {
            "status": "completed_causal_quantile_design",
            "n": int(result["n"]),
            "p": int(result["p"]),
            "horizon_one_parity_max_abs": float(result["horizon_one_parity_max_abs"]),
            "files": {
                name: {
                    "bytes": (temporary / name).stat().st_size,
                    "sha256": sha256_file(temporary / name),
                }
                for name in files
            },
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


def read_design(output_dir: Path) -> tuple[np.memmap, np.memmap, dict[str, Any]]:
    output_dir = Path(output_dir)
    terminal = json.loads((output_dir / "terminal.json").read_text())
    meta = json.loads((output_dir / "design.json").read_text())
    if terminal.get("status") != "completed_causal_quantile_design" or terminal.get("test_opened") is not False:
        raise ValueError("invalid R103 design terminal")
    for name, record in terminal["files"].items():
        if sha256_file(output_dir / name) != record["sha256"]:
            raise ValueError("changed R103 design artifact: {}".format(name))
    n, p = int(meta["n"]), int(meta["p"])
    x = np.memmap(output_dir / "X.bin", mode="r", dtype="<f8", shape=(n, p))
    y = np.memmap(output_dir / "y.bin", mode="r", dtype="<f8", shape=(n,))
    return x, y, meta


def draw_beta_posterior(
    mean: np.ndarray,
    covariance: np.ndarray,
    n_paths: int,
    seed: int,
) -> np.ndarray:
    mean = np.asarray(mean, dtype=float)
    covariance = np.asarray(covariance, dtype=float)
    if mean.ndim != 1 or covariance.shape != (mean.size, mean.size):
        raise ValueError("quantile beta posterior dimensions disagree")
    rng = np.random.default_rng(deterministic_seed(seed, "quantile_beta"))
    draws = mean + rng.standard_normal((int(n_paths), mean.size)) @ _stable_cholesky(covariance).T
    if not np.all(np.isfinite(draws)):
        raise ValueError("non-finite quantile beta draw")
    return draws


def recursive_quantile_design(
    context: Mapping[str, Any],
    driver_draws: np.ndarray,
    origin_index: int,
    driver_regions: Sequence[str],
    readout_mode: str = "state_lead_horizon",
) -> np.ndarray:
    """Build path-varying readout rows from a frozen Normal-RHS panel path."""

    driver = np.asarray(driver_draws, dtype=float)
    regions = [str(x) for x in driver_regions]
    if driver.ndim != 3 or driver.shape[1] != len(HORIZONS) or driver.shape[2] != len(regions):
        raise ValueError("Normal driver path shape is invalid")
    positions = {region: index for index, region in enumerate(regions)}
    active = [str(x) for x in context["active_regions"]]
    if any(region not in positions for region in active):
        raise ValueError("Normal driver omits an active region")
    n_paths = driver.shape[0]
    states = [
        np.repeat(np.asarray(layer[origin_index : origin_index + 1], dtype=float), n_paths, axis=0)
        for layer in context["initial_states"]
    ]
    transition = np.repeat(
        np.asarray(context["initial_lag"][origin_index, -1, :], dtype=float)[None, :],
        n_paths,
        axis=0,
    )
    states = reservoir_step(states, transition, context["reservoir"], context["reservoir_config"])
    basis = horizon_features(np.asarray(HORIZONS), list(HORIZONS))
    rows = []
    for horizon_index in range(len(HORIZONS)):
        if horizon_index > 0:
            exogenous = {
                source: np.asarray(context["raw_lead"][source][origin_index, horizon_index - 1], dtype=float)
                for source in active
            }
            transition = recursive_transition_features(
                str(context["region"]),
                context["spec"],
                {
                    source: driver[:, horizon_index - 1, positions[source]]
                    for source in active
                },
                exogenous,
                context["lag_columns"],
                context["lead_columns"],
                context["input_regions"],
            )
            states = reservoir_step(states, transition, context["reservoir"], context["reservoir_config"])
        state = reservoir_output(states, context["reservoir_config"])
        lead = np.asarray(context["lead_features"][origin_index, horizon_index], dtype=float)
        rows.append(build_readout_rows(
            state,
            np.repeat(lead[None, :], n_paths, axis=0),
            np.repeat(basis[horizon_index : horizon_index + 1], n_paths, axis=0),
            readout_mode,
        ))
    result = np.stack(rows, axis=1)
    if not np.all(np.isfinite(result)):
        raise ValueError("recursive quantile design contains non-finite values")
    return result


def paired_quantile_prediction(design: np.ndarray, beta_draws: np.ndarray) -> np.ndarray:
    """Return the posterior mean quantile path from paired independent draws."""

    design = np.asarray(design, dtype=float)
    beta = np.asarray(beta_draws, dtype=float)
    if design.ndim != 3 or beta.shape != (design.shape[0], design.shape[2]):
        raise ValueError("paired design and beta draws disagree")
    path_values = np.einsum("shp,sp->sh", design, beta, optimize=True)
    return np.mean(path_values, axis=0)
