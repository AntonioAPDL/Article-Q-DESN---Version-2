# Q-DESN VB Source TT500 Median Comparison

Date: 2026-05-28

This note records the focused comparison of currently implemented Q-DESN VB batching approaches on the literal last-500 source subset from the shared dynamic fit/forecast simulation study. It does not add new batching algorithms.

## Repo State

Article repo:

- Path: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Head before this note: `ee4fa9ba18eed1b8e1f08e830ddcf4a74fade6ac`

Package repo:

- Path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Comparison script commit: `e2af4ca Add source TT500 median Q-DESN batching comparison`

The main Dec25 application config was repinned from package commit `37bdd3a`
to `e2af4ca9444298afb77e411372707b774f0bd2b5` so the local-source engine
contract remains aligned with the current package worktree after adding the
comparison script. This does not enable new article-side batching controls.

The Overleaf/main worktree was not edited.

## Dataset

Source directory:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500`

Primary file: `series_wide.csv`

Required columns are present: `t`, `y`, `mu`, `q_target`, `eps`.

Validated facts:

- Rows: `500`
- Source indices: `9501:10000`, from `selection_indices.csv`
- Family: `normal`
- Tau: `0.50`
- `max(abs(mu - q_target)) = 0`
- Missing values in `y`, `mu`, `q_target`: `0`

Dataset summaries:

| variable | min | q1 | median | mean | q3 | max | sd |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `y` | 152.4499 | 196.4359 | 210.7059 | 211.9006 | 226.5918 | 267.0330 | 20.0983 |
| `mu` | 181.7359 | 197.2724 | 211.5038 | 212.0245 | 227.8269 | 241.8352 | 17.5167 |
| `q_target` | 181.7359 | 197.2724 | 211.5038 | 212.0245 | 227.8269 | 241.8352 | 17.5167 |
| `eps` | -32.2433 | -6.7643 | 0.5780 | -0.1239 | 6.1318 | 30.7003 | 9.8433 |

The literal last-500 subset was chosen instead of the broader 1812-row validation fit/forecast slice because this pass is a focused, economical real-data comparison gate. It uses a real shared-validation source while keeping the run small enough to repeat frequently during batching development.

## Modeling Rule

The Q-DESN was fit to `y` only. The true median columns `mu` and `q_target` were used only for diagnostics and plotting. No new covariate or input adapter was introduced.

## Q-DESN Settings

- `p0 = 0.50`
- `D = 1`
- `n = 50`
- `n_tilde = integer(0)`
- `m = 1`
- `washout = 50`
- `add_bias = TRUE`
- Fixed Q-DESN seed: `20260628`
- Readout prior: ridge beta prior with `beta_ridge_tau2 = 50`
- Effective post-washout fitted rows: `450`

## VB Controls

Shared AL controls:

- `likelihood_family = "al"`
- `al_fixed_gamma = 0`
- `max_iter = 50` for unchunked and exact chunked AL
- `tol = 0`, `tol_par = 0`
- `n_samp_xi = 32`

AL exact chunking:

```r
chunking = list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 64L,
  order = "sequential"
)
```

AL stochastic mini-batch controls:

```r
chunking = list(
  enabled = TRUE,
  mode = "stochastic",
  chunk_size = 64L,
  order = "random",
  seed = 20260528,
  learning_rate = list(t0 = 10, kappa = 0.75, rho_min = 0.02),
  refresh = list(
    full_every = 20,
    objective_every = 20,
    sigma_every = 5,
    rhs_every = 20,
    local_every = 20
  ),
  diagnostics = list(
    trace = TRUE,
    store_batch_ids = TRUE,
    check_finite_every = 1
  )
)
```

Optional exAL controls reused the same unchunked and exact-chunked structure. Stochastic exAL was attempted only as a forbidden-mode check and failed early as expected.

## Methods Compared

Implemented methods run:

- Q-DESN AL unchunked full-data VB
- Q-DESN AL exact chunked full-data VB
- Q-DESN AL stochastic mini-batch VB, approximate
- Q-DESN exAL unchunked full-data VB
- Q-DESN exAL exact chunked full-data VB

Excluded and still gated:

- Stochastic exAL
- Hybrid AL with periodic full refresh
- Variance-reduced SVI
- Streaming/posterior-as-prior VB
- Article GloFAS stochastic or hybrid batching
- Multivariate Q-DESN batching

## Commands

Package comparison:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
mkdir -p results/qdesn_vb_batching_source_tt500_median_20260528
/usr/bin/time -v \
  -o results/qdesn_vb_batching_source_tt500_median_20260528/source_tt500_median.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_batching_comparison_source_tt500_median_20260528.R \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --output-dir results/qdesn_vb_batching_source_tt500_median_20260528 \
  --seed 20260528 \
  > results/qdesn_vb_batching_source_tt500_median_20260528/source_tt500_median.console.log 2>&1
```

Focused package tests:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-stochastic-al-vb.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-batching-controls.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
```

## Output Files

Package outputs were written under ignored local results:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_vb_batching_source_tt500_median_20260528`

Files:

- `repo_state.csv`
- `dataset_summary.csv`
- `method_summary.csv`
- `exact_equivalence.csv`
- `stochastic_diagnostics.csv`
- `prediction_metrics.csv`
- `predictions_by_method.csv`
- `forbidden_modes.csv`
- `qdesn_vb_batching_source_tt500_median_summary.md`
- `qdesn_vb_batching_source_tt500_median_diagnostic.png`
- `source_tt500_median.console.log`
- `source_tt500_median.time.log`

## Results

All comparison gates passed.

Exact chunking equivalence, tolerance `1e-7`:

| comparison | max gate difference | passed |
| --- | ---: | --- |
| AL unchunked vs AL exact chunked | 9.544010e-11 | yes |
| exAL unchunked vs exAL exact chunked | 4.099689e-10 | yes |

The exact chunked methods preserved the full-data fitted target up to floating-point ordering differences.

Stochastic AL diagnostics against AL unchunked:

| diagnostic | value |
| --- | ---: |
| stochastic trace rows | 100 |
| finite state | true |
| reproducible beta mean max absolute difference | 0 |
| reproducible fitted median max absolute difference | 0 |
| beta mean max absolute difference vs unchunked | 0.5215431 |
| fitted median max absolute difference vs unchunked | 1.044429 |
| pinball loss difference vs unchunked | 0.008513 |
| MAE difference vs unchunked | 0.017026 |
| RMSE difference vs unchunked | -0.083075 |

Stochastic AL is approximate. These diagnostics show a finite, fixed-seed reproducible stochastic fit that is close to the unchunked AL fit on this controlled source subset, but it is not an exact-equivalence result.

Prediction metrics:

| method | pinball_y | mae_y | rmse_y | mae_q_target | rmse_q_target | cor_q_target |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Q-DESN AL unchunked | 7.948943 | 15.89789 | 19.33456 | 14.08488 | 16.61399 | 0.908976 |
| Q-DESN AL exact chunked | 7.948943 | 15.89789 | 19.33456 | 14.08488 | 16.61399 | 0.908976 |
| Q-DESN AL stochastic | 7.957456 | 15.91491 | 19.25149 | 14.06965 | 16.51251 | 0.908915 |
| Q-DESN exAL unchunked | 7.965642 | 15.93128 | 19.44687 | 14.15612 | 16.74778 | 0.908729 |
| Q-DESN exAL exact chunked | 7.965642 | 15.93128 | 19.44687 | 14.15612 | 16.74778 | 0.908729 |

The stochastic exAL forbidden-mode check passed:

- Attempted: yes
- Failed early: yes
- Message: `stochastic VB chunking is currently supported only for likelihood_family = 'al'.`

Runtime and memory:

- Total wall time: `0:44.10`
- Peak resident set size: `572920` KB
- Per-fit elapsed times:
  - AL unchunked: `3.028` sec
  - AL exact chunked: `15.838` sec
  - AL stochastic: `2.332` sec
  - exAL unchunked: `2.980` sec
  - exAL exact chunked: `3.012` sec

The AL exact-chunked path is slower than unchunked on this small `n = 50`, `T = 500` example, which is expected because chunking overhead dominates at this scale. It remains useful here as an exactness gate rather than a performance optimization.

## Tests

Focused package tests passed:

| test file | result |
| --- | --- |
| `test-exal-exact-chunking-stats.R` | 38 pass, 0 fail |
| `test-exal-likelihood-family-al.R` | 35 pass, 0 fail |
| `test-exal-inference-config.R` | 203 pass, 0 fail |
| `test-qdesn-vb-likelihood-family.R` | 12 pass, 0 fail |
| `test-exal-stochastic-al-vb.R` | 38 pass, 0 fail |
| `test-exal-batching-controls.R` | 49 pass, 0 fail |
| `test-qdesn-vb-batching-modes.R` | 20 pass, 0 fail |
| `test-static-beta-prior-rhs.R` | 110 pass, 0 fail |

Total focused package tests: 505 pass, 0 fail.

## Pass/Fail Status

Pass.

- Dataset invariants passed.
- AL exact chunked matched AL unchunked within `1e-7`.
- exAL exact chunked matched exAL unchunked within `1e-7`.
- Stochastic AL was finite and reproducible under the fixed seed.
- Stochastic AL was labeled approximate.
- Stochastic exAL failed early.
- Focused package tests passed.

The individual fits reached the configured maximum iteration counts rather than declaring convergence in this economical comparison configuration. The exact-equivalence comparisons used matched convergence status, matched iteration counts, and fitted-state differences, so this does not invalidate the batching gate.

## Recommended Next Step

Use this source TT500 median comparison as the first real-data package example for the implemented Q-DESN batching methods. For a larger example, repeat the same harness with a larger reservoir or a broader validation slice only after deciding the intended runtime and memory budget.

The next implementation target remains separate from this comparison pass: hybrid AL with periodic full refresh, after documenting its stochastic objective and refresh contract. Stochastic exAL, article-side stochastic/hybrid batching, streaming/posterior-as-prior VB, and multivariate Q-DESN batching remain gated.
