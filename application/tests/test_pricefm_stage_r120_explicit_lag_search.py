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


def load(relative: str, name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec); assert spec.loader is not None; spec.loader.exec_module(module)
    return module


import pricefm_r120_engine as ENGINE  # noqa: E402
PREP = load("application/scripts/pricefm/413_prepare_pricefm_stage_r120_explicit_lag_search.py", "r120_prep_test")
RUN = load("application/scripts/pricefm/414_run_pricefm_stage_r120_explicit_lag_search.py", "r120_run_test")


def spec(**overrides):
    value = {"region": "BG", "feature_policy": "target_only", "calendar": "none",
        "readout": "pure_all_layers", "m_y": 3, "m_x": 2, "units": [4, 3],
        "alpha": .5, "rho": .82, "input_scale": .15, "input_fan_in": 2,
        "recurrent_sparsity": .5, "seed": 17}
    value.update(overrides); return ENGINE.normalize_spec(value)


def window(region: str, origins: int = 3, shift: float = 0.0):
    lag = np.empty((origins, ENGINE.SOURCE_WINDOW, 4), dtype=float)
    lead = np.empty((origins, 96, 3), dtype=float); response = np.empty((origins, 96), dtype=float)
    for origin in range(origins):
        lag[origin, :, 0] = shift + origin * 10000 + np.arange(ENGINE.SOURCE_WINDOW)
        for column in range(3):
            lag[origin, :, column + 1] = shift + 100000 * (column + 1) + origin * 10000 + np.arange(ENGINE.SOURCE_WINDOW)
            lead[origin, :, column] = shift + 500000 * (column + 1) + origin * 10000 + np.arange(96)
        response[origin] = shift + 900000 + origin * 10000 + np.arange(96)
    return {"X_lag": lag, "X_lead": lead, "Y": response,
        "anchors": np.asarray([f"a{index}" for index in range(origins)]),
        "lag_cols": [f"{region}-price", f"{region}-load", f"{region}-solar", f"{region}-wind"],
        "lead_cols": [f"{region}-load", f"{region}-solar", f"{region}-wind"],
        "path": f"/{region}.npz", "sha256": region, "manifest_path": f"/{region}.json", "manifest_sha256": region + "m"}


def arrays(current_spec=None):
    current_spec = current_spec or spec()
    regions = ENGINE.active_regions(current_spec)
    return ENGINE.explicit_arrays({region: window(region, shift=position * 1e7) for position, region in enumerate(regions)}, current_spec)


def test_source_window_is_maximum_lag_plus_fixed_warmup():
    assert ENGINE.SOURCE_WINDOW == 970
    assert ENGINE.SOURCE_WINDOW == ENGINE.MAX_EXPLICIT_LAG + ENGINE.WARMUP_STEPS


def test_explicit_input_uses_exact_target_and_exogenous_lags():
    current = spec(); value = arrays(current); row = ENGINE.explicit_input(value, current, [0], 0)[0]
    assert row[:3].tolist() == [969.0, 968.0, 967.0]
    # x_t comes from lead horizon zero, then x_(t-1), x_(t-2) from history.
    assert row[3:6].tolist() == [500000.0, 1000000.0, 1500000.0]
    assert row[6:9].tolist() == [100969.0, 200969.0, 300969.0]
    assert row[9:12].tolist() == [100968.0, 200968.0, 300968.0]


def test_recursive_input_replaces_only_target_lags_inside_active_path():
    current = spec(); value = arrays(current); generated = np.asarray([[11.0, 22.0]])
    row = ENGINE.explicit_input(value, current, [0], 2, generated)[0]
    assert row[:3].tolist() == [22.0, 11.0, 969.0]
    # Future exogenous values remain their declared stream, never generated prices.
    assert row[3:6].tolist() == [500002.0, 1000002.0, 1500002.0]


def test_teacher_forcing_uses_observed_training_response():
    current = spec(); value = arrays(current); row = ENGINE.explicit_input(value, current, [0], 2)[0]
    assert row[:3].tolist() == [900001.0, 900000.0, 969.0]


def test_internal_preprocessing_is_fit_only_on_declared_training_origins():
    value = arrays(spec()); scaled, contract = ENGINE.standardize_from_training_origins(value, [0, 1])
    expected = np.concatenate((value.price_history[:2].reshape(-1), value.response[:2].reshape(-1)))
    assert contract["price_mean"] == float(np.mean(expected))
    assert contract["training_origin_count"] == 2
    # The held-out third origin is transformed, but cannot affect the scaler.
    assert not np.isclose(np.mean(scaled.response[2]), 0.0)


def test_warmup_begins_only_after_all_730_lags_are_available():
    current = spec(m_y=730, m_x=730); value = arrays(current)
    first = ENGINE.explicit_input(value, current, [0], -ENGINE.WARMUP_STEPS)[0]
    assert first[0] == 729.0
    assert first[729] == 0.0


def test_graph_policies_never_add_neighbor_price_channels():
    current = spec(feature_policy="graph_neighbor_exogenous"); value = arrays(current)
    assert all("price" not in name for name in value.exog_names)
    assert value.exog_history.shape[-1] == 3 * len(ENGINE.active_regions(current))


def test_readout_identity_is_pure_or_one_copy_of_input():
    states = [np.ones((2, 4)), np.ones((2, 3)) * 2]; transition = np.ones((2, 5)) * 3
    pure = ENGINE.readout_rows(states, transition, "pure_all_layers")
    extended = ENGINE.readout_rows(states, transition, "extended_all_layers")
    assert pure.shape == (2, 8)
    assert extended.shape == (2, 13)
    assert np.array_equal(extended[:, 1:6], transition)


def test_sparse_input_fan_in_is_exact_and_deterministic():
    current = spec(input_fan_in=2); first, _, audit1 = ENGINE.make_reservoir(current, 12); second, _, audit2 = ENGINE.make_reservoir(current, 12)
    assert audit1 == audit2
    assert audit1["layers"][0]["input_nonzero"] == 2 * current["units"][0]
    assert all(np.isclose(layer["realized_spectral_radius"], current["rho"]) for layer in audit1["layers"])
    assert (first["layers"][0]["input"] != second["layers"][0]["input"]).nnz == 0


def test_tiny_end_to_end_ridge_and_recursive_score_is_finite():
    current = spec(m_y=3, m_x=2, units=[4, 3]); value = arrays(current)
    scaled, _ = ENGINE.standardize_from_training_origins(value, [0, 1])
    stats, _ = ENGINE.teacher_forced_statistics(scaled, current, {"fit": np.asarray([0, 1])})
    fit = ENGINE.fit_scaled_ridge(stats["fit"])
    score = ENGINE.recursive_normal_score(scaled, current, fit, [2])
    assert score["origins_scored"] == 1
    assert all(np.isfinite(score[key]) for key in ("AQL", "late_AQL", "median_MAE", "interval_80_width"))


def test_stage_b_is_complete_72_by_4_by_2_cross():
    frame = PREP.stage_b_candidates()
    assert len(frame) == 576
    assert frame[["m_y", "m_x"]].drop_duplicates().shape[0] == 72
    assert set(frame.m_y) == set(PREP.M_Y); assert set(frame.m_x) == set(PREP.M_X)
    assert frame.feature_policy.value_counts().eq(144).all()
    assert frame.units.value_counts().eq(288).all()


def test_resource_dimension_records_distinct_lag_orders():
    estimate = ENGINE.resource_estimate(spec(m_y=32, m_x=48, calendar="compact3"), 6)
    assert estimate["input_dimension"] == 32 + 49 * 6 + 3
    assert estimate["readout_dimension"] == 1 + 4 + 3


def test_stage_c_balanced_bank_has_640_unique_rows(tmp_path: Path):
    retained = []
    for policy in ENGINE.POLICIES:
        for band, pair in zip(("short", "daily", "multi_day", "weekly"), ((32, 0), (96, 48), (336, 192), (730, 672))):
            retained.append({"feature_policy": policy, "memory_band": band, "m_y": pair[0], "m_x": pair[1], "mean_AQL": 1.0})
    frame = RUN._stage_c_manifest(tmp_path, __import__("pandas").DataFrame(retained))
    assert len(frame) == 640
    assert not frame.semantic_sha256.duplicated().any()
    assert frame.units.nunique() == len(RUN.GEOMETRIES)


def test_seed_robustness_manifest_drops_inherited_ranking_results(tmp_path: Path):
    rows = []
    for position in range(10):
        current = spec(seed=RUN.SEEDS[0])
        current["m_y"] = 32 + position
        rows.append({
            "candidate_id": f"primary_{position}", "stage": "R120C",
            "candidate_role": "balanced_geometry_dynamics",
            "semantic_sha256": ENGINE.fingerprint(current),
            "spec_json": json.dumps(current, sort_keys=True, separators=(",", ":")),
            **{key: value for key, value in current.items() if key != "units"},
            "units": json.dumps(current["units"], separators=(",", ":")),
            "ridge_rank": position + 1, "mean_AQL": 1.0 + position,
            "worst_AQL": 2.0 + position, "mean_late_AQL": 1.5 + position,
            "mean_coverage": 0.8,
        })
    seed_manifest = RUN._stage_c_seed_robustness(tmp_path, pd.DataFrame(rows))
    assert len(seed_manifest) == 20
    assert not {"ridge_rank", "mean_AQL", "worst_AQL", "mean_late_AQL", "mean_coverage"} & set(seed_manifest.columns)


def test_ridge_ranking_recomputes_inherited_result_columns(tmp_path: Path):
    manifest = pd.DataFrame([{
        "candidate_id": "seed_candidate", "stage": "R120CSEED",
        "readout_dimension": 8,
        "ridge_rank": 99, "mean_AQL": 99.0, "worst_AQL": 99.0,
        "mean_late_AQL": 99.0, "mean_coverage": 0.0,
    }])
    output = RUN._ridge_root(tmp_path, "R120CSEED", "seed_candidate")
    output.mkdir(parents=True)
    (output / "terminal.json").write_text(json.dumps({
        "status": "completed_r120_ridge_cell", "test_opened": False,
    }))
    pd.DataFrame([
        {"AQL": 2.0, "late_AQL": 3.0, "interval_80_coverage": 0.7},
        {"AQL": 4.0, "late_AQL": 5.0, "interval_80_coverage": 0.9},
    ]).to_csv(output / "validation_metrics.csv", index=False)
    ranking = RUN._ridge_ranking(tmp_path, manifest, "R120CSEED")
    assert ranking.ridge_rank.tolist() == [1]
    assert ranking.mean_AQL.tolist() == [3.0]
    assert ranking.worst_AQL.tolist() == [4.0]
    assert ranking.mean_late_AQL.tolist() == [4.0]
    assert ranking.mean_coverage.tolist() == [0.8]


def test_controller_and_quantile_runner_keep_scientific_firewalls():
    source = (SCRIPTS / "414_run_pricefm_stage_r120_explicit_lag_search.py").read_text()
    atom = (SCRIPTS / "415_fit_pricefm_stage_r120_quantile_atom.R").read_text()
    assert '"joint_model_fitted": False' in source
    assert '"mcmc_fitted": False' in source
    assert "exact CRAN exdqlm 1.1.1" in atom
    assert "prior_center_from_initializer = FALSE" in atom
    assert 'fit_root.mkdir(parents=True, exist_ok=True)' in source


def test_plan_records_explicit_lags_and_fixed_warmup():
    plan = (ROOT / "local_trackers/pricefm_stage_r120_explicit_lag_search_master_plan_20260925.md").read_text()
    assert "m_y in {32, 48, 96, 192, 336, 480, 672, 730}" in plan
    assert "m_x in {0, 32, 48, 96, 192, 336, 480, 672, 730}" in plan
    assert "970" in plan and "240" in plan
