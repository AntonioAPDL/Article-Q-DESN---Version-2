# Q-DESN Exact Chunked VB Validation and Activation Note

Date: 2026-05-27

## Scope

This note records the validation pass after the exact chunked VB implementation
documented in
`docs/implementation_notes/qdesn_exact_chunked_vb_blueprint_20260527.md` and
`docs/implementation_notes/qdesn_exact_chunked_vb_implementation_log_20260527.md`.
The production target remains exact full-data chunking. Stochastic or hybrid
mini-batch VB remains unimplemented and gated; non-`exact` chunking modes must
continue to fail early.

The Overleaf/main worktree was not edited.

## Repository State

Article repo:

- Path: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Starting HEAD: `1d885a70189bfdd700595ff47435f1b9b8d495a2`
- Remote: `origin https://github.com/AntonioAPDL/Article-Q-DESN.git`
- Upstream: `origin/application-ensemble-likelihood-redesign`
- State before article edits: clean and synced.

Package/shared validation repo:

- Path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Starting HEAD: `5c868f897984638a82868549c14dbc35ae4dcea0`
- New package HEAD after this pass:
  `73c043f0436b508808366f312350fd44c2d06771`
- Remote: `origin git@github.com:AntonioAPDL/exdqlm.git`
- Upstream: `origin/validation/shared-fitforecast-v2-1.0.0`
- Package branch is clean and synced after push.

Package stashes exist on other branches and were left untouched:

- `stash@{0}` on `feature/qdesn-mcmc-alternative`
- `stash@{1}` on `jaguir26/dqlm-conjugacy-cavi-gibbs`

## Review Findings and Fixes

The existing exact chunked implementation matched the intended invariants:

- Exact chunking is full-data CAVI, not stochastic approximation.
- Defaults remain unchunked when chunking is absent.
- `enabled = FALSE` is equivalent to no chunking.
- Only `mode = "exact"` is supported.
- RHS updates remain global and are not row-batched.
- Package AL still uses the existing `qsiggam`, fixed-gamma,
  Laplace-Delta sigma path.
- exAL exact chunking preserves the existing engine update order.
- qbeta, qv, qs, and sigma/gamma stats are additive over deterministic chunks.
- Article latent-path chunking only touches fixed historical rows.
- Streamed grouped future moments, latent future-path updates, no-leakage
  checks, and source-specific sigma logic are preserved.

One scoped package issue was found and fixed:

- `qdesn_fit_vb()` forwarded explicit `likelihood_family` and
  `al_fixed_gamma`, but top-level `vb_args$chunking` did not reach
  `exal_ldvb_fit()`. It only worked when nested under `vb_args$vb_control`.
- Fix: forward top-level `vb_args$chunking` into `exal_make_vb_control()`
  while preserving nested `vb_args$vb_control$chunking`.
- Regression test added to verify exact chunking equivalence and early failure
  for non-exact top-level chunking.

Package commit:

- `73c043f0436b508808366f312350fd44c2d06771`
- Message: `Harden exact chunked VB validation`

## Package Validation

Logs were saved under ignored local path:
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/logs/exact_chunked_vb_20260527/`.

Commands run with R 4.6.0:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_dir("tests/testthat", filter = "qdesn-vb|qdesn.*likelihood")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_dir("tests/testthat", filter = "exal")'
```

Results:

- `test-exal-exact-chunking-stats.R`: passed, 38 checks.
- `test-exal-likelihood-family-al.R`: passed, 35 checks.
- `test-exal-inference-config.R`: passed, 199 checks.
- `test-qdesn-vb-likelihood-family.R`: passed, 12 checks.
- `test-static-beta-prior-rhs.R`: passed, 110 checks.
- Filtered Q-DESN likelihood sweep: passed, 12 checks.
- Filtered exAL sweep: passed, 805 checks.

The broad exAL sweep emitted expected synthetic diagnostic JSON from existing
failure-rescue tests; those diagnostics were not test failures.

## Article Changes

Article/config/doc changes made in this pass:

- Repinned the shared validation engine SHA from
  `5c868f897984638a82868549c14dbc35ae4dcea0` to
  `73c043f0436b508808366f312350fd44c2d06771` in:
  - `README.md`
  - `application/config/README.md`
  - `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- Added controlled exact-chunking smoke config:
  `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`
- Added a preparation-test assertion that the smoke config resolves chunking
  through `app_make_qdesn_discrepancy_vb_args()`.

The exact-chunked smoke config mirrors the selected D=1, n=300, m=100 smoke
profile and adds:

```yaml
chunking:
  enabled: true
  mode: exact
  chunk_size: 512
  order: sequential
  trace: false
```

## Article Validation

Logs were saved under ignored local path:
`/data/jaguir26/local/src/Article-Q-DESN/application/logs/exact_chunked_vb_20260527/`.

Commands run with R 4.6.0:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R

PATH=/data/jaguir26/local/opt/R/4.6.0/bin:$PATH \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml \
  --run_id exact_chunked_smoke_validation_20260527
```

Results:

- Full article test harness passed.
- The expected discrepancy-fit adapter skip remained:
  `Skipping discrepancy fit adapter test because the Q-DESN discrepancy engine is unavailable.`
- Exact-chunked smoke workflow passed through `run_all.R`.
- Smoke fit status:
  - raw GloFAS row completed.
  - Q-DESN latent-path AL-VB row completed.
  - Q-DESN fit runtime in `fit_status.csv`: 49.449 seconds.
  - Wrote 128 posterior-draw rows and 2 summary prediction rows.
- Engine contract in the smoke run:
  - engine SHA `73c043f0436b508808366f312350fd44c2d06771`
  - branch `validation/shared-fitforecast-v2-1.0.0`
  - `require_discrepancy = FALSE`
  - required exports present
  - source policy OK.
- Draw identity contract in the smoke run:
  - `max_identity_error = 0`
  - `all_identity_errors_within_tolerance = TRUE`

## Paired Chunked vs Unchunked Smoke

The paired check used the exact-chunked smoke config and an in-memory unchunked
twin made by removing only `inference.vb_ld.chunking`. Both fits used the same:

- config input paths
- model row
- cutoff row
- origin date
- reservoir seed
- VB iteration/draw limits
- package engine commit

Smoke setup:

- Config: `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`
- Model/fit id: `qdesn_latent_path_rhs_al_vb_d1n300_selected_smoke_p50`
- Cutoff id: `dec25_2022_latent_smoke`
- Origin date: `2022-12-25`
- Seed: `20260512`
- Chunking: exact, chunk size 512

Final state-equivalence results:

| Metric | Max absolute difference |
| --- | ---: |
| theta_mean | 1.221245e-14 |
| theta_cov | 3.653761e-17 |
| sigma_mean | 4.024558e-16 |
| sigma_shape | 0 |
| sigma_rate | 2.486900e-13 |
| y_future_mean | 1.776357e-14 |
| y_future_cov | 8.049117e-16 |
| elbo_trace | 2.501110e-12 |

Additional paired checks:

- Design hashes matched:
  `398cf2dec1dfc008bbf6418e40dd078a56b7273606fa633d79d714b8580f13fd`
- Both fits ran 5 iterations.
- Both smoke fits reported `converged = FALSE` because the smoke config has a
  deliberately tiny 5-iteration cap; this is expected for a runtime smoke and
  is not an equivalence failure.
- Posterior draw identity checks passed exactly:
  - unchunked max identity error: 0
  - chunked max identity error: 0
- Future covariance sanity passed:
  - unchunked min eigenvalue: 0.04708679
  - chunked min eigenvalue: 0.04708679
- Future linearization strategy was preserved as `first_order_delta`.
- No-leakage validation passed on the chunked future input audit.
- Runtime in paired in-process check:
  - unchunked: 38.392 seconds
  - chunked: 32.161 seconds
- `gc()` used counts were recorded but are not treated as reliable memory
  benchmarks because the two fits ran in one R process:
  - before: 2,079,003
  - after unchunked: 8,585,904
  - after chunked: 12,081,801

Two validation attempts were intentionally not hidden:

- First paired script attempt failed before fitting because it asked the engine
  contract for the legacy `qdesn_fit_discrepancy` export. The latent-path
  adapter does not require that export. The rerun used the same predicate as
  the application workflow:
  `app_qdesn_engine_requires_discrepancy_export(cfg, model_grid)`.
- A stricter draw-matrix byte-equivalence gate failed even though fitted
  moments matched. Diagnosis: `app_latent_mvn_draws()` uses an eigen root; tiny
  floating-point changes in covariance accumulation can flip or rotate
  eigenvectors and therefore change finite Monte Carlo draw matrices without
  changing the fitted posterior state. The final gate therefore checks fitted
  state equivalence and the posterior draw identity contract, and reports draw
  matrix differences as non-gating diagnostics.

## Activation Decision

Exact chunking is now activated in the controlled smoke profile:

- `application/config/glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml`

The manuscript-scale main config was repinned to the hardened package commit,
but exact chunking was not enabled there yet. Reason: the paired smoke proves
fitted-state equivalence and shows a small runtime improvement, but it does not
provide a reliable separate-process memory benchmark for the large D=2,
n=1000 x 1000 main profile. Promotion to the final-launch config should happen
after a short full-specification pilot or separate-process memory profile.

## Remaining Risks

- Exact chunking changes floating-point accumulation order. Fitted states are
  equivalent to tolerance, but finite posterior draw matrices may not be
  byte-identical because of eigen-root sign/rotation effects.
- The smoke run uses a 5-iteration cap, so it validates plumbing and
  equivalence, not convergence quality.
- Memory observations from same-process paired checks are only rough `gc()`
  counts. Use separate-process profiling before making memory claims.
- Stochastic/hybrid mini-batch VB remains unimplemented. It still needs a
  mathematical scaling, objective, seed, and RHS contract before code changes.

## Next Recommended Action

Run a separate-process short full-specification pilot with the same exact
chunking block and compare against the current unchunked main configuration.
If the fitted-state equivalence remains tight and peak memory or runtime is
acceptable, promote exact chunking to
`application/config/glofas_latent_path_al_vb_dec25_main.yaml`.
