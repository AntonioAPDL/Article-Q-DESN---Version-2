#!/usr/bin/env python3
"""Close R94 on validation only and freeze one complete quantile family."""

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
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r94_coherent_exal_refit_20260906"
MANIFEST = DATA / "experiment_grids" / TAG / "task_manifest.csv"
OUTPUT = DATA / "authoritative/pricefm_stage_r94_validation_family_closeout_20260907"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--manifest", type=Path, default=MANIFEST)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def load_scaler(task: dict[str, Any]):
    with Path(task["source_r93_task"]).open() as handle:
        r93 = json.load(handle)
    with Path(r93["data_config"]).open() as handle:
        config = yaml.safe_load(handle)["pricefm"]
    processed = Path(config["processed_dir"])
    if not processed.is_absolute():
        processed = ARTIFACT_REPO / processed
    path = processed / "scalers" / f"fold_{int(task['fold'])}" / "per_region_separate_xy_scalers.joblib"
    scalers = joblib.load(path)
    return scalers[str(task["region"])]["y_scaler"], path


def pinball(y: np.ndarray, prediction: np.ndarray, tau: float) -> float:
    error = y - prediction
    return float(np.maximum(tau * error, (tau - 1.0) * error).mean())


def surface_metrics(
    family: str,
    predictions: pd.DataFrame,
    rows: pd.DataFrame,
    scaler,
) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame]:
    validate_quantiles(sorted(predictions.tau.astype(float).unique()), label=f"{family} quantiles")
    if set(predictions.split.astype(str)) != {"val"}:
        raise RuntimeError(f"{family} predictions include a non-validation split")
    keys = ["origin_id", "horizon"]
    if predictions.duplicated(keys + ["tau"]).any():
        raise RuntimeError(f"{family} predictions duplicate row/quantile keys")
    wide = predictions.pivot(index=keys, columns="tau", values="pred_scaled")
    wide = wide.reindex(columns=list(PAPER_QUANTILES))
    expected = rows[keys + ["y_scaled"]].merge(
        wide.reset_index(), on=keys, how="left", validate="one_to_one"
    )
    if len(expected) != len(rows) or expected[list(PAPER_QUANTILES)].isna().any().any():
        raise RuntimeError(f"{family} prediction rows do not align with validation truth")
    y_scaled = expected.y_scaled.to_numpy(float)
    pred_scaled = expected[list(PAPER_QUANTILES)].to_numpy(float)
    y_original = inverse_scale_y(y_scaled, scaler)
    pred_original = inverse_scale_y(pred_scaled, scaler)
    overall = {
        "family": family,
        "method_id": str(predictions.method_id.iloc[0]),
        **metric_dict(y_original, pred_original, PAPER_QUANTILES),
    }
    quantile_rows = []
    for index, tau in enumerate(PAPER_QUANTILES):
        quantile_rows.append({
            "family": family, "tau": tau,
            "validation_quantile_loss_original": pinball(
                y_original, pred_original[:, index], tau
            ),
        })
    block_rows = []
    for start in (1, 25, 49, 73):
        stop = start + 23
        mask = expected.horizon.astype(int).between(start, stop).to_numpy()
        block_rows.append({
            "family": family, "horizon_group": f"{start}-{stop}",
            **metric_dict(y_original[mask], pred_original[mask], PAPER_QUANTILES),
        })
    return overall, pd.DataFrame(quantile_rows), pd.DataFrame(block_rows)


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest_path = args.manifest.resolve()
    manifest = pd.read_csv(manifest_path).sort_values("tau")
    if len(manifest) != 7 or manifest.task_id.duplicated().any():
        raise RuntimeError("R94 closeout requires exactly seven unique tasks")
    validate_quantiles(manifest.tau.tolist(), label="R94 manifest quantiles")
    if not manifest.likelihood_family.eq("exal").all():
        raise RuntimeError("R94 closeout manifest is not exAL-only")
    tasks = [json.loads(Path(row.task_config).read_text()) for row in manifest.itertuples(index=False)]
    if len({task["pipeline_contract_sha256"] for task in tasks}) != 1:
        raise RuntimeError("R94 tasks do not share one immutable pipeline contract")
    adapter = Path(tasks[0]["adapter_dir"])
    validate_no_test_adapter(adapter)
    rows = pd.read_csv(adapter / "rows_val.csv")
    if "y_scaled" not in rows:
        raise RuntimeError("R94 validation rows omit y_scaled")
    scaler, scaler_path = load_scaler(tasks[0])

    al_predictions: list[pd.DataFrame] = []
    exal_predictions: list[pd.DataFrame] = []
    numerical_rows: list[dict[str, Any]] = []
    source_records = [file_record(manifest_path, "r94_task_manifest")]
    al_eligible = True
    exal_eligible = True
    frozen_atoms: dict[str, list[dict[str, Any]]] = {"al": [], "exal": []}
    for row, task in zip(manifest.itertuples(index=False), tasks):
        task_path = Path(row.task_config)
        if sha256_file(task_path) != str(row.task_config_sha256):
            raise RuntimeError(f"R94 task hash changed: {row.task_id}")
        tau = float(task["tau"])
        al_terminal_path = Path(task["al_source_terminal"])
        al_terminal = json.loads(al_terminal_path.read_text())
        if al_terminal.get("numerical_gate_passed") is not True:
            al_eligible = False
        al_prediction_path = Path(task["al_prediction_path"])
        if sha256_file(al_prediction_path) != task["al_prediction_sha256"]:
            raise RuntimeError(f"R93 AL prediction hash changed at tau={tau}")
        al_prediction = pd.read_csv(al_prediction_path)
        al_predictions.append(al_prediction)
        frozen_atoms["al"].append({
            "tau": tau,
            "beta": file_record(task["al_beta_path"], "selected_atom_beta"),
            "prediction": file_record(al_prediction_path, "selected_atom_validation_prediction"),
            "terminal": file_record(al_terminal_path, "selected_atom_terminal"),
        })

        output = Path(task["output_dir"])
        terminal_path = output / "terminal.json"
        if not terminal_path.is_file():
            raise RuntimeError(f"R94 atom is not terminal at tau={tau}")
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("task_id") != task["task_id"] or terminal.get("test_loaded") is not False:
            raise RuntimeError(f"R94 terminal identity/firewall mismatch at tau={tau}")
        if terminal.get("test_opened") is not False or terminal.get("test_access_authorized") is not False:
            raise RuntimeError(f"R94 terminal opened or authorized test at tau={tau}")
        passed = terminal.get("status") == "completed" and terminal.get("numerical_gate_passed") is True
        exal_eligible = exal_eligible and passed
        prediction_path = output / "predictions_scaled.csv"
        if not prediction_path.is_file():
            raise RuntimeError(f"R94 prediction is missing at tau={tau}")
        expected_hash = (terminal.get("artifact_sha256") or {}).get("predictions_scaled.csv")
        if not expected_hash or sha256_file(prediction_path) != expected_hash:
            raise RuntimeError(f"R94 prediction hash mismatch at tau={tau}")
        exal_predictions.append(pd.read_csv(prediction_path))
        method = pd.read_csv(output / "method_summary.csv").iloc[0]
        gate = json.loads((output / "numerical_gate.json").read_text())
        numerical_rows.append({
            "family": "exal", "tau": tau, "status": terminal["status"],
            "numerical_gate_passed": bool(terminal.get("numerical_gate_passed")),
            "formal_converged": bool(terminal.get("formal_converged")),
            "iterations": int(terminal.get("iter", 0)),
            "structured_updates": int(terminal.get("structured_updates", 0)),
            "first_state_delta_below_100_diagnostic": bool(gate.get("first_state_delta_below_100")),
            "train_seconds": float(method.get("train_seconds", math.nan)),
        })
        frozen_atoms["exal"].append({
            "tau": tau,
            "beta": file_record(output / "beta_summary.csv", "selected_atom_beta"),
            "prediction": file_record(prediction_path, "selected_atom_validation_prediction"),
            "terminal": file_record(terminal_path, "selected_atom_terminal"),
        })
        source_records.extend([
            file_record(task_path, "r94_task"),
            file_record(al_prediction_path, "r93_al_validation_prediction"),
            file_record(terminal_path, "r94_terminal"),
            file_record(prediction_path, "r94_validation_prediction"),
        ])

    metrics = []
    quantiles = []
    blocks = []
    for family, parts in (("al", al_predictions), ("exal", exal_predictions)):
        overall, by_quantile, by_block = surface_metrics(
            family, pd.concat(parts, ignore_index=True), rows, scaler
        )
        overall["numerically_eligible"] = al_eligible if family == "al" else exal_eligible
        metrics.append(overall)
        quantiles.append(by_quantile)
        blocks.append(by_block)
    comparison = pd.DataFrame(metrics).sort_values("family")
    eligible = comparison[comparison.numerically_eligible].sort_values(
        ["AQL", "family"], kind="stable"
    )
    if not al_eligible or eligible.empty:
        raise RuntimeError("R94 closeout has no complete AL fallback")
    winner = eligible.iloc[0]

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or (args.output_dir.parent / "quarantine"),
        reason="replaced_r94_validation_closeout",
        allow_quarantine=args.quarantine_existing,
    )
    comparison.to_csv(output / "pricefm_stage_r94_validation_family_comparison.csv", index=False)
    pd.concat(quantiles, ignore_index=True).to_csv(
        output / "pricefm_stage_r94_validation_quantile_metrics.csv", index=False
    )
    pd.concat(blocks, ignore_index=True).to_csv(
        output / "pricefm_stage_r94_validation_horizon_metrics.csv", index=False
    )
    pd.DataFrame(numerical_rows).to_csv(
        output / "pricefm_stage_r94_numerical_eligibility.csv", index=False
    )
    frozen = {
        "schema_version": 1,
        "stage": "R94",
        "status": "validation_family_frozen_awaiting_allfold_pretest_fit",
        "region": tasks[0]["region"],
        "selection_fold": int(tasks[0]["fold"]),
        "quantiles": list(PAPER_QUANTILES),
        "selected_family": str(winner.family),
        "selected_method_id": str(winner.method_id),
        "selected_validation_AQL_original": float(winner.AQL),
        "selection_rule": "minimum_raw_AQL_among_complete_numerically_eligible_whole_families",
        "per_quantile_family_mixing": False,
        "pipeline_contract_sha256": tasks[0]["pipeline_contract_sha256"],
        "frozen_desn": tasks[0]["frozen_desn"],
        "rhs_tau0": float(tasks[0]["rhs_tau0"]),
        "selected_atoms": frozen_atoms[str(winner.family)],
        "all_family_atoms": frozen_atoms,
        "adapter_files": tasks[0]["adapter_files"],
        "scaler": file_record(scaler_path, "fold1_y_scaler_bundle"),
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    frozen_path = output / "pricefm_stage_r94_frozen_validation_family.json"
    atomic_write_json(frozen_path, frozen)
    source_records.extend([
        file_record(adapter / "rows_val.csv", "validation_rows"),
        file_record(adapter / "y_val.csv", "validation_response"),
        file_record(scaler_path, "fold1_y_scaler_bundle"),
    ])
    pd.DataFrame(source_records).drop_duplicates("path").to_csv(
        output / "source_manifest.csv", index=False
    )
    summary = {
        **{key: frozen[key] for key in (
            "stage", "status", "region", "selection_fold", "selected_family",
            "selected_method_id", "selected_validation_AQL_original",
            "test_opened", "test_access_authorized",
            "registry_mutation_authorized", "article_mutation_authorized",
            "joint_model_authorized", "mcmc_authorized",
        )},
        "al_validation_AQL_original": float(comparison.loc[comparison.family.eq("al"), "AQL"].iloc[0]),
        "exal_validation_AQL_original": float(comparison.loc[comparison.family.eq("exal"), "AQL"].iloc[0]),
        "al_numerically_eligible": bool(al_eligible),
        "exal_numerically_eligible": bool(exal_eligible),
        "quarantined_previous_closeout": str(quarantined) if quarantined else None,
        "frozen_family_contract": str(frozen_path),
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r94_validation_family_closeout.md").write_text(
        "# PriceFM Stage-R94 Validation Family Closeout\n\n"
        f"The complete `{summary['selected_family']}` family was frozen for "
        f"`{summary['region']}` from Fold-{summary['selection_fold']} validation-only "
        f"AQL `{summary['selected_validation_AQL_original']:.9f}`. AL AQL was "
        f"`{summary['al_validation_AQL_original']:.9f}` and exAL AQL was "
        f"`{summary['exal_validation_AQL_original']:.9f}`. Selection used one whole "
        "seven-quantile family. Test, registry, article, joint, and MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
