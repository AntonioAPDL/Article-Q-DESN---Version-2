#!/usr/bin/env python3
"""Run one complete PriceFM R102B recursive validation surface."""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import tempfile
from typing import Any

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, sha256_file, write_json
from pricefm_desn_adapter import load_window
from pricefm_graph import graph_adj_matrix
from pricefm_recursive_adapter import build_policy_features
from pricefm_recursive_normal import (
    QUANTILES,
    _block,
    deterministic_seed,
    draw_normal_posterior,
    precompute_initial_states,
    read_float64,
    recursive_panel_origin,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r102b_recursive_validation_20260916"
R102_PREP = DATA / "launch_prep/pricefm_stage_r102_recursive_normal_20260916"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--task-id", required=True)
    value.add_argument("--force", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def truthy(value: Any) -> bool:
    return value is True or str(value).strip().lower() in {"1", "true", "yes"}


def verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R102B preparation hash mismatch: {}".format(role))
    if sha256_file(prep / "pricefm_stage_r102b_launch_control.json") != summary["launch_control_sha256"]:
        raise RuntimeError("R102B launch-control hash mismatch")
    sources = pd.read_csv(prep / "source_manifest.csv")
    for row in sources.itertuples(index=False):
        if not Path(row.path).is_file() or sha256_file(row.path) != str(row.sha256):
            raise RuntimeError("R102B source hash mismatch: {}".format(row.path))
    return summary, pd.read_csv(prep / "pricefm_stage_r102b_task_manifest.csv")


def _fit_artifacts(path: Path, prior_type: str, n_paths: int, seed: int) -> tuple[dict[str, np.ndarray], dict[str, Any]]:
    terminal = read_json(path / "terminal.json")
    if (
        terminal.get("status") != "completed_recursive_normal_fit"
        or terminal.get("converged") is not True
        or terminal.get("prior_type") != prior_type
        or terminal.get("test_opened") is not False
    ):
        raise RuntimeError("invalid R102A fit terminal: {}".format(path))
    for row in terminal["artifacts"]:
        artifact = path / row["path"]
        if not artifact.is_file() or sha256_file(artifact) != row["sha256"]:
            raise RuntimeError("changed R102A fit artifact: {}".format(artifact))
    p = int(terminal["p"])
    mean = read_float64(path / "beta_mean.bin", (p,))
    covariance = read_float64(path / "beta_cov.bin", (p, p))
    precision_inverse = None
    if prior_type == "scaled_ridge":
        precision_inverse = read_float64(path / "beta_precision_inv.bin", (p, p))
    draws = draw_normal_posterior(
        mean,
        covariance,
        terminal["omega_shape"],
        terminal["omega_rate"],
        n_paths,
        seed,
        prior_type,
        precision_inverse=precision_inverse,
    )
    return draws, terminal


def _reservoir(stats_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    meta = read_json(stats_dir / "statistics.json")
    terminal = read_json(stats_dir / "terminal.json")
    if terminal.get("status") != "completed_causal_sufficient_statistics" or terminal.get("test_opened") is not False:
        raise RuntimeError("invalid R102A statistics terminal")
    for name, record in terminal["files"].items():
        if sha256_file(stats_dir / name) != record["sha256"]:
            raise RuntimeError("changed R102A statistics artifact: {}".format(stats_dir / name))
    with np.load(stats_dir / "reservoir.npz", allow_pickle=False) as archive:
        layers = []
        for layer_id in range(1, len(meta["reservoir_config"]["units"]) + 1):
            layers.append({
                "input": np.asarray(archive["input_{}".format(layer_id)], dtype=float),
                "recurrent": np.asarray(archive["recurrent_{}".format(layer_id)], dtype=float),
                "bias": np.asarray(archive["bias_{}".format(layer_id)], dtype=float),
            })
    return {"layers": layers}, meta


def load_contexts(
    r102_prep: Path,
    panel: str,
    prior_type: str,
    fold: int,
    n_paths: int,
    base_seed: int,
) -> tuple[dict[str, dict[str, Any]], dict[str, Any], list[dict[str, Any]]]:
    panels = pd.read_csv(r102_prep / "pricefm_stage_r102_panel_map.csv")
    designs = pd.read_csv(r102_prep / "pricefm_stage_r102_design_manifest.csv")
    fits = pd.read_csv(r102_prep / "pricefm_stage_r102_fit_manifest.csv")
    selected = panels[(panels.panel == panel) & (panels.fold.astype(int) == fold)].copy()
    if len(selected) != 38 or selected.region.astype(str).nunique() != 38:
        raise RuntimeError("task does not map a complete panel")
    regions = list(graph_adj_matrix())
    selected = selected.set_index("region").loc[regions].reset_index()
    design_by_id = designs.set_index("design_id")
    fit_by_id = fits.set_index("fit_id")
    contexts: dict[str, dict[str, Any]] = {}
    source_records: dict[str, dict[str, Any]] = {}
    anchors = None

    for panel_row in selected.itertuples(index=False):
        region = str(panel_row.region)
        fit_id = str(panel_row.ridge_fit_id if prior_type == "scaled_ridge" else panel_row.rhs_fit_id)
        fit_row = fit_by_id.loc[fit_id]
        design_row = design_by_id.loc[str(fit_row.design_id)]
        if int(design_row.fold) != fold or str(design_row.region) != region:
            raise RuntimeError("R102B fit/design identity mismatch")
        stats_dir = Path(design_row.statistics_dir)
        reservoir, stats_meta = _reservoir(stats_dir)
        spec = dict(stats_meta["contract"])
        active = [str(x) for x in stats_meta["feature_policy_manifest"]["active_regions"]]
        if active[0] != region:
            raise RuntimeError("recursive active-region order must start with the target")
        data_config = load_config(design_row.data_config_path)
        windows = {source: load_window(data_config, fold, source, "val") for source in active}
        initial = build_policy_features(
            region,
            {source: _block(window) for source, window in windows.items()},
            spec["feature_policy"],
            spec["spatial"],
            input_regions=regions,
        )
        local_anchors = np.asarray(windows[region]["anchors"], dtype=str)
        if anchors is None:
            anchors = local_anchors
        elif not np.array_equal(anchors, local_anchors):
            raise RuntimeError("R102B panel anchors disagree")
        expected_lead = [name.replace("lead::", "", 1) for name in stats_meta["feature_names"] if name.startswith("lead::")]
        if list(initial["lead_cols"]) != expected_lead:
            raise RuntimeError("R102B lead-feature ordering changed")
        fit_dir = Path(fit_row.output_dir)
        draws, fit_terminal = _fit_artifacts(
            fit_dir,
            prior_type,
            n_paths,
            deterministic_seed(base_seed, "parameter", fold, prior_type, region),
        )
        context = {
            "region": region,
            "spec": spec,
            "active_regions": active,
            "input_regions": regions,
            "initial_lag": np.asarray(initial["X_lag"], dtype=float),
            "lead_features": np.asarray(initial["X_lead"], dtype=float),
            "raw_lead": {source: np.asarray(window["X_lead"], dtype=float) for source, window in windows.items()},
            "lag_columns": {source: list(window["lag_cols"]) for source, window in windows.items()},
            "lead_columns": {source: list(window["lead_cols"]) for source, window in windows.items()},
            "truth": np.asarray(windows[region]["Y"], dtype=float),
            "reservoir": reservoir,
            "reservoir_config": stats_meta["reservoir_config"],
            "posterior_draws": draws,
            "fit_id": fit_id,
            "posterior_target_sha256": fit_terminal["posterior_target_sha256"],
        }
        context["initial_states"] = precompute_initial_states(context)
        contexts[region] = context
        for source, window in windows.items():
            for path in (Path(window["path"]), Path(window["path"]).with_suffix(".manifest.json")):
                source_records[str(path.resolve())] = {
                    "role": "validation_window",
                    "path": str(path.resolve()),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
        stats_terminal = read_json(stats_dir / "terminal.json")
        fit_terminal_payload = read_json(fit_dir / "terminal.json")
        bound_inputs = [(stats_dir / "terminal.json", "statistics_terminal"), (fit_dir / "terminal.json", "fit_terminal")]
        bound_inputs.extend((stats_dir / name, "statistics_artifact") for name in stats_terminal["files"])
        bound_inputs.extend((fit_dir / row["path"], "fit_artifact") for row in fit_terminal_payload["artifacts"])
        bound_inputs.append((Path(design_row.data_config_path), "validation_data_config"))
        for path, role in bound_inputs:
            source_records[str(path.resolve())] = {
                "role": role,
                "path": str(path.resolve()),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }

    scaler_path = Path(data_config["pricefm"]["processed_dir"]) / "scalers" / "fold_{}".format(fold) / "per_region_separate_xy_scalers.joblib"
    scalers = joblib.load(scaler_path)
    scaler_values = {
        region: {
            "center": float(np.asarray(scalers[region]["y_scaler"].center_).reshape(-1)[0]),
            "scale": float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0]),
        }
        for region in regions
    }
    source_records[str(scaler_path.resolve())] = {
        "role": "fold_scaler",
        "path": str(scaler_path.resolve()),
        "bytes": scaler_path.stat().st_size,
        "sha256": sha256_file(scaler_path),
    }
    return contexts, {"regions": regions, "anchors": anchors, "scalers": scaler_values}, list(source_records.values())


def valid_origin(path: Path) -> bool:
    terminal_path = path.with_suffix(".json")
    if not path.is_file() or not terminal_path.is_file():
        return False
    try:
        terminal = read_json(terminal_path)
        return (
            terminal.get("status") == "completed_recursive_origin"
            and terminal.get("test_opened") is False
            and sha256_file(path) == terminal.get("sha256")
        )
    except (OSError, json.JSONDecodeError):
        return False


def write_origin(path: Path, draws: np.ndarray, anchor: str, regions: list[str], origin_index: int) -> dict[str, Any]:
    if not np.all(np.isfinite(draws)):
        raise ValueError("R102B origin paths contain non-finite values")
    stored = np.asarray(draws, dtype=np.float32)
    if not np.all(np.isfinite(stored)):
        raise ValueError("R102B origin paths overflow float32 storage")
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=path.parent)
    os.close(handle)
    Path(temporary_name).unlink()
    temporary = Path(temporary_name + ".npz")
    try:
        np.savez_compressed(
            temporary,
            response_draws=stored,
            anchor=np.asarray([anchor], dtype=str),
            regions=np.asarray(regions, dtype=str),
        )
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()
    terminal = {
        "status": "completed_recursive_origin",
        "origin_index": int(origin_index),
        "anchor": str(anchor),
        "shape": list(stored.shape),
        "dtype": str(stored.dtype),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "test_opened": False,
    }
    write_json(path.with_suffix(".json"), terminal)
    return terminal


def score_surface(
    output: Path,
    contexts: dict[str, dict[str, Any]],
    metadata: dict[str, Any],
    panel: str,
    prior_type: str,
    fold: int,
) -> dict[str, Path]:
    regions = metadata["regions"]
    quantiles = np.asarray(QUANTILES, dtype=float)
    region_loss = np.zeros(len(regions), dtype=float)
    region_count = np.zeros(len(regions), dtype=np.int64)
    quantile_loss = np.zeros(len(quantiles), dtype=float)
    quantile_count = np.zeros(len(quantiles), dtype=np.int64)
    horizon_loss = np.zeros(4, dtype=float)
    horizon_count = np.zeros(4, dtype=np.int64)
    total_loss = 0.0
    total_count = 0
    crossing_sum = 0
    crossing_count = 0
    origin_rows = []
    centers = np.asarray([metadata["scalers"][region]["center"] for region in regions], dtype=float)
    scales = np.asarray([metadata["scalers"][region]["scale"] for region in regions], dtype=float)

    for origin_index, anchor in enumerate(metadata["anchors"]):
        path = output / "origins" / "origin_{:04d}.npz".format(origin_index)
        terminal_path = path.with_suffix(".json")
        if not valid_origin(path):
            raise RuntimeError("invalid R102B origin artifact: {}".format(path))
        terminal = read_json(terminal_path)
        origin_rows.append({
            "origin_index": origin_index,
            "anchor": anchor,
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": terminal["sha256"],
            "terminal_path": str(terminal_path.resolve()),
            "terminal_sha256": sha256_file(terminal_path),
        })
        with np.load(path, allow_pickle=False) as archive:
            draws = np.asarray(archive["response_draws"], dtype=float)
        prediction = np.quantile(draws, quantiles, axis=0).transpose(1, 2, 0)
        truth_scaled = np.column_stack([contexts[region]["truth"][origin_index] for region in regions])
        truth = truth_scaled * scales[None, :] + centers[None, :]
        prediction = prediction * scales[None, :, None] + centers[None, :, None]
        error = truth[:, :, None] - prediction
        loss = np.maximum(
            quantiles[None, None, :] * error,
            (quantiles[None, None, :] - 1.0) * error,
        )
        total_loss += float(loss.sum())
        total_count += int(loss.size)
        region_loss += loss.sum(axis=(0, 2))
        region_count += loss.shape[0] * loss.shape[2]
        quantile_loss += loss.sum(axis=(0, 1))
        quantile_count += loss.shape[0] * loss.shape[1]
        for group, start in enumerate((0, 24, 48, 72)):
            block = loss[start : start + 24]
            horizon_loss[group] += float(block.sum())
            horizon_count[group] += int(block.size)
        crossing_sum += int((prediction[:, :, :-1] > prediction[:, :, 1:]).sum())
        crossing_count += int(np.prod(prediction[:, :, :-1].shape))

    overall = pd.DataFrame([{
        "panel": panel,
        "prior_type": prior_type,
        "fold": fold,
        "validation_AQL_original": total_loss / total_count,
        "validation_AQCR": crossing_sum / crossing_count,
        "n_loss_atoms": total_count,
        "n_origins": len(metadata["anchors"]),
        "posterior_paths": int(contexts[regions[0]]["posterior_draws"]["beta"].shape[0]),
        "selection_split": "validation_only",
        "test_opened": False,
    }])
    by_region = pd.DataFrame({
        "panel": panel,
        "prior_type": prior_type,
        "fold": fold,
        "region": regions,
        "validation_AQL_original": region_loss / region_count,
        "n_loss_atoms": region_count,
    })
    by_quantile = pd.DataFrame({
        "panel": panel,
        "prior_type": prior_type,
        "fold": fold,
        "tau": quantiles,
        "validation_quantile_loss_original": quantile_loss / quantile_count,
        "n_loss_atoms": quantile_count,
    })
    by_horizon = pd.DataFrame({
        "panel": panel,
        "prior_type": prior_type,
        "fold": fold,
        "horizon_group": ["1-24", "25-48", "49-72", "73-96"],
        "validation_AQL_original": horizon_loss / horizon_count,
        "n_loss_atoms": horizon_count,
    })
    tables = {
        "origin_manifest": pd.DataFrame(origin_rows),
        "metrics_overall": overall,
        "metrics_region": by_region,
        "metrics_quantile": by_quantile,
        "metrics_horizon": by_horizon,
    }
    paths = {}
    for role, table in tables.items():
        path = output / "{}.csv".format(role)
        table.to_csv(path, index=False, quoting=csv.QUOTE_MINIMAL)
        paths[role] = path
    return paths


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    _, tasks = verify_prep(prep)
    selected = tasks[tasks.task_id.astype(str) == args.task_id]
    if len(selected) != 1:
        raise RuntimeError("R102B task_id is absent or duplicated")
    task = selected.iloc[0]
    if str(task.selection_split) != "validation_only" or truthy(task.test_access_authorized):
        raise RuntimeError("R102B task attempted to open test")
    output = Path(task.output_dir)
    terminal_path = output / "terminal.json"
    if terminal_path.is_file() and not args.force:
        terminal = read_json(terminal_path)
        if terminal.get("status") == "completed_recursive_validation_surface":
            print(json.dumps(terminal, indent=2, sort_keys=True))
            return terminal
    output.mkdir(parents=True, exist_ok=True)
    control = read_json(prep / "pricefm_stage_r102b_launch_control.json")
    contexts, metadata, source_records = load_contexts(
        Path(control["r102_prep"]),
        str(task.panel), str(task.prior_type), int(task.fold), int(task.posterior_paths), int(task.base_seed)
    )
    for origin_index, anchor in enumerate(metadata["anchors"]):
        path = output / "origins" / "origin_{:04d}.npz".format(origin_index)
        if valid_origin(path) and not args.force:
            continue
        draws = recursive_panel_origin(
            contexts,
            origin_index,
            int(task.posterior_paths),
            int(task.fold),
            int(task.base_seed),
            calculation_order=metadata["regions"],
        )
        write_origin(path, draws, str(anchor), metadata["regions"], origin_index)
        write_json(output / "progress.json", {
            "task_id": args.task_id,
            "origins_complete": origin_index + 1,
            "origins_total": len(metadata["anchors"]),
            "test_opened": False,
        })
    paths = score_surface(
        output, contexts, metadata, str(task.panel), str(task.prior_type), int(task.fold)
    )
    source_path = output / "task_sources.csv"
    pd.DataFrame(source_records).sort_values(["role", "path"]).to_csv(source_path, index=False)
    paths["task_sources"] = source_path
    artifacts = [
        {"role": role, "path": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
        for role, path in paths.items()
    ]
    fit_targets = {
        region: {
            "fit_id": context["fit_id"],
            "posterior_target_sha256": context["posterior_target_sha256"],
            "posterior_draw_contract": context["posterior_draws"]["contract"],
        }
        for region, context in contexts.items()
    }
    terminal = {
        "stage": "R102B",
        "status": "completed_recursive_validation_surface",
        "task_id": args.task_id,
        "panel": str(task.panel),
        "prior_type": str(task.prior_type),
        "fold": int(task.fold),
        "regions": len(metadata["regions"]),
        "origins": len(metadata["anchors"]),
        "horizons": 96,
        "posterior_paths": int(task.posterior_paths),
        "fit_targets": fit_targets,
        "path_storage_dtype": "float32",
        "path_generation_arithmetic": "float64",
        "recursive_contract": "synchronous_all_regions_predict_then_update",
        "selection_split": "validation_only",
        "test_opened": False,
        "quantile_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "artifacts": artifacts,
    }
    write_json(terminal_path, terminal)
    print(json.dumps(terminal, indent=2, sort_keys=True))
    return terminal


def main() -> int:
    return 0 if run(parser().parse_args()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
