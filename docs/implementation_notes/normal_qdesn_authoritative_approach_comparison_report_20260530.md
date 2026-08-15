# Normal DESN / Q-DESN Authoritative Approach Comparison Report

Date: 2026-05-30

## Executive Decision

This report is the current authoritative comparison gate for the completed
Normal DESN and Q-DESN source-median workflow. It supports the following
manuscript-facing decisions:

1. Use the full-covariance Normal DESN scaled-ridge row and the Q-DESN
   full-covariance AL/exAL rows as the primary comparison spine.
2. Use `rhs_ns` as the default shrinkage prior in manuscript comparisons.
3. Keep legacy `rhs` as a footnoted sensitivity/compatibility prior.
4. Treat stochastic and hybrid rows as approximate diagnostics, not exact
   replacements.
5. Keep diagonal covariance out of the primary table for this source because it
   is finite and exact-chunked equivalent to its own target, but predictively
   poor here.
6. Treat subset, rolling-window, posterior-as-prior, online, and initializer
   rows as workflow or target-changing diagnostics.

This report does not include the GloFAS memory-refinement batch as finished
evidence. Those runs were still active in `03_fit_models.R` during the
2026-05-30 health check and should be summarized separately after completion.

## Source And Scope

The completed comparison uses the frozen Gaussian median source:

```text
/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast/normal/tau_0p50/fit_input_lastTT500
```

Source metadata:

| Field | Value |
|---|---|
| scenario | `dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast` |
| family | `normal` |
| tau | `0.50` |
| source rows | `500` |
| fit rows after washout | `450` |
| source indices | `9501:10000` |
| series_wide.csv sha256 | `e47b6845fe6452fe29904e6b686e893d3164419ea60fdf1f636669ef4baa8990` |

The source is a bridge case: under Gaussian noise at `tau = 0.50`, the
conditional mean and the target quantile coincide. That makes the dataset
appropriate for checking whether Normal DESN mean readouts and Q-DESN median
readouts are wired coherently, but it is not a stress test of non-Gaussian or
tail quantile behavior.

## Reproducibility State

Package comparison run:

| Item | Value |
|---|---|
| package repo | `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0` |
| branch | `validation/shared-fitforecast-v2-1.0.0` |
| unified comparison HEAD at run | `b415b4d Harden unified comparison preflight metadata` |
| manuscript summarizer HEAD | `afb196d Add Normal Q-DESN manuscript comparison summarizer` |
| figure-prep HEAD | `784d336 Prepare RHS NS default comparison figures` |
| dirty at run time | `FALSE` |
| output root | `results/normal_qdesn_unified_source_median_20260529/` |

Article documentation state:

| Item | Value |
|---|---|
| article repo | `/data/jaguir26/local/src/Article-Q-DESN` |
| branch | `application-ensemble-likelihood-redesign` |
| prior interpretation note | `944b877 Document RHS NS default comparison interpretation` |

Main run settings:

| Setting | Value |
|---|---:|
| seed | `20260529` |
| DESN depth `D` | `1` |
| reservoir width `n` | `50` |
| lag/embedding `m` | `1` |
| washout | `50` |
| chunk size | `64` |
| subset size | `180` |
| VB max_iter | `25` |
| stochastic max_iter | `60` |
| hybrid max_iter | `60` |
| hybrid full refresh cadence | `15` |
| cores | `4` |
| wall time | `3:13.33` |
| peak RSS | `632256 KB` |

Important limitation: this is an economical comparison gate. Many VB rows are
finite but hit the `max_iter = 25` cap, so the report should be read as a
controlled implementation and approach-comparison check, not as the final
large-scale performance study.

## Reproducible Commands

Unified comparison:

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

Manuscript-ready summaries and figures:

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

## Output Inventory

Generated outputs remain local and ignored in the package repo. The key files
are:

```text
results/normal_qdesn_unified_source_median_20260529/
  component_runs.csv
  repo_state.csv
  method_summary.csv
  prediction_metrics.csv
  predictions_by_method.csv
  exact_equivalence.csv
  approximate_diagnostics.csv
  target_changing_diagnostics.csv
  initializer_diagnostics.csv
  forbidden_modes.csv
  normal_qdesn_unified_comparison_summary.md
  time.log
  manuscript_ready/
    manuscript_method_table.csv
    manuscript_compact_methods.csv
    manuscript_exact_gate_summary.csv
    manuscript_approximate_summary.csv
    normal_qdesn_manuscript_ready_summary.md
    manuscript_pinball_overview.pdf
    figures/
      figure_predictive_metrics.png
      figure_runtime_vs_loss.png
      figure_prediction_overlay.png
      figure_exact_gates.png
      figure_manifest.csv
      figure_input_hashes.csv
```

The manuscript-ready schema contains:

| Artifact | Count |
|---|---:|
| all manuscript method rows | `51` |
| compact primary rows | `10` |
| exact gate rows | `18` |
| approximate diagnostic rows | `9` |
| target-changing/workflow diagnostic rows | `10` |
| forbidden/deferred rows | `4` |
| initializer diagnostic rows | `10` |

## Approach Taxonomy

| Approach family | Status in this comparison | Primary use |
|---|---|---|
| Normal DESN scaled ridge | implemented, exact full-data baseline | Gaussian mean/median reference |
| Normal DESN RHS_NS VB | implemented, finite VB shrinkage diagnostic | Normal shrinkage baseline |
| Q-DESN AL ridge | implemented, full-data VB/CAVI baseline | main quantile baseline |
| Q-DESN exAL ridge | implemented, full-data VB/CAVI baseline | richer likelihood baseline |
| Q-DESN AL/exAL RHS_NS | implemented, full-data shrinkage baseline | default shrinkage comparison |
| exact chunking | implemented, full-data preserving | numerical equivalence and memory workflow |
| stochastic AL | implemented, approximate | runtime/accuracy diagnostic |
| hybrid AL/exAL | implemented, approximate | runtime/accuracy diagnostic |
| diagonal covariance | implemented for supported cases, approximate | diagnostic only here |
| fixed/stratified subsets | implemented, target-changing | sensitivity and cheaper screening |
| rolling/PAP/online | implemented for narrow AL ridge workflows | ordered-state handoff diagnostics |
| Normal DESN warm starts | implemented workflow support | initialization diagnostics |
| stochastic exAL | forbidden | fail-early until separately derived |
| exAL RHS/RHS_NS diagonal covariance | gated/forbidden | requires separate contract |
| divide-and-combine VB | deferred | research mode |
| variational coresets | deferred | research mode |

## Primary Manuscript Table

The compact table is the recommended first manuscript table. It excludes legacy
`rhs` and diagnostic-only covariance/subset/workflow rows.

| Method | Target group | Likelihood | Prior | Pinball | RMSE | Seconds |
|---|---|---|---|---:|---:|---:|
| Normal DESN, ridge | Normal exact baseline | normal | ridge | 8.0060 | 19.4690 | 0.320 |
| Normal DESN, RHS_NS | full-data baseline | normal | rhs_ns | 8.5430 | 20.4021 | 0.482 |
| Q-DESN AL, ridge | full-data baseline | al | ridge | 8.5023 | 20.5573 | 0.460 |
| Q-DESN AL, ridge stochastic | approximate full-data fit | al | ridge | 8.5092 | 20.4380 | 1.692 |
| Q-DESN AL, ridge hybrid | approximate full-data fit | al | ridge | 8.5033 | 20.5016 | 1.864 |
| Q-DESN exAL, ridge | full-data baseline | exal | ridge | 8.5095 | 20.6384 | 2.101 |
| Q-DESN exAL, ridge hybrid | approximate full-data fit | exal | ridge | 8.5031 | 20.5069 | 2.610 |
| Q-DESN AL, RHS_NS | full-data baseline | al | rhs_ns | 8.5105 | 20.5298 | 0.889 |
| Q-DESN exAL, RHS_NS | full-data baseline | exal | rhs_ns | 8.5120 | 20.6013 | 2.577 |
| Q-DESN exAL, RHS_NS hybrid | approximate full-data fit | exal | rhs_ns | 8.5138 | 20.4766 | 3.145 |

Interpretation:

- Normal DESN scaled ridge performs best on this Gaussian median bridge source,
  as expected because the mean and median targets coincide.
- Q-DESN AL/exAL full-data rows are stable and close to one another.
- `rhs_ns` is the default shrinkage story. Its performance is close to ridge
  for Q-DESN and gives the shrinkage comparison without elevating legacy `rhs`.
- Hybrid exAL ridge slightly improves pinball relative to its full-data ridge
  reference in this economical gate, but remains approximate and must be labeled
  that way.

## Exact Equivalence Gates

Exact chunking is not a new statistical method. It is an implementation device
that must preserve the same target as the unchunked row. The comparison passed
all exact gates:

```text
exact gates passed: 18 / 18
largest exact max absolute difference: 9.766773e-07
gate tolerance: 1e-6
```

The largest exact-gate difference came from the Normal scaled-ridge covariance
comparison. All Q-DESN exact and exact-chunked comparisons passed with small
absolute and/or relative discrepancies.

Largest exact-gate rows:

| Component | Comparison | Reference | Candidate | Max Gate Diff | Relative Diff | Passed |
|---|---|---|---|---:|---:|---|
| normal_source | exact chunking | normal_scaled_ridge | normal_scaled_ridge_exact_chunked | 9.767e-07 | NA | yes |
| qdesn_implemented_modes | diagonal exact chunking | qdesn_al_rhs_diagonal | qdesn_al_rhs_diagonal_exact | 7.387e-07 | 2.040e-10 | yes |
| qdesn_implemented_modes | diagonal exact chunking | qdesn_exal_ridge_diagonal | qdesn_exal_ridge_diagonal_exact | 2.103e-07 | 2.597e-10 | yes |
| qdesn_implemented_modes | diagonal exact chunking | qdesn_al_ridge_diagonal | qdesn_al_ridge_diagonal_exact | 1.825e-07 | 1.647e-10 | yes |
| qdesn_implemented_modes | exact chunking | qdesn_exal_rhs_full | qdesn_exal_rhs_exact | 8.543e-10 | 4.105e-12 | yes |
| qdesn_implemented_modes | exact chunking | qdesn_al_rhs_ns_full | qdesn_al_rhs_ns_exact | 4.146e-11 | 1.987e-13 | yes |
| qdesn_implemented_modes | exact chunking | qdesn_al_ridge_full | qdesn_al_ridge_exact | 7.034e-11 | 3.376e-13 | yes |

Conclusion: exact chunking is ready to use as a full-data preserving workflow
option for the supported Normal DESN and Q-DESN targets.

## Approximate Full-Data Diagnostics

Approximate rows preserve the intended full-data objective only approximately.
They are useful for runtime/accuracy tradeoff diagnostics and are not exact
replacements.

| Comparison | Reference | Candidate | Fitted Diff | Pinball Diff | Repeat Beta Diff |
|---|---|---|---:|---:|---:|
| hybrid AL | qdesn_al_ridge_full | qdesn_al_ridge_hybrid | 0.488565 | 0.000985 | 0.000000 |
| hybrid exAL | qdesn_exal_rhs_full | qdesn_exal_rhs_hybrid | 1.120663 | 0.001754 | 0.000000 |
| hybrid exAL | qdesn_exal_rhs_ns_full | qdesn_exal_rhs_ns_hybrid | 1.113084 | 0.001841 | 0.000000 |
| hybrid exAL | qdesn_exal_ridge_full | qdesn_exal_ridge_hybrid | 1.009254 | -0.006388 | 0.000000 |
| stochastic AL | qdesn_al_ridge_full | qdesn_al_ridge_stochastic | 1.227635 | 0.006878 | 0.000000 |

Interpretation:

- Hybrid AL is very close to full-data AL ridge on pinball loss.
- Hybrid exAL is finite and reproducible in ridge, `rhs`, and `rhs_ns` rows.
- Stochastic AL is finite and exactly reproducible under the fixed seed, but
  shows a larger fitted-state departure than hybrid AL.
- Pure stochastic exAL remains correctly forbidden.

## Covariance Approximation Diagnostics

Diagonal covariance rows are finite and exact-chunked equivalent to their own
diagonal targets, but they are not suitable for the primary table on this
source.

| Candidate | Reference | Fitted Diff | Pinball Diff |
|---|---|---:|---:|
| qdesn_al_ridge_diagonal | qdesn_al_ridge_full | 198.705364 | 92.149876 |
| qdesn_al_rhs_ns_diagonal | qdesn_al_rhs_ns_full | 434.212203 | 207.436280 |
| qdesn_exal_ridge_diagonal | qdesn_exal_ridge_full | 601.646982 | 290.693261 |
| qdesn_al_rhs_diagonal | qdesn_al_rhs_full | 1440.678059 | 710.611193 |

Conclusion: diagonal covariance support is useful as a tested diagnostic and
implementation scaffold, but it is not a recommended default for this
comparison.

## Target-Changing Diagnostics

Subset, rolling-window, posterior-as-prior, and online rows deliberately change
the statistical target or workflow. They should not be interpreted as
full-data-preserving replacements.

Subset diagnostics versus Q-DESN AL ridge full-data:

| Candidate | Rows Used | Original Rows | Fitted Diff | Pinball Diff | Finite |
|---|---:|---:|---:|---:|---|
| qdesn_al_ridge_fixed_subset | 180 | 450 | 0.278204 | 0.000549 | yes |
| qdesn_al_ridge_stratified_subset | 180 | 450 | 0.737519 | 0.011115 | yes |
| qdesn_al_ridge_stratified_equal_subset | 180 | 450 | 1.227081 | 0.007074 | yes |
| qdesn_al_ridge_stratified_response_subset | 180 | 450 | 0.441375 | 0.005121 | yes |
| qdesn_al_ridge_stratified_leverage_subset | 180 | 450 | 1.325547 | 0.027093 | yes |

Ordered workflow diagnostics:

| Method | Workflow | Target Label | No Future Leakage | Units | Seconds | Exact Pair Passed |
|---|---|---|---|---:|---:|---|
| qdesn_al_ridge_rolling | rolling refit | rolling_window_full_data_vb | yes | 2 | 21.001 | NA |
| qdesn_al_ridge_posterior_as_prior | rolling handoff | posterior_as_prior_al_ridge | yes | 2 | 1.584 | NA |
| qdesn_al_ridge_online | online handoff | online_posterior_as_prior_al_ridge | yes | 2 | 1.463 | yes |
| qdesn_al_ridge_online_exact | online handoff, exact chunked | online_posterior_as_prior_al_ridge | yes | 2 | 2.309 | yes |

Conclusion: target-changing modes are implemented and reproducible enough for
workflow diagnostics, but they should be reported in a separate panel or
appendix.

## Normal DESN Initialization Diagnostics

Normal DESN fits can initialize Q-DESN VB workflows. In this gate, all
initializer paths were finite.

| Method | Init Source | Pinball | Seconds | Max Prediction Diff vs Cold |
|---|---|---:|---:|---:|
| al_vb_cold | none | 8.5835 | 3.097 | NA |
| al_vb_normal_scaled_ridge_init | normal_scaled_ridge | 8.5822 | 15.036 | 0.033684 |
| al_vb_normal_rhs_ns_init | normal_rhs_ns_vb | 8.5825 | 0.607 | 0.025759 |
| exal_vb_cold | none | 8.6046 | 1.641 | NA |
| exal_vb_normal_scaled_ridge_init | normal_scaled_ridge | 8.6048 | 1.499 | 0.003202 |
| exal_vb_normal_rhs_ns_init | normal_rhs_ns_vb | 8.6047 | 1.480 | 0.002551 |

Interpretation:

- Normal initializers are working as a workflow feature.
- Normal RHS_NS initialization is especially cheap for AL in this run.
- Initialization rows are not new posterior targets and should be described as
  workflow aids.

## Forbidden And Deferred Modes

The comparison also confirmed fail-early behavior:

| Mode | Attempted | Result |
|---|---|---|
| qdesn_exal_stochastic | yes | failed early as expected |
| qdesn_exal_rhs_diagonal_covariance | yes | failed early as expected |
| divide_and_combine_vb | no | explicitly deferred |
| variational_coresets | no | explicitly deferred |

These should remain outside the comparison until their mathematical contracts,
implementation paths, and tests are complete.

## Figures

Prepared local figures:

| Figure | Purpose |
|---|---|
| `figure_predictive_metrics.png` | Primary pinball/RMSE comparison |
| `figure_runtime_vs_loss.png` | Runtime versus loss tradeoff |
| `figure_prediction_overlay.png` | Prediction overlay by evaluation row |
| `figure_exact_gates.png` | Exact equivalence gate summary |
| `manuscript_pinball_overview.pdf` | Compact pinball overview |

Figure root:

```text
/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/results/normal_qdesn_unified_source_median_20260529/manuscript_ready/figures/
```

The figure manifest records non-empty PNGs and package HEAD `784d336`.

## Main Comparison Conclusions

1. **Normal DESN scaled ridge is the strongest baseline on this source.**
   This is expected and scientifically sensible because the source is Gaussian
   and the median equals the conditional mean.

2. **Q-DESN AL/exAL full-data rows are coherent and stable.**
   The primary Q-DESN rows are finite, reproducible, and share the same DESN
   feature-map ecosystem as the Normal DESN rows.

3. **`rhs_ns` should be the default shrinkage prior.**
   It is the conjugate/default shrinkage story for the manuscript comparison.
   Legacy `rhs` remains available but should be footnoted or placed in
   supplemental sensitivity material.

4. **Exact chunking is validated.**
   It passed every exact gate and can be used as a full-data preserving
   implementation option.

5. **Hybrid methods are promising but approximate.**
   Hybrid AL/exAL rows show small pinball differences from their references on
   this gate, but they must be labeled approximate.

6. **Diagonal covariance should not be in the main table.**
   It is finite and tested, but its predictive behavior is poor here.

7. **Workflow modes need separate interpretation.**
   Subset, rolling, posterior-as-prior, online, and initializer rows are useful
   for workflow, speed, and sensitivity analyses, but they do not all preserve
   the full-data target.

## What This Report Does Not Claim

- It does not claim final application performance on GloFAS.
- It does not claim Q-DESN should beat Normal DESN on a Gaussian median source.
- It does not claim diagonal covariance is a recommended approximation.
- It does not claim stochastic exAL, divide-and-combine VB, or variational
  coresets are implemented.
- It does not treat subset or online methods as full-data replacements.

## Recommended Next Comparison

Run the same unified Normal/Q-DESN comparison on at least one source where the
Normal mean readout is not naturally advantaged:

1. a non-median quantile source, such as `tau = 0.05` or `tau = 0.95`;
2. a non-Gaussian family from the validation study;
3. a higher-noise or asymmetric source where conditional mean and target
   quantile separate more clearly.

Keep the same report schema and retain `rhs_ns` as the default shrinkage prior.
Use legacy `rhs`, diagonal covariance, subset, rolling/PAP/online, and
initializer rows as secondary panels or appendices.
