#!/usr/bin/env python3
"""Prepare the frozen SE_2 R95 surface for an authorized no-refit test audit."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd
import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    content_task_id,
    file_record,
    git_identity,
    prepare_empty_directory,
    sha256_file,
    validate_quantiles,
    verify_file_record,
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r96_se2_scoring_only_test_20260908"
R95_CLOSEOUT = DATA / "authoritative/pricefm_stage_r95_allfold_validation_closeout_20260907"
R95_GRID = DATA / "experiment_grids/pricefm_stage_r95_region_frozen_allfold_validation_20260907"
R94_FROZEN = DATA / (
    "authoritative/pricefm_stage_r94_validation_family_closeout_20260907/"
    "pricefm_stage_r94_frozen_validation_family.json"
)
R93_TASK = DATA / (
    "authoritative/pricefm_stage_r93_overnight_validation_ladder_20260906/"
    "outer_normal_closeout/pricefm_stage_r93_quantile_task.json"
)
REGISTRY = DATA / (
    "authoritative/pricefm_full_surface_decision_closeout_20260704/"
    "pricefm_full_surface_decision_registry.csv"
)
SOURCE_DATA_CONFIG = ARTIFACT_REPO / "application/config/pricefm_data_pipeline.yaml"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
PROCESSED = DATA / "processed_stage_r96_se2_scoring_only_test_20260908"
OUTPUT = DATA / "authoritative/pricefm_stage_r96_scoring_only_test_prep_20260908"
SCORER = Path(__file__).with_name("312_run_pricefm_stage_r96_scoring_only_fold.py")
LAUNCHER = Path(__file__).with_name("313_launch_pricefm_stage_r96_scoring_only_test.py")
CLOSEOUT = Path(__file__).with_name("314_closeout_pricefm_stage_r96_scoring_only_test.py")
ADAPTER = Path(__file__).with_name("pricefm_desn_adapter.py")
CODE_ROOT = Path(__file__).resolve().parents[3]
ACTIVE_REGIONS = ("SE_2", "NO_3", "NO_4", "SE_1", "SE_3")
FOLDS = (1, 2, 3)
BLOCKED = (
    "model_refit_authorized",
    "selection_change_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--r95-closeout", type=Path, default=R95_CLOSEOUT)
    value.add_argument("--r95-grid", type=Path, default=R95_GRID)
    value.add_argument("--r94-frozen", type=Path, default=R94_FROZEN)
    value.add_argument("--r93-task", type=Path, default=R93_TASK)
    value.add_argument("--authority-registry", type=Path, default=REGISTRY)
    value.add_argument("--source-data-config", type=Path, default=SOURCE_DATA_CONFIG)
    value.add_argument("--grid-dir", type=Path, default=GRID)
    value.add_argument("--run-dir", type=Path, default=RUNS)
    value.add_argument("--processed-dir", type=Path, default=PROCESSED)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--code-root", type=Path, default=CODE_ROOT)
    value.add_argument("--replay-tolerance", type=float, default=1e-10)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    value.add_argument("--skip-git-check", action="store_true", help=argparse.SUPPRESS)
    return value


def write_yaml(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w") as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)
    temporary.replace(path)


def parse_units(value: Any) -> list[int]:
    parsed = json.loads(value) if isinstance(value, str) else value
    units = [int(item) for item in parsed]
    if not units or any(item <= 0 for item in units):
        raise RuntimeError("R96 frozen units are invalid")
    return units


def make_test_data_config(source: dict[str, Any], processed: Path, lag_window: int) -> dict[str, Any]:
    payload = copy.deepcopy(source)
    spec = payload["pricefm"]
    for name in ("raw_dir", "interim_dir", "external_repo_dir", "log_dir"):
        path = Path(spec[name])
        if not path.is_absolute():
            spec[name] = str((ARTIFACT_REPO / path).resolve())
    spec["processed_dir"] = str(processed.resolve())
    spec["allow_absolute_local_paths"] = True
    spec["windows"]["lag_window"] = int(lag_window)
    spec["pilot"] = {"enabled": True, "region": "SE_2", "fold": 1}
    by_fold = {int(item["fold"]): item for item in spec["splits"]}
    spec["splits"] = [copy.deepcopy(by_fold[fold]) for fold in FOLDS]
    if any(set(item) != {"fold", "train", "val", "test"} for item in spec["splits"]):
        raise RuntimeError("R96 requires exact train/validation/test fold intervals")
    return payload


def frozen_adapter_records(r94: dict[str, Any], fold: int) -> dict[str, dict[str, Any]]:
    if fold == 1:
        records = {Path(item["path"]).name: item for item in r94["adapter_files"]}
        required = {"X_val.csv", "rows_val.csv", "feature_manifest.json"}
        if not required.issubset(records):
            raise RuntimeError("R94 Fold-1 adapter evidence is incomplete")
        return {name: records[name] for name in required}
    adapter = DATA / (
        "runs/pricefm_stage_r95_region_frozen_allfold_validation_20260907/normal/"
        f"cells/region=SE_2/fold={fold}/adapter"
    )
    return {
        name: file_record(adapter / name, f"fold{fold}_frozen_{name}")
        for name in ("X_val.csv", "rows_val.csv", "feature_manifest.json")
    }


def scaler_record(r94: dict[str, Any], fold: int) -> dict[str, Any]:
    if fold == 1:
        verify_file_record(r94["scaler"], label="R94 Fold-1 scaler")
        return r94["scaler"]
    path = DATA / (
        "processed_stage_r95_region_frozen_allfold_20260907/scalers/"
        f"fold_{fold}/per_region_separate_xy_scalers.joblib"
    )
    return file_record(path, f"fold{fold}_training_fitted_scaler")


def validate_adapter_contract(smoke: dict[str, Any], frozen_desn: dict[str, Any]) -> None:
    adapter = smoke["adapter"]
    observed = {
        "depth": int(adapter["depth"]),
        "units": [int(value) for value in adapter["units"]],
        "alpha": float(adapter["alpha"]),
        "rho": float(adapter["rho"]),
        "input_scale": float(adapter["input_scale"]),
        "state_output": str(adapter["state_output"]),
        "feature_policy": str(smoke["feature_policy"]),
    }
    expected = {
        "depth": int(frozen_desn["depth"]),
        "units": parse_units(frozen_desn["units"]),
        "alpha": float(frozen_desn["alpha"]),
        "rho": float(frozen_desn["rho"]),
        "input_scale": float(frozen_desn["input_scale"]),
        "state_output": str(frozen_desn["state_output"]),
        "feature_policy": str(frozen_desn["feature_policy"]),
    }
    if observed != expected:
        raise RuntimeError(f"R96 adapter contract differs from R95: {observed} != {expected}")
    neighbors = [str(value) for value in adapter["spatial"]["neighbor_regions"]]
    if ["SE_2", *neighbors] != list(ACTIVE_REGIONS):
        raise RuntimeError("R96 graph information set differs from the frozen R95 contract")


def run(args: argparse.Namespace) -> dict[str, Any]:
    if args.replay_tolerance != 1e-10:
        raise RuntimeError("R96 validation replay tolerance is preregistered at 1e-10")
    required = (
        args.r95_closeout / "summary.json",
        args.r95_closeout / "pricefm_stage_r95_frozen_allfold_validation_surface.json",
        args.r95_closeout / "pricefm_stage_r95_fold_family_validation_metrics.csv",
        args.r95_grid / "launch_summary.json",
        args.r94_frozen,
        args.r93_task,
        args.authority_registry,
        args.source_data_config,
        SCORER,
        LAUNCHER,
        CLOSEOUT,
        ADAPTER,
    )
    for path in required:
        if not Path(path).is_file():
            raise FileNotFoundError(path)

    r95_summary_path = args.r95_closeout / "summary.json"
    surface_path = args.r95_closeout / "pricefm_stage_r95_frozen_allfold_validation_surface.json"
    r95_summary = json.loads(r95_summary_path.read_text())
    surface = json.loads(surface_path.read_text())
    launch = json.loads((args.r95_grid / "launch_summary.json").read_text())
    if (
        r95_summary.get("status") != "allfold_validation_surface_frozen_awaiting_test_authorization"
        or r95_summary.get("frozen_surface_sha256") != sha256_file(surface_path)
        or launch.get("status") != "completed_validation_closeout"
        or launch.get("completed") != 30
        or launch.get("failed_or_blocked") != 0
    ):
        raise RuntimeError("R95 is not a complete hash-frozen pre-test surface")
    if (
        surface.get("region") != "SE_2"
        or surface.get("effective_whole_region_family") != "exal"
        or surface.get("folds") != list(FOLDS)
        or surface.get("test_opened") is not False
        or surface.get("test_access_authorized") is not False
        or surface.get("per_fold_or_quantile_family_mixing") is not False
    ):
        raise RuntimeError("R96 accepts only the frozen coherent SE_2 exAL surface")
    validate_quantiles(surface.get("quantiles", ()), label="R95 frozen surface quantiles")
    if sum(len(surface["selected_atoms"].get(str(fold), ())) for fold in FOLDS) != 21:
        raise RuntimeError("R95 frozen surface does not contain 21 selected atoms")

    r94 = json.loads(args.r94_frozen.read_text())
    r93_task = json.loads(args.r93_task.read_text())
    r93_config = yaml.safe_load(Path(r93_task["config"]).read_text())["pricefm_desn_smoke"]
    validate_adapter_contract(r93_config, surface["frozen_desn"])
    if int(r93_config["adapter"]["seed"]) != 2026090601:
        raise RuntimeError("R96 frozen reservoir seed changed")

    registry = pd.read_csv(args.authority_registry)
    references = registry.loc[registry.region.eq("SE_2"), [
        "region", "fold", "qdesn_method_id", "qdesn_AQL",
        "pricefm_method_id", "pricefm_AQL", "selection_is_validation_only",
        "test_metrics_role", "evidence_path", "evidence_sha256",
    ]].sort_values("fold")
    if (
        len(references) != 3
        or references.fold.astype(int).tolist() != list(FOLDS)
        or not np.isfinite(references[["qdesn_AQL", "pricefm_AQL"]]).all().all()
        or not references.selection_is_validation_only.astype(bool).all()
    ):
        raise RuntimeError("R96 authoritative SE_2 comparator surface is invalid")
    references = references.rename(columns={
        "qdesn_method_id": "authoritative_qdesn_method_id",
        "qdesn_AQL": "authoritative_qdesn_test_AQL",
        "pricefm_method_id": "cached_pricefm_method_id",
        "pricefm_AQL": "cached_pricefm_test_AQL",
    })

    code_root = args.code_root.resolve()
    if args.skip_git_check:
        git = {
            "worktree": str(code_root), "branch": "fixture", "head": "fixture",
            "upstream": "fixture", "upstream_head": "fixture", "clean": True,
        }
    else:
        identity = git_identity(code_root)
        git = identity.to_dict()
        if not identity.clean or identity.head != identity.upstream_head:
            raise RuntimeError("R96 preparation requires a clean synchronized task branch")

    quarantine = args.quarantine_root or (args.output_dir.parent / "quarantine")
    grid, quarantined_grid = prepare_empty_directory(
        args.grid_dir, quarantine_root=quarantine, reason="replaced_r96_grid",
        allow_quarantine=args.quarantine_existing,
    )
    output, quarantined_output = prepare_empty_directory(
        args.output_dir, quarantine_root=quarantine, reason="replaced_r96_prep",
        allow_quarantine=args.quarantine_existing,
    )
    args.run_dir.mkdir(parents=True, exist_ok=True)
    configs = grid / "configs"
    tasks = grid / "tasks"
    configs.mkdir()
    tasks.mkdir()

    source_data = yaml.safe_load(args.source_data_config.read_text())
    data_config_path = configs / "pricefm_stage_r96_test_data.yaml"
    write_yaml(
        data_config_path,
        make_test_data_config(source_data, args.processed_dir, int(surface["frozen_desn"]["lag_window"])),
    )

    validation_metrics = pd.read_csv(
        args.r95_closeout / "pricefm_stage_r95_fold_family_validation_metrics.csv"
    )
    validation_metrics = validation_metrics.loc[validation_metrics.family.eq("exal")].set_index("fold")
    selected_rows: list[dict[str, Any]] = []
    config_paths: dict[int, Path] = {}
    for fold in FOLDS:
        records = frozen_adapter_records(r94, fold)
        for record in records.values():
            verify_file_record(record, label=f"R96 Fold-{fold} validation adapter")
        scaler = scaler_record(r94, fold)
        verify_file_record(scaler, label=f"R96 Fold-{fold} scaler")
        smoke = copy.deepcopy(r93_config)
        smoke["data_config"] = str(data_config_path.resolve())
        smoke["fold"] = fold
        smoke["splits"] = ["val", "test"]
        smoke["adapter"]["output_dir"] = str((args.run_dir / f"fold={fold}" / "adapter").resolve())
        smoke["adapter"]["keep_matrices_after_success"] = False
        smoke["run"]["output_dir"] = str((args.run_dir / f"fold={fold}" / "score").resolve())
        validate_adapter_contract(smoke, surface["frozen_desn"])
        config_path = configs / f"pricefm_stage_r96_se2_fold{fold}.yaml"
        write_yaml(config_path, {
            "pricefm_desn_smoke": smoke,
            "pricefm_stage_r96": {
                "stage": "R96", "region": "SE_2", "fold": fold,
                "role": "scoring_only_test_audit_after_frozen_R95",
                "test_access_authorized": True,
                **{name: False for name in BLOCKED},
            },
        })
        config_paths[fold] = config_path
        atoms = sorted(surface["selected_atoms"][str(fold)], key=lambda item: float(item["tau"]))
        if not np.allclose([float(item["tau"]) for item in atoms], PAPER_QUANTILES):
            raise RuntimeError(f"R96 Fold-{fold} quantile surface is incomplete")
        for atom in atoms:
            for role in ("beta", "prediction", "terminal"):
                verify_file_record(atom[role], label=f"R96 Fold-{fold} selected {role}")
            selected_rows.append({
                "case_id": f"pricefm_region_frozen_se_2_f{fold}",
                "region": "SE_2", "fold": fold, "selected_family": "exal",
                "tau": float(atom["tau"]),
                "selected_validation_AQL": float(validation_metrics.loc[fold, "AQL"]),
                "beta_path": atom["beta"]["path"], "beta_sha256": atom["beta"]["sha256"],
                "validation_prediction_path": atom["prediction"]["path"],
                "validation_prediction_sha256": atom["prediction"]["sha256"],
                "terminal_path": atom["terminal"]["path"],
                "terminal_sha256": atom["terminal"]["sha256"],
                "x_val_path": records["X_val.csv"]["path"],
                "x_val_sha256": records["X_val.csv"]["sha256"],
                "rows_val_path": records["rows_val.csv"]["path"],
                "rows_val_sha256": records["rows_val.csv"]["sha256"],
                "feature_manifest_path": records["feature_manifest.json"]["path"],
                "feature_manifest_sha256": records["feature_manifest.json"]["sha256"],
                "source_case_config": str(config_path.resolve()),
                "source_case_config_sha256": sha256_file(config_path),
                "scaler_path": scaler["path"], "scaler_sha256": scaler["sha256"],
            })
    selected = pd.DataFrame(selected_rows).sort_values(["fold", "tau"])
    selected_path = output / "pricefm_stage_r96_frozen_atom_manifest.csv"
    selected.to_csv(selected_path, index=False)
    references_path = output / "pricefm_stage_r96_frozen_dual_references.csv"
    references.to_csv(references_path, index=False)

    pipeline = {
        "schema_version": 1, "stage": "R96", "tag": TAG,
        "region": "SE_2", "folds": list(FOLDS),
        "quantiles": list(PAPER_QUANTILES), "selected_family": "exal",
        "selection_rule": "reuse_hash_frozen_R95_whole_region_exAL_no_test_reselection",
        "r95_summary": file_record(r95_summary_path, "R95_closeout_summary"),
        "r95_frozen_surface": file_record(surface_path, "R95_frozen_allfold_surface"),
        "authority_registry": file_record(args.authority_registry, "authoritative_QDESN_and_cached_PriceFM_registry"),
        "frozen_atoms": file_record(selected_path, "R96_frozen_atom_manifest"),
        "frozen_references": file_record(references_path, "R96_frozen_dual_references"),
        "source_data_config": file_record(args.source_data_config, "canonical_data_config"),
        "generated_data_config": file_record(data_config_path, "R96_authorized_test_data_config"),
        "processed_dir": str(args.processed_dir.resolve()),
        "run_dir": str(args.run_dir.resolve()),
        "active_window_regions": list(ACTIVE_REGIONS),
        "replay_tolerance": args.replay_tolerance,
        "scorer": file_record(SCORER, "R96_scoring_only_worker"),
        "launcher": file_record(LAUNCHER, "R96_scoring_only_launcher"),
        "closeout": file_record(CLOSEOUT, "R96_dual_comparator_closeout"),
        "adapter": file_record(ADAPTER, "PriceFM_DESN_adapter"),
        "git_identity": git,
        "test_opened": False, "test_access_authorized": True,
        **{name: False for name in BLOCKED},
    }
    pipeline_hash = canonical_sha256(pipeline)
    pipeline["pipeline_contract_sha256"] = pipeline_hash
    atomic_write_json(grid / "pipeline_contract.json", pipeline)

    task_rows = []
    for fold in FOLDS:
        identity = {
            "pipeline_contract_sha256": pipeline_hash,
            "region": "SE_2", "fold": fold, "role": "scoring_only_test",
        }
        task_id = content_task_id(f"r96_se_2_f{fold}_scoring_only", identity)
        task = {
            "schema_version": 1, "stage": "R96", "task_id": task_id,
            "case_id": f"pricefm_region_frozen_se_2_f{fold}",
            "region": "SE_2", "fold": fold,
            "pipeline_contract_sha256": pipeline_hash,
            "config": str(config_paths[fold].resolve()),
            "config_sha256": sha256_file(config_paths[fold]),
            "selected_manifest": str(selected_path.resolve()),
            "selected_manifest_sha256": sha256_file(selected_path),
            "reference_manifest": str(references_path.resolve()),
            "reference_manifest_sha256": sha256_file(references_path),
            "scorer_script": str(SCORER.resolve()), "scorer_script_sha256": sha256_file(SCORER),
            "adapter_script": str(ADAPTER.resolve()), "adapter_script_sha256": sha256_file(ADAPTER),
            "adapter_dir": str((args.run_dir / f"fold={fold}" / "adapter").resolve()),
            "output_dir": str((args.run_dir / f"fold={fold}" / "score").resolve()),
            "replay_tolerance": args.replay_tolerance,
            "test_opened": False, "test_access_authorized": True,
            **{name: False for name in BLOCKED},
        }
        task_path = tasks / f"{task_id}.json"
        atomic_write_json(task_path, task)
        task_rows.append({
            "stage": "R96", "task_id": task_id, "case_id": task["case_id"],
            "region": "SE_2", "fold": fold,
            "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256_file(task_path),
            "output_dir": task["output_dir"],
            "pipeline_contract_sha256": pipeline_hash,
            "test_access_authorized": True,
            **{name: False for name in BLOCKED},
        })
    manifest = pd.DataFrame(task_rows).sort_values("fold")
    manifest_path = grid / "task_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    atomic_write_json(grid / "launch_control.json", {
        "schema_version": 1, "stage": "R96", "tag": TAG,
        "tasks": 3, "workers": 3, "threads_per_process": 1,
        "one_process_per_cpu": True,
        "task_manifest": str(manifest_path.resolve()),
        "task_manifest_sha256": sha256_file(manifest_path),
        "pipeline_contract": str((grid / "pipeline_contract.json").resolve()),
        "pipeline_contract_sha256": pipeline_hash,
        "test_opened": False, "test_access_authorized": True,
        **{name: False for name in BLOCKED},
    })

    contract = {
        "stage": "R96", "test_role": "one_time_audit_after_frozen_R95",
        "selection_change_authorized": False, "model_refit_authorized": False,
        "comparator_granularity": "SE_2_fold_level_seven_quantile_AQL",
        "promotion_requires": [
            "exact_validation_replay", "complete_finite_seven_quantile_surface",
            "complete_finite_four_horizon_blocks", "candidate_test_AQL_below_authoritative_qdesn",
            "candidate_test_AQL_below_cached_pricefm", "no_test_driven_family_or_specification_change",
        ],
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    atomic_write_json(output / "promotion_contract.json", contract)
    gates = pd.DataFrame([
        {"gate": "R95_frozen_before_test", "passed": True, "observed": sha256_file(surface_path)},
        {"gate": "exact_three_fold_scope", "passed": len(manifest) == 3, "observed": len(manifest)},
        {"gate": "exact_twenty_one_atoms", "passed": len(selected) == 21, "observed": len(selected)},
        {"gate": "one_coherent_exAL_family", "passed": selected.selected_family.eq("exal").all(), "observed": "exal"},
        {"gate": "dual_references_frozen", "passed": len(references) == 3, "observed": len(references)},
        {"gate": "scoring_only_no_refit", "passed": not any(manifest[name].astype(bool).any() for name in BLOCKED), "observed": "blocked"},
        {"gate": "test_scoring_explicitly_authorized", "passed": manifest.test_access_authorized.astype(bool).all(), "observed": "authorized"},
        {"gate": "registry_and_article_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"R96 preparation gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "pricefm_stage_r96_prep_gates.csv", index=False)
    source_records = [
        file_record(Path(__file__), "R96_preparer"), file_record(SCORER, "R96_worker"),
        file_record(LAUNCHER, "R96_launcher"), file_record(CLOSEOUT, "R96_closeout"),
        file_record(ADAPTER, "DESN_adapter"), file_record(surface_path, "R95_frozen_surface"),
        file_record(r95_summary_path, "R95_summary"), file_record(args.r94_frozen, "R94_frozen_family"),
        file_record(args.r93_task, "R93_fold1_task"), file_record(args.authority_registry, "authority_registry"),
        file_record(args.source_data_config, "source_data_config"), file_record(data_config_path, "generated_test_data_config"),
        file_record(selected_path, "frozen_atom_manifest"), file_record(references_path, "frozen_dual_references"),
        file_record(output / "promotion_contract.json", "promotion_contract"),
    ]
    pd.DataFrame(source_records).drop_duplicates("path").to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "r96_scoring_only_test_prepared_not_run",
        "region": "SE_2", "folds": list(FOLDS), "tasks": 3,
        "selected_family": "exal", "selected_atoms": 21,
        "model_refits_authorized": 0, "selection_changes_authorized": 0,
        "pipeline_contract_sha256": pipeline_hash,
        "task_manifest": str(manifest_path.resolve()),
        "quarantined_previous_grid": str(quarantined_grid) if quarantined_grid else None,
        "quarantined_previous_output": str(quarantined_output) if quarantined_output else None,
        "test_opened": False, "test_access_authorized": True,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r96_scoring_only_test_plan.md").write_text(
        "# PriceFM Stage-R96 Scoring-Only Test Audit\n\n"
        "R96 freezes the complete R95 `SE_2` exAL surface before opening test data. "
        "It regenerates the three validation/test designs, requires exact validation replay, "
        "and scores the unchanged 21 posterior-mean readouts against authoritative Q-DESN "
        "and cached PriceFM. It cannot fit, reselect, mutate the registry, or update the article.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
