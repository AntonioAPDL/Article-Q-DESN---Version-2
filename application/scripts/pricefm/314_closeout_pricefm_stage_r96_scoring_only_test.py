#!/usr/bin/env python3
"""Close out R96 test scoring against frozen Q-DESN and PriceFM references."""

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
TAG = "pricefm_stage_r96_se2_scoring_only_test_20260908"
GRID = DATA / "experiment_grids" / TAG
PREP = DATA / "authoritative/pricefm_stage_r96_scoring_only_test_prep_20260908"
OUTPUT = DATA / "authoritative/pricefm_stage_r96_scoring_only_test_closeout_20260908"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BLOCKS = ("1-24", "25-48", "49-72", "73-96")


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--grid-dir", type=Path, default=GRID)
    value.add_argument("--prep-dir", type=Path, default=PREP)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--force", action="store_true")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def horizon_group(horizon: pd.Series) -> pd.Series:
    lower = ((horizon.astype(int) - 1) // 24) * 24 + 1
    return lower.astype(str) + "-" + (lower + 23).astype(str)


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    scale = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid R96 target scale: {path}")
    return scale


def score_fold(row: Any, atoms: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    output = Path(row.output_dir)
    adapter = Path(json.loads(Path(row.task_config).read_text())["adapter_dir"])
    terminal_path = output / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if (
        terminal.get("status") != "completed"
        or terminal.get("validation_replay_passed") is not True
        or terminal.get("model_fitted") is not False
        or terminal.get("selection_changed") is not False
        or terminal.get("test_opened") is not True
    ):
        raise RuntimeError(f"Invalid R96 scoring terminal: {terminal_path}")
    for name, expected in terminal["retained_artifact_sha256"].items():
        path = adapter / name if name in {
            "rows_test.csv", "rows_val.csv", "adapter_manifest.json", "feature_manifest.json"
        } else output / name
        if not path.is_file() or sha256(path) != expected:
            raise RuntimeError(f"Changed R96 retained artifact: {path}")
    replay = pd.read_csv(output / "validation_replay.csv")
    predictions = pd.read_csv(output / "test_predictions_scaled.csv")
    truth = pd.read_csv(adapter / "rows_test.csv")
    selected = atoms.loc[atoms.case_id.eq(row.case_id)].sort_values("tau")
    if (
        len(selected) != 7
        or not np.allclose(selected.tau.to_numpy(float), TAUS)
        or len(predictions) != len(truth) * 7
        or not replay.passed.astype(bool).all()
    ):
        raise RuntimeError(f"Incomplete R96 Fold-{row.fold} test surface")
    if predictions.duplicated(["origin_id", "horizon", "tau"]).any():
        raise RuntimeError(f"Duplicate R96 Fold-{row.fold} prediction keys")
    if set(predictions.horizon.astype(int)) != set(range(1, 97)):
        raise RuntimeError(f"Incomplete R96 Fold-{row.fold} horizons")
    scaler_path = Path(selected.scaler_path.iloc[0])
    if selected.scaler_path.nunique() != 1 or sha256(scaler_path) != selected.scaler_sha256.iloc[0]:
        raise RuntimeError(f"Changed R96 Fold-{row.fold} scaler")
    scale = target_scale(scaler_path, row.region)
    merged = predictions.merge(
        truth[["origin_id", "horizon", "y_scaled"]],
        on=["origin_id", "horizon"], how="left", validate="many_to_one",
    )
    if merged.y_scaled.isna().any() or not np.isfinite(merged[["y_scaled", "pred_scaled"]]).all().all():
        raise RuntimeError(f"Invalid R96 Fold-{row.fold} scored rows")
    error = merged.y_scaled - merged.pred_scaled
    merged["loss"] = np.maximum(merged.tau * error, (merged.tau - 1.0) * error) * scale
    merged["horizon_group"] = horizon_group(merged.horizon)
    quantiles = merged.groupby("tau", as_index=False).loss.mean().rename(
        columns={"loss": "candidate_test_AQL"}
    )
    quantiles.insert(0, "fold", int(row.fold))
    quantiles.insert(0, "region", row.region)
    quantiles.insert(0, "case_id", row.case_id)
    horizons = merged.groupby("horizon_group", as_index=False).loss.mean().rename(
        columns={"loss": "candidate_test_AQL"}
    )
    horizons.insert(0, "fold", int(row.fold))
    horizons.insert(0, "region", row.region)
    horizons.insert(0, "case_id", row.case_id)
    if set(horizons.horizon_group) != set(BLOCKS):
        raise RuntimeError(f"Incomplete R96 Fold-{row.fold} horizon groups")
    wide = merged.pivot(index=["origin_id", "horizon"], columns="tau", values="pred_scaled")
    wide = wide.loc[:, list(TAUS)]
    crossing = wide.to_numpy()[:, :-1] > wide.to_numpy()[:, 1:]
    median = merged.loc[np.isclose(merged.tau, 0.5)]
    median_error = (median.y_scaled - median.pred_scaled).to_numpy(float) * scale
    case = {
        "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
        "selected_family": "exal",
        "selected_validation_AQL": float(selected.selected_validation_AQL.iloc[0]),
        "candidate_test_AQL": float(merged.loss.mean()),
        "candidate_test_MAE": float(np.abs(median_error).mean()),
        "candidate_test_RMSE": float(np.sqrt(np.mean(np.square(median_error)))),
        "adjacent_crossing_rate": float(crossing.mean()),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
        "test_truth_rows": len(truth),
        "validation_replay_max_abs_diff": float(replay.maximum_absolute_difference.max()),
        "validation_replay_pass": True,
        "model_refitted": False, "selection_changed_after_test": False,
    }
    return quantiles, horizons, case


def apply_promotion_gates(
    cases: pd.DataFrame,
    quantiles: pd.DataFrame,
    horizons: pd.DataFrame,
    references: pd.DataFrame,
) -> pd.DataFrame:
    decisions = cases.merge(references, on=["region", "fold"], validate="one_to_one")
    qcheck = quantiles.groupby(["region", "fold"]).agg(
        quantile_rows=("tau", "size"), quantiles=("tau", "nunique"),
        quantiles_finite=("candidate_test_AQL", lambda x: bool(np.isfinite(x).all())),
    ).reset_index()
    hcheck = horizons.groupby(["region", "fold"]).agg(
        horizon_rows=("horizon_group", "size"),
        horizon_blocks=("horizon_group", "nunique"),
        horizons_finite=("candidate_test_AQL", lambda x: bool(np.isfinite(x).all())),
    ).reset_index()
    decisions = decisions.merge(qcheck, on=["region", "fold"], validate="one_to_one")
    decisions = decisions.merge(hcheck, on=["region", "fold"], validate="one_to_one")
    decisions["full_quantile_confirmation_pass"] = (
        decisions.quantile_rows.eq(7) & decisions.quantiles.eq(7) & decisions.quantiles_finite
    )
    decisions["full_horizon_confirmation_pass"] = (
        decisions.horizon_rows.eq(4) & decisions.horizon_blocks.eq(4) & decisions.horizons_finite
    )
    decisions["beats_authoritative_qdesn"] = (
        decisions.candidate_test_AQL < decisions.authoritative_qdesn_test_AQL
    )
    decisions["beats_cached_pricefm"] = (
        decisions.candidate_test_AQL < decisions.cached_pricefm_test_AQL
    )
    decisions["delta_candidate_minus_qdesn"] = (
        decisions.candidate_test_AQL - decisions.authoritative_qdesn_test_AQL
    )
    decisions["delta_candidate_minus_pricefm"] = (
        decisions.candidate_test_AQL - decisions.cached_pricefm_test_AQL
    )
    decisions["promotion_eligible"] = (
        decisions.beats_authoritative_qdesn & decisions.beats_cached_pricefm
        & decisions.full_quantile_confirmation_pass & decisions.full_horizon_confirmation_pass
        & decisions.validation_replay_pass & ~decisions.model_refitted
        & ~decisions.selection_changed_after_test
    )
    decisions["decision"] = np.where(
        decisions.promotion_eligible,
        "candidate_passes_gate_for_separate_integration_review",
        "retain_current_authoritative_qdesn",
    )
    decisions["registry_mutation_authorized"] = False
    decisions["article_mutation_authorized"] = False
    return decisions.sort_values("fold")


def run(args: argparse.Namespace) -> dict[str, Any]:
    launch_path = args.grid_dir / "launch_summary.json"
    prep_summary_path = args.prep_dir / "summary.json"
    contract_path = args.prep_dir / "promotion_contract.json"
    manifest_path = args.grid_dir / "task_manifest.csv"
    status_path = args.grid_dir / "launch_status.csv"
    selected_path = args.prep_dir / "pricefm_stage_r96_frozen_atom_manifest.csv"
    references_path = args.prep_dir / "pricefm_stage_r96_frozen_dual_references.csv"
    for path in (
        launch_path, prep_summary_path, contract_path, manifest_path,
        status_path, selected_path, references_path,
    ):
        if not path.is_file():
            raise FileNotFoundError(path)
    launch = json.loads(launch_path.read_text())
    prep = json.loads(prep_summary_path.read_text())
    contract = json.loads(contract_path.read_text())
    if (
        launch.get("status") != "completed_scoring_only_test"
        or launch.get("completed") != 3
        or launch.get("failed") != 0
        or launch.get("model_refits") != 0
        or prep.get("model_refits_authorized") != 0
        or contract.get("model_refit_authorized") is not False
    ):
        raise RuntimeError("R96 scoring-only launch is not complete and admissible")
    manifest = pd.read_csv(manifest_path).sort_values("fold")
    statuses = pd.read_csv(status_path).set_index("task_id")
    atoms = pd.read_csv(selected_path)
    references = pd.read_csv(references_path)
    if len(manifest) != 3 or len(atoms) != 21 or len(references) != 3:
        raise RuntimeError("R96 closeout input surface is incomplete")

    qrows: list[pd.DataFrame] = []
    hrows: list[pd.DataFrame] = []
    case_rows: list[dict[str, Any]] = []
    for row in manifest.itertuples(index=False):
        if statuses.loc[row.task_id, "status"] not in {"completed", "skipped_completed"}:
            raise RuntimeError(f"R96 task is incomplete: {row.task_id}")
        quantile, horizon, case = score_fold(row, atoms)
        qrows.append(quantile)
        hrows.append(horizon)
        case_rows.append(case)
    quantiles = pd.concat(qrows, ignore_index=True).sort_values(["fold", "tau"])
    horizons = pd.concat(hrows, ignore_index=True).sort_values(["fold", "horizon_group"])
    cases = pd.DataFrame(case_rows).sort_values("fold")
    decisions = apply_promotion_gates(cases, quantiles, horizons, references)

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    quantiles.to_csv(output / "pricefm_stage_r96_candidate_test_quantile_metrics.csv", index=False)
    horizons.to_csv(output / "pricefm_stage_r96_candidate_test_horizon_metrics.csv", index=False)
    decisions.to_csv(output / "pricefm_stage_r96_se2_fold_comparison.csv", index=False)
    promotion = decisions.loc[decisions.promotion_eligible].copy()
    promotion.to_csv(output / "pricefm_stage_r96_promotion_review_queue.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "R96_complete_three_of_three", "passed": True, "observed": 3},
        {"gate": "no_model_refits", "passed": not decisions.model_refitted.any(), "observed": 0},
        {"gate": "validation_replay_all_folds", "passed": decisions.validation_replay_pass.all(), "observed": int(decisions.validation_replay_pass.sum())},
        {"gate": "complete_twenty_one_quantile_metrics", "passed": len(quantiles) == 21, "observed": len(quantiles)},
        {"gate": "complete_twelve_horizon_metrics", "passed": len(horizons) == 12, "observed": len(horizons)},
        {"gate": "selection_unchanged_after_test", "passed": not decisions.selection_changed_after_test.any(), "observed": "frozen R95 exAL"},
        {"gate": "registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R96 closeout gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r96_closeout_gates.csv", index=False)
    source_paths = (
        Path(__file__).resolve(), launch_path, prep_summary_path, contract_path,
        manifest_path, status_path, selected_path, references_path,
    )
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in source_paths
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r96_scoring_only_test_closed_promotion_review_frozen",
        "region": "SE_2", "folds": 3, "selected_family": "exal",
        "candidate_beats_authoritative_qdesn_folds": int(decisions.beats_authoritative_qdesn.sum()),
        "candidate_beats_cached_pricefm_folds": int(decisions.beats_cached_pricefm.sum()),
        "candidate_beats_both_folds": int((decisions.beats_authoritative_qdesn & decisions.beats_cached_pricefm).sum()),
        "promotion_review_folds": len(promotion),
        "all_folds_pass_promotion_gate": bool(decisions.promotion_eligible.all()),
        "mean_candidate_test_AQL": float(decisions.candidate_test_AQL.mean()),
        "mean_authoritative_qdesn_test_AQL": float(decisions.authoritative_qdesn_test_AQL.mean()),
        "mean_cached_pricefm_test_AQL": float(decisions.cached_pricefm_test_AQL.mean()),
        "model_refits": 0, "selection_changes_after_test": 0,
        "registry_mutated": False, "article_mutated": False,
        "additional_region_launch_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    table = decisions[[
        "fold", "candidate_test_AQL", "authoritative_qdesn_test_AQL",
        "cached_pricefm_test_AQL", "beats_authoritative_qdesn",
        "beats_cached_pricefm", "promotion_eligible",
    ]].to_markdown(index=False)
    recommendation = (
        "All three folds pass the strict dual-comparator gate. Submit the frozen queue for separate registry/article review."
        if decisions.promotion_eligible.all() else
        "Retain authority for every failing fold. Do not retune from test; use the frozen comparison as audit evidence."
    )
    (output / "pricefm_stage_r96_test_comparison_report.md").write_text(
        "# PriceFM Stage-R96 SE_2 Test Comparison\n\n" + table + "\n\n" + recommendation +
        " Registry and article files were not modified.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
