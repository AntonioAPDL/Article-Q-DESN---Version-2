# Q-DESN VB Stratified Subset Stage

Date: 2026-05-28

## Purpose

This note documents the first stratified subset CAVI stage. Like fixed subset
VB, this is a target-changing diagnostic/screening mode. It fits VB to a
deterministic, seed-reproducible subset of static readout rows after DESN
feature construction. It is not exact chunking, not stochastic mini-batching,
and not a full-data posterior approximation.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `7f310ed Add stratified subset VB target mode`

## Implemented Scope

Implemented:

- package static/readout AL;
- univariate Q-DESN AL routing through `qdesn_fit_vb()`;
- ridge beta prior only;
- unchunked subset-target VB;
- exact chunked subset-target VB;
- `subset_fit$mode = "stratified"`;
- `subset_fit$strata = "time_block"`;
- `subset_fit$allocation = "proportional"`;
- explicit subset `size`, `n_strata`, and `seed`.

Still gated:

- response-quantile strata;
- leverage/design-score strata;
- custom allocations;
- RHS/RHS_NS subset fitting;
- exAL subset fitting;
- stochastic/hybrid subset fitting;
- rolling/online/posterior-as-prior subset handoff;
- article GloFAS adapters.

## Contract

The implemented stratifier partitions the already-built static readout rows into
time blocks:

```text
stratum_id_i = time_block(i; n_rows, n_strata)
```

A proportional allocation chooses `size` rows across the non-empty strata. When
`size >= n_strata`, each non-empty stratum receives at least one selected row.
As of package commit `4912699`, `allocation = "equal"` is also supported and
fills time-block strata as evenly as possible before sampling rows within each
stratum. Rows are sampled within strata using the explicit seed, then sorted
before the VB fit. The fit target is:

```text
X_subset = X[rows, ]
y_subset = y[rows]
```

Exact chunking, when enabled, chunks only the selected subset target and is
therefore required to match unchunked stratified subset VB for the same seed and
control block.

For Q-DESN fits, `rows` are post-washout static readout row IDs, not raw time
indices.

## API

Package controls:

```r
vb_args <- list(
  likelihood_family = "al",
  al_fixed_gamma = 0,
  beta_prior_type = "ridge",
  subset_fit = list(
    enabled = TRUE,
    mode = "stratified",
    strata = "time_block",
    size = 120L,
    n_strata = 6L,
    allocation = "proportional", # or "equal"
    seed = 20260528L
  )
)
```

Default behavior is unchanged: when `subset_fit` is absent, no subset target is
used and `exal_make_vb_control()` omits the control.

Unsupported combinations fail early:

- `likelihood_family = "exal"`;
- RHS/RHS_NS beta priors;
- stochastic or hybrid chunking;
- unsupported strata such as `response_quantile`;
- unsupported allocations other than `proportional` or `equal`;
- missing seed, invalid size, or invalid stratum count.

## Result Metadata

The result records:

- `fit$misc$target_label = "subset_data_vb"`;
- `fit$misc$preserves_full_data_target = FALSE`;
- `fit$misc$subset_rows`;
- `fit$misc$subset_strata`;
- `fit$misc$subset_allocation`;
- `fit$misc$subset_fit`.

## Tests

Package test file:

```text
tests/testthat/test-exal-subset-fit.R
```

Baseline before implementation:

- focused current-mode freeze: 453 pass, 0 fail.

Focused regression set after implementation:

- `test-exal-subset-fit.R`: 67 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-stochastic-al-vb.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- `test-exal-beta-covariance-approx.R`: 36 pass;
- total: 520 pass, 0 fail.

Covered checks:

- stratified controls normalize;
- row selection is reproducible under a fixed seed;
- different seeds can produce different rows;
- allocation sums to requested subset size;
- each stratum is represented when possible;
- pending controls can be built before `nrow(X)` is known;
- unsupported strata/allocation/missing seed/oversized subset fail early;
- stratified subset VB matches an explicit direct fit on selected rows;
- exact chunked stratified subset matches unchunked stratified subset;
- Q-DESN routes stratified subset controls through `qdesn_fit_vb()`.

## Equal Allocation Addendum

Date: 2026-05-29

Package commit `4912699` adds equal allocation for time-block strata. The
focused subset test now covers 80 passing checks, including equal allocation
normalization, explicit-fit equivalence, exact chunked subset equivalence, and
fail-early unsupported allocation values.

Equal allocation is documented separately in
`qdesn_vb_equal_stratified_subset_stage_20260529.md`.

## Richer Strata Addendum

Date: 2026-05-29

Package commit `f0d45ea` adds response-quantile and design-leverage
stratifiers for AL + ridge subset-data VB. These are documented separately in
`qdesn_vb_richer_subset_stage_20260529.md`.

## Remaining Risks

- This mode intentionally changes the data target.
- Custom strata remain gated because they need separate leakage and sampling
  contracts.
- The target is useful for screening and sensitivity checks, not as a full-data
  posterior proxy.

## Recommended Next Stage

The next single stage should be selected from:

- RHS/RHS_NS diagonal covariance, after validating shrinkage second moments;
- canonical Q-DESN online wrapper contract and no-leakage gate;
- custom strata only after their sampling contracts are written.

Stochastic/hybrid exAL remains forbidden until the exAL approximate derivation
is upgraded from requirements to an implementation contract.
