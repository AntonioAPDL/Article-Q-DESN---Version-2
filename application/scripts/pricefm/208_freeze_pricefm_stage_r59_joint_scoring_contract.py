#!/usr/bin/env python3
"""Freeze the completed R58 joint validation scoring contract without opening test."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R58 = DATA / "authoritative/pricefm_stage_r58_joint_recovery_audit_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r59_joint_scoring_contract_20260826"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r58-dir", type=Path, default=R58)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def stability_band(value: float) -> str:
    if not math.isfinite(value):
        return "nonfinite"
    if value <= 0.01:
        return "stable_le_0p01"
    if value <= 0.1:
        return "review_0p01_to_0p1"
    if value <= 1:
        return "review_0p1_to_1"
    if value <= 10:
        return "unstable_1_to_10"
    return "explosive_gt_10"


def markdown_table(frame: pd.DataFrame) -> str:
    if frame.empty:
        return "No rows."
    columns = list(frame.columns)
    rows = ["| " + " | ".join(columns) + " |", "| " + " | ".join(["---"] * len(columns)) + " |"]
    for values in frame.itertuples(index=False, name=None):
        cells = []
        for value in values:
            if isinstance(value, float):
                value = "" if math.isnan(value) else f"{value:.6g}"
            cells.append(str(value).replace("|", "\\|").replace("\n", " "))
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join(rows)


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    r58 = args.r58_dir.resolve()
    summary_path = r58 / "summary.json"
    triage_path = r58 / "pricefm_stage_r58_case_triage.csv"
    gates_path = r58 / "pricefm_stage_r58_gates.csv"
    summary = json.loads(summary_path.read_text())
    triage = pd.read_csv(triage_path)
    r58_gates = pd.read_csv(gates_path)
    required = {
        "case_id", "region", "fold", "likelihood_family", "method_id",
        "source_method_id", "source_experiment_id",
        "current_authoritative_validation_AQL", "raw_joint_validation_AQL",
        "contract_validation_AQL", "raw_relative_gain", "contract_relative_gain",
        "postfit_complete", "integrity_pass", "fit_converged", "final_max_change",
        "last5_change_slope", "raw_crossing_rows", "contract_crossing_pairs",
        "checkpoint", "checkpoint_sha256", "test_opened",
    }
    missing = sorted(required - set(triage.columns))
    if missing:
        raise RuntimeError(f"R58 triage is missing columns: {missing}")
    if (
        summary.get("status") != "full_surface_ready_for_scoring_contract_freeze"
        or len(triage) != args.expected_cases
        or int(summary.get("postfit_complete", -1)) != args.expected_cases
        or int(summary.get("integrity_failures", -1)) != 0
        or bool(summary.get("test_opened", True))
    ):
        raise RuntimeError("R58 is not a complete, integrity-clean, sealed-test surface")
    required_r58_gates = {
        "full_114_case_surface_repaired", "all_completed_cases_pass_integrity",
        "contract_predictions_noncrossing", "selection_is_validation_only",
        "sealed_test_not_opened",
    }
    observed_gates = set(r58_gates.loc[r58_gates.passed.astype(bool), "gate"].astype(str))
    if not required_r58_gates.issubset(observed_gates):
        raise RuntimeError("R58 prerequisite gates are not all passing")

    decisions = triage.copy()
    decisions["primary_scoring_role"] = "monotone_contract"
    decisions["primary_selection_metric"] = "validation_original_AQL"
    decisions["primary_validation_AQL"] = decisions.contract_validation_AQL
    decisions["raw_joint_role"] = "diagnostic_not_selection"
    decisions["stability_band"] = decisions.final_max_change.map(stability_band)
    decisions["primary_improves_authority"] = (
        decisions.primary_validation_AQL < decisions.current_authoritative_validation_AQL
    )
    decisions["repair_required"] = ~decisions.primary_improves_authority
    decisions["decision_status"] = decisions.repair_required.map({
        True: "repair_required_before_validation_freeze",
        False: "provisional_contract_winner_stability_review",
    })
    decisions["selection_frozen"] = False
    decisions["test_opened"] = False
    decisions["mcmc_confirmation_eligible"] = False
    decisions["registry_mutation_authorized"] = False
    decisions["article_mutation_authorized"] = False
    decisions = decisions.sort_values(["region", "fold"]).reset_index(drop=True)
    repair = decisions[decisions.repair_required].copy()
    provisional = decisions[~decisions.repair_required].copy()

    gates = pd.DataFrame([
        {"gate": "r58_complete_surface", "passed": len(decisions) == args.expected_cases, "observed": len(decisions)},
        {"gate": "r58_integrity_clean", "passed": bool(decisions.integrity_pass.all()), "observed": int((~decisions.integrity_pass).sum())},
        {"gate": "contract_noncrossing", "passed": bool(decisions.contract_crossing_pairs.eq(0).all()), "observed": int((decisions.contract_crossing_pairs > 0).sum())},
        {"gate": "test_sealed", "passed": bool(~decisions.test_opened.any()), "observed": bool(decisions.test_opened.any())},
        {"gate": "primary_score_frozen", "passed": True, "observed": "monotone_contract_validation_original_AQL"},
        {"gate": "raw_role_frozen", "passed": True, "observed": "diagnostic_not_selection"},
        {"gate": "repair_queue_bounded", "passed": len(repair) == 2, "observed": len(repair)},
        {"gate": "mcmc_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    if not gates.passed.astype(bool).all():
        raise RuntimeError(f"R59 scoring freeze gates failed: {gates.loc[~gates.passed.astype(bool)].to_dict('records')}")

    decisions.to_csv(output / "pricefm_stage_r59_joint_scoring_decisions.csv", index=False)
    provisional.to_csv(output / "pricefm_stage_r59_joint_provisional_winners.csv", index=False)
    repair.to_csv(output / "pricefm_stage_r59_joint_repair_queue.csv", index=False)
    gates.to_csv(output / "pricefm_stage_r59_joint_scoring_gates.csv", index=False)
    source_paths = [summary_path, triage_path, gates_path, Path(__file__).resolve()]
    pd.DataFrame([{
        "path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size,
    } for path in source_paths]).to_csv(output / "source_manifest.csv", index=False)
    result = {
        "status": "completed_joint_scoring_contract_freeze",
        "expected_cases": int(args.expected_cases),
        "primary_scoring_role": "monotone_contract",
        "primary_selection_metric": "validation_original_AQL",
        "raw_joint_role": "diagnostic_not_selection",
        "provisional_contract_winners": int(len(provisional)),
        "repair_required": int(len(repair)),
        "repair_case_ids": repair.case_id.astype(str).tolist(),
        "joint_scoring_contract_frozen": True,
        "validation_selection_frozen": False,
        "test_opened": False,
        "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "recommended_action": "run_bounded_r60_initializer_stability_repair_for_two_nonwinners",
    }
    write_json(output / "summary.json", result)
    report_rows = repair[[
        "case_id", "likelihood_family", "current_authoritative_validation_AQL",
        "raw_joint_validation_AQL", "contract_validation_AQL", "final_max_change",
        "last5_change_slope", "stability_band",
    ]]
    (output / "pricefm_stage_r59_joint_scoring_contract_report.md").write_text(
        "# PriceFM Stage-R59 joint scoring contract\n\n"
        "The complete R58 validation surface fixes monotone-contract original-scale AQL as the "
        "primary joint-model score. Raw joint AQL and raw crossings remain diagnostics; they are "
        "not an alternative score that may be chosen after seeing results. This is a validation-only "
        "freeze and the test ledger remains sealed.\n\n"
        f"The contract provisionally retains {len(provisional)} of {len(decisions)} cases and sends "
        f"exactly {len(repair)} cases to bounded initializer-stability repair. None is yet eligible "
        "for MCMC, registry mutation, or article promotion.\n\n"
        "## Repair queue\n\n" + markdown_table(report_rows) + "\n"
    )
    return result


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
