#!/usr/bin/env python3
"""Prepare the bounded PriceFM Stage-R39 partial-pooling qualification launch."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
DEFAULT_R36_PREP = ARTIFACT_ROOT / "authoritative/pricefm_stage_r36_nested_horizon_readout_launch_prep_20260804"
DEFAULT_R38_DIR = ARTIFACT_ROOT / "authoritative/pricefm_stage_r38_partial_pooling_capability_20260805"
DEFAULT_OUTPUT = ARTIFACT_ROOT / "authoritative/pricefm_stage_r39_partial_pooling_launch_prep_20260805"
DEFAULT_GRID_ROOT = ARTIFACT_ROOT / "experiment_grids/pricefm_stage_r39_partial_pooling_20260805"
DEFAULT_RUN_ROOT = ARTIFACT_ROOT / "runs/pricefm_stage_r39_partial_pooling_20260805"
SOURCE_GRID = "pricefm_stage_r36_nested_horizon_readout_grid.yaml"
OUT_GRID = "pricefm_stage_r39_partial_pooling_grid.yaml"
OUT_MANIFEST = "pricefm_stage_r39_launch_manifest.csv"
OUT_GATES = "pricefm_stage_r39_launch_prep_gates.csv"
OUT_SOURCE = "source_manifest.csv"
OUT_SUMMARY = "summary.json"
OUT_REPORT = "pricefm_stage_r39_partial_pooling_launch_prep_report.md"
OUT_COMMAND = "pricefm_stage_r39_launch_command.txt"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r36-prep-dir", default=str(DEFAULT_R36_PREP))
    p.add_argument("--stage-r38-dir", default=str(DEFAULT_R38_DIR))
    p.add_argument("--output-dir", default=str(DEFAULT_OUTPUT))
    p.add_argument("--grid-root", default=str(DEFAULT_GRID_ROOT))
    p.add_argument("--run-root", default=str(DEFAULT_RUN_ROOT))
    p.add_argument("--materializer", default="application/scripts/pricefm/12_prepare_desn_experiment_grid.py")
    p.add_argument("--launcher", default="application/scripts/pricefm/13_run_desn_experiment_grid.py")
    p.add_argument("--python-bin", default=str(ARTIFACT_ROOT / "venv/bin/python"))
    p.add_argument("--cpu-list", default="16-26")
    p.add_argument("--experiment-jobs", type=int, default=11)
    p.add_argument("--authorize-launch", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def cpu_ids(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if "-" in token:
            lo, hi = [int(x) for x in token.split("-", 1)]
            result.extend(range(lo, hi + 1))
        elif token:
            result.append(int(token))
    if len(result) != len(set(result)) or any(x < 0 for x in result):
        raise ValueError("CPU list must contain unique nonnegative IDs")
    return result


def build_grid(source: dict[str, Any], output: Path, grid_root: Path, run_root: Path, cpus: list[int], jobs: int, authorized: bool) -> dict[str, Any]:
    payload = copy.deepcopy(source)
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "pricefm_stage_r39_partial_pooling_20260805"
    grid["purpose"] = "Case-specific nested qualification of empirically partial-pooled shared and separate AL/RHS_NS horizon-block readouts."
    base_data = output / "pricefm_stage_r39_base_data_config.yaml"
    base_full = output / "pricefm_stage_r39_base_full_config.yaml"
    grid["base"]["data_config"] = str(base_data)
    grid["base"]["full_config"] = str(base_full)
    grid["base"]["generated_root"] = str(grid_root)
    grid["base"]["run_root"] = str(run_root)
    nested = grid["fixed"]["nested_validation"]
    nested.update({
        "n_folds": 5,
        "initial_train_fraction": 0.45,
        "validation_fraction": 0.10,
        "selection_rule": "per_horizon_block_median_inner_AQL_one_standard_error_stronger_pooling",
        "practical_harm_margin_relative": 0.005,
    })
    horizon = grid["fixed"]["qdesn_vb"]["horizon_readout"]
    horizon["partial_pooling"] = {
        "enabled": True,
        "weights": [0.0, 0.25, 0.5, 0.75, 1.0],
        "selection_scope": "case_specific_horizon_block",
        "preference": "one_standard_error_toward_shared",
    }
    preserve = grid["fixed"]["artifact_hygiene"]["preserve_patterns"]
    for name in ["nested_partial_pooling_metrics.csv", "nested_partial_pooling_convergence.csv"]:
        if name not in preserve:
            preserve.append(name)
    grid["launch"] = {
        "stage_r39_full_background_launch": {
            "priorities": [0, 1], "experiment_jobs": jobs, "cell_jobs": 1,
            "cpu_ids": cpus, "build_windows": False, "dry_run": False,
            "resume": True, "force": False, "authorized_now": authorized,
        }
    }
    for experiment in grid["experiments"]:
        experiment["id"] = str(experiment["id"]).replace("r36_", "r39_", 1)
        experiment["stage"] = "stage_r39_partial_pooling_qualification"
        experiment["target_label"] = "stage_r39_partial_pooling_median_qualification"
        experiment["candidate_family"] = "empirical_partial_pool_horizon_block_al_rhs_ns"
        experiment["factor_changed"] = "nested_selected_pooling_between_shared_and_separate_readouts"
        experiment["final_decision"] = "stage_r39_qualification_not_promotion"
        experiment["candidate_source_final"] = "pricefm_stage_r39_partial_pooling_launch_prep_20260805"
        experiment["nested_validation_rule"] = nested["selection_rule"]
        experiment["rationale"] = "Frozen case-specific R34 reservoir with prospectively nested partial pooling between paired R36 readout extremes."
    return payload


def run(args: argparse.Namespace) -> dict[str, Any]:
    r36 = Path(args.stage_r36_prep_dir).resolve()
    r38 = Path(args.stage_r38_dir).resolve()
    output = Path(args.output_dir).resolve()
    grid_root = Path(args.grid_root).resolve()
    run_root = Path(args.run_root).resolve()
    summary38 = json.loads((r38 / "summary.json").read_text())
    if not summary38.get("r39_implementation_justified", False):
        raise ValueError("R38 does not authorize R39 implementation")
    cpus = cpu_ids(args.cpu_list)
    if len(cpus) < args.experiment_jobs:
        raise ValueError("Need at least one dedicated CPU per concurrent experiment")
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"R39 output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(r36 / "pricefm_stage_r36_base_data_config.yaml", output / "pricefm_stage_r39_base_data_config.yaml")
    shutil.copy2(r36 / "pricefm_stage_r36_base_full_config.yaml", output / "pricefm_stage_r39_base_full_config.yaml")
    source_grid_path = r36 / SOURCE_GRID
    source_grid = yaml.safe_load(source_grid_path.read_text())
    payload = build_grid(source_grid, output, grid_root, run_root, cpus, args.experiment_jobs, bool(args.authorize_launch))
    grid_path = output / OUT_GRID
    grid_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    materializer_path = Path(args.materializer).resolve()
    materializer = load_module(materializer_path)
    grid = materializer.load_grid(str(grid_path))
    generated = materializer.prepare_grid(grid, str(grid_root), write=True)
    manifest = pd.DataFrame(generated)
    manifest["region"] = manifest["regions"].map(lambda value: json.loads(value)[0])
    manifest["fold"] = manifest["folds"].map(lambda value: json.loads(value)[0])
    manifest["selection_is_validation_only"] = True
    manifest["test_metrics_role"] = "quarantined_not_loaded"
    manifest["practical_harm_margin_relative"] = 0.005
    manifest["launch_authorized_by_user"] = bool(args.authorize_launch)
    manifest.to_csv(output / OUT_MANIFEST, index=False)
    checks = [
        ("r38_implementation_gate", bool(summary38["r39_implementation_justified"]), "R38 supports partial pooling."),
        ("case_count", len(manifest) == 11, "Exactly 11 frozen qualification cases."),
        ("five_inner_folds", payload["pricefm_desn_experiment_grid"]["fixed"]["nested_validation"]["n_folds"] == 5, "Five embargoed folds."),
        ("test_quarantined", payload["pricefm_desn_experiment_grid"]["scope"]["splits"] == ["train", "val"], "No test split."),
        ("one_cpu_per_worker", len(cpus) >= args.experiment_jobs, "Dedicated CPU capacity."),
        ("registry_article_blocked", True, "Qualification only."),
    ]
    gates = pd.DataFrame([{"gate": gate, "passed": passed, "detail": detail} for gate, passed, detail in checks])
    gates.to_csv(output / OUT_GATES, index=False)
    if not gates["passed"].all():
        raise ValueError("R39 launch-prep gates failed")
    launcher = Path(args.launcher).resolve()
    command = (
        # Preserve the venv entrypoint: resolving its symlink loses the venv
        # package context on this host.
        f"{Path(args.python_bin).absolute()} {launcher} --grid-config {grid_path} "
        f"--priorities 0,1 --experiment-jobs {args.experiment_jobs} --cell-jobs 1 "
        f"--build-windows false --resume true --force false --dry-run false --cpu-list {args.cpu_list}"
    )
    (output / OUT_COMMAND).write_text(command + "\n")
    sources = [Path(__file__).resolve(), source_grid_path, r38 / "summary.json", materializer_path, launcher]
    pd.DataFrame([{"path": str(path), "sha256": sha256_file(path), "bytes": path.stat().st_size} for path in sources]).to_csv(output / OUT_SOURCE, index=False)
    summary = {
        "status": "completed_launch_ready", "cases": len(manifest),
        "nested_folds": 5, "pooling_weights": [0, 0.25, 0.5, 0.75, 1],
        "experiment_jobs": args.experiment_jobs, "cpu_ids": cpus,
        "launch_authorized_by_user": bool(args.authorize_launch),
        "launch_command": command, "run_root": str(run_root),
        "test_inspected": False, "mutates_registry": False,
        "mutates_article": False, "mcmc_authorized": False,
    }
    write_json(output / OUT_SUMMARY, summary)
    (output / OUT_REPORT).write_text("\n".join([
        "# PriceFM Stage-R39 Partial-Pooling Launch Prep", "",
        "R39 freezes all 11 R36 case-specific reservoir anchors and changes only the consumed",
        "pooling rule between shared and separate 24-hour readouts. Five embargoed folds select",
        "weights independently by case and horizon block. Test, registry, article, and MCMC remain blocked.", "",
    ]))
    return summary


def main() -> None:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
