#!/usr/bin/env python3
"""Validate PriceFM/Q-DESN model-selection parity without refitting models.

This script checks that the dry-run bridge to the package
``exdqlm::qdesn_model_selection()`` agrees with the article-side PriceFM
artifact registry and fold-aligned comparison outputs. It intentionally does
not launch fits. The current package selector is generic/origin-oriented, while
PriceFM uses a direct-horizon fold contract, so this validator keeps the
boundary explicit and audits apples-to-apples compatibility.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import repo_path, write_json


DEFAULT_BRIDGE_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_qdesn_model_selection_bridge_de_lu_folds23_20260606"
)
DEFAULT_REGISTRY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_median_de_lu_folds23_followup_registry_20260605"
)
DEFAULT_COMPARISON_TEMPLATE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_phase1_vs_desn_de_lu_fold{fold}_followup_20260605"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_qdesn_model_selection_parity_de_lu_folds23_20260606"
)
DEFAULT_METHODS = (
    "qdesn_exal_rhs_ns_exact_chunked,"
    "qdesn_al_rhs_ns_exact_chunked"
)


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bridge-dir", default=DEFAULT_BRIDGE_DIR)
    p.add_argument("--registry-dir", default=DEFAULT_REGISTRY_DIR)
    p.add_argument("--comparison-dir-template", default=DEFAULT_COMPARISON_TEMPLATE)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--regions", default="DE_LU")
    p.add_argument("--folds", default="2,3")
    p.add_argument("--selection-methods", default=DEFAULT_METHODS)
    p.add_argument("--selection-split", default="val")
    p.add_argument("--selection-unit", default="original")
    p.add_argument("--selection-metric", default="AQL")
    p.add_argument("--comparison-split", default="test")
    p.add_argument("--comparison-unit", default="original")
    p.add_argument("--baseline-method", default="pricefm_phase1_pretraining")
    p.add_argument("--expected-horizons", default="1:96")
    p.add_argument("--write", default="true")
    return p


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def parse_csv(value, cast=str):
    if value is None or str(value).strip() in {"", "all"}:
        return None
    return [cast(x.strip()) for x in str(value).split(",") if x.strip()]


def parse_horizons(value):
    text = str(value).strip()
    if ":" in text:
        left, right = text.split(":", 1)
        return list(range(int(left), int(right) + 1))
    return [int(x.strip()) for x in text.split(",") if x.strip()]


def boolish(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def read_csv_required(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("Missing required CSV: {}".format(path))
    return pd.read_csv(path)


def read_yaml_required(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("Missing required YAML: {}".format(path))
    with open(path, "r") as f:
        return yaml.safe_load(f)


def unique_values(frame, column):
    if column not in frame.columns:
        return []
    return sorted(str(x) for x in frame[column].dropna().unique())


def select_scope(frame, regions, folds):
    out = frame.copy()
    if regions:
        out = out[out["region"].astype(str).isin(regions)].copy()
    if folds:
        out = out[out["fold"].astype(int).isin(folds)].copy()
    return out


def comparison_dir(template, fold):
    return repo_path(str(template).format(fold=int(fold)))


def require_columns(frame, columns, context):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ValueError("{} is missing required columns: {}".format(context, sorted(missing)))


def load_inputs(bridge_dir, registry_dir):
    bridge_dir = repo_path(bridge_dir)
    registry_dir = repo_path(registry_dir)
    inputs = {
        "bridge_manifest": read_csv_required(bridge_dir / "bridge_manifest.csv"),
        "bridge_compatibility": read_csv_required(bridge_dir / "bridge_compatibility.csv"),
        "registry": read_csv_required(registry_dir / "median_selection_registry.csv"),
        "candidate_metrics": read_csv_required(registry_dir / "median_candidate_metrics.csv"),
        "method_coverage": read_csv_required(registry_dir / "median_selection_method_coverage.csv"),
    }
    require_columns(inputs["bridge_manifest"], ["region", "fold", "n_candidates", "config_path", "package_launch_ready"], "bridge_manifest")
    require_columns(inputs["bridge_compatibility"], ["region", "fold", "experiment_id", "config_path", "representable_candidate_controls", "package_launch_ready"], "bridge_compatibility")
    require_columns(inputs["registry"], ["region", "fold", "experiment_id", "selected_method_id", "selected_on_split", "selected_on_unit", "selection_metric", "selection_metric_value"], "median_selection_registry")
    require_columns(inputs["candidate_metrics"], ["region", "fold", "experiment_id", "method_id", "split", "unit"], "median_candidate_metrics")
    require_columns(inputs["method_coverage"], ["region", "fold", "method_id", "covered"], "median_selection_method_coverage")
    return inputs


def validate_bridge_configs(manifest, compatibility, regions, folds):
    rows = []
    manifest = select_scope(manifest, regions, folds)
    compatibility = select_scope(compatibility, regions, folds)
    for _, row in manifest.iterrows():
        region = str(row["region"])
        fold = int(row["fold"])
        cfg_path = row["config_path"]
        cfg = read_yaml_required(cfg_path)
        cfg_bridge = cfg.get("pricefm_bridge", {})
        cfg_pipeline = cfg.get("pipeline", {})
        stage = cfg.get("model_selection", {}).get("stages", [{}])[0]
        candidates = stage.get("candidate_grid", {}).get("candidates", [])
        bridge_ids = set(
            compatibility[
                compatibility["region"].astype(str).eq(region)
                & compatibility["fold"].astype(int).eq(fold)
            ]["experiment_id"].astype(str)
        )
        cfg_ids = set(str(c.get("id")) for c in candidates)
        config_ready = boolish(cfg_bridge.get("package_launch_ready", True))
        pipeline_ready = boolish(cfg_pipeline.get("pricefm_bridge_launch_ready", True))
        manifest_ready = boolish(row["package_launch_ready"])
        rows.append({
            "region": region,
            "fold": fold,
            "config_path": cfg_path,
            "manifest_n_candidates": int(row["n_candidates"]),
            "config_n_candidates": len(candidates),
            "bridge_n_candidates": len(bridge_ids),
            "candidate_ids_match": cfg_ids == bridge_ids,
            "candidate_count_match": len(candidates) == int(row["n_candidates"]) == len(bridge_ids),
            "manifest_package_launch_ready": manifest_ready,
            "config_package_launch_ready": config_ready,
            "pipeline_pricefm_bridge_launch_ready": pipeline_ready,
            "launch_blocked_as_expected": (not manifest_ready) and (not config_ready) and (not pipeline_ready),
        })
    return pd.DataFrame(rows)


def candidate_match_table(compatibility, candidate_metrics, regions, folds):
    rows = []
    compatibility = select_scope(compatibility, regions, folds)
    candidate_metrics = select_scope(candidate_metrics, regions, folds)
    for region in unique_values(compatibility, "region"):
        folds_here = sorted(int(x) for x in compatibility[compatibility["region"].astype(str).eq(region)]["fold"].unique())
        for fold in folds_here:
            bridge_ids = set(
                compatibility[
                    compatibility["region"].astype(str).eq(region)
                    & compatibility["fold"].astype(int).eq(fold)
                ]["experiment_id"].astype(str)
            )
            reg_ids = set(
                candidate_metrics[
                    candidate_metrics["region"].astype(str).eq(region)
                    & candidate_metrics["fold"].astype(int).eq(fold)
                ]["experiment_id"].astype(str)
            )
            rows.append({
                "region": region,
                "fold": fold,
                "bridge_n_candidates": len(bridge_ids),
                "registry_n_candidates": len(reg_ids),
                "candidate_sets_match": bridge_ids == reg_ids,
                "missing_from_registry": ",".join(sorted(bridge_ids - reg_ids)),
                "missing_from_bridge": ",".join(sorted(reg_ids - bridge_ids)),
            })
    return pd.DataFrame(rows)


def method_coverage_table(coverage, regions, folds, methods):
    coverage = select_scope(coverage, regions, folds)
    if methods:
        coverage = coverage[coverage["method_id"].astype(str).isin(methods)].copy()
    out = coverage.copy()
    out["covered"] = out["covered"].map(boolish)
    return out.sort_values(["region", "fold", "method_id"]).reset_index(drop=True)


def selection_match_table(registry, compatibility, regions, folds, selection_split, selection_unit, selection_metric):
    registry = select_scope(registry, regions, folds)
    compatibility = select_scope(compatibility, regions, folds)
    rows = []
    for _, row in registry.iterrows():
        region = str(row["region"])
        fold = int(row["fold"])
        bridge_ids = set(
            compatibility[
                compatibility["region"].astype(str).eq(region)
                & compatibility["fold"].astype(int).eq(fold)
            ]["experiment_id"].astype(str)
        )
        selected_id = str(row["experiment_id"])
        rows.append({
            "region": region,
            "fold": fold,
            "experiment_id": selected_id,
            "selected_method_id": row["selected_method_id"],
            "selection_metric_value": float(row["selection_metric_value"]),
            "selected_on_split": row["selected_on_split"],
            "selected_on_unit": row["selected_on_unit"],
            "selection_metric": row["selection_metric"],
            "selected_candidate_in_bridge": selected_id in bridge_ids,
            "selection_rule_matches_contract": (
                str(row["selected_on_split"]) == str(selection_split)
                and str(row["selected_on_unit"]) == str(selection_unit)
                and str(row["selection_metric"]) == str(selection_metric)
            ),
            "test_metrics_are_audit_fields": all(col.startswith("test_") or col not in {"test_AQL", "test_MAE", "test_RMSE"} for col in row.index),
        })
    return pd.DataFrame(rows)


def read_comparison_outputs(template, fold):
    comp_dir = comparison_dir(template, fold)
    return {
        "comparison_dir": comp_dir,
        "row_audit": read_csv_required(comp_dir / "pricefm_vs_desn_row_alignment_audit.csv"),
        "metrics": read_csv_required(comp_dir / "pricefm_vs_desn_metric_summary.csv"),
        "predictions": read_csv_required(comp_dir / "pricefm_vs_desn_predictions_original.csv"),
    }


def row_identity_table(template, regions, folds, methods, expected_horizons, split):
    rows = []
    expected_horizon_set = set(int(x) for x in expected_horizons)
    for fold in folds:
        comp = read_comparison_outputs(template, fold)
        pred = comp["predictions"]
        require_columns(pred, ["method_id", "split", "origin_market_time", "response_market_time", "horizon", "tau"], "comparison predictions")
        pred = pred[pred["split"].astype(str).eq(str(split))].copy()
        if methods:
            pred = pred[pred["method_id"].astype(str).isin(methods)].copy()
        for method_id, sub in pred.groupby("method_id"):
            row_keys = ["split", "origin_market_time", "response_market_time", "horizon"]
            tau_keys = row_keys + ["tau"]
            horizons = set(int(x) for x in sub["horizon"].dropna().unique())
            duplicate_tau_rows = int(sub.duplicated(tau_keys).sum())
            response_rows = sub.drop_duplicates(row_keys)
            origins = response_rows["origin_market_time"].nunique()
            expected_response_rows = origins * len(expected_horizon_set)
            per_origin = response_rows.groupby("origin_market_time")["horizon"].agg(
                lambda x: set(int(v) for v in x)
            )
            per_origin_horizon_complete = bool(per_origin.map(lambda x: x == expected_horizon_set).all())
            rows.append({
                "region": regions[0] if len(regions) == 1 else ",".join(regions),
                "fold": int(fold),
                "method_id": method_id,
                "n_prediction_rows": int(sub.shape[0]),
                "n_unique_response_rows": int(response_rows.shape[0]),
                "n_origins": int(origins),
                "n_horizons": int(len(horizons)),
                "expected_n_horizons": int(len(expected_horizon_set)),
                "horizon_set_matches": horizons == expected_horizon_set,
                "per_origin_horizon_complete": per_origin_horizon_complete,
                "expected_response_rows": int(expected_response_rows),
                "response_row_count_matches": int(response_rows.shape[0]) == int(expected_response_rows),
                "duplicate_tau_rows": duplicate_tau_rows,
                "row_identity_pass": horizons == expected_horizon_set and per_origin_horizon_complete and duplicate_tau_rows == 0 and int(response_rows.shape[0]) == int(expected_response_rows),
            })
    return pd.DataFrame(rows).sort_values(["fold", "method_id"]).reset_index(drop=True)


def row_alignment_audit_table(template, folds, methods, baseline_method):
    rows = []
    expected = set(methods or [])
    if baseline_method:
        expected.add(str(baseline_method))
    for fold in folds:
        comp = read_comparison_outputs(template, fold)
        audit = comp["row_audit"]
        require_columns(
            audit,
            ["method_id", "available_prediction_rows", "available_unique_response_rows", "aligned_prediction_rows", "aligned_unique_response_rows"],
            "comparison row alignment audit",
        )
        for method_id in sorted(expected):
            sub = audit[audit["method_id"].astype(str).eq(method_id)].copy()
            if sub.empty:
                rows.append({
                    "fold": int(fold),
                    "method_id": method_id,
                    "present": False,
                    "available_prediction_rows": 0,
                    "aligned_prediction_rows": 0,
                    "available_unique_response_rows": 0,
                    "aligned_unique_response_rows": 0,
                    "alignment_pass": False,
                })
                continue
            row = sub.iloc[0]
            available_prediction = int(row["available_prediction_rows"])
            aligned_prediction = int(row["aligned_prediction_rows"])
            available_response = int(row["available_unique_response_rows"])
            aligned_response = int(row["aligned_unique_response_rows"])
            rows.append({
                "fold": int(fold),
                "method_id": method_id,
                "present": True,
                "available_prediction_rows": available_prediction,
                "aligned_prediction_rows": aligned_prediction,
                "available_unique_response_rows": available_response,
                "aligned_unique_response_rows": aligned_response,
                "alignment_pass": (
                    available_prediction == aligned_prediction
                    and available_response == aligned_response
                    and aligned_prediction > 0
                    and aligned_response > 0
                ),
            })
    return pd.DataFrame(rows).sort_values(["fold", "method_id"]).reset_index(drop=True)


def metric_contract_table(template, folds, methods, baseline_method, split, unit):
    rows = []
    for fold in folds:
        comp = read_comparison_outputs(template, fold)
        metric = comp["metrics"]
        require_columns(metric, ["method_id", "split", "unit", "AQL"], "comparison metrics")
        metric = metric[metric["split"].astype(str).eq(str(split)) & metric["unit"].astype(str).eq(str(unit))].copy()
        present = set(metric["method_id"].astype(str))
        expected = set(methods or [])
        if baseline_method:
            expected.add(str(baseline_method))
        for method_id in sorted(expected):
            sub = metric[metric["method_id"].astype(str).eq(method_id)]
            rows.append({
                "fold": int(fold),
                "method_id": method_id,
                "split": split,
                "unit": unit,
                "present": bool(not sub.empty),
                "AQL": float(sub["AQL"].iloc[0]) if not sub.empty and pd.notna(sub["AQL"].iloc[0]) else float("nan"),
                "is_baseline": method_id == baseline_method,
            })
        rows.append({
            "fold": int(fold),
            "method_id": "__all_expected__",
            "split": split,
            "unit": unit,
            "present": bool(expected.issubset(present)),
            "AQL": float("nan"),
            "is_baseline": False,
        })
    return pd.DataFrame(rows).sort_values(["fold", "is_baseline", "method_id"]).reset_index(drop=True)


def markdown_table(frame, columns=None, float_digits=6):
    if columns is not None:
        frame = frame.loc[:, [c for c in columns if c in frame.columns]].copy()
    if frame.empty:
        return "_No rows._"
    cols = list(frame.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in frame.iterrows():
        vals = []
        for col in cols:
            value = row[col]
            if isinstance(value, float):
                vals.append(("{:." + str(int(float_digits)) + "f}").format(value))
            else:
                vals.append(str(value).replace("\n", " ").replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(out_dir, payload, tables):
    with open(out_dir / "qdesn_model_selection_parity_report.md", "w") as f:
        f.write("# PriceFM/Q-DESN Model-Selection Parity Report\n\n")
        f.write("This no-refit report checks whether the PriceFM bridge, median registry, and fold-aligned comparison artifacts agree under the current direct-horizon PriceFM contract.\n\n")
        f.write("Overall pass: `{}`\n\n".format(payload["overall_pass"]))
        f.write("## Contract\n\n")
        f.write("- Selection split/unit/metric: `{}` / `{}` / `{}`\n".format(
            payload["selection_split"], payload["selection_unit"], payload["selection_metric"]
        ))
        f.write("- Comparison split/unit: `{}` / `{}`\n".format(
            payload["comparison_split"], payload["comparison_unit"]
        ))
        f.write("- Expected horizons: `{}`\n".format(payload["expected_horizons"]))
        f.write("- Baseline method: `{}`\n\n".format(payload["baseline_method"]))
        f.write("## Bridge Config Gate\n\n")
        f.write(markdown_table(tables["bridge_config"]))
        f.write("\n\n## Candidate Universe\n\n")
        f.write(markdown_table(tables["candidate_match"]))
        f.write("\n\n## Selection Match\n\n")
        f.write(markdown_table(tables["selection_match"]))
        f.write("\n\n## Method Coverage\n\n")
        f.write(markdown_table(tables["method_coverage"]))
        f.write("\n\n## Row Identity\n\n")
        f.write(markdown_table(
            tables["row_identity"],
            columns=[
                "fold", "method_id", "n_unique_response_rows", "n_origins",
                "n_horizons", "expected_n_horizons", "horizon_set_matches",
                "per_origin_horizon_complete", "response_row_count_matches",
                "duplicate_tau_rows", "row_identity_pass",
            ],
        ))
        f.write("\n\n## Row Alignment Audit\n\n")
        f.write(markdown_table(tables["row_alignment"]))
        f.write("\n\n## Metric Contract\n\n")
        f.write(markdown_table(tables["metric_contract"]))
        f.write("\n\n## Decision\n\n")
        if payload["overall_pass"]:
            f.write("The existing PriceFM bridge is parity-valid as a candidate/contract artifact. It remains intentionally not package-launch-ready until the generic package selector supports PriceFM direct-horizon fold scoring.\n")
        else:
            f.write("Parity failed. Do not use the bridge/registry pair for apples-to-apples selection until the failing tables are resolved.\n")


def all_true(frame, column):
    return bool(not frame.empty and frame[column].map(boolish).all())


def validate_parity(
    bridge_dir=DEFAULT_BRIDGE_DIR,
    registry_dir=DEFAULT_REGISTRY_DIR,
    comparison_dir_template=DEFAULT_COMPARISON_TEMPLATE,
    output_dir=DEFAULT_OUTPUT_DIR,
    regions=None,
    folds=None,
    selection_methods=None,
    selection_split="val",
    selection_unit="original",
    selection_metric="AQL",
    comparison_split="test",
    comparison_unit="original",
    baseline_method="pricefm_phase1_pretraining",
    expected_horizons=None,
    write=True,
):
    regions = regions or ["DE_LU"]
    folds = folds or [2, 3]
    selection_methods = selection_methods or DEFAULT_METHODS.split(",")
    expected_horizons = expected_horizons or list(range(1, 97))
    inputs = load_inputs(bridge_dir, registry_dir)

    tables = {
        "bridge_config": validate_bridge_configs(inputs["bridge_manifest"], inputs["bridge_compatibility"], regions, folds),
        "candidate_match": candidate_match_table(inputs["bridge_compatibility"], inputs["candidate_metrics"], regions, folds),
        "method_coverage": method_coverage_table(inputs["method_coverage"], regions, folds, selection_methods),
        "selection_match": selection_match_table(inputs["registry"], inputs["bridge_compatibility"], regions, folds, selection_split, selection_unit, selection_metric),
        "row_identity": row_identity_table(comparison_dir_template, regions, folds, selection_methods + [baseline_method], expected_horizons, comparison_split),
        "row_alignment": row_alignment_audit_table(comparison_dir_template, folds, selection_methods, baseline_method),
        "metric_contract": metric_contract_table(comparison_dir_template, folds, selection_methods, baseline_method, comparison_split, comparison_unit),
    }

    checks = {
        "bridge_configs_block_launch": all_true(tables["bridge_config"], "launch_blocked_as_expected"),
        "bridge_candidate_counts_match": all_true(tables["bridge_config"], "candidate_count_match"),
        "candidate_universe_matches": all_true(tables["candidate_match"], "candidate_sets_match"),
        "method_coverage_complete": all_true(tables["method_coverage"], "covered"),
        "selection_candidates_in_bridge": all_true(tables["selection_match"], "selected_candidate_in_bridge"),
        "selection_rule_matches_contract": all_true(tables["selection_match"], "selection_rule_matches_contract"),
        "row_identity_pass": all_true(tables["row_identity"], "row_identity_pass"),
        "row_alignment_pass": all_true(tables["row_alignment"], "alignment_pass"),
        "metric_contract_present": bool(
            not tables["metric_contract"].empty
            and tables["metric_contract"][tables["metric_contract"]["method_id"].eq("__all_expected__")]["present"].map(boolish).all()
        ),
    }
    payload = {
        "bridge_dir": str(repo_path(bridge_dir)),
        "registry_dir": str(repo_path(registry_dir)),
        "comparison_dir_template": comparison_dir_template,
        "regions": regions,
        "folds": [int(x) for x in folds],
        "selection_methods": selection_methods,
        "selection_split": selection_split,
        "selection_unit": selection_unit,
        "selection_metric": selection_metric,
        "comparison_split": comparison_split,
        "comparison_unit": comparison_unit,
        "baseline_method": baseline_method,
        "expected_horizons": "{}:{}".format(min(expected_horizons), max(expected_horizons)),
        "checks": checks,
        "overall_pass": all(checks.values()),
    }

    if write:
        out_dir = repo_path(output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        tables["bridge_config"].to_csv(out_dir / "parity_bridge_config.csv", index=False)
        tables["candidate_match"].to_csv(out_dir / "parity_candidate_match.csv", index=False)
        tables["method_coverage"].to_csv(out_dir / "parity_method_coverage.csv", index=False)
        tables["selection_match"].to_csv(out_dir / "parity_selection_match.csv", index=False)
        tables["row_identity"].to_csv(out_dir / "parity_row_identity.csv", index=False)
        tables["row_alignment"].to_csv(out_dir / "parity_row_alignment.csv", index=False)
        tables["metric_contract"].to_csv(out_dir / "parity_metric_contract.csv", index=False)
        write_json(out_dir / "summary.json", payload)
        write_report(out_dir, payload, tables)
        payload["outputs"] = {
            "summary": str(out_dir / "summary.json"),
            "report": str(out_dir / "qdesn_model_selection_parity_report.md"),
            "candidate_match": str(out_dir / "parity_candidate_match.csv"),
            "selection_match": str(out_dir / "parity_selection_match.csv"),
            "row_identity": str(out_dir / "parity_row_identity.csv"),
            "row_alignment": str(out_dir / "parity_row_alignment.csv"),
        }

    if not payload["overall_pass"]:
        failed = [k for k, v in checks.items() if not v]
        raise ValueError("PriceFM/Q-DESN parity failed: {}".format(", ".join(failed)))
    return {"summary": payload, "tables": tables}


def main():
    args = parser().parse_args()
    result = validate_parity(
        bridge_dir=args.bridge_dir,
        registry_dir=args.registry_dir,
        comparison_dir_template=args.comparison_dir_template,
        output_dir=args.output_dir,
        regions=parse_csv(args.regions, str) or ["DE_LU"],
        folds=parse_csv(args.folds, int) or [2, 3],
        selection_methods=parse_csv(args.selection_methods, str) or DEFAULT_METHODS.split(","),
        selection_split=args.selection_split,
        selection_unit=args.selection_unit,
        selection_metric=args.selection_metric,
        comparison_split=args.comparison_split,
        comparison_unit=args.comparison_unit,
        baseline_method=args.baseline_method,
        expected_horizons=parse_horizons(args.expected_horizons),
        write=parse_bool(args.write),
    )
    print(json.dumps(result["summary"], indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
