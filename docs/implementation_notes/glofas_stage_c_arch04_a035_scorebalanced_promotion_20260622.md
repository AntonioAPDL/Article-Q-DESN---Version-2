# GloFAS Stage C `arch04_a035` Score-Balanced Promotion, 2026-06-22

## Scope

This note records the GloFAS application promotion performed after the Stage C
full-seven confirmation run. It only concerns the Article-Q-DESN GloFAS
application outputs. It does not modify the shared validation study or PriceFM
application work.

## Decision

The promoted candidate is:

```text
glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_synthesis_final
```

The stable manuscript-facing aliases now point to this run through:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_selection_manifest.csv
```

## Model Specification

The promoted candidate uses the Stage C `arch04_a035` GloFAS Q-DESN
configuration:

| component | value |
| --- | --- |
| reservoir depth | 4 |
| reservoir widths | 100, 100, 100, 100 |
| reducer widths | 100, 100, 100 |
| memory | 300 |
| washout | 500 |
| leak rates | 0.035, 0.035, 0.035, 0.035 |
| spectral radii | 0.95, 0.95, 0.95, 0.95 |
| reservoir sparsity | 0.03 in each layer |
| input inclusion | 1.00 in each layer |
| input scaling | global 0.18, bias 0.18 |
| seed | 20260512 |
| inference | AL likelihood, VB--LD |
| maximum VB iterations | 150 |
| shared RHS tau0 | 0.001 |
| discrepancy RHS tau0 | 0.03 |
| spread calibration | factor 1.4 plus additive half-width 0.5 |

The score-balanced synthesis is a no-refit forecast-window synthesis adjustment.
It does not refit the Q-DESN reservoirs, likelihood, priors, or readout
coefficients.

## Evidence

The candidate passed the required full-seven gates:

- all seven quantile source runs complete;
- target quantiles available at 0.05, 0.15, 0.35, 0.50, 0.65, 0.80, and 0.95;
- duplicate prediction keys absent;
- post-synthesis crossing count equal to zero;
- synthesis score summary available;
- manuscript figures available;
- diagnostic figures available.

The score-balanced comparison against the previous `cal07` baseline is:

| candidate | check loss | CRPS | interval score | coverage |
| --- | ---: | ---: | ---: | ---: |
| previous `cal07` score-balanced | 0.3818 | 0.7915 | 4.1930 | 0.583 |
| Stage C `arch04_a035` score-balanced | 0.3777 | 0.7833 | 4.0349 | 0.643 |

The improvement is modest but coherent across the main metrics. Relative to the
previous score-balanced baseline, the selected Stage C candidate lowers mean
check loss by about 1.1%, lowers CRPS by about 1.0%, lowers the interval score
by about 3.8%, and improves mean empirical coverage by about 0.060.

Relative to raw GloFAS for the same audited forecast origin, the promoted
Q-DESN output reduces mean check loss by 50.6%, interval score by 69.1%, and
quantile-grid CRPS by 45.7%.

## Promotion Commands

The storage-light synthesis outputs were promoted with:

```bash
Rscript application/scripts/21_promote_glofas_synthesis_outputs.R \
  --config local_trackers/runtime_configs/glofas_stage_c_full7_confirmations_20260622/arch04_a035/synthesis_config_scorebalanced.yaml \
  --synthesis_run_id glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_synthesis_final \
  --diagnostic_run_id glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_diagnostic_figures \
  --output_slug glofas_stage_c_arch04_a035_scorebalanced_20260622 \
  --allow_ignored_config TRUE
```

The promoted output set was selected as the stable manuscript-facing current
GloFAS application candidate with:

```bash
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
```

## Article-Facing Paths

Primary promoted figures:

```text
figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
figures/glofas_application/glofas_qdesn_discrepancy_draws_by_horizon__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
```

Key diagnostics:

```text
figures/glofas_application/diagnostics/glofas_stage_c_arch04_a035_scorebalanced_qdesn_synthesized_bands__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
figures/glofas_application/diagnostics/glofas_stage_c_arch04_a035_scorebalanced_raw_vs_qdesn_monotone_paths__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
figures/glofas_application/diagnostics/glofas_stage_c_arch04_a035_scorebalanced_discrepancy_prepost_cutoff_window__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
figures/glofas_application/diagnostics/glofas_stage_c_arch04_a035_scorebalanced_vb_elbo_traces__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
figures/glofas_application/diagnostics/glofas_stage_c_arch04_a035_scorebalanced_vb_parameter_change_traces__glofas_stage_c_arch04_a035_scorebalanced_20260622.pdf
```

Key promoted tables:

```text
tables/glofas_application_score_summary__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
tables/glofas_application_promotion_manifest__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
tables/glofas_application_run_config__glofas_stage_c_arch04_a035_scorebalanced_20260622.yaml
tables/glofas_application_diagnostic_readiness_report__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
tables/glofas_application_launch_readiness_report__glofas_stage_c_arch04_a035_scorebalanced_20260622.csv
```

## Validation

The promotion and current-selection manifests were verified by recomputing file
hashes:

- promoted artifact manifest: 46 rows, all hashes matched;
- current selection manifest: 10 rows, all hashes matched.

The diagnostic readiness report confirms 16 diagnostic figures were written for
the score-balanced candidate.

## Cleanup Note

The non-winner Stage C candidates, `arch07_w140` and `arch08_d3w200`, remain
available as local run archives. Their heavy `.rds` design and fit objects can
be removed later to recover disk space after an explicit cleanup command, while
keeping the promoted Stage C `arch04_a035` artifacts and the previous `cal07`
baseline intact.

## Next Step

Use this promoted candidate as the current manuscript-facing GloFAS application
result. Future exploration should treat it as the baseline to beat and should
stay local to the `D=4`, width 100, memory 300, low-leak neighborhood unless a
clear diagnostic reason motivates a broader search.
