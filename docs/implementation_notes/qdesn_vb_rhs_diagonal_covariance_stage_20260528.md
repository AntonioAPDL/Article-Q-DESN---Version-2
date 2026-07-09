# Q-DESN VB RHS Diagonal Covariance Stage

Date: 2026-05-28

## Purpose

This note documents the second beta covariance approximation stage. It extends
the existing diagonal beta covariance approximation from AL + ridge to AL +
RHS/RHS_NS priors. The mode is approximate because the beta posterior covariance
is constrained to be diagonal. It preserves the full-data row target when no
subset mode is used, but it does not preserve full-covariance VB uncertainty.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `28251d8 Add RHS diagonal covariance VB support`

## Implemented Scope

Implemented:

- package static/readout AL;
- univariate Q-DESN AL routing through `qdesn_fit_vb()`;
- ridge, RHS, and RHS_NS beta priors;
- full-data unchunked VB;
- exact chunked VB;
- diagonal beta covariance approximation.

Still gated:

- exAL diagonal covariance;
- stochastic/hybrid diagonal covariance;
- subset plus diagonal covariance beyond the already supported independent
  AL-ridge subset modes;
- RHS/RHS_NS diagonal covariance for article GloFAS adapters;
- low-rank covariance.

## Contract

For ridge and RHS-family priors, the beta update can be written with a global
expected prior precision diagonal:

```text
P_diag_j = diag(S_beta)_j + E_q[Lambda_beta_j]
diag_V_j = 1 / P_diag_j
m_beta_j = diag_V_j * g_beta_j
```

RHS/RHS_NS updates remain global. They are not row-batched. Their shrinkage
updates consume beta second moments:

```text
E(beta_j^2) = m_beta_j^2 + diag_V_j
```

This is coherent for a diagonal beta covariance approximation because the RHS
family code already depends only on `diag(V_beta)` for beta second moments.
The approximation is entirely in the beta covariance solve, not in row
accumulation or RHS state updates.

Full prior-precision corrections and nonzero Gaussian natural-vector priors are
still forbidden for diagonal covariance. Those require a separate diagonal
natural-parameter contract and were not implemented in this stage.

## API

Package controls:

```r
vb_args <- list(
  likelihood_family = "al",
  al_fixed_gamma = 0,
  beta_prior_type = "rhs_ns",
  beta_rhs = list(
    tau0 = 0.8,
    s2 = 1.25,
    zeta2_fixed = 1.25,
    shrink_intercept = FALSE,
    n_inner = 1L
  ),
  beta_covariance = list(
    approximation = "diagonal",
    label_uncertainty = TRUE
  )
)
```

Default behavior is unchanged: absent `beta_covariance` still uses full beta
covariance. Exact chunking remains full-data row-additive chunking before the
same diagonal beta solve.

## Tests

Baseline before implementation:

- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-stochastic-al-vb.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- `test-exal-subset-fit.R`: 67 pass;
- `test-exal-beta-covariance-approx.R`: 36 pass;
- total: 520 pass, 0 fail.

Focused regression after implementation:

- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-stochastic-al-vb.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- `test-exal-subset-fit.R`: 67 pass;
- `test-exal-beta-covariance-approx.R`: 75 pass;
- total: 559 pass, 0 fail.

Covered checks:

- defaults and explicit full covariance remain unchanged;
- diagonal AL ridge remains finite and labeled approximate;
- diagonal AL RHS and RHS_NS fits are finite and reproducible;
- RHS/RHS_NS expected precision stays finite and global;
- Q-DESN routes diagonal covariance with RHS_NS;
- exact chunked diagonal RHS/RHS_NS matches unchunked diagonal RHS/RHS_NS;
- exAL diagonal covariance remains forbidden;
- stochastic/hybrid diagonal covariance remains forbidden;
- unsupported full prior-precision/natural-vector priors remain forbidden.

## Exact Equivalence

Exact chunking still accumulates the same full-data row sufficient statistics
before the diagonal beta solve. The focused tests verify equality between
unchunked and exact chunked diagonal RHS/RHS_NS fits for:

- beta posterior means;
- beta posterior covariance matrices;
- ELBO traces;
- RHS tau traces;
- RHS slab/global traces where available.

The tolerance used by the test is `1e-8`.

## Remaining Risks

- Diagonal covariance can understate uncertainty when beta posterior
  correlations matter.
- RHS/RHS_NS shrinkage now sees diagonal covariance second moments by design;
  that is coherent, but it is still an approximate covariance regime.
- exAL remains deferred because `q(s)`, sigma/gamma LD stats, and xi feedback
  need a separate diagonal-covariance contract.
- Stochastic/hybrid diagonal covariance remains deferred because it would mix
  two approximation layers.

## Recommended Next Stage

The next single safe stage should be richer subset stratification for AL ridge
or a canonical Q-DESN online wrapper contract. Low-rank covariance should wait
until diagonal covariance is exercised on the intended comparison examples.
