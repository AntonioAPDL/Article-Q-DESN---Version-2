#!/usr/bin/env python3
"""Reconstruct a matched seven-quantile PriceFM authority without opening test."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R57_AUTHORITY = DATA / (
    "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824/"
    "pricefm_stage_r57_joint_case_authority.csv"
)
R59_DECISIONS = DATA / (
    "authoritative/pricefm_stage_r59_joint_scoring_contract_20260826/"
    "pricefm_stage_r59_joint_scoring_decisions.csv"
)
PANEL_ROOT = DATA / "authoritative"
OUTPUT = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
METHODS = {
    "al": "qdesn_al_rhs_ns_exact_chunked",
    "exal": "qdesn_exal_rhs_ns_exact_chunked",
}
TAU_SUFFIX = re.compile(r"_tau0p(?:1|25|45|5|55|75|9)$")
METRIC_TOL = 1.0e-9


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r57-authority", type=Path, default=R57_AUTHORITY)
    p.add_argument("--r59-decisions", type=Path, default=R59_DECISIONS)
    p.add_argument("--panel-root", type=Path, default=PANEL_ROOT)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cells", type=int, default=114)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def payload_sha256(payload: Any) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False)
    return hashlib.sha256(raw.encode()).hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def resolve(repo: Path, value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo / path).resolve()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def as_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    return float(value)


def as_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    return int(float(value))


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def normalized_list(value: Any, cast=None) -> list:
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = [item.strip() for item in text.strip("[]").split(",") if item.strip()]
    if not isinstance(value, (list, tuple)):
        value = [value]
    return [cast(item) if cast else item for item in value]


def load_yaml(path: Path, cache: dict[str, dict]) -> dict:
    key = str(path.resolve())
    if key not in cache:
        cache[key] = yaml.safe_load(path.read_text())
    return cache[key]


def scientific_contract(repo: Path, config_path: Path, cache: dict[str, dict]) -> tuple[dict, Path]:
    payload = load_yaml(config_path, cache)
    smoke = payload.get("pricefm_desn_smoke", {})
    if not smoke:
        raise RuntimeError(f"Not a PriceFM smoke config: {config_path}")
    data_path = resolve(repo, smoke["data_config"])
    data = load_yaml(data_path, cache).get("pricefm", {})
    adapter = smoke.get("adapter", {})
    spatial = adapter.get("spatial") or {}
    windows = data.get("windows", {})
    contract = {
        "region": str(smoke.get("region")),
        "fold": as_int(smoke.get("fold")),
        "feature_policy": str(smoke.get("feature_policy")),
        "horizons": normalized_list(smoke.get("horizons"), as_int),
        "adapter": {
            "feature_map": str(adapter.get("feature_map")),
            "feature_dim": as_int(adapter.get("feature_dim")),
            "depth": as_int(adapter.get("depth")),
            "units": normalized_list(adapter.get("units"), as_int),
            "alpha": as_float(adapter.get("alpha")),
            "rho": as_float(adapter.get("rho")),
            "input_scale": as_float(adapter.get("input_scale")),
            "projection_scale": as_float(adapter.get("projection_scale", 1.0)),
            "recurrent_sparsity": as_float(adapter.get("recurrent_sparsity")),
            "state_output": str(adapter.get("state_output")),
            "seed": as_int(adapter.get("seed")),
            "graph_degree": as_int(spatial.get("graph_degree")),
        },
        "rhs_tau0": as_float((smoke.get("rhs_ns") or {}).get("tau0")),
        "training": {
            "train_origin_limit": as_int((smoke.get("training") or {}).get("train_origin_limit")),
            "train_origin_selection": str((smoke.get("training") or {}).get("train_origin_selection")),
        },
        "data": {
            "frequency": str(data.get("frequency")),
            "features": data.get("features"),
            "scaling": data.get("scaling"),
            "splits": data.get("splits"),
            "lag_window": as_int(windows.get("lag_window")),
            "lead_window": as_int(windows.get("lead_window")),
            "anchor_hour": as_int(windows.get("anchor_hour")),
            "anchor_minute": as_int(windows.get("anchor_minute")),
            "train_boundary_mode": windows.get("train_boundary_mode"),
            "validation_boundary_mode": windows.get("validation_boundary_mode"),
            "test_boundary_mode": windows.get("test_boundary_mode"),
        },
    }
    return contract, data_path


def feature_semantics(adapter_dir: Path) -> tuple[dict, Path | None]:
    path = adapter_dir / "feature_manifest.json"
    if not path.is_file():
        return {}, None
    payload = json.loads(path.read_text())
    policy = payload.get("feature_policy_manifest") or {}
    graph = policy.get("graph") or {}
    spatial = policy.get("spatial") or {}
    spread = policy.get("neighbor_spread_summary") or {}
    semantics = {
        "feature_policy": payload.get("feature_policy") or policy.get("feature_policy"),
        "feature_map": payload.get("feature_map"),
        "feature_dim": as_int(payload.get("feature_dim")),
        "horizon_features": payload.get("horizon_features"),
        "input_scope": policy.get("input_scope"),
        "output_scope": policy.get("output_scope"),
        "spatial_information_set": policy.get("spatial_information_set"),
        "lead_covariate_status": policy.get("lead_covariate_status"),
        "graph": {
            "graph_degree": as_int(graph.get("graph_degree", spatial.get("graph_degree"))),
            "graph_hash": graph.get("graph_hash", spatial.get("graph_hash")),
            "target_region": graph.get("target_region"),
            "active_regions": graph.get("active_regions"),
            "neighbor_regions": graph.get("neighbor_regions", spread.get("neighbor_regions", spatial.get("neighbor_regions"))),
        },
        "neighbor_spread_summary": spread or None,
        "feature_provenance": policy.get("feature_provenance"),
        "leakage_contract": policy.get("leakage_contract"),
        "reservoir": payload.get("reservoir"),
    }
    return semantics, path


def metric_row(path: Path, method_id: str) -> dict:
    frame = pd.read_csv(path)
    selected = frame[
        frame["method_id"].astype(str).eq(method_id)
        & frame["split"].astype(str).eq("val")
        & frame["unit"].astype(str).eq("original")
    ]
    if len(selected) != 1:
        raise RuntimeError(f"Expected one validation metric for {method_id}: {path}")
    row = selected.iloc[0]
    aql = float(row["AQL"])
    if not math.isfinite(aql):
        raise RuntimeError(f"Non-finite validation AQL: {path}")
    return {"AQL": aql, "MAE": float(row["MAE"])}


def panel_metric(panel_dir: Path, region: str, fold: int, method_id: str) -> float | None:
    path = panel_dir / "panel_metric.csv"
    if not path.is_file():
        return None
    frame = pd.read_csv(path)
    selected = frame[
        frame["region"].astype(str).eq(region)
        & pd.to_numeric(frame["fold"], errors="coerce").eq(fold)
        & frame["method_id"].astype(str).eq(method_id)
        & frame["split"].astype(str).eq("val")
        & frame["unit"].astype(str).eq("original")
    ]
    if len(selected) != 1:
        return None
    return float(selected.iloc[0]["AQL"])


def discover_bundles(repo: Path, panel_root: Path) -> tuple[pd.DataFrame, list[dict], list[Path]]:
    cache: dict[str, dict] = {}
    grouped: dict[tuple, list[dict]] = defaultdict(list)
    source_paths: list[Path] = []
    for status_path in sorted(panel_root.glob("*/panel_status.csv")):
        source_paths.append(status_path.resolve())
        frame = pd.read_csv(status_path)
        required = {"region", "fold", "id", "tau", "complete", "model_dir", "adapter_dir"}
        if not required.issubset(frame.columns):
            raise RuntimeError(f"Panel status schema mismatch: {status_path}")
        for row in frame.to_dict("records"):
            tau = round(float(row["tau"]), 8)
            if not as_bool(row["complete"]) or tau not in TAUS:
                continue
            base_id = TAU_SUFFIX.sub("", str(row["id"]))
            grouped[(status_path.parent.resolve(), str(row["region"]), int(row["fold"]), base_id)].append({
                "tau": tau,
                "model_dir": resolve(repo, row["model_dir"]),
                "adapter_dir": resolve(repo, row["adapter_dir"]),
            })

    ledger_rows: list[dict] = []
    malformed: list[dict] = []
    for (panel_dir, region, fold, base_id), components in sorted(grouped.items(), key=lambda item: str(item[0])):
        taus = sorted({item["tau"] for item in components})
        if taus != list(TAUS):
            continue
        components = sorted(components, key=lambda item: item["tau"])
        try:
            contracts = []
            semantics = []
            config_paths = []
            feature_paths = []
            for component in components:
                config_path = component["model_dir"].parent / "config.yaml"
                contract, data_path = scientific_contract(repo, config_path, cache)
                semantic, feature_path = feature_semantics(component["adapter_dir"])
                contracts.append(contract)
                semantics.append(semantic)
                config_paths.append(config_path.resolve())
                source_paths.extend([config_path.resolve(), data_path.resolve()])
                if feature_path:
                    feature_paths.append(feature_path.resolve())
                    source_paths.append(feature_path.resolve())
            contract_hashes = {payload_sha256(item) for item in contracts}
            semantic_hashes = {payload_sha256(item) for item in semantics}
            if len(contract_hashes) != 1 or len(semantic_hashes) != 1:
                raise RuntimeError("seven quantile components do not share one scientific contract")
            contract_hash = next(iter(contract_hashes))
            semantic_hash = next(iter(semantic_hashes))
            for family, method_id in METHODS.items():
                values = []
                metric_paths = []
                for component in components:
                    path = component["model_dir"] / "metric_summary.csv"
                    values.append(metric_row(path, method_id)["AQL"])
                    metric_paths.append(path.resolve())
                    source_paths.append(path.resolve())
                recomputed = sum(values) / len(values)
                aggregate = panel_metric(panel_dir, region, fold, method_id)
                aggregate_matches = aggregate is not None and math.isclose(
                    recomputed, aggregate, rel_tol=0.0, abs_tol=METRIC_TOL
                )
                ledger_rows.append({
                    "panel_dir": str(panel_dir),
                    "base_id": base_id,
                    "region": region,
                    "fold": fold,
                    "likelihood_family": family,
                    "method_id": method_id,
                    "paper_quantiles": json.dumps(TAUS),
                    "component_count": len(components),
                    "scientific_contract_sha256": contract_hash,
                    "feature_semantics_sha256": semantic_hash,
                    "validation_AQL_recomputed": recomputed,
                    "validation_AQL_panel": aggregate,
                    "panel_metric_matches": aggregate_matches,
                    "config_paths": json.dumps([str(path) for path in config_paths]),
                    "feature_manifest_paths": json.dumps([str(path) for path in feature_paths]),
                    "metric_paths": json.dumps([str(path) for path in metric_paths]),
                    "integrity_pass": aggregate_matches,
                })
        except Exception as exc:
            malformed.append({
                "panel_dir": str(panel_dir), "base_id": base_id, "region": region,
                "fold": fold, "error": str(exc),
            })
    return pd.DataFrame(ledger_rows), malformed, source_paths


def legacy_source_metric(repo: Path, row: pd.Series) -> dict:
    path = resolve(repo, row["source_run_dir"]) / "cells" / f"region={row.region}" / f"fold={int(row.fold)}" / "model/metric_summary.csv"
    declared = str(row.source_method_id)
    other = METHODS["al"] if declared == METHODS["exal"] else METHODS["exal"]
    declared_metric = metric_row(path, declared)
    other_metric = metric_row(path, other)
    authority = float(row.current_authoritative_validation_AQL)
    return {
        "legacy_metric_path": str(path.resolve()),
        "legacy_declared_family_validation_AQL": declared_metric["AQL"],
        "legacy_other_family_validation_AQL": other_metric["AQL"],
        "legacy_authority_matches_declared_family": math.isclose(authority, declared_metric["AQL"], abs_tol=METRIC_TOL),
        "legacy_authority_matches_other_family": math.isclose(authority, other_metric["AQL"], abs_tol=METRIC_TOL),
        "legacy_declared_AQL_equals_MAE_over_2": math.isclose(declared_metric["AQL"], declared_metric["MAE"] / 2, abs_tol=METRIC_TOL),
        "legacy_other_AQL_equals_MAE_over_2": math.isclose(other_metric["AQL"], other_metric["MAE"] / 2, abs_tol=METRIC_TOL),
    }


def queue_label(relative_delta: float | None) -> str:
    if relative_delta is None:
        return "exact_comparator_missing"
    if relative_delta < 0:
        return "existing_joint_validation_win"
    if relative_delta <= 0.01:
        return "near_loss_le_1pct"
    if relative_delta <= 0.05:
        return "moderate_loss_1_to_5pct"
    return "severe_loss_gt_5pct"


def run(args: argparse.Namespace) -> dict:
    repo = args.artifact_repo.resolve()
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    authority = pd.read_csv(args.r57_authority)
    r59 = pd.read_csv(args.r59_decisions)
    required = {"case_id", "region", "fold", "source_config", "source_adapter_manifest", "source_method_id", "likelihood_family", "current_authoritative_validation_AQL"}
    if not required.issubset(authority.columns):
        raise RuntimeError(f"R57 authority missing columns: {sorted(required - set(authority.columns))}")
    if len(authority) != args.expected_cells or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R57 authority is not the expected unique surface")
    if r59.duplicated(["case_id"]).any():
        raise RuntimeError("R59 decisions contain duplicate case IDs")

    ledger, malformed, discovered_sources = discover_bundles(repo, args.panel_root.resolve())
    cache: dict[str, dict] = {}
    match_rows = []
    family_rows = []
    comparison_rows = []
    selected_sources: list[Path] = []
    r59_by_case = r59.set_index("case_id")
    for row in authority.sort_values(["region", "fold"]).itertuples(index=False):
        source_config = resolve(repo, row.source_config)
        contract, data_path = scientific_contract(repo, source_config, cache)
        source_adapter = resolve(repo, row.source_adapter_manifest).parent
        semantic, feature_path = feature_semantics(source_adapter)
        contract_hash = payload_sha256(contract)
        semantic_hash = payload_sha256(semantic)
        source_payload = load_yaml(source_config, cache).get("pricefm_desn_smoke", {})
        source_quantiles = normalized_list(source_payload.get("quantiles"), float)
        legacy = legacy_source_metric(repo, pd.Series(row._asdict()))
        candidates = ledger[
            ledger["region"].astype(str).eq(str(row.region))
            & pd.to_numeric(ledger["fold"], errors="coerce").eq(int(row.fold))
            & ledger["scientific_contract_sha256"].eq(contract_hash)
            & ledger["feature_semantics_sha256"].eq(semantic_hash)
            & ledger["integrity_pass"].map(as_bool)
        ].copy()
        family_candidates: dict[str, dict] = {}
        conflicts = []
        for family in METHODS:
            subset = candidates[candidates["likelihood_family"].eq(family)].copy()
            if subset.empty:
                continue
            unique_values = sorted({round(float(value), 12) for value in subset.validation_AQL_recomputed})
            if len(unique_values) != 1:
                conflicts.append(family)
                continue
            chosen = subset.sort_values(["panel_dir", "base_id"]).iloc[0].to_dict()
            chosen["duplicate_provenance_count"] = len(subset)
            family_candidates[family] = chosen
        status = "matched" if family_candidates and not conflicts else "provenance_conflict" if conflicts else "exact_comparator_missing"
        selected_family = None
        selected = None
        if status == "matched":
            selected_family, selected = min(
                family_candidates.items(),
                key=lambda item: (float(item[1]["validation_AQL_recomputed"]), item[0]),
            )
            for path in json.loads(selected["config_paths"]) + json.loads(selected["metric_paths"]) + json.loads(selected["feature_manifest_paths"]):
                selected_sources.append(Path(path))
        independent_aql = float(selected["validation_AQL_recomputed"]) if selected else None
        old_family = str(row.likelihood_family)
        match = {
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "match_status": status,
            "source_likelihood_family": old_family,
            "selected_seven_quantile_family": selected_family,
            "selected_method_id": METHODS.get(selected_family) if selected_family else None,
            "selected_seven_quantile_validation_AQL": independent_aql,
            "selected_panel_dir": selected["panel_dir"] if selected else None,
            "selected_base_id": selected["base_id"] if selected else None,
            "duplicate_provenance_count": selected.get("duplicate_provenance_count") if selected else 0,
            "scientific_contract_sha256": contract_hash,
            "feature_semantics_sha256": semantic_hash,
            "source_quantiles": json.dumps(source_quantiles),
            "source_quantile_count": len(source_quantiles),
            "legacy_median_validation_AQL": float(row.current_authoritative_validation_AQL),
            "family_changed_from_r57": selected_family is not None and selected_family != old_family,
            "provenance_conflict_families": json.dumps(conflicts),
            "selection_split": "val",
            "selection_metric": "seven_quantile_mean_AQL",
            "test_opened": False,
            "launch_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        } | legacy
        match_rows.append(match)
        if selected_family and selected_family != old_family:
            family_rows.append({
                "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
                "r57_likelihood_family": old_family,
                "corrected_seven_quantile_family": selected_family,
                "corrected_validation_AQL": independent_aql,
                "required_action": "review_and_refit_joint_in_corrected_family_before_promotion",
            })
        joint = r59_by_case.loc[row.case_id]
        joint_aql = float(joint["primary_validation_AQL"])
        delta = joint_aql - independent_aql if independent_aql is not None else None
        relative = delta / independent_aql if independent_aql is not None else None
        comparison_rows.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "match_status": status,
            "joint_likelihood_family": old_family,
            "independent_selected_family": selected_family,
            "independent_seven_quantile_validation_AQL": independent_aql,
            "joint_contract_validation_AQL": joint_aql,
            "delta_joint_minus_independent": delta,
            "relative_delta_joint_minus_independent": relative,
            "mechanism_queue": queue_label(relative),
            "validation_only": True,
            "test_opened": False,
            "mcmc_eligible": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })
        selected_sources.extend([source_config, data_path, resolve(repo, row.source_adapter_manifest), Path(legacy["legacy_metric_path"])])
        if feature_path:
            selected_sources.append(feature_path)

    matched = pd.DataFrame(match_rows)
    comparison = pd.DataFrame(comparison_rows)
    gaps = matched[matched["match_status"].ne("matched")].copy()
    gaps["required_action"] = gaps["match_status"].map({
        "exact_comparator_missing": "prepare_exact_seven_quantile_replay_of_source_contract",
        "provenance_conflict": "resolve_conflicting_validation_provenance_before_selection",
    })
    family = pd.DataFrame(family_rows, columns=[
        "case_id", "region", "fold", "r57_likelihood_family",
        "corrected_seven_quantile_family", "corrected_validation_AQL", "required_action",
    ])
    queues = comparison[[
        "case_id", "region", "fold", "match_status", "joint_likelihood_family",
        "independent_selected_family", "independent_seven_quantile_validation_AQL",
        "joint_contract_validation_AQL", "delta_joint_minus_independent",
        "relative_delta_joint_minus_independent", "mechanism_queue",
    ]].copy()

    legacy_median = matched["source_quantile_count"].eq(1) & matched["source_quantiles"].eq("[0.5]")
    selected_matched = matched[matched.match_status.eq("matched")]
    selected_ledger_ok = selected_matched.selected_panel_dir.notna().all()
    gates = pd.DataFrame([
        {"gate": "unique_r57_surface", "passed": len(matched) == args.expected_cells and not matched.duplicated(["region", "fold"]).any(), "observed": len(matched)},
        {"gate": "legacy_source_is_median_only", "passed": legacy_median.all(), "observed": int(legacy_median.sum())},
        {"gate": "legacy_metric_is_median_mae_over_2", "passed": matched.legacy_declared_AQL_equals_MAE_over_2.all() and matched.legacy_other_AQL_equals_MAE_over_2.all(), "observed": int((matched.legacy_declared_AQL_equals_MAE_over_2 & matched.legacy_other_AQL_equals_MAE_over_2).sum())},
        {"gate": "candidate_bundle_integrity", "passed": bool(ledger.integrity_pass.map(as_bool).all()) if len(ledger) else False, "observed": len(ledger)},
        {"gate": "no_malformed_complete_bundle", "passed": len(malformed) == 0, "observed": len(malformed)},
        {"gate": "matched_selection_has_provenance", "passed": selected_ledger_ok, "observed": int(selected_matched.shape[0])},
        {"gate": "full_114_exact_coverage", "passed": matched.match_status.eq("matched").all(), "observed": int(matched.match_status.eq("matched").sum())},
        {"gate": "test_firewall", "passed": not matched.test_opened.any() and not comparison.test_opened.any(), "observed": False},
        {"gate": "no_launch_registry_article_mcmc", "passed": True, "observed": "blocked"},
    ])

    ledger.to_csv(output / "pricefm_stage_r62_candidate_bundle_ledger.csv", index=False)
    matched.to_csv(output / "pricefm_stage_r62_matched_seven_quantile_authority.csv", index=False)
    gaps.to_csv(output / "pricefm_stage_r62_exact_coverage_gaps.csv", index=False)
    family.to_csv(output / "pricefm_stage_r62_family_corrections.csv", index=False)
    comparison.to_csv(output / "pricefm_stage_r62_corrected_joint_comparison.csv", index=False)
    queues.to_csv(output / "pricefm_stage_r62_mechanism_queues.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r62_gates.csv", index=False)
    pd.DataFrame(malformed, columns=["panel_dir", "base_id", "region", "fold", "error"]).to_csv(
        output / "pricefm_stage_r62_malformed_bundle_ledger.csv", index=False
    )

    fixed_sources = [Path(__file__).resolve(), args.r57_authority.resolve(), args.r59_decisions.resolve()]
    manifest_rows = []
    for path in sorted({path.resolve() for path in fixed_sources + selected_sources if path.is_file()}):
        manifest_rows.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    pd.DataFrame(manifest_rows).to_csv(output / "source_manifest.csv", index=False)

    queue_counts = Counter(comparison.mechanism_queue)
    family_counts = Counter(selected_matched.selected_seven_quantile_family)
    mismatch_count = int(matched.legacy_authority_matches_other_family.sum())
    status = "completed_full_matched_seven_quantile_authority" if gaps.empty else "completed_with_exact_coverage_gaps"
    summary = {
        "status": status,
        "artifact_repo_head": git_head(repo),
        "surface_cells": len(matched),
        "matched_cells": int(matched.match_status.eq("matched").sum()),
        "coverage_gap_cells": len(gaps),
        "provenance_conflict_cells": int(matched.match_status.eq("provenance_conflict").sum()),
        "legacy_median_only_cells": int(legacy_median.sum()),
        "legacy_family_value_mismatches": mismatch_count,
        "family_corrections": len(family),
        "selected_family_counts": dict(family_counts),
        "mechanism_queue_counts": dict(queue_counts),
        "quantiles": list(TAUS),
        "selection_role": "validation_only_seven_quantile_mean_AQL",
        "test_opened": False,
        "launch_authorized": False,
        "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "recommended_action": "fill_exact_comparator_gaps_then_freeze_full_surface" if len(gaps) else "freeze_corrected_full_surface",
    }
    write_json(output / "summary.json", summary)
    report = f"""# PriceFM Stage-R62 matched seven-quantile authority audit

Stage-R62 reconstructed historical individual AL/exAL evidence using exactly the
seven paper quantiles and original-scale validation AQL. It recomputed each
aggregate AQL from the seven component metric files and verified it against the
historical panel aggregate.

## Result

- Surface cells: {len(matched)}
- Exact matched cells: {summary['matched_cells']}
- Exact coverage gaps: {summary['coverage_gap_cells']}
- Provenance conflicts: {summary['provenance_conflict_cells']}
- Legacy median-only cells: {summary['legacy_median_only_cells']}
- Legacy family/value mismatches: {summary['legacy_family_value_mismatches']}
- Corrected family changes: {summary['family_corrections']}
- Corrected queues: `{json.dumps(dict(queue_counts), sort_keys=True)}`

## Decision

The old R57 median comparator is superseded for seven-quantile selection. Test,
MCMC, registry, article, and launch access remain blocked. Any exact coverage
gap must be filled by replaying the same region/fold scientific contract at the
seven paper quantiles; approximate or nearest-neighbor substitution is not
allowed.
"""
    (output / "pricefm_stage_r62_matched_seven_quantile_authority_report.md").write_text(report)
    return summary


def main() -> int:
    args = parser().parse_args()
    print(json.dumps(run(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
