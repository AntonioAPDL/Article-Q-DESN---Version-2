#!/usr/bin/env python3.11
"""Focused contracts for the GloFAS semantic-confirmation preparer."""

from __future__ import annotations

import csv
import importlib.util
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/436_prepare_glofas_part1_joint_al_semantic_confirmation.py"
spec = importlib.util.spec_from_file_location("semantic_confirmation", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

assert module.SOURCE_JOB == "cert_part1_fit_joint_al_all7"
assert module.TARGET_JOB == "semantic_part1_fit_joint_al_all7"

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    trace = root / "trace.csv"
    with trace.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=("global_iter", "value"))
        writer.writeheader()
        for iteration in range(1, 401):
            writer.writerow({"global_iter": iteration, "value": iteration / 400})
    module.validate_trace(trace)

    bad = root / "bad.csv"
    bad.write_text("global_iter,value\n1,0\n3,0\n")
    try:
        module.validate_trace(bad)
    except RuntimeError:
        pass
    else:
        raise AssertionError("A discontinuous source trace must fail closed")

    source = root / "source.txt"
    destination = root / "nested/destination.txt"
    source.write_text("semantic-confirmation\n")
    row = module.link_verified(source, destination)
    assert destination.read_text() == source.read_text()
    assert row["sha256"] == module.sha256(source)
    assert row["bytes"] == source.stat().st_size

print("GLOFAS_QUANTILE_ROOT_CAUSE_LAUNCHERS_TEST_PASS")
