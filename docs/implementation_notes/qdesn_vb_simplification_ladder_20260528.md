# Q-DESN VB Simplification Ladder

Date: 2026-05-28

Status: implemented package comparison harness and economical validation gate.
This note documents Stage 1 of the Q-DESN VB modes roadmap. It does not add a
new inference algorithm.

## Scope

The simplification ladder compares already implemented univariate Q-DESN VB
readout modes after fixed DESN feature construction:

- AL with ridge, RHS, and RHS_NS beta priors;
- exAL with ridge, RHS, and RHS_NS beta priors;
- unchunked full-data VB;
- exact chunked full-data VB;
- stochastic mini-batch AL VB, explicitly approximate.

The ladder excludes stochastic exAL, hybrid AL/exAL, rolling-window or
posterior-as-prior VB, covariance approximations, subset CAVI, online-mode
promotion, divide-and-combine VB, and variational coresets.

## Repo State

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- starting checkpoint: `8287dc8e4bf65ad324031daa211a642a37a56114`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- package commits:
  - `db92153` `Add Q-DESN VB simplification ladder`
  - `258b6e9` `Support source data in Q-DESN VB ladder`

No Overleaf/main worktree files were edited.

## Package Harness

Tracked package script:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/scripts/run_qdesn_vb_simplification_ladder_20260528.R`

Tracked package test:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/tests/testthat/test-qdesn-vb-simplification-ladder.R`

The script writes ignored result artifacts under `results/`, including:

- `repo_state.csv`
- `ladder_method_summary.csv`
- `exact_equivalence.csv`
- `stochastic_diagnostics.csv`
- `prior_diagnostics.csv`
- `forbidden_modes.csv`
- `prediction_metrics.csv`
- `predictions_by_method.csv`
- `qdesn_vb_simplification_ladder_summary.md`
- `time_v.log` when run under `/usr/bin/time -v`

## Rungs

| Likelihood | Prior | Unchunked | Exact Chunked | Stochastic |
| --- | --- | --- | --- | --- |
| AL | ridge | implemented | implemented | implemented, approximate |
| AL | RHS | implemented | implemented | implemented, approximate |
| AL | RHS_NS | implemented | implemented | implemented, approximate |
| exAL | ridge | implemented | implemented | forbidden for stochastic |
| exAL | RHS | implemented | implemented | forbidden for stochastic |
| exAL | RHS_NS | implemented | implemented | forbidden for stochastic |

RHS and RHS_NS remain global shrinkage priors. The ladder records intercept
shrinkage policy and RHS trace metadata; it does not row-batch RHS states.

## Commands

Baseline/final focused package tests used R 4.6.0 with one-thread math library
settings:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-exact-chunking-stats.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-likelihood-family-al.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-inference-config.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-likelihood-family.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-batching-controls.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-exal-stochastic-al-vb.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-batching-modes.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-static-beta-prior-rhs.R")'
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript -e 'pkgload::load_all(".", quiet = TRUE); testthat::test_file("tests/testthat/test-qdesn-vb-simplification-ladder.R")'
```

Synthetic ladder:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
out=results/qdesn_vb_simplification_ladder_20260528
mkdir -p "$out"
/usr/bin/time -v -o "$out/time_v.log" \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_simplification_ladder_20260528.R \
  --output-dir "$out" \
  --seed 20260528
```

TT500 source ladder:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
source_dir=/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
out=results/qdesn_vb_simplification_ladder_tt500_20260528
mkdir -p "$out"
/usr/bin/time -v -o "$out/time_v.log" \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_simplification_ladder_20260528.R \
  --source-dir "$source_dir" \
  --output-dir "$out" \
  --seed 20260528 \
  --reservoir-size 6 \
  --washout 50 \
  --chunk-size 64 \
  --max-iter 24 \
  --stochastic-max-iter 48 \
  --exact-tolerance 1e-6 \
  --stochastic-tolerance 3.0 \
  --stochastic-pinball-tolerance 0.75
```

## Test Results

Focused package tests after the source-data harness update:

| Test file | Pass |
| --- | ---: |
| `test-exal-exact-chunking-stats.R` | 38 |
| `test-exal-likelihood-family-al.R` | 35 |
| `test-exal-inference-config.R` | 203 |
| `test-qdesn-vb-likelihood-family.R` | 12 |
| `test-exal-batching-controls.R` | 49 |
| `test-exal-stochastic-al-vb.R` | 38 |
| `test-qdesn-vb-batching-modes.R` | 20 |
| `test-static-beta-prior-rhs.R` | 110 |
| `test-qdesn-vb-simplification-ladder.R` | 33 |
| Total | 538 |

All focused tests passed.

## Synthetic Gate

Settings:

- synthetic univariate response generated by the harness;
- `D = 1`;
- reservoir size `n = 6`;
- `washout = 6`;
- `max_iter = 24`;
- stochastic `max_iter = 48`;
- exact tolerance `1e-6`;
- stochastic fitted tolerance `0.10`;
- stochastic pinball tolerance `0.02`.

Exact chunked gates all passed:

| Pair | Max Gate Diff |
| --- | ---: |
| AL ridge | `2.28e-11` |
| exAL ridge | `4.97e-09` |
| AL RHS | `2.40e-11` |
| exAL RHS | `4.40e-08` |
| AL RHS_NS | `1.12e-11` |
| exAL RHS_NS | `9.29e-09` |

Stochastic AL diagnostics all passed finite-state, reproducibility, approximate
labeling, and distance gates:

| Prior | Max Fitted Diff vs Unchunked | Pinball Diff vs Unchunked | Repeat Diff |
| --- | ---: | ---: | ---: |
| ridge | `3.50e-02` | `1.54e-03` | `0` |
| RHS | `6.35e-02` | `2.47e-03` | `0` |
| RHS_NS | `6.71e-02` | `3.71e-03` | `0` |

Runtime/memory from `/usr/bin/time -v`:

- wall time: `1:14.62`;
- maximum resident set size: `513628` KB.

## TT500 Source Gate

Dataset:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500`

The ladder uses `series_wide.csv` and fits only `y`. The `q_target` column is
used as the diagnostic signal.

Settings:

- 500 source rows;
- effective post-washout rows: 450;
- `D = 1`;
- reservoir size `n = 6`;
- `washout = 50`;
- exact/stochastic chunk size `64`;
- `max_iter = 24`;
- stochastic `max_iter = 48`;
- exact tolerance `1e-6`;
- source-scale stochastic fitted tolerance `3.0`;
- source-scale stochastic pinball tolerance `0.75`.

Exact chunked gates all passed:

| Pair | Max Gate Diff |
| --- | ---: |
| AL ridge | `5.21e-11` |
| exAL ridge | `3.42e-08` |
| AL RHS | `1.73e-11` |
| exAL RHS | `2.01e-10` |
| AL RHS_NS | `5.92e-11` |
| exAL RHS_NS | `5.00e-10` |

Stochastic AL source diagnostics passed finite-state, reproducibility,
approximate labeling, and source-scale diagnostic gates:

| Prior | Max Fitted Diff vs Unchunked | Pinball Diff vs Unchunked | Repeat Diff |
| --- | ---: | ---: | ---: |
| ridge | `2.51` | `-0.543` | `0` |
| RHS | `1.78` | `0.0187` | `0` |
| RHS_NS | `1.78` | `0.0187` | `0` |

The ridge stochastic rung improved pinball loss on this bounded run, but it is
still an approximate stochastic result and is not an exact-equivalence claim.

Runtime/memory from `/usr/bin/time -v`:

- wall time: `1:24.36`;
- maximum resident set size: `526288` KB.

## Forbidden Modes

The ladder attempts stochastic exAL under ridge, RHS, and RHS_NS and verifies
that all three fail early with:

`stochastic VB chunking is currently supported only for likelihood_family = 'al'.`

## Interpretation

Stage 1 is complete. The ladder gives a reproducible comparison grid for the
currently implemented modes. Exact chunking is full-data equivalent for AL and
exAL under ridge, RHS, and RHS_NS. Stochastic AL is implemented and reproducible
but remains approximate; the ladder records fitted-state and predictive
diagnostics rather than claiming equivalence. Stochastic/hybrid exAL remains
gated.

## Article Config Repin and Tiny Gate

After the package ladder commits were pushed, the active article engine pins
were updated to package commit:

`258b6e92d1b5c6db26d3f3fce31ddf3b1de26dfe`

Touched article configs:

- `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`

The tiny D1N5 real-data article gate was rerun against that package SHA.
Ignored local outputs are under:

`application/logs/exact_chunked_vb_tiny_d1n5_pkg258b6e9_20260528/`

Tiny gate summary:

| Metric | Value |
| --- | ---: |
| same engine SHA | `TRUE` |
| same design hash | `TRUE` |
| intended config differences only | `TRUE` |
| unchunked converged | `FALSE` |
| exact chunked converged | `FALSE` |
| unchunked iterations | `3` |
| exact chunked iterations | `3` |
| max gate diff | `1.72e-12` |
| tolerance | `1e-7` |
| passed | `TRUE` |
| unchunked max RSS | `139760` KB |
| exact chunked max RSS | `139936` KB |
| unchunked wall time | `19.20` sec |
| exact chunked wall time | `18.14` sec |

Both fits stopped after the same bounded pilot iteration count, so the
non-converged flag is expected for this cheap gate; the comparison gate is
fitted-state equivalence, not convergence to the final article target.

The next implementation target is the canonical warm-start API for package
Q-DESN AL/exAL under ridge and RHS/RHS_NS, starting with full-data and exact
chunked modes only.
