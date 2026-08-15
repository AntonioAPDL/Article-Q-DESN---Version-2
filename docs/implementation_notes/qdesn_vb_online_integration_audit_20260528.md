# Q-DESN VB Online Integration Audit

Date: 2026-05-28

## Purpose

This note documents the online VB-LD audit/readiness stage. The stage does not
add a new Q-DESN inference algorithm. It verifies the existing package-level
static/readout online exAL VB-LD helpers enough to keep them from being
misclassified in comparison tables.

The original result was intentionally conservative: online exAL VB-LD was
tested as a static/readout helper, with no canonical Q-DESN online wrapper and
no article GloFAS online adapter.

Follow-up status: package commit `b7369b9` later added
`qdesn_vb_fit_online()` as the first canonical Q-DESN AL ridge ordered-batch
posterior-as-prior wrapper. That wrapper is documented separately in
`qdesn_vb_online_wrapper_al_ridge_stage_20260528.md`. The exAL VB-LD helper
audited here remains a separate static/readout helper, not the Q-DESN online
wrapper.

## Package Commit

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- commit: `36428a8 Add online VB-LD readiness tests`

## Existing Online Surfaces

The package already exported these online helpers:

- `exal_online_init()`;
- `exal_online_step()`;
- `exal_online_run()`;
- `exal_online_fit()`;
- `exal_online_predict_quantile()`;
- `exal_online_health_check()`;
- `exal_online_trace_diagnostics()`;
- `exal_online_stage0_benchmark()`;
- `exal_online_stage0_write_artifacts()`;
- `exal_make_vb_online_control()`.

These are static/readout online exAL VB-LD helpers. They are not exact chunking,
not stochastic AL, and not posterior-as-prior Q-DESN rolling fits.

## Implemented Scope

Implemented in this stage:

- readiness tests for disabled pass-through behavior;
- readiness tests for RDS serialization and resume;
- readiness tests for one-row streaming behavior;
- readiness tests for fixed-seed reproducibility;
- readiness tests for order sensitivity;
- explicit fail-early guard for enabled `likelihood_family = "al"`.

Still gated for the audited `exal_online_*` helper surface:

- AL online VB-LD;
- online RHS/RHS_NS semantics beyond existing helper behavior;
- online article GloFAS adapters;
- online comparison harness promotion;
- online no-leakage source-window gates.

Implemented later outside this audit:

- canonical Q-DESN AL ridge ordered-batch online wrapper
  `qdesn_vb_fit_online()`, using posterior-as-prior Gaussian beta handoff and
  full covariance only.

## Contract

When `control$enabled = FALSE`, `exal_online_fit()` must preserve the normal
batch `exal_ldvb_fit()` behavior and only annotate `fit$misc$online` as
disabled.

When `control$enabled = TRUE`, the online helper:

1. runs batch exAL LDVB on an initialization prefix;
2. streams remaining static readout rows in order;
3. updates online beta natural statistics, local moments, and scheduled refresh
   hooks;
4. records diagnostics in `fit$misc$online`.

The mode is order-sensitive by design. It changes the workflow target and
should not be described as full-data CAVI or exact chunking.

Enabled AL online mode now fails early because this module is the exAL VB-LD
online updater with `q(s)` and sigma/gamma machinery. The package AL stochastic
and hybrid modes remain separate.

## Tests

Package test file:

```text
tests/testthat/test-exal-online-vbld.R
```

Focused regression set after implementation:

- `test-exal-online-vbld.R`: 36 pass;
- `test-exal-subset-fit.R`: 30 pass;
- `test-exal-beta-covariance-approx.R`: 36 pass;
- `test-exal-inference-config.R`: 203 pass;
- `test-exal-exact-chunking-stats.R`: 38 pass;
- `test-exal-stochastic-al-vb.R`: 38 pass;
- `test-qdesn-vb-batching-modes.R`: 28 pass;
- `test-static-beta-prior-rhs.R`: 110 pass;
- total: 519 pass, 0 fail.

Covered checks:

- disabled online fit matches direct batch fit;
- online state survives `saveRDS()` / `readRDS()` and resumes for one row;
- one-row online wrapper records `t_stream = 1` and trace metadata;
- stage-0 benchmark is reproducible under a fixed seed;
- forward and reversed streaming orders produce different, finite states;
- enabled AL online mode fails early;
- disabled AL pass-through still works.

## Classification

For comparison-readiness tables:

- static/readout exAL online VB-LD: partial, tested helper;
- Q-DESN AL ridge ordered-batch online wrapper: implemented and
  target-changing;
- article online mode: gated.

Do not confuse these two online surfaces. The implemented Q-DESN wrapper records
feature settings, design hashes, batch metadata, state hashes, one-batch
ordinary-fit equivalence, exact chunking equivalence, and no-leakage checks.
The static/readout exAL helper remains partial and should not be promoted as a
Q-DESN comparison mode.

## Recommended Next Stage

The next single implementation stage should be chosen deliberately:

- RHS/RHS_NS diagonal covariance if shrinkage second-moment semantics are the
  priority;
- stratified subset CAVI if cheap screening designs are the priority;
- richer subset or low-rank covariance stages if they are the next comparison
  priority.

Stochastic/hybrid exAL remains forbidden until the exAL approximate derivation
is implemented and tested.
