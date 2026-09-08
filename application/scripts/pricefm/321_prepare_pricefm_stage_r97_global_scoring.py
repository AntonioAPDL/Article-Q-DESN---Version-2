#!/usr/bin/env python3
"""Open test once for the complete validation-frozen R97 region surface."""

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
)


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
SOURCE_DATA = Path(__file__).resolve().parents[2] / "config/pricefm_data_pipeline.yaml"
ADAPTER = Path(__file__).with_name("07_build_desn_direct_horizon_adapter.py")
SCORER = Path(__file__).with_name("320_score_pricefm_stage_r97_frozen_case.py")
BLOCKED = (
    "model_refit_authorized", "selection_change_authorized",
    "registry_mutation_authorized", "article_mutation_authorized",
    "joint_model_authorized", "mcmc_authorized",
)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign-contract", type=Path, required=True)
    value.add_argument("--authority-registry", type=Path, required=True)
    value.add_argument("--region-closeout-root", type=Path, required=True)
    value.add_argument("--source-data-config", type=Path, default=SOURCE_DATA)
    value.add_argument("--processed-dir", type=Path, required=True)
    value.add_argument("--grid-dir", type=Path, required=True)
    value.add_argument("--run-dir", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def write_yaml(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(yaml.safe_dump(payload, sort_keys=False))
    temporary.replace(path)


def test_data(source: dict[str, Any], processed: Path, lag: int, region: str) -> dict[str, Any]:
    payload = copy.deepcopy(source)
    spec = payload["pricefm"]
    for name in ("raw_dir", "interim_dir", "external_repo_dir", "log_dir"):
        path = Path(spec[name])
        if not path.is_absolute():
            spec[name] = str((ARTIFACT_REPO / path).resolve())
    spec["processed_dir"] = str(processed.resolve())
    spec["allow_absolute_local_paths"] = True
    spec["windows"]["lag_window"] = int(lag)
    spec["pilot"] = {"enabled": True, "region": region, "fold": 1}
    if any(set(item) != {"fold", "train", "val", "test"} for item in spec["splits"]):
        raise RuntimeError("R97 scoring requires exact train/validation/test intervals")
    return payload


def smoke_from_full(full_path: Path, data_path: Path, region: str, fold: int, adapter_dir: Path, output_dir: Path) -> dict[str, Any]:
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    return {
        "data_config": str(data_path.resolve()),
        "package_path": full["package_path"],
        "region": region, "fold": fold, "splits": ["val", "test"],
        "horizons": list(range(1, 97)), "quantiles": list(PAPER_QUANTILES),
        "feature_policy": full["scope"]["feature_policy"],
        "adapter": {
            **full["adapter"], "output_dir": str(adapter_dir.resolve()),
            "keep_matrices_after_success": False,
        },
        "run": {**full["run"], "output_dir": str(output_dir.resolve())},
        "artifact_hygiene": full.get("artifact_hygiene", {}),
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    campaign = json.loads(args.campaign_contract.read_text())
    unhashed = {key: value for key, value in campaign.items() if key != "campaign_contract_sha256"}
    if canonical_sha256(unhashed) != campaign.get("campaign_contract_sha256") or campaign.get("case_count") != 114:
        raise RuntimeError("R97 campaign contract hash or surface size changed")
    if sha256_file(args.authority_registry) != campaign["authority_registry"]["sha256"]:
        raise RuntimeError("R97 scoring authority differs from the frozen campaign authority")
    if sha256_file(args.source_data_config) != campaign["source_data_config"]["sha256"]:
        raise RuntimeError("R97 scoring data contract differs from the frozen campaign contract")
    identity = git_identity(args.code_root)
    if not identity.clean or identity.head != identity.upstream_head:
        raise RuntimeError("R97 scoring preparation requires a clean synchronized task branch")
    authority = pd.read_csv(args.authority_registry)
    if len(authority) != 114 or authority.duplicated(["region", "fold"]).any():
        raise RuntimeError("R97 scoring comparator is not the exact 114-case authority")
    source = yaml.safe_load(args.source_data_config.read_text())
    regions_to_fit = list(campaign["regions_to_fit"])
    frozen: dict[str, tuple[dict[str, Any], Path, Path]] = {}
    for region in regions_to_fit:
        closeout = args.region_closeout_root / region
        summary_path = closeout / "summary.json"
        surface_path = closeout / "pricefm_stage_r97_frozen_region_surface.json"
        if not summary_path.is_file() or not surface_path.is_file():
            raise FileNotFoundError(f"R97 region is not validation-frozen: {region}")
        summary = json.loads(summary_path.read_text())
        surface = json.loads(surface_path.read_text())
        if (
            summary.get("status") != "completed_region_validation_surface_frozen"
            or surface.get("region") != region or surface.get("test_opened") is not False
            or surface.get("per_fold_or_quantile_family_mixing") is not False
        ):
            raise RuntimeError(f"R97 region surface is invalid: {region}")
        selected_path = Path(surface["selected_atom_manifest"]["path"])
        if sha256_file(selected_path) != surface["selected_atom_manifest"]["sha256"]:
            raise RuntimeError(f"R97 selected atom manifest changed: {region}")
        selected = pd.read_csv(selected_path)
        if len(selected) != 21 or sorted(selected.fold.unique()) != [1, 2, 3]:
            raise RuntimeError(f"R97 region selected surface is incomplete: {region}")
        frozen[region] = (surface, surface_path, selected_path)

    grid, quarantined_grid = prepare_empty_directory(
        args.grid_dir, quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_global_scoring_grid", allow_quarantine=args.quarantine_existing,
    )
    output, quarantined_output = prepare_empty_directory(
        args.output_dir, quarantine_root=args.quarantine_root or args.output_dir.parent / "quarantine",
        reason="replaced_r97_global_scoring_prep", allow_quarantine=args.quarantine_existing,
    )
    args.run_dir.mkdir(parents=True, exist_ok=True)
    configs = grid / "configs"
    tasks_dir = grid / "tasks"
    configs.mkdir()
    tasks_dir.mkdir()
    task_rows = []
    selected_sources = []
    for region in regions_to_fit:
        surface, surface_path, selected_path = frozen[region]
        selected = pd.read_csv(selected_path)
        lag = int(surface["frozen_desn"]["lag_window"])
        data_path = configs / region / "test_data.yaml"
        write_yaml(data_path, test_data(source, args.processed_dir, lag, region))
        selected_sources.extend([
            file_record(surface_path, f"{region}_frozen_surface"),
            file_record(selected_path, f"{region}_selected_atoms"),
        ])
        reference_rows = authority[authority.region.astype(str).eq(region)].set_index("fold")
        for fold in (1, 2, 3):
            atoms = selected[selected.fold.astype(int).eq(fold)].sort_values("tau")
            if len(atoms) != 7 or not np.allclose(atoms.tau.to_numpy(float), PAPER_QUANTILES):
                raise RuntimeError(f"R97 scoring source is incomplete: {region} fold {fold}")
            source_full = Path(atoms.source_case_config_path.iloc[0])
            adapter_dir = args.run_dir / f"region={region}" / f"fold={fold}" / "adapter"
            score_dir = args.run_dir / f"region={region}" / f"fold={fold}" / "score"
            config_path = configs / region / f"fold_{fold}.yaml"
            write_yaml(config_path, {
                "pricefm_desn_smoke": smoke_from_full(source_full, data_path, region, fold, adapter_dir, score_dir),
                "pricefm_stage_r97": {
                    "stage": "R97", "role": "scoring_only_test", "region": region,
                    "fold": fold, "test_access_authorized": True,
                    **{name: False for name in BLOCKED},
                },
            })
            identity_payload = {"region": region, "fold": fold, "selected_manifest_sha256": sha256_file(selected_path)}
            task_id = content_task_id(f"r97_{region}_f{fold}_score", identity_payload)
            reference = reference_rows.loc[fold]
            task = {
                "schema_version": 1, "stage": "R97", "role": "scoring_only_test",
                "task_id": task_id, "region": region, "fold": fold,
                "selected_family": surface["selected_family"],
                "selected_atom_manifest": str(selected_path.resolve()),
                "selected_atom_manifest_sha256": sha256_file(selected_path),
                "case_config": str(config_path.resolve()), "case_config_sha256": sha256_file(config_path),
                "adapter_script": str(ADAPTER.resolve()), "adapter_script_sha256": sha256_file(ADAPTER),
                "scorer_script": str(SCORER.resolve()), "scorer_script_sha256": sha256_file(SCORER),
                "adapter_dir": str(adapter_dir.resolve()), "output_dir": str(score_dir.resolve()),
                "current_authoritative_qdesn_AQL": float(reference.qdesn_AQL),
                "cached_pricefm_AQL": float(reference.pricefm_AQL),
                "replay_tolerance": 1e-10,
                "test_opened": False, "test_access_authorized": True,
                **{name: False for name in BLOCKED},
            }
            task_path = tasks_dir / f"{task_id}.json"
            atomic_write_json(task_path, task)
            task_rows.append({
                "task_id": task_id, "region": region, "fold": fold,
                "selected_family": surface["selected_family"],
                "task_config": str(task_path.resolve()), "task_config_sha256": sha256_file(task_path),
                "output_dir": str(score_dir.resolve()), "test_access_authorized": True,
                **{name: False for name in BLOCKED},
            })
    manifest = pd.DataFrame(task_rows).sort_values(["region", "fold"])
    if len(manifest) != 111 or manifest.duplicated(["region", "fold"]).any():
        raise RuntimeError("R97 scoring manifest must contain 111 new cases plus frozen SE_2 reuse")
    manifest_path = grid / "task_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    pipeline = {
        "schema_version": 1, "stage": "R97", "role": "complete_surface_scoring_only_test",
        "new_cases": 111, "reused_SE_2_cases": 3, "total_cases": 114,
        "final_aggregation": campaign["final_decision"],
        "campaign_contract": file_record(args.campaign_contract, "campaign_contract"),
        "authority_registry": file_record(args.authority_registry, "R92_authority"),
        "source_data_config": file_record(args.source_data_config, "PriceFM_data_contract"),
        "scorer": file_record(SCORER, "scoring_only_worker"),
        "adapter": file_record(ADAPTER, "DESN_adapter"),
        "git_identity": identity.to_dict(), "test_opened": False,
        "test_access_authorized": True, **{name: False for name in BLOCKED},
    }
    pipeline_hash = canonical_sha256(pipeline)
    pipeline["pipeline_contract_sha256"] = pipeline_hash
    atomic_write_json(grid / "pipeline_contract.json", pipeline)
    source_path = output / "source_manifest.csv"
    pd.DataFrame([
        file_record(args.campaign_contract, "campaign_contract"),
        file_record(args.authority_registry, "R92_authority"),
        file_record(args.source_data_config, "PriceFM_data_contract"),
        *selected_sources,
    ]).to_csv(source_path, index=False)
    summary = {
        "status": "completed_global_scoring_prepared_not_launched", "stage": "R97",
        "new_scoring_tasks": 111, "reused_SE_2_cases": 3, "total_cases": 114,
        "manifest": str(manifest_path), "pipeline_contract_sha256": pipeline_hash,
        "processed_dir": str(args.processed_dir.resolve()),
        "quarantined_previous_grid": str(quarantined_grid) if quarantined_grid else None,
        "quarantined_previous_output": str(quarantined_output) if quarantined_output else None,
        "test_access_authorized": True, "model_refit_authorized": False,
        "registry_mutated": False, "article_mutated": False,
    }
    atomic_write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
