#!/usr/bin/env python3
"""Prepare the bounded Stage-R33A SE_1 guard repair without launching it."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"

DEFAULT_SOURCE_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r33_lean_capacity_history_20260722.yaml"
)
DEFAULT_SOURCE_MANIFEST = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r33_lean_capacity_history_launch_prep_20260722/"
    "pricefm_stage_r33_launch_manifest.csv"
)
DEFAULT_SOURCE_GRID_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r33_lean_capacity_history_20260722"
)
DEFAULT_SOURCE_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_r33_lean_capacity_history_20260722"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_r33a_se1_guard_repair_prep_20260803"
)
DEFAULT_REPAIR_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_r33a_se1_guard_repair_20260803.yaml"
)
DEFAULT_REPAIR_GRID_ID = "pricefm_stage_r33a_se1_guard_repair_20260803"
DEFAULT_REPAIR_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_r33a_se1_guard_repair_20260803"
)
DEFAULT_FAILURE_PATTERN = (
    "horizon_weighting expansion factor 6.5 exceeds max_expansion_factor 6"
)

OUT_MANIFEST = "pricefm_stage_r33a_se1_guard_repair_manifest.csv"
OUT_FAILURES = "pricefm_stage_r33a_failure_evidence.csv"
OUT_ADAPTERS = "pricefm_stage_r33a_adapter_reuse_audit.csv"
OUT_DIFF = "pricefm_stage_r33a_single_factor_diff_audit.csv"
OUT_GATES = "pricefm_stage_r33a_repair_prep_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r33a_se1_guard_repair_prep_report.md"

ADAPTER_REQUIRED = (
    "adapter_manifest.json",
    "X_train.csv",
    "X_val.csv",
    "X_test.csv",
    "y_train.csv",
    "y_val.csv",
    "y_test.csv",
    "rows_train.csv",
    "rows_val.csv",
    "rows_test.csv",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-grid-config", default=DEFAULT_SOURCE_GRID_CONFIG)
    p.add_argument("--source-manifest", default=DEFAULT_SOURCE_MANIFEST)
    p.add_argument("--source-grid-root", default=DEFAULT_SOURCE_GRID_ROOT)
    p.add_argument("--source-run-root", default=DEFAULT_SOURCE_RUN_ROOT)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--repair-grid-config", default=DEFAULT_REPAIR_GRID_CONFIG)
    p.add_argument("--repair-grid-id", default=DEFAULT_REPAIR_GRID_ID)
    p.add_argument("--repair-generated-root", default=DEFAULT_REPAIR_GENERATED_ROOT)
    p.add_argument(
        "--repair-run-root",
        default="",
        help="Existing R33 run root. Blank reuses --source-run-root.",
    )
    p.add_argument("--expected-source-experiments", type=int, default=480)
    p.add_argument("--expected-repairs", type=int, default=24)
    p.add_argument("--repair-region", default="SE_1")
    p.add_argument("--repair-fold", type=int, default=3)
    p.add_argument("--guard-before", type=float, default=6.0)
    p.add_argument("--guard-after", type=float, default=7.0)
    p.add_argument("--failure-pattern", default=DEFAULT_FAILURE_PATTERN)
    p.add_argument("--recommended-experiment-jobs", type=int, default=16)
    p.add_argument("--launch-authorized", type=parse_bool, default=False)
    p.add_argument("--write-grid", type=parse_bool, default=False)
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
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "passed"}


def read_csv_required(path: str | Path, label: str) -> pd.DataFrame:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required CSV: {full}")
    return pd.read_csv(full, low_memory=False)


def read_yaml_required(path: str | Path, label: str) -> dict[str, Any]:
    full = repo_path(path)
    if not full.exists() or full.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing required YAML: {full}")
    with full.open("r") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{label} did not parse to a mapping: {full}")
    return payload


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


def config_path_value(path: str | Path) -> str:
    full = repo_path(path)
    root = repo_path(".")
    try:
        return str(full.relative_to(root))
    except ValueError:
        return str(full)


def experiment_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if GRID_BLOCK not in payload or not isinstance(payload[GRID_BLOCK], dict):
        raise ValueError(f"Source grid is missing {GRID_BLOCK}")
    experiments = payload[GRID_BLOCK].get("experiments", [])
    if not isinstance(experiments, list):
        raise ValueError("Source grid experiments must be a list")
    by_id = {str(experiment.get("id", "")): experiment for experiment in experiments}
    if "" in by_id or len(by_id) != len(experiments):
        raise ValueError("Source grid experiment IDs must be nonempty and unique")
    return by_id


def flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        rows: dict[str, Any] = {}
        for key in sorted(value):
            child = f"{prefix}.{key}" if prefix else str(key)
            rows.update(flatten(value[key], child))
        return rows
    if isinstance(value, list):
        rows = {}
        for index, item in enumerate(value):
            rows.update(flatten(item, f"{prefix}[{index}]"))
        return rows
    return {prefix: value}


def experiment_diff(source: dict[str, Any], repair: dict[str, Any]) -> list[dict[str, Any]]:
    before = flatten(source)
    after = flatten(repair)
    rows = []
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key):
            rows.append(
                {
                    "field": key,
                    "source_value": json.dumps(before.get(key), sort_keys=True),
                    "repair_value": json.dumps(after.get(key), sort_keys=True),
                }
            )
    return rows


def adapter_dir(run_root: str | Path, experiment_id: str, region: str, fold: int) -> Path:
    return (
        repo_path(run_root)
        / experiment_id
        / "cells"
        / f"region={region}"
        / f"fold={int(fold)}"
        / "adapter"
    )


def model_dir(run_root: str | Path, experiment_id: str, region: str, fold: int) -> Path:
    return (
        repo_path(run_root)
        / experiment_id
        / "cells"
        / f"region={region}"
        / f"fold={int(fold)}"
        / "model"
    )


def model_log(run_root: str | Path, experiment_id: str, region: str, fold: int) -> Path:
    return (
        repo_path(run_root)
        / experiment_id
        / "logs"
        / f"region={region}_fold={int(fold)}.model.log"
    )


def build_repair_grid(
    source_payload: dict[str, Any],
    repair_experiments: list[dict[str, Any]],
    args: argparse.Namespace,
) -> dict[str, Any]:
    payload = copy.deepcopy(source_payload)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.repair_grid_id)
    grid["purpose"] = (
        "Stage-R33A bounded repair of the 24 SE_1 fold-3 experiments stopped before fitting "
        "by the horizon-weight expansion guard. The model contract is unchanged except that "
        "max_expansion_factor is raised from 6 to 7."
    )
    grid["base"]["generated_root"] = config_path_value(args.repair_generated_root)
    repair_run_root = args.repair_run_root or args.source_run_root
    grid["base"]["run_root"] = config_path_value(repair_run_root)
    grid["scope"]["regions"] = [str(args.repair_region)]
    grid["scope"]["folds"] = [int(args.repair_fold)]
    grid["launch"] = {
        "stage_r33a_guard_repair": {
            "priorities": [0],
            "experiment_jobs": int(args.recommended_experiment_jobs),
            "cell_jobs": 1,
            "build_windows": False,
            "dry_run": False,
            "resume": True,
            "force": False,
            "authorized_now": bool(args.launch_authorized),
            "note": "Prep writes inputs only; the launcher remains a separate command.",
        }
    }
    grid["experiments"] = repair_experiments
    grid["experiment_blocks"] = []
    return payload


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in sorted(set(paths)):
        if path.exists() and path.is_file():
            rows.append(
                {"path": str(path), "sha256": sha256_file(path), "bytes": path.stat().st_size}
            )
    return pd.DataFrame(rows, columns=["path", "sha256", "bytes"])


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    source_payload = read_yaml_required(args.source_grid_config, "Stage-R33 source grid")
    source_manifest_frame = read_csv_required(args.source_manifest, "Stage-R33 launch manifest")
    source_status_path = repo_path(args.source_grid_root) / "launch_status.csv"
    source_status = read_csv_required(source_status_path, "Stage-R33 launch status")
    require_columns(
        source_manifest_frame,
        [
            "experiment_id",
            "region",
            "fold",
            "seed",
            "selection_is_validation_only",
            "mutates_registry",
            "mutates_manuscript",
        ],
        "Stage-R33 launch manifest",
    )
    require_columns(source_status, ["id", "kind", "status", "return_code"], "Stage-R33 launch status")
    if source_manifest_frame["experiment_id"].duplicated().any():
        raise ValueError("Stage-R33 launch manifest contains duplicate experiment IDs")

    source_experiments = experiment_map(source_payload)
    experiment_status = source_status[source_status["kind"].astype(str).eq("experiment")].copy()
    experiment_status["return_code_numeric"] = pd.to_numeric(
        experiment_status["return_code"], errors="coerce"
    )
    failed = experiment_status[
        experiment_status["status"].astype(str).str.lower().eq("failed")
        & experiment_status["return_code_numeric"].ne(0)
    ].copy()
    failed_ids = set(failed["id"].astype(str))
    successful_ids = set(
        experiment_status.loc[
            experiment_status["status"].astype(str).str.lower().eq("completed")
            & experiment_status["return_code_numeric"].eq(0),
            "id",
        ].astype(str)
    )
    manifest_by_id = source_manifest_frame.set_index("experiment_id", drop=False)

    failure_rows = []
    adapter_rows = []
    repair_rows = []
    repair_experiments = []
    diff_rows = []
    source_paths = [repo_path(args.source_grid_config), repo_path(args.source_manifest), source_status_path]
    for experiment_id in sorted(failed_ids):
        if experiment_id not in manifest_by_id.index:
            raise ValueError(f"Failed experiment is absent from Stage-R33 manifest: {experiment_id}")
        if experiment_id not in source_experiments:
            raise ValueError(f"Failed experiment is absent from Stage-R33 grid: {experiment_id}")
        manifest_row = manifest_by_id.loc[experiment_id]
        region = str(manifest_row["region"])
        fold = int(manifest_row["fold"])
        log_path = model_log(args.source_run_root, experiment_id, region, fold)
        log_text = log_path.read_text(errors="replace") if log_path.exists() else ""
        reason_match = str(args.failure_pattern) in log_text
        failure_rows.append(
            {
                "experiment_id": experiment_id,
                "region": region,
                "fold": fold,
                "source_status": "failed",
                "source_return_code": int(
                    failed.loc[failed["id"].astype(str).eq(experiment_id), "return_code_numeric"].iloc[0]
                ),
                "model_log_path": str(log_path),
                "model_log_sha256": sha256_file(log_path) if log_path.exists() else "",
                "expected_failure_pattern": str(args.failure_pattern),
                "failure_pattern_matched": reason_match,
            }
        )
        if log_path.exists():
            source_paths.append(log_path)

        adapter = adapter_dir(args.source_run_root, experiment_id, region, fold)
        files = [adapter / name for name in ADAPTER_REQUIRED]
        missing = [str(path) for path in files if not path.exists() or path.stat().st_size == 0]
        metric = model_dir(args.source_run_root, experiment_id, region, fold) / "metric_summary.csv"
        adapter_rows.append(
            {
                "experiment_id": experiment_id,
                "region": region,
                "fold": fold,
                "adapter_dir": str(adapter),
                "required_file_count": len(files),
                "present_nonempty_file_count": len(files) - len(missing),
                "missing_required_files": json.dumps(missing),
                "adapter_ready_for_model": not missing,
                "metric_summary_path": str(metric),
                "metric_summary_preexists": metric.exists() and metric.stat().st_size > 0,
            }
        )
        adapter_manifest = adapter / "adapter_manifest.json"
        if adapter_manifest.exists():
            source_paths.append(adapter_manifest)

        source_experiment = source_experiments[experiment_id]
        source_guard = (
            source_experiment.get("training", {})
            .get("horizon_weighting", {})
            .get("max_expansion_factor")
        )
        repair_experiment = copy.deepcopy(source_experiment)
        repair_experiment.setdefault("training", {}).setdefault("horizon_weighting", {})[
            "max_expansion_factor"
        ] = float(args.guard_after)
        per_experiment_diff = experiment_diff(source_experiment, repair_experiment)
        for row in per_experiment_diff:
            diff_rows.append({"experiment_id": experiment_id, **row})
        repair_experiments.append(repair_experiment)
        repair_rows.append(
            {
                **manifest_row.to_dict(),
                "source_status": "failed",
                "source_guard": source_guard,
                "repair_guard": float(args.guard_after),
                "repair_reason": "raise_resource_guard_to_observed_expansion_ceiling",
                "reuses_existing_adapter": not missing,
                "refits_model_only": True,
                "source_metric_summary_preexists": metric.exists() and metric.stat().st_size > 0,
                "repair_generated_root": config_path_value(args.repair_generated_root),
                "repair_run_root": config_path_value(args.repair_run_root or args.source_run_root),
                "selection_rule_unchanged": True,
                "registry_mutation_authorized": False,
                "manuscript_mutation_authorized": False,
            }
        )

    failure_frame = pd.DataFrame(failure_rows)
    adapter_frame = pd.DataFrame(adapter_rows)
    repair_manifest = pd.DataFrame(repair_rows)
    diff_frame = pd.DataFrame(diff_rows)
    expected_diff_field = "training.horizon_weighting.max_expansion_factor"
    source_grid = source_payload[GRID_BLOCK]
    repair_run_root = args.repair_run_root or args.source_run_root
    checks = [
        (
            "source_manifest_count",
            len(source_manifest_frame) == int(args.expected_source_experiments),
            "The immutable Stage-R33 launch manifest has the expected complete design size.",
        ),
        (
            "source_grid_count",
            len(source_experiments) == int(args.expected_source_experiments),
            "The immutable Stage-R33 grid has the expected complete design size.",
        ),
        (
            "source_status_count",
            len(experiment_status) == int(args.expected_source_experiments),
            "The original launch ledger has one experiment record per Stage-R33 ID.",
        ),
        (
            "repair_count",
            len(failed_ids) == int(args.expected_repairs),
            "Only the expected failed Stage-R33 rows enter the repair.",
        ),
        (
            "successful_rows_excluded",
            successful_ids.isdisjoint(failed_ids)
            and len(successful_ids) == int(args.expected_source_experiments) - int(args.expected_repairs),
            "Every successful Stage-R33 experiment is excluded from R33A.",
        ),
        (
            "repair_case_exact",
            not repair_manifest.empty
            and repair_manifest["region"].astype(str).eq(str(args.repair_region)).all()
            and repair_manifest["fold"].astype(int).eq(int(args.repair_fold)).all(),
            "Every repair row is the pre-registered SE_1 fold-3 case.",
        ),
        (
            "failure_reason_exact",
            not failure_frame.empty and failure_frame["failure_pattern_matched"].map(boolish).all(),
            "Every failed row carries the same observed expansion-guard error.",
        ),
        (
            "adapters_reusable",
            not adapter_frame.empty and adapter_frame["adapter_ready_for_model"].map(boolish).all(),
            "All runner-required adapter matrices and row/target files are present and nonempty.",
        ),
        (
            "no_existing_metrics_for_repair",
            not adapter_frame.empty and not adapter_frame["metric_summary_preexists"].map(boolish).any(),
            "No repaired row already has a metric summary.",
        ),
        (
            "source_guard_exact",
            not repair_manifest.empty
            and pd.to_numeric(repair_manifest["source_guard"], errors="coerce")
            .eq(float(args.guard_before))
            .all(),
            "Every failed source row used max_expansion_factor=6.",
        ),
        (
            "repair_guard_minimal",
            float(args.guard_after) > float(args.guard_before)
            and float(args.guard_after) >= 6.5,
            "The repaired guard admits the observed 6.5 expansion without changing weights.",
        ),
        (
            "single_factor_diff_only",
            len(diff_frame) == int(args.expected_repairs)
            and set(diff_frame.get("field", pd.Series(dtype=str)).astype(str)) == {expected_diff_field},
            "Each experiment changes only training.horizon_weighting.max_expansion_factor.",
        ),
        (
            "same_run_root_reuses_adapters",
            repo_path(repair_run_root) == repo_path(args.source_run_root),
            "Repair configs point to the original R33 run directories so the runner reuses adapters.",
        ),
        (
            "separate_repair_ledger",
            repo_path(args.repair_generated_root) != repo_path(args.source_grid_root),
            "R33A writes a separate generated grid and launch_status ledger.",
        ),
        (
            "validation_selection_preserved",
            not repair_manifest.empty
            and repair_manifest["selection_is_validation_only"].map(boolish).all(),
            "Validation-only case selection remains frozen.",
        ),
        (
            "registry_manuscript_blocked",
            not repair_manifest["mutates_registry"].map(boolish).any()
            and not repair_manifest["mutates_manuscript"].map(boolish).any(),
            "The repair cannot mutate the registry or manuscript.",
        ),
    ]
    gates = pd.DataFrame(
        [{"gate": name, "passed": bool(passed), "detail": detail} for name, passed, detail in checks]
    )
    failed_gates = gates.loc[~gates["passed"].map(boolish), "gate"].tolist()
    if failed_gates:
        raise ValueError(f"Stage-R33A repair-prep gates failed: {failed_gates}")

    repair_payload = build_repair_grid(source_payload, repair_experiments, args)
    summary = {
        "status": "validated_repair_ready_for_materialization",
        "source_grid_id": str(source_grid.get("grid_id", "")),
        "repair_grid_id": str(args.repair_grid_id),
        "source_experiments": int(len(source_manifest_frame)),
        "source_successes_excluded": int(len(successful_ids)),
        "repair_experiments": int(len(repair_manifest)),
        "repair_region": str(args.repair_region),
        "repair_fold": int(args.repair_fold),
        "guard_before": float(args.guard_before),
        "observed_expansion_factor": 6.5,
        "guard_after": float(args.guard_after),
        "adapters_reused": int(adapter_frame["adapter_ready_for_model"].map(boolish).sum()),
        "model_fields_changed_per_experiment": 1,
        "repair_grid_written": bool(args.write_grid),
        "launch_authorized": bool(args.launch_authorized),
        "launcher_invoked_by_prep": False,
        "registry_mutation_authorized": False,
        "manuscript_mutation_authorized": False,
    }
    return {
        "repair_payload": repair_payload,
        "repair_manifest": repair_manifest,
        "failure_evidence": failure_frame,
        "adapter_audit": adapter_frame,
        "diff_audit": diff_frame,
        "gates": gates,
        "sources": source_manifest(source_paths),
        "summary": summary,
    }


def render_report(summary: dict[str, Any]) -> str:
    return "\n".join(
        [
            "# PriceFM Stage-R33A SE_1 Guard Repair Prep",
            "",
            f"- Source experiments: `{summary['source_experiments']}`",
            f"- Successful experiments excluded: `{summary['source_successes_excluded']}`",
            f"- Repair experiments: `{summary['repair_experiments']}`",
            f"- Repair case: `{summary['repair_region']} / fold {summary['repair_fold']}`",
            f"- Guard change: `{summary['guard_before']} -> {summary['guard_after']}`",
            f"- Existing adapters reusable: `{summary['adapters_reused']}`",
            f"- Repair YAML written: `{summary['repair_grid_written']}`",
            "",
            "The 24 source experiment IDs, seeds, windows, features, reservoir settings,",
            "likelihoods, selection policy, and run directories are unchanged. Only the",
            "resource-safety ceiling is raised enough to admit the observed 6.5 expansion.",
            "The original R33 grid and launch ledger remain immutable. R34 must reconcile",
            "the separate R33A ledger before any scientific decision is materialized.",
            "Registry, manuscript, full-quantile, and MCMC actions remain blocked.",
            "",
        ]
    )


def write_frame(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def materialize(result: dict[str, Any], args: argparse.Namespace) -> None:
    output_dir = repo_path(args.output_dir)
    grid_path = repo_path(args.repair_grid_config)
    if output_dir.exists() and any(output_dir.iterdir()) and not bool(args.force):
        raise FileExistsError(f"R33A output exists; use --force true to replace it: {output_dir}")
    if bool(args.write_grid) and grid_path.exists() and not bool(args.force):
        raise FileExistsError(f"R33A repair grid exists; use --force true to replace it: {grid_path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    write_frame(output_dir / OUT_MANIFEST, result["repair_manifest"])
    write_frame(output_dir / OUT_FAILURES, result["failure_evidence"])
    write_frame(output_dir / OUT_ADAPTERS, result["adapter_audit"])
    write_frame(output_dir / OUT_DIFF, result["diff_audit"])
    write_frame(output_dir / OUT_GATES, result["gates"])
    write_frame(output_dir / OUT_SOURCE, result["sources"])
    write_json(output_dir / OUT_SUMMARY, result["summary"])
    (output_dir / OUT_REPORT).write_text(render_report(result["summary"]))
    if bool(args.write_grid):
        grid_path.parent.mkdir(parents=True, exist_ok=True)
        with grid_path.open("w") as handle:
            yaml.safe_dump(result["repair_payload"], handle, sort_keys=False)


def main() -> None:
    args = parser().parse_args()
    result = prepare(args)
    materialize(result, args)
    print(json.dumps(result["summary"], indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
