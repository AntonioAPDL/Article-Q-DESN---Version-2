#!/usr/bin/env python3
"""Close out R61 using the frozen validation contract without opening test."""

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
R59 = DATA / "authoritative/pricefm_stage_r59_joint_scoring_contract_20260826"
GRID = DATA / "experiment_grids/pricefm_stage_r61_joint_mechanism_campaign_20260826"
OUTPUT = DATA / "authoritative/pricefm_stage_r61_joint_mechanism_closeout_20260826"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r59-dir", type=Path, default=R59)
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-runs", type=int, default=14)
    p.add_argument("--stability-max-change", type=float, default=1.0)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def validation_aql(path: Path, role: str) -> float:
    frame = pd.read_csv(path)
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


def run_row(row) -> dict:
    model = Path(row.output_dir)
    summary_path = model / "job_summary.json"
    metric_path = model / "raw_contract_metric_summary.csv"
    rhs_path = model / "rhs_block_diagnostics.csv"
    summary = read_json(summary_path)
    complete = (
        summary.get("status") == "completed"
        and summary.get("postfit_repaired") is True
        and metric_path.is_file()
        and rhs_path.is_file()
    )
    result = {
        "case_id": row.case_id, "source_case_id": row.source_case_id,
        "region": row.region, "fold": int(row.fold), "arm_id": row.arm_id,
        "question": row.question, "likelihood_family": row.likelihood_family,
        "method_id": row.method_id, "initialization_mode": row.initialization_mode,
        "adapter_variant": row.adapter_variant, "complexity_rank": int(row.complexity_rank),
        "status": summary.get("status", "missing"), "postfit_complete": complete,
        "raw_joint_validation_AQL": math.nan, "contract_validation_AQL": math.nan,
        "fit_converged": bool(summary.get("converged", False)),
        "final_max_change": summary.get("final_max_change", math.nan),
        "last5_change_slope": summary.get("last5_change_slope", math.nan),
        "checkpoint": summary.get("checkpoint", ""),
        "checkpoint_sha256": summary.get("checkpoint_sha256", ""),
        "checkpoint_format": summary.get("output_checkpoint_format", ""),
        "checkpoint_hash_verified": False, "source_manifest_hash_verified": False,
        "split_firewall_valid": summary.get("split_firewall") == "train_validation_only",
        "test_opened": bool(summary.get("test_accessed", False)), "integrity_pass": False,
        "job_summary": str(summary_path), "raw_contract_metrics": str(metric_path),
    }
    if not complete:
        return result
    checkpoint = Path(str(summary.get("checkpoint", "")))
    source_manifest = Path(str(summary.get("source_manifest", "")))
    checkpoint_ok = (
        checkpoint.is_file() and len(str(summary.get("checkpoint_sha256", ""))) == 64
        and sha256(checkpoint) == summary.get("checkpoint_sha256")
    )
    source_ok = (
        source_manifest.is_file() and len(str(summary.get("source_manifest_sha256", ""))) == 64
        and sha256(source_manifest) == summary.get("source_manifest_sha256")
    )
    integrity = (
        checkpoint_ok and source_ok
        and summary.get("output_checkpoint_format") == "pricefm_joint_vb_checkpoint_v2"
        and int(summary.get("contract_crossing_pairs", -1)) == 0
        and summary.get("split_firewall") == "train_validation_only"
        and not bool(summary.get("test_accessed", False))
    )
    result.update({
        "raw_joint_validation_AQL": validation_aql(metric_path, "raw_joint"),
        "contract_validation_AQL": validation_aql(metric_path, "monotone_contract"),
        "checkpoint_hash_verified": checkpoint_ok,
        "source_manifest_hash_verified": source_ok,
        "integrity_pass": integrity,
    })
    return result


def run(args: argparse.Namespace) -> dict:
    if args.stability_max_change <= 0 or args.expected_runs < 1:
        raise ValueError("Invalid R61 closeout controls")
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    r59_summary_path = args.r59_dir / "summary.json"
    decisions_path = args.r59_dir / "pricefm_stage_r59_joint_scoring_decisions.csv"
    r59_summary = read_json(r59_summary_path)
    decisions = pd.read_csv(decisions_path)
    manifest = pd.read_csv(args.manifest)
    required = {
        "case_id", "source_case_id", "region", "fold", "arm_id", "question",
        "likelihood_family", "method_id", "initialization_mode", "adapter_variant",
        "complexity_rank", "output_dir", "test_access_authorized",
    }
    if required - set(manifest.columns) or len(manifest) != args.expected_runs:
        raise RuntimeError("R61 manifest is incomplete")
    if manifest.test_access_authorized.astype(bool).any():
        raise RuntimeError("R61 manifest attempted to authorize test")
    if (
        r59_summary.get("status") != "completed_joint_scoring_contract_freeze"
        or bool(r59_summary.get("test_opened", True))
    ):
        raise RuntimeError("R59 scoring freeze is not valid")

    runs = pd.DataFrame([run_row(row) for row in manifest.itertuples(index=False)])
    runs.to_csv(output / "pricefm_stage_r61_run_health.csv", index=False)
    complete = int(runs.postfit_complete.sum())
    integrity_failures = int((runs.postfit_complete & ~runs.integrity_pass).sum())
    if complete != args.expected_runs or integrity_failures:
        result = {
            "status": "incomplete_or_integrity_blocked", "expected_runs": int(args.expected_runs),
            "postfit_complete": complete, "remaining_runs": int(args.expected_runs - complete),
            "integrity_failures": integrity_failures, "validation_selection_frozen": False,
            "test_opened": False, "mcmc_launch_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        }
        write_json(output / "summary.json", result)
        return result

    references = decisions.set_index("case_id").current_authoritative_validation_AQL.to_dict()
    runs["current_authoritative_validation_AQL"] = runs.source_case_id.map(references)
    if runs.current_authoritative_validation_AQL.isna().any():
        raise RuntimeError("R61 source case is absent from R59")
    runs["contract_delta_minus_authority"] = runs.contract_validation_AQL - runs.current_authoritative_validation_AQL
    runs["contract_relative_gain"] = (
        runs.current_authoritative_validation_AQL - runs.contract_validation_AQL
    ) / runs.current_authoritative_validation_AQL
    runs["primary_improves_authority"] = runs.contract_delta_minus_authority < 0
    runs["stability_guard_pass"] = (
        runs.final_max_change.astype(float).le(args.stability_max_change)
        & runs.last5_change_slope.astype(float).le(0)
    )
    runs.to_csv(output / "pricefm_stage_r61_arm_metrics.csv", index=False)

    case_rows, test_queue_rows, continuation_rows = [], [], []
    for source_case_id, group in runs.groupby("source_case_id", sort=True):
        ranked = group.sort_values([
            "contract_validation_AQL", "final_max_change", "complexity_rank", "arm_id",
        ])
        best = ranked.iloc[0]
        improves = bool(best.primary_improves_authority)
        stable = bool(best.stability_guard_pass)
        if improves and stable:
            decision = "r61_validation_winner"
            next_action = "freeze_selection_then_open_one_sealed_test_audit"
            test_queue_rows.append({
                "source_case_id": source_case_id, "selected_case_id": best.case_id,
                "region": best.region, "fold": int(best.fold), "arm_id": best.arm_id,
                "checkpoint": best.checkpoint, "checkpoint_sha256": best.checkpoint_sha256,
                "selection_role": "validation_only_monotone_contract",
                "test_access_authorized": False,
            })
        elif improves:
            decision = "r61_validation_win_needs_exact_continuation"
            next_action = "continue_selected_v2_checkpoint_before_test"
            continuation_rows.append({
                "source_case_id": source_case_id, "selected_case_id": best.case_id,
                "checkpoint": best.checkpoint, "checkpoint_sha256": best.checkpoint_sha256,
                "test_access_authorized": False,
            })
        else:
            decision = "retain_individual_authority_joint_mechanism_unresolved"
            next_action = "stop_joint_screening_and_reassess_parameterization"
        case_rows.append({
            "source_case_id": source_case_id, "region": best.region, "fold": int(best.fold),
            "current_authoritative_validation_AQL": float(best.current_authoritative_validation_AQL),
            "selected_case_id": best.case_id, "selected_arm_id": best.arm_id,
            "selected_question": best.question, "selected_likelihood_family": best.likelihood_family,
            "selected_adapter_variant": best.adapter_variant,
            "selected_contract_validation_AQL": float(best.contract_validation_AQL),
            "selected_raw_validation_AQL": float(best.raw_joint_validation_AQL),
            "contract_relative_gain": float(best.contract_relative_gain),
            "selected_final_max_change": float(best.final_max_change),
            "selected_last5_change_slope": float(best.last5_change_slope),
            "primary_improves_authority": improves, "stability_guard_pass": stable,
            "decision": decision, "next_action": next_action,
            "selection_role": "validation_only_monotone_contract", "test_opened": False,
            "mcmc_confirmation_eligible": False,
        })
    cases = pd.DataFrame(case_rows).sort_values(["region", "fold"]).reset_index(drop=True)
    cases.to_csv(output / "pricefm_stage_r61_case_decisions.csv", index=False)
    pd.DataFrame(test_queue_rows, columns=[
        "source_case_id", "selected_case_id", "region", "fold", "arm_id", "checkpoint",
        "checkpoint_sha256", "selection_role", "test_access_authorized",
    ]).to_csv(output / "pricefm_stage_r61_sealed_test_audit_queue.csv", index=False)
    pd.DataFrame(continuation_rows, columns=[
        "source_case_id", "selected_case_id", "checkpoint", "checkpoint_sha256",
        "test_access_authorized",
    ]).to_csv(output / "pricefm_stage_r61_exact_continuation_queue.csv", index=False)

    stable_winners = int((cases.primary_improves_authority & cases.stability_guard_pass).sum())
    unstable_winners = int((cases.primary_improves_authority & ~cases.stability_guard_pass).sum())
    unresolved = int((~cases.primary_improves_authority).sum())
    selection_frozen = stable_winners == len(cases)
    gates = pd.DataFrame([
        {"gate": "all_campaign_runs_complete", "passed": complete == args.expected_runs, "observed": complete},
        {"gate": "all_integrity_checks_pass", "passed": integrity_failures == 0, "observed": integrity_failures},
        {"gate": "primary_contract_preserved", "passed": True, "observed": "monotone_contract_validation_original_AQL"},
        {"gate": "test_sealed", "passed": not bool(runs.test_opened.any()), "observed": bool(runs.test_opened.any())},
        {"gate": "stable_validation_winner_per_case", "passed": selection_frozen, "observed": stable_winners},
        {"gate": "mcmc_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r61_closeout_gates.csv", index=False)
    source_paths = [r59_summary_path, decisions_path, args.manifest.resolve(), Path(__file__).resolve()]
    source_paths.extend(Path(path) for path in runs.job_summary)
    source_paths.extend(Path(path) for path in runs.raw_contract_metrics)
    pd.DataFrame([{
        "path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size,
    } for path in source_paths if path.is_file()]).drop_duplicates(["path", "sha256"]).to_csv(
        output / "source_manifest.csv", index=False
    )
    result = {
        "status": "completed_validation_selection_frozen" if selection_frozen else "completed_joint_mechanism_unresolved_or_unstable",
        "expected_runs": int(args.expected_runs), "postfit_complete": complete, "remaining_runs": 0,
        "integrity_failures": integrity_failures, "stable_validation_winners": stable_winners,
        "unstable_validation_winners": unstable_winners, "mechanism_unresolved_cases": unresolved,
        "validation_selection_frozen": selection_frozen, "test_opened": False,
        "test_audit_authorized": False, "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False, "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", result)
    (output / "pricefm_stage_r61_closeout_report.md").write_text(
        "# PriceFM Stage-R61 joint mechanism closeout\n\n"
        f"All {complete} prepared mechanism arms completed. Validation-only selection found "
        f"{stable_winners} stable winner(s), {unstable_winners} unstable validation winner(s), and "
        f"{unresolved} unresolved case(s).\n\n"
        "Test remains sealed. The queue is a proposal only; a separate explicit authorization is required "
        "before test audit, MCMC, registry, or article work.\n"
    )
    return result


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
