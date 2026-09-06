#!/usr/bin/env python3
"""Focused tests for the Part 2 bridge forecast manifest and dependency gates."""

from __future__ import annotations

import csv
import subprocess
import tempfile
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def main() -> int:
    root = repo_root()
    with tempfile.TemporaryDirectory(prefix="part2_bridge_chain_test_") as tmp:
        runtime = Path(tmp) / "runtime"
        subprocess.check_call(
            [
                "python3",
                "application/scripts/67_prepare_glofas_part2_bridge_forecast_chain.py",
                "--runtime_root",
                str(runtime),
                "--workers",
                "3",
            ],
            cwd=root,
        )
        manifest = read_csv(runtime / "tables" / "part2_bridge_forecast_job_manifest.csv")
        assert len(manifest) == 18
        by_id = {row["job_id"]: row for row in manifest}
        assert by_id["normal_ridge"]["dependencies"] == ""
        assert by_id["normal_rhs_vb"]["dependencies"] == "normal_ridge"
        assert by_id["independent_al_q0p50"]["dependencies"] == "normal_rhs_vb"
        assert by_id["independent_al_q0p35"]["dependencies"] == "independent_al_q0p50"
        assert by_id["independent_al_q0p65"]["dependencies"] == "independent_al_q0p50"
        assert by_id["independent_exal_q0p35"]["dependencies"] == "independent_al_q0p35"
        assert "joint_al_all7" in by_id["joint_exal_all7"]["dependencies"].split("|")

        out = subprocess.check_output(
            [
                "python3",
                "application/scripts/68_check_glofas_part2_bridge_forecast_chain.py",
                "--runtime_root",
                str(runtime),
                "--write",
            ],
            cwd=root,
            text=True,
        )
        assert "TOTAL" in out
        health = read_csv(runtime / "tables" / "part2_bridge_forecast_health_latest.csv")
        total = next(row for row in health if row["group"] == "TOTAL")
        assert total["total"] == "18"
        assert total["completed"] == "0"
        assert total["ready"] == "1"
        assert total["left_to_finish"] == "18"

        done_path = root / by_id["normal_ridge"]["status_done_path"]
        done_path.parent.mkdir(parents=True, exist_ok=True)
        done_path.write_text("job_id=normal_ridge\n")
        subprocess.check_call(
            [
                "python3",
                "application/scripts/68_check_glofas_part2_bridge_forecast_chain.py",
                "--runtime_root",
                str(runtime),
                "--write",
            ],
            cwd=root,
        )
        rows = read_csv(runtime / "tables" / "part2_bridge_forecast_job_status_latest.csv")
        states = {row["job_id"]: row["state"] for row in rows}
        assert states["normal_ridge"] == "completed"
        assert states["normal_rhs_vb"] == "ready"
        assert (runtime / "tables" / "artifact_manifest.csv").exists()
        assert (runtime / "tables" / "artifact_file_list.csv").exists()
    print("Part 2 bridge forecast chain tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
