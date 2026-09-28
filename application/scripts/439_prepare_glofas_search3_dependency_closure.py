#!/usr/bin/env python3.11
"""Prepare the complete Search III GloFAS Part 1-4 dependency closure."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


EXPECTED_SELECTION = {
    "reference": {
        "candidate_id": "search3_ref_001",
        "canonical_seed": "20260512",
        "m0": 40.0,
        "rhs_zeta2_fixed": None,
        "adoption_action": "retain_search2_incumbent",
    },
    "discrepancy": {
        "candidate_id": "search3_dis_007",
        "canonical_seed": "20261521",
        "m0": 60.0,
        "rhs_zeta2_fixed": 16.0,
        "adoption_action": "adopt_search3_challenger",
    },
}
EXPECTED_COUNTS = {"part1": 37, "part2": 37, "part3": 37, "part4": 21, "shared": 1}
ITERATION_CONTROLS = {
    "max_iter": 200,
    "min_iter": 200,
    "tol": 1.0e-4,
    "freeze_beta_warmup_iters": 20,
    "min_beta_updates": 180,
    "n_draws": 500,
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo_root() / path).resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def truth(value: object) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes"}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_search3_selection(path: Path) -> dict[str, object]:
    rows = read_csv(path)
    if len(rows) != 2 or {row.get("component") for row in rows} != set(EXPECTED_SELECTION):
        raise RuntimeError("Search III selection must contain exactly reference and discrepancy")
    shared_fields = (
        "source_head", "candidate_manifest_sha256", "confirmation_aggregate_sha256",
        "adoption_decision_sha256",
    )
    shared_values: dict[str, str] = {}
    for row in rows:
        component = row["component"]
        expected = EXPECTED_SELECTION[component]
        if row.get("selection_program") != "search3_rainy_season":
            raise RuntimeError(f"{component} is not a Search III selection")
        if row.get("selection_schema_version") != "1":
            raise RuntimeError(f"{component} has an unsupported selection schema")
        if row.get("adoption_status") != "adopted" or not truth(row.get("scientific_gate_pass")):
            raise RuntimeError(f"{component} did not pass the frozen adoption gate")
        for field in ("candidate_id", "canonical_seed", "adoption_action"):
            if row.get(field) != str(expected[field]):
                raise RuntimeError(f"{component} {field} differs from the adopted Search III contract")
        if abs(float(row["m0"]) - float(expected["m0"])) > 1.0e-12:
            raise RuntimeError(f"{component} m0 differs from the adopted Search III prior")
        zeta = row.get("rhs_zeta2_fixed", "").strip()
        expected_zeta = expected["rhs_zeta2_fixed"]
        if expected_zeta is None:
            if zeta and zeta.lower() not in {"na", "nan"}:
                raise RuntimeError("Search III reference must use the learned slab policy")
        elif not zeta or abs(float(zeta) - float(expected_zeta)) > 1.0e-12:
            raise RuntimeError("Search III discrepancy must use fixed zeta2=16")
        for field in shared_fields:
            value = row.get(field, "")
            if not value:
                raise RuntimeError(f"Search III selection lacks {field}")
            if field in shared_values and shared_values[field] != value:
                raise RuntimeError(f"Search III rows disagree on {field}")
            shared_values[field] = value
    return {
        "selection_sha256": sha256(path),
        "selection_program": "search3_rainy_season",
        "components": EXPECTED_SELECTION,
        **shared_values,
    }


def validate_gate_contract(root: Path) -> dict[str, object]:
    contract_path = root / "configs/certification_continuation_contract.json"
    manifest_path = root / "configs/certification_continuation_job_manifest.json"
    if not contract_path.is_file() or not manifest_path.is_file():
        raise RuntimeError("Final Part 1 diagnostic gate is missing its frozen contract")
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    jobs = json.loads(manifest_path.read_text(encoding="utf-8"))
    if contract.get("schema_version") != "glofas_part1_joint_al_final_confirmation_v1":
        raise RuntimeError("Unexpected final Part 1 gate schema")
    if sha256(manifest_path) != contract.get("manifest_sha256"):
        raise RuntimeError("Final Part 1 gate manifest hash mismatch")
    if len(jobs) != 1 or jobs[0].get("job_id") != "semantic_final_part1_fit_joint_al_all7":
        raise RuntimeError("Final Part 1 gate must contain exactly the declared diagnostic fit")
    iteration = contract.get("iteration_contract") or {}
    decision = contract.get("decision_contract") or {}
    if int(iteration.get("cumulative_iterations", 0)) != 800:
        raise RuntimeError("Final Part 1 gate does not end at the hard stop of 800")
    if decision.get("if_uncertified") != "quarantine_part1_joint_al_no_further_continuation":
        raise RuntimeError("Final Part 1 gate lacks the required quarantine decision")
    return {
        "runtime_root": str(root),
        "contract_path": str(contract_path),
        "contract_sha256": sha256(contract_path),
        "manifest_path": str(manifest_path),
        "manifest_sha256": sha256(manifest_path),
        "job_id": jobs[0]["job_id"],
        "state_at_prepare": "completed" if (root / f"status/{jobs[0]['job_id']}.completed").is_file() else "incomplete",
    }


def command_value(command: list[str], flag: str) -> str:
    try:
        return command[command.index(flag) + 1]
    except (ValueError, IndexError) as error:
        raise RuntimeError(f"Prepared command lacks {flag}") from error


def validate_prepared_dag(runtime: Path) -> dict[str, object]:
    manifest = runtime / "tables/post_search2_job_manifest.csv"
    execution_path = runtime / "configs/post_search2_execution_contract.json"
    rows = read_csv(manifest)
    execution = json.loads(execution_path.read_text(encoding="utf-8"))
    counts = {part: sum(row["part"] == part for row in rows) for part in EXPECTED_COUNTS}
    if len(rows) != 133 or counts != EXPECTED_COUNTS:
        raise RuntimeError(f"Unexpected dependency DAG dimensions: {counts}")
    if execution.get("jobs_by_part") != EXPECTED_COUNTS or execution.get("n_driver_paths") != 500:
        raise RuntimeError("Execution contract does not match the 133-job, 500-path closure")
    for row in rows:
        command = json.loads(row["command_json"])
        if row["stage"] == "fit" and row["part"] in {"part1", "part2", "part3"}:
            checks = {
                "--max_iter": "200", "--min_iter": "200", "--tol": "0.0001",
                "--freeze_beta_warmup_iters": "20", "--min_beta_updates": "180",
            }
            for flag, expected in checks.items():
                if command_value(command, flag) != expected:
                    raise RuntimeError(f"{row['job_id']} violates {flag}={expected}")
        if row["job_id"] == "part4_prepare_runtime":
            for flag, expected in {
                "--max_iter": "200", "--min_iter": "200", "--tol": "0.0001",
                "--freeze_beta_warmup_iters": "20", "--min_beta_updates": "180",
                "--n_draws": "500",
            }.items():
                if command_value(command, flag) != expected:
                    raise RuntimeError(f"Part 4 preparation violates {flag}={expected}")
    return {
        "job_manifest": str(manifest),
        "job_manifest_sha256": sha256(manifest),
        "execution_contract": str(execution_path),
        "execution_contract_sha256": sha256(execution_path),
        "job_count": len(rows),
        "jobs_by_part": counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--part4-runtime-root", required=True)
    parser.add_argument("--base-config", required=True)
    parser.add_argument("--part4-base-config", default="application/config/glofas_latent_path_al_vb_dec25_main.yaml")
    parser.add_argument("--selected-components", required=True)
    parser.add_argument("--authoritative-input-root", required=True)
    parser.add_argument("--final-part1-gate-runtime", required=True)
    parser.add_argument("--workers", type=int, default=25)
    parser.add_argument("--cpu-pool", default="0-24")
    parser.add_argument("--session-prefix", default="glofas_search3_dependency_closure_20260928")
    parser.add_argument("--seed", type=int, default=20260928)
    args = parser.parse_args()

    runtime = resolve(args.runtime_root)
    part4_runtime = resolve(args.part4_runtime_root)
    selection_path = resolve(args.selected_components)
    gate_root = resolve(args.final_part1_gate_runtime)
    selection = validate_search3_selection(selection_path)
    gate = validate_gate_contract(gate_root)

    command = [
        "python3", "application/scripts/404_prepare_glofas_post_search2_runtime.py",
        "--runtime-root", str(runtime), "--part4-runtime-root", str(part4_runtime),
        "--part4-run-label", part4_runtime.name,
        "--base-config", str(resolve(args.base_config)),
        "--part4-base-config", str(resolve(args.part4_base_config)),
        "--selected-components", str(selection_path),
        "--authoritative-input-root", str(resolve(args.authoritative_input_root)),
        "--workers", str(args.workers), "--cpu-pool", args.cpu_pool,
        "--session-prefix", args.session_prefix,
        "--max-iter", "200", "--min-iter", "200", "--tol", "0.0001",
        "--n-draws", "500", "--seed", str(args.seed), "--forecast-backend", "cpp",
        "--freeze-beta-warmup-iters", "20", "--min-beta-updates", "180",
    ]
    subprocess.run(command, cwd=repo_root(), check=True)
    dag = validate_prepared_dag(runtime)
    base_readiness = runtime / "configs/launch_readiness.json"
    contract = {
        "schema_version": "glofas_search3_dependency_closure_v1",
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo_root(), text=True).strip(),
        "git_branch": subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_root(), text=True).strip(),
        "runtime_root": str(runtime),
        "part4_runtime_root": str(part4_runtime),
        "scientific_contract": {
            "cutoff": "2022-12-25", "forecast_start": "2022-12-26",
            "forecast_end": "2023-01-24", "part4_horizon_days": 28,
            "response_scale": "log1p", "selection_program": "search3_rainy_season",
            "full_refit_required": True,
            "full_refit_reason": "reference m0 changed from Search II 25 to Search III 40 and discrepancy geometry/prior changed",
        },
        "iteration_controls": ITERATION_CONTROLS,
        "resource_contract": {"workers": args.workers, "cpu_pool": args.cpu_pool},
        "selection": selection,
        "final_part1_diagnostic_gate": gate,
        "dag": dag,
        "base_launch_readiness": str(base_readiness),
        "base_launch_readiness_sha256": sha256(base_readiness),
        "launch_policy": "blocked_until_final_part1_gate_is_completed_and_classified",
    }
    contract_path = runtime / "configs/search3_dependency_closure_contract.json"
    contract_path.write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    readiness = {
        "schema_version": "glofas_search3_dependency_closure_readiness_v1",
        "status": "prepared_waiting_for_final_part1_gate" if gate["state_at_prepare"] != "completed" else "ready_for_gate_validation",
        "artifacts": [
            {"path": str(path), "size_bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in (contract_path, base_readiness, selection_path, Path(gate["contract_path"]), Path(gate["manifest_path"]))
        ],
    }
    readiness_path = runtime / "configs/search3_dependency_closure_readiness.json"
    readiness_path.write_text(json.dumps(readiness, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    launch = runtime / "scripts/launch_after_part1_gate.sh"
    launch.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n"
        f"python3.11 application/scripts/440_launch_glofas_search3_dependency_closure.py --runtime-root {shlex.quote(str(runtime))} "
        f"--workers {args.workers} --cpu-pool {shlex.quote(args.cpu_pool)} --session-prefix {shlex.quote(args.session_prefix)} --background\n",
        encoding="utf-8",
    )
    launch.chmod(0o755)
    print(json.dumps({
        "runtime_root": str(runtime), "part4_runtime_root": str(part4_runtime),
        "jobs": dag["job_count"], "jobs_by_part": dag["jobs_by_part"],
        "gate_state": gate["state_at_prepare"], "preparation_state": readiness["status"],
        "contract_sha256": sha256(contract_path),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
