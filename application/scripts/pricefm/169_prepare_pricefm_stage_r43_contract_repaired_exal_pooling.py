#!/usr/bin/env python3
"""Prepare the bounded R43 contract-repaired exAL pooling qualification."""

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
DEFAULT_R41 = DATA / "authoritative/pricefm_stage_r41_exal_partial_pooling_launch_prep_20260806"
DEFAULT_R42 = DATA / "authoritative/pricefm_stage_r42_exal_partial_pooling_closeout_20260807"
DEFAULT_R33_GRID = DATA / "experiment_grids/pricefm_stage_r33_lean_capacity_history_20260722"
DEFAULT_OUTPUT = DATA / "authoritative/pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_20260807"
DEFAULT_GRID_ROOT = DATA / "experiment_grids/pricefm_stage_r43_contract_repaired_exal_pooling_20260807"
DEFAULT_RUN_ROOT = DATA / "runs/pricefm_stage_r43_contract_repaired_exal_pooling_20260807"
SOURCE_GRID = "pricefm_stage_r41_exal_partial_pooling_grid.yaml"
SPATIAL_FIELDS = [
    "neighbor_regions", "max_neighbor_regions", "target_lag_features", "target_lead_features",
    "neighbor_lag_features", "neighbor_lead_features", "summary_stats",
]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage-r41-dir", type=Path, default=DEFAULT_R41)
    p.add_argument("--stage-r42-dir", type=Path, default=DEFAULT_R42)
    p.add_argument("--stage-r33-grid", type=Path, default=DEFAULT_R33_GRID)
    p.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    p.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    p.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
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


def resolve_artifact_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ARTIFACT_REPO / path


def cpu_ids(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if "-" in token:
            low, high = map(int, token.split("-", 1))
            result.extend(range(low, high + 1))
        else:
            result.append(int(token))
    if not result or len(result) != len(set(result)):
        raise ValueError("CPU IDs must be nonempty and unique")
    return result


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def full_config(path: Path) -> dict:
    return yaml.safe_load(path.read_text())["pricefm_desn_full"]


def capability_audit(runner: Path) -> pd.DataFrame:
    source = runner.read_text()
    checks = [
        ("nested_normal_fit_uses_inner_train", "nested_normal_fit <- exdqlm::normal_desn_fit(" in source and "X_inner," in source and "y_inner," in source),
        ("nested_al_cache_materialized", "inner_fit_cache[[likelihood]][[tau_key(tau)]] <- shared_fit" in source),
        ("nested_exal_sources_same_fold_al", 'source_label <- paste0("nested_al_tau_", tau_key(tau))' in source),
        ("nested_init_passed_to_fit", "init = init_info$init" in source),
        ("nested_provenance_materialized", 'nested_warm_start_diagnostics.csv' in source),
        ("partial_pooling_consumed", "pricefm_partial_pool_predictions(" in source),
        ("test_quarantine_declared", 'existing_test_role = "not_loaded_not_predicted_not_selected"' in source),
    ]
    return pd.DataFrame([
        {"capability": name, "passed": passed, "evidence_file": str(runner.resolve())}
        for name, passed in checks
    ])


def selected_r33_configs(r33_manifest: pd.DataFrame, source_ids: set[str]) -> dict[str, dict]:
    rows = r33_manifest[r33_manifest["id"].isin(source_ids)]
    if len(rows) != len(source_ids):
        missing = sorted(source_ids - set(rows["id"]))
        raise ValueError(f"Missing selected R33 configs: {missing}")
    return {
        row.id: full_config(resolve_artifact_path(row.full_config))
        for row in rows.itertuples(index=False)
    }


def build_grid(
    source: dict,
    target_ids: set[str],
    r33_configs: dict[str, dict],
    output: Path,
    grid_root: Path,
    run_root: Path,
    cpus: list[int],
    authorized: bool,
) -> dict:
    payload = copy.deepcopy(source)
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "pricefm_stage_r43_contract_repaired_exal_pooling_20260807"
    grid["purpose"] = "Six-case validation-only qualification with restored R33 spatial contracts and consumed nested AL-to-exAL initialization."
    grid["base"].update({
        "data_config": str(output / "pricefm_stage_r43_base_data_config.yaml"),
        "full_config": str(output / "pricefm_stage_r43_base_full_config.yaml"),
        "generated_root": str(grid_root),
        "run_root": str(run_root),
    })
    fixed = grid["fixed"]
    fixed["qdesn_likelihoods"] = ["al", "exal"]
    fixed["normal"] = {"enabled": True}
    fixed["warm_start"] = {
        "enabled": True,
        "record_diagnostics": True,
        "fallback_to_cold": False,
        "qdesn": {
            "al": {
                "enabled": True,
                "first_tau_source": "normal_rhs_ns",
                "next_tau_source": "previous_al_tau",
                "tau_order": [0.5],
                "components": ["beta", "beta_state", "sigma"],
            },
            "exal": {
                "enabled": True,
                "source": "al_same_tau",
                "components": ["beta", "beta_state", "sigma"],
                "gamma_policy": "zero",
            },
        },
    }
    fixed["exact_equivalence"] = {"enabled": False}
    preserve = fixed["artifact_hygiene"].setdefault("preserve_patterns", [])
    if "nested_warm_start_diagnostics.csv" not in preserve:
        preserve.append("nested_warm_start_diagnostics.csv")
    experiments = []
    for experiment in grid["experiments"]:
        if experiment["id"] not in target_ids:
            continue
        item = copy.deepcopy(experiment)
        source_id = item["source_r34_experiment_id"]
        selected = r33_configs[source_id]
        spatial = copy.deepcopy(selected["adapter"].get("spatial", {}))
        item["id"] = item["id"].replace("r41_", "r43_", 1)
        item["stage"] = "stage_r43_contract_repaired_exal_pooling_qualification"
        item["spatial"] = spatial
        for field in SPATIAL_FIELDS:
            if field in spatial:
                item[field] = copy.deepcopy(spatial[field])
            else:
                item.pop(field, None)
        if "graph_degree" in spatial:
            item["graph_degree"] = int(spatial["graph_degree"])
        item["training"] = copy.deepcopy(selected["training"])
        item["readout_interaction"] = "none"
        item.pop("readout_interaction_basis", None)
        item["candidate_family"] = "contract_repaired_empirical_partial_pool_horizon_block_exal_rhs_ns"
        item["factor_changed"] = "restore_selected_r33_spatial_contract_and_consume_nested_normal_al_exal_chain"
        item["final_decision"] = "stage_r43_qualification_not_promotion"
        item["candidate_source_final"] = "pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_20260807"
        item["rationale"] = (
            "Restore the exact selected R33 spatial and weighting contract, retain interaction-free pooling, "
            "and consume leakage-free same-fold normal-to-AL-to-exAL initialization."
        )
        experiments.append(item)
    grid["experiments"] = experiments
    grid["scope"]["regions"] = sorted({item["regions"][0] for item in experiments})
    grid["scope"]["folds"] = sorted({int(item["folds"][0]) for item in experiments})
    grid["scope"]["splits"] = ["train", "val"]
    grid["launch"] = {"stage_r43_full_background_launch": {
        "priorities": [0, 1],
        "experiment_jobs": len(experiments),
        "cell_jobs": 1,
        "cpu_ids": cpus,
        "build_windows": False,
        "dry_run": False,
        "resume": True,
        "force": False,
        "authorized_now": authorized,
    }}
    return payload


def realized_config_audit(generated: list[dict], r33_configs: dict[str, dict]) -> pd.DataFrame:
    rows = []
    for item in generated:
        cfg = full_config(resolve_artifact_path(item["full_config"]))
        source_id = item["source_r34_experiment_id"]
        selected = r33_configs[source_id]
        adapter_fields = [
            "feature_map", "feature_dim", "seed", "include_intercept", "row_chunk_size",
            "projection_scale", "depth", "units", "alpha", "rho", "input_scale",
            "recurrent_sparsity", "reservoir_activation", "state_output",
        ]
        adapter_match = all(cfg["adapter"].get(key) == selected["adapter"].get(key) for key in adapter_fields)
        rows.append({
            "experiment_id": item["id"],
            "region": json.loads(item["regions"])[0] if isinstance(item["regions"], str) else item["regions"][0],
            "fold": int(json.loads(item["folds"])[0] if isinstance(item["folds"], str) else item["folds"][0]),
            "source_r34_experiment_id": source_id,
            "selected_r33_adapter_contract_match": adapter_match,
            "selected_r33_spatial_contract_match": cfg["adapter"].get("spatial", {}) == selected["adapter"].get("spatial", {}),
            "selected_r33_rhs_contract_match": cfg["rhs_ns"] == selected["rhs_ns"],
            "selected_r33_training_contract_match": cfg["training"] == selected["training"],
            "readout_interaction_none": cfg["adapter"].get("readout_interaction", "none") == "none",
            "likelihood_chain_al_exal": cfg["qdesn_vb"]["likelihoods"] == ["al", "exal"],
            "normal_enabled": bool(cfg["normal"].get("enabled", True)),
            "warm_start_enabled": bool(cfg["warm_start"].get("enabled", False)),
            "warm_fallback_blocked": not bool(cfg["warm_start"].get("fallback_to_cold", False)),
            "exal_source_al_same_tau": cfg["warm_start"]["qdesn"]["exal"].get("source") == "al_same_tau",
            "nested_validation_folds": int(cfg["nested_validation"]["n_folds"]),
            "configured_splits": json.dumps(cfg["scope"]["splits"]),
            "test_quarantined": cfg["scope"]["splits"] == ["train", "val"],
        })
    result = pd.DataFrame(rows)
    gate_columns = [
        "selected_r33_adapter_contract_match", "selected_r33_spatial_contract_match",
        "selected_r33_rhs_contract_match", "selected_r33_training_contract_match",
        "readout_interaction_none", "likelihood_chain_al_exal", "normal_enabled",
        "warm_start_enabled", "warm_fallback_blocked", "exal_source_al_same_tau", "test_quarantined",
    ]
    result["launch_contract_pass"] = result[gate_columns].all(axis=1) & result["nested_validation_folds"].eq(5)
    return result


def run(args: argparse.Namespace) -> dict:
    output, grid_root, run_root = args.output_dir.resolve(), args.grid_root.resolve(), args.run_root.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(f"Output exists; use --force true: {output}")
    output.mkdir(parents=True, exist_ok=True)
    runner = args.runner.resolve()
    materializer_path = args.materializer.resolve()
    launcher = args.launcher.resolve()
    capability = capability_audit(runner)
    capability.to_csv(output / "pricefm_stage_r43_runner_capability_audit.csv", index=False)
    if not capability["passed"].all():
        raise RuntimeError("Runner does not consume the required nested initialization chain")
    r42_summary_path = args.stage_r42_dir / "summary.json"
    r42_cases_path = args.stage_r42_dir / "pricefm_stage_r42_case_closeout.csv"
    r42_wiring_path = args.stage_r42_dir / "pricefm_stage_r42_realized_contract_audit.csv"
    r42_summary = json.loads(r42_summary_path.read_text())
    cases = pd.read_csv(r42_cases_path)
    wiring = pd.read_csv(r42_wiring_path)
    if r42_summary["full_quantile_candidates"] != 0 or r42_summary["test_inspected"]:
        raise RuntimeError("Unexpected R42 decision state")
    if len(cases) != 6 or len(wiring) != 6 or not wiring["realized_rows_and_weight_contract_pass"].all():
        raise RuntimeError("R42 six-case repair contract is incomplete")
    r33_manifest_path = args.stage_r33_grid / "manifest.csv"
    r33_manifest = pd.read_csv(r33_manifest_path)
    source_ids = set(cases["source_r34_experiment_id"])
    selected_configs = selected_r33_configs(r33_manifest, source_ids)
    shutil.copy2(args.stage_r41_dir / "pricefm_stage_r41_base_data_config.yaml", output / "pricefm_stage_r43_base_data_config.yaml")
    shutil.copy2(args.stage_r41_dir / "pricefm_stage_r41_base_full_config.yaml", output / "pricefm_stage_r43_base_full_config.yaml")
    source_grid_path = args.stage_r41_dir / SOURCE_GRID
    source_grid = yaml.safe_load(source_grid_path.read_text())
    cpus = cpu_ids(args.cpu_list)
    if len(cpus) < len(cases):
        raise ValueError("R43 requires one dedicated CPU per case")
    payload = build_grid(
        source_grid, set(cases["experiment_id"]), selected_configs,
        output, grid_root, run_root, cpus, bool(args.authorize_launch),
    )
    grid_path = output / "pricefm_stage_r43_contract_repaired_exal_pooling_grid.yaml"
    grid_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    materializer = load_module(materializer_path)
    generated = materializer.prepare_grid(materializer.load_grid(str(grid_path)), str(grid_root), write=True)
    launch_manifest = pd.DataFrame(generated)
    launch_manifest["selection_is_validation_only"] = True
    launch_manifest["test_metrics_role"] = "quarantined_not_loaded"
    launch_manifest["mutates_registry"] = False
    launch_manifest["mutates_article"] = False
    launch_manifest.to_csv(output / "pricefm_stage_r43_launch_manifest.csv", index=False)
    contract = realized_config_audit(generated, selected_configs)
    contract.to_csv(output / "pricefm_stage_r43_materialized_config_contract.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r42_zero_candidates", "passed": r42_summary["full_quantile_candidates"] == 0, "detail": "R41 did not promote."},
        {"gate": "runner_consumes_nested_chain", "passed": bool(capability["passed"].all()), "detail": "Normal-to-AL-to-exAL same-fold path."},
        {"gate": "six_repair_targets_only", "passed": len(launch_manifest) == 6, "detail": len(launch_manifest)},
        {"gate": "materialized_contracts_pass", "passed": bool(contract["launch_contract_pass"].all()), "detail": int(contract["launch_contract_pass"].sum())},
        {"gate": "test_quarantined", "passed": payload["pricefm_desn_experiment_grid"]["scope"]["splits"] == ["train", "val"], "detail": "Train/validation only."},
        {"gate": "one_cpu_per_case", "passed": len(cpus) >= 6, "detail": args.cpu_list},
        {"gate": "explicit_launch_authorization", "passed": bool(args.authorize_launch), "detail": bool(args.authorize_launch)},
        {"gate": "registry_article_mcmc_blocked", "passed": True, "detail": "Qualification only."},
    ])
    gates.to_csv(output / "pricefm_stage_r43_launch_gates.csv", index=False)
    if not gates["passed"].all():
        failed = ", ".join(gates.loc[~gates["passed"], "gate"])
        raise RuntimeError(f"R43 launch-prep gates failed: {failed}")
    command = (
        f"{args.python_bin.absolute()} {launcher} --grid-config {grid_path} --priorities 0,1 "
        f"--experiment-jobs 6 --cell-jobs 1 --build-windows false --resume true "
        f"--force false --dry-run false --cpu-list {args.cpu_list}"
    )
    (output / "pricefm_stage_r43_launch_command.txt").write_text(command + "\n")
    source_paths = [
        Path(__file__).resolve(), runner, materializer_path, launcher, source_grid_path,
        r42_summary_path, r42_cases_path, r42_wiring_path, r33_manifest_path,
    ] + [resolve_artifact_path(row.full_config) for row in r33_manifest[r33_manifest["id"].isin(source_ids)].itertuples(index=False)]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in dict.fromkeys(source_paths)
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_launch_ready",
        "targets": len(launch_manifest),
        "likelihood_chain": ["al", "exal"],
        "nested_folds": 5,
        "pooling_weights": [0, 0.25, 0.5, 0.75, 1],
        "spatial_contracts_restored": int(contract["selected_r33_spatial_contract_match"].sum()),
        "materialized_contracts_passed": int(contract["launch_contract_pass"].sum()),
        "cpu_ids": cpus,
        "launch_authorized_by_user": bool(args.authorize_launch),
        "launch_command": command,
        "test_inspected": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "mcmc_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_report.md").write_text(
        "# PriceFM Stage-R43 contract-repaired exAL pooling qualification\n\n"
        "R43 contains exactly six R34 exAL-anchor cases. Each materialized config restores the selected R33 "
        "spatial, reservoir, RHS, and training contract; keeps the new readout interaction disabled; and enables "
        "five-fold same-fold normal-to-AL-to-exAL initialization before interaction-free horizon-block pooling.\n\n"
        "Selection is validation-only. Test, full-quantile, MCMC, registry, and article actions remain blocked. "
        "The prep script materializes and audits configs but never invokes the launcher.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
