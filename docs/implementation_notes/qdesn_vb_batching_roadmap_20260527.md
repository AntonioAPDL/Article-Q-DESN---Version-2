# Q-DESN VB Batching Roadmap and Resume Plan

Date: 2026-05-27

## Purpose

This is the canonical resume plan for the Q-DESN VB batching work after the
exact chunked implementation, validation pass, full-spec pilot, and economical
tiny D1N5 pilot.

The mathematical source of truth is:

- `docs/implementation_notes/qdesn_vb_batching_derivations_20260527.md`

The exact chunked implementation record is:

- `docs/implementation_notes/qdesn_exact_chunked_vb_blueprint_20260527.md`
- `docs/implementation_notes/qdesn_exact_chunked_vb_implementation_log_20260527.md`
- `docs/implementation_notes/qdesn_exact_chunked_vb_validation_20260527.md`
- `docs/implementation_notes/qdesn_exact_chunked_vb_fullspec_pilot_20260527.md`
- `docs/implementation_notes/qdesn_exact_chunked_vb_tiny_d1n5_pilot_20260527.md`

This roadmap replaces the ad hoc AI-generated proposal as the operational
resume point. The ignored report
`QDESN_Batched_VB_Implementation_Report.md` remains background only.

## Current Checkpoint

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- comparison-readiness parent:
  `f271463 Document stochastic AL VB batching status`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- current pushed comparison checkpoint:
  `37bdd3a Add Q-DESN VB batching comparison harness`

Known unrelated local work:

- PriceFM files may be dirty or untracked in the article worktree.
- Leave PriceFM work untouched during Q-DESN VB batching work.

## Implemented Baseline

Exact chunking is implemented, tested, documented, and pushed for:

- package static AL LDVB
- package static exAL LDVB
- univariate Q-DESN AL VB through `qdesn_fit_vb()`
- univariate Q-DESN exAL VB through `qdesn_fit_vb()`
- article GloFAS latent-path AL-VB for fixed historical rows

Exact chunking is full-data VB. It is not stochastic, and it remains the
reference baseline for all later approximate methods.

Stochastic mini-batch AL VB is now implemented for:

- package static AL LDVB
- univariate Q-DESN AL VB through `qdesn_fit_vb()`

Stochastic AL and hybrid AL are approximate, not full-data equivalent, except
that hybrid with a full refresh every iteration is tested to recover exact AL.
Stochastic/hybrid exAL, variance-reduced SVI, streaming/posterior-as-prior VB,
article approximate batching, and multivariate Q-DESN batching are not
implemented unless a later commit explicitly says so.

## Economical Pilot Gate

The economical article-side gate is the tiny D1N5 real-data pair:

- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`
- `application/config/model_grid_latent_path_al_vb_dec25_tiny_d1n5_pilot.csv`

This gate uses the authoritative Dec. 25 GloFAS/USGS application input bundle,
but limits the design to:

- `D = 1`
- `n = 5`
- `m = 5`
- limited history, horizons, ensemble members, lag windows, draws, and VB
  iterations

The original 2026-05-27 run on exact-chunking package commit `73c043f`
passed:

- unchunked wall time: 18.61 s
- exact-chunked wall time: 18.38 s
- max RSS: about 140 MB for each run
- fixed historical rows: 670
- stacked rows: 676
- augmented features: 12
- max fitted-state gate difference: `1.71951342053944e-12`
- tolerance: `1e-7`

Use this tiny pair as the repeated real-data article-side regression gate. It
does not replace the manuscript-scale gate.

After package stochastic AL commit `246554e`, the tiny pair was repinned to
the full package SHA `246554eea52cc5c2f1e5f4f515f7897ae4075b86` and rerun.
That rerun also passed:

- unchunked wall time: 19.33 s
- exact-chunked wall time: 18.11 s
- max RSS: about 140 MB for each run
- max fitted-state gate difference: `1.71951342053944e-12`
- tolerance: `1e-7`

The article main and exact-chunked smoke configs are also repinned to that
package SHA so the application source-policy gate matches the current shared
validation package branch. They remain article-side AL-VB configs; stochastic
controls are not exposed in article GloFAS configs.

After package comparison-harness commit `37bdd3a`, the tiny pair was repinned
to `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3` and rerun. That rerun also
passed:

- unchunked wall time: 20.48 s
- exact-chunked wall time: 21.31 s
- max RSS: about 140 MB for each run
- max fitted-state gate difference: `1.71951342053944e-12`
- tolerance: `1e-7`

The comparison-readiness layer is now documented in:

- `docs/implementation_notes/qdesn_vb_method_availability_20260528.md`
- `docs/implementation_notes/qdesn_vb_comparison_plan_20260528.md`
- `docs/implementation_notes/qdesn_vb_comparison_results_20260528.md`

## Full-Spec Pilot Status

The full-spec Dec. 25 pilot is recorded in:

- `docs/implementation_notes/qdesn_exact_chunked_vb_fullspec_pilot_20260527.md`

Result:

- unchunked full-spec pilot completed
- exact-chunked full-spec pilot failed before writing a fitted state
- no fitted-state equivalence comparison was possible
- main Dec. 25 config remains unchunked

This does not block package-level stochastic AL development. It does block any
claim that article full-spec exact chunking is ready for the main Dec. 25 run.

## Method Status Matrix

Status labels:

- `implemented`: coded, tested, and documented at current checkpoint
- `implement now`: next implementation target
- `safe next`: next after the current target passes
- `needs theory`: requires a complete derivation or runtime contract first
- `defer`: intentionally later
- `not applicable`: not meaningful for that method

| Method family | Unchunked full-data VB | Exact chunked full-data VB | Stochastic mini-batch VB | Hybrid SVI with full refresh | Variance-reduced SVI | Streaming/posterior-as-prior VB |
| --- | --- | --- | --- | --- | --- | --- |
| package static AL LDVB | implemented | implemented | implemented | implemented | defer | needs theory |
| package static exAL LDVB | implemented | implemented | defer | defer | defer | needs theory |
| univariate Q-DESN AL VB | implemented | implemented | implemented | implemented | defer | needs theory |
| univariate Q-DESN exAL VB | implemented | implemented | defer | defer | defer | needs theory |
| article GloFAS latent-path AL-VB | implemented | implemented | defer | defer | defer | needs theory |
| future multivariate Q-DESN | needs theory | needs theory | needs theory | needs theory | needs theory | needs theory |

## Confirmed Architecture

The implemented approximate-batching architecture is package-first and
AL-first:

1. Implement stochastic mini-batch AL only for the package static/readout path.
2. Keep exact chunking unchanged and full-data equivalent.
3. Keep unchunked defaults unchanged.
4. Allow stochastic mode only for `likelihood_family = "al"`.
5. Make stochastic mode fail early for `likelihood_family = "exal"`.
6. Keep RHS shrinkage global; never row-batch RHS.
7. Preserve the current AL sigma path through the existing qsiggam,
   fixed-gamma, Laplace-Delta machinery.
8. Route stochastic AL through Q-DESN only after package static AL stochastic
   tests pass.
9. Do not expose stochastic controls in article GloFAS configs in this pass.
10. Use the tiny D1N5 pair only as an article-side exact-chunking regression
    gate when package commits are repinned into article configs.

## Stochastic Package AL Contract

The stochastic package AL implementation must follow the derivation note.

Target:

- approximate the same full-data AL LDVB fixed point as unchunked and exact
  chunked package AL
- label all stochastic results approximate

Batching:

- support reproducible mini-batches with an explicit seed
- default to randomized or shuffled order for stochastic approximation
- define epoch semantics in the control object or trace

Scaling:

- scale data natural statistics by `n / batch_size`
- do not scale prior precision
- do not scale RHS states as row quantities

Local variables:

- store local moments for all rows
- refresh only batch rows during stochastic steps
- retain stale moments for unseen rows, with this behavior documented
- initialize all local moments deterministically before stochastic iterations

Beta update:

- maintain damped data natural statistics
- use a Robbins-Monro learning-rate schedule such as
  `rho_t = max(rho_min, (t0 + t)^(-kappa))`
- reject invalid `t0`, `kappa`, and `rho_min`

Sigma update:

- first version should use periodic full sigma refreshes
- keep gamma fixed in AL mode
- do not implement stochastic sigma stats until a separate testable contract is
  added

RHS:

- update RHS globally from current `qbeta`
- first version should update RHS only on full refresh iterations or on an
  explicit global cadence
- never update RHS from a row batch

Diagnostics:

- distinguish noisy stochastic surrogate traces from full-data ELBO refreshes
- include finite-state checks
- optionally trace batch ids, refresh iterations, and learning rates
- stop immediately if any state becomes non-finite or if exAL stochastic mode
  runs

## Control Surface

Exact mode remains:

```r
chunking = list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 512,
  order = "sequential",
  trace = FALSE
)
```

Planned stochastic controls:

```r
chunking = list(
  enabled = TRUE,
  mode = "stochastic",
  chunk_size = 512,
  order = "random",
  seed = 20260527,
  learning_rate = list(
    schedule = "robbins_monro",
    t0 = 10,
    kappa = 0.75,
    rho_min = 1.0e-4
  ),
  refresh = list(
    full_every = 20,
    objective_every = 20,
    sigma_every = 5,
    rhs_every = 20,
    local_every = 20
  ),
  diagnostics = list(
    trace = TRUE,
    store_batch_ids = FALSE,
    check_finite_every = 1
  )
)
```

Names may be adjusted to match package style, but the semantics above should
not change without updating the derivation note first.

## Ordered Resume Plan

### Stage 0: Synchronize and Verify

Before coding:

1. Fetch article and package repos.
2. Verify branch, upstream, HEAD, dirty state, stashes, and latest origin state.
3. Confirm no exact D1N5 pilot process is still running.
4. Leave PriceFM work untouched.
5. Inspect the derivation note and this roadmap.

### Stage 1: Package Stochastic Controls and Unit Helpers

Status: implemented and pushed in package commit
`c321b3b Add stochastic AL VB batching controls`.

Repo:

- `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

Likely files:

- `R/exal_inference_config.R`
- `R/exal_online_state.R`
- `R/exal_online_step.R`
- tests under `tests/testthat/`

Add or validate helpers:

- `.exal_batch_sampler_init()`
- `.exal_batch_sampler_next()`
- `.exal_learning_rate()`
- `.exal_stochastic_beta_stats()`

Tests:

- control normalization
- invalid mode/control failures
- sampler reproducibility
- learning-rate monotonicity and lower bound
- exact chunking controls unchanged
- defaults unchanged

Commit only after focused tests pass.

### Stage 2: Package Static AL Stochastic Engine

Status: implemented and pushed in package commit
`246554e Implement stochastic AL VB batching`.

Repo:

- package repo only

Likely files:

- `R/exal_ldvb_engine.R`
- `R/exal_online_state.R`
- `R/exal_online_step.R`
- `R/exal_inference_config.R`

Implementation:

- branch inside the existing engine path for `chunking$mode == "stochastic"`
- allow only `likelihood_family = "al"`
- fail early for `likelihood_family = "exal"`
- initialize full local state deterministically
- update batch local variables
- accumulate scaled beta data stats
- damp beta data stats
- solve beta with unscaled prior precision
- refresh sigma on a full-data cadence through the existing LD path
- refresh RHS globally on an explicit cadence
- write traces that clearly say stochastic/approximate

Tests:

- finite static AL stochastic fit
- fixed-seed reproducibility
- broad closeness to exact AL on easy synthetic data
- no false equivalence claim
- RHS finite and globally updated
- exAL stochastic fails clearly
- unchunked and exact chunked regressions still pass

Commit only after focused package tests pass.

### Stage 3: Q-DESN AL Routing

Status: implemented and pushed in package commit
`246554e Implement stochastic AL VB batching`.

Repo:

- package repo

Likely files:

- `R/qdesn_vb.R`
- `tests/testthat/test-qdesn-vb-batching-modes.R`

Requirements:

- `qdesn_fit_vb(... likelihood_family = "al", chunking$mode = "stochastic")`
  works on a simple synthetic/readout case
- fixed seed reproducibility
- finite approximate fitted state
- exact chunking unchanged
- defaults unchanged
- Q-DESN exAL stochastic fails clearly

Commit only after package static AL and Q-DESN AL routing tests pass.

### Stage 4: Package Example Comparison

Status: implemented in
`docs/implementation_notes/qdesn_vb_stochastic_al_package_example_20260527.md`
and generalized by package script
`scripts/run_qdesn_vb_batching_comparison_20260528.R` at package commit
`37bdd3a`.

Repo:

- package repo, or package docs if the example note belongs there

Compare:

- AL unchunked
- AL exact chunked
- AL stochastic mini-batch

Optional:

- exAL unchunked
- exAL exact chunked

Do not include exAL stochastic unless it is separately implemented and tested.

Record:

- data-generating setup
- seed
- controls
- fitted-state distances
- runtime
- reproducibility
- limitations

### Stage 5: Article Documentation and Tiny Gate

Status: implemented after package commit `246554e` and rerun after comparison
harness commit `37bdd3a`. The tiny D1N5 configs are repinned to
`37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3` and passed the economical
real-data exact-chunking gate. Article GloFAS stochastic controls remain
unexposed.

Repo:

- article repo

Do not expose article stochastic controls.

If the article repo is repinned to a new package commit, use the tiny D1N5
pilot pair first:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml \
  --label tiny_d1n5_unchunked \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527

/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml \
  --label tiny_d1n5_exact_chunked \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode compare \
  --left_result application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked__fit_state.rds \
  --right_result application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked__fit_state.rds \
  --left_time_log application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked.time.log \
  --right_time_log application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked.time.log \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527 \
  --comparison_prefix paired_tiny_d1n5_exact_chunked \
  --comparison_title 'Exact Chunked VB Tiny D1N5 Pilot Comparison' \
  --tolerance 1e-7
```

Then run:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
git diff --check
```

Only after the tiny gate passes should any article config repinning be committed.
The main Dec. 25 config should remain unchunked unless a production-scale gate
passes.

### Stage 6: Hybrid AL

Status: implemented for package static/readout and univariate Q-DESN AL in
exdqlm commit `685d2f5fcf789dd65495223f6b6f2dfa59a5cf22`.
The source comparison harness includes hybrid AL as of package commit
`c51e9da4508f6fb89a73f8b78e08f9d80604e11a`.

First version:

- stochastic steps between full refreshes
- full refresh reanchors beta stats, local moments, sigma, RHS, and optional
  full-data objective
- `full_every = 1` should reduce to exact full-data behavior within tolerance,
  and is covered by package tests

### Stage 7: Deferred Methods

Do not implement until separately authorized and derived:

- approximate exAL batching
- article GloFAS stochastic/hybrid batching
- variance-reduced AL
- streaming/posterior-as-prior VB
- multivariate Q-DESN batching

## Mandatory Package Test Commands

Run focused package tests with R 4.6.0:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
```

Add and run, once implemented:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-batching-controls.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-stochastic-al-vb.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-hybrid-al-vb.R")'

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
```

## Stop Gates

Stop and report instead of continuing if:

- exact chunking equivalence breaks
- unchunked defaults change
- stochastic AL is unstable on simple synthetic tests
- RHS update semantics become ambiguous
- exAL stochastic mode runs
- article tests fail
- tiny D1N5 exact gate fails after package repinning
- implementation deviates from the derivation note without first updating the
  derivation note
- changes require broad unrelated refactors
- any process hangs or threatens unrelated validation jobs
- PriceFM work would need to be edited or staged

## Recommended Next Coding Task

After package hybrid AL and the tiny D1N5 article repin gate, the next coding
task is:

> Implement rolling-window/posterior-as-prior Q-DESN VB only after the
> warm-start handoff contract is re-reviewed against the new hybrid controls,
> keeping exAL approximate, article approximate, covariance approximations,
> subset targets, variance-reduced SVI, divide-and-combine, coresets, and
> multivariate modes gated.
