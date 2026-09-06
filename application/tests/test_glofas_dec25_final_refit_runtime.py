#!/usr/bin/env python3
"""Focused tests for Dec25 final-refit manifests, health checks, and packages."""

from __future__ import annotations

import csv
import json
import subprocess
import tarfile
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


with tempfile.TemporaryDirectory(prefix="glofas_dec25_runtime_test_") as tmp:
    root = Path(tmp)
    runtime = root / "runtime"
    package_dir = root / "packages"
    subprocess.run(
        [
            "python3",
            "application/scripts/380_prepare_glofas_dec25_final_refit_runtime.py",
            "--runtime-root",
            str(runtime),
            "--package-output-dir",
            str(package_dir),
            "--workers",
            "4",
        ],
        cwd=REPO,
        check=True,
    )
    manifest = read_csv(runtime / "tables" / "final_dec25_job_manifest.csv")
    assert len(manifest) == 80
    counts = {}
    for row in manifest:
        counts[(row["part"], row["stage"])] = counts.get((row["part"], row["stage"]), 0) + 1
    assert counts[("part2", "design_cache")] == 1
    assert counts[("part2", "initializer_audit")] == 1
    assert counts[("part2", "fit")] == 18
    assert counts[("part2", "forecast")] == 18
    assert counts[("part2", "package")] == 2
    assert counts[("part3", "design_cache")] == 1
    assert counts[("part3", "initializer_audit")] == 1
    assert counts[("part3", "fit")] == 18
    assert counts[("part3", "forecast")] == 18
    assert counts[("part3", "package")] == 2
    by_id = {row["job_id"]: row for row in manifest}
    for row in manifest:
        for dep in row["dependencies"].split("|"):
            if dep:
                assert dep in by_id, (row["job_id"], dep)
    assert by_id["part2_fit_normal_ridge"]["dependencies"] == "part2_design_cache"
    assert by_id["part2_fit_normal_rhs_vb"]["dependencies"] == "part2_fit_normal_ridge"
    assert by_id["part2_initializer_audit"]["dependencies"] == "part2_fit_normal_rhs_vb"
    assert by_id["part2_forecast_normal_rhs_vb"]["dependencies"] == "part2_fit_normal_rhs_vb"
    for tau_slug in ("q0p05", "q0p20", "q0p35", "q0p50", "q0p65", "q0p80", "q0p95"):
        al = by_id[f"part2_fit_independent_al_{tau_slug}"]
        assert set(al["dependencies"].split("|")) == {"part2_fit_normal_rhs_vb", "part2_initializer_audit"}
        command = json.loads(al["command_json"])
        assert command[command.index("--init_fit_job_ids") + 1] == "AUTO_AUDIT"
    for tau_slug in ("q0p05", "q0p20", "q0p35", "q0p50", "q0p65", "q0p80", "q0p95"):
        al = by_id[f"part3_fit_independent_al_{tau_slug}"]
        assert set(al["dependencies"].split("|")) == {"part3_fit_normal_rhs_vb", "part3_initializer_audit"}
        command = json.loads(al["command_json"])
        assert command[command.index("--init_fit_job_ids") + 1] == "AUTO_AUDIT"
    assert set(by_id["part2_fit_joint_al_all7"]["dependencies"].split("|")) == {
        "part2_fit_independent_al_q0p05",
        "part2_fit_independent_al_q0p20",
        "part2_fit_independent_al_q0p35",
        "part2_fit_independent_al_q0p50",
        "part2_fit_independent_al_q0p65",
        "part2_fit_independent_al_q0p80",
        "part2_fit_independent_al_q0p95",
    }
    assert by_id["part3_fit_independent_exal_q0p50"]["dependencies"] == "part3_fit_independent_al_q0p50"
    metadata = json.loads((runtime / "configs" / "final_dec25_relaunch_metadata.json").read_text(encoding="utf-8"))
    assert metadata["job_counts"]["model_fit_jobs"] == 36
    assert metadata["job_counts"]["forecast_jobs"] == 36
    assert metadata["job_counts"]["initializer_audit_jobs"] == 2
    assert metadata["production_launched"] is False

    out = subprocess.check_output(
        [
            "python3",
            "application/scripts/384_check_glofas_dec25_final_refit_dag.py",
            "--runtime-root",
            str(runtime),
            "--write",
        ],
        cwd=REPO,
        text=True,
    )
    assert "TOTAL" in out
    health = read_csv(runtime / "tables" / "final_dec25_health_latest.csv")
    total = next(row for row in health if row["part"] == "TOTAL")
    assert total["total"] == "80"
    assert total["completed"] == "0"
    assert total["ready"] == "2"
    assert total["left_to_finish"] == "80"

    (runtime / "status" / "part2_design_cache.completed").write_text("test\n", encoding="utf-8")
    subprocess.run(
        [
            "python3",
            "application/scripts/384_check_glofas_dec25_final_refit_dag.py",
            "--runtime-root",
            str(runtime),
            "--write",
        ],
        cwd=REPO,
        check=True,
    )
    states = {row["job_id"]: row["state"] for row in read_csv(runtime / "tables" / "final_dec25_job_status_latest.csv")}
    assert states["part2_fit_normal_ridge"] == "ready"

    subprocess.run(
        [
            "python3",
            "application/scripts/382_package_glofas_dec25_final_refit.py",
            "--runtime-root",
            str(runtime),
            "--part",
            "part2",
            "--package-kind",
            "compact",
            "--output-dir",
            str(package_dir),
            "--dry-run",
        ],
        cwd=REPO,
        check=True,
    )
    assert (runtime / "manifests" / "part2_compact_handoff_file_manifest.csv").exists()
    package = subprocess.check_output(
        [
            "python3",
            "application/scripts/382_package_glofas_dec25_final_refit.py",
            "--runtime-root",
            str(runtime),
            "--part",
            "part2",
            "--package-kind",
            "compact",
            "--output-dir",
            str(package_dir),
        ],
        cwd=REPO,
        text=True,
    )
    archive_line = next(line for line in package.splitlines() if line.startswith("archive="))
    archive = REPO / archive_line.split("=", 1)[1]
    assert archive.exists()
    extract_dir = root / "extract"
    extract_dir.mkdir()
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(extract_dir)
    package_root = next(path for path in extract_dir.iterdir() if path.is_dir())
    subprocess.run(["python3", "verify_handoff_package.py", str(package_root)], cwd=package_root, check=True)

    old_diag = root / "old_diag"
    subprocess.run(
        [
            "python3",
            "application/scripts/67_prepare_glofas_part2_bridge_forecast_chain.py",
            "--runtime_root",
            str(old_diag),
            "--workers",
            "2",
        ],
        cwd=REPO,
        check=True,
    )
    cfg = json.loads((old_diag / "configs" / "part2_bridge_forecast_chain_config.json").read_text(encoding="utf-8"))
    assert cfg["origin_date"] == "2022-12-25"

print("test_glofas_dec25_final_refit_runtime: OK")
