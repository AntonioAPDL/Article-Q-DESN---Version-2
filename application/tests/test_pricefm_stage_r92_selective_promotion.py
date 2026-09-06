"""Tests for the frozen PriceFM R92 selective materialization."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/289_materialize_pricefm_stage_r92_selective_promotion.py"


def load_script():
    spec = importlib.util.spec_from_file_location("pricefm_r92", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_r92_requires_explicit_coordinator_authorization(tmp_path):
    module = load_script()
    with pytest.raises(PermissionError, match="authorize-registry-promotion"):
        module.run(SimpleNamespace(output_dir=tmp_path / "unauthorized", authorize_registry_promotion=False))


def test_r92_materializes_exact_frozen_selective_update(tmp_path):
    module = load_script()
    if not module.DATA_ROOT.is_dir():
        pytest.skip("Frozen PriceFM evidence is not mounted")
    output = tmp_path / "r92"
    summary = module.run(SimpleNamespace(
        output_dir=output,
        authorize_registry_promotion=True,
        allow_test_output=True,
    ))

    assert summary["status"] == "completed"
    assert summary["promoted_rows"] == 12
    assert summary["unchanged_rows"] == 102
    assert summary["promoted_exal_rows"] == 11
    assert summary["promoted_al_rows"] == 1
    assert summary["likelihood_family_changes"] == 1
    assert summary["decision_counts"] == {
        "qdesn_wins": 66, "qdesn_close": 12, "pricefm_wins": 36,
    }
    direct = summary["direct_comparison_metrics"]
    assert np.isclose(direct["qdesn"]["AQL"], 6.823677420470439, atol=1e-12)
    assert np.isclose(direct["qdesn"]["AQCR_percent"], 2.579293032015585, atol=1e-12)
    assert np.isclose(direct["qdesn"]["MAE"], 16.721997707630997, atol=1e-12)
    assert np.isclose(direct["qdesn"]["RMSE"], 25.449231419703835, atol=1e-12)
    assert summary["full_candidate_surface_promoted"] is False
    assert np.isclose(summary["full_56_candidate_mean_AQL"], 6.704209343364271, atol=1e-12)
    assert summary["models_fitted"] is False
    assert summary["selection_changed_after_test"] is False

    registry = pd.read_csv(output / "pricefm_full_surface_decision_registry.csv")
    historical = pd.read_csv(module.HISTORICAL / "pricefm_full_surface_decision_registry.csv")
    ledger = pd.read_csv(output / "pricefm_stage_r92_promotion_ledger.csv")
    promoted = pd.read_csv(output / "pricefm_stage_r92_promoted_case_metrics.csv")
    assert len(registry) == registry[["region", "fold"]].drop_duplicates().shape[0] == 114
    assert len(ledger) == len(promoted) == 12
    observed = {
        (str(row.region), int(row.fold)): str(row.selected_family)
        for row in promoted.itertuples(index=False)
    }
    assert observed == module.EXPECTED_PROMOTIONS
    assert (ledger.promoted_qdesn_AQL < ledger.old_qdesn_AQL).all()
    assert (ledger.promoted_qdesn_AQL < ledger.pricefm_AQL).all()

    pricefm_columns = [name for name in historical.columns if name.startswith("pricefm_")]
    old_sorted = historical.sort_values(["region", "fold"]).reset_index(drop=True)
    new_sorted = registry.sort_values(["region", "fold"]).reset_index(drop=True)
    pd.testing.assert_frame_equal(old_sorted[pricefm_columns], new_sorted[pricefm_columns])
    promoted_keys = set(module.EXPECTED_PROMOTIONS)
    old_non = old_sorted[
        ~old_sorted.apply(lambda row: (str(row.region), int(row.fold)) in promoted_keys, axis=1)
    ].reset_index(drop=True)
    new_non = new_sorted[
        ~new_sorted.apply(lambda row: (str(row.region), int(row.fold)) in promoted_keys, axis=1)
    ].reset_index(drop=True)
    pd.testing.assert_frame_equal(old_non, new_non)

    old_h = pd.read_csv(module.HISTORICAL / "pricefm_full_surface_horizon_diagnostics.csv")
    new_h = pd.read_csv(output / "pricefm_full_surface_horizon_diagnostics.csv")
    joined = old_h.merge(
        new_h, on=["region", "fold", "source_class", "horizon_group"],
        suffixes=("_old", "_new"), validate="one_to_one",
    )
    changed = joined[
        ~np.isclose(
            joined.horizon_delta_AQL_qdesn_minus_pricefm_old,
            joined.horizon_delta_AQL_qdesn_minus_pricefm_new,
            atol=1e-14, rtol=0.0,
        )
    ]
    assert len(joined) == 288
    assert len(changed) == 20
    assert changed[["region", "fold"]].drop_duplicates().shape[0] == 5
    horizon_summary = pd.read_csv(output / "pricefm_full_surface_horizon_summary.csv")
    assert horizon_summary.qdesn_wins.tolist() == [22, 45, 34, 42]
    assert np.allclose(
        horizon_summary.mean_delta_AQL,
        [0.41515480326196835, -0.6835525620342087, -0.1983022078010112, -0.15547452528154534],
        atol=1e-12, rtol=0.0,
    )

    stored = json.loads((output / "summary.json").read_text())
    for name, expected in stored["output_sha256"].items():
        assert digest(output / Path(stored["outputs"][name]).name) == expected

    second = tmp_path / "r92_second"
    module.run(SimpleNamespace(
        output_dir=second,
        authorize_registry_promotion=True,
        allow_test_output=True,
    ))
    for name in (
        "pricefm_full_surface_decision_registry.csv",
        "pricefm_full_surface_method_summary.csv",
        "pricefm_full_surface_horizon_diagnostics.csv",
        "pricefm_full_surface_horizon_summary.csv",
        "pricefm_stage_r92_promoted_case_metrics.csv",
        "pricefm_stage_r92_promotion_ledger.csv",
        "source_manifest.csv",
        "pricefm_stage_r92_selective_promotion_report.md",
    ):
        assert digest(output / name) == digest(second / name)

    with pytest.raises(FileExistsError, match="new directory"):
        module.run(SimpleNamespace(
            output_dir=output,
            authorize_registry_promotion=True,
            allow_test_output=True,
        ))
