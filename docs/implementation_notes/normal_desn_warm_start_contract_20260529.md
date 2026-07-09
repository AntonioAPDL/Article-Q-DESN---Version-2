# Normal DESN Warm-Start Metadata Contract

Date: 2026-05-29

## Purpose

This note defines the implementation contract for a Normal DESN warm-start
metadata object. It is a planning artifact for the next safe package stage
after the active Q-DESN comparison/hybrid work finishes and the package
worktree is clean.

The goal is not to create a new statistical target. The goal is to make Normal
DESN fitted states portable, validated, reproducible, and safe to use as
initialization sources for Q-DESN AL/exAL VB and MCMC workflows.

## Current State

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
current planning checkpoint: 6d976b2 Clarify Q-DESN VB gate package checkpoints
```

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
latest Normal DESN warm-start checkpoint: 9f1c32d Cover RHS Normal warm-start labels
```

Implementation status: this contract is implemented in the package through
`52ea0b0 Add Normal DESN warm-start states` and the direct RHS-family label
test coverage in `9f1c32d Cover RHS Normal warm-start labels`.

## Implemented Normal DESN Surface

The package already exposes:

```text
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

Implemented Normal readout modes:

```text
scaled_ridge exact Normal-inverse-gamma
scaled_ridge exact chunked Normal-inverse-gamma
RHS/RHS_NS approximate global VB
```

The formal object analogous to `qdesn_vb_warm_start()` now exists and stores
the Normal DESN posterior state together with compatibility metadata.

## Relationship To Existing Q-DESN Warm Starts

Q-DESN already has:

```text
qdesn_vb_make_warm_start()
qdesn_vb_warm_start
vb_args$warm_start
```

That object is an initialization and reproducibility mechanism for Q-DESN VB
states. The Normal DESN object should follow the same spirit:

- it should be serializable;
- it should carry enough metadata to reject incompatible use;
- it should be convertible into existing Normal-to-Q-DESN initializer lists;
- it should not silently change the posterior target.

The Normal object should not reuse the class name `qdesn_vb_warm_start`, because
the source likelihood and posterior state are different.

## Proposed API

Package exports:

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

The conversion helpers may internally call the existing
`qdesn_normal_to_vb_init()` and `qdesn_normal_to_mcmc_init()` logic, but they
should first validate the warm-start object.

## Object Class

Class:

```text
c("qdesn_normal_warm_start", "list")
```

Required top-level fields:

```text
type
version
target
readout
beta
omega2
prior
design
qdesn
package
control
created_at
```

Required identity fields:

```text
type = "qdesn_normal_warm_start"
version = "0.1"
target$family = "normal"
target$label
target$exact_status
target$preserves_full_data_target
```

The target label should mirror the fitted Normal DESN readout:

```text
normal_scaled_ridge_exact
normal_scaled_ridge_exact_chunked
normal_rhs_vb_approx
normal_rhs_ns_vb_approx
```

## Posterior State

Required beta fields:

```text
beta$mean
beta$cov
beta$dim
```

Required omega fields:

```text
omega2$shape
omega2$rate
omega2$mean
omega2$mode
```

For RHS/RHS_NS approximate Normal DESN fits, include the shrinkage state if it
is available:

```text
prior$family
prior$rhs_state
prior$shrink_intercept
prior$hypers
```

The warm-start object does not need to make RHS/RHS_NS exact. It only needs to
record the source state honestly and keep the target label approximate.

## Design Metadata

Required design fields:

```text
design$n_rows
design$n_features
design$design_hash
design$colnames
```

The design hash should use the same hashing convention used by the Q-DESN
warm-start helpers:

```text
digest(list(dim = dim(X), colnames = colnames(X), X = unclass(X)), algo = "sha256")
```

If `object` is a full `qdesn_normal_fit`, `X` can default to `object$X`. If the
input is only a `normal_desn_readout`, `X` must be supplied unless the readout
already stores the design matrix.

## Feature Metadata

Required Q-DESN metadata fields when available:

```text
qdesn$feature_settings_hash
qdesn$reservoir_metadata
qdesn$input_mode
qdesn$add_bias
qdesn$D
qdesn$n
qdesn$n_tilde
qdesn$m
qdesn$m_input
```

The feature settings hash should follow the same field subset as
`.qdesn_vb_feature_settings_hash()` to keep Normal and Q-DESN validation
aligned.

## Package Metadata

Required package fields:

```text
package$sha
package$version
```

`validate_package_sha = FALSE` should remain the default because reproducible
experiments often intentionally replay a state after small documentation or
test commits. Strict SHA validation should be available for final locked
comparison runs.

## Validation Rules

The validator must reject:

- missing or wrong `type`;
- unsupported object `version`;
- non-finite beta mean;
- non-square beta covariance;
- beta covariance with incompatible dimension;
- non-symmetric or non-positive-definite beta covariance;
- non-positive omega2 mean/mode;
- mismatched design hash when `validate_design_hash = TRUE`;
- mismatched feature settings hash when requested and metadata is available;
- mismatched package SHA when `validate_package_sha = TRUE`;
- missing required target/prior labels in strict mode.

The validator should allow:

- missing package SHA when strict SHA validation is disabled;
- unavailable feature settings hash for a raw `normal_desn_readout`, if strict
  feature validation is disabled;
- approximate RHS/RHS_NS source states, as long as the target label is not
  presented as exact.

## Conversion To VB Initialization

`qdesn_normal_warm_start_to_vb_init()` should return a list compatible with
`vb_args$init` for `qdesn_fit_vb()`:

```text
beta_m
beta_V
qbeta$m
qbeta$V
beta_mean
beta_cov
sigma
source
```

The source block should include:

```text
type = "qdesn_normal_vb_init"
source_type = "qdesn_normal_warm_start"
normal_target
normal_exact_status
likelihood_family
beta_prior_type
p0
design_hash
feature_settings_hash
package_sha
```

The `sigma` initialization should use `sqrt(omega2$mean)` when available, with
a finite positive fallback to `sqrt(omega2$mode)`.

## Conversion To MCMC Initialization

`qdesn_normal_warm_start_to_mcmc_init()` should return a list compatible with
`mcmc_args$init` for `qdesn_fit_mcmc()`:

```text
beta
sigma
gamma
source
```

For AL, `gamma` should use `al_fixed_gamma`, usually zero. For exAL, `gamma`
should use the supplied initialization value.

## Testing Requirements

Package tests should be added in a focused file, for example:

```text
tests/testthat/test-qdesn-normal-warm-start.R
```

Required tests:

- scaled-ridge Normal fit creates a `qdesn_normal_warm_start`;
- exact chunked scaled-ridge Normal fit creates a warm start with the chunked
  target label;
- RHS/RHS_NS Normal fit creates a warm start labeled approximate;
- serialization round trip through `saveRDS()` and `readRDS()`;
- design hash mismatch fails;
- feature settings hash mismatch fails when strict validation is enabled;
- package SHA mismatch fails only when `validate_package_sha = TRUE`;
- beta covariance non-positive-definite state fails;
- omega2 invalid state fails;
- conversion to VB init matches existing `qdesn_normal_to_vb_init()` fields;
- conversion to MCMC init matches existing `qdesn_normal_to_mcmc_init()` fields;
- conversion preserves source metadata;
- defaults do not affect existing Normal or Q-DESN fits.

Suggested focused test command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-warm-start.R")'
```

Regression tests after implementation:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-normal-init-comparison.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-warm-start.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
```

## Documentation Requirements

Update:

```text
man/qdesn_normal.Rd
docs/implementation_notes/normal_desn_qdesn_method_availability_20260529.md
docs/implementation_notes/normal_desn_end_to_end_roadmap_20260529.md
```

If the implementation changes any user-facing examples, update the source and
initialization comparison notes after rerunning the relevant scripts from a
clean package HEAD.

## Stop Gates

Stop before implementation if:

- the package repo is dirty from the parallel Q-DESN work;
- `R/qdesn_normal.R` has unexpected local changes;
- the existing Normal initializer tests fail before changes;
- the warm-start object would need to modify Q-DESN engine internals;
- the implementation would require touching `R/exal_ldvb_engine.R`,
  `R/exal_inference_config.R`, or `R/exal_online_state.R`;
- design hash validation cannot be made consistent with Q-DESN warm starts.

## First Safe Coding Stage

After the package repo is clean:

1. Implement `qdesn_normal_make_warm_start()` and validation helpers in
   `R/qdesn_normal.R` or a small dedicated `R/qdesn_normal_warm_start.R`.
2. Export the helpers in `NAMESPACE`.
3. Add focused tests.
4. Run Normal and warm-start regression tests.
5. Commit package changes:

```text
Add Normal DESN warm-start metadata
```

6. Update article docs and commit:

```text
Document Normal DESN warm-start metadata
```
