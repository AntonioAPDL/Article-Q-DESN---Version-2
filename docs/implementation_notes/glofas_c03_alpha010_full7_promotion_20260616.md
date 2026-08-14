# GloFAS c03 alpha010 full-seven promotion, 2026-06-16

This note records the current promoted GloFAS application candidate.  The run is
an article-facing, storage-light promotion of the c03 discrepancy-smoothing
candidate after completing all seven paper quantiles.

## Selected run

- Synthesis run: `glofas_c03_alpha010_full7_completion_20260616_synthesis_final`
- Model ID:
  `qdesn_latent_path_rhs_al_vb_glofas_discrepancy_smoothing_gate_20260616_c03_m420_alpha010_tau_current`
- Specification: `D = 1`, `n = 300`, `m = 420`, `alpha = 0.10`,
  `rho = 0.95`, `pi_w = 0.03`, `pi_in = 1`, `win_scale_global = 0.18`,
  seed `20260512`
- RHS prior: shared/discrepancy `tau0 = 0.10`/`0.03`
- VB settings: `max_iter = 150`
- Quantiles: `0.05`, `0.15`, `0.35`, `0.50`, `0.65`, `0.80`, `0.95`
- Forecast origin: `2022-12-25`

The source quantile fits reuse the completed c03 gate fits for `p05`, `p50`,
and `p95`, and add the completion fits for `p15`, `p35`, `p65`, and `p80`.

## Score summary

| Comparison | Mean check loss | CRPS | Interval score | Coverage |
| --- | ---: | ---: | ---: | ---: |
| Q--DESN c03 | 0.495186 | 1.009671 | 5.757744 | 0.214286 |
| Raw GloFAS | 0.763943 | 1.442359 | 13.053786 | 0.000000 |
| Previous m420 full-seven | 0.571919 | 1.147799 | 7.267766 | 0.166667 |

Relative to raw GloFAS, c03 reduces mean check loss by `35.2%`.  Relative to
the previous m420 full-seven candidate, c03 improves mean check loss by
`0.076732`, CRPS by `0.138128`, interval score by `1.510023`, and coverage by
`0.047619`.

Per-quantile mean check losses for c03 were:

| Quantile | Q--DESN | Raw GloFAS | Improvement |
| ---: | ---: | ---: | ---: |
| 0.05 | 0.102808 | 0.115945 | 11.3% |
| 0.15 | 0.269203 | 0.316672 | 15.0% |
| 0.35 | 0.547039 | 0.657938 | 16.9% |
| 0.50 | 0.708783 | 0.875379 | 19.0% |
| 0.65 | 0.802606 | 1.059875 | 24.3% |
| 0.80 | 0.789126 | 1.177597 | 33.0% |
| 0.95 | 0.246737 | 1.144194 | 78.4% |

## Promoted article-facing outputs

Stable current aliases now point to this run through:

- `tables/glofas_application_current_outputs.tex`
- `tables/glofas_application_current_score_summary.tex`
- `tables/glofas_application_current_score_summary.csv`
- `tables/glofas_application_current_selection_manifest.csv`

Run-specific promoted outputs are immutable and include:

- `tables/glofas_application_promotion_manifest__glofas_c03_alpha010_full7_completion_20260616.csv`
- `tables/glofas_application_score_summary__glofas_c03_alpha010_full7_completion_20260616.tex`
- `tables/glofas_application_score_summary__glofas_c03_alpha010_full7_completion_20260616.csv`
- `figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_c03_alpha010_full7_completion_20260616.pdf`
- `figures/glofas_application/glofas_qdesn_discrepancy_draws_by_horizon__glofas_c03_alpha010_full7_completion_20260616.pdf`
- `figures/glofas_application/diagnostics/glofas_c03_alpha010_full7_discrepancy_prepost_cutoff_window__glofas_c03_alpha010_full7_completion_20260616.pdf`
- `figures/glofas_application/diagnostics/glofas_c03_alpha010_full7_discrepancy_forecast_correction_comparison__glofas_c03_alpha010_full7_completion_20260616.pdf`
- `figures/glofas_application/diagnostics/glofas_c03_alpha010_full7_vb_elbo_traces__glofas_c03_alpha010_full7_completion_20260616.pdf`
- `figures/glofas_application/diagnostics/glofas_c03_alpha010_full7_vb_parameter_change_traces__glofas_c03_alpha010_full7_completion_20260616.pdf`

## Reproducibility commands

The runtime configs live under `local_trackers/runtime_configs/` and are
ignored by git.  The following commands reproduce the storage-light diagnostics,
promotion, and current-selection registry from the completed run artifacts.

```bash
Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R \
  --config local_trackers/runtime_configs/glofas_c03_alpha010_full7_completion_20260616/synthesis_config.yaml \
  --source_manifest local_trackers/runtime_configs/glofas_c03_alpha010_full7_completion_20260616/synthesis_source_manifest.csv \
  --synthesis_run_id glofas_c03_alpha010_full7_completion_20260616_synthesis_final \
  --run_id glofas_c03_alpha010_full7_completion_20260616_diagnostic_figures \
  --figure_prefix glofas_c03_alpha010_full7 \
  --discrepancy_history_days 1000
```

```bash
Rscript application/scripts/21_promote_glofas_synthesis_outputs.R \
  --config local_trackers/runtime_configs/glofas_c03_alpha010_full7_completion_20260616/synthesis_config.yaml \
  --synthesis_run_id glofas_c03_alpha010_full7_completion_20260616_synthesis_final \
  --diagnostic_run_id glofas_c03_alpha010_full7_completion_20260616_diagnostic_figures \
  --output_slug glofas_c03_alpha010_full7_completion_20260616
```

```bash
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__glofas_c03_alpha010_full7_completion_20260616.csv
```

## Validation

Promotion validation passed with `44` promoted outputs:

- `2` article figures
- `16` article tables
- `18` diagnostic figures
- `5` diagnostic tables
- `3` provenance snapshots

Every source/promoted SHA-256 pair in the promotion manifest matched.  The
current-selection registry was regenerated from the c03 promotion manifest.
