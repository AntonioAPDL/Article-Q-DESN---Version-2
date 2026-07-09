# Normal/Q-DESN Unified Source-Median Comparison

Date: 2026-05-29

## Scope

This note records the first authoritative unified comparison across the
currently implemented Normal DESN and Q-DESN AL/exAL modes. It uses the frozen
Gaussian median source from the shared validation study, where the conditional
mean and median coincide (`q_true = mu`).

Generated outputs are local and ignored in the package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_qdesn_unified_source_median_20260529/
```

No generated result files were committed.

## Repo State

Package repo:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
branch: validation/shared-fitforecast-v2-1.0.0
comparison HEAD: b415b4d Harden unified comparison preflight metadata
manuscript-prep HEAD: afb196d Add Normal Q-DESN manuscript comparison summarizer
dirty at run time: FALSE
```

Article repo:

```text
/data/jaguir26/local/src/Article-Q-DESN
branch: application-ensemble-likelihood-redesign
```

The article worktree still has unrelated untracked GloFAS memory-refinement
files. They were not touched.

## Dataset

Source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Source details:

```text
scenario: dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast
family: normal
tau: 0.50
source rows: 500
source indices: 9501:10000
series_wide.csv sha256: e47b6845fe6452fe29904e6b686e893d3164419ea60fdf1f636669ef4baa8990
```

DESN settings:

```text
D = 1
n = 50
m = 1
washout = 50
effective fitted rows = 450
chunk_size = 64
subset_size = 180
seed = 20260529
max_iter = 25
stochastic_max_iter = 60
hybrid_max_iter = 60
hybrid_full_every = 15
cores = 4
```

## Command

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

## Outputs

The unified launcher wrote:

```text
repo_state.csv
component_runs.csv
method_summary.csv
prediction_metrics.csv
exact_equivalence.csv
approximate_diagnostics.csv
target_changing_diagnostics.csv
initializer_diagnostics.csv
forbidden_modes.csv
predictions_by_method.csv
normal_qdesn_unified_comparison_summary.md
console.log
time.log
```

The manuscript-prep summarizer was then run on the same ignored result root:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/summarize_normal_qdesn_unified_report_20260529.R \
  --input-dir results/normal_qdesn_unified_source_median_20260529 \
  --output-dir results/normal_qdesn_unified_source_median_20260529/manuscript_ready
```

It produced local/ignored manuscript-prep artifacts:

```text
manuscript_ready/manuscript_method_table.csv
manuscript_ready/manuscript_compact_methods.csv
manuscript_ready/manuscript_exact_gate_summary.csv
manuscript_ready/manuscript_approximate_summary.csv
manuscript_ready/manuscript_pinball_overview.pdf
manuscript_ready/normal_qdesn_manuscript_ready_summary.md
```

Component runtimes:

| Component | Status | Seconds |
|---|---:|---:|
| normal_source | 0 | 34.18 |
| normal_init | 0 | 47.20 |
| qdesn_implemented_modes | 0 | 110.23 |

Total timed wrapper run:

```text
elapsed wall time: 3:13.33
max RSS: 632256 KB
exit status: 0
```

## Gates

Overall:

```text
method rows: 51
finite-state failures: 0
exact gates passed: 18 / 18
largest exact max absolute difference: 9.766773e-07
```

The largest exact difference came from the Normal scaled-ridge covariance
summary under deterministic chunked accumulation. It passed the explicit
`1e-6` exact gate; fitted means and predictions were much tighter.

Forbidden/deferred checks:

| Mode | Result |
|---|---|
| stochastic exAL | failed early as expected |
| exAL RHS/RHS_NS diagonal covariance | failed early as expected |
| divide-and-combine VB | deferred |
| variational coresets | deferred |

## Approximate Diagnostics

Approximate and covariance-diagnostic rows were finite.

| Comparison | Candidate | Reproducible Beta Diff | Pinball Diff vs Reference |
|---|---|---:|---:|
| stochastic AL | qdesn_al_ridge_stochastic | 0 | 0.006878 |
| hybrid AL | qdesn_al_ridge_hybrid | 0 | 0.000985 |
| hybrid exAL | qdesn_exal_ridge_hybrid | 0 | -0.006388 |
| hybrid exAL | qdesn_exal_rhs_hybrid | 0 | 0.001754 |
| hybrid exAL | qdesn_exal_rhs_ns_hybrid | 0 | 0.001841 |

Diagonal covariance rows were finite and exact-chunked equivalent to their
diagonal targets, but predictive diagnostics were poor on this source gate:

| Candidate | Pinball Diff vs Reference |
|---|---:|
| qdesn_al_ridge_diagonal | 92.15 |
| qdesn_al_rhs_diagonal | 710.61 |
| qdesn_al_rhs_ns_diagonal | 207.44 |
| qdesn_exal_ridge_diagonal | 290.69 |

Interpretation: diagonal covariance remains a supported diagnostic
approximation, not a recommended default for this example.

## Target-Changing Diagnostics

Subset rows were finite and exact-chunked equivalent to their own subset
targets. They are not full-data replacements.

Rolling, posterior-as-prior, and online AL ridge workflow rows were finite and
recorded no-future-leakage metadata. Online exact chunking matched online
unchunked state handoff.

## Initializer Diagnostics

Normal DESN serialized warm starts were present and validated:

| Warm Start | Normal Target | Exact Status | Prior | Beta Dim |
|---|---|---|---|---:|
| normal_scaled_ridge | normal_scaled_ridge_exact | exact | scaled_ridge | 51 |
| normal_rhs_ns_vb | normal_rhs_ns_vb_approx | approximate_vb | rhs_ns | 51 |

Normal-initialized AL/exAL VB rows were finite. These rows are workflow
diagnostics, not distinct posterior targets.

## Interpretation

This run confirms the system is now regularized enough for comparison work:

- Normal DESN exact ridge and exact chunked ridge are wired and comparable.
- Normal DESN RHS_NS is available as an approximate Gaussian readout.
- Normal DESN warm starts serialize, validate, and seed AL/exAL workflows.
- Q-DESN AL/exAL exact chunking remains full-data equivalent.
- Q-DESN stochastic/hybrid modes are finite and reproducible where implemented.
- Subset, rolling, posterior-as-prior, and online rows are clearly
  target-changing/workflow diagnostics.
- Forbidden modes fail early or remain explicitly deferred.

The manuscript-prep pass recommends using full-covariance Normal ridge and
Q-DESN AL/exAL ridge/RHS/RHS_NS rows as the primary comparison spine. It keeps
stochastic and hybrid rows as explicitly approximate speed/accuracy diagnostics,
keeps subset/rolling/posterior-as-prior/online/initializer rows as workflow or
sensitivity diagnostics, and excludes diagonal covariance rows from the primary
table for this source gate because they are finite but predictively poor here.

## Remaining Work

The main comparison infrastructure is ready. Remaining method-development
items stay gated:

- pure stochastic exAL;
- exAL RHS/RHS_NS diagonal covariance;
- low-rank covariance;
- Normal exogenous/decomposition-aware forecast extensions;
- article-side stochastic/hybrid/rolling/online adapters;
- divide-and-combine VB;
- variational coresets.

## Next Step

Use this unified comparison output to choose the compact set of methods for the
next manuscript-quality example table/figure. The generated CSVs under the
package result root are the authoritative source for that summarization pass.
The `manuscript_ready/` artifacts are now the prepared starting point for the
first compact table and overview figure.
