# Q-DESN VB Diagonal Covariance Stage

Date: 2026-05-28

## Purpose

This note documents the first beta covariance approximation stage. The mode is
an explicit approximate VB mode, not exact chunking and not a new DESN feature
construction method. It changes the beta posterior covariance approximation and
therefore labels uncertainty as approximate.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `03aab6c Add diagonal beta covariance approximation`

## Implemented Scope

Implemented:

- package static/readout AL;
- univariate Q-DESN AL routing through `qdesn_fit_vb()`;
- ridge beta prior only;
- full-data unchunked VB;
- exact chunked VB;
- diagonal beta covariance approximation.

Implemented in later stage:

- RHS/RHS_NS diagonal covariance is implemented in package commit `28251d8`
  and documented in
  `qdesn_vb_rhs_diagonal_covariance_stage_20260528.md`.

Still gated:

- exAL diagonal covariance;
- stochastic/hybrid diagonal covariance;
- low-rank covariance;
- article GloFAS adapters.

## Contract

Full covariance reference:

```text
V_beta = solve(S_beta + Lambda_beta)
m_beta = V_beta g_beta
```

Diagonal approximation:

```text
diag_V_j = 1 / (diag(S_beta)_j + Lambda_beta_j)
m_beta_j = diag_V_j g_beta_j
```

The row-additive sufficient statistics `S_beta` and `g_beta` are still computed
from all rows. Exact chunking remains exact for those sufficient statistics and
therefore matches unchunked diagonal covariance for the same target. The
approximation happens only in the beta solve.

## API

Package controls:

```r
vb_args <- list(
  likelihood_family = "al",
  al_fixed_gamma = 0,
  beta_prior_type = "ridge",
  beta_covariance = list(
    approximation = "diagonal",
    label_uncertainty = TRUE
  )
)
```

Default behavior is unchanged: when `beta_covariance` is absent, the engine uses
full beta covariance.

The result records:

- `fit$qbeta$covariance_approximation = "diagonal"`;
- `fit$qbeta$approximate_covariance = TRUE`;
- `fit$misc$beta_covariance$approximation = "diagonal"`;
- `fit$misc$approximate_covariance = TRUE`;
- a `fit$misc$covariance_objective_note` warning that uncertainty is
  approximate.

## Tests

Package test file:

```text
tests/testthat/test-exal-beta-covariance-approx.R
```

Focused regression set after implementation:

- `test-exal-beta-covariance-approx.R`: 36 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-stochastic-al-vb.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- total: 453 pass, 0 fail.

Covered checks:

- default full covariance unchanged when the control is absent;
- explicit `approximation = "full"` matches absent default;
- diagonal solve follows the documented diagonal formula;
- diagonal AL ridge fit is finite and positive;
- diagonal exact chunking matches diagonal unchunked;
- Q-DESN AL routes the control;
- exAL, RHS/RHS_NS, and stochastic/hybrid diagonal covariance failed early in
  this ridge-only first stage. RHS/RHS_NS are enabled by the later stage note.

## Remaining Risks

- This mode is approximate even when all data rows are used.
- It can understate or distort uncertainty when beta posterior correlations are
  important.
- RHS/RHS_NS shrinkage updates consume beta second moments and are now enabled
  for AL under the separate RHS diagonal covariance stage note.
- exAL gamma/sigma and `q(s)` feedback need separate tests before enabling.

## Recommended Next Stage

This note describes the first ridge-only diagonal covariance stage. See
`qdesn_vb_rhs_diagonal_covariance_stage_20260528.md` for the RHS/RHS_NS
extension. Do not combine future low-rank, online, and exAL approximate work in
one pass.
