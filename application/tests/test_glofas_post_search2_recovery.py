#!/usr/bin/env python3
"""Focused tests for certificate-based post-Search-II runtime recovery."""

import importlib.util
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


recovery = load(
    "glofas_post_search2_recovery",
    ROOT / "application/scripts/408_recover_glofas_post_search2_runtime.py",
)


source_command = json.dumps([
    "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
    "--runtime_root", "/old/runtime", "--job_id", "fit_a", "--job_type", "fit",
    "--base_config", "/old/config.yaml", "--max_iter", "100", "--tol", "0.01",
])
destination_command = json.dumps([
    "Rscript", "application/scripts/403_run_glofas_post_search2_support_job.R",
    "--runtime_root", "/new/runtime", "--job_id", "fit_a", "--job_type", "fit",
    "--base_config", "/new/config.yaml", "--max_iter", "100", "--tol", "0.01",
])
row = {
    "job_id": "fit_a", "part": "part1", "stage": "fit", "model_family": "normal_rhs_vb",
    "tau": "", "dependencies": "ridge_a", "worker_slots": "1", "role": "test",
    "command_json": source_command,
}
row_new = {**row, "command_json": destination_command}
recovery.validate_job_contracts([row], [row_new], {"fit_a"})

bad = {**row_new, "tau": "0.50"}
try:
    recovery.validate_job_contracts([row], [bad], {"fit_a"})
except SystemExit as exc:
    assert "mismatch" in str(exc)
else:
    raise AssertionError("scientific job mismatch was accepted")

with tempfile.TemporaryDirectory(prefix="glofas_post_search2_recovery_") as tmp:
    tmp = Path(tmp)
    source_runtime = tmp / "source"
    source_part4 = tmp / "source_part4"
    for path in (source_runtime / "objects", source_runtime / "logs", source_part4 / "objects"):
        path.mkdir(parents=True, exist_ok=True)
    (source_runtime / "objects" / "fit_a_fit.rds").write_bytes(b"not-read-in-unit-test")
    (source_runtime / "logs" / "fit_a.log").write_text("done\n", encoding="utf-8")
    artifacts = recovery.required_artifacts(row, source_runtime, source_part4)
    names = {str(relative) for _, relative, _ in artifacts}
    assert "objects/fit_a_fit.rds" in names
    assert "logs/fit_a.log" in names

    status = source_runtime / "status"
    status.mkdir()
    (status / "fit_a.completed").write_text("done\n", encoding="utf-8")
    assert recovery.completed_job_ids(source_runtime, [row]) == {"fit_a"}

print("GLOFAS_POST_SEARCH2_RECOVERY_TEST_PASS")
