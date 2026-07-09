"""Tests for graph/local PriceFM median closeout."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import pandas as pd
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


def registry_row(region, fold, experiment_id, val_aql, test_aql, source):
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
        "test_MAE": 2.0 * test_aql,
        "test_RMSE": 3.0 * test_aql,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 2,
        "units": "[120, 120]",
        "alpha": "0.5",
        "rho": "0.9",
        "input_scale": "0.5",
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260614,
        "candidate_source": source,
    }
    if source == "graph_unit":
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
    else:
        row.update({
            "feature_policy": "target_only",
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
        })
    return row


def closeout_args(tmp_path):
    return SimpleNamespace(
        local_registry_csv=tmp_path / "local.csv",
        graph_registry_csv=tmp_path / "graph.csv",
        output_dir=tmp_path / "out",
        grid_id="unit_graph_closeout",
        candidate_source="graph_unit",
        validation_tolerance=0.0,
    )


def test_graph_closeout_promotes_only_validation_winners(tmp_path):
    mod = load_script("38_closeout_pricefm_graph_neighbor_median_registry.py")
    args = closeout_args(tmp_path)
    local = pd.DataFrame([
        registry_row("DE_LU", 1, "local_val_loser", 10.0, 9.0, "local_unit"),
        registry_row("EE", 1, "local_test_loser", 10.0, 12.0, "local_unit"),
    ])
    graph = pd.DataFrame([
        registry_row("DE_LU", 1, "graph_val_winner", 9.8, 12.0, "graph_unit"),
        registry_row("EE", 1, "graph_test_winner_only", 10.3, 8.0, "graph_unit"),
    ])
    local.to_csv(args.local_registry_csv, index=False)
    graph.to_csv(args.graph_registry_csv, index=False)

    summary = mod.closeout(args)
    decisions = pd.read_csv(args.output_dir / "promotion_decisions.csv")
    merged = pd.read_csv(args.output_dir / "merged_selection_registry.csv")

    assert summary["n_graph_promoted"] == 1
    assert summary["n_local_kept"] == 1
    by_region = {r.region: r for r in decisions.itertuples(index=False)}
    assert by_region["DE_LU"].final_decision == "promote_graph_validation_win"
    assert by_region["EE"].final_decision == "keep_local_validation_not_improved"
    assert by_region["EE"].test_improved

    final = {r.region: r for r in merged.itertuples(index=False)}
    assert final["DE_LU"].experiment_id == "graph_val_winner"
    assert final["DE_LU"].selected_source == "graph"
    assert final["DE_LU"].feature_policy == "graph_khop"
    assert final["DE_LU"].spatial_information_set == "pricefm_released_graph_khop"
    assert int(final["DE_LU"].graph_degree) == 1
    assert final["EE"].experiment_id == "local_test_loser"
    assert final["EE"].selected_source == "local"
    assert final["EE"].feature_policy == "target_only"
    assert final["EE"].spatial_information_set == "local_only_not_pricefm_graph"
    assert merged["selection_is_validation_only"].all()


def test_graph_closeout_registry_feeds_quantile_grid_metadata(tmp_path):
    closeout_mod = load_script("38_closeout_pricefm_graph_neighbor_median_registry.py")
    quantile_mod = load_script("21_prepare_pricefm_quantile_grid_from_median_registry.py")
    args = closeout_args(tmp_path)
    local = pd.DataFrame([
        registry_row("DE_LU", 1, "local_a", 10.0, 9.0, "local_unit"),
        registry_row("EE", 1, "local_b", 10.0, 9.0, "local_unit"),
    ])
    graph = pd.DataFrame([
        registry_row("DE_LU", 1, "graph_a", 9.5, 9.2, "graph_unit"),
        registry_row("EE", 1, "graph_b", 10.5, 8.0, "graph_unit"),
    ])
    local.to_csv(args.local_registry_csv, index=False)
    graph.to_csv(args.graph_registry_csv, index=False)
    closeout_mod.closeout(args)
    registry = pd.read_csv(args.output_dir / "merged_selection_registry.csv")
    template = yaml.safe_load(
        (ROOT / "application" / "config" / "pricefm_desn_experiment_grid_de_lu_fold1_paper_quantiles_authoritative_20260602.yaml").read_text()
    )

    payload = quantile_mod.build_grid(
        template,
        registry,
        "unit_quantile_grid",
        "generated",
        "runs",
        [0.1, 0.5],
        0,
    )
    exps = payload["pricefm_desn_experiment_grid"]["experiments"]
    by_region = {(exp["regions"][0], exp["quantile"]): exp for exp in exps}

    graph_exp = by_region[("DE_LU", 0.1)]
    assert graph_exp["feature_policy"] == "graph_khop"
    assert graph_exp["spatial_information_set"] == "pricefm_released_graph_khop"
    assert graph_exp["graph_degree"] == 1
    assert graph_exp["median_registry"]["selected_source"] == "graph"

    local_exp = by_region[("EE", 0.5)]
    assert local_exp["feature_policy"] == "target_only"
    assert local_exp["spatial_information_set"] == "local_only_not_pricefm_graph"
    assert local_exp["median_registry"]["selected_source"] == "local"
