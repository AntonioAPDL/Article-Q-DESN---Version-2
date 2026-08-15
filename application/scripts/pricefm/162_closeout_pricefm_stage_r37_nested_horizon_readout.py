#!/usr/bin/env python3
"""Close out PriceFM Stage-R36 with strict validation-only mechanism gates."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_PREP_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r36_nested_horizon_readout_launch_prep_20260804"
)
DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r36_nested_horizon_readout_20260804"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r36_nested_horizon_readout_20260804"
)
DEFAULT_R34_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r34_lean_capacity_history_closeout_20260728"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r37_nested_horizon_readout_closeout_20260805"
)

MANIFEST = "pricefm_stage_r36_launch_manifest.csv"
PROTOCOL = "pricefm_stage_r36_selection_protocol.csv"
R34_SELECTED = "pricefm_stage_r34_validation_selected_cases.csv"
SHARED = "qdesn_al_rhs_ns_exact_chunked"
SEPARATE = f"{SHARED}_horizon_separate"

OUT_COMPLETION = "pricefm_stage_r37_completion_audit.csv"
OUT_INNER = "pricefm_stage_r37_inner_fold_metrics.csv"
OUT_CASES = "pricefm_stage_r37_case_closeout.csv"
OUT_HORIZONS = "pricefm_stage_r37_outer_horizon_diagnostics.csv"
OUT_FAILURES = "pricefm_stage_r37_convergence_failures.csv"
OUT_SENSITIVITY = "pricefm_stage_r37_harm_tolerance_sensitivity.csv"
OUT_QUEUE = "pricefm_stage_r37_full_quantile_confirmation_queue.csv"
OUT_GATES = "pricefm_stage_r37_decision_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r37_nested_horizon_readout_closeout_report.md"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r36-prep-dir", default=DEFAULT_PREP_DIR)
    p.add_argument("--grid-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--stage-r34-dir", default=DEFAULT_R34_DIR)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-cases", type=int, default=11)
    p.add_argument("--expected-harm-guards", type=int, default=2)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def boolish(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "completed"}


def read_csv(path: Path, label: str) -> pd.DataFrame:
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {path}")
    return pd.read_csv(path, low_memory=False)


def require_columns(frame: pd.DataFrame, columns: list[str], label: str) -> None:
    missing = [column for column in columns if column not in frame.columns]
    if missing:
        raise ValueError(f"{label} missing required columns: {missing}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def model_dir(run_root: Path, experiment_id: str, region: str, fold: int) -> Path:
    return run_root / experiment_id / "cells" / f"region={region}" / f"fold={fold}" / "model"


def completion_audit(
    manifest: pd.DataFrame, status: pd.DataFrame, run_root: Path, expected_cases: int
) -> tuple[pd.DataFrame, bool]:
    experiment_status = status[status["kind"].astype(str).eq("experiment")].copy()
    experiment_status["return_code"] = pd.to_numeric(experiment_status["return_code"], errors="coerce")
    completed = (
        experiment_status["status"].astype(str).str.lower().eq("completed")
        & experiment_status["return_code"].eq(0)
    )
    expected_ids = set(manifest["experiment_id"].astype(str))
    status_ids = set(experiment_status["id"].astype(str))
    artifact_checks = []
    for row in manifest.itertuples(index=False):
        directory = model_dir(run_root, str(row.experiment_id), str(row.region), int(row.fold))
        artifact_checks.append(
            all((directory / name).exists() and (directory / name).stat().st_size > 0 for name in [
                "nested_validation_metrics.csv",
                "metric_summary.csv",
                "metric_by_horizon_group.csv",
                "model_method_summary.csv",
            ])
        )
    checks = [
        ("manifest_cases", len(manifest), expected_cases, len(manifest) == expected_cases),
        ("manifest_unique_ids", manifest["experiment_id"].nunique(), expected_cases, manifest["experiment_id"].nunique() == expected_cases),
        ("launch_status_ids", len(status_ids), expected_cases, status_ids == expected_ids),
        ("launch_completed_zero", int(completed.sum()), expected_cases, len(completed) == expected_cases and completed.all()),
        ("complete_artifact_sets", sum(artifact_checks), expected_cases, all(artifact_checks)),
    ]
    audit = pd.DataFrame([
        {"check": name, "observed": observed, "expected": expected, "passed": passed}
        for name, observed, expected, passed in checks
    ])
    return audit, bool(audit["passed"].map(boolish).all())


def parse_artifacts(manifest: pd.DataFrame, run_root: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    inner_rows: list[dict[str, Any]] = []
    horizon_rows: list[dict[str, Any]] = []
    outer_rows: list[dict[str, Any]] = []
    for source in manifest.to_dict("records"):
        directory = model_dir(run_root, str(source["experiment_id"]), str(source["region"]), int(source["fold"]))
        inner = read_csv(directory / "nested_validation_metrics.csv", "nested metrics")
        require_columns(inner, ["inner_fold", "method_id", "readout_mode", "converged", "AQL_scaled"], str(directory))
        if set(inner["method_id"].astype(str)) != {SHARED, SEPARATE} or len(inner) != 6:
            raise ValueError(f"Unexpected R36 inner metric surface: {directory}")
        for row in inner.to_dict("records"):
            inner_rows.append({**source, **row, "source_path": str(directory / "nested_validation_metrics.csv")})

        metrics = read_csv(directory / "metric_summary.csv", "outer metrics")
        require_columns(metrics, ["method_id", "split", "unit", "AQL"], str(directory))
        if set(metrics["split"].astype(str)) != {"val"}:
            raise ValueError(f"R36 test quarantine violated by metric summary: {directory}")
        selected_metrics = metrics[
            metrics["method_id"].astype(str).isin([SHARED, SEPARATE])
            & metrics["unit"].astype(str).eq("original")
        ]
        if len(selected_metrics) != 2:
            raise ValueError(f"Expected paired outer validation metrics: {directory}")
        for row in selected_metrics.to_dict("records"):
            outer_rows.append({**source, **row, "source_path": str(directory / "metric_summary.csv")})

        horizons = read_csv(directory / "metric_by_horizon_group.csv", "horizon metrics")
        require_columns(horizons, ["method_id", "split", "unit", "horizon_group", "AQL"], str(directory))
        if set(horizons["split"].astype(str)) != {"val"}:
            raise ValueError(f"R36 test quarantine violated by horizon metrics: {directory}")
        horizons = horizons[
            horizons["method_id"].astype(str).isin([SHARED, SEPARATE])
            & horizons["unit"].astype(str).eq("original")
        ]
        for row in horizons.to_dict("records"):
            horizon_rows.append({**source, **row, "source_path": str(directory / "metric_by_horizon_group.csv")})
    return pd.DataFrame(inner_rows), pd.DataFrame(outer_rows), pd.DataFrame(horizon_rows)


def closeout_cases(
    manifest: pd.DataFrame, inner: pd.DataFrame, outer: pd.DataFrame, r34: pd.DataFrame
) -> pd.DataFrame:
    anchors = r34.set_index(["region", "fold"])
    rows: list[dict[str, Any]] = []
    for source in manifest.to_dict("records"):
        region, fold = str(source["region"]), int(source["fold"])
        group = inner[(inner["region"].astype(str) == region) & (inner["fold"].astype(int) == fold)].copy()
        paired = outer[(outer["region"].astype(str) == region) & (outer["fold"].astype(int) == fold)]
        stats: dict[str, dict[str, float | bool]] = {}
        for method in [SHARED, SEPARATE]:
            values = pd.to_numeric(group.loc[group["method_id"].astype(str).eq(method), "AQL_scaled"])
            stats[method] = {
                "median": float(values.median()),
                "worst": float(values.max()),
                "all_converged": bool(group.loc[group["method_id"].astype(str).eq(method), "converged"].map(boolish).all()),
            }
        inner_delta = float(stats[SEPARATE]["median"]) - float(stats[SHARED]["median"])
        worst_delta = float(stats[SEPARATE]["worst"]) - float(stats[SHARED]["worst"])
        median_selects_separate = inner_delta < 0
        strict_harm_pass = worst_delta <= 0
        convergence_pass = bool(stats[SEPARATE]["all_converged"])
        selected = SEPARATE if median_selects_separate else SHARED
        outer_map = paired.set_index("method_id")["AQL"].astype(float).to_dict()
        frozen_outer = float(outer_map[selected])
        anchor = float(anchors.loc[(region, fold), "val_AQL"])
        outer_improves_shared = frozen_outer < float(outer_map[SHARED])
        outer_improves_r34 = frozen_outer < anchor
        eligible = bool(
            selected == SEPARATE
            and convergence_pass
            and strict_harm_pass
            and outer_improves_shared
            and outer_improves_r34
        )
        if eligible:
            decision = "eligible_for_fresh_full_quantile_confirmation"
        elif not convergence_pass and selected == SEPARATE:
            decision = "blocked_inner_nonconvergence"
        elif selected != SEPARATE:
            decision = "retain_shared_readout"
        elif not strict_harm_pass:
            decision = "blocked_strict_worst_fold_harm"
        elif not outer_improves_shared:
            decision = "blocked_no_outer_paired_improvement"
        else:
            decision = "blocked_no_r34_anchor_improvement"
        rows.append({
            **source,
            "shared_inner_median_AQL_scaled": stats[SHARED]["median"],
            "separate_inner_median_AQL_scaled": stats[SEPARATE]["median"],
            "separate_minus_shared_inner_median": inner_delta,
            "shared_inner_worst_AQL_scaled": stats[SHARED]["worst"],
            "separate_inner_worst_AQL_scaled": stats[SEPARATE]["worst"],
            "separate_minus_shared_inner_worst": worst_delta,
            "separate_all_inner_folds_converged": convergence_pass,
            "strict_zero_harm_gate_passed": strict_harm_pass,
            "inner_selected_method": selected,
            "shared_outer_val_AQL": float(outer_map[SHARED]),
            "separate_outer_val_AQL": float(outer_map[SEPARATE]),
            "frozen_outer_val_AQL": frozen_outer,
            "frozen_minus_shared_outer_val": frozen_outer - float(outer_map[SHARED]),
            "r34_anchor_val_AQL": anchor,
            "frozen_minus_r34_anchor_val": frozen_outer - anchor,
            "outer_improves_paired_shared": outer_improves_shared,
            "outer_improves_r34_anchor": outer_improves_r34,
            "full_quantile_confirmation_eligible": eligible,
            "decision": decision,
            "test_inspected": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "mcmc_authorized": False,
        })
    return pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True)


def tolerance_sensitivity(cases: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for tolerance in [0.0, 0.00025, 0.001]:
        for row in cases.to_dict("records"):
            passes = float(row["separate_minus_shared_inner_worst"]) <= tolerance
            rows.append({
                "region": row["region"],
                "fold": row["fold"],
                "diagnostic_tolerance_scaled_AQL": tolerance,
                "worst_fold_harm_passed": passes,
                "authoritative_for_decision": tolerance == 0.0,
                "role": "strict_pre_registered_interpretation" if tolerance == 0.0 else "diagnostic_only_posthoc_sensitivity",
            })
    return pd.DataFrame(rows)


def decision_gates(complete: bool, cases: pd.DataFrame, queue: pd.DataFrame) -> pd.DataFrame:
    no_test = bool(not cases["test_inspected"].map(boolish).any())
    rows = [
        ("r36_complete", complete, "All 11 paired mechanism experiments completed with required artifacts."),
        ("selection_is_case_specific", True, "Readout selection is independent within region/fold."),
        ("selection_uses_inner_validation_only", True, "Median inner-fold scaled AQL selects the readout."),
        ("strict_worst_fold_harm_guard", True, "No nonzero tolerance was pre-registered; authoritative tolerance is zero."),
        ("nonconverged_separate_fits_blocked", True, "Any selected separate arm with inner nonconvergence is ineligible."),
        ("outer_validation_is_qualification_only", True, "Outer validation audits transfer after inner selection."),
        ("test_quarantined", no_test, "No existing test metric is loaded or used by R37."),
        ("fresh_full_quantile_candidate_exists", len(queue) > 0, "Candidate must pass convergence, strict harm, paired outer, and R34-anchor gates."),
        ("full_quantile_launch_authorized", False, "R37 is read-only; a fresh confirmation design requires explicit authorization."),
        ("mcmc_authorized", False, "MCMC remains blocked until full-quantile and dual-reference confirmation."),
        ("registry_mutation_authorized", False, "Registry mutation remains blocked."),
        ("article_mutation_authorized", False, "Article mutation remains blocked."),
    ]
    return pd.DataFrame([{"gate": gate, "passed": passed, "detail": detail} for gate, passed, detail in rows])


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in sorted(set(paths)):
        if path.exists() and path.is_file():
            rows.append({"path": str(path), "sha256": sha256_file(path), "bytes": path.stat().st_size})
    return pd.DataFrame(rows, columns=["path", "sha256", "bytes"])


def render_report(summary: dict[str, Any], cases: pd.DataFrame) -> str:
    lines = [
        "# PriceFM Stage-R37 Nested Horizon-Readout Closeout", "",
        f"- R36 complete: `{summary['r36_complete']}`",
        f"- Cases: `{summary['cases']}`",
        f"- Inner-median separate selections: `{summary['inner_separate_selections']}`",
        f"- Fully converged separate surfaces: `{summary['fully_converged_cases']}`",
        f"- Frozen choices improving paired outer shared: `{summary['outer_paired_improvements']}`",
        f"- Frozen choices improving R34 validation anchor: `{summary['r34_anchor_improvements']}`",
        f"- Fresh full-quantile confirmation candidates: `{summary['full_quantile_candidates']}`", "",
        "## Authoritative decision", "",
        "R36 pre-registered a worst-fold harm guard but no positive tolerance. R37 therefore",
        "uses zero as the authoritative tolerance. Positive tolerances are emitted only as",
        "post hoc sensitivity diagnostics and cannot create a confirmation candidate.", "",
        "| Case | Inner choice | Worst-fold delta | Outer vs shared | Outer vs R34 | Decision |",
        "|---|---|---:|---:|---:|---|",
    ]
    for row in cases.to_dict("records"):
        lines.append(
            f"| {row['region']} f{int(row['fold'])} | {row['inner_selected_method']} | "
            f"{row['separate_minus_shared_inner_worst']:+.6f} | "
            f"{row['frozen_minus_shared_outer_val']:+.4f} | "
            f"{row['frozen_minus_r34_anchor_val']:+.4f} | {row['decision']} |"
        )
    lines += ["", "Test, registry, article, full-quantile launch, and MCMC actions remain blocked.", ""]
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    prep = repo_path(args.stage_r36_prep_dir)
    grid = repo_path(args.grid_root)
    run_root = repo_path(args.run_root)
    r34_dir = repo_path(args.stage_r34_dir)
    manifest = read_csv(prep / MANIFEST, "R36 manifest")
    protocol = read_csv(prep / PROTOCOL, "R36 selection protocol")
    status = read_csv(grid / "launch_status.csv", "R36 launch status")
    r34 = read_csv(r34_dir / R34_SELECTED, "R34 selected cases")
    require_columns(manifest, ["experiment_id", "region", "fold", "protect_current_qdesn", "selection_rule"], "R36 manifest")
    require_columns(protocol, ["gate", "rule"], "R36 selection protocol")
    require_columns(status, ["id", "kind", "status", "return_code"], "R36 status")
    require_columns(r34, ["region", "fold", "val_AQL"], "R34 selected cases")
    if len(manifest) != int(args.expected_cases):
        raise ValueError(f"Expected {args.expected_cases} R36 cases, found {len(manifest)}")
    if int(manifest["protect_current_qdesn"].map(boolish).sum()) != int(args.expected_harm_guards):
        raise ValueError("Unexpected R36 harm-guard count")
    if not manifest["selection_rule"].astype(str).eq("nested_temporal_validation_AQL_only_within_case").all():
        raise ValueError("R36 selection contract changed")
    protocol_rules = dict(zip(protocol["gate"].astype(str), protocol["rule"].astype(str)))
    if "median inner-fold scaled AQL" not in protocol_rules.get("inner_selection", ""):
        raise ValueError("R36 inner-selection protocol changed")
    if "worst inner fold" not in protocol_rules.get("stability", ""):
        raise ValueError("R36 worst-fold harm protocol changed")

    audit, complete = completion_audit(manifest, status, run_root, int(args.expected_cases))
    if not complete:
        raise RuntimeError("R36 is incomplete; refusing to materialize R37 decisions")
    inner, outer, horizons = parse_artifacts(manifest, run_root)
    cases = closeout_cases(manifest, inner, outer, r34)
    failures = inner[~inner["converged"].map(boolish)].copy()
    sensitivity = tolerance_sensitivity(cases)
    queue = cases[cases["full_quantile_confirmation_eligible"].map(boolish)].copy()
    if not queue.empty:
        queue["next_stage"] = "fresh_full_quantile_validation_only_confirmation_design"
        queue["launch_authorized"] = False
        queue["test_role"] = "audit_only_after_frozen_full_quantile_selection"
    gates = decision_gates(complete, cases, queue)

    output = repo_path(args.output_dir)
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"R37 output exists; use --force true to replace files: {output}")
    output.mkdir(parents=True, exist_ok=True)
    sources = source_manifest(
        [Path(__file__).resolve(), prep / MANIFEST, prep / PROTOCOL, prep / "summary.json", grid / "launch_status.csv", grid / "launch_summary.json", r34_dir / R34_SELECTED]
        + [Path(p) for p in inner["source_path"].unique()]
        + [Path(p) for p in outer["source_path"].unique()]
        + [Path(p) for p in horizons["source_path"].unique()]
    )
    summary = {
        "status": "completed_read_only_no_confirmation_candidates" if queue.empty else "completed_read_only_confirmation_candidates_exist",
        "r36_complete": complete,
        "cases": int(len(cases)),
        "experiments_completed": int(len(manifest)),
        "experiments_remaining": 0,
        "inner_metric_rows": int(len(inner)),
        "inner_separate_selections": int(cases["inner_selected_method"].eq(SEPARATE).sum()),
        "fully_converged_cases": int(cases["separate_all_inner_folds_converged"].map(boolish).sum()),
        "outer_paired_improvements": int(cases["outer_improves_paired_shared"].map(boolish).sum()),
        "r34_anchor_improvements": int(cases["outer_improves_r34_anchor"].map(boolish).sum()),
        "full_quantile_candidates": int(len(queue)),
        "authoritative_harm_tolerance_scaled_AQL": 0.0,
        "test_inspected": False,
        "full_quantile_launch_authorized": False,
        "mcmc_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    for name, frame in [
        (OUT_COMPLETION, audit), (OUT_INNER, inner), (OUT_CASES, cases),
        (OUT_HORIZONS, horizons), (OUT_FAILURES, failures),
        (OUT_SENSITIVITY, sensitivity), (OUT_QUEUE, queue), (OUT_GATES, gates),
        (OUT_SOURCE, sources),
    ]:
        frame.to_csv(output / name, index=False)
    write_json(output / OUT_SUMMARY, summary)
    (output / OUT_REPORT).write_text(render_report(summary, cases))
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
