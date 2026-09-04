#!/usr/bin/env python3
"""Close out the R76/R83 exAL surface and freeze validation-only AL/exAL choices."""

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
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
R76 = DATA / "experiment_grids/pricefm_stage_r76_repaired_exal_surface_20260902"
R83 = DATA / "experiment_grids/pricefm_stage_r83_structured_init_failed_atom_retry_20260904"
OUTPUT = DATA / "authoritative/pricefm_stage_r84_independent_vb_family_selection_20260904"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}
RUNTIME_CONTRACTS = {
    "R76": {
        "version": "1.1.1.9002",
        "repair": "scale-aware-SPD-plus-large-n-GIG",
    },
    "R83": {
        "version": "1.1.1.9004",
        "repair": (
            "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-"
            "plus-structured-plugin-init"
        ),
    },
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--case-manifest", type=Path, default=R69B / "case_manifest.csv")
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--r76-manifest", type=Path, default=R76 / "task_manifest.csv")
    p.add_argument("--r76-status", type=Path, default=R76 / "launch_status.csv")
    p.add_argument("--r83-manifest", type=Path, default=R83 / "retry_manifest.csv")
    p.add_argument("--r83-status", type=Path, default=R83 / "launch_status.csv")
    p.add_argument("--r83-summary", type=Path, default=R83 / "launch_summary.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def pinball(y: np.ndarray, prediction: np.ndarray, tau: float) -> np.ndarray:
    error = y - prediction
    return np.maximum(tau * error, (tau - 1.0) * error)


def numeric_trace_frame(
    trace: pd.DataFrame, required: list[str], source_stage: str, output: Path
) -> pd.DataFrame:
    try:
        return trace.loc[:, required].apply(pd.to_numeric, errors="raise").astype(float)
    except (TypeError, ValueError) as error:
        raise RuntimeError(f"Non-numeric {source_stage} trace: {output}") from error


def validate_output(output: Path, expected_task: str, source_stage: str) -> dict:
    terminal_path = output / "terminal.json"
    terminal = json.loads(terminal_path.read_text())
    if (
        terminal.get("status") != "completed"
        or terminal.get("task_id") != expected_task
        or terminal.get("test_loaded") is not False
    ):
        raise RuntimeError(f"Invalid completed terminal: {terminal_path}")
    hashes = terminal.get("artifact_sha256") or {}
    required = ["predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
                "vb_trace.csv", "warm_start_manifest.json"]
    if source_stage == "R83":
        required.append("structured_initialization.json")
    for name in required:
        path = output / name
        if not path.is_file() or hashes.get(name) != sha256(path):
            raise RuntimeError(f"Changed completed artifact: {path}")
    if any(path.suffix in BINARY_SUFFIXES for path in output.rglob("*") if path.is_file()):
        raise RuntimeError(f"Binary model artifact found in {output}")
    contract = RUNTIME_CONTRACTS[source_stage]
    package = terminal.get("package") or {}
    if package.get("version") != contract["version"] or package.get("repair") != contract["repair"]:
        raise RuntimeError(f"Wrong {source_stage} runtime provenance: {terminal_path}")
    if source_stage == "R83":
        initialization = json.loads((output / "structured_initialization.json").read_text())
        if (
            initialization.get("mode") != "plugin_at_warm_start_before_structured_update"
            or initialization.get("package_version") != contract["version"]
            or initialization.get("package_repair") != contract["repair"]
            or initialization.get("test_loaded") is not False
        ):
            raise RuntimeError(f"Wrong R83 initialization provenance: {output}")
    return terminal


def resolve_atoms(r76: pd.DataFrame, status76: pd.DataFrame,
                  r83: pd.DataFrame, status83: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    status76 = status76.set_index("task_id")
    status83 = status83.set_index("task_id")
    replacements = r83.set_index("source_task_id")
    rows, sources = [], {}
    for task in r76.sort_values(["region", "fold", "tau"]).itertuples(index=False):
        original_status = str(status76.loc[task.task_id, "status"])
        if original_status == "completed":
            source_stage = "R76"
            source_task = task.task_id
            output = Path(task.output_dir)
        elif original_status == "failed":
            if task.task_id not in replacements.index:
                raise RuntimeError(f"No R83 replacement for failed atom {task.task_id}")
            replacement = replacements.loc[task.task_id]
            if str(status83.loc[replacement.task_id, "status"]) not in {"completed", "skipped_completed"}:
                raise RuntimeError(f"R83 replacement did not complete: {replacement.task_id}")
            source_stage = "R83"
            source_task = str(replacement.task_id)
            output = Path(replacement.output_dir)
        else:
            raise RuntimeError(f"Unexpected R76 status for {task.task_id}: {original_status}")
        terminal = validate_output(output, source_task, source_stage)
        prediction = pd.read_csv(output / "predictions_scaled.csv")
        method = pd.read_csv(output / "method_summary.csv").iloc[0]
        parameter = pd.read_csv(output / "parameter_summary.csv").iloc[0]
        trace = pd.read_csv(output / "vb_trace.csv")
        contract = RUNTIME_CONTRACTS[source_stage]
        if str(method.package_version) != contract["version"] or str(method.repair) != contract["repair"]:
            raise RuntimeError(f"Wrong {source_stage} method provenance: {output}")
        required_trace = ["sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"]
        # Historical traces can contain numeric CSV fields inferred as strings.
        # Coerce once so both the finite check and all registered bounds use the
        # same validated numeric representation.
        numeric_trace = numeric_trace_frame(trace, required_trace, source_stage, output)
        trace_values = numeric_trace.to_numpy(dtype=float)
        trace_finite = bool(np.isfinite(trace_values).all())
        beta_l2 = float(parameter.beta_l2)
        beta_l2_ratio = float(beta_l2 / max(float(parameter.al_init_beta_l2), 1e-12))
        max_sigma = float(numeric_trace.sigma.max())
        max_abs_gamma = float(numeric_trace.gamma.abs().max())
        first_delta_state = float(numeric_trace.delta_state.iloc[0])
        stable_tail = bool(
            trace_finite
            and numeric_trace.tail(10).delta_state.max() < 2
            and numeric_trace.tail(10).delta_sigma.max() < 2
        )
        repair_bounds_passed = bool(
            source_stage != "R83"
            or (
                max_sigma < 100
                and beta_l2_ratio < 10
                and max_abs_gamma < 4
                and first_delta_state < 100
            )
        )
        key = (str(task.case_id), round(float(task.tau), 12))
        sources[key] = prediction
        rows.append({
            "case_id": task.case_id,
            "region": task.region,
            "fold": int(task.fold),
            "tau": float(task.tau),
            "source_stage": source_stage,
            "source_task_id": source_task,
            "output_dir": str(output.resolve()),
            "prediction_path": str((output / "predictions_scaled.csv").resolve()),
            "prediction_sha256": sha256(output / "predictions_scaled.csv"),
            "terminal_path": str((output / "terminal.json").resolve()),
            "terminal_sha256": sha256(output / "terminal.json"),
            "package_version": str(method.package_version),
            "package_repair": str(method.repair),
            "converged": boolish(method.converged),
            "iter": int(method.iter),
            "structured_updates": int(method.structured_updates),
            "trace_finite": trace_finite,
            "tail_stable": stable_tail,
            "repair_bounds_passed": repair_bounds_passed,
            "max_sigma": max_sigma,
            "beta_l2_ratio": beta_l2_ratio,
            "max_abs_gamma": max_abs_gamma,
            "first_delta_state": first_delta_state,
            "final_delta_state": float(numeric_trace.delta_state.iloc[-1]),
            "final_delta_sigma": float(numeric_trace.delta_sigma.iloc[-1]),
            "beta_l2": beta_l2,
            "sigma": float(parameter.sigma),
            "gamma": float(parameter.gamma),
            "test_opened": False,
        })
    frame = pd.DataFrame(rows)
    if len(frame) != 294 or frame.case_id.nunique() != 42 or not frame.groupby("case_id").tau.nunique().eq(7).all():
        raise RuntimeError("R76/R83 did not resolve to 42 complete seven-quantile surfaces")
    if frame.source_stage.value_counts().to_dict() != {"R76": 280, "R83": 14}:
        raise RuntimeError("R76/R83 atom partition changed")
    return frame, sources


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    scale = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid target scale: {path}")
    return scale


def evaluate_exal(case: Any, atoms: pd.DataFrame, sources: dict,
                  r73_case: pd.Series) -> dict:
    adapter = Path(case.adapter_dir)
    if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
        raise RuntimeError(f"Test data found in validation adapter: {adapter}")
    truth = pd.read_csv(adapter / "rows_val.csv")
    if not {"origin_id", "horizon", "y_scaled"}.issubset(truth) or truth.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Invalid validation truth: {adapter}")
    wide = truth[["origin_id", "horizon", "y_scaled"]].copy()
    for tau in TAUS:
        pred = sources[(case.case_id, round(tau, 12))].copy()
        if set(pred.split.astype(str)) != {"val"} or not np.allclose(pred.tau.astype(float), tau):
            raise RuntimeError(f"Invalid validation prediction for {case.case_id} tau {tau}")
        pred = pred[["origin_id", "horizon", "pred_scaled"]].rename(
            columns={"pred_scaled": f"q_{tau:g}"}
        )
        wide = wide.merge(pred, on=["origin_id", "horizon"], how="left", validate="one_to_one")
    matrix = wide[[f"q_{tau:g}" for tau in TAUS]].to_numpy(float)
    y = wide.y_scaled.to_numpy(float)
    if not np.isfinite(matrix).all() or not np.isfinite(y).all():
        raise RuntimeError(f"Non-finite completed validation surface: {case.case_id}")
    scale_path = Path(r73_case.scaler_path)
    if sha256(scale_path) != r73_case.scaler_sha256:
        raise RuntimeError(f"Changed R73 scaler: {scale_path}")
    scale = target_scale(scale_path, case.region)
    raw = np.column_stack([pinball(y, matrix[:, i], tau) for i, tau in enumerate(TAUS)])
    arranged_matrix = np.sort(matrix, axis=1)
    arranged = np.column_stack([
        pinball(y, arranged_matrix[:, i], tau) for i, tau in enumerate(TAUS)
    ])
    crossing = matrix[:, :-1] > matrix[:, 1:]
    case_atoms = atoms[atoms.case_id.eq(case.case_id)]
    return {
        "case_id": case.case_id,
        "region": case.region,
        "fold": int(case.fold),
        "validation_rows": len(wide),
        "exal_raw_validation_AQL": float(raw.mean() * scale),
        "exal_rearranged_validation_AQL_sensitivity": float(arranged.mean() * scale),
        "al_validation_AQL": float(r73_case.validation_AQL),
        "exal_minus_al_raw_validation_AQL": float(raw.mean() * scale - r73_case.validation_AQL),
        "exal_raw_beats_al": bool(raw.mean() * scale < r73_case.validation_AQL),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
        "adjacent_crossing_rate": float(crossing.mean()),
        "all_atoms_trace_finite": bool(case_atoms.trace_finite.all()),
        "all_atoms_tail_stable": bool(case_atoms.tail_stable.all()),
        "all_r83_atoms_repair_bounded": bool(case_atoms.repair_bounds_passed.all()),
        "converged_atoms": int(case_atoms.converged.sum()),
        "all_atoms_converged": bool(case_atoms.converged.all()),
        "r83_replacement_atoms": int(case_atoms.source_stage.eq("R83").sum()),
        "selection_eligible": bool(
            case_atoms.trace_finite.all()
            and case_atoms.tail_stable.all()
            and case_atoms.repair_bounds_passed.all()
        ),
        "test_opened": False,
    }


def run(args: argparse.Namespace) -> dict:
    r83_summary = json.loads(args.r83_summary.read_text())
    if r83_summary.get("status") != "completed" or r83_summary.get("failed") != 0:
        raise RuntimeError("R83 has not completed cleanly")
    cases = pd.read_csv(args.case_manifest)
    r73_metrics = pd.read_csv(args.r73_dir / "pricefm_stage_r73_case_validation_metrics.csv")
    r73_atoms = pd.read_csv(args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv")
    r76 = pd.read_csv(args.r76_manifest)
    status76 = pd.read_csv(args.r76_status)
    r83 = pd.read_csv(args.r83_manifest)
    status83 = pd.read_csv(args.r83_status)
    atoms, sources = resolve_atoms(r76, status76, r83, status83)

    r73_by_case = r73_metrics.set_index("case_id")
    exal_cases = set(atoms.case_id)
    rows = []
    case_by_id = cases.set_index("case_id")
    for case_id in sorted(exal_cases):
        case = case_by_id.loc[case_id]
        case.name = case_id
        case_obj = type("Case", (), {**case.to_dict(), "case_id": case_id})
        rows.append(evaluate_exal(case_obj, atoms, sources, r73_by_case.loc[case_id]))
    metrics = pd.DataFrame(rows).sort_values(["region", "fold"])

    selections = []
    for row in r73_metrics.sort_values(["region", "fold"]).itertuples(index=False):
        if row.case_id not in exal_cases:
            selected, reason = "al", "frozen_r69a_al_anchor_no_new_exal_refit"
            exal_aql, eligible = np.nan, False
        else:
            exal = metrics.set_index("case_id").loc[row.case_id]
            eligible = bool(exal.selection_eligible)
            if eligible and bool(exal.exal_raw_beats_al):
                selected, reason = "exal", "lower_raw_validation_AQL_and_integrity_pass"
            else:
                selected = "al"
                reason = "exal_integrity_block" if not eligible else "al_lower_or_equal_raw_validation_AQL"
            exal_aql = float(exal.exal_raw_validation_AQL)
        selections.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "r69a_family_anchor": row.selected_family_anchor,
            "al_validation_AQL": float(row.validation_AQL),
            "exal_validation_AQL": exal_aql,
            "exal_selection_eligible": eligible,
            "selected_family": selected,
            "selected_validation_AQL": exal_aql if selected == "exal" else float(row.validation_AQL),
            "selection_rule": "raw_original_seven_quantile_validation_AQL_with_integrity_guard",
            "selection_reason": reason,
            "test_opened": False,
            "registry_mutated": False,
            "article_mutated": False,
        })
    selection = pd.DataFrame(selections).sort_values(["region", "fold"])

    selected_atoms = []
    al_index = r73_atoms.set_index(["case_id", "tau"])
    exal_index = atoms.set_index(["case_id", "tau"])
    for row in selection.itertuples(index=False):
        for tau in TAUS:
            source = exal_index.loc[(row.case_id, tau)] if row.selected_family == "exal" else al_index.loc[(row.case_id, tau)]
            selected_atoms.append({
                "case_id": row.case_id,
                "region": row.region,
                "fold": row.fold,
                "tau": tau,
                "selected_family": row.selected_family,
                "source_stage": source.source_stage,
                "prediction_path": source.prediction_path,
                "prediction_sha256": source.prediction_sha256,
                "selection_split": "val",
                "test_access_authorized": False,
                "registry_mutation_authorized": False,
                "article_mutation_authorized": False,
            })
    selected_manifest = pd.DataFrame(selected_atoms).sort_values(["region", "fold", "tau"])
    if len(selection) != 56 or len(selected_manifest) != 392:
        raise RuntimeError("R84 final independent surface is incomplete")

    gates = pd.DataFrame([
        {"gate": "r76_frozen_partition", "passed": True, "observed": "280 completed; 14 failed"},
        {"gate": "r83_exact_replacement_partition", "passed": True, "observed": "14 atoms; 11 cases"},
        {"gate": "complete_exal_anchor_surface", "passed": len(atoms) == 294, "observed": len(atoms)},
        {"gate": "complete_selected_independent_surface", "passed": len(selected_manifest) == 392,
         "observed": len(selected_manifest)},
        {"gate": "validation_only_selection", "passed": True, "observed": "raw original-scale AQL"},
        {"gate": "rearrangement_is_sensitivity_only", "passed": True, "observed": "not used for selection"},
        {"gate": "test_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R84 closeout gates failed")

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True)
    atoms.to_csv(output / "pricefm_stage_r84_exal_atom_ledger.csv", index=False)
    metrics.to_csv(output / "pricefm_stage_r84_exal_case_validation_metrics.csv", index=False)
    selection.to_csv(output / "pricefm_stage_r84_family_selection.csv", index=False)
    selected_manifest.to_csv(output / "pricefm_stage_r84_selected_atom_manifest.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r84_closeout_gates.csv", index=False)
    fixed_sources = [Path(__file__).resolve(), args.case_manifest, args.r76_manifest,
                     args.r76_status, args.r83_manifest, args.r83_status, args.r83_summary,
                     args.r73_dir / "pricefm_stage_r73_case_validation_metrics.csv",
                     args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv"]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed_sources
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "provisional_selection_quarantined_pending_surface_wide_repair",
        "scientific_authority": False,
        "cases": 56,
        "al_selected_cases": int(selection.selected_family.eq("al").sum()),
        "exal_selected_cases": int(selection.selected_family.eq("exal").sum()),
        "exal_anchor_cases": 42,
        "r76_atoms_reused": 280,
        "r83_atoms_repaired": 14,
        "selected_atoms": 392,
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "recommended_next_action": "audit_and_refit_all_280_legacy_r76_atoms_before_selection_or_test",
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r84_independent_vb_family_selection_report.md").write_text(
        "# PriceFM Stage-R84 Independent VB Family Selection\n\n"
        "R84 is a provisional diagnostic reconstruction that reuses 280 R76 exAL atoms and "
        "exactly 14 R83 numerical replacements. A later surface-wide audit found that every "
        "R76 atom used the invalid nonsmooth delta initializer, including atoms that happened "
        "to terminate successfully. Therefore this ranking has no scientific authority and "
        "cannot authorize test access. It "
        "does not refit AL. For each of the 42 exAL-anchor region/fold cases, it compares the "
        "complete raw seven-quantile exAL validation AQL with the corresponding R73 AL AQL. "
        "The lower family is selected only when all exAL traces are finite and tail-stable. The "
        "remaining 14 AL-anchor cases retain AL. Rowwise monotone rearrangement is reported only "
        "as a sensitivity and cannot change selection. Test access and every registry/article "
        "mutation remain blocked until all 280 legacy R76 atoms are refit with the R82 runtime "
        "and a new validation-only selection is independently frozen.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
