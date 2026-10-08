#!/usr/bin/env python3.11
"""Health and integrity checker for the GloFAS 19-fit correction DAG."""

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


def marker_state(root: Path, job_id: str) -> str:
    for state in ("failed", "running", "completed"):
        if (root / "status" / f"{job_id}.{state}").exists():
            return state
    return "pending"


def read_one_csv(path: Path) -> dict[str, str]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(f"Expected one row in {path}, found {len(rows)}")
    return rows[0]


def truthy(value: object) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    root = (repo / args.runtime_root).resolve() if not Path(args.runtime_root).is_absolute() else Path(args.runtime_root).resolve()
    manifest_path = root / "configs/correction_job_manifest.json"
    contract = json.loads((root / "configs/correction_contract.json").read_text())
    if sha256(manifest_path) != contract["manifest_sha256"]:
        raise SystemExit("Manifest hash mismatch")
    jobs = json.loads(manifest_path.read_text())
    rows: list[dict[str, object]] = []
    for job in jobs:
        job_id = str(job["job_id"])
        current = marker_state(root, job_id)
        record: dict[str, object] = {
            "job_id": job_id, "lane": job["lane"], "action": job["action"],
            "model_family": job["model_family"], "tau": job["tau"], "state": current,
            "iterations": "", "converged": "", "terminal_certificate_passed": "",
            "artifact_contract_ok": False,
        }
        if current == "completed":
            execution = root / "logs" / f"{job_id}_execution_contract.csv"
            if not execution.exists():
                raise RuntimeError(f"Missing execution contract for completed job {job_id}")
            contract_row = read_one_csv(execution)
            if job["action"] == "fit":
                fit_path = root / "objects" / f"{job_id}_fit.rds"
                trace_path = root / "traces" / f"{job_id}_trace.csv"
                if not fit_path.exists() or not trace_path.exists():
                    raise RuntimeError(f"Missing fit or trace for completed fit {job_id}")
                with trace_path.open(newline="") as handle:
                    trace_rows = sum(1 for _ in csv.DictReader(handle))
                iterations = int(float(contract_row.get("iterations", "0") or 0))
                record.update({
                    "iterations": iterations,
                    "converged": truthy(contract_row.get("converged")),
                    "terminal_certificate_passed": truthy(contract_row.get("terminal_certificate_passed")),
                    "artifact_contract_ok": (
                        iterations == 200 and trace_rows == 200 and
                        truthy(contract_row.get("fixed_iterations_requested")) and
                        truthy(contract_row.get("full_state_convergence_requested")) and
                        contract_row.get("fit_sha256") == sha256(fit_path)
                    ),
                })
            else:
                fit_id = str(job["dependencies"][0])
                fit_path = root / "objects" / f"{fit_id}_fit.rds"
                retained = Path(contract_row.get("retained_fit", contract_row.get("retained_fit_path", "")))
                expected = contract_row.get("retained_fit_sha256", "")
                record["artifact_contract_ok"] = (
                    fit_path.exists() and retained.exists() and expected == sha256(fit_path) == sha256(retained)
                )
        rows.append(record)

    counts = {state: sum(row["state"] == state for row in rows) for state in ("completed", "running", "failed", "pending")}
    fits = [row for row in rows if row["action"] == "fit"]
    promotable = sum(
        row["state"] == "completed" and row["artifact_contract_ok"] and
        row["converged"] and row["terminal_certificate_passed"]
        for row in fits
    )
    summary = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": str(root), "total": len(rows), **counts,
        "left": len(rows) - counts["completed"],
        "fit_total": len(fits), "fit_promotable": promotable,
        "fit_completed_not_certified": sum(row["state"] == "completed" for row in fits) - promotable,
        "status": "complete_and_certified" if counts["completed"] == len(rows) and promotable == len(fits) else
                  "failed" if counts["failed"] else "running_or_pending",
    }
    with (root / "tables/correction_health_latest.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (root / "tables/correction_health_summary_latest.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
