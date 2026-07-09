# GloFAS Application Candidate, 2026-06-21

## Purpose

This note records the `cal07` manuscript-facing GloFAS reference-case
candidate after visual inspection of the promoted figures. It records the
selected run, the score table used by the manuscript at that time, the promoted
artifacts, and the replacement rule for future GloFAS experiments.

This is not a claim of broad operational validation. The application remains a
single audited forecast-origin reference case.

## Supersession Status

This candidate was superseded on 2026-06-22 by the Stage C score-balanced
`arch04_a035` candidate:

```text
glofas_stage_c_full7_confirmations_20260622_arch04_a035_scorebalanced_synthesis_final
```

The replacement was made only after the Stage C full-seven synthesis and
diagnostic readiness checks passed and the figures were visually accepted. The
new current aliases are still the stable manuscript-facing interface:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_selection_manifest.csv
```

The `cal07` files below remain retained as historical baseline evidence.

## Selected Candidate

```text
run_id: glofas_cal07_scorebalanced_spread140_add050_synthesis_final
origin_date: 2022-12-25
scored_horizons: 28
reservoir_depth: 4
reservoir_widths: 100,100,100,100
reducer_widths: 100,100,100
memory: 300
washout: 500
alpha: 0.05,0.05,0.05,0.05
rho: 0.95,0.95,0.95,0.95
reservoir_seed: 20260512
tau0_ref: 0.003
tau0_disc: 0.06
spread_calibration_id: scorebalanced_spread_x1p400_plus0p500
spread_factor: 1.4
spread_additive_half_width: 0.5
spread_center_quantile: 0.50
```

The selected spread calibration is a no-refit synthesis adjustment. It changes
the forecast-window synthesized bands only. It does not refit the Q-DESN
reservoirs, likelihood, priors, or readout coefficients.

## Manuscript-Facing Scores

| Model | Check loss | Interval score | CRPS | Mean coverage |
|---|---:|---:|---:|---:|
| Q-DESN calibration | 0.3818 | 4.1930 | 0.7915 | 0.583 |
| Raw GloFAS | 0.7639 | 13.0538 | 1.4424 | 0.000 |

Relative to raw GloFAS, the selected Q-DESN output reduces mean check loss by
50.0%, interval score by 67.9%, and quantile-grid CRPS by 45.1% for this
audited forecast origin.

## Tracked Interface Files

Stable current aliases:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_score_summary.csv
tables/glofas_application_current_selection_manifest.csv
```

Promoted run snapshot and provenance:

```text
tables/glofas_application_run_config__glofas_cal07_scorebalanced_spread140_add050_20260621.yaml
tables/glofas_application_promotion_manifest__glofas_cal07_scorebalanced_spread140_add050_20260621.csv
tables/glofas_application_spread_calibration_manifest__glofas_cal07_scorebalanced_spread140_add050_20260621.csv
```

Primary manuscript figures:

```text
figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_qdesn_synthesized_bands__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
```

Diagnostic figures:

```text
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_raw_vs_qdesn_monotone_paths__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_discrepancy_prepost_cutoff_window__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_vb_elbo_traces__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_vb_parameter_change_traces__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
figures/glofas_application/diagnostics/glofas_cal07_scorebalanced_spread140_add050_score_summary__glofas_cal07_scorebalanced_spread140_add050_20260621.pdf
```

## Replacement Rule

Future GloFAS candidates should not overwrite manuscript paths by hand.
Replacement should use the existing promotion contract:

1. Generate the candidate outputs under `application/outputs/generated/<run_id>/`.
2. Promote lightweight article-facing tables and figures with
   `application/scripts/08_promote_application_outputs.R`.
3. Select the candidate with `application/scripts/09_select_application_outputs.R`
   and an explicit promotion manifest.
4. Confirm that `tables/glofas_application_current_selection_manifest.csv`
   records the selected run, source hashes, promoted file hashes, article Git
   SHA, and engine SHA.
5. Recompile `main.tex` and `qdesn-supplement.tex`.

This keeps the manuscript decoupled from local run archives while preserving a
reproducible route from fitted runs to article-facing outputs.
