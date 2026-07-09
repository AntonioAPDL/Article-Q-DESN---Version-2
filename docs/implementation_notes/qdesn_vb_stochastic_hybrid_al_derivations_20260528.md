# Q-DESN Stochastic and Hybrid AL VB Derivations

Date: 2026-05-28

Status: derivation and implementation contract. Package stochastic AL is
implemented and approximate. Package hybrid AL with periodic full refresh is
implemented in exdqlm commit `685d2f5fcf789dd65495223f6b6f2dfa59a5cf22` for
package static/readout and univariate Q-DESN AL only.

## Scope

This note applies to package static/readout AL after fixed DESN feature
construction. It covers:

- existing stochastic mini-batch AL VB;
- hybrid AL SVI with periodic full refresh;
- ridge, RHS, and RHS_NS beta priors.

It does not authorize:

- stochastic or hybrid exAL;
- article GloFAS stochastic/hybrid batching;
- multivariate Q-DESN batching;
- variance-reduced SVI.

## Target

The reference target is the full-data AL LDVB fixed point. Exact chunking
computes that target exactly up to floating-point ordering. Stochastic and
hybrid AL use scaled row subsamples to approximate full-data data terms and are
therefore approximate unless a full refresh is performed every iteration.

## Data Batching

Let `B_t` be a mini-batch of row indices at stochastic iteration `t`, with
batch size `M = |B_t|`.

Supported sampling options should be explicit:

- `order = "random"`: sample rows using a fixed RNG seed;
- `order = "shuffled"`: shuffle rows each epoch and consume sequential chunks;
- `order = "sequential"` only for deterministic diagnostics, not as a claim of
  stochastic unbiasedness.

Epoch definition:

```text
one epoch = enough mini-batches to cover N sampled row slots
```

With replacement and without replacement must be recorded in controls. The
first hybrid implementation should reuse the existing tested stochastic sampler
rather than adding a second sampler.

## Scaling

For stochastic data natural statistics:

```text
scale_t = N / M
S_hat_t = scale_t * sum_{i in B_t} w_i x_i x_i'
g_hat_t = scale_t * sum_{i in B_t} x_i b_i
```

Scaled:

- beta data precision statistic;
- beta data linear statistic;
- any stochastic sigma data statistic if implemented.

Not scaled:

- prior precision;
- RHS/RHS_NS state;
- intercept policy;
- full-refresh statistics;
- diagnostics computed on the full data.

RHS/RHS_NS states remain global and are updated from current global beta
moments according to the chosen refresh cadence.

## Local Variables

The engine stores local moments for all rows:

- `qv_m`;
- `qv_m_inv`;
- AL-inactive `qs` compatibility state if required by engine internals.

At stochastic steps:

- rows in `B_t` are refreshed from current globals;
- rows not in `B_t` retain stale local moments;
- deterministic initialization must refresh all rows before the first
  stochastic update.

Hybrid mode adds periodic full-local refresh:

```text
if t %% local_every == 0:
  refresh qv for all rows
```

The result object and traces must report stale-local behavior.

## Global Beta Update

A stochastic natural-stat update should damp data statistics, not prior terms:

```text
S_bar_t = (1 - rho_t) S_bar_{t-1} + rho_t S_hat_t
g_bar_t = (1 - rho_t) g_bar_{t-1} + rho_t g_hat_t

V_beta_t = solve(S_bar_t + Lambda_beta_t)
m_beta_t = V_beta_t g_bar_t
```

Learning-rate schedule:

```text
rho_t = max(rho_min, (t0 + t)^(-kappa))
```

Valid defaults:

- `t0 >= 1`;
- `0.5 < kappa <= 1`;
- `0 <= rho_min < 1`;
- `rho_min` small enough not to dominate late iterations.

Hybrid full-refresh-every-iteration should recover exact AL up to tolerance by
setting the refreshed full-data data stats as the current data stats.

## Sigma Updates

Conservative first hybrid design:

- keep stochastic beta/local steps between refreshes;
- perform sigma LD updates on a full-data refreshed state every `sigma_every`;
- do not claim exact ELBO on non-refresh iterations.

If stochastic sigma stats are ever added:

- scale only row-additive data terms by `N / M`;
- damp sigma stats separately;
- preserve AL fixed gamma;
- require finite positive sigma state after every update.

For the next hybrid AL implementation, prefer periodic full sigma refresh over
fully stochastic sigma stats.

## RHS/RHS_NS Updates

RHS/RHS_NS updates are global. Valid first policies:

- update RHS from current `qbeta` every iteration; or
- update RHS only at full refresh iterations.

The chosen policy must be a documented control:

```r
refresh = list(rhs_every = 20)
```

No row batch may update RHS local/global shrinkage terms directly.

## Objective and Diagnostics

Trace fields must distinguish:

- noisy stochastic surrogate;
- full-data objective refresh;
- exact ELBO/objective when computed on all rows.

Recommended trace names:

- `objective_stochastic`;
- `objective_full_refresh`;
- `full_refresh_iter`;
- `batch_size`;
- `rho`;
- `epoch`;
- `stale_local_fraction`.

Do not label stochastic objectives as exact ELBO unless they are computed on
all rows with refreshed locals.

## API Proposal

Existing stochastic controls remain under `chunking`:

```r
chunking = list(
  enabled = TRUE,
  mode = "stochastic",
  chunk_size = 64,
  order = "random",
  seed = 20260528,
  learning_rate = list(
    schedule = "robbins_monro",
    t0 = 10,
    kappa = 0.75,
    rho_min = 1e-4
  ),
  refresh = list(
    full_every = NULL,
    objective_every = 20,
    sigma_every = 5,
    rhs_every = 20,
    local_every = 20
  )
)
```

Hybrid uses `mode = "hybrid"` with the same sampling, learning-rate, refresh,
and diagnostic control families. It remains approximate unless every iteration
is a full refresh. The implemented package gate requires `full_every = 1` to
recover exact AL within tolerance.

## Implementation Mapping

Likely package files:

- `R/exal_inference_config.R`
  - normalize stochastic/hybrid controls;
  - fail early for unsupported exAL approximate modes.
- `R/exal_online_state.R`
  - batch sampler and data-stat helpers.
- `R/exal_ldvb_engine.R`
  - stochastic/hybrid AL loop;
  - full refresh branches;
  - trace labeling.
- `R/qdesn_vb.R`
  - Q-DESN routing for implemented AL modes only.

## Tests

Existing stochastic and hybrid AL tests:

- `tests/testthat/test-exal-stochastic-al-vb.R`
- `tests/testthat/test-exal-hybrid-al-vb.R`
- `tests/testthat/test-exal-batching-controls.R`
- `tests/testthat/test-qdesn-vb-batching-modes.R`

Hybrid tests implemented in package commit `685d2f5`:

- controls normalize and invalid controls fail;
- `mode = "hybrid"` with `full_every = 1` recovers exact AL;
- finite and reproducible synthetic fit;
- RHS/RHS_NS remains global;
- stochastic/hybrid exAL fails early;
- default full/exact/stochastic behavior unchanged.

## Economical Gates

Package:

- synthetic ladder with AL ridge and RHS/RHS_NS;
- TT500 source gate;
- larger last1000/wash500/D1n300 gate only after synthetic and TT500 pass.

Article:

- no article stochastic/hybrid controls from this stage;
- article docs may report package readiness only.

## Stop Conditions

Stop or rollback if:

- full-refresh-every-iteration does not recover exact AL;
- RHS/RHS_NS update semantics are ambiguous;
- stale local moments produce non-finite states on synthetic tests;
- stochastic/hybrid exAL can run;
- objective traces imply exact ELBO on mini-batch iterations;
- package defaults or exact chunking change.
