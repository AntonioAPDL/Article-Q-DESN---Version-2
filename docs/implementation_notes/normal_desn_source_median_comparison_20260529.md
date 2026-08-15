# Normal DESN Source-Median Comparison

Date: 2026-05-29

## Scope

This note documents the economical source-median comparison harness for Normal
DESN and currently implemented Q-DESN readout modes.

Package script:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/scripts/run_normal_desn_source_median_comparison_20260529.R
```

Ignored result directory:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_desn_source_median_comparison_20260529/
```

No Overleaf/main files were edited.

## Dataset

The real-data smoke used the frozen Gaussian median validation source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

The harness verifies that `series_wide.csv` has columns:

```text
t, y, mu, q_target, eps
```

and that `q_target` equals `mu`, as expected for the Gaussian median source.

The run used:

```text
D = 1
n = 5
m = 1
washout = 25
effective fitted rows = 475
chunk_size = 64
max_iter = 12
stochastic_max_iter = 30
seed = 20260529
```

## Methods Compared

The harness compares implemented and safe modes only:

```text
normal_scaled_ridge
normal_scaled_ridge_exact_chunked
normal_rhs_ns_vb
qdesn_al_ridge
qdesn_al_ridge_exact_chunked
qdesn_al_ridge_stochastic
qdesn_exal_ridge
qdesn_exal_ridge_exact_chunked
```

Interpretation rules:

- Normal DESN is a conditional-mean Gaussian readout.
- Q-DESN AL/exAL are tau = 0.50 quantile readouts in this comparison.
- The Gaussian median source makes mean and median coincide, so tau = 0.50
  pinball is a useful descriptive metric here.
- Exact chunked methods must match the corresponding unchunked target.
- Stochastic AL remains approximate.

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v -o results/normal_desn_source_median_comparison_20260529/run.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_desn_source_median_comparison_20260529.R \
  --output-dir results/normal_desn_source_median_comparison_20260529 \
  --seed 20260529 \
  --D 1 \
  --n 5 \
  --m 1 \
  --washout 25 \
  --chunk-size 64 \
  --max-iter 12 \
  --stochastic-max-iter 30
```

## Reproducibility Note

The result metadata records:

```text
package_head = 0f5d4f6
package_dirty = FALSE
```

The documented run was rerun from a clean package worktree after fixing the
comparison harness dirty-state metadata.

## Exact Equivalence

Tolerance: `1e-7`.

| Reference | Exact Chunked | Max Gate Diff | Passed |
|---|---|---:|---|
| normal_scaled_ridge | normal_scaled_ridge_exact_chunked | 5.86e-09 | TRUE |
| qdesn_al_ridge | qdesn_al_ridge_exact_chunked | 3.78e-11 | TRUE |
| qdesn_exal_ridge | qdesn_exal_ridge_exact_chunked | 2.15e-10 | TRUE |

## Method Summary

| Method | Family | Target | RMSE | Pinball 0.50 | Finite | Elapsed sec |
|---|---|---|---:|---:|---|---:|
| normal_scaled_ridge | normal | conditional_mean | 20.079 | 8.378 | TRUE | 0.130 |
| normal_scaled_ridge_exact_chunked | normal | conditional_mean | 20.079 | 8.378 | TRUE | 1.931 |
| normal_rhs_ns_vb | normal | conditional_mean | 20.079 | 8.378 | TRUE | 0.280 |
| qdesn_al_ridge | al | tau_0p50_quantile | 21.033 | 8.548 | TRUE | 1.005 |
| qdesn_al_ridge_exact_chunked | al | tau_0p50_quantile | 21.033 | 8.548 | TRUE | 6.718 |
| qdesn_al_ridge_stochastic | al | tau_0p50_quantile | 20.661 | 8.456 | TRUE | 0.409 |
| qdesn_exal_ridge | exal | tau_0p50_quantile | 20.958 | 8.529 | TRUE | 0.389 |
| qdesn_exal_ridge_exact_chunked | exal | tau_0p50_quantile | 20.958 | 8.529 | TRUE | 0.367 |

The full timed run reported:

```text
Elapsed wall time: 0:21.91
Maximum resident set size: 517316 KB
```

## Validation

The package script has a synthetic smoke test:

```text
tests/testthat/test-qdesn-normal-comparison-script.R
```

That test verifies that the script:

- runs without the real source folder;
- writes `repo_state.csv`, `method_summary.csv`, `exact_equivalence.csv`,
  `predictions_by_method.csv`, and a Markdown summary;
- includes the expected Normal/Q-DESN methods;
- passes all exact equivalence gates;
- produces finite predictions and metrics.

## Limitations

- This is not a final manuscript benchmark.
- Stochastic AL is included only as an approximate implemented mode.
- Stochastic/hybrid exAL is not included.
- Normal DESN is not interpreted as a quantile likelihood.
- This is a clean-worktree economical run, but not a final manuscript-scale
  benchmark.

## Next Stage

The next roadmap stage is a Normal initialization comparison:

```text
scripts/run_normal_desn_init_comparison_20260529.R
docs/implementation_notes/normal_desn_initialization_comparison_20260529.md
```

That stage should compare cold AL/exAL starts against Normal scaled-ridge and
Normal RHS/RHS_NS initialization, while keeping MCMC as a tiny smoke unless a
larger run is explicitly authorized.
