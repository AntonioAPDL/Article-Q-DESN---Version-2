#!/usr/bin/env python3
"""Prepare the bounded BG extended-readout continuation after R118."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import sha256_file, write_json  # noqa: E402


STAGE = "R119"
TAG = "pricefm_stage_r119_bg_extended_all_layer_exact_cran_20260925"
R117_TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
R118_TAG = "pricefm_stage_r118_exact_cran_quantile_repair_20260925"
R111B_TAG = "pricefm_stage_r111b_bg_exposure_readout_20260922"
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DEFAULT_CPUS = tuple(range(17, 32))


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--cpu-list", default="17-31")
    return value


def parse_cpus(value: str) -> list[int]:
    result: list[int] = []
    for token in str(value).split(","):
        token = token.strip()
        if not token:
            continue
        if "-" in token:
            lower, upper = token.split("-", 1)
            result.extend(range(int(lower), int(upper) + 1))
        else:
            result.append(int(token))
    if not result or len(result) != len(set(result)) or min(result) < 0:
        raise ValueError("invalid R119 CPU list")
    return result


def selected_extended_tau0(ranking: pd.DataFrame) -> pd.Series:
    required = {"rank", "tau0", "multiplier", "mean_AQL", "mean_late_AQL", "worst_AQL"}
    if not required.issubset(ranking):
        raise ValueError(f"extended tau0 ranking lacks {sorted(required - set(ranking))}")
    values = ranking.sort_values(
        ["rank", "mean_AQL", "mean_late_AQL", "worst_AQL", "tau0"],
        kind="mergesort",
    ).reset_index(drop=True)
    selected = values.iloc[0]
    if int(selected["rank"]) != 1 or float(selected["tau0"]) <= 0:
        raise RuntimeError("R117 extended tau0 winner is invalid")
    return selected


def require_json(path: Path, status: str) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if value.get("status") != status or value.get("test_opened") is not False:
        raise RuntimeError(f"invalid frozen source: {path}")
    return value


def prepare(artifact_repo: Path, code_root: Path, output: Path, cpus: list[int]) -> dict[str, Any]:
    artifact_repo = artifact_repo.resolve()
    code_root = code_root.resolve()
    output = output.resolve()
    data = artifact_repo / "application/data_local/pricefm"
    r117 = data / "campaigns" / R117_TAG
    r118 = data / "campaigns" / R118_TAG
    r111b = data / "campaigns" / R111B_TAG
    r117_prep = data / "launch_prep" / R117_TAG
    r118_prep = data / "launch_prep" / R118_TAG

    r117_winner_path = r117 / "winner/winner.json"
    r117_winner = require_json(r117_winner_path, "frozen_r117_normal_rhs_winner")
    if (
        r117_winner.get("test_opened") is not False
        or r117_winner.get("spec", {}).get("readout") != "pure_all_layers"
        or r117_winner.get("spec", {}).get("region") != "BG"
    ):
        raise RuntimeError("R117 winner identity changed")
    tau_summary_path = r117 / "extended/tau0_closeout/summary.json"
    tau_summary = require_json(tau_summary_path, "completed_r117_extended_tau0_closeout")
    if (
        int(tau_summary.get("planned_cells", 0)) != 9
        or int(tau_summary.get("scored_cells", 0)) != 9
        or int(tau_summary.get("eligible_complete_groups", 0)) != 3
    ):
        raise RuntimeError("R117 extended tau0 screen is incomplete")
    tau_ranking_path = r117 / "extended/tau0_closeout/ranking.csv"
    selected = selected_extended_tau0(pd.read_csv(tau_ranking_path))

    r118_terminal_path = r118 / "campaign_terminal.json"
    r118_terminal = require_json(r118_terminal_path, "completed_pure_bg_not_promoted")
    r118_comparison_path = r118 / "comparison_closeout/summary.json"
    r118_comparison = require_json(
        r118_comparison_path, "completed_read_only_comparison_not_promoted"
    )
    if (
        r118_terminal.get("extended_variant_authorized") is not False
        or r118_comparison.get("promotion_authorized") is not False
        or float(r118_comparison["r118_pooled_outer_validation_AQL"]) <= float(
            r118_comparison["aligned_direct_reference_pooled_AQL"]
        )
    ):
        raise RuntimeError("R118 does not support a bounded readout diagnosis")

    r111b_summary_path = r111b / "summary.json"
    r111b_summary = require_json(r111b_summary_path, "completed_bg_exposure_readout_closeout")
    if r111b_summary.get("selected_arm") != "mixed_equal":
        raise RuntimeError("R111B exposure reference changed")

    r117_control_path = r117_prep / "launch_control.json"
    r117_control = json.loads(r117_control_path.read_text())
    exact_contract_path = r118_prep / "contracts/al_reference.json"
    exact_contract = json.loads(exact_contract_path.read_text())
    exact_sources = {
        key: exact_contract[key]
        for key in (
            "cran_library", "cran_manifest", "cran_manifest_sha256",
            "cran_tarball", "cran_tarball_sha256", "cran_adapter",
            "cran_adapter_sha256",
        )
    }
    for path_key, hash_key in (
        ("cran_manifest", "cran_manifest_sha256"),
        ("cran_tarball", "cran_tarball_sha256"),
        ("cran_adapter", "cran_adapter_sha256"),
    ):
        path = Path(exact_sources[path_key])
        if not path.is_file() or sha256_file(path) != exact_sources[hash_key]:
            raise RuntimeError(f"changed exact-CRAN source: {path}")

    spec = dict(r117_winner["spec"])
    spec["readout"] = "extended_all_layers"
    extended_winner = {
        "stage": STAGE,
        "status": "frozen_r119_extended_rhs_winner",
        "variant": "extended",
        "candidate_id": str(r117_winner["candidate_id"]),
        "tau0": float(selected["tau0"]),
        "tau0_multiplier": float(selected["multiplier"]),
        "spec": spec,
        "geometry_source": str(r117_winner_path),
        "geometry_source_sha256": sha256_file(r117_winner_path),
        "tau0_source": str(tau_ranking_path),
        "tau0_source_sha256": sha256_file(tau_ranking_path),
        "selection_split": "R117_fold1_training_internal_validation_only",
        "outer_validation_used_for_tuning": False,
        "test_opened": False,
    }

    thresholds = {
        "reference": "R118_fold1_mean_feature",
        "maximum_AQL": 20.911086149012015,
        "maximum_late_AQL": 28.19377040334674,
        "maximum_median_MAE": 50.37904255317054,
        "minimum_interval_80_coverage": 0.40,
        "maximum_interval_80_coverage": 0.95,
        "minimum_interval_80_width": 20.0,
        "maximum_interval_80_width": 150.0,
        "maximum_crossing_rate": 0.10,
        "derivation": (
            "at least 20% lower AQL, 10% lower late AQL, and 5% lower median "
            "MAE than R118 Fold 1, plus noncollapsed interval and crossing guards"
        ),
    }
    decision = {
        "stage": STAGE,
        "status": "preregistered_r119_fold1_mechanism_gate",
        "region": "BG",
        "readout": "extended_all_layers",
        "eligible_operators": ["path_specific", "mean_feature"],
        "diagnostic_only_operators": ["normal_driver"],
        "thresholds": thresholds,
        "folds_2_3_require_fold1_gate": True,
        "failed_gate_action": "stop_without_retuning",
        "promotion_authorized": False,
        "test_opened": False,
    }

    source_files = [
        code_root / "application/scripts/pricefm/409_prepare_pricefm_stage_r119_extended_readout.py",
        code_root / "application/scripts/pricefm/410_fit_pricefm_stage_r119_quantile_atom.R",
        code_root / "application/scripts/pricefm/411_run_pricefm_stage_r119_extended_readout.py",
        code_root / "application/scripts/pricefm/412_closeout_pricefm_stage_r119_comparison.py",
        code_root / "application/scripts/pricefm/pricefm_r117_engine.py",
        code_root / "application/scripts/pricefm/pricefm_r118_engine.py",
        code_root / "application/scripts/pricefm/400_run_pricefm_stage_r117_bg_pilot.py",
        code_root / "application/scripts/pricefm/336_fit_pricefm_stage_r102_recursive_normal.R",
        code_root / "application/R/pricefm_recursive_normal_fit.R",
        r117_winner_path, tau_summary_path, tau_ranking_path,
        r118_terminal_path, r118_comparison_path, r111b_summary_path,
        r117_control_path, exact_contract_path,
        Path(exact_sources["cran_manifest"]), Path(exact_sources["cran_tarball"]),
        Path(exact_sources["cran_adapter"]),
    ]
    missing = [str(path) for path in source_files if not path.is_file()]
    if missing:
        raise FileNotFoundError("R119 source bundle is incomplete: " + ", ".join(missing))

    output.mkdir(parents=True, exist_ok=True)
    winner_path = output / "frozen_extended_winner.json"
    decision_path = output / "decision_contract.json"
    write_json(winner_path, extended_winner)
    write_json(decision_path, decision)
    source_manifest = pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256_file(path), "bytes": path.stat().st_size}
        for path in source_files
    ])
    source_manifest.to_csv(output / "source_manifest.csv", index=False)

    control = {
        "stage": STAGE, "status": "prepared_not_launched", "tag": TAG,
        "region": "BG", "artifact_repo": str(artifact_repo),
        "code_root": str(code_root), "campaign_root": str(data / "campaigns" / TAG),
        "r117_source": str(r117), "r117_prep": str(r117_prep),
        "r118_source": str(r118), "r111b_source": str(r111b),
        "normal_runtime": r117_control["normal_runtime"],
        "runtime_processed": r117_control["runtime_processed"],
        "rscript": r117_control["rscript"],
        "python": str(data / "venv/bin/python"),
        "cpu_list": cpus, "workers": len(cpus), "posterior_paths": 500,
        "frozen_winner": str(winner_path),
        "frozen_winner_sha256": sha256_file(winner_path),
        "decision_contract": str(decision_path),
        "decision_contract_sha256": sha256_file(decision_path),
        "source_manifest": str(output / "source_manifest.csv"),
        "source_manifest_sha256": sha256_file(output / "source_manifest.csv"),
        **exact_sources,
        "selection_rule": "Fold1_mechanism_gate_then_frozen_Folds2_3",
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
        "exal_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    gates = pd.DataFrame([
        {"gate": "R117_extended_tau0_complete", "passed": True, "observed": 9},
        {"gate": "R118_pure_not_promotable", "passed": True, "observed": r118_comparison["r118_pooled_outer_validation_AQL"]},
        {"gate": "R111B_exposure_reference_available", "passed": True, "observed": r111b_summary["selected_arm"]},
        {"gate": "exact_CRAN_1p1p1_sources_hash_valid", "passed": True, "observed": exact_sources["cran_manifest_sha256"]},
        {"gate": "AL_only", "passed": True, "observed": "exAL_blocked"},
        {"gate": "no_promotion_authority", "passed": True, "observed": False},
    ])
    gates.to_csv(output / "gates.csv", index=False)
    summary = {
        "stage": STAGE, "status": "prepared_not_launched", "region": "BG",
        "candidate_id": extended_winner["candidate_id"],
        "readout": "extended_all_layers", "tau0": extended_winner["tau0"],
        "workers": len(cpus), "cpu_list": cpus, "posterior_paths": 500,
        "fold1_quantile_atoms": 7, "conditional_folds_2_3_quantile_atoms": 14,
        "exal_atoms": 0, "joint_models": 0, "mcmc_models": 0,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    args = parser().parse_args()
    artifact = args.artifact_repo.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    result = prepare(artifact, args.code_root, output, parse_cpus(args.cpu_list))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
