# GloFAS Q-DESN Feature Contract

Date: 2026-05-12

## Purpose

This note records the article-side feature contract used by the GloFAS
discrepancy-calibration application. The contract is separate from the sampler:
it defines the fixed readout matrix passed to the Q-DESN discrepancy engine and
the matching prediction matrix used for posterior-draw forecast correction.

The contract is designed to make model-specification changes reproducible. DESN
architecture, output lags, precipitation and soil lags, readout-intercept
handling, and horizon features are all controlled from the YAML configuration.

## Bias and Intercept Rule

The reservoir input may include an internal bias. That bias is part of the
reservoir-state recursion and is controlled by the engine arguments. The
Bayesian readout has its own intercept, controlled by
`feature_contract.readout.add_intercept`.

The article adapter now calls the reservoir design builder with the engine
readout bias disabled. The fitted readout matrix may therefore contain
`readout_intercept`, but it must not contain the reservoir's internal bias as a
second constant-one column. This avoids duplicate-intercept and identification
problems in the ridge and regularized-horseshoe readout priors.

## Large Dec. 25 Contract

The large VB and MCMC Dec. 25 configurations use
`feature_contract.version = "0.2"`. For a forecast origin \(T\), target
\(T+h\), and horizon scale \(H\), the prediction-row contract is

```text
[readout_intercept, reservoir_state_at_T, y_lags_at_T,
 ppt_soil_lags_at_T_plus_h, h / H]
```

The active large profile contains:

- one readout intercept;
- 1,000 fixed reservoir-state features from `D = 2`, `n = (500, 500)`;
- 180 direct transformed-streamflow lags, `y_lag_1` through `y_lag_180`;
- 122 direct precipitation and soil features, `ppt_lag_0` through `ppt_lag_60`
  and `soil_lag_0` through `soil_lag_60`;
- one scaled-horizon feature.

The resulting base readout matrix has 1,304 columns. The source-augmented
discrepancy design has 2,608 columns because the shared quantile and GloFAS
discrepancy readouts each receive the same feature block.

## Forecast Alignment

Output lags are anchored at the forecast origin. For a prediction row at
origin \(T\), `y_lag_ell` uses the transformed reference value at
\(T-\ell\). It never uses reference values from the issued forecast window.

Covariate lags are anchored at the target date. For a prediction row at
target \(T+h\), `ppt_lag_ell` and `soil_lag_ell` use the model-facing
precipitation and soil timeline at \(T+h-\ell\). In the forecast window, that
timeline is the deterministic blended GEFS construction documented in the
covariate contract.

## Validation Gates

The application tests verify:

- range and explicit-value lag specifications;
- strict rejection of lag 0 for output-lag features;
- allowance of lag 0 for target-date covariates;
- rejection of any direct readout input block that tries to include the
  reservoir's internal bias;
- output-lag forecast rows anchored at the origin rather than at future target
  dates;
- consistent column order between fitted and prediction matrices.

The Dec. 25 p50 VB design preflight

```sh
Rscript application/scripts/03_check_model_design.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id feature_contract_check_20260512
```

completed successfully with 12,495 base feature rows, 26,418 stacked response
rows, 1,304 base readout features, and 28 issued prediction rows.
