#!/usr/bin/env python3
"""Prepare the non-launching PriceFM R93 region-frozen model ladder."""

from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import itertools
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, sha256_file, write_json
from pricefm_graph import graph_scope_manifest_for_policy


GRID_BLOCK = "pricefm_desn_experiment_grid"
ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_R92_REGISTRY = Path(
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__integration_pricefm_r91_20260905/"
    "application/data_local/pricefm/authoritative/pricefm_stage_r92_selective_promotion_20260905/"
    "pricefm_full_surface_decision_registry.csv"
)
DEFAULT_CONTROL_REGISTRY = (
    DATA_ROOT
    / "authoritative/pricefm_region_panel_median_graph_local_closeout_20260614/"
    "merged_selection_registry.csv"
)
DEFAULT_TEMPLATE = repo_path(
    "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
)
DEFAULT_OUTPUT = (
    DATA_ROOT / "authoritative/pricefm_stage_r93_region_frozen_ladder_prep_20260906"
)
DEFAULT_GENERATED = (
    DATA_ROOT / "experiment_grids/pricefm_stage_r93_region_frozen_ridge_20260906"
)
DEFAULT_RUN_ROOT = DATA_ROOT / "runs/pricefm_stage_r93_region_frozen_ridge_20260906"
DEFAULT_PROCESSED_ROOT = (
    DATA_ROOT / "processed_stage_r93_region_frozen_20260906"
)
DEFAULT_NORMAL_RUNTIME_ROOT = (
    DATA_ROOT / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names"
)
DEFAULT_NORMAL_RUNTIME = DEFAULT_NORMAL_RUNTIME_ROOT / "exdqlm"
DEFAULT_NORMAL_RUNTIME_MANIFEST = (
    DEFAULT_NORMAL_RUNTIME_ROOT / "pricefm_stage_r93_normal_runtime_manifest.json"
)

R92_SHA256 = "3922a06a965e8eac6320edbc2cb38464c007c51698814b419271690f9a4c9f87"
CONTROL_REGISTRY_SHA256 = "1482ab9f3b6d5629e8f56bfaa77b152eddadc942d10c889bd072fcc26a054815"
QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
INNER_SPLITS = [
    {"fold": 101, "train": ["2022-01-01", "2023-09-01"], "val": ["2023-09-01", "2024-01-01"]},
    {"fold": 102, "train": ["2022-01-01", "2024-01-01"], "val": ["2024-01-01", "2024-05-01"]},
    {"fold": 103, "train": ["2022-01-01", "2024-05-01"], "val": ["2024-05-01", "2024-09-01"]},
]
POLICY_WEIGHTS = {
    "target_only": 0.40,
    "graph_summary_mean": 0.30,
    "graph_summary_mean_std": 0.20,
    "graph_khop": 0.10,
}
SUPPORTED_CONTROL_POLICIES = {
    *POLICY_WEIGHTS,
    "graph_neighbor_direct",
    "graph_neighbor_spread_summary",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r92-registry", type=Path, default=DEFAULT_R92_REGISTRY)
    p.add_argument("--control-registry", type=Path, default=DEFAULT_CONTROL_REGISTRY)
    p.add_argument("--template-grid", type=Path, default=DEFAULT_TEMPLATE)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--grid-config", type=Path, default=None)
    p.add_argument("--generated-root", type=Path, default=DEFAULT_GENERATED)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    p.add_argument("--processed-root", type=Path, default=DEFAULT_PROCESSED_ROOT)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--normal-runtime-source", type=Path, default=DEFAULT_NORMAL_RUNTIME)
    p.add_argument("--normal-runtime-manifest", type=Path, default=DEFAULT_NORMAL_RUNTIME_MANIFEST)
    p.add_argument("--target-region", default="SE_2")
    p.add_argument("--candidate-count", type=int, default=240)
    p.add_argument("--ridge-top-k", type=int, default=30)
    p.add_argument("--search-seed", type=int, default=2026090601)
    p.add_argument("--write-grid", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    p.add_argument("--allow-fixture-hashes", action="store_true")
    p.add_argument("--expected-r92-sha256", default=R92_SHA256)
    p.add_argument("--expected-control-sha256", default=CONTROL_REGISTRY_SHA256)
    return p


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


def write_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def boolish(value: Any) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def units_value(value: Any) -> list[int]:
    parsed = ast.literal_eval(str(value)) if isinstance(value, str) else value
    units = [int(x) for x in parsed]
    if not units or any(x <= 0 for x in units):
        raise ValueError(f"Invalid reservoir units: {value}")
    return units


def semantic_fingerprint(row: dict[str, Any]) -> str:
    keys = [
        "region", "feature_policy", "lag_window", "depth", "units", "alpha", "rho",
        "input_scale", "state_output", "seed", "graph_degree", "neighbor_regions",
        "max_neighbor_regions",
    ]
    payload = {key: row[key] for key in keys}
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def quota_counts(total: int) -> dict[str, int]:
    if total < 10:
        raise ValueError("candidate-count must be at least 10")
    counts = {name: int(total * weight) for name, weight in POLICY_WEIGHTS.items()}
    remainder = total - sum(counts.values())
    for name in POLICY_WEIGHTS:
        if remainder <= 0:
            break
        counts[name] += 1
        remainder -= 1
    return counts


def candidate_geometries() -> list[list[int]]:
    return [
        [48], [64], [96], [128], [160],
        [48, 48], [64, 64], [80, 80], [96, 96], [120, 120], [96, 48], [120, 64],
        [40, 40, 40], [48, 48, 48], [64, 64, 64], [80, 80, 80], [96, 64, 48],
    ]


def read_authority(args: argparse.Namespace) -> tuple[pd.DataFrame, pd.DataFrame]:
    for path in (args.r92_registry, args.control_registry, args.template_grid):
        if not path.exists() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    if not args.allow_fixture_hashes:
        if sha256_file(args.r92_registry) != str(args.expected_r92_sha256):
            raise RuntimeError("R92 registry hash does not match the frozen authority")
        if sha256_file(args.control_registry) != str(args.expected_control_sha256):
            raise RuntimeError("control registry hash does not match the frozen authority")

    registry = pd.read_csv(args.r92_registry, low_memory=False)
    controls = pd.read_csv(args.control_registry, low_memory=False)
    region = str(args.target_region)
    r92_region = registry[registry.region.astype(str).eq(region)].copy()
    controls = controls[controls.region.astype(str).eq(region)].copy()
    if sorted(r92_region.fold.astype(int).tolist()) != [1, 2, 3]:
        raise RuntimeError(f"R92 does not contain exactly three folds for {region}")
    if sorted(controls.fold.astype(int).tolist()) != [1, 2, 3]:
        raise RuntimeError(f"control registry does not contain exactly three folds for {region}")
    required = {
        "experiment_id", "feature_policy", "lag_window", "depth", "units",
        "alpha", "rho", "input_scale", "state_output", "seed", "tau0",
    }
    missing = sorted(required - set(controls.columns))
    if missing:
        raise RuntimeError(f"control registry omits required specification fields: {missing}")
    if controls.experiment_id.astype(str).str.strip().eq("").any():
        raise RuntimeError(f"authoritative {region} controls contain an empty experiment ID")
    if not set(controls.feature_policy.astype(str)).issubset(SUPPORTED_CONTROL_POLICIES):
        raise RuntimeError(f"authoritative {region} controls contain an unsupported feature policy")
    return r92_region.sort_values("fold"), controls.sort_values("fold")


def verify_normal_runtime(args: argparse.Namespace) -> Path:
    package = args.normal_runtime_source.resolve()
    if args.allow_fixture_hashes:
        if not package.is_dir():
            raise FileNotFoundError(package)
        return package
    manifest_path = args.normal_runtime_manifest.resolve()
    if not manifest_path.is_file():
        raise FileNotFoundError(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    normal = package / "R/qdesn_normal.R"
    expected = manifest.get("patched_files", {}).get("R/qdesn_normal.R", {}).get("sha256")
    if (
        manifest.get("status") != "materialized_and_probed"
        or manifest.get("repair") != "pricefm-r93-normal-scaled-ridge-prior-exact-name-access"
        or manifest.get("probe", {}).get("passed") is not True
        or Path(manifest.get("package_path", "")).resolve() != package
        or not normal.is_file()
        or not expected
        or sha256_file(normal) != expected
    ):
        raise RuntimeError("R93 normal runtime manifest or patched source is invalid")
    return package


def control_ledger(r92: pd.DataFrame, controls: pd.DataFrame) -> pd.DataFrame:
    authority = r92[[
        "region", "fold", "experiment_id", "qdesn_method_id", "qdesn_AQL",
        "pricefm_AQL", "decision_label"
    ]].rename(columns={
        "experiment_id": "authority_experiment_id",
        "qdesn_method_id": "authority_qdesn_method_id",
        "qdesn_AQL": "authority_qdesn_AQL",
        "pricefm_AQL": "authority_pricefm_AQL",
        "decision_label": "authority_decision_label",
    })
    merged = controls.merge(
        authority,
        on=["region", "fold"],
        validate="one_to_one",
    )
    mismatch = merged.experiment_id.astype(str) != merged.authority_experiment_id.astype(str)
    if mismatch.any():
        bad = merged.loc[mismatch, ["region", "fold", "experiment_id", "authority_experiment_id"]]
        raise RuntimeError(f"control experiment IDs differ from R92 authority: {bad.to_dict('records')}")
    rows = []
    for row in merged.itertuples(index=False):
        units = units_value(row.units)
        rows.append({
            "region": row.region,
            "source_fold": int(row.fold),
            "source_experiment_id": row.experiment_id,
            "source_method_id": row.authority_qdesn_method_id,
            "feature_policy": str(row.feature_policy),
            "lag_window": int(row.lag_window),
            "depth": int(row.depth),
            "units": json.dumps(units, separators=(",", ":")),
            "alpha": float(row.alpha),
            "rho": float(row.rho),
            "input_scale": float(row.input_scale),
            "state_output": row.state_output,
            "source_seed": int(row.seed),
            "source_tau0": float(row.tau0),
            "graph_degree": int(row.graph_degree) if "graph_degree" in merged and pd.notna(row.graph_degree) else 1,
            "neighbor_regions": row.neighbor_regions if "neighbor_regions" in merged and pd.notna(row.neighbor_regions) else "[]",
            "max_neighbor_regions": int(row.max_neighbor_regions) if "max_neighbor_regions" in merged and pd.notna(row.max_neighbor_regions) else None,
            "historical_qdesn_AQL_audit_only": float(row.authority_qdesn_AQL),
            "historical_pricefm_AQL_audit_only": float(row.authority_pricefm_AQL),
            "historical_decision_audit_only": row.authority_decision_label,
            "selection_use_of_historical_test_metrics": False,
        })
    return pd.DataFrame(rows).sort_values("source_fold").reset_index(drop=True)


def graph_fields(
    region: str, all_regions: list[str], policy: str,
    *, spatial: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if policy == "target_only":
        return {
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph_degree": 0, "neighbor_regions": [], "max_neighbor_regions": 0,
        }
    spatial = {"graph_degree": 1, **dict(spatial or {})}
    graph = graph_scope_manifest_for_policy(
        region, all_regions, policy, spatial=spatial,
    )
    fields = {
        "graph_degree": int(spatial["graph_degree"]),
        "graph_source": graph["graph_source"],
        "graph_hash": graph["graph_hash"],
        "neighbor_regions": graph["neighbor_regions"],
        "max_neighbor_regions": len(graph["neighbor_regions"]),
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial": spatial,
    }
    if policy == "graph_khop":
        fields.update({
            "input_scope": f"pricefm_graph_khop_degree1_n{len(graph['neighbor_regions'])}",
            "spatial_information_set": "pricefm_released_graph_khop_full_feature_concat",
        })
    elif policy in {"graph_summary_mean", "graph_summary_mean_std"}:
        suffix = "mean" if policy == "graph_summary_mean" else "mean_std"
        fields.update({
            "input_scope": f"pricefm_graph_summary_{suffix}_degree1_n{len(graph['neighbor_regions'])}",
            "spatial_information_set": f"pricefm_released_graph_summary_{suffix}",
        })
    elif policy == "graph_neighbor_direct":
        fields.update({
            "input_scope": f"pricefm_graph_neighbor_direct_degree1_n{len(graph['neighbor_regions'])}",
            "spatial_information_set": "pricefm_neighbor_augmented_direct",
        })
    elif policy == "graph_neighbor_spread_summary":
        fields.update({
            "input_scope": f"pricefm_graph_neighbor_spread_summary_degree1_n{len(graph['neighbor_regions'])}",
            "spatial_information_set": "pricefm_neighbor_augmented_spread_summary",
        })
    else:
        raise RuntimeError(f"unsupported PriceFM feature policy: {policy}")
    return fields


def build_candidates(
    controls: pd.DataFrame,
    all_regions: list[str],
    args: argparse.Namespace,
) -> pd.DataFrame:
    region = str(args.target_region)
    quotas = quota_counts(int(args.candidate_count))
    rows: list[dict[str, Any]] = []
    control_by_fingerprint: dict[str, dict[str, Any]] = {}
    for source in controls.itertuples(index=False):
        row = {
            "region": region,
            "candidate_role": "authoritative_fold_geometry_control",
            "source_fold": str(int(source.source_fold)),
            "source_experiment_id": str(source.source_experiment_id),
            "feature_policy": str(source.feature_policy),
            "lag_window": int(source.lag_window),
            "depth": int(source.depth),
            "units": json.loads(source.units),
            "feature_dim": int(json.loads(source.units)[-1]),
            "alpha": float(source.alpha),
            "rho": float(source.rho),
            "input_scale": float(source.input_scale),
            "state_output": str(source.state_output),
            "seed": int(source.source_seed),
        }
        neighbor_regions = json.loads(source.neighbor_regions) if isinstance(source.neighbor_regions, str) else list(source.neighbor_regions)
        spatial = {"graph_degree": int(source.graph_degree)}
        if neighbor_regions:
            spatial["neighbor_regions"] = neighbor_regions
        if source.max_neighbor_regions is not None and not pd.isna(source.max_neighbor_regions):
            spatial["max_neighbor_regions"] = int(source.max_neighbor_regions)
        row.update(graph_fields(region, all_regions, row["feature_policy"], spatial=spatial))
        row["semantic_fingerprint"] = semantic_fingerprint(row)
        fingerprint = row["semantic_fingerprint"]
        if fingerprint in control_by_fingerprint:
            existing = control_by_fingerprint[fingerprint]
            existing["source_fold"] = ";".join(sorted(
                {*(str(existing["source_fold"]).split(";")), str(row["source_fold"])},
                key=int,
            ))
            existing["source_experiment_id"] = ";".join(sorted({
                *str(existing["source_experiment_id"]).split(";"),
                str(row["source_experiment_id"]),
            }))
        else:
            control_by_fingerprint[fingerprint] = row
            rows.append(row)

    axes = itertools.product(
        candidate_geometries(),
        [48, 96, 168, 240],
        [0.25, 0.35, 0.40, 0.45, 0.50, 0.55],
        [0.82, 0.90, 0.95],
        [0.15, 0.20, 0.25, 0.35, 0.50],
    )
    base_specs = list(axes)
    policy_fields = {
        policy: graph_fields(region, all_regions, policy)
        for policy in quotas
    }
    unsupported_controls = sum(row["feature_policy"] not in quotas for row in rows)
    quotas = quota_counts(int(args.candidate_count) - unsupported_controls)
    for policy, quota in quotas.items():
        existing = sum(row["feature_policy"] == policy for row in rows)
        needed = quota - existing
        pool = []
        for units, lag, alpha, rho, input_scale in base_specs:
            row = {
                "region": region,
                "candidate_role": "bounded_space_filling_search",
                "source_fold": "",
                "source_experiment_id": "",
                "feature_policy": policy,
                "lag_window": int(lag),
                "depth": len(units),
                "units": list(units),
                "feature_dim": int(units[-1]),
                "alpha": float(alpha),
                "rho": float(rho),
                "input_scale": float(input_scale),
                "state_output": "final_layer",
                "seed": int(args.search_seed),
            }
            row.update(copy.deepcopy(policy_fields[policy]))
            row["semantic_fingerprint"] = semantic_fingerprint(row)
            score = hashlib.sha256(
                f"{args.search_seed}|{policy}|{row['semantic_fingerprint']}".encode("utf-8")
            ).hexdigest()
            pool.append((score, row))
        pool.sort(key=lambda item: item[0])
        rows.extend(row for _, row in pool[:needed])

    if len(rows) != int(args.candidate_count):
        raise RuntimeError("candidate bank size does not match candidate-count")
    fingerprints = [row["semantic_fingerprint"] for row in rows]
    if len(fingerprints) != len(set(fingerprints)):
        raise RuntimeError("candidate bank contains duplicate semantic fingerprints")
    for index, row in enumerate(rows, start=1):
        role = "ctrl" if row["candidate_role"].startswith("authoritative") else "search"
        row["candidate_id"] = (
            f"r93_{region.lower().replace('_', '')}_{role}_{index:03d}_"
            f"{row['semantic_fingerprint'][:10]}"
        )
        row["selection_eligible"] = True
        row["selection_split"] = "fold1_train_internal_temporal_validation"
        row["selection_metric"] = "median_inner_validation_AQL_original"
        row["test_access_authorized"] = False
        row["rhs_tau0_placeholder_not_used_by_ridge"] = 0.001
    return pd.DataFrame(rows).sort_values(
        ["candidate_role", "source_fold", "candidate_id"], kind="stable"
    ).reset_index(drop=True)


def make_base_configs(
    template: dict[str, Any], output: Path, target_region: str, artifact_repo: Path,
    normal_runtime: Path, processed_root: Path,
) -> tuple[Path, Path, list[str]]:
    grid = template[GRID_BLOCK]
    data_source = repo_path(grid["base"]["data_config"])
    full_source = repo_path(grid["base"]["full_config"])
    data = load_yaml(data_source)
    full = load_yaml(full_source)
    data_cfg = data["pricefm"]
    all_regions = [str(x) for x in data_cfg["regions"]]
    for key in ["raw_dir", "interim_dir", "processed_dir", "external_repo_dir", "log_dir"]:
        value = Path(str(data_cfg[key]))
        if not value.is_absolute():
            data_cfg[key] = str(artifact_repo / value)
    data_cfg["processed_dir"] = str(processed_root.resolve())
    data_cfg["allow_absolute_local_paths"] = True
    data_cfg["splits"] = copy.deepcopy(INNER_SPLITS)
    data_cfg["pilot"] = {"enabled": True, "region": target_region, "fold": 101}
    data_path = output / "configs/base/pricefm_stage_r93_observational_data.yaml"
    write_yaml(data_path, data)

    full_cfg = full["pricefm_desn_full"]
    full_cfg["data_config"] = str(data_path)
    full_cfg["package_path"] = str(normal_runtime)
    full_cfg["python_bin"] = str(
        artifact_repo / "application/data_local/pricefm/venv/bin/python"
    )
    full_cfg["scope"].update({
        "regions": [target_region],
        "folds": [101, 102, 103],
        "splits": ["train", "val"],
        "horizons": "all",
        "quantiles": QUANTILES,
        "feature_policy": "target_only",
    })
    full_cfg["normal"].update({
        "enabled": True,
        "prior_types": ["scaled_ridge"],
        "predictive_quantile_mode": "analytic_student_t",
    })
    full_cfg["qdesn_vb"].update({"enabled": False, "likelihoods": ["al"]})
    full_cfg["exact_equivalence"]["enabled"] = False
    full_cfg["warm_start"] = {"enabled": False}
    full_cfg["nested_validation"] = {"enabled": False}
    full_path = output / "configs/base/pricefm_stage_r93_ridge_only_full.yaml"
    write_yaml(full_path, full)
    return data_path, full_path, all_regions


def experiment_from_candidate(row: pd.Series) -> dict[str, Any]:
    exp = {
        "id": row.candidate_id,
        "stage": "pricefm_stage_r93_ridge_observational_screen",
        "priority": 0,
        "regions": [row.region],
        "folds": [101, 102, 103],
        "quantiles": QUANTILES,
        "lag_window": int(row.lag_window),
        "feature_map": "window_reservoir_v1",
        "feature_policy": row.feature_policy,
        "feature_dim": int(row.feature_dim),
        "depth": int(row.depth),
        "units": json.loads(row.units) if isinstance(row.units, str) else list(row.units),
        "alpha": float(row.alpha),
        "rho": float(row.rho),
        "input_scale": float(row.input_scale),
        "projection_scale": 1.0,
        "recurrent_sparsity": 0.05,
        "reservoir_activation": "tanh",
        "state_output": "final_layer",
        "tau0": 0.001,
        "seed": int(row.seed),
        "normal": {
            "enabled": True,
            "prior_types": ["scaled_ridge"],
            "predictive_quantile_mode": "analytic_student_t",
        },
        "qdesn_vb": {"enabled": False},
        "exact_equivalence": {"enabled": False},
        "stage_r93_candidate_role": row.candidate_role,
        "stage_r93_source_fold": row.source_fold,
        "stage_r93_source_experiment_id": row.source_experiment_id,
        "stage_r93_semantic_fingerprint": row.semantic_fingerprint,
        "stage_r93_selection_contract": "fold1_train_internal_temporal_validation_only",
        "stage_r93_test_access_authorized": False,
        "selection_rule": "median_inner_validation_AQL_then_worst_fold_then_complexity",
        "selection_is_validation_only": True,
        "selected_on_split": "inner_validation",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "not_loaded_not_predicted_not_selected",
        "rationale": "R93 normal scaled-Ridge observational-window geometry screen.",
    }
    for key in [
        "input_scope", "output_scope", "lead_covariate_status",
        "spatial_information_set", "graph_degree", "graph_source", "graph_hash",
        "neighbor_regions", "max_neighbor_regions", "spatial",
    ]:
        value = row.get(key, None)
        if value is not None and not (isinstance(value, float) and pd.isna(value)) and value != "":
            if isinstance(value, str) and key in {"neighbor_regions", "spatial"}:
                value = json.loads(value)
            exp[key] = value
    return exp


def build_grid(
    template: dict[str, Any], candidates: pd.DataFrame, data_path: Path,
    full_path: Path, args: argparse.Namespace,
) -> dict[str, Any]:
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = "pricefm_stage_r93_region_frozen_ridge_20260906"
    grid["purpose"] = (
        "SE_2 region-level normal Ridge screen on three temporal validation windows wholly "
        "inside the original Fold-1 training period. Outer validation/test are absent."
    )
    grid["base"] = {
        "data_config": str(data_path),
        "full_config": str(full_path),
        "generated_root": str(args.generated_root),
        "run_root": str(args.run_root),
    }
    grid["scope"] = {
        "regions": [args.target_region],
        "folds": [101, 102, 103],
        "splits": ["train", "val"],
        "quantiles": QUANTILES,
        "horizons": "all",
        "ranking_split": "inner_validation",
        "ranking_unit": "original",
        "ranking_metric": "median_AQL",
        "audit_split": "disabled_no_forecast_window",
    }
    grid["fixed"].update({
        "lead_window": 96,
        "feature_map": "window_reservoir_v1",
        "include_intercept": True,
        "shrink_intercept": False,
        "train_origin_limit": 3000,
        "train_origin_selection": "tail",
        "row_chunk_size": 512,
        "projection_scale": 1.0,
        "recurrent_sparsity": 0.05,
        "reservoir_activation": "tanh",
        "state_output": "final_layer",
        "default_jobs": 1,
        "normal": {
            "enabled": True,
            "prior_types": ["scaled_ridge"],
            "predictive_quantile_mode": "analytic_student_t",
        },
        "qdesn_vb": {"enabled": False},
        "exact_equivalence": {"enabled": False},
        "artifact_hygiene": {
            "enabled": True,
            "clean_adapter_patterns": ["X_*.csv"],
            "clean_model_patterns": ["*.rds", "*.rda", "*.RData", "*.rdata"],
            "preserve_patterns": [
                "adapter_manifest.json", "feature_manifest.json", "rows_*.csv", "y_*.csv",
                "metric_summary.csv", "metric_by_horizon*.csv", "model_method_summary.csv",
                "model_parameter_summary.csv", "model_trace_summary.csv",
                "predictions_with_naive_scaled.csv", "model_predictions_scaled.csv",
                "report.md", "*.json", "*.log",
            ],
        },
    })
    grid["launch"] = {
        "prepared_not_authorized": {
            "experiment_jobs": 20,
            "cell_jobs": 1,
            "build_windows": True,
            "resume": True,
            "force": False,
            "dry_run": False,
            "authorized": False,
            "note": "Do not invoke until the user explicitly authorizes the R93 Ridge launch.",
        }
    }
    grid["experiments"] = [experiment_from_candidate(row) for _, row in candidates.iterrows()]
    grid["experiment_blocks"] = []
    return payload


def stage_contracts(args: argparse.Namespace) -> pd.DataFrame:
    rows = [
        (1, "ridge_screen", 240, "3 inner temporal folds", "normal_scaled_ridge", "median inner-validation AQL", "select top 30"),
        (2, "normal_rhs_refit", 30, "same 3 inner folds", "normal_rhs_ns", "median inner-validation AQL with convergence guard", "select one DESN/tau0"),
        (3, "outer_validation_confirmation", 1, "original Fold-1 train/validation", "normal_rhs_ns", "validation AQL; test unavailable", "freeze region spec"),
        (4, "independent_quantile_surface", 1, "original Fold-1 train/validation", "AL and repaired structured exAL VB", "seven-quantile validation AQL", "freeze likelihood family"),
        (5, "all_fold_forecast_audit", 1, "real folds 1,2,3", "frozen seven-quantile family", "test audit after freeze", "compare with R92 and PriceFM"),
        (6, "joint_quantile_gate", 1, "only after independent finite", "joint VB same DESN/tau0/family", "validation then test audit", "diagnostic; no automatic promotion"),
    ]
    frame = pd.DataFrame(rows, columns=[
        "order", "stage", "max_geometries", "selection_window", "model_family",
        "selection_rule", "terminal_action",
    ])
    frame["target_region"] = args.target_region
    frame["forecast_window_selects_model"] = False
    frame["registry_mutation_authorized"] = False
    frame["article_mutation_authorized"] = False
    return frame


def continuation_contract(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "stage": "pricefm_stage_r93_region_frozen_ladder",
        "status": "ridge_launch_prepared_downstream_data_dependent",
        "target_region": args.target_region,
        "ridge": {
            "candidate_count": int(args.candidate_count),
            "mandatory_authoritative_fold_controls": 3,
            "inner_fold_ids": [101, 102, 103],
            "top_k_to_rhs": int(args.ridge_top_k),
            "ranking": ["median_validation_AQL", "max_validation_AQL", "n_state_features", "candidate_id"],
        },
        "rhs": {
            "input": "exactly the validation-selected Ridge top 30",
            "coarse_tau0": [1e-4, 1e-3, 1e-2],
            "conditional_refinement_tau0": [5e-5, 5e-4, 2e-3],
            "winner_count": 1,
            "warm_start": "internal deterministic scaled-Ridge reconstruction on identical X/y",
        },
        "freeze": {
            "scope": f"one DESN geometry and one tau0 for {args.target_region}",
            "forbidden_dimensions": ["fold", "quantile", "forecast/test performance"],
            "outer_validation_confirmation_required": True,
        },
        "independent_quantiles": {
            "quantiles": QUANTILES,
            "families": ["al", "exal"],
            "warm_order": [0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90],
            "exal_contract": "exact CRAN exdqlm 1.1.1 public API plus hash-pinned R82 structured-init repair",
            "posthoc_synthesis": False,
        },
        "firewalls": {
            "ridge_and_rhs_test_loaded": False,
            "forecast_window_selects_or_retunes": False,
            "registry_mutation": False,
            "article_mutation": False,
            "mcmc": False,
            "launch_invoked_by_prep": False,
        },
    }


def exclusions() -> pd.DataFrame:
    return pd.DataFrame([
        {"excluded": "D>=4 or width>160", "reason": "R32 high-capacity screen was costly and scientifically negative"},
        {"excluded": "lag_window 300 or 500", "reason": "R32/R33 found no dual-reference rescue and incurred high cost"},
        {"excluded": "concat_layers", "reason": "larger readout did not justify its cost; final_layer is the primary contract"},
        {"excluded": "horizon-weighted loss or horizon-block readout", "reason": "R25/R30 mechanism experiments were negative"},
        {"excluded": "per-fold or per-quantile geometry/tau0 tuning", "reason": "violates the requested region-frozen scientific estimand"},
        {"excluded": "historical test AQL as a screening covariate", "reason": "test evidence is audit provenance only"},
        {"excluded": "MCMC, registry, or article mutation", "reason": "blocked until full validation and forecast audit gates pass"},
    ])


def build_gates(
    candidates: pd.DataFrame, controls: pd.DataFrame, grid: dict[str, Any],
    grid_written: bool, args: argparse.Namespace,
) -> pd.DataFrame:
    unsupported_controls = candidates[
        ~candidates.feature_policy.isin(POLICY_WEIGHTS)
    ]
    quotas = quota_counts(int(args.candidate_count) - len(unsupported_controls))
    observed_quotas = candidates[
        candidates.feature_policy.isin(POLICY_WEIGHTS)
    ].feature_policy.value_counts().to_dict()
    cfg = grid[GRID_BLOCK]
    gates = [
        ("candidate_count", len(candidates) == args.candidate_count, f"{len(candidates)}"),
        (
            "mandatory_fold_controls",
            len(controls) == 3 and all(
                str(experiment_id) in ";".join(candidates.source_experiment_id.astype(str))
                for experiment_id in controls.source_experiment_id
            ),
            "all three fold authorities represented; duplicate specifications may share one arm",
        ),
        ("policy_quotas", observed_quotas == quotas, json.dumps(observed_quotas, sort_keys=True)),
        ("extra_policies_are_controls_only", unsupported_controls.candidate_role.str.startswith("authoritative").all(), ";".join(sorted(unsupported_controls.feature_policy.unique()))),
        ("unique_semantic_fingerprints", candidates.semantic_fingerprint.is_unique, str(candidates.semantic_fingerprint.nunique())),
        ("ridge_top_30", args.ridge_top_k == 30 and args.ridge_top_k < len(candidates), str(args.ridge_top_k)),
        ("three_inner_temporal_folds", [x["fold"] for x in INNER_SPLITS] == [101, 102, 103], "101,102,103"),
        ("inner_windows_precede_outer_validation", INNER_SPLITS[-1]["val"][1] == "2024-09-01", "ends at original Fold-1 validation boundary"),
        ("test_absent_from_scope", cfg["scope"]["splits"] == ["train", "val"] and cfg["scope"]["audit_split"] == "disabled_no_forecast_window", "train,val"),
        ("ridge_only", cfg["fixed"]["normal"]["prior_types"] == ["scaled_ridge"] and cfg["fixed"]["qdesn_vb"]["enabled"] is False, "normal scaled-Ridge only"),
        ("deterministic_ridge_quantiles", cfg["fixed"]["normal"]["predictive_quantile_mode"] == "analytic_student_t", "analytic Student-t"),
        ("region_frozen_contract", all(not x for x in candidates.test_access_authorized), "no fold/quantile/test tuning"),
        ("grid_materialized", bool(grid_written), str(args.grid_config or args.output_dir / "pricefm_stage_r93_ridge_grid.yaml")),
        ("launcher_not_invoked", cfg["launch"]["prepared_not_authorized"]["authorized"] is False, "prepared_not_authorized"),
    ]
    return pd.DataFrame([{"gate": name, "passed": bool(passed), "observed": observed} for name, passed, observed in gates])


def report_text(summary: dict[str, Any]) -> str:
    return f"""# PriceFM Stage-R93 region-frozen ladder prep

## Decision

The first executable phase is prepared but not launched. It targets `{summary['target_region']}`
and treats the three current fold-specific
winner geometries as mandatory Ridge controls. Their historical test scores are retained
only in a separate audit ledger and never enter selection.

## Selection firewall

The Ridge bank contains `{summary['candidate_count']}` candidates. Every candidate is
scored on three expanding temporal validation windows that lie wholly inside the original
Fold-1 training period. The best `{summary['ridge_top_k']}` by median validation AQL,
worst-window AQL, complexity, and deterministic identifier may advance to normal RHS.
The original Fold-1 validation window is reserved for confirmation. No outer test or
forecast window is present in the Ridge configuration.

## Frozen estimand

Normal RHS selects one region-level DESN geometry and one `tau0`. That same pair is then
used for all seven quantiles and all three real folds. AL and repaired structured exAL VB
are compared on validation only. Test scoring happens only after the geometry, `tau0`,
and likelihood family have been frozen.

## Launch status

`NOT LAUNCHED`. The grid is materialized with a recommended concurrency of 20, but its
authorization flag is false. Registry, article, MCMC, and joint-model actions remain
blocked.
"""


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = args.output_dir.resolve()
    grid_config = (args.grid_config or output / "pricefm_stage_r93_ridge_grid.yaml").resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"output directory exists and is nonempty: {output}")
    output.mkdir(parents=True, exist_ok=True)

    r92, raw_controls = read_authority(args)
    normal_runtime = verify_normal_runtime(args)
    controls = control_ledger(r92, raw_controls)
    template = load_yaml(args.template_grid)
    data_path, full_path, all_regions = make_base_configs(
        template, output, str(args.target_region), args.artifact_repo.resolve(),
        normal_runtime, args.processed_root,
    )
    candidates = build_candidates(controls, all_regions, args)
    grid = build_grid(template, candidates, data_path, full_path, args)
    if args.write_grid:
        write_yaml(grid_config, grid)

    split_rows = []
    for split in INNER_SPLITS:
        split_rows.append({
            "fold": split["fold"],
            "train_start": split["train"][0],
            "train_end_exclusive": split["train"][1],
            "validation_start": split["val"][0],
            "validation_end_exclusive": split["val"][1],
            "inside_original_fold1_train": True,
            "test_access_authorized": False,
        })

    candidates_for_csv = candidates.copy()
    for column in ["units", "neighbor_regions", "spatial"]:
        if column in candidates_for_csv:
            candidates_for_csv[column] = candidates_for_csv[column].map(
                lambda value: json.dumps(value, separators=(",", ":"))
                if isinstance(value, (list, dict)) else value
            )
    contracts = stage_contracts(args)
    gates = build_gates(candidates, controls, grid, bool(args.write_grid and grid_config.exists()), args)
    if not gates.passed.all():
        raise RuntimeError(f"R93 launch-prep gates failed: {gates.loc[~gates.passed].to_dict('records')}")

    outputs = {
        "controls": output / "pricefm_stage_r93_authoritative_fold_controls.csv",
        "candidates": output / "pricefm_stage_r93_ridge_candidate_manifest.csv",
        "splits": output / "pricefm_stage_r93_observational_split_contract.csv",
        "exclusions": output / "pricefm_stage_r93_exclusion_ledger.csv",
        "stages": output / "pricefm_stage_r93_stage_contracts.csv",
        "gates": output / "pricefm_stage_r93_launch_prep_gates.csv",
        "continuation": output / "pricefm_stage_r93_continuation_contract.json",
        "report": output / "pricefm_stage_r93_region_frozen_ladder_prep_report.md",
    }
    write_csv(outputs["controls"], controls)
    write_csv(outputs["candidates"], candidates_for_csv)
    write_csv(outputs["splits"], pd.DataFrame(split_rows))
    write_csv(outputs["exclusions"], exclusions())
    write_csv(outputs["stages"], contracts)
    write_csv(outputs["gates"], gates)
    write_json(outputs["continuation"], continuation_contract(args))

    sources = []
    for label, path, role in [
        ("r92_registry", args.r92_registry, "frozen_model_authority"),
        ("control_registry", args.control_registry, "fold_geometry_provenance"),
        ("template_grid", args.template_grid, "configuration_template"),
        ("runner", repo_path("application/scripts/pricefm/08_run_desn_model_smoke.R"), "stage_selective_model_runner"),
        ("grid_materializer", repo_path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py"), "grid_materializer"),
        ("grid_launcher", repo_path("application/scripts/pricefm/13_run_desn_experiment_grid.py"), "not_invoked"),
    ]:
        sources.append({"source": label, "path": str(path), "sha256": sha256_file(path), "role": role})
    normal_runtime_source = normal_runtime / "R/qdesn_normal.R"
    if normal_runtime_source.is_file():
        sources.append({
            "source": "normal_runtime_source",
            "path": str(normal_runtime_source),
            "sha256": sha256_file(normal_runtime_source),
            "role": "hash_pinned_exact_name_repair",
        })
    if args.normal_runtime_manifest.is_file():
        sources.append({
            "source": "normal_runtime_manifest",
            "path": str(args.normal_runtime_manifest.resolve()),
            "sha256": sha256_file(args.normal_runtime_manifest),
            "role": "normal_runtime_provenance_and_probe",
        })
    source_path = output / "source_manifest.csv"
    write_csv(source_path, pd.DataFrame(sources))

    summary = {
        "stage": "pricefm_stage_r93_region_frozen_ladder_prep",
        "status": "completed_not_launched",
        "target_region": args.target_region,
        "candidate_count": int(len(candidates)),
        "authoritative_fold_controls": 3,
        "ridge_top_k": int(args.ridge_top_k),
        "inner_temporal_folds": 3,
        "planned_ridge_fits": int(len(candidates) * 3),
        "policy_counts": {str(k): int(v) for k, v in candidates.feature_policy.value_counts().sort_index().items()},
        "selection_uses_forecast_or_test_window": False,
        "normal_runtime": str(normal_runtime),
        "grid_config": str(grid_config),
        "grid_written": bool(args.write_grid),
        "launcher_invoked": False,
        "fits_started": False,
        "registry_mutated": False,
        "article_mutated": False,
        "outputs": {key: str(path) for key, path in outputs.items()},
    }
    outputs["report"].write_text(report_text(summary))
    summary["output_sha256"] = {key: sha256_file(path) for key, path in outputs.items()}
    summary["source_manifest"] = str(source_path)
    summary["source_manifest_sha256"] = sha256_file(source_path)
    write_json(output / "summary.json", summary)
    return summary


def main() -> None:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
