from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))

import pricefm_r120_engine as R120
import pricefm_r122_runtime as RUNTIME


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = _load(
    "pricefm_r122_launch_prep_test",
    "428_prepare_pricefm_stage_r122_long_memory_launch.py",
)
RUN = _load(
    "pricefm_r122_long_memory_runner_test",
    "429_run_pricefm_stage_r122_long_memory.py",
)


def test_r122_runtime_extends_limits_without_mutating_r120():
    spec = {
        "region": "BG", "feature_policy": "target_only", "calendar": "none",
        "readout": "pure_all_layers", "m_y": 2880, "m_x": 96,
        "source_window": 3120, "warmup_steps": 240, "depth": 2,
        "units": [128, 128], "alpha": .1, "rho": .82,
        "input_scale": .05, "input_fan_in": 32,
        "recurrent_sparsity": .02, "seed": 2026092501,
    }
    assert RUNTIME.normalize_spec(spec)["m_y"] == 2880
    assert RUNTIME.BASE.SOURCE_WINDOW == 3120
    assert R120.SOURCE_WINDOW == 970
    with pytest.raises(ValueError):
        R120.normalize_spec(spec)


def test_r122_internal_splits_are_exact_and_disjoint():
    splits = RUNTIME.internal_splits(940)
    assert [(len(row["train"]), len(row["validation"])) for row in splits] == [
        (506, 125), (631, 135), (766, 174),
    ]
    for row in splits:
        assert set(row["train"]).isdisjoint(set(row["validation"]))
        assert int(row["train"][-1]) + 1 == int(row["validation"][0])
    with pytest.raises(ValueError):
        RUNTIME.internal_splits(939)


def test_test_split_firewall_distinguishes_role_from_harmless_key_names():
    assert RUN._split_is_test({"name": "test", "test_boundary_mode": "half_open"})
    assert RUN._split_is_test({"partition": "historical_test"})
    assert not RUN._split_is_test({
        "name": "train", "test_boundary_mode": "contained_half_open",
    })
    assert not RUN._split_is_test({
        "name": "validation", "test_access_authorized": False,
    })


def test_origin_comparison_is_timezone_and_format_stable():
    assert RUN._same_utc_instant(
        np.datetime64("2022-02-04T00:00:00"),
        "2022-02-04 00:00:00+00:00",
    )
    assert not RUN._same_utc_instant(
        "2022-02-04 00:15:00+00:00",
        "2022-02-04 00:00:00+00:00",
    )


def test_immutable_csv_is_idempotent_and_rejects_manifest_drift(tmp_path):
    path = tmp_path / "manifest.csv"
    frame = pd.DataFrame({"candidate_id": ["a", "b"], "score": [1.0, 2.0]})
    RUN._write_immutable_csv(frame, path)
    original = path.read_bytes()
    RUN._write_immutable_csv(frame.copy(), path)
    assert path.read_bytes() == original
    with pytest.raises(RuntimeError):
        RUN._write_immutable_csv(frame.assign(score=[1.0, 3.0]), path)


def test_tau_center_and_unique_shortlist_contract():
    tau0 = RUN._tau_center(readout_dimension=193, n_ref=1000)
    expected = (14 / (192 - 14)) / np.sqrt(1000)
    assert tau0 == pytest.approx(expected)
    ranking = pd.DataFrame({
        "candidate_id": ["a", "a", "b", "c", "d"],
        "tau0": [1e-4, 1e-3, 1e-4, 1e-4, 1e-4],
        "mean_AQL": [1, 2, 3, 4, 5],
    })
    selected = RUN._unique_al_shortlist(ranking, 3)
    assert selected.candidate_id.tolist() == ["a", "b", "c"]


def test_tau_activation_is_bounded_and_score_driven(tmp_path):
    candidate = "a"; center_tau = 1e-3
    center_dir = tmp_path / f"rhs/center/fits/r122rhs_{candidate}_s3_t{center_tau:.8e}"
    center_dir.mkdir(parents=True)
    np.asarray([1.0, 2.0], dtype="<f8").tofile(center_dir / "beta_mean.bin")
    pilot_rows = []
    for tau0 in (1e-5, 1e-4, 1e-2, 1e-1):
        path = tmp_path / f"rhs/pilot/fits/r122rhs_{candidate}_s3_t{tau0:.8e}"
        path.mkdir(parents=True)
        np.asarray([1.0, 2.0], dtype="<f8").tofile(path / "beta_mean.bin")
        pilot_rows.append({
            "candidate_id": candidate, "tau0": tau0,
            "mean_AQL": 1.0, "mean_coverage": .8,
        })
    center = pd.DataFrame([{
        "candidate_id": candidate, "tau0": center_tau,
        "mean_AQL": 1.0, "mean_coverage": .8,
    }])
    pilot = pd.DataFrame(pilot_rows)
    inactive = RUN._tau_activation(
        tmp_path, {candidate: center_tau}, center, pilot, [candidate],
    )
    assert inactive["active"] is False
    pilot.loc[0, "mean_AQL"] = 1.01
    active = RUN._tau_activation(
        tmp_path, {candidate: center_tau}, center, pilot, [candidate],
    )
    assert active["active"] is True


def test_launch_prep_and_controller_keep_all_prohibited_surfaces_closed():
    prep_source = (
        SCRIPTS / "428_prepare_pricefm_stage_r122_long_memory_launch.py"
    ).read_text().lower()
    runner_source = (
        SCRIPTS / "429_run_pricefm_stage_r122_long_memory.py"
    ).read_text().lower()
    assert '"total_fit_count": int(len(execution))' in prep_source
    assert '"official_test_scoring_authorized": false' in prep_source
    assert '"article_mutation_authorized": false' in prep_source
    assert '"registry_mutation_authorized": false' in prep_source
    assert '"exal_authorized": false' in prep_source
    assert '"mcmc_authorized": false' in prep_source
    assert "rhs_tau_pilot_multipliers" in prep_source
    assert '"cpu_audit_seconds": 10' in prep_source
    assert '_cpu_snapshot(audit_seconds)' in runner_source
    assert "checks = {key: bool(value) for key, value in checks.items()}" in prep_source
    assert "r122_internal_specification_frozen_test_blocked" in runner_source
    assert "_unique_al_shortlist" in runner_source


def test_control_rows_are_external_and_never_test_authorized():
    candidates, fits = PREP._control_rows()
    assert len(candidates) == 1
    assert len(fits) == 2
    assert candidates.iloc[0].role == "external_model_setting_control_refit_on_r122_common_origins"
    assert set(fits.role) == {"external_control"}
    assert candidates.iloc[0].input_dimension > 730
    assert candidates.iloc[0].readout_dimension == 193
    assert not candidates.test_access_authorized.astype(bool).any()
    assert not fits.test_access_authorized.astype(bool).any()
