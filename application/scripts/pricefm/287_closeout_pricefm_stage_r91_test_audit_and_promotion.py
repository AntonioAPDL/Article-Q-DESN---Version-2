#!/usr/bin/env python3
"""Close out R90 against dual references without mutating scientific authority."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import joblib
import numpy as np
import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r90_scoring_only_test_audit_20260905"
GRID = DATA / "experiment_grids" / TAG
PREP = DATA / "authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905"
R89 = DATA / "authoritative/pricefm_stage_r89_validation_family_selection_20260905"
OUTPUT = DATA / "authoritative/pricefm_stage_r91_test_audit_and_promotion_20260905"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BLOCKS = ("1-24", "25-48", "49-72", "73-96")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--prep-dir", type=Path, default=PREP)
    p.add_argument("--r89-dir", type=Path, default=R89)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pinball(y: np.ndarray, prediction: np.ndarray, tau: float) -> np.ndarray:
    error = y - prediction
    return np.maximum(tau * error, (tau - 1.0) * error)


def horizon_group(horizon: pd.Series) -> pd.Series:
    lower = ((horizon.astype(int) - 1) // 24) * 24 + 1
    upper = lower + 23
    return lower.astype(str) + "-" + upper.astype(str)


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    scale = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid target scale: {path}")
    return scale


def score_case(row: Any, selected: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    output = Path(row.output_dir); adapter = Path(row.adapter_dir)
    terminal_path = output / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if terminal.get("status") != "completed" or terminal.get("validation_replay_passed") is not True:
        raise RuntimeError(f"Invalid R90 terminal: {terminal_path}")
    if terminal.get("model_fitted") is not False or terminal.get("selection_changed") is not False:
        raise RuntimeError(f"R90 violated scoring-only contract: {terminal_path}")
    for name, expected in (terminal.get("retained_artifact_sha256") or {}).items():
        path = adapter / name if name in {"rows_test.csv", "adapter_manifest.json", "feature_manifest.json"} else output / name
        if not path.is_file() or sha256(path) != expected:
            raise RuntimeError(f"Changed R90 artifact: {path}")
    replay = pd.read_csv(output / "validation_replay.csv")
    if len(replay) != 7 or not replay.passed.astype(bool).all():
        raise RuntimeError(f"Validation replay gate failed: {row.case_id}")
    truth = pd.read_csv(adapter / "rows_test.csv")
    predictions = pd.read_csv(output / "test_predictions_scaled.csv")
    atoms = selected[selected.case_id.eq(row.case_id)].sort_values("tau")
    if len(atoms) != 7 or len(predictions) != len(truth) * 7:
        raise RuntimeError(f"Incomplete R90 test surface: {row.case_id}")
    if set(atoms.tau.astype(float)) != set(TAUS):
        raise RuntimeError(f"Unexpected selected quantiles: {row.case_id}")
    if truth.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Duplicate R90 test truth keys: {row.case_id}")
    if predictions.duplicated(["origin_id", "horizon", "tau"]).any():
        raise RuntimeError(f"Duplicate R90 test prediction keys: {row.case_id}")
    if set(predictions.tau.astype(float)) != set(TAUS):
        raise RuntimeError(f"Unexpected R90 prediction quantiles: {row.case_id}")
    if set(predictions.horizon.astype(int)) != set(range(1, 97)):
        raise RuntimeError(f"Unexpected R90 prediction horizons: {row.case_id}")
    if "split" in predictions and set(predictions.split.astype(str)) != {"test"}:
        raise RuntimeError(f"Unexpected R90 prediction split: {row.case_id}")
    if atoms.scaler_path.nunique() != 1 or atoms.scaler_sha256.nunique() != 1:
        raise RuntimeError(f"Mixed target scalers in selected case: {row.case_id}")
    scaler_path = Path(atoms.scaler_path.iloc[0])
    if sha256(scaler_path) != atoms.scaler_sha256.iloc[0]:
        raise RuntimeError(f"Changed target scaler: {scaler_path}")
    scale = target_scale(scaler_path, row.region)
    merged = predictions.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"], how="left", validate="many_to_one",
    )
    if merged.y_scaled.isna().any() or not np.isfinite(merged[["y_scaled", "pred_scaled"]]).all().all():
        raise RuntimeError(f"Invalid R90 scored rows: {row.case_id}")
    merged["loss"] = np.maximum(
        merged.tau * (merged.y_scaled - merged.pred_scaled),
        (merged.tau - 1.0) * (merged.y_scaled - merged.pred_scaled),
    ) * scale
    merged["horizon_group"] = horizon_group(merged.horizon)
    quantiles = merged.groupby("tau", as_index=False).loss.mean().rename(columns={"loss": "candidate_test_AQL"})
    quantiles.insert(0, "fold", int(row.fold)); quantiles.insert(0, "region", row.region)
    quantiles.insert(0, "case_id", row.case_id)
    horizons = merged.groupby(["tau", "horizon_group"], as_index=False).loss.mean().rename(
        columns={"loss": "candidate_test_AQL"}
    )
    if set(horizons.horizon_group) != set(BLOCKS):
        raise RuntimeError(f"Incomplete R90 horizon blocks: {row.case_id}")
    horizons.insert(0, "fold", int(row.fold)); horizons.insert(0, "region", row.region)
    horizons.insert(0, "case_id", row.case_id)
    wide = merged.pivot(index=["origin_id", "horizon"], columns="tau", values="pred_scaled")
    wide = wide.loc[:, list(TAUS)]
    crossing = wide.to_numpy()[:, :-1] > wide.to_numpy()[:, 1:]
    case = {
        "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
        "selected_family": str(atoms.selected_family.iloc[0]),
        "selected_validation_AQL": float(atoms.selected_validation_AQL.iloc[0]),
        "candidate_test_AQL": float(merged.loss.mean()),
        "test_rows": len(truth),
        "adjacent_crossing_rate": float(crossing.mean()),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
        "validation_replay_max_abs_diff": float(replay.maximum_absolute_difference.max()),
        "validation_replay_pass": True,
    }
    return quantiles, horizons, case


def apply_promotion_gates(
    cases: pd.DataFrame, quantiles: pd.DataFrame, horizons: pd.DataFrame,
    case_refs: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    refs = case_refs.set_index("case_id")[[
        "authoritative_qdesn_test_AQL", "cached_pricefm_test_AQL",
    ]]
    decisions = cases.set_index("case_id").join(refs)
    qcheck = quantiles.groupby("case_id").agg(
        quantile_rows=("tau", "size"), quantiles=("tau", "nunique"),
        all_quantile_metrics_finite=("candidate_test_AQL", lambda x: bool(np.isfinite(x).all())),
    )
    hcheck = horizons.groupby("case_id").agg(
        horizon_rows=("horizon_group", "size"),
        horizon_blocks=("horizon_group", "nunique"),
        all_horizon_metrics_finite=("candidate_test_AQL", lambda x: bool(np.isfinite(x).all())),
    )
    integrity = qcheck.join(hcheck)
    integrity["full_quantile_confirmation_pass"] = (
        integrity.quantile_rows.eq(7) & integrity.quantiles.eq(7)
        & integrity.all_quantile_metrics_finite
    )
    integrity["full_horizon_confirmation_pass"] = (
        integrity.horizon_rows.eq(28) & integrity.horizon_blocks.eq(4)
        & integrity.all_horizon_metrics_finite
    )
    integrity["comparator_granularity"] = "case_level_only"
    integrity["subgroup_metrics_role"] = "candidate_diagnostics_not_comparator_gate"
    decisions = decisions.join(integrity)
    decisions["beats_authoritative_qdesn"] = decisions.candidate_test_AQL < decisions.authoritative_qdesn_test_AQL
    decisions["beats_cached_pricefm"] = decisions.candidate_test_AQL < decisions.cached_pricefm_test_AQL
    decisions["complete_finite_surface"] = np.isfinite(decisions.candidate_test_AQL)
    decisions["promotion_eligible"] = (
        decisions.beats_authoritative_qdesn & decisions.beats_cached_pricefm
        & decisions.full_quantile_confirmation_pass
        & decisions.full_horizon_confirmation_pass
        & decisions.validation_replay_pass & decisions.complete_finite_surface
    )
    decisions["decision"] = np.where(
        decisions.promotion_eligible, "promote_candidate_for_integration_review",
        "retain_current_authoritative_qdesn",
    )
    decisions["registry_mutation_authorized"] = False
    decisions["article_mutation_authorized"] = False
    return decisions.reset_index(), integrity.reset_index()


def run(args: argparse.Namespace) -> dict[str, Any]:
    launch_summary_path = args.grid_dir / "launch_summary.json"
    launch = json.loads(launch_summary_path.read_text())
    if launch.get("status") != "completed" or launch.get("completed") != 56 or launch.get("failed") != 0:
        raise RuntimeError("R90 scoring audit has not completed cleanly")
    prep_summary_path = args.prep_dir / "summary.json"
    prep = json.loads(prep_summary_path.read_text())
    contract_path = args.prep_dir / "promotion_contract.json"
    contract = json.loads(contract_path.read_text())
    if prep.get("model_refits_authorized") != 0 or contract.get("model_refit_authorized") is not False:
        raise RuntimeError("R90 scoring-only contract changed")
    manifest_path = args.grid_dir / "task_manifest.csv"
    status_path = args.grid_dir / "launch_status.csv"
    selected_path = args.r89_dir / "pricefm_stage_r89_selected_atom_manifest.csv"
    selection_path = args.r89_dir / "pricefm_stage_r89_family_selection.csv"
    cref_path = args.prep_dir / "pricefm_stage_r90_frozen_case_references.csv"
    manifest = pd.read_csv(manifest_path).sort_values(["region", "fold"])
    statuses = pd.read_csv(status_path).set_index("task_id")
    selected = pd.read_csv(selected_path)
    selection = pd.read_csv(selection_path)
    if len(manifest) != 56 or len(selected) != 392 or len(selection) != 56:
        raise RuntimeError("R91 input surface is incomplete")
    qrows, hrows, case_rows = [], [], []
    for row in manifest.itertuples(index=False):
        if statuses.loc[row.task_id, "status"] not in {"completed", "skipped_completed"}:
            raise RuntimeError(f"R90 task is incomplete: {row.task_id}")
        q, h, case = score_case(row, selected)
        qrows.append(q); hrows.append(h); case_rows.append(case)
    quantiles = pd.concat(qrows, ignore_index=True).sort_values(["region", "fold", "tau"])
    horizons = pd.concat(hrows, ignore_index=True).sort_values(["region", "fold", "tau", "horizon_group"])
    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    if len(quantiles) != 392 or len(horizons) != 1568 or len(cases) != 56:
        raise RuntimeError("R91 scored surface is incomplete")
    decisions, integrity = apply_promotion_gates(
        cases, quantiles, horizons, pd.read_csv(cref_path),
    )
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    quantiles.to_csv(output / "pricefm_stage_r91_candidate_quantile_metrics.csv", index=False)
    horizons.to_csv(output / "pricefm_stage_r91_candidate_horizon_metrics.csv", index=False)
    integrity.to_csv(output / "pricefm_stage_r91_subgroup_integrity_ledger.csv", index=False)
    decisions.to_csv(output / "pricefm_stage_r91_case_decisions.csv", index=False)
    promotion = decisions[decisions.promotion_eligible].copy()
    promotion.to_csv(output / "pricefm_stage_r91_promotion_queue.csv", index=False)
    decisions[[
        "case_id", "region", "fold", "selected_family", "selected_validation_AQL",
        "candidate_test_AQL", "authoritative_qdesn_test_AQL", "cached_pricefm_test_AQL",
        "promotion_eligible", "decision",
    ]].to_csv(output / "pricefm_stage_r91_article_candidate_table.csv", index=False)
    decisions[[
        "case_id", "region", "fold", "candidate_test_AQL",
        "authoritative_qdesn_test_AQL", "cached_pricefm_test_AQL", "promotion_eligible",
    ]].to_csv(output / "pricefm_stage_r91_figure_data.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r90_complete_56_of_56", "passed": True, "observed": 56},
        {"gate": "validation_replay_all_cases", "passed": decisions.validation_replay_pass.all(), "observed": int(decisions.validation_replay_pass.sum())},
        {"gate": "complete_392_quantile_metrics", "passed": len(quantiles) == 392, "observed": len(quantiles)},
        {"gate": "complete_1568_horizon_metrics", "passed": len(horizons) == 1568, "observed": len(horizons)},
        {"gate": "selection_unchanged_after_test", "passed": True, "observed": "frozen R89"},
        {"gate": "registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R91 global gates failed")
    gates.to_csv(output / "pricefm_stage_r91_global_gates.csv", index=False)
    fixed = [
        Path(__file__).resolve(), launch_summary_path, prep_summary_path, contract_path,
        manifest_path, status_path, selected_path, selection_path, cref_path,
    ]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "test_audit_closed_promotion_queue_frozen",
        "cases": 56, "selected_atoms": 392,
        "al_selected_cases": int(decisions.selected_family.eq("al").sum()),
        "exal_selected_cases": int(decisions.selected_family.eq("exal").sum()),
        "beats_authoritative_qdesn_cases": int(decisions.beats_authoritative_qdesn.sum()),
        "beats_cached_pricefm_cases": int(decisions.beats_cached_pricefm.sum()),
        "beats_both_cases": int((decisions.beats_authoritative_qdesn & decisions.beats_cached_pricefm).sum()),
        "promotion_eligible_cases": len(promotion),
        "mean_candidate_test_AQL": float(decisions.candidate_test_AQL.mean()),
        "mean_authoritative_qdesn_test_AQL": float(decisions.authoritative_qdesn_test_AQL.mean()),
        "mean_cached_pricefm_test_AQL": float(decisions.cached_pricefm_test_AQL.mean()),
        "additional_fit_authorized": False, "registry_mutated": False,
        "article_mutated": False, "joint_or_mcmc_authorized": False,
        "ready_for_integration": bool(len(promotion)),
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    recommendation = (
        "Submit the frozen promotion queue to the integration coordinator for case-level registry "
        "and article review."
        if len(promotion) else
        "Retain the current authoritative Q-DESN surface; the repaired independent VB campaign "
        "does not justify registry or article mutation."
    )
    (output / "pricefm_stage_r91_closeout_report.md").write_text(
        "# PriceFM Stage-R91 Test Audit Closeout\n\n"
        f"R91 audited 56 frozen case-specific AL/exAL surfaces. {len(promotion)} cases pass "
        "both strict case-level test comparators plus all quantile, horizon, replay, and integrity gates. "
        f"{recommendation}\n"
    )
    (output / "article_prose_recommendation.md").write_text(
        "# PriceFM article recommendation\n\n" + recommendation + "\n"
    )
    (output / "integration_handoff.md").write_text(
        "# PriceFM R85-R91 integration handoff\n\n"
        f"Status: {'READY_FOR_INTEGRATION' if len(promotion) else 'NOT_READY_FOR_INTEGRATION'}\n\n"
        f"Promotion-eligible cases: {len(promotion)}/56. Registry and article were not modified. "
        "Use the case decisions, promotion queue, source manifest, and hash-pinned R89/R90 "
        "artifacts for coordinator review. Runtime adapters and predictions remain ignored.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
