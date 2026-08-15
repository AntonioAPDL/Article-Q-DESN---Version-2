"""Tests for Stage-E PriceFM full-panel quantile completion helpers."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

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


def write_csv(path, rows):
    pd.DataFrame(rows).to_csv(path, index=False)


def median_row(region, fold):
    return {
        "region": region,
        "fold": fold,
        "experiment_id": "exp_{}_{}".format(region.lower(), fold),
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selection_metric_value": 1.0 + fold,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260619,
    }


def decision_row(region, fold, label, *, local=1.0, pricefm=2.0, graph=False):
    row = {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "local_AQL": local,
        "pricefm_AQL": pricefm,
        "delta_abs": local - pricefm,
        "delta_rel": (local - pricefm) / pricefm,
        "stage_c_quantile_decision": label,
        "stage_c_recommendation": "promote_local_candidate",
    }
    if graph:
        row.update({
            "feature_policy": "graph_khop",
            "input_scope": "pricefm_graph_khop_degree1",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "pricefm_released_graph_khop",
            "graph_degree": 1,
            "graph_source": "PriceFM.graph_adj_matrix",
            "graph_hash": "abc123",
        })
    return row


def write_inputs(tmp_path):
    write_csv(tmp_path / "median.csv", [
        median_row("A", 1),
        median_row("A", 2),
        median_row("B", 1),
        median_row("B", 2),
    ])
    write_csv(tmp_path / "old.csv", [
        decision_row("A", 1, "stage_c_pricefm_fallback", local=3.0, pricefm=2.0),
        decision_row("A", 2, "stage_c_confirmed_local_win", local=1.0, pricefm=2.0),
    ])
    write_csv(tmp_path / "new.csv", [
        decision_row("A", 1, "stage_c_confirmed_local_win", local=1.0, pricefm=2.0, graph=True),
        decision_row("B", 1, "stage_c_pricefm_fallback", local=4.0, pricefm=2.0),
    ])
    write_csv(tmp_path / "stage_e.csv", [
        decision_row("B", 2, "stage_c_local_close_to_pricefm", local=2.05, pricefm=2.0),
    ])


def test_prepare_stage_e_missing_registry(tmp_path):
    mod = load_script("56_prepare_pricefm_stage_e_quantile_completion.py")
    write_inputs(tmp_path)

    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        decision_source=[
            "old={}".format(tmp_path / "old.csv"),
            "new={}".format(tmp_path / "new.csv"),
        ],
        output_dir=str(tmp_path / "out"),
        stage_label="unit_stage_e",
    )
    summary = mod.prepare(args)
    missing = pd.read_csv(tmp_path / "out" / "stage_e_missing_quantile_registry.csv")
    coverage = pd.read_csv(tmp_path / "out" / "stage_e_coverage_audit.csv")

    assert summary["n_median_rows"] == 4
    assert summary["n_covered_region_folds"] == 3
    assert summary["n_missing_region_folds"] == 1
    assert list(missing[["region", "fold"]].itertuples(index=False, name=None)) == [("B", 2)]
    assert set(coverage["stage_e_action"]) == {
        "already_frozen",
        "needs_paper_quantile_completion",
    }


def test_authoritative_decision_merge_uses_later_precedence(tmp_path):
    mod = load_script("57_freeze_pricefm_authoritative_quantile_decisions.py")
    write_inputs(tmp_path)

    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        decision_source=[
            "old={}".format(tmp_path / "old.csv"),
            "new={}".format(tmp_path / "new.csv"),
            "stage_e={}".format(tmp_path / "stage_e.csv"),
        ],
        output_dir=str(tmp_path / "merged"),
        registry_id="unit_authoritative",
        notes="unit",
    )
    summary = mod.freeze(args)
    registry = pd.read_csv(tmp_path / "merged" / "authoritative_quantile_decision_registry.csv")
    a1 = registry[(registry["region"] == "A") & (registry["fold"] == 1)].iloc[0]

    assert summary["n_region_folds"] == 4
    assert summary["n_promoted_local"] == 2
    assert summary["n_close_to_pricefm"] == 1
    assert summary["n_pricefm_fallback"] == 1
    assert a1["decision_source"] == "new"
    assert a1["stage_c_quantile_decision"] == "stage_c_confirmed_local_win"
    assert a1["feature_policy"] == "graph_khop"
    assert a1["input_scope"] == "pricefm_graph_khop_degree1"
    assert a1["spatial_information_set"] == "pricefm_released_graph_khop"


def test_authoritative_decision_merge_accepts_prior_authoritative_source(tmp_path):
    mod = load_script("57_freeze_pricefm_authoritative_quantile_decisions.py")
    write_inputs(tmp_path)

    prior = pd.read_csv(tmp_path / "stage_e.csv")
    prior["experiment_id"] = "prior_decision_exp"
    prior["experiment_id_median_registry"] = "old_median_exp"
    prior["feature_policy_median_registry"] = "target_only"
    prior["input_scope_median_registry"] = "local_target_only"
    prior.to_csv(tmp_path / "prior_authoritative.csv", index=False)

    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        decision_source=[
            "old={}".format(tmp_path / "old.csv"),
            "new={}".format(tmp_path / "new.csv"),
            "prior={}".format(tmp_path / "prior_authoritative.csv"),
        ],
        output_dir=str(tmp_path / "merged_prior"),
        registry_id="unit_authoritative_prior",
        notes="unit",
    )
    summary = mod.freeze(args)
    registry = pd.read_csv(
        tmp_path / "merged_prior" / "authoritative_quantile_decision_registry.csv"
    )
    b2 = registry[(registry["region"] == "B") & (registry["fold"] == 2)].iloc[0]

    assert summary["n_region_folds"] == 4
    assert b2["decision_source"] == "prior"
    assert b2["experiment_id"] == "prior_decision_exp"
    assert b2["experiment_id_median_registry"] == "exp_b_2"
    assert "experiment_id_median_registry_median_registry" not in registry.columns


def test_authoritative_decision_merge_rejects_incomplete_coverage(tmp_path):
    mod = load_script("57_freeze_pricefm_authoritative_quantile_decisions.py")
    write_inputs(tmp_path)

    args = SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        decision_source=["old={}".format(tmp_path / "old.csv")],
        output_dir=str(tmp_path / "merged"),
        registry_id="unit_authoritative",
        notes="unit",
    )
    try:
        mod.freeze(args)
    except ValueError as exc:
        assert "Decision coverage mismatch" in str(exc)
    else:
        raise AssertionError("incomplete decision coverage should fail")
