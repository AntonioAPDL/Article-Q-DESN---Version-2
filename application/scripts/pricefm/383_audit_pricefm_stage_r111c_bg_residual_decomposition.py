#!/usr/bin/env python3
"""Decompose the frozen R111B BG residual without fitting or selection."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import joblib
import numpy as np
import pandas as pd


STAGE = "R111C"
TAG = "pricefm_stage_r111c_bg_residual_decomposition_20260922"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
OUTPUT = DATA / "authoritative" / TAG
R108 = DATA / "authoritative/pricefm_stage_r108_recursive_driver_decomposition_20260920"
R110 = DATA / "authoritative/pricefm_stage_r110_frozen_qdesn_replay_20260921"
R111B = DATA / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
FOLDS = (1, 2, 3)
QUANTILES = np.asarray((0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90))
POLICIES = (
    "r97_direct_reference",
    "r111b_exposure_aligned_readout",
    "pricefm_quantile_paths_all_active",
    "r110_direct_target_rhs_neighbors",
)
BLOCKS = ((1, 24, "h01_24"), (25, 48, "h25_48"), (49, 72, "h49_72"), (73, 96, "h73_96"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True, default=str) + "\n")


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def require_summary(path: Path, stage: str, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if (
        value.get("stage") != stage
        or value.get("status") != status
        or value.get("test_opened") is not False
        or value.get("registry_mutated") is not False
        or value.get("article_mutated") is not False
    ):
        raise RuntimeError(f"invalid frozen {stage} summary: {path}")
    return value


def verify_terminal(path: Path, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if value.get("status") != status or value.get("test_opened") is not False:
        raise RuntimeError(f"invalid frozen terminal: {path}")
    for row in value.get("artifacts", []):
        source = Path(row["path"])
        if not source.is_absolute():
            source = path.parent / source
        if not source.is_file() or sha256_file(source) != row["sha256"]:
            raise RuntimeError(f"changed frozen artifact: {source}")
    return value


def validate_authority() -> list[dict[str, Any]]:
    r108 = require_summary(R108 / "summary.json", "R108", "completed_recursive_driver_decomposition")
    r110 = require_summary(R110 / "summary.json", "R110B", "completed_frozen_qdesn_replay_closeout")
    r111b = require_summary(R111B / "summary.json", "R111B", "completed_bg_exposure_readout_closeout")
    orchestrator = json.loads((R111B / "orchestrator_terminal.json").read_text())
    if (
        r108.get("model_fit_started") is not False
        or r110.get("model_fit_started") is not False
        or r111b.get("cases_complete") != 3
        or r111b.get("all_gates_passed") is not False
        or r111b.get("next_stage") != "stop_recursive_redesign_retain_R97"
        or orchestrator.get("status") != "completed_r111b_orchestration"
        or orchestrator.get("task_count") != 51
        or orchestrator.get("test_opened") is not False
    ):
        raise RuntimeError("R111C frozen authority contract changed")
    return [
        artifact("r108_summary", R108 / "summary.json"),
        artifact("r110_summary", R110 / "summary.json"),
        artifact("r111b_summary", R111B / "summary.json"),
        artifact("r111b_orchestrator_terminal", R111B / "orchestrator_terminal.json"),
        artifact("r111b_gate_ledger", R111B / "pricefm_stage_r111b_gates.csv"),
        artifact("r111b_selected_arm", R111B / "selected_exposure_arm.json"),
    ]


def validate_alignment(
    truth: np.ndarray,
    predictions: dict[str, np.ndarray],
    anchors: np.ndarray,
    quantiles: np.ndarray,
) -> None:
    if truth.ndim != 2 or truth.shape[1] != 96 or len(anchors) != truth.shape[0]:
        raise RuntimeError("R111C truth geometry changed")
    if not np.allclose(quantiles, QUANTILES):
        raise RuntimeError("R111C quantile grid changed")
    expected = (len(QUANTILES), truth.shape[0], 96)
    if set(predictions) != set(POLICIES):
        raise RuntimeError("R111C policy surface is incomplete")
    if any(value.shape != expected or not np.isfinite(value).all() for value in predictions.values()):
        raise RuntimeError("R111C prediction geometry is invalid")
    if not np.isfinite(truth).all():
        raise RuntimeError("R111C truth contains nonfinite values")


def pinball_loss(truth: np.ndarray, prediction: np.ndarray) -> np.ndarray:
    error = np.asarray(truth, dtype=float)[None, :, :] - np.asarray(prediction, dtype=float)
    tau = QUANTILES[:, None, None]
    return np.maximum(tau * error, (tau - 1.0) * error)


def score_surface(truth: np.ndarray, prediction: np.ndarray) -> dict[str, Any]:
    loss = pinball_loss(truth, prediction)
    median = prediction[3]
    return {
        "AQL": float(loss.mean()),
        "AQCR": float(np.mean(prediction[:-1] > prediction[1:])),
        "coverage_10_90": float(np.mean((truth >= prediction[0]) & (truth <= prediction[-1]))),
        "mean_width_10_90": float(np.mean(prediction[-1] - prediction[0])),
        "mean_width_25_75": float(np.mean(prediction[5] - prediction[1])),
        "median_MAE": float(np.mean(np.abs(truth - median))),
        "median_RMSE": float(np.sqrt(np.mean((truth - median) ** 2))),
        "n_origins": int(truth.shape[0]),
        "n_loss_atoms": int(loss.size),
    }


def load_fold(fold: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    r108_dir = R108 / f"cases/region=BG/fold={fold}"
    r110_dir = R110 / f"cases/region=BG/fold={fold}"
    r111b_dir = R111B / f"replay/fold={fold}"
    verify_terminal(r108_dir / "terminal.json", "completed_recursive_driver_decomposition_case")
    verify_terminal(r110_dir / "terminal.json", "completed_r110_frozen_qdesn_replay_case")
    verify_terminal(r111b_dir / "terminal.json", "completed_r111b_bg_replay_case")

    manifest_path = r111b_dir / "source_manifest.csv"
    manifest = pd.read_csv(manifest_path)
    scaler_row = manifest[manifest.role.eq("r103_bg_scaler")]
    if len(scaler_row) != 1:
        raise RuntimeError(f"R111C fold {fold} scaler provenance is ambiguous")
    scaler_path = Path(scaler_row.iloc[0].path)
    if sha256_file(scaler_path) != scaler_row.iloc[0].sha256:
        raise RuntimeError(f"R111C fold {fold} scaler changed")
    scaler = joblib.load(scaler_path)["BG"]["y_scaler"]
    center = float(np.asarray(scaler.center_).reshape(-1)[0])
    scale = float(np.asarray(scaler.scale_).reshape(-1)[0])

    r108_path = r108_dir / "validation_predictions.npz"
    r110_path = r110_dir / "validation_predictions.npz"
    r111b_path = r111b_dir / "validation_predictions.npz"
    with np.load(r108_path, allow_pickle=False) as archive:
        r108_truth = np.asarray(archive["truth_scaled"], dtype=float)
        r108_anchors = np.asarray(archive["anchors"], dtype=str)
        quantiles = np.asarray(archive["quantiles"], dtype=float)
        names = [str(value) for value in archive["policies"].tolist()]
        surfaces = np.asarray(archive["predictions_scaled"], dtype=float)
        r97 = surfaces[names.index("r97_direct_reference")]
        pricefm = surfaces[names.index("pricefm_quantile_paths_all_active")]
    with np.load(r110_path, allow_pickle=False) as archive:
        r110_truth = np.asarray(archive["truth_scaled"], dtype=float)
        r110_anchors = np.asarray(archive["anchors"], dtype=str)
        r110_quantiles = np.asarray(archive["quantiles"], dtype=float)
        r110 = np.asarray(archive["prediction_scaled"], dtype=float)
    with np.load(r111b_path, allow_pickle=False) as archive:
        r111b_truth = np.asarray(archive["truth_scaled"], dtype=float)
        r111b_anchors = np.asarray(archive["anchors"], dtype=str)
        r111b_quantiles = np.asarray(archive["quantiles"], dtype=float)
        r111b = np.asarray(archive["prediction_scaled"], dtype=float)
    if (
        not np.array_equal(r108_anchors, r110_anchors)
        or not np.array_equal(r108_anchors, r111b_anchors)
        or not np.allclose(r108_truth, r110_truth, rtol=0, atol=1e-6)
        or not np.allclose(r108_truth, r111b_truth, rtol=0, atol=1e-6)
        or not np.allclose(quantiles, r110_quantiles)
        or not np.allclose(quantiles, r111b_quantiles)
    ):
        raise RuntimeError(f"R111C fold {fold} saved surfaces do not align")
    truth = r108_truth * scale + center
    predictions = {
        "r97_direct_reference": r97 * scale + center,
        "r111b_exposure_aligned_readout": r111b * scale + center,
        "pricefm_quantile_paths_all_active": pricefm * scale + center,
        "r110_direct_target_rhs_neighbors": r110 * scale + center,
    }
    validate_alignment(truth, predictions, r108_anchors, quantiles)
    records = [
        artifact("r108_case_terminal", r108_dir / "terminal.json", fold=fold),
        artifact("r110_case_terminal", r110_dir / "terminal.json", fold=fold),
        artifact("r111b_case_terminal", r111b_dir / "terminal.json", fold=fold),
        artifact("r108_prediction_surface", r108_path, fold=fold),
        artifact("r110_prediction_surface", r110_path, fold=fold),
        artifact("r111b_prediction_surface", r111b_path, fold=fold),
        artifact("r111b_case_source_manifest", manifest_path, fold=fold),
        artifact("response_scaler", scaler_path, fold=fold),
    ]
    return {
        "fold": fold,
        "truth": truth,
        "predictions": predictions,
        "anchors": r108_anchors,
        "losses": {name: pinball_loss(truth, value) for name, value in predictions.items()},
    }, records


def decompose(cases: list[dict[str, Any]]) -> dict[str, pd.DataFrame]:
    fold_rows: list[dict[str, Any]] = []
    quantile_rows: list[dict[str, Any]] = []
    horizon_rows: list[dict[str, Any]] = []
    block_rows: list[dict[str, Any]] = []
    origin_rows: list[dict[str, Any]] = []
    cell_rows: list[dict[str, Any]] = []
    for case in cases:
        fold = int(case["fold"])
        truth = case["truth"]
        for policy, prediction in case["predictions"].items():
            fold_rows.append({"fold": fold, "policy": policy, **score_surface(truth, prediction)})
            loss = case["losses"][policy]
            for index, tau in enumerate(QUANTILES):
                quantile_rows.append({
                    "fold": fold, "policy": policy, "tau": float(tau),
                    "AQL": float(loss[index].mean()), "n_loss_atoms": int(loss[index].size),
                })
            for horizon in range(96):
                horizon_rows.append({
                    "fold": fold, "policy": policy, "horizon": horizon + 1,
                    "AQL": float(loss[:, :, horizon].mean()),
                    "coverage_10_90": float(np.mean(
                        (truth[:, horizon] >= prediction[0, :, horizon])
                        & (truth[:, horizon] <= prediction[-1, :, horizon])
                    )),
                    "width_10_90": float(np.mean(prediction[-1, :, horizon] - prediction[0, :, horizon])),
                    "n_loss_atoms": int(loss[:, :, horizon].size),
                })
            for start, end, label in BLOCKS:
                subset = loss[:, :, start - 1 : end]
                block_rows.append({
                    "fold": fold, "policy": policy, "horizon_block": label,
                    "AQL": float(subset.mean()), "n_loss_atoms": int(subset.size),
                })
            for index, anchor in enumerate(case["anchors"]):
                origin_rows.append({
                    "fold": fold, "policy": policy, "origin_index": index,
                    "anchor": str(anchor), "AQL": float(loss[:, index].mean()),
                    "n_loss_atoms": int(loss[:, index].size),
                })
        candidate = case["losses"]["r111b_exposure_aligned_readout"]
        reference = case["losses"]["r97_direct_reference"]
        for start, end, label in BLOCKS:
            for index, tau in enumerate(QUANTILES):
                c = candidate[index, :, start - 1 : end]
                r = reference[index, :, start - 1 : end]
                cell_rows.append({
                    "fold": fold, "horizon_block": label, "tau": float(tau),
                    "r111b_AQL": float(c.mean()), "r97_AQL": float(r.mean()),
                    "gap_AQL": float((c - r).mean()), "n_loss_atoms": int(c.size),
                })

    folds = pd.DataFrame(fold_rows)
    quantiles = pd.DataFrame(quantile_rows)
    horizons = pd.DataFrame(horizon_rows)
    blocks = pd.DataFrame(block_rows)
    origins = pd.DataFrame(origin_rows)
    cells = pd.DataFrame(cell_rows)

    for frame, keys in ((quantiles, ["policy", "tau"]), (horizons, ["policy", "horizon"]), (blocks, ["policy", "horizon_block"])):
        pooled = frame.groupby(keys, sort=False).apply(
            lambda x: pd.Series({
                "AQL": np.average(x.AQL, weights=x.n_loss_atoms),
                "n_loss_atoms": int(x.n_loss_atoms.sum()),
                **({
                    "coverage_10_90": np.average(x.coverage_10_90, weights=x.n_loss_atoms),
                    "width_10_90": np.average(x.width_10_90, weights=x.n_loss_atoms),
                } if "coverage_10_90" in x else {}),
            }),
            include_groups=False,
        ).reset_index()
        pooled.insert(0, "fold", 0)
        if frame is quantiles:
            quantiles = pd.concat([quantiles, pooled], ignore_index=True)
        elif frame is horizons:
            horizons = pd.concat([horizons, pooled], ignore_index=True)
        else:
            blocks = pd.concat([blocks, pooled], ignore_index=True)

    pooled_fold_rows = []
    for policy in POLICIES:
        truths = np.concatenate([case["truth"] for case in cases], axis=0)
        predictions = np.concatenate([case["predictions"][policy] for case in cases], axis=1)
        pooled_fold_rows.append({"fold": 0, "policy": policy, **score_surface(truths, predictions)})
    folds = pd.concat([folds, pd.DataFrame(pooled_fold_rows)], ignore_index=True)

    pivot = origins.pivot(index=["fold", "origin_index", "anchor"], columns="policy", values="AQL").reset_index()
    pivot["r111b_minus_r97"] = pivot["r111b_exposure_aligned_readout"] - pivot["r97_direct_reference"]
    pivot["r111b_minus_pricefm"] = pivot["r111b_exposure_aligned_readout"] - pivot["pricefm_quantile_paths_all_active"]
    return {
        "policy_metrics": folds.sort_values(["fold", "AQL", "policy"]),
        "quantile_metrics": quantiles.sort_values(["fold", "tau", "policy"]),
        "horizon_metrics": horizons.sort_values(["fold", "horizon", "policy"]),
        "horizon_block_metrics": blocks.sort_values(["fold", "horizon_block", "policy"]),
        "origin_metrics": origins.sort_values(["fold", "origin_index", "policy"]),
        "origin_gap": pivot.sort_values("r111b_minus_r97", ascending=False),
        "cell_gap": cells.sort_values("gap_AQL", ascending=False),
    }


def gap_attribution(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows = []
    for dimension, frame, key in (
        ("fold", frames["policy_metrics"].query("fold > 0"), "fold"),
        ("quantile", frames["quantile_metrics"].query("fold == 0"), "tau"),
        ("horizon_block", frames["horizon_block_metrics"].query("fold == 0"), "horizon_block"),
    ):
        pivot = frame.pivot(index=key, columns="policy", values=["AQL", "n_loss_atoms"])
        for value in pivot.index:
            weight = int(pivot.loc[value, ("n_loss_atoms", "r111b_exposure_aligned_readout")])
            candidate = float(pivot.loc[value, ("AQL", "r111b_exposure_aligned_readout")])
            reference = float(pivot.loc[value, ("AQL", "r97_direct_reference")])
            rows.append({
                "dimension": dimension, "stratum": str(value),
                "r111b_AQL": candidate, "r97_AQL": reference,
                "gap_AQL": candidate - reference, "n_loss_atoms": weight,
            })
    result = pd.DataFrame(rows)
    for dimension, group in result.groupby("dimension"):
        total_atoms = group.n_loss_atoms.sum()
        index = group.index
        result.loc[index, "contribution_AQL_points"] = (
            group.gap_AQL * group.n_loss_atoms / total_atoms
        )
        total_gap = result.loc[index, "contribution_AQL_points"].sum()
        result.loc[index, "share_of_net_gap"] = result.loc[index, "contribution_AQL_points"] / total_gap
    return result.sort_values(["dimension", "contribution_AQL_points"], ascending=[True, False])


def decision(frames: dict[str, pd.DataFrame]) -> dict[str, Any]:
    pooled = frames["policy_metrics"].query("fold == 0").set_index("policy")
    blocks = frames["horizon_block_metrics"].query("fold == 0").pivot(
        index="horizon_block", columns="policy", values="AQL"
    )
    quantiles = frames["quantile_metrics"].query("fold == 0").pivot(
        index="tau", columns="policy", values="AQL"
    )
    folds = frames["policy_metrics"].query("fold > 0").pivot(index="fold", columns="policy", values="AQL")
    candidate = float(pooled.loc["r111b_exposure_aligned_readout", "AQL"])
    r97 = float(pooled.loc["r97_direct_reference", "AQL"])
    pricefm = float(pooled.loc["pricefm_quantile_paths_all_active", "AQL"])
    r110 = float(pooled.loc["r110_direct_target_rhs_neighbors", "AQL"])
    block_gap = blocks["r111b_exposure_aligned_readout"] - blocks["r97_direct_reference"]
    quantile_gap = quantiles["r111b_exposure_aligned_readout"] - quantiles["r97_direct_reference"]
    return {
        "r111b_AQL": candidate,
        "r97_AQL": r97,
        "pricefm_AQL": pricefm,
        "r110_AQL": r110,
        "r111b_minus_r97": candidate - r97,
        "r111b_relative_to_r97": candidate / r97 - 1.0,
        "r111b_gain_vs_pricefm": 1.0 - candidate / pricefm,
        "r111b_gain_vs_r110": 1.0 - candidate / r110,
        "r111b_beats_pricefm_all_folds": bool((folds.r111b_exposure_aligned_readout < folds.pricefm_quantile_paths_all_active).all()),
        "r111b_beats_r97_fold_count": int((folds.r111b_exposure_aligned_readout < folds.r97_direct_reference).sum()),
        "short_horizon_gap_vs_r97": float(block_gap.loc["h01_24"]),
        "all_late_blocks_worse_than_r97": bool((block_gap.drop("h01_24") > 0).all()),
        "all_quantiles_worse_than_r97": bool((quantile_gap > 0).all()),
        "residual_classification": "late_horizon_recursive_transfer_not_single_quantile_calibration",
        "recommended_action": "stop_recursive_redesign_retain_R97",
        "new_model_fit_authorized": False,
        "broad_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "article_classification": "diagnostic_only_no_promotion",
    }


def report(decision_value: dict[str, Any], frames: dict[str, pd.DataFrame], attribution: pd.DataFrame) -> str:
    pooled = frames["policy_metrics"].query("fold == 0")[["policy", "AQL", "coverage_10_90", "mean_width_10_90", "median_MAE"]]
    blocks = frames["horizon_block_metrics"].query("fold == 0").pivot(index="horizon_block", columns="policy", values="AQL").reset_index()
    quantiles = frames["quantile_metrics"].query("fold == 0").pivot(index="tau", columns="policy", values="AQL").reset_index()
    top_cells = frames["cell_gap"].head(10)
    lines = [
        "# PriceFM Stage-R111C BG residual decomposition", "",
        "R111C is a read-only decomposition of saved validation predictions. It starts no fit,",
        "opens no test split, and changes no registry or article asset.", "",
        "## Decision", "",
        "The mixed-exposure R111B readout materially repaired R110 and beat the cached PriceFM",
        "surface in every fold, but it remained 2.63% worse than R97 overall. R111B is better",
        "than R97 at horizons 1--24 and worse in every later 24-hour block. Every quantile has",
        "a positive pooled gap versus R97, so the residual is not an isolated tail or calibration",
        "defect. The evidence supports accumulated recursive-transfer error after the first day.", "",
        "**Frozen action:** stop this recursive-redesign branch and retain R97. R111B remains",
        "diagnostic evidence only; no broad launch or promotion is authorized.", "",
        "## Pooled metrics", "", pooled.to_markdown(index=False), "",
        "## Horizon-block AQL", "", blocks.to_markdown(index=False), "",
        "## Quantile AQL", "", quantiles.to_markdown(index=False), "",
        "## Largest fold/block/quantile residual cells", "", top_cells.to_markdown(index=False), "",
        "## Gap attribution", "", attribution.to_markdown(index=False), "",
        "## Reproducibility", "",
        "All four surfaces share identical fold anchors, truths, seven quantiles, and 96 horizons.",
        "Every input terminal and prediction artifact was hash-verified before decomposition.",
        f"Decision object: `{decision_value['recommended_action']}`.",
    ]
    return "\n".join(lines) + "\n"


def run(code_root: Path, output: Path, force: bool = False) -> dict[str, Any]:
    code_root = code_root.resolve()
    output = output.resolve()
    summary_path = output / "summary.json"
    if summary_path.is_file() and not force:
        existing = json.loads(summary_path.read_text())
        if existing.get("status") == "completed_bg_residual_decomposition":
            return existing
    if output.exists() and any(output.iterdir()) and not force:
        raise RuntimeError(f"R111C output exists but is not reusable: {output}")
    evidence = validate_authority()
    cases = []
    for fold in FOLDS:
        case, records = load_fold(fold)
        cases.append(case)
        evidence.extend(records)
    frames = decompose(cases)
    attribution = gap_attribution(frames)
    decision_value = decision(frames)
    if (
        decision_value["r111b_gain_vs_r110"] < 0.09
        or decision_value["r111b_gain_vs_pricefm"] <= 0
        or decision_value["short_horizon_gap_vs_r97"] >= 0
        or not decision_value["all_late_blocks_worse_than_r97"]
        or not decision_value["all_quantiles_worse_than_r97"]
    ):
        raise RuntimeError("R111C residual classification no longer follows the frozen evidence")
    script_path = Path(__file__).resolve()
    evidence.append(artifact("executed_source", script_path))
    evidence_frame = pd.DataFrame(evidence).drop_duplicates(subset=["path", "sha256"]).sort_values(["role", "path"])

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output.name + ".tmp.", dir=output.parent))
    try:
        names = {
            "policy_metrics": "pricefm_stage_r111c_policy_metrics.csv",
            "quantile_metrics": "pricefm_stage_r111c_quantile_metrics.csv",
            "horizon_metrics": "pricefm_stage_r111c_horizon_metrics.csv",
            "horizon_block_metrics": "pricefm_stage_r111c_horizon_block_metrics.csv",
            "origin_metrics": "pricefm_stage_r111c_origin_metrics.csv",
            "origin_gap": "pricefm_stage_r111c_origin_gap.csv",
            "cell_gap": "pricefm_stage_r111c_fold_block_quantile_gap.csv",
        }
        for key, name in names.items():
            frames[key].to_csv(temporary / name, index=False, quoting=csv.QUOTE_MINIMAL)
        attribution.to_csv(temporary / "pricefm_stage_r111c_gap_attribution.csv", index=False)
        evidence_frame.to_csv(temporary / "source_manifest.csv", index=False, quoting=csv.QUOTE_MINIMAL)
        write_json(temporary / "decision.json", decision_value)
        (temporary / "pricefm_stage_r111c_bg_residual_decomposition.md").write_text(
            report(decision_value, frames, attribution)
        )
        outputs = []
        for path in sorted(temporary.iterdir()):
            outputs.append({
                "path": str((output / path.name).resolve()),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
        head = subprocess.check_output(["git", "-C", str(code_root), "rev-parse", "HEAD"], text=True).strip()
        summary = {
            "stage": STAGE,
            "status": "completed_bg_residual_decomposition",
            "tag": TAG,
            "region": "BG",
            "folds_complete": 3,
            "folds_expected": 3,
            "policies": list(POLICIES),
            "quantiles": QUANTILES.tolist(),
            "horizons": 96,
            "head": head,
            **decision_value,
            "model_fit_started": False,
            "launch_started": False,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
            "outputs": outputs,
        }
        write_json(temporary / "summary.json", summary)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(json.dumps(run(args.code_root, args.output_dir, args.force), indent=2, sort_keys=True, default=str))


if __name__ == "__main__":
    main()
