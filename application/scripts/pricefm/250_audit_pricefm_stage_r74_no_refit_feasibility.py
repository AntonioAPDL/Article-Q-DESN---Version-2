#!/usr/bin/env python3
"""Audit no-refit monotonicity and calibration remedies for R73 predictions.

Outcome-free rearrangement is evaluated on the full validation surface. Additive
calibration is assessed only with forward validation blocks: past origins fit an
offset and strictly later origins evaluate it. The stage is diagnostic and never
opens test data, launches fits, or mutates authoritative state.
"""

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
R69B = DATA / "experiment_grids/pricefm_stage_r69b_bounded_cran111_independent_vb_20260831/case_manifest.csv"
R73 = DATA / "authoritative/pricefm_stage_r73_completed_al_surface_20260902"
OUTPUT = DATA / "authoritative/pricefm_stage_r74_no_refit_feasibility_20260902"
TAUS = np.asarray((0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90), dtype=float)
ARMS = (
    "raw", "rearranged", "global_offset", "global_offset_rearranged",
    "horizon_block_offset", "horizon_block_offset_rearranged",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r69b-manifest", type=Path, default=R69B)
    p.add_argument("--r73-dir", type=Path, default=R73)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=56)
    p.add_argument("--expected-atoms", type=int, default=392)
    p.add_argument("--coverage-harm-tolerance", type=float, default=0.01)
    p.add_argument("--force", action="store_true")
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def pinball(y: np.ndarray, prediction: np.ndarray, tau: np.ndarray = TAUS) -> np.ndarray:
    error = y[:, None] - prediction
    return np.maximum(tau[None, :] * error, (tau[None, :] - 1.0) * error)


def metrics(y: np.ndarray, prediction: np.ndarray, scale: float) -> dict[str, float]:
    crossing = prediction[:, :-1] > prediction[:, 1:]
    coverage = np.mean(y[:, None] <= prediction, axis=0)
    return {
        "AQL": float(pinball(y, prediction).mean() * scale),
        "coverage_mae": float(np.mean(np.abs(coverage - TAUS))),
        "adjacent_crossing_rate": float(crossing.mean()),
        "row_any_crossing_rate": float(crossing.any(axis=1).mean()),
    }


def target_scale(path: Path, region: str) -> float:
    scalers = joblib.load(path)
    scale = float(np.asarray(scalers[region]["y_scaler"].scale_).reshape(-1)[0])
    if not np.isfinite(scale) or scale <= 0:
        raise RuntimeError(f"Invalid target scale: {path}")
    return scale


def case_surface(case: Any, atoms: pd.DataFrame) -> tuple[pd.DataFrame, np.ndarray]:
    adapter = Path(case.adapter_dir)
    if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
        raise RuntimeError(f"Validation adapter contains test artifacts: {adapter}")
    rows = pd.read_csv(adapter / "rows_val.csv")
    required = {"origin_id", "horizon", "y_scaled"}
    if not required.issubset(rows.columns) or rows.duplicated(["origin_id", "horizon"]).any():
        raise RuntimeError(f"Invalid validation row ledger: {adapter}")
    if "origin_market_time" in rows:
        rows["origin_order"] = pd.to_datetime(rows["origin_market_time"], utc=True)
    else:
        rows["origin_order"] = rows["origin_id"]
    rows = rows.sort_values(["origin_order", "origin_id", "horizon"]).reset_index(drop=True)
    surface = rows[["origin_id", "horizon"]].copy()
    case_atoms = atoms[atoms["case_id"].eq(case.case_id)].sort_values("tau")
    if len(case_atoms) != len(TAUS) or not np.allclose(case_atoms["tau"], TAUS):
        raise RuntimeError(f"Incomplete R73 atom surface: {case.case_id}")
    for atom in case_atoms.itertuples(index=False):
        path = Path(atom.prediction_path)
        if sha256(path) != str(atom.prediction_sha256):
            raise RuntimeError(f"Changed R73 prediction artifact: {path}")
        pred = pd.read_csv(path)
        if set(pred["split"].astype(str)) != {"val"}:
            raise RuntimeError(f"Non-validation prediction: {path}")
        pred = pred[["origin_id", "horizon", "pred_scaled"]].rename(
            columns={"pred_scaled": f"q_{float(atom.tau):g}"}
        )
        surface = surface.merge(pred, on=["origin_id", "horizon"], how="left", validate="one_to_one")
    matrix = surface[[f"q_{tau:g}" for tau in TAUS]].to_numpy(float)
    if matrix.shape[0] != len(rows) or not np.isfinite(matrix).all():
        raise RuntimeError(f"Incomplete predictions: {case.case_id}")
    return rows, matrix


def forward_blocks(rows: pd.DataFrame) -> list[tuple[str, np.ndarray, np.ndarray]]:
    origins = rows[["origin_id", "origin_order"]].drop_duplicates().sort_values("origin_order")
    ids = origins["origin_id"].to_numpy()
    if len(ids) < 6:
        raise RuntimeError("R74 requires at least six validation origins")
    first = max(1, len(ids) // 3)
    second = max(first + 1, 2 * len(ids) // 3)
    definitions = (
        ("early_to_middle", ids[:first], ids[first:second]),
        ("expanding_to_late", ids[:second], ids[second:]),
    )
    return [
        (name, rows["origin_id"].isin(cal).to_numpy(), rows["origin_id"].isin(evaluate).to_numpy())
        for name, cal, evaluate in definitions
    ]


def quantile_offset(y: np.ndarray, prediction: np.ndarray) -> np.ndarray:
    return np.asarray([
        np.quantile(y - prediction[:, index], tau, method="linear")
        for index, tau in enumerate(TAUS)
    ])


def fit_offsets(rows: pd.DataFrame, y: np.ndarray, prediction: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, dict[int, np.ndarray]]:
    global_offset = quantile_offset(y[mask], prediction[mask])
    block_offsets = {}
    block = ((rows["horizon"].to_numpy(int) - 1) // 24).astype(int)
    for value in sorted(set(block)):
        selected = mask & (block == value)
        block_offsets[value] = quantile_offset(y[selected], prediction[selected]) if selected.any() else global_offset
    return global_offset, block_offsets


def apply_arm(
    arm: str, rows: pd.DataFrame, prediction: np.ndarray,
    global_offset: np.ndarray, block_offsets: dict[int, np.ndarray],
) -> np.ndarray:
    out = prediction.copy()
    if arm.startswith("global_offset"):
        out += global_offset[None, :]
    elif arm.startswith("horizon_block_offset"):
        block = ((rows["horizon"].to_numpy(int) - 1) // 24).astype(int)
        for value, offset in block_offsets.items():
            out[block == value] += offset[None, :]
    if arm == "rearranged" or arm.endswith("_rearranged"):
        out = np.sort(out, axis=1)
    return out


def run(args: argparse.Namespace) -> dict[str, Any]:
    cases = pd.read_csv(args.r69b_manifest)
    atoms_path = args.r73_dir / "pricefm_stage_r73_al_atom_ledger.csv"
    case_metrics_path = args.r73_dir / "pricefm_stage_r73_case_validation_metrics.csv"
    atoms = pd.read_csv(atoms_path)
    r73_metrics = pd.read_csv(case_metrics_path)
    r73_summary = json.loads((args.r73_dir / "summary.json").read_text())
    if r73_summary.get("status") != "completed_al_surface_closed_out_no_automatic_promotion":
        raise RuntimeError("R73 is not a valid completed closeout")
    if len(cases) != args.expected_cases or len(atoms) != args.expected_atoms:
        raise RuntimeError("Unexpected R73 surface dimensions")
    if cases["case_id"].duplicated().any() or atoms.duplicated(["case_id", "tau"]).any():
        raise RuntimeError("Duplicate R74 source identifiers")
    r73_by_case = r73_metrics.set_index("case_id")

    full_rows: list[dict[str, Any]] = []
    block_rows: list[dict[str, Any]] = []
    offset_rows: list[dict[str, Any]] = []
    for case in cases.sort_values(["region", "fold"]).itertuples(index=False):
        rows, prediction = case_surface(case, atoms)
        y = pd.to_numeric(rows["y_scaled"], errors="coerce").to_numpy(float)
        scale = target_scale(Path(r73_by_case.loc[case.case_id, "scaler_path"]), str(case.region))
        raw = metrics(y, prediction, scale)
        rearranged = metrics(y, np.sort(prediction, axis=1), scale)
        source = r73_by_case.loc[case.case_id]
        for arm, values in (("raw", raw), ("rearranged", rearranged)):
            aql = values["AQL"]
            full_rows.append({
                "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
                "arm": arm, "validation_AQL": aql, "delta_vs_raw": aql - raw["AQL"],
                "delta_vs_prior_authoritative_qdesn": aql - float(source.prior_authoritative_qdesn_validation_AQL),
                "delta_vs_operational_pricefm": aql - float(source.operational_pricefm_validation_AQL),
                "beats_prior_authoritative_qdesn": aql < float(source.prior_authoritative_qdesn_validation_AQL),
                "beats_operational_pricefm": aql < float(source.operational_pricefm_validation_AQL),
                **{key: value for key, value in values.items() if key != "AQL"},
                "outcome_used_to_fit_transform": False, "test_opened": False,
            })
        for block_name, calibration_mask, evaluation_mask in forward_blocks(rows):
            global_offset, horizon_offsets = fit_offsets(rows, y, prediction, calibration_mask)
            for tau, value in zip(TAUS, global_offset, strict=True):
                offset_rows.append({
                    "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
                    "forward_block": block_name, "offset_scope": "global", "horizon_block": "all",
                    "tau": tau, "offset_scaled": value, "offset_original": value * scale,
                    "calibration_rows": int(calibration_mask.sum()), "test_opened": False,
                })
            for horizon_block, offsets in horizon_offsets.items():
                for tau, value in zip(TAUS, offsets, strict=True):
                    offset_rows.append({
                        "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
                        "forward_block": block_name, "offset_scope": "horizon_block",
                        "horizon_block": f"{horizon_block * 24 + 1}-{min((horizon_block + 1) * 24, 96)}",
                        "tau": tau, "offset_scaled": value, "offset_original": value * scale,
                        "calibration_rows": int(calibration_mask.sum()), "test_opened": False,
                    })
            evaluation_rows = rows.loc[evaluation_mask].reset_index(drop=True)
            evaluated = {}
            for arm in ARMS:
                transformed = apply_arm(arm, rows, prediction, global_offset, horizon_offsets)
                evaluated[arm] = metrics(y[evaluation_mask], transformed[evaluation_mask], scale)
            raw_eval = evaluated["raw"]
            for arm, values in evaluated.items():
                block_rows.append({
                    "case_id": case.case_id, "region": case.region, "fold": int(case.fold),
                    "forward_block": block_name, "arm": arm,
                    "calibration_origins": int(rows.loc[calibration_mask, "origin_id"].nunique()),
                    "evaluation_origins": int(evaluation_rows["origin_id"].nunique()),
                    "evaluation_rows": int(evaluation_mask.sum()),
                    "validation_AQL": values["AQL"], "delta_AQL_vs_raw": values["AQL"] - raw_eval["AQL"],
                    "coverage_mae": values["coverage_mae"],
                    "delta_coverage_mae_vs_raw": values["coverage_mae"] - raw_eval["coverage_mae"],
                    "adjacent_crossing_rate": values["adjacent_crossing_rate"],
                    "row_any_crossing_rate": values["row_any_crossing_rate"],
                    "selection_role": "mechanism_diagnostic_only", "test_opened": False,
                })

    full = pd.DataFrame(full_rows).sort_values(["region", "fold", "arm"])
    blocks = pd.DataFrame(block_rows).sort_values(["region", "fold", "forward_block", "arm"])
    offsets = pd.DataFrame(offset_rows).sort_values(["region", "fold", "forward_block", "offset_scope", "horizon_block", "tau"])
    recommendations = []
    for (case_id, region, fold), group in blocks.groupby(["case_id", "region", "fold"], sort=True):
        arm_stats = group.groupby("arm").agg(
            mean_delta_AQL=("delta_AQL_vs_raw", "mean"),
            worst_delta_AQL=("delta_AQL_vs_raw", "max"),
            mean_delta_coverage_mae=("delta_coverage_mae_vs_raw", "mean"),
            blocks_improved=("delta_AQL_vs_raw", lambda values: int((values < -1e-12).sum())),
        ).reset_index()
        eligible = arm_stats[
            arm_stats["arm"].ne("raw")
            & arm_stats["worst_delta_AQL"].lt(-1e-12)
            & arm_stats["mean_delta_coverage_mae"].le(args.coverage_harm_tolerance)
        ].sort_values(["mean_delta_AQL", "mean_delta_coverage_mae", "arm"])
        if eligible.empty:
            best_arm, disposition = "raw", "no_robust_no_refit_remedy"
            mean_delta = 0.0
        else:
            selected = eligible.iloc[0]
            best_arm = str(selected.arm)
            mean_delta = float(selected.mean_delta_AQL)
            disposition = "bounded_no_refit_mechanism_supported"
        recommendations.append({
            "case_id": case_id, "region": region, "fold": int(fold),
            "recommended_arm": best_arm, "mean_forward_delta_AQL": mean_delta,
            "disposition": disposition, "promotion_authorized": False,
            "reason_promotion_blocked": "forward_blocks_are_mechanism_diagnostics_not_a_frozen_selector",
            "test_opened": False,
        })
    recommendations = pd.DataFrame(recommendations).sort_values(["region", "fold"])
    rearranged = full[full["arm"].eq("rearranged")]
    raw = full[full["arm"].eq("raw")]
    gates = pd.DataFrame([
        {"gate": "exact_case_count", "passed": recommendations.shape[0] == args.expected_cases, "observed": recommendations.shape[0]},
        {"gate": "two_forward_blocks_per_case", "passed": blocks.groupby(["case_id", "arm"]).size().eq(2).all(), "observed": len(blocks)},
        {"gate": "rearrangement_never_increases_full_validation_AQL", "passed": (rearranged["delta_vs_raw"] <= 1e-10).all(), "observed": float(rearranged["delta_vs_raw"].max())},
        {"gate": "all_prediction_hashes_verified", "passed": True, "observed": args.expected_atoms},
        {"gate": "test_registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
        {"gate": "no_launch_or_yaml", "passed": True, "observed": "read_only"},
    ])
    if not gates["passed"].all():
        raise RuntimeError(f"R74 feasibility gates failed: {gates.loc[~gates.passed, 'gate'].tolist()}")

    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    full.to_csv(output / "pricefm_stage_r74_full_validation_rearrangement.csv", index=False)
    blocks.to_csv(output / "pricefm_stage_r74_forward_calibration_arm_metrics.csv", index=False)
    offsets.to_csv(output / "pricefm_stage_r74_forward_calibration_offsets.csv", index=False)
    recommendations.to_csv(output / "pricefm_stage_r74_case_mechanism_recommendations.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r74_feasibility_gates.csv", index=False)
    source_paths = [
        Path(__file__).resolve(), args.r69b_manifest.resolve(), atoms_path.resolve(),
        case_metrics_path.resolve(), (args.r73_dir / "summary.json").resolve(),
    ]
    source_paths.extend(Path(value) for value in atoms["prediction_path"])
    source_paths.extend(Path(value) for value in cases["adapter_dir"].map(lambda value: str(Path(value) / "rows_val.csv")))
    source_paths.extend(Path(value) for value in r73_metrics["scaler_path"])
    unique = list(dict.fromkeys(path.resolve() for path in source_paths))
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in unique
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_read_only_no_refit_feasibility_audit",
        "cases": int(len(recommendations)),
        "forward_evaluations": int(len(blocks)),
        "cases_with_robust_no_refit_remedy": int(recommendations["disposition"].eq("bounded_no_refit_mechanism_supported").sum()),
        "recommended_arm_counts": recommendations["recommended_arm"].value_counts().sort_index().to_dict(),
        "rearrangement_improved_full_validation_cases": int((rearranged["delta_vs_raw"] < -1e-12).sum()),
        "rearrangement_mean_delta_AQL": float(rearranged["delta_vs_raw"].mean()),
        "rearrangement_beats_operational_pricefm_cases": int(rearranged["beats_operational_pricefm"].sum()),
        "raw_beats_operational_pricefm_cases": int(raw["beats_operational_pricefm"].sum()),
        "promotion_candidates": 0,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "launch_yaml_written": False, "launch_authorized": False,
        "recommended_next_action": "repair_and_gate_large_n_structured_exal; use_r74_only_to_bound_future_postfit_work",
    }
    write_json(output / "summary.json", summary)
    report = f"""# PriceFM Stage-R74 No-Refit Feasibility Audit

R74 tested deterministic rowwise quantile rearrangement on the complete validation
surface and additive calibration in two strictly forward blocks. Calibration offsets
were learned from earlier origins and evaluated only on later origins.

Rearrangement improved full-validation AQL in
{summary['rearrangement_improved_full_validation_cases']}/{len(recommendations)} cases,
with mean delta {summary['rearrangement_mean_delta_AQL']:.6f}; it produced
{summary['rearrangement_beats_operational_pricefm_cases']} operational PriceFM wins.
Forward diagnostics support a stable no-refit mechanism in
{summary['cases_with_robust_no_refit_remedy']}/{len(recommendations)} cases.

These diagnostics do not define a frozen final selector and therefore authorize no
promotion. Test, registry, article, joint-model, MCMC, and launch actions remain
blocked. The next justified engineering action is the isolated large-n structured
exAL numerical repair and mechanism gate.
"""
    (output / "pricefm_stage_r74_feasibility_report.md").write_text(report)
    if list(output.rglob("*.yaml")) or list(output.rglob("*.yml")):
        raise RuntimeError("R74 must not write launch YAML")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
