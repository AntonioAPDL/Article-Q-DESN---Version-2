#!/usr/bin/env python3
"""Close out Stage-R63 against the corrected R62 validation authority."""

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
GRID = DATA / "experiment_grids/pricefm_stage_r63_corrected_joint_campaign_20260827"
OUTPUT = DATA / "authoritative/pricefm_stage_r63_corrected_joint_closeout_20260827"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-runs", type=int, default=38)
    p.add_argument("--stability-max-change", type=float, default=1.0)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            h.update(block)
    return h.hexdigest()


def read_json(path: Path) -> dict:
    try: return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError): return {}


def metric(path: Path, role: str) -> float:
    frame = pd.read_csv(path)
    row = frame[(frame.prediction_role.astype(str) == role) & (frame.split.astype(str) == "val") & (frame.unit.astype(str) == "original")]
    if len(row) != 1 or not math.isfinite(float(row.iloc[0].AQL)):
        raise RuntimeError(f"Invalid {role} validation metric: {path}")
    return float(row.iloc[0].AQL)


def audit_row(row) -> dict:
    model = Path(row.output_dir); summary = read_json(model / "job_summary.json")
    raw_metric = model / "raw_contract_metric_summary.csv"
    checkpoint = Path(str(summary.get("checkpoint", ""))); source_manifest = Path(str(summary.get("source_manifest", "")))
    complete = summary.get("status") == "completed" and summary.get("postfit_repaired") is True and raw_metric.is_file()
    checkpoint_ok = complete and checkpoint.is_file() and sha256(checkpoint) == summary.get("checkpoint_sha256")
    source_ok = complete and source_manifest.is_file() and sha256(source_manifest) == summary.get("source_manifest_sha256")
    integrity = checkpoint_ok and source_ok and summary.get("output_checkpoint_format") == "pricefm_joint_vb_checkpoint_v2" and summary.get("split_firewall") == "train_validation_only" and not summary.get("test_accessed", False) and int(summary.get("contract_crossing_pairs", -1)) == 0
    return {"case_id": row.case_id, "source_case_id": row.source_case_id, "region": row.region, "fold": int(row.fold),
            "arm_id": row.arm_id, "question": row.question, "target_reason": row.target_reason,
            "likelihood_family": row.likelihood_family, "complexity_rank": int(row.complexity_rank),
            "postfit_complete": complete, "integrity_pass": integrity,
            "raw_validation_AQL": metric(raw_metric, "raw_joint") if complete else math.nan,
            "contract_validation_AQL": metric(raw_metric, "monotone_contract") if complete else math.nan,
            "independent_validation_AQL": float(row.independent_validation_AQL), "old_joint_validation_AQL": float(row.old_joint_validation_AQL),
            "fit_converged": bool(summary.get("converged", False)), "final_max_change": summary.get("final_max_change", math.nan),
            "last5_change_slope": summary.get("last5_change_slope", math.nan), "checkpoint": str(checkpoint),
            "checkpoint_sha256": summary.get("checkpoint_sha256", ""), "test_opened": bool(summary.get("test_accessed", False))}


def choose(rows: pd.DataFrame, stability_max_change: float) -> pd.DataFrame:
    decisions = []
    for source_case, group in rows.groupby("source_case_id", sort=True):
        best = group.sort_values(["contract_validation_AQL", "final_max_change", "complexity_rank", "arm_id"]).iloc[0]
        stable = bool(float(best.final_max_change) <= stability_max_change and float(best.last5_change_slope) <= 0)
        beats_independent = bool(best.contract_validation_AQL < best.independent_validation_AQL)
        beats_old_joint = bool(best.contract_validation_AQL < best.old_joint_validation_AQL)
        eligible = bool(best.integrity_pass and stable and beats_independent and beats_old_joint)
        decisions.append({"source_case_id": source_case, "region": best.region, "fold": int(best.fold),
                          "selected_case_id": best.case_id, "selected_arm_id": best.arm_id,
                          "selected_family": best.likelihood_family, "selected_contract_validation_AQL": best.contract_validation_AQL,
                          "independent_validation_AQL": best.independent_validation_AQL, "old_joint_validation_AQL": best.old_joint_validation_AQL,
                          "beats_independent": beats_independent, "beats_old_joint": beats_old_joint,
                          "stability_guard_pass": stable, "integrity_pass": bool(best.integrity_pass),
                          "validation_confirmation_eligible": eligible, "checkpoint": best.checkpoint,
                          "checkpoint_sha256": best.checkpoint_sha256, "test_opened": False,
                          "decision": "freeze_validation_winner" if eligible else "retain_r62_independent_authority"})
    return pd.DataFrame(decisions)


def run(args: argparse.Namespace) -> dict:
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force: raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = pd.read_csv(args.manifest)
    if len(manifest) != args.expected_runs or manifest.test_access_authorized.astype(bool).any():
        raise RuntimeError("R63 manifest count or test firewall failed")
    rows = pd.DataFrame([audit_row(row) for row in manifest.itertuples(index=False)])
    rows.to_csv(output / "pricefm_stage_r63_run_health.csv", index=False)
    complete = int(rows.postfit_complete.sum()); integrity_failures = int((rows.postfit_complete & ~rows.integrity_pass).sum())
    if complete != args.expected_runs or integrity_failures:
        result = {"status": "incomplete_or_integrity_blocked", "expected_runs": args.expected_runs,
                  "postfit_complete": complete, "remaining_runs": args.expected_runs - complete,
                  "integrity_failures": integrity_failures, "test_opened": False,
                  "mcmc_launch_authorized": False, "registry_mutation_authorized": False,
                  "article_mutation_authorized": False}
        write_json(output / "summary.json", result); return result
    decisions = choose(rows, args.stability_max_change)
    rows.to_csv(output / "pricefm_stage_r63_arm_metrics.csv", index=False)
    decisions.to_csv(output / "pricefm_stage_r63_case_decisions.csv", index=False)
    eligible = decisions[decisions.validation_confirmation_eligible].copy()
    eligible.assign(mcmc_launch_authorized=False, test_access_authorized=False).to_csv(output / "pricefm_stage_r63_confirmation_queue.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "all_runs_complete", "passed": complete == args.expected_runs, "observed": complete},
        {"gate": "all_integrity_pass", "passed": integrity_failures == 0, "observed": integrity_failures},
        {"gate": "validation_only_selection", "passed": not rows.test_opened.any(), "observed": bool(rows.test_opened.any())},
        {"gate": "dual_baseline_gate_applied", "passed": True, "observed": "R62_independent_and_old_joint"},
        {"gate": "mcmc_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r63_closeout_gates.csv", index=False)
    paths = [args.manifest.resolve(), Path(__file__).resolve()] + [Path(x) for x in rows.checkpoint if Path(x).is_file()]
    pd.DataFrame([{"path": str(p), "sha256": sha256(p), "bytes": p.stat().st_size} for p in paths]).to_csv(output / "source_manifest.csv", index=False)
    result = {"status": "completed_r63_validation_closeout", "expected_runs": args.expected_runs,
              "postfit_complete": complete, "target_cells": len(decisions),
              "validation_confirmation_eligible": len(eligible), "retained_independent": int((~decisions.validation_confirmation_eligible).sum()),
              "test_opened": False, "mcmc_launch_authorized": False,
              "registry_mutation_authorized": False, "article_mutation_authorized": False}
    write_json(output / "summary.json", result); return result


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
