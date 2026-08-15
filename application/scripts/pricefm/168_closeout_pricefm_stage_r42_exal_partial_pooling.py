#!/usr/bin/env python3
"""Close out R41 exAL pooling and audit its realized R33/R34 contract."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_PREP = DATA / "authoritative/pricefm_stage_r41_exal_partial_pooling_launch_prep_20260806"
DEFAULT_GRID = DATA / "experiment_grids/pricefm_stage_r41_exal_partial_pooling_20260806"
DEFAULT_RUNS = DATA / "runs/pricefm_stage_r41_exal_partial_pooling_20260806"
DEFAULT_R37 = DATA / "authoritative/pricefm_stage_r37_nested_horizon_readout_closeout_20260805"
DEFAULT_R33_GRID = DATA / "experiment_grids/pricefm_stage_r33_lean_capacity_history_20260722"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r42_exal_partial_pooling_closeout_20260807"
BLOCKS = ["1-24", "25-48", "49-72", "73-96"]
SHARED = "qdesn_exal_rhs_ns_exact_chunked"
SEPARATE = SHARED + "_horizon_separate"
PRESERVED_FIELDS = [
    "lag_window", "feature_map", "feature_policy", "feature_dim", "projection_scale",
    "depth", "units", "alpha", "rho", "input_scale", "recurrent_sparsity",
    "state_output", "tau0", "seed", "horizon_focus", "horizon_weight_multiplier",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=DEFAULT_PREP)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUNS)
    p.add_argument("--stage-r37-dir", type=Path, default=DEFAULT_R37)
    p.add_argument("--stage-r33-grid", type=Path, default=DEFAULT_R33_GRID)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--expected-cases", type=int, default=6)
    p.add_argument("--harm-margin", type=float, default=0.005)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_artifact_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ARTIFACT_REPO / path


def boolish(value) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes", "completed"}


def model_dir(root: Path, row) -> Path:
    return root / str(row.id) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}" / "model"


def adapter_dir(root: Path, row) -> Path:
    return root / str(row.id) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}" / "adapter"


def select_block(metrics: pd.DataFrame, convergence: pd.DataFrame, block: str, harm_margin: float) -> dict:
    group = metrics[metrics["horizon_group"].astype(str).eq(block)].copy()
    conv = convergence[convergence["horizon_group"].astype(str).eq(block)]
    shared_ok = bool(group["shared_converged"].map(boolish).all())
    separate_ok = bool(conv["converged"].map(boolish).all())
    stats = group.groupby("separate_weight")["AQL_scaled"].agg(["median", "std", "count"]).reset_index()
    stats["standard_error"] = stats["std"].fillna(0.0) / np.sqrt(stats["count"])
    stats["eligible"] = shared_ok & (stats["separate_weight"].eq(0) | separate_ok)
    eligible = stats[stats["eligible"]]
    if eligible.empty:
        raise RuntimeError(f"No eligible pooling weight for {block}")
    raw = eligible.loc[eligible["median"].idxmin()]
    threshold = float(raw["median"] + raw["standard_error"])
    selected = eligible[eligible["median"].le(threshold + 1e-15)].sort_values("separate_weight").iloc[0]
    weight = float(selected["separate_weight"])
    paired = group[group["separate_weight"].eq(weight)][["inner_fold", "AQL_scaled"]].merge(
        group[group["separate_weight"].eq(0)][["inner_fold", "AQL_scaled"]],
        on="inner_fold", suffixes=("_selected", "_shared"),
    )
    relative = paired["AQL_scaled_selected"] / paired["AQL_scaled_shared"] - 1.0
    return {
        "horizon_group": block,
        "raw_best_weight": float(raw["separate_weight"]),
        "raw_best_median_AQL_scaled": float(raw["median"]),
        "raw_best_standard_error": float(raw["standard_error"]),
        "one_se_threshold": threshold,
        "selected_weight": weight,
        "selected_median_AQL_scaled": float(selected["median"]),
        "shared_all_folds_converged": shared_ok,
        "separate_all_folds_converged": separate_ok,
        "selected_convergence_pass": shared_ok and (weight == 0 or separate_ok),
        "max_relative_harm": float(relative.max()),
        "harm_guard_pass": bool(relative.le(harm_margin + 1e-12).all()),
    }


def pooled_outer(model: Path, adapter: Path, weights: dict[str, float]) -> tuple[float, float, float]:
    predictions = pd.read_csv(model / "model_predictions_scaled.csv")
    observed = pd.read_csv(adapter / "rows_val.csv")[["origin_id", "horizon", "y_scaled"]]
    shared = predictions[predictions["method_id"].eq(SHARED)]
    separate = predictions[predictions["method_id"].eq(SEPARATE)]
    paired = shared.merge(
        separate, on=["split", "origin_id", "horizon", "tau"], suffixes=("_shared", "_separate")
    ).merge(observed, on=["origin_id", "horizon"])
    paired["horizon_group"] = pd.cut(paired["horizon"], [0, 24, 48, 72, 96], labels=BLOCKS)
    paired["weight"] = paired["horizon_group"].map(weights).astype(float)
    paired["pooled"] = (
        paired["pred_scaled_shared"] * (1 - paired["weight"])
        + paired["pred_scaled_separate"] * paired["weight"]
    )
    aql = lambda pred: float(np.mean(0.5 * np.abs(paired["y_scaled"] - pred)))
    return aql(paired["pooled"]), aql(paired["pred_scaled_shared"]), aql(paired["pred_scaled_separate"])


def full_config(path: Path) -> dict:
    return yaml.safe_load(path.read_text())["pricefm_desn_full"]


def same_manifest_value(left, right) -> bool:
    if pd.isna(left) and pd.isna(right):
        return True
    return str(left) == str(right)


def scalar_scope(value):
    if isinstance(value, str) and value.strip().startswith("["):
        return json.loads(value)[0]
    if isinstance(value, (list, tuple)):
        return value[0]
    return value


def npz_contract(left: Path, right: Path) -> tuple[bool, str]:
    with np.load(left) as left_npz, np.load(right) as right_npz:
        if left_npz.files != right_npz.files:
            return False, "array_keys_differ"
        differences = []
        for key in left_npz.files:
            a, b = left_npz[key], right_npz[key]
            if a.shape != b.shape:
                differences.append(f"{key}:shape={a.shape}!={b.shape}")
            elif not np.array_equal(a, b):
                differences.append(f"{key}:values_differ")
        return not differences, ";".join(differences)


def realized_wiring_row(r41_row, r33_row) -> tuple[dict, list[Path]]:
    r33_run = resolve_artifact_path(r33_row.run_dir)
    r41_run = resolve_artifact_path(r41_row.run_dir)
    r33_cell = r33_run / "cells" / f"region={r41_row.region}" / f"fold={int(r41_row.fold)}"
    r41_cell = r41_run / "cells" / f"region={r41_row.region}" / f"fold={int(r41_row.fold)}"
    r33_full_path = resolve_artifact_path(r33_row.full_config)
    r41_full_path = resolve_artifact_path(r41_row.full_config)
    r33_cfg, r41_cfg = full_config(r33_full_path), full_config(r41_full_path)
    preserved = {field: same_manifest_value(getattr(r33_row, field), getattr(r41_row, field)) for field in PRESERVED_FIELDS}
    paths = {
        "rows_train": (r33_cell / "adapter/rows_train.csv", r41_cell / "adapter/rows_train.csv"),
        "rows_val": (r33_cell / "adapter/rows_val.csv", r41_cell / "adapter/rows_val.csv"),
        "feature_map": (r33_cell / "adapter/feature_map_matrix.npz", r41_cell / "adapter/feature_map_matrix.npz"),
        "training_weights": (r33_cell / "model/training_weight_summary.csv", r41_cell / "model/training_weight_summary.csv"),
    }
    hashes = {name: (sha256(pair[0]), sha256(pair[1])) for name, pair in paths.items()}
    feature_map_equal, feature_map_difference = npz_contract(*paths["feature_map"])
    r33_weight = r33_cfg["training"]["horizon_weighting"]
    r41_weight = r41_cfg["training"]["horizon_weighting"]
    spatial_r33 = r33_cfg["adapter"].get("spatial", {})
    spatial_r41 = r41_cfg["adapter"].get("spatial", {})
    spatial_equal = spatial_r33 == spatial_r41
    rows_and_weight_pass = (
        all(preserved.values())
        and hashes["rows_train"][0] == hashes["rows_train"][1]
        and hashes["rows_val"][0] == hashes["rows_val"][1]
        and hashes["training_weights"][0] == hashes["training_weights"][1]
    )
    row = {
        "experiment_id": r41_row.id,
        "region": r41_row.region,
        "fold": int(r41_row.fold),
        "source_r34_experiment_id": r41_row.source_r34_experiment_id,
        "preserved_manifest_fields_pass": all(preserved.values()),
        "preserved_manifest_field_failures": ";".join(k for k, value in preserved.items() if not value),
        "rows_train_sha256_r33": hashes["rows_train"][0],
        "rows_train_sha256_r41": hashes["rows_train"][1],
        "rows_train_identical": hashes["rows_train"][0] == hashes["rows_train"][1],
        "rows_val_sha256_r33": hashes["rows_val"][0],
        "rows_val_sha256_r41": hashes["rows_val"][1],
        "rows_val_identical": hashes["rows_val"][0] == hashes["rows_val"][1],
        "feature_map_sha256_r33": hashes["feature_map"][0],
        "feature_map_sha256_r41": hashes["feature_map"][1],
        "feature_map_identical": feature_map_equal,
        "feature_map_difference": feature_map_difference,
        "spatial_config_identical": spatial_equal,
        "r33_spatial_config": json.dumps(spatial_r33, sort_keys=True),
        "r41_spatial_config": json.dumps(spatial_r41, sort_keys=True),
        "training_weight_sha256_r33": hashes["training_weights"][0],
        "training_weight_sha256_r41": hashes["training_weights"][1],
        "training_weight_identical": hashes["training_weights"][0] == hashes["training_weights"][1],
        "r33_readout_interaction": r33_cfg["adapter"].get("readout_interaction", "none"),
        "r41_readout_interaction": r41_cfg["adapter"].get("readout_interaction", "none"),
        "readout_difference_intentional": (
            r33_cfg["adapter"].get("readout_interaction") == "horizon_block"
            and r41_cfg["adapter"].get("readout_interaction", "none") == "none"
        ),
        "r33_warm_start_enabled": bool(r33_cfg.get("warm_start", {}).get("enabled", False)),
        "r41_warm_start_enabled": bool(r41_cfg.get("warm_start", {}).get("enabled", False)),
        "r33_normal_enabled": bool(r33_cfg.get("normal", {}).get("enabled", True)),
        "r41_normal_enabled": bool(r41_cfg.get("normal", {}).get("enabled", True)),
        "r33_likelihoods": json.dumps(r33_cfg["qdesn_vb"]["likelihoods"]),
        "r41_likelihoods": json.dumps(r41_cfg["qdesn_vb"]["likelihoods"]),
        "r33_max_expansion_factor": int(r33_weight.get("max_expansion_factor", 0)),
        "r41_max_expansion_factor": int(r41_weight.get("max_expansion_factor", 0)),
        "realized_rows_and_weight_contract_pass": rows_and_weight_pass,
        "realized_data_reservoir_weight_contract_pass": rows_and_weight_pass and feature_map_equal and spatial_equal,
        "nested_al_to_exal_warm_start_consumed": False,
        "r43_spatial_repair_required": not (feature_map_equal and spatial_equal),
        "r43_warm_start_repair_required": True,
        "r43_repair_required": rows_and_weight_pass,
        "r43_repair_scope": (
            "restore_selected_r33_spatial_information_set_and_nested_normal_to_al_to_exal_initialization_keep_interaction_none"
            if not (feature_map_equal and spatial_equal)
            else "nested_normal_to_al_to_exal_initialization_keep_interaction_none"
        ),
        "test_inspected": False,
    }
    source_paths = [r33_full_path, r41_full_path] + [path for pair in paths.values() for path in pair]
    return row, source_paths


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = args.prep_dir / "pricefm_stage_r41_launch_manifest.csv"
    status_path = args.grid_root / "launch_status.csv"
    r37_path = args.stage_r37_dir / "pricefm_stage_r37_case_closeout.csv"
    r33_manifest_path = args.stage_r33_grid / "manifest.csv"
    manifest = pd.read_csv(manifest_path)
    if "region" not in manifest:
        manifest["region"] = manifest["regions"].map(scalar_scope)
    if "fold" not in manifest:
        manifest["fold"] = manifest["folds"].map(scalar_scope).astype(int)
    status = pd.read_csv(status_path)
    r37 = pd.read_csv(r37_path)
    r33_manifest = pd.read_csv(r33_manifest_path).set_index("id")
    complete = status["status"].eq("completed") & status["return_code"].eq(0)
    gates = [
        ("expected_cases", len(manifest) == args.expected_cases, len(manifest)),
        ("unique_cases", manifest["id"].nunique() == args.expected_cases, manifest["id"].nunique()),
        ("completed_zero_exit", len(status) == args.expected_cases and bool(complete.all()), int(complete.sum())),
        ("exal_anchors_only", manifest["source_r34_selected_method"].eq(SHARED).all(), "exAL"),
        ("test_quarantined", manifest["test_metrics_role"].eq("quarantined_not_loaded").all(), "validation only"),
    ]
    completion = pd.DataFrame(gates, columns=["gate", "passed", "observed"])
    completion.to_csv(output / "pricefm_stage_r42_completion_audit.csv", index=False)
    if not completion["passed"].all():
        raise RuntimeError("R41 completion gates failed")

    r37_index = r37.assign(key=r37["experiment_id"].str.replace("r36_", "", regex=False)).set_index("key")
    block_rows, case_rows, wiring_rows = [], [], []
    sources = [manifest_path, status_path, r37_path, r33_manifest_path, Path(__file__).resolve()]
    for row in manifest.itertuples(index=False):
        model, adapter = model_dir(args.run_root, row), adapter_dir(args.run_root, row)
        metric_path = model / "nested_partial_pooling_metrics.csv"
        conv_path = model / "nested_partial_pooling_convergence.csv"
        metrics, convergence = pd.read_csv(metric_path), pd.read_csv(conv_path)
        if set(metrics["likelihood_family"]) != {"exal"} or set(metrics["tau"].astype(float)) != {0.5}:
            raise ValueError(f"Unexpected R41 likelihood surface: {row.id}")
        selected = []
        for block in BLOCKS:
            result = select_block(metrics, convergence, block, args.harm_margin)
            block_rows.append({"experiment_id": row.id, "region": row.region, "fold": int(row.fold), **result})
            selected.append(result)
        weights = {item["horizon_group"]: item["selected_weight"] for item in selected}
        pooled_scaled, shared_scaled, separate_scaled = pooled_outer(model, adapter, weights)
        metric_summary_path = model / "metric_summary.csv"
        metric_summary = pd.read_csv(metric_summary_path)
        if set(metric_summary["split"]) != {"val"}:
            raise ValueError(f"Test quarantine violated: {row.id}")
        shared_original = float(metric_summary[(metric_summary["method_id"].eq(SHARED)) & (metric_summary["unit"].eq("original"))]["AQL"].iloc[0])
        scale = shared_original / shared_scaled
        anchor = r37_index.loc[str(row.id).replace("r41_", "", 1)]
        pooled_original = pooled_scaled * scale
        convergence_pass = all(item["selected_convergence_pass"] for item in selected)
        harm_pass = all(item["harm_guard_pass"] for item in selected)
        improves_shared = pooled_original < shared_original - 1e-12
        improves_r34 = pooled_original < float(anchor["r34_anchor_val_AQL"]) - 1e-12
        eligible = convergence_pass and harm_pass and improves_shared and improves_r34
        case_rows.append({
            "experiment_id": row.id, "region": row.region, "fold": int(row.fold),
            "source_r34_experiment_id": anchor["source_r34_experiment_id"],
            "source_r34_selected_method": anchor["source_r34_selected_method"],
            **{f"weight_{block.replace('-', '_')}": weights[block] for block in BLOCKS},
            "selected_convergence_pass": convergence_pass, "harm_guard_pass": harm_pass,
            "pooled_outer_val_AQL": pooled_original, "shared_outer_val_AQL": shared_original,
            "separate_outer_val_AQL": separate_scaled * scale,
            "r34_anchor_val_AQL": float(anchor["r34_anchor_val_AQL"]),
            "pooled_minus_shared": pooled_original - shared_original,
            "pooled_minus_r34_anchor": pooled_original - float(anchor["r34_anchor_val_AQL"]),
            "outer_improves_paired_shared": improves_shared, "outer_improves_r34_anchor": improves_r34,
            "full_quantile_confirmation_eligible": eligible,
            "decision": "eligible_for_full_quantile_confirmation" if eligible else "blocked_r41_promotion_gate",
            "test_inspected": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "mcmc_authorized": False,
        })
        wiring, wiring_sources = realized_wiring_row(row, r33_manifest.loc[row.source_r34_experiment_id])
        wiring_rows.append(wiring)
        sources.extend(wiring_sources + [metric_path, conv_path, metric_summary_path, model / "model_predictions_scaled.csv", adapter / "rows_val.csv"])

    blocks = pd.DataFrame(block_rows)
    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    wiring = pd.DataFrame(wiring_rows).sort_values(["region", "fold"])
    failures = blocks[~blocks["separate_all_folds_converged"]].copy()
    queue = cases[cases["full_quantile_confirmation_eligible"]].copy()
    if not wiring["realized_rows_and_weight_contract_pass"].all():
        raise RuntimeError("R41 does not preserve the selected R33 row/weight contract")
    blocks.to_csv(output / "pricefm_stage_r42_block_selection.csv", index=False)
    cases.to_csv(output / "pricefm_stage_r42_case_closeout.csv", index=False)
    failures.to_csv(output / "pricefm_stage_r42_convergence_failures.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r42_full_quantile_confirmation_queue.csv", index=False)
    wiring.to_csv(output / "pricefm_stage_r42_realized_contract_audit.csv", index=False)
    unique_sources = list(dict.fromkeys(path.resolve() for path in sources))
    pd.DataFrame([
        {"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in unique_sources
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_read_only_r43_repair_justified" if queue.empty else "completed_candidates_queued",
        "cases": len(cases), "experiments_completed": int(complete.sum()), "experiments_remaining": 0,
        "selected_shared_blocks": int(blocks["selected_weight"].eq(0).sum()),
        "selected_partial_blocks": int(blocks["selected_weight"].between(0, 1, inclusive="neither").sum()),
        "selected_separate_blocks": int(blocks["selected_weight"].eq(1).sum()),
        "cases_improving_shared": int(cases["outer_improves_paired_shared"].sum()),
        "cases_improving_r34": int(cases["outer_improves_r34_anchor"].sum()),
        "harm_guard_cases": int(cases["harm_guard_pass"].sum()),
        "full_quantile_candidates": len(queue),
        "realized_rows_and_weight_cases_passed": int(wiring["realized_rows_and_weight_contract_pass"].sum()),
        "realized_full_contract_cases_passed": int(wiring["realized_data_reservoir_weight_contract_pass"].sum()),
        "spatial_config_mismatch_cases": int((~wiring["spatial_config_identical"]).sum()),
        "reservoir_input_map_mismatch_cases": int((~wiring["feature_map_identical"]).sum()),
        "nested_warm_start_cases_consumed": int(wiring["nested_al_to_exal_warm_start_consumed"].sum()),
        "r43_repair_cases": int(wiring["r43_repair_required"].sum()),
        "r43_repair_scope": "restore_selected_r33_spatial_where_needed_and_nested_normal_to_al_to_exal_initialization_keep_interaction_none",
        "test_inspected": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r42_exal_partial_pooling_closeout_report.md").write_text(
        "# PriceFM Stage-R42 exAL partial-pooling closeout\n\n"
        f"R41 completed {len(cases)}/{len(cases)} cases. The frozen selector chose "
        f"{summary['selected_shared_blocks']} shared, {summary['selected_partial_blocks']} partially pooled, "
        f"and {summary['selected_separate_blocks']} separate blocks. "
        f"{summary['cases_improving_shared']} cases improved over paired shared exAL, "
        f"{summary['cases_improving_r34']} improved over the R34 anchor, and "
        f"{summary['full_quantile_candidates']} passed both gates.\n\n"
        f"All six row and training-weight contracts match their selected R33 source. Explicit spatial configuration "
        f"was dropped in {summary['spatial_config_mismatch_cases']} cases, changing the realized reservoir input map "
        f"in {summary['reservoir_input_map_mismatch_cases']} cases. "
        "R41 intentionally removed the Stage-R4/R19-style horizon interaction, and its nested exAL fits were cold "
        "because the runner did not consume the configured normal-to-AL-to-exAL chain inside nested validation. "
        "A bounded six-case R43 repair is therefore justified; it must restore the selected R33 spatial contract, "
        "consume the nested initialization chain, and keep interaction `none`. "
        "test, registry, article, full-quantile, and MCMC actions blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
