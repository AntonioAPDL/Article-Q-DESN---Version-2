# Normal/Q-DESN Manuscript Comparison Interpretation

Date: 2026-05-29

## Scope

This note records the first manuscript-prep interpretation layer for the
Normal DESN and Q-DESN source-median comparison. It is based on the
authoritative unified comparison run documented in:

```text
docs/implementation_notes/normal_qdesn_unified_source_median_comparison_20260529.md
```

The key policy decision for manuscript tables is:

- use `rhs_ns` as the default shrinkage prior;
- treat legacy `rhs` as a footnoted sensitivity/compatibility prior;
- keep diagonal covariance, subset, rolling, posterior-as-prior, online, and
  initialization rows out of the primary table unless they answer a specific
  workflow question.

## Repo State

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
comparison run HEAD: b415b4d Harden unified comparison preflight metadata
manuscript summarizer HEAD: afb196d Add Normal Q-DESN manuscript comparison summarizer
figure-prep HEAD: 784d336 Prepare RHS NS default comparison figures
```

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
```

Generated comparison outputs remain local and ignored in the package repo.

## Source

Frozen Gaussian median source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Metadata:

```text
scenario: dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast
family: normal
tau: 0.50
source rows: 500
source indices: 9501:10000
series_wide.csv sha256: e47b6845fe6452fe29904e6b686e893d3164419ea60fdf1f636669ef4baa8990
```

This is a bridge example: under Gaussian noise at `tau = 0.50`, the conditional
mean and target quantile coincide. That makes it appropriate for comparing a
Normal DESN mean readout against Q-DESN median readouts without claiming that
mean and quantile targets generally coincide.

## Reproducible Commands

The authoritative unified run was:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
rm -rf results/normal_qdesn_unified_source_median_20260529
mkdir -p results/normal_qdesn_unified_source_median_20260529

/usr/bin/time -v \
  -o results/normal_qdesn_unified_source_median_20260529/time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_normal_qdesn_unified_source_median_20260529.R \
  --output-dir results/normal_qdesn_unified_source_median_20260529 \
  --source-dir /data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500 \
  --seed 20260529 \
  --D 1 \
  --n 50 \
  --m 1 \
  --washout 50 \
  --chunk-size 64 \
  --subset-size 180 \
  --max-iter 25 \
  --stochastic-max-iter 60 \
  --hybrid-max-iter 60 \
  --hybrid-full-every 15 \
  --cores 4
```

The manuscript-prep summarizer and figures were then regenerated with:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/summarize_normal_qdesn_unified_report_20260529.R \
  --input-dir results/normal_qdesn_unified_source_median_20260529 \
  --output-dir results/normal_qdesn_unified_source_median_20260529/manuscript_ready

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/plot_normal_qdesn_manuscript_comparison_20260529.R \
  --input-dir results/normal_qdesn_unified_source_median_20260529 \
  --manuscript-dir results/normal_qdesn_unified_source_median_20260529/manuscript_ready \
  --output-dir results/normal_qdesn_unified_source_median_20260529/manuscript_ready/figures
```

## Prepared Outputs

Ignored package output root:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_qdesn_unified_source_median_20260529/
```

Prepared manuscript tables:

```text
manuscript_ready/manuscript_method_table.csv
manuscript_ready/manuscript_compact_methods.csv
manuscript_ready/manuscript_exact_gate_summary.csv
manuscript_ready/manuscript_approximate_summary.csv
manuscript_ready/normal_qdesn_manuscript_ready_summary.md
```

Prepared local figures:

```text
manuscript_ready/figures/figure_predictive_metrics.png
manuscript_ready/figures/figure_runtime_vs_loss.png
manuscript_ready/figures/figure_prediction_overlay.png
manuscript_ready/figures/figure_exact_gates.png
manuscript_ready/figures/figure_manifest.csv
manuscript_ready/figures/figure_input_hashes.csv
```

The figure manifest records non-empty outputs and input hashes. The generated
figures are intentionally not tracked yet.

## Compact Primary Table

The first manuscript table should start from the `manuscript_compact_methods`
schema. Current compact rows are:

| Method | Role | Prior | Primary | RHS_NS Default | Pinball | RMSE | Seconds |
|---|---|---|---:|---:|---:|---:|---:|
| Normal DESN, ridge | primary baseline | ridge | yes | no | 8.0060 | 19.4690 | 0.320 |
| Normal DESN, RHS_NS | diagnostic shrinkage baseline | rhs_ns | yes | yes | 8.5430 | 20.4021 | 0.482 |
| Q-DESN AL, ridge | primary baseline | ridge | yes | no | 8.5023 | 20.5573 | 0.460 |
| Q-DESN AL, ridge stochastic | approximate candidate | ridge | no | no | 8.5092 | 20.4380 | 1.692 |
| Q-DESN AL, ridge hybrid | approximate candidate | ridge | no | no | 8.5033 | 20.5016 | 1.864 |
| Q-DESN exAL, ridge | primary baseline | ridge | yes | no | 8.5095 | 20.6384 | 2.101 |
| Q-DESN exAL, ridge hybrid | approximate candidate | ridge | no | no | 8.5031 | 20.5069 | 2.610 |
| Q-DESN AL, RHS_NS | primary baseline | rhs_ns | yes | yes | 8.5105 | 20.5298 | 0.889 |
| Q-DESN exAL, RHS_NS | primary baseline | rhs_ns | yes | yes | 8.5120 | 20.6013 | 2.577 |
| Q-DESN exAL, RHS_NS hybrid | approximate candidate | rhs_ns | no | yes | 8.5138 | 20.4766 | 3.145 |

Legacy `rhs` rows remain in the full method table, but they are marked
`legacy_rhs_footnote = TRUE` and excluded from the compact primary table.

## Exact Gates

The unified run had:

```text
exact gates passed: 18 / 18
largest exact max absolute difference: 9.766773e-07
```

Interpretation:

- exact chunking remains an implementation-equivalence device, not a new
  statistical target;
- the largest gate difference came from Normal scaled-ridge covariance under
  deterministic chunked accumulation and passed the explicit `1e-6` gate;
- all Q-DESN exact gates passed with comfortable absolute or relative margins.

## Approximate Rows

The approximate rows are finite and reproducible under fixed seed:

| Comparison | Candidate | Pinball Diff vs Reference |
|---|---|---:|
| hybrid AL | Q-DESN AL ridge hybrid | 0.000985 |
| hybrid exAL | Q-DESN exAL RHS hybrid | 0.001754 |
| hybrid exAL | Q-DESN exAL RHS_NS hybrid | 0.001841 |
| hybrid exAL | Q-DESN exAL ridge hybrid | -0.006388 |
| stochastic AL | Q-DESN AL ridge stochastic | 0.006878 |

Interpretation:

- hybrid AL/exAL rows are promising approximate runtime/accuracy diagnostics;
- stochastic AL is available and reproducible, but should remain clearly labeled
  approximate;
- pure stochastic exAL remains forbidden.

## Diagnostic Rows

Diagonal covariance rows are finite and exact-chunked equivalent to their
diagonal-covariance targets, but they were predictively poor on this source
gate. They should not appear in the primary manuscript table.

Subset, rolling, posterior-as-prior, online, and initializer rows remain useful
workflow or sensitivity diagnostics. They should not be compared as if they
preserve the full-data target.

## Manuscript Claim Draft

For this Gaussian median bridge source:

1. Normal DESN scaled ridge is the best aligned Gaussian mean/median baseline.
2. Q-DESN AL/exAL full-data methods are finite, reproducible, and support the
   same DESN feature-map workflow.
3. `rhs_ns` is the default shrinkage prior for manuscript comparison; legacy
   `rhs` is retained only for footnoted compatibility/sensitivity checks.
4. Hybrid approximate rows are accurate enough on this gate to justify
   follow-up examples, but they must be labeled approximate.
5. Diagonal covariance is currently diagnostic-only.

## Next Step

Use the prepared figures and compact table to draft the first manuscript-facing
comparison panel. Then run the same pipeline on a non-median or non-Gaussian
source where Normal mean-readout is not naturally advantaged, so Q-DESN
quantile-specific behavior is tested more directly.
