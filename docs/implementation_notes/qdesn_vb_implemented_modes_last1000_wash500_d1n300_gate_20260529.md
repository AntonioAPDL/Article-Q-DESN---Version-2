# Q-DESN VB Implemented-Modes Last1000 Wash500 D1N300 Gate

Date: 2026-05-29

## Purpose

This note records the implemented-mode comparison on the controlled source
median dataset using a larger washout and a fixed 500 fitted-row target. It is
a package Q-DESN gate, not an article GloFAS run.

## Repo State

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- source-gate HEAD: `71cac6c`
- VB stage commit included in history: `4912699 Extend hybrid exAL and subset comparison modes`
- later package checkpoint: `0f5d4f6 Fix Normal DESN comparison dirty-state metadata`

The package branch contains unrelated Normal DESN commits after the Q-DESN VB
stage. The Q-DESN implemented-mode gate was rerun at source-gate HEAD
`71cac6c`, after the Normal DESN forecast stage and before the later
Normal-only comparison metadata fix `0f5d4f6`. The `0f5d4f6` commit does not
alter the Q-DESN VB algorithms or this gate's conclusions.

## Dataset

Source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT5000
```

Selection:

- source rows available: 5000;
- selected tail rows: 1000;
- selected source indices: 9001:10000;
- response: `y`;
- diagnostic truth: `mu` / `q_target`;
- `mu == q_target`: true.

The fit uses `y` only. `mu` and `q_target` are diagnostics.

## Q-DESN Settings

- tau: 0.50;
- `D = 1`;
- reservoir size `n = 300`;
- lag `m = 1`;
- washout: 500;
- effective fitted rows: 500;
- chunk size: 64;
- subset size: 180;
- seed: 20260529;
- cores: 6;
- rolling/posterior-as-prior/online workflow rows skipped in this gate with
  `--skip-workflows`.

Workflow diagnostics were skipped because this source-scale gate is intended to
exercise currently implemented static/readout modes. Rolling and online modes
already have focused unit tests and smaller workflow gates.

## Command

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
OUT=results/qdesn_vb_implemented_modes_source_last1000_wash500_d1n300_20260529_current_head
rm -rf "$OUT"
mkdir -p "$OUT"
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
  --exact-relative-tolerance 1e-7 \
  --skip-workflows \
  --output-dir "$OUT" \
  --seed 20260529
```

## Outputs

Output directory:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/qdesn_vb_implemented_modes_source_last1000_wash500_d1n300_20260529_current_head
```

Important files:

- `repo_state.csv`;
- `method_summary.csv`;
- `prediction_metrics.csv`;
- `exact_equivalence.csv`;
- `approximate_diagnostics.csv`;
- `target_changing_diagnostics.csv`;
- `forbidden_modes.csv`;
- `implemented_modes_comparison_summary.md`;
- `console.log`;
- `time.log`.

Generated result files remain under package `results/` and were not committed.

## Methods Exercised

The gate ran 29 method rows, including:

- AL ridge full-data, exact chunked, stochastic, hybrid, diagonal covariance;
- AL ridge fixed subset, proportional time-block subset, equal time-block
  subset, and exact chunked subset variants;
- AL RHS/RHS_NS full-data, exact chunked, and diagonal covariance;
- exAL ridge full-data, exact chunked, and hybrid;
- exAL RHS/RHS_NS full-data, exact chunked, and hybrid.

Deliberately excluded:

- stochastic exAL;
- exAL diagonal covariance;
- low-rank covariance;
- divide-and-combine VB;
- variational coresets;
- article GloFAS adapters.

## Exact Equivalence

Exact-equivalence gate:

- rows: 12;
- passed: 12;
- absolute tolerance: `1e-6`;
- relative tolerance: `1e-7`;
- max absolute gate difference: `0.0001637543`;
- max relative gate difference: `3.180675e-08`.

The largest absolute difference occurred on a large-scale diagonal-covariance
comparison and passed by the documented relative tolerance. This is acceptable
for the current gate because diagonal covariance can produce large-magnitude
state components while preserving tight relative agreement.

## Approximate Diagnostics

All approximate rows were finite and fixed-seed reproducible where repeat rows
exist.

| method | target label | pinball_y | rmse_q_target |
| --- | --- | ---: | ---: |
| AL ridge stochastic | full_data_approx_stochastic | 8.389297 | 17.50789 |
| AL ridge hybrid | full_data_approx_hybrid | 8.383308 | 17.52995 |
| exAL ridge hybrid | full_data_approx_hybrid | 8.383377 | 17.52954 |
| exAL RHS hybrid | full_data_approx_hybrid | 8.384392 | 17.52386 |
| exAL RHS_NS hybrid | full_data_approx_hybrid | 8.384392 | 17.52386 |

Hybrid exAL repeat beta-mean max difference: 0 for ridge, RHS, and RHS_NS.

## Target-Changing Diagnostics

Subset rows are target-changing and do not preserve the full-data posterior
target.

| method | target label | pinball_y | rmse_q_target |
| --- | --- | ---: | ---: |
| equal time-block subset | subset_target | 8.403154 | 17.71687 |
| equal time-block subset exact chunked | subset_target | 8.403154 | 17.71687 |

Rolling/posterior-as-prior/online workflow diagnostics were intentionally
skipped in this source-scale gate and recorded as `workflow_skipped`.

## Runtime and Memory

`/usr/bin/time -v`:

- wall time: 2:23.57;
- user time: 679.81 seconds;
- system time: 30.60 seconds;
- CPU: 494 percent;
- max resident set size: 922792 KB;
- exit status: 0.

## Pass/Fail Decision

Pass.

The source-gate run passed exact equivalence, approximate finite-state and
reproducibility checks, and forbidden-mode checks.

## Next Step

Use this gate as the compact comparison readiness baseline. The next
implementation stage should be chosen from unresolved gated modes, with exAL
diagonal covariance remaining blocked until its exact-chunking feedback issue
is resolved.
