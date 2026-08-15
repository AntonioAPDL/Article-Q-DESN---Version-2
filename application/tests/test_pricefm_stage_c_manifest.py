"""Tests for preparing the PriceFM Stage-C expansion manifest."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def score(region, phase1=7.0, spread=500.0, negative=0.01):
    return {
        "region": region,
        "phase1_AQL": phase1,
        "phase1_MAE": 2.0 * phase1,
        "phase1_RMSE": 3.0 * phase1,
        "median": 50.0,
        "spread_p99_p01": spread,
        "tail_range": spread * 2.0,
        "negative_rate": negative,
        "zero_rate": 0.0,
        "min": -10.0,
        "p01": 0.0,
        "p99": spread,
        "max": spread + 100.0,
    }


def scores():
    return pd.DataFrame([
        score("AT", phase1=7.0),
        score("FI", phase1=9.0),
        score("PL", phase1=8.0),
        score("EE", phase1=15.0),
        score("LV", phase1=13.0),
        score("LT", phase1=12.0),
        score("DE_LU", phase1=5.0, negative=0.04),
        score("CZ", phase1=6.0),
        score("HU", phase1=8.0, spread=590.0),
        score("IT_NORD", phase1=6.0),
        score("SI", phase1=6.0),
        score("SE_4", phase1=7.5, negative=0.04),
    ])


def evaluated():
    return pd.DataFrame([
        {
            "region": "AT",
            "fold": 2,
            "promotion_label": "confirmed_win",
            "rel_delta": -0.01,
            "worst_horizon_group": "25-48",
            "worst_horizon_delta": 1.0,
        },
        {
            "region": "FI",
            "fold": 3,
            "promotion_label": "evaluated_loss",
            "rel_delta": 0.10,
            "worst_horizon_group": "1-24",
            "worst_horizon_delta": 2.5,
        },
        {
            "region": "PL",
            "fold": 2,
            "promotion_label": "confirmed_win",
            "rel_delta": -0.07,
            "worst_horizon_group": "1-24",
            "worst_horizon_delta": 0.7,
        },
        {
            "region": "DE_LU",
            "fold": 1,
            "promotion_label": "confirmed_win",
            "rel_delta": -0.1,
            "worst_horizon_group": "",
            "worst_horizon_delta": 0.0,
        },
        {
            "region": "DE_LU",
            "fold": 2,
            "promotion_label": "confirmed_win",
            "rel_delta": -0.1,
            "worst_horizon_group": "",
            "worst_horizon_delta": 0.0,
        },
        {
            "region": "DE_LU",
            "fold": 3,
            "promotion_label": "confirmed_win",
            "rel_delta": -0.1,
            "worst_horizon_group": "",
            "worst_horizon_delta": 0.0,
        },
    ])


def exceptions():
    return pd.DataFrame([
        {
            "region": "FI",
            "fold": 3,
            "exception_label": "needs_short_horizon_rescue",
            "best_method": "qdesn_exal_rhs_ns_exact_chunked",
            "best_AQL": 8.1,
            "pricefm_AQL": 7.2,
            "delta": 0.9,
            "rel_delta": 0.12,
            "worst_horizon_group": "1-24",
            "worst_horizon_delta": 2.5,
        }
    ])


def test_stage_c_manifest_splits_completion_new_regions_and_exceptions():
    mod = load_script("50_prepare_pricefm_stage_c_manifest.py")

    manifest, exception_rows = mod.build_manifest(
        scores(),
        scores()["region"].tolist(),
        evaluated(),
        exceptions(),
        ["EE", "LV"],
        [1, 2, 3],
        allow_retest=False,
    )

    completion = manifest[manifest["queue"].eq("completion_folds")]
    new_regions = manifest[manifest["queue"].eq("diverse_new_regions")]
    assert set(zip(completion["region"], completion["fold"])) == {
        ("AT", 1), ("AT", 3), ("FI", 1), ("FI", 2), ("PL", 1), ("PL", 3)
    }
    assert set(zip(new_regions["region"], new_regions["fold"])) == {
        ("EE", 1), ("EE", 2), ("EE", 3), ("LV", 1), ("LV", 2), ("LV", 3)
    }
    assert set(completion["caution_label"]) == {
        "narrow_existing_win",
        "existing_fold_exception",
        "short_horizon_fragile_existing_win",
    }
    assert exception_rows.shape[0] == 1
    assert exception_rows.loc[0, "queue"] == "exception_rescue"
    assert exception_rows.loc[0, "recommended_next_gate"] == "short_horizon_rescue"
    assert ("FI", 3) not in set(zip(manifest["region"], manifest["fold"]))
    assert manifest[["region", "fold"]].duplicated().sum() == 0
    assert manifest["recommended_next_gate"].eq("median_screen").all()


def test_stage_c_manifest_rejects_queue2_region_already_evaluated():
    mod = load_script("50_prepare_pricefm_stage_c_manifest.py")

    try:
        mod.build_manifest(
            scores(),
            scores()["region"].tolist(),
            evaluated(),
            exceptions(),
            ["AT"],
            [1, 2, 3],
            allow_retest=False,
        )
    except ValueError as exc:
        assert "already has evaluated Stage-B rows" in str(exc)
    else:
        raise AssertionError("evaluated Queue 2 region should fail")


def test_stage_c_manifest_rejects_duplicate_rows():
    mod = load_script("50_prepare_pricefm_stage_c_manifest.py")
    manifest, _ = mod.build_manifest(
        scores(),
        scores()["region"].tolist(),
        evaluated(),
        exceptions(),
        ["EE"],
        [1, 2, 3],
        allow_retest=False,
    )
    bad = pd.concat([manifest, manifest.iloc[[0]]], ignore_index=True)

    try:
        mod.validate_manifest(bad, scores()["region"].tolist(), [1, 2, 3])
    except ValueError as exc:
        assert "duplicate region/fold" in str(exc)
    else:
        raise AssertionError("duplicate rows should fail validation")


def test_stage_c_manifest_rejects_unknown_queue2_region():
    mod = load_script("50_prepare_pricefm_stage_c_manifest.py")

    try:
        mod.build_manifest(
            scores(),
            scores()["region"].tolist(),
            evaluated(),
            exceptions(),
            ["UNKNOWN"],
            [1, 2, 3],
            allow_retest=False,
        )
    except ValueError as exc:
        assert "missing from score universe" in str(exc)
    else:
        raise AssertionError("unknown Queue 2 region should fail")
