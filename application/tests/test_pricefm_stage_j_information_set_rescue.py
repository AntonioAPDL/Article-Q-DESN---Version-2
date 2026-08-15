"""Tests for Stage-J PriceFM information-set rescue preparation."""

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


def write_csv(path, rows):
    pd.DataFrame(rows).to_csv(path, index=False)


def template_payload(tmp_path):
    return {
        "pricefm_desn_experiment_grid": {
            "grid_id": "unit_template",
            "purpose": "unit",
            "base": {
                "data_config": str(tmp_path / "data.yaml"),
                "generated_root": str(tmp_path / "generated"),
                "run_root": str(tmp_path / "runs"),
            },
            "scope": {
                "regions": [],
                "folds": [],
                "quantiles": [0.5],
            },
            "fixed": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    }


def write_data_config(tmp_path):
    payload = {
        "pricefm": {
            "regions": [
                "BE", "DE_LU", "FR", "NL", "AT", "CZ", "DK_1", "DK_2",
                "NO_2", "PL", "SE_4", "RO", "BG", "HU", "SI", "SK",
            ]
        }
    }
    (tmp_path / "data.yaml").write_text(yaml.safe_dump(payload, sort_keys=False))


def median_row(region, fold, *, graph=False):
    return {
        "region": region,
        "fold": fold,
        "experiment_id": "median_{}_{}".format(region.lower(), fold),
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selection_metric_value": 1.0,
        "selection_AQL": 1.0,
        "test_AQL": 2.0,
        "test_MAE": 2.0,
        "test_RMSE": 2.0,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260623,
        "feature_policy": "graph_khop" if graph else "target_only",
        "input_scope": "pricefm_graph_khop_degree1" if graph else "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": (
            "pricefm_released_graph_khop" if graph else "local_only_not_pricefm_graph"
        ),
        "graph_degree": 1 if graph else "",
        "graph_source": "PriceFM.graph_adj_matrix" if graph else "",
        "graph_hash": "abc123" if graph else "",
    }


def decision_row(region, fold, label, *, delta_rel, graph=False):
    pricefm = 10.0
    delta_abs = pricefm * float(delta_rel)
    return {
        "region": region,
        "fold": fold,
        "stage_c_quantile_decision": label,
        "local_AQL": pricefm + delta_abs,
        "pricefm_AQL": pricefm,
        "delta_abs": delta_abs,
        "delta_rel": float(delta_rel),
        "feature_policy": "graph_khop" if graph else "target_only",
    }


def make_args(tmp_path):
    return SimpleNamespace(
        template_grid_config=str(tmp_path / "template.yaml"),
        median_registry_csv=str(tmp_path / "median.csv"),
        authoritative_decision_registry_csv=str(tmp_path / "decisions.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        grid_id="unit_stage_j",
        generated_root=str(tmp_path / "generated"),
        run_root=str(tmp_path / "runs"),
        summary_dir=str(tmp_path / "summary"),
        include_close=True,
        include_fallback=True,
        near_fallback_rel=0.06,
        hard_fallback_rel=0.18,
        max_variants_priority0=6,
        max_variants_priority1=4,
        max_variants_priority2=2,
        candidate_source="unit_stage_j",
        stage_name="stage_j_information_set_rescue",
        experiment_id_prefix="stagej",
        target_label="stage_j_information_set_rescue_validation",
        launch_key="stage_j_information_set_rescue",
        summary_prefix="stage_j_information_set_rescue",
        write=True,
    )


def write_inputs(tmp_path):
    write_data_config(tmp_path)
    (tmp_path / "template.yaml").write_text(
        yaml.safe_dump(template_payload(tmp_path), sort_keys=False)
    )
    write_csv(tmp_path / "median.csv", [
        median_row("SE_4", 3),
        median_row("BE", 3, graph=True),
        median_row("AT", 3),
        median_row("HU", 2, graph=True),
    ])
    write_csv(tmp_path / "decisions.csv", [
        decision_row("SE_4", 3, "stage_c_local_close_to_pricefm", delta_rel=0.02),
        decision_row("BE", 3, "stage_c_pricefm_fallback", delta_rel=0.05, graph=True),
        decision_row("AT", 3, "stage_c_pricefm_fallback", delta_rel=0.13),
        decision_row("HU", 2, "stage_c_pricefm_fallback", delta_rel=0.19, graph=True),
    ])


def test_stage_j_prioritizes_close_and_near_fallbacks(tmp_path):
    mod = load_script("61_prepare_pricefm_stage_j_information_set_rescue.py")
    write_inputs(tmp_path)

    summary = mod.prepare(make_args(tmp_path))
    scope = pd.read_csv(tmp_path / "summary" / "stage_j_information_set_rescue_scope.csv")
    manifest = pd.read_csv(
        tmp_path / "summary" / "stage_j_information_set_rescue_experiment_manifest.csv"
    )
    grid = yaml.safe_load((tmp_path / "grid.yaml").read_text())["pricefm_desn_experiment_grid"]

    priorities = scope.set_index(["region", "fold"])["stage_j_rescue_priority"]
    assert priorities.loc[("SE_4", 3)] == 0
    assert priorities.loc[("BE", 3)] == 0
    assert priorities.loc[("AT", 3)] == 1
    assert priorities.loc[("HU", 2)] == 2
    assert summary["n_rescue_rows"] == 4
    assert set(manifest["stage"]) == {"stage_j_information_set_rescue"}
    assert set(grid["launch"]["stage_j_information_set_rescue"]["priorities"]) == {0, 1, 2}
    assert all(exp["selection_is_validation_only"] for exp in grid["experiments"])
    assert set(exp["test_metrics_role"] for exp in grid["experiments"]) == {"audit_only"}


def test_stage_j_target_only_rows_receive_graph_metadata(tmp_path):
    mod = load_script("61_prepare_pricefm_stage_j_information_set_rescue.py")
    write_inputs(tmp_path)
    mod.prepare(make_args(tmp_path))
    manifest = pd.read_csv(
        tmp_path / "summary" / "stage_j_information_set_rescue_experiment_manifest.csv"
    )

    se4 = manifest[manifest["id"].astype(str).str.contains("se4_f3")]
    assert not se4.empty
    assert set(se4["feature_policy"]) == {"graph_khop"}
    assert {1, 2}.issubset(set(pd.to_numeric(se4["graph_degree"], errors="coerce").dropna().astype(int)))
    assert set(se4["spatial_information_set"]) == {"pricefm_released_graph_khop"}
    assert set(se4["stage_j_information_set_action"]) == {"add_pricefm_graph_inputs"}


def test_stage_j_graph_rows_keep_guardrail_and_refinement_labels(tmp_path):
    mod = load_script("61_prepare_pricefm_stage_j_information_set_rescue.py")
    write_inputs(tmp_path)
    mod.prepare(make_args(tmp_path))
    manifest = pd.read_csv(
        tmp_path / "summary" / "stage_j_information_set_rescue_experiment_manifest.csv"
    )

    be = manifest[manifest["id"].astype(str).str.contains("be_f3")]
    assert "target_only" in set(be["feature_policy"])
    assert "graph_khop" in set(be["feature_policy"])
    assert set(be["stage_j_information_set_action"]) == {"refine_existing_graph_geometry"}


def test_stage_j_validates_threshold_order(tmp_path):
    mod = load_script("61_prepare_pricefm_stage_j_information_set_rescue.py")
    write_inputs(tmp_path)
    args = make_args(tmp_path)
    args.near_fallback_rel = 0.2
    args.hard_fallback_rel = 0.1

    try:
        mod.prepare(args)
    except ValueError as exc:
        assert "near-fallback-rel" in str(exc)
    else:
        raise AssertionError("invalid threshold ordering should fail")
