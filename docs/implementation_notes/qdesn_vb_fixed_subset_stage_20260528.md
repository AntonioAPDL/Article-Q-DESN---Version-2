# Q-DESN VB Fixed Subset Stage

Date: 2026-05-28

## Purpose

This note documents the first fixed subset CAVI stage. This mode is a
target-changing diagnostic/screening mode: it fits VB to an explicit fixed row
subset after DESN feature construction. It is not exact chunking, not stochastic
mini-batching, and not an approximation to the full-data posterior unless a
future importance-weighting or coreset derivation says otherwise.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `fbf04f1 Add fixed subset VB target mode`

## Implemented Scope

Implemented:

- package static/readout AL;
- univariate Q-DESN AL routing through `qdesn_fit_vb()`;
- ridge beta prior only;
- full-data unchunked VB applied to the selected rows;
- exact chunked VB applied to the selected rows;
- deterministic fixed row IDs through `subset_fit`.

Still gated:

- response-quantile, leverage/design-score, and custom stratified subset
  selection;
- RHS/RHS_NS subset fitting;
- exAL subset fitting;
- stochastic/hybrid subset fitting;
- online, rolling, or posterior-as-prior subset handoff;
- article GloFAS adapters.

## Contract

The control selects a deterministic row subset of the static readout design
matrix received by the LDVB engine. For Q-DESN fits, those row IDs are therefore
post-washout readout rows, not raw pre-washout time indices.

```text
X_subset = X[rows, ]
y_subset = y[rows]
```

The engine then runs the existing AL ridge VB update on `(X_subset, y_subset)`.
Exact chunking, when enabled, only chunks rows inside this subset target and is
therefore required to match the unchunked subset fit.

The result records:

- `fit$misc$target_label = "subset_data_vb"`;
- `fit$misc$preserves_full_data_target = FALSE`;
- `fit$misc$subset_rows`;
- `fit$misc$original_n`;
- `fit$misc$subset_fit$n_subset`.

## API

Package controls:

```r
vb_args <- list(
  likelihood_family = "al",
  al_fixed_gamma = 0,
  beta_prior_type = "ridge",
  subset_fit = list(
    enabled = TRUE,
    mode = "fixed",
    rows = c(1L, 5L, 9L, 13L)
  )
)
```

Default behavior is unchanged: when `subset_fit` is absent, no subset target is
used and `exal_make_vb_control()` omits the control.

Unsupported combinations fail early:

- `likelihood_family = "exal"`;
- RHS/RHS_NS beta priors;
- stochastic or hybrid chunking.

## Tests

Package test file:

```text
tests/testthat/test-exal-subset-fit.R
```

Focused regression set after implementation:

- `test-exal-subset-fit.R`: 30 pass;
- `test-exal-beta-covariance-approx.R`: 36 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- total: 445 pass, 0 fail.

Covered checks:

- fixed row controls normalize and validate integer row IDs;
- malformed, missing, fractional, and out-of-range row IDs fail early;
- fixed subset VB matches an explicit direct fit on those rows;
- exact chunked subset VB matches unchunked subset VB;
- Q-DESN routes fixed subset controls through `qdesn_fit_vb()`;
- exAL, RHS/RHS_NS, and stochastic/hybrid subset modes fail early.

## Remaining Risks

- This mode intentionally changes the inference target, so it is suitable for
  cheap screening and sensitivity checks, not as a full-data posterior proxy.
- Row IDs for Q-DESN are post-washout readout rows. Any user-facing time-index
  adapter should be a separate documented layer.
- Time-block stratified subset selection is now implemented separately in
  package commit `7f310ed`. Response-quantile, leverage/design-score, random,
  and custom subset schemes still require explicit sampling contracts and
  reproducibility metadata before implementation.

## Recommended Next Stage

The next single stage should be chosen from RHS/RHS_NS diagonal covariance,
canonical Q-DESN online wrapper design, or richer stratification contracts. Low-
rank covariance, divide-and-combine VB, and coresets remain lower-priority
research extensions.
