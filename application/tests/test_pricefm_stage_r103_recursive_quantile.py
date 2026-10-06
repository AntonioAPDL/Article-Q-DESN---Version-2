from __future__ import annotations

import importlib.util
import json
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
REPAIR = load("348_repair_pricefm_stage_r103_exal_gate.py")


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


def test_conservative_exal_gate_bound_dominates_exact_diagnostics() -> None:
    rng = np.random.default_rng(802)
    design = rng.normal(size=(37, 11))
    delta = rng.normal(scale=1e-4, size=11)
    scale = 1.7
    state = float(np.max(np.abs(delta)))
    previous = rng.normal(size=11)
    relative_exact = state / max(1.0, float(np.max(np.abs(previous))))
    prediction_exact = float(np.sqrt(np.mean((design @ delta) ** 2)) / scale)
    row_l1_rms = float(np.sqrt(np.mean(np.sum(np.abs(design), axis=1) ** 2)))
    prediction_bound = state * row_l1_rms / scale
    assert relative_exact <= state
    assert prediction_exact <= prediction_bound + 1e-15


def test_exal_gate_repair_preserves_model_artifacts(tmp_path: Path) -> None:
    atom = tmp_path / "atom"
    atom.mkdir()
    (atom / "beta_mean.bin").write_bytes(b"mean")
    (atom / "beta_cov.bin").write_bytes(b"covariance")
    (atom / "parameter_summary.json").write_text('{"sigma": 1.0}\n')
    pd.DataFrame({
        "sigma": [1.0, 1.0],
        "gamma": [0.1, 0.1],
        "delta_state": [0.002, 0.001],
        "delta_sigma": [0.0, 0.0],
        "delta_gamma": [0.0, 0.0],
        "delta_s": [0.0, 0.0],
    }).to_csv(atom / "vb_trace.csv", index=False)
    REPAIR.write_json(atom / "numerical_gate.json", {"checks": {}, "passed": False})
    records = []
    for name, role in (
        ("beta_mean.bin", "beta_mean"),
        ("beta_cov.bin", "beta_cov"),
        ("parameter_summary.json", "parameter_summary"),
        ("vb_trace.csv", "vb_trace"),
        ("numerical_gate.json", "numerical_gate"),
    ):
        path = atom / name
        records.append({
            "path": str(path),
            "role": role,
            "bytes": path.stat().st_size,
            "sha256": REPAIR.sha256_file(path),
        })
    checks = {
        "finite_core": True,
        "formal_converged": True,
        "trace_complete": False,
        "trace_finite": False,
        "coherent_warm_start_recorded": True,
        "structured_updates_at_least_35": True,
        "sigma_below_100": True,
        "gamma_bounded": True,
        "tail_relative_state_below_0p01": False,
        "tail_prediction_scaled_below_0p01": False,
    }
    terminal_path = atom / "terminal.json"
    REPAIR.write_json(terminal_path, {
        "atom_id": "fixture_exal",
        "family": "exal",
        "formal_converged": True,
        "numerical_gate_passed": False,
        "numerical_checks": checks,
        "artifacts": records,
    })
    before = {
        record["role"]: record["sha256"]
        for record in records if record["role"] in REPAIR.PROTECTED_ATOM_ROLES
    }
    result = REPAIR.repair_atom(
        terminal_path,
        {"n": 2, "p": 2, "rms_row_l1": 2.0, "response_scale": 1.0},
        write=True,
    )
    terminal = json.loads(terminal_path.read_text())
    after = {
        record["role"]: REPAIR.sha256_file(record["path"])
        for record in terminal["artifacts"] if record["role"] in REPAIR.PROTECTED_ATOM_ROLES
    }
    assert result["status"] == "repaired"
    assert terminal["numerical_gate_passed"] is True
    assert terminal["diagnostic_gate_method"] == "conservative_bound_repair_v1"
    assert before == after
    assert (atom / "diagnostic_gate_repair.json").is_file()


def test_exal_gate_repair_rejects_a_genuine_failure() -> None:
    terminal = {
        "family": "exal",
        "formal_converged": False,
        "numerical_checks": {
            "finite_core": True,
            "formal_converged": False,
            "trace_complete": False,
        },
    }
    assert REPAIR.repairable(terminal) is False


def test_launch_and_fit_firewalls_are_explicit() -> None:
    prep = (SCRIPTS / "343_prepare_pricefm_stage_r103_recursive_quantile.py").read_text()
    r_source = (SCRIPTS / "344_run_pricefm_stage_r103_quantile_case.R").read_text()
    orchestrator = (SCRIPTS / "347_orchestrate_pricefm_stage_r103_recursive_quantile.py").read_text()
    assert 'path = normalizePath(file.path(atom$output_dir, name), mustWork = FALSE)' in r_source
    assert 'prior_center_from_initializer = FALSE' in r_source
    assert 'deltas <- fit$diagnostics$deltas %||% list()' in r_source
    assert '"exact_runtime_diagnostics"' in r_source
    assert 'retry_max_iter <- max(configured_max_iter, 750L)' in r_source
    assert 'extended_nonconvergence_retry' in r_source
    assert 'joint_model_fitted = FALSE' in r_source
    assert 'mcmc_fitted = FALSE' in r_source
    assert "RUN_PRICEFM_R103_RECURSIVE_QUANTILE" in orchestrator
    assert "core_usage[core]" in orchestrator
    assert "cpu_worker" in orchestrator
    assert '"R/exdqlm.rdb"' in prep
    assert '"libs/exdqlm.so"' in prep
