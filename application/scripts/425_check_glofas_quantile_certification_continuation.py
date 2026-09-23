#!/usr/bin/env python3.11
"""Health and artifact checker for GloFAS certification continuations."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def state(root: Path, job_id: str) -> str:
    for value in ("failed", "completed", "blocked", "running"):
        if (root / "status" / f"{job_id}.{value}").exists():
            return value
    return "pending"


def truth(value: str) -> bool:
    return str(value).strip().lower() in ("true", "1", "yes")


def forecast_contract_valid(root: Path, job: dict[str, object], result: dict[str, str]) -> bool:
    retained_value = result.get("retained_fit_path") or result.get("retained_fit")
    retained_hash = result.get("retained_fit_sha256", "")
    output_values = [
        value for value in result.get("output_paths", "").split("|") if value
    ]
    if not retained_value or not retained_hash or not output_values:
        return False
    retained = Path(retained_value)
    dependencies = list(job.get("dependencies", []))
    if len(dependencies) != 1:
        return False
    dependency = str(dependencies[0])
    expected_fit = root / "objects" / f"{dependency}_fit.rds"
    return (
        retained.is_file() and expected_fit.is_file() and
        retained.resolve() == expected_fit.resolve() and
        sha256(retained) == retained_hash and
        all(Path(value).is_file() for value in output_values) and
        (root / "status" / f"{dependency}.certified").is_file()
    )


def expected_iterations(
    job: dict[str, object], contract: dict[str, object]
) -> tuple[int, int, int]:
    iteration_contract = dict(contract["iteration_contract"])
    source_value = job.get(
        "expected_source_iterations", iteration_contract.get("source_iterations")
    )
    if source_value is None:
        raise RuntimeError(f"Missing source-iteration contract for {job.get('job_id')}")
    source = int(source_value)
    segment = int(iteration_contract["continuation_iterations"])
    cumulative = int(job.get("expected_cumulative_iterations", source + segment))
    if source < 1 or segment < 1 or cumulative != source + segment:
        raise RuntimeError(f"Invalid iteration contract for {job.get('job_id')}")
    return source, segment, cumulative


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    args = parser.parse_args()
    root = Path(args.runtime_root).resolve()
    manifest_path = root / "configs/certification_continuation_job_manifest.json"
    contract_path = root / "configs/certification_continuation_contract.json"
    jobs = json.loads(manifest_path.read_text())
    contract = json.loads(contract_path.read_text())
    manifest_hash_ok = sha256(manifest_path) == contract["manifest_sha256"]
    rows: list[dict[str, object]] = []
    artifact_failures: list[str] = []
    for job in jobs:
        job_id = str(job["job_id"])
        value = state(root, job_id)
        row: dict[str, object] = {
            "job_id": job_id, "part": job["part"], "action": job["action"],
            "model_family": job["model_family"], "tau": job["tau"], "state": value,
            "certified": (root / "status" / f"{job_id}.certified").is_file(),
            "artifact_valid": "",
        }
        if value == "completed":
            execution = root / "logs" / f"{job_id}_execution_contract.csv"
            if not execution.is_file():
                artifact_failures.append(f"{job_id}:missing_execution_contract")
                row["artifact_valid"] = False
            else:
                with execution.open(newline="") as handle:
                    values = list(csv.DictReader(handle))
                if len(values) != 1:
                    artifact_failures.append(f"{job_id}:bad_execution_contract_rows")
                    row["artifact_valid"] = False
                elif job["action"] == "fit":
                    result = values[0]
                    expected_source, expected_segment, expected_cumulative = expected_iterations(
                        job, contract
                    )
                    fit_path = Path(result["fit_path"])
                    cumulative_path = Path(result["cumulative_trace_path"])
                    valid = (
                        fit_path.is_file() and sha256(fit_path) == result["fit_sha256"] and
                        cumulative_path.is_file() and sha256(cumulative_path) == result["cumulative_trace_sha256"] and
                        int(result["source_iterations"]) == expected_source and
                        int(result["segment_iterations"]) == expected_segment and
                        int(result["cumulative_iterations"]) == expected_cumulative and
                        result["source_fit_sha256"] == job["source_fit_sha256"] and
                        result["source_cumulative_trace_sha256"] == job["source_cumulative_trace_sha256"] and
                        result["restart_kind"] == "exact_local_state_available" and
                        result["prior_source_sha256"] == result["prior_continuation_sha256"] and
                        truth(result["certified"]) == bool(row["certified"])
                    )
                    row["artifact_valid"] = valid
                    if not valid:
                        artifact_failures.append(f"{job_id}:fit_contract_invalid")
                else:
                    result = values[0]
                    valid = forecast_contract_valid(root, job, result)
                    row["artifact_valid"] = valid
                    if not valid:
                        artifact_failures.append(f"{job_id}:forecast_fit_binding_invalid")
        rows.append(row)

    counts = {
        key: sum(row["state"] == key for row in rows)
        for key in ("completed", "running", "failed", "blocked", "pending")
    }
    fit_rows = [row for row in rows if row["action"] == "fit"]
    certified_count = sum(bool(row["certified"]) for row in fit_rows)
    all_artifacts_valid = not artifact_failures and all(
        row["artifact_valid"] is True for row in rows if row["state"] == "completed"
    )
    if counts["failed"]:
        status = "FAILED"
    elif counts["running"] or counts["pending"]:
        status = "RUNNING_OR_PENDING"
    elif counts["blocked"] or certified_count < len(fit_rows):
        status = "COMPLETE_WITH_UNCERTIFIED_FITS"
    elif counts["completed"] == len(rows) and all_artifacts_valid and manifest_hash_ok:
        status = "COMPLETE_AND_CERTIFIED"
    else:
        status = "COMPLETE_WITH_ARTIFACT_ERRORS"
    payload = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": str(root), "status": status, "total": len(rows), **counts,
        "left": counts["running"] + counts["pending"],
        "fit_total": len(fit_rows), "fit_certified": certified_count,
        "manifest_hash_ok": manifest_hash_ok,
        "all_completed_artifacts_valid": all_artifacts_valid,
        "artifact_failures": artifact_failures,
    }
    (root / "tables").mkdir(exist_ok=True)
    with (root / "tables/certification_continuation_health_latest.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (root / "tables/certification_continuation_health_summary_latest.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )
    print(json.dumps(payload, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
