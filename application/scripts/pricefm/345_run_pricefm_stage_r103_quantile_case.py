#!/usr/bin/env python3
"""Build, fit, and validate one R103 region-fold independent quantile case."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any

import joblib
import numpy as np
import pandas as pd

from pricefm_common import load_config, sha256_file, write_json
from pricefm_desn_adapter import load_window
from pricefm_graph import graph_adj_matrix
from pricefm_recursive_adapter import build_policy_features
from pricefm_recursive_normal import _block, precompute_initial_states
from pricefm_recursive_quantile import (
    QUANTILES,
    causal_teacher_forced_design,
    draw_beta_posterior,
    paired_quantile_prediction,
    read_design,
    recursive_quantile_design,
    write_design,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PREP = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
R_RUNNER = Path(__file__).with_name("344_run_pricefm_stage_r103_quantile_case.R")
THREAD_ENV = (
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "RCPP_PARALLEL_NUM_THREADS",
    "BLIS_NUM_THREADS",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--case-id", required=True)
    value.add_argument("--preflight-only", action="store_true")
    value.add_argument("--force-design", action="store_true")
    return value


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def verify_prep(prep: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    summary = read_json(prep / "summary.json")
    if summary.get("status") != "prepared_validation_only_campaign" or summary.get("test_opened") is not False:
        raise RuntimeError("R103 prep summary is invalid")
    for role, name in summary["output_files"].items():
        if sha256_file(prep / name) != summary["output_sha256"][role]:
            raise RuntimeError("R103 prep hash mismatch: {}".format(role))
    for row in pd.read_csv(prep / "source_manifest.csv").itertuples(index=False):
        path = Path(row.path)
        if not path.is_file() or sha256_file(path) != str(row.sha256):
            raise RuntimeError("R103 source changed: {}".format(path))
    return summary, pd.read_csv(prep / "pricefm_stage_r103_case_manifest.csv")


def valid_design(path: Path) -> bool:
    try:
        read_design(path)
        return True
    except (OSError, ValueError, json.JSONDecodeError):
        return False


def valid_case(path: Path, config: dict[str, Any]) -> bool:
    terminal_path = path / "terminal.json"
    if not terminal_path.is_file():
        return False
    try:
        terminal = read_json(terminal_path)
        if (
            terminal.get("status") != "completed_recursive_quantile_case"
            or terminal.get("case_id") != config["case_id"]
            or terminal.get("case_contract_sha256") != config["case_contract_sha256"]
            or terminal.get("test_opened") is not False
            or int(terminal.get("atoms_complete", -1)) != 14
        ):
            return False
        return all(
            Path(record["path"]).is_file()
            and sha256_file(record["path"]) == record["sha256"]
            for record in terminal["artifacts"]
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def build_design(config: dict[str, Any], force: bool = False) -> dict[str, Any]:
    path = Path(config["design_dir"])
    if valid_design(path) and not force:
        return read_json(path / "terminal.json")
    data_config = load_config(config["data_config_path"])
    windows = {
        region: load_window(data_config, int(config["fold"]), region, "train")
        for region in config["active_regions"]
    }
    result = causal_teacher_forced_design(
        windows,
        json.loads(config["spec_json"]),
        list(graph_adj_matrix()),
    )
    terminal = write_design(path, result, force=True)
    terminal.update({
        "stage": "R103",
        "case_id": config["case_id"],
        "region": config["region"],
        "fold": int(config["fold"]),
        "design_id": config["design_id"],
    })
    write_json(path / "terminal.json", terminal)
    return terminal


def run_r(config_path: Path, preflight_only: bool) -> None:
    command = [str(RSCRIPT), str(R_RUNNER), "--case-config", str(config_path)]
    if preflight_only:
        command.extend(["--preflight-only", "true"])
    env = dict(os.environ)
    env.update({name: "1" for name in THREAD_ENV})
    result = subprocess.run(command, env=env, check=False)
    if result.returncode:
        raise RuntimeError("R103 R fit runner failed with status {}".format(result.returncode))


def load_reservoir(statistics_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    meta = read_json(statistics_dir / "statistics.json")
    terminal = read_json(statistics_dir / "terminal.json")
    if terminal.get("status") != "completed_causal_sufficient_statistics" or terminal.get("test_opened") is not False:
        raise RuntimeError("R103 source statistics are invalid")
    for name, record in terminal["files"].items():
        if sha256_file(statistics_dir / name) != record["sha256"]:
            raise RuntimeError("R103 source statistics changed")
    with np.load(statistics_dir / "reservoir.npz", allow_pickle=False) as archive:
        layers = [
            {
                "input": np.asarray(archive["input_{}".format(index)], dtype=float),
                "recurrent": np.asarray(archive["recurrent_{}".format(index)], dtype=float),
                "bias": np.asarray(archive["bias_{}".format(index)], dtype=float),
            }
            for index in range(1, len(meta["reservoir_config"]["units"]) + 1)
        ]
    return {"layers": layers}, meta


def validation_context(config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    statistics = Path(config["statistics_dir"])
    reservoir, meta = load_reservoir(statistics)
    spec = dict(meta["contract"])
    active = [str(x) for x in meta["feature_policy_manifest"]["active_regions"]]
    data_config = load_config(config["data_config_path"])
    windows = {
        region: load_window(data_config, int(config["fold"]), region, "val")
        for region in active
    }
    initial = build_policy_features(
        str(config["region"]),
        {region: _block(window) for region, window in windows.items()},
        spec["feature_policy"],
        spec["spatial"],
        input_regions=list(graph_adj_matrix()),
    )
    context = {
        "region": str(config["region"]),
        "spec": spec,
        "active_regions": active,
        "input_regions": list(graph_adj_matrix()),
        "initial_lag": np.asarray(initial["X_lag"], dtype=float),
        "lead_features": np.asarray(initial["X_lead"], dtype=float),
        "raw_lead": {region: np.asarray(window["X_lead"], dtype=float) for region, window in windows.items()},
        "lag_columns": {region: list(window["lag_cols"]) for region, window in windows.items()},
        "lead_columns": {region: list(window["lead_cols"]) for region, window in windows.items()},
        "truth": np.asarray(windows[str(config["region"])]["Y"], dtype=float),
        "anchors": np.asarray(windows[str(config["region"])]["anchors"], dtype=str),
        "reservoir": reservoir,
        "reservoir_config": meta["reservoir_config"],
    }
    context["initial_states"] = precompute_initial_states(context)
    scaler_path = (
        Path(data_config["pricefm"]["processed_dir"])
        / "scalers"
        / "fold_{}".format(config["fold"])
        / "per_region_separate_xy_scalers.joblib"
    )
    scaler = joblib.load(scaler_path)[str(config["region"])]["y_scaler"]
    return context, {
        "scaler_path": scaler_path,
        "center": float(np.asarray(scaler.center_).reshape(-1)[0]),
        "scale": float(np.asarray(scaler.scale_).reshape(-1)[0]),
    }


def read_atom(config: dict[str, Any], atom: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    output = Path(atom["output_dir"])
    terminal = read_json(output / "terminal.json")
    if (
        terminal.get("status") != "completed_recursive_quantile_atom"
        or terminal.get("atom_id") != atom["atom_id"]
        or terminal.get("posterior_target_sha256") != atom["posterior_target_sha256"]
        or terminal.get("test_opened") is not False
    ):
        raise RuntimeError("R103 atom terminal is invalid: {}".format(atom["atom_id"]))
    for record in terminal["artifacts"]:
        path = Path(record["path"])
        if not path.is_file() or sha256_file(path) != record["sha256"]:
            raise RuntimeError("R103 atom artifact changed: {}".format(path))
    p = int(terminal["p"])
    mean = np.fromfile(output / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(output / "beta_cov.bin", dtype="<f8").reshape(p, p)
    if mean.size != p or not np.all(np.isfinite(mean)) or not np.all(np.isfinite(covariance)):
        raise RuntimeError("R103 atom posterior is invalid")
    return mean, covariance, terminal


def write_npz(path: Path, **arrays: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, name = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=path.parent)
    os.close(handle)
    Path(name).unlink()
    temporary = Path(name + ".npz")
    try:
        np.savez_compressed(temporary, **arrays)
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def score_case(config: dict[str, Any]) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    context, scaler = validation_context(config)
    fit_terminal = read_json(Path(config["output_dir"]) / "fit_terminal.json")
    if fit_terminal.get("status") != "completed_recursive_quantile_fits" or fit_terminal.get("test_opened") is not False:
        raise RuntimeError("R103 fit terminal is invalid")
    atoms = list(config["atoms"])
    beta: dict[tuple[str, float], np.ndarray] = {}
    atom_terminals: dict[tuple[str, float], dict[str, Any]] = {}
    for atom in atoms:
        mean, covariance, terminal = read_atom(config, atom)
        key = (str(atom["family"]), float(atom["tau"]))
        beta[key] = draw_beta_posterior(mean, covariance, int(config["posterior_paths"]), int(atom["seed"]))
        atom_terminals[key] = terminal
    surface = Path(config["normal_driver_surface"])
    surface_terminal = read_json(surface / "terminal.json")
    if (
        surface_terminal.get("status") != "completed_recursive_validation_surface"
        or surface_terminal.get("task_id") != config["normal_driver_task_id"]
        or surface_terminal.get("prior_type") != "rhs_ns"
        or surface_terminal.get("test_opened") is not False
    ):
        raise RuntimeError("R103 Normal-RHS driver surface is invalid")
    prediction = {
        family: np.empty((len(QUANTILES), len(context["anchors"]), 96), dtype=np.float32)
        for family in ("al", "exal")
    }
    source_records: list[dict[str, Any]] = []
    for origin_index, anchor in enumerate(context["anchors"]):
        path = surface / "origins" / "origin_{:04d}.npz".format(origin_index)
        marker = path.with_suffix(".json")
        record = read_json(marker)
        if record.get("status") != "completed_recursive_origin" or sha256_file(path) != record.get("sha256"):
            raise RuntimeError("R103 Normal driver origin is invalid: {}".format(path))
        with np.load(path, allow_pickle=False) as archive:
            driver = np.asarray(archive["response_draws"], dtype=float)
            regions = [str(x) for x in archive["regions"].tolist()]
            stored_anchor = str(archive["anchor"].tolist()[0])
        if stored_anchor != str(anchor) or driver.shape[0] != int(config["posterior_paths"]):
            raise RuntimeError("R103 Normal driver identity mismatch")
        design = recursive_quantile_design(context, driver, origin_index, regions)
        for family in ("al", "exal"):
            for tau_index, tau in enumerate(QUANTILES):
                prediction[family][tau_index, origin_index] = paired_quantile_prediction(
                    design, beta[(family, float(tau))]
                ).astype(np.float32)
        source_records.append({
            "role": "normal_driver_origin",
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": record["sha256"],
        })
    truth = context["truth"] * scaler["scale"] + scaler["center"]
    rows = []
    output = Path(config["output_dir"])
    for family in ("al", "exal"):
        path = output / "{}_validation_quantiles.npz".format(family)
        write_npz(
            path,
            prediction_scaled=prediction[family],
            quantiles=np.asarray(QUANTILES, dtype=float),
            anchors=np.asarray(context["anchors"], dtype=str),
        )
        pred_original = prediction[family].astype(float) * scaler["scale"] + scaler["center"]
        error = truth[None, :, :] - pred_original
        tau = np.asarray(QUANTILES, dtype=float)[:, None, None]
        loss = np.maximum(tau * error, (tau - 1.0) * error)
        crossing = pred_original[:-1] > pred_original[1:]
        eligible = all(atom_terminals[(family, float(value))]["numerical_gate_passed"] for value in QUANTILES)
        rows.append({
            "region": config["region"],
            "fold": int(config["fold"]),
            "family": family,
            "validation_AQL_original": float(loss.mean()),
            "validation_AQCR": float(crossing.mean()),
            "n_loss_atoms": int(loss.size),
            "n_origins": int(len(context["anchors"])),
            "posterior_paths": int(config["posterior_paths"]),
            "numerically_eligible": bool(eligible),
            "prediction_path": str(path.resolve()),
            "prediction_sha256": sha256_file(path),
            "selection_split": "validation_only",
            "test_opened": False,
        })
    source_records.extend([
        {
            "role": "fold_scaler",
            "path": str(scaler["scaler_path"].resolve()),
            "bytes": scaler["scaler_path"].stat().st_size,
            "sha256": sha256_file(scaler["scaler_path"]),
        },
        {
            "role": "fit_terminal",
            "path": str((output / "fit_terminal.json").resolve()),
            "bytes": (output / "fit_terminal.json").stat().st_size,
            "sha256": sha256_file(output / "fit_terminal.json"),
        },
    ])
    return pd.DataFrame(rows), source_records


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = args.prep_dir.resolve()
    _, cases = verify_prep(prep)
    selected = cases[cases.case_id.astype(str).eq(args.case_id)]
    if len(selected) != 1:
        raise RuntimeError("R103 case_id is absent or duplicated")
    row = selected.iloc[0]
    config_path = Path(row.case_config)
    config = read_json(config_path)
    stored_contract = config.get("case_contract_sha256")
    payload = dict(config)
    payload.pop("case_contract_sha256", None)
    if (
        stored_contract != str(row.case_contract_sha256)
        or stored_contract != canonical_hash(payload)
    ):
        raise RuntimeError("R103 case contract identity mismatch")
    output = Path(config["output_dir"])
    terminal_path = output / "terminal.json"
    if valid_case(output, config) and not args.force_design and not args.preflight_only:
        terminal = read_json(terminal_path)
        print(json.dumps(terminal, indent=2, sort_keys=True))
        return terminal
    build_design(config, force=args.force_design)
    run_r(config_path, args.preflight_only)
    if args.preflight_only:
        value = {
            "status": "preflight_passed_not_fitted",
            "case_id": args.case_id,
            "test_opened": False,
        }
        print(json.dumps(value, indent=2, sort_keys=True))
        return value
    metrics, sources = score_case(config)
    output.mkdir(parents=True, exist_ok=True)
    metrics_path = output / "family_validation_metrics.csv"
    metrics.to_csv(metrics_path, index=False, quoting=csv.QUOTE_MINIMAL)
    sources_path = output / "source_manifest.csv"
    pd.DataFrame(sources).sort_values(["role", "path"]).to_csv(sources_path, index=False)
    artifacts = [
        {
            "role": "family_validation_metrics",
            "path": str(metrics_path.resolve()),
            "bytes": metrics_path.stat().st_size,
            "sha256": sha256_file(metrics_path),
        },
        {
            "role": "source_manifest",
            "path": str(sources_path.resolve()),
            "bytes": sources_path.stat().st_size,
            "sha256": sha256_file(sources_path),
        },
    ]
    for family in ("al", "exal"):
        path = output / "{}_validation_quantiles.npz".format(family)
        artifacts.append({
            "role": "{}_validation_quantiles".format(family),
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    terminal = {
        "stage": "R103",
        "status": "completed_recursive_quantile_case",
        "case_id": args.case_id,
        "case_contract_sha256": config["case_contract_sha256"],
        "region": config["region"],
        "fold": int(config["fold"]),
        "atoms_complete": 14,
        "families_scored": 2,
        "posterior_paths": int(config["posterior_paths"]),
        "artifacts": artifacts,
        "selection_split": "validation_only",
        "test_opened": False,
        "joint_model_fitted": False,
        "mcmc_fitted": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    write_json(terminal_path, terminal)
    print(json.dumps(terminal, indent=2, sort_keys=True))
    return terminal


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
