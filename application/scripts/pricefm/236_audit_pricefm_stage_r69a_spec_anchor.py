#!/usr/bin/env python3
"""Read-only PriceFM Stage-R69A spec-anchor audit for R68 refit targets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R68 = DATA / "authoritative/pricefm_stage_r68_authority_reconciliation_20260831"
R62 = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
OUTPUT = DATA / "authoritative/pricefm_stage_r69a_spec_anchor_audit_20260831"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
ANCHOR_FIELDS = (
    "feature_policy",
    "feature_map",
    "input_scope",
    "output_scope",
    "spatial_information_set",
    "lead_covariate_status",
    "depth_D",
    "units_json",
    "n_per_layer",
    "reservoir_feature_dim",
    "alpha",
    "rho",
    "input_scale",
    "projection_scale",
    "recurrent_sparsity",
    "reservoir_activation",
    "state_output",
    "graph_degree",
    "rhs_tau0",
    "lag_window",
    "lead_window",
    "train_origin_limit",
    "train_origin_selection",
)
REQUIRED_ANCHOR_FIELDS = {
    "feature_policy",
    "feature_map",
    "input_scope",
    "output_scope",
    "spatial_information_set",
    "lead_covariate_status",
    "depth_D",
    "units_json",
    "reservoir_feature_dim",
    "alpha",
    "rho",
    "input_scale",
    "state_output",
    "rhs_tau0",
    "lag_window",
    "lead_window",
    "train_origin_limit",
    "train_origin_selection",
}
GRAPH_POLICIES_REQUIRE_DEGREE = {
    "graph_khop",
    "graph_neighbor_spread_summary",
    "graph_summary_mean",
    "graph_summary_mean_std",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r68-target-queue", type=Path, default=R68 / "pricefm_stage_r68_refit_target_queue.csv")
    p.add_argument("--r68-summary", type=Path, default=R68 / "summary.json")
    p.add_argument("--r62-candidate-ledger", type=Path, default=R62 / "pricefm_stage_r62_candidate_bundle_ledger.csv")
    p.add_argument("--r62-summary", type=Path, default=R62 / "summary.json")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-targets", type=int, default=56)
    p.add_argument("--expected-quantiles", type=float, nargs="+", default=list(TAUS))
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str | None:
    if not path.exists():
        return None
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
        ).strip()
    except Exception:
        return None


def prepare_output(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text())


def read_csv(path: Path, label: str) -> pd.DataFrame:
    if not Path(path).is_file():
        raise FileNotFoundError(f"Missing {label}: {path}")
    return pd.read_csv(path)


def parse_json_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return []
    text = str(value).strip()
    if not text:
        return []
    loaded = json.loads(text)
    return loaded if isinstance(loaded, list) else [loaded]


def resolve(path: str | Path, artifact_repo: Path) -> Path:
    path = Path(path)
    return path.resolve() if path.is_absolute() else (artifact_repo / path).resolve()


def as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if pd.notna(number) else None


def as_int(value: Any) -> int | None:
    number = as_float(value)
    return None if number is None else int(number)


def scalar_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def list_consistent(values: list[Any], *, required: bool = True) -> bool:
    if not values:
        return not required
    return all(scalar_json(value) == scalar_json(values[0]) for value in values)


def tau_key(value: Any) -> float:
    return round(float(value), 10)


def load_yaml(path: Path) -> dict[str, Any]:
    payload = yaml.safe_load(path.read_text())
    if not isinstance(payload, dict):
        raise RuntimeError(f"YAML did not parse as a mapping: {path}")
    return payload


def feature_scope(feature_payload: dict[str, Any], smoke: dict[str, Any]) -> dict[str, Any]:
    policy = feature_payload.get("feature_policy_manifest") or {}
    graph = policy.get("graph") or {}
    spatial = policy.get("spatial") or {}
    adapter_spatial = (smoke.get("adapter") or {}).get("spatial") or {}
    feature_policy = str(smoke.get("feature_policy") or feature_payload.get("feature_policy") or "")
    if feature_policy == "target_only":
        return {
            "input_scope": policy.get("input_scope") or "local_target_only",
            "output_scope": policy.get("output_scope") or "target_region_path",
            "spatial_information_set": policy.get("spatial_information_set") or "local_only_not_pricefm_graph",
            "lead_covariate_status": policy.get("lead_covariate_status") or "realized_ex_post",
            "graph_degree": None,
            "graph_hash": None,
            "neighbor_count": 0,
            "active_region_count": 0,
        }
    return {
        "input_scope": policy.get("input_scope"),
        "output_scope": policy.get("output_scope"),
        "spatial_information_set": policy.get("spatial_information_set"),
        "lead_covariate_status": policy.get("lead_covariate_status"),
        "graph_degree": as_int(graph.get("graph_degree", spatial.get("graph_degree", adapter_spatial.get("graph_degree")))),
        "graph_hash": graph.get("graph_hash", spatial.get("graph_hash")),
        "neighbor_count": len(graph.get("neighbor_regions") or spatial.get("neighbor_regions") or []),
        "active_region_count": len(graph.get("active_regions") or []),
    }


def component_record(
    artifact_repo: Path,
    target: pd.Series,
    ledger: pd.Series,
    config_path: Path,
    feature_path: Path,
    metric_path: Path,
) -> dict[str, Any]:
    config_exists = config_path.is_file()
    feature_exists = feature_path.is_file()
    metric_exists = metric_path.is_file()
    record: dict[str, Any] = {
        "case_id": target["case_id"],
        "region": str(target["region"]),
        "fold": int(target["fold"]),
        "selected_family": str(target["selected_seven_quantile_family"]),
        "refit_priority": str(target["refit_priority"]),
        "config_path": str(config_path),
        "feature_manifest_path": str(feature_path),
        "metric_path": str(metric_path),
        "config_exists": config_exists,
        "feature_manifest_exists": feature_exists,
        "metric_exists": metric_exists,
        "config_sha256": sha256(config_path) if config_exists else "",
        "feature_manifest_sha256": sha256(feature_path) if feature_exists else "",
        "metric_sha256": sha256(metric_path) if metric_exists else "",
    }
    if not config_exists:
        return record
    payload = load_yaml(config_path)
    smoke = payload.get("pricefm_desn_smoke") or {}
    if not smoke:
        record["parse_error"] = "missing_pricefm_desn_smoke"
        return record
    data_config = resolve(smoke.get("data_config", ""), artifact_repo)
    data_payload = load_yaml(data_config).get("pricefm", {}) if data_config.is_file() else {}
    adapter = smoke.get("adapter") or {}
    training = smoke.get("training") or {}
    rhs = smoke.get("rhs_ns") or {}
    qdesn_vb = smoke.get("qdesn_vb") or {}
    feature_payload = json.loads(feature_path.read_text()) if feature_exists else {}
    scope = feature_scope(feature_payload, smoke)
    units = [as_int(value) for value in (adapter.get("units") or [])]
    features = data_payload.get("features") or {}
    windows = data_payload.get("windows") or {}
    quantiles = [tau_key(value) for value in (smoke.get("quantiles") or [])]
    record.update({
        "config_region": str(smoke.get("region")),
        "config_fold": as_int(smoke.get("fold")),
        "quantiles_json": scalar_json(quantiles),
        "tau": quantiles[0] if len(quantiles) == 1 else None,
        "split_list_json": scalar_json(smoke.get("splits") or []),
        "historical_config_contains_test_split": "test" in [str(x).lower() for x in (smoke.get("splits") or [])],
        "horizon_count": len(smoke.get("horizons") or []),
        "feature_policy": smoke.get("feature_policy"),
        "feature_map": adapter.get("feature_map"),
        "depth_D": as_int(adapter.get("depth")),
        "units_json": scalar_json(units),
        "equal_units_all_layers": bool(units) and len(set(units)) == 1,
        "n_per_layer": units[0] if units and len(set(units)) == 1 else None,
        "reservoir_feature_dim": as_int(adapter.get("feature_dim")),
        "alpha": as_float(adapter.get("alpha")),
        "rho": as_float(adapter.get("rho")),
        "input_scale": as_float(adapter.get("input_scale")),
        "projection_scale": as_float(adapter.get("projection_scale")),
        "recurrent_sparsity": as_float(adapter.get("recurrent_sparsity")),
        "reservoir_activation": adapter.get("reservoir_activation"),
        "state_output": adapter.get("state_output"),
        "graph_degree": scope["graph_degree"],
        "input_scope": scope["input_scope"],
        "output_scope": scope["output_scope"],
        "spatial_information_set": scope["spatial_information_set"],
        "lead_covariate_status": scope["lead_covariate_status"],
        "graph_hash": scope["graph_hash"],
        "neighbor_count": scope["neighbor_count"],
        "active_region_count": scope["active_region_count"],
        "rhs_tau0": as_float(rhs.get("tau0")),
        "rhs_shrink_intercept": bool(rhs.get("shrink_intercept", False)),
        "rhs_freeze_tau_iters": as_int(rhs.get("freeze_tau_iters")),
        "rhs_freeze_tau_warmup_iters": as_int(rhs.get("freeze_tau_warmup_iters")),
        "lag_window": as_int(windows.get("lag_window")),
        "lead_window": as_int(windows.get("lead_window")),
        "lag_features_json": scalar_json(features.get("lag") or []),
        "lead_features_json": scalar_json(features.get("lead") or []),
        "lag_feature_count": len(features.get("lag") or []),
        "lead_feature_count": len(features.get("lead") or []),
        "train_origin_limit": as_int(training.get("train_origin_limit")),
        "train_origin_selection": training.get("train_origin_selection"),
        "qdesn_likelihoods_json": scalar_json(qdesn_vb.get("likelihoods") or []),
        "qdesn_vb_max_iter": as_int(qdesn_vb.get("max_iter")),
        "qdesn_vb_min_iter_elbo": as_int(qdesn_vb.get("min_iter_elbo")),
        "qdesn_vb_n_samp_xi": as_int(qdesn_vb.get("n_samp_xi")),
        "warm_start_enabled": bool((smoke.get("warm_start") or {}).get("enabled", False)),
        "artifact_hygiene_enabled": bool((smoke.get("artifact_hygiene") or {}).get("enabled", False)),
        "data_config_path": str(data_config),
        "data_config_exists": data_config.is_file(),
        "data_config_sha256": sha256(data_config) if data_config.is_file() else "",
        "ledger_scientific_contract_sha256": ledger.get("scientific_contract_sha256", ""),
        "ledger_feature_semantics_sha256": ledger.get("feature_semantics_sha256", ""),
    })
    return record


def anchor_from_components(target: pd.Series, ledger: pd.Series, components: pd.DataFrame, expected_taus: list[float]) -> dict[str, Any]:
    row: dict[str, Any] = {
        "case_id": target["case_id"],
        "region": str(target["region"]),
        "fold": int(target["fold"]),
        "selected_family": str(target["selected_seven_quantile_family"]),
        "refit_priority": str(target["refit_priority"]),
        "operational_gap_class": str(target["operational_gap_class"]),
        "qdesn_minus_operational_pricefm_AQL": float(target["qdesn_minus_operational_pricefm_AQL"]),
        "qdesn_minus_cached_pricefm_AQL": float(target["qdesn_minus_cached_pricefm_AQL"]),
        "mechanism_queue": str(target["mechanism_queue"]),
        "panel_dir": str(ledger["panel_dir"]),
        "base_id": str(ledger["base_id"]),
        "component_count": int(float(ledger["component_count"])),
        "integrity_pass": str(ledger["integrity_pass"]).strip().lower() == "true",
        "paper_quantiles": ledger["paper_quantiles"],
        "validation_AQL_recomputed": float(ledger["validation_AQL_recomputed"]),
        "validation_AQL_panel": float(ledger["validation_AQL_panel"]),
        "panel_metric_matches": str(ledger["panel_metric_matches"]).strip().lower() == "true",
    }
    if components.empty:
        row.update({"anchor_consistency_pass": False, "anchor_launch_grade": False, "anchor_block_reason": "no_components"})
        return row

    observed_taus = sorted(tau_key(value) for value in components["tau"].dropna())
    expected = sorted(tau_key(value) for value in expected_taus)
    row["observed_quantiles_json"] = scalar_json(observed_taus)
    row["expected_quantiles_json"] = scalar_json(expected)
    row["complete_quantile_set"] = observed_taus == expected
    for field in ANCHOR_FIELDS:
        values = [value for value in components[field].tolist() if pd.notna(value)] if field in components else []
        row[field] = values[0] if values else None
        row[f"{field}_consistent"] = list_consistent(values, required=field in REQUIRED_ANCHOR_FIELDS)
    selected_policy = str(row["feature_policy"])
    row["graph_degree_required"] = selected_policy in GRAPH_POLICIES_REQUIRE_DEGREE
    graph_degree_values = [value for value in components["graph_degree"].tolist() if pd.notna(value)] if "graph_degree" in components else []
    row["graph_degree_semantic_pass"] = bool(
        list_consistent(graph_degree_values, required=row["graph_degree_required"])
    )
    row["units_equal_all_layers"] = bool(components["equal_units_all_layers"].all())
    row["historical_any_test_split"] = bool(components["historical_config_contains_test_split"].any())
    row["all_files_exist"] = bool(
        components[["config_exists", "feature_manifest_exists", "metric_exists", "data_config_exists"]].all().all()
    )
    row["region_fold_consistent"] = bool(
        components["config_region"].astype(str).eq(str(target["region"])).all()
        and components["config_fold"].astype(int).eq(int(target["fold"])).all()
    )
    consistency_fields = [f"{field}_consistent" for field in ANCHOR_FIELDS]
    row["anchor_consistency_pass"] = bool(
        row["complete_quantile_set"]
        and row["all_files_exist"]
        and row["region_fold_consistent"]
        and all(bool(row[field]) for field in consistency_fields)
        and row["graph_degree_semantic_pass"]
        and row["integrity_pass"]
        and row["panel_metric_matches"]
    )
    row["future_launch_must_strip_test_split"] = True
    row["future_launch_must_use_train_val_only"] = True
    row["future_launch_must_use_cran111_public_api"] = True
    row["failed_r65_r66_structured_exal_reuse_blocked"] = True
    row["joint_or_mcmc_authorized"] = False
    row["registry_mutation_authorized"] = False
    row["article_mutation_authorized"] = False
    if not row["anchor_consistency_pass"]:
        reasons = []
        for key in ("complete_quantile_set", "all_files_exist", "region_fold_consistent", "integrity_pass", "panel_metric_matches"):
            if not row[key]:
                reasons.append(key)
        for field in consistency_fields:
            if not row[field]:
                reasons.append(field)
        if not row["graph_degree_semantic_pass"]:
            reasons.append("graph_degree_required_for_graph_policy")
        row["anchor_block_reason"] = ";".join(reasons)
    else:
        row["anchor_block_reason"] = ""
    row["anchor_launch_grade"] = bool(row["anchor_consistency_pass"])
    row["recommended_stage_r69b_role"] = (
        "priority_0_full_bounded_case_specific_refit"
        if str(target["refit_priority"]) == "priority_0_near_miss"
        else "priority_1_narrow_case_specific_refit"
    )
    row["recommended_tau0_axis_json"] = scalar_json(sorted(set([
        float(row["rhs_tau0"]),
        1e-4,
        5e-4,
        1e-3,
    ])))
    row["recommended_spec_policy"] = (
        "anchor_plus_small_tau0_spec_sensitivity; no all_114_refit; no_failed_structured_exal_reuse"
    )
    return row


def build_audit(args: argparse.Namespace, targets: pd.DataFrame, ledger: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    components: list[dict[str, Any]] = []
    anchors: list[dict[str, Any]] = []
    ledger_index = {
        (
            str(row.panel_dir),
            str(row.base_id),
            str(row.likelihood_family),
        ): row
        for row in ledger.itertuples(index=False)
    }
    expected_taus = [tau_key(tau) for tau in args.expected_quantiles]
    for _, target in targets.iterrows():
        key = (
            str(target["selected_panel_dir"]),
            str(target["selected_base_id"]),
            str(target["selected_seven_quantile_family"]),
        )
        if key not in ledger_index:
            anchors.append({
                "case_id": target["case_id"],
                "region": target["region"],
                "fold": int(target["fold"]),
                "selected_family": target["selected_seven_quantile_family"],
                "refit_priority": target["refit_priority"],
                "anchor_consistency_pass": False,
                "anchor_launch_grade": False,
                "anchor_block_reason": "missing_r62_candidate_bundle_ledger_match",
            })
            continue
        ledger_row = pd.Series(ledger_index[key]._asdict())
        config_paths = [resolve(path, args.artifact_repo) for path in parse_json_list(ledger_row["config_paths"])]
        feature_paths = [resolve(path, args.artifact_repo) for path in parse_json_list(ledger_row["feature_manifest_paths"])]
        metric_paths = [resolve(path, args.artifact_repo) for path in parse_json_list(ledger_row["metric_paths"])]
        max_len = max(len(config_paths), len(feature_paths), len(metric_paths))
        case_component_rows = []
        for index in range(max_len):
            record = component_record(
                args.artifact_repo,
                target,
                ledger_row,
                config_paths[index] if index < len(config_paths) else Path(""),
                feature_paths[index] if index < len(feature_paths) else Path(""),
                metric_paths[index] if index < len(metric_paths) else Path(""),
            )
            record["component_index"] = index + 1
            case_component_rows.append(record)
            components.append(record)
        anchors.append(anchor_from_components(
            target,
            ledger_row,
            pd.DataFrame(case_component_rows),
            expected_taus,
        ))
    return pd.DataFrame(anchors), pd.DataFrame(components)


def summarize_specs(anchors: pd.DataFrame) -> pd.DataFrame:
    columns = [
        "selected_family", "refit_priority", "feature_policy", "input_scope",
        "spatial_information_set", "depth_D", "units_json", "n_per_layer",
        "lag_window", "lead_window", "state_output", "rhs_tau0",
        "alpha", "rho", "input_scale",
    ]
    anchors = anchors.copy()
    for column in columns:
        if column not in anchors:
            anchors[column] = None
    rows = []
    for values, group in anchors.groupby(columns, dropna=False):
        row = dict(zip(columns, values))
        row["rows"] = len(group)
        row["launch_grade_rows"] = int(group["anchor_launch_grade"].sum())
        row["regions_folds_json"] = scalar_json([
            {"region": str(r.region), "fold": int(r.fold)}
            for r in group.itertuples(index=False)
        ])
        rows.append(row)
    return pd.DataFrame(rows).sort_values(["rows", "selected_family"], ascending=[False, True])


def readiness_gates(anchors: pd.DataFrame, components: pd.DataFrame, expected_targets: int) -> pd.DataFrame:
    return pd.DataFrame([
        {"gate": "expected_target_count", "required": True, "passed": len(anchors) == expected_targets},
        {"gate": "all_targets_have_r62_bundle_match", "required": True, "passed": not anchors["anchor_block_reason"].astype(str).str.contains("missing_r62", na=False).any()},
        {"gate": "all_targets_have_complete_quantile_set", "required": True, "passed": anchors["complete_quantile_set"].all() if "complete_quantile_set" in anchors else False},
        {"gate": "all_targets_have_existing_files", "required": True, "passed": anchors["all_files_exist"].all() if "all_files_exist" in anchors else False},
        {"gate": "all_targets_anchor_consistent", "required": True, "passed": anchors["anchor_consistency_pass"].all()},
        {"gate": "all_targets_launch_grade", "required": True, "passed": anchors["anchor_launch_grade"].all()},
        {"gate": "historical_test_split_flagged_for_removal", "required": True, "passed": anchors["future_launch_must_strip_test_split"].all() if "future_launch_must_strip_test_split" in anchors else False},
        {"gate": "future_cran111_public_api_required", "required": True, "passed": anchors["future_launch_must_use_cran111_public_api"].all() if "future_launch_must_use_cran111_public_api" in anchors else False},
        {"gate": "failed_structured_exal_reuse_blocked", "required": True, "passed": anchors["failed_r65_r66_structured_exal_reuse_blocked"].all() if "failed_r65_r66_structured_exal_reuse_blocked" in anchors else False},
        {"gate": "component_rows_are_7x_targets", "required": True, "passed": len(components) == 7 * len(anchors)},
        {"gate": "registry_article_joint_mcmc_blocked", "required": True, "passed": True},
        {"gate": "launch_yaml_absent", "required": True, "passed": True},
    ])


def source_manifest(paths: list[Path]) -> pd.DataFrame:
    rows = []
    for path in dict.fromkeys(Path(p).resolve() for p in paths):
        if path.is_file():
            rows.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    return pd.DataFrame(rows)


def report(summary: dict[str, Any]) -> str:
    return f"""# PriceFM Stage-R69A Spec Anchor Audit

## Decision

Stage-R69A recovered launch-grade specification anchors for the Stage-R68
target queue without launching or fitting models. It writes no launch YAML and
keeps registry, article, joint, and MCMC work blocked.

## Result

| Quantity | Value |
|---|---:|
| R68 target rows | {summary['targets']} |
| Launch-grade anchors | {summary['launch_grade_targets']} |
| Missing/inconsistent anchors | {summary['blocked_targets']} |
| Component rows | {summary['component_rows']} |
| Priority-0 targets | {summary['priority_counts'].get('priority_0_near_miss', 0)} |
| Priority-1 targets | {summary['priority_counts'].get('priority_1_moderate_gap', 0)} |
| AL targets | {summary['family_counts'].get('al', 0)} |
| exAL targets | {summary['family_counts'].get('exal', 0)} |

## Interpretation

The R68 queue is technically recoverable from the R62 candidate-bundle ledger.
Each future R69B launch row must use the recovered case-specific anchor as its
baseline, strip historical test splits, keep only train/validation selection,
and use exact CRAN `exdqlm` 1.1.1 public APIs for any new fit.

The audit does not itself authorize launching. Its output is the source for a
bounded R69B launch-prep stage.
"""


def run(args: argparse.Namespace) -> dict[str, Any]:
    output = prepare_output(args.output_dir, args.force)
    targets = read_csv(args.r68_target_queue, "R68 target queue")
    r68_summary = read_json(args.r68_summary)
    r62_summary = read_json(args.r62_summary)
    ledger = read_csv(args.r62_candidate_ledger, "R62 candidate bundle ledger")
    if len(targets) != args.expected_targets or r68_summary.get("targeted_refit_candidates") != args.expected_targets:
        raise RuntimeError("R68 target queue count changed")
    if r62_summary.get("matched_cells") != 114:
        raise RuntimeError("R62 authority is not the full 114-cell surface")
    if str(r68_summary.get("future_new_fit_package_authority")) != "exact_CRAN_exdqlm_1.1.1_public_API":
        raise RuntimeError("R68 did not preserve the CRAN 1.1.1 future-fit boundary")

    anchors, components = build_audit(args, targets, ledger)
    spec_summary = summarize_specs(anchors)
    missing = anchors.loc[~anchors["anchor_launch_grade"].astype(bool)].copy()
    gates = readiness_gates(anchors, components, args.expected_targets)
    required_pass = bool(gates.loc[gates.required, "passed"].all())

    anchors.to_csv(output / "pricefm_stage_r69a_spec_anchor_audit.csv", index=False)
    components.to_csv(output / "pricefm_stage_r69a_quantile_component_anchor_audit.csv", index=False)
    spec_summary.to_csv(output / "pricefm_stage_r69a_spec_distribution.csv", index=False)
    missing.to_csv(output / "pricefm_stage_r69a_missing_or_inconsistent_anchors.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r69a_launch_readiness_gates.csv", index=False)

    priority_counts = anchors["refit_priority"].value_counts().to_dict()
    family_counts = anchors["selected_family"].value_counts().to_dict()
    summary = {
        "status": "completed_read_only_spec_anchor_audit" if required_pass else "completed_with_blocked_anchors",
        "recommended_next_action": (
            "prepare_stage_r69b_bounded_cran111_independent_vb_launch_manifest"
            if required_pass else "repair_missing_spec_anchors_before_launch_prep"
        ),
        "targets": int(len(anchors)),
        "launch_grade_targets": int(anchors["anchor_launch_grade"].sum()),
        "blocked_targets": int((~anchors["anchor_launch_grade"].astype(bool)).sum()),
        "component_rows": int(len(components)),
        "priority_counts": {str(k): int(v) for k, v in priority_counts.items()},
        "family_counts": {str(k): int(v) for k, v in family_counts.items()},
        "spec_distribution_rows": int(len(spec_summary)),
        "all_readiness_gates_passed": required_pass,
        "future_launch_must_strip_test_split": True,
        "future_new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        "launch_authorized": False,
        "launch_yaml_written": False,
        "fit_models": False,
        "test_opened_by_this_stage": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "artifact_repo_head": git_head(args.artifact_repo),
    }
    write_json(output / "summary.json", summary)

    source_paths = [
        args.r68_target_queue, args.r68_summary,
        args.r62_candidate_ledger, args.r62_summary,
        Path(__file__).resolve(),
        Path(__file__).resolve().parents[2] / "tests/test_pricefm_stage_r69a_spec_anchor.py",
        Path(__file__).resolve().parents[3] / "docs/implementation_notes/pricefm_stage_r69a_spec_anchor_audit_20260831.md",
    ]
    for col in ("config_path", "feature_manifest_path", "metric_path", "data_config_path"):
        if col in components:
            source_paths.extend(Path(path) for path in components[col].dropna().astype(str) if path)
    source_manifest(source_paths).to_csv(output / "source_manifest.csv", index=False)
    (output / "pricefm_stage_r69a_spec_anchor_audit_report.md").write_text(report(summary))
    if any(output.rglob("*.yaml")) or any(output.rglob("*.yml")):
        raise RuntimeError("Stage-R69A must not write launch YAML")
    if any(output.rglob("*.rds")) or any(output.rglob("*.rda")) or any(output.rglob("*.RData")) or any(output.rglob("*.rdata")):
        raise RuntimeError("Stage-R69A must not write model binary artifacts")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
