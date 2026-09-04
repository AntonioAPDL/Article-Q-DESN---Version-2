#!/usr/bin/env python3
"""Prepare frozen R89 candidates for a scoring-only, no-refit test audit."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import numpy as np
import pandas as pd
import yaml


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R89 = DATA / "authoritative/pricefm_stage_r89_validation_family_selection_20260905"
R68 = DATA / "authoritative/pricefm_stage_r68_authority_reconciliation_20260831"
TAG = "pricefm_stage_r90_scoring_only_test_audit_20260905"
GRID = DATA / "experiment_grids" / TAG
RUNS = DATA / "runs" / TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r90_scoring_only_test_prep_20260905"
SCORER = Path(__file__).resolve().with_name(
    "285_run_pricefm_stage_r90_scoring_only_case.py"
)
ADAPTER = Path(__file__).resolve().with_name("pricefm_desn_adapter.py")
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r89-dir", type=Path, default=R89)
    p.add_argument("--r68-dir", type=Path, default=R68)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--run-dir", type=Path, default=RUNS)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--replay-tolerance", type=float, default=1e-10)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict[str, Any]:
    r89_summary_path = args.r89_dir / "summary.json"
    r89_summary = json.loads(r89_summary_path.read_text())
    selected_path = args.r89_dir / "pricefm_stage_r89_selected_atom_manifest.csv"
    selected = pd.read_csv(selected_path)
    authority_path = args.r68_dir / "pricefm_stage_r68_refit_target_queue.csv"
    authority = pd.read_csv(authority_path)
    if (
        r89_summary.get("r90_scoring_only_test_prep_authorized") is not True
        or r89_summary.get("test_opened") is not False
        or len(selected) != 392 or selected.case_id.nunique() != 56
    ):
        raise RuntimeError("R89 is not a complete pre-test frozen selection")
    if len(authority) != 56 or set(authority.case_id) != set(selected.case_id):
        raise RuntimeError("R68 dual-reference authority does not match the R89 cases")
    if args.replay_tolerance != 1e-10:
        raise RuntimeError("R90 registered thresholds cannot be changed")
    case_references = authority[[
        "case_id", "region", "fold", "qdesn_method_id", "pricefm_method_id",
        "cached_registry_qdesn_test_AQL", "cached_registry_pricefm_test_AQL",
    ]].rename(columns={
        "qdesn_method_id": "authoritative_qdesn_method_id",
        "pricefm_method_id": "cached_pricefm_method_id",
        "cached_registry_qdesn_test_AQL": "authoritative_qdesn_test_AQL",
        "cached_registry_pricefm_test_AQL": "cached_pricefm_test_AQL",
    }).sort_values(["region", "fold"])
    if not np.isfinite(case_references[[
        "authoritative_qdesn_test_AQL", "cached_pricefm_test_AQL",
    ]]).all().all():
        raise RuntimeError("R90 case-level dual references are not finite")

    grid = args.grid_dir.resolve(); output = args.output_dir.resolve()
    for path in (grid, output):
        if path.exists() and any(path.iterdir()):
            if not args.force:
                raise FileExistsError(path)
            shutil.rmtree(path)
        path.mkdir(parents=True)
    configs = grid / "configs"; tasks = grid / "tasks"
    configs.mkdir(); tasks.mkdir(); args.run_dir.mkdir(parents=True, exist_ok=True)
    manifest_rows = []
    selected_by_case = selected.groupby("case_id", sort=True)
    for case_id, atoms in selected_by_case:
        if len(atoms) != 7:
            raise RuntimeError(f"Incomplete R89 case: {case_id}")
        first = atoms.iloc[0]
        source_config = Path(first.source_case_config)
        if sha256(source_config) != first.source_case_config_sha256:
            raise RuntimeError(f"Changed frozen case config: {source_config}")
        payload = yaml.safe_load(source_config.read_text())
        smoke = payload["pricefm_desn_smoke"]
        if smoke.get("splits") != ["train", "val"]:
            raise RuntimeError(f"Unexpected source split contract: {source_config}")
        adapter_dir = args.run_dir.resolve() / case_id / "adapter"
        score_dir = args.run_dir.resolve() / case_id / "score"
        smoke["splits"] = ["val", "test"]
        smoke["adapter"]["output_dir"] = str(adapter_dir)
        smoke["run"]["output_dir"] = str(score_dir)
        payload["pricefm_stage_r90"] = {
            "stage": "R90", "case_id": case_id,
            "role": "scoring_only_test_audit_after_frozen_r89",
            "model_refit_authorized": False, "selection_change_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "joint_model_authorized": False, "mcmc_authorized": False,
        }
        config_path = configs / f"{case_id}.yaml"
        config_path.write_text(yaml.safe_dump(payload, sort_keys=False))
        task = {
            "stage": "R90", "task_id": f"{case_id}__r90_scoring_only",
            "case_id": case_id, "region": first.region, "fold": int(first.fold),
            "config": str(config_path.resolve()), "config_sha256": sha256(config_path),
            "selected_manifest": str(selected_path.resolve()),
            "selected_manifest_sha256": sha256(selected_path),
            "scorer_script": str(SCORER), "scorer_script_sha256": sha256(SCORER),
            "adapter_script": str(ADAPTER), "adapter_script_sha256": sha256(ADAPTER),
            "adapter_dir": str(adapter_dir), "output_dir": str(score_dir),
            "replay_tolerance": args.replay_tolerance,
            "model_refit_authorized": False, "selection_change_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
            "joint_model_authorized": False, "mcmc_authorized": False,
            "test_access_authorized": True,
        }
        task_path = tasks / f"{task['task_id']}.json"
        task_path.write_text(json.dumps(task, indent=2, sort_keys=True) + "\n")
        manifest_rows.append({
            **task, "task_config": str(task_path.resolve()),
            "task_config_sha256": sha256(task_path),
        })
    manifest = pd.DataFrame(manifest_rows).sort_values(["region", "fold"])
    manifest.to_csv(grid / "task_manifest.csv", index=False)
    case_references.to_csv(output / "pricefm_stage_r90_frozen_case_references.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "r89_selection_frozen_before_test", "passed": True, "observed": 392},
        {"gate": "exact_56_case_scoring_scope", "passed": len(manifest) == 56, "observed": len(manifest)},
        {"gate": "seven_quantiles_per_case", "passed": selected.groupby("case_id").tau.nunique().eq(7).all(), "observed": 7},
        {"gate": "dual_case_references_frozen", "passed": len(case_references) == 56, "observed": len(case_references)},
        {"gate": "no_unsupported_granular_reference_inference", "passed": True, "observed": "case-level references only"},
        {"gate": "validation_replay_tolerance_frozen", "passed": args.replay_tolerance == 1e-10, "observed": args.replay_tolerance},
        {"gate": "scoring_only_no_refit", "passed": not manifest.model_refit_authorized.astype(bool).any(), "observed": "blocked"},
        {"gate": "registry_article_joint_mcmc_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.all():
        raise RuntimeError("R90 preparation gates failed")
    gates.to_csv(output / "pricefm_stage_r90_prep_gates.csv", index=False)
    contract = {
        "validation_replay_absolute_tolerance": args.replay_tolerance,
        "promotion_requires": [
            "validation_replay_pass", "candidate_test_AQL_below_authoritative_qdesn",
            "candidate_test_AQL_below_cached_pricefm",
            "finite_complete_seven_quantile_predictions",
            "finite_complete_four_horizon_block_diagnostics",
        ],
        "comparator_granularity": "case_level_seven_quantile_AQL_only",
        "granular_metrics_role": "candidate_diagnostics_only_not_comparator_gates",
        "granular_reference_limitation": (
            "legacy authority does not preserve a universal per-quantile/per-horizon "
            "surface for the selected seven-quantile QDESN and PriceFM references"
        ),
        "test_role": "one_time_audit_after_frozen_r89",
        "model_refit_authorized": False,
    }
    (output / "promotion_contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
    fixed = [Path(__file__).resolve(), SCORER, ADAPTER, r89_summary_path, selected_path, authority_path,
             output / "pricefm_stage_r90_frozen_case_references.csv",
             output / "promotion_contract.json", grid / "task_manifest.csv"]
    pd.DataFrame([
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in fixed
    ]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "scoring_only_test_audit_prepared_not_run",
        "cases": 56, "selected_atoms": 392, "test_adapters_materialized": 0,
        "model_refits_authorized": 0,
        "replay_tolerance": args.replay_tolerance,
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "joint_or_mcmc_authorized": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
