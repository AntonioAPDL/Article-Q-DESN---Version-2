#!/usr/bin/env python3
"""Prepare the validation-only PriceFM R120 explicit-lag BG campaign."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r120_engine import (
    MAX_EXPLICIT_LAG, POLICIES, SOURCE_WINDOW, WARMUP_STEPS, active_regions,
    fingerprint, normalize_spec, resource_estimate,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"
M_Y = (32, 48, 96, 192, 336, 480, 672, 730)
M_X = (0, 32, 48, 96, 192, 336, 480, 672, 730)
ANCHOR_GEOMETRIES = ((96, 64, 48), (384, 256, 128))
SEED = 2026092501


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, default=15)
    value.add_argument("--cpu-list", default="")
    value.add_argument("--force", action="store_true")
    return value


def exog_dimension(spec: dict[str, Any]) -> int:
    policy = str(spec["feature_policy"])
    if policy == "target_only":
        return 3
    if policy == "graph_summary_mean":
        return 6
    if policy == "graph_summary_mean_std":
        return 9
    return 3 * len(active_regions(spec))


def stage_b_candidates() -> pd.DataFrame:
    rows = []
    for m_y, m_x, policy, units in itertools.product(M_Y, M_X, POLICIES, ANCHOR_GEOMETRIES):
        spec = normalize_spec({
            "region": "BG", "feature_policy": policy, "calendar": "compact3",
            "readout": "pure_all_layers", "m_y": m_y, "m_x": m_x,
            "source_window": SOURCE_WINDOW, "warmup_steps": WARMUP_STEPS,
            "depth": len(units), "units": list(units),
            "alpha": 0.50, "rho": 0.82, "input_scale": 0.15,
            "input_fan_in": 64, "recurrent_sparsity": 0.05, "seed": SEED,
        })
        identity = fingerprint(spec)
        resources = resource_estimate(spec, exog_dimension(spec))
        rows.append({
            "candidate_id": f"r120b_{identity[:16]}", "stage": "R120B",
            "candidate_role": "complete_lag_policy_cross_anchor_geometry",
            "semantic_sha256": identity,
            "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
            **{key: value for key, value in spec.items() if key != "units"},
            "units": json.dumps(spec["units"], separators=(",", ":")),
            "exog_dimension": exog_dimension(spec), **resources,
            "selection_split": "fold1_train_internal_expanding_validation",
            "test_access_authorized": False,
        })
    frame = pd.DataFrame(rows)
    if len(frame) != 576 or frame.candidate_id.duplicated().any() or frame.semantic_sha256.duplicated().any():
        raise RuntimeError("R120B candidate identity contract failed")
    return frame.sort_values("candidate_id", kind="mergesort").reset_index(drop=True)


def run(args: argparse.Namespace) -> dict[str, Any]:
    if int(args.workers) != 15:
        raise ValueError("R120 production contract requires 15 workers")
    artifact = args.artifact_repo.resolve()
    code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)

    candidates = stage_b_candidates()
    candidate_path = output / "pricefm_stage_r120b_candidate_manifest.csv"
    candidates.to_csv(candidate_path, index=False)

    source_processed = data / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/processed_validation"
    runtime_processed = campaign / "processed"
    base_path = data / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908/regions/AT/surface_grid/configs/train_validation_data.yaml"
    base_text = base_path.read_text()
    config = yaml.safe_load(base_text)
    config["pricefm"]["processed_dir"] = str(runtime_processed)
    config["pricefm"]["splits"] = [item for item in config["pricefm"]["splits"] if "test" not in item]
    config["pricefm"]["windows"]["lag_window"] = SOURCE_WINDOW
    config_dir = output / "data_configs"; config_dir.mkdir(exist_ok=True)
    base_snapshot = config_dir / "source_train_validation_data.yaml"; base_snapshot.write_text(base_text)
    data_config = config_dir / f"data_L{SOURCE_WINDOW}.yaml"
    data_config.write_text(yaml.safe_dump(config, sort_keys=False))

    source_paths = [
        Path(__file__).resolve(), SCRIPT_DIR / "pricefm_r120_engine.py",
        SCRIPT_DIR / "414_run_pricefm_stage_r120_explicit_lag_search.py",
        SCRIPT_DIR / "415_fit_pricefm_stage_r120_quantile_atom.R",
        code / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R",
        code / "application/R/pricefm_recursive_normal_fit.R",
        code / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        code / "application/scripts/pricefm/05_build_windows.py",
        base_snapshot, data_config,
    ]
    missing = [str(path) for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"R120 source file(s) missing: {missing}")
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths
    ]).to_csv(output / "source_manifest.csv", index=False)

    control = {
        "stage": "R120", "tag": TAG, "status": "prepared_not_launched",
        "target_region": "BG", "workers": 15, "cpu_list": str(args.cpu_list),
        "stage_b_candidate_count": 576, "stage_b_retain_lag_policy": 16,
        "stage_c_candidate_count": 640, "stage_c_top_seed_specs": 10,
        "stage_d_rhs_top_k": 50, "source_window": SOURCE_WINDOW,
        "maximum_explicit_lag": MAX_EXPLICIT_LAG, "warmup_steps": WARMUP_STEPS,
        "m_y": list(M_Y), "m_x": list(M_X), "policies": list(POLICIES),
        "rhs_tau_reference": 1e-4, "rhs_tau_reference_dimension": 128,
        "rhs_tau_multipliers": [0.25, 1.0, 4.0],
        "quantiles": [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90],
        "posterior_paths": 500, "source_processed": str(source_processed),
        "runtime_processed": str(runtime_processed), "campaign_root": str(campaign),
        "data_config": str(data_config),
        "normal_runtime": str(data / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
        "cran_library": str(data / "runtime_libraries/exdqlm_cran_1p1p1"),
        "cran_manifest": str(data / "runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json"),
        "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript", "r_version": "4.6.0",
        "selection_contract": "Fold1 training internal temporal validation only",
        "outer_contract": "Fold1 freezes family/operator; Folds2-3 evaluate frozen choice",
        "test_opened": False, "joint_model_authorized": False, "mcmc_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    gates = pd.DataFrame([
        ("candidate_count", len(candidates) == 576, len(candidates)),
        ("complete_lag_cross", candidates[["m_y", "m_x"]].drop_duplicates().shape[0] == 72, candidates[["m_y", "m_x"]].drop_duplicates().shape[0]),
        ("policy_balance", candidates.feature_policy.value_counts().eq(144).all(), candidates.feature_policy.value_counts().to_dict()),
        ("geometry_balance", candidates.units.value_counts().eq(288).all(), candidates.units.value_counts().to_dict()),
        ("fixed_warmup", candidates.warmup_steps.eq(WARMUP_STEPS).all(), WARMUP_STEPS),
        ("fixed_source_window", candidates.source_window.eq(SOURCE_WINDOW).all(), SOURCE_WINDOW),
        ("pure_readout", candidates.readout.eq("pure_all_layers").all(), candidates.readout.unique().tolist()),
        ("test_absent", not candidates.test_access_authorized.astype(bool).any(), False),
    ], columns=["gate", "passed", "observed"])
    gates.to_csv(output / "gates.csv", index=False)
    if not gates.passed.all():
        raise RuntimeError("R120 preparation gate failed")
    hashes = {
        name: sha256_file(output / name) for name in (
            "pricefm_stage_r120b_candidate_manifest.csv", "source_manifest.csv",
            "launch_control.json", "gates.csv",
        )
    }
    summary = {**control, "output_sha256": hashes, "launch_authorized": True}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
