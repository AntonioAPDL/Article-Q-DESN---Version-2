# Q-DESN Exact Chunked VB Implementation Log

Date: 2026-05-27

This log records the implementation pass that followed
`docs/implementation_notes/qdesn_exact_chunked_vb_blueprint_20260527.md`.

## Scope Implemented

Implemented in the shared validation exdqlm worktree:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

Branch:

`validation/shared-fitforecast-v2-1.0.0`

Package commit:

`5c868f897984638a82868549c14dbc35ae4dcea0`

Package changes:

- Added exact row chunk helpers for beta data stats, row quadratic forms, local
  q(v)/q(s) updates, and sigma/gamma LD sufficient stats.
- Preserved `.exal_beta_natural_stats()` as the compatibility wrapper.
- Added optional `vb_control$chunking` normalization with the default disabled.
- Added exact chunked engine execution through the existing
  `exal_ldvb_engine()` update order.
- Kept RHS updates global and unchanged.
- Kept AL on the existing `qsiggam`, fixed-gamma, `find_mode_ld()`, and
  `compute_xi_fast()` path.
- Forwarded explicit `vb_args$likelihood_family` and `vb_args$al_fixed_gamma`
  from direct `qdesn_fit_vb()` into `exal_ldvb_fit()`.
- Covered exact chunking for both AL and exAL with package tests.

Implemented in the article repo:

`/data/jaguir26/local/src/Article-Q-DESN`

Branch:

`application-ensemble-likelihood-redesign`

Article changes:

- Added optional latent-path AL-VB chunking controls.
- Chunked only fixed historical row contributions to theta precision/RHS.
- Chunked only fixed historical source-specific sigma shape/rate
  contributions.
- Preserved streamed grouped future moments, keyed GloFAS future rows, latent
  future path updates, no-leakage checks, and block RHS behavior.
- Left default article behavior unchanged when `chunking` is absent.

## Stage Status

- Stage 0: Complete. Blueprint and implementation log are tracked.
- Stage 1: Complete. Beta data-stat helpers extracted and tested.
- Stage 2: Complete. Exact chunked AL package engine path implemented.
- Stage 3: Complete. Optional `vb_control$chunking` config plumbing added.
- Stage 4: Complete. Direct Q-DESN likelihood-family forwarding added.
- Stage 5: Complete. Article-side fixed historical row chunking added.
- Stage 6: Explicitly gated. Stochastic/hybrid AL is not enabled in this
  implementation because the repo does not yet define a validated stochastic
  scaling, objective, seed, or RHS contract. Non-exact chunking modes fail
  early.
- Stage 7: Complete for exact exAL chunking. The same exact row-stat helpers
  are covered by exAL equivalence tests.

## Validation Results

Package focused tests run with R 4.6.0:

```bash
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
```

Focused package result summary:

- `test-exal-exact-chunking-stats.R`: passed.
- `test-exal-likelihood-family-al.R`: passed.
- `test-exal-inference-config.R`: passed.
- `test-qdesn-vb-likelihood-family.R`: passed.
- `test-static-beta-prior-rhs.R`: passed, 110 checks.

Broader package filtered tests:

```bash
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_dir("tests/testthat", filter = "qdesn-vb|qdesn.*likelihood")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_dir("tests/testthat", filter = "exal")'
```

Broader package result summary:

- `qdesn-vb|qdesn.*likelihood`: passed, 6 checks.
- `exal`: passed, 805 checks.

Article validation run with R 4.6.0:

```bash
cd /data/jaguir26/local/src/Article-Q-DESN
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
```

Article result summary:

- Full application test harness passed.

Formatting checks:

- `git diff --check` passed in the package worktree.
- `git diff --check` passed in the article repo.

Note:

- `devtools::test()` was not available because `devtools` is not installed in
  the R 4.6.0 environment. Equivalent `testthat::test_dir()` commands were run
  instead.

## Stochastic/Hybrid Gate

The stochastic or hybrid AL stage remains intentionally disabled. The exact
chunking implementation now provides the needed helper surface, but stochastic
mini-batching still needs separate scientific decisions and tests for:

- row-subsample scaling of beta natural stats
- local q(v)/q(s) state refresh policy for rows not in a mini-batch
- sigma/gamma LD statistic scaling
- objective trace interpretation
- fixed-seed reproducibility
- RHS update cadence and whether RHS should use exact or approximate qbeta

Until those decisions are made, `mode = "exact"` is the only supported
chunking mode.
