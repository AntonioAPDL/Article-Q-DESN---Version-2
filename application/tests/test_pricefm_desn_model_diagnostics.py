"""Tests for PriceFM DESN per-cell diagnostic artifacts."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

spec = importlib.util.spec_from_file_location(
    "pricefm_desn_summary",
    ROOT / "application" / "scripts" / "pricefm" / "09_summarize_desn_model_smoke.py",
)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class IdentityScaler:
    def inverse_transform(self, arr):
        return arr


def test_make_cell_figures_writes_trace_parameter_and_fit_plots(tmp_path):
    run_dir = tmp_path / "cell"
    run_dir.mkdir()
    pd.DataFrame([
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "iter": 1,
            "elbo": -10.0,
            "sigma": 0.4,
            "gamma": 0.0,
            "rhs_tau": 0.1,
            "rhs_lambda_mean": 2.0,
            "parameter_change": 0.05,
        },
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "iter": 2,
            "elbo": -9.0,
            "sigma": 0.3,
            "gamma": 0.0,
            "rhs_tau": 0.2,
            "rhs_lambda_mean": 1.5,
            "parameter_change": 0.01,
        },
    ]).to_csv(run_dir / "model_trace_summary.csv", index=False)
    pd.DataFrame([
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "beta_l2": 1.0,
            "beta_max_abs": 0.8,
            "beta_cov_trace": 0.2,
            "sigma": 0.3,
            "gamma": 0.0,
        },
    ]).to_csv(run_dir / "model_parameter_summary.csv", index=False)

    rows = {
        "test": pd.DataFrame([
            {
                "origin_id": 1,
                "horizon": 1,
                "response_market_time": "2026-01-01T00:00:00Z",
                "y_scaled": 1.0,
            },
            {
                "origin_id": 1,
                "horizon": 2,
                "response_market_time": "2026-01-01T01:00:00Z",
                "y_scaled": 2.0,
            },
        ])
    }
    pred = pd.DataFrame([
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "split": "test",
            "origin_id": 1,
            "horizon": 1,
            "tau": 0.5,
            "pred_scaled": 1.1,
        },
        {
            "method_id": "qdesn_al_rhs_ns_exact_chunked",
            "split": "test",
            "origin_id": 1,
            "horizon": 2,
            "tau": 0.5,
            "pred_scaled": 1.9,
        },
    ])

    info = summary.make_cell_figures(run_dir, rows, pred, IdentityScaler(), [0.5])
    figures = [Path(x) for x in info["figures"]]
    assert run_dir / "figures" / "trace_elbo.png" in figures
    assert run_dir / "figures" / "trace_parameter_diagnostics.png" in figures
    assert run_dir / "figures" / "final_parameter_summary.png" in figures
    assert run_dir / "figures" / "test_fit_first14_origins.png" in figures
    assert all(path.exists() and path.stat().st_size > 0 for path in figures)
