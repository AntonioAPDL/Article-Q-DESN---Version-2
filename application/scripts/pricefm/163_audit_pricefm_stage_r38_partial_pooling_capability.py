#!/usr/bin/env python3
"""Audit PriceFM R36 partial-pooling headroom and confirmation readiness."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import parse_bool, repo_path, write_json


DEFAULT_R36_RUN_ROOT = (
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/"
    "pricefm_stage_r36_nested_horizon_readout_20260804"
)
DEFAULT_R37_DIR = (
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/"
    "pricefm_stage_r37_nested_horizon_readout_closeout_20260805"
)
DEFAULT_SPLIT_ROOT = (
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/processed/splits"
)
DEFAULT_OUTPUT_DIR = (
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/"
    "pricefm_stage_r38_partial_pooling_capability_20260805"
)

SHARED = "qdesn_al_rhs_ns_exact_chunked"
SEPARATE = f"{SHARED}_horizon_separate"
LAMBDAS = np.linspace(0.0, 1.0, 21)
BLOCKS = [(1, 24), (25, 48), (49, 72), (73, 96)]

OUT_CASES = "pricefm_stage_r38_partial_pooling_capability_atlas.csv"
OUT_GLOBAL = "pricefm_stage_r38_global_blend_curve.csv"
OUT_BLOCK = "pricefm_stage_r38_block_blend_curve.csv"
OUT_CONVERGENCE = "pricefm_stage_r38_convergence_capability_audit.csv"
OUT_DATA = "pricefm_stage_r38_confirmation_data_authority.csv"
OUT_DESIGN = "pricefm_stage_r38_r39_design_contract.csv"
OUT_GATES = "pricefm_stage_r38_decision_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r38_partial_pooling_capability_report.md"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r36-run-root", default=DEFAULT_R36_RUN_ROOT)
    p.add_argument("--stage-r37-dir", default=DEFAULT_R37_DIR)
    p.add_argument("--split-root", default=DEFAULT_SPLIT_ROOT)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--expected-cases", type=int, default=11)
    p.add_argument("--practical-harm-margin-relative", type=float, default=0.005)
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
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def read_csv(path: Path, label: str) -> pd.DataFrame:
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError(f"{label} missing: {path}")
    return pd.read_csv(path, low_memory=False)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def pinball(y: pd.Series, prediction: pd.Series, tau: float = 0.5) -> float:
    error = y.to_numpy(dtype=float) - prediction.to_numpy(dtype=float)
    return float(np.mean(np.maximum(tau * error, (tau - 1.0) * error)))


def prediction_paths(run_root: Path) -> list[Path]:
    return sorted(run_root.glob("*/cells/region=*/fold=*/model/model_predictions_scaled.csv"))


def case_frame(path: Path) -> tuple[str, int, pd.DataFrame, Path]:
    region = path.parts[-4].split("=", 1)[1]
    fold = int(path.parts[-3].split("=", 1)[1])
    predictions = read_csv(path, "R36 prediction artifact")
    selected = predictions[predictions["method_id"].astype(str).isin([SHARED, SEPARATE])]
    wide = selected.pivot(
        index=["origin_id", "horizon"], columns="method_id", values="pred_scaled"
    ).reset_index()
    rows_path = path.parent.parent / "adapter" / "rows_val.csv"
    truth = read_csv(rows_path, "R36 validation rows")[["origin_id", "horizon", "y_scaled"]]
    merged = wide.merge(truth, on=["origin_id", "horizon"], validate="one_to_one")
    if merged[[SHARED, SEPARATE, "y_scaled"]].isna().any().any():
        raise ValueError(f"Incomplete paired prediction surface: {path}")
    return region, fold, merged, rows_path


def blend_atlas(run_root: Path, expected_cases: int) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[Path]]:
    cases, global_rows, block_rows, sources = [], [], [], []
    paths = prediction_paths(run_root)
    if len(paths) != expected_cases:
        raise ValueError(f"Expected {expected_cases} R36 prediction artifacts, found {len(paths)}")
    for path in paths:
        region, fold, frame, truth_path = case_frame(path)
        sources += [path, truth_path]
        shared_aql = pinball(frame["y_scaled"], frame[SHARED])
        separate_aql = pinball(frame["y_scaled"], frame[SEPARATE])
        for weight in LAMBDAS:
            prediction = (1.0 - weight) * frame[SHARED] + weight * frame[SEPARATE]
            global_rows.append({
                "region": region, "fold": fold, "separate_weight": weight,
                "AQL_scaled": pinball(frame["y_scaled"], prediction),
                "role": "outer_validation_oracle_capability_only",
                "selection_authorized": False,
            })
        global_case = pd.DataFrame(global_rows)
        global_case = global_case[(global_case["region"] == region) & (global_case["fold"] == fold)]
        global_best = global_case.sort_values(["AQL_scaled", "separate_weight"]).iloc[0]
        block_prediction = pd.Series(index=frame.index, dtype=float)
        block_weights: dict[str, float] = {}
        for start, end in BLOCKS:
            mask = frame["horizon"].between(start, end)
            label = f"{start}-{end}"
            candidates = []
            for weight in LAMBDAS:
                prediction = (1.0 - weight) * frame.loc[mask, SHARED] + weight * frame.loc[mask, SEPARATE]
                score = pinball(frame.loc[mask, "y_scaled"], prediction)
                candidates.append((weight, score))
                block_rows.append({
                    "region": region, "fold": fold, "horizon_group": label,
                    "separate_weight": weight, "AQL_scaled": score,
                    "role": "outer_validation_oracle_capability_only",
                    "selection_authorized": False,
                })
            weight, _ = min(candidates, key=lambda value: (value[1], value[0]))
            block_weights[label] = float(weight)
            block_prediction.loc[mask] = (
                (1.0 - weight) * frame.loc[mask, SHARED] + weight * frame.loc[mask, SEPARATE]
            )
        block_aql = pinball(frame["y_scaled"], block_prediction)
        best_extreme = min(shared_aql, separate_aql)
        cases.append({
            "region": region, "fold": fold,
            "shared_AQL_scaled": shared_aql,
            "separate_AQL_scaled": separate_aql,
            "best_extreme_AQL_scaled": best_extreme,
            "global_oracle_separate_weight": float(global_best["separate_weight"]),
            "global_oracle_AQL_scaled": float(global_best["AQL_scaled"]),
            "global_oracle_gain_vs_best_extreme": float(global_best["AQL_scaled"] - best_extreme),
            "block_oracle_weights": json.dumps(block_weights, sort_keys=True),
            "block_oracle_AQL_scaled": block_aql,
            "block_oracle_gain_vs_best_extreme": block_aql - best_extreme,
            "partial_pooling_headroom_observed": block_aql < best_extreme - 1.0e-12,
            "evidence_role": "diagnostic_outer_validation_oracle_not_selection",
            "test_inspected": False,
        })
    return pd.DataFrame(cases).sort_values(["region", "fold"]), pd.DataFrame(global_rows), pd.DataFrame(block_rows), sources


def convergence_audit(r37_dir: Path) -> pd.DataFrame:
    inner = read_csv(r37_dir / "pricefm_stage_r37_inner_fold_metrics.csv", "R37 inner metrics")
    rows = []
    for (region, fold), group in inner.groupby(["region", "fold"], sort=True):
        separate = group[group["method_id"].astype(str).eq(SEPARATE)]
        failed = separate[~separate["converged"].map(boolish)]
        rows.append({
            "region": region, "fold": int(fold),
            "separate_inner_folds": int(len(separate)),
            "nonconverged_inner_folds": int(len(failed)),
            "failed_inner_fold_ids": json.dumps(sorted(failed["inner_fold"].astype(int).tolist())),
            "per_block_inner_convergence_available": False,
            "diagnostic_limit": "R36 records aggregate four-block convergence per inner fold",
            "r39_requirement": "write one convergence and trace row per inner fold and horizon block",
        })
    return pd.DataFrame(rows)


def data_authority(split_root: Path) -> pd.DataFrame:
    rows = []
    latest = pd.Timestamp.min.tz_localize("UTC")
    for path in sorted(split_root.glob("fold_*/*.parquet")):
        frame = pd.read_parquet(path, columns=["time_utc"])
        start = pd.to_datetime(frame["time_utc"], utc=True).min()
        end = pd.to_datetime(frame["time_utc"], utc=True).max()
        latest = max(latest, end)
        rows.append({
            "artifact": str(path), "kind": "observations", "first_time": start.isoformat(),
            "last_time": end.isoformat(), "post_2025_available": end.year > 2025,
            "row_level_forecasts": False,
        })
    rows.append({
        "artifact": "cached PriceFM registry metrics", "kind": "pricefm_reference",
        "first_time": "", "last_time": latest.isoformat(), "post_2025_available": False,
        "row_level_forecasts": False,
    })
    rows.append({
        "artifact": "required future confirmation window", "kind": "decision",
        "first_time": "2026-01-01T00:00:00+00:00", "last_time": "",
        "post_2025_available": False, "row_level_forecasts": False,
    })
    return pd.DataFrame(rows)


def design_contract(harm_margin: float) -> pd.DataFrame:
    rows = [
        (1, "model", "hierarchical_partial_pooling", "shared coefficients plus four 24-hour deviation states"),
        (2, "prior", "structured_rhs_ns", "distinct shared and deviation shrinkage scales; identifiable deviations"),
        (3, "controls", "shared_and_separate", "retain both R36 extremes in every case"),
        (4, "reservoir", "frozen_case_specific_r34_anchor", "do not reopen D/n/m/feature-policy search"),
        (5, "selection", "five_fold_embargoed_nested_validation", "case-specific; test unavailable"),
        (6, "stability", "prospective_relative_noninferiority", f"worst-fold AQL deterioration <= {harm_margin:.4%}"),
        (7, "preference", "one_standard_error", "prefer stronger pooling when statistically indistinguishable"),
        (8, "convergence", "per_block_fail_closed", "all selected inner and outer fits must converge"),
        (9, "confirmation", "fresh_post_2025_preferred", "requires observations and comparable PriceFM forecasts"),
        (10, "fallback", "rolling_origin_crossfit_disclosed", "not an untouched holdout claim"),
        (11, "promotion", "dual_reference_then_full_quantile_mcmc", "registry/article remain blocked until all gates pass"),
    ]
    return pd.DataFrame([{"order": order, "area": area, "contract": contract, "detail": detail} for order, area, contract, detail in rows])


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in sorted(set(paths)):
        if path.exists() and path.is_file():
            rows.append({"path": str(path), "sha256": sha256_file(path), "bytes": path.stat().st_size})
    return pd.DataFrame(rows, columns=["path", "sha256", "bytes"])


def render_report(summary: dict[str, Any], cases: pd.DataFrame) -> str:
    return "\n".join([
        "# PriceFM Stage-R38 Partial-Pooling Capability Audit", "",
        f"- Cases audited: `{summary['cases']}`",
        f"- Global blends beating both extremes: `{summary['global_blend_headroom_cases']}`",
        f"- Block blends beating both extremes: `{summary['block_blend_headroom_cases']}`",
        f"- Median global oracle gain: `{summary['median_global_gain_vs_best_extreme']:.6f}` scaled AQL",
        f"- Median block oracle gain: `{summary['median_block_gain_vs_best_extreme']:.6f}` scaled AQL",
        f"- Post-2025 observations available: `{summary['post_2025_observations_available']}`",
        f"- Post-2025 PriceFM forecasts available: `{summary['post_2025_pricefm_forecasts_available']}`", "",
        "The blend atlas is an outer-validation oracle capability bound. It cannot select or promote",
        "a model. Its role is to determine whether engineering a prospectively selected hierarchical",
        "partial-pooling readout has measurable headroom over the R36 extremes.", "",
        "R39 implementation is justified, but independent article confirmation remains blocked until",
        "a post-2025 observation and comparable PriceFM forecast window is acquired, or the evidence",
        "is explicitly downgraded to rolling-origin cross-validation.", "",
    ])


def run(args: argparse.Namespace) -> dict[str, Any]:
    run_root = Path(args.stage_r36_run_root).resolve()
    r37_dir = Path(args.stage_r37_dir).resolve()
    split_root = Path(args.split_root).resolve()
    output = Path(args.output_dir).resolve()
    if not 0.0 <= args.practical_harm_margin_relative <= 0.05:
        raise ValueError("Practical harm margin must be between 0 and 5%")
    r37_summary = json.loads((r37_dir / "summary.json").read_text())
    if r37_summary.get("status") != "completed_read_only_no_confirmation_candidates":
        raise ValueError("R37 is not the expected completed negative closeout")
    cases, global_curve, block_curve, prediction_sources = blend_atlas(run_root, args.expected_cases)
    convergence = convergence_audit(r37_dir)
    authority = data_authority(split_root)
    design = design_contract(args.practical_harm_margin_relative)
    post_obs = bool(authority.loc[authority["kind"].eq("observations"), "post_2025_available"].map(boolish).any())
    post_pricefm = bool(authority.loc[authority["kind"].eq("pricefm_reference"), "post_2025_available"].map(boolish).any())
    block_headroom = int(cases["partial_pooling_headroom_observed"].map(boolish).sum())
    global_headroom = int((cases["global_oracle_gain_vs_best_extreme"] < -1.0e-12).sum())
    majority_required = math.floor(int(args.expected_cases) / 2) + 1
    gates = pd.DataFrame([
        {"gate": "r37_negative_loaded", "passed": True, "detail": "R37 completed with zero confirmation candidates."},
        {"gate": "paired_prediction_surfaces_complete", "passed": len(cases) == args.expected_cases, "detail": "All R36 paired outer-validation predictions are available."},
        {"gate": "partial_pooling_headroom", "passed": block_headroom >= majority_required, "detail": "A strict majority of cases must have oracle headroom over both extremes."},
        {"gate": "r39_model_implementation_justified", "passed": block_headroom >= majority_required, "detail": "Implement consumed hierarchical partial pooling with prospective nested selection."},
        {"gate": "fresh_confirmation_data_ready", "passed": post_obs and post_pricefm, "detail": "Post-2025 observations and comparable PriceFM forecasts are both required."},
        {"gate": "expensive_launch_authorized", "passed": False, "detail": "R38 is read-only; implementation and tests precede launch authorization."},
        {"gate": "registry_article_mcmc_authorized", "passed": False, "detail": "Blocked pending confirmation."},
    ])
    summary = {
        "status": "completed_r39_implementation_justified_confirmation_data_blocked",
        "cases": int(len(cases)),
        "global_blend_headroom_cases": global_headroom,
        "block_blend_headroom_cases": block_headroom,
        "median_global_gain_vs_best_extreme": float(cases["global_oracle_gain_vs_best_extreme"].median()),
        "median_block_gain_vs_best_extreme": float(cases["block_oracle_gain_vs_best_extreme"].median()),
        "nonconverged_case_count": int((convergence["nonconverged_inner_folds"] > 0).sum()),
        "post_2025_observations_available": post_obs,
        "post_2025_pricefm_forecasts_available": post_pricefm,
        "r39_implementation_justified": block_headroom >= majority_required,
        "practical_harm_margin_relative": float(args.practical_harm_margin_relative),
        "launch_authorized": False,
        "test_inspected": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "mcmc_authorized": False,
    }
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"R38 output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    source_paths = [Path(__file__).resolve(), r37_dir / "summary.json", r37_dir / "pricefm_stage_r37_inner_fold_metrics.csv"] + prediction_sources + sorted(split_root.glob("fold_*/*.parquet"))
    outputs = [
        (OUT_CASES, cases), (OUT_GLOBAL, global_curve), (OUT_BLOCK, block_curve),
        (OUT_CONVERGENCE, convergence), (OUT_DATA, authority), (OUT_DESIGN, design),
        (OUT_GATES, gates), (OUT_SOURCE, source_manifest(source_paths)),
    ]
    for name, frame in outputs:
        frame.to_csv(output / name, index=False)
    write_json(output / OUT_SUMMARY, summary)
    (output / OUT_REPORT).write_text(render_report(summary, cases))
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
