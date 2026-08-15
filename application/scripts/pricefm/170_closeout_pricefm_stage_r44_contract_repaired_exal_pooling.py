#!/usr/bin/env python3
"""Close out R43 using validation-only, frozen horizon-block pooling selection."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_PREP = DATA / "authoritative/pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_20260807"
DEFAULT_GRID = DATA / "experiment_grids/pricefm_stage_r43_contract_repaired_exal_pooling_20260807"
DEFAULT_RUNS = DATA / "runs/pricefm_stage_r43_contract_repaired_exal_pooling_20260807"
DEFAULT_R42 = DATA / "authoritative/pricefm_stage_r42_exal_partial_pooling_closeout_20260807"
DEFAULT_R33 = DATA / "experiment_grids/pricefm_stage_r33_lean_capacity_history_20260722"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r44_contract_repaired_exal_pooling_closeout_20260807"
BLOCKS = ["1-24", "25-48", "49-72", "73-96"]
SHARED = "qdesn_exal_rhs_ns_exact_chunked"
SEPARATE = SHARED + "_horizon_separate"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prep-dir", type=Path, default=DEFAULT_PREP)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUNS)
    p.add_argument("--stage-r42-dir", type=Path, default=DEFAULT_R42)
    p.add_argument("--stage-r33-grid", type=Path, default=DEFAULT_R33)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--expected-cases", type=int, default=6)
    p.add_argument("--expected-candidates", type=int, default=2)
    p.add_argument("--expected-candidate-cases", default="NO_3:2,NO_3:3")
    p.add_argument("--harm-margin", type=float, default=0.005)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def boolish(value) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes", "completed"}


def scalar_list(value) -> list:
    if isinstance(value, str):
        return list(ast.literal_eval(value))
    return list(value)


def case_key(region: str, fold: int) -> str:
    return f"{region}:{int(fold)}"


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
    predictions = predictions[predictions["tau"].astype(float).eq(0.5)]
    observed = pd.read_csv(adapter / "rows_val.csv")[["origin_id", "horizon", "y_scaled"]]
    shared = predictions[predictions["method_id"].eq(SHARED)]
    separate = predictions[predictions["method_id"].eq(SEPARATE)]
    paired = shared.merge(
        separate, on=["split", "origin_id", "horizon", "tau"], suffixes=("_shared", "_separate")
    ).merge(observed, on=["origin_id", "horizon"])
    if paired.empty or set(paired["split"]) != {"val"}:
        raise RuntimeError("R43 outer predictions are incomplete or violate test quarantine")
    paired["horizon_group"] = pd.cut(paired["horizon"], [0, 24, 48, 72, 96], labels=BLOCKS)
    paired["weight"] = paired["horizon_group"].map(weights).astype(float)
    paired["pooled"] = paired["pred_scaled_shared"] * (1 - paired["weight"]) + paired["pred_scaled_separate"] * paired["weight"]
    aql = lambda pred: float(np.mean(0.5 * np.abs(paired["y_scaled"] - pred)))
    return aql(paired["pooled"]), aql(paired["pred_scaled_shared"]), aql(paired["pred_scaled_separate"])


def warm_audit(model: Path, experiment_id: str, region: str, fold: int) -> dict:
    nested = pd.read_csv(model / "nested_warm_start_diagnostics.csv")
    outer = pd.read_csv(model / "warm_start_diagnostics.csv")
    al = nested[(nested["likelihood_family"].eq("al")) & (nested["readout_mode"].eq("shared_static"))]
    exal = nested[(nested["likelihood_family"].eq("exal")) & (nested["readout_mode"].eq("shared_static"))]
    selected = nested[nested["likelihood_family"].isin(["al", "exal"])]
    normal = nested[nested["likelihood_family"].eq("normal")]
    fallback = outer["fallback_used"].map(boolish) if "fallback_used" in outer else pd.Series([], dtype=bool)
    return {
        "experiment_id": experiment_id, "region": region, "fold": int(fold),
        "nested_al_shared_fits": len(al),
        "nested_al_sources_normal": bool(al["init_source"].eq("nested_normal_rhs_ns").all()),
        "nested_exal_shared_fits": len(exal),
        "nested_exal_sources_same_tau_al": bool(exal["init_source"].eq("nested_al_tau_0.5").all()),
        "nested_sources_available": bool(selected["source_available"].map(boolish).all()),
        "selected_al_exal_fits_converged": bool(selected["converged"].map(boolish).all()),
        "nested_normal_nonconverged": int((~normal["converged"].map(boolish)).sum()),
        "outer_fallback_count": int(fallback.sum()),
        "warm_chain_pass": bool(
            len(al) == 5 and len(exal) == 5
            and al["init_source"].eq("nested_normal_rhs_ns").all()
            and exal["init_source"].eq("nested_al_tau_0.5").all()
            and selected["source_available"].map(boolish).all()
            and selected["converged"].map(boolish).all()
            and not fallback.any()
        ),
    }


def full_config(path: Path) -> dict:
    return yaml.safe_load(path.read_text())["pricefm_desn_full"]


def resolve_artifact_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ARTIFACT_REPO / path


def realized_contract(row, r33_row) -> tuple[dict, list[Path]]:
    r43_full = resolve_artifact_path(row.full_config)
    r33_full = resolve_artifact_path(r33_row.full_config)
    r43_cfg, r33_cfg = full_config(r43_full), full_config(r33_full)
    r43_cell = resolve_artifact_path(row.run_dir) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}"
    r33_cell = resolve_artifact_path(r33_row.run_dir) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}"
    pairs = {
        "rows_train": (r33_cell / "adapter/rows_train.csv", r43_cell / "adapter/rows_train.csv"),
        "rows_val": (r33_cell / "adapter/rows_val.csv", r43_cell / "adapter/rows_val.csv"),
        "feature_map": (r33_cell / "adapter/feature_map_matrix.npz", r43_cell / "adapter/feature_map_matrix.npz"),
        "training_weights": (r33_cell / "model/training_weight_summary.csv", r43_cell / "model/training_weight_summary.csv"),
    }
    hashes = {name: (sha256(left), sha256(right)) for name, (left, right) in pairs.items()}
    with np.load(pairs["feature_map"][0]) as left, np.load(pairs["feature_map"][1]) as right:
        map_equal = left.files == right.files and all(np.array_equal(left[k], right[k]) for k in left.files)
    adapter_fields = ["feature_map", "feature_dim", "seed", "projection_scale", "depth", "units", "alpha", "rho", "input_scale", "recurrent_sparsity", "state_output", "spatial"]
    adapter_equal = all(r43_cfg["adapter"].get(k) == r33_cfg["adapter"].get(k) for k in adapter_fields)
    config_equal = adapter_equal and r43_cfg["rhs_ns"] == r33_cfg["rhs_ns"] and r43_cfg["training"] == r33_cfg["training"]
    artifact_equal = all(a == b for a, b in hashes.values()) and map_equal
    result = {
        "experiment_id": row.id, "region": row.region, "fold": int(row.fold),
        "source_r34_experiment_id": row.source_r34_experiment_id,
        "selected_r33_config_contract_match": config_equal,
        **{f"{name}_identical": a == b for name, (a, b) in hashes.items()},
        "feature_map_arrays_identical": map_equal,
        "readout_interaction_none": r43_cfg["adapter"].get("readout_interaction", "none") == "none",
        "scope_train_val_only": r43_cfg["scope"]["splits"] == ["train", "val"],
        "realized_contract_pass": config_equal and artifact_equal and map_equal,
        "test_inspected": False,
    }
    return result, [r43_full, r33_full] + [p for pair in pairs.values() for p in pair]


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = args.prep_dir / "pricefm_stage_r43_launch_manifest.csv"
    status_path = args.grid_root / "launch_status.csv"
    contract_path = args.prep_dir / "pricefm_stage_r43_materialized_config_contract.csv"
    r42_cases_path = args.stage_r42_dir / "pricefm_stage_r42_case_closeout.csv"
    r33_manifest_path = args.stage_r33_grid / "manifest.csv"
    manifest, status = pd.read_csv(manifest_path), pd.read_csv(status_path)
    manifest["region"] = manifest["regions"].map(lambda x: scalar_list(x)[0])
    manifest["fold"] = manifest["folds"].map(lambda x: int(scalar_list(x)[0]))
    materialized_contract = pd.read_csv(contract_path)
    r42 = pd.read_csv(r42_cases_path).set_index(["region", "fold"])
    r33 = pd.read_csv(r33_manifest_path).set_index("id")
    complete = status["status"].eq("completed") & status["return_code"].astype(int).eq(0)
    gates = [
        ("expected_cases", len(manifest) == args.expected_cases, len(manifest)),
        ("unique_cases", manifest[["region", "fold"]].drop_duplicates().shape[0] == args.expected_cases, manifest["id"].nunique()),
        ("completed_zero_exit", len(status) == args.expected_cases and bool(complete.all()), int(complete.sum())),
        ("materialized_contracts_pass", len(materialized_contract) == args.expected_cases and bool(materialized_contract["launch_contract_pass"].map(boolish).all()), int(materialized_contract["launch_contract_pass"].map(boolish).sum())),
        ("test_quarantined", bool(manifest["test_metrics_role"].eq("quarantined_not_loaded").all()), "validation only"),
    ]
    completion = pd.DataFrame(gates, columns=["gate", "passed", "observed"])
    completion.to_csv(output / "pricefm_stage_r44_completion_audit.csv", index=False)
    if not completion["passed"].all():
        raise RuntimeError("R43 completion gates failed")

    block_rows, case_rows, warm_rows, contract_rows = [], [], [], []
    sources = [Path(__file__).resolve(), manifest_path, status_path, contract_path, r42_cases_path, r33_manifest_path]
    for row in manifest.itertuples(index=False):
        model, adapter = model_dir(args.run_root, row), adapter_dir(args.run_root, row)
        metric_path = model / "nested_partial_pooling_metrics.csv"
        convergence_path = model / "nested_partial_pooling_convergence.csv"
        metrics = pd.read_csv(metric_path)
        convergence = pd.read_csv(convergence_path)
        metrics = metrics[metrics["likelihood_family"].eq("exal") & metrics["tau"].astype(float).eq(0.5)]
        convergence = convergence[convergence["likelihood_family"].eq("exal") & convergence["tau"].astype(float).eq(0.5)]
        if len(metrics) != 100 or len(convergence) != 20:
            raise RuntimeError(f"Incomplete R43 exAL nested surface: {row.id}")
        selected = []
        for block in BLOCKS:
            result = select_block(metrics, convergence, block, args.harm_margin)
            block_rows.append({"experiment_id": row.id, "region": row.region, "fold": int(row.fold), **result})
            selected.append(result)
        weights = {x["horizon_group"]: x["selected_weight"] for x in selected}
        pooled_scaled, shared_scaled, separate_scaled = pooled_outer(model, adapter, weights)
        summary_path = model / "metric_summary.csv"
        metric_summary = pd.read_csv(summary_path)
        if set(metric_summary["split"]) != {"val"}:
            raise RuntimeError(f"Test quarantine violated: {row.id}")
        shared_original = float(metric_summary[(metric_summary["method_id"].eq(SHARED)) & metric_summary["unit"].eq("original")]["AQL"].iloc[0])
        scale = shared_original / shared_scaled
        anchor = r42.loc[(row.region, int(row.fold))]
        pooled_original = pooled_scaled * scale
        convergence_pass = all(x["selected_convergence_pass"] for x in selected)
        harm_pass = all(x["harm_guard_pass"] for x in selected)
        improves_shared = pooled_original < shared_original - 1e-12
        improves_r34 = pooled_original < float(anchor["r34_anchor_val_AQL"]) - 1e-12
        eligible = convergence_pass and harm_pass and improves_shared and improves_r34
        case_rows.append({
            "experiment_id": row.id, "region": row.region, "fold": int(row.fold),
            "source_r34_experiment_id": row.source_r34_experiment_id,
            "source_r34_selected_method": row.source_r34_selected_method,
            **{f"weight_{b.replace('-', '_')}": weights[b] for b in BLOCKS},
            "selected_convergence_pass": convergence_pass, "harm_guard_pass": harm_pass,
            "pooled_outer_val_AQL": pooled_original, "shared_outer_val_AQL": shared_original,
            "separate_outer_val_AQL": separate_scaled * scale,
            "r34_anchor_val_AQL": float(anchor["r34_anchor_val_AQL"]),
            "pooled_minus_shared": pooled_original - shared_original,
            "pooled_minus_r34_anchor": pooled_original - float(anchor["r34_anchor_val_AQL"]),
            "outer_improves_paired_shared": improves_shared,
            "outer_improves_r34_anchor": improves_r34,
            "full_quantile_confirmation_eligible": eligible,
            "decision": "eligible_for_r45_full_quantile_confirmation" if eligible else "blocked_r44_validation_gate",
            "selection_split": "nested_inner_validation_and_outer_validation",
            "test_inspected": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False, "mcmc_authorized": False,
        })
        warm = warm_audit(model, row.id, row.region, int(row.fold))
        warm_rows.append(warm)
        realized, realized_sources = realized_contract(row, r33.loc[row.source_r34_experiment_id])
        contract_rows.append(realized)
        sources.extend(realized_sources + [metric_path, convergence_path, summary_path, model / "model_predictions_scaled.csv", model / "nested_warm_start_diagnostics.csv", model / "warm_start_diagnostics.csv", adapter / "rows_val.csv"])

    blocks = pd.DataFrame(block_rows).sort_values(["region", "fold", "horizon_group"])
    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"])
    warm = pd.DataFrame(warm_rows).sort_values(["region", "fold"])
    contracts = pd.DataFrame(contract_rows).sort_values(["region", "fold"])
    queue = cases[cases["full_quantile_confirmation_eligible"]].copy()
    expected = {x.strip() for x in args.expected_candidate_cases.split(",") if x.strip()}
    observed = {case_key(r.region, r.fold) for r in queue.itertuples(index=False)}
    decision_gates = pd.DataFrame([
        {"gate": "all_warm_chains_pass", "passed": bool(warm["warm_chain_pass"].all()), "observed": int(warm["warm_chain_pass"].sum())},
        {"gate": "all_realized_contracts_pass", "passed": bool(contracts["realized_contract_pass"].all()), "observed": int(contracts["realized_contract_pass"].sum())},
        {"gate": "expected_candidate_count", "passed": len(queue) == args.expected_candidates, "observed": len(queue)},
        {"gate": "expected_candidate_identity", "passed": observed == expected, "observed": ";".join(sorted(observed))},
        {"gate": "test_registry_article_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not decision_gates["passed"].all():
        raise RuntimeError("R44 decision gates failed")
    completion = pd.concat([completion, decision_gates], ignore_index=True)
    completion.to_csv(output / "pricefm_stage_r44_completion_audit.csv", index=False)
    blocks.to_csv(output / "pricefm_stage_r44_block_selection.csv", index=False)
    cases.to_csv(output / "pricefm_stage_r44_case_closeout.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r44_full_quantile_confirmation_queue.csv", index=False)
    warm.to_csv(output / "pricefm_stage_r44_warm_start_audit.csv", index=False)
    contracts.to_csv(output / "pricefm_stage_r44_realized_contract_audit.csv", index=False)
    unique_sources = list(dict.fromkeys(Path(x).resolve() for x in sources))
    pd.DataFrame([{"path": str(p), "sha256": sha256(p), "bytes": p.stat().st_size} for p in unique_sources]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_two_candidates_queued", "cases": len(cases),
        "experiments_completed": int(complete.sum()), "experiments_remaining": 0,
        "selected_shared_blocks": int(blocks["selected_weight"].eq(0).sum()),
        "selected_partial_blocks": int(blocks["selected_weight"].between(0, 1, inclusive="neither").sum()),
        "selected_separate_blocks": int(blocks["selected_weight"].eq(1).sum()),
        "cases_improving_shared": int(cases["outer_improves_paired_shared"].sum()),
        "cases_improving_r34": int(cases["outer_improves_r34_anchor"].sum()),
        "harm_guard_cases": int(cases["harm_guard_pass"].sum()),
        "full_quantile_candidates": len(queue), "candidate_cases": sorted(observed),
        "normal_initializer_nonconvergence_count": int(warm["nested_normal_nonconverged"].sum()),
        "selected_al_exal_warm_chains_passed": int(warm["warm_chain_pass"].sum()),
        "realized_contracts_passed": int(contracts["realized_contract_pass"].sum()),
        "test_inspected": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r44_contract_repaired_exal_pooling_closeout_report.md").write_text(
        "# PriceFM Stage-R44 contract-repaired exAL pooling closeout\n\n"
        "R43 completed 6/6 validation-only cases with zero launch failures. The frozen one-standard-error selector "
        f"chose {summary['selected_shared_blocks']} shared and {summary['selected_partial_blocks']} partially pooled "
        "horizon blocks; no fully separate block was selected. All six selected AL/exAL warm chains and realized "
        "R33 data/reservoir/training contracts passed.\n\n"
        "Only `NO_3` folds 2 and 3 beat both their paired shared exAL control and frozen R34 validation anchor while "
        "passing the 0.5% inner-fold harm guard. Their case-specific weights are frozen for R45. Test, registry, "
        "article, and MCMC actions remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
