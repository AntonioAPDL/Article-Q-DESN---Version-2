# Normal DESN Initialization Comparison

Date: 2026-05-29

## Scope

This note documents the Normal DESN initialization comparison harness for
currently implemented AL/exAL Q-DESN VB readouts.

Package script:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/scripts/run_normal_desn_init_comparison_20260529.R
```

Ignored result directory:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_desn_init_comparison_20260529/
```

No Overleaf/main files were edited.

## Interpretation

Normal DESN initialization is a workflow mechanism, not a new posterior
target. The AL/exAL likelihood, prior, and variational objective remain the
target being fit after initialization.

The comparison is intentionally conservative:

- cold AL VB and exAL VB;
- AL/exAL VB initialized from serialized Normal scaled-ridge warm-start moments;
- AL/exAL VB initialized from serialized Normal RHS_NS warm-start moments;
- optional tiny AL MCMC path exposed by the script but not enabled in the
  default documented run.

## Dataset And Settings

The documented run used the frozen Gaussian median validation source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Settings:

```text
D = 1
n = 5
m = 1
washout = 25
effective fitted rows = 475
max_iter = 12
seed = 20260529
MCMC enabled = FALSE
```

The latest warm-start validation rerun used the same source and DESN settings
with `max_iter = 15` from clean package commit `9f1c32d`.

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v -o results/normal_desn_init_comparison_20260529/run.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_desn_init_comparison_20260529.R \
  --output-dir results/normal_desn_init_comparison_20260529 \
  --seed 20260529 \
  --D 1 \
  --n 5 \
  --m 1 \
  --washout 25 \
  --max-iter 15
```

## Reproducibility Note

The result metadata records:

```text
package_head = 9f1c32d
package_dirty = FALSE
```

The documented rerun used the serialized Normal DESN warm-start API before
converting into AL/exAL VB initializers.

## Results

| Method | Init Source | Family | RMSE | Pinball 0.50 | Finite | Elapsed sec | Max Beta Diff vs Cold |
|---|---|---|---:|---:|---|---:|---:|
| normal_scaled_ridge | fit | normal | 20.079 | 8.378 | TRUE | 0.165 | NA |
| normal_rhs_ns_vb | fit | normal | 20.079 | 8.378 | TRUE | 2.244 | NA |
| al_vb_cold | none | al | 21.106 | 8.568 | TRUE | 2.373 | NA |
| al_vb_normal_scaled_ridge_init | normal_scaled_ridge | al | 21.072 | 8.559 | TRUE | 14.103 | 0.1099 |
| al_vb_normal_rhs_ns_init | normal_rhs_ns_vb | al | 21.073 | 8.559 | TRUE | 0.276 | 0.1089 |
| exal_vb_cold | none | exal | 21.003 | 8.540 | TRUE | 0.869 | NA |
| exal_vb_normal_scaled_ridge_init | normal_scaled_ridge | exal | 20.985 | 8.536 | TRUE | 0.901 | 0.0594 |
| exal_vb_normal_rhs_ns_init | normal_rhs_ns_vb | exal | 20.986 | 8.536 | TRUE | 0.881 | 0.0588 |

Warm-start states written by the harness:

| Warm Start | Normal Target | Exact Status | Prior | Beta Dim |
|---|---|---|---|---:|
| normal_scaled_ridge | normal_scaled_ridge_exact | exact | scaled_ridge | 6 |
| normal_rhs_ns_vb | normal_rhs_ns_vb_approx | approximate_vb | rhs_ns | 6 |

The full timed run reported:

```text
Elapsed wall time: 0:39.63
Maximum resident set size: 514984 KB
```

All fitted states were finite. The small metric differences should not be
overinterpreted because these fits used a short iteration budget. The result
does support the basic workflow claim: Normal DESN moments can seed AL/exAL VB
without breaking design hashes, feature-setting hashes, finite-state checks, or
fit execution.

## Validation

The package script has a synthetic smoke test:

```text
tests/testthat/test-qdesn-normal-init-comparison.R
```

That test verifies:

- the script runs without the real source folder;
- expected output files are written;
- cold and Normal-initialized AL/exAL VB rows are present;
- Normal initialization sources are recorded;
- metrics and fitted states are finite.

Focused Normal warm-start tests also verify:

- exact and exact-chunked scaled-ridge labels;
- RHS/RHS_NS approximate labels;
- design and feature-hash mismatch failures;
- package SHA strict validation;
- covariance and omega2 state validation;
- VB and MCMC initializer conversion metadata.

## Limitations

- The documented run does not enable MCMC.
- The iteration budget is intentionally small.
- This is not a claim that Normal initialization improves final converged
  posterior quality.
- This is a clean-worktree economical smoke, not a final manuscript-scale
  benchmark.

## Next Stage

The next high-value stage is the final Normal/Q-DESN unified comparison using
package commit `9f1c32d` or later. Recursive Normal DESN forecast paths are
already implemented for the narrow standard univariate setting.
