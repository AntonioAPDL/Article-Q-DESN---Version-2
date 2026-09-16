"""Focused tests for PriceFM Stage-R102 recursive Normal preparation."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_recursive_normal as recursive  # noqa: E402


def load_prep():
    path = SCRIPTS / "335_prepare_pricefm_stage_r102_recursive_normal.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_orchestrator():
    path = SCRIPTS / "338_orchestrate_pricefm_stage_r102_recursive_normal.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load_prep()
ORCHESTRATOR = load_orchestrator()


def toy_window(n_origins: int = 3, lag: int = 4) -> dict:
    rng = np.random.default_rng(14)
    x_lag = rng.normal(size=(n_origins, lag, 4))
    x_lead = rng.normal(size=(n_origins, 96, 3))
    y = rng.normal(size=(n_origins, 96))
    return {
        "X_lag": x_lag,
        "X_lead": x_lead,
        "Y": y,
        "anchors": np.asarray([f"origin-{i}" for i in range(n_origins)], dtype=object),
        "lag_cols": np.asarray(["AT-price", "AT-load", "AT-solar", "AT-wind"], dtype=object),
        "lead_cols": np.asarray(["AT-load", "AT-solar", "AT-wind"], dtype=object),
    }


def toy_spec() -> dict:
    return {
        "region": "AT",
        "feature_policy": "target_only",
        "lag_window": 4,
        "depth": 2,
        "units": [3, 2],
        "alpha": 0.3,
        "rho": 0.8,
        "input_scale": 0.2,
        "state_output": "final_layer",
        "seed": 71,
        "spatial": {"graph_degree": 0},
        "tau0": 0.01,
    }


def test_causal_statistics_are_bounded_and_horizon_one_exact() -> None:
    result = recursive.causal_teacher_forced_statistics(
        {"AT": toy_window()}, toy_spec(), input_regions=["AT"]
    )
    assert result["n"] == 3 * 96
    assert result["XtX"].shape == (result["p"], result["p"])
    assert result["Xty"].shape == (result["p"],)
    assert result["horizon_one_parity_max_abs"] <= 1e-12
    assert result["training_timing"].startswith("initialize_L_minus_1")
    assert result["test_opened"] is False


def test_teacher_forcing_uses_previous_response_after_horizon_one() -> None:
    first = toy_window()
    second = {key: np.array(value, copy=True) if isinstance(value, np.ndarray) else value for key, value in first.items()}
    second["Y"][:, 0] += 20.0
    stats_first = recursive.causal_teacher_forced_statistics({"AT": first}, toy_spec(), ["AT"])
    stats_second = recursive.causal_teacher_forced_statistics({"AT": second}, toy_spec(), ["AT"])
    assert not np.allclose(stats_first["XtX"], stats_second["XtX"])
    assert stats_first["horizon_one_parity_max_abs"] == stats_second["horizon_one_parity_max_abs"] == 0.0


def test_recursive_future_block_uses_canonical_region_price_column() -> None:
    block = recursive._future_block(toy_window(), "AT")
    assert block["lag_cols"][0] == "AT-price"
    broken = toy_window()
    broken["lag_cols"] = np.asarray(["AT-demand", "AT-load", "AT-solar", "AT-wind"], dtype=object)
    try:
        recursive._future_block(broken, "AT")
    except ValueError as error:
        assert "target-price column" in str(error)
    else:
        raise AssertionError("missing region-price column must fail closed")


def test_statistics_binary_round_trip(tmp_path: Path) -> None:
    result = recursive.causal_teacher_forced_statistics({"AT": toy_window()}, toy_spec(), ["AT"])
    terminal = recursive.write_statistics(tmp_path / "stats", result)
    assert terminal["status"] == "completed_causal_sufficient_statistics"
    restored = recursive.read_float64(tmp_path / "stats/XtX.bin", result["XtX"].shape)
    np.testing.assert_allclose(restored, result["XtX"])
    assert json.loads((tmp_path / "stats/statistics.json").read_text())["test_opened"] is False


def test_statistics_force_atomically_replaces_incomplete_packet(tmp_path: Path) -> None:
    output = tmp_path / "stats"
    output.mkdir()
    (output / "partial.bin").write_bytes(b"interrupted")
    result = recursive.causal_teacher_forced_statistics({"AT": toy_window()}, toy_spec(), ["AT"])
    terminal = recursive.write_statistics(output, result, force=True)
    assert terminal["status"] == "completed_causal_sufficient_statistics"
    assert not (output / "partial.bin").exists()
    assert (output / "terminal.json").is_file()


def test_r102_manifest_is_bounded_and_test_free() -> None:
    args = PREP.parser().parse_args([])
    bundle = PREP.build(args)
    assert len(bundle["designs"]) == 144
    assert bundle["fits"].prior_type.value_counts().to_dict() == {"rhs_ns": 147, "scaled_ridge": 144}
    assert len(bundle["panels"]) == 228
    assert set(bundle["windows"].split) == {"train", "val"}
    assert bundle["fits"].test_access_authorized.eq(False).all()
    assert bundle["summary"]["quantile_fit_authorized"] is False
    assert bundle["summary"]["launch_authorized"] is False


def test_posterior_target_hash_separates_tau0_but_not_initialization() -> None:
    first = recursive.posterior_target_hash("a" * 64, "rhs_ns", 0.01)
    second = recursive.posterior_target_hash("a" * 64, "rhs_ns", 0.02)
    assert first != second
    assert first == recursive.posterior_target_hash("a" * 64, "rhs_ns", 0.01)


def test_launch_prep_source_keeps_later_surfaces_blocked() -> None:
    prep = (SCRIPTS / "335_prepare_pricefm_stage_r102_recursive_normal.py").read_text()
    runner = (SCRIPTS / "336_fit_pricefm_stage_r102_recursive_normal.R").read_text()
    assert '"quantile_fit_authorized": False' in prep
    assert '"joint_fit_authorized": False' in prep
    assert '"mcmc_authorized": False' in prep
    assert '"registry_mutation_authorized": False' in prep
    assert '"article_mutation_authorized": False' in prep
    assert "test_access_authorized" in runner


def test_orchestrator_cpu_and_boolean_contracts() -> None:
    assert ORCHESTRATOR.parse_cpus("0-2,4") == [0, 1, 2, 4]
    assert ORCHESTRATOR.truthy(True)
    assert ORCHESTRATOR.truthy("TRUE")
    assert not ORCHESTRATOR.truthy(False)
    assert not ORCHESTRATOR.truthy("False")


def test_orchestrator_requires_frozen_source_and_explicit_approval() -> None:
    source = (SCRIPTS / "338_orchestrate_pricefm_stage_r102_recursive_normal.py").read_text()
    assert "RUN_PRICEFM_R102_RECURSIVE_NORMAL" in source
    assert 'identity["head"] == identity["upstream_head"]' in source
    assert 'identity["branch"].startswith("work/pricefm-")' in source
    assert "R102 source hash mismatch" in source
    assert "R102 split firewall failed" in source


def test_prep_hashes_every_r102_execution_entrypoint() -> None:
    args = PREP.parser().parse_args([])
    source_names = {Path(path).name for path in PREP.build(args)["sources"].path}
    assert {
        "pricefm_recursive_normal.py",
        "pricefm_recursive_normal_fit.R",
        "335_prepare_pricefm_stage_r102_recursive_normal.py",
        "336_fit_pricefm_stage_r102_recursive_normal.R",
        "337_build_pricefm_stage_r102_recursive_statistics.py",
        "338_orchestrate_pricefm_stage_r102_recursive_normal.py",
    } <= source_names
