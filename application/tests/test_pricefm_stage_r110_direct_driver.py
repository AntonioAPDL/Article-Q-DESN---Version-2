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
    "pricefm_r110_prep",
    "application/scripts/pricefm/366_prepare_pricefm_stage_r110_direct_driver.py",
)
orchestrator = load_script(
    "pricefm_r110_orchestrator",
    "application/scripts/pricefm/368_orchestrate_pricefm_stage_r110_direct_driver.py",
)
closeout = load_script(
    "pricefm_r110_closeout",
    "application/scripts/pricefm/369_closeout_pricefm_stage_r110_direct_driver.py",
)


def test_prepare_is_bounded_and_test_closed(tmp_path):
    result = prep.prepare(ROOT, tmp_path)
    assert result["task_count"] == 45
    assert result["phase_counts"] == {
        "ridge_selection": 18,
        "rhs_selection": 18,
        "outer_validation": 9,
    }
    assert result["test_access_authorized"] is False
    assert result["selection_contract"] == "fold1_training_inner_folds_only_one_policy_per_region"
    with (tmp_path / "conceptual_task_manifest.csv").open() as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 45
    assert {row["region"] for row in rows} == {"BG", "EE", "BE"}
    assert not any("test" in row["dependency"].lower() for row in rows)
    for config_path in (tmp_path / "configs").glob("**/*.yaml"):
        text = config_path.read_text()
        assert "- train" in text and "- val" in text
        assert "- test" not in text


def inner_rows(prior: str, readout: str, region: str, values: list[float], tau0=np.nan):
    return pd.DataFrame({
        "region": region,
        "readout": readout,
        "prior_type": prior,
        "tau0": tau0,
        "inner_fold": [1, 2, 3],
        "AQL_scaled": values,
    })


def test_selection_uses_one_region_policy_and_preserves_null_ridge_tau0():
    ridge = pd.concat([
        inner_rows("scaled_ridge", "shared", "BG", [1.0, 1.0, 1.0]),
        inner_rows("scaled_ridge", "block24", "BG", [1.2, 1.2, 1.2]),
        inner_rows("scaled_ridge", "shared", "EE", [2.0, 2.0, 2.0]),
        inner_rows("scaled_ridge", "block24", "EE", [1.5, 1.5, 1.5]),
        inner_rows("scaled_ridge", "shared", "BE", [0.8, 0.8, 0.8]),
        inner_rows("scaled_ridge", "block24", "BE", [0.9, 0.9, 0.9]),
    ], ignore_index=True)
    selected_ridge = orchestrator.select_ridge(ridge)
    assert {row["region"]: row["readout"] for row in selected_ridge} == {
        "BG": "shared", "EE": "block24", "BE": "shared"
    }
    rhs = pd.concat([
        inner_rows("rhs_ns", "shared", "BG", [1.1] * 3, 1e-4),
        inner_rows("rhs_ns", "shared", "BG", [1.2] * 3, 2.5e-5),
        inner_rows("rhs_ns", "block24", "EE", [1.4] * 3, 1e-4),
        inner_rows("rhs_ns", "block24", "EE", [1.6] * 3, 2.5e-5),
        inner_rows("rhs_ns", "shared", "BE", [0.7] * 3, 2e-3),
        inner_rows("rhs_ns", "shared", "BE", [0.75] * 3, 5e-4),
    ], ignore_index=True)
    selected = orchestrator.select_final(ridge, rhs, selected_ridge)
    by_region = {row["region"]: row for row in selected}
    assert by_region["BG"]["prior_type"] == "scaled_ridge"
    assert pd.isna(by_region["BG"]["tau0"])
    assert by_region["EE"]["prior_type"] == "rhs_ns"
    assert by_region["EE"]["tau0"] == 1e-4
    assert by_region["BE"]["prior_type"] == "rhs_ns"
    assert by_region["BE"]["tau0"] == 2e-3


def test_path_scoring_and_gate_algebra():
    rng = np.random.default_rng(9)
    truth = np.zeros(96)
    paths = rng.normal(0, 1, size=(96, 500))
    metric, horizon = closeout.score_paths(paths, truth, np.arange(1, 97), 2.0)
    assert metric["posterior_paths"] == 500
    assert metric["n_points"] == 96
    assert len(horizon) == 96
    assert np.isfinite(metric["AQL"])

    cases = pd.DataFrame([
        {"region": region, "fold": fold, "AQL": 5.0, "coverage_10_90": 0.80, "n_points": 96, "posterior_paths": 500}
        for region in ("BG", "EE", "BE") for fold in (1, 2, 3)
    ])
    candidate_horizon = pd.DataFrame([
        {"region": region, "fold": fold, "horizon": h, "AQL": 5.0, "n_origins": 1}
        for region in ("BG", "EE", "BE") for fold in (1, 2, 3) for h in range(1, 97)
    ])
    references = []
    reference_horizon = []
    for method, value, coverage in (("normal_rhs_paths", 10.0, 0.80), ("cached_pricefm_quantiles", 4.5, 0.80)):
        for region in ("BG", "EE", "BE"):
            for fold in (1, 2, 3):
                references.append({"region": region, "fold": fold, "driver_method": method, "AQL": value, "coverage_10_90": coverage, "n_points": 96})
                for h in range(1, 97):
                    reference_horizon.append({"region": region, "fold": fold, "driver_method": method, "horizon": h, "AQL": value, "n_origins": 1})
    gates = closeout.evaluate_gate(cases, candidate_horizon, pd.DataFrame(references), pd.DataFrame(reference_horizon))
    assert gates.passed.all()


def test_completed_budget_recovers_exact_terminal_contract(tmp_path):
    output = tmp_path / "fit"
    output.mkdir()
    base = {"task_id": "x", "test_access_authorized": False}
    old = orchestrator.task_contract(base | {"max_iter": 750}, output)
    (output / "terminal.json").write_text(json.dumps({
        "status": "completed_r110_case",
        "test_opened": False,
        "task_contract_sha256": old["task_contract_sha256"],
    }))
    assert orchestrator.completed_budget(base, output, (500, 750, 1000)) == 750
    assert orchestrator.completed_budget(base | {"seed": 2}, output, (500, 750, 1000)) is None


def test_launch_sources_contain_hard_guards():
    worker = (ROOT / "application/scripts/pricefm/367_run_pricefm_stage_r110_direct_case.R").read_text()
    controller = (ROOT / "application/scripts/pricefm/368_orchestrate_pricefm_stage_r110_direct_driver.py").read_text()
    assert 'stop("R110 forbids test access"' in worker
    assert "OMP_NUM_THREADS" in controller
    assert "taskset" in controller
    assert "selected_physical_core_count" in controller
    assert "completed_budget(rhs_base, rhs_output, (500, 750))" in controller
    assert "completed_budget(final_base, final_output, allowed_budgets)" in controller
    assert "registry_mutated" in worker and "article_mutated" in worker
