"""Focused tests for the consumed PriceFM horizon-specific readout path."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
RSCRIPT = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
HELPER = ROOT / "application" / "scripts" / "pricefm" / "pricefm_horizon_readout.R"
RUNNER = ROOT / "application" / "scripts" / "pricefm" / "08_run_desn_model_smoke.R"
PACKAGE_ROOT = Path("/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0")


def test_horizon_readout_fits_distinct_blocks_and_embargoes_nested_folds():
    code = f"""
source({str(HELPER)!r})
origin <- rep(seq_len(60), each = 4)
horizon <- rep(seq_len(4), times = 60)
origin_time <- as.POSIXct('2024-01-01', tz = 'UTC') + (origin - 1) * 86400
rows <- data.frame(
  origin_id = origin,
  horizon = horizon,
  origin_market_time = format(origin_time, '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC'),
  response_market_time = format(origin_time + horizon * 3600, '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
)
X <- cbind(1, rep(seq(-1, 1, length.out = 60), each = 4))
block <- pricefm_horizon_block_labels(horizon, 2)
y <- ifelse(block == '1-2', 2 + 0.5 * X[, 2], -3 + 1.5 * X[, 2])
fits <- pricefm_fit_horizon_block_models(
  X, y, horizon, 2,
  function(X_block, y_block, block_name, block_index) list(beta = lm.fit(X_block, y_block)$coefficients)
)
pred <- pricefm_predict_horizon_block_models(
  fits, X, horizon, 2,
  function(fit, X_block, block_name) as.numeric(X_block %*% fit$beta)
)
stopifnot(identical(sort(names(fits)), c('1-2', '3-4')))
stopifnot(max(abs(pred - y)) < 1e-10)
folds <- pricefm_build_nested_temporal_folds(
  rows,
  n_folds = 3,
  initial_train_fraction = 0.5,
  validation_fraction = 0.15,
  min_train_origins = 20,
  min_validation_origins = 5
)
stopifnot(nrow(folds$summary) == 3)
stopifnot(all(folds$summary$embargo_passed))
for (fold in folds$folds) {{
  train_response <- as.POSIXct(rows$response_market_time[fold$train_index], tz = 'UTC')
  val_origin <- as.POSIXct(rows$origin_market_time[fold$validation_index], tz = 'UTC')
  stopifnot(max(train_response) < min(val_origin))
}}
diag <- pricefm_quantile_diagnostics(y, pred, 0.5)
stopifnot(diag$AQL_scaled < 1e-10)
pooled <- pricefm_partial_pool_predictions(rep(0, length(y)), pred, 0.5)
stopifnot(max(abs(pooled - 0.5 * pred)) < 1e-12)
"""
    result = subprocess.run(
        [str(RSCRIPT), "-e", code],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_runner_consumes_nested_and_separate_readout_configuration():
    text = RUNNER.read_text()
    assert 'cfg$qdesn_vb$readout_modes' in text
    assert '"separate_horizon_block"' in text
    assert "pricefm_fit_horizon_block_models" in text
    assert "pricefm_predict_horizon_block_models" in text
    assert "pricefm_build_nested_temporal_folds" in text
    assert "nested_validation_metrics.csv" in text
    assert "nested_partial_pooling_metrics.csv" in text
    assert "nested_partial_pooling_convergence.csv" in text
    assert "nested_warm_start_diagnostics.csv" in text
    assert 'source_label <- paste0("nested_al_tau_", tau_key(tau))' in text
    assert 'X_inner,' in text
    assert 'y_inner,' in text
    assert 'existing_test_role = "not_loaded_not_predicted_not_selected"' in text


@pytest.mark.skipif(not PACKAGE_ROOT.exists(), reason="PriceFM exdqlm package worktree unavailable")
def test_actual_runner_fits_nested_shared_and_separate_readouts_without_test(tmp_path):
    adapter = tmp_path / "adapter"
    output = tmp_path / "model"
    adapter.mkdir()
    horizons = np.arange(1, 5, dtype=int)

    def write_split(split: str, n_origins: int, start: str) -> None:
        origin = np.repeat(np.arange(1, n_origins + 1), len(horizons))
        horizon = np.tile(horizons, n_origins)
        base = np.repeat(np.linspace(-1.0, 1.0, n_origins), len(horizons))
        X = np.column_stack([np.ones(origin.size), base, horizon / 4.0])
        y = 0.4 * base + np.where(horizon <= 2, 0.6, -0.5) + 0.03 * horizon
        origin_time = pd.Timestamp(start, tz="UTC") + pd.to_timedelta(origin - 1, unit="D")
        response_time = origin_time + pd.to_timedelta(horizon, unit="h")
        np.savetxt(adapter / f"X_{split}.csv", X, delimiter=",", fmt="%.17g")
        np.savetxt(adapter / f"y_{split}.csv", y[:, None], delimiter=",", fmt="%.17g")
        pd.DataFrame({
            "split": split,
            "origin_id": origin,
            "horizon": horizon,
            "origin_market_time": origin_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "response_market_time": response_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "y_scaled": y,
        }).to_csv(adapter / f"rows_{split}.csv", index=False)

    write_split("train", 48, "2024-01-01")
    write_split("val", 8, "2024-03-01")
    (adapter / "adapter_manifest.json").write_text("{}\n")
    config = tmp_path / "config.yaml"
    config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "data_config": str(ROOT / "application" / "config" / "pricefm_data_pipeline.yaml"),
            "package_path": str(PACKAGE_ROOT),
            "region": "UNIT",
            "fold": 1,
            "splits": ["train", "val"],
            "horizons": horizons.tolist(),
            "quantiles": [0.5],
            "adapter": {"output_dir": str(adapter)},
            "run": {"output_dir": str(output), "seed": 20260804, "nd_predictive": 10},
            "rhs_ns": {
                "tau0": 1.0e-4,
                "shrink_intercept": False,
                "freeze_tau_iters": 1,
                "freeze_tau_warmup_iters": 1,
            },
            "warm_start": {
                "enabled": True,
                "record_diagnostics": True,
                "fallback_to_cold": False,
                "qdesn": {
                    "al": {
                        "enabled": True,
                        "first_tau_source": "normal_rhs_ns",
                        "next_tau_source": "previous_al_tau",
                        "tau_order": [0.5],
                        "components": ["beta", "beta_state", "sigma"],
                    },
                    "exal": {
                        "enabled": True,
                        "source": "al_same_tau",
                        "components": ["beta", "beta_state", "sigma"],
                        "gamma_policy": "zero",
                    },
                },
            },
            "normal": {
                "enabled": True,
                "omega_prior": {"a": 2.0, "b": 1.0},
                "vb_control": {"max_iter": 5, "min_iter": 2, "tol": 1.0e-3, "verbose": False},
            },
            "qdesn_vb": {
                "likelihoods": ["al", "exal"],
                "readout_modes": ["shared_static", "separate_horizon_block"],
                "horizon_readout": {
                    "block_size": 2,
                    "warm_start_components": ["beta", "beta_state", "sigma"],
                    "partial_pooling": {
                        "enabled": True,
                        "weights": [0.0, 0.5, 1.0],
                    },
                },
                "max_iter": 5,
                "min_iter_elbo": 2,
                "tol": 1.0e-3,
                "tol_par": 1.0e-3,
                "n_samp_xi": 4,
                "prior_sigma": {"a": 1.0, "b": 1.0},
                "prior_gamma": {"mu0": 0.0, "s20": 10.0},
                "chunking": {
                    "enabled": True,
                    "mode": "exact",
                    "chunk_size": 64,
                    "order": "sequential",
                    "trace": False,
                },
            },
            "exact_equivalence": {"enabled": False},
            "training": {"horizon_weighting": {"enabled": False}},
            "nested_validation": {
                "enabled": True,
                "n_folds": 2,
                "initial_train_fraction": 0.5,
                "validation_fraction": 0.2,
                "min_train_origins": 20,
                "min_validation_origins": 6,
            },
        }
    }, sort_keys=False))

    result = subprocess.run(
        [str(RSCRIPT), str(RUNNER), "--smoke-config", str(config), "--force", "true"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    methods = pd.read_csv(output / "model_method_summary.csv")
    assert set(methods["readout_mode"]) == {"shared_static", "separate_horizon_block"}
    nested = pd.read_csv(output / "nested_validation_metrics.csv")
    assert len(nested) == 8
    assert set(nested["readout_mode"]) == {"shared_static", "separate_horizon_block"}
    assert set(nested["likelihood_family"]) == {"al", "exal"}
    pooling = pd.read_csv(output / "nested_partial_pooling_metrics.csv")
    assert len(pooling) == 2 * 2 * 2 * 3
    assert set(pooling["separate_weight"]) == {0.0, 0.5, 1.0}
    convergence = pd.read_csv(output / "nested_partial_pooling_convergence.csv")
    assert len(convergence) == 2 * 2 * 2
    warm = pd.read_csv(output / "nested_warm_start_diagnostics.csv")
    nested_exal = warm[(warm["likelihood_family"] == "exal") & (warm["readout_mode"] == "shared_static")]
    assert len(nested_exal) == 2
    assert set(nested_exal["init_source"]) == {"nested_al_tau_0.5"}
    assert nested_exal["source_available"].all()
    assert nested_exal["init_components"].str.contains("beta").all()
    predictions = pd.read_csv(output / "model_predictions_scaled.csv")
    assert set(predictions["split"]) == {"val"}
    manifest = json.loads((output / "run_manifest.json").read_text())
    assert manifest["configured_splits"] == ["train", "val"]
    assert manifest["evaluation_splits"] == "val" or manifest["evaluation_splits"] == ["val"]
    assert not (adapter / "X_test.csv").exists()
    assert not (output / "nested_validation_predictions_test.csv").exists()
