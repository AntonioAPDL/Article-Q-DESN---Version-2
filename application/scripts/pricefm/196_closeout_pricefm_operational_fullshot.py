#!/usr/bin/env python3
"""Close out the operational PriceFM benchmark without mutating registries or article files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import statistics

from pricefm_operational_fullshot import (
    QDESN_REGISTRY_SHA256,
    atomic_write_csv,
    atomic_write_json,
    atomic_write_text,
    read_csv_rows,
    read_json,
    sha256_file,
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--artifact-root", required=True)
    p.add_argument("--qdesn-registry", required=True)
    return p


def mean(rows: list[dict[str, object]], field: str) -> float:
    return statistics.fmean(float(row[field]) for row in rows)


def closeout(root: Path, registry_path: Path) -> dict[str, object]:
    if sha256_file(registry_path) != QDESN_REGISTRY_SHA256:
        raise RuntimeError("Authoritative Q-DESN decision registry hash mismatch")
    test_summary = read_json(root / "test" / "aggregation_summary.json")
    primary_path = Path(test_summary["selectors"]["cell_specific"]["path"])
    sensitivity_path = Path(test_summary["selectors"]["region_global"]["path"])
    if sha256_file(primary_path) != test_summary["selectors"]["cell_specific"]["sha256"]:
        raise RuntimeError("Primary operational PriceFM metric hash mismatch")
    if sha256_file(sensitivity_path) != test_summary["selectors"]["region_global"]["sha256"]:
        raise RuntimeError("Sensitivity operational PriceFM metric hash mismatch")

    primary = read_csv_rows(primary_path)
    sensitivity = read_csv_rows(sensitivity_path)
    registry = read_csv_rows(registry_path)
    if len(primary) != 114 or len(registry) != 114:
        raise RuntimeError(f"Expected 114 primary and registry rows, got {len(primary)} and {len(registry)}")
    registry_index = {(int(row["fold"]), row["region"]): row for row in registry}
    sensitivity_index = {(int(row["fold"]), row["region"]): row for row in sensitivity}

    decisions = []
    for result in primary:
        key = (int(result["fold"]), result["region"])
        if key not in registry_index or key not in sensitivity_index:
            raise RuntimeError(f"Missing comparison row for {key}")
        reference = registry_index[key]
        sensitivity_result = sensitivity_index[key]
        operational_aql = float(result["AQL"])
        qdesn_aql = float(reference["qdesn_AQL"])
        cached_pricefm_aql = float(reference["pricefm_AQL"])
        beats_qdesn = operational_aql < qdesn_aql
        beats_cached = operational_aql < cached_pricefm_aql
        decisions.append({
            "region": result["region"],
            "fold": int(result["fold"]),
            "operational_pricefm_candidate_id": result["candidate_id"],
            "operational_pricefm_phase": result["phase"],
            "operational_pricefm_degree": result["canonical_degree"],
            "operational_pricefm_AQL": operational_aql,
            "region_global_sensitivity_AQL": float(sensitivity_result["AQL"]),
            "current_qdesn_method_id": reference["qdesn_method_id"],
            "current_qdesn_AQL": qdesn_aql,
            "cached_pricefm_method_id": reference["pricefm_method_id"],
            "cached_pricefm_AQL": cached_pricefm_aql,
            "delta_operational_minus_qdesn": operational_aql - qdesn_aql,
            "delta_operational_minus_cached_pricefm": operational_aql - cached_pricefm_aql,
            "operational_beats_current_qdesn": beats_qdesn,
            "operational_beats_cached_pricefm": beats_cached,
            "dual_promotion_gate_pass": beats_qdesn and beats_cached,
            "decision": "promotion_queue" if beats_qdesn and beats_cached else "audit_only",
            "registry_mutated": False,
            "article_mutated": False,
        })
    decision_path = root / "closeout" / "decision_registry.csv"
    atomic_write_csv(decision_path, decisions)

    by_fold = []
    for fold in (1, 2, 3):
        rows = [row for row in decisions if int(row["fold"]) == fold]
        by_fold.append({
            "scope": f"fold_{fold}",
            "n_rows": len(rows),
            "mean_operational_pricefm_AQL": mean(rows, "operational_pricefm_AQL"),
            "mean_current_qdesn_AQL": mean(rows, "current_qdesn_AQL"),
            "mean_cached_pricefm_AQL": mean(rows, "cached_pricefm_AQL"),
            "n_operational_beats_current_qdesn": sum(bool(row["operational_beats_current_qdesn"]) for row in rows),
            "n_operational_beats_cached_pricefm": sum(bool(row["operational_beats_cached_pricefm"]) for row in rows),
            "n_dual_gate_pass": sum(bool(row["dual_promotion_gate_pass"]) for row in rows),
        })
    by_fold.append({
        "scope": "all",
        "n_rows": len(decisions),
        "mean_operational_pricefm_AQL": mean(decisions, "operational_pricefm_AQL"),
        "mean_current_qdesn_AQL": mean(decisions, "current_qdesn_AQL"),
        "mean_cached_pricefm_AQL": mean(decisions, "cached_pricefm_AQL"),
        "n_operational_beats_current_qdesn": sum(bool(row["operational_beats_current_qdesn"]) for row in decisions),
        "n_operational_beats_cached_pricefm": sum(bool(row["operational_beats_cached_pricefm"]) for row in decisions),
        "n_dual_gate_pass": sum(bool(row["dual_promotion_gate_pass"]) for row in decisions),
    })
    aggregate_path = root / "closeout" / "aggregate_summary.csv"
    atomic_write_csv(aggregate_path, by_fold)
    overall = by_fold[-1]
    report = f"""# PriceFM operational public-architecture full-shot closeout

## Contract

- Surface: fixed-CET normalized, 365-day fold-aligned test windows.
- Architecture: public PriceFM graph-gated four-expert model, 341,044 parameters.
- Selection: validation only; cell-specific primary and region-global sensitivity.
- Test role: one-time audit after winner-manifest hashes were frozen.
- Registry and article mutation: blocked.

## Result

| Quantity | Value |
|---|---:|
| Region-fold rows | {overall['n_rows']} |
| Mean operational PriceFM AQL | {overall['mean_operational_pricefm_AQL']:.6f} |
| Mean current Q-DESN AQL | {overall['mean_current_qdesn_AQL']:.6f} |
| Mean cached PriceFM AQL | {overall['mean_cached_pricefm_AQL']:.6f} |
| Operational PriceFM beats current Q-DESN | {overall['n_operational_beats_current_qdesn']} / 114 |
| Operational PriceFM beats cached PriceFM | {overall['n_operational_beats_cached_pricefm']} / 114 |
| Dual promotion gate passes | {overall['n_dual_gate_pass']} / 114 |

No registry or manuscript file was changed. Any promotion requires a separate, explicit review of the frozen decision rows and prediction artifacts.
"""
    report_path = root / "closeout" / "report.md"
    atomic_write_text(report_path, report)
    summary = {
        "status": "completed_read_only",
        "decision_registry": str(decision_path),
        "decision_registry_sha256": sha256_file(decision_path),
        "aggregate_summary": str(aggregate_path),
        "aggregate_summary_sha256": sha256_file(aggregate_path),
        "report": str(report_path),
        "report_sha256": sha256_file(report_path),
        "n_dual_promotion_gate_pass": overall["n_dual_gate_pass"],
        "registry_mutated": False,
        "article_mutated": False,
    }
    atomic_write_json(root / "closeout" / "summary.json", summary)
    return summary


def main() -> None:
    args = parser().parse_args()
    result = closeout(Path(args.artifact_root).resolve(), Path(args.qdesn_registry).resolve())
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
