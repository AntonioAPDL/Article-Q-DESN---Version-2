#!/usr/bin/env python3
"""Freeze the 114-cell PriceFM authority for a joint seven-quantile campaign."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
REGISTRY = DATA / "authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_decision_registry.csv"
ATLAS = DATA / "authoritative/pricefm_stage_r8_specification_atlas_20260706/pricefm_stage_r8_specification_atlas.csv"
OUTPUT = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
AL_METHOD = "qdesn_al_rhs_ns_exact_chunked"
EXAL_METHOD = "qdesn_exal_rhs_ns_exact_chunked"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--registry", type=Path, default=REGISTRY)
    p.add_argument("--atlas", type=Path, default=ATLAS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cells", type=int, default=114)
    p.add_argument("--expected-al", type=int, default=27)
    p.add_argument("--expected-exal", type=int, default=87)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def parse_list(value) -> list:
    if isinstance(value, list):
        return value
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return []
    text = str(value).strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = ast.literal_eval(text)
    return parsed if isinstance(parsed, list) else [parsed]


def resolve_from_repo(repo: Path, value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo / path).resolve()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def matched_authority(registry: pd.DataFrame, atlas: pd.DataFrame) -> pd.DataFrame:
    required_registry = {
        "region", "fold", "experiment_id", "qdesn_method_id", "feature_policy",
        "selected_on_split", "selection_metric", "selection_is_validation_only",
        "selection_metric_value", "test_metrics_role", "qdesn_AQL", "pricefm_AQL",
    }
    required_atlas = {
        "region", "fold", "experiment_id", "method_id", "run_dir", "manifest_path",
        "lag_window", "feature_map", "feature_dim", "depth", "units", "alpha", "rho",
        "input_scale", "projection_scale", "recurrent_sparsity", "state_output", "tau0", "seed",
    }
    missing_registry = sorted(required_registry - set(registry.columns))
    missing_atlas = sorted(required_atlas - set(atlas.columns))
    if missing_registry or missing_atlas:
        raise RuntimeError(f"Authority inputs missing columns: registry={missing_registry}, atlas={missing_atlas}")
    authority = registry.rename(columns={
        column: f"authority_{column}"
        for column in registry.columns
        if column not in {"region", "fold", "experiment_id"}
    })
    matched = atlas.merge(
        authority,
        left_on=["region", "fold", "experiment_id", "method_id"],
        right_on=["region", "fold", "experiment_id", "authority_qdesn_method_id"],
        how="inner",
    )
    matched = matched.drop_duplicates(["region", "fold", "experiment_id", "method_id"])
    if matched.duplicated(["region", "fold"]).any() or len(matched) != len(registry):
        recovered = set(zip(matched.region.astype(str), matched.fold.astype(int)))
        expected = set(zip(registry.region.astype(str), registry.fold.astype(int)))
        raise RuntimeError(f"Atlas authority recovery is not one-to-one; missing={sorted(expected - recovered)}")
    return matched.sort_values(["region", "fold"]).reset_index(drop=True)


def source_contract(artifact_repo: Path, row) -> dict:
    run_dir = resolve_from_repo(artifact_repo, row.run_dir)
    cell = run_dir / "cells" / f"region={row.region}" / f"fold={int(row.fold)}"
    source_config = cell / "config.yaml"
    source_adapter_manifest = cell / "adapter/adapter_manifest.json"
    source_experiment_manifest = resolve_from_repo(artifact_repo, row.manifest_path)
    for path in (source_config, source_adapter_manifest, source_experiment_manifest):
        if not path.is_file():
            raise FileNotFoundError(path)
    payload = yaml.safe_load(source_config.read_text())
    smoke = payload.get("pricefm_desn_smoke", {})
    if str(smoke.get("region")) != str(row.region) or int(smoke.get("fold", -1)) != int(row.fold):
        raise RuntimeError(f"Source config region/fold mismatch: {source_config}")
    data_config = resolve_from_repo(artifact_repo, smoke["data_config"])
    if not data_config.is_file():
        raise FileNotFoundError(data_config)
    adapter = smoke["adapter"]
    rhs = smoke["rhs_ns"]
    include_intercept = bool(adapter.get("include_intercept", True))
    if not include_intercept:
        raise RuntimeError(f"Joint PriceFM contract requires source adapter intercept: {source_config}")
    likelihood = "exal" if str(row.authority_qdesn_method_id) == EXAL_METHOD else "al"
    if str(row.authority_qdesn_method_id) not in (AL_METHOD, EXAL_METHOD):
        raise RuntimeError(f"Unsupported authority method: {row.authority_qdesn_method_id}")
    return {
        "region": str(row.region),
        "fold": int(row.fold),
        "case_id": f"pricefm_joint_{str(row.region).lower()}_f{int(row.fold)}",
        "experiment_id": str(row.experiment_id),
        "source_method_id": str(row.authority_qdesn_method_id),
        "likelihood_family": likelihood,
        "vb_method_id": "VB1_structured_v" if likelihood == "exal" else "AL_joint_cavi",
        "mcmc_method_id": "M0_v_collapsed_support_logit" if likelihood == "exal" else "AL_joint_gibbs",
        "feature_policy": str(row.authority_feature_policy),
        "lag_window": int(row.lag_window),
        "feature_map": str(adapter["feature_map"]),
        "feature_dim": int(adapter["feature_dim"]),
        "depth": int(adapter["depth"]),
        "units": json.dumps(parse_list(adapter["units"]), separators=(",", ":")),
        "alpha": float(adapter["alpha"]),
        "rho": float(adapter["rho"]),
        "input_scale": float(adapter["input_scale"]),
        "projection_scale": float(adapter.get("projection_scale", 1.0)),
        "recurrent_sparsity": float(adapter["recurrent_sparsity"]),
        "state_output": str(adapter["state_output"]),
        "tau0": float(rhs["tau0"]),
        "seed": int(adapter["seed"]),
        "paper_quantiles": json.dumps(TAUS),
        "source_config": str(source_config.resolve()),
        "source_config_sha256": sha256(source_config),
        "source_data_config": str(data_config.resolve()),
        "source_data_config_sha256": sha256(data_config),
        "source_adapter_manifest": str(source_adapter_manifest.resolve()),
        "source_adapter_manifest_sha256": sha256(source_adapter_manifest),
        "source_experiment_manifest": str(source_experiment_manifest.resolve()),
        "source_experiment_manifest_sha256": sha256(source_experiment_manifest),
        "source_run_dir": str(run_dir),
        "selection_split": str(row.authority_selected_on_split),
        "selection_metric": str(row.authority_selection_metric),
        "current_authoritative_validation_AQL": float(row.authority_selection_metric_value),
        "selection_is_validation_only": bool(row.authority_selection_is_validation_only),
        "test_metrics_role": str(row.authority_test_metrics_role),
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    registry = pd.read_csv(args.registry)
    atlas = pd.read_csv(args.atlas, low_memory=False)
    matched = matched_authority(registry, atlas)
    contracts = pd.DataFrame([source_contract(args.artifact_repo.resolve(), row) for row in matched.itertuples(index=False)])
    method_counts = contracts.likelihood_family.value_counts().to_dict()

    validation_only = (
        contracts.selection_split.eq("val").all()
        and contracts.selection_metric.eq("AQL").all()
        and contracts.selection_is_validation_only.all()
        and contracts.test_metrics_role.eq("audit_only").all()
    )
    gates = pd.DataFrame([
        {"gate": "authority_cell_count", "passed": len(contracts) == args.expected_cells, "observed": len(contracts)},
        {"gate": "unique_region_fold", "passed": not contracts.duplicated(["region", "fold"]).any(), "observed": contracts[["region", "fold"]].drop_duplicates().shape[0]},
        {"gate": "al_count", "passed": method_counts.get("al", 0) == args.expected_al, "observed": method_counts.get("al", 0)},
        {"gate": "exal_count", "passed": method_counts.get("exal", 0) == args.expected_exal, "observed": method_counts.get("exal", 0)},
        {"gate": "validation_only_selection", "passed": validation_only, "observed": validation_only},
        {"gate": "source_files_hash_pinned", "passed": contracts.filter(regex="_sha256$").apply(lambda col: col.astype(str).str.len().eq(64).all()).all(), "observed": "all"},
        {"gate": "shared_tau0_contract", "passed": contracts.tau0.eq(0.001).all(), "observed": sorted(contracts.tau0.unique().tolist())},
        {"gate": "no_registry_or_article_mutation", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"Stage-R57 authority gates failed: {gates.loc[~gates.passed].to_dict('records')}")

    # Test outcomes are isolated from the fit contract so no runner can select on them.
    test_ledger = registry[[
        "region", "fold", "qdesn_method_id", "qdesn_AQL", "pricefm_method_id", "pricefm_AQL",
        "decision_label", "evidence_path", "evidence_sha256",
    ]].copy()
    test_ledger["role"] = "sealed_test_audit_reference_not_for_selection"

    contracts.to_csv(output / "pricefm_stage_r57_joint_case_authority.csv", index=False)
    test_ledger.to_csv(output / "pricefm_stage_r57_sealed_test_reference_ledger.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r57_authority_gates.csv", index=False)

    source_rows = [
        {"label": "authority_registry", "path": str(args.registry.resolve()), "sha256": sha256(args.registry), "bytes": args.registry.stat().st_size},
        {"label": "stage_r8_atlas", "path": str(args.atlas.resolve()), "sha256": sha256(args.atlas), "bytes": args.atlas.stat().st_size},
        {"label": "authority_freeze_script", "path": str(Path(__file__).resolve()), "sha256": sha256(Path(__file__).resolve()), "bytes": Path(__file__).stat().st_size},
    ]
    for row in contracts.itertuples(index=False):
        for label in ("source_config", "source_data_config", "source_adapter_manifest", "source_experiment_manifest"):
            path = Path(getattr(row, label))
            source_rows.append({
                "label": f"{row.case_id}:{label}", "path": str(path),
                "sha256": getattr(row, f"{label}_sha256"), "bytes": path.stat().st_size,
            })
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)

    summary = {
        "status": "completed_joint_authority_freeze",
        "artifact_repo_head": git_head(args.artifact_repo),
        "surface_cells": len(contracts),
        "al_cells": int(method_counts.get("al", 0)),
        "exal_cells": int(method_counts.get("exal", 0)),
        "quantiles": list(TAUS),
        "selection_role": "validation_only",
        "test_role": "sealed_audit_after_validation_freeze",
        "joint_fit_structure": "single_joint_ordered_seven_quantile_model_per_region_fold",
        "tau0_screening_authorized": False,
        "launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r57_joint_authority_freeze_report.md").write_text(
        "# PriceFM Stage-R57 joint authority freeze\n\n"
        "This freeze transfers all 114 authoritative region/fold DESN and information-set specifications "
        "into one joint seven-quantile case per cell. It preserves the selected AL versus exAL family, "
        "local versus graph input policy, reservoir geometry, and RHS-NS hyper-scale `tau0=0.001`.\n\n"
        "The fit contract contains no test outcomes. Current Q-DESN and cached PriceFM test metrics are "
        "sealed in a separate audit ledger that may only be opened after validation decisions are frozen. "
        "No launch, registry mutation, or article mutation is authorized by this stage.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
