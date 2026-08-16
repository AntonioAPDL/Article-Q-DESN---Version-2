#!/usr/bin/env python3
"""Prepare the PriceFM Stage-C row-preserving median-selection grid.

Stage C starts from the ignored Stage-C candidate manifest and writes a normal
DESN/Q-DESN experiment-grid YAML. It does not launch model fits. Each generated
experiment is scoped to exactly one region/fold and one geometry so that queue,
caution, and PriceFM-reference metadata remain attached through downstream
selection and closeout artifacts.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, repo_path, write_json


GRID_BLOCK = "pricefm_desn_experiment_grid"
DEFAULT_MANIFEST = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_manifest_20260618/stage_c_candidate_manifest.csv"
)
DEFAULT_TEMPLATE = "application/config/pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"
DEFAULT_OUTPUT_GRID = (
    "application/data_local/pricefm/configs/"
    "pricefm_desn_experiment_grid_stage_c_median_20260618.yaml"
)
DEFAULT_GENERATED_ROOT = (
    "application/data_local/pricefm/experiment_grids/"
    "pricefm_stage_c_median_20260618"
)
DEFAULT_RUN_ROOT = (
    "application/data_local/pricefm/runs/"
    "pricefm_stage_c_median_20260618"
)
DEFAULT_SUMMARY_DIR = (
    "application/data_local/pricefm/authoritative/"
    "pricefm_stage_c_median_grid_plan_20260618"
)
DEFAULT_GRID_ID = "pricefm_stage_c_median_20260618"
LOCAL_PRICEFM_PREFIX = "application/data_local/pricefm/"


REQUIRED_MANIFEST_COLUMNS = {
    "region",
    "fold",
    "queue",
    "stage_c_priority",
    "recommended_next_gate",
    "selection_split",
    "audit_split",
    "selection_metric",
    "selection_unit",
    "target_quantile",
    "paper_quantiles",
    "candidate_strategy",
    "allowed_final_methods",
    "input_scope",
    "output_scope",
    "feature_policy",
    "lead_covariate_status",
    "spatial_information_set",
    "shrink_intercept",
    "qdesn_likelihoods",
    "beta_prior",
    "exact_chunking",
    "cleanup_binary_artifacts",
    "preserve_pricefm_as_benchmark_only",
    "rationale",
    "caution_label",
}


GEOMETRIES = [
    {
        "geometry_id": "core",
        "id_suffix": "core_l096_d1_n120_a0p5_r0p9_in0p50_seed20260601",
        "lag_window": 96,
        "depth": 1,
        "units": [120],
        "alpha": 0.50,
        "rho": 0.90,
        "input_scale": 0.50,
        "seed": 20260601,
        "rationale": "Stage-C compact core geometry inherited from the Stage-B stable anchor.",
    },
    {
        "geometry_id": "lowinput",
        "id_suffix": "lowinput_l096_d1_n120_a0p5_r0p9_in0p25_seed20260603",
        "lag_window": 96,
        "depth": 1,
        "units": [120],
        "alpha": 0.50,
        "rho": 0.90,
        "input_scale": 0.25,
        "seed": 20260603,
        "rationale": "Stage-C lower-input-scale geometry for reduced reservoir saturation.",
    },
    {
        "geometry_id": "d2",
        "id_suffix": "d2_l096_d2_n080x080_a0p4_r0p9_in0p35_seed20260603",
        "lag_window": 96,
        "depth": 2,
        "units": [80, 80],
        "alpha": 0.40,
        "rho": 0.90,
        "input_scale": 0.35,
        "seed": 20260603,
        "rationale": "Stage-C compact two-layer geometry inherited from confirmed D=2 behavior.",
    },
]


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidate-manifest-csv", default=DEFAULT_MANIFEST)
    p.add_argument("--template-grid-config", default=DEFAULT_TEMPLATE)
    p.add_argument("--output-grid-config", default=DEFAULT_OUTPUT_GRID)
    p.add_argument("--grid-id", default=DEFAULT_GRID_ID)
    p.add_argument("--generated-root", default=DEFAULT_GENERATED_ROOT)
    p.add_argument("--run-root", default=DEFAULT_RUN_ROOT)
    p.add_argument("--summary-dir", default=DEFAULT_SUMMARY_DIR)
    p.add_argument("--write", type=parse_bool, default=True)
    return p


def read_yaml(path):
    with open(repo_path(path), "r") as f:
        return yaml.safe_load(f)


def write_yaml(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def config_path_value(path):
    path = repo_path(path)
    root = repo_path(".")
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def path_is_local_pricefm(path):
    value = config_path_value(path)
    return value.startswith(LOCAL_PRICEFM_PREFIX)


def require_local_pricefm_paths(paths):
    bad = [config_path_value(path) for path in paths if not path_is_local_pricefm(path)]
    if bad:
        raise ValueError("Stage-C generated paths must stay under {}: {}".format(
            LOCAL_PRICEFM_PREFIX,
            bad,
        ))


def plain_value(value):
    if pd.isna(value):
        return None
    if isinstance(value, (pd.Timestamp,)):
        return value.isoformat()
    if hasattr(value, "item"):
        try:
            value = value.item()
        except ValueError:
            pass
    if isinstance(value, float):
        if not math.isfinite(value):
            return None
        if value.is_integer():
            return int(value)
    return value


def row_payload(row):
    out = {}
    for key, value in row.items():
        out[str(key)] = plain_value(value)
    return out


def slug(value):
    text = str(value).strip().lower()
    text = text.replace("_", "")
    text = re.sub(r"[^a-z0-9]+", "", text)
    return text or "x"


def read_manifest(path):
    path = repo_path(path)
    if not path.exists() or path.stat().st_size == 0:
        raise FileNotFoundError("Stage-C candidate manifest is missing: {}".format(path))
    frame = pd.read_csv(path)
    validate_manifest(frame)
    return frame


def validate_manifest(frame):
    missing = REQUIRED_MANIFEST_COLUMNS - set(frame.columns)
    if missing:
        raise ValueError("Stage-C candidate manifest missing columns: {}".format(sorted(missing)))
    out = frame.copy()
    out["region"] = out["region"].astype(str)
    out["fold"] = out["fold"].astype(int)
    if out.empty:
        raise ValueError("Stage-C candidate manifest must be nonempty.")
    dup = out[out.duplicated(["region", "fold"], keep=False)]
    if not dup.empty:
        raise ValueError("Stage-C candidate manifest has duplicate region/fold rows: {}".format(
            dup[["region", "fold"]].drop_duplicates().to_dict("records")
        ))
    bad_gate = out[~out["recommended_next_gate"].astype(str).eq("median_screen")]
    if not bad_gate.empty:
        raise ValueError("Stage-C median grid received non-median-screen rows: {}".format(
            bad_gate[["region", "fold", "recommended_next_gate"]].to_dict("records")
        ))
    if ((out["region"].eq("FI")) & (out["fold"].eq(3))).any():
        raise ValueError("FI fold 3 must stay in the exception-rescue queue, not the generic median grid.")
    if out["stage_c_priority"].isna().any():
        raise ValueError("Stage-C candidate manifest has missing priorities.")
    allowed_queues = {"completion_folds", "diverse_new_regions"}
    bad_queue = sorted(set(out["queue"].astype(str)) - allowed_queues)
    if bad_queue:
        raise ValueError("Stage-C median grid received unsupported queues: {}".format(bad_queue))
    return True


def read_template(path):
    payload = read_yaml(path)
    if not isinstance(payload, dict) or GRID_BLOCK not in payload:
        raise ValueError("Template grid must contain top-level '{}'.".format(GRID_BLOCK))
    return payload


def common_experiment_fields(manifest_row):
    metadata = row_payload(manifest_row)
    return {
        "stage": "stage_c_local_median",
        "regions": [str(manifest_row["region"])],
        "folds": [int(manifest_row["fold"])],
        "feature_map": "window_reservoir_v1",
        "feature_policy": str(manifest_row["feature_policy"]),
        "input_scope": str(manifest_row["input_scope"]),
        "output_scope": str(manifest_row["output_scope"]),
        "lead_covariate_status": str(manifest_row["lead_covariate_status"]),
        "spatial_information_set": str(manifest_row["spatial_information_set"]),
        "candidate_source": "pricefm_stage_c_median_20260618",
        "candidate_source_final": "pricefm_stage_c_median_20260618",
        "selection_is_validation_only": True,
        "selected_on_split": str(manifest_row["selection_split"]),
        "selected_on_unit": str(manifest_row["selection_unit"]),
        "selection_metric": str(manifest_row["selection_metric"]),
        "target_label": "stage_c_local_median_validation",
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "quantile": float(manifest_row["target_quantile"]),
        "state_output": "final_layer",
        "median_registry": {
            "stage_c_manifest": metadata,
            "region": str(manifest_row["region"]),
            "fold": int(manifest_row["fold"]),
            "queue": str(manifest_row["queue"]),
            "stage_c_priority": int(manifest_row["stage_c_priority"]),
            "caution_label": str(manifest_row["caution_label"]),
            "recommended_next_gate": str(manifest_row["recommended_next_gate"]),
            "selection_is_validation_only": True,
        },
    }


def build_experiments(manifest):
    experiments = []
    ids = set()
    for _, row in manifest.sort_values(["stage_c_priority", "queue", "region", "fold"]).iterrows():
        common = common_experiment_fields(row)
        region = slug(row["region"])
        fold = int(row["fold"])
        queue = slug(row["queue"])
        for geom in GEOMETRIES:
            exp = copy.deepcopy(common)
            exp_id = "stagec_p{priority}_{queue}_{region}_f{fold}_{suffix}".format(
                priority=int(row["stage_c_priority"]),
                queue=queue,
                region=region,
                fold=fold,
                suffix=geom["id_suffix"],
            )
            if exp_id in ids:
                raise ValueError("Generated duplicate Stage-C experiment id: {}".format(exp_id))
            ids.add(exp_id)
            exp.update({
                "id": exp_id,
                "priority": int(row["stage_c_priority"]),
                "lag_window": int(geom["lag_window"]),
                "depth": int(geom["depth"]),
                "units": list(geom["units"]),
                "alpha": float(geom["alpha"]),
                "rho": float(geom["rho"]),
                "input_scale": float(geom["input_scale"]),
                "seed": int(geom["seed"]),
                "rationale": "{} Manifest rationale: {}; caution: {}.".format(
                    geom["rationale"],
                    str(row["rationale"]),
                    str(row["caution_label"]),
                ),
            })
            exp["median_registry"]["geometry_id"] = geom["geometry_id"]
            exp["median_registry"]["geometry_rationale"] = geom["rationale"]
            experiments.append(exp)
    return experiments


def build_grid(template_payload, manifest, grid_id, generated_root, run_root):
    require_local_pricefm_paths([generated_root, run_root])
    payload = copy.deepcopy(template_payload)
    grid = payload[GRID_BLOCK]
    experiments = build_experiments(manifest)
    regions = sorted(manifest["region"].astype(str).unique().tolist())
    folds = sorted(int(x) for x in manifest["fold"].unique())
    grid["grid_id"] = str(grid_id)
    grid["purpose"] = (
        "Stage-C row-preserving local median screen generated from the "
        "Stage-C candidate manifest. Selection is validation-only; PriceFM "
        "metrics remain benchmark labels."
    )
    grid["base"]["generated_root"] = str(generated_root)
    grid["base"]["run_root"] = str(run_root)
    grid["scope"]["regions"] = regions
    grid["scope"]["folds"] = folds
    grid["scope"]["quantiles"] = [0.50]
    grid["scope"]["ranking_split"] = "val"
    grid["scope"]["audit_split"] = "test"
    grid["scope"]["ranking_unit"] = "original"
    grid["scope"]["ranking_metric"] = "AQL"
    grid.setdefault("fixed", {})
    grid["fixed"]["feature_policy"] = "target_only"
    grid["fixed"]["train_origin_limit"] = 3000
    grid["fixed"]["train_origin_selection"] = "tail"
    grid["fixed"]["shrink_intercept"] = False
    grid["fixed"]["qdesn_likelihoods"] = ["al", "exal"]
    grid["experiments"] = experiments
    grid["experiment_blocks"] = []
    grid["launch"] = {
        "dry_run_completion_folds": {
            "priorities": [0],
            "experiment_jobs": 2,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Dry-run priority 0 before launch.",
        },
        "completion_folds": {
            "priorities": [0],
            "experiment_jobs": 6,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "First real Stage-C launch: completion folds only.",
        },
        "diverse_new_regions": {
            "priorities": [1],
            "experiment_jobs": 10,
            "cell_jobs": 1,
            "build_windows": True,
            "note": "Launch only after completion-fold closeout is healthy.",
        },
    }
    return payload


def planned_cell_summary(manifest, payload):
    rows = []
    for exp in payload[GRID_BLOCK]["experiments"]:
        reg = exp["regions"][0]
        fold = exp["folds"][0]
        stage_meta = exp["median_registry"]["stage_c_manifest"]
        rows.append({
            "experiment_id": exp["id"],
            "priority": int(exp["priority"]),
            "queue": stage_meta["queue"],
            "region": reg,
            "fold": int(fold),
            "geometry_id": exp["median_registry"]["geometry_id"],
            "lag_window": int(exp["lag_window"]),
            "depth": int(exp["depth"]),
            "units": json.dumps(exp["units"]),
            "alpha": float(exp["alpha"]),
            "rho": float(exp["rho"]),
            "input_scale": float(exp["input_scale"]),
            "seed": int(exp["seed"]),
            "caution_label": stage_meta["caution_label"],
            "rationale": stage_meta["rationale"],
        })
    return pd.DataFrame(rows).sort_values(["priority", "queue", "region", "fold", "geometry_id"])


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


def write_report(summary_dir, manifest, planned, grid_path, payload):
    report = summary_dir / "stage_c_median_grid_report.md"
    counts = planned.groupby(["queue", "priority"], as_index=False).size().rename(columns={"size": "n_cells"})
    by_region = planned.groupby(["queue", "region", "fold"], as_index=False).size().rename(columns={"size": "n_geometries"})
    with open(report, "w") as f:
        f.write("# PriceFM Stage-C Median Grid Plan\n\n")
        f.write("Grid config: `{}`\n\n".format(config_path_value(grid_path)))
        f.write("Grid id: `{}`\n\n".format(payload[GRID_BLOCK]["grid_id"]))
        f.write("## Purpose\n\n")
        f.write(
            "This grid is generated from the Stage-C candidate manifest. Each "
            "experiment is scoped to one region/fold/geometry so queue and "
            "caution metadata survive downstream selection and closeout.\n\n"
        )
        f.write("## Cell Counts\n\n")
        f.write(markdown_table(counts, columns=["queue", "priority", "n_cells"]))
        f.write("\n\n## Region/Fold Scope\n\n")
        f.write(markdown_table(by_region, columns=["queue", "region", "fold", "n_geometries"]))
        f.write("\n\n## Geometries\n\n")
        geom = pd.DataFrame(GEOMETRIES)
        f.write(markdown_table(
            geom,
            columns=["geometry_id", "lag_window", "depth", "units", "alpha", "rho", "input_scale", "seed"],
        ))
        f.write("\n\n## Launch Discipline\n\n")
        f.write("- Run script 12 to materialize generated configs.\n")
        f.write("- Dry-run priority 0 before any real launch.\n")
        f.write("- Launch priority 0 completion folds before priority 1 new regions.\n")
        f.write("- Do not include FI fold 3 in this generic median grid.\n")
        f.write("- Selection remains validation-only; PriceFM test metrics are audit labels.\n")
        f.write("- Clean binary R artifacts only after metrics and figures exist.\n")
    return report


def main():
    args = parser().parse_args()
    manifest = read_manifest(args.candidate_manifest_csv)
    template = read_template(args.template_grid_config)
    payload = build_grid(
        template,
        manifest,
        args.grid_id,
        args.generated_root,
        args.run_root,
    )
    planned = planned_cell_summary(manifest, payload)
    summary_dir = repo_path(args.summary_dir)
    grid_path = repo_path(args.output_grid_config)
    if bool(args.write):
        write_yaml(grid_path, payload)
        summary_dir.mkdir(parents=True, exist_ok=True)
        manifest.to_csv(summary_dir / "stage_c_candidate_manifest_used.csv", index=False)
        planned.to_csv(summary_dir / "stage_c_planned_cell_summary.csv", index=False)
        report = write_report(summary_dir, manifest, planned, grid_path, payload)
        queue_counts = (
            planned.groupby(["queue", "priority"], as_index=False)
            .size()
            .rename(columns={"size": "n_cells"})
        )
        write_json(summary_dir / "summary.json", {
            "grid_config": config_path_value(grid_path),
            "grid_id": str(args.grid_id),
            "generated_root": config_path_value(args.generated_root),
            "run_root": config_path_value(args.run_root),
            "n_manifest_rows": int(manifest.shape[0]),
            "n_experiments": int(planned.shape[0]),
            "queue_counts": queue_counts.to_dict("records"),
            "report": config_path_value(report),
        })
    print(json.dumps({
        "grid_config": config_path_value(grid_path),
        "summary_dir": config_path_value(summary_dir),
        "grid_id": str(args.grid_id),
        "n_manifest_rows": int(manifest.shape[0]),
        "n_experiments": int(planned.shape[0]),
        "queue_counts": (
            planned.groupby(["queue", "priority"], as_index=False)
            .size()
            .rename(columns={"size": "n_cells"})
            .to_dict("records")
        ),
        "write": bool(args.write),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
