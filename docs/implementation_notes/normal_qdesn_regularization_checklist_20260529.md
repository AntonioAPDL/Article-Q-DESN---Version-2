# Normal DESN And Q-DESN Feature Regularization Checklist

Date: 2026-05-29

## Purpose

This checklist is the implementation plan for regularizing the Normal DESN
Gaussian readout tools with the current Q-DESN AL/exAL ecosystem before running
the final Normal/Q-DESN comparison.

Regularization does not mean forcing identical algorithms into every model.
Normal ridge is a closed-form Gaussian readout, while Q-DESN AL/exAL are
iterative quantile readout fits. The shared standard should be API coherence,
metadata, reproducibility, target labels, test gates, and comparison outputs.

## Current Anchors

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
latest planning checkpoint: d6ba02e Align Normal and Q-DESN comparison planning
```

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
Q-DESN extended-mode checkpoint: f0d45ea Extend Q-DESN VB comparison and subset modes
Normal warm-start checkpoint: 52ea0b0 Add Normal DESN warm-start states
Normal warm-start RHS label test checkpoint: 9f1c32d Cover RHS Normal warm-start labels
Unified comparison launcher checkpoint: 63001e4 Write unified comparison console log
Unified comparison preflight checkpoint: b415b4d Harden unified comparison preflight metadata
```

Ignore unrelated untracked GloFAS memory-refinement files while working on this
checklist. Do not edit Overleaf/main.

## Existing Package Functions

Normal DESN surface:

```text
R/qdesn_normal.R
normal_desn_fit()
qdesn_fit_normal()
normal_desn_posterior_draws()
normal_desn_posterior_predict()
predict_mu.qdesn_normal_fit()
posterior_predict.qdesn_normal_fit()
forecast_paths.qdesn_normal_fit()
qdesn_normal_to_vb_init()
qdesn_normal_to_mcmc_init()
qdesn_normal_make_warm_start()
qdesn_normal_validate_warm_start()
qdesn_normal_warm_start_to_vb_init()
qdesn_normal_warm_start_to_mcmc_init()
```

Q-DESN warm-start and workflow surface:

```text
R/qdesn_vb_warm_start.R
qdesn_vb_make_warm_start()

R/qdesn_vb_rolling_window.R
qdesn_vb_fit_rolling()
qdesn_vb_fit_online()
```

Q-DESN VB control surface:

```text
R/exal_online_state.R
.exal_normalize_vb_chunking_cfg()
.exal_normalize_vb_beta_covariance_cfg()
.exal_normalize_vb_subset_fit_cfg()

R/exal_ldvb_engine.R
exal_ldvb_engine()

R/qdesn_vb.R
qdesn_fit_vb()
```

Comparison scripts:

```text
scripts/run_normal_desn_source_median_comparison_20260529.R
scripts/run_normal_desn_init_comparison_20260529.R
scripts/run_qdesn_vb_implemented_modes_source_median_20260528.R
scripts/summarize_qdesn_vb_implemented_modes_report_20260529.R
```

## Principle Checklist

- [ ] Preserve statistical meanings. Normal DESN is conditional-mean Gaussian;
      Q-DESN is tau-specific conditional quantile AL/exAL.
- [ ] Do not invent stochastic/hybrid Normal ridge. It is closed form and does
      not need iterative stochastic VB.
- [ ] Keep exact chunking labels strict: exact chunking preserves the same
      target only when it accumulates row-additive statistics and performs the
      same global update.
- [ ] Keep approximate labels strict: stochastic, hybrid, diagonal covariance,
      and Normal RHS/RHS_NS VB must be labeled approximate where applicable.
- [ ] Keep target-changing labels strict: subset, rolling-window,
      posterior-as-prior, and online state-handoff modes are not full-data
      equivalence claims.
- [ ] Keep RHS/RHS_NS states global. Do not row-batch or mini-batch shrinkage
      states without a separate derivation and tests.
- [ ] Do not enable pure stochastic exAL before a complete exAL-specific
      stochastic contract exists.
- [ ] Do not implement divide-and-combine VB or variational coresets in this
      phase.

## Stage 0: Baseline Freeze

Objective: establish a clean baseline before any package implementation.

Checklist:

- [x] Fetch article and package repos.
- [x] Confirm package repo is clean at or beyond `f0d45ea`.
- [x] Confirm article docs are at or beyond `e3161ab`.
- [x] Ignore unrelated untracked GloFAS memory-refinement artifacts.
- [x] Run package Normal tests.
- [x] Run package Q-DESN warm-start/batching smoke tests.
- [x] Record pass/fail counts in the implementation note.

Commands:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-warm-start.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
```

Stop if any baseline test fails.

## Stage 1: Normal DESN Warm-Start Metadata

Objective: add a serializable, validated Normal DESN warm-start object. This is
the main alignment gap before the final comparison.

Status: implemented in package commit `52ea0b0 Add Normal DESN warm-start
states`, with direct RHS-family label coverage added in `9f1c32d Cover RHS
Normal warm-start labels`.

Contract source:

```text
docs/implementation_notes/normal_desn_warm_start_contract_20260529.md
```

Package API to add:

```r
qdesn_normal_make_warm_start(object, X = NULL, package_sha = NULL)
qdesn_normal_validate_warm_start(
  warm_start,
  X = NULL,
  meta = NULL,
  strict = TRUE,
  validate_design_hash = TRUE,
  validate_feature_settings_hash = TRUE,
  validate_package_sha = FALSE
)
qdesn_normal_warm_start_to_vb_init(
  warm_start,
  likelihood_family = c("al", "exal"),
  beta_prior_type = c("ridge", "rhs", "rhs_ns"),
  p0 = 0.5,
  eps = 1e-8
)
qdesn_normal_warm_start_to_mcmc_init(
  warm_start,
  likelihood_family = c("al", "exal"),
  beta_prior_type = c("ridge", "rhs", "rhs_ns"),
  p0 = 0.5,
  gamma = 0,
  al_fixed_gamma = 0
)
```

Likely package files:

```text
R/qdesn_normal.R or R/qdesn_normal_warm_start.R
NAMESPACE
man/qdesn_normal.Rd
tests/testthat/test-qdesn-normal-warm-start.R
```

Checklist:

- [x] Support `qdesn_normal_fit` input.
- [x] Support `normal_desn_readout` input when `X` is supplied or stored.
- [x] Record beta mean, beta covariance, and beta dimension.
- [x] Record omega2 shape/rate/mean/mode when available.
- [x] Record target label and exact/approximate status.
- [x] Record prior family and RHS/RHS_NS state if available.
- [x] Record design hash using the same convention as Q-DESN warm starts.
- [x] Record feature settings hash when Q-DESN metadata is available.
- [x] Record package SHA and package version.
- [x] Validate finite beta mean.
- [x] Validate square, symmetric, positive-definite beta covariance.
- [x] Validate finite positive omega2 state.
- [x] Fail on design hash mismatch when requested.
- [x] Fail on feature settings hash mismatch when requested and available.
- [x] Fail on package SHA mismatch only when strict SHA validation is enabled.
- [x] Convert to VB init with the same fields as `qdesn_normal_to_vb_init()`.
- [x] Convert to MCMC init with the same fields as
      `qdesn_normal_to_mcmc_init()`.
- [x] Preserve existing initializer behavior.
- [x] Do not touch `R/exal_ldvb_engine.R`, `R/exal_inference_config.R`, or
      `R/exal_online_state.R` for this stage.

Required tests:

- [x] scaled-ridge Normal fit creates a warm-start object;
- [x] exact-chunked scaled-ridge Normal fit records exact-chunked label;
- [x] `qdesn_normal_fit` records feature hashes and validates them;
- [x] `saveRDS()` / `readRDS()` round trip passes validation;
- [x] design hash mismatch fails;
- [x] feature settings hash mismatch fails when strict;
- [x] package SHA mismatch fails only when requested;
- [x] invalid covariance fails;
- [x] invalid omega2 state fails;
- [x] VB init conversion matches existing initializer fields;
- [x] MCMC init conversion matches existing initializer fields;
- [x] source metadata is preserved.

Implemented validation:

```text
test-qdesn-normal-warm-start.R: 36 pass
test-qdesn-normal.R: 144 pass
test-qdesn-normal-init-comparison.R: 9 pass
test-qdesn-vb-warm-start.R: 39 pass
test-qdesn-vb-batching-modes.R: 42 pass
focused total: 270 pass, 0 fail
```

Post-stage tests:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-warm-start.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-warm-start.R")'
```

Commit boundary:

```text
Package: Add Normal DESN warm-start metadata
Article: Document Normal DESN warm-start metadata
```

## Stage 2: Normal/Q-DESN Method Availability Update

Objective: make the method matrix reflect the actual package state after
Normal warm starts and Q-DESN commit `f0d45ea`.

Docs to update:

```text
docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
docs/implementation_notes/normal_qdesn_alignment_audit_20260529.md
docs/implementation_notes/normal_qdesn_unified_comparison_contract_20260529.md
```

Checklist:

- [ ] Mark Normal warm-start metadata as implemented after tests pass.
- [ ] Keep Normal stochastic/hybrid batching gated or not applicable.
- [ ] Keep Normal ridge exact and exact chunked labels separate.
- [ ] Keep Normal RHS/RHS_NS approximate.
- [ ] Include Q-DESN AL response-quantile and design-leverage subsets.
- [ ] Include Q-DESN exAL ridge diagonal as diagnostic covariance
      approximation, not recommended default.
- [ ] Include Q-DESN exAL RHS/RHS_NS hybrid.
- [ ] Keep pure stochastic exAL gated.
- [ ] Keep exAL RHS/RHS_NS diagonal covariance gated.

## Stage 3: Unified Comparison Harness

Objective: run one authoritative source-median comparison across implemented
Normal DESN and Q-DESN modes.

Contract source:

```text
docs/implementation_notes/normal_qdesn_unified_comparison_contract_20260529.md
```

Preferred dataset:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000
```

Recommended economical source gate:

```text
tail rows: 1000
washout: 500
effective rows: 500
D: 1
n: 300
m: 1
chunk size: 64
subset size: 180
seed: 20260529 or later recorded seed
```

Include Normal rows:

- [ ] Normal scaled ridge;
- [ ] Normal scaled ridge exact chunked;
- [ ] Normal RHS/RHS_NS approximate VB;
- [ ] Normal warm-start serialization check;
- [ ] Normal warm-start to AL VB init;
- [ ] Normal warm-start to exAL VB init;
- [ ] Normal warm-start to AL MCMC init if economical;
- [ ] existing Normal-to-Q-DESN initializer comparison rows.

Include Q-DESN rows:

- [ ] AL ridge full;
- [ ] AL ridge exact chunked;
- [ ] AL ridge stochastic;
- [ ] AL ridge hybrid;
- [ ] AL ridge diagonal covariance;
- [ ] AL RHS/RHS_NS full;
- [ ] AL RHS/RHS_NS exact chunked;
- [ ] AL RHS/RHS_NS diagonal covariance;
- [ ] AL fixed subset;
- [ ] AL time-block stratified subset;
- [ ] AL response-quantile subset;
- [ ] AL design-leverage subset;
- [ ] AL rolling ridge if included as target-changing diagnostic;
- [ ] AL posterior-as-prior ridge if included as target-changing diagnostic;
- [ ] AL online ridge if included as workflow/state-handoff diagnostic;
- [ ] exAL ridge full;
- [ ] exAL ridge exact chunked;
- [ ] exAL ridge hybrid;
- [ ] exAL ridge diagonal covariance diagnostic;
- [ ] exAL RHS/RHS_NS full;
- [ ] exAL RHS/RHS_NS exact chunked;
- [ ] exAL RHS/RHS_NS hybrid.

Forbidden/probed rows:

- [ ] pure stochastic exAL;
- [ ] exAL RHS/RHS_NS diagonal covariance;
- [ ] RHS/RHS_NS posterior-as-prior;
- [ ] RHS/exAL subset targets;
- [ ] divide-and-combine VB;
- [ ] variational coresets.

## Stage 4: Unified Output Schema

Status: implemented in package commits `26284f1 Add Normal Q-DESN unified
comparison launcher`, `63001e4 Write unified comparison console log`, and
`b415b4d Harden unified comparison preflight metadata`.

Generated package output root:

```text
results/normal_qdesn_unified_source_median_20260529/
```

Required generated files:

- [x] `repo_state.csv`;
- [x] `component_runs.csv`;
- [x] `method_summary.csv`;
- [x] `prediction_metrics.csv`;
- [x] `exact_equivalence.csv`;
- [x] `approximate_diagnostics.csv`;
- [x] `target_changing_diagnostics.csv`;
- [x] `initializer_diagnostics.csv`;
- [x] `forbidden_modes.csv`;
- [x] `predictions_by_method.csv`;
- [x] `normal_qdesn_unified_comparison_summary.md`;
- [x] `console.log`;
- [ ] `time.log`, supplied by the external `/usr/bin/time -v` launch wrapper.

Launch script:

```text
scripts/run_normal_qdesn_unified_source_median_20260529.R
```

Smoke validation:

```text
test-normal-qdesn-unified-comparison.R: 8 pass, 0 fail
```

Tracked article summary:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

Do not commit large generated result files.

## Stage 5: Interpretation Rules

Checklist:

- [ ] Compare exact chunked rows only against their unchunked same-target
      references.
- [ ] Compare stochastic/hybrid/diagonal rows as approximate diagnostics, not
      exact failures.
- [ ] Compare subset, rolling, posterior-as-prior, and online rows as
      target-changing or workflow diagnostics.
- [ ] Compare Normal and Q-DESN predictive metrics carefully: the source is a
      Gaussian median source where `q_true = mu`, but Normal DESN remains a
      conditional-mean model and Q-DESN remains a quantile model.
- [ ] State which methods are recommended defaults and which are diagnostics.
- [ ] State that exAL ridge diagonal covariance is supported but not
      recommended as a predictive default based on current source diagnostics.

## Stage 6: Final Validation And Commits

Before final comparison:

- [x] package repo clean after launcher commits;
- [ ] article repo has only unrelated GloFAS untracked artifacts, or those are
      separately handled;
- [x] package focused tests pass for the launcher/Normal/Q-DESN smoke surface;
- [x] `git diff --check` passes in package and article repos.

After final comparison:

- [ ] compact article summary created;
- [ ] generated results remain ignored/local;
- [ ] package commit only if scripts/tests/code changed;
- [ ] article commit for documentation summary;
- [ ] final report lists commits, tests, methods, exact gates, approximate
      diagnostics, target-changing diagnostics, runtime, memory, and remaining
      gates.

## Deferred Work

Do not implement before the unified comparison:

- [ ] pure stochastic exAL;
- [ ] exAL RHS/RHS_NS diagonal covariance;
- [ ] low-rank covariance;
- [ ] Normal stochastic/hybrid batching;
- [ ] Normal rolling/online/posterior-as-prior;
- [ ] article-side stochastic/hybrid/rolling/online adapters;
- [ ] divide-and-combine VB;
- [ ] variational coresets.

## Current Next Single Task

Run the final Normal/Q-DESN unified comparison from a clean package HEAD and
write the tracked article comparison summary:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

The Normal warm-start metadata gap is closed. The next pass should use package
commit `b415b4d` or later and keep generated comparison outputs local/ignored.

Recommended launch command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
mkdir -p results/normal_qdesn_unified_source_median_20260529

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_20260529/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_20260529 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260529 \
  --D 1 \
  --n 50 \
  --m 1 \
  --washout 50 \
  --chunk-size 64 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --cores 4
```
