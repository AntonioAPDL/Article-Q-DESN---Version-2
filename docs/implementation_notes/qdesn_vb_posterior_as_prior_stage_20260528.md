# Q-DESN VB Posterior-as-Prior Stage

Date: 2026-05-28

## Purpose

This note documents the first implemented posterior-as-prior Q-DESN VB stage.
It is a target-changing rolling workflow, not a warm start and not a batching
approximation. Each origin uses only its own allowed training window for the
likelihood, then the fitted beta posterior from that origin becomes the next
origin's Gaussian beta prior.

## Package Commits

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`

Relevant commits:

- `fef2558` - beta prior natural-parameter hook;
- `1259199` - posterior-as-prior rolling mode and economical gate script;
- `3df0e15` - expanding-origin posterior-as-prior test coverage;
- `b7369b9` - full-covariance guard plus canonical Q-DESN AL online wrapper
  using the same Gaussian beta handoff.

## Implemented Scope

Implemented:

- package univariate Q-DESN only;
- AL likelihood only;
- ridge base beta prior only;
- rolling or expanding origin sequences;
- posterior-as-prior beta Gaussian handoff;
- unchunked full-window VB;
- exact chunked full-window VB.

Still gated:

- RHS/RHS_NS posterior-as-prior;
- exAL posterior-as-prior;
- stochastic or hybrid posterior-as-prior;
- article GloFAS adapters;
- diagonal-covariance posterior-as-prior;
- RHS/RHS_NS, exAL, stochastic, hybrid, and article online adapters.

Implemented later:

- Q-DESN AL ridge ordered-batch online wrapper through `qdesn_vb_fit_online()`,
  documented in `qdesn_vb_online_wrapper_al_ridge_stage_20260528.md`.

## Mathematical Contract

For origin `o`, the current likelihood uses only rows in window `W_o`. After
origin `o - 1`, the previous beta posterior is

```text
q_{o-1}(beta) = N(m_{o-1}, V_{o-1}).
```

The next origin uses the global Gaussian beta prior contribution

```text
Lambda_o = inverse(V_{o-1} + jitter I)
g_o = Lambda_o m_{o-1}.
```

This prior is added once to the beta natural parameters. It is not row-scaled,
not chunked, and not an RHS/RHS_NS update. Exact chunking inside the origin only
changes how row-additive likelihood statistics are accumulated and preserves
the origin's posterior-as-prior target.

## API

```r
fit <- exdqlm::qdesn_vb_fit_rolling(
  y = y,
  p0 = 0.5,
  origins = c(24, 30, 36),
  window_size = 18,
  desn_args = list(D = 1L, n = 4L, m = 1L, washout = 3L,
                   add_bias = TRUE, seed = 20260528L),
  vb_args = list(likelihood_family = "al", al_fixed_gamma = 0,
                 beta_prior_type = "ridge", beta_ridge_tau2 = 10),
  posterior_as_prior = list(
    enabled = TRUE,
    mode = "gaussian_beta",
    prior_strength = 1.0,
    jitter = 1.0e-8,
    validate_feature_settings = TRUE
  )
)
```

The result records:

- `target$type = "posterior_as_prior_al_ridge"`;
- `target$preserves_full_data_target = FALSE`;
- `target$posterior_as_prior = TRUE`;
- per-origin `previous_state_hash`;
- per-origin `prior_natural_norm`;
- `state_handoffs` with input/output state hashes and feature hashes.

## Tests

Baseline freeze before implementation:

- 318 focused package assertions passed;
- 0 failed.

Beta-prior hook regression:

- 233 focused assertions passed;
- 0 failed.

Final focused regression after posterior-as-prior implementation:

- 363 focused assertions passed before the expanding-origin tightening;
- `tests/testthat/test-qdesn-vb-rolling-window.R` then passed 65 assertions
  after adding expanding-origin coverage.

Key files:

- `tests/testthat/test-exal-beta-prior-natural.R`;
- `tests/testthat/test-qdesn-vb-rolling-window.R`;
- `tests/testthat/test-qdesn-vb-warm-start.R`;
- `tests/testthat/test-qdesn-vb-simplification-ladder.R`;
- `tests/testthat/test-exal-exact-chunking-stats.R`;
- `tests/testthat/test-exal-stochastic-al-vb.R`;
- `tests/testthat/test-qdesn-vb-batching-modes.R`;
- `tests/testthat/test-static-beta-prior-rhs.R`.

## Economical Gate

Command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_posterior_as_prior_gate_20260528.R \
  --output-dir results/qdesn_vb_posterior_as_prior_gate_20260528
```

Gate setup:

- synthetic series length: `36`;
- seed: `20260528`;
- window size: `18`;
- origins: `24, 30, 36`;
- Q-DESN: `D = 1`, `n = 4`, `m = 1`, `washout = 3`;
- `max_iter = 8`.

Gate results:

| Check | Result |
| --- | ---: |
| Max beta-mean difference, exact chunked vs unchunked posterior-as-prior | `2.602e-10` |
| Max beta-covariance difference, exact chunked vs unchunked posterior-as-prior | `1.192e-10` |
| Max fitted prediction difference, exact chunked vs unchunked posterior-as-prior | `2.197e-12` |
| Forbidden exAL posterior-as-prior failed early | `TRUE` |
| Forbidden RHS/RHS_NS posterior-as-prior failed early | `TRUE` |
| Forbidden stochastic posterior-as-prior failed early | `TRUE` |

Ignored output directory:

```text
results/qdesn_vb_posterior_as_prior_gate_20260528/
```

## Decisions

- Posterior-as-prior is not exposed through `chunking`.
- Posterior-as-prior is not a warm start.
- The carried prior is a global beta-prior contribution and is not row-scaled.
- DESN features are rebuilt from the current origin's allowed window. Feature
  settings, not row-level design hashes, are validated across handoffs.
- Exact chunking remains full-window equivalent for the current
  posterior-as-prior target.
- Full beta covariance is required for posterior-as-prior because the handoff
  uses `inverse(V_beta)`. Diagonal covariance posterior-as-prior now fails early
  until that approximation has a separate contract.

## Remaining Risks

- RHS/RHS_NS posterior-as-prior requires a shrinkage-state transition contract.
- exAL posterior-as-prior requires q(s), q(v), sigma/gamma, xi, and metadata
  handoff decisions.
- Stochastic/hybrid posterior-as-prior needs separate approximate target labels
  and refresh semantics.
- Diagonal-covariance posterior-as-prior needs a contract for whether and how a
  diagonal covariance approximation may be used as the next Gaussian prior.
- Article GloFAS adapters need a no-leakage contract before any exposure.

## Recommended Next Stage

The online wrapper and diagonal covariance stages are now complete for their
narrow scopes. The next single implementation stage should be richer subset
stratification or low-rank covariance after diagonal covariance is exercised on
comparison examples. Do not start exAL approximate modes or RHS/RHS_NS
posterior-as-prior before their contracts are explicit.
