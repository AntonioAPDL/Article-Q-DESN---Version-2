#!/usr/bin/env python3
"""Audit exAL pooling capability and prepare the isolated R41 qualification."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
DEFAULT_R39 = DATA / "authoritative/pricefm_stage_r39_partial_pooling_launch_prep_20260805"
DEFAULT_R40 = DATA / "authoritative/pricefm_stage_r40_partial_pooling_closeout_20260806"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r41_exal_partial_pooling_launch_prep_20260806"
DEFAULT_GRID_ROOT = DATA / "experiment_grids/pricefm_stage_r41_exal_partial_pooling_20260806"
DEFAULT_RUN_ROOT = DATA / "runs/pricefm_stage_r41_exal_partial_pooling_20260806"
SOURCE_GRID = "pricefm_stage_r39_partial_pooling_grid.yaml"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r39-dir", type=Path, default=DEFAULT_R39)
    p.add_argument("--stage-r40-dir", type=Path, default=DEFAULT_R40)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    p.add_argument("--runner", type=Path, default=Path("application/scripts/pricefm/08_run_desn_model_smoke.R"))
    p.add_argument("--materializer", type=Path, default=Path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py"))
    p.add_argument("--launcher", type=Path, default=Path("application/scripts/pricefm/13_run_desn_experiment_grid.py"))
    p.add_argument("--python-bin", type=Path, default=DATA / "venv/bin/python")
    p.add_argument("--cpu-list", default="16-21")
    p.add_argument("--authorize-launch", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cpu_ids(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if "-" in token:
            low, high = map(int, token.split("-", 1))
            result.extend(range(low, high + 1))
        else:
            result.append(int(token))
    if len(result) != len(set(result)):
        raise ValueError("CPU IDs must be unique")
    return result


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def capability_audit(runner: Path) -> pd.DataFrame:
    source = runner.read_text()
    checks = [
        ("accepts_exal_likelihood", 'c("al", "exal")' in source),
        ("fits_exal_shared", 'fit_qdesn_like("exal"' in source),
        ("fits_exal_separate", 'fit_qdesn_horizon_separate("exal"' in source),
        ("nested_loop_is_likelihood_generic", "for (likelihood in qdesn_likelihoods)" in source),
        ("partial_pooling_is_consumed", "pricefm_partial_pool_predictions(" in source),
        ("exal_gamma_warm_start_preserved", 'gamma_policy = if (identical(likelihood, "al")) "zero" else "source"' in source),
        ("pooling_metrics_materialized", 'nested_partial_pooling_metrics.csv' in source),
    ]
    return pd.DataFrame([{"capability": name, "passed": passed, "evidence_file": str(runner.resolve())} for name, passed in checks])


def build_grid(source: dict, target_ids: set[str], output: Path, grid_root: Path, run_root: Path, cpus: list[int], authorized: bool) -> dict:
    payload = copy.deepcopy(source)
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "pricefm_stage_r41_exal_partial_pooling_20260806"
    grid["purpose"] = "Paired exAL partial-pooling qualification for the six R34 exAL-anchor cases."
    grid["base"].update({
        "data_config": str(output / "pricefm_stage_r41_base_data_config.yaml"),
        "full_config": str(output / "pricefm_stage_r41_base_full_config.yaml"),
        "generated_root": str(grid_root), "run_root": str(run_root),
    })
    grid["fixed"]["qdesn_likelihoods"] = ["exal"]
    experiments = []
    for experiment in grid["experiments"]:
        if experiment["id"] not in target_ids:
            continue
        item = copy.deepcopy(experiment)
        item["id"] = item["id"].replace("r39_", "r41_", 1)
        item["stage"] = "stage_r41_exal_partial_pooling_qualification"
        item["candidate_family"] = "empirical_partial_pool_horizon_block_exal_rhs_ns"
        item["factor_changed"] = "likelihood_alignment_al_to_exal_only"
        item["final_decision"] = "stage_r41_qualification_not_promotion"
        item["candidate_source_final"] = "pricefm_stage_r41_exal_partial_pooling_launch_prep_20260806"
        item["rationale"] = "Freeze the R34 case specification and align the R39 readout experiment with its authoritative exAL anchor."
        experiments.append(item)
    grid["experiments"] = experiments
    grid["scope"]["regions"] = sorted({item["regions"][0] for item in experiments})
    grid["scope"]["folds"] = sorted({int(item["folds"][0]) for item in experiments})
    grid["launch"] = {"stage_r41_full_background_launch": {
        "priorities": [0, 1], "experiment_jobs": len(experiments), "cell_jobs": 1,
        "cpu_ids": cpus, "build_windows": False, "dry_run": False,
        "resume": True, "force": False, "authorized_now": authorized,
    }}
    return payload


def run(args: argparse.Namespace) -> dict:
    output, grid_root, run_root = args.output_dir.resolve(), args.grid_root.resolve(), args.run_root.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    runner, materializer_path, launcher = args.runner.resolve(), args.materializer.resolve(), args.launcher.resolve()
    capability = capability_audit(runner)
    capability.to_csv(output / "pricefm_stage_r41_mechanism_capability_audit.csv", index=False)
    if not capability["passed"].all():
        raise RuntimeError("Runner does not consume the required exAL pooling mechanism")
    r40_summary = json.loads((args.stage_r40_dir / "summary.json").read_text())
    if r40_summary["full_quantile_candidates"] != 0 or r40_summary["test_inspected"]:
        raise RuntimeError("Unexpected R40 decision state")
    cases = pd.read_csv(args.stage_r40_dir / "pricefm_stage_r40_case_closeout.csv")
    targets = cases[cases["source_r34_selected_method"].eq("qdesn_exal_rhs_ns_exact_chunked")].copy()
    exclusions = cases[~cases.index.isin(targets.index)].copy()
    targets["r41_role"] = "paired_exal_mechanism_qualification"
    targets["selection_is_validation_only"] = True
    exclusions["r41_exclusion_reason"] = "r34_anchor_al_already_likelihood_matched_in_r39"
    targets.to_csv(output / "pricefm_stage_r41_target_manifest.csv", index=False)
    exclusions.to_csv(output / "pricefm_stage_r41_exclusion_manifest.csv", index=False)
    if len(targets) != 6 or len(exclusions) != 5:
        raise RuntimeError(f"Expected 6 exAL targets and 5 AL exclusions, got {len(targets)} and {len(exclusions)}")
    shutil.copy2(args.stage_r39_dir / "pricefm_stage_r39_base_data_config.yaml", output / "pricefm_stage_r41_base_data_config.yaml")
    shutil.copy2(args.stage_r39_dir / "pricefm_stage_r39_base_full_config.yaml", output / "pricefm_stage_r41_base_full_config.yaml")
    source_grid_path = args.stage_r39_dir / SOURCE_GRID
    source_grid = yaml.safe_load(source_grid_path.read_text())
    cpus = cpu_ids(args.cpu_list)
    if len(cpus) < len(targets):
        raise ValueError("R41 requires one dedicated CPU per case")
    payload = build_grid(source_grid, set(targets["experiment_id"]), output, grid_root, run_root, cpus, bool(args.authorize_launch))
    grid_path = output / "pricefm_stage_r41_exal_partial_pooling_grid.yaml"
    grid_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    materializer = load_module(materializer_path)
    generated = materializer.prepare_grid(materializer.load_grid(str(grid_path)), str(grid_root), write=True)
    launch_manifest = pd.DataFrame(generated)
    launch_manifest["selection_is_validation_only"] = True
    launch_manifest["test_metrics_role"] = "quarantined_not_loaded"
    launch_manifest["mutates_registry"] = False
    launch_manifest["mutates_article"] = False
    launch_manifest.to_csv(output / "pricefm_stage_r41_launch_manifest.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r40_zero_candidates", "passed": r40_summary["full_quantile_candidates"] == 0, "detail": "R39 did not promote."},
        {"gate": "runner_consumes_exal_pooling", "passed": bool(capability["passed"].all()), "detail": "All code-path checks pass."},
        {"gate": "six_exal_targets_only", "passed": len(launch_manifest) == 6, "detail": "Only exAL-anchor cases."},
        {"gate": "five_al_cases_excluded", "passed": len(exclusions) == 5, "detail": "No R39 AL reuse."},
        {"gate": "test_quarantined", "passed": payload["pricefm_desn_experiment_grid"]["scope"]["splits"] == ["train", "val"], "detail": "Train/validation only."},
        {"gate": "one_cpu_per_case", "passed": len(cpus) >= 6, "detail": args.cpu_list},
        {"gate": "registry_article_mcmc_blocked", "passed": True, "detail": "Qualification only."},
    ])
    gates.to_csv(output / "pricefm_stage_r41_launch_gates.csv", index=False)
    if not gates["passed"].all():
        raise RuntimeError("R41 launch-prep gates failed")
    command = (
        f"{args.python_bin.absolute()} {launcher} --grid-config {grid_path} --priorities 0,1 "
        f"--experiment-jobs 6 --cell-jobs 1 --build-windows false --resume true "
        f"--force false --dry-run false --cpu-list {args.cpu_list}"
    )
    (output / "pricefm_stage_r41_launch_command.txt").write_text(command + "\n")
    source_paths = [Path(__file__).resolve(), runner, materializer_path, launcher, source_grid_path, args.stage_r40_dir / "summary.json", args.stage_r40_dir / "pricefm_stage_r40_case_closeout.csv"]
    pd.DataFrame([{"path": str(p.resolve()), "sha256": sha256(p), "bytes": p.stat().st_size} for p in source_paths]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_launch_ready", "targets": len(targets), "excluded_al_cases": len(exclusions),
        "likelihood": "exal", "nested_folds": 5, "pooling_weights": [0, .25, .5, .75, 1],
        "cpu_ids": cpus, "launch_authorized_by_user": bool(args.authorize_launch), "launch_command": command,
        "test_inspected": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r41_exal_partial_pooling_launch_prep_report.md").write_text(
        "# PriceFM Stage-R41 exAL partial-pooling qualification\n\n"
        "R41 isolates the likelihood/readout confound found by R40. It retains only the six cases whose authoritative R34 anchor selected exAL, freezes every case-specific reservoir and information-set field, and changes the R39 fitting likelihood from AL to exAL. The five AL-anchor cases are excluded.\n\n"
        "Selection remains five-fold validation-only with the R39 one-standard-error and 0.5% harm gates. Test, full-quantile, MCMC, registry, and article actions remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
