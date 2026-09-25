from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import threading

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import pricefm_r117_engine as engine  # noqa: E402


def load(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PREP = load(
    "application/scripts/pricefm/399_prepare_pricefm_stage_r117_bg_pilot.py",
    "pricefm_r117_prep",
)
CONTROLLER = load(
    "application/scripts/pricefm/400_run_pricefm_stage_r117_bg_pilot.py",
    "pricefm_r117_controller",
)


def spec(**overrides) -> dict:
    value = {
        "region": "BG",
        "feature_policy": "target_only",
        "calendar": "none",
        "readout": "pure_all_layers",
        "lag_window": 4,
        "depth": 2,
        "units": [3, 2],
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.25,
        "recurrent_sparsity": 0.1,
        "seed": 117,
    }
    value.update(overrides)
    return value


def window(region: str, *, origins: int = 64, offset: float = 0.0) -> dict:
    lag = np.empty((origins, 4, 4), dtype=float)
    lead = np.empty((origins, 96, 3), dtype=float)
    response = np.empty((origins, 96), dtype=float)
    for origin in range(origins):
        lag[origin, :, 0] = offset + origin * 1000 + np.arange(4)
        for column in range(1, 4):
            lag[origin, :, column] = offset + column * 100 + np.arange(4)
        for column in range(3):
            lead[origin, :, column] = offset + 10000 + column * 100 + np.arange(96)
        response[origin] = offset + 20000 + np.arange(96)
    return {
        "X_lag": lag,
        "X_lead": lead,
        "Y": response,
        "anchors": np.asarray([f"anchor-{index}" for index in range(origins)]),
        "lag_cols": [f"{region}-price", f"{region}-load", f"{region}-solar", f"{region}-wind"],
        "lead_cols": [f"{region}-load", f"{region}-solar", f"{region}-wind"],
        "path": f"/{region}.npz",
        "sha256": region.lower(),
        "manifest_path": f"/{region}.manifest.json",
        "manifest_sha256": f"manifest-{region.lower()}",
    }


def windows() -> dict[str, dict]:
    return {
        "BG": window("BG", offset=0.0),
        "GR": window("GR", offset=100000.0),
        "RO": window("RO", offset=200000.0),
    }


def test_active_regions_excludes_graph_self_entry() -> None:
    assert engine.active_regions(spec(feature_policy="target_only")) == ["BG"]
    assert engine.active_regions(spec(feature_policy="graph_summary_mean")) == ["BG", "GR", "RO"]


def test_corrected_transition_uses_previous_price_and_current_exogenous() -> None:
    source = {"BG": windows()["BG"]}
    arrays = engine.corrected_arrays(source, spec())
    target = source["BG"]
    np.testing.assert_array_equal(arrays.history[:, :, 0], target["X_lag"][:, :-1, 0])
    np.testing.assert_array_equal(arrays.history[:, :, 1:], target["X_lag"][:, 1:, 1:])
    np.testing.assert_array_equal(arrays.future_teacher[:, 0, 0], target["X_lag"][:, -1, 0])
    np.testing.assert_array_equal(arrays.future_teacher[:, 1:, 0], target["Y"][:, :-1])
    np.testing.assert_array_equal(arrays.future_teacher[:, :, 1:], target["X_lead"])


def test_neighbor_policies_use_exogenous_values_but_never_neighbor_prices() -> None:
    source = windows()
    selected = spec(feature_policy="graph_neighbor_exogenous")
    baseline = engine.corrected_arrays(source, selected)

    changed_price = {name: dict(value) for name, value in source.items()}
    changed_price["GR"]["X_lag"] = source["GR"]["X_lag"].copy()
    changed_price["GR"]["X_lag"][:, :, 0] += 9e6
    changed_price["GR"]["Y"] = source["GR"]["Y"].copy() + 9e6
    price_result = engine.corrected_arrays(changed_price, selected)
    np.testing.assert_array_equal(baseline.history, price_result.history)
    np.testing.assert_array_equal(baseline.future_teacher, price_result.future_teacher)

    changed_exogenous = {name: dict(value) for name, value in source.items()}
    changed_exogenous["GR"]["X_lead"] = source["GR"]["X_lead"].copy()
    changed_exogenous["GR"]["X_lead"][:, :, 0] += 7.0
    exogenous_result = engine.corrected_arrays(changed_exogenous, selected)
    assert not np.array_equal(baseline.future_teacher, exogenous_result.future_teacher)


def test_pure_readout_is_intercept_plus_every_layer_only() -> None:
    states = [np.arange(6, dtype=float).reshape(2, 3), np.arange(4, dtype=float).reshape(2, 2)]
    transition = np.full((2, 4), 99.0)
    pure = engine.readout_rows(states, transition, "pure_all_layers")
    extended = engine.readout_rows(states, transition, "extended_all_layers")
    assert pure.shape == (2, 6)
    np.testing.assert_array_equal(pure[:, 0], np.ones(2))
    np.testing.assert_array_equal(pure[:, 1:4], states[0])
    np.testing.assert_array_equal(pure[:, 4:], states[1])
    assert not np.any(pure == 99.0)
    np.testing.assert_array_equal(extended[:, 1:5], transition)
    np.testing.assert_array_equal(extended[:, 5:], np.column_stack(states))


def test_calendar_and_recurrent_sparsity_are_explicit_and_reproducible() -> None:
    arrays = engine.corrected_arrays(
        {"BG": windows()["BG"]}, spec(calendar="compact3")
    )
    assert arrays.history.shape[-1] == 7
    assert arrays.future_teacher.shape[-1] == 7
    assert arrays.input_names[-3:] == (
        "calendar::quarter_scaled", "calendar::sin_day", "calendar::cos_day"
    )
    first, _ = engine.make_reservoir(spec(recurrent_sparsity=0.05), 4)
    repeated, _ = engine.make_reservoir(spec(recurrent_sparsity=0.05), 4)
    changed, _ = engine.make_reservoir(spec(recurrent_sparsity=0.20), 4)
    for left, right in zip(first["layers"], repeated["layers"]):
        np.testing.assert_array_equal(left["recurrent"], right["recurrent"])
    assert any(
        not np.array_equal(left["recurrent"], right["recurrent"])
        for left, right in zip(first["layers"], changed["layers"])
    )


def test_internal_splits_are_strictly_temporal_and_validation_only() -> None:
    splits = engine.internal_splits(100)
    assert len(splits) == 3
    assert [len(item["validation"]) for item in splits] == [13, 14, 18]
    for item in splits:
        assert item["train"][-1] < item["validation"][0]
        assert np.all(np.diff(item["train"]) == 1)
        assert np.all(np.diff(item["validation"]) == 1)


def test_candidate_bank_is_balanced_pure_and_covers_every_factor(tmp_path: Path) -> None:
    registry = tmp_path / "registry.csv"
    registry.write_text(
        "region,fold,units,lag_window,alpha,rho,input_scale\n"
        'BG,1,"[40,40,40]",240,0.25,0.82,0.35\n'
    )
    frame = PREP.candidate_frame(registry, 240)
    assert len(frame) == 240
    assert frame.feature_policy.value_counts().to_dict() == {
        "target_only": 60,
        "graph_summary_mean": 60,
        "graph_summary_mean_std": 60,
        "graph_neighbor_exogenous": 60,
    }
    assert set(frame.readout) == {"pure_all_layers"}
    assert set(frame.calendar) == set(PREP.CALENDARS)
    assert set(frame.lag_window) == set(PREP.LAGS)
    assert set(frame.recurrent_sparsity) == set(PREP.SPARSITIES)
    assert not frame.test_access_authorized.astype(bool).any()


def test_preparation_source_contains_no_test_or_mutation_authority() -> None:
    source = (SCRIPTS / "399_prepare_pricefm_stage_r117_bg_pilot.py").read_text()
    assert '"test_opened": False' in source
    assert '"registry_mutation_authorized": False' in source
    assert '"article_mutation_authorized": False' in source
    assert '"joint_model_authorized": False' in source
    assert '"mcmc_authorized": False' in source
    assert '"readout": "pure_all_layers"' in source
    assert 'source_train_validation_data.yaml' in source
    assert json.loads(json.dumps(list(PREP.GEOMETRIES)))


def test_physical_core_guard_includes_busy_siblings(monkeypatch) -> None:
    identities = {0: (0, 0), 32: (0, 0), 1: (1, 0), 33: (1, 0)}
    monkeypatch.setattr(CONTROLLER, "_physical_core", lambda cpu: identities[cpu])
    usage = {0: 0.0, 32: 87.0, 1: 4.0, 33: 3.0}
    assert CONTROLLER._physical_core_max_usage(0, usage) == 87.0
    assert CONTROLLER._physical_core_max_usage(1, usage) == 4.0


def test_variant_paths_keep_pure_and_extended_artifacts_separate(tmp_path: Path) -> None:
    assert CONTROLLER._variant_root(tmp_path, "pure") == tmp_path
    assert CONTROLLER._variant_root(tmp_path, "extended") == tmp_path / "extended"
    assert CONTROLLER._winner_path(tmp_path, "pure").name == "winner.json"
    assert CONTROLLER._winner_path(tmp_path, "extended").name == "extended_winner.json"


def test_screening_queue_records_failures_and_finishes_other_tasks(tmp_path: Path, monkeypatch) -> None:
    attempted = []
    lock = threading.Lock()

    def fake_command(command, cwd, log, cpu):
        with lock:
            attempted.append(command[0])
        if command[0] == "bad":
            raise RuntimeError("deliberate screening failure")

    monkeypatch.setattr(CONTROLLER, "_command", fake_command)
    tasks = [
        ("ok-1", ["ok-1"], tmp_path / "ok-1.log"),
        ("bad", ["bad"], tmp_path / "bad.log"),
        ("ok-2", ["ok-2"], tmp_path / "ok-2.log"),
    ]
    progress = tmp_path / "progress.json"
    state = CONTROLLER._run_queue(
        tasks, [0, 1], tmp_path, progress, fail_fast=False,
    )
    assert sorted(attempted) == ["bad", "ok-1", "ok-2"]
    assert state["complete"] == 2
    assert state["failed"] == 1
    assert state["failed_task_ids"] == ["bad"]
    assert json.loads(progress.read_text())["failed"] == 1


def test_complete_screening_groups_require_all_three_splits() -> None:
    import pandas as pd

    cells = pd.DataFrame([
        {"candidate_id": "complete", "tau0": 0.1, "split": split, "AQL": float(split)}
        for split in (1, 2, 3)
    ] + [
        {"candidate_id": "incomplete", "tau0": 0.2, "split": split, "AQL": float(split)}
        for split in (1, 2)
    ])
    eligible = CONTROLLER._complete_screening_groups(
        cells, ["candidate_id", "tau0"],
    )
    assert set(eligible.candidate_id) == {"complete"}
    assert set(eligible.split) == {1, 2, 3}


def test_full_fold_normal_contract_can_extend_iteration_ceiling(tmp_path: Path) -> None:
    stats = tmp_path / "stats"
    stats.mkdir()
    (stats / "terminal.json").write_text('{"status":"completed_causal_sufficient_statistics"}')
    contract = CONTROLLER._normal_contract(
        "final-fold", stats, tmp_path / "fit", 1e-4,
        {"normal_runtime": "/runtime"}, tmp_path, max_iter=1000,
    )
    assert contract["max_iter"] == 1000
    assert contract["min_iter"] == 100
    assert contract["convergence_mode"] == "predictive_fixed_point"
