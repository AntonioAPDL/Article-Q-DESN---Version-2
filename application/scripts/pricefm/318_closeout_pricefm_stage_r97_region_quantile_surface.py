#!/usr/bin/env python3
"""Select one whole AL/exAL family for an R97 region using validation only."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys
from typing import Any

import joblib
import numpy as np
import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_metrics import inverse_scale_y, metric_dict
from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    file_record,
    prepare_empty_directory,
    sha256_file,
    validate_no_test_adapter,
    validate_quantiles,
    verify_file_record,
)


FOLDS = (1, 2, 3)
FAMILIES = ("al", "exal")
BLOCKED = (
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--manifest", type=Path, required=True)
    value.add_argument("--pipeline-contract", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def terminal(task: dict[str, Any]) -> tuple[dict[str, Any], Path]:
    path = Path(task["output_dir"]) / "terminal.json"
    if not path.is_file():
        raise FileNotFoundError(path)
    payload = json.loads(path.read_text())
    if (
        payload.get("task_id") != task["task_id"]
        or payload.get("pipeline_contract_sha256") != task["pipeline_contract_sha256"]
        or payload.get("status") not in {"completed", "completed_numerically_ineligible"}
        or payload.get("test_loaded") is not False
        or payload.get("test_opened") is not False
        or payload.get("test_access_authorized") is not False
    ):
        raise RuntimeError(f"R97 task terminal is invalid or unsealed: {path}")
    for record in payload.get("artifacts") or []:
        verify_file_record(record, label="R97 task artifact")
    return payload, path


def family_fold(
    tasks: list[dict[str, Any]], family: str, fold: int,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    selected = sorted(
        [task for task in tasks if task["likelihood_family"] == family and int(task["fold"]) == fold],
        key=lambda task: float(task["tau"]),
    )
    if len(selected) != 7:
        raise RuntimeError(f"R97 {family} fold {fold} does not contain seven atoms")
    validate_quantiles([task["tau"] for task in selected], label=f"R97 {family} fold {fold}")
    adapter = Path(selected[0]["adapter_dir"])
    validate_no_test_adapter(adapter)
    rows_path = adapter / "rows_val.csv"
    rows = pd.read_csv(rows_path)
    data = yaml.safe_load(Path(selected[0]["data_config"]).read_text())["pricefm"]
    scaler_path = Path(data["processed_dir"]) / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)[selected[0]["region"]]["y_scaler"]
    prediction_frames = []
    atom_records = []
    evidence = [
        file_record(rows_path, f"fold{fold}_validation_rows"),
        file_record(scaler_path, f"fold{fold}_scaler"),
    ]
    eligible = True
    for task in selected:
        payload, terminal_path = terminal(task)
        atom_eligible = payload.get("status") == "completed" and payload.get("numerical_gate_passed") is True
        eligible = eligible and atom_eligible
        beta_path = Path(task["output_dir"]) / "beta_summary.csv"
        prediction_path = Path(task["output_dir"]) / "predictions_scaled.csv"
        prediction_frames.append(pd.read_csv(prediction_path))
        atom = {
            "region": task["region"], "fold": fold, "family": family,
            "tau": float(task["tau"]), "task_id": task["task_id"],
            "beta": file_record(beta_path, f"fold{fold}_{family}_beta"),
            "prediction": file_record(prediction_path, f"fold{fold}_{family}_validation_prediction"),
            "terminal": file_record(terminal_path, f"fold{fold}_{family}_terminal"),
            "source_case_config": file_record(Path(task["normal_full_config"]), "source_case_config"),
            "feature_manifest": file_record(adapter / "feature_manifest.json", "feature_manifest"),
            "x_val": file_record(adapter / "X_val.csv", "validation_design"),
            "rows_val": file_record(rows_path, "validation_rows"),
            "scaler": file_record(scaler_path, "fold_scaler"),
        }
        atom_records.append(atom)
        evidence.extend(atom[name] for name in ("beta", "prediction", "terminal"))
    predictions = pd.concat(prediction_frames, ignore_index=True)
    keys = ["origin_id", "horizon"]
    if set(predictions.split.astype(str)) != {"val"} or predictions.duplicated(keys + ["tau"]).any():
        raise RuntimeError(f"R97 {family} fold {fold} validation prediction identity is invalid")
    wide = predictions.pivot(index=keys, columns="tau", values="pred_scaled").reindex(columns=list(PAPER_QUANTILES))
    aligned = rows[keys + ["y_scaled"]].merge(wide.reset_index(), on=keys, how="left", validate="one_to_one")
    if len(aligned) != len(rows) or aligned[list(PAPER_QUANTILES)].isna().any().any():
        raise RuntimeError(f"R97 {family} fold {fold} predictions do not align")
    truth = inverse_scale_y(aligned.y_scaled.to_numpy(float), scaler)
    prediction = inverse_scale_y(aligned[list(PAPER_QUANTILES)].to_numpy(float), scaler)
    metrics = {
        "region": selected[0]["region"], "fold": fold, "family": family,
        "numerically_eligible": bool(eligible),
        **metric_dict(truth, prediction, PAPER_QUANTILES),
    }
    return metrics, atom_records, evidence


def choose_family(metrics: pd.DataFrame) -> tuple[str, str, bool]:
    """Choose one region-wide family on Fold-1 validation, with numerical fallback."""
    al_fold1 = metrics[(metrics.family == "al") & (metrics.fold == 1)]
    if len(al_fold1) != 1 or not bool(al_fold1.iloc[0].numerically_eligible):
        raise RuntimeError("R97 complete Fold-1 AL fallback is absent")
    eligible_fold1 = metrics[
        (metrics.fold == 1) & metrics.numerically_eligible.astype(bool)
    ]
    if eligible_fold1.empty:
        raise RuntimeError("R97 has no numerically eligible Fold-1 family")
    fold1_winner = str(
        eligible_fold1.sort_values(["AQL", "family"], kind="stable").iloc[0].family
    )
    selected_family = fold1_winner
    numerical_fallback = False
    if not metrics[metrics.family == selected_family].numerically_eligible.astype(bool).all():
        selected_family = "al"
        numerical_fallback = True
    if not metrics[metrics.family == selected_family].numerically_eligible.astype(bool).all():
        raise RuntimeError("R97 selected whole-region family is not numerically eligible on all folds")
    return selected_family, fold1_winner, numerical_fallback


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    if len(manifest) != 45 or manifest.task_id.duplicated().any():
        raise RuntimeError("R97 region closeout requires the exact 45-task surface")
    tasks = []
    for row in manifest.itertuples(index=False):
        path = Path(row.task_config)
        if sha256_file(path) != str(row.task_config_sha256):
            raise RuntimeError(f"R97 task hash changed: {row.task_id}")
        tasks.append(json.loads(path.read_text()))
    pipeline = json.loads(args.pipeline_contract.read_text())
    if pipeline.get("stage") != "R97" or pipeline.get("test_opened") is not False:
        raise RuntimeError("R97 pipeline contract is invalid or test-opened")
    if any(pipeline.get(name) is not False for name in BLOCKED):
        raise RuntimeError("R97 pipeline authorizes a blocked action")
    hashes = {task["pipeline_contract_sha256"] for task in tasks}
    if hashes != {pipeline["pipeline_contract_sha256"]}:
        raise RuntimeError("R97 task surface differs from its pipeline contract")
    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_region_closeout",
        allow_quarantine=args.quarantine_existing,
    )
    metric_rows, atoms, evidence = [], {}, []
    for family in FAMILIES:
        atoms[family] = {}
        for fold in FOLDS:
            metrics, records, sources = family_fold(tasks, family, fold)
            metric_rows.append(metrics)
            atoms[family][str(fold)] = records
            evidence.extend(sources)
    metrics = pd.DataFrame(metric_rows)
    selected_family, fold1_winner, numerical_fallback = choose_family(metrics)
    selected_atoms = [atom for fold in FOLDS for atom in atoms[selected_family][str(fold)]]
    selected_rows = pd.DataFrame([{
        "region": atom["region"], "fold": atom["fold"], "selected_family": selected_family,
        "tau": atom["tau"], "task_id": atom["task_id"],
        **{f"{name}_path": atom[name]["path"] for name in (
            "beta", "prediction", "terminal", "source_case_config", "feature_manifest",
            "x_val", "rows_val", "scaler",
        )},
        **{f"{name}_sha256": atom[name]["sha256"] for name in (
            "beta", "prediction", "terminal", "source_case_config", "feature_manifest",
            "x_val", "rows_val", "scaler",
        )},
    } for atom in selected_atoms]).sort_values(["fold", "tau"])
    selected_path = output / "pricefm_stage_r97_selected_atom_manifest.csv"
    selected_rows.to_csv(selected_path, index=False)
    metrics_path = output / "pricefm_stage_r97_family_fold_validation_metrics.csv"
    metrics.to_csv(metrics_path, index=False)
    frozen = {
        "schema_version": 1, "stage": "R97", "status": "region_validation_surface_frozen",
        "region": pipeline["region"], "folds": list(FOLDS),
        "quantiles": list(PAPER_QUANTILES), "selected_family": selected_family,
        "fold1_validation_winner_before_numerical_fallback": fold1_winner,
        "numerical_fallback_to_AL": numerical_fallback,
        "family_selection_rule": pipeline["family_selection_rule"],
        "per_fold_or_quantile_family_mixing": False,
        "frozen_desn": pipeline["frozen_desn"], "rhs_tau0": pipeline["rhs_tau0"],
        "selected_atom_manifest": file_record(selected_path, "selected_21_atom_surface"),
        "validation_metrics": file_record(metrics_path, "family_fold_validation_metrics"),
        "pipeline_contract": file_record(args.pipeline_contract, "pipeline_contract"),
        "test_opened": False, **{name: False for name in BLOCKED},
    }
    frozen_path = output / "pricefm_stage_r97_frozen_region_surface.json"
    atomic_write_json(frozen_path, frozen)
    dedup = {(record["path"], record["sha256"], record["role"]): record for record in evidence}
    pd.DataFrame([file_record(args.manifest, "task_manifest"), file_record(args.pipeline_contract, "pipeline_contract"), *dedup.values()]).to_csv(
        output / "source_manifest.csv", index=False,
    )
    summary = {
        "status": "completed_region_validation_surface_frozen", "stage": "R97",
        "region": pipeline["region"], "selected_family": selected_family,
        "fold1_winner": fold1_winner, "numerical_fallback_to_AL": numerical_fallback,
        "selected_atoms": 21, "family_fold_rows": 6,
        "frozen_surface": str(frozen_path), "selected_atom_manifest": str(selected_path),
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "region_validation_closeout.md").write_text(
        f"# R97 validation closeout: {pipeline['region']}\n\n"
        f"Fold-1 validation selected the whole `{selected_family}` family. "
        f"Numerical fallback to AL: `{str(numerical_fallback).lower()}`. The same family "
        "is frozen for all three folds and all seven quantiles; test remained sealed.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
