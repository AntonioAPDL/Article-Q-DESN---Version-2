#!/usr/bin/env python3.11
"""Self-contained contract tests for the Part 4 joint release controller."""

from __future__ import annotations

import importlib.util
import json
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
    assert contract["quadrature_nodes"] == [4, 8, 12, 16, 24]
    assert contract["quadrature_tolerance"] == 1.0e-6
    assert set(contract["source_hashes"]) == {
        "application/R/latent_path_vb_joint.R",
        "application/R/latent_path_vb_exal.R",
        "application/R/joint_exqdesn_exact_structured_inference.R",
        "application/R/glofas_part4_exal_inner_audit.R",
        "application/R/glofas_part3_partitioned_rhs.R",
        "application/scripts/389_continue_glofas_part4_joint_fit.R",
        "application/scripts/413_launch_glofas_part4_joint_continuation.py",
    }

    completed = output / "status/part4_joint_al_continuation_b01.completed"
    completed.write_text("converged=TRUE\nouter_iterations=6\n")
    output_trace = output / "traces/part4_joint_al_continuation_b01_trace.csv"
    output_trace.write_text("outer_iteration\n1\n2\n3\n4\n5\n6\n")
    assert MODULE.completed_outer_iteration(completed, output_trace, 5, 5) == 6

    completed.write_text("converged=TRUE\nouter_iterations=10\n")
    try:
        MODULE.completed_outer_iteration(completed, output_trace, 5, 5)
    except RuntimeError as error:
        assert "marker/trace" in str(error)
    else:
        raise AssertionError("A completion marker/trace mismatch was accepted")

    completed.write_text("converged=TRUE\nouter_iterations=11\n")
    output_trace.write_text("outer_iteration\n1\n2\n3\n4\n5\n11\n")
    try:
        MODULE.completed_outer_iteration(completed, output_trace, 5, 5)
    except RuntimeError as error:
        assert "outside" in str(error)
    else:
        raise AssertionError("A continuation exceeding its requested budget was accepted")

    def fake_worker(command, cwd, env, stdout, stderr):
        def value(flag):
            return command[command.index(flag) + 1]

        output_root = Path(value("--output_runtime_root"))
        output_job = value("--output_job_id")
        (output_root / "objects" / f"{output_job}_fit_side.rds").write_text("continued fit\n")
        (output_root / "traces" / f"{output_job}_trace.csv").write_text(
            "outer_iteration\n1\n2\n3\n4\n5\n6\n"
        )
        (output_root / "status" / f"{output_job}.completed").write_text(
            "converged=TRUE\n"
            "rhs_release_qualified=TRUE\n"
            "outer_iterations=6\n"
            "executed_additional_outer_iterations=1\n"
        )
        return 0

    original_call = MODULE.subprocess.call
    MODULE.subprocess.call = fake_worker
    try:
        assert MODULE.run(
            REPO, Path(contract["contract_path"]), contract["contract_sha256"]
        ) == 0
    finally:
        MODULE.subprocess.call = original_call
    health = json.loads((output / "status/part4_joint_al_controller_health.json").read_text())
    terminal = json.loads((output / "status/part4_joint_al_controller.completed").read_text())
    assert health["cumulative_outer_iterations"] == 6
    assert health["requested_additional_outer_iterations"] == 5
    assert health["executed_additional_outer_iterations"] == 1
    assert terminal["cumulative_outer_iterations"] == 6

    try:
        MODULE.prepare(
            REPO, source, root / "too_short", "al", job,
            max_cumulative=8, batch_size=3,
        )
    except RuntimeError as error:
        assert "RHS release and response" in str(error)
    else:
        raise AssertionError("A warmup-only continuation ceiling was accepted")

    certificate = root / "certificate"
    for sub in ("status", "manifests", "tables"):
        (certificate / sub).mkdir(parents=True, exist_ok=True)
    (certificate / "status/certificate.completed").write_text(
        "READY_FOR_TARGETED_JOINT_EXAL_CORRECTION\n"
    )
    (certificate / "manifests/quadrature_contract.csv").write_text(
        "candidate_nodes,tolerance\n\"4,8,12,16,24\",0.000001\n"
    )
    (certificate / "tables/quadrature_certificate.csv").write_text(
        "source,passed\nY,TRUE\nG,TRUE\n"
    )
    certificate_manifest = certificate / "manifests/quadrature_output_manifest.csv"
    certificate_manifest.write_text(
        "relative_path,sha256\n"
        f"tables/quadrature_certificate.csv,{MODULE.sha256(certificate / 'tables/quadrature_certificate.csv')}\n"
        f"manifests/quadrature_contract.csv,{MODULE.sha256(certificate / 'manifests/quadrature_contract.csv')}\n"
    )
    exal_contract = MODULE.prepare(
        REPO, source, root / "exal_output", "exal", job,
        max_cumulative=20, batch_size=5,
        quadrature_certificate_root=certificate,
    )
    assert exal_contract["schema_version"] == "glofas_part4_joint_bounded_continuation_v4"
    assert exal_contract["quadrature_certificate_root"] == str(certificate.resolve())
    assert exal_contract["quadrature_certificate_manifest_rows"] == 2

    try:
        MODULE.prepare(
            REPO, source, root / "exal_without_certificate", "exal", job,
            max_cumulative=20, batch_size=5,
        )
    except RuntimeError as error:
        assert "certificate" in str(error)
    else:
        raise AssertionError("An uncertified joint exAL continuation was accepted")

print("GLOFAS_PART4_JOINT_RELEASE_CONTROLLER_TEST_PASS")
