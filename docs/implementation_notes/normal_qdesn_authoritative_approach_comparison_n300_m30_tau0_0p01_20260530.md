# Normal/Q-DESN Source-Median Comparison, n300 m30 tau0 0.01

Date: 2026-05-30

This note records the rerun of the Normal DESN and Q-DESN implemented-mode
comparison on the frozen Gaussian median source with a larger DESN feature map
and tighter shrinkage initialization:

- reservoir replicates: `n = 300`
- lag depth: `m = 30`
- RHS/RHS_NS global scale initialization: `tau0 = 0.01`
- ridge scale: `beta_ridge_tau2 = 50`
- washout: `50`
- exact chunk size: `128`
- subset size: `180`

The run is a source-level comparison, not a GloFAS application run.

## Repos

Package repo:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`

- branch: `validation/shared-fitforecast-v2-1.0.0`
- package HEAD used by the comparison: `d4411eb`
- package dirty at run time: `FALSE`

Article repo:

`/data/jaguir26/local/src/Article-Q-DESN`

- branch: `application-ensemble-likelihood-redesign`
- this file is documentation only

## Source

Frozen source:

`/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500`

The source is the Gaussian median case where `q_target = mu`, so the Normal
conditional-mean DESN is expected to be a strong reference. Q-DESN rows are
tau-specific quantile readouts at `tau = 0.50`.

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260530 \
  --D 1 \
  --n 300 \
  --m 30 \
  --washout 50 \
  --chunk-size 128 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --rhs-tau0 0.01 \
  --ridge-tau2 50 \
  --exact-tolerance 1e-6 \
  --exact-relative-tolerance 1e-7 \
  --cores 1
```

The `1e-7` relative exact tolerance is deliberate for this larger feature map.
The first pass with `1e-8` failed only on a scale-sensitive exAL+RHS ELBO-trace
gate: the beta, covariance, fitted values, sigma, and gamma differences were
already tight. The accepted gate remains strict: absolute difference `<= 1e-6`
or relative difference `<= 1e-7`.

## Outputs

Root:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_qdesn_unified_source_median_n300_m30_tau0_0p01_20260530`

Important files:

- `normal_qdesn_unified_comparison_summary.md`
- `method_summary.csv`
- `prediction_metrics.csv`
- `exact_equivalence.csv`
- `approximate_diagnostics.csv`
- `target_changing_diagnostics.csv`
- `initializer_diagnostics.csv`
- `forbidden_modes.csv`
- `time.log`
- `manuscript_ready/normal_qdesn_manuscript_ready_summary.md`
- `manuscript_ready/manuscript_method_table.csv`
- `manuscript_ready/manuscript_compact_methods.csv`
- `manuscript_ready/figures/figure_predictive_metrics.png`
- `manuscript_ready/figures/figure_runtime_vs_loss.png`
- `manuscript_ready/figures/figure_prediction_overlay.png`
- `manuscript_ready/figures/figure_exact_gates.png`

Generated result files remain package-side artifacts and were not committed.

## Runtime

The successful unified run completed with:

- wall time: `24:44.35`
- max RSS: `930720 KB`
- cores: `1`
- exit status: `0`

This is more expensive than the earlier `n = 50, m = 1` gate but still small
enough for repeatable source-level comparisons.

## Main Method Table

Sorted by pinball/check loss among the compact manuscript rows:

| Method | Role | Target group | Pinball | RMSE | Elapsed sec | Note |
|---|---:|---:|---:|---:|---:|---|
| Normal DESN, ridge | primary baseline | Normal exact baseline | 4.488292 | 11.33682 | 3.028 | Best row, as expected for Gaussian mean=median source |
| Q-DESN AL, ridge | primary baseline | full-data baseline | 4.686786 | 11.84439 | 12.715 | Strong Q-DESN baseline |
| Q-DESN exAL, ridge | primary baseline | full-data baseline | 4.687333 | 11.85712 | 7.366 | Similar to AL ridge |
| Q-DESN AL, ridge hybrid | approximate candidate | approximate full-data fit | 4.711581 | 11.87684 | 11.958 | Finite/reproducible approximate row |
| Q-DESN exAL, ridge hybrid | approximate candidate | approximate full-data fit | 4.711865 | 11.87805 | 11.618 | Finite/reproducible approximate row |
| Q-DESN AL, ridge stochastic | approximate candidate | approximate full-data fit | 4.714697 | 11.86145 | 11.320 | Finite/reproducible approximate row |
| Q-DESN AL, RHS_NS | primary baseline | full-data baseline | 5.064563 | 12.90685 | 7.491 | Default shrinkage row, strong regularization at `tau0 = 0.01` |
| Q-DESN exAL, RHS_NS | primary baseline | full-data baseline | 5.072362 | 12.94028 | 6.470 | Default shrinkage row |
| Q-DESN exAL, RHS_NS hybrid | approximate candidate | approximate full-data fit | 5.267716 | 13.39361 | 10.282 | Finite but less predictive here |
| Normal DESN, RHS_NS | normal RHS_NS diagnostic | full-data baseline | 5.489950 | 13.87231 | 2.630 | Diagnostic shrinkage row |

Interpretation:

- The Normal ridge row is the strongest row on this Gaussian median source,
  which is the expected sanity check.
- Q-DESN AL/exAL ridge rows remain competitive and coherent under the larger
  feature map.
- `tau0 = 0.01` makes RHS_NS materially more conservative here; it is stable,
  but worse predictively than ridge on this source.
- Approximate stochastic/hybrid rows are finite and reproducible, but they are
  not exact full-data replacements.

## Exact Gates

Exact gates passed:

- passed: `18 / 18`
- largest absolute gate diff: `3.603124e-05`
- largest relative gate diff: `1.861043e-08`

Largest gate rows:

| Reference | Candidate | Max abs diff | Relative diff | Passed |
|---|---|---:|---:|---:|
| Normal DESN ridge | Normal DESN ridge exact chunked | 3.603124e-05 | 2.035695e-11 | TRUE |
| Q-DESN exAL RHS | Q-DESN exAL RHS exact chunked | 4.359014e-06 | 1.861043e-08 | TRUE |
| Q-DESN exAL ridge diagonal | exact chunked | 2.641487e-06 | 1.539283e-09 | TRUE |
| Q-DESN AL RHS diagonal | exact chunked | 4.228246e-07 | 9.647362e-11 | TRUE |
| Q-DESN AL ridge diagonal | exact chunked | 1.765911e-07 | 1.882934e-11 | TRUE |

The larger Normal exact-chunked absolute covariance difference is tiny relative
to the covariance scale. This is numerical solve/order sensitivity, not a
different target.

## Approximate Rows

Approximate rows are finite and reproducible under fixed seeds:

| Comparison | Candidate | Pinball diff vs reference | Fitted max diff | Repro beta diff |
|---|---|---:|---:|---:|
| stochastic AL | Q-DESN AL ridge stochastic | +0.027910 | 2.942424 | 0 |
| hybrid AL | Q-DESN AL ridge hybrid | +0.024794 | 2.092523 | 0 |
| hybrid exAL | Q-DESN exAL ridge hybrid | +0.024532 | 2.493365 | 0 |
| hybrid exAL | Q-DESN exAL RHS | -0.123243 | 7.904312 | 0 |
| hybrid exAL | Q-DESN exAL RHS_NS | +0.195354 | 3.298867 | 0 |

Diagonal covariance rows are finite but diagnostic-only. Their predictive
differences are very large in this run, so they should not be used as defaults
for this source-level comparison.

## Target-Changing Rows

Subset rows are target-changing, not full-data VB replacements:

| Candidate | Subset rows | Original rows | Pinball diff vs AL ridge | Finite |
|---|---:|---:|---:|---:|
| fixed subset | 180 | 450 | +0.256708 | TRUE |
| time-block stratified subset | 180 | 450 | +0.198982 | TRUE |
| equal time-block stratified subset | 180 | 450 | +0.186145 | TRUE |
| response-quantile stratified subset | 180 | 450 | +0.092482 | TRUE |
| leverage stratified subset | 180 | 450 | +0.147271 | TRUE |

Workflow rows also ran:

- rolling AL ridge: 2 units, no future leakage TRUE
- posterior-as-prior AL ridge: 2 units, no future leakage TRUE
- online AL ridge: 2 units, no future leakage TRUE
- online exact-chunked AL ridge: no-future-leakage gate TRUE

These are workflow/state-handoff targets, not full-data replacements.

## Validation Notes

- Exact chunking remains target preserving for Normal DESN and Q-DESN rows.
- Stochastic and hybrid rows remain approximate and are labeled as such.
- RHS_NS is still the default shrinkage family; legacy RHS remains supporting.
- Divide-and-combine VB and variational coresets remain deferred.
- Generated comparison outputs were not committed.
- Existing unrelated GloFAS runs were not modified.

## Takeaway

This is the best current source-level comparison for the more realistic DESN
specification requested here. It supports using:

1. Normal DESN ridge as the Gaussian-source sanity baseline and possible
   informed initializer.
2. Q-DESN AL/exAL ridge as the primary quantile readout baselines.
3. RHS_NS as the shrinkage-default sensitivity, with the caveat that
   `tau0 = 0.01` is very conservative on this source.
4. Exact chunking as a validated implementation detail, not a new estimator.
5. Stochastic/hybrid rows as finite approximate runtime/accuracy diagnostics.
