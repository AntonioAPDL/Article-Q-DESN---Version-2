# Q-DESN Full and Exact-Chunked VB Derivations

Date: 2026-05-28

Status: derivation and implementation contract. This note documents already
implemented full-data and exact-chunked package/Q-DESN AL and exAL modes under
ridge, RHS, and RHS_NS beta priors. It does not introduce a new algorithm.

## Scope

This note applies after DESN feature construction. The design matrix `X` is
fixed and the VB target is a static readout problem for scalar response `y`.

Implemented targets covered here:

- AL full-data CAVI/LDVB;
- AL exact chunked full-data CAVI/LDVB;
- exAL full-data LDVB;
- exAL exact chunked full-data LDVB;
- ridge, RHS, and RHS_NS beta priors.

Exact chunking is a memory/order-of-accumulation implementation of the same
full-data fixed point. It is not stochastic.

## Notation

Let `N` be the number of readout rows and `P` the number of readout features
including any intercept column. For row `i`:

- `x_i` is a `P` vector;
- `y_i` is the scalar response;
- `q(beta) = N(m_beta, V_beta)`;
- `qv_m[i] = E(v_i)`;
- `qv_m_inv[i] = E(1 / v_i)`;
- exAL additionally has `qs_m[i] = E(s_i)` and
  `qs_m2[i] = E(s_i^2)`.

The package stores likelihood expectations in `xis`. The names are code-owned,
but the important contract is:

- `xis` are refreshed after sigma/gamma LD updates;
- beta, local, sigma/gamma, and RHS updates all use the current `xis`;
- AL keeps gamma fixed through the existing sigma-only LD path.

## Likelihood Targets

### AL

AL is the asymmetric Laplace working likelihood at quantile `p0`. In the
current package engine, AL is represented through the same LD sigma block as
exAL with fixed gamma. The first exact and approximate AL modes must preserve
that path rather than replacing it with a separate inverse-gamma sigma update.

### exAL

exAL uses the quantile-fixed extended asymmetric Laplace representation. It has
the same beta and `v_i` structure as AL plus the `s_i` local skewing block and
the full sigma/gamma LD update.

## Prior Families

### Ridge

Ridge contributes a fixed diagonal beta precision:

```text
Lambda_beta = diag(1 / tau2)
```

This precision is global, not row-additive data.

### RHS and RHS_NS

RHS/RHS_NS contribute an expected beta precision vector computed from a global
shrinkage state:

```text
Lambda_beta = diag(E_prior(lambda_beta))
```

The state is updated from the full current `qbeta` moments, not from row
batches. Exact chunking may chunk data statistics, but RHS/RHS_NS updates remain
global.

The intercept shrinkage policy must remain explicit. Current Q-DESN policy is
to avoid shrinking the intercept unless a config deliberately opts in and passes
the existing guardrails.

## Full-Data Beta Update

For the current iteration, define row weights and linear terms:

```text
w_i = likelihood_weight_i(xis, qv_m_inv[i])
b_i = likelihood_linear_i(y_i, xis, qv_m_inv[i], qs_m[i])
```

The row-additive data natural statistics are:

```text
S_beta = sum_i w_i x_i x_i'
g_beta = sum_i x_i b_i
```

Given prior precision `Lambda_beta`, the update is:

```text
V_beta = solve(S_beta + Lambda_beta)
m_beta = V_beta g_beta
```

Only `S_beta` and `g_beta` are row-additive data terms. `Lambda_beta` is global.

## Exact Chunking

Let chunks `C_1, ..., C_K` partition rows `1:N`. For exact chunking:

```text
S_beta = sum_k sum_{i in C_k} w_i x_i x_i'
g_beta = sum_k sum_{i in C_k} x_i b_i
```

The final `S_beta`, `g_beta`, `m_beta`, and `V_beta` must match the unchunked
path up to floating-point ordering tolerance. Chunk order does not change the
target.

## Local Updates

### q(v)

`qv` rows are conditionally independent given current globals. Exact chunking
may update `qv` in row chunks, but every row must be refreshed once per full
iteration before downstream sigma/gamma and objective computations use the new
locals.

Required safeguards:

- positive shape/rate or equivalent GIG arguments;
- finite `qv_m`;
- finite positive `qv_m_inv`;
- fail or clamp through existing package safeguards when a numerical domain is
  violated.

### q(s)

`qs` is active for exAL and inactive/fixed by the AL reduction. Exact exAL
chunking may update `qs` in row chunks, but every row must be refreshed once per
full iteration.

Required safeguards:

- finite truncated-normal moments;
- positive second moments;
- no stochastic or stale `qs` behavior under exact mode.

## Sigma/Gamma LD Updates

The sigma/gamma block uses LD mode finding and `compute_xi_fast()` in the
package engine.

For exact chunking, only row-additive sigma/gamma sufficient statistics may be
accumulated in chunks. The final LD update must see the same full-data
statistics as the unchunked path.

AL-specific rule:

- gamma remains fixed at the AL value;
- only sigma is updated through the existing LD machinery;
- do not substitute another sigma posterior.

exAL-specific rule:

- sigma and gamma LD stats must include the current full refreshed `qv` and
  `qs` moments;
- exact chunking must preserve the engine update order.

## Existing Engine Order

The implemented package engine order is part of the contract:

1. update `qbeta` from current `qv`, `qs`, and `xis`;
2. update `qv`;
3. update `qs`;
4. accumulate sigma/gamma LD stats and update `qsiggam`;
5. refresh `xis`;
6. update RHS/RHS_NS globally from the new `qbeta`;
7. compute objective/traces.

Exact chunking may change how row sums are accumulated inside steps 1 through
4, but it must not reorder the global steps.

## Implementation Mapping

Package files:

- `R/exal_online_state.R`
  - `.exal_make_row_chunks()`
  - `.exal_beta_data_stats()`
  - `.exal_beta_data_stats_chunks()`
  - `.exal_beta_solve_from_data_stats()`
  - `.exal_beta_natural_stats()` compatibility wrapper
- `R/exal_ldvb_engine.R`
  - full engine loop and exact chunking branches
- `R/exal_inference_config.R`
  - `vb_control$chunking` normalization and validation
- `R/qdesn_vb.R`
  - Q-DESN routing into `exal_ldvb_fit()`
- `R/priors_beta.R`
  - ridge/RHS prior object construction
- `R/qdesn_rhs_ns_prior.R`
  - RHS_NS prior object construction

Article consumers:

- `application/R/latent_path_vb_al.R` has its own article-side AL fitter.
  This note describes package/Q-DESN static readout behavior, not article
  future latent-path batching.

## API and Controls

Existing exact control surface:

```r
vb_control$chunking <- list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 512,
  order = "sequential",
  trace = FALSE
)
```

Defaults when `chunking` is absent or disabled must remain the historical
unchunked path.

Only `mode = "exact"` is full-data equivalent. Non-exact modes require their
own derivation and tests.

## Tests

Existing required package tests:

- `tests/testthat/test-exal-exact-chunking-stats.R`
- `tests/testthat/test-exal-likelihood-family-al.R`
- `tests/testthat/test-exal-inference-config.R`
- `tests/testthat/test-qdesn-vb-likelihood-family.R`
- `tests/testthat/test-exal-batching-controls.R`
- `tests/testthat/test-qdesn-vb-batching-modes.R`
- `tests/testthat/test-static-beta-prior-rhs.R`
- `tests/testthat/test-qdesn-vb-simplification-ladder.R`

Required properties:

- unchunked defaults unchanged;
- `chunking$enabled = FALSE` equals no chunking;
- exact chunked AL matches AL unchunked;
- exact chunked exAL matches exAL unchunked;
- ridge/RHS/RHS_NS all covered;
- RHS state metadata is finite and globally updated;
- stochastic exAL still fails early.

## Economical Gates

Package gates:

- synthetic simplification ladder;
- TT500 source simplification ladder.

Article gate after package SHA repin:

- tiny D1N5 real-data latent-path unchunked versus exact chunked pair.

## Stop Conditions

Stop and do not promote if:

- exact chunking no longer matches unchunked within tolerance;
- RHS/RHS_NS state differs beyond floating-point effects under exact chunking;
- AL uses a different sigma update path without a new derivation;
- exAL stochastic/hybrid accidentally runs;
- article tiny D1N5 gate fails after a package SHA repin.
