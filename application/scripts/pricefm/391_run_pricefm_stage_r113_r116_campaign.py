#!/usr/bin/env python3
"""Atomic Python workers for the PriceFM R113--R116 campaign."""

from __future__ import annotations

import argparse
import ast
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Mapping

import joblib
import numpy as np
import pandas as pd
from scipy import stats

from pricefm_common import load_config, sha256_file, write_json
from pricefm_desn_adapter import load_window
from pricefm_graph import graph_active_regions_for_policy, graph_adj_matrix
from pricefm_recursive_adapter import build_policy_features
from pricefm_recursive_normal import _block, precompute_initial_states
from pricefm_recursive_quantile import (
    QUANTILES,
    causal_teacher_forced_design,
    draw_beta_posterior,
    paired_quantile_prediction,
    recursive_quantile_design,
    write_design,
)
from pricefm_recursive_quantile_marginal import (
    forecast_uniforms,
    recursive_quantile_curve_forecast,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_CAMPAIGN = DATA / "campaigns/pricefm_stage_r113_r116_rolled_state_driver_20260922"
R103 = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916/cases/r103_bg_f1.json"
R103_CASES = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916/cases"
R111B = DATA / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
R97_PROCESSED = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/processed_scoring"


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_fit(campaign: Path, family: str, inner_fold: int) -> tuple[dict[float, np.ndarray], dict[float, np.ndarray]]:
    root = campaign / f"runs/r114_fit/family={family}/inner={inner_fold}"
    terminal = json.loads((root / "terminal.json").read_text())
    if (
        terminal.get("status") != "completed_r114_quantile_family_fit"
        or terminal.get("family") != family
        or int(terminal.get("inner_fold", -1)) != int(inner_fold)
        or terminal.get("test_opened") is not False
    ):
        raise RuntimeError(f"invalid R114 {family} fit for inner fold {inner_fold}")
    means: dict[float, np.ndarray] = {}
    covariances: dict[float, np.ndarray] = {}
    for tau in QUANTILES:
        label = str(tau).replace(".", "p")
        atom = root / f"tau={label}"
        atom_terminal = json.loads((atom / "terminal.json").read_text())
        if not atom_terminal.get("numerically_eligible"):
            raise RuntimeError(f"ineligible R114 atom: {family} inner={inner_fold} tau={tau}")
        p = int(atom_terminal["p"])
        means[float(tau)] = np.fromfile(atom / "beta_mean.bin", dtype="<f8")
        covariances[float(tau)] = np.fromfile(atom / "beta_cov.bin", dtype="<f8").reshape(p, p)
    return means, covariances


def read_quantile_fit(
    root: Path,
    family: str,
    expected_status: str,
    atom_status: str,
) -> tuple[dict[float, np.ndarray], dict[float, np.ndarray]]:
    """Read one complete seven-quantile family fit behind a frozen terminal."""

    terminal = json.loads((root / "terminal.json").read_text())
    if (
        terminal.get("status") != expected_status
        or terminal.get("family") != family
        or terminal.get("test_opened") is not False
        or terminal.get("all_atoms_eligible") is not True
    ):
        raise RuntimeError(f"invalid quantile family fit: {root}")
    means: dict[float, np.ndarray] = {}
    covariances: dict[float, np.ndarray] = {}
    for tau in QUANTILES:
        atom = root / f"tau={str(tau).replace('.', 'p')}"
        atom_terminal = json.loads((atom / "terminal.json").read_text())
        if (
            atom_terminal.get("status") != atom_status
            or atom_terminal.get("numerically_eligible") is not True
            or atom_terminal.get("test_opened") is not False
        ):
            raise RuntimeError(f"invalid quantile atom: {atom}")
        p = int(atom_terminal["p"])
        mean = np.fromfile(atom / "beta_mean.bin", dtype="<f8")
        covariance = np.fromfile(atom / "beta_cov.bin", dtype="<f8").reshape(p, p)
        if mean.size != p or not np.isfinite(mean).all() or not np.isfinite(covariance).all():
            raise RuntimeError(f"nonfinite quantile posterior: {atom}")
        means[float(tau)] = mean
        covariances[float(tau)] = covariance
    return means, covariances


def training_context(case: Mapping[str, Any], spec: Mapping[str, Any] | None = None) -> dict[str, Any]:
    frozen = json.loads(case["spec_json"]) if spec is None else dict(spec)
    all_windows, active = _policy_windows(case, frozen, "train")
    initial = build_policy_features(
        str(frozen["region"]),
        {region: _block(window) for region, window in all_windows.items()},
        frozen["feature_policy"], frozen["spatial"], input_regions=list(graph_adj_matrix()),
    )
    windows = {region: all_windows[region] for region in active}
    fitted = causal_teacher_forced_design(
        windows, frozen, list(graph_adj_matrix()), readout_mode="state_lead_horizon"
    )
    value = {
        "region": str(frozen["region"]), "spec": frozen, "active_regions": active,
        "input_regions": list(graph_adj_matrix()),
        "initial_lag": np.asarray(initial["X_lag"], dtype=float),
        "lead_features": np.asarray(initial["X_lead"], dtype=float),
        "raw_lead": {region: np.asarray(window["X_lead"], dtype=float) for region, window in windows.items()},
        "lag_columns": {region: list(window["lag_cols"]) for region, window in windows.items()},
        "lead_columns": {region: list(window["lead_cols"]) for region, window in windows.items()},
        "truth": np.asarray(windows[str(frozen["region"])]["Y"], dtype=float),
        "anchors": np.asarray(windows[str(frozen["region"])]["anchors"], dtype=str),
        "reservoir": fitted["reservoir"], "reservoir_config": fitted["reservoir_config"],
    }
    value["initial_states"] = precompute_initial_states(value)
    return value


def observed_ranks(y: np.ndarray, curves: np.ndarray) -> np.ndarray:
    response = np.asarray(y, dtype=float)
    values = np.sort(np.asarray(curves, dtype=float), axis=-1)
    if values.shape != response.shape + (len(QUANTILES),):
        raise ValueError("observed-rank dimensions disagree")
    out = np.empty(response.shape, dtype=float)
    tau = np.asarray(QUANTILES, dtype=float)
    for index in np.ndindex(response.shape):
        out[index] = np.interp(response[index], values[index], tau, left=0.05, right=0.95)
    return np.clip(out, 1e-6, 1 - 1e-6)


def sample_crps(samples: np.ndarray, truth: np.ndarray) -> np.ndarray:
    values = np.sort(np.asarray(samples, dtype=float), axis=-1)
    y = np.asarray(truth, dtype=float)
    if values.shape[:-1] != y.shape:
        raise ValueError("CRPS sample and truth dimensions disagree")
    n = values.shape[-1]
    first = np.mean(np.abs(values - y[..., None]), axis=-1)
    weights = 2 * np.arange(1, n + 1, dtype=float) - n - 1
    second = np.sum(values * weights, axis=-1) / (n * n)
    return first - second


def driver_metrics(samples: np.ndarray, truth: np.ndarray, family: str, policy: str, inner_fold: int) -> tuple[dict[str, Any], pd.DataFrame]:
    values = np.asarray(samples, dtype=float)
    y = np.asarray(truth, dtype=float)
    if values.shape != (y.shape[0], 500, 96):
        raise ValueError("R114 driver sample dimensions disagree")
    median = np.quantile(values, 0.5, axis=1)
    lower = np.quantile(values, 0.1, axis=1)
    upper = np.quantile(values, 0.9, axis=1)
    crps = sample_crps(values.transpose(0, 2, 1), y)
    blocks = []
    for start in range(0, 96, 24):
        sl = slice(start, start + 24)
        blocks.append({
            "family": family, "rank_policy": policy, "inner_fold": inner_fold,
            "horizon_block": f"{start + 1}-{start + 24}",
            "MAE_scaled": float(np.mean(np.abs(median[:, sl] - y[:, sl]))),
            "RMSE_scaled": float(np.sqrt(np.mean((median[:, sl] - y[:, sl]) ** 2))),
            "CRPS_scaled": float(np.mean(crps[:, sl])),
            "coverage_10_90": float(np.mean((y[:, sl] >= lower[:, sl]) & (y[:, sl] <= upper[:, sl]))),
        })
    summary = {
        "family": family, "rank_policy": policy, "inner_fold": inner_fold,
        "n_origins": int(y.shape[0]), "posterior_paths": 500,
        "MAE_scaled": float(np.mean(np.abs(median - y))),
        "RMSE_scaled": float(np.sqrt(np.mean((median - y) ** 2))),
        "bias_scaled": float(np.mean(median - y)),
        "CRPS_scaled": float(np.mean(crps)),
        "coverage_10_90": float(np.mean((y >= lower) & (y <= upper))),
        "width_10_90_scaled": float(np.mean(upper - lower)),
        "late_CRPS_scaled": float(np.mean(crps[:, 48:])),
        "selection_split": "BG_fold1_training_nested_temporal_only",
        "test_opened": False,
    }
    return summary, pd.DataFrame(blocks)


def score_r114(campaign: Path, family: str, inner_fold: int) -> dict[str, Any]:
    output = campaign / f"runs/r114_score/family={family}/inner={inner_fold}"
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        existing = json.loads(terminal_path.read_text())
        if existing.get("status") == "completed_r114_driver_score":
            return existing
    case = json.loads(R103.read_text())
    context = training_context(case)
    design_meta = json.loads((Path(case["design_dir"]) / "design.json").read_text())
    n, p = int(design_meta["n"]), int(design_meta["p"])
    x = np.fromfile(Path(case["design_dir"]) / "X.bin", dtype="<f8").reshape(n, p)
    y = np.fromfile(Path(case["design_dir"]) / "y.bin", dtype="<f8")
    split = np.load(campaign / f"splits/inner_fold_{inner_fold}.npz")
    train_index = np.asarray(split["train_index"], dtype=int)
    validation_origins = np.asarray(split["validation_origin_id"], dtype=int)
    means, covariances = read_fit(campaign, family, inner_fold)
    beta_draws = {
        tau: draw_beta_posterior(
            means[tau], covariances[tau], 500,
            2026092300 + 100 * (family == "exal") + 10 * inner_fold + index,
        )
        for index, tau in enumerate(QUANTILES)
    }
    n_origins = len(context["anchors"])
    train_origin_counts = np.bincount(train_index % n_origins, minlength=n_origins)
    complete_train_origins = np.where(train_origin_counts == 96)[0]
    if len(complete_train_origins) < 2:
        raise RuntimeError("R114 lacks complete training trajectories for rank coupling")
    curves = np.empty((len(complete_train_origins), 96, len(QUANTILES)), dtype=float)
    response = np.empty((len(complete_train_origins), 96), dtype=float)
    for h in range(96):
        idx = h * n_origins + complete_train_origins
        response[:, h] = y[idx]
        for q, tau in enumerate(QUANTILES):
            curves[:, h, q] = x[idx] @ means[tau]
    ranks = observed_ranks(response, curves)
    policies = {
        "independent_stratified": None,
        "training_block_rank_6": 6,
        "training_block_rank_12": 12,
        "training_block_rank_24": 24,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        summary_rows = []
        horizon_rows = []
        for policy, block_length in policies.items():
            all_samples = np.empty((len(validation_origins), 500, 96), dtype=np.float32)
            for local, origin_id in enumerate(validation_origins):
                uniforms = forecast_uniforms(
                    "independent_stratified" if block_length is None else "training_block_rank",
                    500, 96, 2026092400 + 100 * inner_fold + int(origin_id),
                    training_ranks=None if block_length is None else ranks,
                    block_length=block_length,
                )
                external = np.zeros((500, 96, 1), dtype=float)
                result = recursive_quantile_curve_forecast(
                    context, external, int(origin_id), ["BG"], beta_draws,
                    seed=2026092400 + int(origin_id), uniforms=uniforms,
                )
                all_samples[local] = result["samples"].astype(np.float32)
            truth = np.asarray(context["truth"], dtype=float)[validation_origins]
            summary, horizons = driver_metrics(all_samples, truth, family, policy, inner_fold)
            summary_rows.append(summary)
            horizon_rows.append(horizons)
            np.savez_compressed(
                temporary / f"driver_paths__{policy}.npz",
                samples=all_samples, origin_id=validation_origins,
                truth_scaled=truth, training_ranks=ranks,
            )
        pd.DataFrame(summary_rows).to_csv(temporary / "driver_metrics.csv", index=False)
        pd.concat(horizon_rows, ignore_index=True).to_csv(temporary / "driver_horizon_metrics.csv", index=False)
        artifacts = [
            {"path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
            for path in sorted(temporary.iterdir())
        ]
        terminal = {
            "stage": "R114", "status": "completed_r114_driver_score",
            "family": family, "inner_fold": inner_fold,
            "policy_count": 4, "posterior_paths": 500,
            "selection_split": "BG_fold1_training_nested_temporal_only",
            "artifacts": artifacts, "test_opened": False,
            "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def parse_value(value: Any, default: Any = None) -> Any:
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return default
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return ast.literal_eval(value)


def load_normal_paths(campaign: Path, region: str, inner_fold: int) -> tuple[np.ndarray, np.ndarray]:
    root = campaign / f"runs/r114_normal_driver/region={region}/inner={inner_fold}"
    terminal = json.loads((root / "terminal.json").read_text())
    if terminal.get("status") != "completed_r114_normal_driver" or terminal.get("test_opened") is not False:
        raise RuntimeError(f"invalid R114 Normal paths for {region} inner {inner_fold}")
    rows = pd.read_csv(root / "evaluation_rows.csv")
    values = np.fromfile(root / "prediction_paths_scaled.bin", dtype="<f8").reshape(len(rows), 500)
    origin_ids = np.sort(rows.origin_id.unique().astype(int))
    ordered = rows.sort_values(["origin_id", "horizon"], kind="mergesort")
    if not np.array_equal(ordered.index.to_numpy(), np.arange(len(rows))):
        values = values[ordered.index.to_numpy()]
        rows = ordered.reset_index(drop=True)
    cube = values.reshape(len(origin_ids), 96, 500).transpose(2, 0, 1)
    return cube, origin_ids


def fit_scaled_ridge(x: np.ndarray, y: np.ndarray) -> dict[str, np.ndarray | float]:
    x = np.asarray(x, dtype=float); y = np.asarray(y, dtype=float)
    precision0 = np.full(x.shape[1], 1e-4, dtype=float)
    precision0[0] = 1e-6
    precision = x.T @ x + np.diag(precision0)
    inverse = np.linalg.inv(precision)
    mean = inverse @ (x.T @ y)
    shape = 2.0 + len(y) / 2.0
    rate = max(1.0 + 0.5 * (y @ y - mean @ precision @ mean), np.finfo(float).eps)
    return {"mean": mean, "precision_inverse": inverse, "shape": shape, "rate": rate}


def ridge_quantiles(fit: Mapping[str, Any], x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    location = x @ np.asarray(fit["mean"])
    leverage = np.einsum("ij,jk,ik->i", x, np.asarray(fit["precision_inverse"]), x)
    scale = np.sqrt(float(fit["rate"]) / float(fit["shape"]) * (1.0 + leverage))
    return np.column_stack([
        location + scale * stats.t.ppf(tau, df=2.0 * float(fit["shape"]))
        for tau in QUANTILES
    ])


def aql(y: np.ndarray, prediction: np.ndarray) -> float:
    error = np.asarray(y)[:, None] - np.asarray(prediction)
    tau = np.asarray(QUANTILES)[None, :]
    return float(np.mean(np.maximum(tau * error, (tau - 1.0) * error)))


def candidate_spec(row: pd.Series) -> dict[str, Any]:
    return {
        "region": "BG", "feature_policy": str(row.feature_policy),
        "lag_window": int(row.lag_window), "depth": int(row.depth),
        "units": [int(value) for value in parse_value(row.units, [])],
        "alpha": float(row.alpha), "rho": float(row.rho),
        "input_scale": float(row.input_scale), "state_output": str(row.state_output),
        "seed": int(row.seed), "spatial": dict(parse_value(row.spatial, {}) or {}),
        "tau0": 1e-4,
    }


def r115_ridge(campaign: Path, candidate_id: str) -> dict[str, Any]:
    output = campaign / f"runs/r115_ridge/candidate={candidate_id}"
    if (output / "terminal.json").is_file():
        existing = json.loads((output / "terminal.json").read_text())
        if existing.get("status") == "completed_r115_ridge_candidate":
            return existing
    selected = json.loads((campaign / "r114_selected_driver.json").read_text())
    bank = pd.read_csv(campaign / "r115_candidate_bank.csv")
    matches = bank[bank.candidate_id.astype(str).eq(str(candidate_id))]
    if len(matches) != 1:
        raise RuntimeError(f"R115 candidate identity is not unique: {candidate_id}")
    spec = candidate_spec(matches.iloc[0])
    case = json.loads(R103.read_text())
    data_config = load_config(case["data_config_path"])
    windows, active = _policy_windows(case, spec, "train")
    scaler_path = Path(data_config["pricefm"]["processed_dir"]) / "scalers/fold_1/per_region_separate_xy_scalers.joblib"
    scale = float(np.asarray(joblib.load(scaler_path)["BG"]["y_scaler"].scale_).reshape(-1)[0])
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        metric_rows = []
        for readout_mode in ("state_horizon", "state_only"):
            fitted = causal_teacher_forced_design(
                windows, spec, list(graph_adj_matrix()), readout_mode=readout_mode
            )
            context = training_context(case, spec)
            for inner_fold in (1, 2, 3):
                split = np.load(campaign / f"splits/inner_fold_{inner_fold}.npz")
                train_index = np.asarray(split["train_index"], dtype=int)
                validation_origins = np.asarray(split["validation_origin_id"], dtype=int)
                if selected["family"] == "normal_rhs":
                    target_samples, target_origins = load_normal_paths(
                        campaign, "BG", inner_fold
                    )
                else:
                    selected_root = campaign / f"runs/r114_score/family={selected['family']}/inner={inner_fold}"
                    target_archive = np.load(selected_root / f"driver_paths__{selected['rank_policy']}.npz")
                    target_samples = np.asarray(target_archive["samples"], dtype=float).transpose(1, 0, 2)
                    target_origins = np.asarray(target_archive["origin_id"], dtype=int)
                if not np.array_equal(target_origins, validation_origins):
                    raise RuntimeError("R115 selected target-driver origins changed")
                cubes = {"BG": target_samples}
                for region in active:
                    if region == "BG":
                        continue
                    cube, origin_ids = load_normal_paths(campaign, region, inner_fold)
                    if not np.array_equal(origin_ids, validation_origins):
                        raise RuntimeError("R115 neighbor-driver origins changed")
                    cubes[region] = cube
                driver = np.stack([cubes[region] for region in active], axis=-1)
                n_val = len(validation_origins)
                recursive = np.empty((n_val, 96, fitted["p"]), dtype=float)
                for local, origin_id in enumerate(validation_origins):
                    rows = recursive_quantile_design(
                        context, driver[:, local], int(origin_id), active,
                        readout_mode=readout_mode,
                    )
                    recursive[local] = rows.mean(axis=0)
                x_eval = recursive.transpose(1, 0, 2).reshape(-1, fitted["p"])
                y_eval = np.asarray(context["truth"])[validation_origins].T.reshape(-1)
                x_train = np.asarray(fitted["X"])[train_index]
                y_train = np.asarray(fitted["y"])[train_index]
                ridge = fit_scaled_ridge(x_train, y_train)
                prediction = ridge_quantiles(ridge, x_eval)
                horizon = np.repeat(np.arange(1, 97), n_val)
                late = horizon >= 49
                metric_rows.append({
                    "candidate_id": candidate_id, "readout_mode": readout_mode,
                    "inner_fold": inner_fold, "p": fitted["p"],
                    "AQL_scaled": aql(y_eval, prediction),
                    "AQL_original": aql(y_eval, prediction) * scale,
                    "late_AQL_scaled": aql(y_eval[late], prediction[late]),
                    "coverage_10_90": float(np.mean((y_eval >= prediction[:, 0]) & (y_eval <= prediction[:, -1]))),
                    "width_10_90_scaled": float(np.mean(prediction[:, -1] - prediction[:, 0])),
                    "selection_split": "BG_fold1_training_nested_temporal_only",
                    "test_opened": False,
                })
                np.savez_compressed(
                    temporary / f"stats__{readout_mode}__inner{inner_fold}.npz",
                    XtX=x_train.T @ x_train, Xty=x_train.T @ y_train,
                    yty=np.asarray([y_train @ y_train]), n=np.asarray([len(y_train)]),
                    X_eval=x_eval.astype(np.float32), y_eval=y_eval.astype(np.float32),
                    horizon=horizon, p=np.asarray([fitted["p"]]),
                )
        pd.DataFrame(metric_rows).to_csv(temporary / "ridge_metrics.csv", index=False)
        terminal = {
            "stage": "R115", "status": "completed_r115_ridge_candidate",
            "candidate_id": candidate_id, "metric_rows": len(metric_rows),
            "driver_family": selected["family"], "rank_policy": selected["rank_policy"],
            "selection_split": "BG_fold1_training_nested_temporal_only",
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def selected_r115_spec(campaign: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    selected = json.loads((campaign / "r115_selected_no_bypass.json").read_text())
    bank = pd.read_csv(campaign / "r115_candidate_bank.csv")
    row = bank[bank.candidate_id.astype(str).eq(str(selected["candidate_id"]))]
    if len(row) != 1 or selected["readout_mode"] not in {"state_horizon", "state_only"}:
        raise RuntimeError("R115 selected no-bypass contract is invalid")
    spec = candidate_spec(row.iloc[0])
    spec["tau0"] = float(selected["tau0"])
    return selected, spec


def _policy_windows(case: Mapping[str, Any], spec: Mapping[str, Any], split: str) -> tuple[dict[str, Any], list[str]]:
    source = load_config(case["data_config_path"])
    data_config = dict(source)
    data_config["pricefm"] = dict(source["pricefm"])
    data_config["pricefm"]["windows"] = dict(source["pricefm"]["windows"])
    data_config["pricefm"]["processed_dir"] = str(R97_PROCESSED)
    data_config["pricefm"]["windows"]["lag_window"] = int(spec["lag_window"])
    pool = {
        region: load_window(data_config, int(case["fold"]), region, split)
        for region in ("BG", "GR", "RO")
    }
    policy = build_policy_features(
        "BG", {region: _block(window) for region, window in pool.items()},
        spec["feature_policy"], spec["spatial"], input_regions=list(graph_adj_matrix()),
    )
    active = [str(value) for value in policy["feature_policy_manifest"]["active_regions"]]
    if any(region not in pool for region in active):
        raise RuntimeError(f"R116 BG candidate requires an unsupported active region: {active}")
    return {region: pool[region] for region in active}, active


def forecast_context(
    case: Mapping[str, Any],
    spec: Mapping[str, Any],
    fitted: Mapping[str, Any],
    split: str = "val",
) -> dict[str, Any]:
    windows, active = _policy_windows(case, spec, split)
    initial = build_policy_features(
        "BG", {region: _block(window) for region, window in windows.items()},
        spec["feature_policy"], spec["spatial"], input_regions=list(graph_adj_matrix()),
    )
    value = {
        "region": "BG", "spec": dict(spec), "active_regions": active,
        "input_regions": list(graph_adj_matrix()),
        "initial_lag": np.asarray(initial["X_lag"], dtype=float),
        "lead_features": np.asarray(initial["X_lead"], dtype=float),
        "raw_lead": {region: np.asarray(window["X_lead"], dtype=float) for region, window in windows.items()},
        "lag_columns": {region: list(window["lag_cols"]) for region, window in windows.items()},
        "lead_columns": {region: list(window["lead_cols"]) for region, window in windows.items()},
        "truth": np.asarray(windows["BG"]["Y"], dtype=float),
        "anchors": np.asarray(windows["BG"]["anchors"], dtype=str),
        "reservoir": fitted["reservoir"], "reservoir_config": fitted["reservoir_config"],
    }
    value["initial_states"] = precompute_initial_states(value)
    return value


def prepare_r116_family_design(campaign: Path) -> dict[str, Any]:
    output = campaign / "runs/r116_family_design"
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        existing = json.loads(terminal_path.read_text())
        if existing.get("status") == "completed_r116_family_design":
            return existing
    selected, spec = selected_r115_spec(campaign)
    case = json.loads(R103.read_text())
    windows, _ = _policy_windows(case, spec, "train")
    fitted = causal_teacher_forced_design(
        windows, spec, list(graph_adj_matrix()), readout_mode=selected["readout_mode"]
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        write_design(temporary / "design", fitted)
        evaluations = []
        for inner in (1, 2, 3):
            stats_root = (
                campaign / "r115_rhs_stats" / f"candidate={selected['candidate_id']}"
                / selected["readout_mode"] / f"inner={inner}"
            )
            manifest = json.loads((stats_root / "manifest.json").read_text())
            p, n_eval = int(manifest["p"]), int(manifest["n_eval"])
            if p != int(fitted["p"]):
                raise RuntimeError("R116 family design dimension changed from R115")
            x_eval = np.fromfile(stats_root / "X_eval.bin", dtype="<f8").reshape(n_eval, p)
            y_eval = np.fromfile(stats_root / "y_eval.bin", dtype="<f8")
            path = temporary / f"evaluation_inner_{inner}.npz"
            np.savez_compressed(path, X_eval=x_eval, y_eval=y_eval)
            evaluations.append({
                "inner_fold": inner, "path": str((output / path.name).resolve()),
                "sha256": sha256_file(path), "n_eval": n_eval, "p": p,
            })
        write_json(temporary / "selected_spec.json", {
            "candidate_id": selected["candidate_id"], "readout_mode": selected["readout_mode"],
            "tau0": selected["tau0"], "spec": spec, "test_opened": False,
        })
        terminal = {
            "stage": "R116", "status": "completed_r116_family_design",
            "candidate_id": selected["candidate_id"], "readout_mode": selected["readout_mode"],
            "tau0": selected["tau0"], "n": int(fitted["n"]), "p": int(fitted["p"]),
            "evaluations": evaluations, "selection_split": "BG_fold1_training_nested_temporal_only",
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def score_r116_family(campaign: Path, family: str, inner_fold: int) -> dict[str, Any]:
    output = campaign / f"runs/r116_family_score/family={family}/inner={inner_fold}"
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        existing = json.loads(terminal_path.read_text())
        if existing.get("status") == "completed_r116_family_score":
            return existing
    fit_root = campaign / f"runs/r116_family_fit/family={family}/inner={inner_fold}"
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        eligible = True
        reason = "complete_seven_quantile_fit"
        try:
            means, _ = read_quantile_fit(
                fit_root, family, "completed_r116_quantile_family_fit",
                "completed_r116_quantile_atom",
            )
        except (OSError, KeyError, ValueError, RuntimeError, json.JSONDecodeError) as error:
            eligible = False
            reason = f"ineligible_fit:{type(error).__name__}"
            means = {}
        archive = np.load(campaign / f"runs/r116_family_design/evaluation_inner_{inner_fold}.npz")
        x_eval = np.asarray(archive["X_eval"], dtype=float)
        y_eval = np.asarray(archive["y_eval"], dtype=float)
        if eligible:
            prediction = np.column_stack([x_eval @ means[float(tau)] for tau in QUANTILES])
            horizon = np.repeat(np.arange(1, 97), len(y_eval) // 96)
            loss = np.maximum(
                np.asarray(QUANTILES)[None, :] * (y_eval[:, None] - prediction),
                (np.asarray(QUANTILES)[None, :] - 1) * (y_eval[:, None] - prediction),
            )
            metric = {
                "family": family, "inner_fold": inner_fold, "eligible": True,
                "AQL_scaled": float(loss.mean()),
                "late_AQL_scaled": float(loss[horizon >= 49].mean()),
                "coverage_10_90": float(np.mean((y_eval >= prediction[:, 0]) & (y_eval <= prediction[:, -1]))),
                "width_10_90_scaled": float(np.mean(prediction[:, -1] - prediction[:, 0])),
                "crossing_rate": float(np.mean(prediction[:, :-1] > prediction[:, 1:])),
                "reason": reason, "test_opened": False,
            }
        else:
            metric = {
                "family": family, "inner_fold": inner_fold, "eligible": False,
                "AQL_scaled": np.nan, "late_AQL_scaled": np.nan,
                "coverage_10_90": np.nan, "width_10_90_scaled": np.nan,
                "crossing_rate": np.nan, "reason": reason, "test_opened": False,
            }
        pd.DataFrame([metric]).to_csv(temporary / "metrics.csv", index=False)
        terminal = {
            "stage": "R116", "status": "completed_r116_family_score",
            "family": family, "inner_fold": inner_fold, "eligible": eligible,
            "reason": reason, "selection_split": "BG_fold1_training_nested_temporal_only",
            "test_opened": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def prepare_r116_outer_design(campaign: Path, fold: int) -> dict[str, Any]:
    output = campaign / f"runs/r116_outer_design/fold={fold}"
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        existing = json.loads(terminal_path.read_text())
        if existing.get("status") == "completed_r116_outer_design":
            return existing
    selected, selected_spec = selected_r115_spec(campaign)
    case_path = R103_CASES / f"r103_bg_f{fold}.json"
    case = json.loads(case_path.read_text())
    current_spec = json.loads(case["spec_json"])
    designs = {
        "current_lead": (current_spec, "state_lead_horizon"),
        "selected_no_bypass": (selected_spec, selected["readout_mode"]),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        records = []
        for name, (spec, readout_mode) in designs.items():
            windows, _ = _policy_windows(case, spec, "train")
            fitted = causal_teacher_forced_design(
                windows, spec, list(graph_adj_matrix()), readout_mode=readout_mode
            )
            design_dir = temporary / name / "design"
            write_design(design_dir, fitted)
            split_path = temporary / name / "full_training_split.csv"
            pd.DataFrame({
                "split": np.repeat("train", int(fitted["n"])),
                "design_index_zero_based": np.arange(int(fitted["n"]), dtype=np.int64),
            }).to_csv(split_path, index=False)
            records.append({
                "readout_id": name, "readout_mode": readout_mode,
                "design_dir": str((output / name / "design").resolve()),
                "split_csv_path": str((output / name / split_path.name).resolve()),
                "n": int(fitted["n"]), "p": int(fitted["p"]),
            })
        pd.DataFrame(records).to_csv(temporary / "design_manifest.csv", index=False)
        write_json(temporary / "selected_contract.json", {
            "fold": fold, "selected": selected, "selected_spec": selected_spec,
            "current_spec": current_spec, "case_path": str(case_path.resolve()),
            "case_sha256": sha256_file(case_path), "test_opened": False,
        })
        terminal = {
            "stage": "R116", "status": "completed_r116_outer_design", "fold": fold,
            "design_count": 2, "selection_frozen_before_outer_validation": True,
            "evaluation_split": "outer_validation_only", "test_opened": False,
            "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def load_normal_region_paths(region: str, fold: int, anchors: np.ndarray) -> np.ndarray:
    case = json.loads((R103_CASES / f"r103_{region.lower()}_f{fold}.json").read_text())
    surface = Path(case["normal_driver_surface"])
    terminal = json.loads((surface / "terminal.json").read_text())
    if (
        terminal.get("status") != "completed_recursive_validation_surface"
        or terminal.get("test_opened") is not False
    ):
        raise RuntimeError(f"invalid frozen Normal driver surface: {surface}")
    values = np.empty((500, len(anchors), 96), dtype=float)
    for origin_index, anchor in enumerate(anchors):
        path = surface / "origins" / f"origin_{origin_index:04d}.npz"
        marker = json.loads(path.with_suffix(".json").read_text())
        if marker.get("status") != "completed_recursive_origin" or marker.get("sha256") != sha256_file(path):
            raise RuntimeError(f"invalid Normal driver origin: {path}")
        with np.load(path, allow_pickle=False) as archive:
            regions = [str(value) for value in archive["regions"].tolist()]
            stored_anchor = str(archive["anchor"].tolist()[0])
            draws = np.asarray(archive["response_draws"], dtype=float)
        if stored_anchor != str(anchor) or region not in regions or draws.shape[0:2] != (500, 96):
            raise RuntimeError(f"Normal driver identity changed: {path}")
        values[:, origin_index] = draws[:, :, regions.index(region)]
    return values


def selected_driver_paths(
    campaign: Path,
    fold: int,
    current_context: Mapping[str, Any],
    current_means: Mapping[float, np.ndarray],
    current_covariances: Mapping[float, np.ndarray],
) -> np.ndarray:
    selected = json.loads((campaign / "r114_selected_driver.json").read_text())
    if selected["family"] == "normal_rhs":
        return load_normal_region_paths("BG", fold, np.asarray(current_context["anchors"]))
    beta = {
        tau: draw_beta_posterior(
            current_means[tau], current_covariances[tau], 500,
            2026092600 + 100 * fold + index,
        )
        for index, tau in enumerate(QUANTILES)
    }
    case = json.loads((R103_CASES / f"r103_bg_f{fold}.json").read_text())
    design_meta = json.loads((Path(case["design_dir"]) / "design.json").read_text())
    n, p = int(design_meta["n"]), int(design_meta["p"])
    x = np.fromfile(Path(case["design_dir"]) / "X.bin", dtype="<f8").reshape(n, p)
    y = np.fromfile(Path(case["design_dir"]) / "y.bin", dtype="<f8")
    n_origins = n // 96
    curves = np.empty((n_origins, 96, len(QUANTILES)), dtype=float)
    response = np.empty((n_origins, 96), dtype=float)
    for horizon in range(96):
        index = slice(horizon * n_origins, (horizon + 1) * n_origins)
        response[:, horizon] = y[index]
        for position, tau in enumerate(QUANTILES):
            curves[:, horizon, position] = x[index] @ current_means[tau]
    ranks = observed_ranks(response, curves)
    policy = str(selected["rank_policy"])
    block = None if policy == "independent_stratified" else int(policy.rsplit("_", 1)[1])
    samples = np.empty((500, len(current_context["anchors"]), 96), dtype=float)
    for origin_index in range(len(current_context["anchors"])):
        uniforms = forecast_uniforms(
            "independent_stratified" if block is None else "training_block_rank",
            500, 96, 2026092700 + 1000 * fold + origin_index,
            training_ranks=None if block is None else ranks, block_length=block,
        )
        result = recursive_quantile_curve_forecast(
            current_context, np.zeros((500, 96, 1)), origin_index, ["BG"], beta,
            seed=2026092700 + origin_index, uniforms=uniforms,
            readout_mode="state_lead_horizon",
        )
        samples[:, origin_index] = result["samples"]
    return samples


def score_surface(truth: np.ndarray, prediction: np.ndarray) -> dict[str, float | int]:
    y = np.asarray(truth, dtype=float)
    q = np.asarray(prediction, dtype=float)
    if q.shape != (len(QUANTILES), *y.shape):
        raise ValueError("R116 quantile surface dimensions disagree")
    error = y[None, :, :] - q
    tau = np.asarray(QUANTILES)[:, None, None]
    loss = np.maximum(tau * error, (tau - 1) * error)
    return {
        "AQL": float(loss.mean()), "AQCR": float(np.mean(q[:-1] > q[1:])),
        "coverage_10_90": float(np.mean((y >= q[0]) & (y <= q[-1]))),
        "width_10_90": float(np.mean(q[-1] - q[0])), "n_loss_atoms": int(loss.size),
    }


def score_r116_outer(campaign: Path, fold: int) -> dict[str, Any]:
    output = campaign / f"runs/r116_outer_score/fold={fold}"
    terminal_path = output / "terminal.json"
    if terminal_path.is_file():
        existing = json.loads(terminal_path.read_text())
        if existing.get("status") == "completed_r116_outer_score":
            return existing
    selected_family = json.loads((campaign / "r116_selected_family.json").read_text())["family"]
    selected, selected_spec = selected_r115_spec(campaign)
    case = json.loads((R103_CASES / f"r103_bg_f{fold}.json").read_text())
    current_spec = json.loads(case["spec_json"])
    current_windows, _ = _policy_windows(case, current_spec, "train")
    selected_windows, _ = _policy_windows(case, selected_spec, "train")
    current_fitted = causal_teacher_forced_design(
        current_windows, current_spec, list(graph_adj_matrix()), readout_mode="state_lead_horizon"
    )
    selected_fitted = causal_teacher_forced_design(
        selected_windows, selected_spec, list(graph_adj_matrix()), readout_mode=selected["readout_mode"]
    )
    current_context = forecast_context(case, current_spec, current_fitted)
    selected_context = forecast_context(case, selected_spec, selected_fitted)
    if not np.array_equal(current_context["anchors"], selected_context["anchors"]):
        raise RuntimeError("R116 outer contexts have different anchors")
    current_root = campaign / f"runs/r116_outer_fit/readout=current_lead/family={selected_family}/fold={fold}"
    selected_root = campaign / f"runs/r116_outer_fit/readout=selected_no_bypass/family={selected_family}/fold={fold}"
    current_means, current_covariances = read_quantile_fit(
        current_root, selected_family, "completed_r116_quantile_family_fit",
        "completed_r116_quantile_atom",
    )
    selected_means, selected_covariances = read_quantile_fit(
        selected_root, selected_family, "completed_r116_quantile_family_fit",
        "completed_r116_quantile_atom",
    )
    current_beta = {
        tau: draw_beta_posterior(current_means[tau], current_covariances[tau], 500, 2026092800 + 100 * fold + i)
        for i, tau in enumerate(QUANTILES)
    }
    selected_beta = {
        tau: draw_beta_posterior(selected_means[tau], selected_covariances[tau], 500, 2026092900 + 100 * fold + i)
        for i, tau in enumerate(QUANTILES)
    }
    selected_driver_family = json.loads((campaign / "r114_selected_driver.json").read_text())["family"]
    driver_fit_family = selected_driver_family if selected_driver_family in {"al", "exal"} else selected_family
    driver_root = campaign / f"runs/r116_outer_fit/readout=current_lead/family={driver_fit_family}/fold={fold}"
    driver_means, driver_covariances = read_quantile_fit(
        driver_root, driver_fit_family, "completed_r116_quantile_family_fit",
        "completed_r116_quantile_atom",
    )
    target_selected = selected_driver_paths(
        campaign, fold, current_context, driver_means, driver_covariances
    )
    anchors = np.asarray(current_context["anchors"])
    normal = {
        region: load_normal_region_paths(region, fold, anchors)
        for region in sorted(set(current_context["active_regions"]) | set(selected_context["active_regions"]))
    }
    drivers = {
        "current_lead": {
            "normal": np.stack([normal[region] for region in current_context["active_regions"]], axis=-1),
            "selected": np.stack([
                target_selected if region == "BG" else normal[region]
                for region in current_context["active_regions"]
            ], axis=-1),
        },
        "selected_no_bypass": {
            "normal": np.stack([normal[region] for region in selected_context["active_regions"]], axis=-1),
            "selected": np.stack([
                target_selected if region == "BG" else normal[region]
                for region in selected_context["active_regions"]
            ], axis=-1),
        },
    }
    cells = {
        "A": (current_context, current_beta, "current_lead", "normal", "state_lead_horizon"),
        "B": (current_context, current_beta, "current_lead", "selected", "state_lead_horizon"),
        "C": (selected_context, selected_beta, "selected_no_bypass", "normal", selected["readout_mode"]),
        "D": (selected_context, selected_beta, "selected_no_bypass", "selected", selected["readout_mode"]),
    }
    data_config = load_config(case["data_config_path"])
    scaler_path = Path(data_config["pricefm"]["processed_dir"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])
    truth = np.asarray(current_context["truth"], dtype=float) * scale + center
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        metrics = []
        horizons = []
        for cell, (context, beta, readout_id, driver_id, readout_mode) in cells.items():
            prediction = np.empty((len(QUANTILES), len(anchors), 96), dtype=float)
            for origin_index in range(len(anchors)):
                design = recursive_quantile_design(
                    context, drivers[readout_id][driver_id][:, origin_index], origin_index,
                    context["active_regions"], readout_mode=readout_mode,
                )
                for q_index, tau in enumerate(QUANTILES):
                    prediction[q_index, origin_index] = paired_quantile_prediction(design, beta[tau])
            prediction_original = prediction * scale + center
            metric = score_surface(truth, prediction_original)
            metrics.append({
                "fold": fold, "cell": cell, "driver": driver_id, "readout": readout_id,
                "family": selected_family, **metric, "test_opened": False,
            })
            for start in range(0, 96, 24):
                block = score_surface(truth[:, start:start + 24], prediction_original[:, :, start:start + 24])
                horizons.append({
                    "fold": fold, "cell": cell, "horizon_block": f"{start + 1}-{start + 24}",
                    "driver": driver_id, "readout": readout_id, "family": selected_family,
                    **block, "test_opened": False,
                })
            np.savez_compressed(
                temporary / f"cell_{cell}_validation_predictions.npz",
                prediction_scaled=prediction.astype(np.float32),
                truth_scaled=np.asarray(current_context["truth"], dtype=np.float32),
                quantiles=np.asarray(QUANTILES), anchors=anchors.astype(str),
            )
        pd.DataFrame(metrics).to_csv(temporary / "metrics.csv", index=False)
        pd.DataFrame(horizons).to_csv(temporary / "horizon_metrics.csv", index=False)
        terminal = {
            "stage": "R116", "status": "completed_r116_outer_score", "fold": fold,
            "cell_count": 4, "selected_family": selected_family,
            "selected_driver_family": selected_driver_family,
            "selected_readout": selected["readout_mode"], "posterior_paths": 500,
            "evaluation_split": "outer_validation_only", "test_opened": False,
            "registry_mutated": False, "article_mutated": False,
        }
        write_json(temporary / "terminal.json", terminal)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return terminal
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=(
            "r114-score", "r115-ridge", "r116-family-design",
            "r116-family-score", "r116-outer-design", "r116-outer-score",
        ),
    )
    parser.add_argument("--campaign-root", type=Path, default=DEFAULT_CAMPAIGN)
    parser.add_argument("--family", choices=("al", "exal"))
    parser.add_argument("--inner-fold", type=int, choices=(1, 2, 3))
    parser.add_argument("--fold", type=int, choices=(1, 2, 3))
    parser.add_argument("--candidate-id")
    args = parser.parse_args()
    if args.mode == "r114-score":
        if args.family is None or args.inner_fold is None:
            parser.error("r114-score requires --family and --inner-fold")
        result = score_r114(args.campaign_root.resolve(), args.family, args.inner_fold)
    elif args.mode == "r115-ridge":
        if args.candidate_id is None:
            parser.error("r115-ridge requires --candidate-id")
        result = r115_ridge(args.campaign_root.resolve(), args.candidate_id)
    elif args.mode == "r116-family-design":
        result = prepare_r116_family_design(args.campaign_root.resolve())
    elif args.mode == "r116-family-score":
        if args.family is None or args.inner_fold is None:
            parser.error("r116-family-score requires --family and --inner-fold")
        result = score_r116_family(
            args.campaign_root.resolve(), args.family, args.inner_fold
        )
    elif args.mode == "r116-outer-design":
        if args.fold is None:
            parser.error("r116-outer-design requires --fold")
        result = prepare_r116_outer_design(args.campaign_root.resolve(), args.fold)
    else:
        if args.fold is None:
            parser.error("r116-outer-score requires --fold")
        result = score_r116_outer(args.campaign_root.resolve(), args.fold)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
