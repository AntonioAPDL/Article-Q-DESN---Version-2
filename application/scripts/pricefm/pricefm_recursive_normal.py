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
from pricefm_recursive_readout import (
    build_readout_rows,
    readout_dimension,
    readout_feature_names,
)


HORIZONS = tuple(range(1, 97))
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def deterministic_seed(*parts: Any) -> int:
    """Return a stable NumPy seed without depending on Python's hash salt."""

    payload = json.dumps(parts, sort_keys=True, separators=(",", ":"), default=str)
    value = int.from_bytes(hashlib.sha256(payload.encode()).digest()[:8], "little")
    return value % (2**63 - 1)


def _stable_cholesky(value: np.ndarray) -> np.ndarray:
    matrix = 0.5 * (np.asarray(value, dtype=float) + np.asarray(value, dtype=float).T)
    jitter = 0.0
    for _ in range(10):
        candidate = matrix if jitter == 0 else matrix + np.eye(matrix.shape[0]) * jitter
        try:
            return np.linalg.cholesky(candidate)
        except np.linalg.LinAlgError:
            scale = max(1.0, float(np.mean(np.diag(matrix))))
            jitter = np.sqrt(np.finfo(float).eps) * scale if jitter == 0 else jitter * 10.0
    raise ValueError("posterior covariance is not positive definite")


def draw_normal_posterior(
    beta_mean: np.ndarray,
    beta_covariance: np.ndarray,
    omega_shape: float,
    omega_rate: float,
    n_paths: int,
    seed: int,
    prior_type: str,
    precision_inverse: np.ndarray | None = None,
) -> dict[str, np.ndarray]:
    """Draw the matching exact-Ridge or mean-field-RHS Normal posterior.

    Ridge retains the exact Normal-inverse-gamma dependence. RHS uses the
    fitted mean-field factors q(beta) q(omega2), which are independent by
    construction. These draws affect prediction only; they do not redefine a
    prior or posterior target.
    """

    mean = np.asarray(beta_mean, dtype=float)
    covariance = np.asarray(beta_covariance, dtype=float)
    n_paths = int(n_paths)
    shape = float(omega_shape)
    rate = float(omega_rate)
    if mean.ndim != 1 or covariance.shape != (mean.size, mean.size):
        raise ValueError("posterior beta mean/covariance dimensions disagree")
    if n_paths < 1 or min(shape, rate) <= 0 or not np.isfinite([shape, rate]).all():
        raise ValueError("invalid posterior draw controls")
    sigma_rng = np.random.default_rng(deterministic_seed(seed, "omega2"))
    beta_rng = np.random.default_rng(deterministic_seed(seed, "beta"))
    omega2 = 1.0 / sigma_rng.gamma(shape=shape, scale=1.0 / rate, size=n_paths)
    z = beta_rng.standard_normal((n_paths, mean.size))
    if str(prior_type) == "scaled_ridge":
        if precision_inverse is None:
            raise ValueError("exact Ridge draws require the conditional precision inverse")
        conditional = np.asarray(precision_inverse, dtype=float)
        if conditional.shape != covariance.shape:
            raise ValueError("Ridge precision inverse dimensions disagree")
        beta = mean + (z @ _stable_cholesky(conditional).T) * np.sqrt(omega2)[:, None]
        contract = "exact_normal_inverse_gamma_conditional"
    elif str(prior_type) == "rhs_ns":
        beta = mean + z @ _stable_cholesky(covariance).T
        contract = "mean_field_q_beta_times_q_omega2"
    else:
        raise ValueError("unsupported Normal prior type: {}".format(prior_type))
    if not np.all(np.isfinite(beta)) or not np.all(np.isfinite(omega2)):
        raise ValueError("non-finite Normal posterior draw")
    return {"beta": beta, "omega2": omega2, "contract": contract}


def recursive_transition_features(
    target_region: str,
    spec: Mapping[str, Any],
    panel_snapshot: Mapping[str, np.ndarray],
    exogenous_snapshot: Mapping[str, np.ndarray],
    lag_columns: Mapping[str, Sequence[str]],
    lead_columns: Mapping[str, Sequence[str]],
    input_regions: Sequence[str],
) -> np.ndarray:
    """Build one path-varying h-1 transition from a frozen panel snapshot."""

    normalized = normalize_spec(spec)
    active = [str(region) for region in panel_snapshot]
    if any(region not in panel_snapshot or region not in exogenous_snapshot for region in active):
        raise ValueError("recursive panel snapshot is missing an active region")
    n_paths = {np.asarray(panel_snapshot[region]).size for region in active}
    if len(n_paths) != 1:
        raise ValueError("recursive regional path counts disagree")
    blocks: dict[str, dict[str, Any]] = {}
    for region in active:
        price = np.asarray(panel_snapshot[region], dtype=float).reshape(-1, 1, 1)
        exogenous = np.asarray(exogenous_snapshot[region], dtype=float).reshape(1, 1, -1)
        exogenous = np.repeat(exogenous, price.shape[0], axis=0)
        expected_lag = list(lag_columns[region])
        if len(expected_lag) != exogenous.shape[-1] + 1:
            raise ValueError("recursive lag contract must be price plus lead covariates")
        blocks[region] = {
            "X_lag": np.concatenate([price, exogenous], axis=-1),
            "lag_cols": expected_lag,
            "X_lead": exogenous,
            "lead_cols": list(lead_columns[region]),
        }
    transformed = build_policy_features(
        target_region,
        blocks,
        normalized["feature_policy"],
        normalized["spatial"],
        input_regions=input_regions,
    )
    return np.asarray(transformed["X_lag"][:, 0, :], dtype=float)


def precompute_initial_states(context: Mapping[str, Any]) -> list[np.ndarray]:
    """Compute path-invariant states through the first L-1 observed inputs."""

    lag = np.asarray(context["initial_lag"], dtype=float)
    config = context["reservoir_config"]
    states = [np.zeros((lag.shape[0], int(units)), dtype=float) for units in config["units"]]
    for lag_index in range(lag.shape[1] - 1):
        states = reservoir_step(states, lag[:, lag_index, :], context["reservoir"], config)
    return states


def recursive_panel_origin(
    contexts: Mapping[str, Mapping[str, Any]],
    origin_index: int,
    n_paths: int,
    fold: int,
    base_seed: int,
    calculation_order: Sequence[str] | None = None,
) -> np.ndarray:
    """Generate one synchronized Normal panel forecast for one daily origin."""

    regions = [str(x) for x in contexts]
    order = [str(x) for x in (calculation_order or regions)]
    if set(order) != set(regions) or len(order) != len(regions):
        raise ValueError("calculation_order must be a permutation of panel regions")
    n_paths = int(n_paths)
    if n_paths < 1:
        raise ValueError("n_paths must be positive")
    horizon = len(HORIZONS)
    output = np.empty((n_paths, horizon, len(regions)), dtype=float)
    positions = {region: index for index, region in enumerate(regions)}
    states: dict[str, list[np.ndarray]] = {}

    for region in regions:
        context = contexts[region]
        initial = [
            np.repeat(np.asarray(layer[origin_index : origin_index + 1], dtype=float), n_paths, axis=0)
            for layer in context["initial_states"]
        ]
        transition = np.repeat(
            np.asarray(context["initial_lag"][origin_index, -1, :], dtype=float)[None, :],
            n_paths,
            axis=0,
        )
        states[region] = reservoir_step(
            initial, transition, context["reservoir"], context["reservoir_config"]
        )

    panel_snapshot: dict[str, np.ndarray] | None = None
    basis = horizon_features(np.asarray(HORIZONS), list(HORIZONS))
    for horizon_index in range(horizon):
        if horizon_index > 0:
            assert panel_snapshot is not None
            for region in order:
                context = contexts[region]
                exogenous = {
                    source: np.asarray(context["raw_lead"][source][origin_index, horizon_index - 1], dtype=float)
                    for source in context["active_regions"]
                }
                transition = recursive_transition_features(
                    region,
                    context["spec"],
                    {source: panel_snapshot[source] for source in context["active_regions"]},
                    exogenous,
                    context["lag_columns"],
                    context["lead_columns"],
                    context["input_regions"],
                )
                states[region] = reservoir_step(
                    states[region], transition, context["reservoir"], context["reservoir_config"]
                )

        pending: dict[str, np.ndarray] = {}
        for region in order:
            context = contexts[region]
            state_value = reservoir_output(states[region], context["reservoir_config"])
            lead = np.asarray(context["lead_features"][origin_index, horizon_index], dtype=float)
            beta = np.asarray(context["posterior_draws"]["beta"], dtype=float)
            state_stop = 1 + state_value.shape[1]
            lead_stop = state_stop + lead.size
            if beta.shape != (n_paths, lead_stop + basis.shape[1]):
                raise ValueError("posterior beta dimension disagrees with recursive design")
            location = (
                beta[:, 0]
                + np.sum(beta[:, 1:state_stop] * state_value, axis=1)
                + beta[:, state_stop:lead_stop] @ lead
                + beta[:, lead_stop:] @ basis[horizon_index]
            )
            innovation = np.random.default_rng(
                deterministic_seed(base_seed, "innovation", fold, origin_index, horizon_index, region)
            ).standard_normal(n_paths)
            response = location + np.sqrt(context["posterior_draws"]["omega2"]) * innovation
            if not np.all(np.isfinite(response)):
                raise ValueError("non-finite recursive response")
            pending[region] = response
        panel_snapshot = pending
        for region in regions:
            output[:, horizon_index, positions[region]] = pending[region]
    return output


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
    readout_mode: str = "state_lead_horizon",
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
    p = readout_dimension(
        state_dim, x_lead.shape[-1], horizon_basis.shape[-1], readout_mode
    )
    xtx = np.zeros((p, p), dtype=float)
    xty = np.zeros(p, dtype=float)
    yty = 0.0
    horizon_one_design = None
    for horizon_index in range(len(HORIZONS)):
        transition = x_lag[:, -1, :] if horizon_index == 0 else future_lag[:, horizon_index - 1, :]
        states = reservoir_step(states, transition, reservoir, reservoir_config)
        state_value = reservoir_output(states, reservoir_config)
        basis = np.repeat(horizon_basis[horizon_index : horizon_index + 1], n_origins, axis=0)
        design = build_readout_rows(
            state_value, x_lead[:, horizon_index, :], basis, readout_mode
        )
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
    direct_h1 = build_readout_rows(
        reservoir_output(direct_states, reservoir_config),
        x_lead[:, 0, :],
        np.repeat(horizon_basis[0:1], n_origins, axis=0),
        readout_mode,
    )
    parity_error = float(np.max(np.abs(direct_h1 - horizon_one_design)))
    if parity_error > 1e-12:
        raise RuntimeError("causal horizon-one design does not match the frozen direct design")

    feature_names = readout_feature_names(
        state_dim, initial["lead_cols"], horizon_basis.shape[-1], readout_mode
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
        "readout_mode": str(readout_mode),
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
                "feature_policy_manifest", "contract", "training_timing",
                "readout_mode", "test_opened",
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
