#!/usr/bin/env python3
import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path("application/scripts/58_prepare_glofas_part3_joint_historical_launch.py")


def read_rows(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_deferred_manifest_is_fail_closed_without_winners():
    with tempfile.TemporaryDirectory() as tmp:
        runtime_root = Path(tmp) / "part3_deferred"
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--repo-root",
                ".",
                "--run-label",
                "toy_part3_deferred",
                "--runtime-root",
                str(runtime_root),
            ],
            check=True,
            universal_newlines=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        metadata = json.loads(completed.stdout)
        assert metadata["model_slots"] == 18
        assert metadata["normal_slots"] == 2
        assert metadata["quantile_slots"] == 16
        manifest = Path(metadata["manifest_path"])
        rows = read_rows(manifest)
        assert len(rows) == 18
        assert sum(row["model_family"] == "normal_ridge_joint" for row in rows) == 1
        assert sum(row["model_family"] == "normal_rhs_vb_joint" for row in rows) == 1
        assert sum(row["model_family"] == "independent_al_rhs_vb" for row in rows) == 7
        assert sum(row["model_family"] == "independent_exal_rhs_vb" for row in rows) == 7
        assert sum(row["model_family"] == "joint_al_rhs_vb" for row in rows) == 1
        assert sum(row["model_family"] == "joint_exal_rhs_vb" for row in rows) == 1
        normal_rows = [row for row in rows if row["model_family"].startswith("normal_")]
        quantile_rows = [row for row in rows if not row["model_family"].startswith("normal_")]
        assert all(row["status"].startswith("blocked_") for row in normal_rows)
        assert all(row["status"] == "implemented_via_separate_part3_quantile_forecast_continuation" for row in quantile_rows)
        assert all(row["launch_command"] == "" for row in rows)
        subprocess.run(["bash", "-n", metadata["launch_path"]], check=True)


def test_frozen_winner_manifest_releases_only_normal_rows():
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        winner_manifest = tmp_path / "winners.csv"
        fields = [
            "component",
            "stage",
            "candidate_id",
            "source_runtime_root",
            "score_path",
            "method",
            "status",
            "winner_role",
            "n_vector",
            "m",
            "output_lag_max",
            "covariate_lag_max",
            "washout",
            "alpha",
            "rho",
            "seed",
            "rhs_tau0",
            "design_hash",
            "frozen",
        ]
        rows = [
            {
                "component": "reference",
                "stage": "G1",
                "candidate_id": "ref_winner",
                "source_runtime_root": "g1",
                "score_path": "g1_scores.csv",
                "method": "normal_rhs_vb",
                "status": "completed",
                "winner_role": "reference",
                "n_vector": "3000",
                "m": "360",
                "output_lag_max": "360",
                "covariate_lag_max": "180",
                "washout": "500",
                "alpha": "0.5",
                "rho": "0.9",
                "seed": "20260512",
                "rhs_tau0": "1",
                "design_hash": "hash1",
                "frozen": "true",
            },
            {
                "component": "discrepancy",
                "stage": "G2",
                "candidate_id": "disc_winner",
                "source_runtime_root": "g2",
                "score_path": "g2_scores.csv",
                "method": "normal_rhs_vb",
                "status": "completed",
                "winner_role": "discrepancy",
                "n_vector": "1500",
                "m": "360",
                "output_lag_max": "360",
                "covariate_lag_max": "180",
                "washout": "500",
                "alpha": "0.5",
                "rho": "0.9",
                "seed": "20261521",
                "rhs_tau0": "0.001",
                "design_hash": "hash2",
                "frozen": "true",
            },
        ]
        with winner_manifest.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        runtime_root = tmp_path / "part3_ready"
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--repo-root",
                ".",
                "--run-label",
                "toy_part3_ready",
                "--runtime-root",
                str(runtime_root),
                "--winner-manifest",
                str(winner_manifest),
            ],
            check=True,
            universal_newlines=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        metadata = json.loads(completed.stdout)
        rows = read_rows(Path(metadata["manifest_path"]))
        normal_rows = [
            row for row in rows
            if row["model_family"] in {"normal_ridge_joint", "normal_rhs_vb_joint"}
        ]
        quantile_rows = [row for row in rows if row not in normal_rows]
        assert len(normal_rows) == 2
        ridge_row = next(row for row in normal_rows if row["model_family"] == "normal_ridge_joint")
        rhs_row = next(row for row in normal_rows if row["model_family"] == "normal_rhs_vb_joint")
        assert ridge_row["status"] == "ready_after_operator_launch_approval"
        assert ridge_row["depends_on"] == ""
        assert rhs_row["status"] == "blocked_until_normal_ridge_joint_completed"
        assert rhs_row["depends_on"] == "normal_ridge_joint"
        assert all("59_run_glofas_part3_joint_historical_worker.R" in row["launch_command"] for row in normal_rows)
        assert "--ridge_warm_start_path" in rhs_row["launch_command"]
        assert "--ridge_warm_start_sha256" in rhs_row["launch_command"]
        assert "--ridge_warm_start_path" not in ridge_row["launch_command"]
        assert all(row["status"] == "implemented_via_separate_part3_quantile_forecast_continuation" for row in quantile_rows)
        assert all(row["launch_command"] == "" for row in quantile_rows)
        assert all(row["selected_reference_candidate_id"] == "ref_winner" for row in rows)
        assert all(row["selected_discrepancy_candidate_id"] == "disc_winner" for row in rows)
        launch_text = Path(metadata["launch_path"]).read_text(encoding="utf-8")
        assert "70_preflight_glofas_part3_joint_historical.R" in launch_text
        assert launch_text.index("normal_ridge_joint") < launch_text.index("normal_rhs_vb_joint")
        assert "refusing to duplicate" in launch_text
        subprocess.run(["bash", "-n", metadata["launch_path"]], check=True)


if __name__ == "__main__":
    test_deferred_manifest_is_fail_closed_without_winners()
    test_frozen_winner_manifest_releases_only_normal_rows()
    print("glofas part3 deferred launcher tests passed")
