#!/usr/bin/env python3
"""Close R95 on validation only and freeze one whole-region family surface."""

from __future__ import annotations

import argparse
import json
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


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r95_region_frozen_allfold_validation_20260907"
MANIFEST = DATA / "experiment_grids" / TAG / "task_manifest.csv"
R94_FROZEN = DATA / (
    "authoritative/pricefm_stage_r94_validation_family_closeout_20260907/"
    "pricefm_stage_r94_frozen_validation_family.json"
)
OUTPUT = DATA / "authoritative/pricefm_stage_r95_allfold_validation_closeout_20260907"
BLOCKED = (
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--manifest", type=Path, default=MANIFEST)
    value.add_argument("--r94-frozen", type=Path, default=R94_FROZEN)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
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
        raise RuntimeError(f"R95 terminal identity/firewall mismatch: {path}")
    for record in payload.get("artifacts") or []:
        verify_file_record(record, label="R95 terminal artifact")
    return payload, path


def pinball(y: np.ndarray, prediction: np.ndarray, tau: float) -> float:
    error = y - prediction
    return float(np.maximum(tau * error, (tau - 1.0) * error).mean())


def surface_metrics(
    family: str,
    fold: int,
    predictions: pd.DataFrame,
    rows: pd.DataFrame,
    scaler,
) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    validate_quantiles(sorted(predictions.tau.astype(float).unique()), label=f"fold{fold} {family} quantiles")
    if set(predictions.split.astype(str)) != {"val"}:
        raise RuntimeError(f"fold{fold} {family} predictions contain a non-validation split")
    keys = ["origin_id", "horizon"]
    if predictions.duplicated(keys + ["tau"]).any():
        raise RuntimeError(f"fold{fold} {family} predictions duplicate row/quantile keys")
    wide = predictions.pivot(index=keys, columns="tau", values="pred_scaled")
    wide = wide.reindex(columns=list(PAPER_QUANTILES))
    aligned = rows[keys + ["y_scaled"]].merge(
        wide.reset_index(), on=keys, how="left", validate="one_to_one"
    )
    if len(aligned) != len(rows) or aligned[list(PAPER_QUANTILES)].isna().any().any():
        raise RuntimeError(f"fold{fold} {family} predictions do not align with validation truth")
    y_scaled = aligned.y_scaled.to_numpy(float)
    pred_scaled = aligned[list(PAPER_QUANTILES)].to_numpy(float)
    y_original = inverse_scale_y(y_scaled, scaler)
    pred_original = inverse_scale_y(pred_scaled, scaler)
    overall = {
        "fold": fold,
        "family": family,
        "method_id": str(predictions.method_id.iloc[0]),
        **metric_dict(y_original, pred_original, PAPER_QUANTILES),
    }
    by_quantile = pd.DataFrame([
        {
            "fold": fold,
            "family": family,
            "tau": tau,
            "validation_quantile_loss_original": pinball(y_original, pred_original[:, index], tau),
        }
        for index, tau in enumerate(PAPER_QUANTILES)
    ])
    by_horizon = []
    for start in (1, 25, 49, 73):
        stop = start + 23
        mask = aligned.horizon.astype(int).between(start, stop).to_numpy()
        by_horizon.append({
            "fold": fold,
            "family": family,
            "horizon_group": f"{start}-{stop}",
            **metric_dict(y_original[mask], pred_original[mask], PAPER_QUANTILES),
        })
    return overall, by_quantile, pd.DataFrame(by_horizon)


def fold1_sources(frozen: dict[str, Any], family: str) -> tuple[pd.DataFrame, pd.DataFrame, Any, list[dict[str, Any]], bool]:
    adapter_record = next(
        record for record in frozen["adapter_files"]
        if Path(record["path"]).name == "rows_val.csv"
    )
    verify_file_record(adapter_record, label="R94 Fold-1 validation rows")
    rows = pd.read_csv(adapter_record["path"])
    verify_file_record(frozen["scaler"], label="R94 Fold-1 scaler")
    scaler = joblib.load(frozen["scaler"]["path"])[frozen["region"]]["y_scaler"]
    predictions = []
    records = []
    eligible = True
    for atom in frozen["all_family_atoms"][family]:
        for role in ("beta", "prediction", "terminal"):
            verify_file_record(atom[role], label=f"R94 Fold-1 {family} {role}")
        payload = json.loads(Path(atom["terminal"]["path"]).read_text())
        eligible = eligible and payload.get("status") == "completed" and payload.get("numerical_gate_passed") is True
        predictions.append(pd.read_csv(atom["prediction"]["path"]))
        records.append({"tau": float(atom["tau"]), **atom})
    return pd.concat(predictions, ignore_index=True), rows, scaler, records, eligible


def later_fold_sources(
    tasks: list[dict[str, Any]], family: str, fold: int
) -> tuple[pd.DataFrame, pd.DataFrame, Any, list[dict[str, Any]], bool, list[dict[str, Any]]]:
    selected = sorted(
        [task for task in tasks if int(task["fold"]) == fold and task["likelihood_family"] == family],
        key=lambda task: float(task["tau"]),
    )
    if len(selected) != 7:
        raise RuntimeError(f"R95 fold{fold} {family} surface is incomplete")
    validate_quantiles([task["tau"] for task in selected], label=f"R95 fold{fold} {family} tasks")
    adapter = Path(selected[0]["adapter_dir"])
    validate_no_test_adapter(adapter)
    rows = pd.read_csv(adapter / "rows_val.csv")
    with Path(selected[0]["data_config"]).open() as handle:
        data = yaml.safe_load(handle)["pricefm"]
    processed = Path(data["processed_dir"])
    scaler_path = processed / "scalers" / f"fold_{fold}" / "per_region_separate_xy_scalers.joblib"
    scaler = joblib.load(scaler_path)[selected[0]["region"]]["y_scaler"]
    predictions = []
    records = []
    source_records = [
        file_record(adapter / "rows_val.csv", f"fold{fold}_validation_rows"),
        file_record(scaler_path, f"fold{fold}_scaler"),
    ]
    eligible = True
    for task in selected:
        payload, terminal_path = terminal(task)
        atom_eligible = payload.get("status") == "completed" and payload.get("numerical_gate_passed") is True
        eligible = eligible and atom_eligible
        prediction = Path(task["output_dir"]) / "predictions_scaled.csv"
        beta = Path(task["output_dir"]) / "beta_summary.csv"
        predictions.append(pd.read_csv(prediction))
        atom = {
            "tau": float(task["tau"]),
            "beta": file_record(beta, f"fold{fold}_{family}_beta"),
            "prediction": file_record(prediction, f"fold{fold}_{family}_validation_prediction"),
            "terminal": file_record(terminal_path, f"fold{fold}_{family}_terminal"),
        }
        records.append(atom)
        source_records.extend(atom[role] for role in ("beta", "prediction", "terminal"))
    return pd.concat(predictions, ignore_index=True), rows, scaler, records, eligible, source_records


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest_path = args.manifest.resolve()
    frozen_path = args.r94_frozen.resolve()
    manifest = pd.read_csv(manifest_path)
    if len(manifest) != 30 or set(manifest.fold.astype(int)) != {2, 3}:
        raise RuntimeError("R95 closeout requires the exact 30-task folds 2/3 manifest")
    task_rows = []
    for row in manifest.itertuples(index=False):
        path = Path(row.task_config)
        if sha256_file(path) != str(row.task_config_sha256):
            raise RuntimeError(f"R95 task hash mismatch: {row.task_id}")
        task_rows.append(json.loads(path.read_text()))
    pipeline_hashes = {task["pipeline_contract_sha256"] for task in task_rows}
    if len(pipeline_hashes) != 1:
        raise RuntimeError("R95 tasks do not share one pipeline contract")
    pipeline_hash = next(iter(pipeline_hashes))
    frozen = json.loads(frozen_path.read_text())
    if frozen.get("selected_family") != "exal" or frozen.get("test_opened") is not False:
        raise RuntimeError("R95 closeout requires the sealed R94 exAL family freeze")

    existing_summary = args.output_dir / "summary.json"
    if existing_summary.is_file() and not args.quarantine_existing:
        existing = json.loads(existing_summary.read_text())
        existing_surface = Path(existing.get("frozen_surface", ""))
        source_manifest = args.output_dir / "source_manifest.csv"
        sources_valid = source_manifest.is_file()
        if sources_valid:
            for row in pd.read_csv(source_manifest).itertuples(index=False):
                path = Path(row.path)
                if not path.is_file() or sha256_file(path) != str(row.sha256):
                    sources_valid = False
                    break
        if (
            existing.get("pipeline_contract_sha256") == pipeline_hash
            and existing.get("status") == "allfold_validation_surface_frozen_awaiting_test_authorization"
            and existing_surface.is_file()
            and sha256_file(existing_surface) == existing.get("frozen_surface_sha256")
            and sources_valid
        ):
            return existing

    overall_rows = []
    quantile_frames = []
    horizon_frames = []
    atoms: dict[str, dict[str, list[dict[str, Any]]]] = {"al": {}, "exal": {}}
    eligibility: dict[str, dict[str, bool]] = {"al": {}, "exal": {}}
    source_records = [file_record(manifest_path, "R95_task_manifest"), file_record(frozen_path, "R94_frozen_family")]
    for family in ("al", "exal"):
        predictions, rows, scaler, records, eligible = fold1_sources(frozen, family)
        overall, quantiles, horizons = surface_metrics(family, 1, predictions, rows, scaler)
        overall["numerically_eligible"] = eligible
        overall_rows.append(overall)
        quantile_frames.append(quantiles)
        horizon_frames.append(horizons)
        atoms[family]["1"] = records
        eligibility[family]["1"] = eligible
        for fold in (2, 3):
            predictions, rows, scaler, records, eligible, sources = later_fold_sources(task_rows, family, fold)
            overall, quantiles, horizons = surface_metrics(family, fold, predictions, rows, scaler)
            overall["numerically_eligible"] = eligible
            overall_rows.append(overall)
            quantile_frames.append(quantiles)
            horizon_frames.append(horizons)
            atoms[family][str(fold)] = records
            eligibility[family][str(fold)] = eligible
            source_records.extend(sources)

    comparison = pd.DataFrame(overall_rows).sort_values(["fold", "family"])
    if not all(eligibility["al"].values()):
        raise RuntimeError("R95 has no complete finite whole-region AL fallback")
    exal_eligible = all(eligibility["exal"].values())
    effective_family = "exal" if exal_eligible else "al"
    fallback_used = not exal_eligible
    selected_atoms = atoms[effective_family]

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or (args.output_dir.parent / "quarantine"),
        reason="replaced_r95_validation_closeout",
        allow_quarantine=args.quarantine_existing,
    )
    comparison.to_csv(output / "pricefm_stage_r95_fold_family_validation_metrics.csv", index=False)
    pd.concat(quantile_frames, ignore_index=True).to_csv(
        output / "pricefm_stage_r95_validation_quantile_metrics.csv", index=False
    )
    pd.concat(horizon_frames, ignore_index=True).to_csv(
        output / "pricefm_stage_r95_validation_horizon_metrics.csv", index=False
    )
    eligibility_rows = [
        {"family": family, "fold": int(fold), "complete_numerically_eligible": value}
        for family, values in eligibility.items() for fold, value in values.items()
    ]
    pd.DataFrame(eligibility_rows).sort_values(["fold", "family"]).to_csv(
        output / "pricefm_stage_r95_numerical_eligibility.csv", index=False
    )
    frozen_surface = {
        "schema_version": 1,
        "stage": "R95",
        "status": "allfold_validation_surface_frozen_awaiting_test_authorization",
        "region": frozen["region"],
        "folds": [1, 2, 3],
        "quantiles": list(PAPER_QUANTILES),
        "validation_selected_family_from_R94": "exal",
        "effective_whole_region_family": effective_family,
        "whole_region_AL_fallback_used": fallback_used,
        "family_rule": "retain_R94_exAL_if_all_21_atoms_eligible_else_whole_region_AL",
        "fold_validation_metrics_role": "replication_diagnostic_only_no_retuning",
        "per_fold_or_quantile_family_mixing": False,
        "frozen_desn": frozen["frozen_desn"],
        "rhs_tau0": frozen["rhs_tau0"],
        "pipeline_contract_sha256": pipeline_hash,
        "selected_atoms": selected_atoms,
        "all_family_atoms": atoms,
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    frozen_surface_path = output / "pricefm_stage_r95_frozen_allfold_validation_surface.json"
    atomic_write_json(frozen_surface_path, frozen_surface)
    pd.DataFrame(source_records).drop_duplicates("path").to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": frozen_surface["status"],
        "region": frozen["region"],
        "folds_complete": 3,
        "quantile_atoms_per_family": 21,
        "validation_selected_family_from_R94": "exal",
        "effective_whole_region_family": effective_family,
        "whole_region_AL_fallback_used": fallback_used,
        "pipeline_contract_sha256": pipeline_hash,
        "frozen_surface": str(frozen_surface_path),
        "frozen_surface_sha256": sha256_file(frozen_surface_path),
        "quarantined_previous_closeout": str(quarantined) if quarantined else None,
        "next_action": "stop_and_request_separate_scoring_only_test_authorization",
        "test_opened": False,
        **{name: False for name in BLOCKED},
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r95_allfold_validation_closeout.md").write_text(
        "# PriceFM Stage-R95 All-Fold Validation Closeout\n\n"
        f"All three `SE_2` validation folds were frozen under the R94-selected "
        f"region specification. The effective whole-region family is `{effective_family}`; "
        f"whole-region AL fallback used: `{str(fallback_used).lower()}`. Fold-2 and "
        "Fold-3 validation scores are replication diagnostics and did not retune geometry, "
        "tau0, or family. Test, registry, article, joint, and MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
