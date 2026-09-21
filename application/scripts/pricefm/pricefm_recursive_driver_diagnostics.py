"""No-refit recursive-driver diagnostics for the PriceFM application."""

from __future__ import annotations

from typing import Any, Mapping, Sequence

import numpy as np

from pricefm_desn_adapter import horizon_features
from pricefm_recursive_normal import (
    HORIZONS,
    reservoir_output,
    reservoir_step,
    recursive_transition_features,
)
from pricefm_recursive_quantile import QUANTILES
from pricefm_recursive_quantile_marginal import (
    conditional_quantile_paths,
    interpolate_quantile_curves,
    rearrange_quantile_curves,
    stratified_uniforms,
)


ORACLE_LAMBDAS = (0.0, 0.25, 0.50, 0.75, 1.0)
TARGET_MODES = ("self", "oracle_bridge", "external")


def oracle_bridge(
    truth: np.ndarray,
    self_driver: np.ndarray,
    lambda_value: float,
) -> np.ndarray:
    """Interpolate from exact truth to the paired self-recursive driver."""

    observed = np.asarray(truth, dtype=float)
    generated = np.asarray(self_driver, dtype=float)
    value = float(lambda_value)
    if observed.ndim == 0:
        observed = np.full(generated.shape, float(observed), dtype=float)
    if observed.shape != generated.shape:
        try:
            observed = np.broadcast_to(observed, generated.shape)
        except ValueError as exc:
            raise ValueError("oracle truth and self driver dimensions disagree") from exc
    if not 0.0 <= value <= 1.0 or not np.isfinite(value):
        raise ValueError("oracle lambda must be finite and inside [0, 1]")
    result = observed + value * (generated - observed)
    if not np.isfinite(result).all():
        raise ValueError("oracle bridge must be finite")
    return np.asarray(result, dtype=float)


def repeat_driver(values: np.ndarray, n_paths: int) -> np.ndarray:
    """Repeat one deterministic horizon path across posterior paths."""

    vector = np.asarray(values, dtype=float)
    if vector.shape != (len(HORIZONS),) or not np.isfinite(vector).all():
        raise ValueError("deterministic driver must contain 96 finite horizons")
    if int(n_paths) < 2:
        raise ValueError("driver diagnostics require at least two paths")
    return np.repeat(vector[None, :], int(n_paths), axis=0)


def quantile_curve_driver_paths(
    curves: np.ndarray,
    n_paths: int,
    seed: int,
    quantiles: Sequence[float] = QUANTILES,
    uniforms: np.ndarray | None = None,
) -> dict[str, Any]:
    """Construct bounded pseudo-paths from horizon-specific quantile curves."""

    values = np.asarray(curves, dtype=float)
    tau = np.asarray(quantiles, dtype=float)
    if values.shape != (len(HORIZONS), tau.size):
        raise ValueError("driver quantile curves must have shape (96, n_quantiles)")
    if not np.isfinite(values).all():
        raise ValueError("driver quantile curves must be finite")
    ordered = np.sort(values, axis=1)
    if uniforms is None:
        uniforms = stratified_uniforms(int(n_paths), len(HORIZONS), int(seed))
    uniforms = np.asarray(uniforms, dtype=float)
    if uniforms.shape != (int(n_paths), len(HORIZONS)):
        raise ValueError("driver uniforms have invalid dimensions")
    paths = np.empty_like(uniforms)
    for horizon_index in range(len(HORIZONS)):
        horizon_curves = np.repeat(
            ordered[horizon_index : horizon_index + 1], int(n_paths), axis=0
        )
        paths[:, horizon_index] = interpolate_quantile_curves(
            horizon_curves, tau, uniforms[:, horizon_index]
        )
    crossing = values[:, :-1] > values[:, 1:]
    return {
        "paths": paths,
        "pre_rearrangement_crossing_rate": float(np.mean(crossing)),
        "rearrangement_mean_abs": float(np.mean(np.abs(ordered - values))),
        "tail_rule": "winsorize_uniforms_to_fitted_0p10_0p90_grid",
        "rank_coupling": "shared_cross_region_rank_independent_horizon",
    }


def state_support(states: np.ndarray) -> dict[str, np.ndarray | float | int]:
    """Summarize teacher-forced training states for rollout support checks."""

    values = np.asarray(states, dtype=float)
    if values.ndim != 2 or values.shape[0] < 2 or values.shape[1] < 1:
        raise ValueError("training states must be a non-empty two-dimensional array")
    if not np.isfinite(values).all():
        raise ValueError("training states must be finite")
    median = np.median(values, axis=0)
    mad = np.median(np.abs(values - median), axis=0) * 1.4826
    fallback = np.std(values, axis=0, ddof=0)
    scale = np.where(mad > 1e-10, mad, np.where(fallback > 1e-10, fallback, 1.0))
    norms = np.linalg.norm(values, axis=1)
    return {
        "lower": np.quantile(values, 0.01, axis=0),
        "upper": np.quantile(values, 0.99, axis=0),
        "median": median,
        "scale": scale,
        "norm_p99": float(np.quantile(norms, 0.99)),
        "n_training_states": int(values.shape[0]),
        "state_dim": int(values.shape[1]),
    }


def summarize_state(
    states: np.ndarray,
    support: Mapping[str, Any] | None,
    design: np.ndarray | None = None,
    direct_design: np.ndarray | None = None,
) -> dict[str, float]:
    """Summarize one horizon of recursive state paths."""

    values = np.asarray(states, dtype=float)
    if values.ndim != 2 or not np.isfinite(values).all():
        raise ValueError("recursive states must be a finite matrix")
    norms = np.linalg.norm(values, axis=1)
    result = {
        "state_norm_mean": float(np.mean(norms)),
        "state_norm_p95": float(np.quantile(norms, 0.95)),
        "state_saturation_rate": float(np.mean(np.abs(values) >= 0.99)),
        "state_outside_training_envelope_rate": np.nan,
        "state_component_outside_rate": np.nan,
        "state_robust_distance_mean": np.nan,
        "state_robust_distance_p95": np.nan,
        "direct_design_distance_mean": np.nan,
        "direct_design_distance_p95": np.nan,
    }
    if support is not None:
        lower = np.asarray(support["lower"], dtype=float)
        upper = np.asarray(support["upper"], dtype=float)
        median = np.asarray(support["median"], dtype=float)
        scale = np.asarray(support["scale"], dtype=float)
        if any(item.shape != (values.shape[1],) for item in (lower, upper, median, scale)):
            raise ValueError("training support dimension disagrees with recursive state")
        outside = (values < lower) | (values > upper)
        distance = np.sqrt(np.mean(((values - median) / scale) ** 2, axis=1))
        result.update({
            "state_outside_training_envelope_rate": float(np.mean(np.any(outside, axis=1))),
            "state_component_outside_rate": float(np.mean(outside)),
            "state_robust_distance_mean": float(np.mean(distance)),
            "state_robust_distance_p95": float(np.quantile(distance, 0.95)),
        })
    if design is not None and direct_design is not None:
        rows = np.asarray(design, dtype=float)
        reference = np.asarray(direct_design, dtype=float)
        if reference.ndim != 1 or rows.shape[1] != reference.size:
            raise ValueError("direct and recursive design dimensions disagree")
        distance = np.sqrt(np.mean((rows - reference[None, :]) ** 2, axis=1))
        result.update({
            "direct_design_distance_mean": float(np.mean(distance)),
            "direct_design_distance_p95": float(np.quantile(distance, 0.95)),
        })
    return result


def recursive_quantile_driver_forecast(
    context: Mapping[str, Any],
    external_panel: Mapping[str, np.ndarray],
    origin_index: int,
    beta_draws: Mapping[float, np.ndarray],
    seed: int,
    target_mode: str = "self",
    target_truth: np.ndarray | None = None,
    oracle_lambda: float | None = None,
    target_external: np.ndarray | None = None,
    support: Mapping[str, Any] | None = None,
    direct_design: np.ndarray | None = None,
    uniforms: np.ndarray | None = None,
    quantiles: Sequence[float] = QUANTILES,
) -> dict[str, Any]:
    """Forecast Q-DESN quantiles while varying only future endogenous drivers."""

    mode = str(target_mode)
    if mode not in TARGET_MODES:
        raise ValueError("unsupported target driver mode: {}".format(mode))
    active = [str(value) for value in context["active_regions"]]
    target = str(context["region"])
    if target not in active:
        raise ValueError("target region is absent from active regions")
    if not beta_draws:
        raise ValueError("beta draws cannot be empty")
    n_paths = int(np.asarray(next(iter(beta_draws.values()))).shape[0])
    for tau in quantiles:
        beta = np.asarray(beta_draws[float(tau)], dtype=float)
        if beta.ndim != 2 or beta.shape[0] != n_paths:
            raise ValueError("beta path dimensions disagree")
    panel = {}
    for region in active:
        if region == target:
            continue
        if region not in external_panel:
            raise ValueError("external panel omits active neighbor {}".format(region))
        values = np.asarray(external_panel[region], dtype=float)
        if values.shape != (n_paths, len(HORIZONS)) or not np.isfinite(values).all():
            raise ValueError("external neighbor driver has invalid dimensions")
        panel[region] = values
    truth = None if target_truth is None else np.asarray(target_truth, dtype=float)
    if mode == "oracle_bridge":
        if truth is None or truth.shape != (len(HORIZONS),):
            raise ValueError("oracle bridge requires 96 target truths")
        if oracle_lambda is None:
            raise ValueError("oracle bridge requires lambda")
    external_target = None if target_external is None else np.asarray(target_external, dtype=float)
    if mode == "external":
        if external_target is None or external_target.shape != (n_paths, len(HORIZONS)):
            raise ValueError("external target driver has invalid dimensions")
        if not np.isfinite(external_target).all():
            raise ValueError("external target driver must be finite")
    if uniforms is None:
        uniforms = stratified_uniforms(n_paths, len(HORIZONS), int(seed))
    uniforms = np.asarray(uniforms, dtype=float)
    if uniforms.shape != (n_paths, len(HORIZONS)):
        raise ValueError("forecast uniforms have invalid dimensions")
    reference_design = None if direct_design is None else np.asarray(direct_design, dtype=float)
    if reference_design is not None:
        if reference_design.ndim != 2 or reference_design.shape[0] != len(HORIZONS):
            raise ValueError("direct design must contain 96 horizon rows")

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
    samples = np.empty((n_paths, len(HORIZONS)), dtype=float)
    target_driver = np.empty_like(samples)
    diagnostics = []

    for horizon_index in range(len(HORIZONS)):
        state = reservoir_output(states, context["reservoir_config"])
        lead = np.asarray(context["lead_features"][origin_index, horizon_index], dtype=float)
        rows = np.column_stack([
            np.ones(n_paths, dtype=float),
            state,
            np.repeat(lead[None, :], n_paths, axis=0),
            np.repeat(basis[horizon_index : horizon_index + 1], n_paths, axis=0),
        ])
        conditional = conditional_quantile_paths(rows, beta_draws, quantiles)
        ordered, rearrangement = rearrange_quantile_curves(conditional)
        generated = interpolate_quantile_curves(
            ordered, quantiles, uniforms[:, horizon_index]
        )
        samples[:, horizon_index] = generated
        if mode == "self":
            driver = generated
        elif mode == "oracle_bridge":
            driver = oracle_bridge(
                np.repeat(truth[horizon_index], n_paths),
                generated,
                float(oracle_lambda),
            )
        else:
            driver = external_target[:, horizon_index]
        target_driver[:, horizon_index] = driver

        state_row = summarize_state(
            state,
            support,
            design=rows,
            direct_design=(
                None if reference_design is None else reference_design[horizon_index]
            ),
        )
        median_index = int(np.argmin(np.abs(np.asarray(quantiles, dtype=float) - 0.50)))
        conditional_median = ordered[:, median_index]
        neighbor_variances = [
            float(np.var(panel[region][:, horizon_index], ddof=0))
            for region in active
            if region != target
        ]
        state_row.update({
            "horizon": int(horizon_index + 1),
            "pre_rearrangement_crossing_rate": rearrangement[
                "pre_rearrangement_crossing_rate"
            ],
            "rearrangement_mean_abs": rearrangement["rearrangement_mean_abs"],
            "rearrangement_max_abs": rearrangement["rearrangement_max_abs"],
            "conditional_median_variance": float(np.var(conditional_median, ddof=0)),
            "recursive_innovation_variance": float(
                np.var(generated - conditional_median, ddof=0)
            ),
            "target_driver_variance": float(np.var(driver, ddof=0)),
            "neighbor_driver_variance_mean": (
                float(np.mean(neighbor_variances)) if neighbor_variances else 0.0
            ),
            "lower_tail_clipped_rate": float(np.mean(uniforms[:, horizon_index] < quantiles[0])),
            "upper_tail_clipped_rate": float(np.mean(uniforms[:, horizon_index] > quantiles[-1])),
        })
        diagnostics.append(state_row)

        if horizon_index + 1 < len(HORIZONS):
            exogenous = {
                source: np.asarray(
                    context["raw_lead"][source][origin_index, horizon_index], dtype=float
                )
                for source in active
            }
            snapshot = {
                source: (
                    driver if source == target else panel[source][:, horizon_index]
                )
                for source in active
            }
            transition = recursive_transition_features(
                target,
                context["spec"],
                snapshot,
                exogenous,
                context["lag_columns"],
                context["lead_columns"],
                context["input_regions"],
            )
            states = reservoir_step(
                states, transition, context["reservoir"], context["reservoir_config"]
            )

    marginal = np.quantile(
        samples, np.asarray(quantiles, dtype=float), axis=0, method="linear"
    )
    adjacent_rank_correlation = []
    for horizon_index in range(1, len(HORIZONS)):
        adjacent_rank_correlation.append(
            float(np.corrcoef(uniforms[:, horizon_index - 1], uniforms[:, horizon_index])[0, 1])
        )
    return {
        "prediction": marginal,
        "samples": samples,
        "target_driver": target_driver,
        "diagnostics": diagnostics,
        "uniforms": uniforms,
        "adjacent_uniform_rank_correlation_mean": float(
            np.mean(adjacent_rank_correlation)
        ),
        "target_mode": mode,
        "oracle_lambda": None if oracle_lambda is None else float(oracle_lambda),
        "tail_rule": "winsorize_uniforms_to_fitted_0p10_0p90_grid",
        "test_opened": False,
    }
