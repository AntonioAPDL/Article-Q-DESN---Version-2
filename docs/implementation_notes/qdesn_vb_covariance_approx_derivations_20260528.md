# Q-DESN Covariance Approximation Derivations

Date: 2026-05-28

Status: implementation complete for package static/readout and univariate
Q-DESN AL diagonal beta covariance with ridge and RHS/RHS_NS priors, and for
exAL ridge diagonal beta covariance. Low-rank covariance, exAL RHS/RHS_NS
diagonal covariance, stochastic/hybrid covariance combinations, and article
adapters remain gated.

2026-05-29 update: exAL diagonal covariance was first stopped after an
equivalence mismatch, then reopened narrowly for ridge after a practical source
gate. exAL ridge diagonal covariance is now finite and exact-chunked equivalent
under the implemented `1e-6` absolute and relative gates, but it performed
poorly on the D=1, n=300 source median comparison. exAL RHS/RHS_NS diagonal
covariance remains gated.

## Purpose

Full-covariance beta updates can become expensive for large readout dimension
`P`. Covariance approximations may reduce cost, but they change posterior
uncertainty and can affect local-variable updates through `x_i' V_beta x_i`.
They must therefore be explicit approximate modes.

## Scope

Implemented stages:

- package static/readout AL;
- univariate Q-DESN AL routing;
- ridge, RHS, and RHS_NS priors;
- package static/readout and univariate Q-DESN exAL ridge routing;
- diagonal beta covariance only;
- full-data and exact chunked data stats.

Deferred:

- exAL RHS/RHS_NS until shrinkage-state feedback is derived and tested;
- stochastic/hybrid diagonal covariance until its mixed-approximation contract
  is derived;
- low-rank plus diagonal until diagonal mode passes;
- article GloFAS adapters.

## Full Covariance Reference

Reference update:

```text
V_beta = solve(S_beta + Lambda_beta)
m_beta = V_beta g_beta
```

Local updates use:

```text
q_i = x_i' V_beta x_i
```

## Diagonal Approximation

Approximate covariance:

```text
diag_V_j = 1 / (diag(S_beta)_j + Lambda_beta_j)
m_beta_j = diag_V_j * g_beta_j
```

Local quadratic term:

```text
q_i_diag = sum_j x_ij^2 diag_V_j
```

This ignores posterior beta correlations. It is approximate even when all row
data are used.

## Low-Rank Plus Diagonal Sketch

A later low-rank mode could use:

```text
V_beta approx D + U C U'
```

with `D` diagonal and `U` a low-rank basis from a stable decomposition of the
data precision. This is not the first implementation. It needs its own
positive-definite and prediction-variance contract.

## Row-Additive Terms

`S_beta` and `g_beta` remain row-additive. Exact chunking can still accumulate
data stats exactly before applying the diagonal approximation.

The approximation happens in the beta solve, not in row accumulation.

## Prior and RHS Handling

Ridge is straightforward because `Lambda_beta` is fixed diagonal.

RHS/RHS_NS are now enabled for AL because their global shrinkage updates consume
posterior beta second moments only through the diagonal of `V_beta`:

```text
E(beta_j^2) = m_beta_j^2 + diag_V_j
```

The RHS/RHS_NS states remain global. They are not row-batched, and exact
chunking still only accumulates row-additive data statistics before the same
global beta and shrinkage updates. This stage does not support nonzero Gaussian
beta-prior natural vectors or full prior-precision corrections under diagonal
covariance.

## AL and exAL Differences

AL first:

- no `qs` block;
- gamma fixed;
- easier interpretation of local `qv` sensitivity to `q_i_diag`.

exAL:

- `qs` and sigma/gamma LD stats also depend on local quadratic terms;
- approximation error can feed back into gamma;
- ridge is implemented with finite-state and exact-chunking gates;
- RHS/RHS_NS remain gated because the shrinkage state and exAL LD feedback need
  a separate second-moment contract.

## API Proposal

Do not use `chunking` for this approximation. Add a separate beta covariance
control:

```r
vb_control$beta_covariance <- list(
  approximation = "full",      # "full" or "diagonal"
  label_uncertainty = TRUE
)
```

Default remains `"full"`. The implemented package control is:

```r
vb_args$beta_covariance <- list(
  approximation = "diagonal",
  label_uncertainty = TRUE
)
```

Any result using `"diagonal"` must mark posterior covariance and prediction
variance as approximate.

## Implementation Mapping

Likely package files:

- `R/exal_inference_config.R`
  - normalizes covariance controls;
- `R/exal_online_state.R`
  - adds the diagonal solve helper;
- `R/exal_ldvb_engine.R`
  - routes the beta solve and labels approximate covariance;
- `R/qdesn_vb.R`
  - passes controls and labels result metadata.

Potential helper signatures:

Implemented helper:

```r
.exal_beta_solve_diagonal_from_data_stats(stats, prec_diag)
```

## Tests

Implemented package tests:

- default full covariance unchanged;
- diagonal covariance finite and positive;
- diagonal solve follows the documented diagonal formula;
- exact chunked diagonal equals unchunked diagonal for ridge and RHS-family
  priors;
- exact chunked diagonal equals unchunked diagonal for exAL ridge under
  practical absolute and relative gates;
- covariance mode is labeled approximate in `qbeta` and `misc`;
- RHS/RHS_NS expected precision remains finite and global;
- Q-DESN routes diagonal covariance for AL + RHS_NS;
- exAL RHS/RHS_NS and stochastic/hybrid diagonal covariance still fail early.

The exAL RHS/RHS_NS fail-early rule is deliberate. It should not be relaxed
until the exAL-specific diagonal covariance contract defines qv/qs,
sigma/gamma, xi, RHS-family shrinkage, and exact chunking feedback semantics.

Test file:

```text
tests/testthat/test-exal-beta-covariance-approx.R
```

## Economical Gates

Package:

- tiny orthogonal design where diagonal equals full;
- low-correlation synthetic Q-DESN design;
- TT500 source AL ridge diagnostic gate.

Article:

- no article config exposure initially;
- document package readiness only.

## Stop Conditions

Stop if:

- full covariance default changes;
- diagonal variances become non-positive or non-finite;
- prediction outputs fail to label approximate uncertainty;
- exAL RHS/RHS_NS diagonal mode accidentally runs before its feedback contract
  is written.
- stochastic/hybrid diagonal covariance runs before its contract is written.
