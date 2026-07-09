"""Tests for PriceFM median selection and promotion helpers."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest
import yaml


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


def metric_frame():
    rows = []
    for fold in [2, 3]:
        for experiment_id, val_aql, test_aql in [
            ("exp_a", 8.0 + fold, 9.0 + fold),
            ("exp_b", 7.0 + fold, 11.0 + fold),
        ]:
            for split, aql in [("val", val_aql), ("test", test_aql)]:
                rows.append({
                    "region": "DE_LU",
                    "fold": fold,
                    "experiment_id": experiment_id,
                    "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                    "split": split,
                    "unit": "original",
                    "AQL": aql,
                    "AQCR": 0.0,
                    "MAE": 2.0 * aql,
                    "RMSE": 3.0 * aql,
                    "stage": "unit",
                    "priority": 0,
                    "lag_window": 96,
                    "feature_map": "window_reservoir_v1",
                    "feature_dim": 120,
                    "projection_scale": 1.0,
                    "depth": 1,
                    "units": "[120]",
                    "alpha": "0.5",
                    "rho": "0.9",
                    "input_scale": "0.5",
                    "recurrent_sparsity": "0.05",
                    "state_output": "final_layer",
                    "quantiles": "[0.5]",
                    "tau0": 1.0e-3,
                    "seed": 20260601,
                    "data_config": "data.yaml",
                    "full_config": "full.yaml",
                    "run_dir": "run",
                    "model_dir": "model",
                    "adapter_dir": "adapter",
                    "rationale": "unit",
                })
    return pd.DataFrame(rows)


def test_median_selection_uses_validation_not_test():
    mod = load_script("20_select_pricefm_desn_median_specs.py")
    registry = mod.select_registry(
        metric_frame(),
        "val",
        "original",
        "AQL",
        ["qdesn_exal_rhs_ns_exact_chunked"],
    )
    assert registry.shape[0] == 2
    assert set(registry["experiment_id"]) == {"exp_b"}
    fold2 = registry[registry["fold"].eq(2)].iloc[0]
    assert np.isclose(fold2["selection_metric_value"], 9.0)
    assert np.isclose(fold2["test_AQL"], 13.0)


def test_median_selection_rankings_are_per_fold():
    mod = load_script("20_select_pricefm_desn_median_specs.py")
    rankings = mod.fold_rankings(
        metric_frame(),
        "val",
        "original",
        "AQL",
        ["qdesn_exal_rhs_ns_exact_chunked"],
    )
    first = rankings[rankings["rank"].eq(1.0)]
    assert first.shape[0] == 2
    assert set(first["experiment_id"]) == {"exp_b"}


def test_median_selection_row_filters_are_explicit():
    mod = load_script("20_select_pricefm_desn_median_specs.py")
    rows = [
        {"id": "p0_a", "priority": 0, "stage": "main"},
        {"id": "p1_b", "priority": 1, "stage": "optional"},
        {"id": "p0_c", "priority": 0, "stage": "optional"},
    ]
    assert [row["id"] for row in mod.select_rows(rows, priorities=[0])] == ["p0_a", "p0_c"]
    assert [row["id"] for row in mod.select_rows(rows, stages=["optional"])] == ["p1_b", "p0_c"]
    assert [row["id"] for row in mod.select_rows(rows, ids=["p1_b"])] == ["p1_b"]


def test_median_selection_method_coverage_requires_requested_methods():
    mod = load_script("20_select_pricefm_desn_median_specs.py")
    metrics = metric_frame()
    coverage = mod.selection_method_coverage(
        metrics,
        "val",
        "original",
        "AQL",
        ["qdesn_exal_rhs_ns_exact_chunked", "qdesn_al_rhs_ns_exact_chunked"],
    )
    assert coverage.shape[0] == 4
    missing = coverage[~coverage["covered"]]
    assert set(missing["method_id"]) == {"qdesn_al_rhs_ns_exact_chunked"}
    with pytest.raises(ValueError, match="Missing finite selection metrics"):
        mod.assert_selection_method_coverage(coverage)


def test_median_selection_writes_package_style_artifacts(tmp_path):
    mod = load_script("20_select_pricefm_desn_median_specs.py")
    metrics = metric_frame()
    methods = ["qdesn_exal_rhs_ns_exact_chunked"]
    registry = mod.select_registry(metrics, "val", "original", "AQL", methods)
    coverage = mod.selection_method_coverage(metrics, "val", "original", "AQL", methods)
    status = pd.DataFrame([
        {"region": "DE_LU", "fold": 2, "completed": True},
        {"region": "DE_LU", "fold": 3, "completed": True},
    ])
    args = SimpleNamespace(
        selection_split="val",
        selection_unit="original",
        selection_metric="AQL",
        selection_methods="qdesn_exal_rhs_ns_exact_chunked",
        regions="DE_LU",
        folds="2,3",
        priorities="0",
        stages=None,
        ids=None,
        expected_horizons="1:96",
        parity_summary=None,
    )
    outputs = mod.write_package_style_outputs(
        tmp_path, metrics, registry, coverage, status, args, "unit_grid"
    )

    for path in outputs.values():
        assert Path(path).exists()
    contract = (tmp_path / "model_selection_contract.json").read_text()
    assert "exdqlm::qdesn_model_selection" in contract
    assert "pricefm_direct_horizon_fold_aql" in contract
    winners = pd.read_csv(tmp_path / "model_selection_winners.csv")
    assert set(winners["candidate_id"]) == {"exp_b"}
    assert winners["package_launch_ready"].eq(False).all()
    pkg_metrics = pd.read_csv(tmp_path / "model_selection_candidate_metrics.csv")
    assert pkg_metrics["is_selection_row"].sum() == 4
    parity = (tmp_path / "model_selection_parity_summary.json").read_text()
    assert '"parity_gate_required": true' in parity


def test_quantile_promotion_grid_uses_registry_region_fold_scope():
    mod = load_script("21_prepare_pricefm_quantile_grid_from_median_registry.py")
    template = yaml.safe_load(
        (ROOT / "application" / "config" / "pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml").read_text()
    )
    registry = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 2,
            "experiment_id": "exp_b",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_metric_value": 9.0,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": "[120]",
            "alpha": "0.5",
            "rho": "0.9",
            "input_scale": "0.5",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "final_decision": "promote_candidate",
            "candidate_source_final": "local_ar_unit",
            "selection_is_validation_only": True,
        }
    ])
    payload = mod.build_grid(
        template,
        registry,
        "unit_grid",
        "generated",
        "runs",
        [0.1, 0.5],
        0,
    )
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["scope"]["folds"] == [2]
    assert len(grid["experiments"]) == 2
    assert all(exp["folds"] == [2] for exp in grid["experiments"])
    assert all(exp["regions"] == ["DE_LU"] for exp in grid["experiments"])
    assert {exp["quantile"] for exp in grid["experiments"]} == {0.1, 0.5}
    assert all(exp["input_scope"] == "local_target_only" for exp in grid["experiments"])
    assert all(exp["spatial_information_set"] == "local_only_not_pricefm_graph" for exp in grid["experiments"])
    assert all(exp["final_decision"] == "promote_candidate" for exp in grid["experiments"])
    assert all(exp["median_registry"]["median_experiment_id"] == "exp_b" for exp in grid["experiments"])


def closeout_row(region, fold, experiment_id, val_aql, test_aql, test_rmse, model_dir=None):
    row = {
        "region": region,
        "fold": fold,
        "experiment_id": experiment_id,
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selection_metric": "AQL",
        "selection_metric_value": val_aql,
        "selection_AQL": val_aql,
        "test_AQL": test_aql,
        "test_MAE": test_aql / 2.0,
        "test_RMSE": test_rmse,
        "depth": 2,
        "units": "[80, 80]",
        "input_scale": "0.25",
        "alpha": "0.3",
        "rho": "0.9",
        "candidate_source": "previous_authoritative",
    }
    if model_dir is not None:
        row["model_dir"] = str(model_dir)
    return row


def write_method_summary(model_dir, converged=True):
    model_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([{
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "converged": converged,
    }]).to_csv(model_dir / "model_method_summary.csv", index=False)


def closeout_args(tmp_path):
    return SimpleNamespace(
        new_registry_dir=tmp_path / "new",
        previous_registry_csv=tmp_path / "previous.csv",
        output_dir=tmp_path / "out",
        grid_id="unit_grid",
        candidate_source="local_ar_unit",
        validation_tolerance=0.0,
        tiny_validation_gain=0.01,
        test_aql_warning=0.25,
        test_rmse_warning=1.0,
        severe_test_aql_warning=1.0,
        severe_test_rmse_warning=5.0,
        input_scope="local_target_only",
        output_scope="target_region_path",
        lead_covariate_status="realized_ex_post",
    )


def test_local_ar_closeout_promotes_only_clean_validation_winners(tmp_path):
    mod = load_script("34_closeout_pricefm_median_registry.py")
    args = closeout_args(tmp_path)
    args.new_registry_dir.mkdir(parents=True)
    rows = {
        "promote": ("DE_LU", 1, 10.0, 9.0, 20.0, 20.1, 30.0, 30.2),
        "no_val_gain": ("DE_LU", 2, 10.0, 10.2, 20.0, 18.0, 30.0, 25.0),
        "test_risk": ("EE", 1, 10.0, 9.8, 20.0, 21.6, 30.0, 36.0),
    }
    previous = []
    new = []
    for key, (region, fold, prev_val, new_val, prev_test, new_test, prev_rmse, new_rmse) in rows.items():
        model_dir = tmp_path / "models" / key
        write_method_summary(model_dir, converged=True)
        previous.append(closeout_row(region, fold, "current_" + key, prev_val, prev_test, prev_rmse))
        new.append(closeout_row(region, fold, "candidate_" + key, new_val, new_test, new_rmse, model_dir))
    pd.DataFrame(previous).to_csv(args.previous_registry_csv, index=False)
    pd.DataFrame(new).to_csv(args.new_registry_dir / "median_selection_registry.csv", index=False)

    summary = mod.closeout(args)
    decisions = pd.read_csv(args.output_dir / "promotion_decisions.csv")
    merged = pd.read_csv(args.output_dir / "merged_selection_registry.csv")

    assert summary["n_promote_candidate"] == 1
    assert summary["n_review"] == 1
    assert summary["n_keep_previous"] == 1
    by_fold = {(r.region, int(r.fold)): r for r in decisions.itertuples(index=False)}
    assert by_fold[("DE_LU", 1)].final_decision == "promote_candidate"
    assert by_fold[("DE_LU", 2)].final_decision == "keep_previous_no_val_gain"
    assert by_fold[("EE", 1)].final_decision == "review_val_gain_test_risk"

    final = {(r.region, int(r.fold)): r for r in merged.itertuples(index=False)}
    assert final[("DE_LU", 1)].experiment_id == "candidate_promote"
    assert final[("DE_LU", 1)].candidate_source_final == "local_ar_unit"
    assert final[("DE_LU", 2)].experiment_id == "current_no_val_gain"
    assert final[("EE", 1)].experiment_id == "current_test_risk"
    assert set(merged["input_scope"]) == {"local_target_only"}
    assert set(merged["spatial_information_set"]) == {"local_only_not_pricefm_graph"}
    assert merged["selection_is_validation_only"].all()


def test_local_ar_closeout_convergence_risk_keeps_previous(tmp_path):
    mod = load_script("34_closeout_pricefm_median_registry.py")
    args = closeout_args(tmp_path)
    args.new_registry_dir.mkdir(parents=True)
    model_dir = tmp_path / "models" / "nonconverged"
    write_method_summary(model_dir, converged=False)
    previous = pd.DataFrame([
        closeout_row("HU", 3, "current", 11.0, 15.0, 18.0),
    ])
    new = pd.DataFrame([
        closeout_row("HU", 3, "candidate", 10.0, 14.0, 17.0, model_dir),
    ])
    previous.to_csv(args.previous_registry_csv, index=False)
    new.to_csv(args.new_registry_dir / "median_selection_registry.csv", index=False)

    mod.closeout(args)
    decisions = pd.read_csv(args.output_dir / "promotion_decisions.csv")
    merged = pd.read_csv(args.output_dir / "merged_selection_registry.csv")

    assert decisions.iloc[0]["final_decision"] == "review_val_gain_convergence_risk"
    assert decisions.iloc[0]["candidate_converged"] == np.False_
    assert merged.iloc[0]["experiment_id"] == "current"
