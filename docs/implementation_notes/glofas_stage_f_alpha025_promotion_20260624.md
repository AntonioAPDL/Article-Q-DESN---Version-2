# GloFAS application promotion: Stage F alpha025 score-balanced synthesis

Date: 2026-06-24

This note records the promotion of the Stage F GloFAS Q-DESN application
candidate to the manuscript-facing current output set.

## Promoted candidate

- Synthesis run:
  `glofas_stage_f_alpha025_full7_confirmation_20260623_d_alpha_025_scorebalanced_synthesis_final`
- Runtime configuration:
  `local_trackers/runtime_configs/glofas_stage_f_alpha025_full7_confirmation_20260623/d_alpha_025/synthesis_config_scorebalanced.yaml`
- Promotion slug:
  `glofas_stage_f_alpha025_scorebalanced_20260624`
- Engine commit recorded in the promotion manifest:
  `73c043f0436b508808366f312350fd44c2d06771`

The candidate uses the Stage F local refinement of the previous Stage C
architecture. The selected change is the common DESN leak rate
`alpha = 0.025`, with the remaining architecture and prior settings inherited
from the Stage C application baseline. The promoted synthesis uses the
score-balanced spread calibration already recorded in the run configuration.

## Evidence

The full-seven synthesis contains all target quantiles
`0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95`. The synthesis readiness checks
passed, including source completion, target-quantile availability, duplicate
prediction-key checks, post-synthesis crossing checks, score-summary
availability, and manuscript-figure availability.

Relative to the previously promoted Stage C score-balanced candidate:

| Candidate | Check loss | CRPS | Interval score | Coverage |
|---|---:|---:|---:|---:|
| Stage C score-balanced | 0.377664 | 0.783304 | 4.034885 | 0.642857 |
| Stage F alpha025 score-balanced | 0.350432 | 0.724866 | 3.967708 | 0.738095 |

Stage F improves the mean check loss by about 7.2 percent and the quantile-grid
CRPS by about 7.5 percent, while also improving interval score and empirical
coverage over the held-out GloFAS forecast window.

## Promotion commands

The storage-light outputs were promoted through the existing GloFAS synthesis
promotion route:

```bash
Rscript application/scripts/21_promote_glofas_synthesis_outputs.R \
  --config local_trackers/runtime_configs/glofas_stage_f_alpha025_full7_confirmation_20260623/d_alpha_025/synthesis_config_scorebalanced.yaml \
  --synthesis_run_id glofas_stage_f_alpha025_full7_confirmation_20260623_d_alpha_025_scorebalanced_synthesis_final \
  --diagnostic_run_id glofas_stage_f_alpha025_full7_confirmation_20260623_d_alpha_025_scorebalanced_diagnostic_figures \
  --output_slug glofas_stage_f_alpha025_scorebalanced_20260624 \
  --allow_ignored_config true
```

The promoted output set was then selected as the current manuscript-facing
GloFAS application output:

```bash
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__glofas_stage_f_alpha025_scorebalanced_20260624.csv
```

## Article-facing outputs

The stable current aliases are:

- `tables/glofas_application_current_outputs.tex`
- `tables/glofas_application_current_score_summary.csv`
- `tables/glofas_application_current_score_summary.tex`
- `tables/glofas_application_current_selection_manifest.csv`

The promoted Stage F manifest is:

- `tables/glofas_application_promotion_manifest__glofas_stage_f_alpha025_scorebalanced_20260624.csv`

The main promoted figures are:

- `figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_stage_f_alpha025_scorebalanced_20260624.pdf`
- `figures/glofas_application/glofas_qdesn_discrepancy_draws_by_horizon__glofas_stage_f_alpha025_scorebalanced_20260624.pdf`

Diagnostic figures are under:

- `figures/glofas_application/diagnostics/*__glofas_stage_f_alpha025_scorebalanced_20260624.pdf`

## Calibration note

The score-balanced synthesis is a post hoc calibrated synthesis of independently
fit quantile models. It should be described as calibrated synthesis, not as the
raw identity-preserving discrepancy output. The posterior draw identity check
passes in the synthesis readiness audit; the calibrated independent quantile
paths may record a nonzero discrepancy-identity adjustment because the spread
calibration is applied after model fitting.
