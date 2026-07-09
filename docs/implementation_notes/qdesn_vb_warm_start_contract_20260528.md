# Q-DESN VB Warm-Start Contract

Date: 2026-05-28

Status: first package stage implemented in package commit
`438aea863749fc23acb4de809da56cfc24b4b12c`. This note remains the contract for
future warm-start extensions.

## Purpose

Warm starts should allow a Q-DESN VB fit to initialize from a previous fitted
state without changing the target posterior. The first implementation should be
package/Q-DESN only and should cover full-data and exact-chunked AL/exAL under
ridge, RHS, and RHS_NS priors. Stochastic, hybrid, rolling-window, and article
GloFAS warm starts are downstream consumers, not the first implementation.

## Scope

Implemented first:

- package static/readout AL full-data;
- package static/readout AL exact chunked;
- package static/readout exAL full-data;
- package static/readout exAL exact chunked;
- univariate Q-DESN routing for the same modes;
- ridge, RHS, and RHS_NS beta priors.

Still not implemented:

- stochastic warm starts;
- hybrid warm starts;
- rolling/posterior-as-prior handoff;
- article latent-path warm starts;
- multivariate Q-DESN warm starts.

## Target

A warm start changes initialization only. For a fixed dataset, design, prior,
likelihood, controls, and convergence criteria, a converged warm-started fit
should target the same full-data VB fixed point as a cold fit.

Exact chunking with a warm start remains full-data equivalent.

## Warm-Start Object

The first warm-start object should be a plain R list with a version tag:

```r
list(
  type = "qdesn_vb_warm_start",
  version = "0.1",
  qbeta = list(mean = ..., cov = ...),
  qv = list(mean = ..., mean_inv = ...),
  qs = list(mean = ..., mean2 = ...),        # required for exAL, absent/null for AL
  qsiggam = ...,
  xis = ...,
  rhs = ...,                                # null for ridge
  likelihood = list(family = ..., p0 = ..., al_fixed_gamma = ...),
  prior = list(family = ..., shrink_intercept = ..., metadata = ...),
  design = list(n_rows = ..., n_features = ..., design_hash = ...),
  qdesn = list(feature_settings_hash = ..., reservoir_metadata = ...),
  package = list(sha = ..., version = ...),
  control = list(source = "vb", mode = "full_or_exact")
)
```

Required fields:

- `qbeta$mean`: numeric vector of length `P`;
- `qbeta$cov`: `P x P` positive-definite covariance matrix;
- `qv$mean`, `qv$mean_inv`: numeric length `N`, finite and positive;
- `qs$mean`, `qs$mean2`: numeric length `N` for exAL;
- `qsiggam`: engine-compatible sigma/gamma state;
- `xis`: likelihood expectation list/vector as expected by the engine;
- `rhs`: prior-state object for RHS/RHS_NS, otherwise `NULL`;
- likelihood and prior metadata;
- row count, feature count, and design hash;
- package SHA and warm-start object version.

## Validation Rules

The engine must fail early if any of the following mismatch:

- likelihood family;
- `p0`;
- AL fixed-gamma policy;
- prior family;
- beta dimension;
- row count for local variables;
- design hash when provided;
- feature settings hash when provided;
- missing `qs` for exAL;
- non-null incompatible `qs` for AL, unless ignored with a clear message;
- invalid or non-finite state components.

The first implementation should require same-row warm starts. Rolling-window
or posterior-as-prior handoff is a separate mode because the target changes.

## RHS/RHS_NS Handling

RHS/RHS_NS warm starts must include the global prior state and must validate:

- `shrink_intercept` policy;
- expected precision length;
- finite hyperparameters;
- positive variance/scale parameters;
- prior family name and version.

RHS/RHS_NS states remain global. Warm-start validation must not row-batch or
subsample shrinkage states.

## AL and exAL Differences

AL:

- `qs` should be absent or explicitly inactive;
- gamma must remain fixed through the existing AL LD path;
- `qsiggam` must be compatible with sigma-only updates.

exAL:

- `qs` and `qs^2` moments are required;
- sigma/gamma state must include gamma metadata;
- exact chunked warm starts must refresh all rows before any claim of
  equivalence.

## Implemented API

Package commit `438aea8` adds:

- exported helper `qdesn_vb_make_warm_start()`;
- `vb_args$warm_start` routing in `qdesn_fit_vb()`;
- design hash, likelihood, prior, p0, finite-state, and RHS/RHS_NS expected
  precision validation;
- `init$beta_state` support in `exal_ldvb_engine()`;
- fail-early behavior for stochastic warm starts.

Optional controls without changing defaults:

```r
vb_args = list(
  warm_start = list(
    enabled = TRUE,
    state = warm_state,
    strict = TRUE,
    validate_design_hash = TRUE,
    validate_package_sha = FALSE
  )
)
```

Alternative package-level control:

```r
vb_control$warm_start <- list(
  enabled = TRUE,
  state = warm_state,
  strict = TRUE
)
```

Implemented first-stage behavior:

- accept warm start through `qdesn_fit_vb()` as `vb_args$warm_start`;
- pass normalized initialization into `exal_ldvb_fit(init = ...)`;
- keep `exal_ldvb_fit(init = list(...))` backward compatible.

## Implementation Mapping

Package files:

- `R/qdesn_vb.R`
  - parse Q-DESN warm-start controls;
  - compute/validate design and feature hashes;
  - attach warm-start metadata to results.
- `R/exal_ldvb_fit.R`
  - remains backward compatible with explicit `init = list(...)`.
- `R/exal_ldvb_engine.R`
  - initialize `qbeta`, `qv`, `qs`, `qsiggam`, `xis`, and prior state.
- `R/exal_inference_config.R`
  - remains the VB control normalizer; warm start is routed through Q-DESN
    `vb_args` in the first stage.
- `R/qdesn_vb_warm_start.R`
  - `qdesn_vb_make_warm_start()`;
  - internal validation and hash helpers.

## Tests

Package test file:

- `tests/testthat/test-qdesn-vb-warm-start.R`

Implemented tests:

- default cold-start behavior unchanged;
- warm API routes to the same engine init as explicit `init`;
- warm-started exact-chunked AL matches warm-started unchunked AL;
- exAL and RHS_NS finite-state coverage;
- ridge coverage;
- serialization round trip with `saveRDS()`/`readRDS()`;
- mismatch failures for likelihood, prior, beta dimension, row count, and
  design hash;
- invalid finite-state failures;
- stochastic warm-start controls fail early until implemented.

Focused package regression after implementation:

- existing exact chunking, likelihood-family, batching-control, stochastic AL,
  Q-DESN batching, RHS, and simplification-ladder tests passed;
- `test-qdesn-vb-warm-start.R` passed 38 assertions after adding serialization
  coverage.

## Economical Gates

Package:

- synthetic simplification-ladder data, using a cold short run to build a warm
  object and a second run to verify same target;
- TT500 source gate for AL ridge and one RHS-family prior.

Article:

- no article warm-start adapter in the first implementation;
- rerun article tests if package SHA is repinned;
- rerun tiny D1N5 exact gate only if article configs are touched.

Article repin gate after package commit `438aea8`:

- active article configs were repinned to
  `438aea863749fc23acb4de809da56cfc24b4b12c`;
- tiny D1N5 unchunked versus exact-chunked gate passed;
- max gate difference: `1.72e-12` against tolerance `1e-7`;
- same engine SHA: `TRUE`;
- same design hash: `TRUE`;
- no-leakage audits checked: `3` per fit;
- unchunked wall time/RSS: `19.53` sec / `139956` KB;
- exact-chunked wall time/RSS: `19.84` sec / `140124` KB.

Ignored local outputs:

`application/logs/exact_chunked_vb_tiny_d1n5_pkg438aea8_20260528/`

## Stop Conditions

Stop before implementation or rollback if:

- warm start changes default cold-start behavior;
- design mismatch can pass silently;
- RHS/RHS_NS state semantics become ambiguous;
- exAL can initialize without valid `qs`;
- exact chunked warm-start equivalence fails;
- implementation requires broad refactoring outside Q-DESN/exAL VB paths.
