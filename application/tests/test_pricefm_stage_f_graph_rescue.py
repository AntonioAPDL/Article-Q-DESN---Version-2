"""Tests for Stage-F graph median rescue grid preparation."""

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
            "experiments": [],
            "experiment_blocks": [],
        }
    }


def median_row(region, fold):
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
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": 20260620,
    }


def decision_row(region, fold, label, *, rel, graph=False):
    return {
        "region": region,
        "fold": fold,
        "stage_c_quantile_decision": label,
        "local_AQL": 10.0 * (1.0 + rel),
        "pricefm_AQL": 10.0,
        "delta_abs": 10.0 * rel,
        "delta_rel": rel,
        "feature_policy": "graph_khop" if graph else "target_only",
    }


def test_stage_f_graph_rescue_prepares_target_only_close_and_fallback_rows(tmp_path):
    mod = load_script("58_prepare_pricefm_stage_f_graph_rescue.py")
    template = tmp_path / "template.yaml"
    template.write_text(yaml.safe_dump(template_payload(tmp_path), sort_keys=False))
    write_csv(tmp_path / "median.csv", [
        median_row("A", 1),
        median_row("B", 1),
        median_row("C", 1),
        median_row("D", 1),
    ])
    write_csv(tmp_path / "decisions.csv", [
        decision_row("A", 1, "stage_c_pricefm_fallback", rel=0.30),
        decision_row("B", 1, "stage_c_local_close_to_pricefm", rel=0.02),
        decision_row("C", 1, "stage_c_confirmed_local_win", rel=-0.10),
        decision_row("D", 1, "stage_c_pricefm_fallback", rel=0.08, graph=True),
    ])

    args = SimpleNamespace(
        template_grid_config=str(template),
        median_registry_csv=str(tmp_path / "median.csv"),
        authoritative_decision_registry_csv=str(tmp_path / "decisions.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        grid_id="unit_stage_f",
        generated_root=str(tmp_path / "generated"),
        run_root=str(tmp_path / "runs"),
        summary_dir=str(tmp_path / "summary"),
        include_graph_rows=False,
        include_close=True,
        include_fallback=True,
        max_variants_per_row=3,
        candidate_source="unit_stage_f",
        write=True,
    )

    summary = mod.prepare(args)
    scope = pd.read_csv(tmp_path / "summary" / "stage_f_graph_rescue_scope.csv")
    manifest = pd.read_csv(tmp_path / "summary" / "stage_f_graph_rescue_experiment_manifest.csv")

    assert summary["n_rescue_rows"] == 2
    assert summary["n_experiments"] == 6
    assert list(scope[["region", "fold"]].itertuples(index=False, name=None)) == [("A", 1), ("B", 1)]
    assert set(manifest["stage"]) == {"stage_f_graph_median_rescue"}
    assert set(manifest["feature_policy"]) == {"graph_khop"}
    assert set(manifest["spatial_information_set"]) == {"pricefm_released_graph_khop"}
    assert all(str(x).startswith("pricefm_graph_khop_degree") for x in manifest["input_scope"])
    assert set(scope["stage_f_rescue_priority"]) == {0}
