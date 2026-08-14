# Q-DESN Exact Chunked VB Implementation Blueprint

Date checked: 2026-05-27

Primary article repo:
`/data/jaguir26/local/src/Article-Q-DESN`

Article branch:
`application-ensemble-likelihood-redesign`

Primary implementation target for package work:
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

Target package branch:
`validation/shared-fitforecast-v2-1.0.0`

## A. Purpose and Scope

This document is the canonical tracked implementation blueprint for the exact
chunked, and later batched, VB work needed by the Q-DESN article/application
stack.

The ignored file `QDESN_Batched_VB_Implementation_Report.md` is background
only. It was useful as an initial proposal, but it was not generated from the
actual repo layout and should not be edited or treated as authoritative.

This blueprint is intentionally pre-implementation. It records the repo-aware
architecture, staging, helper seams, API defaults, tests, validation commands,
risks, rollback points, and human decisions needed before code changes begin.

Strict scope for the next implementation pass:

- Start with exact chunked full-data AL behavior.
- Do not implement stochastic mini-batching first.
- Do not change current public API behavior when chunking is absent or disabled.
- Do not replace the current package AL sigma path with a new inverse-gamma
  sigma update in the first stage.
- Do not row-batch or mini-batch RHS updates.
- Do not edit the ignored AI report.
- Do not edit the Overleaf/main worktree or older package worktrees.

## B. Current Implementation Map

### Repo and Worktree State

Article repo state checked before writing this document:

- Branch: `application-ensemble-likelihood-redesign`
- Upstream: `origin/application-ensemble-likelihood-redesign`
- Remote: `https://github.com/AntonioAPDL/Article-Q-DESN.git`
- HEAD: `6c2e8c7bc1186531400dcd8cea8401428660af1a`
- Dirty/untracked state: clean before this document was added
- Article stashes: none

Article worktrees checked:

- `/data/jaguir26/local/src/Article-Q-DESN`
  at `6c2e8c7` on `application-ensemble-likelihood-redesign`
- `/data/jaguir26/local/src/Article-Q-DESN__wt__exdqlm_0p5p0_article`
  at `8c8ddb3` on `work/article-exdqlm-0.5.0`
- `/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514`
  at `d27a6c6` on `main`

Shared validation package worktree state checked:

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Upstream: `origin/validation/shared-fitforecast-v2-1.0.0`
- HEAD: `d075941313186b15853e94c2a2cad7d0fec410d8`
- Dirty/untracked state: clean
- Stashes in the exdqlm repository: two unrelated historical stashes on older
  branches. They are not part of this article-repo documentation change.

The article application config
`application/config/glofas_latent_path_al_vb_dec25_main.yaml` pins the shared
validation package path, branch, commit, and minimum package version. It also
explicitly disallows the older `exdqlm__wt__qdesn_fitforecast_0p5p0` and
`exdqlm__wt__validation_fitforecast_0p5p0` paths for the Dec25 latent-path run.

### Article and Application Layer

The article repo owns the GloFAS application workflow and reproducibility
contract. The root `README.md`, `application/README.md`, and
`application/R/README.md` make the application repo responsible for launch
configuration, article-facing adapters, source separation, tests, and execution
gates, while keeping general Q-DESN engine work in the pinned exdqlm package
source.

Important article-side code paths:

- `application/R/engine_contract.R`
  validates the required Q-DESN package exports, package path, branch, commit,
  version, load mode, and disallowed path rules.
- `application/R/discrepancy_design.R`
  builds deterministic retrospective readout feature matrices and versioned
  discrepancy feature contracts.
- `application/R/latent_path_design.R`
  continues fixed DESN reservoirs through latent future reference paths and
  enforces no-leakage checks for post-cutoff observed USGS values.
- `application/R/fit_qdesn_latent_path.R`
  builds the article-side latent-path design, stacks historical USGS and GloFAS
  rows, constructs augmented beta/alpha discrepancy blocks, requires
  `inference_method = vb_ld` and `likelihood_family = al`, and calls the
  article-side AL-VB fitter.
- `application/R/latent_path_vb_al.R`
  implements the article-side latent-path AL-VB fitter. It supports AL only,
  block RHS beta/alpha priors, source-specific Y/G sigma states, latent future
  reference paths, streamed grouped future moments, dense debug equivalence
  paths, first-order Delta future updates, and grouped future objective logic.

The article-side latent-path fitter is not a thin call into the package static
readout engine. It solves the GloFAS ensemble-likelihood latent-path model with
fixed historical rows plus future latent-path row moments. Therefore, article
chunking should be staged after package exact AL equivalence is proven, and it
should initially chunk only fixed historical rows.

### Q-DESN Package Feature Construction and Readout

In the shared validation exdqlm worktree, `R/qdesn_vb.R` owns the direct
`qdesn_fit_vb()` pathway. It constructs fixed DESN feature maps first, then
optionally fits a static exAL/AL readout through `exal_ldvb_fit()`.

Confirmed behavior:

- DESN feature maps are fixed before posterior inference.
- Posterior inference is static Bayesian quantile regression over readout
  coefficients, likelihood parameters, local augmentation variables, and RHS
  shrinkage states.
- `qdesn_fit_vb()` builds a `vb_control` list and calls `exal_ldvb_fit()` when
  `fit_readout = TRUE`.
- The current direct `qdesn_fit_vb()` call path appears not to forward
  `vb_args$likelihood_family` or `vb_args$al_fixed_gamma` into
  `exal_ldvb_fit()`. This means direct Q-DESN wrapper-level AL claims need a
  small sidecar fix before Q-DESN-level AL chunking is claimed.

### `exal_ldvb_fit()`

In `R/exal_ldvb_fit.R`, `exal_ldvb_fit()` is the package wrapper around the
static LDVB engine. It accepts both list-style and flat control arguments. It
supports:

- `likelihood_family = c("exal", "al")`
- `vb_control`
- `prior_gamma`
- `prior_sigma`
- `beta_prior_obj`

The wrapper normalizes inputs and calls `exal_ldvb_engine()` with
`likelihood_family`.

### `exal_ldvb_engine()`

In `R/exal_ldvb_engine.R`, `exal_ldvb_engine()` owns the full static LDVB loop
for the package readout model.

The confirmed update order is:

1. Update `qbeta` from current `qv`, `qs`, and `xis`.
2. Update `qv`.
3. Update `qs`.
4. Accumulate sigma/gamma Laplace-Delta sufficient stats and update `qsiggam`.
5. Refresh `xis`.
6. Optionally run beta presteps used by RHS warmup controls.
7. Update RHS globally from the new `qbeta`.
8. Compute objective and traces.

This update order is part of the runtime contract for exact chunking. Exact
chunking must reproduce the same factors, traces, convergence behavior, and RHS
state, modulo floating point summation tolerance.

Even when `likelihood_family = "al"`, the current package engine still uses the
existing sigma-only Laplace-Delta machinery through:

- `qsiggam`
- fixed gamma logic
- `find_mode_ld()`
- `compute_xi_fast()`

The first exact chunked AL stage must preserve this machinery. It must not
replace AL sigma updates with a separate inverse-gamma sigma path.

### RHS Prior Updates

The package beta prior object interface is used by `exal_ldvb_engine()` through:

- `init(p)`
- `expected_prec(state, p)`
- `update(state, qbeta)`
- `elbo(state, qbeta)`

RHS state updates happen globally from the full `qbeta` after the beta update
and after likelihood local updates. Exact chunking may change how row-level
data statistics are accumulated, but it must not row-batch, mini-batch, or
subsample RHS updates. The `expected_prec()` and `update()` calls should see
the same inputs under chunked and unchunked exact modes.

### Existing Beta Natural Stats Helper

`R/exal_online_state.R` currently defines:

- `.exal_effective_barw_barm(y, xis, qv_m_inv, qs_m)`
- `.exal_beta_natural_stats(X, y, xis, qv_m_inv, qs_m, prec_diag = NULL)`

The existing `.exal_beta_natural_stats()` computes effective weights and data
stats, then optionally adds the prior precision into `P`. Stage 1 should
extract data-only helpers while preserving this wrapper's behavior exactly.

### Validation Interface

The shared validation study branch includes direct pipeline paths that call
`exal_fit()` and pass the validation-level likelihood family into the package
fit. The article Dec25 application config pins the shared validation package
worktree and requires R 4.6.0.

Validation vocabulary already uses batch/smoke/full launch terms. New VB
controls should therefore prefer the name `chunking` over `batch` to avoid
confusion with validation launch vocabulary.

### Posterior Prediction

Posterior prediction in the direct Q-DESN package path depends on fixed DESN
features and the fitted readout posterior. Exact chunking must be limited to
equivalent accumulation of full-data sufficient statistics and local updates.
It must not alter feature construction, reservoir continuation, posterior draw
semantics, or forecast interface schemas.

## C. Confirmed Target Architecture

The target architecture is:

- Package first.
- Shared validation exdqlm worktree first.
- Exact chunking first.
- AL likelihood first.
- API-preserving defaults.
- RHS global updates unchanged.
- exAL chunking later.
- Article-side latent-path chunking later.

The first implementation target should be:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

It should not be the older 0.5.0 Q-DESN worktree, because the article
application config currently pins the shared validation package path.

The first implementation should make full-data exact chunking a computational
strategy inside the existing engine path, not a new model, not a new public
framework, and not a stochastic optimizer.

## D. Ordered Implementation Stages

### Stage 0: Documentation and Helper Extraction Planning

Status: this document.

Goals:

- Record the implementation target, API surface, update order, and test gates.
- Keep ignored AI-generated proposal text out of tracked implementation state.
- Define helper names that support exact accumulation first and stochastic
  extensions later.
- Avoid code changes until this blueprint is reviewed.

### Stage 1: Beta Natural-Stat Helper Extraction and Equivalence Tests

Target worktree:
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

Goal:

Extract data-only beta statistic helpers from the existing
`.exal_beta_natural_stats()` implementation while preserving
`.exal_beta_natural_stats()` behavior exactly.

This stage should not change public APIs and should not add engine chunking yet.

Required equivalence:

- Existing `.exal_beta_natural_stats()` outputs are unchanged.
- Single full chunk equals current unchunked data stats.
- Multiple chunks sum to the same data stats as one full chunk.
- Prior precision is added only in the solve/wrapper layer, not inside
  chunk-local data accumulation.

### Stage 2: Exact Chunked AL Package Engine Path

Target files:

- `R/exal_ldvb_engine.R`
- `R/exal_online_state.R`
- possibly a small internal helper file if this matches package style

Goal:

Add an optional exact chunked path to the package LDVB engine for
`likelihood_family = "al"` while preserving the existing update order:

1. Update `qbeta` from current `qv`, `qs`, and `xis`.
2. Update `qv`.
3. Update `qs`.
4. Accumulate sigma/gamma LD stats and update `qsiggam`.
5. Refresh `xis`.
6. Run any existing beta presteps.
7. Update RHS globally from the new `qbeta`.
8. Compute objective and traces.

The chunked path should compute the same quantities as the unchunked path:

- beta precision and RHS data stats
- `xb`
- row quadratic terms `q_i`
- `qv` updates
- `qs` updates
- sigma/gamma LD sufficient stats `S1` through `S6`
- objective ingredients

The first AL chunked path must keep using the current `qsiggam` and
Laplace-Delta machinery. It must not replace the sigma block with a separate
inverse-gamma implementation.

### Stage 3: Control and Config Plumbing

Goal:

Add optional chunking controls while preserving current defaults and outputs
when chunking is absent or disabled.

The preferred control shape is:

```r
vb_control$chunking <- list(
  enabled = FALSE,
  mode = "exact",
  chunk_size = NULL,
  order = "sequential",
  trace = FALSE
)
```

`chunking` should be the user-facing name. Avoid `batch` in the public control
surface because validation launch configs already use batch/smoke/full
vocabulary.

This stage may add config normalization in `R/exal_inference_config.R` and
thread the control through existing validation config builders. It should still
default to disabled.

### Stage 4: Q-DESN Likelihood-Family Forwarding Sidecar

Target file:

- `R/qdesn_vb.R`

Goal:

Forward `vb_args$likelihood_family` and, if supported, `vb_args$al_fixed_gamma`
from direct `qdesn_fit_vb()` into `exal_ldvb_fit()`.

This can be done before or after Stage 2, but it should be a small sidecar
commit with focused tests before claiming direct Q-DESN-level AL chunking.

This stage should preserve defaults. If `vb_args$likelihood_family` is absent,
current behavior should remain unchanged.

### Stage 5: Article-Side Fixed-Row Chunking

Target article repo:
`/data/jaguir26/local/src/Article-Q-DESN`

Target file:

- `application/R/latent_path_vb_al.R`

Goal:

Only after package AL equivalence is proven, add exact chunking where useful to
the article-side latent-path AL-VB fitter.

Initial article chunking should target fixed historical rows only:

- fixed `H_fixed`
- fixed `z_fixed`
- fixed `source_fixed`
- source-specific historical Y/G contributions to theta precision/RHS
- source-specific sigma shape/rate contributions for fixed rows

It must preserve:

- streamed grouped future moments
- keyed GloFAS future row logic
- latent future path updates
- source-specific sigma logic
- block RHS beta/alpha updates
- no-leakage checks
- dense debug equivalence paths

Do not chunk future latent-path groups first. Those groups already have
specialized streamed grouped calculations and are more sensitive to row/key
alignment.

### Stage 6: Stochastic or Hybrid AL

Goal:

Consider stochastic mini-batches or hybrid SVI only after exact chunking passes
all equivalence and reproducibility gates.

This stage should introduce explicit stochastic controls, seed handling,
scaling rules, diagnostics, and validation experiments. It should not reuse the
exact `chunking` mode ambiguously.

### Stage 7: exAL Chunking

Goal:

Extend exact chunking to `likelihood_family = "exal"` only after AL chunking is
stable.

Reason:

exAL has more delicate `qs`, sigma/gamma LD, and xi behavior. The AL path
already uses the same sigma-only LD machinery with fixed gamma, which makes it
the safer first target for exact row-stat accumulation.

## E. Exact Files and Functions Likely to Edit Later

### Package Files in the Shared Validation Worktree

Likely package files:

- `R/exal_online_state.R`
  for beta data-stat helper extraction and compatibility wrapper preservation.
- `R/exal_ldvb_engine.R`
  for exact chunked engine branches and chunked local/stat accumulation.
- `R/exal_ldvb_fit.R`
  only if wrapper-level control validation or forwarding needs adjustment.
- `R/exal_inference_config.R`
  for `vb_control$chunking` normalization.
- `R/qdesn_vb.R`
  for direct `qdesn_fit_vb()` likelihood-family forwarding.

Likely package tests:

- `tests/testthat/test-exal-exact-chunking-stats.R`
- `tests/testthat/test-exal-likelihood-family-al.R`
- `tests/testthat/test-exal-inference-config.R`
- `tests/testthat/test-qdesn-vb-likelihood-family.R`
- existing RHS prior tests such as `tests/testthat/test-static-beta-prior-rhs.R`
  or a focused new RHS chunking test file.

### Article Files

Later article-side files:

- `application/R/latent_path_vb_al.R`
- `application/R/fit_qdesn_latent_path.R`
- `application/R/engine_contract.R`, only if a new package commit pin is needed.
- `application/config/glofas_latent_path_al_vb_dec25_main.yaml`, only if
  chunking config is intentionally exposed to the Dec25 run.

Later article tests:

- `application/tests/test_latent_path_design.R`
- `application/tests/test_vb_preparation.R`
- `application/tests/test_latent_path_recovery.R`
- possibly engine contract tests if a package pin changes.

### Validation Config and Runtime Files

Later validation files in the shared package worktree:

- validation config YAMLs under `config/validation/`
- pipeline config readers or launch scripts only after package defaults and
  unit tests pass
- storage-light and full-launch configs only when exact chunking needs runtime
  exposure

### Files and Branches Not to Touch Yet

Do not edit yet:

- `QDESN_Batched_VB_Implementation_Report.md`
- `/data/jaguir26/local/src/Article-Q-DESN__wt__main_overleaf_20260514`
- `/data/jaguir26/local/src/Article-Q-DESN__wt__exdqlm_0p5p0_article`
- `/data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0`
- `/data/jaguir26/local/src/exdqlm__wt__validation_fitforecast_0p5p0`
- package source files during the documentation-only commit that adds this
  blueprint

## F. Proposed Helper Functions and Signatures

Package helper extraction should keep names internal and preserve existing
behavior.

Proposed signatures:

```r
.exal_make_row_chunks <- function(n, chunk_size = NULL) {
  # returns a list of integer row indices
}

.exal_beta_data_stats <- function(X, y, xis, qv_m_inv, qs_m) {
  # returns list(barw, barm, S, g)
}

.exal_beta_data_stats_chunks <- function(X, y, xis, qv_m_inv, qs_m, chunks) {
  # returns list(barw, barm, S, g), with S and g accumulated across chunks
}

.exal_beta_solve_from_data_stats <- function(stats, prec_diag) {
  # returns list(P, h, sol), or a shape compatible with update_qbeta()
}

.exal_row_quad_form_chunks <- function(X, V, m = NULL, chunks) {
  # returns q_i = rowSums((X %*% V) * X), optionally xb = X %*% m
}

.exal_local_updates_chunks <- function(X, y, qbeta, qv, qs, xis, chunks) {
  # returns chunk-equivalent qv and qs update ingredients
}

.exal_sigmagam_stats_chunks <- function(X, y, qbeta, qv, qs, chunks) {
  # returns S1, S2, S3, S4, S5, S6 accumulated across chunks
}
```

Compatibility requirement:

```r
.exal_beta_natural_stats <- function(X, y, xis, qv_m_inv, qs_m, prec_diag = NULL) {
  # remains callable with the current signature and returns the same fields:
  # barw, barm, S, g, and if prec_diag is supplied, P, h, prec_diag.
}
```

Important design notes:

- Chunk helpers should accumulate data-only sufficient statistics.
- Prior precision belongs in the global solve/wrapper layer.
- `.exal_beta_natural_stats()` should be retained as the compatibility wrapper.
- Any Cholesky or positive-definite repair behavior should remain centralized in
  existing solve helpers such as `.solve_sympd()`.
- Chunk order should initially be deterministic sequential order.
- Parallel or shuffled chunk orders should be deferred until exact sequential
  equivalence is tested.

Later article-side helper candidates:

```r
app_latent_fixed_theta_stats_chunks <- function(row_moments, e_inv_v, sigma_state, constants, prior_state, chunks) {
  # fixed historical row contribution only
}

app_latent_fixed_sigma_stats_chunks <- function(row_moments, e_v, e_inv_v, constants, chunks) {
  # fixed historical source-specific sigma shape/rate contribution only
}
```

Article helpers should not own future grouped contributions at first.

## G. API and Config Additions

Preferred optional control surface:

```r
vb_control$chunking <- list(
  enabled = FALSE,
  mode = "exact",
  chunk_size = NULL,
  order = "sequential",
  trace = FALSE
)
```

Default behavior:

- If `vb_control$chunking` is absent, behavior must match current output.
- If `vb_control$chunking$enabled` is `FALSE`, behavior must match current
  output.
- If `mode = "exact"`, the engine must process all rows every iteration and
  only change how row-level statistics are accumulated.
- `chunk_size = NULL` should mean no chunking or one full chunk, depending on
  the implementation layer, but either choice must preserve current output.
- `order = "sequential"` is the only first-stage order.
- `trace = FALSE` avoids adding output noise by default.

Possible normalization point:

```r
exal_make_vb_control(
  ...,
  chunking = NULL
)
```

If `exal_make_vb_control()` gains a `chunking` argument, it should preserve all
existing arguments and default outputs when `chunking` is not supplied.

Possible validation YAML shape:

```yaml
inference:
  vb:
    chunking:
      enabled: false
      mode: exact
      chunk_size:
      order: sequential
      trace: false
```

Do not expose this YAML surface in launch configs until package-level unit
tests pass.

## H. Test Plan

Mandatory package tests before any stochastic work:

- `tests/testthat/test-exal-exact-chunking-stats.R`
  - `.exal_make_row_chunks()` covers full, size 1, uneven, exact divisor, and
    too-large chunk sizes.
  - `.exal_beta_data_stats()` matches the current one-shot calculation.
  - `.exal_beta_data_stats_chunks()` equals one-shot stats for multiple chunk
    sizes.
  - `.exal_beta_natural_stats()` remains backward compatible field-for-field.
  - Chunked beta solve matches unchunked beta solve under ridge precision.
  - Additivity holds for `S`, `g`, and effective row moment vectors.
- `tests/testthat/test-exal-likelihood-family-al.R`
  - AL unchunked behavior remains stable.
  - AL chunked exact fit equals AL unchunked fit for small deterministic data.
  - `qbeta$m`, `qbeta$V`, `qv`, `qs`, `qsiggam`, `xis`, traces, convergence
    flags, and iteration counts match within explicit tolerances.
  - The AL path continues to use the existing `qsiggam` machinery with fixed
    gamma.
- `tests/testthat/test-exal-inference-config.R`
  - `exal_make_vb_control()` defaults are unchanged.
  - `chunking` normalizes only when supplied.
  - Invalid chunking controls fail early with readable messages.
  - The term `chunking` is used rather than `batch`.
- `tests/testthat/test-qdesn-vb-likelihood-family.R`
  - Direct `qdesn_fit_vb()` forwards `vb_args$likelihood_family = "al"` to
    `exal_ldvb_fit()`.
  - Absent `likelihood_family` preserves current default behavior.
  - Optional `al_fixed_gamma` forwarding is covered if implemented.
- RHS equivalence test in an existing RHS prior test, likely
  `tests/testthat/test-static-beta-prior-rhs.R`, or a focused new test file.
  - Exact chunking leaves RHS `expected_prec()` and `update()` semantics global.
  - RHS state, traces, and tau update gates match unchunked exact mode.
  - RHS is not row-batched or subsampled.

Mandatory numerical safeguards:

- Cholesky and positive-definite repair paths still route through existing
  solver helpers.
- Chunked accumulation does not introduce asymmetric precision matrices.
- Single-row and highly collinear design cases are covered.
- Floating point tolerances are explicit and no looser than necessary.

Mandatory article tests before article-side chunking:

- `application/tests/test_latent_path_design.R`
  - fixed historical chunk contributions equal unchunked fixed contributions.
  - streamed grouped future moments remain equivalent to dense debug where
    existing tests already compare them.
  - no-leakage checks remain active.
- `application/tests/test_vb_preparation.R`
  - article config/vb args defaults remain unchanged when chunking is absent.
  - any later article chunking control defaults to disabled.
- `application/tests/test_latent_path_recovery.R`
  - synthetic recovery smoke test remains stable.
  - fixed seeds produce reproducible draws and summaries.

Tests required before stochastic or hybrid mini-batches:

- Exact chunking equivalence across several chunk sizes.
- Runtime and memory benchmark snapshots.
- Reproducibility under fixed seeds.
- Explicit stochastic scaling tests.
- Diagnostics for objective comparability or a documented reason when
  stochastic objectives are not directly comparable.
- No-leakage checks for latent-path future features.
- AL/exAL reduction checks if exAL code paths are touched.

## I. Validation Commands

Use R 4.6.0 for package and article validation.

Package-stage commands from the shared validation exdqlm worktree:

```bash
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
```

Broader package smoke after the focused package tests pass:

```bash
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'devtools::test(filter = "exal")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'devtools::test(filter = "qdesn-vb")'
```

Article-stage commands from the article repo, after any later article changes:

```bash
cd /data/jaguir26/local/src/Article-Q-DESN
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/test_vb_preparation.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/test_latent_path_design.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/test_latent_path_recovery.R
```

If the package commit pin changes, also run the article engine-contract checks
used by the application test suite.

## J. Risks and Rollback Points

### Helper Extraction

Risk:

- The compatibility wrapper changes field names, matrix symmetry, or prior
  precision placement.

Rollback:

- Revert only the helper extraction commit. The engine can continue using the
  original `.exal_beta_natural_stats()` implementation.

### Control-Surface Addition

Risk:

- `vb_control` normalization changes current defaults or collides with existing
  validation config vocabulary.

Rollback:

- Remove `chunking` normalization and keep internal helpers only. Public API
  remains unchanged.

### Engine Exact Chunking

Risk:

- Chunked accumulation changes update order, refreshes `xis` at the wrong time,
  changes RHS timing, or loosens numerical safeguards.

Rollback:

- Gate all chunked behavior behind `vb_control$chunking$enabled`. If problems
  appear, force the default and validation configs back to disabled while
  retaining helper tests.

### Q-DESN Likelihood Forwarding

Risk:

- Direct `qdesn_fit_vb()` behavior changes for users who relied on the current
  implicit exAL default.

Rollback:

- Keep forwarding only when `vb_args$likelihood_family` is explicitly supplied.
  If needed, revert the forwarding sidecar independently from chunking helpers.

### Article Fixed-Row Chunking

Risk:

- Historical fixed-row chunking accidentally changes future grouped row moments,
  source-specific sigma shape/rate calculations, or latent future no-leakage
  contracts.

Rollback:

- Keep article chunking behind a disabled default control.
- Revert article-side chunking without reverting package exact chunking.
- Preserve dense debug tests as the reference for future grouped equivalence.

### Target Drift

Risk:

- The article repo config pin and package worktree HEAD diverge during the
  implementation window.

Rollback:

- Stop implementation and re-run `engine_contract.R` checks before editing.
  Do not carry package changes into article config until the human confirms the
  new package commit pin.

## K. Human Decisions Before Implementation

The human should confirm:

- The shared validation exdqlm worktree
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
  remains the implementation target.
- The public control name should be `chunking`.
- The first public mode name should be `mode = "exact"`.
- Whether the `qdesn_fit_vb()` likelihood-family forwarding sidecar should be
  the first code commit or remain separate after helper extraction.
- Whether the initial chunking goal is memory reduction, equivalence
  infrastructure, or both.
- The first production chunk-size policy for validation configs, if any.
- Whether article config pins should be updated immediately after package-stage
  commits or only after full validation.
- Whether any stochastic or hybrid AL work is in scope before Dec25 application
  runs, or should be deferred entirely.

## L. Recommended First Coding Task

Extract package-level beta data-stat helpers in the shared validation exdqlm
worktree while preserving `.exal_beta_natural_stats()` behavior exactly, and
add additivity/equivalence tests. No public API changes in this first commit.
