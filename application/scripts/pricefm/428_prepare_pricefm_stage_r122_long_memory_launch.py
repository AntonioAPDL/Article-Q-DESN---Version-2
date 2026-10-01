#!/usr/bin/env python3
"""Authorize and materialize the leakage-firewalled R122 long-memory launch."""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

import pandas as pd
import yaml

from pricefm_common import sha256_file, write_json
from pricefm_r122_engine import RESERVOIR_SEEDS, exogenous_dimension, fingerprint


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
TAG = "pricefm_stage_r122_bg_long_memory_screen_20261001"
DESIGN_TAG = "pricefm_stage_r122_bg_long_memory_extension_prep_20260929"
STAGE0B_TAG = "pricefm_stage_r122_stage0b_complete_proxy_confirmation_20260930"
EVALUATION_TAG = "pricefm_stage_r122_evaluation_contract_20260930"
R120_TAG = "pricefm_stage_r120_bg_explicit_lag_all_layer_search_20260925"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--workers", type=int, default=15)
    value.add_argument("--force", action="store_true")
    return value


def _read(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _copy(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def _git(code: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(code), *arguments], text=True,
    ).strip()


def _control_rows() -> tuple[pd.DataFrame, pd.DataFrame]:
    spec = {
        "region": "BG", "feature_policy": "graph_summary_mean", "calendar": "none",
        "readout": "pure_all_layers", "m_y": 730, "m_x": 0,
        "source_window": 3120, "warmup_steps": 240,
        "depth": 1, "units": [192], "alpha": .10, "rho": .82,
        "input_scale": .05, "input_fan_in": 16, "recurrent_sparsity": .05,
    }
    structural = fingerprint(spec)
    candidate = pd.DataFrame([{
        "candidate_id": "r122_common_origin_r120_d1_control",
        "structural_sha256": structural,
        "spec_json": json.dumps(spec, sort_keys=True, separators=(",", ":")),
        "role": "external_model_setting_control_refit_on_r122_common_origins",
        "input_dimension": spec["m_y"] + (spec["m_x"] + 1) * exogenous_dimension(spec["feature_policy"]),
        "readout_dimension": 1 + sum(spec["units"]),
        "test_access_authorized": False,
    }])
    fits = []
    for seed in RESERVOIR_SEEDS[:2]:
        fit_hash = fingerprint({"structural_sha256": structural, "reservoir_seed": int(seed)})
        fits.append({
            "fit_id": f"r122f_{fit_hash[:16]}",
            "candidate_id": candidate.iloc[0].candidate_id,
            "structural_sha256": structural,
            "reservoir_seed": int(seed), "fit_sha256": fit_hash,
            "canonical_seed": int(seed) == int(RESERVOIR_SEEDS[0]),
            "role": "external_control", "test_access_authorized": False,
        })
    return candidate, pd.DataFrame(fits)


def run(args: argparse.Namespace) -> dict[str, Any]:
    if int(args.workers) != 15:
        raise ValueError("R122 launch contract requires exactly 15 workers")
    artifact = args.artifact_repo.resolve(); code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    design = data / "launch_prep" / DESIGN_TAG
    stage0b = data / "campaigns" / STAGE0B_TAG
    evaluation = data / "launch_prep" / EVALUATION_TAG
    r120_prep = data / "launch_prep" / R120_TAG
    r120_campaign = data / "campaigns" / R120_TAG

    terminal = _read(stage0b / "terminal.json")
    decision = _read(stage0b / "closeout/proxy_decision.json")
    evaluation_contract = _read(evaluation / "evaluation_contract.json")
    if terminal.get("status") != "R122_STAGE0B_PROXY_AUTHORIZED" or not decision.get("passed"):
        raise RuntimeError("R122 broad launch is not authorized by Stage 0B")
    if evaluation_contract.get("status") != "R122_EVALUATION_CONTRACT_READY":
        raise RuntimeError("R122 evaluation contract is not ready")

    inherited = (
        "candidate_universe.csv", "candidate_manifest.csv", "fit_manifest.csv",
        "parameter_coverage.csv", "target_contract.json", "reservoir_seed_contract.json",
    )
    for name in inherited:
        _copy(design / name, output / name)
    candidates = pd.read_csv(output / "candidate_manifest.csv")
    fits = pd.read_csv(output / "fit_manifest.csv")
    controls, control_fits = _control_rows()
    controls.to_csv(output / "control_manifest.csv", index=False)
    control_fits.to_csv(output / "control_fit_manifest.csv", index=False)

    primary = fits.merge(
        candidates[[
            "candidate_id", "structural_sha256", "spec_json",
            "input_dimension", "readout_dimension",
        ]],
        on=["candidate_id", "structural_sha256"], how="left", validate="many_to_one",
    )
    primary.insert(0, "fit_id", primary.fit_sha256.map(lambda value: f"r122f_{str(value)[:16]}"))
    primary["role"] = "search"
    control_execution = control_fits.merge(
        controls[[
            "candidate_id", "structural_sha256", "spec_json",
            "input_dimension", "readout_dimension",
        ]],
        on=["candidate_id", "structural_sha256"], how="left", validate="many_to_one",
    )
    execution = pd.concat([primary, control_execution], ignore_index=True, sort=False)
    execution = execution.sort_values(
        ["role", "candidate_id", "reservoir_seed"], kind="mergesort",
    ).reset_index(drop=True)
    execution.to_csv(output / "execution_manifest.csv", index=False)

    source_config = design / "data_configs/data_L3120.yaml"
    config = yaml.safe_load(source_config.read_text())
    config["pricefm"]["processed_dir"] = str((campaign / "processed").resolve())
    config["pricefm"]["splits"] = [
        item for item in config["pricefm"]["splits"]
        if "test" not in json.dumps(item).lower()
    ]
    config_dir = output / "data_configs"; config_dir.mkdir(exist_ok=True)
    source_config_snapshot = config_dir / "source_data_L3120.yaml"
    _copy(source_config, source_config_snapshot)
    runtime_config = config_dir / "data_L3120.yaml"
    runtime_config.write_text(yaml.safe_dump(config, sort_keys=False))
    _copy(evaluation / "evaluation_contract.json", output / "evaluation_contract.json")
    _copy(stage0b / "terminal.json", output / "stage0b_terminal.json")
    _copy(stage0b / "closeout/proxy_decision.json", output / "stage0b_proxy_decision.json")
    _copy(stage0b / "closeout/ranking.csv", output / "stage0b_ranking.csv")

    git_head = _git(code, "rev-parse", "HEAD")
    git_branch = _git(code, "branch", "--show-current")
    git_status = _git(code, "status", "--short")
    runtime_environment = {
        "python_executable": str(Path(sys.executable).absolute()),
        "python_version": platform.python_version(),
        "python_prefix": sys.prefix,
        "pandas_version": pd.__version__,
        "pyyaml_version": yaml.__version__,
        "git_head": git_head,
        "git_branch": git_branch,
        "git_worktree_clean": not bool(git_status),
    }
    write_json(output / "runtime_environment.json", runtime_environment)

    sources = [
        Path(__file__).resolve(), SCRIPT_DIR / "429_run_pricefm_stage_r122_long_memory.py",
        SCRIPT_DIR / "pricefm_r122_runtime.py", SCRIPT_DIR / "pricefm_r122_engine.py",
        SCRIPT_DIR / "pricefm_r120_engine.py", SCRIPT_DIR / "pricefm_common.py",
        SCRIPT_DIR / "420_fit_pricefm_stage_r121_quantile_atom.R",
        SCRIPT_DIR / "336_fit_pricefm_stage_r102_recursive_normal.R",
        code / "application/R/pricefm_recursive_normal_fit.R",
        SCRIPT_DIR / "pricefm_stage_r67_cran111_adapter.R",
        code / "application/scripts/pricefm/05_build_windows.py",
        code / "application/tests/test_pricefm_stage_r122_long_memory_launch.py",
        source_config_snapshot, runtime_config,
    ]
    missing = [str(path) for path in sources if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"R122 launch source bundle is incomplete: {missing}")
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256_file(path)} for path in sources
    ]).to_csv(output / "source_manifest.csv", index=False)

    r120_control = _read(r120_prep / "launch_control.json")
    control = {
        "stage": "R122", "tag": TAG, "status": "prepared_not_launched",
        "target_region": "BG", "workers": 15,
        "campaign_root": str(campaign), "data_config": str(runtime_config),
        "source_processed": r120_control["source_processed"],
        "runtime_processed": str(campaign / "processed"),
        "normal_runtime": str(data / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"),
        "cran_library": str(data / "runtime_libraries/exdqlm_cran_1p1p1"),
        "cran_manifest": str(data / "runtime_libraries/exdqlm_cran_1p1p1/pricefm_r67_cran111_install_manifest.json"),
        "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        "python_executable": str(Path(sys.executable).absolute()),
        "python_prefix": sys.prefix,
        "code_head": git_head, "code_branch": git_branch,
        "primary_fit_count": int(len(primary)), "control_fit_count": int(len(control_execution)),
        "total_fit_count": int(len(execution)), "search_structure_count": int(len(candidates)),
        "third_seed_top_k": 320, "rhs_top_k": 96, "al_shortlist_k": 3,
        "rhs_tau_pilot_top_k": 5, "rhs_tau_expansion_top_k": 20,
        "rhs_tau_pilot_multipliers": [0.01, 0.1, 10.0, 100.0],
        "rhs_tau_expansion_multipliers": [0.1, 10.0],
        "broad_score_max_origins_per_split": 48,
        "rhs_score_max_origins_per_split": 64,
        "rhs_max_iter": 500, "al_final_max_iter": 1000,
        "al_companion_max_iter": 750, "posterior_paths": 500,
        "minimum_memory_gib": 200, "minimum_free_gib": 200,
        "stage0b_terminal_sha256": sha256_file(output / "stage0b_terminal.json"),
        "stage0b_decision_sha256": sha256_file(output / "stage0b_proxy_decision.json"),
        "evaluation_contract_sha256": sha256_file(output / "evaluation_contract.json"),
        "selection_scope": "Fold1 training only with three inherited expanding blocked splits",
        "official_test_scoring_authorized": False,
        "test_access_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
    }
    write_json(output / "launch_control.json", control)
    checks = {
        "stage0b_authorized": terminal.get("proxy_authorized") is True and decision.get("passed") is True,
        "evaluation_contract_ready": evaluation_contract.get("status") == "R122_EVALUATION_CONTRACT_READY",
        "search_structures_3199": len(candidates) == 3199,
        "primary_fits_6398": len(primary) == 6398,
        "control_fits_2": len(control_execution) == 2,
        "total_fits_6400": len(execution) == 6400,
        "fit_ids_unique": not execution.fit_id.duplicated().any(),
        "fit_hashes_unique": not execution.fit_sha256.duplicated().any(),
        "all_specs_present": execution.spec_json.notna().all(),
        "two_primary_seeds": set(primary.reservoir_seed.astype(int)) == set(RESERVOIR_SEEDS[:2]),
        "test_firewall": not execution.test_access_authorized.astype(bool).any(),
        "runtime_config_has_no_test": "test" not in json.dumps(config["pricefm"]["splits"]).lower(),
        "code_worktree_clean": not bool(git_status),
        "dedicated_task_branch": git_branch.startswith("work/pricefm-r122-"),
    }
    checks = {key: bool(value) for key, value in checks.items()}
    write_json(output / "preparation_gates.json", {
        "status": "passed" if all(checks.values()) else "failed", "checks": checks,
    })
    if not all(checks.values()):
        raise RuntimeError(f"R122 launch preparation failed: {checks}")
    output_names = [
        *inherited, "control_manifest.csv", "control_fit_manifest.csv",
        "execution_manifest.csv", "evaluation_contract.json", "stage0b_terminal.json",
        "stage0b_proxy_decision.json", "stage0b_ranking.csv", "source_manifest.csv",
        "launch_control.json", "preparation_gates.json", "data_configs/data_L3120.yaml",
        "data_configs/source_data_L3120.yaml", "runtime_environment.json",
    ]
    summary = {
        **control, "status": "R122_LONG_MEMORY_LAUNCH_READY", "launch_authorized": True,
        "output_sha256": {name: sha256_file(output / name) for name in output_names},
    }
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
