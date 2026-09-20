#!/usr/bin/env python3.11
"""Synthetic contract tests for GloFAS correction and continuation launchers."""

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, REPO / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare_module = load("glofas_prepare_correction", "application/scripts/410_prepare_glofas_quantile_integrity_correction.py")
launch_module = load("glofas_launch_correction", "application/scripts/411_launch_glofas_quantile_integrity_correction.py")
continuation_module = load("glofas_part4_controller", "application/scripts/413_launch_glofas_part4_joint_continuation.py")

assert prepare_module.qslug(0.05) == "q0p05"
assert prepare_module.qslug(0.50) == "q0p50"

with tempfile.TemporaryDirectory(prefix="glofas_integrity_launcher_") as temporary:
    temporary = Path(temporary)
    source = temporary / "source"
    output = temporary / "output"
    part4 = temporary / "part4"
    for sub in ("status", "configs", "objects"):
        (source / sub).mkdir(parents=True, exist_ok=True)
    part4.mkdir()
    for index in range(133):
        (source / "status" / f"job_{index:03d}.completed").write_text("completed\n")
    for name in (
        "part1_post_search2_design_cache.rds", "part2_final_dec25_design_cache.rds",
        "part3_final_dec25_design_cache.rds", "part123_base_config_frozen.yaml",
        "full_data_rhs_calibration.csv",
    ):
        (source / "configs" / name).write_text(name + "\n")
    for part in ("part1", "part2", "part3"):
        (source / "objects" / f"{part}_normal_rhs_driver_bank.rds").write_text(part + "\n")
    taus = ("q0p05", "q0p20", "q0p35", "q0p50", "q0p65", "q0p80", "q0p95")
    for part in ("part1", "part2"):
        for family in ("independent_al", "independent_exal"):
            for tau in taus:
                (source / "objects" / f"{part}_fit_{family}_{tau}_fit.rds").write_text(f"{part} {family} {tau}\n")
    for tau in taus:
        (source / "objects" / f"part3_fit_independent_al_{tau}_fit.rds").write_text(tau + "\n")

    subprocess.check_call([
        "/usr/bin/python3.11", str(REPO / "application/scripts/410_prepare_glofas_quantile_integrity_correction.py"),
        "--source-root", str(source), "--part4-root", str(part4),
        "--runtime-root", str(output), "--workers", "7",
    ], cwd=REPO)
    jobs = json.loads((output / "configs/correction_job_manifest.json").read_text())
    assert len(jobs) == 38
    assert sum(job["action"] == "fit" for job in jobs) == 19
    assert sum(job["action"] == "forecast" for job in jobs) == 19
    assert sum(job["model_family"] == "joint_exal" and job["action"] == "fit" for job in jobs) == 2
    assert sum(job["lane"] == "part3" and job["action"] == "fit" for job in jobs) == 1
    for job in jobs:
        if job["action"] == "fit":
            command = job["command"]
            assert command[command.index("--max_iter") + 1] == "200"
            assert command[command.index("--min_iter") + 1] == "200"
            assert command[command.index("--fixed_iterations") + 1] == "true"
            assert command[command.index("--full_state_convergence") + 1] == "true"
    verified_jobs, _ = launch_module.verify_contract(REPO, output)
    assert len(verified_jobs) == 38

    p4_source = temporary / "p4_source"
    p4_output = temporary / "p4_output"
    source_job = "toy_joint_al"
    for sub in ("status", "objects", "traces", "configs"):
        (p4_source / sub).mkdir(parents=True, exist_ok=True)
    (p4_source / "status" / f"{source_job}.completed").write_text("completed\n")
    (p4_source / "objects" / f"{source_job}_fit_side.rds").write_text("fit\n")
    (p4_source / "objects/part4_shared_design_truth_free.rds").write_text("design\n")
    (p4_source / "objects/part4_scoring_panel_sidecar.rds").write_text("sidecar\n")
    (p4_source / "configs/part4_model_manifest.csv").write_text("run_id\n")
    (p4_source / "traces" / f"{source_job}_trace.csv").write_text(
        "outer_iteration\n1\n2\n3\n4\n5\n"
    )
    contract = continuation_module.prepare(REPO, p4_source, p4_output, "al", source_job, 20, 5)
    assert contract["initial_outer_iterations"] == 5
    assert contract["max_cumulative_outer_iterations"] == 20
    assert contract["terminal_consecutive_passes"] == 3

print("GLOFAS_QUANTILE_INTEGRITY_LAUNCHER_TEST_PASS")
