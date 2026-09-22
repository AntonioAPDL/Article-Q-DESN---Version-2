from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]


def load_script(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prep = load_script(
    "pricefm_r111a_prep",
    "application/scripts/pricefm/373_prepare_pricefm_stage_r111a_ee_neighbor_driver.py",
)
replay = load_script(
    "pricefm_r111a_replay",
    "application/scripts/pricefm/375_replay_pricefm_stage_r111a_ee_all_active.py",
)
orchestrator = load_script(
    "pricefm_r111a_orchestrator",
    "application/scripts/pricefm/376_orchestrate_pricefm_stage_r111a_ee_neighbor_driver.py",
)


def test_prepare_is_bounded_authorized_and_test_closed(tmp_path):
    result = prep.prepare(ROOT, tmp_path)
    assert result["fit_regions"] == ["FI", "LV"]
    assert result["replay_active_regions"] == ["EE", "FI", "LV"]
    assert result["fit_task_count"] == 30
    assert result["replay_case_count"] == 3
    assert result["task_count"] == 33
    assert result["phase_counts"] == {
        "ridge_selection": 12,
        "rhs_selection": 12,
        "outer_validation": 6,
        "ee_all_active_replay": 3,
    }
    assert result["test_access_authorized"] is False
    assert result["broad_all_region_launch_authorized"] is False
    assert result["path_scale_contract"].startswith("each_active_region")
    assert result["rhs_iteration_ceiling_ladder"] == [750, 1500]
    assert result["final_rhs_iteration_ceiling"] == 1500
    assert result["rhs_numerical_eligibility_contract"] == "candidate_requires_all_three_converged_inner_folds"
    with (tmp_path / "conceptual_task_manifest.csv").open() as handle:
        rows = list(csv.DictReader(handle))
    assert {row["region"] for row in rows if row["phase"] != "ee_all_active_replay"} == {
        "FI", "LV"
    }
    assert not any("test" in row["dependency"].lower() for row in rows)
    for path in (tmp_path / "configs").glob("**/*.yaml"):
        text = path.read_text()
        assert "- train" in text and "- val" in text
        assert "- test" not in text


def test_frozen_neighbor_specs_match_r98_authority():
    assert prep.SPECS["FI"] == {
        "feature_policy": "target_only", "feature_dim": 96, "depth": 2,
        "units": [96, 96], "lag_window": 240, "alpha": 0.5, "rho": 0.82,
        "input_scale": 0.15, "tau0": 0.01, "neighbors": [], "graph_degree": 0,
    }
    assert prep.SPECS["LV"] == {
        "feature_policy": "graph_summary_mean", "feature_dim": 40, "depth": 3,
        "units": [40, 40, 40], "lag_window": 96, "alpha": 0.35, "rho": 0.9,
        "input_scale": 0.2, "tau0": 0.01, "neighbors": ["EE", "LT"],
        "graph_degree": 1,
    }


def inner_rows(prior: str, readout: str, region: str, values: list[float], tau0=np.nan):
    return pd.DataFrame({
        "region": region,
        "readout": readout,
        "prior_type": prior,
        "tau0": tau0,
        "inner_fold": [1, 2, 3],
        "AQL_scaled": values,
    })


def test_selection_is_one_policy_per_region_from_inner_training_only():
    ridge = pd.concat([
        inner_rows("scaled_ridge", "shared", "FI", [1.0, 1.0, 1.0]),
        inner_rows("scaled_ridge", "block24", "FI", [0.9, 0.9, 0.9]),
        inner_rows("scaled_ridge", "shared", "LV", [0.7, 0.7, 0.7]),
        inner_rows("scaled_ridge", "block24", "LV", [0.8, 0.8, 0.8]),
    ], ignore_index=True)
    ridge_choice = orchestrator.select_ridge(ridge)
    assert {row["region"]: row["readout"] for row in ridge_choice} == {
        "FI": "block24", "LV": "shared"
    }
    rhs = pd.concat([
        inner_rows("rhs_ns", "block24", "FI", [0.8] * 3, 0.01),
        inner_rows("rhs_ns", "block24", "FI", [0.85] * 3, 0.0025),
        inner_rows("rhs_ns", "shared", "LV", [0.75] * 3, 0.01),
        inner_rows("rhs_ns", "shared", "LV", [0.65] * 3, 0.0025),
    ], ignore_index=True)
    selected = orchestrator.select_final(ridge, rhs, ridge_choice)
    by_region = {row["region"]: row for row in selected}
    assert by_region["FI"]["prior_type"] == "rhs_ns"
    assert by_region["FI"]["tau0"] == 0.01
    assert by_region["LV"]["prior_type"] == "rhs_ns"
    assert by_region["LV"]["tau0"] == 0.0025


def test_incomplete_rhs_candidate_is_ineligible_not_promoted():
    ridge = pd.concat([
        inner_rows("scaled_ridge", "shared", "FI", [1.0] * 3),
        inner_rows("scaled_ridge", "block24", "FI", [0.9] * 3),
        inner_rows("scaled_ridge", "shared", "LV", [0.8] * 3),
        inner_rows("scaled_ridge", "block24", "LV", [0.7] * 3),
    ], ignore_index=True)
    ridge_choice = orchestrator.select_ridge(ridge)
    rhs = pd.concat([
        inner_rows("rhs_ns", "block24", "FI", [0.1] * 3, 0.01).iloc[:2],
        inner_rows("rhs_ns", "block24", "LV", [0.6] * 3, 0.01),
    ], ignore_index=True)
    selected = {row["region"]: row for row in orchestrator.select_final(ridge, rhs, ridge_choice)}
    assert selected["FI"]["prior_type"] == "scaled_ridge"
    assert selected["LV"]["prior_type"] == "rhs_ns"


def test_read_neighbor_paths_preserves_region_scale_and_path_identity(tmp_path):
    output = tmp_path / "runs/outer_validation/FI/fold=1"
    output.mkdir(parents=True)
    n_paths, n_origins = 3, 2
    anchors = np.array(["2024-01-01T00:00:00+00:00", "2024-01-02T00:00:00+00:00"])
    truth = np.arange(n_origins * 96, dtype=float).reshape(n_origins, 96)
    rows = pd.DataFrame({
        "split": "val",
        "origin_id": np.repeat(np.arange(n_origins), 96),
        "horizon": np.tile(np.arange(1, 97), n_origins),
        "origin_market_time": np.repeat(anchors, 96),
        "y_scaled": truth.reshape(-1),
    })
    rows.to_csv(output / "evaluation_rows.csv", index=False)
    expected = np.arange(n_paths * n_origins * 96, dtype=float).reshape(n_paths, n_origins, 96)
    expected.reshape(n_paths, -1).T.reshape(-1, order="F").astype("<f8").tofile(
        output / "prediction_paths_scaled.bin"
    )
    (output / "prediction_paths_manifest.json").write_text(json.dumps({
        "n_rows": n_origins * 96,
        "n_paths": n_paths,
        "storage_order": "R_column_major",
        "dtype": "float64_little_endian",
    }))
    artifacts = []
    for name in ("evaluation_rows.csv", "prediction_paths_scaled.bin", "prediction_paths_manifest.json"):
        artifacts.append({"path": name, "sha256": replay.sha256_file(output / name)})
    (output / "terminal.json").write_text(json.dumps({
        "stage": "R111A", "status": "completed_r111a_direct_case",
        "phase": "outer_validation", "region": "FI", "outer_fold": 1,
        "paths": n_paths, "test_opened": False, "artifacts": artifacts,
    }))
    observed, evidence = replay.read_r111a_paths(
        tmp_path, "FI", 1, {"anchors": anchors, "truth": truth}, anchors, n_paths
    )
    assert np.array_equal(observed, expected)
    assert len(evidence) == 4


def metric_rows(policy: str, value: float, paths: int | None = None) -> list[dict]:
    rows = []
    for fold in (1, 2, 3):
        row = {
            "region": "EE", "fold": fold, "policy": policy, "AQL": value,
            "n_loss_atoms": 100, "coverage_10_90": 0.8,
        }
        if paths is not None:
            row["posterior_paths"] = paths
        rows.append(row)
    return rows


def horizon_rows(policy: str, value: float) -> list[dict]:
    return [
        {"region": "EE", "fold": fold, "policy": policy, "horizon": horizon,
         "AQL": value, "n_origins": 10}
        for fold in (1, 2, 3) for horizon in range(1, 97)
    ]


def test_ee_replay_gate_requires_gain_fold_safety_and_direct_proximity():
    candidate = pd.DataFrame(metric_rows(replay.POLICY, 8.0, 500))
    horizons = pd.DataFrame(horizon_rows(replay.POLICY, 8.0))
    references = pd.DataFrame(
        metric_rows("r110_direct_target_rhs_neighbors", 10.0)
        + metric_rows("r97_direct_reference", 7.5)
    )
    reference_horizons = pd.DataFrame(
        horizon_rows("r110_direct_target_rhs_neighbors", 10.0)
        + horizon_rows("r97_direct_reference", 7.5)
    )
    gates = replay.evaluate_gates(candidate, horizons, references, reference_horizons)
    assert gates.passed.all()
    harmed = candidate.copy()
    harmed.loc[harmed.fold.eq(3), "AQL"] = 11.0
    assert not replay.evaluate_gates(
        harmed, horizons, references, reference_horizons
    ).passed.all()


def test_launch_sources_enforce_scope_threads_and_no_mutation():
    worker = (ROOT / "application/scripts/pricefm/374_run_pricefm_stage_r111a_direct_case.R").read_text()
    controller = (ROOT / "application/scripts/pricefm/376_orchestrate_pricefm_stage_r111a_ee_neighbor_driver.py").read_text()
    replay_text = (ROOT / "application/scripts/pricefm/375_replay_pricefm_stage_r111a_ee_all_active.py").read_text()
    assert 'stop("R111A forbids test access"' in worker
    assert 'contract$region %in% c("FI", "LV")' in worker
    assert "taskset" in controller and "OMP_NUM_THREADS" in controller
    assert "completed_r111a_direct_case" in controller
    assert "completed_budget(rhs_base, rhs_output, (500, 750, 1500))" in controller
    assert "default_budget = 1500" in controller
    assert "fail_on_nonzero=False" in controller
    assert "rhs_convergence_gate_failed_at_1500" in controller
    assert '"model_fit_started": False' in replay_text
    assert '"broad_all_region_launch_authorized": False' in replay_text
    assert '"registry_mutated": False' in replay_text
    assert '"article_mutated": False' in replay_text
