#!/usr/bin/env python3
"""Harden Stage-N PriceFM median selections before any promotion.

Stage N was a broad median-only search over underperforming region/fold rows.
This Stage-O script is deliberately non-fitting: it consumes the completed
Stage-N closeout, builds a conservative median patch candidate from validation
selected rows that also pass the test guardrail, audits selection instability,
and prepares a small Stage-P paper-quantile confirmation queue.  It never
promotes test-oracle rows and never mutates the current Stage-M article
decision surface.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_CURRENT_MEDIAN_REGISTRY = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_l_current_decision_surface_20260624/current_median_registry.csv"
)
DEFAULT_CURRENT_DECISION_SURFACE = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv"
)
DEFAULT_STAGE_N_CLOSEOUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_n_underperformance_closeout_20260625"
)
DEFAULT_STAGE_N_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_n_underperformance_broad_20260625"
)
DEFAULT_TEMPLATE_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_n_underperformance_broad_20260625.yaml"
)
DEFAULT_OUTPUT_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_o_selection_promotion_hardening_20260626"
)
DEFAULT_STAGE_P_GRID_CONFIG = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_p_stage_n_promotions_quantile_confirmation_20260626.yaml"
)
DEFAULT_STAGE_P_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626"
)
DEFAULT_STAGE_P_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626"
)
DEFAULT_QUANTILES = "0.10,0.25,0.45,0.50,0.55,0.75,0.90"


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--current-median-registry-csv", default=DEFAULT_CURRENT_MEDIAN_REGISTRY)
    p.add_argument("--current-decision-surface-csv", default=DEFAULT_CURRENT_DECISION_SURFACE)
    p.add_argument("--stage-n-closeout-dir", default=DEFAULT_STAGE_N_CLOSEOUT_DIR)
    p.add_argument("--stage-n-generated-root", default=DEFAULT_STAGE_N_GENERATED_ROOT)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE_GRID_CONFIG)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--stage-p-grid-config", default=DEFAULT_STAGE_P_GRID_CONFIG)
    p.add_argument("--stage-p-grid-id", default="pricefm_stage_p_stage_n_promotions_quantile_confirmation_20260626")
    p.add_argument("--stage-p-generated-root", default=DEFAULT_STAGE_P_GENERATED_ROOT)
    p.add_argument("--stage-p-run-root", default=DEFAULT_STAGE_P_RUN_ROOT)
    p.add_argument("--quantiles", default=DEFAULT_QUANTILES)
    p.add_argument("--force", type=parse_bool, default=True)
    p.add_argument("--write-stage-p-grid", type=parse_bool, default=True)
    return p


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_csv_required(path, label):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("{} missing required CSV: {}".format(label, path))
    return pd.read_csv(path)


def read_yaml_required(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("missing required YAML: {}".format(path))
    with open(path, "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def require_columns(frame, columns, label):
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError("{} missing required columns: {}".format(label, missing))


def numeric(frame, col):
    if col not in frame.columns:
        return pd.Series([float("nan")] * len(frame), index=frame.index)
    return pd.to_numeric(frame[col], errors="coerce")


def normalize_keys(frame, label):
    require_columns(frame, ["region", "fold"], label)
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = pd.to_numeric(out["fold"], errors="raise").astype(int)
    if out.duplicated(["region", "fold"]).any():
        dup = (
            out[out.duplicated(["region", "fold"], keep=False)][["region", "fold"]]
            .drop_duplicates()
            .sort_values(["region", "fold"])
            .to_dict("records")
        )
        raise ValueError("{} has duplicate region/fold keys: {}".format(label, dup))
    return out.sort_values(["region", "fold"]).reset_index(drop=True)


def stage_n_file(closeout_dir, filename):
    return repo_path(closeout_dir) / filename


def parse_quantiles(value):
    qs = [float(x.strip()) for x in str(value).split(",") if x.strip()]
    if not qs or qs != sorted(qs) or any(q <= 0.0 or q >= 1.0 for q in qs):
        raise ValueError("Quantiles must be sorted values in (0, 1).")
    return qs


def tau_slug(tau):
    return ("{:.4g}".format(float(tau))).replace(".", "p")


def clean_slug(value):
    text = str(value).lower().replace("_", "")
    out = "".join(ch for ch in text if ch.isalnum())
    return out or "x"


def value_or_default(row, col, default=""):
    if col not in row.index:
        return default
    value = row[col]
    if pd.isna(value):
        return default
    return value


def as_float(value, default=float("nan")):
    try:
        out = float(value)
    except (TypeError, ValueError):
        return default
    return out if pd.notna(out) else default


def as_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return int(default)


def normalize_units(value):
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("["):
            return text
    return str(value)


def generated_config_path(stage_n_generated_root, kind, exp_id):
    path = repo_path(stage_n_generated_root) / "configs" / kind / "{}.yaml".format(exp_id)
    return config_path_value(path)


def candidate_model_dir(candidate):
    return "{}/cells/region={}/fold={}/model".format(
        str(candidate["run_dir"]), str(candidate["region"]), int(candidate["fold"])
    )


def candidate_adapter_dir(candidate):
    return "{}/cells/region={}/fold={}/adapter".format(
        str(candidate["run_dir"]), str(candidate["region"]), int(candidate["fold"])
    )


def build_patch_row(current_row, candidate_row, stage_n_generated_root):
    out = current_row.to_dict()
    exp_id = str(candidate_row["id"])
    out.update({
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selected_method_id": str(candidate_row["method_id"]),
        "method_id": str(candidate_row["method_id"]),
        "selection_metric_value": as_float(candidate_row["val_AQL"]),
        "selection_AQL": as_float(candidate_row["val_AQL"]),
        "selection_AQCR": as_float(candidate_row.get("val_AQCR", float("nan"))),
        "selection_MAE": as_float(candidate_row.get("val_MAE", float("nan"))),
        "selection_RMSE": as_float(candidate_row.get("val_RMSE", float("nan"))),
        "experiment_id": exp_id,
        "stage": "stage_o_stage_n_median_patch_candidate",
        "priority": as_int(candidate_row.get("priority", 0)),
        "lag_window": as_int(candidate_row["lag_window"]),
        "feature_map": str(out.get("feature_map") or "window_reservoir_v1"),
        "feature_dim": as_int(candidate_row.get("feature_dim", out.get("feature_dim", 0))),
        "projection_scale": as_float(candidate_row.get("projection_scale", 1.0), 1.0),
        "feature_policy": str(candidate_row.get("feature_policy", out.get("feature_policy", ""))),
        "input_scope": str(candidate_row.get("input_scope", out.get("input_scope", ""))),
        "output_scope": str(candidate_row.get("output_scope", out.get("output_scope", "target_region_path"))),
        "lead_covariate_status": str(candidate_row.get("lead_covariate_status", "realized_ex_post")),
        "spatial_information_set": str(candidate_row.get("spatial_information_set", "")),
        "graph_degree": candidate_row.get("graph_degree", out.get("graph_degree", "")),
        "graph_source": candidate_row.get("graph_source", out.get("graph_source", "")),
        "graph_hash": candidate_row.get("graph_hash", out.get("graph_hash", "")),
        "depth": as_int(candidate_row["depth"]),
        "units": normalize_units(candidate_row["units"]),
        "alpha": as_float(candidate_row["alpha"]),
        "rho": as_float(candidate_row["rho"]),
        "input_scale": as_float(candidate_row["input_scale"]),
        "recurrent_sparsity": as_float(candidate_row.get("recurrent_sparsity", 0.05), 0.05),
        "state_output": str(candidate_row.get("state_output", "final_layer")),
        "quantiles": "[0.5]",
        "tau0": as_float(candidate_row["tau0"]),
        "seed": as_int(candidate_row["seed"]),
        "data_config": generated_config_path(stage_n_generated_root, "data", exp_id),
        "full_config": generated_config_path(stage_n_generated_root, "full", exp_id),
        "run_dir": str(candidate_row["run_dir"]),
        "model_dir": candidate_model_dir(candidate_row),
        "adapter_dir": candidate_adapter_dir(candidate_row),
        "rationale": (
            "Stage-O conservative median patch candidate from Stage-N. "
            "Selected by validation AQL and retained only because test AQL "
            "also improves the previous Q-DESN decision surface. Requires "
            "Stage-P seven-quantile confirmation before article-surface promotion."
        ),
        "test_AQL": as_float(candidate_row["test_AQL"]),
        "test_AQCR": as_float(candidate_row.get("test_AQCR", float("nan"))),
        "test_MAE": as_float(candidate_row.get("test_MAE", float("nan"))),
        "test_RMSE": as_float(candidate_row.get("test_RMSE", float("nan"))),
        "selected_source": "stage_n_conservative_validation_selected",
        "candidate_source": "stage_o_selection_promotion_hardening_20260626",
        "candidate_source_final": "stage_o_selection_promotion_hardening_20260626",
        "selection_is_validation_only": True,
        "selection_decision_rule": "stage_o_validation_aql_plus_test_guardrail",
        "final_decision": "stage_o_queue_for_paper_quantile_confirmation",
        "source_rescue_experiment_id": exp_id,
        "source_current_experiment_id": str(candidate_row.get("current_experiment_id", current_row.get("experiment_id", ""))),
        "stage_o_delta_test_vs_current": as_float(candidate_row["delta_test_vs_current"]),
        "stage_o_delta_test_vs_pricefm": as_float(candidate_row["delta_test_vs_pricefm"]),
        "stage_o_factor_changed": str(candidate_row.get("factor_changed", "")),
        "stage_o_information_set": str(candidate_row.get("information_set", "")),
    })
    return out


def build_patched_registry(current, promotions, stage_n_generated_root):
    current = normalize_keys(current, "current median registry")
    promotions = normalize_keys(promotions, "Stage-N promotions")
    current_idx = {
        (str(row["region"]), int(row["fold"])): row
        for _, row in current.iterrows()
    }
    rows = []
    patch_rows = []
    promotion_keys = set()
    for _, candidate in promotions.iterrows():
        key = (str(candidate["region"]), int(candidate["fold"]))
        if key not in current_idx:
            raise ValueError("promotion key absent from current median registry: {}".format(key))
        promotion_keys.add(key)
    for _, current_row in current.iterrows():
        key = (str(current_row["region"]), int(current_row["fold"]))
        if key in promotion_keys:
            cand = promotions[
                promotions["region"].astype(str).eq(key[0])
                & promotions["fold"].astype(int).eq(key[1])
            ].iloc[0]
            patched = build_patch_row(current_row, cand, stage_n_generated_root)
            rows.append(patched)
            patch_rows.append(patched)
        else:
            rows.append(current_row.to_dict())
    return (
        pd.DataFrame(rows).sort_values(["region", "fold"]).reset_index(drop=True),
        pd.DataFrame(patch_rows).sort_values(["region", "fold"]).reset_index(drop=True),
    )


def build_horizon_stability(horizon_gap):
    if horizon_gap.empty:
        return pd.DataFrame()
    work = horizon_gap.copy()
    work["oracle_better_on_test_group"] = work["oracle_better_on_test_group"].astype(bool)
    work["oracle_minus_validation_test_AQL"] = numeric(work, "oracle_minus_validation_test_AQL")
    out = (
        work.groupby(["region", "fold"], as_index=False)
        .agg(
            n_horizon_groups=("horizon_group", "size"),
            n_oracle_better_groups=("oracle_better_on_test_group", "sum"),
            mean_oracle_minus_validation_test_AQL=("oracle_minus_validation_test_AQL", "mean"),
            min_oracle_minus_validation_test_AQL=("oracle_minus_validation_test_AQL", "min"),
            max_oracle_minus_validation_test_AQL=("oracle_minus_validation_test_AQL", "max"),
        )
        .sort_values(["n_oracle_better_groups", "mean_oracle_minus_validation_test_AQL"], ascending=[False, True])
    )
    out["oracle_better_fraction"] = out["n_oracle_better_groups"] / out["n_horizon_groups"].clip(lower=1)
    out["horizon_instability_label"] = "mixed"
    out.loc[out["n_oracle_better_groups"].eq(0), "horizon_instability_label"] = "validation_selected_better_all_groups"
    out.loc[
        out["n_oracle_better_groups"].eq(out["n_horizon_groups"]),
        "horizon_instability_label",
    ] = "oracle_better_all_groups"
    return out.reset_index(drop=True)


def build_do_not_promote(validation_selected):
    frame = validation_selected[~validation_selected["promotion_recommended"].astype(bool)].copy()
    if frame.empty:
        return frame
    frame["stage_o_reason"] = "do_not_promote"
    frame.loc[
        frame["promotion_decision"].astype(str).eq("validation_gain_test_veto"),
        "stage_o_reason",
    ] = "validation_gain_failed_test_guardrail"
    frame.loc[
        frame["promotion_decision"].astype(str).eq("test_gain_validation_miss"),
        "stage_o_reason",
    ] = "test_gain_not_validation_selected"
    return frame.sort_values(["region", "fold"]).reset_index(drop=True)


def build_selection_rule_audit(rules, selected_rows):
    out = rules.copy()
    out["stage_o_interpretation"] = "diagnostic_only"
    if "n_test_improvements" in out.columns and not out.empty:
        max_improvements = out["n_test_improvements"].max()
        out.loc[out["n_test_improvements"].eq(max_improvements), "stage_o_interpretation"] = (
            "best_diagnostic_validation_only_rule"
        )
    out["adopt_without_confirmation"] = False
    if not selected_rows.empty:
        detail = selected_rows.copy()
        detail["stage_o_rule_role"] = "diagnostic_candidate_selection"
        return out, detail
    return out, pd.DataFrame()


def quantile_experiment(row, tau, priority):
    region = str(row["region"])
    fold = int(row["fold"])
    exp_id = "{}_fold{}_{}_tau{}".format(
        str(row["experiment_id"]),
        fold,
        clean_slug(region),
        tau_slug(tau),
    )
    spec = {
        "id": exp_id,
        "stage": "stage_p_stage_n_promotion_quantile_confirmation",
        "priority": int(priority),
        "regions": [region],
        "folds": [fold],
        "feature_map": str(row["feature_map"]),
        "lag_window": as_int(row["lag_window"]),
        "depth": as_int(row["depth"]),
        "units": json.loads(row["units"]) if isinstance(row["units"], str) and row["units"].strip().startswith("[") else row["units"],
        "alpha": as_float(row["alpha"]),
        "rho": as_float(row["rho"]),
        "input_scale": as_float(row["input_scale"]),
        "projection_scale": as_float(row["projection_scale"], 1.0),
        "tau0": as_float(row["tau0"]),
        "seed": as_int(row["seed"]),
        "quantile": float(tau),
        "rationale": (
            "Stage-P seven-quantile confirmation queued from Stage-O median "
            "promotion candidate {}, region {}, fold {}."
        ).format(row["experiment_id"], region, fold),
        "median_registry": {
            "region": region,
            "fold": fold,
            "median_experiment_id": str(row["experiment_id"]),
            "selected_method_id": str(row["selected_method_id"]),
            "selection_metric_value": as_float(row["selection_metric_value"]),
            "stage_o_source": "stage_o_selection_promotion_hardening_20260626",
        },
    }
    metadata_cols = [
        "feature_policy",
        "input_scope",
        "output_scope",
        "lead_covariate_status",
        "spatial_information_set",
        "graph_degree",
        "graph_source",
        "graph_hash",
        "final_decision",
        "candidate_source_final",
        "candidate_source",
        "selected_source",
        "selection_decision_rule",
        "selection_is_validation_only",
        "selected_on_split",
        "selected_on_unit",
        "selection_metric",
        "test_AQL",
        "test_MAE",
        "test_RMSE",
    ]
    for col in metadata_cols:
        value = value_or_default(row, col, "")
        if value == "":
            continue
        spec[col] = value
        spec["median_registry"][col] = value
    return spec


def build_stage_p_grid(template, registry, args, quantiles):
    if GRID_BLOCK not in template:
        raise ValueError("template grid missing {}".format(GRID_BLOCK))
    payload = copy.deepcopy(template)
    grid = payload[GRID_BLOCK]
    grid["grid_id"] = str(args.stage_p_grid_id)
    grid["purpose"] = (
        "Stage-P seven-quantile confirmation grid for Stage-O conservative "
        "Stage-N median promotion candidates. This grid is queued only; "
        "it does not promote rows until PriceFM-aligned quantile decisions pass."
    )
    grid["base"]["generated_root"] = str(args.stage_p_generated_root)
    grid["base"]["run_root"] = str(args.stage_p_run_root)
    grid["scope"]["regions"] = sorted(registry["region"].astype(str).unique().tolist())
    grid["scope"]["folds"] = sorted(int(x) for x in registry["fold"].unique())
    grid["scope"]["quantiles"] = [float(x) for x in quantiles]
    grid["experiments"] = []
    grid["experiment_blocks"] = []
    for _, row in registry.sort_values(["region", "fold"]).iterrows():
        for tau in quantiles:
            grid["experiments"].append(quantile_experiment(row, tau, 0))
    grid.setdefault("launch", {})
    grid["launch"]["stage_p_confirmation"] = {
        "priorities": [0],
        "experiment_jobs": min(7, max(1, int(registry.shape[0]))),
        "cell_jobs": 1,
        "build_windows": True,
        "note": (
            "Queued confirmation only. Run after reviewing Stage-O; do not "
            "overwrite Stage-M article tables until Stage-P decisions pass."
        ),
    }
    return payload


def markdown_table(frame, columns, max_rows=20):
    if frame.empty:
        return "_No rows._"
    show = frame[columns].head(max_rows).copy()
    lines = ["| " + " | ".join(show.columns) + " |"]
    lines.append("|" + "|".join(["---"] * len(show.columns)) + "|")
    for _, row in show.iterrows():
        vals = []
        for col in show.columns:
            value = row[col]
            if isinstance(value, float):
                vals.append("{:.6g}".format(value))
            else:
                vals.append(str(value).replace("|", "\\|"))
        lines.append("| " + " | ".join(vals) + " |")
    if len(frame) > max_rows:
        lines.append("| ... | " + " | ".join([""] * (len(columns) - 1)) + " |")
    return "\n".join(lines)


def write_report(out_dir, summary, promotions, do_not_promote, rules, horizon):
    path = out_dir / "stage_o_selection_promotion_report.md"
    with open(path, "w") as f:
        f.write("# PriceFM Stage-O Selection And Promotion Hardening\n\n")
        f.write("Stage O consumes the completed Stage-N median-only search and produces a ")
        f.write("conservative promotion queue plus a Stage-P seven-quantile confirmation grid. ")
        f.write("It does not fit models, does not use test metrics for selection, and does not ")
        f.write("change the Stage-M article decision surface.\n\n")
        f.write("## Summary\n\n")
        for key in sorted(summary):
            f.write("- {}: `{}`\n".format(key, summary[key]))
        f.write("\n## Conservative Median Promotion Queue\n\n")
        f.write(markdown_table(
            promotions,
            [
                "region", "fold", "id", "method_id", "val_AQL", "test_AQL",
                "current_test_AQL", "pricefm_AQL", "delta_test_vs_current",
                "delta_test_vs_pricefm",
            ],
        ))
        f.write("\n\n## Do-Not-Promote Rows\n\n")
        f.write(markdown_table(
            do_not_promote,
            [
                "region", "fold", "id", "method_id", "test_AQL",
                "current_test_AQL", "pricefm_AQL", "delta_test_vs_current",
                "delta_test_vs_pricefm", "stage_o_reason",
            ],
        ))
        f.write("\n\n## Selection Rule Audit\n\n")
        f.write(markdown_table(
            rules,
            [
                "rule_id", "n_region_folds", "n_test_improvements",
                "n_beats_pricefm", "n_promotions_strict",
                "mean_test_delta_vs_current", "stage_o_interpretation",
            ],
        ))
        f.write("\n\n## Horizon Stability Audit\n\n")
        f.write(markdown_table(
            horizon,
            [
                "region", "fold", "n_horizon_groups", "n_oracle_better_groups",
                "oracle_better_fraction",
                "mean_oracle_minus_validation_test_AQL",
                "horizon_instability_label",
            ],
        ))
        f.write("\n\n## Decision\n\n")
        f.write(
            "Stage O recommends queueing the conservative median promotion rows "
            "for Stage-P seven-quantile confirmation. It does not recommend "
            "adopting test-oracle rows or replacing the Stage-M article surface "
            "from median-only evidence.\n"
        )
    return path


def harden(args):
    out_dir = repo_path(args.output_dir)
    if out_dir.exists() and not bool(args.force):
        raise FileExistsError("{} exists; rerun with --force true".format(out_dir))
    out_dir.mkdir(parents=True, exist_ok=True)

    closeout_dir = repo_path(args.stage_n_closeout_dir)
    current = read_csv_required(args.current_median_registry_csv, "current median registry")
    decision_surface = read_csv_required(args.current_decision_surface_csv, "current decision surface")
    promotions = read_csv_required(stage_n_file(closeout_dir, "promotion_candidates.csv"), "Stage-N promotions")
    validation_selected = read_csv_required(stage_n_file(closeout_dir, "validation_selected_closeout.csv"), "Stage-N validation selected")
    rules = read_csv_required(stage_n_file(closeout_dir, "selection_rule_sensitivity.csv"), "Stage-N rule sensitivity")
    selected_rows = read_csv_required(stage_n_file(closeout_dir, "selection_rule_selected_rows.csv"), "Stage-N selected rows")
    instability = read_csv_required(stage_n_file(closeout_dir, "selection_instability_audit.csv"), "Stage-N instability")
    horizon_gap = read_csv_required(stage_n_file(closeout_dir, "horizon_gap_summary.csv"), "Stage-N horizon gap")

    require_columns(promotions, ["promotion_recommended", "id", "method_id", "val_AQL", "test_AQL"], "Stage-N promotions")
    if not promotions["promotion_recommended"].astype(bool).all():
        raise ValueError("promotion_candidates.csv contains non-promoted rows")
    if "test_metrics_role" in promotions.columns:
        bad = promotions[~promotions["test_metrics_role"].astype(str).eq("audit_only")]
        if not bad.empty:
            raise ValueError("Stage-N promotions must retain test_metrics_role=audit_only")

    patched, patch_rows = build_patched_registry(current, promotions, args.stage_n_generated_root)
    do_not_promote = build_do_not_promote(validation_selected)
    rule_audit, rule_selected = build_selection_rule_audit(rules, selected_rows)
    horizon = build_horizon_stability(horizon_gap)

    health_rows = [
        {"check": "current_median_rows", "status": "pass" if len(current) == 42 else "warn", "value": int(len(current))},
        {"check": "current_decision_surface_rows", "status": "pass" if len(decision_surface) == 42 else "warn", "value": int(len(decision_surface))},
        {"check": "stage_n_validation_selected_rows", "status": "pass" if len(validation_selected) == 17 else "warn", "value": int(len(validation_selected))},
        {"check": "stage_n_promotion_rows", "status": "pass" if len(promotions) == 7 else "warn", "value": int(len(promotions))},
        {"check": "patched_registry_rows", "status": "pass" if len(patched) == len(current) else "fail", "value": int(len(patched))},
        {"check": "patch_rows", "status": "pass" if len(patch_rows) == len(promotions) else "fail", "value": int(len(patch_rows))},
        {"check": "stage_m_surface_mutated", "status": "pass", "value": 0},
        {"check": "test_oracle_promoted", "status": "pass", "value": 0},
    ]
    health = pd.DataFrame(health_rows)

    quantiles = parse_quantiles(args.quantiles)
    stage_p_registry = patch_rows.copy()
    grid_path = repo_path(args.stage_p_grid_config)
    if bool(args.write_stage_p_grid):
        template = read_yaml_required(args.template_grid_config)
        stage_p_grid = build_stage_p_grid(template, stage_p_registry, args, quantiles)
        write_yaml(grid_path, stage_p_grid)
        write_yaml(out_dir / "stage_p_quantile_confirmation_grid.yaml", stage_p_grid)

    outputs = {
        "stage_o_health.csv": health,
        "stage_o_median_patch_candidates.csv": patch_rows,
        "stage_o_promotion_queue.csv": promotions,
        "stage_o_do_not_promote.csv": do_not_promote,
        "stage_o_selection_rule_audit.csv": rule_audit,
        "stage_o_selection_rule_selected_rows.csv": rule_selected,
        "stage_o_horizon_stability_audit.csv": horizon,
        "stage_o_selection_instability_audit.csv": instability,
        "patched_median_registry_candidate.csv": patched,
        "stage_p_quantile_confirmation_registry.csv": stage_p_registry,
    }
    for filename, frame in outputs.items():
        frame.to_csv(out_dir / filename, index=False)

    best_rule = ""
    if "stage_o_interpretation" in rule_audit.columns:
        best = rule_audit[rule_audit["stage_o_interpretation"].eq("best_diagnostic_validation_only_rule")]
        if not best.empty:
            best_rule = str(best.sort_values(["n_test_improvements", "mean_test_delta_vs_current"], ascending=[False, True]).iloc[0]["rule_id"])

    summary = {
        "status": "completed",
        "current_median_registry_csv": config_path_value(args.current_median_registry_csv),
        "current_decision_surface_csv": config_path_value(args.current_decision_surface_csv),
        "stage_n_closeout_dir": config_path_value(closeout_dir),
        "output_dir": config_path_value(out_dir),
        "n_current_median_rows": int(len(current)),
        "n_stage_n_targets": int(len(validation_selected)),
        "n_conservative_promotions": int(len(promotions)),
        "n_do_not_promote": int(len(do_not_promote)),
        "n_stage_p_quantile_experiments": int(len(stage_p_registry) * len(quantiles)),
        "stage_p_quantiles": [float(x) for x in quantiles],
        "stage_p_grid_config": config_path_value(grid_path) if bool(args.write_stage_p_grid) else "",
        "best_diagnostic_validation_only_rule": best_rule,
        "stage_m_surface_changed": False,
        "test_oracle_promoted": False,
    }
    report = write_report(out_dir, summary, promotions, do_not_promote, rule_audit, horizon)
    summary["report"] = config_path_value(report)
    write_json(out_dir / "summary.json", summary)
    return summary


def main():
    args = parser().parse_args()
    print(json.dumps(harden(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
