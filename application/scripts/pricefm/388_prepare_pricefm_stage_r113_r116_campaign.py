#!/usr/bin/env python3
"""Prepare the gated BG R113--R116 recursive-mechanism campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r113_r116_rolled_state_driver_20260922"
CAMPAIGN = DATA / "campaigns" / TAG
R103 = DATA / "launch_prep/pricefm_stage_r103_recursive_quantile_20260916"
R111B = DATA / "campaigns/pricefm_stage_r111b_bg_exposure_readout_20260922"
R100_CANDIDATES = (
    DATA
    / "launch_prep/pricefm_stage_r100_targeted_normal_recovery_20260913"
    / "regions/BG/ridge_prep/pricefm_stage_r100_ridge_candidate_manifest.csv"
)
R97 = DATA / "campaigns/pricefm_stage_r97_global_region_frozen_campaign_20260908"
R102_CONFIGS = DATA / "campaigns/pricefm_stage_r102_recursive_normal_20260916/configs"
R110_BG_ADAPTER = DATA / "campaigns/pricefm_stage_r110_direct_driver_20260921/adapters/region=BG/fold=1"
CRAN_LIBRARY = DATA / "runtime_libraries/exdqlm_cran_1p1p1"
CRAN_MANIFEST = CRAN_LIBRARY / "pricefm_r67_cran111_install_manifest.json"
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
FAMILIES = ("al", "exal")
INNER_FOLDS = (1, 2, 3)


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def nested_temporal_splits(rows: pd.DataFrame) -> tuple[list[dict[str, np.ndarray]], pd.DataFrame]:
    """Reproduce the three expanding training-only folds used by R111B."""

    required = {"origin_id", "horizon", "origin_market_time", "response_market_time"}
    if not required.issubset(rows):
        raise ValueError(f"missing nested-fold columns: {sorted(required - set(rows))}")
    work = rows.copy()
    work["origin_market_time"] = pd.to_datetime(work.origin_market_time, utc=True)
    work["response_market_time"] = pd.to_datetime(work.response_market_time, utc=True)
    origins = (
        work[["origin_id", "origin_market_time"]]
        .drop_duplicates()
        .sort_values(["origin_market_time", "origin_id"], kind="mergesort")
        .reset_index(drop=True)
    )
    if origins.origin_id.duplicated().any():
        raise ValueError("each origin must map to one time")
    n_origins = len(origins)
    validation_count = max(30, int(np.floor(n_origins * 0.15)))
    first_train_end = max(120, int(np.floor(n_origins * 0.55)))
    last_train_end = n_origins - validation_count
    train_ends = np.unique(np.rint(np.linspace(first_train_end, last_train_end, 3)).astype(int))
    if len(train_ends) != 3:
        raise ValueError("nested split boundaries are not unique")
    n_design_origins = int(work.origin_id.max()) + 1
    if set(work.origin_id.unique()) != set(range(n_design_origins)):
        raise ValueError("R113 requires contiguous zero-based training origin IDs")
    splits: list[dict[str, np.ndarray]] = []
    summaries = []
    for inner_fold, train_end in enumerate(train_ends, start=1):
        validation_origins = origins.iloc[train_end : train_end + validation_count]
        validation_start = validation_origins.origin_market_time.iloc[0]
        train_origins = set(origins.iloc[:train_end].origin_id.astype(int))
        validation_ids = set(validation_origins.origin_id.astype(int))
        train_rows = work.origin_id.astype(int).isin(train_origins) & (
            work.response_market_time < validation_start
        )
        validation_rows = work.origin_id.astype(int).isin(validation_ids)
        if not train_rows.any() or not validation_rows.any():
            raise ValueError("nested temporal split is empty")
        if work.loc[train_rows, "response_market_time"].max() >= work.loc[
            validation_rows, "origin_market_time"
        ].min():
            raise ValueError("nested temporal split violates the response-time embargo")
        def design_indices(mask: pd.Series) -> np.ndarray:
            subset = work.loc[mask, ["origin_id", "horizon"]]
            return (
                (subset.horizon.to_numpy(dtype=np.int64) - 1) * n_design_origins
                + subset.origin_id.to_numpy(dtype=np.int64)
            )
        splits.append({
            "train_index": design_indices(train_rows),
            "validation_index": design_indices(validation_rows),
            "train_origin_id": np.asarray(sorted(train_origins), dtype=np.int64),
            "validation_origin_id": np.asarray(sorted(validation_ids), dtype=np.int64),
        })
        summaries.append({
            "inner_fold": inner_fold,
            "n_train_origins": len(train_origins),
            "n_validation_origins": len(validation_ids),
            "n_train_rows": int(train_rows.sum()),
            "n_validation_rows": int(validation_rows.sum()),
            "train_response_end": work.loc[train_rows, "response_market_time"].max().isoformat(),
            "validation_origin_start": validation_start.isoformat(),
            "embargo_passed": True,
        })
    return splits, pd.DataFrame(summaries)


def _artifact(role: str, path: Path) -> dict[str, Any]:
    path = path.resolve()
    return {"role": role, "path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def prepare(code_root: Path, output_root: Path, force: bool = False) -> dict[str, Any]:
    code_root = code_root.resolve()
    output_root = output_root.resolve()
    if output_root.exists() and any(output_root.iterdir()):
        if not force:
            summary = output_root / "summary.json"
            if summary.is_file():
                value = json.loads(summary.read_text())
                if value.get("status") == "prepared_training_only_not_launched":
                    return value
            raise FileExistsError(output_root)
        shutil.rmtree(output_root)
    output_root.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_root.name + ".tmp.", dir=output_root.parent))
    try:
        cran = json.loads(CRAN_MANIFEST.read_text())
        if (
            cran.get("status") != "installed_exact_cran_exdqlm_1.1.1"
            or cran.get("installed_package", {}).get("version") != "1.1.1"
            or cran.get("installed_package", {}).get("repository") != "CRAN"
        ):
            raise RuntimeError("exact CRAN exdqlm 1.1.1 runtime contract is invalid")
        r111b = json.loads((R111B / "summary.json").read_text())
        if r111b.get("status") != "completed_bg_exposure_readout_closeout":
            raise RuntimeError("R111B frozen control is incomplete")
        case_path = R103 / "cases/r103_bg_f1.json"
        case = json.loads(case_path.read_text())
        design_meta = json.loads((Path(case["design_dir"]) / "design.json").read_text())
        design_terminal = json.loads((Path(case["design_dir"]) / "terminal.json").read_text())
        if (
            design_terminal.get("status") != "completed_causal_quantile_design"
            or design_terminal.get("test_opened") is not False
        ):
            raise RuntimeError("frozen BG causal design is invalid")
        rows = pd.read_csv(R110_BG_ADAPTER / "rows_train.csv")
        splits, split_summary = nested_temporal_splits(rows)
        n_origins = int(rows.origin_id.max()) + 1
        design_y = np.fromfile(Path(case["design_dir"]) / "y.bin", dtype="<f8")
        row_y = np.empty_like(design_y)
        for row in rows.itertuples(index=False):
            row_y[(int(row.horizon) - 1) * n_origins + int(row.origin_id)] = float(row.y_scaled)
        if not np.allclose(design_y, row_y, rtol=0, atol=1e-12):
            raise RuntimeError("R103 design order does not match the nested-fold rows")

        split_dir = temporary / "splits"
        split_dir.mkdir(parents=True)
        split_records = []
        for inner_fold, values in zip(INNER_FOLDS, splits):
            path = split_dir / f"inner_fold_{inner_fold}.npz"
            np.savez_compressed(path, **values)
            csv_path = split_dir / f"inner_fold_{inner_fold}.csv"
            pd.DataFrame({
                "split": np.repeat(
                    ["train", "validation"],
                    [len(values["train_index"]), len(values["validation_index"])],
                ),
                "design_index_zero_based": np.concatenate([
                    values["train_index"], values["validation_index"]
                ]),
            }).to_csv(csv_path, index=False)
            split_records.append({
                "inner_fold": inner_fold,
                "path": str((output_root / "splits" / path.name).resolve()),
                "sha256": sha256_file(path),
                "csv_path": str((output_root / "splits" / csv_path.name).resolve()),
                "csv_sha256": sha256_file(csv_path),
                **split_summary.loc[split_summary.inner_fold.eq(inner_fold)].iloc[0].to_dict(),
            })
        split_summary.to_csv(temporary / "nested_split_summary.csv", index=False)

        candidates = pd.read_csv(R100_CANDIDATES)
        if len(candidates) != 240 or candidates.candidate_id.duplicated().any():
            raise RuntimeError("frozen BG candidate bank is not the expected 240-row bank")
        candidate_path = temporary / "r115_candidate_bank.csv"
        candidates.to_csv(candidate_path, index=False)

        fit_rows = []
        contracts = temporary / "contracts/r114_fit"
        contracts.mkdir(parents=True)
        for family in FAMILIES:
            for inner_fold in INNER_FOLDS:
                task_id = f"r114__{family}__inner{inner_fold}"
                value = {
                    "stage": "R114",
                    "phase": "training_only_driver_fit",
                    "task_id": task_id,
                    "family": family,
                    "inner_fold": inner_fold,
                    "quantiles": list(QUANTILES),
                    "design_dir": case["design_dir"],
                    "split_path": str((output_root / "splits" / f"inner_fold_{inner_fold}.npz").resolve()),
                    "split_sha256": split_records[inner_fold - 1]["sha256"],
                    "split_csv_path": split_records[inner_fold - 1]["csv_path"],
                    "split_csv_sha256": split_records[inner_fold - 1]["csv_sha256"],
                    "al_initializer_dir": None if family == "al" else str(
                        (output_root / "runs/r114_fit" / f"family=al/inner={inner_fold}").resolve()
                    ),
                    "output_dir": str(
                        (output_root / "runs/r114_fit" / f"family={family}/inner={inner_fold}").resolve()
                    ),
                    "runtime_library": str(CRAN_LIBRARY.resolve()),
                    "runtime_manifest": str(CRAN_MANIFEST.resolve()),
                    "runtime_manifest_sha256": sha256_file(CRAN_MANIFEST),
                    "adapter_path": str(
                        (code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R").resolve()
                    ),
                    "rhs": {"tau0": 1e-4, "shrink_intercept": False, "freeze_tau_iters": 50, "freeze_tau_warmup_iters": 50},
                    "vb": {
                        "max_iter": 500, "tol": 1e-4, "n_samp": 200, "n_samp_xi": 200,
                        "prior_sigma": {"a": 1, "b": 1},
                        "prior_gamma": {"mu0": 0, "s20": 10},
                        "structured_sigmagam": {
                            "factorization": "structured", "structured_grid_size": 151,
                            "structured_span_sd": 6, "freeze_warmup_iters": 0,
                            "force_after_warmup": True, "postwarmup_damping": 0.2,
                            "postwarmup_damping_iters": 30, "min_postwarmup_updates": 35,
                        },
                    },
                    "seed": 2026092200 + 100 * FAMILIES.index(family) + inner_fold,
                    "selection_split": "BG_fold1_training_nested_temporal_only",
                    "test_access_authorized": False,
                    "registry_mutation_authorized": False,
                    "article_mutation_authorized": False,
                    "mcmc_authorized": False,
                    "joint_model_authorized": False,
                }
                value["task_contract_sha256"] = canonical_hash(value)
                path = contracts / f"{task_id}.json"
                write_json(path, value)
                fit_rows.append({
                    "task_id": task_id,
                    "family": family,
                    "inner_fold": inner_fold,
                    "contract_path": str((output_root / "contracts/r114_fit" / path.name).resolve()),
                    "contract_sha256": sha256_file(path),
                    "output_dir": value["output_dir"],
                    "fit_cells": 7,
                })
        pd.DataFrame(fit_rows).to_csv(temporary / "r114_fit_manifest.csv", index=False)

        normal_rows = []
        normal_contracts = temporary / "contracts/r114_normal_driver"
        normal_contracts.mkdir(parents=True)
        for region in ("BG", "GR", "RO"):
            adapter_dir = (
                R110_BG_ADAPTER
                if region == "BG"
                else R97 / f"regions/{region}/surface_runs/normal/cells/region={region}/fold=1/adapter"
            )
            for inner_fold in INNER_FOLDS:
                task_id = f"r114_normal__{region}__inner{inner_fold}"
                value = {
                    "stage": "R114", "phase": "training_only_normal_driver",
                    "task_id": task_id, "region": region, "inner_fold": inner_fold,
                    "adapter_dir": str(adapter_dir.resolve()),
                    "output_dir": str((output_root / "runs/r114_normal_driver" / f"region={region}/inner={inner_fold}").resolve()),
                    "readout": "block24", "prior_type": "rhs_ns", "tau0": 2.5e-5,
                    "max_iter": 1500, "min_iter": 50, "tol": 1e-5,
                    "n_paths": 500, "seed": 2026092250 + 10 * ("BG", "GR", "RO").index(region) + inner_fold,
                    "selection_split": "BG_fold1_training_nested_temporal_only",
                    "helper_path": str((code_root / "application/R/pricefm_recursive_normal_fit.R").resolve()),
                    "horizon_helper_path": str((code_root / "application/scripts/pricefm/pricefm_horizon_readout.R").resolve()),
                    "package_path": str((DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm").resolve()),
                    "test_access_authorized": False,
                    "registry_mutation_authorized": False,
                    "article_mutation_authorized": False,
                }
                value["task_contract_sha256"] = canonical_hash(value)
                path = normal_contracts / f"{task_id}.json"
                write_json(path, value)
                normal_rows.append({
                    "task_id": task_id, "region": region, "inner_fold": inner_fold,
                    "contract_path": str((output_root / "contracts/r114_normal_driver" / path.name).resolve()),
                    "contract_sha256": sha256_file(path), "output_dir": value["output_dir"],
                })
        pd.DataFrame(normal_rows).to_csv(temporary / "r114_normal_driver_manifest.csv", index=False)

        normal_package = DATA / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
        source_paths = [
            code_root / "application/scripts/pricefm/388_prepare_pricefm_stage_r113_r116_campaign.py",
            code_root / "application/scripts/pricefm/389_run_pricefm_stage_r114_quantile_fit.R",
            code_root / "application/scripts/pricefm/390_run_pricefm_stage_r114_normal_driver.R",
            code_root / "application/scripts/pricefm/391_run_pricefm_stage_r113_r116_campaign.py",
            code_root / "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py",
            code_root / "application/scripts/pricefm/393_run_pricefm_stage_r115_rhs_cell.R",
            code_root / "application/scripts/pricefm/pricefm_recursive_readout.py",
            code_root / "application/scripts/pricefm/pricefm_recursive_normal.py",
            code_root / "application/scripts/pricefm/pricefm_recursive_quantile.py",
            code_root / "application/scripts/pricefm/pricefm_recursive_quantile_marginal.py",
            code_root / "application/scripts/pricefm/pricefm_recursive_driver_diagnostics.py",
            code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
            code_root / "application/scripts/pricefm/pricefm_horizon_readout.R",
            code_root / "application/R/pricefm_recursive_normal_fit.R",
            CRAN_MANIFEST,
            case_path,
            R111B / "summary.json",
            R100_CANDIDATES,
        ]
        source_paths.extend(
            Path(case["design_dir"]) / name
            for name in ("X.bin", "y.bin", "design.json", "terminal.json")
        )
        source_paths.extend(R102_CONFIGS / f"data_L{lag}.yaml" for lag in (48, 96, 168, 240))
        for region in ("BG", "GR", "RO"):
            adapter_dir = (
                R110_BG_ADAPTER
                if region == "BG"
                else R97 / f"regions/{region}/surface_runs/normal/cells/region={region}/fold=1/adapter"
            )
            source_paths.extend(
                adapter_dir / name
                for name in (
                    "X_train.csv", "y_train.csv", "rows_train.csv",
                    "adapter_manifest.json", "feature_manifest.json", "feature_map_matrix.npz",
                )
            )
        processed = R97 / "processed_scoring"
        for fold in (1, 2, 3):
            source_paths.extend([
                processed / f"scalers/fold_{fold}/per_region_separate_xy_scalers.joblib",
                processed / f"scalers/fold_{fold}/scaling_manifest.json",
            ])
            for region in ("BG", "GR", "RO"):
                window_dir = processed / f"windows/fold_{fold}/region={region}"
                for lag in (48, 96, 168, 240):
                    for stem in (
                        f"train_L{lag}_H96_contained_half_open",
                        f"val_L{lag}_H96_operational_half_open",
                    ):
                        source_paths.extend([window_dir / f"{stem}.npz", window_dir / f"{stem}.manifest.json"])
        source_paths.extend(sorted((normal_package / "R").glob("*.R")))
        source_paths.extend(normal_package / name for name in ("DESCRIPTION", "NAMESPACE"))
        source_paths.extend(R103 / f"cases/r103_bg_f{fold}.json" for fold in (1, 2, 3))
        source_paths.extend(R103 / f"cases/r103_{region}_f{fold}.json" for region in ("gr", "ro") for fold in (1, 2, 3))
        source_paths.extend([
            R111B / "pricefm_stage_r111b_bg_case_metrics.csv",
            R111B / "pricefm_stage_r111b_bg_references.csv",
        ])
        source_manifest = pd.DataFrame([
            _artifact("source_or_frozen_evidence", path) for path in source_paths
        ])
        source_manifest.to_csv(temporary / "source_manifest.csv", index=False)
        contract = {
            "stage": "R113_R116",
            "tag": TAG,
            "status": "prepared_training_only_not_launched",
            "code_root": str(code_root),
            "branch": git_value(code_root, "branch", "--show-current"),
            "head": git_value(code_root, "rev-parse", "HEAD"),
            "upstream": git_value(code_root, "rev-parse", "@{upstream}"),
            "region": "BG",
            "outer_selection_fold": 1,
            "inner_folds": list(INNER_FOLDS),
            "families": list(FAMILIES),
            "quantiles": list(QUANTILES),
            "posterior_paths": 500,
            "rank_policies": ["independent_stratified", "training_block_rank_6", "training_block_rank_12", "training_block_rank_24"],
            "readout_modes": ["state_lead_horizon", "state_horizon", "state_only"],
            "r114_fit_tasks": 6,
            "r114_fit_cells": 42,
            "r114_normal_driver_tasks": 9,
            "r115_ridge_candidates": 240,
            "r115_ridge_fit_cells": 1440,
            "r115_rhs_maximum_fit_cells": 540,
            "r116_family_maximum_fit_cells": 42,
            "r116_factorial_maximum_fit_cells": 84,
            "max_workers": 30,
            "selection_split": "BG_fold1_training_nested_temporal_only",
            "outer_validation_role": "transfer_diagnostic_only",
            "package_contract": "exact_CRAN_exdqlm_1.1.1_public_API_for_AL_exAL",
            "normal_package_contract": "project_Normal_RHS_source_only_for_Normal_driver_and_R115_pruning",
            "source_manifest_sha256": sha256_file(temporary / "source_manifest.csv"),
            "candidate_bank_sha256": sha256_file(candidate_path),
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "mcmc_authorized": False,
            "joint_model_authorized": False,
            "broad_all_region_authorized": False,
        }
        contract["campaign_contract_sha256"] = canonical_hash(contract)
        write_json(temporary / "campaign_contract.json", contract)
        summary = {
            **contract,
            "output_root": str(output_root),
            "nested_split_count": 3,
            "candidate_count": 240,
            "next_action": "jerez_preflight_then_dependency_ordered_background_controller",
        }
        write_json(temporary / "summary.json", summary)
        if output_root.exists():
            shutil.rmtree(output_root)
        temporary.rename(output_root)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-root", type=Path, default=CAMPAIGN)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(args.code_root, args.output_root, args.force), indent=2))


if __name__ == "__main__":
    main()
