#!/usr/bin/env python3
"""Prepare the bounded R45 full-quantile confirmation for R44 candidates."""

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


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
DEFAULT_R43 = DATA / "authoritative/pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_20260807"
DEFAULT_R44 = DATA / "authoritative/pricefm_stage_r44_contract_repaired_exal_pooling_closeout_20260807"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r45_full_quantile_confirmation_launch_prep_20260807"
DEFAULT_GRID = DATA / "experiment_grids/pricefm_stage_r45_full_quantile_confirmation_20260807"
DEFAULT_RUNS = DATA / "runs/pricefm_stage_r45_full_quantile_confirmation_20260807"
PAPER_QUANTILES = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
WARM_ORDER = [0.50, 0.45, 0.55, 0.25, 0.75, 0.10, 0.90]
BLOCKS = ["1-24", "25-48", "49-72", "73-96"]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r43-dir", type=Path, default=DEFAULT_R43)
    p.add_argument("--stage-r44-dir", type=Path, default=DEFAULT_R44)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUNS)
    p.add_argument("--runner", type=Path, default=Path("application/scripts/pricefm/08_run_desn_model_smoke.R"))
    p.add_argument("--materializer", type=Path, default=Path("application/scripts/pricefm/12_prepare_desn_experiment_grid.py"))
    p.add_argument("--launcher", type=Path, default=Path("application/scripts/pricefm/13_run_desn_experiment_grid.py"))
    p.add_argument("--python-bin", type=Path, default=DATA / "venv/bin/python")
    p.add_argument("--cpu-list", required=True)
    p.add_argument("--authorize-launch", type=parse_bool, default=False)
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
    for part in value.split(","):
        token = part.strip()
        if "-" in token:
            low, high = map(int, token.split("-", 1))
            result.extend(range(low, high + 1))
        elif token:
            result.append(int(token))
    if not result or len(result) != len(set(result)) or any(x < 0 for x in result):
        raise ValueError("CPU IDs must be nonnegative, nonempty, and unique")
    return result


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def capability_audit(runner: Path) -> pd.DataFrame:
    source = runner.read_text()
    checks = [
        ("multiple_quantiles_consumed", "for (j in seq_along(quantiles))" in source),
        ("warm_tau_order_consumed", "fit_order <- warm_tau_order(likelihood)" in source),
        ("shared_readout_supported", '"shared_static"' in source),
        ("separate_horizon_readout_supported", '"separate_horizon_block"' in source),
        ("separate_warm_starts_from_shared", 'init_source = paste0("shared_static_tau_"' in source),
        ("exal_sources_same_tau_al", 'source_label <- paste0("qdesn_al_tau_", tau_key(tau))' in source),
        ("validation_predictions_materialized", 'model_predictions_scaled.csv' in source),
    ]
    return pd.DataFrame([{"capability": name, "passed": passed, "evidence_file": str(runner.resolve())} for name, passed in checks])


def frozen_weights(row) -> dict[str, float]:
    return {block: float(getattr(row, f"weight_{block.replace('-', '_')}")) for block in BLOCKS}


def build_grid(source: dict, queue: pd.DataFrame, output: Path, grid_root: Path, run_root: Path, cpus: list[int], authorized: bool) -> dict:
    payload = copy.deepcopy(source)
    grid = payload["pricefm_desn_experiment_grid"]
    queue_index = queue.set_index("experiment_id")
    grid["grid_id"] = "pricefm_stage_r45_full_quantile_confirmation_20260807"
    grid["purpose"] = "Two-case seven-quantile validation confirmation with R44 pooling weights frozen before launch."
    grid["base"].update({
        "data_config": str(output / "pricefm_stage_r45_base_data_config.yaml"),
        "full_config": str(output / "pricefm_stage_r45_base_full_config.yaml"),
        "generated_root": str(grid_root), "run_root": str(run_root),
    })
    grid["scope"].update({
        "quantiles": PAPER_QUANTILES, "splits": ["train", "val"],
        "ranking_split": "outer_validation_confirmation_only",
        "audit_split": "existing_test_quarantined",
    })
    fixed = grid["fixed"]
    fixed["qdesn_likelihoods"] = ["al", "exal"]
    fixed["normal"] = {**fixed.get("normal", {}), "enabled": True}
    fixed["warm_start"] = {
        "enabled": True, "record_diagnostics": True, "fallback_to_cold": False,
        "qdesn": {
            "al": {"enabled": True, "first_tau_source": "normal_rhs_ns", "next_tau_source": "previous_al_tau", "tau_order": WARM_ORDER, "components": ["beta", "beta_state", "sigma"]},
            "exal": {"enabled": True, "source": "al_same_tau", "components": ["beta", "beta_state", "sigma"], "gamma_policy": "zero"},
        },
    }
    fixed["nested_validation"] = {
        "enabled": False,
        "selection_rule": "disabled_r44_weights_frozen_before_launch",
        "existing_test_role": "not_loaded_not_predicted_not_selected",
    }
    fixed["qdesn_vb"]["readout_modes"] = ["shared_static", "separate_horizon_block"]
    horizon = fixed["qdesn_vb"].setdefault("horizon_readout", {})
    horizon["block_size"] = 24
    horizon["partial_pooling"] = {
        "enabled": False,
        "selection_scope": "disabled_r44_case_specific_weights_frozen",
        "preference": "no_reselection",
    }
    experiments = []
    for experiment in grid["experiments"]:
        if experiment["id"] not in queue_index.index:
            continue
        item = copy.deepcopy(experiment)
        decision = queue_index.loc[item["id"]]
        item["id"] = item["id"].replace("r43_", "r45_", 1)
        item["stage"] = "stage_r45_full_quantile_validation_confirmation"
        item["priority"] = 0
        item.pop("quantile", None)
        item["quantiles"] = PAPER_QUANTILES
        item["nested_validation"] = {"enabled": False}
        item["mechanism_qualification_only"] = False
        item["fresh_confirmation_required"] = True
        item["selection_rule"] = "r44_frozen_case_specific_horizon_weights_no_reselection"
        item["selected_on_split"] = "r43_nested_inner_and_outer_validation"
        item["test_metrics_role"] = "quarantined_not_loaded"
        item["final_decision"] = "stage_r45_full_quantile_confirmation_not_promotion"
        item["candidate_source_final"] = "pricefm_stage_r44_contract_repaired_exal_pooling_closeout_20260807"
        item["candidate_family"] = "frozen_case_specific_horizon_partial_pool_exal_rhs_ns_full_quantile"
        item["factor_changed"] = "quantile_surface_only_weights_and_desn_contract_frozen"
        item["rationale"] = "Confirm the validation-selected R43 mechanism across the seven paper quantiles without reselecting its case-specific pooling weights."
        item["frozen_horizon_pooling_weights"] = frozen_weights(decision)
        experiments.append(item)
    grid["experiments"] = experiments
    grid["scope"]["regions"] = sorted({x["regions"][0] for x in experiments})
    grid["scope"]["folds"] = sorted({int(x["folds"][0]) for x in experiments})
    grid["launch"] = {"stage_r45_full_background_launch": {
        "priorities": [0], "experiment_jobs": len(experiments), "cell_jobs": 1,
        "cpu_ids": cpus, "build_windows": False, "dry_run": False,
        "resume": True, "force": False, "authorized_now": authorized,
    }}
    return payload


def realized_config_audit(generated: list[dict], queue: pd.DataFrame) -> pd.DataFrame:
    q = queue.set_index("experiment_id")
    rows = []
    for item in generated:
        config = yaml.safe_load(Path(item["full_config"]).read_text())["pricefm_desn_full"]
        r43_id = str(item["id"]).replace("r45_", "r43_", 1)
        decision = q.loc[r43_id]
        weights = frozen_weights(decision)
        rows.append({
            "experiment_id": item["id"], "source_r43_experiment_id": r43_id,
            "region": json.loads(item["regions"])[0], "fold": int(json.loads(item["folds"])[0]),
            **{f"frozen_weight_{b.replace('-', '_')}": weights[b] for b in BLOCKS},
            "paper_quantiles_exact": config["scope"]["quantiles"] == PAPER_QUANTILES,
            "train_val_only": config["scope"]["splits"] == ["train", "val"],
            "nested_reselection_disabled": not bool(config["nested_validation"]["enabled"]),
            "paired_readouts_enabled": config["qdesn_vb"]["readout_modes"] == ["shared_static", "separate_horizon_block"],
            "runner_partial_pool_selector_disabled": not bool(config["qdesn_vb"]["horizon_readout"]["partial_pooling"]["enabled"]),
            "normal_enabled": bool(config["normal"]["enabled"]),
            "likelihood_chain_al_exal": config["qdesn_vb"]["likelihoods"] == ["al", "exal"],
            "warm_fallback_blocked": not bool(config["warm_start"]["fallback_to_cold"]),
            "warm_tau_order_exact": config["warm_start"]["qdesn"]["al"]["tau_order"] == WARM_ORDER,
            "test_inspected": False,
        })
    result = pd.DataFrame(rows)
    checks = ["paper_quantiles_exact", "train_val_only", "nested_reselection_disabled", "paired_readouts_enabled", "runner_partial_pool_selector_disabled", "normal_enabled", "likelihood_chain_al_exal", "warm_fallback_blocked", "warm_tau_order_exact"]
    result["launch_contract_pass"] = result[checks].all(axis=1)
    return result


def run(args: argparse.Namespace) -> dict:
    output, grid_root, run_root = args.output_dir.resolve(), args.grid_root.resolve(), args.run_root.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    runner, materializer_path, launcher = args.runner.resolve(), args.materializer.resolve(), args.launcher.resolve()
    capability = capability_audit(runner)
    capability.to_csv(output / "pricefm_stage_r45_runner_capability_audit.csv", index=False)
    if not capability["passed"].all():
        raise RuntimeError("Runner lacks the required full-quantile paired-readout capability")
    summary_path = args.stage_r44_dir / "summary.json"
    queue_path = args.stage_r44_dir / "pricefm_stage_r44_full_quantile_confirmation_queue.csv"
    source_manifest_path = args.stage_r44_dir / "source_manifest.csv"
    r44_summary = json.loads(summary_path.read_text())
    queue = pd.read_csv(queue_path)
    if r44_summary["test_inspected"] or r44_summary["full_quantile_candidates"] != 2 or len(queue) != 2:
        raise RuntimeError("R44 did not authorize exactly two validation-only candidates")
    if set(zip(queue["region"], queue["fold"].astype(int))) != {("NO_3", 2), ("NO_3", 3)}:
        raise RuntimeError("Unexpected R44 candidate identity")
    shutil.copy2(args.stage_r43_dir / "pricefm_stage_r43_base_data_config.yaml", output / "pricefm_stage_r45_base_data_config.yaml")
    shutil.copy2(args.stage_r43_dir / "pricefm_stage_r43_base_full_config.yaml", output / "pricefm_stage_r45_base_full_config.yaml")
    source_grid_path = args.stage_r43_dir / "pricefm_stage_r43_contract_repaired_exal_pooling_grid.yaml"
    source_grid = yaml.safe_load(source_grid_path.read_text())
    cpus = cpu_ids(args.cpu_list)
    if len(cpus) < len(queue):
        raise ValueError("R45 requires one dedicated CPU per case")
    payload = build_grid(source_grid, queue, output, grid_root, run_root, cpus, bool(args.authorize_launch))
    grid_path = output / "pricefm_stage_r45_full_quantile_confirmation_grid.yaml"
    grid_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    materializer = load_module(materializer_path)
    generated = materializer.prepare_grid(materializer.load_grid(str(grid_path)), str(grid_root), write=True)
    launch_manifest = pd.DataFrame(generated)
    launch_manifest["source_r43_experiment_id"] = launch_manifest["id"].str.replace("r45_", "r43_", regex=False)
    weight_columns = ["experiment_id"] + [f"weight_{b.replace('-', '_')}" for b in BLOCKS]
    launch_manifest = launch_manifest.merge(queue[weight_columns], left_on="source_r43_experiment_id", right_on="experiment_id", how="left", validate="one_to_one").drop(columns="experiment_id")
    launch_manifest["selection_is_validation_only"] = True
    launch_manifest["test_metrics_role"] = "quarantined_not_loaded"
    launch_manifest["mutates_registry"] = False
    launch_manifest["mutates_article"] = False
    launch_manifest["mcmc_authorized"] = False
    launch_manifest.to_csv(output / "pricefm_stage_r45_launch_manifest.csv", index=False)
    contract = realized_config_audit(generated, queue)
    contract.to_csv(output / "pricefm_stage_r45_materialized_config_contract.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r44_two_candidates", "passed": len(queue) == 2, "detail": len(queue)},
        {"gate": "candidate_identity_frozen", "passed": set(zip(queue["region"], queue["fold"].astype(int))) == {("NO_3", 2), ("NO_3", 3)}, "detail": "NO_3:2;NO_3:3"},
        {"gate": "runner_capability", "passed": bool(capability["passed"].all()), "detail": int(capability["passed"].sum())},
        {"gate": "materialized_contracts", "passed": len(contract) == 2 and bool(contract["launch_contract_pass"].all()), "detail": int(contract["launch_contract_pass"].sum())},
        {"gate": "seven_paper_quantiles", "passed": all(contract["paper_quantiles_exact"]), "detail": json.dumps(PAPER_QUANTILES)},
        {"gate": "test_quarantined", "passed": all(contract["train_val_only"]), "detail": "train,val"},
        {"gate": "weights_frozen_no_reselection", "passed": all(contract["nested_reselection_disabled"] & contract["runner_partial_pool_selector_disabled"]), "detail": "R44 weights"},
        {"gate": "one_cpu_per_case", "passed": len(cpus) >= 2, "detail": args.cpu_list},
        {"gate": "explicit_launch_authorization", "passed": bool(args.authorize_launch), "detail": bool(args.authorize_launch)},
        {"gate": "registry_article_mcmc_blocked", "passed": True, "detail": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r45_launch_gates.csv", index=False)
    if not gates["passed"].all():
        raise RuntimeError("R45 launch-prep gates failed: " + ", ".join(gates.loc[~gates["passed"], "gate"]))
    command = (
        f"{args.python_bin.absolute()} {launcher} --grid-config {grid_path} --priorities 0 "
        f"--experiment-jobs 2 --cell-jobs 1 --build-windows false --resume true --force false "
        f"--dry-run false --cpu-list {args.cpu_list}"
    )
    (output / "pricefm_stage_r45_launch_command.txt").write_text(command + "\n")
    source_paths = [Path(__file__).resolve(), runner, materializer_path, launcher, source_grid_path, summary_path, queue_path, source_manifest_path]
    pd.DataFrame([{"path": str(p.resolve()), "sha256": sha256(p), "bytes": p.stat().st_size} for p in dict.fromkeys(source_paths)]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_launch_ready", "targets": len(launch_manifest),
        "case_quantile_evaluations": len(launch_manifest) * len(PAPER_QUANTILES),
        "quantiles": PAPER_QUANTILES, "warm_tau_order": WARM_ORDER,
        "cpu_ids": cpus, "materialized_contracts_passed": int(contract["launch_contract_pass"].sum()),
        "launch_authorized_by_user": bool(args.authorize_launch), "launch_command": command,
        "selection_weights_frozen": True, "nested_reselection_enabled": False,
        "test_inspected": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r45_full_quantile_confirmation_launch_prep_report.md").write_text(
        "# PriceFM Stage-R45 full-quantile confirmation launch prep\n\n"
        "R45 contains only `NO_3` folds 2 and 3. It evaluates the seven paper quantiles using paired shared and "
        "horizon-separate AL/exAL readouts. The case-specific R44 weights are frozen in the launch manifest; nested "
        "weight selection is disabled, so R45 is confirmation rather than a second search.\n\n"
        "Only train and validation data are configured. Test, registry, article, and MCMC actions remain blocked.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
