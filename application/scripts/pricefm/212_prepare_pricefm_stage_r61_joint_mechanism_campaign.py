#!/usr/bin/env python3
"""Prepare the validation-only R61 joint-mechanism campaign without launching it."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import pandas as pd
import yaml

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R59 = DATA / "authoritative/pricefm_stage_r59_joint_scoring_contract_20260826"
R57_AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
R57_GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
R60_MONITOR = DATA / "authoritative/pricefm_stage_r60_joint_repair_monitor_20260826"
R8_ATLAS = DATA / (
    "authoritative/pricefm_stage_r8_specification_atlas_quantile_seed_contract_20260706/"
    "pricefm_stage_r8_specification_atlas.csv"
)
OUTPUT = DATA / "authoritative/pricefm_stage_r61_joint_mechanism_campaign_prep_20260826"
GRID = DATA / "experiment_grids/pricefm_stage_r61_joint_mechanism_campaign_20260826"
RUNS = DATA / "runs/pricefm_stage_r61_joint_mechanism_campaign_20260826"
PYTHON = DATA / "venv/bin/python"
TARGETS = {"pricefm_joint_no_5_f2", "pricefm_joint_se_2_f2"}
ARM_IDS = (
    "all_blocks_tau1_freeze5",
    "joint_safe_tau_start",
    "training_only_independent_quantiles",
    "innovation_tau0_strong_0p0005",
    "innovation_tau0_weak_0p005",
    "alternate_likelihood",
    "historical_desn_fallback",
)
FALLBACKS = {
    "pricefm_joint_no_5_f2": {
        "experiment_id": "covm_no5_f2_target_d2_n080x080_s035",
        "method_id": "qdesn_al_rhs_ns_exact_chunked",
        "feature_dim": 80,
        "depth": 2,
        "units": [80, 80],
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.35,
        "seed": 20260603,
        "validation_AQL": 5.900152,
    },
    "pricefm_joint_se_2_f2": {
        "experiment_id": "depthcore_d2_ultracompact_input_scale0p5",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "feature_dim": 40,
        "depth": 2,
        "units": [40, 40],
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.5,
        "seed": 20260609,
        "validation_AQL": 5.539847,
    },
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-repo", type=Path, default=ARTIFACT_REPO)
    p.add_argument("--r59-dir", type=Path, default=R59)
    p.add_argument("--r57-authority-dir", type=Path, default=R57_AUTHORITY)
    p.add_argument("--r57-grid-dir", type=Path, default=R57_GRID)
    p.add_argument("--r60-monitor-dir", type=Path, default=R60_MONITOR)
    p.add_argument("--r8-atlas", type=Path, default=R8_ATLAS)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--python-bin", type=Path, default=PYTHON)
    p.add_argument("--max-iter", type=int, default=150)
    p.add_argument("--tol", type=float, default=1e-4)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()


def prepare_dir(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def arm_specs(source_likelihood: str) -> tuple[dict, ...]:
    safe = {
        "anchor_tau0": 0.001,
        "innovation_tau0": 0.001,
        "anchor_init_tau": 1.0,
        "innovation_init_tau": 0.05,
        "freeze_iters": 5,
        "vb_inner": 5,
    }
    return (
        {
            "arm_id": "all_blocks_tau1_freeze5",
            "question": "individual_tau_initialization_parity",
            "initialization_mode": "controlled_cold",
            "rhs_control": {**safe, "innovation_init_tau": 1.0},
            "likelihood_family": source_likelihood,
            "adapter_variant": "authority",
            "complexity_rank": 2,
        },
        {
            "arm_id": "joint_safe_tau_start",
            "question": "parameterization_aware_rhs_initialization",
            "initialization_mode": "controlled_cold",
            "rhs_control": safe,
            "likelihood_family": source_likelihood,
            "adapter_variant": "authority",
            "complexity_rank": 1,
        },
        {
            "arm_id": "training_only_independent_quantiles",
            "question": "bad_joint_coefficient_basin",
            "initialization_mode": "training_only_independent_quantiles",
            "rhs_control": safe,
            "likelihood_family": source_likelihood,
            "adapter_variant": "authority",
            "complexity_rank": 3,
        },
        {
            "arm_id": "innovation_tau0_strong_0p0005",
            "question": "stronger_cross_quantile_shrinkage",
            "initialization_mode": "controlled_cold",
            "rhs_control": {**safe, "innovation_tau0": 0.0005},
            "likelihood_family": source_likelihood,
            "adapter_variant": "authority",
            "complexity_rank": 4,
        },
        {
            "arm_id": "innovation_tau0_weak_0p005",
            "question": "weaker_cross_quantile_shrinkage",
            "initialization_mode": "controlled_cold",
            "rhs_control": {**safe, "innovation_tau0": 0.005},
            "likelihood_family": source_likelihood,
            "adapter_variant": "authority",
            "complexity_rank": 5,
        },
        {
            "arm_id": "alternate_likelihood",
            "question": "joint_likelihood_stability",
            "initialization_mode": "controlled_cold",
            "rhs_control": safe,
            "likelihood_family": "exal" if source_likelihood == "al" else "al",
            "adapter_variant": "authority",
            "complexity_rank": 6,
        },
        {
            "arm_id": "historical_desn_fallback",
            "question": "joint_specific_desn_geometry",
            "initialization_mode": "controlled_cold",
            "rhs_control": safe,
            "likelihood_family": source_likelihood,
            "adapter_variant": "historical_fallback",
            "complexity_rank": 7,
        },
    )


def scientific_spec_sha256(smoke: dict, runtime: dict) -> str:
    adapter = copy.deepcopy(smoke.get("adapter", {}))
    adapter.pop("output_dir", None)
    payload = {
        "region": smoke.get("region"),
        "fold": int(smoke.get("fold")),
        "quantiles": list(map(float, runtime["quantiles"])),
        "likelihood_family": runtime["likelihood_family"],
        "feature_policy": smoke.get("feature_policy", ""),
        "adapter": adapter,
        "rhs_control": runtime["rhs_control"],
        "initialization_mode": runtime["initialization"]["mode"],
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def validate_fallback(atlas: pd.DataFrame, source_case_id: str, region: str, fold: int) -> dict:
    expected = FALLBACKS[source_case_id]
    rows = atlas[
        atlas.experiment_id.astype(str).eq(expected["experiment_id"])
        & atlas.region.astype(str).eq(region)
        & atlas.fold.astype(int).eq(fold)
        & atlas.method_id.astype(str).eq(expected["method_id"])
        & atlas.source_quantile_matches_target.astype(str).eq("True")
    ]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one historical validation row for {source_case_id}, found {len(rows)}")
    row = rows.iloc[0]
    checks = {
        "feature_dim": int(row.feature_dim), "depth": int(row.depth),
        "alpha": float(row.alpha), "rho": float(row.rho), "input_scale": float(row.input_scale),
        "seed": int(row.seed), "validation_AQL": float(row.val_AQL),
    }
    for key, value in checks.items():
        if abs(float(value) - float(expected[key])) > 1e-6:
            raise RuntimeError(f"Historical fallback mismatch for {source_case_id}: {key}")
    if str(row.units).replace(" ", "") != str(expected["units"]).replace(" ", ""):
        raise RuntimeError(f"Historical fallback unit mismatch for {source_case_id}")
    return {
        **expected,
        "full_config": str(row.full_config),
        "data_config": str(row.data_config),
        "observed_validation_AQL": float(row.val_AQL),
    }


def run(args: argparse.Namespace) -> dict:
    if args.max_iter < 25 or args.tol <= 0:
        raise ValueError("Invalid R61 fit controls")
    output, grid, runs = args.output_dir.resolve(), args.grid_dir.resolve(), args.run_dir.resolve()
    prepare_dir(output, args.force)
    prepare_dir(grid, args.force)
    runs.mkdir(parents=True, exist_ok=True)

    r59_summary_path = args.r59_dir / "summary.json"
    r59_decisions_path = args.r59_dir / "pricefm_stage_r59_joint_scoring_decisions.csv"
    authority_path = args.r57_authority_dir / "pricefm_stage_r57_joint_case_authority.csv"
    r57_manifest_path = args.r57_grid_dir / "launch_manifest.csv"
    r60_summary_path = args.r60_monitor_dir / "summary.json"
    r59_summary = read_json(r59_summary_path)
    r60_summary = read_json(r60_summary_path)
    decisions = pd.read_csv(r59_decisions_path)
    authority = pd.read_csv(authority_path)
    old_manifest = pd.read_csv(r57_manifest_path)
    atlas = pd.read_csv(args.r8_atlas, low_memory=False)
    if (
        r59_summary.get("status") != "completed_joint_scoring_contract_freeze"
        or not bool(r59_summary.get("joint_scoring_contract_frozen", False))
        or bool(r59_summary.get("test_opened", True))
    ):
        raise RuntimeError("R59 scoring contract is not frozen with test sealed")
    target_decisions = decisions[decisions.case_id.astype(str).isin(TARGETS)].copy()
    if set(target_decisions.case_id.astype(str)) != TARGETS:
        raise RuntimeError("R59 does not contain both R61 targets")
    forbidden = {"qdesn_AQL", "pricefm_AQL", "test_AQL", "cached_pricefm_test_AQL"}
    if forbidden & set(target_decisions.columns):
        raise RuntimeError("Test outcomes leaked into the R61 design authority")
    sources = authority.merge(
        old_manifest[["case_id", "config", "smoke_config", "output_dir"]],
        on="case_id", how="inner", validate="one_to_one",
    )
    sources = sources[sources.case_id.astype(str).isin(TARGETS)].copy()
    if len(sources) != 2:
        raise RuntimeError("R61 could not recover both source contracts")

    source_root = args.source_root.resolve()
    launch_rows, arm_rows, source_rows, diagnosis_rows, fallback_rows = [], [], [], [], []
    for source in sources.sort_values(["region", "fold"]).itertuples(index=False):
        old_runtime = yaml.safe_load(Path(source.config).read_text())["pricefm_stage_r57_joint_vb"]
        old_smoke = yaml.safe_load(Path(source.smoke_config).read_text())["pricefm_desn_smoke"]
        source_likelihood = str(source.likelihood_family)
        fallback = validate_fallback(atlas, str(source.case_id), str(source.region), int(source.fold))
        fallback_rows.append({
            "source_case_id": source.case_id, "region": source.region, "fold": int(source.fold),
            "experiment_id": fallback["experiment_id"], "method_id": fallback["method_id"],
            "validation_AQL": fallback["observed_validation_AQL"],
            "selection_role": "historical_validation_only", "test_used_for_design": False,
            "full_config": fallback["full_config"], "data_config": fallback["data_config"],
        })
        diagnosis_rows.append({
            "source_case_id": source.case_id, "region": source.region, "fold": int(source.fold),
            "individual_likelihood": source_likelihood,
            "individual_validation_AQL": float(source.current_authoritative_validation_AQL),
            "individual_feature_policy": source.feature_policy,
            "individual_depth": int(source.depth), "individual_units": source.units,
            "individual_tau0": float(source.tau0),
            "r60_status": r60_summary.get("status", "not_materialized"),
            "leading_hypothesis": (
                "optimization_plus_joint_rhs_parameterization" if source.region == "NO_5"
                else "stable_bad_joint_basin_or_cross_quantile_coupling"
            ),
            "test_opened": False,
        })
        for arm in arm_specs(source_likelihood):
            arm_case_id = f"{source.case_id}__r61__{arm['arm_id']}"
            case_dir = runs / arm_case_id
            adapter_dir, model_dir = case_dir / "adapter", case_dir / "model"
            smoke_path = grid / "configs/adapter" / f"{arm_case_id}.yaml"
            runtime_path = grid / "configs/joint_vb" / f"{arm_case_id}.yaml"
            smoke_path.parent.mkdir(parents=True, exist_ok=True)
            runtime_path.parent.mkdir(parents=True, exist_ok=True)
            smoke = copy.deepcopy(old_smoke)
            smoke["splits"] = ["train", "val"]
            smoke["adapter"]["output_dir"] = str(adapter_dir)
            smoke["run"]["output_dir"] = str(model_dir)
            if arm["adapter_variant"] == "historical_fallback":
                for key in ("feature_dim", "depth", "units", "alpha", "rho", "input_scale"):
                    smoke["adapter"][key] = copy.deepcopy(fallback[key])
                smoke["adapter"]["seed"] = int(fallback["seed"])
                smoke["run"]["seed"] = int(fallback["seed"])
                smoke["adapter"]["name"] = f"{source.region}_fold{int(source.fold)}_r61_historical_fallback"
            smoke["artifact_hygiene"] = {
                "enabled": True,
                "clean_adapter_patterns": ["X_*.csv", "y_*.csv", "rows_*.csv", "rows_all.csv"],
                "preserve_patterns": [
                    "adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.*",
                    "feature_provenance.csv",
                ],
            }
            smoke_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke}, sort_keys=False))
            likelihood = arm["likelihood_family"]
            method_id = f"joint_qdesn_{likelihood}_rhs_ns_vb_r61_{arm['arm_id']}"
            runtime = {
                "stage": "R61", "case_id": arm_case_id, "source_case_id": str(source.case_id),
                "arm_id": arm["arm_id"], "region": str(source.region), "fold": int(source.fold),
                "likelihood_family": likelihood, "method_id": method_id,
                "source_method_id": str(source.source_method_id),
                "source_experiment_id": str(source.experiment_id),
                "source_config": str(source.source_config),
                "source_config_sha256": str(source.source_config_sha256),
                "smoke_config": str(smoke_path), "adapter_dir": str(adapter_dir),
                "output_dir": str(model_dir), "source_root": str(source_root),
                "python_bin": str(args.python_bin.absolute()),
                "adapter_builder": str(source_root / "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py"),
                "summarizer": str(source_root / "application/scripts/pricefm/09_summarize_desn_model_smoke.py"),
                "allowed_splits": ["train", "val"], "test_access_authorized": False,
                "quantiles": list(map(float, old_runtime["quantiles"])),
                "rhs_control": copy.deepcopy(arm["rhs_control"]),
                "initialization": {"mode": arm["initialization_mode"]},
                "inherit_al_bootstrap_rhs": True,
                "a_sigma": float(old_runtime["a_sigma"]), "b_sigma": float(old_runtime["b_sigma"]),
                "max_iter": int(args.max_iter), "tol": float(args.tol),
                "max_dense_dim": int(old_runtime["max_dense_dim"]),
                "registry_mutation_authorized": False, "article_mutation_authorized": False,
            }
            runtime_path.write_text(yaml.safe_dump({"pricefm_stage_r61_joint_mechanism": runtime}, sort_keys=False))
            spec_hash = scientific_spec_sha256(smoke, runtime)
            common = {
                "case_id": arm_case_id, "source_case_id": str(source.case_id),
                "region": str(source.region), "fold": int(source.fold),
                "likelihood_family": likelihood, "method_id": method_id,
                "arm_id": arm["arm_id"], "question": arm["question"],
                "initialization_mode": arm["initialization_mode"],
                "adapter_variant": arm["adapter_variant"], "max_iter": int(args.max_iter),
                "config": str(runtime_path), "smoke_config": str(smoke_path),
                "output_dir": str(model_dir), "scientific_spec_sha256": spec_hash,
                "complexity_rank": int(arm["complexity_rank"]),
                "current_authoritative_validation_AQL": float(source.current_authoritative_validation_AQL),
                "status": "prepared_blocked_pending_r60_and_user_authorization",
                "launch_authorized": False, "test_access_authorized": False,
            }
            launch_rows.append(common)
            arm_rows.append({
                **common, **arm["rhs_control"],
                "selection_role": "validation_only_monotone_contract",
                "r60_reference_reused_not_duplicated": True,
                "eligible_only_if_r60_unresolved": True,
            })
            for label, path in (("runtime_config", runtime_path), ("adapter_config", smoke_path)):
                source_rows.append({
                    "case_id": arm_case_id, "label": label, "path": str(path),
                    "sha256": sha256(path), "bytes": path.stat().st_size,
                })

    manifest = pd.DataFrame(launch_rows).sort_values(["region", "fold", "complexity_rank"]).reset_index(drop=True)
    arms = pd.DataFrame(arm_rows).sort_values(["region", "fold", "complexity_rank"]).reset_index(drop=True)
    manifest_path = grid / "launch_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    arms.to_csv(output / "pricefm_stage_r61_joint_mechanism_arm_contract.csv", index=False)
    pd.DataFrame(diagnosis_rows).to_csv(output / "pricefm_stage_r61_case_diagnosis.csv", index=False)
    pd.DataFrame(fallback_rows).to_csv(output / "pricefm_stage_r61_historical_fallback_evidence.csv", index=False)
    pd.DataFrame([
        {"excluded_design": "full_cartesian_grid", "reason": "confounds mechanisms and wastes completed R60 reference evidence"},
        {"excluded_design": "shared_scalar_tau0_sweep", "reason": "cannot separate anchor and innovation shrinkage"},
        {"excluded_design": "graph_feature_screen", "reason": "both individual winners are target-only and NO_5 graph validation was worse"},
        {"excluded_design": "large_capacity_screen", "reason": "same DESN already succeeds individually; SE_2 large historical capacity was not competitive"},
        {"excluded_design": "test_adaptive_arm_selection", "reason": "test remains sealed until validation selection is immutable"},
    ]).to_csv(output / "pricefm_stage_r61_excluded_designs.csv", index=False)

    gates = pd.DataFrame([
        {"gate": "exact_two_targets", "passed": set(manifest.source_case_id) == TARGETS, "observed": manifest.source_case_id.nunique()},
        {"gate": "seven_arms_per_target", "passed": bool(manifest.groupby("source_case_id").size().eq(7).all()), "observed": len(manifest)},
        {"gate": "exact_preregistered_arm_set", "passed": all(set(g.arm_id) == set(ARM_IDS) for _, g in manifest.groupby("source_case_id")), "observed": sorted(manifest.arm_id.unique())},
        {"gate": "train_validation_only", "passed": bool(~manifest.test_access_authorized.any()), "observed": "train,val"},
        {"gate": "launch_blocked", "passed": bool(~manifest.launch_authorized.any()), "observed": bool(manifest.launch_authorized.any())},
        {"gate": "r60_reference_not_duplicated", "passed": bool(arms.r60_reference_reused_not_duplicated.all()), "observed": True},
        {"gate": "historical_fallbacks_validation_backed", "passed": len(fallback_rows) == 2, "observed": len(fallback_rows)},
        {"gate": "registry_article_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r61_prelaunch_gates.csv", index=False)
    if not gates.passed.astype(bool).all():
        raise RuntimeError(f"R61 prep gates failed: {gates.loc[~gates.passed.astype(bool)].to_dict('records')}")

    launch_contract = {
        "pricefm_stage_r61_joint_mechanism_launch": {
            "stage": "R61", "manifest": str(manifest_path),
            "runner": str(source_root / "application/scripts/pricefm/213_run_pricefm_stage_r61_joint_mechanism_case.R"),
            "launcher": str(source_root / "application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py"),
            "maximum_workers": 14, "one_process_per_cpu": True,
            "numerical_threads_per_process": 1, "cpu_list_must_be_reaudited_at_launch": True,
            "r60_closeout_must_be_checked_before_launch": True,
            "drop_case_arms_if_r60_already_resolved": True,
            "launch_authorized": False, "test_access_authorized": False,
            "mcmc_launch_authorized": False, "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
    }
    launch_path = output / "pricefm_stage_r61_joint_mechanism_launch_blocked.yaml"
    launch_path.write_text(yaml.safe_dump(launch_contract, sort_keys=False))

    code_sources = [
        source_root / "application/R/joint_qvp_qdesn.R",
        source_root / "application/R/joint_exqdesn_exact_structured_inference.R",
        source_root / "application/R/pricefm_joint_quantile_inference.R",
        source_root / "application/scripts/pricefm/212_prepare_pricefm_stage_r61_joint_mechanism_campaign.py",
        source_root / "application/scripts/pricefm/213_run_pricefm_stage_r61_joint_mechanism_case.R",
        source_root / "application/scripts/pricefm/214_closeout_pricefm_stage_r61_joint_mechanism_campaign.py",
        source_root / "application/scripts/pricefm/215_monitor_pricefm_stage_r61_joint_mechanism_campaign.py",
        source_root / "application/tests/test_pricefm_stage_r61_joint_mechanism_campaign.py",
        source_root / "application/tests/test_pricefm_stage_r61_joint_mechanism_controls.R",
        source_root / "docs/implementation_notes/pricefm_stage_r61_joint_mechanism_campaign_20260826.md",
    ]
    for label, path in (
        ("r59_summary", r59_summary_path), ("r59_decisions", r59_decisions_path),
        ("r57_authority", authority_path), ("r57_launch_manifest", r57_manifest_path),
        ("r8_atlas", args.r8_atlas), ("r60_monitor_summary", r60_summary_path),
    ):
        if path.is_file():
            source_rows.append({"case_id": "ALL", "label": label, "path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size})
    for path in code_sources:
        if not path.is_file():
            raise FileNotFoundError(path)
        source_rows.append({"case_id": "ALL", "label": "code_source", "path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)

    summary = {
        "status": "prepared_r61_joint_mechanism_campaign_not_launched",
        "source_head": git_head(source_root), "target_cases": 2, "prepared_cases": len(manifest),
        "arms_per_case": 7, "r60_status_at_prep": r60_summary.get("status", "not_materialized"),
        "r60_pending_or_running": int(r60_summary.get("pending_or_running", 0)),
        "selection_role": "validation_only_monotone_contract", "test_opened": False,
        "launch_authorized": False, "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "recommended_action": "wait_for_explicit_user_launch_authorization_after_r60_status_and_cpu_reaudit",
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r61_joint_mechanism_campaign_report.md").write_text(
        "# PriceFM Stage-R61 joint mechanism campaign prep\n\n"
        "R61 prepares seven validation-only, case-specific mechanism arms for each of `NO_5` fold 2 "
        "and `SE_2` fold 2. R60 remains the unchanged reference and is not duplicated. The arms isolate "
        "RHS initialization, joint-safe warm-up, training-only independent coefficient initialization, "
        "stronger or weaker innovation shrinkage, likelihood, and one historically validation-backed DESN fallback.\n\n"
        "All 14 rows are prepared but launch-blocked. Test, MCMC, registry, and article actions remain blocked. "
        "Immediately before any later launch, R60 must be closed out, repaired cases must be pruned, and CPU "
        "availability must be re-audited.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
