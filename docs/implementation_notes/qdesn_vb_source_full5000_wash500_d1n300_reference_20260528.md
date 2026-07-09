# Q-DESN VB Full5000 Wash500 D1n300 Reference

Date: 2026-05-28

This note records the full-source VB reference run requested after the smaller
last1000/wash500 comparison. No new batching algorithms were implemented.

## Setup

Package repo:

- Path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Commit: `9ff6272cbaa67ecbd9be4701934185833037cee3`

Source directory:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000`

Window:

- Selected rows: `5000`, source indices `5001:10000`
- Washout: `500`
- Fitted/evaluated rows: `4500`, source indices `5501:10000`
- `max(abs(mu - q_target)) = 0`
- Missing `y`, `mu`, `q_target`: `0`

Q-DESN:

- `D = 1`
- `n = 300`
- `m = 1`
- `washout = 500`
- `add_bias = TRUE`
- `p0 = 0.50`
- fixed seed: `20260528`
- fixed Q-DESN seed: `20260628`
- ridge readout prior
- exact chunk size: `512`
- worker processes requested: `6`

The model used `y` only. `mu` and `q_target` were diagnostics.

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/usr/bin/time -v \
  -o results/qdesn_vb_batching_source_full5000_wash500_d1n300_median_20260528/source_full5000_wash500_d1n300.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_batching_comparison_source_tt500_median_20260528.R \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000 \
  --expected-effective-rows 4500 \
  --D 1 \
  --n 300 \
  --m 1 \
  --washout 500 \
  --chunk-size 512 \
  --cores 6 \
  --exact-tolerance 1e-6 \
  --output-prefix qdesn_vb_batching_source_full5000_wash500_d1n300_median \
  --output-dir results/qdesn_vb_batching_source_full5000_wash500_d1n300_median_20260528 \
  --seed 20260528
```

## Comparison Table

| Method | Likelihood | Batching | Target | Iter | Time (s) | Pinball vs y | MAE vs y | RMSE vs y | MAE vs mu/q | RMSE vs mu/q | Corr with mu/q | Gate |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Q-DESN AL unchunked | AL | none | full-data | 50 | 140.637 | 11.14132 | 22.28264 | 27.27791 | 20.79950 | 25.39778 | 0.831031 | stochastic reference |
| Q-DESN AL exact chunked | AL | exact, 512 | full-data | 50 | 65.020 | 11.14132 | 22.28264 | 27.27791 | 20.79950 | 25.39778 | 0.831031 | max diff `1.13e-09` |
| Q-DESN AL stochastic | AL | stochastic, 512 | approximate | 100 | 102.063 | 11.15269 | 22.30538 | 27.30639 | 20.82570 | 25.42890 | 0.831200 | finite/reproducible |
| Q-DESN exAL unchunked | exAL | none | full-data | 50 | 141.370 | 11.14115 | 22.28230 | 27.27751 | 20.79854 | 25.39721 | 0.831037 | reference |
| Q-DESN exAL exact chunked | exAL | exact, 512 | full-data | 50 | 66.569 | 11.14115 | 22.28230 | 27.27751 | 20.79854 | 25.39721 | 0.831037 | max diff `6.68e-08` |

Exact chunking was evaluated with tolerance `1e-6` and passed:

- AL exact maximum gate difference: `1.132776e-09`
- exAL exact maximum gate difference: `6.676627e-08`

Stochastic AL diagnostics against AL unchunked:

- finite state: true
- reproducible beta mean max absolute difference: `0`
- reproducible fitted median max absolute difference: `0`
- beta mean max absolute difference vs AL unchunked: `1.485948`
- fitted median max absolute difference vs AL unchunked: `0.3509501`
- pinball loss difference vs AL unchunked: `0.01136673`
- MAE difference vs AL unchunked: `0.02273345`
- RMSE difference vs AL unchunked: `0.02848599`

Stochastic AL remains approximate, not full-data equivalent.

## exAL Stochastic Status

exAL stochastic was not implemented or produced. The comparison harness attempts
`qdesn_exal_stochastic` only as a forbidden-mode check. It failed early with the
expected message:

`stochastic VB chunking is currently supported only for likelihood_family = 'al'.`

Approximate exAL batching remains gated pending a separate sigma/gamma stochastic
contract and tests.

## Runtime and Outputs

Overall `/usr/bin/time -v` summary:

- Wall time: `2:42.77`
- User time: `626.68` seconds
- CPU utilization: `392%`
- Peak resident set size: `896556` KB
- Exit status: `0`

Output directory:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_vb_batching_source_full5000_wash500_d1n300_median_20260528`

Important files:

- `method_summary.csv`
- `prediction_metrics.csv`
- `exact_equivalence.csv`
- `stochastic_diagnostics.csv`
- `forbidden_modes.csv`
- `qdesn_vb_batching_source_full5000_wash500_d1n300_median_summary.md`
- `qdesn_vb_batching_source_full5000_wash500_d1n300_median_diagnostic.png`

## Interpretation

The full-data unchunked AL VB fit is now available as the reference for the
stochastic AL approximation on the same `D1n300`, washout-500 specification.
Exact chunking remains full-data equivalent. Stochastic AL remains close in
predictive metrics but is explicitly approximate. Stochastic exAL remains
unimplemented and correctly gated.
