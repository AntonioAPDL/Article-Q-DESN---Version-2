#!/usr/bin/env python3
"""Freeze Stage-C median winners into quantile-promotion candidate queues.

This script is intentionally conservative. It does not fit models, does not run
PriceFM, and does not promote rows. It turns the completed Stage-C median-screen
registry into explicit next-step queues using validation-only evidence.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess

import pandas as pd

from pricefm_common import repo_path, write_json


DEFAULT_MEDIAN_SELECTION_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_all_median_selection_20260618"
)
DEFAULT_MANIFEST_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_manifest_20260618"
)
DEFAULT_CACHED_PRICEFM_ROOT = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_stage_b_apples_to_apples_20260616"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_quantile_candidate_registry_20260618"
)

PAPER_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"
GREEN_REGIONS = {"BE", "SE_4", "SI", "NL"}
YELLOW_REGIONS = {"DK_1", "DK_2", "SK"}
YELLOW_REGION_FOLDS = {("RO", 2), ("RO", 3)}
RESCUE_REGIONS = {"EE", "LT", "LV"}
COMPLETION_PRIORITY = 0
GREEN_PRIORITY = 1
YELLOW_PRIORITY = 2
HOLD_PRIORITY = 99


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--median-selection-dir",
        default=DEFAULT_MEDIAN_SELECTION_DIR,
        help="Directory containing Stage-C median_selection_registry.csv.",
    )
    p.add_argument(
        "--manifest-dir",
        default=DEFAULT_MANIFEST_DIR,
        help="Directory containing stage_c_candidate_manifest.csv.",
    )
    p.add_argument(
        "--cached-pricefm-root",
        default=DEFAULT_CACHED_PRICEFM_ROOT,
        help="Existing cached PriceFM Phase-I root to audit for region/fold coverage.",
    )
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--grid-id", default="pricefm_stage_c_quantile_candidate_registry_20260618")
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def git_head():
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=str(repo_path(".")),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
    except OSError:
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def read_csv_required(path, context):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(context, path))
    return pd.read_csv(path)


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} missing columns: {}".format(context, sorted(missing)))


def numeric(series):
    return pd.to_numeric(series, errors="coerce")


def bool_series(series):
    def convert(value):
        if isinstance(value, bool):
            return value
        text = str(value).strip().lower()
        if text in {"1", "true", "yes", "y"}:
            return True
        if text in {"0", "false", "no", "n"}:
            return False
        return False
    return series.map(convert)


def validate_unique_region_fold(frame, context):
    require_columns(frame, ["region", "fold"], context)
    dup = frame[frame.duplicated(["region", "fold"], keep=False)].copy()
    if not dup.empty:
        raise ValueError(
            "{} has duplicate region/fold rows:\n{}".format(
                context,
                dup[["region", "fold"]].to_string(index=False),
            )
        )


def validate_median_registry(registry):
    required = [
        "region", "fold", "experiment_id", "selected_method_id",
        "selected_on_split", "selected_on_unit", "selection_metric",
        "selection_metric_value", "selection_AQL", "feature_map",
        "lag_window", "depth", "units", "alpha", "rho", "input_scale",
        "projection_scale", "tau0", "seed",
    ]
    require_columns(registry, required, "Stage-C median registry")
    validate_unique_region_fold(registry, "Stage-C median registry")
    bad_split = registry[
        ~registry["selected_on_split"].astype(str).eq("val")
        | ~registry["selected_on_unit"].astype(str).eq("original")
        | ~registry["selection_metric"].astype(str).eq("AQL")
    ].copy()
    if not bad_split.empty:
        raise ValueError(
            "Stage-C median registry must be validation/original/AQL selected:\n{}".format(
                bad_split[[
                    "region", "fold", "selected_on_split",
                    "selected_on_unit", "selection_metric",
                ]].to_string(index=False)
            )
        )
    values = numeric(registry["selection_metric_value"])
    if values.isna().any() or (~values.map(math.isfinite)).any():
        raise ValueError("Stage-C median registry contains non-finite selection_metric_value.")
    if (values <= 0.0).any():
        raise ValueError("Stage-C median registry contains non-positive selection_metric_value.")


def validate_method_coverage(method_coverage):
    required = ["region", "fold", "method_id", "covered", "n_finite_metric_rows"]
    require_columns(method_coverage, required, "Stage-C method coverage")
    bad = method_coverage[
        ~bool_series(method_coverage["covered"])
        | (numeric(method_coverage["n_finite_metric_rows"]) <= 0)
    ].copy()
    if not bad.empty:
        raise ValueError(
            "Stage-C median method coverage is incomplete:\n{}".format(
                bad[["region", "fold", "method_id", "covered", "n_finite_metric_rows"]]
                .to_string(index=False)
            )
        )


def validate_manifest(manifest):
    required = [
        "region", "fold", "queue", "stage_c_priority",
        "recommended_next_gate", "paper_quantiles", "selection_split",
        "selection_metric", "selection_unit", "input_scope",
        "spatial_information_set", "caution_label", "rationale",
    ]
    require_columns(manifest, required, "Stage-C manifest")
    validate_unique_region_fold(manifest, "Stage-C manifest")
    fi3 = manifest[
        manifest["region"].astype(str).eq("FI")
        & (numeric(manifest["fold"]).astype("Int64") == 3)
    ]
    if not fi3.empty:
        raise ValueError("FI fold 3 must stay out of the generic Stage-C quantile registry.")


def cache_status(row, cached_pricefm_root):
    root = repo_path(cached_pricefm_root)
    region = str(row["region"])
    fold = int(row["fold"])
    base = root / ("region={}".format(region)) / ("fold={}".format(fold))
    required = [
        base / "pricefm_phase1_metrics.csv",
        base / "pricefm_phase1_predictions_original.csv",
        base / "pricefm_phase1_predictions_scaled.csv",
        base / "pricefm_phase1_row_audit.csv",
        base / "pricefm_phase1_metric_by_horizon.csv",
    ]
    exists = [path.exists() and path.stat().st_size > 0 for path in required]
    return {
        "cached_pricefm_root": config_path_value(root),
        "cached_pricefm_region_fold_dir": config_path_value(base),
        "cached_pricefm_exists": bool(all(exists)),
        "cached_pricefm_missing_files": "|".join(
            config_path_value(path) for path, ok in zip(required, exists) if not ok
        ),
    }


def tier_row(row, region_stats):
    region = str(row["region"])
    fold = int(row["fold"])
    queue = str(row["queue"])
    if queue == "completion_folds":
        return {
            "quantile_gate_priority": COMPLETION_PRIORITY,
            "quantile_gate_label": "completion_quantile_ready",
            "quantile_gate_action": "launch_completion_paper_quantiles",
            "candidate_tier": "completion",
            "hold_reason": "",
        }
    if queue != "diverse_new_regions":
        return {
            "quantile_gate_priority": HOLD_PRIORITY,
            "quantile_gate_label": "unsupported_queue_hold",
            "quantile_gate_action": "manual_review",
            "candidate_tier": "hold",
            "hold_reason": "unsupported_queue",
        }
    if region in GREEN_REGIONS:
        return {
            "quantile_gate_priority": GREEN_PRIORITY,
            "quantile_gate_label": "green_full_region_quantile_ready",
            "quantile_gate_action": "pricefm_cache_sentinel_then_paper_quantiles",
            "candidate_tier": "green",
            "hold_reason": "",
        }
    if region in YELLOW_REGIONS or (region, fold) in YELLOW_REGION_FOLDS:
        return {
            "quantile_gate_priority": YELLOW_PRIORITY,
            "quantile_gate_label": "yellow_hold_after_green_gate",
            "quantile_gate_action": "hold_until_green_quantile_results",
            "candidate_tier": "yellow",
            "hold_reason": "moderate_validation_or_mixed_region",
        }
    if region in RESCUE_REGIONS:
        reason = "weak_validation_region"
    else:
        stats = region_stats.get(region, {})
        reason = "mixed_or_weak_validation"
        if stats and float(stats.get("val_mean", 0.0)) <= 13.5:
            reason = "mixed_validation_region"
    return {
        "quantile_gate_priority": HOLD_PRIORITY,
        "quantile_gate_label": "median_rescue_hold",
        "quantile_gate_action": "design_median_rescue_before_quantiles",
        "candidate_tier": "rescue",
        "hold_reason": reason,
    }


def region_validation_stats(registry):
    tmp = registry.copy()
    tmp["selection_metric_value"] = numeric(tmp["selection_metric_value"])
    rows = []
    for region, sub in tmp.groupby("region"):
        rows.append({
            "region": region,
            "n_folds": int(sub.shape[0]),
            "val_mean": float(sub["selection_metric_value"].mean()),
            "val_min": float(sub["selection_metric_value"].min()),
            "val_max": float(sub["selection_metric_value"].max()),
            "n_exal_winners": int(sub["selected_method_id"].astype(str).str.contains("exal").sum()),
            "n_d2_winners": int((numeric(sub["depth"]) == 2).sum()),
        })
    return pd.DataFrame(rows).sort_values(["val_mean", "region"]).reset_index(drop=True)


def build_registry(median_registry, manifest, method_coverage, cached_pricefm_root):
    validate_median_registry(median_registry)
    validate_manifest(manifest)
    validate_method_coverage(method_coverage)
    manifest_cols = [
        "region", "fold", "queue", "stage_c_priority", "recommended_next_gate",
        "paper_quantiles", "selection_split", "selection_metric",
        "selection_unit", "candidate_strategy", "allowed_final_methods",
        "input_scope", "output_scope", "feature_policy",
        "lead_covariate_status", "spatial_information_set",
        "cleanup_binary_artifacts", "preserve_pricefm_as_benchmark_only",
        "phase1_AQL", "phase1_MAE", "phase1_RMSE",
        "degree1_n", "degree2_n", "rationale", "caution_label",
    ]
    cols = [col for col in manifest_cols if col in manifest.columns]
    out = median_registry.merge(
        manifest[cols],
        on=["region", "fold"],
        how="left",
        validate="one_to_one",
    )
    missing_manifest = out[out["queue"].isna()].copy()
    if not missing_manifest.empty:
        raise ValueError(
            "Median registry rows missing from Stage-C manifest:\n{}".format(
                missing_manifest[["region", "fold"]].to_string(index=False)
            )
        )
    region_stats_frame = region_validation_stats(out)
    region_stats = {
        str(row.region): row._asdict()
        for row in region_stats_frame.itertuples(index=False)
    }
    tier_rows = [tier_row(row, region_stats) for _, row in out.iterrows()]
    tiers = pd.DataFrame(tier_rows)
    out = pd.concat([out.reset_index(drop=True), tiers], axis=1)
    cache_rows = [cache_status(row, cached_pricefm_root) for _, row in out.iterrows()]
    out = pd.concat([out.reset_index(drop=True), pd.DataFrame(cache_rows)], axis=1)
    out["target_quantiles"] = PAPER_QUANTILES
    out["selection_uses_test_or_pricefm_metrics"] = False
    out["stage_c_quantile_candidate_source"] = "stage_c_median_validation_registry"
    out["stage_c_quantile_registry_git_head"] = git_head()
    out["requires_pricefm_cache_before_comparison"] = ~out["cached_pricefm_exists"].astype(bool)
    out = out.sort_values(
        ["quantile_gate_priority", "candidate_tier", "region", "fold"],
        na_position="last",
    ).reset_index(drop=True)
    return out, region_stats_frame


def markdown_value(value):
    if isinstance(value, float):
        if pd.isna(value):
            return ""
        return "{:.6g}".format(value)
    if pd.isna(value):
        return ""
    return str(value).replace("\n", " ").replace("|", "\\|")


def markdown_table(frame, columns=None):
    if frame is None or frame.empty:
        return "_No rows._"
    if columns is not None:
        frame = frame[[col for col in columns if col in frame.columns]].copy()
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        lines.append("| " + " | ".join(markdown_value(row[col]) for col in cols) + " |")
    return "\n".join(lines)


def write_report(out_dir, registry, region_stats, summary):
    path = out_dir / "stage_c_quantile_candidate_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-C Quantile Candidate Registry\n\n")
        f.write("Grid: `{}`\n\n".format(summary["grid_id"]))
        f.write(
            "This registry freezes Stage-C median-screen winners into "
            "validation-only quantile-promotion queues. It does not fit "
            "models and it does not use test or PriceFM metrics for "
            "candidate selection.\n\n"
        )
        f.write("## Queue Counts\n\n")
        counts = (
            registry.groupby(["quantile_gate_priority", "quantile_gate_label"])
            .size()
            .reset_index(name="n_rows")
            .sort_values(["quantile_gate_priority", "quantile_gate_label"])
        )
        f.write(markdown_table(counts))
        f.write("\n\n## Region Validation Summary\n\n")
        f.write(markdown_table(
            region_stats,
            columns=[
                "region", "n_folds", "val_mean", "val_min", "val_max",
                "n_exal_winners", "n_d2_winners",
            ],
        ))
        f.write("\n\n## PriceFM Cache Requirements\n\n")
        req = registry[[
            "region", "fold", "queue", "quantile_gate_priority",
            "quantile_gate_label", "cached_pricefm_exists",
            "requires_pricefm_cache_before_comparison",
        ]].copy()
        f.write(markdown_table(req))
        f.write("\n\n## Rules\n\n")
        f.write("- Priority 0 completion folds can proceed to paper quantiles with the existing cached PriceFM root.\n")
        f.write("- Priority 1 green rows require a PriceFM cache sentinel before comparison.\n")
        f.write("- Yellow and rescue rows are held until the first Stage-C quantile gates are inspected.\n")
        f.write("- `FI` fold 3 remains outside this generic flow.\n")
    return path


def freeze(args):
    median_dir = repo_path(args.median_selection_dir)
    manifest_dir = repo_path(args.manifest_dir)
    out_dir = repo_path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    median_registry = read_csv_required(
        median_dir / "median_selection_registry.csv",
        "Stage-C median selection",
    )
    method_coverage = read_csv_required(
        median_dir / "median_selection_method_coverage.csv",
        "Stage-C method coverage",
    )
    manifest = read_csv_required(
        manifest_dir / "stage_c_candidate_manifest.csv",
        "Stage-C manifest",
    )
    registry, region_stats = build_registry(
        median_registry,
        manifest,
        method_coverage,
        args.cached_pricefm_root,
    )
    priority0 = registry[registry["quantile_gate_priority"].eq(COMPLETION_PRIORITY)].copy()
    priority1 = registry[registry["quantile_gate_priority"].eq(GREEN_PRIORITY)].copy()
    priority2 = registry[registry["quantile_gate_priority"].eq(YELLOW_PRIORITY)].copy()
    hold = registry[registry["quantile_gate_priority"].eq(HOLD_PRIORITY)].copy()
    cache_requirements = registry[[
        "region", "fold", "queue", "quantile_gate_priority",
        "quantile_gate_label", "candidate_tier", "cached_pricefm_exists",
        "cached_pricefm_region_fold_dir", "cached_pricefm_missing_files",
        "requires_pricefm_cache_before_comparison",
    ]].copy()

    registry.to_csv(out_dir / "stage_c_quantile_candidate_registry.csv", index=False)
    priority0.to_csv(out_dir / "stage_c_quantile_priority0_completion_registry.csv", index=False)
    priority1.to_csv(out_dir / "stage_c_quantile_priority1_green_registry.csv", index=False)
    priority2.to_csv(out_dir / "stage_c_quantile_priority2_yellow_registry.csv", index=False)
    hold.to_csv(out_dir / "stage_c_quantile_hold_registry.csv", index=False)
    cache_requirements.to_csv(out_dir / "stage_c_benchmark_cache_requirements.csv", index=False)
    region_stats.to_csv(out_dir / "stage_c_region_validation_summary.csv", index=False)

    summary = {
        "grid_id": args.grid_id,
        "median_selection_dir": config_path_value(median_dir),
        "manifest_dir": config_path_value(manifest_dir),
        "cached_pricefm_root": config_path_value(args.cached_pricefm_root),
        "output_dir": config_path_value(out_dir),
        "git_head": git_head(),
        "n_rows": int(registry.shape[0]),
        "n_priority0_completion": int(priority0.shape[0]),
        "n_priority1_green": int(priority1.shape[0]),
        "n_priority2_yellow": int(priority2.shape[0]),
        "n_hold": int(hold.shape[0]),
        "n_cached_pricefm_exists": int(registry["cached_pricefm_exists"].astype(bool).sum()),
        "n_requires_pricefm_cache": int(registry["requires_pricefm_cache_before_comparison"].astype(bool).sum()),
        "selection_uses_test_or_pricefm_metrics": False,
        "outputs": {
            "candidate_registry": config_path_value(out_dir / "stage_c_quantile_candidate_registry.csv"),
            "priority0_completion": config_path_value(out_dir / "stage_c_quantile_priority0_completion_registry.csv"),
            "priority1_green": config_path_value(out_dir / "stage_c_quantile_priority1_green_registry.csv"),
            "priority2_yellow": config_path_value(out_dir / "stage_c_quantile_priority2_yellow_registry.csv"),
            "hold_registry": config_path_value(out_dir / "stage_c_quantile_hold_registry.csv"),
            "cache_requirements": config_path_value(out_dir / "stage_c_benchmark_cache_requirements.csv"),
            "region_validation_summary": config_path_value(out_dir / "stage_c_region_validation_summary.csv"),
        },
    }
    report = write_report(out_dir, registry, region_stats, summary)
    summary["outputs"]["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    summary = freeze(args)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
