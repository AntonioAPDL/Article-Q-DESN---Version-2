# Q-DESN VB Method Availability

Date: 2026-05-28

## Purpose

This note records which Q-DESN VB batching approaches are available for
comparison examples as of the current article and package worktrees. It is
based on the package code, article configs, tests, and implementation notes;
it is not a proposal for new algorithms.

Hybrid AL is now implemented for package static/readout and univariate Q-DESN
AL in exdqlm commit `685d2f5fcf789dd65495223f6b6f2dfa59a5cf22`. Variance-
reduced, streaming, stochastic/hybrid exAL, article stochastic/hybrid, and
multivariate batching methods remain gated.

## Repo State

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- baseline comparison-readiness parent: `f271463`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- stochastic AL implementation commit: `246554e`
- comparison harness commit: `37bdd3a`
- hybrid AL implementation commit: `685d2f5`
- source comparison harness with hybrid AL: `c51e9da`

## Availability Matrix

Status labels:

- `implemented`: available and tested for examples
- `implemented exact only`: unchunked and exact chunked are available, but no
  approximate batching is implemented
- `approximate implemented`: implemented but not full-data equivalent
- `gated`: not implemented; requires a separate mathematical/runtime contract
- `not applicable`: not meaningful for this method family

| Method family | Unchunked full-data VB | Exact chunked full-data VB | Stochastic mini-batch VB | Hybrid SVI with full refresh | Variance-reduced SVI | Streaming/posterior-as-prior VB |
| --- | --- | --- | --- | --- | --- | --- |
| package static AL LDVB | implemented | implemented | approximate implemented | approximate implemented | gated | gated |
| package static exAL LDVB | implemented | implemented | gated | gated | gated | gated |
| univariate Q-DESN AL | implemented | implemented | approximate implemented | approximate implemented | gated | gated |
| univariate Q-DESN exAL | implemented | implemented | gated | gated | gated | gated |
| article GloFAS latent-path AL-VB | implemented | implemented | gated | gated | gated | gated |
| future multivariate Q-DESN | gated | gated | gated | gated | gated | gated |

## Method Details

### Package Static AL LDVB

- status: unchunked and exact chunked are full-data VB; stochastic mini-batch
  and hybrid AL are approximate
- repo/commit: package `246554e` for implementation; `37bdd3a` adds the
  comparison harness
- API path: `exal_fit(..., method = "vb", likelihood_family = "al")` to
  `exal_ldvb_fit()` and `exal_ldvb_engine()`
- controls: `vb_control$chunking`; `mode = "exact"` for exact chunking,
  `mode = "stochastic"` or `mode = "hybrid"` for approximate AL
- tests: `test-exal-exact-chunking-stats.R`,
  `test-exal-likelihood-family-al.R`, `test-exal-stochastic-al-vb.R`,
  `test-exal-hybrid-al-vb.R`,
  `test-exal-batching-controls.R`, `test-static-beta-prior-rhs.R`
- package examples: safe
- article examples: not directly; article examples use the application adapter

### Package Static exAL LDVB

- status: unchunked and exact chunked are implemented; stochastic/hybrid exAL
  is gated
- repo/commit: exact chunking from package `5c868f8`/`73c043f`; harness at
  `37bdd3a`
- API path: `exal_fit(..., method = "vb", likelihood_family = "exal")`
- controls: `vb_control$chunking$mode = "exact"` only for batching
- tests: `test-exal-exact-chunking-stats.R`,
  `test-exal-inference-config.R`, `test-exal-stochastic-al-vb.R` verifies
  stochastic exAL fails early
- package examples: safe for unchunked and exact chunked
- article examples: not exposed in the GloFAS latent-path AL-VB application

### Univariate Q-DESN AL

- status: unchunked and exact chunked are full-data VB; stochastic mini-batch
  and hybrid AL are approximate
- repo/commit: package `246554e` for stochastic AL; package `685d2f5` for
  hybrid AL; comparison harness with hybrid AL at `c51e9da`
- API path: `qdesn_fit_vb()` builds fixed DESN features, then routes to
  `exal_ldvb_fit()`/`exal_ldvb_engine()`
- controls: `vb_args$chunking` or `vb_args$vb_control$chunking`; explicit
  `likelihood_family = "al"` and `al_fixed_gamma`; use `mode = "hybrid"` for
  periodic full-refresh AL
- tests: `test-qdesn-vb-likelihood-family.R`,
  `test-qdesn-vb-batching-modes.R`
- package examples: safe
- article examples: package-level examples only; the article latent-path
  adapter has a different application contract

### Univariate Q-DESN exAL

- status: unchunked and exact chunked are implemented; stochastic/hybrid exAL
  is gated
- repo/commit: package `73c043f`/`246554e`; comparison harness at `37bdd3a`
- API path: `qdesn_fit_vb(..., vb_args = list(likelihood_family = "exal"))`
- controls: exact chunking only through `vb_args$chunking`
- tests: `test-qdesn-vb-likelihood-family.R`,
  `test-qdesn-vb-batching-modes.R`
- package examples: safe for unchunked and exact chunked
- article examples: not applicable to current GloFAS latent-path AL-VB runs

### Article GloFAS Latent-Path AL-VB

- status: unchunked and exact chunked implemented for fixed historical rows;
  stochastic/hybrid article batching is gated
- repo/commit: article `1d885a7` for exact chunked support; current configs are
  repinned to package `c51e9da`
- API path: `application/R/latent_path_vb_al.R` through
  `application/R/fit_qdesn_latent_path.R`
- controls: `inference.vb_ld.chunking` with `mode = "exact"` only
- tests: `application/tests/test_vb_preparation.R`,
  `application/tests/test_latent_path_design.R`,
  `application/tests/test_latent_path_recovery.R`,
  `application/tests/run_tests.R`
- package examples: not applicable
- article examples: safe for unchunked vs exact chunked using the tiny D1N5
  gate only

### Future Multivariate Q-DESN

- status: gated for every batching mode
- reason: no multivariate readout batching contract or implementation is
  present in the package/application path audited here
- next required contract: multivariate likelihood, local-variable, RHS/global
  shrinkage, prediction, and validation interface contract before any code

## Gated Methods

- variance-reduced SVI: deferred until stochastic and hybrid AL are stable
- streaming/posterior-as-prior VB: requires a posterior-state handoff contract
- stochastic or hybrid exAL: gated because q(s) and sigma/gamma LD updates are
  more delicate than AL
- article GloFAS stochastic/hybrid batching: gated until package AL
  approximate methods are stable and an article future-path/no-leakage contract
  is written
- multivariate Q-DESN batching: design-only for now
