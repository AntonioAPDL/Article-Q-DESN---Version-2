#!/usr/bin/env python3.11
"""Self-contained contract tests for the Part 4 joint release controller."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO / "application/scripts/413_launch_glofas_part4_joint_continuation.py"
SPEC = importlib.util.spec_from_file_location("glofas_part4_release_controller", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


with tempfile.TemporaryDirectory(prefix="glofas_part4_release_controller_") as temporary:
    root = Path(temporary)
    source = root / "source"
    output = root / "output"
    job = "joint_al"
    for sub in ("status", "objects", "traces", "configs"):
        (source / sub).mkdir(parents=True, exist_ok=True)
    (source / "status" / f"{job}.completed").write_text("completed\n")
    (source / "objects" / f"{job}_fit_side.rds").write_text("fit\n")
    (source / "objects/part4_shared_design_truth_free.rds").write_text("design\n")
    (source / "objects/part4_scoring_panel_sidecar.rds").write_text("sidecar\n")
    (source / "configs/part4_model_manifest.csv").write_text("run_id\n")
    (source / "traces" / f"{job}_trace.csv").write_text(
        "outer_iteration\n1\n2\n3\n4\n5\n"
    )

    contract = MODULE.prepare(
        REPO, source, output, "al", job, max_cumulative=20, batch_size=5
    )
    assert contract["initial_outer_iterations"] == 5
    assert contract["inner_workers"] == 7
    assert contract["min_rhs_tau_updates"] == 3
    assert contract["require_post_release"] is True
    assert contract["allow_rhs_schedule_rebase"] is True
    assert contract["max_cumulative_outer_iterations"] == 20
    assert set(contract["source_hashes"]) == {
        "application/R/latent_path_vb_joint.R",
        "application/R/glofas_part3_partitioned_rhs.R",
        "application/scripts/389_continue_glofas_part4_joint_fit.R",
    }

    try:
        MODULE.prepare(
            REPO, source, root / "too_short", "al", job,
            max_cumulative=8, batch_size=3,
        )
    except RuntimeError as error:
        assert "RHS release and response" in str(error)
    else:
        raise AssertionError("A warmup-only continuation ceiling was accepted")

print("GLOFAS_PART4_JOINT_RELEASE_CONTROLLER_TEST_PASS")
