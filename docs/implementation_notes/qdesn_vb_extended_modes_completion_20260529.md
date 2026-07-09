# Q-DESN VB Extended Modes Completion

Date: 2026-05-29

## Purpose

This note closes the current extended-mode pass requested after the hybrid exAL
and subset stages. It records the polished implemented-mode comparison, the
resolved exAL ridge diagonal covariance gate, the richer subset strata, and the
remaining stop gates.

## Repo State

- article repo: `/data/jaguir26/local/src/Article-Q-DESN`
- article branch: `application-ensemble-likelihood-redesign`
- package repo:
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- package branch: `validation/shared-fitforecast-v2-1.0.0`
- package commit: `f0d45ea Extend Q-DESN VB comparison and subset modes`

The comparison run recorded package HEAD `0f5d4f6` and was then completed by
committing the implementation and summarizer changes as `f0d45ea`.

## Implemented In This Pass

Package:

- added a polished implemented-mode report summarizer:
  `scripts/summarize_qdesn_vb_implemented_modes_report_20260529.R`;
- added response-quantile and design-leverage stratified subset controls for AL
  ridge subset-data VB;
- extended the source-median comparison harness to include those richer subset
  rows;
- reopened exAL diagonal covariance only for ridge priors, with exact-chunked
  equivalence gates;
- kept exAL RHS/RHS_NS diagonal covariance forbidden;
- kept stochastic exAL forbidden.

Article:

- documentation only. No application code or config changed.

## Source Comparison

Command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
OUT=results/qdesn_vb_implemented_modes_last1000_wash500_d1n300_extended_20260529
/usr/bin/time -v -o "$OUT/time.log" \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_implemented_modes_source_median_20260528.R \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000 \
  --tail-rows 1000 \
  --expected-effective-rows 500 \
  --D 1 \
  --n 300 \
  --m 1 \
  --washout 500 \
  --chunk-size 64 \
  --subset-size 180 \
  --cores 6 \
  --exact-tolerance 1e-6 \
  --exact-relative-tolerance 1e-6 \
  --skip-workflows \
  --output-dir "$OUT" \
  --seed 20260529
```

Polished summary:

```sh
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/summarize_qdesn_vb_implemented_modes_report_20260529.R \
  --input-dir results/qdesn_vb_implemented_modes_last1000_wash500_d1n300_extended_20260529
```

Local outputs:

- `results/qdesn_vb_implemented_modes_last1000_wash500_d1n300_extended_20260529/polished_method_table.csv`
- `results/qdesn_vb_implemented_modes_last1000_wash500_d1n300_extended_20260529/polished_comparison_report.md`

These result files are ignored local artifacts and were not committed.

## Gate Results

- methods run: 35;
- exact gates: 15/15 passed;
- largest exact-gate absolute difference: `1.638e-04`;
- largest exact-gate relative difference: `3.181e-08`;
- elapsed wall time: `2:28.31`;
- max resident set size: `979868 KB`.

Important rows:

| method | target | finite | pinball_y | rmse_mu | exact max abs | exact max rel |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| AL ridge response subset | subset target | yes | 8.389557 | 17.62928 | 2.295e-10 | 1.093e-12 |
| AL ridge leverage subset | subset target | yes | 8.416776 | 17.80596 | 5.057e-10 | 2.423e-12 |
| exAL ridge diagonal | covariance approximation | yes | 166.227109 | 332.79075 | 9.288e-06 | 2.044e-09 |

The exAL ridge diagonal row is finite and exact-chunked equivalent under the
practical gate, but its predictive diagnostics are poor on this source. It is
therefore a supported covariance approximation for diagnostics and method
coverage, not a recommended predictive default.

## Tests

Focused post-change package tests:

| test file | result |
| --- | --- |
| `test-exal-subset-fit.R` | 121 pass |
| `test-exal-beta-covariance-approx.R` | 91 pass |
| `test-qdesn-vb-batching-modes.R` | 42 pass |
| `test-exal-exact-chunking-stats.R` | 38 pass |
| `test-exal-hybrid-exal-vb.R` | 80 pass |
| `test-exal-inference-config.R` | 203 pass |
| `test-static-beta-prior-rhs.R` | 110 pass |

Total: 685 pass, 0 fail.

## Remaining Gates

Still not implemented:

- pure stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- stochastic or hybrid diagonal covariance;
- RHS/RHS_NS or exAL subset targets;
- low-rank covariance;
- article-side stochastic, hybrid, rolling, online, or subset adapters;
- divide-and-combine VB;
- variational coresets.

Pure stochastic exAL should remain gated. Hybrid exAL is implemented, but pure
stochastic exAL still needs a separate contract for qv, qs, sigma/gamma, xi,
stale-local semantics, and noisy objective labels before any code path is
enabled.

## Recommended Next Stage

The next single implementation stage should be low-rank-plus-diagonal
covariance for AL ridge only, or a custom-strata subset interface if cheaper
screening comparisons become more important than covariance approximation.
Do not start pure stochastic exAL until the exAL-specific stochastic derivation
is complete and reviewed.
