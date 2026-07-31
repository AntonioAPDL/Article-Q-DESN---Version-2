#!/usr/bin/env python3
"""Close out PriceFM Stage-R33 with validation-only case selection."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_MANIFEST = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r33_lean_capacity_history_launch_prep_20260722/"
    "pricefm_stage_r33_launch_manifest.csv"
)
DEFAULT_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r33_lean_capacity_history_20260722"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r33_lean_capacity_history_20260722"
)
DEFAULT_LOG_ROOT = "application/data_local/pricefm/logs"
DEFAULT_RUN_TAG = "pricefm_stage_r33_lean_capacity_history_20260722"
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r34_lean_capacity_history_closeout_20260728"
)

OUT_COMPLETION = "pricefm_stage_r34_completion_audit.csv"
OUT_METRICS = "pricefm_stage_r34_metric_rows.csv"
OUT_SELECTED = "pricefm_stage_r34_validation_selected_cases.csv"
OUT_ORACLE = "pricefm_stage_r34_test_oracle_diagnostics.csv"
OUT_PROMOTION = "pricefm_stage_r34_full_quantile_promotion_queue.csv"
OUT_MCMC = "pricefm_stage_r34_mcmc_confirmation_queue.csv"
OUT_CASES = "pricefm_stage_r34_case_outcomes.csv"
OUT_GATES = "pricefm_stage_r34_decision_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r34_closeout_report.md"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", default=DEFAULT_MANIFEST)
    p.add_argument("--grid-root", default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--log-root", default=DEFAULT_LOG_ROOT)
    p.add_argument("--run-tag", default=DEFAULT_RUN_TAG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-experiments", type=int, default=480)
    p.add_argument("--expected-cases", type=int, default=20)
    p.add_argument("--health-only", type=parse_bool, default=False)
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
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed", "completed"}


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


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


def write_frame(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def exit_code(log_root: str | Path, run_tag: str) -> int | None:
    path = repo_path(log_root) / f"{run_tag}.exit"
    if not path.exists():
        return None
    text = path.read_text().strip()
    try:
        return int(text)
    except ValueError:
        return None


def launch_status(grid_root: str | Path) -> pd.DataFrame:
    path = repo_path(grid_root) / "launch_status.csv"
    if not path.exists():
        return pd.DataFrame(columns=["kind", "status", "return_code"])
    frame = pd.read_csv(path, low_memory=False)
    require_columns(frame, ["kind", "status", "return_code"], "Stage-R33 launch status")
    return frame


def metric_paths(run_root: str | Path) -> list[Path]:
    root = repo_path(run_root)
    return sorted(root.glob("*/cells/*/*/model/metric_summary.csv")) if root.exists() else []


def parse_metric_rows(manifest: pd.DataFrame, run_root: str | Path) -> pd.DataFrame:
    by_id = manifest.set_index("experiment_id", drop=False)
    rows: list[dict[str, Any]] = []
    root = repo_path(run_root)
    for path in metric_paths(root):
        experiment_id = path.relative_to(root).parts[0]
        if experiment_id not in by_id.index:
            raise ValueError(f"Metric artifact has no Stage-R33 manifest row: {experiment_id}")
        source = by_id.loc[experiment_id]
        metrics = pd.read_csv(path, low_memory=False)
        require_columns(metrics, ["method_id", "split", "unit", "AQL"], str(path))
        metrics = metrics[
            metrics["unit"].astype(str).eq("original")
            & metrics["method_id"].astype(str).str.startswith("qdesn_")
            & metrics["split"].astype(str).isin(["val", "test"])
        ].copy()
        for method_id, group in metrics.groupby("method_id"):
            split = group.set_index("split")
            if "val" not in split.index or "test" not in split.index:
                continue
            val_aql = float(split.loc["val", "AQL"])
            test_aql = float(split.loc["test", "AQL"])
            current_qdesn = float(source["current_qdesn_AQL"])
            current_pricefm = float(source["current_pricefm_AQL"])
            rows.append(
                {
                    **source.to_dict(),
                    "method_id": str(method_id),
                    "val_AQL": val_aql,
                    "test_AQL": test_aql,
                    "test_minus_current_qdesn": test_aql - current_qdesn,
                    "test_minus_pricefm": test_aql - current_pricefm,
                    "beats_current_qdesn_on_test": test_aql < current_qdesn,
                    "beats_pricefm_on_test": test_aql < current_pricefm,
                    "beats_both_on_test": test_aql < current_qdesn and test_aql < current_pricefm,
                    "metric_summary_path": str(path),
                    "metric_summary_sha256": sha256_file(path),
                }
            )
    return pd.DataFrame(rows)


def completion_audit(
    manifest: pd.DataFrame,
    metrics: pd.DataFrame,
    args: argparse.Namespace,
) -> tuple[pd.DataFrame, bool, dict[str, Any]]:
    paths = metric_paths(args.run_root)
    completed_ids = {p.relative_to(repo_path(args.run_root)).parts[0] for p in paths}
    run_dirs = {
        p.name
        for p in repo_path(args.run_root).iterdir()
        if p.is_dir()
    } if repo_path(args.run_root).exists() else set()
    status = launch_status(args.grid_root)
    experiment_status = status[status["kind"].astype(str).eq("experiment")].copy()
    status_ok = (
        not experiment_status.empty
        and experiment_status["status"].astype(str).str.lower().eq("completed").all()
        and pd.to_numeric(experiment_status["return_code"], errors="coerce").eq(0).all()
    )
    n_cases = int(manifest[["region", "fold"]].drop_duplicates().shape[0])
    metric_method_rows = int(metrics.shape[0])
    expected_method_rows = int(args.expected_experiments) * 2
    code = exit_code(args.log_root, args.run_tag)
    checks = [
        ("manifest_experiments", len(manifest), args.expected_experiments, len(manifest) == args.expected_experiments),
        ("manifest_cases", n_cases, args.expected_cases, n_cases == args.expected_cases),
        ("run_directories", len(run_dirs), args.expected_experiments, len(run_dirs) == args.expected_experiments),
        ("metric_summaries", len(paths), args.expected_experiments, len(paths) == args.expected_experiments),
        ("metric_method_rows", metric_method_rows, expected_method_rows, metric_method_rows == expected_method_rows),
        ("launch_experiment_rows", len(experiment_status), args.expected_experiments, len(experiment_status) == args.expected_experiments),
        ("launch_experiments_completed_zero", bool(status_ok), True, bool(status_ok)),
        ("launcher_exit_code", code if code is not None else "", 0, code == 0),
        ("manifest_ids_have_metrics", len(completed_ids & set(manifest["experiment_id"])), args.expected_experiments,
         completed_ids == set(manifest["experiment_id"])),
    ]
    audit = pd.DataFrame(
        [
            {"check": check, "observed": observed, "expected": expected, "passed": passed}
            for check, observed, expected, passed in checks
        ]
    )
    complete = bool(audit["passed"].map(boolish).all())
    payload = {
        "manifest_experiments": int(len(manifest)),
        "manifest_cases": n_cases,
        "run_directories": int(len(run_dirs)),
        "metric_summaries": int(len(paths)),
        "metric_method_rows": metric_method_rows,
        "launch_status_rows": int(len(status)),
        "launch_experiment_rows": int(len(experiment_status)),
        "launcher_exit_code": code,
        "remaining_experiments": int(max(0, args.expected_experiments - len(paths))),
        "run_complete": complete,
    }
    return audit, complete, payload


def select_cases(metrics: pd.DataFrame, column: str, role: str) -> pd.DataFrame:
    if metrics.empty:
        return metrics.copy()
    order = metrics.sort_values(
        ["region", "fold", column, "experiment_id", "method_id"],
        kind="mergesort",
    )
    selected = order.groupby(["region", "fold"], as_index=False, sort=True).head(1).copy()
    selected["selection_role"] = role
    selected["selected_by"] = (
        "validation_AQL_only" if column == "val_AQL" else "test_AQL_diagnostic_only_not_selection"
    )
    return selected.reset_index(drop=True)


def build_case_outcomes(selected: pd.DataFrame, oracle: pd.DataFrame) -> pd.DataFrame:
    oracle_cols = [
        "region",
        "fold",
        "test_AQL",
        "test_minus_current_qdesn",
        "test_minus_pricefm",
        "experiment_id",
        "method_id",
    ]
    oracle_view = oracle[oracle_cols].rename(
        columns={
            "test_AQL": "oracle_test_AQL",
            "test_minus_current_qdesn": "oracle_test_minus_current_qdesn",
            "test_minus_pricefm": "oracle_test_minus_pricefm",
            "experiment_id": "oracle_experiment_id",
            "method_id": "oracle_method_id",
        }
    )
    out = selected.merge(oracle_view, on=["region", "fold"], how="left", validate="one_to_one")
    out["validation_transfer_gap"] = out["test_AQL"] - out["oracle_test_AQL"]
    out["outcome"] = out["beats_both_on_test"].map(
        lambda value: "dual_reference_win_pending_confirmation"
        if boolish(value)
        else "blocked_no_dual_reference_win"
    )
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def promotion_queue(selected: pd.DataFrame) -> pd.DataFrame:
    out = selected[selected["beats_both_on_test"].map(boolish)].copy()
    out["promotion_status"] = "eligible_for_full_quantile_confirmation"
    out["next_required_gate"] = (
        "full_quantile_validation_only_confirmation_and_reproducibility_hash_audit"
    )
    return out.sort_values(["test_minus_pricefm", "region", "fold"]).reset_index(drop=True)


def mcmc_queue(promotions: pd.DataFrame) -> pd.DataFrame:
    out = promotions.copy()
    out["mcmc_status"] = "blocked_pending_full_quantile_confirmation"
    out["mcmc_initialization"] = "initialize_individual_rhs_ns_mcmc_from_selected_vb_winner"
    out["article_status"] = "blocked_pending_mcmc_and_hash_manifest"
    return out


def decision_gates(complete: bool, selected: pd.DataFrame, promotions: pd.DataFrame) -> pd.DataFrame:
    dual = int(selected["beats_both_on_test"].map(boolish).sum()) if not selected.empty else 0
    rows = [
        ("r33_complete", complete, "All 480 experiments and launcher records must complete cleanly."),
        ("validation_selection_frozen", complete and len(selected) == 20, "One validation-only winner per case."),
        ("test_used_for_audit_only", True, "Test is inspected only after validation selection."),
        ("dual_reference_winner_exists", dual > 0, "Winner must beat current Q-DESN and cached PriceFM on test."),
        ("full_quantile_launch_authorized", False, "Requires explicit user authorization after R34 review."),
        ("mcmc_launch_authorized", False, "Requires successful full-quantile confirmation first."),
        ("registry_mutation_authorized", False, "Requires confirmed VB and MCMC evidence."),
        ("article_mutation_authorized", False, "Requires confirmed evidence and reproducibility hashes."),
    ]
    return pd.DataFrame(
        [{"gate": gate, "passed": passed, "detail": detail} for gate, passed, detail in rows]
    )


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in sorted(set(paths)):
        if path.exists() and path.is_file():
            rows.append(
                {
                    "path": str(path),
                    "sha256": sha256_file(path),
                    "bytes": path.stat().st_size,
                }
            )
    return pd.DataFrame(rows, columns=["path", "sha256", "bytes"])


def render_report(summary: dict[str, Any], selected: pd.DataFrame, promotions: pd.DataFrame) -> str:
    return "\n".join(
        [
            "# PriceFM Stage-R34 Lean Capacity/History Closeout",
            "",
            f"- Run complete: `{summary['run_complete']}`",
            f"- Experiments complete: `{summary['metric_summaries']} / {summary['manifest_experiments']}`",
            f"- Remaining experiments: `{summary['remaining_experiments']}`",
            f"- Validation-selected cases: `{len(selected)}`",
            f"- Validation-selected dual-reference wins: `{len(promotions)}`",
            "",
            "Selection is performed independently within each region/fold using validation AQL only.",
            "Test metrics are audit-only after selection is frozen. Registry, manuscript, article,",
            "full-quantile, and MCMC actions remain blocked by separate gates.",
            "",
        ]
    )


def main() -> None:
    args = parser().parse_args()
    manifest = read_csv_required(args.manifest, "Stage-R33 launch manifest")
    require_columns(
        manifest,
        [
            "experiment_id",
            "region",
            "fold",
            "current_qdesn_AQL",
            "current_pricefm_AQL",
            "selection_is_validation_only",
        ],
        "Stage-R33 launch manifest",
    )
    if not manifest["selection_is_validation_only"].map(boolish).all():
        raise ValueError("Stage-R33 manifest violates validation-only selection")
    metrics = parse_metric_rows(manifest, args.run_root)
    audit, complete, summary = completion_audit(manifest, metrics, args)

    if args.health_only:
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    if not complete:
        raise RuntimeError(
            "Stage-R33 is incomplete; refusing to materialize Stage-R34 decisions. "
            f"{summary['metric_summaries']}/{summary['manifest_experiments']} experiments complete, "
            f"{summary['remaining_experiments']} remaining."
        )

    output_dir = repo_path(args.output_dir)
    if output_dir.exists() and any(output_dir.iterdir()) and not args.force:
        raise FileExistsError(f"Stage-R34 output exists; use --force true to replace files: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    selected = select_cases(metrics, "val_AQL", "authoritative_case_selection")
    oracle = select_cases(metrics, "test_AQL", "diagnostic_test_oracle")
    if len(selected) != args.expected_cases:
        raise ValueError(f"Expected {args.expected_cases} selected cases, found {len(selected)}")
    outcomes = build_case_outcomes(selected, oracle)
    promotions = promotion_queue(selected)
    mcmc = mcmc_queue(promotions)
    gates = decision_gates(complete, selected, promotions)
    sources = source_manifest(
        [repo_path(args.manifest), repo_path(args.grid_root) / "manifest.csv"]
        + metric_paths(args.run_root)
    )

    summary.update(
        {
            "status": "completed_cleanly",
            "validation_selected_cases": int(len(selected)),
            "validation_selected_beats_qdesn": int(selected["beats_current_qdesn_on_test"].map(boolish).sum()),
            "validation_selected_beats_pricefm": int(selected["beats_pricefm_on_test"].map(boolish).sum()),
            "validation_selected_beats_both": int(len(promotions)),
            "full_quantile_launch_authorized": False,
            "mcmc_launch_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    )
    write_frame(output_dir / OUT_COMPLETION, audit)
    write_frame(output_dir / OUT_METRICS, metrics)
    write_frame(output_dir / OUT_SELECTED, selected)
    write_frame(output_dir / OUT_ORACLE, oracle)
    write_frame(output_dir / OUT_PROMOTION, promotions)
    write_frame(output_dir / OUT_MCMC, mcmc)
    write_frame(output_dir / OUT_CASES, outcomes)
    write_frame(output_dir / OUT_GATES, gates)
    write_frame(output_dir / OUT_SOURCE, sources)
    write_json(output_dir / OUT_SUMMARY, summary)
    (output_dir / OUT_REPORT).write_text(render_report(summary, selected, promotions))
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
