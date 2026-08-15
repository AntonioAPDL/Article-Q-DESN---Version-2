# Joint-QVP Synthetic DGP Fit Validation Phase 2

Date: 2026-07-02  
Scope: registry-driven train-split fit validation for the joint multi-quantile
QVP synthetic study. This phase does not implement rolling-origin forecast
validation and does not change TT500, GloFAS, or PriceFM outputs.

## Purpose

Phase 2 consumes the Phase 1 synthetic DGP fixtures and validates fit recovery
on the declared train split only. It is the bridge between source-truth
materialization and the future forecast-validation study.

The primary engine is AL-VB with `kappa = 1`, matching the current validated
joint-QVP synthetic lane. Selected short VB-initialized MCMC runs are included
as implementation references, not as final posterior-promotion evidence.

## Inputs

Default registry:

```text
application/config/joint_qvp_synthetic_dgp_registry_phase1.csv
```

Default Phase 1 fixture directory:

```text
application/cache/joint_qvp_synthetic_dgp_registry_phase1_20260702/
```

The Phase 2 runner can either consume an existing fixture directory or
materialize Phase 1 fixtures inside the Phase 2 output directory. In both cases
it verifies the Phase 1 artifact manifest before fitting.

## Implementation

Core function:

```text
app_joint_qvp_run_synthetic_dgp_fit_validation()
```

Script:

```sh
Rscript application/scripts/76_run_joint_qvp_synthetic_dgp_fit_validation.R
```

Useful smoke command:

```sh
Rscript application/scripts/76_run_joint_qvp_synthetic_dgp_fit_validation.R \
  --smoke true \
  --scenario-ids normal_bridge \
  --vb-max-iter 40 \
  --adaptive-vb-max-iter-grid 40 \
  --n-chains 1 \
  --mcmc-n-iter 30 \
  --mcmc-burn 10 \
  --mcmc-thin 5
```

The loader reconstructs one train-only fit fixture per scenario from:

- `observed_series.csv`
- `design_matrix.csv`
- `true_quantile_wide.csv`
- `split_metadata.csv`
- `scenario_summary.csv`
- `frozen_registry.csv`

It checks that train rows lie inside the declared train window and that no test
time index enters the fit object.

The optional `--scenario-ids` argument accepts a comma-separated list and is
intended for smoke checks, targeted reruns, and debugging. Omitting it runs all
enabled scenarios present in the Phase 1 fixtures.

## Outputs

Default output:

```text
application/cache/joint_qvp_synthetic_dgp_fit_validation_phase2_20260702/
```

The runner writes:

- `run_config.csv`
- `fixture_source_manifest.csv`
- `fit_validation_assessment.csv`
- `fit_summary.csv`
- `truth_fit_summary.csv`
- `pinball_summary.csv`
- `hit_rate_summary.csv`
- `crossing_summary.csv`
- `vb_convergence_audit.csv`
- `objective_diagnostics.csv`
- `elbo_terms.csv`
- `rhs_prior_summary.csv`
- `mcmc_reference_summary.csv`
- `mcmc_draw_summary.csv`
- `chain_summary.csv`
- `vb_mcmc_distance_summary.csv`
- `runtime_summary.csv`
- `provenance.csv`
- `README.md`
- `artifact_manifest.csv`

## Gates

Hard implementation failures include:

- missing or unverifiable Phase 1 fixture hashes;
- malformed split metadata;
- nonfinite observations, features, truth, fitted summaries, or scores;
- nonpositive scale paths in the source fixture;
- train/test leakage;
- fitted quantile crossings after the declared diagnostic contract;
- selected MCMC references that do not use VB initialization or have nonfinite
  draws.

Review statuses include:

- VB reaching the iteration cap while producing finite summaries;
- objective accounting requiring review;
- truth-distance or hit-rate deviations outside provisional thresholds;
- selected short MCMC references with loose VB/MCMC distance review.

Passing Phase 2 means the implementation, split, finiteness, crossing, and
fit-metric gates are satisfied for train-split validation. It is not a forecast
claim.

## MCMC Reference Layer

The default selected MCMC references are:

- `normal_bridge`
- `gaussian_mixture_bridge`
- `asymmetric_laplace_tail`
- `persistent_heavy_tail`

These runs are short and VB-initialized. They test integration, finite draws,
warm starts, and broad VB/MCMC agreement. Longer-chain MCMC references remain a
later calibration layer.

Very short smoke chains can fail crossing or VB/MCMC distance gates. Those
failures should be read as conservative implementation diagnostics, not as
posterior validation evidence.

## Next Phase

Phase 3 should add rolling-origin forecast validation over the same registry
fixtures. It should reuse the Phase 1 source contract and Phase 2 fit outputs,
then score held-out test rows with pinball loss, interval score, WIS-style
interval summaries, CRPS grid approximations, coverage, sharpness, crossing
diagnostics, and runtime.
