#!/usr/bin/env python3
"""Close the R93 Ridge screen and prepare the validation-only normal-RHS stage."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_PREP = (
    DATA_ROOT / "authoritative/pricefm_stage_r93_region_frozen_ladder_prep_20260906"
)
DEFAULT_RIDGE_GENERATED = (
    DATA_ROOT / "experiment_grids/pricefm_stage_r93_region_frozen_ridge_20260906"
)
DEFAULT_OUTPUT = (
    DATA_ROOT / "authoritative/pricefm_stage_r93_ridge_closeout_rhs_prep_20260906"
)
DEFAULT_RHS_GENERATED = (
    DATA_ROOT / "experiment_grids/pricefm_stage_r93_region_frozen_rhs_20260906"
)
DEFAULT_RHS_RUNS = DATA_ROOT / "runs/pricefm_stage_r93_region_frozen_rhs_20260906"
GRID_BLOCK = "pricefm_desn_experiment_grid"
RIDGE_METHOD = "normal_scaled_ridge"
RHS_METHOD = "normal_rhs_ns"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=DEFAULT_PREP)
    p.add_argument("--ridge-grid", type=Path, default=None)
    p.add_argument("--ridge-generated-root", type=Path, default=DEFAULT_RIDGE_GENERATED)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--rhs-grid", type=Path, default=None)
    p.add_argument("--rhs-generated-root", type=Path, default=DEFAULT_RHS_GENERATED)
    p.add_argument("--rhs-run-root", type=Path, default=DEFAULT_RHS_RUNS)
    p.add_argument("--target-region", default="SE_2")
    p.add_argument("--folds", default="101,102,103")
    p.add_argument("--expected-candidates", type=int, default=240)
    p.add_argument("--top-k", type=int, default=30)
    p.add_argument("--tau0-values", default="1e-4,1e-3,1e-2")
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--allow-fixture-counts", action="store_true")
    return p


def parse_ints(value: str) -> list[int]:
    values = [int(x.strip()) for x in value.split(",") if x.strip()]
    if not values or len(values) != len(set(values)):
        raise ValueError("folds must be a nonempty unique integer list")
    return values


def parse_floats(value: str) -> list[float]:
    values = [float(x.strip()) for x in value.split(",") if x.strip()]
    if not values or len(values) != len(set(values)) or any(x <= 0 for x in values):
        raise ValueError("tau0-values must be a nonempty unique positive list")
    return values


def boolish(value: Any) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"YAML is not a mapping: {path}")
    return payload


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def write_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def refuse_outputs(output: Path, force: bool) -> None:
    if output.exists() and any(output.iterdir()) and not force:
        raise FileExistsError(f"{output} is nonempty; use --force true to replace outputs")
    output.mkdir(parents=True, exist_ok=True)


def resolve_path(value: Any) -> Path:
    path = Path(str(value))
    return path if path.is_absolute() else repo_path(path)


def source_row(path: Path, role: str) -> dict[str, Any]:
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def collect_ridge_results(
    candidates: pd.DataFrame,
    manifest: pd.DataFrame,
    folds: list[int],
    target_region: str,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    candidate_ids = candidates["candidate_id"].astype(str)
    manifest_ids = manifest["id"].astype(str)
    if candidate_ids.duplicated().any() or manifest_ids.duplicated().any():
        raise RuntimeError("candidate and generated manifests must have unique IDs")
    if set(candidate_ids) != set(manifest_ids):
        raise RuntimeError("candidate and generated Ridge manifest IDs do not match exactly")

    manifest_by_id = manifest.set_index(manifest_ids, drop=False)
    rows: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    for candidate in candidates.itertuples(index=False):
        candidate_id = str(candidate.candidate_id)
        generated = manifest_by_id.loc[candidate_id]
        run_dir = resolve_path(generated.run_dir)
        fold_values: list[float] = []
        feature_counts: list[int] = []
        for fold in folds:
            model = run_dir / "cells" / f"region={target_region}" / f"fold={fold}" / "model"
            metric_path = model / "metric_summary.csv"
            method_path = model / "model_method_summary.csv"
            for path in (metric_path, method_path):
                if not path.is_file() or path.stat().st_size == 0:
                    raise RuntimeError(f"incomplete Ridge result: {path}")
            metrics = pd.read_csv(metric_path)
            methods = pd.read_csv(method_path)
            required_metric = {"method_id", "split", "unit", "AQL"}
            required_method = {"method_id", "converged", "n_features"}
            if not required_metric.issubset(metrics) or not required_method.issubset(methods):
                raise RuntimeError(f"malformed Ridge result in {model}")
            if metrics["split"].astype(str).str.lower().eq("test").any():
                raise RuntimeError(f"test metrics are forbidden in R93 selection: {metric_path}")
            selected = metrics[
                metrics.method_id.astype(str).eq(RIDGE_METHOD)
                & metrics.split.astype(str).eq("val")
                & metrics.unit.astype(str).eq("original")
            ]
            method = methods[methods.method_id.astype(str).eq(RIDGE_METHOD)]
            if len(selected) != 1 or len(method) != 1:
                raise RuntimeError(f"expected one Ridge validation/method row in {model}")
            if not boolish(method.iloc[0].converged):
                raise RuntimeError(f"Ridge method is not converged: {model}")
            aql = float(pd.to_numeric(selected.iloc[0].AQL, errors="coerce"))
            n_features = int(pd.to_numeric(method.iloc[0].n_features, errors="coerce"))
            if not math.isfinite(aql) or aql < 0 or n_features <= 0:
                raise RuntimeError(f"nonfinite Ridge metric or feature count in {model}")
            fold_values.append(aql)
            feature_counts.append(n_features)
            rows.append({
                "candidate_id": candidate_id,
                "region": target_region,
                "inner_fold": fold,
                "method_id": RIDGE_METHOD,
                "validation_AQL_original": aql,
                "converged": True,
                "n_features": n_features,
                "metric_path": str(metric_path),
                "method_summary_path": str(method_path),
            })
            sources.extend([
                source_row(metric_path, "ridge_validation_metric"),
                source_row(method_path, "ridge_method_summary"),
            ])
        if len(fold_values) != len(folds):
            raise RuntimeError(f"candidate {candidate_id} lacks a complete inner-fold surface")
    return pd.DataFrame(rows), sources


def rank_candidates(candidates: pd.DataFrame, cell_results: pd.DataFrame) -> pd.DataFrame:
    aggregate = cell_results.groupby("candidate_id", as_index=False).agg(
        median_validation_AQL=("validation_AQL_original", "median"),
        max_validation_AQL=("validation_AQL_original", "max"),
        mean_validation_AQL=("validation_AQL_original", "mean"),
        n_inner_folds=("inner_fold", "nunique"),
        n_state_features=("n_features", "max"),
    )
    wide = cell_results.pivot(
        index="candidate_id", columns="inner_fold", values="validation_AQL_original"
    ).rename(columns=lambda fold: f"fold_{int(fold)}_validation_AQL")
    aggregate = aggregate.merge(wide.reset_index(), on="candidate_id", validate="one_to_one")
    keep = [
        "candidate_id", "region", "candidate_role", "source_fold", "source_experiment_id",
        "feature_policy", "lag_window", "depth", "units", "feature_dim", "alpha",
        "rho", "input_scale", "state_output", "seed", "semantic_fingerprint",
        "test_access_authorized",
    ]
    aggregate = aggregate.merge(candidates[keep], on="candidate_id", validate="one_to_one")
    aggregate["sum_units"] = aggregate.units.map(
        lambda value: sum(json.loads(value) if isinstance(value, str) else value)
    )
    aggregate = aggregate.sort_values([
        "median_validation_AQL", "max_validation_AQL", "n_state_features",
        "sum_units", "candidate_id",
    ], kind="stable").reset_index(drop=True)
    aggregate.insert(0, "ridge_rank", range(1, len(aggregate) + 1))
    aggregate["ranking_split"] = "inner_validation"
    aggregate["ranking_unit"] = "original"
    aggregate["ranking_metric"] = "AQL"
    aggregate["test_metrics_loaded_or_used"] = False
    return aggregate


def tau_token(value: float) -> str:
    return f"{value:.0e}".replace("-", "m").replace("+", "p")


def make_rhs_grid(
    ridge_grid: dict[str, Any],
    ranked: pd.DataFrame,
    top_k: int,
    tau0_values: list[float],
    output: Path,
    rhs_generated_root: Path,
    rhs_run_root: Path,
) -> tuple[dict[str, Any], pd.DataFrame, Path, Path]:
    source_grid = ridge_grid[GRID_BLOCK]
    experiments = {str(row["id"]): row for row in source_grid["experiments"]}
    selected = ranked.head(top_k).copy()

    base_data_source = resolve_path(source_grid["base"]["data_config"])
    base_full_source = resolve_path(source_grid["base"]["full_config"])
    base_data = load_yaml(base_data_source)
    base_full = load_yaml(base_full_source)
    base_data_path = output / "configs/base/pricefm_stage_r93_rhs_observational_data.yaml"
    base_full_path = output / "configs/base/pricefm_stage_r93_rhs_only_full.yaml"
    write_yaml(base_data_path, base_data)
    full = base_full["pricefm_desn_full"]
    full["data_config"] = str(base_data_path)
    full.setdefault("normal", {}).update({
        "enabled": True,
        "prior_types": ["rhs_ns"],
        "predictive_quantile_mode": "analytic_normal",
    })
    full.setdefault("qdesn_vb", {})["enabled"] = False
    full.setdefault("exact_equivalence", {})["enabled"] = False
    full["warm_start"] = {"enabled": False}
    full["nested_validation"] = {"enabled": False}
    write_yaml(base_full_path, base_full)

    arms: list[dict[str, Any]] = []
    output_experiments: list[dict[str, Any]] = []
    for selected_row in selected.itertuples(index=False):
        parent_id = str(selected_row.candidate_id)
        if parent_id not in experiments:
            raise RuntimeError(f"selected Ridge candidate absent from grid: {parent_id}")
        for tau0 in tau0_values:
            fingerprint = hashlib.sha256(
                f"{parent_id}|normal_rhs_ns|{tau0:.17g}".encode("utf-8")
            ).hexdigest()
            experiment_id = (
                f"r93_{str(selected_row.region).lower().replace('_', '')}_rhs_"
                f"r{int(selected_row.ridge_rank):02d}_t{tau_token(tau0)}_{fingerprint[:10]}"
            )
            exp = copy.deepcopy(experiments[parent_id])
            exp.update({
                "id": experiment_id,
                "stage": "pricefm_stage_r93_normal_rhs_observational_refit",
                "tau0": float(tau0),
                "normal": {
                    "enabled": True,
                    "prior_types": ["rhs_ns"],
                    "predictive_quantile_mode": "analytic_normal",
                },
                "qdesn_vb": {"enabled": False},
                "exact_equivalence": {"enabled": False},
                "stage_r93_candidate_role": "ridge_top30_rhs_coarse_tau0",
                "stage_r93_source_experiment_id": parent_id,
                "stage_r93_parent_ridge_candidate_id": parent_id,
                "stage_r93_ridge_rank": int(selected_row.ridge_rank),
                "stage_r93_rhs_tau0_phase": "coarse",
                "stage_r93_semantic_fingerprint": fingerprint,
                "rationale": "R93 top-30 Ridge geometry refit under normal RHS_NS on observational validation only.",
            })
            output_experiments.append(exp)
            arms.append({
                "experiment_id": experiment_id,
                "parent_ridge_candidate_id": parent_id,
                "ridge_rank": int(selected_row.ridge_rank),
                "region": selected_row.region,
                "feature_policy": selected_row.feature_policy,
                "lag_window": int(selected_row.lag_window),
                "depth": int(selected_row.depth),
                "units": selected_row.units,
                "alpha": float(selected_row.alpha),
                "rho": float(selected_row.rho),
                "input_scale": float(selected_row.input_scale),
                "state_output": selected_row.state_output,
                "seed": int(selected_row.seed),
                "tau0": float(tau0),
                "selection_split": "inner_validation",
                "selection_unit": "original",
                "selection_metric": "AQL",
                "test_access_authorized": False,
                "launch_authorized": False,
                "semantic_fingerprint": fingerprint,
            })

    payload = copy.deepcopy(ridge_grid)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_r93_region_frozen_rhs_20260906"
    grid["purpose"] = (
        "Refit exactly the validation-selected R93 Ridge top 30 under normal RHS_NS "
        "and coarse tau0 on the same three observational windows."
    )
    grid["base"] = {
        "data_config": str(base_data_path),
        "full_config": str(base_full_path),
        "generated_root": str(rhs_generated_root),
        "run_root": str(rhs_run_root),
    }
    grid["fixed"]["normal"] = {
        "enabled": True,
        "prior_types": ["rhs_ns"],
        "predictive_quantile_mode": "analytic_normal",
    }
    grid["fixed"]["qdesn_vb"] = {"enabled": False}
    grid["fixed"]["exact_equivalence"] = {"enabled": False}
    grid["experiments"] = output_experiments
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "prepared_not_authorized": {
            "experiment_jobs": 20,
            "cell_jobs": 1,
            "build_windows": True,
            "resume": True,
            "force": False,
            "dry_run": False,
            "authorized": False,
            "note": "Do not invoke until Ridge closeout is reviewed and the user authorizes R93 RHS.",
        }
    }
    return payload, pd.DataFrame(arms), base_data_path, base_full_path


def render_report(summary: dict[str, Any], selected: pd.DataFrame) -> str:
    lines = [
        "# PriceFM Stage-R93 Ridge Closeout and RHS Preparation",
        "",
        "## Decision",
        "",
        f"All {summary['ridge_cell_results']} Ridge observational-window results are complete, finite, and converged. ",
        f"The deterministic selector advances exactly {summary['ridge_top_k']} of {summary['ridge_candidates']} geometries.",
        "No test/forecast metric was loaded or used. The RHS grid is materialized but launch authorization is false.",
        "",
        "## Selected Ridge Geometries",
        "",
        "| Rank | Candidate | Policy | D | Units | m | Median val AQL | Worst val AQL |",
        "|---:|---|---|---:|---|---:|---:|---:|",
    ]
    for row in selected.itertuples(index=False):
        lines.append(
            f"| {int(row.ridge_rank)} | `{row.candidate_id}` | `{row.feature_policy}` | "
            f"{int(row.depth)} | `{row.units}` | {int(row.lag_window)} | "
            f"{row.median_validation_AQL:.6f} | {row.max_validation_AQL:.6f} |"
        )
    lines.extend([
        "",
        "## Next Gate",
        "",
        "Run the coarse normal-RHS grid only after explicit authorization. Select one geometry/tau0 by "
        "median inner-validation AQL, worst-window AQL, complexity, and stable ID, with a convergence guard. "
        "A local tau0 refinement is conditional and may not use any forecast/test window.",
        "",
        "Registry, article, quantile, joint, and MCMC work remain blocked.",
        "",
    ])
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    folds = parse_ints(args.folds)
    tau0_values = parse_floats(args.tau0_values)
    prep = args.prep_dir.resolve()
    ridge_grid_path = (args.ridge_grid or (prep / "pricefm_stage_r93_ridge_grid.yaml")).resolve()
    ridge_manifest_path = (args.ridge_generated_root / "manifest.csv").resolve()
    candidate_path = prep / "pricefm_stage_r93_ridge_candidate_manifest.csv"
    for path in (ridge_grid_path, ridge_manifest_path, candidate_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)

    candidates = pd.read_csv(candidate_path)
    manifest = pd.read_csv(ridge_manifest_path)
    if len(candidates) != int(args.expected_candidates):
        raise RuntimeError(
            f"expected {args.expected_candidates} Ridge candidates, found {len(candidates)}"
        )
    if not args.allow_fixture_counts:
        if int(args.expected_candidates) != 240 or folds != [101, 102, 103] or int(args.top_k) != 30:
            raise RuntimeError("production R93 contract requires 240 candidates, folds 101-103, and top-k 30")
        controls = candidates[candidates.candidate_role.eq("authoritative_fold_geometry_control")]
        if sorted(controls.source_fold.astype(int).tolist()) != [1, 2, 3]:
            raise RuntimeError("all three authoritative fold controls must be present")
    if not (0 < int(args.top_k) <= len(candidates)):
        raise ValueError("top-k must be positive and no larger than candidate count")
    if candidates.test_access_authorized.map(boolish).any():
        raise RuntimeError("Ridge candidate manifest authorizes forbidden test access")

    ridge_grid = load_yaml(ridge_grid_path)
    grid = ridge_grid[GRID_BLOCK]
    if list(grid["scope"]["splits"]) != ["train", "val"]:
        raise RuntimeError("Ridge grid must expose train/val only")
    if [int(x) for x in grid["scope"]["folds"]] != folds:
        raise RuntimeError("Ridge grid folds differ from the selection contract")
    normal = grid["fixed"].get("normal", {})
    if normal.get("prior_types") != ["scaled_ridge"] or grid["fixed"].get("qdesn_vb", {}).get("enabled") is not False:
        raise RuntimeError("source grid is not the R93 Ridge-only contract")

    cell_results, runtime_sources = collect_ridge_results(
        candidates, manifest, folds, str(args.target_region)
    )
    ranked = rank_candidates(candidates, cell_results)
    if not ranked.n_inner_folds.eq(len(folds)).all():
        raise RuntimeError("not every candidate has all inner folds")

    output = args.output_dir.resolve()
    refuse_outputs(output, bool(args.force))
    rhs_grid, rhs_manifest, base_data, base_full = make_rhs_grid(
        ridge_grid, ranked, int(args.top_k), tau0_values, output,
        args.rhs_generated_root.resolve(), args.rhs_run_root.resolve(),
    )
    rhs_grid_path = (args.rhs_grid or (output / "pricefm_stage_r93_rhs_grid.yaml")).resolve()

    ranking_path = output / "pricefm_stage_r93_ridge_validation_ranking.csv"
    cell_path = output / "pricefm_stage_r93_ridge_validation_cell_metrics.csv"
    selected_path = output / "pricefm_stage_r93_ridge_top30.csv"
    rhs_manifest_path = output / "pricefm_stage_r93_rhs_coarse_launch_manifest.csv"
    gates_path = output / "pricefm_stage_r93_ridge_to_rhs_gates.csv"
    report_path = output / "pricefm_stage_r93_ridge_closeout_rhs_prep_report.md"
    source_manifest_path = output / "source_manifest.csv"
    summary_path = output / "summary.json"

    selected = ranked.head(int(args.top_k)).copy()
    write_csv(cell_path, cell_results)
    write_csv(ranking_path, ranked)
    write_csv(selected_path, selected)
    write_csv(rhs_manifest_path, rhs_manifest)
    write_yaml(rhs_grid_path, rhs_grid)

    gates = pd.DataFrame([
        ("candidate_surface_complete", len(ranked) == len(candidates), len(ranked), len(candidates)),
        ("all_inner_fold_cells_complete", len(cell_results) == len(candidates) * len(folds), len(cell_results), len(candidates) * len(folds)),
        ("all_ridge_methods_converged", cell_results.converged.map(boolish).all(), int(cell_results.converged.map(boolish).sum()), len(cell_results)),
        ("no_test_metrics_loaded", True, 0, 0),
        ("top_k_exact", len(selected) == int(args.top_k), len(selected), int(args.top_k)),
        ("rhs_arm_count_exact", len(rhs_manifest) == int(args.top_k) * len(tau0_values), len(rhs_manifest), int(args.top_k) * len(tau0_values)),
        ("rhs_train_val_only", rhs_grid[GRID_BLOCK]["scope"]["splits"] == ["train", "val"], 1, 1),
        ("launch_authorization_false", rhs_grid[GRID_BLOCK]["launch"]["prepared_not_authorized"]["authorized"] is False, 1, 1),
    ], columns=["gate", "passed", "observed", "expected"])
    if not gates.passed.map(boolish).all():
        raise RuntimeError("R93 Ridge-to-RHS gates failed")
    write_csv(gates_path, gates)

    fixed_sources = [
        source_row(candidate_path, "ridge_candidate_manifest"),
        source_row(ridge_grid_path, "ridge_grid_contract"),
        source_row(ridge_manifest_path, "ridge_generated_manifest"),
    ]
    source_manifest = pd.DataFrame(fixed_sources + runtime_sources).drop_duplicates("path")
    write_csv(source_manifest_path, source_manifest.sort_values(["role", "path"]))

    summary = {
        "stage": "pricefm_stage_r93_ridge_closeout_rhs_prep",
        "status": "completed_rhs_prepared_not_launched",
        "target_region": str(args.target_region),
        "ridge_candidates": len(ranked),
        "ridge_cell_results": len(cell_results),
        "ridge_top_k": len(selected),
        "rhs_tau0_values": tau0_values,
        "rhs_experiments": len(rhs_manifest),
        "planned_rhs_fits": len(rhs_manifest) * len(folds),
        "selection_uses_forecast_or_test_window": False,
        "all_ridge_methods_converged": True,
        "launch_authorized": False,
        "launcher_invoked": False,
        "ridge_winner": str(ranked.iloc[0].candidate_id),
        "ridge_winner_median_validation_AQL": float(ranked.iloc[0].median_validation_AQL),
        "outputs": {
            "cell_metrics": str(cell_path),
            "ranking": str(ranking_path),
            "selected_top30": str(selected_path),
            "rhs_manifest": str(rhs_manifest_path),
            "rhs_grid": str(rhs_grid_path),
            "gates": str(gates_path),
            "report": str(report_path),
            "source_manifest": str(source_manifest_path),
            "base_data_config": str(base_data),
            "base_full_config": str(base_full),
        },
    }
    report_path.write_text(render_report(summary, selected))
    write_json(summary_path, summary)
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
