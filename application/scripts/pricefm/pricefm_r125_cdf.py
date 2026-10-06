"""Explicit diagnostic distributions constructed from seven quantile knots."""
from __future__ import annotations

import numpy as np

LEVELS = np.array([.10, .25, .45, .50, .55, .75, .90])


def curve_support(curves, tails):
    values = np.asarray(curves, dtype=float)
    if values.ndim != 2 or values.shape[1] != len(LEVELS) or not len(values):
        raise ValueError("nonempty path-by-seven quantile curves required")
    if not np.isfinite(values).all() or tails not in ("clipped", "linear"):
        raise ValueError("finite curves and explicit tail convention required")
    ordered = np.sort(values, axis=1)
    if tails == "linear":
        lower = ordered[:, 0] - (ordered[:, 1] - ordered[:, 0]) * LEVELS[0] / (LEVELS[1] - LEVELS[0])
        upper = ordered[:, -1] + (ordered[:, -1] - ordered[:, -2]) * (1 - LEVELS[-1]) / (LEVELS[-1] - LEVELS[-2])
        knots = np.column_stack((lower, ordered, upper))
        probabilities = np.r_[0., LEVELS, 1.]
    else:
        knots, probabilities = ordered, LEVELS
    return knots, probabilities


def pooled_cdf_from_support(points, knots, probabilities, tails):
    """Average normalized CDFs, retaining endpoint atoms and repeated knots."""
    points = np.atleast_1d(np.asarray(points, dtype=float))
    if points.ndim != 1 or not np.isfinite(points).all():
        raise ValueError("finite one-dimensional CDF queries required")
    x = points[:, None]
    result = probabilities[0] * (x >= knots[:, 0])
    for j, mass in enumerate(np.diff(probabilities)):
        lower, upper = knots[:, j], knots[:, j + 1]
        gap = upper - lower
        fraction = np.zeros((len(points), len(knots)))
        np.divide(x - lower, gap, out=fraction, where=gap > 0)
        fraction = np.clip(fraction, 0, 1)
        fraction[:, gap == 0] = x >= upper[gap == 0]
        result = result + mass * fraction
    result = result + (1 - probabilities[-1]) * (x >= knots[:, -1])
    return np.mean(result, axis=1)


def pooled_cdf(points, curves, tails):
    knots, probabilities = curve_support(curves, tails)
    return pooled_cdf_from_support(points, knots, probabilities, tails)


def pooled_quantiles(curves, tails, levels=LEVELS, iterations=44):
    """Generalized inverse of the pooled CDF; no extra outcome Monte Carlo."""
    levels = np.asarray(levels, dtype=float)
    if levels.ndim != 1 or not np.isfinite(levels).all() or np.any((levels <= 0) | (levels >= 1)):
        raise ValueError("interior quantile probabilities required")
    if not 20 <= int(iterations) <= 60:
        raise ValueError("bounded CDF inversion iterations required")
    knots, probabilities = curve_support(curves, tails)
    lo = np.full(len(levels), np.min(knots))
    hi = np.full(len(levels), np.max(knots))
    for _ in range(int(iterations)):
        middle = lo + (hi - lo) / 2
        below = pooled_cdf_from_support(middle, knots, probabilities, tails) < levels
        lo = np.where(below, middle, lo)
        hi = np.where(below, hi, middle)
    return hi, {
        "tail_convention": tails,
        "crossed_draw_curve_fraction": float(np.mean(np.any(np.diff(curves, axis=1) < 0, axis=1))),
        "maximum_inversion_bracket_width": float(np.max(hi - lo)),
        "distribution_identified_by_seven_quantiles": False,
        "crossing_treatment": "explicit_unweighted_knot_sort",
        "uses_AL_working_density": False,
        "diagnostic_only": True,
    }


def origin_positions(count, requested=12):
    if int(count) < int(requested) or not 2 <= int(requested) <= 12:
        raise ValueError("bounded predeclared origin support required")
    return np.unique(np.linspace(0, int(count) - 1, int(requested), dtype=int))


def forecast_diagnostic(runtime, arrays, spec, normal, quantiles, positions, seed, sampler,
                        paths=500, iterations=44, observe=lambda value: None):
    """Causal driver plus separate oracle-state diagnostics; no model fitting."""
    if int(paths) != 500 or sorted(quantiles) != list(LEVELS):
        raise ValueError("frozen seven-level, 500-path diagnostic required")
    positions = np.asarray(positions, dtype=int)
    if len(positions) != len(arrays.response) or np.any(positions < 0) or len(np.unique(positions)) != len(positions):
        raise ValueError("original R124 local positions required for matched seeds")
    engine = runtime.BASE
    spec = runtime.normalize_spec(spec)
    reservoir, config, _ = runtime.make_reservoir(spec, len(runtime.input_names(spec, arrays.exog_names)))
    seed_for = engine.deterministic_seed
    beta_n = sampler(normal["beta_mean"], normal["beta_cov"], paths, seed_for(seed, "normal_beta"))
    rng = np.random.default_rng(seed_for(seed, "normal_sigma"))
    omega = 1 / rng.gamma(shape=normal["omega_shape"], scale=1 / normal["omega_rate"], size=paths)
    beta_q = {q: sampler(fit["beta_mean"], fit["beta_cov"], paths, seed_for(seed, "quantile_beta", q))
              for q, fit in quantiles.items()}
    shape = (len(positions), 96, len(LEVELS))
    output = {name: np.empty(shape) for name in (
        "mean_feature", "path_specific", "normal_driver", "rearranged_path_mean", "cdf_pool_clipped", "cdf_pool_linear",
        "oracle_mean_feature", "oracle_rearranged_mean", "oracle_cdf_clipped", "oracle_cdf_linear")}
    crossings, oracle_crossings, brackets = [], [], []
    for origin, original_position in enumerate(positions):
        observe(dict(origins_finished=origin, origins_total=len(positions)))
        initial = engine.initialize_states(arrays, spec, reservoir, config, [origin])
        states = [np.repeat(layer, paths, axis=0) for layer in initial]
        oracle_states = [layer.copy() for layer in initial]
        generated = np.empty((paths, 96))
        for horizon in range(96):
            transition = engine.explicit_input(arrays, spec, np.repeat(origin, paths), horizon, generated[:, :horizon])
            states = engine.reservoir_step(states, transition, reservoir, config)
            design = engine.readout_rows(states, transition, spec["readout"])
            location = np.einsum("sp,sp->s", design, beta_n, optimize=True)
            innovation = np.random.default_rng(seed_for(seed, "innovation", int(original_position), horizon)).standard_normal(paths)
            generated[:, horizon] = location + np.sqrt(omega) * innovation
            output["normal_driver"][origin, horizon] = np.quantile(generated[:, horizon], LEVELS)
            curves = np.column_stack([np.einsum("sp,sp->s", design, beta_q[q], optimize=True) for q in LEVELS])
            output["path_specific"][origin, horizon] = curves.mean(axis=0)
            output["rearranged_path_mean"][origin, horizon] = np.sort(curves, axis=1).mean(axis=0)
            output["mean_feature"][origin, horizon] = [np.mean(beta_q[q] @ design.mean(axis=0)) for q in LEVELS]
            # Oracle truth is consumed only by this separate diagnostic state.
            oracle_input = engine.explicit_input(arrays, spec, [origin], horizon, arrays.response[origin:origin + 1, :horizon])
            oracle_states = engine.reservoir_step(oracle_states, oracle_input, reservoir, config)
            oracle_design = engine.readout_rows(oracle_states, oracle_input, spec["readout"])[0]
            oracle_curves = np.column_stack([beta_q[q] @ oracle_design for q in LEVELS])
            output["oracle_mean_feature"][origin, horizon] = oracle_curves.mean(axis=0)
            output["oracle_rearranged_mean"][origin, horizon] = np.sort(oracle_curves, axis=1).mean(axis=0)
            for tails in ("clipped", "linear"):
                pooled, audit = pooled_quantiles(curves, tails, iterations=iterations)
                oracle_pooled, oracle_audit = pooled_quantiles(oracle_curves, tails, iterations=iterations)
                output[f"cdf_pool_{tails}"][origin, horizon] = pooled
                output[f"oracle_cdf_{tails}"][origin, horizon] = oracle_pooled
                brackets.extend((audit["maximum_inversion_bracket_width"], oracle_audit["maximum_inversion_bracket_width"]))
            crossings.append(audit["crossed_draw_curve_fraction"])
            oracle_crossings.append(oracle_audit["crossed_draw_curve_fraction"])
    observe(dict(origins_finished=len(positions), origins_total=len(positions)))
    output["truth"] = np.asarray(arrays.response)
    return output, dict(
        mean_draw_curve_crossing_fraction=float(np.mean(crossings)),
        mean_oracle_draw_curve_crossing_fraction=float(np.mean(oracle_crossings)),
        maximum_inversion_bracket_width=float(np.max(brackets)),
        conditional_quantile_coupling="independent_level_VB_draws",
        tail_distributions_identified=False, sigma_posterior_used_for_quantile_pooling=False,
        oracle_diagnostic_only=True, model_refitted=False,
        predictive_mixture_method="generalized_inverse_of_explicit_equal_weight_conditional_CDF_pool")
