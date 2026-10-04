#!/usr/bin/env python3
"""Private R123 reservoir adapter; historical R120/R122 modules stay unchanged."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import sys

import numpy as np
from scipy import sparse

import pricefm_r122_runtime as SUPPORT

_path = Path(__file__).with_name("pricefm_r120_engine.py")
_name = "pricefm_r120_engine_for_r123_connectivity"
_loader = importlib.util.spec_from_file_location(_name, _path)
BASE = importlib.util.module_from_spec(_loader)
sys.modules[_name] = BASE
_loader.loader.exec_module(BASE)
BASE.MAX_EXPLICIT_LAG = 2880
BASE.SOURCE_WINDOW = 3120
BASE.WARMUP_STEPS = 240
_normalize = BASE.normalize_spec
_legacy_reservoir = BASE.make_reservoir
_cache = {}
POLICIES = ("uniform", "coverage", "balanced")
MANDATORY_LAGS = (1, 2, 4, 12, 24, 48, 96, 192, 672, 1344, 2016, 2688, 2880)


def normalize_spec(value):
    spec = _normalize(value)
    spec["input_policy"] = str(value.get("input_policy", "uniform"))
    spec["interlayer_gain"] = float(value.get("interlayer_gain", spec["input_scale"]))
    if spec["input_policy"] not in POLICIES or not np.isfinite(spec["interlayer_gain"]) or spec["interlayer_gain"] <= 0:
        raise ValueError("invalid R123 input policy or interlayer gain")
    if spec["calendar"] != "none" or spec["readout"] != "pure_all_layers":
        raise ValueError("R123 primary experiment requires pure all-layer readout without calendar")
    if spec["depth"] > 8 or 1 + sum(spec["units"]) > 577:
        raise ValueError("R123 bounded readout/depth exceeded")
    for key in ("alpha", "rho", "input_scale", "recurrent_sparsity"):
        if not np.isfinite(spec[key]):
            raise ValueError("nonfinite reservoir parameter")
    return spec


def mandatory_rows(spec, dimension):
    my, mx = int(spec["m_y"]), int(spec["m_x"])
    remainder = int(dimension) - my
    if remainder <= 0 or remainder % (mx + 1):
        raise ValueError("input dimension does not match exogenous lag groups")
    channels = remainder // (mx + 1)
    return [lag - 1 for lag in MANDATORY_LAGS if lag <= my] + list(range(my, my + channels))


def input_matrix(spec, dimension):
    """Fixed fan with guaranteed current-exogenous and named price-lag coverage."""
    my = int(spec["m_y"])
    units = int(spec["units"][0])
    fan = min(int(spec["input_fan_in"]), dimension)
    mandatory = mandatory_rows(spec, dimension)
    if fan < 2 or len(mandatory) > units:
        raise ValueError("coverage contract requires fan>=2 and enough first-layer units")
    # Independent input stream keeps recurrent matrices paired with the legacy control.
    rng = np.random.default_rng(np.random.SeedSequence([int(spec["seed"]), 123]))
    selected = []
    for unit in range(units):
        if spec["input_policy"] == "balanced":
            ex_count = min(max(1, fan // 2), dimension - my)
            price_count = min(fan - ex_count, my)
            ex_count = fan - price_count
            rows = np.r_[rng.choice(my, price_count, replace=False),
                         rng.choice(np.arange(my, dimension), ex_count, replace=False)]
        else:
            rows = rng.choice(dimension, fan, replace=False)
        selected.append(rows.astype(int))
    for unit, row in enumerate(mandatory):
        if row in selected[unit]:
            continue
        # In balanced mode preserve group quotas while reserving a connection.
        slots = np.flatnonzero((selected[unit] < my) == (row < my))
        slot = int(slots[-1]) if len(slots) else len(selected[unit]) - 1
        selected[unit][slot] = row
    rows, columns, weights = [], [], []
    for unit, indices in enumerate(selected):
        if spec["input_policy"] == "balanced":
            price = indices < my
            scale = np.where(price, .5 / max(1, int(price.sum())),
                             .5 / max(1, int((~price).sum()))) ** .5
        else:
            scale = np.full(fan, 1 / np.sqrt(fan))
        values = rng.normal(size=fan) * float(spec["input_scale"]) * scale
        rows.extend(indices.tolist()); columns.extend([unit] * fan); weights.extend(values.tolist())
    return sparse.csr_matrix((weights, (rows, columns)), shape=(dimension, units))


def reservoir_digest(arrays):
    digest = hashlib.sha256()
    for name in sorted(arrays):
        value = arrays[name]; digest.update(name.encode("utf-8"))
        if sparse.issparse(value):
            value = value.tocsr()
            for block in (value.data, value.indices, value.indptr):
                digest.update(block.tobytes())
        else:
            digest.update(np.ascontiguousarray(value).tobytes())
    return digest.hexdigest()


def make_reservoir(value, dimension):
    spec = normalize_spec(value)
    key = BASE.fingerprint(spec), int(dimension)
    if key in _cache:
        return _cache[key]
    legacy, config, audit = _legacy_reservoir(spec, dimension)
    arrays = dict(legacy["arrays"])
    layers = [dict(layer) for layer in legacy["layers"]]
    if spec["input_policy"] != "uniform":
        layers[0]["input"] = input_matrix(spec, dimension)
        arrays["layer1_input"] = layers[0]["input"]
    for index in range(1, spec["depth"]):
        matrix = layers[index]["input"] * (spec["interlayer_gain"] / spec["input_scale"])
        layers[index]["input"] = matrix; arrays[f"layer{index + 1}_input"] = matrix
    digest = reservoir_digest(arrays)
    reservoir = dict(legacy, layers=layers, arrays=arrays, sha256=digest)
    config = dict(config, input_scale=[spec["input_scale"]] + [spec["interlayer_gain"]] * (spec["depth"] - 1))
    reservoir["config"] = config
    degrees = np.diff(layers[0]["input"].tocsr().indptr)
    realized = [dict(row) for row in audit["layers"]]
    for row, layer in zip(realized, layers):
        row["input_nonzero"] = int(layer["input"].nnz if sparse.issparse(layer["input"]) else np.count_nonzero(layer["input"]))
    channels = (dimension - spec["m_y"]) // (spec["m_x"] + 1)
    current = list(range(spec["m_y"], spec["m_y"] + channels))
    audit = dict(audit, layers=realized, reservoir_sha256=digest,
                 input_policy=spec["input_policy"], interlayer_gain=spec["interlayer_gain"],
                 input_row_degrees=degrees.tolist(), current_exogenous_row_degrees=degrees[current].tolist(),
                 mandatory_row_degrees=degrees[mandatory_rows(spec, dimension)].tolist(),
                 missing_current_exogenous_count=int(np.sum(degrees[current] == 0)))
    _cache[key] = reservoir, config, audit
    return _cache[key]


def washout_audit(arrays, spec, indices, tolerance=1e-3):
    indices = np.asarray(indices, dtype=int)
    names = BASE.input_names(spec, arrays.exog_names)
    reservoir, config, _ = make_reservoir(spec, len(names))
    zero = [np.zeros((len(indices), width)) for width in spec["units"]]
    dispersed = [np.full_like(value, .5) for value in zero]
    for relative_time in range(-240, 0):
        transition = BASE.explicit_input(arrays, spec, indices, relative_time)
        zero = BASE.reservoir_step(zero, transition, reservoir, config)
        dispersed = BASE.reservoir_step(dispersed, transition, reservoir, config)
    differences = [float(np.max(np.abs(a - b))) for a, b in zip(zero, dispersed)]
    return {"passed": max(differences) <= tolerance, "maximum_absolute_state_difference": max(differences),
            "layer_differences": differences, "tolerance": tolerance, "warmup_steps": 240}


BASE.normalize_spec = normalize_spec
BASE.make_reservoir = make_reservoir
for _api in ("ExplicitArrays", "QUANTILES", "active_regions", "explicit_arrays", "feature_names",
             "fit_scaled_ridge", "input_names", "load_normal_fit", "load_quantile_fit", "load_windows",
             "prediction_metrics", "recursive_normal_score", "recursive_quantile_forecast",
             "standardize_from_training_origins", "teacher_forced_design", "teacher_forced_statistics",
             "write_stats_packet"):
    globals()[_api] = getattr(BASE, _api)
internal_splits = SUPPORT.internal_splits
contract_support = SUPPORT.contract_support
subset_arrays = SUPPORT.subset_arrays


def marginal_quantile_diagnostic(curves, uniforms, tails="clipped"):
    """Declared quantile-function mixture, not samples of seven AL densities.

    Curves end in seven levels. Sorting repairs crossings (reported separately).
    Clipped tails place endpoint mass; linear tails extrapolate adjacent slopes.
    Neither is an automatically identified predictive distribution.
    """
    curves = np.asarray(curves, dtype=float)
    uniforms = np.asarray(uniforms, dtype=float)
    levels = np.asarray(QUANTILES)
    if curves.shape[-1] != len(levels) or uniforms.shape != curves.shape[:-1]:
        raise ValueError("invalid quantile-mixture dimensions")
    if not np.isfinite(curves).all() or not np.isfinite(uniforms).all() or np.any((uniforms <= 0) | (uniforms >= 1)):
        raise ValueError("invalid quantile-mixture inputs")
    if tails not in ("clipped", "linear"):
        raise ValueError("explicit tail convention required")
    ordered = np.sort(curves, axis=-1)
    flat = ordered.reshape(-1, len(levels)); u = uniforms.reshape(-1)
    slot = np.clip(np.searchsorted(levels, u, side="right") - 1, 0, len(levels) - 2)
    fraction = (u - levels[slot]) / (levels[slot + 1] - levels[slot])
    if tails == "clipped": fraction = np.clip(fraction, 0, 1)
    sample = flat[np.arange(len(u)), slot] + fraction * (flat[np.arange(len(u)), slot + 1] - flat[np.arange(len(u)), slot])
    return sample.reshape(uniforms.shape), {"tail_convention": tails,
        "crossed_curve_fraction": float(np.mean(np.any(np.diff(curves, axis=-1) < 0, axis=-1))),
        "distribution_identified_by_seven_quantiles": False, "selection_authorized": False}


def recursive_operator_diagnostic(arrays, spec, normal_fit, quantile_fits, paths=500, seed=2026092501):
    """No-refit mixture sensitivity on the same Normal histories as the control."""
    spec = normalize_spec(spec)
    if sorted(quantile_fits) != list(QUANTILES) or int(paths) != 500:
        raise ValueError("diagnostic requires seven fitted levels and 500 paths")
    names = input_names(spec, arrays.exog_names)
    reservoir, config, _ = make_reservoir(spec, len(names))
    seed_for = BASE.deterministic_seed
    beta_n = BASE._draw_gaussian(normal_fit["beta_mean"], normal_fit["beta_cov"], paths, seed_for(seed, "normal_beta"))
    rng = np.random.default_rng(seed_for(seed, "normal_sigma"))
    omega = 1 / rng.gamma(shape=normal_fit["omega_shape"], scale=1 / normal_fit["omega_rate"], size=paths)
    beta_q = {q: BASE._draw_gaussian(fit["beta_mean"], fit["beta_cov"], paths,
                                  seed_for(seed, "quantile_beta", q)) for q, fit in quantile_fits.items()}
    shape = (len(arrays.response), 96, len(QUANTILES))
    output = {name: np.empty(shape) for name in ("mean_feature", "path_specific", "normal_driver",
                                                "mixture_clipped_tails", "mixture_linear_tails")}
    crossings = []
    for origin in range(len(arrays.response)):
        states = BASE.initialize_states(arrays, spec, reservoir, config, [origin])
        states = [np.repeat(layer, paths, axis=0) for layer in states]
        repeated = np.repeat(origin, paths); generated = np.empty((paths, 96))
        for horizon in range(96):
            transition = BASE.explicit_input(arrays, spec, repeated, horizon, generated[:, :horizon])
            states = BASE.reservoir_step(states, transition, reservoir, config)
            design = BASE.readout_rows(states, transition, spec["readout"])
            location = np.einsum("sp,sp->s", design, beta_n, optimize=True)
            innovation = np.random.default_rng(seed_for(seed, "innovation", origin, horizon)).standard_normal(paths)
            generated[:, horizon] = location + np.sqrt(omega) * innovation
            output["normal_driver"][origin, horizon] = np.quantile(generated[:, horizon], QUANTILES)
            curves = np.column_stack([np.einsum("sp,sp->s", design, beta_q[q], optimize=True) for q in QUANTILES])
            output["path_specific"][origin, horizon] = curves.mean(axis=0)
            output["mean_feature"][origin, horizon] = [np.mean(beta_q[q] @ design.mean(axis=0)) for q in QUANTILES]
            rng = np.random.default_rng(seed_for(seed, "mixture_uniform", origin, horizon))
            uniforms = rng.uniform(size=paths)
            for tail in ("clipped", "linear"):
                samples, audit = marginal_quantile_diagnostic(curves, uniforms, tail)
                output[f"mixture_{tail}_tails"][origin, horizon] = np.quantile(samples, QUANTILES)
            crossings.append(audit["crossed_curve_fraction"])
    output["truth"] = np.asarray(arrays.response)
    return output, {"mean_draw_curve_crossing_fraction": float(np.mean(crossings)),
                    "quantile_posterior_coupling": "independent_level_variational_draws",
                    "tails_are_sensitivity_conventions_not_identified": True,
                    "selection_authorized": False, "model_refitted": False}
