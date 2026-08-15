# Q-DESN VB Equal Stratified Subset Stage

Date: 2026-05-29

## Purpose

This note documents the extension of time-block stratified subset VB from
proportional allocation to equal allocation. This is still a target-changing
subset-data mode. It is not exact chunking, not stochastic mini-batching, and
not a full-data posterior approximation.

## Package State

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- stage commit: `4912699 Extend hybrid exAL and subset comparison modes`
- source-gate rerun: `71cac6c`
- later package checkpoint: `0f5d4f6 Fix Normal DESN comparison dirty-state metadata`

The later `0f5d4f6` package commit is a Normal DESN comparison metadata fix and
does not alter the equal-allocation subset implementation or source-gate
results documented here.

## Implemented Scope

Implemented:

- package static/readout AL;
- univariate Q-DESN AL routing through `qdesn_fit_vb()`;
- ridge beta prior only;
- `subset_fit$mode = "stratified"`;
- `subset_fit$strata = "time_block"`;
- `subset_fit$allocation = "proportional"` or `"equal"`;
- unchunked subset-target VB;
- exact chunked subset-target VB.

Still gated:

- response-quantile strata;
- leverage/design-score strata;
- custom external strata;
- RHS/RHS_NS subset fitting;
- exAL subset fitting;
- stochastic/hybrid subset fitting;
- article-side subset adapters.

## Contract

The selected target is:

```text
X_subset = X[rows, ]
y_subset = y[rows]
```

`allocation = "equal"` fills non-empty time-block strata as evenly as possible,
respecting each stratum capacity. If the requested subset size is not divisible
by the number of represented strata, lower-numbered strata receive the first
extra rows under deterministic tie-breaking. Rows are then sampled within each
stratum using the explicit seed and sorted before fitting.

Exact chunking over the selected rows must match the unchunked subset target for
the same seed and subset controls.

## Example Control

```r
vb_args <- list(
  likelihood_family = "al",
  beta_prior_type = "ridge",
  subset_fit = list(
    enabled = TRUE,
    mode = "stratified",
    strata = "time_block",
    allocation = "equal",
    size = 180L,
    n_strata = 5L,
    seed = 20260529L
  )
)
```

## Tests

Post-change coverage in `tests/testthat/test-exal-subset-fit.R` checks:

- equal allocation control normalization;
- allocation sums to the requested subset size;
- each stratum is represented when possible;
- equal-allocation stratified subset VB matches an explicit direct fit;
- exact chunked equal-allocation subset VB matches unchunked subset VB;
- Q-DESN routing remains valid;
- unsupported allocation values fail early.

Focused post-change subset test result: 80 pass, 0 fail.

## Source Gate

The D1-n300 source gate at package `71cac6c` included:

- `qdesn_al_ridge_stratified_equal_subset`;
- `qdesn_al_ridge_stratified_equal_subset_exact`.

Both fits were finite. Exact chunked equal subset matched the unchunked equal
subset target under the exact equivalence gate.

Selected metric from the gate:

| method | pinball_y | rmse_q_target |
| --- | ---: | ---: |
| equal stratified subset | 8.403154 | 17.71687 |
| equal stratified subset exact chunked | 8.403154 | 17.71687 |

## Richer Strata Addendum

Package commit `f0d45ea` adds response-quantile and design-leverage
stratifiers after this equal-allocation stage. They are documented separately in
`qdesn_vb_richer_subset_stage_20260529.md`.

## Remaining Risks

Equal allocation is a sampling design for a target-changing subset mode. It is
useful for sensitivity checks and cheap screening, but it should not be reported
as preserving the full-data posterior target.

Custom strata remain gated because they need separate leakage and sampling
contracts.
