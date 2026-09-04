#!/usr/bin/env python3
"""Freeze case-specific AL/exAL choices from repaired validation surfaces only."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import sys
from typing import Any

import joblib
import numpy as np
import pandas as pd
import sklearn


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
R88 = DATA / "authoritative/pricefm_stage_r88_repaired_exal_surface_closeout_20260905"
OUTPUT = DATA / "authoritative/pricefm_stage_r89_validation_family_selection_20260905"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--case-manifest", type=Path, default=R69B / "case_manifest.csv")
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--r88-dir", type=Path, default=R88)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--required-sklearn-version", default="1.8.0")
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


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    value = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(value) or value <= 0:
        raise RuntimeError(f"Invalid target scale: {path}")
    return value


def beta_path_for_al(atom: Any) -> Path:
    parent = Path(atom.prediction_path).parent
    if atom.source_stage == "R69B":
        return parent / "al_beta_mean.csv"
    if atom.source_stage == "R72":
        return parent / "beta_summary.csv"
    raise RuntimeError(f"Unknown R73 AL source stage: {atom.source_stage}")


def evaluate_surface(case_id: str, atoms: pd.DataFrame, rows_val: Path,
                     scale: float) -> dict[str, Any]:
    truth = pd.read_csv(rows_val)
    if not {"origin_id", "horizon", "y_scaled"}.issubset(truth):
        raise RuntimeError(f"Invalid validation rows: {rows_val}")
    if truth.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Duplicate validation rows: {rows_val}")
    wide = truth[["origin_id", "horizon", "y_scaled"]].copy()
    index = atoms.set_index("tau")
    for tau in TAUS:
        if tau not in index.index:
            raise RuntimeError(f"Missing {case_id} tau={tau}")
        atom = index.loc[tau]
        prediction = pd.read_csv(atom.prediction_path)
        if set(prediction.split.astype(str)) != {"val"}:
            raise RuntimeError(f"Non-validation prediction: {atom.prediction_path}")
        if not np.allclose(prediction.tau.astype(float), tau):
            raise RuntimeError(f"Wrong prediction quantile: {atom.prediction_path}")
        prediction = prediction[["origin_id", "horizon", "pred_scaled"]].rename(
            columns={"pred_scaled": f"q_{tau:g}"}
        )
        wide = wide.merge(prediction, on=["origin_id", "horizon"], how="left", validate="one_to_one")
    matrix = wide[[f"q_{tau:g}" for tau in TAUS]].to_numpy(float)
    y = wide.y_scaled.to_numpy(float)
    if not np.isfinite(matrix).all() or not np.isfinite(y).all():
        raise RuntimeError(f"Non-finite validation surface: {case_id}")
    losses = np.column_stack([pinball(y, matrix[:, i], tau) for i, tau in enumerate(TAUS)])
    arranged = np.sort(matrix, axis=1)
    arranged_losses = np.column_stack([
        pinball(y, arranged[:, i], tau) for i, tau in enumerate(TAUS)
    ])
    crossing = matrix[:, :-1] > matrix[:, 1:]
    return {
        "case_id": case_id,
        "validation_rows": len(wide),
        "raw_validation_AQL": float(losses.mean() * scale),
        "rearranged_validation_AQL_sensitivity": float(arranged_losses.mean() * scale),
        "adjacent_crossing_rate": float(crossing.mean()),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    if sklearn.__version__ != args.required_sklearn_version:
        raise RuntimeError(
            f"R89 requires scikit-learn {args.required_sklearn_version}; observed {sklearn.__version__}"
        )
    r88_summary_path = args.r88_dir / "summary.json"
    r88_summary = json.loads(r88_summary_path.read_text())
    if r88_summary.get("r89_validation_selection_authorized") is not True:
        raise RuntimeError("R88 does not authorize R89")
    cases = pd.read_csv(args.case_manifest)
    r73_metrics_path = args.r73_dir / "pricefm_stage_r73_case_validation_metrics.csv"
    r73_atoms_path = args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv"
    r88_atoms_path = args.r88_dir / "pricefm_stage_r88_exal_atom_ledger.csv"
    r88_cases_path = args.r88_dir / "pricefm_stage_r88_exal_case_eligibility.csv"
    r73_metrics = pd.read_csv(r73_metrics_path)
    r73_atoms = pd.read_csv(r73_atoms_path)
    r88_atoms = pd.read_csv(r88_atoms_path)
    r88_cases = pd.read_csv(r88_cases_path).set_index("case_id")
    if len(cases) != 56 or len(r73_metrics) != 56 or len(r73_atoms) != 392:
        raise RuntimeError("R89 requires the complete 56-case R73 AL surface")
    if len(r88_atoms) != 294 or r88_atoms.case_id.nunique() != 42:
        raise RuntimeError("R89 requires the complete repaired R88 exAL surface")

    case_index = cases.set_index("case_id")
    al_metric_index = r73_metrics.set_index("case_id")
    exal_metrics = []
    for case_id, atoms in r88_atoms.groupby("case_id", sort=True):
        case = case_index.loc[case_id]
        adapter = Path(case.adapter_dir)
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"Test data present before selection freeze: {adapter}")
        scale_path = Path(al_metric_index.loc[case_id, "scaler_path"])
        if sha256(scale_path) != al_metric_index.loc[case_id, "scaler_sha256"]:
            raise RuntimeError(f"Changed scaler: {scale_path}")
        result = evaluate_surface(case_id, atoms, adapter / "rows_val.csv",
                                  target_scale(scale_path, case.region))
        result.update({
            "region": case.region, "fold": int(case.fold),
            "all_atoms_numerically_eligible": bool(
                r88_cases.loc[case_id, "all_atoms_numerically_eligible"]
            ),
        })
        exal_metrics.append(result)
    exal = pd.DataFrame(exal_metrics).sort_values(["region", "fold"])
    exal_index = exal.set_index("case_id")

    selections = []
    for row in r73_metrics.sort_values(["region", "fold"]).itertuples(index=False):
        if row.case_id not in exal_index.index:
            family = "al"
            reason = "frozen_al_anchor_no_repaired_exal_surface"
            exal_aql = np.nan
            eligible = False
        else:
            candidate = exal_index.loc[row.case_id]
            exal_aql = float(candidate.raw_validation_AQL)
            eligible = bool(candidate.all_atoms_numerically_eligible)
            if eligible and exal_aql < float(row.validation_AQL):
                family = "exal"
                reason = "lower_raw_seven_quantile_validation_AQL_and_integrity_pass"
            elif not eligible:
                family = "al"
                reason = "complete_exal_case_integrity_block_fallback_to_al"
            else:
                family = "al"
                reason = "al_lower_or_equal_raw_seven_quantile_validation_AQL"
        selections.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "al_validation_AQL": float(row.validation_AQL),
            "exal_validation_AQL": exal_aql,
            "exal_case_eligible": eligible,
            "selected_family": family,
            "selected_validation_AQL": exal_aql if family == "exal" else float(row.validation_AQL),
            "selection_rule": "case_specific_raw_original_seven_quantile_validation_AQL",
            "selection_reason": reason,
            "selection_split": "val", "selection_frozen_before_test": True,
            "test_opened": False, "registry_mutated": False, "article_mutated": False,
        })
    selection = pd.DataFrame(selections).sort_values(["region", "fold"])

    al_index = r73_atoms.set_index(["case_id", "tau"])
    exal_atom_index = r88_atoms.set_index(["case_id", "tau"])
    selected_rows = []
    for choice in selection.itertuples(index=False):
        case = case_index.loc[choice.case_id]
        adapter = Path(case.adapter_dir)
        feature_manifest = adapter / "feature_manifest.json"
        rows_val = adapter / "rows_val.csv"
        x_val = adapter / "X_val.csv"
        source_config = Path(case.config)
        for tau in TAUS:
            if choice.selected_family == "exal":
                atom = exal_atom_index.loc[(choice.case_id, tau)]
                beta = Path(atom.beta_path)
                source_stage = atom.source_stage
                prediction = Path(atom.prediction_path)
                prediction_hash = atom.prediction_sha256
                terminal = Path(atom.terminal_path)
                terminal_hash = atom.terminal_sha256
            else:
                atom = al_index.loc[(choice.case_id, tau)]
                beta = beta_path_for_al(atom)
                source_stage = atom.source_stage
                prediction = Path(atom.prediction_path)
                prediction_hash = atom.prediction_sha256
                terminal = Path(atom.terminal_path)
                terminal_hash = atom.terminal_sha256
            if not beta.is_file():
                raise FileNotFoundError(beta)
            selected_rows.append({
                "case_id": choice.case_id, "region": choice.region, "fold": choice.fold,
                "tau": tau, "selected_family": choice.selected_family,
                "selected_validation_AQL": choice.selected_validation_AQL,
                "source_stage": source_stage,
                "beta_path": str(beta.resolve()), "beta_sha256": sha256(beta),
                "validation_prediction_path": str(prediction.resolve()),
                "validation_prediction_sha256": prediction_hash,
                "terminal_path": str(terminal.resolve()), "terminal_sha256": terminal_hash,
                "adapter_dir": str(adapter.resolve()),
                "feature_manifest_path": str(feature_manifest.resolve()),
                "feature_manifest_sha256": sha256(feature_manifest),
                "x_val_path": str(x_val.resolve()), "x_val_sha256": sha256(x_val),
                "rows_val_path": str(rows_val.resolve()), "rows_val_sha256": sha256(rows_val),
                "source_case_config": str(source_config.resolve()),
                "source_case_config_sha256": sha256(source_config),
                "scaler_path": al_metric_index.loc[choice.case_id, "scaler_path"],
                "scaler_sha256": al_metric_index.loc[choice.case_id, "scaler_sha256"],
                "selection_split": "val", "test_access_authorized": False,
                "registry_mutation_authorized": False, "article_mutation_authorized": False,
                "joint_model_authorized": False, "mcmc_authorized": False,
            })
    selected = pd.DataFrame(selected_rows).sort_values(["region", "fold", "tau"])
    if len(selection) != 56 or len(selected) != 392:
        raise RuntimeError("R89 selected surface is incomplete")

    gates = pd.DataFrame([
        {"gate": "complete_56_case_selection", "passed": len(selection) == 56, "observed": len(selection)},
        {"gate": "complete_392_atom_surface", "passed": len(selected) == 392, "observed": len(selected)},
        {"gate": "one_family_per_case", "passed": selection.groupby("case_id").selected_family.nunique().eq(1).all(), "observed": "case-specific"},
        {"gate": "selection_is_validation_only", "passed": selection.selection_split.eq("val").all(), "observed": "raw AQL"},
        {"gate": "rearrangement_sensitivity_not_selection", "passed": True, "observed": "reported only"},
        {"gate": "environment_pinned", "passed": sklearn.__version__ == args.required_sklearn_version, "observed": sklearn.__version__},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R89 selection gates failed")

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    exal.to_csv(output / "pricefm_stage_r89_exal_case_validation_metrics.csv", index=False)
    selection.to_csv(output / "pricefm_stage_r89_family_selection.csv", index=False)
    selected.to_csv(output / "pricefm_stage_r89_selected_atom_manifest.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r89_selection_gates.csv", index=False)
    environment = {
        "python": platform.python_version(), "executable": sys.executable,
        "numpy": np.__version__, "pandas": pd.__version__, "scikit_learn": sklearn.__version__,
        "test_opened": False,
    }
    (output / "environment.json").write_text(json.dumps(environment, indent=2, sort_keys=True) + "\n")
    fixed = [Path(__file__).resolve(), args.case_manifest, r73_metrics_path, r73_atoms_path,
             r88_summary_path, r88_atoms_path, r88_cases_path, output / "environment.json"]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "validation_family_selection_frozen_before_test",
        "cases": 56, "selected_atoms": 392,
        "al_selected_cases": int(selection.selected_family.eq("al").sum()),
        "exal_selected_cases": int(selection.selected_family.eq("exal").sum()),
        "r90_scoring_only_test_prep_authorized": True,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r89_validation_family_selection_report.md").write_text(
        "# PriceFM Stage-R89 Validation-Only Family Selection\n\n"
        f"R89 froze one complete seven-quantile family per region/fold: "
        f"{summary['exal_selected_cases']} exAL and {summary['al_selected_cases']} AL. Selection "
        "uses raw original-scale validation AQL only. Test remains sealed; R90 may prepare a "
        "scoring-only replay but cannot refit or mutate scientific authority.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
