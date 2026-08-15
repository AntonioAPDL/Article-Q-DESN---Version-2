"""Tests for PriceFM DESN full-run summary helpers."""

from pathlib import Path
import copy
import importlib.util
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_common import load_config  # noqa: E402
from pricefm_full_run import cell_paths, load_full_config  # noqa: E402


spec = importlib.util.spec_from_file_location(
    "pricefm_full_summary",
    ROOT / "application" / "scripts" / "pricefm" / "11_summarize_desn_model_full.py",
)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)
CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_full.yaml"


def temp_full_config(tmp_path):
    full = copy.deepcopy(load_full_config(CONFIG))
    full["run"]["output_dir"] = str(tmp_path / "run")
    full["scope"]["regions"] = ["DE_LU", "BE"]
    full["scope"]["folds"] = [1]
    return full


def write_cell_outputs(full, region, fold, aql):
    paths = cell_paths(full, region, fold)
    paths["model"].mkdir(parents=True, exist_ok=True)
    pd.DataFrame([
        {
            "method_id": "normal_rhs_ns",
            "split": "test",
            "unit": "original",
            "AQL": aql,
            "AQCR": 0.0,
            "MAE": 2.0 * aql,
            "RMSE": 3.0 * aql,
        }
    ]).to_csv(paths["model"] / "metric_summary.csv", index=False)
    pd.DataFrame([
        {
            "method_id": "normal_rhs_ns",
            "split": "test",
            "unit": "original",
            "horizon": 1,
            "AQL": aql,
            "AQCR": 0.0,
            "MAE": 2.0 * aql,
            "RMSE": 3.0 * aql,
        }
    ]).to_csv(paths["model"] / "metric_by_horizon.csv", index=False)
    pd.DataFrame([
        {
            "method_id": "normal_rhs_ns",
            "split": "test",
            "unit": "original",
            "horizon_group": "1-24",
            "AQL": aql,
            "AQCR": 0.0,
            "MAE": 2.0 * aql,
            "RMSE": 3.0 * aql,
        }
    ]).to_csv(paths["model"] / "metric_by_horizon_group.csv", index=False)
    pd.DataFrame([
        {
            "method_id": "normal_rhs_ns",
            "train_seconds": 1.0,
        }
    ]).to_csv(paths["model"] / "model_method_summary.csv", index=False)
    pd.DataFrame([
        {
            "likelihood_family": "al",
            "prior_family": "rhs_ns",
            "tau": 0.25,
            "beta_mean_max_abs_diff": 1e-10,
            "beta_cov_max_abs_diff": 1e-10,
            "train_prediction_max_abs_diff": 1e-10,
            "tolerance": 1e-6,
            "passed": True,
        }
    ]).to_csv(paths["model"] / "exact_equivalence.csv", index=False)
    pd.DataFrame([
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "likelihood_family": "al",
            "tau": 0.5,
            "fit_order": 1,
            "init_source": "normal_rhs_ns",
            "init_components": "beta+beta_state+sigma",
            "fallback_used": False,
            "converged": True,
            "iter": 5,
        }
    ]).to_csv(paths["model"] / "warm_start_diagnostics.csv", index=False)
    paths["model_time"].parent.mkdir(parents=True, exist_ok=True)
    paths["model_time"].write_text(
        "Elapsed (wall clock) time (h:mm:ss or m:ss): 0:01.00\n"
        "Maximum resident set size (kbytes): 123456\n"
    )


def test_collect_cells_and_macro_rankings(tmp_path):
    full = temp_full_config(tmp_path)
    data = load_config(full["data_config"])
    write_cell_outputs(full, "DE_LU", 1, 10.0)
    write_cell_outputs(full, "BE", 1, 14.0)
    payload = summary.collect_cells(full, data)
    assert len(payload["metrics"]) == 2
    macro = summary.numeric_mean(payload["metrics"], ["method_id", "split", "unit"])
    assert macro.loc[0, "AQL"] == 12.0
    rankings = summary.method_rankings(macro)
    assert rankings.loc[0, "method_id"] == "normal_rhs_ns"
    assert rankings.loc[0, "rank_AQL"] == 1.0
    assert payload["runtime"]["max_rss_kb"].tolist() == [123456, 123456]
    assert len(payload["warm"]) == 2
    assert set(payload["warm"]["init_source"]) == {"normal_rhs_ns"}


def test_write_report_handles_partial_completion(tmp_path):
    full = temp_full_config(tmp_path)
    data = load_config(full["data_config"])
    write_cell_outputs(full, "DE_LU", 1, 10.0)
    payload = summary.collect_cells(full, data)
    macro = summary.numeric_mean(payload["metrics"], ["method_id", "split", "unit"])
    payload.update({"macro": macro, "rankings": summary.method_rankings(macro)})
    out_dir = tmp_path / "summary"
    out_dir.mkdir()
    report = summary.write_report(out_dir, payload)
    text = report.read_text()
    assert "Completed cells: `1` / `2`" in text
    assert "normal_rhs_ns" in text
    assert "Warm-Start Diagnostics" in text
