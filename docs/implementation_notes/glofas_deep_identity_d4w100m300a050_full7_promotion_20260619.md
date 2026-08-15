# GloFAS Deep-Identity D4 Full-Seven Promotion, 2026-06-19

This note records the current manuscript-facing GloFAS application candidate
after promoting the completed deep-identity D4 full-seven run. The promotion is
storage-light: it tracks article tables, figures, config snapshots, manifests,
hashes, and diagnostics, not heavy fit payloads.

## Selected run

- Synthesis run:
  `glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final`
- Diagnostic run:
  `glofas_deep_identity_d4w100m300a050_full7_20260618_diagnostic_figures`
- Model ID:
  `qdesn_latent_path_rhs_al_vb_glofas_deep_identity_d4w100m300a050_full7`
- Forecast origin: `2022-12-25`
- Quantiles: `0.05`, `0.15`, `0.35`, `0.50`, `0.65`, `0.80`, `0.95`

## Model specification

The promoted config snapshot is:

```text
tables/glofas_application_run_config__glofas_deep_identity_d4w100m300a050_full7_20260618.yaml
```

The selected DESN specification is:

| Component | Value |
| --- | --- |
| Depth | `D = 4` |
| Layer widths | `n = [100, 100, 100, 100]` |
| Reducer widths | `n_tilde = [100, 100, 100]` |
| Memory / washout | `m = 300`, washout `500` |
| Leak rates | `alpha = [0.05, 0.05, 0.05, 0.05]` |
| Spectral radii | `rho = [0.95, 0.95, 0.95, 0.95]` |
| Sparsity/input | `pi_w = [0.03, 0.03, 0.03, 0.03]`, `pi_in = [1, 1, 1, 1]` |
| Input scales | `win_scale_global = 0.18`, `win_scale_bias = 0.18` |
| Activations | `act_f = tanh`, `act_k = identity` |
| Seed | `20260512` |

The VB settings are `max_iter = 250`, `tol = 1e-3`, `tol_par = 1e-3`,
`n_samp_xi = 500`, and `n_draws = 2000`.

The readout blocks use separate regularized-horseshoe global scales:

| Readout block | Global scale |
| --- | ---: |
| Reference/shared quantile block | `tau0 = 0.001` |
| GloFAS discrepancy block | `tau0 = 0.03` |

## Score summary

| Comparison | Mean check loss | CRPS | Interval score | Mean coverage |
| --- | ---: | ---: | ---: | ---: |
| Q--DESN D4 | `0.427511` | `0.871118` | `4.996789` | `0.297619` |
| Q--DESN c03 | `0.495186` | `1.009671` | `5.757744` | `0.214286` |
| Raw GloFAS | `0.763943` | `1.442359` | `13.053786` | `0.000000` |

Relative to raw GloFAS, the D4 candidate reduces mean check loss by `44.0%`,
interval score by `61.7%`, and quantile-grid CRPS by `39.6%`. Relative to the
previous c03 promoted candidate, the D4 candidate improves mean check loss,
CRPS, interval score, and coverage. Coverage remains below nominal, so the
application text should treat calibration as improved but not fully solved.

The interval-specific coverage diagnostics for Q--DESN were:

| Nominal interval | Coverage |
| ---: | ---: |
| `0.30` | `0.035714` |
| `0.65` | `0.178571` |
| `0.90` | `0.678571` |

## Readiness checks

The synthesis readiness report passed all required checks:

- all required source runs complete;
- all target quantiles available;
- no duplicate prediction keys;
- no post-synthesis crossings;
- score summary exists;
- manuscript figures exist.

The diagnostic readiness report also passed all required checks:

- all component fits completed;
- synthesis readiness passed;
- no post-synthesis crossings before or after isotonic correction;
- score summary available;
- diagnostic figures and tables written.

The VB strict convergence flags were mixed under the configured parameter-change
tolerance: `p65` and `p95` satisfied the strict flag, while the remaining
quantiles stopped at the `250` iteration cap. The ELBO and trace diagnostics
should therefore remain part of the promoted diagnostic evidence rather than
being replaced by the strict Boolean alone.

## Promoted outputs

The stable current aliases now point to this run through:

- `tables/glofas_application_current_outputs.tex`
- `tables/glofas_application_current_score_summary.tex`
- `tables/glofas_application_current_score_summary.csv`
- `tables/glofas_application_current_selection_manifest.csv`

Run-specific promoted outputs include:

- `tables/glofas_application_promotion_manifest__glofas_deep_identity_d4w100m300a050_full7_20260618.csv`
- `tables/glofas_application_score_summary__glofas_deep_identity_d4w100m300a050_full7_20260618.tex`
- `tables/glofas_application_score_summary__glofas_deep_identity_d4w100m300a050_full7_20260618.csv`
- `figures/glofas_application/glofas_qdesn_discrepancy_corrected_quantile_paths__glofas_deep_identity_d4w100m300a050_full7_20260618.pdf`
- `figures/glofas_application/glofas_qdesn_discrepancy_draws_by_horizon__glofas_deep_identity_d4w100m300a050_full7_20260618.pdf`
- `figures/glofas_application/diagnostics/glofas_deep_identity_full7_vb_elbo_traces__glofas_deep_identity_d4w100m300a050_full7_20260618.pdf`
- `figures/glofas_application/diagnostics/glofas_deep_identity_full7_vb_parameter_change_traces__glofas_deep_identity_d4w100m300a050_full7_20260618.pdf`
- `figures/glofas_application/diagnostics/glofas_deep_identity_full7_qdesn_synthesized_bands__glofas_deep_identity_d4w100m300a050_full7_20260618.pdf`

## Reproducibility commands

Promote the completed storage-light synthesis and diagnostic outputs:

```bash
Rscript application/scripts/21_promote_glofas_synthesis_outputs.R \
  --config local_trackers/runtime_configs/glofas_deep_identity_d4w100m300a050_full7_20260618/synthesis_config.yaml \
  --synthesis_run_id glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final \
  --diagnostic_run_id glofas_deep_identity_d4w100m300a050_full7_20260618_diagnostic_figures \
  --output_slug glofas_deep_identity_d4w100m300a050_full7_20260618
```

Select the promoted run as the manuscript-facing current output set:

```bash
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__glofas_deep_identity_d4w100m300a050_full7_20260618.csv
```

Regenerate all-cutoff source-context figures using the D4 overlay when
available:

```bash
Rscript application/scripts/43_make_glofas_multivariate_cutoff_figures.R \
  --run_id glofas_multivariate_cutoff_figures_20260619_deep_identity_d4w100m300a050 \
  --source_root application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505 \
  --prediction_run_id glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final \
  --window_before_days 60 \
  --window_after_days 30 \
  --transform log1p
```

The all-cutoff figure workflow writes to:

```text
application/outputs/generated/glofas_multivariate_cutoff_figures_20260619_deep_identity_d4w100m300a050
```

The storage-light D4 prediction tables contain Q--DESN forecast paths for the
`2022-12-25` cutoff only. Other cutoffs remain source-context displays without
Q--DESN overlays. The validation table records this with
`qdesn_overlay_available`.

## Validation criteria

Before treating this run as manuscript-facing, verify:

```bash
Rscript -e 'm <- read.csv("tables/glofas_application_promotion_manifest__glofas_deep_identity_d4w100m300a050_full7_20260618.csv", stringsAsFactors = FALSE); stopifnot(nrow(m) > 0, all(file.exists(m$promoted_path)), all(m$source_sha256 == m$promoted_sha256))'
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root(getwd()); m <- app_read_csv("tables/glofas_application_current_selection_manifest.csv"); p <- ifelse(grepl("^/", m$path), m$path, file.path(app_repo_root(), m$path)); stopifnot(all(file.exists(p)), all(vapply(p, app_sha256_file, character(1)) == m$sha256))'
Rscript application/tests/run_tests.R
Rscript application/tests/test_cutoff_multivariate_figures.R
git diff --check
```

Compile the manuscript after the current-output aliases are regenerated:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```
