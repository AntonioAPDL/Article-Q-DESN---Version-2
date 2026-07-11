# Joint QDESN Phase 122 MCMC Case Confirmation

## Purpose

Phase 122 implements the MCMC confirmation layer required after the Phase 121
case-specific VB/VB-LD winner freeze.  It consumes the frozen per-case winners,
refits each winner on the frozen fit split for initialization, runs short or
article-scale MCMC from that initialization, and evaluates both:

- fit-window quantile-grid recovery; and
- no-refit forecast-window quantile-grid behavior on the frozen validation
  origin plan.

This stage does not change article tables by itself.  It prepares the MCMC
evidence that must pass before article-facing validation assets are rebuilt.

## Predictive Contract

The joint composite AL/exAL likelihood is used as a working likelihood for
quantile readout-path inference.  Phase 122 therefore validates posterior
quantile grids and readout paths.  It does not claim a unique scalar posterior
predictive density for future responses.

The runner writes raw quantile outputs and monotone contract quantile outputs.
Scores use the monotone contract grid.  Raw crossings remain diagnostic review
evidence.

## Supported Rows

Phase 122 supports the four rows requested for final confirmation:

- Joint QDESN RHS under AL;
- Independent QDESN RHS under AL;
- Joint exQDESN RHS under exAL;
- Independent exQDESN RHS under exAL.

Joint rows use the full tau grid in one MCMC fit.  Independent rows run one
single-quantile MCMC chain per tau level and stitch the resulting posterior
readout summaries back into the common quantile grid for scoring.  This matches
the independent single-quantile comparator contract.

## Inputs

Default Phase 121 source:

```text
application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711
```

Default fixture source:

```text
application/cache/joint_qdesn_simulation_dgp_fixtures_20260706
```

Both source manifests are verified before fitting.  The runner refuses to use a
failed Phase 121 manifest.

## Outputs

Default artifact directory:

```text
application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711
```

Main outputs:

- `run_config.csv`;
- `phase121_source_manifest_verification.csv`;
- `fixture_source_manifest.csv`;
- `case_winner_controls.csv`;
- `scenario_worker_failures.csv`;
- `mcmc_case_summary.csv`;
- `mcmc_case_assessment.csv`;
- `fit_quantiles_raw.csv`;
- `fit_quantiles.csv`;
- `fit_monotone_adjustment.csv`;
- `forecast_quantiles_raw.csv`;
- `forecast_quantiles.csv`;
- `forecast_monotone_adjustment.csv`;
- fit/forecast truth, check-loss, hit-rate, grid-CRPS, and interval summaries;
- `crossing_summary.csv`;
- `raw_crossing_summary.csv`;
- `vb_convergence_audit.csv`;
- `objective_diagnostics.csv`;
- `rhs_prior_summary.csv`;
- `scale_parameter_summary.csv`;
- `mcmc_draw_summary.csv`;
- `vb_mcmc_distance_summary.csv`;
- `chain_to_pooled_distance_summary.csv`;
- `runtime_summary.csv`;
- `provenance.csv`;
- `artifact_manifest.csv`;
- `README.md`.

## Gates

Hard fail:

- failed Phase 121 or fixture manifest;
- worker failures;
- nonfinite required fit/forecast/MCMC summaries;
- MCMC chains not initialized from the provided VB/VB-LD fit;
- nonfinite MCMC draws;
- fit or forecast contract quantile crossings.

Review:

- VB initialization reaches max iterations;
- raw quantile crossings before the monotone contract;
- monotone adjustment above the review threshold;
- sigma bound hits;
- VB/MCMC normalized distance above the loose review threshold;
- chain-to-pooled distance above the loose review threshold.

Pass:

- all hard gates pass;
- no review diagnostics exceed thresholds.

## Commands

Focused regression:

```bash
Rscript application/tests/test_joint_qdesn_phase122_mcmc_case_confirmation.R
```

Implementation-check run with one case per model:

```bash
Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \
  --phase121-dir application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_phase122_mcmc_case_confirmation_check_20260711 \
  --scenario-limit-per-model 1 \
  --n-chains 1 \
  --mcmc-n-iter 80 \
  --mcmc-burn 40 \
  --mcmc-thin 5 \
  --n-cores 4
```

Article-candidate launch after the implementation check:

```bash
Rscript application/scripts/125_run_joint_qdesn_phase122_mcmc_case_confirmation.R \
  --phase121-dir application/cache/joint_qdesn_phase121_case_vb_winner_freeze_20260711 \
  --fixture-dir application/cache/joint_qdesn_simulation_dgp_fixtures_20260706 \
  --output-dir application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711 \
  --n-chains 2 \
  --mcmc-n-iter 1200 \
  --mcmc-burn 600 \
  --mcmc-thin 10 \
  --n-cores 12
```

## Next Step

Run the Phase 122 implementation-check command first.  If all four model rows
initialize and produce finite noncrossing contract grids, launch the full
article-candidate MCMC confirmation.  Only after that full run is complete,
audited, and hash-manifested should the authoritative article validation tables
be rebuilt.
