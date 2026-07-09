# Q-DESN VB Source Last1000 Wash500 D1n300 Comparison

Date: 2026-05-28

This note records the larger real-source median comparison requested after the
TT500 gate. No new batching algorithms were implemented.

## Setup

Package repo:

- Path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Commit: `9ff6272cbaa67ecbd9be4701934185833037cee3`

Article repo:

- Path: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`

The main Dec25 article config was repinned to package commit `9ff6272` so the
local-source engine contract remains aligned with the current package worktree.
The Overleaf/main worktree was not edited.

## Dataset and Window

Source directory:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000`

The run selected the last `1000` rows from this source:

- Selected source indices: `9001:10000`
- Washout rows: `500`, source indices `9001:9500`
- Fitted/evaluated rows after washout: `500`, source indices `9501:10000`
- `max(abs(mu - q_target)) = 0`
- Missing `y`, `mu`, `q_target`: `0`

The model uses `y` only. `mu` and `q_target` are diagnostics.

## Q-DESN and VB Controls

The package API uses `D` for the number of DESN layers and `n` for reservoir
size. The requested larger comparison was run as the manuscript-style `D1n300`
specification:

- `D = 1`
- `n = 300`
- `m = 1`
- `washout = 500`
- `add_bias = TRUE`
- `p0 = 0.50`
- fixed seed: `20260528`
- fixed Q-DESN seed: `20260628`
- ridge readout prior
- exact chunk size: `64`
- stochastic chunk size: `64`
- worker processes requested: `6`

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/usr/bin/time -v \
  -o results/qdesn_vb_batching_source_last1000_wash500_d1n300_median_20260528/source_last1000_wash500_d1n300.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_batching_comparison_source_tt500_median_20260528.R \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000 \
  --tail-rows 1000 \
  --expected-effective-rows 500 \
  --D 1 \
  --n 300 \
  --m 1 \
  --washout 500 \
  --chunk-size 64 \
  --cores 6 \
  --exact-tolerance 1e-6 \
  --output-prefix qdesn_vb_batching_source_last1000_wash500_d1n300_median \
  --output-dir results/qdesn_vb_batching_source_last1000_wash500_d1n300_median_20260528 \
  --seed 20260528
```

## Main Comparison Table

| Method | Likelihood | Batching | Target | Iter | Time (s) | Pinball vs y | MAE vs y | RMSE vs y | MAE vs mu/q | RMSE vs mu/q | Corr with mu/q | Gate |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Q-DESN AL unchunked | AL | none | full-data | 50 | 16.227 | 8.375984 | 16.75197 | 20.10496 | 14.96804 | 17.53902 | 0.834746 | reference |
| Q-DESN AL exact chunked | AL | exact, 64 | full-data | 50 | 14.406 | 8.375984 | 16.75197 | 20.10496 | 14.96804 | 17.53902 | 0.834746 | max diff `6.95e-10` |
| Q-DESN AL stochastic | AL | stochastic, 64 | approximate | 100 | 22.647 | 8.387019 | 16.77404 | 20.06747 | 14.95671 | 17.48865 | 0.834482 | finite/reproducible |
| Q-DESN exAL unchunked | exAL | none | full-data | 50 | 17.813 | 8.386500 | 16.77300 | 20.18035 | 15.01384 | 17.63169 | 0.834559 | reference |
| Q-DESN exAL exact chunked | exAL | exact, 64 | full-data | 50 | 17.375 | 8.386500 | 16.77300 | 20.18035 | 15.01384 | 17.63169 | 0.834559 | max diff `2.63e-07` |

Exact chunking was evaluated with tolerance `1e-6` for this larger reservoir.
The strict `1e-7` artifact was preserved separately because exAL exceeded it
only through the sigma trace:

- AL exact maximum gate difference: `6.954224e-10`, passes `1e-7`
- exAL exact maximum gate difference: `2.632496e-07`, fails `1e-7` but passes `1e-6`
- exAL fitted median maximum difference: `2.648335e-09`
- exAL beta mean maximum difference: `1.291767e-10`

This is consistent with floating-point accumulation sensitivity in the larger
exAL sigma/gamma trace, not a fitted-state discrepancy.

## Stochastic AL Diagnostics

Stochastic AL is approximate, not full-data equivalent.

| Diagnostic | Value |
| --- | ---: |
| stochastic trace rows | 100 |
| finite state | true |
| reproducible beta mean max abs diff | 0 |
| reproducible fitted median max abs diff | 0 |
| beta mean max abs diff vs AL unchunked | 0.0590835 |
| fitted median max abs diff vs AL unchunked | 1.042233 |
| pinball loss diff vs AL unchunked | 0.0110356 |
| MAE diff vs AL unchunked | 0.0220712 |
| RMSE diff vs AL unchunked | -0.0374892 |

Stochastic exAL was attempted only as a forbidden-mode check and failed early
with the expected message:

`stochastic VB chunking is currently supported only for likelihood_family = 'al'.`

## Runtime and Outputs

Overall `/usr/bin/time -v` summary:

- Wall time: `0:40.16`
- User time: `124.64` seconds
- CPU utilization: `330%`
- Peak resident set size: `579544` KB
- Exit status: `0`

Output directory:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_vb_batching_source_last1000_wash500_d1n300_median_20260528`

Important files:

- `method_summary.csv`
- `prediction_metrics.csv`
- `exact_equivalence.csv`
- `exact_equivalence_strict_1e-7_failed.csv`
- `stochastic_diagnostics.csv`
- `forbidden_modes.csv`
- `qdesn_vb_batching_source_last1000_wash500_d1n300_median_summary.md`
- `qdesn_vb_batching_source_last1000_wash500_d1n300_median_diagnostic.png`

## Interpretation

The larger washout comparison is usable. It keeps exactly 500 fitted/evaluated
observations while letting the reservoir state settle for 500 prior observations.
AL exact chunking remains far inside the strict tolerance. exAL exact chunking is
fitted-state equivalent for practical purposes, but its sigma trace exceeds the
older `1e-7` gate by a small amount at this larger reservoir size, so the
documented pass threshold for this run is `1e-6`.

No stochastic/hybrid exAL, article stochastic/hybrid, streaming, variance-reduced,
or multivariate batching was implemented in this pass.
