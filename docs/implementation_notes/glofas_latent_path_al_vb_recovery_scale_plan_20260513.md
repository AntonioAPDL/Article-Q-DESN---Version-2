# Latent-Path AL-VB Recovery and Scale-Up Plan

Date: 2026-05-13

## Purpose

The latent-path AL-VB smoke workflow is now implemented and passes the current
application tests. The next development step is to make that workflow
statistically trustworthy and computationally ready for the full Dec. 25
GloFAS application run. This note defines the reproducible plan for:

1. freezing the smoke-test checkpoint;
2. adding a synthetic recovery gate for latent-path AL-VB inference;
3. profiling and scaling the AL-VB implementation so the next real-data launch
   can use the full intended configuration rather than a staged partial run.

The smoke profile is a software contract check, not an application-scale
analysis. The recovery and profiling gates below are required before using a
full real-data fit for manuscript interpretation.

## Current Checkpoint

The current checkpoint is:

```text
commit fc64b08  Add latent-path AL-VB smoke workflow
branch application-ensemble-likelihood-redesign
```

It includes:

- recursive latent future-state continuation with strict-lag Jacobians;
- an article-side AL-VB fitter for the latent-path ensemble-likelihood model;
- posterior-draw prediction output compatible with the existing discrepancy
  prediction contract;
- a small Dec. 25, 2022 smoke configuration;
- unit tests for strict-lag future-state sensitivities and AL-VB smoke
  behavior.

The latest checked smoke run at the time of this note was:

```text
application/runs/latent_path_smoke_fit_20260513_210015
```

That run completed and passed the posterior-draw identity check. It used
explicit smoke-only limits on history length, horizon length, and ensemble
members per horizon.

## Design Principles

### Reproducibility

Every synthetic and real-data fit must record:

- article git SHA;
- Q-DESN engine git SHA;
- input manifest hash;
- config hash;
- model-grid hash or model row identity;
- design hash;
- prediction-design hash;
- random seeds;
- elapsed runtime;
- convergence diagnostics;
- fit status and failure messages.

The output location must follow the existing `application/runs/<run_id>/`
contract. No diagnostic should depend on files outside the run directory except
through paths recorded in the run manifest.

### Bayesian Prediction Contract

The latent-path model is a posterior-draw workflow. Point summaries are
secondary. For draw \(s\) and horizon \(h\), the prediction table must preserve
the draw-level identity

```text
q_y_draw[s, h] = q_g_draw[s, h] - d_g_draw[s, h].
```

For the latent-path model, the reported `q_g_draw` is the model-implied GloFAS
quantile draw,

```text
q_g_draw[s, h] = q_y_draw[s, h] + d_g_draw[s, h],
```

where the future state features are recomputed from the sampled latent future
path \(Y_F^{(s)}\). The issued ensemble members enter the fit through the
likelihood; they are not converted into an empirical post-fit quantile.

### Approximation Honesty

The AL-VB route uses a Laplace--Delta approximation for the latent future path.
The monitored objective must remain labeled as an approximation, not as the
exact ELBO of the nonlinear latent-path model. Any scale-up claim should report:

- the future-path covariance structure used;
- whether any Hessian or precision repair was needed;
- the number of VB iterations;
- the final approximate objective;
- the maximum relative parameter change;
- whether posterior draws are finite and satisfy the prediction identity.

### Full-Run Philosophy

The next real-data launch should be the full intended configuration after the
synthetic and profiling gates pass. We do not need a sequence of scientific
partial runs. Small or reduced runs are allowed only as engineering tests for
the synthetic gate and profiler.

## Stage 1: Checkpoint Freeze

Status: completed.

Required actions:

- Commit the smoke-test implementation as a standalone checkpoint.
- Keep the smoke config available as a reproducible wiring check.
- Do not alter the meaning of the smoke config when developing full-scale
  paths. If a new smoke profile is needed, add a new config rather than
  silently changing historical run interpretation.

Completion criteria:

- `git log` contains the checkpoint commit.
- `Rscript application/tests/run_tests.R` passes after the checkpoint.
- The smoke run writes `fit_status.csv`, `posterior_draw_predictions.csv`,
  `qdesn_discrepancy_draw_checks.csv`, `qdesn_discrepancy_design_summary.csv`,
  and `qdesn_discrepancy_fit_manifest.csv`.

## Stage 2: Synthetic Recovery Gate

### Goal

Create a deterministic synthetic latent-path experiment that verifies the
AL-VB fitter is recovering the intended statistical object, not merely
producing finite output.

### Synthetic Data Contract

Add a synthetic fixture that returns:

- a panel compatible with `app_make_glofas_latent_path_data()`;
- a cutoff row with a known forecast origin and contiguous horizon;
- a model row compatible with `qdesn_glofas_discrepancy`;
- true \(\beta\), \(\alpha\), \(\sigma_Y\), and \(\sigma_G\);
- true historical and future reference paths;
- true retrospective and issued GloFAS quantile paths;
- the true discrepancy path;
- the seed and generation settings.

The first recovery fixture should use a small deterministic feature map that is
transparent enough for known-truth checks. A Q-DESN-based synthetic fixture can
be added after the first gate passes, but the first gate should isolate the
AL-VB update logic from reservoir randomness.

### Required Tests

Add tests under `application/tests/test_latent_path_recovery.R`.

The tests should verify:

- fixed row counts for historical USGS, retrospective GloFAS, latent future
  USGS, and issued GloFAS rows;
- requested and effective horizon recording;
- shared `sigma_G` ownership across retrospective and issued GloFAS rows;
- strict-lag future-feature construction;
- finite posterior draws for \(\theta\), \(\sigma_Y\), \(\sigma_G\), and
  \(Y_F\);
- posterior-draw identity to numerical tolerance;
- recovery of the reference quantile path and discrepancy path within explicit
  tolerances.

Initial tolerances should be deliberately loose because this is a variational
approximation and a small synthetic sample. Recommended first thresholds:

```text
median absolute q_Y path error <= 0.35
median absolute q_G path error <= 0.35
median absolute discrepancy path error <= 0.35
relative sigma_Y error <= 0.75
relative sigma_G error <= 0.75
```

These thresholds should be tightened only after repeated synthetic seeds show
stable behavior.

### Synthetic Run Script

Add a script:

```text
application/scripts/03_run_latent_path_synthetic_recovery.R
```

The script should:

1. read a small synthetic recovery config;
2. generate the synthetic panel and truth object;
3. fit the AL-VB latent-path model;
4. write fit objects, posterior draws, truth tables, recovery metrics, and run
   manifests under `application/runs/<run_id>/`;
5. exit with nonzero status if required recovery metrics fail.

The script should not require the real GloFAS input bundle. Synthetic recovery
must be fast and available on any clone with the R dependencies installed.

### Synthetic Config

Add a tracked config:

```text
application/config/glofas_latent_path_al_vb_synthetic_recovery.yaml
```

The config should include:

- seed;
- history length;
- horizon;
- ensemble members per horizon;
- quantile level;
- true coefficient vector;
- source scales;
- VB iteration and draw counts;
- recovery tolerances.

### Completion Criteria

Stage 2 is complete when:

- `Rscript application/tests/run_tests.R` passes;
- the synthetic recovery script completes with status `completed`;
- recovery metrics are written and pass their configured thresholds;
- the run manifest records the synthetic truth seed and config hash;
- the documentation explains that this gate validates AL-VB mechanics, not
  real-data performance.

## Stage 3: Profiling and Full-Scale Readiness

### Goal

Prepare the AL-VB implementation for the full Dec. 25 real-data run without
changing the statistical target.

The current dense implementation recomputes future-state designs and builds
large dense moment matrices. That is acceptable for a smoke test but likely too
slow for:

```text
full history
full available issued horizon
all issued ensemble members
D = 2
n = (500, 500)
n_tilde = 500
m = 180
washout = 500
RHS tau0 = 1e-4
```

Stage 3 should identify and reduce the dominant costs before launching the full
fit.

### Profiling Script

Add a profiling script:

```text
application/scripts/03_profile_latent_path_al_vb.R
```

The script should run deterministic micro-profiles for:

- future-builder evaluation;
- strict-lag Jacobian construction;
- row-moment assembly;
- theta precision/rhs update;
- future-path Laplace step;
- posterior-draw prediction construction.

The profiler should write:

```text
tables/latent_path_profile_summary.csv
tables/latent_path_profile_steps.csv
manifest/latent_path_profile_config.json
```

The summary should include elapsed time, row counts, feature counts, horizon,
member count, history count, memory estimates where available, and the active
config hash.

### Scaling Improvements

Prioritize changes that preserve readability and the current API:

1. Cache fixed historical row moments.
2. Cache future ensemble row mappings from horizon to member rows.
3. Avoid rebuilding direct covariate lag blocks when only \(Y_F\) changes.
4. Vectorize the fixed-row contribution to theta and scale updates.
5. Use source-specific row groups for AL mixture and scale updates.
6. Avoid storing full \(p \times p\) Delta matrices for each row when the
   Jacobian contribution can be accumulated directly.
7. Keep dense matrices only where the prototype requires them; record any
   remaining dense bottleneck explicitly.

Do not add opaque performance tricks that make the model hard to audit. A
moderately faster implementation with transparent linear algebra is preferred
over a fragile implementation that is difficult to verify.

### Full-Run Config Preparation

Add or update a full-run config only after the profiler passes:

```text
application/config/glofas_latent_path_al_vb_dec25_full.yaml
application/config/model_grid_latent_path_al_vb_dec25_full.csv
```

The full config should use:

```text
application_model.contract: latent_path_ensemble_likelihood
application_model.max_history_rows: null
application_model.max_ensemble_members_per_horizon: null
prediction.q_g_source: posterior_model_quantile
prediction.prediction_unit: posterior_draw
feature_contract.two_block_design: false for the first full latent-path fit
feature_contract.reservoir_input.output_lags: [1, 180]
feature_contract.readout.input_block.output_lags: [1, 180]
feature_contract.readout.input_block.covariates.ppt: [0, 60]
feature_contract.readout.input_block.covariates.soil: [0, 60]
reservoir.D: 2
reservoir.n: [500, 500]
reservoir.n_tilde: [500]
reservoir.m: 180
reservoir.washout: 500
inference.vb_ld.rhs_tau0: 1e-4
```

The effective horizon should remain data-driven: use the largest contiguous
available issued horizon up to the requested maximum and record both values.

### Completion Criteria

Stage 3 is complete when:

- synthetic recovery still passes after optimization;
- the Dec. 25 smoke profile still passes;
- the profiler writes step-level timing and memory summaries;
- the profile identifies no unbounded or accidental quadratic work in the
  number of issued ensemble rows beyond the intended likelihood rows;
- the full-run config validates through `00_check_inputs.R`,
  `01_build_panel.R`, and `03_check_model_design.R`;
- the full-run config is documented as ready to launch, but not launched inside
  the profiling stage.

## Full Launch Gate

The full Dec. 25 AL-VB run may be launched only after Stages 2 and 3 pass.
Before launch, run:

```text
Rscript application/tests/run_tests.R
Rscript application/scripts/00_check_inputs.R --config application/config/glofas_latent_path_al_vb_dec25_full.yaml
Rscript application/scripts/01_build_panel.R --config application/config/glofas_latent_path_al_vb_dec25_full.yaml
Rscript application/scripts/03_check_model_design.R --config application/config/glofas_latent_path_al_vb_dec25_full.yaml
Rscript application/scripts/03_profile_latent_path_al_vb.R --config application/config/glofas_latent_path_al_vb_dec25_full.yaml
```

If those pass, launch the full fit with:

```text
Rscript application/scripts/03_fit_models.R --config application/config/glofas_latent_path_al_vb_dec25_full.yaml
```

The full run must be monitored live. If it fails, the failure should be recorded
as a run artifact rather than patched silently.

## Non-Goals for This Pass

This pass does not implement:

- AL-MCMC latent-path inference;
- exAL-VB;
- exAL-MCMC;
- a two-reservoir latent future continuation;
- reservoir-input covariates.

Those extensions should be added only after the AL-VB path passes synthetic
recovery and the full Dec. 25 launch is computationally feasible.
