#!/usr/bin/env python3
"""Prepare the dependency graph for all-fold fitting of a frozen PriceFM family."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_region_frozen_contract import (
    PAPER_QUANTILES,
    atomic_write_json,
    canonical_sha256,
    content_task_id,
    file_record,
    prepare_empty_directory,
    sha256_file,
    validate_pretest_firewall,
    validate_quantiles,
    verify_file_record,
)


WARM_PARENT = {
    0.50: "normal_rhs",
    0.45: "al_0.50",
    0.25: "al_0.45",
    0.10: "al_0.25",
    0.55: "al_0.50",
    0.75: "al_0.55",
    0.90: "al_0.75",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--region-contract", type=Path, required=True)
    value.add_argument("--frozen-family", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, required=True)
    value.add_argument("--run-root", type=Path, required=True)
    value.add_argument("--quarantine-root", type=Path, default=None)
    value.add_argument("--quarantine-existing", action="store_true")
    return value


def task_row(
    pipeline_hash: str,
    region: str,
    fold: int,
    action: str,
    family: str,
    tau: float | None,
    parents: list[str],
    output: Path,
) -> dict[str, Any]:
    identity = {
        "pipeline_contract_sha256": pipeline_hash,
        "region": region, "fold": fold, "action": action,
        "family": family, "tau": tau,
    }
    token = content_task_id(
        f"{region}_f{fold}_{action}_{family}_{tau if tau is not None else 'na'}",
        identity,
    )
    return {
        "task_id": token,
        "region": region,
        "fold": fold,
        "action": action,
        "likelihood_family": family,
        "tau": tau,
        "parent_labels": parents,
        "output_dir": str(output / token),
        "selection_split": "val",
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    region_path = args.region_contract.resolve()
    family_path = args.frozen_family.resolve()
    region_contract = json.loads(region_path.read_text())
    frozen = json.loads(family_path.read_text())
    validate_pretest_firewall(region_contract, label="region contract")
    validate_pretest_firewall(frozen, label="frozen family")
    validate_quantiles(region_contract.get("quantiles", ()), label="region contract quantiles")
    validate_quantiles(frozen.get("quantiles", ()), label="frozen family quantiles")
    if region_contract.get("target_region") != frozen.get("region"):
        raise RuntimeError("region contract and frozen family identify different regions")
    if frozen.get("selected_family") not in {"al", "exal"}:
        raise RuntimeError("frozen family must be AL or exAL")
    if frozen.get("per_quantile_family_mixing") is not False:
        raise RuntimeError("all-fold preparation rejects mixed quantile families")
    if len(frozen.get("selected_atoms") or []) != 7:
        raise RuntimeError("frozen family does not contain seven selected atoms")
    for atom in frozen["selected_atoms"]:
        for role in ("beta", "prediction", "terminal"):
            verify_file_record(atom[role], label=f"frozen {role}")
    folds = [int(value) for value in region_contract["real_folds"]]
    selection_fold = int(region_contract["selection_fold"])
    if folds != [1, 2, 3] or selection_fold != int(frozen["selection_fold"]):
        raise RuntimeError("fold contract mismatch")

    output, quarantined = prepare_empty_directory(
        args.output_dir,
        quarantine_root=args.quarantine_root or (args.output_dir.parent / "quarantine"),
        reason="replaced_allfold_prep",
        allow_quarantine=args.quarantine_existing,
    )
    region = str(frozen["region"])
    family = str(frozen["selected_family"])
    pipeline = {
        "schema_version": 1,
        "stage": "region_frozen_allfold_pretest",
        "region": region,
        "selection_fold": selection_fold,
        "real_folds": folds,
        "selected_family": family,
        "quantiles": list(PAPER_QUANTILES),
        "frozen_desn": frozen["frozen_desn"],
        "rhs_tau0": float(frozen["rhs_tau0"]),
        "region_contract": file_record(region_path, "region_contract"),
        "frozen_family": file_record(family_path, "validation_family_contract"),
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
    }
    pipeline_hash = canonical_sha256(pipeline)
    pipeline["pipeline_contract_sha256"] = pipeline_hash

    rows: list[dict[str, Any]] = []
    for atom in frozen["selected_atoms"]:
        tau = float(atom["tau"])
        row = task_row(
            pipeline_hash, region, selection_fold, "reuse_frozen_atom", family,
            tau, [], args.run_root.resolve(),
        )
        row["execution_required"] = False
        row["source_beta_path"] = atom["beta"]["path"]
        row["source_beta_sha256"] = atom["beta"]["sha256"]
        row["source_prediction_path"] = atom["prediction"]["path"]
        row["source_prediction_sha256"] = atom["prediction"]["sha256"]
        rows.append(row)

    missing_folds = [fold for fold in folds if fold != selection_fold]
    for fold in missing_folds:
        normal = task_row(
            pipeline_hash, region, fold, "fit", "normal_rhs", None, [],
            args.run_root.resolve(),
        )
        normal["execution_required"] = True
        normal["task_label"] = f"f{fold}_normal_rhs"
        rows.append(normal)
        labels: dict[str, str] = {"normal_rhs": normal["task_id"]}
        for tau in (0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90):
            parent_label = WARM_PARENT[tau]
            parent_id = labels[parent_label]
            al = task_row(
                pipeline_hash, region, fold, "fit", "al", tau, [parent_id],
                args.run_root.resolve(),
            )
            al["execution_required"] = True
            al["task_label"] = f"f{fold}_al_{tau:.2f}"
            al["scientific_role"] = "candidate" if family == "al" else "required_warm_start"
            rows.append(al)
            labels[f"al_{tau:.2f}"] = al["task_id"]
            if family == "exal":
                exal = task_row(
                    pipeline_hash, region, fold, "fit", "exal", tau,
                    [al["task_id"]], args.run_root.resolve(),
                )
                exal["execution_required"] = True
                exal["task_label"] = f"f{fold}_exal_{tau:.2f}"
                exal["scientific_role"] = "candidate"
                rows.append(exal)

    manifest = pd.DataFrame(rows)
    expected_new = 16 if family == "al" else 30
    observed_new = int(manifest.execution_required.sum())
    if observed_new != expected_new:
        raise RuntimeError(f"all-fold fit count mismatch: {observed_new} != {expected_new}")
    if manifest.test_access_authorized.any() or manifest.test_opened.any():
        raise RuntimeError("all-fold preparation violated the test firewall")
    task_dir = output / "tasks"
    task_dir.mkdir()
    task_paths = []
    for row in manifest.to_dict("records"):
        task = {
            **row,
            "stage": "region_frozen_allfold_pretest",
            "pipeline_contract_sha256": pipeline_hash,
            "frozen_desn": frozen["frozen_desn"],
            "rhs_tau0": float(frozen["rhs_tau0"]),
            "quantiles": list(PAPER_QUANTILES),
            "launch_authorized": False,
        }
        path = task_dir / f"{row['task_id']}.json"
        atomic_write_json(path, task)
        task_paths.append(str(path))
    manifest["task_config"] = task_paths
    manifest["task_config_sha256"] = [sha256_file(path) for path in task_paths]
    manifest.to_csv(output / "task_manifest.csv", index=False)
    atomic_write_json(output / "pipeline_contract.json", pipeline)
    gates = pd.DataFrame([
        {"gate": "one_region", "passed": manifest.region.nunique() == 1, "observed": region},
        {"gate": "whole_family", "passed": family in {"al", "exal"}, "observed": family},
        {"gate": "fold1_reuse", "passed": int((~manifest.execution_required).sum()) == 7, "observed": int((~manifest.execution_required).sum())},
        {"gate": "exact_new_fit_count", "passed": observed_new == expected_new, "observed": observed_new},
        {"gate": "test_sealed", "passed": not manifest.test_opened.any() and not manifest.test_access_authorized.any(), "observed": "sealed"},
        {"gate": "no_launch_yaml", "passed": not list(output.rglob("*.yaml")), "observed": "none"},
        {"gate": "launch_blocked", "passed": True, "observed": "requires_separate_controller_authorization"},
    ])
    if not gates.passed.all():
        raise RuntimeError(f"all-fold prep gates failed: {gates.loc[~gates.passed].to_dict('records')}")
    gates.to_csv(output / "allfold_prep_gates.csv", index=False)
    summary = {
        "status": "allfold_pretest_dependency_graph_prepared_not_launched",
        "region": region,
        "selected_family": family,
        "fold1_atoms_reused": 7,
        "missing_folds": missing_folds,
        "new_fits": expected_new,
        "normal_rhs_fits": len(missing_folds),
        "al_fits": 7 * len(missing_folds),
        "exal_fits": 7 * len(missing_folds) if family == "exal" else 0,
        "pipeline_contract_sha256": pipeline_hash,
        "quarantined_previous_output": str(quarantined) if quarantined else None,
        "test_opened": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    atomic_write_json(output / "summary.json", summary)
    (output / "allfold_pretest_plan.md").write_text(
        f"# PriceFM All-Fold Pre-Test Plan: {region}\n\n"
        f"Fold-{selection_fold} reuses seven frozen `{family}` atoms. Folds "
        f"{missing_folds} require `{expected_new}` new train/validation-only fits under "
        "the identical region-level DESN and tau0 contract. The dependency graph permits "
        "parallel left/right AL branches and same-tau exAL children. Test remains sealed.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
