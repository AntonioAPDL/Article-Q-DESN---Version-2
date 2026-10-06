#!/usr/bin/env python3
"""Prepare the non-launching R112A all-region Normal-screen extension."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
from types import SimpleNamespace
from typing import Any

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json
from pricefm_graph import graph_adj_matrix, graph_hash


STAGE = "R112A"
TAG = "pricefm_stage_r112a_normal_extension_prep_20260922"
ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R98 = DATA / "authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913"
R99 = DATA / "audits/pricefm_stage_r99_targeted_recovery_20260913"
R100_PREP = DATA / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913"
R100 = DATA / "campaigns/pricefm_stage_r100_targeted_normal_recovery_20260913"
R112 = DATA / "authoritative/pricefm_stage_r112_direct_region_adaptive_design_20260922"
OUTPUT = DATA / "launch_prep" / TAG
CAMPAIGN = DATA / "campaigns/pricefm_stage_r112b_normal_extension_20260922"
RAW = DATA / "interim/FINAL.parquet"
NORMAL_RUNTIME = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
PROCESSED = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/processed_inner"
TEMPLATE = SCRIPT_DIR.parents[1] / "config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
TRAIN_START = "2022-01-01"
TRAIN_END = "2024-09-01"
EXPECTED_REUSE_REGIONS = 17
EXPECTED_EXTENSION_REGIONS = 21
EXPECTED_CANDIDATES_PER_REGION = 240
EXPECTED_RIDGE_TOP_K = 30
EXPECTED_TAU_MULTIPLIERS = (0.25, 1.0, 4.0)


def load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=Path.cwd())
    p.add_argument("--r98-registry", type=Path, default=R98 / "pricefm_stage_r98_authoritative_registry.csv")
    p.add_argument("--r100-winners", type=Path, default=R100 / "pricefm_stage_r100_frozen_normal_winners.csv")
    p.add_argument("--r112-dir", type=Path, default=R112)
    p.add_argument("--raw-parquet", type=Path, default=RAW)
    p.add_argument("--template-grid", type=Path, default=TEMPLATE)
    p.add_argument("--normal-runtime", type=Path, default=NORMAL_RUNTIME)
    p.add_argument("--processed-root", type=Path, default=PROCESSED)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    p.add_argument("--force", action="store_true")
    return p


def artifact(role: str, path: Path, **extra: Any) -> dict[str, Any]:
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "role": role,
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        **extra,
    }


def verify_output_manifest(summary: dict[str, Any]) -> None:
    for row in summary.get("outputs", []):
        path = Path(row["path"])
        if not path.is_file() or sha256_file(path) != row["sha256"]:
            raise RuntimeError(f"R112 output changed: {path}")


def validate_sources(args: argparse.Namespace) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[dict[str, Any]]]:
    r112_summary_path = args.r112_dir / "summary.json"
    r112_summary = json.loads(r112_summary_path.read_text())
    if (
        r112_summary.get("stage") != "R112"
        or r112_summary.get("status") != "completed_direct_region_adaptive_design"
        or r112_summary.get("regions") != 38
        or r112_summary.get("complete_surface_cases") != 114
        or r112_summary.get("r100_normal_winners_reused") != EXPECTED_REUSE_REGIONS
        or r112_summary.get("r112_normal_extension_regions") != EXPECTED_EXTENSION_REGIONS
        or r112_summary.get("forecast_operator") != "direct_96_horizon_no_recursive_target_lags"
        or r112_summary.get("selection_uses_test") is not False
        or r112_summary.get("model_fit_started") is not False
    ):
        raise RuntimeError("R112 design contract changed")
    verify_output_manifest(r112_summary)
    inventory_path = args.r112_dir / "pricefm_stage_r112_region_inventory.csv"
    partition_path = args.r112_dir / "pricefm_stage_r112_execution_partition.csv"
    inventory = pd.read_csv(inventory_path)
    partition = pd.read_csv(partition_path)
    registry = pd.read_csv(args.r98_registry, low_memory=False)
    winners = pd.read_csv(args.r100_winners)
    if (
        len(registry) != 114
        or registry.region.nunique() != 38
        or registry.duplicated(["region", "fold"]).any()
        or len(winners) != EXPECTED_REUSE_REGIONS
        or winners.region.nunique() != EXPECTED_REUSE_REGIONS
        or len(inventory) != 38
        or inventory.normal_screen_fit_required.sum() != EXPECTED_EXTENSION_REGIONS
        or len(partition) != 38
        or partition.normal_screen_host.eq("jerez").sum() != 14
        or partition.normal_screen_host.eq("muscat").sum() != 7
        or partition.normal_screen_host.eq("reuse").sum() != EXPECTED_REUSE_REGIONS
    ):
        raise RuntimeError("R112A regional source cardinality changed")
    pending = set(inventory.loc[inventory.normal_screen_fit_required, "region"].astype(str))
    completed = set(winners.region.astype(str))
    all_regions = set(registry.region.astype(str))
    if pending & completed or pending | completed != all_regions:
        raise RuntimeError("R112A completed/pending region partition changed")
    evidence = [
        artifact("r112_summary", r112_summary_path),
        artifact("r112_region_inventory", inventory_path),
        artifact("r112_execution_partition", partition_path),
        artifact("r98_registry", args.r98_registry),
        artifact("r100_frozen_winners", args.r100_winners),
    ]
    return registry, winners, partition, evidence


def raw_hash_from_r99() -> str:
    sources = pd.read_csv(R99 / "source_manifest.csv")
    rows = sources[sources.role.eq("raw_price_panel")]
    if len(rows) != 1:
        raise RuntimeError("R99 raw-price source record changed")
    return str(rows.iloc[0].sha256)


def all_region_neighbor_signal(raw: pd.DataFrame, regions: list[str]) -> pd.DataFrame:
    time = pd.to_datetime(raw["time_utc"], utc=True)
    train = raw.loc[
        (time >= pd.Timestamp(TRAIN_START, tz="UTC"))
        & (time < pd.Timestamp(TRAIN_END, tz="UTC"))
    ]
    adjacency = graph_adj_matrix()
    rows: list[dict[str, Any]] = []
    for region in regions:
        target = f"{region}-price"
        if target not in train:
            raise RuntimeError(f"raw panel omits {target}")
        y = pd.to_numeric(train[target], errors="coerce")
        dy = y.diff()
        for neighbor in [name for name in adjacency[region] if name != region]:
            column = f"{neighbor}-price"
            if column not in train:
                raise RuntimeError(f"raw panel omits {column}")
            z = pd.to_numeric(train[column], errors="coerce")
            level = float(y.corr(z))
            change = float(dy.corr(z.diff()))
            if not pd.notna(level) or not pd.notna(change):
                raise RuntimeError(f"non-finite train-only neighbor signal: {region}/{neighbor}")
            rows.append({
                "region": region,
                "neighbor": neighbor,
                "level_correlation_train_only": level,
                "change_correlation_train_only": change,
                "absolute_change_correlation": abs(change),
                "selection_cutoff_exclusive": TRAIN_END,
            })
    result = pd.DataFrame(rows).sort_values(
        ["region", "absolute_change_correlation"], ascending=[True, False], kind="stable"
    )
    result["change_rank"] = result.groupby("region").cumcount() + 1
    result["top3_change_neighbor"] = result.change_rank <= 3
    return result.reset_index(drop=True)


def validate_neighbor_regression(neighbors: pd.DataFrame, completed_regions: set[str]) -> None:
    frozen = pd.read_csv(R99 / "pricefm_stage_r99_neighbor_signal_audit.csv")
    rebuilt = neighbors[neighbors.region.isin(completed_regions)].copy()
    keys = ["region", "neighbor"]
    columns = [
        *keys,
        "level_correlation_train_only",
        "change_correlation_train_only",
        "absolute_change_correlation",
        "selection_cutoff_exclusive",
        "change_rank",
        "top3_change_neighbor",
    ]
    frozen = frozen[columns].sort_values(keys).reset_index(drop=True)
    rebuilt = rebuilt[columns].sort_values(keys).reset_index(drop=True)
    if not frozen[keys].equals(rebuilt[keys]):
        raise RuntimeError("R112A neighbor identities differ from frozen R99")
    numeric = columns[2:5]
    if not all(
        pd.to_numeric(frozen[column]).round(14).equals(pd.to_numeric(rebuilt[column]).round(14))
        for column in numeric
    ):
        raise RuntimeError("R112A train-only neighbor values differ from frozen R99")
    for column in columns[5:]:
        if not frozen[column].astype(str).equals(rebuilt[column].astype(str)):
            raise RuntimeError(f"R112A neighbor field differs from frozen R99: {column}")


def validate_candidate_regression(
    r100: Any,
    legacy: Any,
    registry: pd.DataFrame,
    neighbors: pd.DataFrame,
    completed_regions: set[str],
) -> pd.DataFrame:
    rows = []
    for region in sorted(completed_regions):
        current = r100._read_current_spec(registry[registry.region.eq(region)])
        rebuilt = r100.build_candidates(region, current, neighbors, legacy)
        frozen_path = R100_PREP / f"regions/{region}/ridge_prep/pricefm_stage_r100_ridge_candidate_manifest.csv"
        frozen = pd.read_csv(frozen_path)
        if (
            list(rebuilt.candidate_id.astype(str)) != list(frozen.candidate_id.astype(str))
            or list(rebuilt.semantic_fingerprint.astype(str)) != list(frozen.semantic_fingerprint.astype(str))
        ):
            raise RuntimeError(f"R112A candidate generator differs from frozen R100: {region}")
        rows.append({
            "region": region,
            "candidate_count": len(rebuilt),
            "candidate_ids_identical": True,
            "semantic_fingerprints_identical": True,
            "frozen_manifest": str(frozen_path.resolve()),
            "frozen_manifest_sha256": sha256_file(frozen_path),
        })
    return pd.DataFrame(rows)


def prepare_regions(
    args: argparse.Namespace,
    registry: pd.DataFrame,
    partition: pd.DataFrame,
    neighbors: pd.DataFrame,
    output: Path,
    r100: Any,
    legacy: Any,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    template = legacy.load_yaml(args.template_grid)
    pending = partition[partition.normal_screen_host.isin(["jerez", "muscat"])].copy()
    records: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    for item in pending.sort_values("region").itertuples(index=False):
        region = str(item.region)
        host = str(item.normal_screen_host)
        current = r100._read_current_spec(registry[registry.region.eq(region)])
        prep_root = output / f"regions/{region}/ridge_prep"
        generated_root = args.campaign_root / f"hosts/{host}/regions/{region}/ridge_generated"
        run_root = args.campaign_root / f"hosts/{host}/regions/{region}/ridge_runs"
        data_path, full_path, _ = legacy.make_base_configs(
            template,
            prep_root,
            region,
            ARTIFACT_REPO,
            args.normal_runtime.resolve(),
            args.processed_root.resolve(),
        )
        candidates = r100.build_candidates(region, current, neighbors, legacy)
        shim = SimpleNamespace(
            target_region=region,
            generated_root=generated_root,
            run_root=run_root,
            candidate_count=EXPECTED_CANDIDATES_PER_REGION,
            ridge_top_k=EXPECTED_RIDGE_TOP_K,
            output_dir=prep_root,
        )
        grid = legacy.build_grid(template, candidates, data_path, full_path, shim)
        block = grid[legacy.GRID_BLOCK]
        block["grid_id"] = f"pricefm_stage_r112a_normal_extension_ridge_{region.lower()}_20260922"
        block["purpose"] = "R112A all-region R100-equivalent Normal Ridge extension; inner training/validation only."
        block["launch"] = {
            "prepared_not_authorized": {
                "host": host,
                "cell_jobs": 1,
                "one_model_per_logical_cpu": True,
                "runtime_cpu_preflight_required": True,
                "resume": True,
                "force": False,
                "dry_run": False,
                "authorized": False,
            }
        }
        for experiment in block["experiments"]:
            experiment["stage"] = "pricefm_stage_r112a_normal_extension_ridge"
            experiment["rationale"] = "All-region R100-equivalent Normal screen selected only on inner validation."
        grid_path = prep_root / "pricefm_stage_r112a_ridge_grid.yaml"
        legacy.write_yaml(grid_path, grid)
        candidate_path = prep_root / "pricefm_stage_r112a_ridge_candidate_manifest.csv"
        r100._csv_frame(candidates).to_csv(candidate_path, index=False)
        control_path = prep_root / "pricefm_stage_r112a_r98_control.json"
        write_json(control_path, current)
        records.append({
            "region": region,
            "host": host,
            "candidate_count": len(candidates),
            "ridge_top_k": EXPECTED_RIDGE_TOP_K,
            "grid_path": str(grid_path.resolve()),
            "grid_sha256": sha256_file(grid_path),
            "candidate_manifest": str(candidate_path.resolve()),
            "candidate_manifest_sha256": sha256_file(candidate_path),
            "generated_root": str(generated_root.resolve()),
            "run_root": str(run_root.resolve()),
            "processed_root": str(args.processed_root.resolve()),
            "r98_tau0": current["tau0"],
            "r98_observed_readout_features": current["observed_readout_features"],
            "selection_split": "fold1_train_internal_temporal_validation",
            "test_access_authorized": False,
            "launch_authorized": False,
        })
        evidence.extend([
            artifact("r98_selected_atom_manifest", Path(current["source_selected_atom_manifest"]), region=region),
            artifact("r98_feature_manifest", Path(current["source_feature_manifest"]), region=region),
        ])
    return pd.DataFrame(records).sort_values("region"), evidence


def report_text(launch: pd.DataFrame, regression: pd.DataFrame) -> str:
    host_counts = launch.groupby("host").region.nunique().to_dict()
    return f"""# PriceFM Stage-R112A Normal-extension launch preparation

R112A prepares the missing all-region Normal search without launching it. The
current R98 authority and all 17 completed R100 Normal winners remain frozen.

## What was verified

- all {len(regression)} completed R100 region banks were regenerated with the
  generalized all-region neighbor table;
- candidate IDs and semantic fingerprints match the frozen R100 banks exactly;
- the raw neighbor evidence uses only `{TRAIN_START}` through observations
  strictly before `{TRAIN_END}`;
- all 21 new banks contain 240 candidates and the current R98 geometry;
- outer validation and test data cannot rank candidates;
- model, quantile, joint, MCMC, registry, and article work remain blocked.

## Prepared workload

| Item | Count |
|---|---:|
| Missing regions | {len(launch)} |
| Ridge candidates | {int(launch.candidate_count.sum())} |
| Ridge inner fit cells | {int(launch.candidate_count.sum() * 3)} |
| Maximum RHS candidates after top-30 selection | {len(launch) * EXPECTED_RIDGE_TOP_K * len(EXPECTED_TAU_MULTIPLIERS)} |
| Maximum RHS inner fit cells | {len(launch) * EXPECTED_RIDGE_TOP_K * len(EXPECTED_TAU_MULTIPLIERS) * 3} |

The deterministic ownership split is {host_counts}. Actual CPU IDs and worker
counts must be selected by a fresh host-local preflight; they are intentionally
not frozen in this package. One model process must use one logical CPU and one
BLAS/OpenMP thread.

## Next gate

R112B may start only after this package and the host environment are verified.
Its controller must be resumable, retain compact metric/method evidence, freeze
one Normal RHS winner for every missing region, and never open an outer or test
split. R112C remains blocked until the union of 17 R100 and 21 R112B winners is
complete and hash-verified.
"""


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = args.output_dir.resolve()
    summary_path = output / "summary.json"
    if summary_path.is_file() and not args.force:
        existing = json.loads(summary_path.read_text())
        if existing.get("status") == "completed_launch_prep_not_launched":
            verify_output_manifest(existing)
            return existing
    if output.exists() and any(output.iterdir()) and not args.force:
        raise RuntimeError(f"R112A output exists but is not reusable: {output}")

    registry, winners, partition, evidence = validate_sources(args)
    r100 = load_module(SCRIPT_DIR / "332_prepare_pricefm_stage_r100_targeted_normal_screen.py", "pricefm_r100_prep")
    legacy = r100._load_legacy()
    raw_sha256 = sha256_file(args.raw_parquet)
    if raw_sha256 != raw_hash_from_r99():
        raise RuntimeError("R112A raw PriceFM panel differs from frozen R99 evidence")
    raw = pd.read_parquet(args.raw_parquet)
    regions = sorted(registry.region.astype(str).unique())
    neighbors = all_region_neighbor_signal(raw, regions)
    completed = set(winners.region.astype(str))
    validate_neighbor_regression(neighbors, completed)
    regression = validate_candidate_regression(r100, legacy, registry, neighbors, completed)
    if len(regression) != EXPECTED_REUSE_REGIONS:
        raise RuntimeError("R112A did not reproduce all completed R100 candidate banks")

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=False)
    launch, regional_evidence = prepare_regions(
        args, registry, partition, neighbors, output, r100, legacy,
    )
    evidence.extend(regional_evidence)
    if (
        len(launch) != EXPECTED_EXTENSION_REGIONS
        or launch.region.nunique() != EXPECTED_EXTENSION_REGIONS
        or not launch.candidate_count.eq(EXPECTED_CANDIDATES_PER_REGION).all()
        or launch.host.eq("jerez").sum() != 14
        or launch.host.eq("muscat").sum() != 7
        or launch.test_access_authorized.any()
        or launch.launch_authorized.any()
    ):
        raise RuntimeError("R112A launch-prep cardinality or firewall changed")

    neighbors_path = output / "pricefm_stage_r112a_all_region_neighbor_signal.csv"
    regression_path = output / "pricefm_stage_r112a_r100_regression_gate.csv"
    launch_path = output / "pricefm_stage_r112a_normal_extension_launch_manifest.csv"
    host_path = output / "pricefm_stage_r112a_host_partition.csv"
    gate_path = output / "pricefm_stage_r112a_launch_prep_gates.csv"
    neighbors.to_csv(neighbors_path, index=False)
    regression.to_csv(regression_path, index=False)
    launch.to_csv(launch_path, index=False)
    launch[["region", "host", "candidate_count", "generated_root", "run_root"]].to_csv(host_path, index=False)
    gates = pd.DataFrame([
        ("r112_contract", True, "completed_direct_region_adaptive_design"),
        ("raw_panel_hash", True, raw_sha256),
        ("graph_hash", graph_hash() == r100.graph_hash(), graph_hash()),
        ("all_region_neighbor_signal", neighbors.region.nunique() == 38, neighbors.region.nunique()),
        ("r100_candidate_regression", len(regression) == 17, len(regression)),
        ("extension_regions", len(launch) == 21, len(launch)),
        ("candidate_count", int(launch.candidate_count.sum()) == 5040, int(launch.candidate_count.sum())),
        ("host_partition", launch.host.value_counts().to_dict() == {"jerez": 14, "muscat": 7}, launch.host.value_counts().to_dict()),
        ("test_access_blocked", not launch.test_access_authorized.any(), False),
        ("launch_blocked", not launch.launch_authorized.any(), False),
        ("registry_article_blocked", True, "blocked"),
    ], columns=["gate", "passed", "observed"])
    if not gates.passed.all():
        raise RuntimeError(f"R112A preparation gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(gate_path, index=False)

    control = {
        "stage": STAGE,
        "status": "prepared_not_authorized",
        "approval_token_required_for_r112b": "RUN_PRICEFM_R112B_NORMAL_EXTENSION",
        "regions": EXPECTED_EXTENSION_REGIONS,
        "ridge_candidates": 5040,
        "ridge_inner_fit_cells": 15120,
        "ridge_top_k_per_region": EXPECTED_RIDGE_TOP_K,
        "rhs_tau_multipliers": list(EXPECTED_TAU_MULTIPLIERS),
        "maximum_rhs_candidates": 1890,
        "maximum_rhs_inner_fit_cells": 5670,
        "selection_split": "fold1_train_internal_temporal_validation",
        "selection_uses_outer_validation": False,
        "selection_uses_test": False,
        "runtime_cpu_preflight_required": True,
        "one_model_per_logical_cpu": True,
        "thread_count_per_model": 1,
        "launch_authorized": False,
        "quantile_fit_authorized": False,
        "joint_fit_authorized": False,
        "mcmc_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    control_path = output / "pricefm_stage_r112a_launch_control.json"
    write_json(control_path, control)
    (output / "pricefm_stage_r112a_normal_extension_prep.md").write_text(report_text(launch, regression))

    evidence.extend([
        artifact("raw_price_panel", args.raw_parquet),
        artifact("grid_template", args.template_grid),
        artifact("normal_runtime_source", args.normal_runtime / "R/qdesn_normal.R"),
        artifact("r99_neighbor_signal", R99 / "pricefm_stage_r99_neighbor_signal_audit.csv"),
        artifact("r100_candidate_generator", SCRIPT_DIR / "332_prepare_pricefm_stage_r100_targeted_normal_screen.py"),
        artifact("r93_grid_helper", SCRIPT_DIR / "291_prepare_pricefm_stage_r93_region_frozen_ladder.py"),
        artifact("r112b_host_controller", SCRIPT_DIR / "386_run_pricefm_stage_r112b_normal_extension.py"),
        artifact("r112b_union_closeout", SCRIPT_DIR / "387_close_pricefm_stage_r112b_normal_extension.py"),
        artifact("executed_source", Path(__file__)),
    ])
    source_path = output / "source_manifest.csv"
    pd.DataFrame(evidence).drop_duplicates(["path", "sha256"]).sort_values(["role", "path"]).to_csv(source_path, index=False)

    generated = [path for path in output.rglob("*") if path.is_file()]
    outputs = [
        {
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for path in sorted(generated)
    ]
    head = __import__("subprocess").check_output(
        ["git", "-C", str(args.code_root.resolve()), "rev-parse", "HEAD"], text=True
    ).strip()
    summary = {
        "stage": STAGE,
        "status": "completed_launch_prep_not_launched",
        "tag": TAG,
        "head": head,
        "regions_reused_from_r100": EXPECTED_REUSE_REGIONS,
        "regions_prepared": EXPECTED_EXTENSION_REGIONS,
        "candidate_generator_regression_regions": len(regression),
        "ridge_candidates": int(launch.candidate_count.sum()),
        "ridge_inner_fit_cells": int(launch.candidate_count.sum() * 3),
        "maximum_rhs_candidates": EXPECTED_EXTENSION_REGIONS * EXPECTED_RIDGE_TOP_K * len(EXPECTED_TAU_MULTIPLIERS),
        "maximum_rhs_inner_fit_cells": EXPECTED_EXTENSION_REGIONS * EXPECTED_RIDGE_TOP_K * len(EXPECTED_TAU_MULTIPLIERS) * 3,
        "host_counts": launch.host.value_counts().sort_index().to_dict(),
        "selection_uses_outer_validation": False,
        "selection_uses_test": False,
        "model_fit_started": False,
        "launch_started": False,
        "quantile_fit_started": False,
        "joint_fit_started": False,
        "mcmc_fit_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "launch_manifest": str(launch_path.resolve()),
        "launch_control": str(control_path.resolve()),
        "source_manifest": str(source_path.resolve()),
        "source_manifest_sha256": sha256_file(source_path),
        "next_stage": "R112B_host_preflight_and_normal_extension_after_explicit_launch_authorization",
        "outputs": outputs,
    }
    write_json(summary_path, summary)
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
