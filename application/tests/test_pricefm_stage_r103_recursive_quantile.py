from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_recursive_normal as normal  # noqa: E402
import pricefm_recursive_quantile as quantile  # noqa: E402


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CLOSEOUT = load("346_closeout_pricefm_stage_r103_recursive_quantile.py")
ORCHESTRATOR = load("347_orchestrate_pricefm_stage_r103_recursive_quantile.py")


def target_spec(region: str = "AT") -> dict:
    return {
        "region": region,
        "feature_policy": "target_only",
        "lag_window": 3,
        "depth": 1,
        "units": [2],
        "alpha": 0.5,
        "rho": 0.8,
        "input_scale": 0.2,
        "state_output": "final_layer",
        "seed": 17,
        "spatial": {"graph_degree": 0},
        "tau0": 0.01,
    }


def toy_window(region: str = "AT") -> dict:
    rng = np.random.default_rng(91)
    return {
        "X_lag": rng.normal(size=(3, 3, 4)),
        "X_lead": rng.normal(size=(3, 96, 3)),
        "Y": rng.normal(size=(3, 96)),
        "anchors": np.asarray(["a", "b", "c"]),
        "lag_cols": [f"{region}-price", f"{region}-load", f"{region}-solar", f"{region}-wind"],
        "lead_cols": [f"{region}-load", f"{region}-solar", f"{region}-wind"],
    }


def toy_context() -> tuple[dict, dict]:
    window = toy_window()
    result = quantile.causal_teacher_forced_design({"AT": window}, target_spec(), ["AT"])
    context = {
        "region": "AT",
        "spec": target_spec(),
        "active_regions": ["AT"],
        "input_regions": ["AT"],
        "initial_lag": np.asarray(window["X_lag"], dtype=float),
        "lead_features": np.asarray(window["X_lead"], dtype=float),
        "raw_lead": {"AT": np.asarray(window["X_lead"], dtype=float)},
        "lag_columns": {"AT": list(window["lag_cols"])},
        "lead_columns": {"AT": list(window["lead_cols"])},
        "truth": np.asarray(window["Y"], dtype=float),
        "reservoir": result["reservoir"],
        "reservoir_config": result["reservoir_config"],
    }
    context["initial_states"] = normal.precompute_initial_states(context)
    return context, result


def test_causal_design_matches_r102_sufficient_statistics() -> None:
    windows = {"AT": toy_window()}
    design = quantile.causal_teacher_forced_design(windows, target_spec(), ["AT"])
    statistics = normal.causal_teacher_forced_statistics(windows, target_spec(), ["AT"])
    assert design["n"] == statistics["n"]
    assert design["p"] == statistics["p"]
    assert design["feature_names"] == statistics["feature_names"]
    assert design["horizon_one_parity_max_abs"] <= 1e-12
    np.testing.assert_allclose(design["X"].T @ design["X"], statistics["XtX"], rtol=1e-12, atol=1e-10)
    np.testing.assert_allclose(design["X"].T @ design["y"], statistics["Xty"], rtol=1e-12, atol=1e-10)
    np.testing.assert_allclose(design["y"] @ design["y"], statistics["yty"], rtol=1e-12, atol=1e-10)


def test_recursive_quantile_rows_use_normal_paths_and_never_truth() -> None:
    context, result = toy_context()
    driver = np.zeros((5, 96, 1), dtype=float)
    first = quantile.recursive_quantile_design(context, driver, 0, ["AT"])
    context["truth"][:] = 1e12
    second = quantile.recursive_quantile_design(context, driver, 0, ["AT"])
    np.testing.assert_array_equal(first, second)
    changed = driver.copy()
    changed[:, 0, 0] = np.arange(5) + 1.0
    third = quantile.recursive_quantile_design(context, changed, 0, ["AT"])
    np.testing.assert_array_equal(first[:, 0], third[:, 0])
    assert not np.allclose(first[:, 1], third[:, 1])
    assert first.shape == (5, 96, result["p"])


def test_paired_prediction_does_not_form_cartesian_product() -> None:
    design = np.asarray([
        [[1.0, 2.0], [2.0, 3.0]],
        [[3.0, 4.0], [4.0, 5.0]],
    ])
    beta = np.asarray([[1.0, 0.5], [-1.0, 2.0]])
    expected = np.mean(np.einsum("shp,sp->sh", design, beta), axis=0)
    np.testing.assert_allclose(quantile.paired_quantile_prediction(design, beta), expected)


def test_family_selection_is_fold1_only_with_whole_family_fallback() -> None:
    rows = []
    for index in range(38):
        region = f"R{index:02d}"
        for fold in (1, 2, 3):
            rows.extend([
                {
                    "region": region,
                    "fold": fold,
                    "family": "al",
                    "validation_AQL_original": 2.0,
                    "numerically_eligible": True,
                },
                {
                    "region": region,
                    "fold": fold,
                    "family": "exal",
                    "validation_AQL_original": 1.0 if fold == 1 else 99.0,
                    "numerically_eligible": not (index == 0 and fold == 2),
                },
            ])
    decisions = CLOSEOUT.select_families(pd.DataFrame(rows))
    assert decisions.loc[decisions.region.eq("R00"), "selected_family"].item() == "al"
    assert decisions.loc[decisions.region.eq("R01"), "selected_family"].item() == "exal"
    assert decisions.selection_split.eq("fold1_validation_only").all()
    assert not decisions.per_fold_or_quantile_family_mixing.any()


def test_cpu_gate_rejects_idle_sibling_of_a_busy_physical_core(monkeypatch) -> None:
    snapshot = {0: 95.0, 32: 0.0, 33: 0.0}
    monkeypatch.setattr(ORCHESTRATOR, "cpu_snapshot", lambda: snapshot)
    monkeypatch.setattr(
        ORCHESTRATOR,
        "physical_core",
        lambda cpu: "socket0:core0" if cpu in {0, 32} else "socket0:core1",
    )
    cpus, _ = ORCHESTRATOR.choose_cpus(1, 20.0, "32,33")
    assert cpus == [33]


def test_launch_and_fit_firewalls_are_explicit() -> None:
    prep = (SCRIPTS / "343_prepare_pricefm_stage_r103_recursive_quantile.py").read_text()
    r_source = (SCRIPTS / "344_run_pricefm_stage_r103_quantile_case.R").read_text()
    orchestrator = (SCRIPTS / "347_orchestrate_pricefm_stage_r103_recursive_quantile.py").read_text()
    assert 'path = normalizePath(file.path(atom$output_dir, name), mustWork = FALSE)' in r_source
    assert 'prior_center_from_initializer = FALSE' in r_source
    assert 'joint_model_fitted = FALSE' in r_source
    assert 'mcmc_fitted = FALSE' in r_source
    assert "RUN_PRICEFM_R103_RECURSIVE_QUANTILE" in orchestrator
    assert "core_usage[core]" in orchestrator
    assert "cpu_worker" in orchestrator
    assert '"R/exdqlm.rdb"' in prep
    assert '"libs/exdqlm.so"' in prep
