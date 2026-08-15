# Q-DESN VB Implemented-Mode Source Median Comparison

Date: 2026-05-28
Package commit: `9c25db3 Add hybrid exAL ridge VB`
Article branch: `application-ensemble-likelihood-redesign`

## Purpose

This is the authoritative comparison pass over the Q-DESN VB modes that are
currently implemented and safe to run on the controlled validation-study median
source. It does not use the expensive GloFAS application and does not implement
new article-side adapters.

## Dataset

Source directory:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

The comparison uses `series_wide.csv` with 500 rows and source indices
9501:10000. The model is fit to `y` only. `mu` and `q_target` are diagnostic
median targets, and `max(abs(mu - q_target)) = 0`.

Scenario metadata:

- scenario: `dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast`
- family: normal
- tau: 0.50
- TT_main: 10000
- TT_warmup: 2000
- period: 90
- normal_sigma: 10
- q_true_equals_mu: TRUE
- latent_seed: 12011
- noise_seed: 12012

## Command

Run from the package repo:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v \
  -o results/qdesn_vb_implemented_modes_source_median_20260528/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_implemented_modes_source_median_20260528.R \
  --output-dir results/qdesn_vb_implemented_modes_source_median_20260528 \
  --cores 4 \
  > results/qdesn_vb_implemented_modes_source_median_20260528/console.log 2>&1
```

Primary outputs are ignored by git under:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_vb_implemented_modes_source_median_20260528/
```

## Q-DESN Settings

| Setting | Value |
| --- | --- |
| `p0` | 0.50 |
| `D` | 1 |
| reservoir `n` | 50 |
| `m` | 1 |
| washout | 50 |
| effective readout rows | 450 |
| chunk size | 64 |
| fixed subset size | 180 |
| seed | 20260528 |
| Q-DESN seed | 20260628 |
| exact comparison tolerance | `1e-6` |

The `1e-6` source-comparison tolerance is used because diagonal-covariance rows
show harmless floating-order differences around `1e-7` to `6e-7`. The focused
unit tests still check exact chunking at tighter tolerances on smaller synthetic
cases.

## Methods Compared

Full-data preserving exact methods:

- AL ridge full-data and exact chunked;
- AL RHS and RHS_NS full-data and exact chunked;
- exAL ridge full-data and exact chunked;
- exAL RHS and RHS_NS full-data and exact chunked.

Approximate methods:

- AL ridge stochastic mini-batch;
- AL ridge hybrid;
- exAL ridge hybrid;
- AL ridge/RHS/RHS_NS diagonal covariance.

Target-changing workflow methods:

- AL ridge fixed subset;
- AL ridge time-block stratified subset;
- AL ridge rolling-window refits;
- AL ridge posterior-as-prior rolling handoff;
- AL ridge online posterior-as-prior wrapper.

Deliberately excluded or forbidden:

- stochastic exAL: still forbidden and failed early;
- exAL diagonal covariance: still forbidden and failed early;
- RHS/RHS_NS hybrid exAL: gated;
- article GloFAS stochastic/hybrid/rolling/online adapters: gated;
- divide-and-combine VB and variational coresets: deferred.

## Exact Equivalence

All exact chunked comparisons passed at `1e-6`.

| Comparison | Max Gate Diff |
| --- | ---: |
| AL ridge exact chunked | 1.89e-10 |
| AL ridge diagonal exact chunked | 1.87e-07 |
| AL fixed subset exact chunked | 1.20e-10 |
| AL stratified subset exact chunked | 2.53e-10 |
| AL RHS exact chunked | 3.80e-11 |
| AL RHS diagonal exact chunked | 5.82e-07 |
| AL RHS_NS exact chunked | 3.59e-11 |
| AL RHS_NS diagonal exact chunked | 6.92e-10 |
| exAL ridge exact chunked | 1.37e-09 |
| exAL RHS exact chunked | 9.21e-11 |
| exAL RHS_NS exact chunked | 2.22e-10 |

## Approximate Diagnostics

All approximate rows were finite and reproducible under fixed seed when a repeat
was run. Differences below are against the corresponding full-data reference.

| Method | Max Fitted Difference | Pinball Difference |
| --- | ---: | ---: |
| AL stochastic ridge | 1.41 | 2.61e-02 |
| AL hybrid ridge | 4.16e-01 | 2.60e-02 |
| exAL hybrid ridge | 9.02e-01 | 1.49e-02 |
| AL diagonal ridge | 1.86e+02 | 8.52e+01 |
| AL diagonal RHS | 1.15e+03 | 5.63e+02 |
| AL diagonal RHS_NS | 3.72e+02 | 1.75e+02 |

The diagonal covariance rows are technically finite and labeled approximate,
but they are not empirically attractive on this source with these settings.
They should remain a diagnostic/scalability option rather than a preferred
comparison result.

## Predictive Metrics

Selected rows from `prediction_metrics.csv`:

| Method | Target Label | Pinball(y) | RMSE vs `q_target` | Cor(`q_target`, fitted) |
| --- | --- | ---: | ---: | ---: |
| AL ridge full | `full_data_exact` | 7.949 | 16.619 | 0.909 |
| AL ridge exact | `full_data_exact_chunked` | 7.949 | 16.619 | 0.909 |
| AL stochastic ridge | `full_data_approx_stochastic` | 7.975 | 16.532 | 0.908 |
| AL hybrid ridge | `full_data_approx_hybrid` | 7.975 | 16.656 | 0.908 |
| exAL ridge full | `full_data_exact` | 7.962 | 16.721 | 0.909 |
| exAL hybrid ridge | `full_data_approx_hybrid` | 7.977 | 16.665 | 0.908 |
| AL fixed subset | `subset_target` | 8.087 | 16.943 | 0.904 |
| AL stratified subset | `subset_target` | 8.094 | 16.876 | 0.904 |

## Target-Changing Diagnostics

Subset modes are not full-data posterior approximations; they change the data
target. Fixed and stratified subsets were finite and exact chunked subset fits
matched their unchunked subset targets.

Rolling/posterior-as-prior/online diagnostics used two ordered units ending at
rows 250 and 500. No future leakage was reported. Online exact chunking matched
the online unchunked state-handoff workflow, with final beta-L2 difference
`6.14e-11`.

## Runtime And Memory

The comparison finished successfully:

- wall time: 54.95 seconds;
- peak resident set size: 608396 KB, about 594 MiB;
- exit status: 0.

## Takeaways

The exact chunked modes remain the reference-safe way to reduce memory while
preserving the full-data target. Stochastic and hybrid AL are finite,
reproducible, and close enough for controlled diagnostics but remain
approximate. Hybrid exAL ridge is now implemented and comparison-ready as an
approximate package/Q-DESN mode. Stochastic exAL remains forbidden.

The next implementation priority should be to validate hybrid exAL ridge on one
additional economical source-scale gate before considering any RHS/RHS_NS exAL
hybrid extension.
