# Q-DESN exAL Approximate VB Contract

Date: 2026-05-28
Status: implementation contract for hybrid exAL ridge and RHS-family stages.

## Purpose

This note is the contract for the first approximate exAL batching mode and its
RHS-family extension. It replaces the earlier stop-gate requirements note. The
implemented mode is hybrid exAL with periodic full refresh under ridge, RHS, and
RHS_NS beta priors. Pure stochastic exAL, exAL RHS-family diagonal covariance,
article exAL adapters, divide-and-combine VB, and variational coresets remain
out of scope. exAL ridge diagonal covariance is handled by the covariance
approximation contract, not this approximate-batching contract.

## Current exAL Baselines

Already implemented and used as references:

- exAL unchunked full-data LDVB;
- exAL exact chunked full-data LDVB;
- ridge, RHS, and RHS_NS beta priors for full/exact modes.

Still forbidden unless a later contract supersedes this one:

- stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- exAL online or posterior-as-prior wrappers;
- article-side exAL approximate adapters.

## First Supported Scope

The first approximate exAL stage is:

```text
likelihood_family = "exal"
beta_prior_type = "ridge" | "rhs" | "rhs_ns"
chunking$mode = "hybrid"
```

The target is the existing full-data exAL LDVB fixed point, but the iterations
between full refreshes are approximate. Therefore:

- `full_every = 1` must recover exact unchunked exAL under the same iteration
  count and tolerances;
- `full_every > 1` is approximate and must be labeled as such;
- exact chunked exAL remains the full-data reference, not an approximation;
- no stochastic-only exAL mode is enabled by this contract.

## State Components

The exAL engine state contains:

- `qbeta`: Gaussian readout coefficient posterior;
- `qv`: row-local GIG moments;
- `qs`: row-local truncated-normal moments;
- `qsiggam`: Laplace-Delta state for sigma/gamma;
- `xis`: expectations derived from the sigma/gamma LD state;
- objective and diagnostic traces.

RHS/RHS_NS states are global and non-row-additive. They are supported in the
hybrid exAL extension only through the existing global RHS-family update from
the current qbeta state. They are never row-batched.

## Hybrid Update Cadence

At every iteration the engine samples or advances a deterministic batch
according to the normalized `chunking` sampler. The following cadence applies.

`qbeta`:

- On full-refresh iterations, accumulate full-data beta natural statistics
  using all rows and solve the usual global Gaussian update.
- On non-refresh iterations, compute scaled mini-batch beta natural statistics,
  damp the stored natural statistics with the Robbins-Monro learning rate, and
  solve the global Gaussian update using the ridge prior.
- The ridge prior precision is never scaled.

`qv`:

- On full-refresh iterations, refresh `qv` for every row.
- On non-refresh iterations, refresh `qv` only for rows in the current batch.
- Rows not in the current batch retain stale `qv` moments. This is the
  approximation.

`qs`:

- On full-refresh iterations, refresh `qs` for every row.
- On non-refresh iterations, refresh `qs` only for rows in the current batch.
- Rows not in the current batch retain stale `qs` moments. This is the main
  exAL-specific reason the mode is hybrid rather than exact.

`qsiggam` and `xis`:

- The first stage uses periodic full sigma/gamma LD refreshes only.
- On sigma-refresh iterations, the LD objective uses full-data sigma/gamma
  sufficient statistics computed from the current local moments.
- On skipped iterations, `qsiggam` and `xis` remain stale.
- `xis` is refreshed only after a successful LD update.
- If LD mode finding fails or produces non-finite values, the engine must fail
  loudly; it must not silently fall back to stochastic exAL.

Objective:

- The existing engine may compute the full-data objective of the current
  approximate variational state.
- That trace must be documented as the objective of an approximate state, not
  exact CAVI equivalence unless every iteration is a full refresh.

## Controls

The existing `chunking` control surface is reused:

```r
chunking = list(
  enabled = TRUE,
  mode = "hybrid",
  chunk_size = 64,
  order = "random",
  seed = 20260528,
  learning_rate = list(
    schedule = "robbins_monro",
    t0 = 10,
    kappa = 0.75,
    rho_min = 0.02
  ),
  refresh = list(
    full_every = 10,
    objective_every = 10,
    sigma_every = 10,
    rhs_every = 10,
    local_every = 10
  ),
  diagnostics = list(
    trace = TRUE,
    store_batch_ids = TRUE,
    check_finite_every = 1
  )
)
```

For exAL ridge hybrid, `rhs_every` is accepted only because the shared control
normalizer owns that field. For RHS/RHS_NS hybrid exAL, RHS-family shrinkage is
still updated globally by the engine after qbeta updates; no row-level RHS
mini-batch update is introduced.

Invalid combinations must fail early:

- `mode = "stochastic"` with `likelihood_family = "exal"`;
- exAL hybrid with diagonal covariance;
- exAL hybrid with subset fitting;
- article adapters.

## Implementation Mapping

Package files:

- `R/exal_ldvb_engine.R`
  - relax the approximate chunking gate only for exAL ridge/RHS/RHS_NS hybrid;
  - keep stochastic exAL forbidden;
  - keep RHS/RHS_NS updates global;
  - reuse the existing hybrid full-refresh and stale-local logic.
- `R/exal_online_state.R`
  - reuse existing chunking, sampler, and learning-rate controls.
- `R/qdesn_vb.R`
  - route Q-DESN exAL hybrid only after the static/readout gate passes.

No article application file should expose exAL hybrid controls in this stage.

## Required Tests

Static/readout tests:

- invalid controls fail early;
- `full_every = 1` recovers exact exAL ridge/RHS/RHS_NS for qbeta, qv, qs,
  sigma/gamma, RHS-family traces, and objective traces;
- `full_every > 1` is finite and reproducible with fixed seed;
- `qbeta`, `qv`, `qs`, `qsiggam`, and `xis` are finite;
- gamma remains within bounds;
- stochastic exAL still fails early;
- exact chunked exAL remains equivalent to unchunked exAL.

Q-DESN tests:

- `qdesn_fit_vb()` routes exAL ridge hybrid;
- `qdesn_fit_vb()` routes exAL RHS_NS hybrid after static/readout coverage;
- `full_every = 1` recovers Q-DESN exAL ridge full-data VB;
- stochastic exAL still fails early;

Regression tests:

- stochastic AL and hybrid AL behavior unchanged;
- full-data defaults unchanged;
- exact chunking equivalence unchanged.

## Economical Gates

Package gates:

- tiny synthetic static/readout exAL ridge;
- tiny synthetic static/readout exAL RHS-family priors;
- tiny Q-DESN exAL ridge;
- source-scale implemented-mode gate with D1-n300 and 500 effective fitted
  rows;
- existing focused exact chunking, inference config, Q-DESN batching, covariance,
  subset, and RHS tests after implementation.

Article gates:

- documentation-only changes require `git diff --check`;
- no article application tests are required unless application code or configs
  are changed.

## Stop Conditions

Stop if:

- `full_every = 1` does not recover exact exAL;
- sigma/gamma LD mode finding becomes unstable;
- stale `qs`, stale `qv`, or stale `xis` semantics become ambiguous;
- RHS/RHS_NS state handoff becomes necessary;
- stochastic exAL would need to run;
- article adapters would need to change;
- implementation requires unrelated refactors.
