#!/usr/bin/env python3
"""Audit repaired Stage-R57 joint fits using validation evidence only."""

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
AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r58_joint_recovery_audit_20260824"
FORBIDDEN_AUTHORITY_COLUMNS = {
    "qdesn_AQL", "pricefm_AQL", "current_authoritative_test_AQL",
    "cached_pricefm_test_AQL", "test_AQL",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--authority", type=Path,
        default=AUTHORITY / "pricefm_stage_r57_joint_case_authority.csv",
    )
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def atomic_csv(frame: pd.DataFrame, path: Path) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(tmp, index=False)
    tmp.replace(path)


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def validation_aql(path: Path, role: str) -> float:
    frame = pd.read_csv(path)
    required = {"prediction_role", "split", "unit", "AQL"}
    if required - set(frame.columns):
        raise RuntimeError(f"Metric file lacks columns {sorted(required - set(frame.columns))}: {path}")
    rows = frame[
        frame.prediction_role.astype(str).eq(role)
        & frame.split.astype(str).eq("val")
        & frame.unit.astype(str).eq("original")
    ]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one original validation AQL for {role}: {path}")
    value = float(rows.iloc[0].AQL)
    if not math.isfinite(value):
        raise RuntimeError(f"Nonfinite validation AQL for {role}: {path}")
    return value


def hash_matches(path: Path, expected: object) -> bool:
    return path.is_file() and isinstance(expected, str) and len(expected) == 64 and sha256(path) == expected


def queue_label(
    complete: bool, integrity: bool, improves: bool, converged: bool, raw_crossing_rows: int,
) -> str:
    if not complete:
        return "incomplete_fit_or_postfit"
    if not integrity:
        return "integrity_failure"
    if not improves:
        return "no_validation_gain"
    if converged and raw_crossing_rows == 0:
        return "strict_raw_candidate"
    if not converged and raw_crossing_rows > 0:
        return "convergence_and_raw_crossing_review"
    if not converged:
        return "convergence_review"
    return "raw_crossing_review"


def case_row(row) -> dict:
    model = Path(row.output_dir)
    summary_path = model / "job_summary.json"
    metrics_path = model / "raw_contract_metric_summary.csv"
    summary = read_json(summary_path)
    complete = (
        summary.get("status") == "completed"
        and summary.get("postfit_repaired") is True
        and metrics_path.is_file()
    )
    base = {
        "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
        "likelihood_family": row.likelihood_family, "method_id": row.method_id,
        "source_method_id": row.source_method_id,
        "source_experiment_id": row.experiment_id,
        "fit_status": summary.get("status", "missing"),
        "postfit_repaired": bool(summary.get("postfit_repaired", False)),
        "postfit_complete": complete,
        "current_authoritative_validation_AQL": float(row.current_authoritative_validation_AQL),
        "raw_joint_validation_AQL": math.nan,
        "contract_validation_AQL": math.nan,
        "raw_delta_joint_minus_authority": math.nan,
        "contract_delta_joint_minus_authority": math.nan,
        "raw_relative_gain": math.nan,
        "contract_relative_gain": math.nan,
        "contract_delta_minus_raw": math.nan,
        "fit_converged": bool(summary.get("converged", False)),
        "iterations": summary.get("iterations", ""),
        "final_max_change": summary.get("final_max_change", math.nan),
        "last5_change_slope": summary.get("last5_change_slope", math.nan),
        "raw_crossing_rows": int(summary.get("validation_crossing_rows", -1)),
        "raw_crossing_pairs": int(summary.get("validation_crossing_pairs", -1)),
        "contract_crossing_rows": int(summary.get("contract_crossing_rows", -1)),
        "contract_crossing_pairs": int(summary.get("contract_crossing_pairs", -1)),
        "contract_adjusted_rows": int(summary.get("contract_adjusted_rows", -1)),
        "contract_max_abs_adjustment": summary.get("contract_max_abs_adjustment", math.nan),
        "contract_mean_abs_adjustment": summary.get("contract_mean_abs_adjustment", math.nan),
        "checkpoint": summary.get("checkpoint", ""),
        "checkpoint_sha256": summary.get("checkpoint_sha256", ""),
        "checkpoint_hash_verified": False,
        "source_manifest_hash_verified": False,
        "split_firewall_valid": summary.get("split_firewall") == "train_validation_only",
        "test_opened": bool(summary.get("test_accessed", False)),
        "raw_improves_authority": False,
        "contract_improves_authority": False,
        "dual_role_improves_authority": False,
        "integrity_pass": False,
        "strict_raw_candidate": False,
        "provisional_vb_initializer_candidate": False,
        "mechanism_queue": "incomplete_fit_or_postfit",
        "mcmc_confirmation_eligible": False,
        "selection_role": "validation_only",
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "job_summary": str(summary_path),
        "raw_contract_metrics": str(metrics_path),
    }
    if not complete:
        return base

    raw_aql = validation_aql(metrics_path, "raw_joint")
    contract_aql = validation_aql(metrics_path, "monotone_contract")
    reference = float(row.current_authoritative_validation_AQL)
    checkpoint = Path(str(summary.get("checkpoint", "")))
    source_manifest = Path(str(summary.get("source_manifest", "")))
    checkpoint_ok = hash_matches(checkpoint, summary.get("checkpoint_sha256"))
    source_ok = hash_matches(source_manifest, summary.get("source_manifest_sha256"))
    raw_improves = raw_aql < reference
    contract_improves = contract_aql < reference
    dual_improves = raw_improves and contract_improves
    contract_non_crossing = int(summary.get("contract_crossing_pairs", -1)) == 0
    integrity = (
        checkpoint_ok and source_ok and contract_non_crossing
        and summary.get("split_firewall") == "train_validation_only"
        and not bool(summary.get("test_accessed", False))
    )
    converged = bool(summary.get("converged", False))
    raw_crossings = int(summary.get("validation_crossing_rows", -1))
    strict = integrity and dual_improves and converged and raw_crossings == 0
    provisional = integrity and dual_improves
    base.update({
        "raw_joint_validation_AQL": raw_aql,
        "contract_validation_AQL": contract_aql,
        "raw_delta_joint_minus_authority": raw_aql - reference,
        "contract_delta_joint_minus_authority": contract_aql - reference,
        "raw_relative_gain": (reference - raw_aql) / reference if reference else math.nan,
        "contract_relative_gain": (reference - contract_aql) / reference if reference else math.nan,
        "contract_delta_minus_raw": contract_aql - raw_aql,
        "checkpoint_hash_verified": checkpoint_ok,
        "source_manifest_hash_verified": source_ok,
        "raw_improves_authority": raw_improves,
        "contract_improves_authority": contract_improves,
        "dual_role_improves_authority": dual_improves,
        "integrity_pass": integrity,
        "strict_raw_candidate": strict,
        "provisional_vb_initializer_candidate": provisional,
        "mechanism_queue": queue_label(True, integrity, dual_improves, converged, raw_crossings),
    })
    return base


def family_summary(cases: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for family, group in cases.groupby("likelihood_family", sort=True):
        complete = group[group.postfit_complete]
        rows.append({
            "likelihood_family": family,
            "expected_cases": int(len(group)),
            "postfit_complete": int(len(complete)),
            "dual_role_validation_improvements": int(complete.dual_role_improves_authority.sum()),
            "provisional_vb_initializer_candidates": int(complete.provisional_vb_initializer_candidate.sum()),
            "strict_raw_candidates": int(complete.strict_raw_candidate.sum()),
            "converged_cases": int(complete.fit_converged.sum()),
            "cases_with_raw_crossings": int((complete.raw_crossing_rows > 0).sum()),
            "median_raw_relative_gain": complete.raw_relative_gain.median() if len(complete) else math.nan,
            "median_contract_relative_gain": complete.contract_relative_gain.median() if len(complete) else math.nan,
            "median_final_max_change": complete.final_max_change.median() if len(complete) else math.nan,
            "median_contract_max_abs_adjustment": complete.contract_max_abs_adjustment.median() if len(complete) else math.nan,
        })
    return pd.DataFrame(rows)


def evidence_manifest(paths: list[tuple[str, Path]]) -> pd.DataFrame:
    rows = []
    seen = set()
    for label, path in paths:
        path = Path(path)
        key = str(path.resolve())
        if key in seen or not path.is_file():
            continue
        seen.add(key)
        rows.append({
            "label": label, "path": key, "sha256": sha256(path),
            "bytes": int(path.stat().st_size),
        })
    return pd.DataFrame(rows)


def markdown_table(frame: pd.DataFrame) -> str:
    if frame.empty:
        return "No rows."

    def cell(value: object) -> str:
        if isinstance(value, float):
            value = "" if math.isnan(value) else f"{value:.6g}"
        return str(value).replace("|", "\\|").replace("\n", " ")

    header = "| " + " | ".join(map(str, frame.columns)) + " |"
    rule = "| " + " | ".join(["---"] * len(frame.columns)) + " |"
    body = ["| " + " | ".join(cell(value) for value in row) + " |" for row in frame.itertuples(index=False, name=None)]
    return "\n".join([header, rule, *body])


def render_report(summary: dict, family: pd.DataFrame, gates: pd.DataFrame) -> str:
    family_table = markdown_table(family) if len(family) else "No repaired cases yet."
    gate_table = markdown_table(gates)
    return f"""# PriceFM Stage-R58 joint recovery audit

## Decision

Status: `{summary['status']}`. Stage-R57 should continue to the complete 114-case
validation surface while terminal cases are repaired without refitting. No MCMC,
test audit, registry mutation, or article mutation is authorized by this audit.

## Current surface

- Expected cases: {summary['expected_cases']}
- Postfit-complete cases: {summary['postfit_complete']}
- Remaining cases: {summary['remaining_cases']}
- Dual-role validation improvements: {summary['dual_role_validation_improvements']}
- Provisional VB initializer candidates: {summary['provisional_vb_initializer_candidates']}
- Strict raw candidates: {summary['strict_raw_candidates']}

The provisional queue requires finite raw and monotone-contract validation AQL,
improvement over the frozen authoritative validation AQL under both roles, a
verified checkpoint and source manifest, a train/validation-only firewall, and a
noncrossing contract. Maximum-iteration termination and raw crossings remain
explicit review signals rather than irreversible fit failures. The final scoring
contract must be frozen before MCMC eligibility can be declared.

## Likelihood families

{family_table}

## Gates

{gate_table}

## Required next action

Let R57 finish, run the idempotent postfit repair until all 114 cases are repaired,
then rerun this audit and freeze the raw-versus-monotone scoring policy. Only after
that full-surface validation decision may a bounded MCMC confirmation manifest be
designed. The sealed test ledger remains unopened until validation selection is
frozen.
"""


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    authority = pd.read_csv(args.authority)
    manifest = pd.read_csv(args.manifest)
    if FORBIDDEN_AUTHORITY_COLUMNS & set(authority.columns):
        raise RuntimeError("Sealed test outcomes leaked into the R58 authority")
    if len(authority) != args.expected_cases or len(manifest) != args.expected_cases:
        raise RuntimeError("R58 inputs do not contain the expected full region/fold surface")
    required_authority = {
        "case_id", "region", "fold", "likelihood_family", "source_method_id",
        "experiment_id", "current_authoritative_validation_AQL", "selection_split",
        "selection_is_validation_only", "test_metrics_role",
    }
    required_manifest = {"case_id", "method_id", "output_dir"}
    if required_authority - set(authority.columns) or required_manifest - set(manifest.columns):
        raise RuntimeError("R58 input schema is incomplete")
    if (
        not authority.selection_split.astype(str).eq("val").all()
        or not authority.selection_is_validation_only.eq(True).all()
        or not authority.test_metrics_role.astype(str).eq("audit_only").all()
    ):
        raise RuntimeError("R58 authority violates the validation-only selection firewall")
    merged = authority.merge(
        manifest[["case_id", "method_id", "output_dir"]],
        on="case_id", how="inner", validate="one_to_one",
    )
    if len(merged) != args.expected_cases:
        raise RuntimeError("R58 authority and launch manifest case IDs disagree")

    cases = pd.DataFrame([case_row(row) for row in merged.sort_values(["region", "fold"]).itertuples(index=False)])
    family = family_summary(cases)
    postfit_complete = int(cases.postfit_complete.sum())
    integrity_failures = int((cases.postfit_complete & ~cases.integrity_pass).sum())
    all_complete = postfit_complete == args.expected_cases
    all_integrity = all_complete and integrity_failures == 0
    gates = pd.DataFrame([
        {"gate": "full_114_case_surface_repaired", "passed": all_complete, "observed": postfit_complete},
        {"gate": "all_completed_cases_pass_integrity", "passed": integrity_failures == 0, "observed": integrity_failures},
        {"gate": "contract_predictions_noncrossing", "passed": bool((cases.loc[cases.postfit_complete, "contract_crossing_pairs"] == 0).all()), "observed": int((cases.contract_crossing_pairs > 0).sum())},
        {"gate": "selection_is_validation_only", "passed": bool(cases.selection_role.eq("validation_only").all()), "observed": "validation_only"},
        {"gate": "sealed_test_not_opened", "passed": bool(~cases.test_opened.any()), "observed": bool(cases.test_opened.any())},
        {"gate": "joint_scoring_contract_frozen", "passed": False, "observed": "pending explicit freeze"},
        {"gate": "mcmc_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    status = "partial_surface_continue_r57_and_repair"
    if integrity_failures:
        status = "partial_or_complete_surface_with_integrity_failures"
    elif all_integrity:
        status = "full_surface_ready_for_scoring_contract_freeze"
    queue = cases[cases.provisional_vb_initializer_candidate].copy()
    queue["queue_status"] = "provisional_not_mcmc_authorized"
    queue["mcmc_confirmation_eligible"] = False

    atomic_csv(cases, output / "pricefm_stage_r58_case_triage.csv")
    atomic_csv(family, output / "pricefm_stage_r58_family_summary.csv")
    atomic_csv(queue, output / "pricefm_stage_r58_candidate_queues.csv")
    atomic_csv(gates, output / "pricefm_stage_r58_gates.csv")
    evidence = [("authority", args.authority), ("launch_manifest", args.manifest), ("audit_script", Path(__file__))]
    for row in cases[cases.postfit_complete].itertuples(index=False):
        evidence.extend([
            (f"{row.case_id}_job_summary", Path(row.job_summary)),
            (f"{row.case_id}_raw_contract_metrics", Path(row.raw_contract_metrics)),
            (f"{row.case_id}_checkpoint", Path(row.checkpoint)),
        ])
    atomic_csv(evidence_manifest(evidence), output / "source_manifest.csv")
    test_opened = bool(cases.test_opened.any())
    summary = {
        "status": status, "expected_cases": int(args.expected_cases),
        "postfit_complete": postfit_complete,
        "remaining_cases": int(args.expected_cases - postfit_complete),
        "integrity_failures": integrity_failures,
        "raw_validation_improvements": int(cases.raw_improves_authority.sum()),
        "contract_validation_improvements": int(cases.contract_improves_authority.sum()),
        "dual_role_validation_improvements": int(cases.dual_role_improves_authority.sum()),
        "provisional_vb_initializer_candidates": int(cases.provisional_vb_initializer_candidate.sum()),
        "strict_raw_candidates": int(cases.strict_raw_candidate.sum()),
        "selection_frozen": False, "joint_scoring_contract_frozen": False,
        "test_opened": test_opened, "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
        "recommended_action": "continue_r57_repair_all_cases_then_freeze_scoring_contract",
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r58_joint_recovery_report.md").write_text(
        render_report(summary, family, gates)
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
