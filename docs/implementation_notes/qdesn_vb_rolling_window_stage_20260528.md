# Q-DESN VB Rolling-Window Stage

Date: 2026-05-28

## Purpose

This note documents the first implemented rolling-window Q-DESN VB stage. It is
a target-changing workflow wrapper, not a new posterior approximation. Each
origin is fit independently using only the training rows in that origin's
window, so future observations cannot enter DESN feature construction or the VB
readout fit.

## Scope Implemented

Package repo:

- `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`

Implemented API:

- `qdesn_vb_fit_rolling()`

Supported first-stage modes:

- Q-DESN AL likelihood only;
- ridge beta prior only;
- independent rolling-window refits;
- independent expanding-window refits;
- posterior-as-prior AL ridge beta Gaussian handoff over rolling or expanding
  origin sequences;
- unchunked full-window VB;
- exact chunked full-window VB.

Explicitly not implemented in this stage:

- RHS/RHS_NS rolling shrinkage state handoff;
- exAL rolling mode;
- stochastic or hybrid rolling mode;
- article GloFAS rolling/stochastic adapters;
- online VB as a comparison-ready wrapper.

## Target Semantics

For origin `o`, the wrapper fits

```text
y[window_start(o):o]
```

and no rows after `o`. This is a different target from the full-series VB fit
because the data window changes. Exact chunking inside each origin still
preserves that origin's full-window VB target.

The wrapper records:

- `target$type`;
- `target$preserves_full_data_target = FALSE`;
- `target$posterior_as_prior`;
- `target$no_future_leakage`;
- per-origin `window_start`, `window_end`, `window_n`, and `uses_future_rows`.

For `posterior_as_prior = TRUE`, the implemented AL ridge stage records
`target$type = "posterior_as_prior_al_ridge"` and carries the previous origin's
Gaussian beta posterior into the next origin as a global beta prior. This is not
a warm start and does not preserve the full-series posterior target.

## API

Minimal example:

```r
fit <- exdqlm::qdesn_vb_fit_rolling(
  y = y,
  p0 = 0.5,
  origins = c(250, 300, 350),
  window_size = 200,
  mode = "rolling",
  desn_args = list(D = 1L, n = 25L, m = 1L, washout = 25L,
                   add_bias = TRUE, seed = 20260528L),
  vb_args = list(likelihood_family = "al", al_fixed_gamma = 0,
                 beta_prior_type = "ridge", beta_ridge_tau2 = 10,
                 max_iter = 100L, n_samp_xi = 32L)
)
```

Exact chunking may be enabled inside each origin:

```r
vb_args$chunking <- list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 64L,
  order = "sequential"
)
```

Posterior-as-prior may be enabled explicitly:

```r
fit_pap <- exdqlm::qdesn_vb_fit_rolling(
  y = y,
  p0 = 0.5,
  origins = c(250, 300, 350),
  window_size = 200,
  desn_args = list(D = 1L, n = 25L, m = 1L, washout = 25L,
                   add_bias = TRUE, seed = 20260528L),
  vb_args = list(likelihood_family = "al", al_fixed_gamma = 0,
                 beta_prior_type = "ridge", beta_ridge_tau2 = 10,
                 max_iter = 100L, n_samp_xi = 32L),
  posterior_as_prior = list(
    enabled = TRUE,
    mode = "gaussian_beta",
    prior_strength = 1.0,
    jitter = 1.0e-8,
    validate_feature_settings = TRUE
  )
)
```

## Fail-Early Gates

The wrapper fails early for:

- `likelihood_family = "exal"`;
- `beta_prior_type` other than `"ridge"`;
- stochastic or hybrid chunking;
- warm-start objects passed through `vb_args$warm_start`.

These gates keep the first rolling stage honest. Posterior-as-prior is supported
only for AL ridge beta handoff. RHS/RHS_NS state handoff is not the same as a
beta Gaussian handoff and still needs its own contract.

## Tests

Package test:

```text
tests/testthat/test-qdesn-vb-rolling-window.R
```

Fresh focused result:

- 65 pass;
- 0 fail.

Covered checks:

- rolling windows end exactly at the requested origin;
- no future rows are used;
- expanding windows start at row 1;
- per-origin variational states are finite;
- exact chunked rolling fits match unchunked rolling fits per origin;
- posterior-as-prior state handoffs are present, reproducible, target-changing,
  and exact-chunked equivalent to the unchunked handoff target;
- posterior-as-prior expanding origin sequences run;
- exAL, RHS/RHS_NS, stochastic/hybrid, invalid posterior-as-prior modes, and
  warm-start paths fail early.

Command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-rolling-window.R")'
```

## Posterior-as-Prior Package Gate

Package script:

```text
scripts/run_qdesn_vb_posterior_as_prior_gate_20260528.R
```

Fresh synthetic gate:

- package HEAD: `1259199` when the gate was run;
- seed: `20260528`;
- series length: `36`;
- window size: `18`;
- origins: `24, 30, 36`;
- maximum exact posterior-as-prior beta-mean difference between exact chunked
  and unchunked: `2.602e-10`;
- maximum exact posterior-as-prior prediction difference: `2.197e-12`;
- forbidden exAL, RHS/RHS_NS, and stochastic posterior-as-prior paths failed
  early.

Outputs are ignored under:

```text
results/qdesn_vb_posterior_as_prior_gate_20260528/
```

## Next Stage

Do not route RHS/RHS_NS, exAL, stochastic, hybrid, or article-side adapters
through posterior-as-prior until separate tests prove their target labels and
state semantics. The next safe implementation target is diagonal covariance
CAVI for AL + ridge, or a documentation/test audit of online VB before deciding
whether it can become a comparison-ready mode.
