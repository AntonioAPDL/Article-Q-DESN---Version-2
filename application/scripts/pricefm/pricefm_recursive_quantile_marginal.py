"""Marginal recursive forecast diagnostics for PriceFM quantile models."""

from __future__ import annotations

from typing import Any, Mapping, Sequence

import numpy as np

from pricefm_desn_adapter import horizon_features
from pricefm_recursive_normal import (
    HORIZONS,
    deterministic_seed,
    reservoir_output,
    reservoir_step,
    recursive_transition_features,
)
from pricefm_recursive_quantile import QUANTILES
from pricefm_recursive_readout import build_readout_rows


def conditional_quantile_paths(
    design: np.ndarray,
    beta_draws: Mapping[float, np.ndarray],
    quantiles: Sequence[float] = QUANTILES,
) -> np.ndarray:
    """Evaluate paired pathwise conditional quantiles without averaging paths."""

    rows = np.asarray(design, dtype=float)
    if rows.ndim != 2:
        raise ValueError("conditional quantile design must have shape (paths, features)")
    values = []
    for tau in quantiles:
        beta = np.asarray(beta_draws[float(tau)], dtype=float)
        if beta.shape != rows.shape:
            raise ValueError("conditional quantile beta draws disagree with the design")
        values.append(np.einsum("sp,sp->s", rows, beta, optimize=True))
    result = np.column_stack(values)
    if not np.isfinite(result).all():
        raise ValueError("conditional quantile paths must be finite")
    return result


def rearrange_quantile_curves(values: np.ndarray) -> tuple[np.ndarray, dict[str, float]]:
    """Monotonically rearrange pathwise quantile curves and report the change."""

    raw = np.asarray(values, dtype=float)
    if raw.ndim != 2 or raw.shape[1] < 2 or not np.isfinite(raw).all():
        raise ValueError("quantile curves must be a finite two-dimensional array")
    crossing = raw[:, :-1] > raw[:, 1:]
    ordered = np.sort(raw, axis=1)
    change = np.abs(ordered - raw)
    diagnostics = {
        "pre_rearrangement_crossing_rate": float(np.mean(crossing)),
        "rearrangement_mean_abs": float(np.mean(change)),
        "rearrangement_max_abs": float(np.max(change)),
    }
    return ordered, diagnostics


def stratified_uniforms(n_paths: int, n_horizons: int, seed: int) -> np.ndarray:
    """Return reproducible horizon-wise randomized stratified uniforms."""

    n_paths, n_horizons = int(n_paths), int(n_horizons)
    if n_paths < 2 or n_horizons < 1:
        raise ValueError("stratified uniforms require at least two paths and one horizon")
    base = (np.arange(n_paths, dtype=float) + 0.5) / n_paths
    rng = np.random.default_rng(deterministic_seed(seed, "quantile_curve_uniforms"))
    result = np.empty((n_paths, n_horizons), dtype=float)
    for horizon in range(n_horizons):
        result[:, horizon] = base[rng.permutation(n_paths)]
    return result


def training_block_rank_uniforms(
    training_ranks: np.ndarray,
    n_paths: int,
    n_horizons: int,
    block_length: int,
    seed: int,
) -> np.ndarray:
    """Bootstrap temporal rank blocks while preserving each horizon's strata.

    ``training_ranks`` must contain only training-period rank trajectories.
    The sampled values determine temporal ordering; every output horizon is
    then mapped back to the exact stratified marginal grid.  This preserves
    the fitted marginal quantile contract and changes only temporal coupling.
    """

    ranks = np.asarray(training_ranks, dtype=float)
    n_paths, n_horizons, block_length = int(n_paths), int(n_horizons), int(block_length)
    if ranks.ndim != 2 or ranks.shape[0] < 2 or ranks.shape[1] < block_length:
        raise ValueError("training ranks must contain at least two sufficiently long trajectories")
    if not np.isfinite(ranks).all() or np.any((ranks <= 0) | (ranks >= 1)):
        raise ValueError("training ranks must be finite and lie strictly inside (0, 1)")
    if n_paths < 2 or n_horizons < 1 or block_length not in {6, 12, 24}:
        raise ValueError("invalid training-block rank controls")
    rng = np.random.default_rng(deterministic_seed(seed, "training_block_rank_uniforms"))
    raw = np.empty((n_paths, n_horizons), dtype=float)
    max_start = ranks.shape[1] - block_length
    for path_index in range(n_paths):
        for output_start in range(0, n_horizons, block_length):
            width = min(block_length, n_horizons - output_start)
            source_row = int(rng.integers(0, ranks.shape[0]))
            source_start = int(rng.integers(0, max_start + 1))
            raw[path_index, output_start : output_start + width] = ranks[
                source_row, source_start : source_start + width
            ]
    base = (np.arange(n_paths, dtype=float) + 0.5) / n_paths
    result = np.empty_like(raw)
    for horizon_index in range(n_horizons):
        jitter = rng.uniform(0.0, np.finfo(float).eps, size=n_paths)
        order = np.argsort(raw[:, horizon_index] + jitter, kind="mergesort")
        result[order, horizon_index] = base
    return result


def forecast_uniforms(
    policy: str,
    n_paths: int,
    n_horizons: int,
    seed: int,
    training_ranks: np.ndarray | None = None,
    block_length: int | None = None,
) -> np.ndarray:
    """Dispatch the two preregistered recursive rank policies."""

    policy = str(policy)
    if policy == "independent_stratified":
        return stratified_uniforms(n_paths, n_horizons, seed)
    if policy == "training_block_rank":
        if training_ranks is None or block_length is None:
            raise ValueError("training-block ranks require training_ranks and block_length")
        return training_block_rank_uniforms(
            training_ranks, n_paths, n_horizons, block_length, seed
        )
    raise ValueError(f"unsupported recursive rank policy: {policy}")


def interpolate_quantile_curves(
    curves: np.ndarray,
    quantiles: Sequence[float],
    uniforms: np.ndarray,
) -> np.ndarray:
    """Sample bounded piecewise-linear inverse CDFs from pathwise curves."""

    values = np.asarray(curves, dtype=float)
    tau = np.asarray(quantiles, dtype=float)
    u = np.asarray(uniforms, dtype=float)
    if values.ndim != 2 or values.shape[1] != tau.size or u.shape != (values.shape[0],):
        raise ValueError("quantile interpolation dimensions disagree")
    if tau.size < 2 or np.any(np.diff(tau) <= 0) or tau[0] <= 0 or tau[-1] >= 1:
        raise ValueError("quantile grid must be strictly increasing inside (0, 1)")
    if not np.isfinite(values).all() or not np.isfinite(u).all() or np.any((u <= 0) | (u >= 1)):
        raise ValueError("quantile interpolation inputs must be finite and uniforms inside (0, 1)")
    if np.any(values[:, :-1] > values[:, 1:]):
        raise ValueError("quantile curves must be rearranged before interpolation")

    clipped = np.clip(u, tau[0], tau[-1])
    upper = np.searchsorted(tau, clipped, side="right")
    upper = np.clip(upper, 1, tau.size - 1)
    lower = upper - 1
    rows = np.arange(values.shape[0])
    weight = (clipped - tau[lower]) / (tau[upper] - tau[lower])
    result = values[rows, lower] + weight * (values[rows, upper] - values[rows, lower])
    if not np.isfinite(result).all():
        raise ValueError("interpolated recursive prices must be finite")
    return result


def recursive_quantile_curve_forecast(
    context: Mapping[str, Any],
    external_driver: np.ndarray,
    origin_index: int,
    driver_regions: Sequence[str],
    beta_draws: Mapping[float, np.ndarray],
    seed: int,
    quantiles: Sequence[float] = QUANTILES,
    readout_mode: str = "state_lead_horizon",
    uniforms: np.ndarray | None = None,
) -> dict[str, Any]:
    """Propagate the target price through an interpolated quantile curve.

    Non-target regional prices come from the supplied frozen Normal panel.
    The target price is sampled from the rearranged seven-quantile curve and
    becomes the target's next endogenous lag. Validation responses are never
    referenced.
    """

    driver = np.asarray(external_driver, dtype=float)
    regions = [str(value) for value in driver_regions]
    active = [str(value) for value in context["active_regions"]]
    target = str(context["region"])
    if target not in active or any(region not in regions for region in active):
        raise ValueError("external driver omits an active recursive region")
    if driver.ndim != 3 or driver.shape[1] != len(HORIZONS) or driver.shape[2] != len(regions):
        raise ValueError("external driver path shape is invalid")
    n_paths = int(driver.shape[0])
    positions = {region: index for index, region in enumerate(regions)}
    for tau in quantiles:
        beta = np.asarray(beta_draws[float(tau)], dtype=float)
        if beta.ndim != 2 or beta.shape[0] != n_paths:
            raise ValueError("beta path count disagrees with the external driver")

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
    if uniforms is None:
        uniforms = stratified_uniforms(n_paths, len(HORIZONS), seed)
    uniforms = np.asarray(uniforms, dtype=float)
    if uniforms.shape != (n_paths, len(HORIZONS)):
        raise ValueError("recursive quantile uniforms have invalid dimensions")
    samples = np.empty((n_paths, len(HORIZONS)), dtype=float)
    crossing_count = 0.0
    crossing_cells = 0
    rearrangement_sum = 0.0
    rearrangement_cells = 0
    rearrangement_max = 0.0

    for horizon_index in range(len(HORIZONS)):
        state = reservoir_output(states, context["reservoir_config"])
        lead = np.asarray(context["lead_features"][origin_index, horizon_index], dtype=float)
        rows = build_readout_rows(
            state,
            np.repeat(lead[None, :], n_paths, axis=0),
            np.repeat(basis[horizon_index : horizon_index + 1], n_paths, axis=0),
            readout_mode,
        )
        conditional = conditional_quantile_paths(rows, beta_draws, quantiles)
        ordered, diagnostics = rearrange_quantile_curves(conditional)
        samples[:, horizon_index] = interpolate_quantile_curves(
            ordered, quantiles, uniforms[:, horizon_index]
        )
        crossing_count += diagnostics["pre_rearrangement_crossing_rate"] * n_paths * (len(quantiles) - 1)
        crossing_cells += n_paths * (len(quantiles) - 1)
        rearrangement_sum += diagnostics["rearrangement_mean_abs"] * conditional.size
        rearrangement_cells += conditional.size
        rearrangement_max = max(rearrangement_max, diagnostics["rearrangement_max_abs"])

        if horizon_index + 1 < len(HORIZONS):
            exogenous = {
                source: np.asarray(context["raw_lead"][source][origin_index, horizon_index], dtype=float)
                for source in active
            }
            panel = {
                source: (
                    samples[:, horizon_index]
                    if source == target
                    else driver[:, horizon_index, positions[source]]
                )
                for source in active
            }
            transition = recursive_transition_features(
                target,
                context["spec"],
                panel,
                exogenous,
                context["lag_columns"],
                context["lead_columns"],
                context["input_regions"],
            )
            states = reservoir_step(states, transition, context["reservoir"], context["reservoir_config"])

    marginal = np.quantile(samples, np.asarray(quantiles, dtype=float), axis=0, method="linear")
    return {
        "prediction": marginal,
        "samples": samples,
        "pre_rearrangement_crossing_rate": float(crossing_count / crossing_cells),
        "rearrangement_mean_abs": float(rearrangement_sum / rearrangement_cells),
        "rearrangement_max_abs": float(rearrangement_max),
        "tail_rule": "winsorize_uniforms_to_fitted_0p10_0p90_grid",
        "readout_mode": str(readout_mode),
        "seed": int(seed),
        "test_opened": False,
    }
