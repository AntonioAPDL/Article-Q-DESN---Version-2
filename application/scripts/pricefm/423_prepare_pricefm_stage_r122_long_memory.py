#!/usr/bin/env python3
"""Materialize the launch-blocked R122 long-memory design and provenance bundle."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r122_engine import (
    FAN_INS, M_X, M_Y, POLICIES, RESERVOIR_SEEDS, SOURCE_WINDOW,
    WARMUP_STEPS, candidate_universe, factor_coverage, fit_manifest,
    selected_panel, stage0_proxy_decision,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_bg_long_memory_extension_prep_20260929"
R121B_TAG = "pricefm_stage_r121b_bg_targeted_dense_refinement_repair_20260928"
R120_TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    return value


def _r120_control() -> dict[str, Any]:
    spec = {"region": "BG", "feature_policy": "graph_summary_mean", "calendar": "none",
            "readout": "pure_all_layers", "m_y": 730, "m_x": 0,
            "source_window": SOURCE_WINDOW, "warmup_steps": WARMUP_STEPS,
            "depth": 1, "units": [192], "alpha": .10, "rho": .82,
            "input_scale": .05, "input_fan_in": 16, "recurrent_sparsity": .05}
    return {"control_id": "r122_common_origin_r120_d1_control",
            "role": "external_model_setting_control_refit_on_r122_common_origins",
            "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
            "reuse_r120_score": False, "test_access_authorized": False}


def _stage0(r121b: Path) -> dict[str, Any]:
    shortlist = pd.read_csv(r121b / "imported_screening/unique_normal_shortlist.csv")
    cells = pd.read_csv(r121b / "al_internal/closeout/cell_metrics.csv")
    return stage0_proxy_decision(shortlist, cells)


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve(); code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)

    r121b = data / "campaigns" / R121B_TAG
    r120_prep = data / "launch_prep" / R120_TAG
    universe = candidate_universe(); panel = selected_panel(universe)
    fits = fit_manifest(panel, RESERVOIR_SEEDS[:2]); coverage = factor_coverage(panel)
    universe.to_csv(output / "candidate_universe.csv", index=False)
    panel.to_csv(output / "candidate_manifest.csv", index=False)
    fits.to_csv(output / "fit_manifest.csv", index=False)
    coverage.to_csv(output / "parameter_coverage.csv", index=False)
    pd.DataFrame([_r120_control()]).to_csv(output / "control_manifest.csv", index=False)

    stage0 = _stage0(r121b); write_json(output / "stage0_proxy_decision.json", stage0)
    target = {
        "stage": "R122", "target_region": "BG", "selection_scope": "Fold1 training only",
        "maximum_explicit_lag": 2880, "warmup_steps": 240, "source_window": 3120,
        "expected_origin_count": 940, "expected_first_origin_utc": "2022-02-04 00:00:00+00:00",
        "internal_split_boundaries": "inherit_R121_timestamps_then_intersect_common_support",
        "expected_internal_counts": {"1": {"train": 506, "validation": 125},
                                     "2": {"train": 631, "validation": 135},
                                     "3": {"train": 766, "validation": 174}},
        "recursive_future_target_access": False, "outer_selection_access": False,
        "test_access_authorized": False,
    }
    write_json(output / "target_contract.json", target)
    seeds = {"primary_seeds": list(RESERVOIR_SEEDS[:2]), "gated_third_seed": RESERVOIR_SEEDS[2],
             "canonical_al_seed": RESERVOIR_SEEDS[0], "best_seed_selection_authorized": False,
             "declaration_timing": "before_any_r122_score"}
    write_json(output / "reservoir_seed_contract.json", seeds)

    source_config = r120_prep / "data_configs/source_train_validation_data.yaml"
    if not source_config.is_file():
        source_config = r120_prep / "data_configs/data_L970.yaml"
    if not source_config.is_file():
        raise FileNotFoundError("R122 could not locate the frozen R120 train/validation data configuration")
    source_text = source_config.read_text(); config = yaml.safe_load(source_text)
    config["pricefm"]["processed_dir"] = str((campaign / "processed").resolve())
    config["pricefm"]["splits"] = [value for value in config["pricefm"]["splits"] if "test" not in str(value).lower()]
    config["pricefm"]["windows"]["lag_window"] = SOURCE_WINDOW
    config_dir = output / "data_configs"; config_dir.mkdir(exist_ok=True)
    snapshot = config_dir / "source_train_validation_data.yaml"; snapshot.write_text(source_text)
    runtime_config = config_dir / "data_L3120.yaml"; runtime_config.write_text(yaml.safe_dump(config, sort_keys=False))

    source_paths = [Path(__file__).resolve(), SCRIPT_DIR / "pricefm_r122_engine.py",
                    SCRIPT_DIR / "421_prepare_pricefm_stage_r122_stage0_calibration.py",
                    SCRIPT_DIR / "422_run_pricefm_stage_r122_stage0_calibration.py",
                    code / "application/scripts/pricefm/05_build_windows.py", snapshot, runtime_config]
    if any(not path.is_file() for path in source_paths):
        raise FileNotFoundError("R122 source bundle is incomplete")
    pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths]).to_csv(
        output / "source_manifest.csv", index=False)

    control = {
        "stage": "R122", "tag": TAG, "status": "prepared_blocked_stage0",
        "candidate_universe_count": len(universe), "search_panel_count": len(panel),
        "control_count": 1, "total_structural_count": len(panel) + 1,
        "primary_fit_count": len(fits), "m_y": list(M_Y), "m_x": list(M_X),
        "feature_policies": list(POLICIES), "input_fan_in": list(FAN_INS),
        "data_config": str(runtime_config.resolve()), "campaign_root": str(campaign),
        "workers_after_stage0": 15, "minimum_memory_gib": 200, "minimum_free_gib": 200,
        "stage0_status": stage0["status"], "launch_authorized": False,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    gates = {
        "universe_5280": len(universe) == 5280,
        "search_panel_3199": len(panel) == 3199,
        "total_with_control_3200": len(panel) + 1 == 3200,
        "primary_two_seed_fits_6398": len(fits) == 6398,
        "identities_unique": not universe.structural_sha256.duplicated().any() and not fits.fit_sha256.duplicated().any(),
        "factor_balance_exact": all(group['count'].max() - group['count'].min() <= 1 for _, group in coverage.groupby("factor")),
        "pure_readout": panel.readout.eq("pure_all_layers").all(),
        "common_window": panel.source_window.eq(3120).all(),
        "train_only": not panel.test_access_authorized.astype(bool).any(),
        "stage0_launch_blocked": not bool(stage0["passed"]),
    }
    gates = {key: bool(value) for key, value in gates.items()}
    write_json(output / "preparation_gates.json", {"checks": gates, "status": "passed" if all(gates.values()) else "failed"})
    if not all(gates.values()):
        raise RuntimeError(f"R122 preparation gate failed: {gates}")
    names = ("candidate_universe.csv", "candidate_manifest.csv", "fit_manifest.csv",
             "parameter_coverage.csv", "control_manifest.csv", "stage0_proxy_decision.json",
             "target_contract.json", "reservoir_seed_contract.json", "source_manifest.csv",
             "launch_control.json", "preparation_gates.json")
    summary = {**control, "status": "prepared_r122_long_memory_design_blocked_stage0",
               "output_sha256": {name: sha256_file(output / name) for name in names}}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
