# Joint QDESN VB fit and no-refit forecast validation

Date: 2026-07-06

This note documents the article-scale VB validation layer for the new joint QDESN simulation study. It implements the next stage after the VB-readiness audit and long-series DGP fixture materialization.

## Scope

The implementation is scoped to the new QDESN simulation study only. It does not modify TT500, GloFAS, PriceFM, or the older joint-QVP Phase 4 calibration campaign.

The implemented model set is:

- `JOINT QDESN RHS`;
- `JOINT exQDESN RHS`;
- `QDESN RHS`;
- `exQDESN RHS`.

The first two are joint multi-quantile readouts. The latter two are independent single-quantile comparators assembled across the same quantile grid and passed through the same monotone output contract.

## Implemented Files

- `application/R/joint_qdesn_simulation_validation.R`
- `application/scripts/99_run_joint_qdesn_simulation_vb_fit_validation.R`
- `application/scripts/101_run_joint_qdesn_simulation_vb_forecast_validation.R`
- `application/tests/test_joint_qdesn_simulation_validation.R`
- `docs/implementation_notes/joint_qdesn_simulation_main_launch_audit_plan_20260706.md`
- `docs/implementation_notes/joint_qdesn_simulation_vb_fit_forecast_validation_20260706.md`

## Source Fixture Contract

Both runners consume the frozen fixture directory:

`application/cache/joint_qdesn_simulation_dgp_fixtures_20260706`

Before fitting, the runners verify the fixture `artifact_manifest.csv` and require every source artifact hash to match. They also require the fixture validation table to contain only `pass` rows.

The fixture layer provides:

- 9 DGP scenarios;
- 12000 simulated rows per scenario;
- 2000 DGP warmup rows;
- 10000 effective rows;
- last 2000 effective rows as 500 DESN washout, 500 fit rows, and 1000 validation rows;
- 297 no-refit forecast-origin rows across all scenarios;
- materialized oracle conditional quantiles.

## Fit Validation

The fit runner uses only rows with `role == "fit"`. It writes:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `model_fit_summary.csv`
- `fit_quantiles_raw.csv`
- `fit_quantiles.csv`
- `fit_monotone_adjustment.csv`
- `fit_truth_comparison.csv`
- `check_loss_summary.csv`
- `crps_grid_summary.csv`
- `hit_rate_summary.csv`
- `interval_summary.csv`
- `crossing_summary.csv`
- `raw_crossing_summary.csv`
- `vb_convergence_audit.csv`
- `objective_diagnostics.csv`
- `rhs_prior_summary.csv`
- `scale_parameter_summary.csv`
- `runtime_summary.csv`
- `fit_validation_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The scored contract quantiles are written to `fit_quantiles.csv`. Raw model outputs are preserved separately in `fit_quantiles_raw.csv`.

## Forecast Validation

The forecast runner fits each scenario-model pair once on the declared fit window and evaluates the frozen validation-origin plan. It does not refit within validation blocks.

The runner writes:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `forecast_origin_plan.csv`
- `forecast_quantiles_raw.csv`
- `forecast_quantiles.csv`
- `forecast_monotone_adjustment.csv`
- `forecast_truth_comparison.csv`
- `truth_distance_summary.csv`
- `check_loss_summary.csv`
- `crps_grid_summary.csv`
- `hit_rate_summary.csv`
- `interval_summary.csv`
- `crossing_summary.csv`
- `raw_crossing_summary.csv`
- `vb_convergence_audit.csv`
- `objective_diagnostics.csv`
- `rhs_prior_summary.csv`
- `runtime_summary.csv`
- `forecast_validation_assessment.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

The forecast design uses target-row features from the frozen synthetic fixture and records `uses_frozen_target_design = TRUE` in `run_config.csv`. Target responses are not used in fitting.

## Noncrossing Contract

Both runners preserve raw quantile outputs and apply the monotone contract before scoring:

- raw outputs: `*_quantiles_raw.csv`;
- contract outputs used for scores: `*_quantiles.csv`;
- adjustment diagnostics: `*_monotone_adjustment.csv`;
- raw crossing diagnostics: `raw_crossing_summary.csv`;
- contract crossing diagnostics: `crossing_summary.csv`.

This keeps raw model behavior visible while ensuring that the reported quantile scores use a coherent noncrossing quantile curve.

## Gates

Hard fail:

- missing or mismatched fixture hashes;
- malformed fixture rows;
- nonfinite fitted or forecast contract quantiles;
- nonfinite check loss or truth-distance scores;
- contract quantile crossings;
- missing runtime.

Review:

- VB reaches max iterations but outputs remain finite;
- raw quantiles cross before the contract step;
- monotone adjustment exceeds the declared review threshold.

Pass:

- all implementation checks pass;
- contract quantiles are finite and noncrossing;
- scores and provenance are complete;
- convergence and adjustment diagnostics are acceptable.

## Verification

Focused checks used during implementation:

```bash
Rscript application/tests/test_joint_qdesn_simulation_validation.R
Rscript application/tests/test_joint_qdesn_simulation_vb_readiness_audit.R
Rscript application/tests/test_joint_qdesn_simulation_dgp_fixtures.R
```

Single-scenario full-fixture checks were also run through the CLI scripts with deliberately tiny VB iteration controls. Those checks produced `review` gates, as expected, because `vb_max_iter` was intentionally set to 2.

## Article-Scale Launch

The article-scale launch should run the fit validation first and then the no-refit forecast validation:

```bash
Rscript application/scripts/99_run_joint_qdesn_simulation_vb_fit_validation.R \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_simulation_vb_fit_validation_article_20260706 \
  --vb-max-iter 240 \
  --adaptive-vb-max-iter-grid 240,480 \
  --rhs-vb-inner 5 \
  --tau0 1 \
  --n-cores 8

Rscript application/scripts/101_run_joint_qdesn_simulation_vb_forecast_validation.R \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_simulation_vb_forecast_validation_article_20260706 \
  --vb-max-iter 240 \
  --adaptive-vb-max-iter-grid 240,480 \
  --rhs-vb-inner 5 \
  --tau0 1 \
  --n-cores 8
```

MCMC remains intentionally deferred until the VB fit and forecast artifacts have been audited.
