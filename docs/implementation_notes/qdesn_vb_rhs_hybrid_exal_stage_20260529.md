# Q-DESN VB RHS-Family Hybrid exAL Stage

Date: 2026-05-29

## Purpose

This note documents the narrow extension of hybrid exAL VB from ridge-only beta
priors to RHS-family beta priors. The mode is still approximate unless every
iteration is a full refresh. Pure stochastic exAL remains forbidden.

## Package State

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- stage commit: `4912699 Extend hybrid exAL and subset comparison modes`
- source-gate rerun: `71cac6c`
- later package checkpoint: `0f5d4f6 Fix Normal DESN comparison dirty-state metadata`

The package branch advanced after the VB commit with unrelated Normal DESN work.
The source-gate rerun at `71cac6c` confirms the Q-DESN VB behavior still
passes with the VB stage included. The later `0f5d4f6` commit is a Normal DESN
comparison metadata fix and does not change this Q-DESN hybrid exAL result.

## Implemented Scope

Implemented:

- package static/readout exAL hybrid VB;
- univariate Q-DESN exAL hybrid routing through `qdesn_fit_vb()`;
- beta priors: `ridge`, `rhs`, and `rhs_ns`;
- full covariance beta updates only;
- periodic full refresh with stale-local iterations between refreshes;
- exact recovery when `chunking$mode = "hybrid"` and `refresh$full_every = 1`;
- global RHS/RHS_NS shrinkage updates.

Still forbidden:

- pure stochastic exAL;
- exAL diagonal covariance;
- exAL subset fitting;
- exAL posterior-as-prior or online wrappers;
- article-side exAL adapters.

## Contract

Hybrid exAL approximates the full-data exAL LDVB fixed point between periodic
full refreshes. A full-refresh iteration refreshes qbeta, qv, qs, sigma/gamma
LD state, xi expectations, and RHS-family shrinkage states from the current
full data state. A non-refresh iteration updates only the stochastic/hybrid
row-local and beta natural-stat components defined by the existing hybrid
engine.

The RHS/RHS_NS shrinkage states are global. They are never row-batched. The
extension is allowed because the existing engine already updates RHS-family
states globally from the current qbeta second moments after the qbeta update.

When `full_every = 1`, every iteration is a full refresh and the hybrid path
must match the exact exAL path within strict numerical tolerance. When
`full_every > 1`, result metadata and diagnostics must continue to label the
mode as approximate.

## Controls

Example supported control:

```r
vb_args <- list(
  likelihood_family = "exal",
  beta_prior_type = "rhs_ns",
  chunking = list(
    enabled = TRUE,
    mode = "hybrid",
    chunk_size = 64L,
    order = "random",
    seed = 20260529L,
    refresh = list(full_every = 15L),
    diagnostics = list(trace = TRUE, store_batch_ids = TRUE)
  )
)
```

`mode = "stochastic"` with `likelihood_family = "exal"` still fails early.

## Tests

Post-change package regression:

- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-qdesn-vb-batching-modes.R`: 42 pass;
- `test-exal-beta-covariance-approx.R`: 75 pass;
- `test-exal-subset-fit.R`: 80 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- `test-exal-hybrid-al-vb.R`: 33 pass;
- `test-exal-hybrid-exal-vb.R`: 80 pass.

Total focused post-change regression: 661 pass, 0 fail.

The new coverage checks:

- hybrid exAL with `rhs` and `rhs_ns` has finite qbeta, qv, qs, sigma/gamma,
  and RHS-family traces;
- `full_every = 1` recovers exact exAL for RHS-family priors;
- Q-DESN routes hybrid exAL with RHS_NS;
- stochastic exAL remains forbidden.

## Source Gate

The implemented-mode source gate used:

- source: `fit_input_lastTT5000`;
- selected rows: last 1000 source rows, indices 9001:10000;
- washout: 500;
- effective fitted rows: 500;
- Q-DESN: `D = 1`, reservoir `n = 300`, `m = 1`;
- cores: 6;
- output: `results/qdesn_vb_implemented_modes_source_last1000_wash500_d1n300_20260529_current_head`.

Results:

- 29 method rows;
- 12/12 exact equivalence rows passed;
- max absolute exact gate difference: `0.0001637543`;
- max relative exact gate difference: `3.180675e-08`;
- hybrid exAL ridge/RHS/RHS_NS finite: yes;
- hybrid exAL fixed-seed repeat beta difference: 0.

Runtime:

- elapsed wall time: 2:23.57;
- max resident set size: 922792 KB.

## Remaining Risks

- Hybrid exAL is approximate unless every iteration is a full refresh.
- RHS-family hybrid exAL uses global shrinkage updates from the current qbeta
  state; no row-batched RHS-family update has been introduced.
- The mode is not a posterior-as-prior or online exAL workflow.

## Recommended Next Stage

Do not move to pure stochastic exAL yet. The next safe exAL-related work is to
keep exercising hybrid exAL on controlled examples, then decide whether exAL
diagonal covariance or stochastic exAL has enough mathematical support to
reopen. The current exAL diagonal stop gate should be resolved before enabling
any covariance approximation for exAL.
