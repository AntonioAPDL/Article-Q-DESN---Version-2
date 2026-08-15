# Q-DESN AL Online Wrapper Stage

Date: 2026-05-28

## Purpose

This note documents the first canonical Q-DESN online wrapper stage. The wrapper
is a workflow/state-handoff layer over already tested Q-DESN AL ridge VB fits.
It is not a new streaming reservoir engine and not a new likelihood update.

The online target is target-changing: ordered batches are fit sequentially, and
each post-first batch receives the previous batch's beta posterior as a
Gaussian beta prior.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `b7369b9 Add Q-DESN AL online wrapper`

No article application code or config was changed by this stage.

## Implemented Scope

Implemented:

- package univariate Q-DESN only;
- AL likelihood only;
- ridge base beta prior only;
- full beta covariance only;
- ordered batch/window sequence;
- posterior-as-prior Gaussian beta handoff;
- unchunked or exact chunked per-batch VB;
- one-batch equivalence to ordinary Q-DESN AL ridge VB;
- metadata for batch boundaries, feature hashes, design hashes, package SHA,
  prior-family handoff, covariance form, and state hashes.

Still gated:

- RHS/RHS_NS posterior-as-prior and online handoff;
- exAL online/posterior-as-prior;
- stochastic or hybrid online modes;
- diagonal-covariance posterior-as-prior;
- article GloFAS online adapters;
- low-level streaming DESN state handoff.

Divide-and-combine VB and variational coresets were not implemented and remain
explicitly deferred.

## API

```r
fit <- exdqlm::qdesn_vb_fit_online(
  y = y,
  p0 = 0.5,
  batch_ends = c(100, 200, length(y)),
  desn_args = list(D = 1L, n = 4L, m = 1L, washout = 3L,
                   add_bias = TRUE, seed = 20260528L),
  vb_args = list(likelihood_family = "al", al_fixed_gamma = 0,
                 beta_prior_type = "ridge", beta_ridge_tau2 = 10),
  posterior_as_prior = list(
    enabled = TRUE,
    mode = "gaussian_beta",
    prior_strength = 1,
    jitter = 1.0e-8,
    validate_feature_settings = TRUE
  )
)
```

The result has class `qdesn_vb_online_fit` and records:

- `target$type = "online_posterior_as_prior_al_ridge"`;
- `target$preserves_full_data_target = FALSE`;
- `target$workflow = "online_state_handoff"`;
- `target$order_sensitive = TRUE`;
- `batches` with source row boundaries and no-future-leakage flags;
- `summary` with likelihood, beta-prior type, chunking mode, covariance form,
  finite-state flags, and design hashes;
- `state_handoffs` with input/output state hashes, prior natural norms, feature
  hashes, package SHA, and covariance form.

## Mathematical Contract

For batch `b`, let the allowed rows be `B_b`. The first batch uses the base
ridge beta prior. For each later batch:

```text
q_{b-1}(beta) = N(m_{b-1}, V_{b-1})
Lambda_b = inverse(V_{b-1} + jitter I)
g_b = Lambda_b m_{b-1}
```

The pair `(Lambda_b, g_b)` becomes the next batch's global Gaussian beta prior.
It is not row-scaled and not chunked. Exact chunking inside a batch only changes
how row-additive AL likelihood statistics are accumulated and must match the
unchunked batch target.

The current wrapper rebuilds Q-DESN features within each ordered batch using
only that batch's responses. It does not carry reservoir states across batches.
That low-level streaming DESN handoff remains gated.

## Tests

Baseline freeze before package edits:

- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-qdesn-vb-rolling-window.R`: 65 pass;
- `test-qdesn-vb-warm-start.R`: 39 pass;
- `test-exal-beta-covariance-approx.R`: 75 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- total baseline: 558 pass, 0 fail.

Post-implementation focused regression:

- `test-qdesn-vb-posterior-as-prior.R`: 19 pass;
- `test-qdesn-vb-online-wrapper.R`: 37 pass;
- `test-qdesn-vb-rolling-window.R`: 65 pass;
- `test-qdesn-vb-warm-start.R`: 39 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- total post-implementation: 539 pass, 0 fail.

Covered checks:

- one-batch online wrapper equals ordinary Q-DESN AL ridge VB;
- two-batch online wrapper uses posterior-as-prior handoff metadata;
- exact chunked online matches unchunked online within tolerance;
- fixed-seed reproducibility;
- batch boundaries and no-future-leakage flags;
- exAL, RHS/RHS_NS, stochastic, warm-start, disabled posterior-as-prior, and
  diagonal-covariance online combinations fail early.

## Decisions

- The wrapper is exposed through `qdesn_vb_fit_online()`, not through
  `chunking`.
- `posterior_as_prior` must be enabled for this wrapper.
- Full covariance is required because the carried prior uses
  `inverse(V_beta)`.
- Warm starts remain same-target initialization tools and are not used by this
  target-changing workflow.
- Article configs are not repinned or exposed to online controls in this stage.

## Remaining Risks

- The wrapper does not carry reservoir states across batches.
- RHS/RHS_NS handoff needs a global shrinkage-state contract.
- exAL handoff needs q(s), q(v), sigma/gamma, xi, and objective semantics.
- Stochastic/hybrid online modes need separate approximate target labels and
  refresh contracts.
- Article online adapters need no-leakage and latent future-path contracts.

## Recommended Next Stage

The next single stage should be either:

1. richer subset stratification contracts and implementation for AL ridge; or
2. low-rank covariance design after diagonal covariance is exercised on the
   intended comparison examples.

Do not start stochastic/hybrid exAL, RHS/RHS_NS posterior-as-prior, or article
online adapters until their contracts are explicit and tested.
