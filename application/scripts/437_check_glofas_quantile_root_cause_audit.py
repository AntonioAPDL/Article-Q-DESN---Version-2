#!/usr/bin/env python3.11
"""Independently verify a completed GloFAS quantile root-cause audit."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_manifest(path: Path) -> tuple[int, list[str]]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    failures = []
    for row in rows:
        artifact = Path(row["path"])
        if not artifact.is_file():
            failures.append(f"missing:{artifact}")
        elif artifact.stat().st_size != int(float(row["size_bytes"])):
            failures.append(f"size:{artifact}")
        elif sha256(artifact) != row["sha256"]:
            failures.append(f"sha256:{artifact}")
    return len(rows), failures


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def truth(value: str) -> bool:
    return value.strip().lower() in ("true", "1", "yes")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    args = parser.parse_args()
    root = Path(args.runtime_root).resolve()
    required = (
        "status/audit.completed",
        "manifests/source_artifact_manifest.csv",
        "manifests/diagnostic_output_manifest.csv",
        "tables/part4_bounded_rhs_solver_validation.csv",
        "tables/issue_registry.csv",
        "tables/search3_adopted_components.csv",
        "reports/root_cause_findings.md",
    )
    missing = [relative for relative in required if not (root / relative).is_file()]
    failures = [f"missing:{relative}" for relative in missing]
    marker = root / "status/audit.completed"
    if marker.is_file() and marker.read_text().strip() != "DIAGNOSTIC_COMPLETE_PRODUCTION_REFIT_NOT_AUTHORIZED":
        failures.append("bad_status_marker")

    source_rows = output_rows = 0
    if not missing:
        source_rows, source_failures = verify_manifest(root / "manifests/source_artifact_manifest.csv")
        output_rows, output_failures = verify_manifest(root / "manifests/diagnostic_output_manifest.csv")
        failures.extend(source_failures)
        failures.extend(output_failures)

        solver = read_rows(root / "tables/part4_bounded_rhs_solver_validation.csv")
        if len(solver) != 4:
            failures.append(f"solver_rows:{len(solver)}")
        for row in solver:
            if not truth(row["rhs_inner_converged"]):
                failures.append(f"solver_not_converged:{row['family']}:{row['component']}")
            if int(row["rhs_inner_iterations"]) > 50:
                failures.append(f"solver_cap:{row['family']}:{row['component']}")
            if float(row["terminal_inferential_relative_change"]) > 1.0e-4:
                failures.append(f"solver_tolerance:{row['family']}:{row['component']}")

        issues = {row["issue_id"]: row for row in read_rows(root / "tables/issue_registry.csv")}
        expected_issues = {
            "QAL_PART3_COUNTER_CONTAMINATION": "root_cause_confirmed_counter_contamination",
            "PART4_JOINT_AL_NESTED_GATE": "root_cause_confirmed_incomplete_rhs_inner_solve",
            "SEARCH3_DISCREPANCY_GEOMETRY": "resolved_adopt_search3_dis_007",
        }
        for issue_id, status in expected_issues.items():
            if issues.get(issue_id, {}).get("status") != status:
                failures.append(f"issue_status:{issue_id}")

        adoption = {
            row["component"]: row["candidate_id"]
            for row in read_rows(root / "tables/search3_adopted_components.csv")
        }
        if adoption != {"reference": "search3_ref_001", "discrepancy": "search3_dis_007"}:
            failures.append(f"search3_adoption:{adoption}")

    payload = {
        "runtime_root": str(root),
        "source_manifest_rows": source_rows,
        "output_manifest_rows": output_rows,
        "failure_count": len(failures),
        "failures": failures,
        "status": "VERIFIED" if not failures else "FAILED",
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0 if not failures else 1)


if __name__ == "__main__":
    main()
