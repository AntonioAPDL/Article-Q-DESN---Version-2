#!/usr/bin/env python3
"""Audit R103 and compare no-refit recursive forecast operators on BG and BE."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Iterable, Mapping

import numpy as np
import pandas as pd

from pricefm_common import sha256_file
from pricefm_recursive_normal import deterministic_seed
from pricefm_recursive_quantile import (
    QUANTILES,
    draw_beta_posterior,
    paired_quantile_prediction,
    recursive_quantile_design,
)
from pricefm_recursive_quantile_marginal import recursive_quantile_curve_forecast


DEFAULT_DATA_ROOT = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
)
R103_TAG = "pricefm_stage_r103_recursive_quantile_20260916"
R102B_TAG = "pricefm_stage_r102b_recursive_validation_20260916"
R97_TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
OUTPUT_TAG = "pricefm_stage_r104_forecast_operator_diagnosis_20260918"
FOCUS_REGIONS = ("BG", "BE")
COLORS = {
    "normal_rhs_mean_conditional": "#C44E52",
    "normal_ridge_mean_conditional": "#4C72B0",
    "quantile_curve_self": "#2F855A",
    "quantile_curve_self_rhs_neighbors": "#2F855A",
    "quantile_curve_self_ridge_neighbors": "#8A5A9E",
}
LABELS = {
    "normal_rhs_mean_conditional": "Current: RHS driver + mean conditional q",
    "normal_ridge_mean_conditional": "Ridge driver + mean conditional q",
    "quantile_curve_self": "Quantile-curve self recursion",
    "quantile_curve_self_rhs_neighbors": "Self recursion + RHS neighbors",
    "quantile_curve_self_ridge_neighbors": "Self recursion + Ridge neighbors",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    value.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_DATA_ROOT / "authoritative" / OUTPUT_TAG,
    )
    value.add_argument("--posterior-paths", type=int, default=500)
    value.add_argument("--regions", default=",".join(FOCUS_REGIONS))
    value.add_argument("--force", action="store_true")
    return value


def load_script(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load script: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SCRIPTS = Path(__file__).resolve().parent
CASE_RUNNER = load_script(SCRIPTS / "345_run_pricefm_stage_r103_quantile_case.py", "r103_case_runner")


def atomic_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")
    temporary.replace(path)


def active_r103_processes() -> list[dict[str, Any]]:
    records = []
    for item in Path("/proc").glob("[0-9]*"):
        try:
            command = (item / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if "stage_r103" in command and "350_audit_pricefm_stage_r104" not in command:
            records.append({"pid": int(item.name), "command": command.strip()})
    return sorted(records, key=lambda value: value["pid"])


def artifact_record(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = Path(path).resolve()
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def verify_terminal_artifacts(terminal: Mapping[str, Any]) -> None:
    for record in terminal.get("artifacts", []):
        path = Path(record["path"])
        if not path.is_file() or sha256_file(path) != record["sha256"]:
            raise RuntimeError(f"changed R103 artifact: {path}")


def freeze_partial_campaign(data_root: Path) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    campaign = data_root / "campaigns" / R103_TAG
    case_rows = []
    atom_rows = []
    for region_dir in sorted((campaign / "cases").glob("region=*")):
        region = region_dir.name.split("=", 1)[1]
        for fold_dir in sorted(region_dir.glob("fold=*")):
            fold = int(fold_dir.name.split("=", 1)[1])
            case_terminal = fold_dir / "terminal.json"
            case_complete = False
            if case_terminal.is_file():
                terminal = json.loads(case_terminal.read_text())
                case_complete = terminal.get("status") == "completed_recursive_quantile_case"
                if case_complete:
                    verify_terminal_artifacts(terminal)
            completed_atoms = 0
            for atom_terminal in sorted(fold_dir.glob("atoms/*/terminal.json")):
                terminal = json.loads(atom_terminal.read_text())
                if terminal.get("status") != "completed_recursive_quantile_atom":
                    continue
                verify_terminal_artifacts(terminal)
                trace_path = atom_terminal.parent / "vb_trace.csv"
                trace = pd.read_csv(trace_path)
                last = trace.iloc[-1] if len(trace) else pd.Series(dtype=float)
                atom_rows.append({
                    "region": region,
                    "fold": fold,
                    "atom_id": terminal["atom_id"],
                    "family": terminal["family"],
                    "tau": float(terminal["tau"]),
                    "formal_converged": bool(terminal["formal_converged"]),
                    "numerical_gate_passed": bool(terminal["numerical_gate_passed"]),
                    "iterations": int(terminal["iterations"]),
                    "final_elbo": float(last.get("elbo", np.nan)),
                    "final_delta_elbo": float(last.get("delta_elbo", np.nan)),
                    "final_delta_state": float(last.get("delta_state", np.nan)),
                    "final_delta_sigma": float(last.get("delta_sigma", np.nan)),
                    "final_delta_gamma": float(last.get("delta_gamma", np.nan)),
                    "terminal_path": str(atom_terminal.resolve()),
                    "terminal_sha256": sha256_file(atom_terminal),
                    "trace_path": str(trace_path.resolve()),
                    "trace_sha256": sha256_file(trace_path),
                })
                completed_atoms += 1
            case_rows.append({
                "region": region,
                "fold": fold,
                "case_complete": case_complete,
                "completed_atoms": completed_atoms,
                "case_terminal_path": str(case_terminal.resolve()) if case_terminal.is_file() else "",
                "case_terminal_sha256": sha256_file(case_terminal) if case_terminal.is_file() else "",
            })
    case_frame = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    atom_frame = pd.DataFrame(atom_rows).sort_values(["region", "fold", "family", "tau"])
    processes = active_r103_processes()
    summary = {
        "stage": "R104",
        "source_campaign": R103_TAG,
        "status": "partial_campaign_frozen_for_forecast_operator_diagnosis",
        "cases_total": 114,
        "cases_complete": int(case_frame.case_complete.sum()),
        "cases_partial": int(((~case_frame.case_complete) & case_frame.completed_atoms.gt(0)).sum()),
        "completed_atoms": int(len(atom_frame)),
        "expected_atoms": 1596,
        "formal_converged_atoms": int(atom_frame.formal_converged.sum()),
        "numerical_gate_passed_atoms": int(atom_frame.numerical_gate_passed.sum()),
        "active_r103_processes": processes,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
    }
    if processes:
        raise RuntimeError("R103 processes remain active; refusing to freeze a diagnostic snapshot")
    return case_frame, atom_frame, summary


def selected_family(metrics: pd.DataFrame) -> str:
    fold1 = metrics[metrics.fold.astype(int).eq(1)].sort_values(
        ["validation_AQL_original", "family"]
    )
    winner = str(fold1.iloc[0].family)
    eligible = metrics[metrics.family.eq(winner)].numerically_eligible.astype(bool).all()
    return winner if eligible else "al"


def score_surface(truth: np.ndarray, prediction_qnh: np.ndarray) -> dict[str, float]:
    truth = np.asarray(truth, dtype=float)
    prediction = np.asarray(prediction_qnh, dtype=float).transpose(1, 2, 0)
    tau = np.asarray(QUANTILES, dtype=float).reshape(1, 1, -1)
    if prediction.shape != truth.shape + (len(QUANTILES),):
        raise ValueError("forecast surface geometry is invalid")
    error = truth[..., None] - prediction
    loss = np.maximum(tau * error, (tau - 1.0) * error)
    median = prediction[..., 3]
    return {
        "AQL": float(np.mean(loss)),
        "AQCR": float(np.mean(prediction[..., :-1] > prediction[..., 1:])),
        "coverage_10_90": float(np.mean((truth >= prediction[..., 0]) & (truth <= prediction[..., -1]))),
        "mean_width_10_90": float(np.mean(prediction[..., -1] - prediction[..., 0])),
        "mean_width_25_75": float(np.mean(prediction[..., 5] - prediction[..., 1])),
        "median_MAE": float(np.mean(np.abs(truth - median))),
        "median_RMSE": float(np.sqrt(np.mean((truth - median) ** 2))),
        "n_origins": int(truth.shape[0]),
        "n_loss_atoms": int(loss.size),
    }


def horizon_metrics(
    region: str,
    fold: int,
    family: str,
    policy: str,
    truth: np.ndarray,
    prediction_qnh: np.ndarray,
) -> pd.DataFrame:
    prediction = np.asarray(prediction_qnh, dtype=float).transpose(1, 2, 0)
    tau = np.asarray(QUANTILES, dtype=float).reshape(1, 1, -1)
    error = np.asarray(truth, dtype=float)[..., None] - prediction
    loss = np.maximum(tau * error, (tau - 1.0) * error)
    return pd.DataFrame({
        "region": region,
        "fold": fold,
        "family": family,
        "policy": policy,
        "horizon": np.arange(1, 97),
        "AQL": loss.mean(axis=(0, 2)),
        "coverage_10_90": ((truth >= prediction[..., 0]) & (truth <= prediction[..., -1])).mean(axis=0),
        "width_10_90": (prediction[..., -1] - prediction[..., 0]).mean(axis=0),
    })


def read_driver(surface: Path, origin_index: int, anchor: str) -> tuple[np.ndarray, list[str], list[dict[str, Any]]]:
    path = surface / "origins" / f"origin_{origin_index:04d}.npz"
    marker = path.with_suffix(".json")
    record = json.loads(marker.read_text())
    if record.get("status") != "completed_recursive_origin" or sha256_file(path) != record.get("sha256"):
        raise RuntimeError(f"invalid Normal recursive origin: {path}")
    with np.load(path, allow_pickle=False) as archive:
        draws = np.asarray(archive["response_draws"], dtype=float)
        regions = [str(value) for value in archive["regions"].tolist()]
        stored_anchor = str(archive["anchor"].tolist()[0])
    if stored_anchor != str(anchor):
        raise RuntimeError("Normal driver anchor disagrees with the quantile context")
    return draws, regions, [artifact_record("normal_driver_origin", path), artifact_record("normal_driver_origin_marker", marker)]


def read_beta_draws(config: dict[str, Any], family: str, n_paths: int) -> tuple[dict[float, np.ndarray], list[dict[str, Any]]]:
    result = {}
    evidence = []
    atoms = [atom for atom in config["atoms"] if str(atom["family"]) == family]
    if len(atoms) != len(QUANTILES):
        raise RuntimeError("selected R103 family is incomplete")
    for atom in atoms:
        mean, covariance, terminal = CASE_RUNNER.read_atom(config, atom)
        tau = float(atom["tau"])
        result[tau] = draw_beta_posterior(mean, covariance, n_paths, int(atom["seed"]))
        terminal_path = Path(atom["output_dir"]) / "terminal.json"
        evidence.append(artifact_record("selected_atom_terminal", terminal_path, family=family, tau=tau))
        if not terminal.get("formal_converged") or not terminal.get("numerical_gate_passed"):
            raise RuntimeError(f"ineligible selected atom: {atom['atom_id']}")
    return result, evidence


def current_prediction(case_output: Path, family: str) -> np.ndarray:
    path = case_output / f"{family}_validation_quantiles.npz"
    with np.load(path, allow_pickle=False) as archive:
        prediction = np.asarray(archive["prediction_scaled"], dtype=float)
        quantiles = np.asarray(archive["quantiles"], dtype=float)
    if prediction.shape[0] != len(QUANTILES) or not np.allclose(quantiles, QUANTILES):
        raise RuntimeError("stored R103 quantile surface is invalid")
    return prediction


def scaled_to_original(values: np.ndarray, center: float, scale: float) -> np.ndarray:
    return np.asarray(values, dtype=float) * float(scale) + float(center)


def diagnose_case(
    data_root: Path,
    temporary: Path,
    region: str,
    fold: int,
    family: str,
    n_paths: int,
) -> tuple[list[dict[str, Any]], list[pd.DataFrame], list[dict[str, Any]], dict[str, dict[str, np.ndarray]]]:
    config_path = data_root / "launch_prep" / R103_TAG / "cases" / f"r103_{region.lower()}_f{fold}.json"
    config = json.loads(config_path.read_text())
    if int(config["posterior_paths"]) != n_paths:
        raise RuntimeError("R104 must use the frozen R103 posterior path count")
    context, scaler = CASE_RUNNER.validation_context(config)
    beta, evidence = read_beta_draws(config, family, n_paths)
    case_output = data_root / "campaigns" / R103_TAG / "cases" / f"region={region}" / f"fold={fold}"
    predictions: dict[str, np.ndarray] = {
        "normal_rhs_mean_conditional": current_prediction(case_output, family),
        "normal_ridge_mean_conditional": np.empty((len(QUANTILES), len(context["anchors"]), 96)),
    }
    self_policies = ["quantile_curve_self"] if len(context["active_regions"]) == 1 else [
        "quantile_curve_self_rhs_neighbors",
        "quantile_curve_self_ridge_neighbors",
    ]
    for policy in self_policies:
        predictions[policy] = np.empty((len(QUANTILES), len(context["anchors"]), 96))

    rhs_surface = Path(config["normal_driver_surface"])
    ridge_surface = data_root / "campaigns" / R102B_TAG / "surfaces" / "r98_control" / "scaled_ridge" / f"fold_{fold}"
    evidence.extend([
        artifact_record("r103_case_config", config_path),
        artifact_record("rhs_driver_terminal", rhs_surface / "terminal.json"),
        artifact_record("ridge_driver_terminal", ridge_surface / "terminal.json"),
    ])
    diagnostics = {policy: [] for policy in self_policies}
    for origin_index, anchor in enumerate(context["anchors"]):
        rhs, rhs_regions, records = read_driver(rhs_surface, origin_index, str(anchor))
        evidence.extend(records)
        ridge, ridge_regions, records = read_driver(ridge_surface, origin_index, str(anchor))
        evidence.extend(records)
        if rhs.shape[0] != n_paths or ridge.shape[0] != n_paths:
            raise RuntimeError("Normal driver path count changed")
        ridge_design = recursive_quantile_design(context, ridge, origin_index, ridge_regions)
        for tau_index, tau in enumerate(QUANTILES):
            predictions["normal_ridge_mean_conditional"][tau_index, origin_index] = paired_quantile_prediction(
                ridge_design, beta[float(tau)]
            )
        if len(context["active_regions"]) == 1:
            result = recursive_quantile_curve_forecast(
                context,
                rhs,
                origin_index,
                rhs_regions,
                beta,
                deterministic_seed(config["case_id"], family, origin_index, "self_quantile_curve"),
            )
            predictions["quantile_curve_self"][:, origin_index] = result["prediction"]
            diagnostics["quantile_curve_self"].append(result)
        else:
            for policy, driver, regions in (
                ("quantile_curve_self_rhs_neighbors", rhs, rhs_regions),
                ("quantile_curve_self_ridge_neighbors", ridge, ridge_regions),
            ):
                result = recursive_quantile_curve_forecast(
                    context,
                    driver,
                    origin_index,
                    regions,
                    beta,
                    deterministic_seed(config["case_id"], family, origin_index, "self_quantile_curve"),
                )
                predictions[policy][:, origin_index] = result["prediction"]
                diagnostics[policy].append(result)

    truth = scaled_to_original(context["truth"], scaler["center"], scaler["scale"])
    metric_rows = []
    horizon_frames = []
    saved = {}
    for policy, prediction_scaled in predictions.items():
        prediction = scaled_to_original(prediction_scaled, scaler["center"], scaler["scale"])
        values = score_surface(truth, prediction)
        diag = diagnostics.get(policy, [])
        values.update({
            "region": region,
            "fold": fold,
            "family": family,
            "policy": policy,
            "pre_rearrangement_crossing_rate": float(np.mean([x["pre_rearrangement_crossing_rate"] for x in diag])) if diag else np.nan,
            "rearrangement_mean_abs_scaled": float(np.mean([x["rearrangement_mean_abs"] for x in diag])) if diag else np.nan,
            "rearrangement_max_abs_scaled": float(np.max([x["rearrangement_max_abs"] for x in diag])) if diag else np.nan,
            "selection_split": "validation_only",
            "test_opened": False,
        })
        metric_rows.append(values)
        horizon_frames.append(horizon_metrics(region, fold, family, policy, truth, prediction))
        path = temporary / "predictions" / region / f"fold_{fold}" / f"{family}_{policy}.npz"
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(
            path,
            truth=truth.astype(np.float32),
            prediction=prediction.astype(np.float32),
            quantiles=np.asarray(QUANTILES),
            anchors=np.asarray(context["anchors"], dtype=str),
        )
        saved[policy] = {"truth": truth, "prediction": prediction, "anchors": context["anchors"]}
    return metric_rows, horizon_frames, evidence, saved


def completed_region_comparison(data_root: Path, case_frame: pd.DataFrame) -> pd.DataFrame:
    r102 = pd.read_csv(
        data_root / "authoritative" / "pricefm_stage_r102b_recursive_validation_closeout_20260916"
        / "pricefm_stage_r102b_region_metrics.csv"
    )
    r102 = r102[(r102.panel.eq("r98_control")) & (r102.prior_type.eq("rhs_ns"))]
    rows = []
    complete_regions = sorted(
        region for region, group in case_frame.groupby("region")
        if len(group) == 3 and group.case_complete.all()
    )
    for region in complete_regions:
        metric_frames = []
        for fold in (1, 2, 3):
            path = data_root / "campaigns" / R103_TAG / "cases" / f"region={region}" / f"fold={fold}" / "family_validation_metrics.csv"
            metric_frames.append(pd.read_csv(path))
        metrics = pd.concat(metric_frames, ignore_index=True)
        family = selected_family(metrics)
        selected = metrics[metrics.family.eq(family)]
        r103_aql = float(np.average(selected.validation_AQL_original, weights=selected.n_loss_atoms))
        normal = r102[r102.region.eq(region)]
        normal_aql = float(np.average(normal.validation_AQL_original, weights=normal.n_loss_atoms))
        closeout = data_root / "campaigns" / R97_TAG / "region_closeouts" / region
        old_manifest = pd.read_csv(closeout / "pricefm_stage_r97_selected_atom_manifest.csv")
        old_family = str(old_manifest.selected_family.iloc[0])
        old = pd.read_csv(closeout / "pricefm_stage_r97_family_fold_validation_metrics.csv")
        old = old[old.family.eq(old_family)]
        rows.append({
            "region": region,
            "R103_selected_family": family,
            "R103_validation_AQL": r103_aql,
            "Normal_RHS_driver_validation_AQL": normal_aql,
            "R97_direct_family": old_family,
            "R97_direct_validation_AQL": float(old.AQL.mean()),
            "R103_minus_R97": r103_aql - float(old.AQL.mean()),
        })
    result = pd.DataFrame(rows)
    if len(result) < 2:
        raise RuntimeError("insufficient complete R103 regions for diagnosis")
    return result.sort_values("R103_validation_AQL")


def representative_index(n_origins: int) -> int:
    return (int(n_origins) - 1) // 2


def write_forecast_pdf(
    path: Path,
    region: str,
    metrics: pd.DataFrame,
    horizons: pd.DataFrame,
    surfaces: Mapping[tuple[int, str], Mapping[str, np.ndarray]],
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    policies = list(dict.fromkeys(metrics.policy.tolist()))
    with PdfPages(path) as pdf:
        fig, axes = plt.subplots(1, 3, figsize=(15, 4.8))
        width = 0.8 / len(policies)
        for index, policy in enumerate(policies):
            subset = metrics[metrics.policy.eq(policy)].sort_values("fold")
            x = np.arange(1, 4) + (index - (len(policies) - 1) / 2) * width
            axes[0].bar(x, subset.AQL, width=width, color=COLORS[policy], label=LABELS[policy])
            axes[1].bar(x, subset.coverage_10_90, width=width, color=COLORS[policy])
            axes[2].bar(x, subset.mean_width_10_90, width=width, color=COLORS[policy])
        axes[0].set_title("Validation AQL (lower is better)")
        axes[1].set_title("10-90 predictive coverage")
        axes[1].axhline(0.8, color="#202428", linestyle="--", linewidth=1, label="Nominal 0.80")
        axes[2].set_title("Mean 10-90 interval width")
        for axis in axes:
            axis.set_xlabel("Fold")
            axis.set_xticks([1, 2, 3])
            axis.grid(axis="y", alpha=0.25)
        handles, labels = axes[0].get_legend_handles_labels()
        fig.legend(handles, labels, loc="lower center", ncol=min(2, len(labels)), frameon=False)
        fig.suptitle(f"{region}: no-refit recursive forecast-operator audit", fontsize=15)
        fig.tight_layout(rect=(0, 0.13, 1, 0.94))
        pdf.savefig(fig)
        plt.close(fig)

        for fold in (1, 2, 3):
            fig, axis = plt.subplots(figsize=(12, 5.5))
            for policy in policies:
                subset = horizons[(horizons.fold.eq(fold)) & horizons.policy.eq(policy)]
                axis.plot(subset.horizon, subset.AQL, color=COLORS[policy], linewidth=2, label=LABELS[policy])
            axis.set_title(f"{region}, Fold {fold}: validation AQL by horizon")
            axis.set_xlabel("Forecast horizon (hours)")
            axis.set_ylabel("AQL")
            axis.grid(alpha=0.25)
            axis.legend(frameon=False)
            fig.tight_layout()
            pdf.savefig(fig)
            plt.close(fig)

            fig, axes = plt.subplots(len(policies), 1, figsize=(13, 3.0 * len(policies)), sharex=True)
            axes = np.atleast_1d(axes)
            for axis, policy in zip(axes, policies):
                surface = surfaces[(fold, policy)]
                index = representative_index(surface["truth"].shape[0])
                prediction = surface["prediction"][:, index]
                truth = surface["truth"][index]
                x = np.arange(1, 97)
                axis.fill_between(x, prediction[0], prediction[-1], color=COLORS[policy], alpha=0.16, label="10-90%")
                axis.fill_between(x, prediction[1], prediction[5], color=COLORS[policy], alpha=0.27, label="25-75%")
                axis.plot(x, prediction[3], color=COLORS[policy], linewidth=1.8, label="Median")
                axis.plot(x, truth, color="#202428", linewidth=1.3, label="Observed")
                axis.set_ylabel("Price")
                axis.set_title(LABELS[policy], loc="left", fontsize=10)
                axis.grid(alpha=0.2)
            axes[-1].set_xlabel("Forecast horizon (hours)")
            handles, labels = axes[0].get_legend_handles_labels()
            fig.legend(handles, labels, loc="lower center", ncol=4, frameon=False)
            fig.suptitle(f"{region}, Fold {fold}: representative validation origin", fontsize=14)
            fig.tight_layout(rect=(0, 0.05, 1, 0.96))
            pdf.savefig(fig)
            plt.close(fig)


def write_trace_pdf(path: Path, atom_frame: pd.DataFrame, regions: Iterable[str]) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    with PdfPages(path) as pdf:
        for region in regions:
            for fold in (1, 2, 3):
                for family in ("al", "exal"):
                    subset = atom_frame[
                        atom_frame.region.eq(region)
                        & atom_frame.fold.eq(fold)
                        & atom_frame.family.eq(family)
                    ].sort_values("tau")
                    if len(subset) != len(QUANTILES):
                        raise RuntimeError(f"incomplete trace packet for {region} fold {fold} {family}")
                    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
                    for row in subset.itertuples(index=False):
                        trace = pd.read_csv(row.trace_path)
                        iteration = trace["iter"] if "iter" in trace else np.arange(1, len(trace) + 1)
                        gap = np.maximum(float(trace.elbo.iloc[-1]) - trace.elbo.to_numpy(dtype=float), 1e-12)
                        axes[0, 0].plot(iteration, gap, label=f"q={row.tau:g}")
                        axes[0, 1].plot(iteration, np.maximum(np.abs(trace.delta_state), 1e-12))
                        axes[1, 0].plot(iteration, trace.sigma)
                        if family == "exal" and "gamma" in trace:
                            axes[1, 1].plot(iteration, trace.gamma)
                        else:
                            axes[1, 1].plot(iteration, np.maximum(np.abs(trace.delta_elbo.fillna(np.nan)), 1e-12))
                    axes[0, 0].set_title("ELBO distance from terminal")
                    axes[0, 1].set_title("Absolute state change")
                    axes[1, 0].set_title("Sigma trace")
                    axes[1, 1].set_title("Gamma trace" if family == "exal" else "Absolute ELBO change")
                    axes[0, 0].set_yscale("log")
                    axes[0, 1].set_yscale("log")
                    if family == "al":
                        axes[1, 1].set_yscale("log")
                    for axis in axes.ravel():
                        axis.set_xlabel("Iteration")
                        axis.grid(alpha=0.2)
                    axes[0, 0].legend(frameon=False, ncol=2, fontsize=8)
                    fig.suptitle(f"{region}, Fold {fold}, {family.upper()}: VB convergence", fontsize=14)
                    fig.tight_layout(rect=(0, 0, 1, 0.96))
                    pdf.savefig(fig)
                    plt.close(fig)


def aggregate_operator_metrics(metrics: pd.DataFrame) -> pd.DataFrame:
    """Pool folds without selecting a different operator inside any fold."""
    weighted_columns = [
        "AQL",
        "AQCR",
        "coverage_10_90",
        "mean_width_10_90",
        "mean_width_25_75",
        "median_MAE",
        "median_RMSE",
        "pre_rearrangement_crossing_rate",
        "rearrangement_mean_abs_scaled",
        "rearrangement_max_abs_scaled",
    ]
    rows = []
    for (region, family, policy), group in metrics.groupby(
        ["region", "family", "policy"], sort=True
    ):
        weights = group["n_loss_atoms"].to_numpy(dtype=float)
        row = {
            "region": region,
            "family": family,
            "policy": policy,
            "folds": int(group["fold"].nunique()),
            "n_origins": int(group["n_origins"].sum()),
            "n_loss_atoms": int(weights.sum()),
            "selection_split": "validation",
            "test_opened": False,
        }
        for column in weighted_columns:
            values = group[column].to_numpy(dtype=float)
            finite = np.isfinite(values)
            row[column] = (
                float(np.average(values[finite], weights=weights[finite]))
                if finite.any()
                else np.nan
            )
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["region", "AQL", "policy"]).reset_index(drop=True)


def write_report(
    path: Path,
    freeze: dict[str, Any],
    comparison: pd.DataFrame,
    metrics: pd.DataFrame,
    aggregate: pd.DataFrame,
) -> None:
    current = metrics[metrics.policy.eq("normal_rhs_mean_conditional")]
    candidate = metrics[metrics.policy.str.startswith("quantile_curve_self")]
    merged = current.merge(
        candidate,
        on=["region", "fold", "family"],
        suffixes=("_current", "_candidate"),
    ).sort_values(["region", "policy_candidate", "fold"])
    lines = [
        "# PriceFM Stage-R104 forecast-operator diagnosis",
        "",
        "## Status",
        "",
        f"R103 is frozen with {freeze['cases_complete']}/114 complete cases and "
        f"{freeze['completed_atoms']}/1,596 completed atoms. No R103 process was "
        "active while this packet was materialized. Test, registry, article, joint, "
        "and MCMC access remained blocked.",
        "",
        "## Interpretation boundary",
        "",
        "This packet compares validation-only forecast operators while reusing the "
        "same fitted independent AL/exAL readouts. It does not select an article "
        "model and does not authorize a broad relaunch. The quantile-curve diagnostic "
        "uses bounded 0.10--0.90 interpolation; tail behavior remains a later design "
        "question.",
        "",
        "## Frozen completed-region evidence",
        "",
        comparison.to_markdown(index=False, floatfmt=".4f"),
        "",
        "## Focus-region operator comparison",
        "",
        metrics[[
            "region", "fold", "family", "policy", "AQL", "coverage_10_90",
            "mean_width_10_90", "AQCR", "median_MAE",
            "pre_rearrangement_crossing_rate",
        ]].to_markdown(index=False, floatfmt=".4f"),
        "",
        "## Fixed-policy aggregate comparison",
        "",
        "Operators are pooled over all three folds as fixed policies. No operator is "
        "selected separately within a fold.",
        "",
        aggregate[[
            "region", "family", "policy", "folds", "AQL", "coverage_10_90",
            "mean_width_10_90", "AQCR", "median_MAE",
            "pre_rearrangement_crossing_rate",
        ]].to_markdown(index=False, floatfmt=".4f"),
        "",
        "## Every candidate delta against current R103",
        "",
        merged[[
            "region", "fold", "policy_candidate", "AQL_current", "AQL_candidate",
            "coverage_10_90_current", "coverage_10_90_candidate",
        ]].to_markdown(index=False, floatfmt=".4f"),
        "",
        "## Human review gate",
        "",
        "Review the forecast and convergence PDFs before accepting any operator. "
        "AQL improvement alone is insufficient: coverage, horizon stability, curve "
        "crossing, path boundedness, and scientific interpretation must also be "
        "acceptable. No broad run may resume without explicit user confirmation.",
        "",
    ]
    path.write_text("\n".join(lines))


def run(args: argparse.Namespace) -> dict[str, Any]:
    data_root = args.data_root.resolve()
    output = args.output_dir.resolve()
    regions = tuple(value.strip() for value in args.regions.split(",") if value.strip())
    if regions != FOCUS_REGIONS:
        raise ValueError("R104 is bounded to BG,BE in that order")
    if int(args.posterior_paths) != 500:
        raise ValueError("R104 must first diagnose the frozen 500-path contract")
    case_frame, atom_frame, freeze = freeze_partial_campaign(data_root)
    comparison = completed_region_comparison(data_root, case_frame)
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        metric_rows = []
        horizon_frames = []
        evidence = []
        all_surfaces: dict[str, dict[tuple[int, str], Mapping[str, np.ndarray]]] = {}
        for region in regions:
            region_surfaces = {}
            metric_frames = []
            for fold in (1, 2, 3):
                case_metrics = pd.read_csv(
                    data_root / "campaigns" / R103_TAG / "cases" / f"region={region}" / f"fold={fold}"
                    / "family_validation_metrics.csv"
                )
                metric_frames.append(case_metrics)
            family = selected_family(pd.concat(metric_frames, ignore_index=True))
            for fold in (1, 2, 3):
                rows, horizons, records, surfaces = diagnose_case(
                    data_root, temporary, region, fold, family, int(args.posterior_paths)
                )
                metric_rows.extend(rows)
                horizon_frames.extend(horizons)
                evidence.extend(records)
                for policy, surface in surfaces.items():
                    region_surfaces[(fold, policy)] = surface
            all_surfaces[region] = region_surfaces
        metrics = pd.DataFrame(metric_rows).sort_values(["region", "fold", "policy"])
        aggregate = aggregate_operator_metrics(metrics)
        horizons = pd.concat(horizon_frames, ignore_index=True).sort_values(
            ["region", "fold", "policy", "horizon"]
        )
        case_frame.to_csv(temporary / "pricefm_stage_r104_partial_case_ledger.csv", index=False)
        atom_frame.to_csv(temporary / "pricefm_stage_r104_partial_atom_ledger.csv", index=False)
        comparison.to_csv(temporary / "pricefm_stage_r104_completed_region_diagnosis.csv", index=False)
        metrics.to_csv(temporary / "pricefm_stage_r104_operator_metrics.csv", index=False)
        aggregate.to_csv(temporary / "pricefm_stage_r104_operator_aggregate_metrics.csv", index=False)
        horizons.to_csv(temporary / "pricefm_stage_r104_operator_horizon_metrics.csv", index=False)
        source_manifest = pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(["role", "path"])
        source_manifest.to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        atomic_json(temporary / "pricefm_stage_r104_partial_freeze.json", freeze)
        for region in regions:
            write_forecast_pdf(
                temporary / f"pricefm_stage_r104_{region.lower()}_forecast_operator_diagnostics.pdf",
                region,
                metrics[metrics.region.eq(region)],
                horizons[horizons.region.eq(region)],
                all_surfaces[region],
            )
        write_trace_pdf(
            temporary / "pricefm_stage_r104_bg_be_vb_convergence_diagnostics.pdf",
            atom_frame,
            regions,
        )
        write_report(
            temporary / "pricefm_stage_r104_forecast_operator_diagnosis.md",
            freeze,
            comparison,
            metrics,
            aggregate,
        )
        outputs = []
        for path in sorted(temporary.rglob("*")):
            if path.is_file() and path.name != "summary.json":
                outputs.append({
                    "path": str((output / path.relative_to(temporary)).resolve()),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        summary = {
            **freeze,
            "status": "completed_validation_only_forecast_operator_diagnosis",
            "focus_regions": list(regions),
            "posterior_paths": int(args.posterior_paths),
            "operator_rows": int(len(metrics)),
            "operator_aggregate_rows": int(len(aggregate)),
            "broad_relaunch_authorized": False,
            "next_gate": "user_visual_review_and_explicit_operator_confirmation",
            "outputs": outputs,
        }
        atomic_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> int:
    run(parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
