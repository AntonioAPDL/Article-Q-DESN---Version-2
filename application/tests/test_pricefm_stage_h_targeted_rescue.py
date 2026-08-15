"""Tests for Stage-H targeted PriceFM median rescue preparation."""

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


def median_row(region, fold, *, graph=False, selected_on_split="val"):
    return {
        "region": region,
        "fold": fold,
        "experiment_id": "median_{}_{}".format(region.lower(), fold),
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selected_on_split": selected_on_split,
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
        "seed": 20260622,
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


def decision_row(region, fold, label, *, delta, graph=False):
    return {
        "region": region,
        "fold": fold,
        "stage_c_quantile_decision": label,
        "local_AQL": 10.0 + delta,
        "pricefm_AQL": 10.0,
        "delta_abs": delta,
        "delta_rel": delta / 10.0,
        "feature_policy": "graph_khop" if graph else "target_only",
    }


def make_args(tmp_path):
    return SimpleNamespace(
        template_grid_config=str(tmp_path / "template.yaml"),
        median_registry_csv=str(tmp_path / "median.csv"),
        authoritative_decision_registry_csv=str(tmp_path / "decisions.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        grid_id="unit_stage_h",
        generated_root=str(tmp_path / "generated"),
        run_root=str(tmp_path / "runs"),
        summary_dir=str(tmp_path / "summary"),
        include_close=True,
        include_fallback=True,
        priority0_delta_abs=1.0,
        priority1_delta_abs=0.25,
        max_variants_priority0=5,
        max_variants_priority1=4,
        max_variants_priority2=3,
        candidate_source="unit_stage_h",
        write=True,
    )


def write_inputs(tmp_path):
    (tmp_path / "template.yaml").write_text(
        yaml.safe_dump(template_payload(tmp_path), sort_keys=False)
    )
    write_csv(tmp_path / "median.csv", [
        median_row("A", 1),
        median_row("B", 1, graph=True),
        median_row("C", 1),
        median_row("D", 1),
    ])
    write_csv(tmp_path / "decisions.csv", [
        decision_row("A", 1, "stage_c_pricefm_fallback", delta=1.5),
        decision_row("B", 1, "stage_c_pricefm_fallback", delta=0.3, graph=True),
        decision_row("C", 1, "stage_c_local_close_to_pricefm", delta=0.1),
        decision_row("D", 1, "stage_c_confirmed_local_win", delta=-1.0),
    ])


def test_stage_h_prioritizes_severe_fallbacks_and_keeps_close_rows_last(tmp_path):
    mod = load_script("60_prepare_pricefm_stage_h_targeted_rescue.py")
    write_inputs(tmp_path)

    summary = mod.prepare(make_args(tmp_path))
    scope = pd.read_csv(tmp_path / "summary" / "stage_h_targeted_rescue_scope.csv")
    manifest = pd.read_csv(tmp_path / "summary" / "stage_h_targeted_rescue_experiment_manifest.csv")
    grid = yaml.safe_load((tmp_path / "grid.yaml").read_text())["pricefm_desn_experiment_grid"]

    assert summary["n_rescue_rows"] == 3
    assert summary["n_experiments"] == 12
    assert set(scope[["region", "fold"]].itertuples(index=False, name=None)) == {
        ("A", 1),
        ("B", 1),
        ("C", 1),
    }
    assert scope.set_index("region").loc["A", "stage_h_rescue_priority"] == 0
    assert scope.set_index("region").loc["B", "stage_h_rescue_priority"] == 1
    assert scope.set_index("region").loc["C", "stage_h_rescue_priority"] == 2
    assert set(manifest["stage"]) == {"stage_h_targeted_median_rescue"}
    assert set(manifest["feature_policy"]) == {"graph_khop", "target_only"}
    assert "targetonly_base" in " ".join(manifest["id"])
    assert grid["launch"]["stage_h_targeted_median_rescue"]["priorities"] == [0, 1, 2]
    assert all(exp["selection_is_validation_only"] for exp in grid["experiments"])
    assert set(exp["test_metrics_role"] for exp in grid["experiments"]) == {"audit_only"}


def test_stage_h_rejects_non_validation_median_registry(tmp_path):
    mod = load_script("60_prepare_pricefm_stage_h_targeted_rescue.py")
    (tmp_path / "template.yaml").write_text(
        yaml.safe_dump(template_payload(tmp_path), sort_keys=False)
    )
    write_csv(tmp_path / "median.csv", [median_row("A", 1, selected_on_split="test")])
    write_csv(tmp_path / "decisions.csv", [
        decision_row("A", 1, "stage_c_pricefm_fallback", delta=1.5),
    ])

    try:
        mod.prepare(make_args(tmp_path))
    except ValueError as exc:
        assert "validation/original/AQL" in str(exc)
    else:
        raise AssertionError("non-validation median registry should fail")


def test_stage_h_generator_accepts_custom_stage_labels(tmp_path):
    mod = load_script("60_prepare_pricefm_stage_h_targeted_rescue.py")
    write_inputs(tmp_path)
    args = make_args(tmp_path)
    args.stage_name = "stage_i_unresolved_median_rescue"
    args.experiment_id_prefix = "stagei"
    args.target_label = "stage_i_unresolved_median_rescue_validation"
    args.launch_key = "stage_i_unresolved_median_rescue"
    args.summary_prefix = "stage_i_unresolved_rescue"

    summary = mod.prepare(args)
    grid = yaml.safe_load((tmp_path / "grid.yaml").read_text())["pricefm_desn_experiment_grid"]
    manifest = pd.read_csv(tmp_path / "summary" / "stage_i_unresolved_rescue_experiment_manifest.csv")

    assert summary["n_rescue_rows"] == 3
    assert set(manifest["stage"]) == {"stage_i_unresolved_median_rescue"}
    assert all(str(x).startswith("stagei_") for x in manifest["id"])
    assert set(exp["target_label"] for exp in grid["experiments"]) == {
        "stage_i_unresolved_median_rescue_validation",
    }
    assert "stage_i_unresolved_median_rescue" in grid["launch"]
    assert (tmp_path / "summary" / "stage_i_unresolved_rescue_scope.csv").exists()
