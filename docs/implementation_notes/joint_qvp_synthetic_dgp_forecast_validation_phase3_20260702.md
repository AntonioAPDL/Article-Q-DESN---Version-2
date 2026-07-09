# Joint-QVP Synthetic DGP Forecast Validation Phase 3

Date: 2026-07-02  
Scope: registry-driven rolling-origin forecast validation for the joint
multi-quantile QVP synthetic study. This phase does not change TT500, GloFAS,
or PriceFM outputs.

## Purpose

Phase 3 consumes the Phase 1 synthetic DGP fixtures and validates held-out
forecast behavior on the declared test split. It complements Phase 2, which
validates train-split fit recovery only.

The primary engine is AL-VB with `kappa = 1`. MCMC posterior promotion is not
part of this phase. The runner uses the source-truth fixture contract from
Phase 1, the fit/gate conventions from Phase 2, and forecast scores appropriate
for multi-quantile forecasts.

## Rolling-Origin Design

The default protocol is expanding-window, one-step-ahead forecasting over test
rows:

- first forecast origin fits on the declared train split;
- later origins may include previously observed test rows;
- the current and future test target rows are never included in a fit;
- `refit_stride = 1` refits at every origin by default;
- larger `refit_stride` values reuse the most recent earlier fit and are useful
  for smoke checks.

The optional `--scenario-ids` argument accepts a comma-separated list for
targeted runs. The optional `--max-origins-per-scenario` argument limits the
number of test origins for smoke/debugging.

## Implementation

Core function:

```text
app_joint_qvp_run_synthetic_dgp_forecast_validation()
```

Script:

```sh
Rscript application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R
```

Useful smoke command:

```sh
Rscript application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R \
  --smoke true \
  --vb-max-iter 8 \
  --adaptive-vb-max-iter-grid 8 \
  --refit-stride 2 \
  --max-origins-per-scenario 3
```

The loader reconstructs retained train/test forecast fixtures from:

- `observed_series.csv`
- `design_matrix.csv`
- `true_quantile_wide.csv`
- `true_quantile_long.csv`
- `split_metadata.csv`
- `scenario_summary.csv`
- `frozen_registry.csv`

It verifies the Phase 1 artifact manifest before fitting and records the
verified source hashes in the Phase 3 artifact directory.

## Outputs

Default output:

```text
application/cache/joint_qvp_synthetic_dgp_forecast_validation_phase3_20260702/
```

The runner writes:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `forecast_origin_config.csv`
- `forecast_quantiles_raw.csv`
- `forecast_quantiles.csv`
- `forecast_monotone_adjustment.csv`
- `forecast_truth_comparison.csv`
- `pinball_summary.csv`
- `hit_rate_summary.csv`
- `interval_coverage_summary.csv`
- `interval_score_summary.csv`
- `wis_summary.csv`
- `crps_grid_summary.csv`
- `raw_crossing_summary.csv`
- `crossing_summary.csv`
- `vb_convergence_audit.csv`
- `objective_diagnostics.csv`
- `runtime_summary.csv`
- `forecast_validation_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Scores

Phase 3 reports:

- raw forecast quantiles before monotone projection;
- monotone contract forecast quantiles used for scoring;
- raw-to-contract monotone adjustment diagnostics;
- pinball/check loss by scenario and tau;
- empirical hit rates and hit-rate errors by tau;
- central interval coverage when paired tau levels exist;
- interval width/sharpness and interval score;
- WIS-style summaries when a median and central intervals are present;
- CRPS grid approximations from the quantile grid;
- truth-distance summaries comparing forecast quantiles to oracle conditional
  quantiles;
- quantile crossing diagnostics;
- VB convergence/objective diagnostics and runtime by origin.

## Gates

Hard implementation failures include:

- missing or unverifiable Phase 1 fixture hashes;
- malformed split metadata;
- nonfinite observations, features, truth, forecast quantiles, or scores;
- nonpositive source scale paths;
- train/test leakage at any rolling origin;
- forecast quantile crossings after the declared diagnostic contract.

Review statuses include:

- VB reaching the max-iteration cap while producing finite forecasts;
- objective accounting requiring review;
- truth-distance or hit-rate deviations outside provisional thresholds.

Passing Phase 3 means the source, leakage, finiteness, crossing, score, and
diagnostic gates are satisfied for held-out forecast validation. It is not a
final article promotion claim until the full article-scale run and threshold
calibration are complete.

## Tests

Focused Phase 3 tests exercise:

- Phase 1 fixture loading into forecast fixtures;
- rolling-origin train/test slicing;
- one-step test-row alignment;
- output schemas and artifact hashes;
- finite forecast quantiles, scores, truth distances, intervals, WIS, CRPS, and
  crossing diagnostics;
- deterministic repeated smoke-run hashes where runtime is excluded.

## Next Phase

After this implementation smoke layer, run the full article-scale Phase 3
campaign over the complete registry, calibrate forecast thresholds using
separate calibration seeds, and then freeze the final validation tables and
figures for article integration.
