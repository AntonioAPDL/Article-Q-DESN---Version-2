# Q-DESN VB Hybrid exAL Ridge Stage

Date: 2026-05-28
Package commit: `9c25db3 Add hybrid exAL ridge VB`

## Scope

This stage implements the first approximate exAL batching mode:

```text
likelihood_family = "exal"
beta_prior_type = "ridge"
chunking$mode = "hybrid"
```

It is available for the package static/readout engine and through univariate
`qdesn_fit_vb()`. It is not exposed in article GloFAS configs.

## Contract

Hybrid exAL ridge approximates the existing full-data exAL LDVB target between
periodic full refreshes. It preserves the full-data data target but not exact
CAVI equivalence unless every iteration is a full refresh.

Required behavior:

- `full_every = 1` recovers exact exAL ridge within practical tolerance;
- non-refresh iterations update beta with damped mini-batch natural statistics;
- non-refresh iterations refresh only current-batch `qv` and `qs`;
- rows outside the current batch retain stale local moments;
- sigma/gamma LD and `xis` are refreshed on the configured full/sigma refresh
  cadence;
- stochastic exAL remains forbidden;
- RHS/RHS_NS hybrid exAL remains forbidden.

## Package Changes

Changed files:

- `R/exal_ldvb_engine.R`
- `tests/testthat/test-exal-hybrid-al-vb.R`
- `tests/testthat/test-exal-hybrid-exal-vb.R`
- `tests/testthat/test-qdesn-vb-batching-modes.R`
- `scripts/run_qdesn_vb_implemented_modes_source_median_20260528.R`

The engine gate now permits approximate chunking for exAL only when
`mode = "hybrid"` and the beta prior is ridge. `mode = "stochastic"` still
fails early for exAL.

## Validation

Baseline focused tests before changes passed with 675 assertions.

Post-change focused tests passed with 590 assertions:

- `test-exal-exact-chunking-stats.R`: 38 pass
- `test-exal-inference-config.R`: 203 pass
- `test-qdesn-vb-batching-modes.R`: 33 pass
- `test-exal-beta-covariance-approx.R`: 75 pass
- `test-exal-subset-fit.R`: 67 pass
- `test-static-beta-prior-rhs.R`: 110 pass
- `test-exal-hybrid-al-vb.R`: 33 pass
- `test-exal-hybrid-exal-vb.R`: 31 pass

Focused hybrid exAL checks:

- static/readout `full_every = 1` recovers exact exAL ridge with max absolute
  checks at `1e-6` for beta/local/sigma/objective quantities and `2e-6` for the
  gamma trace;
- static/readout `full_every > 1` is finite and reproducible under fixed seed;
- gamma traces remain inside configured bounds;
- stochastic exAL fails early;
- RHS/RHS_NS hybrid exAL fails early;
- Q-DESN exAL hybrid routes through `qdesn_fit_vb()`;
- Q-DESN full-refresh hybrid exAL recovers exact Q-DESN exAL beta state within
  `1e-6`.

## Source Median Gate

The implemented-mode source median comparison includes Q-DESN exAL ridge hybrid.
The row is finite, reproducible, and labeled approximate:

- max fitted difference versus exAL ridge full-data: `0.902`;
- pinball-loss difference versus exAL ridge full-data: `0.0149`;
- stochastic exAL still fails early.

The comparison run used `/usr/bin/time -v` and finished in 54.95 seconds with
peak resident set size 608396 KB.

## Remaining Gated Work

- pure stochastic exAL;
- RHS/RHS_NS hybrid exAL;
- exAL diagonal covariance;
- exAL online/posterior-as-prior wrappers;
- article-side exAL approximate adapters;
- divide-and-combine VB;
- variational coresets.

## Next Recommended Stage

Run one additional economical source-scale hybrid exAL ridge gate, then decide
whether RHS/RHS_NS hybrid exAL has enough mathematical value to justify a new
global-shrinkage contract.
