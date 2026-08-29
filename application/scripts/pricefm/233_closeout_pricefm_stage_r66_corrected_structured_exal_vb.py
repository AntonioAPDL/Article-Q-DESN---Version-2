#!/usr/bin/env python3
"""Close out R66 with validation-only whole-bundle selection."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, write_json
from pricefm_metrics import average_quantile_loss


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r66_corrected_structured_exal_vb_20260829"
GRID = DATA / "experiment_grids" / TAG
MANIFEST = GRID / "case_manifest.csv"
COMPONENTS = GRID / "component_ledger.csv"
STATUS = GRID / "launch_status.csv"
GATE = GRID / "production_gate.json"
OUTPUT = DATA / "authoritative/pricefm_stage_r66_corrected_structured_exal_vb_closeout_20260829"
METHOD_AL = "qdesn_al_rhs_ns_exact_chunked_r66_parity"
METHOD_EXAL = "qdesn_exal_rhs_ns_exact_chunked_structured_corrected_r66"
TAUS = np.array([0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90])


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--component-ledger", type=Path, default=COMPONENTS)
    p.add_argument("--launch-status", type=Path, default=STATUS)
    p.add_argument("--production-gate", type=Path, default=GATE)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--parity-relative-tolerance", type=float, default=1e-6)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def boolish(value) -> bool:
    return str(value).lower() in {"1", "true", "yes", "y"}


def pava(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    means: list[float] = []
    weights: list[int] = []
    starts: list[int] = []
    ends: list[int] = []
    for index, value in enumerate(values):
        means.append(float(value)); weights.append(1); starts.append(index); ends.append(index + 1)
        while len(means) >= 2 and means[-2] > means[-1]:
            total = weights[-2] + weights[-1]
            merged = (means[-2] * weights[-2] + means[-1] * weights[-1]) / total
            means[-2:] = [merged]
            weights[-2:] = [total]
            starts[-2:] = [starts[-2]]
            ends[-2:] = [ends[-1]]
    out = np.empty_like(values)
    for mean, start, end in zip(means, starts, ends):
        out[start:end] = mean
    return out


def prediction_surface(model: Path, adapter: Path, method: str) -> tuple[np.ndarray, np.ndarray]:
    pred = pd.read_csv(model / "model_predictions_scaled.csv")
    pred = pred[pred.method_id.astype(str).eq(method) & pred.split.astype(str).eq("val")]
    wide = pred.pivot(index=["origin_id", "horizon"], columns="tau", values="pred_scaled")
    wide = wide.reindex(columns=TAUS)
    truth = pd.read_csv(adapter / "rows_val.csv").set_index(["origin_id", "horizon"])
    truth = truth.reindex(wide.index)
    if wide.isna().any().any() or truth.y_scaled.isna().any():
        raise RuntimeError(f"Incomplete validation prediction surface for {model} / {method}")
    return truth.y_scaled.to_numpy(float), wide.to_numpy(float)


def metric_value(metric: pd.DataFrame, method: str, unit: str) -> float:
    selected = metric[
        metric.method_id.astype(str).eq(method)
        & metric.split.astype(str).eq("val")
        & metric.unit.astype(str).eq(unit)
    ]
    if len(selected) != 1:
        raise RuntimeError(f"Missing validation metric for {method} / {unit}")
    return float(selected.iloc[0].AQL)


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = pd.read_csv(args.manifest)
    components = pd.read_csv(args.component_ledger)
    status = pd.read_csv(args.launch_status)
    production_gate = json.loads(args.production_gate.read_text())
    if len(manifest) != args.expected_cases or len(components) != args.expected_cases * 7:
        raise RuntimeError("R66 manifest/component coverage is incomplete")
    if status.case_id.nunique() != args.expected_cases or status.status.isin(["failed", "launcher_exception"]).any():
        raise RuntimeError("R66 launch has not completed cleanly")
    if production_gate.get("status") != "production_gate_passed" or not production_gate.get("passed"):
        raise RuntimeError("R66 real-case production gate did not pass")

    case_rows = []
    parity_rows = []
    synthesis_rows = []
    source_rows = []
    for row in manifest.sort_values(["region", "fold"]).itertuples(index=False):
        model = Path(row.output_dir)
        adapter = Path(row.adapter_dir)
        required = [
            model / "metric_summary.csv",
            model / "model_predictions_scaled.csv",
            model / "r66_component_status.csv",
            model / "r66_case_fit_summary.json",
            model / "checkpoint_provenance.csv",
            model / "run_manifest.json",
        ]
        if not all(path.is_file() for path in required):
            raise RuntimeError(f"R66 case is incomplete: {row.case_id}")
        metric = pd.read_csv(model / "metric_summary.csv")
        predictions = pd.read_csv(model / "model_predictions_scaled.csv", usecols=["split"])
        if set(predictions.split.astype(str)) != {"val"}:
            raise RuntimeError(f"R66 test firewall violation in predictions: {row.case_id}")
        if any((adapter / name).exists() for name in ("X_test.csv", "y_test.csv", "rows_test.csv")):
            raise RuntimeError(f"R66 test firewall violation in adapter: {row.case_id}")
        component_status = pd.read_csv(model / "r66_component_status.csv")
        convergence_pass = (
            len(component_status) == 7
            and component_status.selection_eligible.map(boolish).all()
            and component_status.structured_telemetry_pass.map(boolish).all()
            and component_status.exact_conditional_gig_moment_pass.map(boolish).all()
            and component_status.continuation_start_pass.map(boolish).all()
            and not component_status.optimizer_used_fallback.map(boolish).any()
            and component_status.exact_commit_count.astype(int).ge(5).all()
            and component_status.gamma_relative_boundary_margin.astype(float).ge(1e-6).all()
        )
        new_al = metric_value(metric, METHOD_AL, "original")
        new_exal = metric_value(metric, METHOD_EXAL, "original")
        new_al_scaled = metric_value(metric, METHOD_AL, "scaled")
        new_exal_scaled = metric_value(metric, METHOD_EXAL, "scaled")
        scale_al = new_al / new_al_scaled
        scale_exal = new_exal / new_exal_scaled

        case_components = components[components.case_id.astype(str).eq(str(row.case_id))].sort_values("tau")
        y_al, pred_al = prediction_surface(model, adapter, METHOD_AL)
        y_exal, pred_exal = prediction_surface(model, adapter, METHOD_EXAL)
        if not np.array_equal(y_al, y_exal):
            raise RuntimeError(f"AL/exAL validation truth mismatch for {row.case_id}")
        for index, component in enumerate(case_components.itertuples(index=False)):
            tau = float(component.tau)
            loss = np.maximum(tau * (y_al - pred_al[:, index]), (tau - 1) * (y_al - pred_al[:, index])).mean()
            current = float(component.legacy_al_validation_AQL)
            observed = float(loss * scale_al)
            tolerance = args.parity_relative_tolerance * max(1.0, abs(current))
            parity_rows.append({
                "case_id": row.case_id,
                "region": row.region,
                "fold": int(row.fold),
                "tau": tau,
                "legacy_al_validation_AQL": current,
                "new_al_parity_validation_AQL": observed,
                "absolute_delta": observed - current,
                "tolerance": tolerance,
                "parity_pass": abs(observed - current) <= tolerance,
            })

        pava_al = np.vstack([pava(values) for values in pred_al])
        pava_exal = np.vstack([pava(values) for values in pred_exal])
        crossing_al = int((np.diff(pred_al, axis=1) < 0).sum())
        crossing_exal = int((np.diff(pred_exal, axis=1) < 0).sum())
        pava_al_aql = average_quantile_loss(y_al, pava_al, TAUS) * scale_al
        pava_exal_aql = average_quantile_loss(y_exal, pava_exal, TAUS) * scale_exal
        synthesis_rows.extend([
            {
                "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
                "family": "al_parity", "raw_validation_AQL": new_al,
                "pava_validation_AQL": pava_al_aql, "crossing_pairs": crossing_al,
                "mean_abs_pava_adjustment_scaled": float(np.abs(pava_al - pred_al).mean()),
                "selection_role": "diagnostic_only_raw_AQL_is_primary",
            },
            {
                "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
                "family": "corrected_structured_exal", "raw_validation_AQL": new_exal,
                "pava_validation_AQL": pava_exal_aql, "crossing_pairs": crossing_exal,
                "mean_abs_pava_adjustment_scaled": float(np.abs(pava_exal - pred_exal).mean()),
                "selection_role": "diagnostic_only_raw_AQL_is_primary",
            },
        ])

        bundle_tol = args.parity_relative_tolerance * max(1.0, abs(float(row.legacy_al_validation_AQL)))
        component_parity = all(item["parity_pass"] for item in parity_rows if item["case_id"] == row.case_id)
        bundle_parity = abs(new_al - float(row.legacy_al_validation_AQL)) <= bundle_tol
        parity_pass = component_parity and bundle_parity
        legacy_selected = str(row.legacy_selected_family)
        legacy_selected_aql = float(row.legacy_selected_validation_AQL)
        selection_tol = args.parity_relative_tolerance * max(1.0, abs(legacy_selected_aql))
        structured_improves = new_exal < legacy_selected_aql - selection_tol
        structured_eligible = convergence_pass and parity_pass and structured_improves
        selected_family = "corrected_structured_exal" if structured_eligible else f"legacy_{legacy_selected}"
        selected_aql = new_exal if structured_eligible else legacy_selected_aql
        blocked_reason = ""
        if not convergence_pass:
            blocked_reason = "component_convergence_or_structured_telemetry_failed"
        elif not parity_pass:
            blocked_reason = "al_parity_failed"
        elif not structured_improves:
            blocked_reason = "structured_exal_did_not_beat_current_authority_beyond_tolerance"
        case_rows.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "legacy_selected_family": legacy_selected,
            "legacy_al_validation_AQL": float(row.legacy_al_validation_AQL),
            "legacy_exal_validation_AQL": float(row.legacy_exal_validation_AQL),
            "new_al_parity_validation_AQL": new_al,
            "new_corrected_structured_exal_validation_AQL": new_exal,
            "al_parity_pass": parity_pass,
            "convergence_and_telemetry_pass": convergence_pass,
            "structured_exal_improves_beyond_tolerance": structured_improves,
            "selected_family": selected_family,
            "selected_validation_AQL": selected_aql,
            "validation_gain_vs_r62": legacy_selected_aql - selected_aql,
            "validation_relative_gain_vs_r62": (legacy_selected_aql - selected_aql) / legacy_selected_aql,
            "decision": "freeze_corrected_structured_exal_validation_winner" if structured_eligible else "retain_r62_authority",
            "blocked_reason": blocked_reason,
            "selection_split": "val",
            "test_opened": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        })
        source_rows.extend({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size} for path in required)

    decisions = pd.DataFrame(case_rows)
    parity = pd.DataFrame(parity_rows)
    synthesis = pd.DataFrame(synthesis_rows)
    queue = decisions[decisions.decision.eq("freeze_corrected_structured_exal_validation_winner")].copy()
    decisions.to_csv(output / "pricefm_stage_r66_case_decisions.csv", index=False)
    parity.to_csv(output / "pricefm_stage_r66_al_parity_components.csv", index=False)
    synthesis.to_csv(output / "pricefm_stage_r66_family_synthesis_diagnostics.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r66_frozen_test_audit_queue.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "all_case_jobs_completed", "passed": len(decisions) == args.expected_cases, "observed": len(decisions)},
        {"gate": "all_components_accounted", "passed": len(parity) == args.expected_cases * 7, "observed": len(parity)},
        {"gate": "test_remained_sealed", "passed": decisions.test_opened.eq(False).all(), "observed": "sealed"},
        {"gate": "whole_bundle_selection", "passed": decisions.selected_family.notna().all(), "observed": "one family per region/fold"},
        {"gate": "real_case_production_gate_passed", "passed": bool(production_gate.get("passed")), "observed": production_gate.get("status")},
        {"gate": "registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R66 closeout gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r66_closeout_gates.csv", index=False)
    fixed = [args.manifest.resolve(), args.component_ledger.resolve(), args.launch_status.resolve(), args.production_gate.resolve(), Path(__file__).resolve()]
    source_rows.extend({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size} for path in fixed)
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).sort_values("path").to_csv(
        output / "source_manifest.csv", index=False
    )
    summary = {
        "status": "completed_validation_only_r66_closeout",
        "cases": len(decisions),
        "al_parity_cases": int(decisions.al_parity_pass.sum()),
        "convergence_and_telemetry_cases": int(decisions.convergence_and_telemetry_pass.sum()),
        "structured_exal_validation_winners": len(queue),
        "retained_r62_authority_cases": int(decisions.decision.eq("retain_r62_authority").sum()),
        "test_opened": False,
        "test_audit_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r66_closeout_report.md").write_text(
        "# PriceFM Stage-R66 validation-only closeout\n\n"
        f"R66 closed {len(decisions)} independent seven-quantile region/fold cases. "
        f"Structured exAL displaced the frozen R62 authority in {len(queue)} cases after convergence, telemetry, "
        "and AL-parity gates. Test remained sealed; registry, article, joint-model, and MCMC actions remain blocked.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
