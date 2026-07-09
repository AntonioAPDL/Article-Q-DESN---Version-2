# Q-DESN Rolling-Window and Posterior-as-Prior VB Derivations

Date: 2026-05-28

Status: rolling-window contract with first-stage posterior-as-prior and online
wrapper implementation. Independent rolling/expanding-window Q-DESN AL ridge
refits and AL ridge posterior-as-prior beta handoff are implemented through
`qdesn_vb_fit_rolling()`. Ordered-batch online posterior-as-prior handoff is
implemented through `qdesn_vb_fit_online()`. RHS/RHS_NS state handoff, exAL
rolling/online, stochastic/hybrid rolling/online, article adapters, and
low-level DESN reservoir state handoff remain gated.

## Purpose

Rolling-window and posterior-as-prior VB change the statistical target. They
must not be hidden under `chunking`, because chunking is reserved for changing
the way a fixed target is evaluated or approximated over rows.

## Scope

Implemented first stage:

- package univariate Q-DESN;
- AL likelihood;
- ridge beta prior;
- independent cold refits over explicit origin/window indices;
- posterior-as-prior beta Gaussian handoff over rolling or expanding origin
  sequences;
- ordered-batch online wrapper using the same AL ridge Gaussian beta handoff;
- unchunked or exact chunked full-window VB per origin.

Deferred:

- RHS/RHS_NS rolling shrinkage state handoff;
- article GloFAS latent-path rolling adapters;
- exAL rolling;
- stochastic/hybrid rolling windows;
- RHS/RHS_NS, exAL, stochastic/hybrid, and diagonal-covariance online handoff;
- low-level DESN reservoir state handoff across online batches;
- forgetting factors unless derived separately.

## Target Definition

For forecast origin `o`, define a training window:

```text
W_o = {i: start_o <= time_i <= end_o}
```

The implemented independent-refit target is the VB posterior using only rows in
`W_o`. Exact chunking inside an origin preserves that origin's full-window VB
target.

Posterior-as-prior adds an explicit global beta-prior contribution from origin
`o - 1`. The implemented first posterior-as-prior stage is AL + ridge only. It
maps the previous Gaussian beta posterior to the next origin's Gaussian beta
prior and still uses only rows in `W_o` for the current origin's likelihood.

This is not the full-series posterior unless `W_o` contains all available
training rows and no posterior-as-prior transition is used. It is therefore a
target-changing workflow, not an approximation to the full-series fit.

Implementation mapping:

- package file: `R/qdesn_vb_rolling_window.R`;
- exported APIs: `qdesn_vb_fit_rolling()` and `qdesn_vb_fit_online()`;
- package tests: `tests/testthat/test-qdesn-vb-rolling-window.R`,
  `tests/testthat/test-qdesn-vb-posterior-as-prior.R`, and
  `tests/testthat/test-qdesn-vb-online-wrapper.R`;
- article note:
  `docs/implementation_notes/qdesn_vb_rolling_window_stage_20260528.md`.

## Posterior-as-Prior Transition

A posterior-as-prior transition may map:

```text
q_{o-1}(beta) -> prior_o(beta)
```

For a Gaussian beta posterior:

```text
Lambda_prior_o = inverse(V_beta_{o-1})
g_prior_o = Lambda_prior_o m_beta_{o-1}
```

This is a target change. It is not just a warm start:

- warm start initializes the same target;
- posterior-as-prior changes the prior term for the next target.

For RHS/RHS_NS, posterior-as-prior is not immediately valid unless the global
shrinkage state transition is derived. First implementation should either:

- forbid RHS/RHS_NS posterior-as-prior; or
- carry the RHS/RHS_NS state with explicit metadata and validation.

## Leakage Rules

For each origin:

- all training row times must be `<= origin`;
- no response or diagnostic target after the origin may enter features;
- DESN state construction must use only allowed historical inputs;
- forecast evaluation rows must be separate from fit rows;
- source row IDs and time indices must be recorded.

Article GloFAS future latent paths have stricter no-leakage contracts and are
out of scope for the first package rolling implementation.

## Window Controls

Use explicit controls outside `chunking`. The first implemented package API is:

```r
qdesn_vb_fit_rolling(
  y,
  p0,
  origins,
  window_size = NULL,
  mode = c("rolling", "expanding"),
  desn_args = list(),
  vb_args = list(),
  posterior_as_prior = FALSE,
  keep_fits = TRUE
)
```

A future config-facing control can wrap that API as:

```r
rolling_window = list(
  enabled = TRUE,
  origin_col = "t",
  origins = NULL,
  window_size = 500,
  min_train = 100,
  step = 1,
  include_origin = TRUE
)
```

Posterior-as-prior controls:

```r
posterior_as_prior = list(
  enabled = TRUE,
  mode = "gaussian_beta",
  prior_strength = 1.0,
  jitter = 1e-8,
  validate_feature_settings = TRUE
)
```

Do not overload `vb_control$chunking`.

Current fail-early gates:

- `likelihood_family != "al"`;
- `beta_prior_type != "ridge"`;
- stochastic/hybrid chunking;
- diagonal beta covariance for posterior-as-prior/online handoff until the
  `inverse(V_beta)` contract is explicitly validated for that approximation;
- `vb_args$warm_start`, because warm starts are same-target initialization and
  posterior-as-prior is a target-changing prior handoff.

## Online Wrapper Controls

The first canonical Q-DESN online wrapper is:

```r
qdesn_vb_fit_online(
  y,
  p0,
  batch_ends = NULL,
  batch_size = NULL,
  desn_args = list(),
  vb_args = list(),
  posterior_as_prior = TRUE,
  keep_fits = TRUE,
  keep_states = TRUE
)
```

This wrapper processes ordered batches. The first batch uses the base ridge
prior. Later batches use the previous batch's beta posterior as a Gaussian beta
prior. It records batch boundaries, source row IDs, design hashes, feature
setting hashes, package SHA, covariance form, and input/output handoff hashes.

This is not the same as the existing `exal_online_*` helpers. It does not carry
DESN reservoir states across batches. Q-DESN features are rebuilt inside each
batch using only that batch's allowed responses. A low-level streaming DESN
state handoff remains a separate gated design.

## Row-Additive and Global Terms

Within a window, AL/exAL data terms are row-additive exactly as in full-data
VB. Prior terms are global.

For posterior-as-prior:

- the carried beta precision is a global prior contribution;
- it is not scaled by row count;
- it must be added once to the window data stats.

RHS/RHS_NS shrinkage remains global within each window.

## Online VB Files

Existing package files to audit before implementation:

- `R/exal_online_state.R`
- `R/exal_online_step.R`
- `R/exal_online_vbld.R`
- `R/exal_online_stage0.R`

Current status:

- `qdesn_vb_fit_online()` is implemented for package Q-DESN AL + ridge ordered
  batch handoff, full covariance, and unchunked/exact chunked per-batch VB.
- Existing `exal_online_*` helpers remain static/readout exAL VB-LD helpers.
  They are audited separately and are not Q-DESN online wrapper APIs.

## Implementation Mapping

Implemented package files:

- `R/qdesn_vb_rolling_window.R` for explicit rolling/expanding window
  construction, independent Q-DESN VB refits, AL ridge posterior-as-prior state
  handoff, and ordered-batch Q-DESN online wrapper handoff;
- `R/priors_beta.R`, `R/exal_online_state.R`, and `R/exal_ldvb_engine.R` for
  the Gaussian beta prior natural-vector hook used by posterior-as-prior;
- `NAMESPACE` export for `qdesn_vb_fit_rolling()`;
- `NAMESPACE` export for `qdesn_vb_fit_online()`;
- `tests/testthat/test-qdesn-vb-rolling-window.R`;
- `tests/testthat/test-qdesn-vb-posterior-as-prior.R`;
- `tests/testthat/test-qdesn-vb-online-wrapper.R`;
- `tests/testthat/test-exal-beta-prior-natural.R`;
- `scripts/run_qdesn_vb_posterior_as_prior_gate_20260528.R`.

Posterior-as-prior deliberately does not reuse `vb_args$warm_start`. Warm starts
initialize the same target; posterior-as-prior changes the next origin's prior
term and records separate state-handoff hashes.

## Tests

Implemented package tests:

- window index construction and reproducibility;
- no future leakage in row selection;
- exact chunking inside a window matches unchunked window fit;
- AL ridge posterior-as-prior handoff metadata is present and reproducible;
- posterior-as-prior exact chunking matches unchunked posterior-as-prior per
  origin;
- rolling and expanding posterior-as-prior origin sequences run;
- unsupported exAL, RHS/RHS_NS, stochastic/hybrid, and warm-start paths fail
  early.
- one-batch Q-DESN online wrapper equals ordinary AL ridge fit;
- two-batch Q-DESN online wrapper records posterior-as-prior handoff metadata;
- exact chunked Q-DESN online wrapper matches unchunked online wrapper;
- Q-DESN online wrapper records batch boundaries and no-future-leakage flags;
- unsupported exAL, RHS/RHS_NS, stochastic/hybrid, warm-start, disabled
  posterior-as-prior, and diagonal-covariance online paths fail early.

Future package tests:

- unsupported RHS/RHS_NS posterior-as-prior fails early until derived;
- serialization round trip for carried state.

## Economical Gates

Package:

- synthetic time-indexed dataset with known windows;
- `scripts/run_qdesn_vb_posterior_as_prior_gate_20260528.R`;
- TT500 source subset with small rolling origins;
- exact same-window cold/warm equivalence gate.

Article:

- no article rolling adapter initially;
- do not repin or expose article configs until package gates pass.

## Stop Conditions

Stop if:

- row indices can include future data;
- posterior-as-prior target is mislabeled as warm start;
- RHS/RHS_NS state handoff lacks a derivation;
- online helper behavior is confused with the explicit Q-DESN online wrapper
  target;
- exact chunking within a window fails equivalence.
