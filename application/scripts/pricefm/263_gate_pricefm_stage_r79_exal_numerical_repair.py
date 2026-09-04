#!/usr/bin/env python3
"""Gate an R76 retry from R77 evidence and the installed structured-exAL source."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R77 = DATA / "authoritative/pricefm_stage_r77_exal_failure_atlas_20260904"
RUNTIME = DATA / "runtime_libraries/exdqlm_pricefm_r75_large_n_gig_repair/pricefm_stage_r75_large_n_gig_repair_manifest.json"
OUTPUT = DATA / "authoritative/pricefm_stage_r79_exal_numerical_repair_gate_20260904"
EXPECTED_STRUCTURED_SHA = "50d69262c22fef169a0d608783b60ffb8b1bd9f4a0b0b1818d6f6c7137d01091"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r77-dir", type=Path, default=R77)
    p.add_argument("--runtime-manifest", type=Path, default=RUNTIME)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--force", action="store_true")
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict[str, Any]:
    r77_summary_path = args.r77_dir / "summary.json"
    eligibility_path = args.r77_dir / "pricefm_stage_r77_retry_eligibility.csv"
    r77 = json.loads(r77_summary_path.read_text())
    eligibility = pd.read_csv(eligibility_path)
    runtime = json.loads(args.runtime_manifest.read_text())
    source = Path(runtime["patched_source"]) / "R/exal_sigmagam_structured.R"
    text = source.read_text()
    required_flow = {
        "adaptive_grid": "eta_grid <- seq(lo, hi, length.out = grid_size)",
        "coarse_grid_fallback": "eta_grid <- coarse",
        "all_nonfinite_abort": "has no finite gamma grid",
        "stats_not_persisted": "failure_diagnostics.json" not in text,
    }
    exact_source = sha256(source) == EXPECTED_STRUCTURED_SHA
    unresolved = int(r77.get("unresolved_aggregate_contract_failures", -1))
    failed_stats_available = False
    general_repair_defined = False
    successful_regression_equivalence_checked = False
    retry_authorized = all([
        exact_source,
        all(bool(value) for value in required_flow.values()),
        unresolved == 0,
        failed_stats_available,
        general_repair_defined,
        successful_regression_equivalence_checked,
    ])
    gates = pd.DataFrame([
        {"gate": "r77_failure_atlas_complete", "passed": r77.get("status") == "failure_atlas_complete_retry_blocked", "observed": r77.get("status")},
        {"gate": "exact_r75_structured_source", "passed": exact_source, "observed": sha256(source)},
        {"gate": "adaptive_and_coarse_grid_paths_present", "passed": all(bool(v) for v in required_flow.values()), "observed": required_flow},
        {"gate": "failed_component_observed_for_all_atoms", "passed": unresolved == 0, "observed": f"{unresolved} unresolved"},
        {"gate": "failed_sufficient_statistics_persisted", "passed": failed_stats_available, "observed": "not written by R76"},
        {"gate": "general_numerical_repair_defined", "passed": general_repair_defined, "observed": "blocked pending diagnostic replay"},
        {"gate": "successful_atom_regression_equivalence", "passed": successful_regression_equivalence_checked, "observed": "not applicable before repair"},
        {"gate": "r80_retry_authorized", "passed": retry_authorized, "observed": 14 if retry_authorized else 0},
        {"gate": "test_registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        if not args.force:
            raise FileExistsError(output)
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    gates.to_csv(output / "pricefm_stage_r79_numerical_repair_gates.csv", index=False)
    questions = pd.DataFrame([
        {"priority": 1, "question": "Which terminal field is non-finite in each aggregate-contract failure?", "evidence": "requires R78-instrumented diagnostic replay", "status": "open"},
        {"priority": 2, "question": "Which sufficient-statistic term makes every gamma-grid log weight non-finite?", "evidence": "requires compact stats capture at package boundary", "status": "open"},
        {"priority": 3, "question": "Can one general repair preserve successful-atom predictions?", "evidence": "requires fixture plus successful regression comparisons", "status": "open"},
        {"priority": 4, "question": "Does the repair complete all 14 atoms without changing scientific specifications?", "evidence": "bounded R80 retry only after gates 1-3", "status": "blocked"},
    ])
    questions.to_csv(output / "pricefm_stage_r79_open_numerical_questions.csv", index=False)
    sources = [Path(__file__).resolve(), r77_summary_path.resolve(), eligibility_path.resolve(),
               args.runtime_manifest.resolve(), source.resolve()]
    pd.DataFrame([{"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size}
                  for path in sources]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "numerical_repair_not_identified_retry_blocked",
        "failed_atoms": int(len(eligibility)), "retry_atoms_authorized": 0,
        "unresolved_failure_components": unresolved,
        "failed_sufficient_statistics_available": False,
        "next_action": "instrumented diagnostic replay before any production retry",
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (output / "pricefm_stage_r79_numerical_repair_report.md").write_text(
        "# PriceFM Stage-R79 Numerical Repair Gate\n\n"
        "The R75 implementation already evaluates an adaptive eta grid and falls back to a "
        "coarse grid. Widening the same grid is therefore not an evidence-backed repair. R76 did "
        "not retain failed sufficient statistics and thirteen failures do not identify the failed "
        "terminal field. R80 remains blocked. The next permissible execution is an instrumented, "
        "non-selective diagnostic replay, followed by a general repair and successful-atom "
        "regression equivalence checks. No test, registry, or article access is authorized.\n"
    )
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
