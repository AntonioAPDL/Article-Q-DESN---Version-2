#!/usr/bin/env python3.11
"""Focused contracts for the Search III Part 1-4 dependency closure."""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prepare = load("search3_prepare", "application/scripts/439_prepare_glofas_search3_dependency_closure.py")
launch = load("search3_launch", "application/scripts/440_launch_glofas_search3_dependency_closure.py")


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selection_rows() -> list[dict[str, object]]:
    base = {
        "adoption_status": "adopted", "scientific_gate_pass": "True",
        "selection_program": "search3_rainy_season", "selection_schema_version": "1",
        "source_head": "abc", "candidate_manifest_sha256": "c" * 64,
        "confirmation_aggregate_sha256": "a" * 64, "adoption_decision_sha256": "d" * 64,
    }
    return [
        {**base, "component": "reference", "candidate_id": "search3_ref_001",
         "canonical_seed": "20260512", "m0": "40", "rhs_zeta2_fixed": "",
         "adoption_action": "retain_search2_incumbent"},
        {**base, "component": "discrepancy", "candidate_id": "search3_dis_007",
         "canonical_seed": "20261521", "m0": "60", "rhs_zeta2_fixed": "16",
         "adoption_action": "adopt_search3_challenger"},
    ]


with tempfile.TemporaryDirectory(prefix="glofas_search3_closure_test_") as tmp:
    root = Path(tmp)
    selection = root / "selection.csv"
    write_csv(selection, selection_rows())
    checked = prepare.validate_search3_selection(selection)
    assert checked["selection_program"] == "search3_rainy_season"
    assert checked["components"]["reference"]["m0"] == 40.0

    bad = selection_rows()
    bad[0]["m0"] = "25"
    bad_path = root / "bad_selection.csv"
    write_csv(bad_path, bad)
    try:
        prepare.validate_search3_selection(bad_path)
        raise AssertionError("Search II m0=25 was incorrectly admitted as Search III")
    except RuntimeError as error:
        assert "m0" in str(error)

    gate = root / "gate"
    for sub in ("configs", "status", "logs", "objects", "traces", "tables"):
        (gate / sub).mkdir(parents=True, exist_ok=True)
    job_id = "semantic_final_part1_fit_joint_al_all7"
    fit = gate / f"objects/{job_id}_fit.rds"
    trace = gate / f"traces/{job_id}_cumulative_trace.csv"
    fit.write_bytes(b"fit")
    trace.write_text("global_iter\n800\n", encoding="utf-8")
    manifest = [{
        "job_id": job_id, "part": "part1", "action": "fit", "model_family": "joint_al",
        "tau": "all7", "dependencies": [], "required_certified_dependencies": [],
        "source_fit_sha256": "s" * 64, "source_cumulative_trace_sha256": "t" * 64,
        "expected_source_iterations": 600, "expected_cumulative_iterations": 800,
    }]
    manifest_path = gate / "configs/certification_continuation_job_manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    contract = {
        "schema_version": "glofas_part1_joint_al_final_confirmation_v1",
        "manifest_sha256": digest(manifest_path),
        "iteration_contract": {"source_iterations": 600, "continuation_iterations": 200,
                               "cumulative_iterations": 800},
        "decision_contract": {"if_uncertified": "quarantine_part1_joint_al_no_further_continuation"},
    }
    contract_path = gate / "configs/certification_continuation_contract.json"
    contract_path.write_text(json.dumps(contract), encoding="utf-8")
    (gate / f"status/{job_id}.completed").write_text("done\n", encoding="utf-8")
    execution = [{
        "fit_path": str(fit), "fit_sha256": digest(fit),
        "cumulative_trace_path": str(trace), "cumulative_trace_sha256": digest(trace),
        "source_iterations": "600", "segment_iterations": "200", "cumulative_iterations": "800",
        "source_fit_sha256": "s" * 64, "source_cumulative_trace_sha256": "t" * 64,
        "restart_kind": "exact_local_state_available", "prior_source_sha256": "p" * 64,
        "prior_continuation_sha256": "p" * 64, "certified": "FALSE",
    }]
    write_csv(gate / f"logs/{job_id}_execution_contract.csv", execution)

    gate_contract = prepare.validate_gate_contract(gate)
    assert gate_contract["state_at_prepare"] == "completed"
    classification = launch.classify_final_gate({"final_part1_diagnostic_gate": gate_contract})
    assert classification["classification"] == "quarantined_after_hard_stop"
    assert classification["posterior_target_unchanged"] is True

source = (ROOT / "application/scripts/404_prepare_glofas_post_search2_runtime.py").read_text(encoding="utf-8")
for expected in (
    'parser.add_argument("--max-iter", type=int, default=200)',
    'parser.add_argument("--min-iter", type=int, default=200)',
    'parser.add_argument("--tol", type=float, default=1.0e-4)',
    'parser.add_argument("--min-beta-updates", type=int, default=180)',
):
    assert expected in source

print("Search III dependency-closure contract tests passed")
