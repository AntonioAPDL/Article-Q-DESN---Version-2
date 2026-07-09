"""Tests for Stage-D graph-informed median rescue grid preparation."""

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


def template_payload():
    return yaml.safe_load(
        (ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_region_panel_20260606.yaml")
        .read_text()
    )


def median_row(region, fold, experiment_id, *, units="[120]", depth=1, input_scale=0.25):
    return {
        "region": region,
        "fold": fold,
        "experiment_id": experiment_id,
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selection_metric_value": 7.0,
        "selection_AQL": 7.0,
        "test_AQL": 8.0,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": depth,
        "units": units,
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": input_scale,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260619,
        "recurrent_sparsity": 0.05,
        "state_output": "final_layer",
    }


def decision_row(region, fold, decision, delta_rel):
    return {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "local_AQL": 8.0,
        "pricefm_AQL": 7.0,
        "delta_abs": 1.0,
        "delta_rel": delta_rel,
        "stage_c_quantile_decision": decision,
    }


def args(tmp_path):
    return SimpleNamespace(
        template_grid_config=str(tmp_path / "template.yaml"),
        median_registry_csv=str(tmp_path / "median.csv"),
        stage_c_decision_registry_csv=str(tmp_path / "decisions.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        grid_id="unit_stage_d_graph",
        generated_root="application/data_local/pricefm/experiment_grids/unit_stage_d_graph",
        run_root="application/data_local/pricefm/runs/unit_stage_d_graph",
        summary_dir=str(tmp_path / "summary"),
        include_wins=False,
        max_variants_per_row=8,
        candidate_source="unit_stage_d_graph",
        write=True,
    )


def write_inputs(tmp_path):
    pd.DataFrame([
        median_row("WIN", 1, "win_exp"),
        median_row("CLOSE", 1, "close_exp"),
        median_row("LOSS", 2, "loss_exp", units="[80, 80]", depth=2, input_scale=0.35),
    ]).to_csv(tmp_path / "median.csv", index=False)
    pd.DataFrame([
        decision_row("WIN", 1, "stage_c_confirmed_local_win", -0.02),
        decision_row("CLOSE", 1, "stage_c_local_close_to_pricefm", 0.02),
        decision_row("LOSS", 2, "stage_c_pricefm_fallback", 0.20),
    ]).to_csv(tmp_path / "decisions.csv", index=False)
    (tmp_path / "template.yaml").write_text(yaml.safe_dump(template_payload(), sort_keys=False))


def test_stage_d_graph_rescue_targets_close_and_fallback_only(tmp_path):
    mod = load_script("55_prepare_pricefm_stage_d_graph_median_rescue.py")
    write_inputs(tmp_path)

    summary = mod.prepare(args(tmp_path))
    payload = yaml.safe_load((tmp_path / "grid.yaml").read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    exps = grid["experiments"]

    assert summary["n_rescue_rows"] == 2
    assert summary["n_experiments"] == 16
    assert {tuple(exp["regions"])[0] for exp in exps} == {"CLOSE", "LOSS"}
    assert all(exp["feature_policy"] == "graph_khop" for exp in exps)
    assert {exp["graph_degree"] for exp in exps} == {1, 2}
    assert all(exp["selection_is_validation_only"] for exp in exps)
    assert all(exp["test_metrics_role"] == "audit_only" for exp in exps)
    assert grid["fixed"]["feature_policy"] == "graph_khop"
    assert "stage_d_graph_rescue_scope.csv" in {
        path.name for path in (tmp_path / "summary").iterdir()
    }


def test_stage_d_graph_rescue_can_include_wins_as_diagnostics(tmp_path):
    mod = load_script("55_prepare_pricefm_stage_d_graph_median_rescue.py")
    write_inputs(tmp_path)
    a = args(tmp_path)
    a.include_wins = True
    a.max_variants_per_row = 2

    summary = mod.prepare(a)
    payload = yaml.safe_load((tmp_path / "grid.yaml").read_text())
    exps = payload["pricefm_desn_experiment_grid"]["experiments"]

    assert summary["n_rescue_rows"] == 3
    assert summary["n_experiments"] == 6
    assert {tuple(exp["regions"])[0] for exp in exps} == {"WIN", "CLOSE", "LOSS"}


def test_stage_d_graph_rescue_rejects_non_validation_median_registry(tmp_path):
    mod = load_script("55_prepare_pricefm_stage_d_graph_median_rescue.py")
    write_inputs(tmp_path)
    median = pd.read_csv(tmp_path / "median.csv")
    median.loc[0, "selected_on_split"] = "test"
    median.to_csv(tmp_path / "median.csv", index=False)

    try:
        mod.prepare(args(tmp_path))
    except ValueError as exc:
        assert "validation/original/AQL" in str(exc)
    else:
        raise AssertionError("test-selected median registry should fail")
