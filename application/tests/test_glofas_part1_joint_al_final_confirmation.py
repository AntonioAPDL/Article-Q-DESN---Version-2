#!/usr/bin/env python3.11
"""Focused tests for the bounded 600-to-800 Part 1 confirmation."""

from __future__ import annotations

import csv
import importlib.util
import math
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/438_prepare_glofas_part1_joint_al_final_confirmation.py"
spec = importlib.util.spec_from_file_location("final_confirmation", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

assert module.SOURCE_JOB == "semantic_part1_fit_joint_al_all7"
assert module.TARGET_JOB == "semantic_final_part1_fit_joint_al_all7"
assert module.SOURCE_ITERATIONS == 600
assert module.TARGET_ITERATIONS == 800

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "progress.csv"
    fields = (
        "iter", "global_iter", "beta_updated", "max_beta_relative_change",
        "max_path_change", "max_latent_change", "max_rhs_change", "monitor",
    )
    rows = []
    for iteration in range(1, 201):
        released = max(0, iteration - 20)
        rows.append({
            "iter": iteration, "global_iter": 400 + iteration,
            "beta_updated": iteration > 20,
            "max_beta_relative_change": 2.0e-6,
            "max_path_change": 1.0e-5,
            "max_latent_change": 1.04e-4 * math.exp(-0.008 * (iteration - 200)),
            "max_rhs_change": 4.65e-4 * math.exp(-0.012 * (iteration - 200)),
            "monitor": -700 + released * 1.0e-4,
        })
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    diagnosis = module.diagnose_progress(path)
    assert diagnosis["final_continuation_authorized"] is True
    assert 100 <= diagnosis["projected_released_updates_to_rhs_tolerance"] <= 150
    assert diagnosis["recent20_rhs_strictly_decreasing"] is True
    assert diagnosis["recent20_monitor_nondecreasing"] is True

    rows[-1]["max_rhs_change"] = 7.0e-4
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    diagnosis = module.diagnose_progress(path)
    assert diagnosis["final_continuation_authorized"] is False

print("GLOFAS_PART1_JOINT_AL_FINAL_CONFIRMATION_TEST_PASS")
