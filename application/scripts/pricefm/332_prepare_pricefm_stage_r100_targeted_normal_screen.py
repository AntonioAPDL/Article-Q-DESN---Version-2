#!/usr/bin/env python3
"""Prepare the R100 targeted train-only Ridge/RHS recovery campaign."""

from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_graph import graph_hash


SCRIPT_DIR = Path(__file__).resolve().parent
ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R99 = DATA / "audits/pricefm_stage_r99_targeted_recovery_20260913"
R98 = DATA / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913"
R97 = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
CAMPAIGN = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
CPUS = list(range(0, 25)) + list(range(32, 57))
QUOTAS = {
    "target_only": 12,
    "graph_summary_mean": 48,
    "graph_summary_mean_std": 72,
    "graph_neighbor_spread_summary": 84,
    "graph_khop": 24,
}
GEOMETRIES = [
    [48], [64], [96], [128], [48, 48], [64, 64], [80, 80],
    [96, 48], [120, 64], [40, 40, 40], [48, 48, 48],
    [64, 64, 64], [96, 64, 48],
]
LAGS = [96, 168, 240]
ALPHAS = [0.25, 0.35, 0.45, 0.55]
RHOS = [0.82, 0.90, 0.95]
INPUT_SCALES = [0.15, 0.20, 0.35, 0.50]
SEEDS = [2026091301, 2026091302]


def _load_legacy() -> Any:
    path = SCRIPT_DIR / "291_prepare_pricefm_stage_r93_region_frozen_ladder.py"
    spec = importlib.util.spec_from_file_location("pricefm_r93_prep", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r99-dir", type=Path, default=R99)
    p.add_argument("--r98-registry", type=Path, default=R98 / "pricefm_stage_r98_authoritative_registry.csv")
    p.add_argument("--r97-root", type=Path, default=R97)
    p.add_argument("--template-grid", type=Path, default=SCRIPT_DIR.parents[1] / "config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml")
    p.add_argument("--normal-runtime", type=Path, default=DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm")
    p.add_argument("--output-dir", type=Path, default=DATA / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913")
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--processed-root", type=Path, default=R97 / "processed_inner")
    p.add_argument("--candidate-count", type=int, default=240)
    p.add_argument("--ridge-top-k", type=int, default=30)
    p.add_argument("--workers", type=int, default=50)
    p.add_argument("--force", action="store_true")
    return p


def _canonical(spec: dict[str, Any]) -> str:
    return json.dumps(spec, sort_keys=True, separators=(",", ":"))


def _fingerprint(spec: dict[str, Any]) -> str:
    return hashlib.sha256(_canonical(spec).encode()).hexdigest()


def _units(value: Any) -> list[int]:
    if isinstance(value, str):
        value = ast.literal_eval(value)
    return [int(x) for x in value]


def _read_current_spec(region_rows: pd.DataFrame) -> dict[str, Any]:
    first = region_rows.iloc[0]
    selected_path = Path(first.selected_atom_manifest_path)
    if selected_path.suffix.lower() == ".json":
        surface = json.loads(selected_path.read_text())
        frozen = surface["frozen_desn"]
        feature_path = DATA / "runs/pricefm_stage_r93_region_frozen_quantile_validation_20260906/r93_se2_region_frozen/adapter/feature_manifest.json"
    else:
        manifest = pd.read_csv(selected_path)
        feature_path = Path(manifest.iloc[0].feature_manifest_path)
        frozen = {}
    feature = json.loads(feature_path.read_text())
    reservoir = feature["reservoir"]
    policy_manifest = feature.get("feature_policy_manifest") or {}
    spatial = policy_manifest.get("spatial") or {}
    return {
        "region": str(first.region), "feature_policy": str(frozen.get("feature_policy", first.feature_policy)),
        "lag_window": int(frozen.get("lag_window", first.lag_window)), "depth": int(frozen.get("depth", first.depth)),
        "units": _units(frozen.get("units", first.units)), "alpha": float(frozen.get("alpha", first.alpha)), "rho": float(frozen.get("rho", first.rho)),
        "input_scale": float(frozen.get("input_scale", first.input_scale)), "state_output": str(frozen.get("state_output", first.state_output)),
        "seed": int(feature.get("seed", reservoir.get("seed", 2026090601))),
        "tau0": float(first.rhs_tau0), "spatial": spatial,
        "source_selected_atom_manifest": str(selected_path.resolve()),
        "source_selected_atom_manifest_sha256": str(first.selected_atom_manifest_sha256),
        "source_feature_manifest": str(feature_path.resolve()),
        "source_feature_manifest_sha256": sha256_file(feature_path),
        "observed_readout_features": int(len(feature.get("feature_names") or [])),
    }


def _spatial_variants(region: str, policy: str, neighbors: pd.DataFrame) -> list[dict[str, Any]]:
    if policy == "target_only":
        return [{"graph_degree": 0}]
    if policy != "graph_neighbor_spread_summary":
        return [{"graph_degree": 1}]
    ranked = neighbors[neighbors.region.eq(region)].sort_values("change_rank").neighbor.astype(str).tolist()
    variants = []
    for count in sorted(set([min(2, len(ranked)), min(3, len(ranked)), len(ranked)])):
        if count:
            for stats in (["mean_diff", "sd"], ["mean_diff", "sd", "min_diff", "max_diff"]):
                variants.append({
                    "graph_degree": 1, "neighbor_regions": ranked[:count],
                    "max_neighbor_regions": count, "summary_stats": stats,
                })
    if not variants:
        raise RuntimeError(f"no graph neighbors for {region}")
    return variants


def _spec_payload(row: dict[str, Any]) -> dict[str, Any]:
    spatial = row.get("spatial") or {}
    return {
        "region": row["region"], "feature_policy": row["feature_policy"],
        "lag_window": int(row["lag_window"]), "units": list(row["units"]),
        "alpha": float(row["alpha"]), "rho": float(row["rho"]),
        "input_scale": float(row["input_scale"]), "state_output": row["state_output"],
        "seed": int(row["seed"]), "graph_degree": int(spatial.get("graph_degree", 0)),
        "neighbor_regions": list(spatial.get("neighbor_regions") or []),
        "summary_stats": list(spatial.get("summary_stats") or []),
    }


def build_candidates(region: str, current: dict[str, Any], neighbors: pd.DataFrame, legacy: Any) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    current_row = copy.deepcopy(current)
    current_row.update({
        "candidate_role": "R98_frozen_control", "source_fold": "1;2;3",
        "source_experiment_id": current["source_selected_atom_manifest"],
        "feature_dim": int(current["units"][-1]),
    })
    rows.append(current_row)
    seen = {_fingerprint(_spec_payload(current_row))}
    products = list(itertools.product(GEOMETRIES, LAGS, ALPHAS, RHOS, INPUT_SCALES, SEEDS))
    for policy, quota in QUOTAS.items():
        already = int(current["feature_policy"] == policy)
        needed = quota - already
        pool = []
        for units, lag, alpha, rho, input_scale, seed in products:
            for spatial in _spatial_variants(region, policy, neighbors):
                row = {
                    "region": region, "candidate_role": "R100_targeted_novel_search",
                    "source_fold": "", "source_experiment_id": "",
                    "feature_policy": policy, "lag_window": lag, "depth": len(units),
                    "units": list(units), "feature_dim": int(units[-1]), "alpha": alpha,
                    "rho": rho, "input_scale": input_scale, "state_output": "final_layer",
                    "seed": seed, "spatial": spatial,
                }
                identity = _fingerprint(_spec_payload(row))
                if identity in seen:
                    continue
                score = hashlib.sha256(f"R100|{region}|{policy}|{identity}".encode()).hexdigest()
                pool.append((score, identity, row))
        pool.sort(key=lambda item: item[0])
        accepted = 0
        for _, identity, row in pool:
            if identity in seen:
                continue
            seen.add(identity)
            rows.append(row)
            accepted += 1
            if accepted == needed:
                break
        if accepted != needed:
            raise RuntimeError(f"could not fill {policy} quota for {region}")
    if len(rows) != sum(QUOTAS.values()):
        raise RuntimeError(f"candidate count mismatch for {region}: {len(rows)}")

    # The legacy helper requires the released region order; the graph dictionary preserves it.
    from pricefm_graph import graph_adj_matrix
    all_regions = list(graph_adj_matrix())
    output = []
    for index, row in enumerate(rows, start=1):
        spatial = copy.deepcopy(row.get("spatial") or {})
        row.update(legacy.graph_fields(region, all_regions, row["feature_policy"], spatial=spatial))
        row["spatial"] = spatial if row["feature_policy"] == "target_only" else row.get("spatial", spatial)
        identity = _fingerprint(_spec_payload(row))
        row["semantic_fingerprint"] = identity
        role = "ctrl" if row["candidate_role"] == "R98_frozen_control" else "search"
        row["candidate_id"] = f"r100_{region.lower().replace('_', '')}_{role}_{index:03d}_{identity[:10]}"
        row["selection_eligible"] = True
        row["selection_split"] = "fold1_train_internal_temporal_validation"
        row["selection_metric"] = "median_inner_validation_AQL_original"
        row["test_access_authorized"] = False
        row["rhs_tau0_placeholder_not_used_by_ridge"] = float(current["tau0"])
        output.append(row)
    frame = pd.DataFrame(output)
    if not frame.semantic_fingerprint.is_unique:
        raise RuntimeError(f"duplicate candidate semantics for {region}")
    return frame


def _csv_frame(frame: pd.DataFrame) -> pd.DataFrame:
    result = frame.copy()
    for column in ("units", "neighbor_regions", "summary_stats", "spatial"):
        if column in result:
            result[column] = result[column].map(lambda x: json.dumps(x, sort_keys=True) if isinstance(x, (list, dict)) else x)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.candidate_count != 240 or args.ridge_top_k != 30:
        raise RuntimeError("production R100 requires 240 candidates and Ridge top 30")
    if args.workers != 50 or len(CPUS) != 50:
        raise RuntimeError("production R100 requires 50 one-logical-CPU workers")
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    summary99 = json.loads((args.r99_dir / "summary.json").read_text())
    if summary99.get("status") != "completed_targeted_recovery_gate_passed" or not summary99.get("r100_launch_scientifically_supported"):
        raise RuntimeError("R99 did not authorize the targeted R100 mechanism screen")
    normal_source = args.normal_runtime / "R/qdesn_normal.R"
    if not normal_source.is_file():
        raise FileNotFoundError(normal_source)
    queue_path = args.r99_dir / "pricefm_stage_r99_target_queue.csv"
    neighbor_path = args.r99_dir / "pricefm_stage_r99_neighbor_signal_audit.csv"
    queue = pd.read_csv(queue_path, usecols=["region", "selection_data_contract", "test_metrics_may_rank_candidates", "r100_status"])
    if len(queue) != 17 or queue.region.duplicated().any() or queue.test_metrics_may_rank_candidates.astype(bool).any():
        raise RuntimeError("R99 target queue violates the selection firewall")
    neighbors = pd.read_csv(neighbor_path)
    registry = pd.read_csv(args.r98_registry, low_memory=False)
    legacy = _load_legacy()
    template = legacy.load_yaml(args.template_grid)
    region_records = []
    source_rows = []
    for region in queue.region.astype(str):
        current = _read_current_spec(registry[registry.region.eq(region)])
        region_root = output / "regions" / region
        prep_root = region_root / "ridge_prep"
        generated_root = args.campaign_root / f"regions/{region}/ridge_generated"
        run_root = args.campaign_root / f"regions/{region}/ridge_runs"
        processed_root = args.processed_root.resolve()
        data_path, full_path, _ = legacy.make_base_configs(
            template, prep_root, region, ARTIFACT_REPO, args.normal_runtime.resolve(), processed_root,
        )
        candidates = build_candidates(region, current, neighbors, legacy)
        shim = SimpleNamespace(
            target_region=region, generated_root=generated_root, run_root=run_root,
            candidate_count=240, ridge_top_k=30, output_dir=prep_root,
        )
        grid = legacy.build_grid(template, candidates, data_path, full_path, shim)
        block = grid[legacy.GRID_BLOCK]
        block["grid_id"] = f"pricefm_stage_r100_targeted_normal_ridge_{region.lower()}_20260913"
        block["purpose"] = "R100 targeted novel spatial/seed Ridge screen; inner train/validation only."
        block["launch"] = {"authorized": {
            "workers": 50, "cell_jobs": 1, "cpu_list": CPUS,
            "one_model_per_logical_cpu": True, "physical_core_pairs": 25,
            "resume": True, "force": False, "dry_run": False,
        }}
        for exp in block["experiments"]:
            exp["stage"] = "pricefm_stage_r100_targeted_normal_ridge"
            exp["rationale"] = "Targeted spatial/regime recovery selected only on inner validation."
        grid_path = prep_root / "pricefm_stage_r100_ridge_grid.yaml"
        legacy.write_yaml(grid_path, grid)
        candidate_path = prep_root / "pricefm_stage_r100_ridge_candidate_manifest.csv"
        _csv_frame(candidates).to_csv(candidate_path, index=False)
        control_path = prep_root / "pricefm_stage_r100_r98_control.json"
        write_json(control_path, current)
        region_records.append({
            "region": region, "candidate_count": len(candidates), "ridge_top_k": 30,
            "grid_path": str(grid_path), "candidate_manifest": str(candidate_path),
            "generated_root": str(generated_root), "run_root": str(run_root),
            "processed_root": str(processed_root), "r98_tau0": current["tau0"],
            "r98_observed_readout_features": current["observed_readout_features"],
            "test_access_authorized": False,
        })
        source_rows.extend([
            {"role": f"{region}_R98_selected_atom", "path": current["source_selected_atom_manifest"], "sha256": current["source_selected_atom_manifest_sha256"]},
            {"role": f"{region}_R98_feature_manifest", "path": current["source_feature_manifest"], "sha256": current["source_feature_manifest_sha256"]},
        ])
    launch_manifest = pd.DataFrame(region_records)
    launch_path = output / "pricefm_stage_r100_ridge_launch_manifest.csv"
    launch_manifest.to_csv(launch_path, index=False)
    gates = pd.DataFrame([
        ("target_count", len(launch_manifest) == 17, len(launch_manifest)),
        ("candidate_count", int(launch_manifest.candidate_count.sum()) == 4080, int(launch_manifest.candidate_count.sum())),
        ("one_region_level_bank", launch_manifest.region.is_unique, launch_manifest.region.nunique()),
        ("test_access_blocked", not launch_manifest.test_access_authorized.any(), False),
        ("workers_exact", args.workers == 50, args.workers),
        ("physical_logical_contract", CPUS == list(range(25)) + list(range(32, 57)), str(CPUS)),
        ("graph_hash_current", summary99["graph_sha256"] == graph_hash(), graph_hash()),
        ("registry_article_blocked", True, "blocked"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError("R100 preparation gate failed")
    gate_path = output / "pricefm_stage_r100_launch_gates.csv"
    gates.to_csv(gate_path, index=False)
    source_rows.extend([
        {"role": "R99_target_queue", "path": str(queue_path.resolve()), "sha256": sha256_file(queue_path)},
        {"role": "R99_neighbor_signal", "path": str(neighbor_path.resolve()), "sha256": sha256_file(neighbor_path)},
        {"role": "R98_registry", "path": str(args.r98_registry.resolve()), "sha256": sha256_file(args.r98_registry)},
        {"role": "grid_template", "path": str(args.template_grid.resolve()), "sha256": sha256_file(args.template_grid)},
        {"role": "normal_runtime", "path": str(normal_source.resolve()), "sha256": sha256_file(normal_source)},
    ])
    source_path = output / "source_manifest.csv"
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(source_path, index=False)
    control = {
        "stage": "R100", "status": "launch_authorized_by_user_preflight_required",
        "approval_token": "RUN_PRICEFM_R100_TARGETED_NORMAL_RECOVERY",
        "workers": 50, "cpu_ids": CPUS, "physical_cores": list(range(25)),
        "one_model_per_logical_cpu": True, "thread_count_per_model": 1,
        "ridge_experiments": 4080, "ridge_inner_cells": 12240,
        "rhs_top_k_per_region": 30, "rhs_relative_tau_multipliers": [0.25, 1.0, 4.0],
        "rhs_tau_formula": "r98_tau0 * sqrt(r98_readout_features / candidate_readout_features)",
        "minimum_free_disk_gib": 250, "minimum_available_memory_gib": 64,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "test_scoring_authorized": False, "quantile_fit_authorized": False,
        "joint_fit_authorized": False, "mcmc_authorized": False,
    }
    control_path = output / "pricefm_stage_r100_launch_control.json"
    write_json(control_path, control)
    summary = {
        "stage": "R100_launch_prep", "status": "completed_launch_ready",
        "targets": launch_manifest.region.tolist(), "ridge_experiments": 4080,
        "ridge_inner_cells": 12240, "maximum_rhs_experiments": 1530,
        "maximum_rhs_inner_cells": 4590, "workers": 50, "cpu_ids": CPUS,
        "selection_uses_test": False, "launcher_invoked": False,
        "launch_manifest": str(launch_path), "launch_control": str(control_path),
        "source_manifest": str(source_path), "source_manifest_sha256": sha256_file(source_path),
    }
    write_json(output / "summary.json", summary)
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
