from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/370_audit_pricefm_stage_r110_frozen_qdesn_replay.py"
spec = importlib.util.spec_from_file_location("pricefm_r110_replay", SCRIPT)
replay = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(replay)


def test_read_r110_paths_preserves_r_column_major_path_identity(tmp_path):
    root = tmp_path / "driver"
    output = root / "runs/outer_validation/BG/fold=1"
    output.mkdir(parents=True)
    n_paths = 3
    n_origins = 2
    rows = pd.DataFrame({
        "split": "val",
        "origin_id": np.repeat(np.arange(n_origins), 96),
        "horizon": np.tile(np.arange(1, 97), n_origins),
        "origin_market_time": np.repeat(
            ["2024-01-01T00:00:00+00:00", "2024-01-02T00:00:00+00:00"], 96
        ),
        "y_scaled": np.arange(n_origins * 96, dtype=float),
    })
    rows.to_csv(output / "evaluation_rows.csv", index=False)
    expected = np.arange(n_paths * n_origins * 96, dtype=float).reshape(n_paths, n_origins, 96)
    matrix = expected.reshape(n_paths, n_origins * 96).T
    matrix.reshape(-1, order="F").astype("<f8").tofile(output / "prediction_paths_scaled.bin")
    (output / "prediction_paths_manifest.json").write_text(json.dumps({
        "n_rows": n_origins * 96,
        "n_paths": n_paths,
        "storage_order": "R_column_major",
        "dtype": "float64_little_endian",
    }))
    artifacts = []
    for name in ("evaluation_rows.csv", "prediction_paths_scaled.bin", "prediction_paths_manifest.json"):
        path = output / name
        artifacts.append({"path": name, "sha256": replay.sha256_file(path)})
    (output / "terminal.json").write_text(json.dumps({
        "status": "completed_r110_case",
        "phase": "outer_validation",
        "region": "BG",
        "outer_fold": 1,
        "paths": n_paths,
        "test_opened": False,
        "artifacts": artifacts,
    }))
    context = {
        "anchors": np.array(["2024-01-01T00:00:00+00:00", "2024-01-02T00:00:00+00:00"]),
        "truth": rows.y_scaled.to_numpy().reshape(n_origins, 96),
    }
    observed, evidence = replay.read_r110_paths(root, "BG", 1, context, n_paths)
    assert np.array_equal(observed, expected)
    assert len(evidence) == 4


def reference_rows(policy: str, value: float) -> list[dict]:
    return [
        {
            "region": region,
            "fold": fold,
            "policy": policy,
            "AQL": value,
            "coverage_10_90": 0.8,
            "mean_width_10_90": 10.0,
            "median_MAE": value,
            "n_loss_atoms": 100,
        }
        for region in replay.REGIONS for fold in replay.FOLDS
    ]


def test_replay_gate_requires_gain_and_direct_reference_proximity():
    candidate = pd.DataFrame(reference_rows(replay.POLICY, 8.0)).assign(posterior_paths=500)
    references = pd.DataFrame(
        reference_rows("self_rhs_neighbors", 12.0)
        + reference_rows("r97_direct_reference", 7.5)
    )
    gates = replay.evaluate_gates(candidate, references)
    assert gates.passed.all()
    failed = replay.evaluate_gates(candidate.assign(AQL=10.0), references)
    assert not failed.passed.all()


def test_replay_source_is_no_refit_and_test_closed():
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"test_opened": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "R104.read_beta_draws" in text
    assert "target_mode=\"external\"" in text
    assert "ProcessPoolExecutor" in text
