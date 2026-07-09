# GloFAS/NWS Multivariate Cutoff Figure Workflow

Date: 2026-06-18

## Purpose

This note documents the storage-light workflow for regenerating the GloFAS
application figures that compare USGS observations, GloFAS and NWS products,
and the current promoted Q-DESN forecast quantile outputs at every authoritative
cutoff.

The workflow is figure-only. It does not refit Q-DESN models and does not
require `.rds`, `.rda`, or `.RData` fit objects.

## Authoritative Inputs

The frozen all-cutoff source bundle is:

```text
application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505
```

Each cutoff directory is expected to contain:

```text
retros/retros.csv
forecasts/glofas_forecast.csv
forecasts/nws_forecast.csv
inputs/usgs_daily.csv
```

The retrospective file provides the pre-cutoff USGS, GloFAS, and NWS series.
The forecast files provide post-cutoff forecast ensembles. The daily USGS file
provides held-out observations after the cutoff for visual checking.

The current promoted Q-DESN run used as an optional overlay is:

```text
application/runs/glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final
```

Only storage-light CSV tables are consumed:

```text
tables/prediction_quantiles_synthesized.csv
tables/posterior_draw_predictions.csv
```

## Generated Outputs

The standard regeneration command writes to:

```text
application/outputs/generated/glofas_multivariate_cutoff_figures_20260619_deep_identity_d4w100m300a050
```

The output layout is:

```text
figures/multivariate_synthesis_by_cutoff/cutoff_date=YYYY-MM-DD/
figures/multivariate_quantiles_by_cutoff/cutoff_date=YYYY-MM-DD/
tables/cutoff_figure_manifest.csv
tables/cutoff_figure_validation.csv
logs/git_state.txt
logs/session_info.txt
```

The `multivariate_synthesis_by_cutoff` figures show:

- USGS observations before the cutoff;
- held-out USGS observations after the cutoff;
- GloFAS and NWS retrospectives before the cutoff;
- GloFAS and NWS forecast ensemble members and medians after the cutoff;
- a vertical dashed cutoff line;
- the current promoted Q-DESN median forecast and central band when available.

The `multivariate_quantiles_by_cutoff` figures show the same source context and
the promoted Q-DESN forecast quantile paths before and after monotone correction
when the promoted run provides that cutoff. The current promoted storage-light
tables contain forecast-window quantile paths, not fitted historical quantile
paths for every cutoff. The validation table records this explicitly with
`pre_cutoff_quantile_history_available = FALSE`.

## Regeneration Command

```bash
Rscript application/scripts/43_make_glofas_multivariate_cutoff_figures.R \
  --run_id glofas_multivariate_cutoff_figures_20260619_deep_identity_d4w100m300a050 \
  --source_root application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505 \
  --prediction_run_id glofas_deep_identity_d4w100m300a050_full7_20260618_synthesis_final \
  --window_before_days 60 \
  --window_after_days 30 \
  --transform log1p
```

Focused test:

```bash
Rscript application/tests/test_cutoff_multivariate_figures.R
```

## Validation Criteria

Before using the figures in the manuscript or supplement, check:

1. `tables/cutoff_figure_manifest.csv` has three figure rows per cutoff.
2. `tables/cutoff_figure_validation.csv` confirms retrospective GloFAS and NWS
   rows before each cutoff.
3. GloFAS and NWS forecast horizons are recorded separately. In the frozen
   source bundle, GloFAS extends farther than NWS; this should remain visible
   rather than being forced to a common horizon.
4. Q-DESN overlay availability is true only for cutoffs covered by the promoted
   prediction tables.
5. No heavy fit payloads are required to regenerate the figures.

## Workflow Boundary

This workflow is integrated with the Article-Q-DESN application outputs, but it
does not promote a new model. It only regenerates diagnostic and manuscript-ready
source-context figures from authoritative inputs and the current promoted
storage-light prediction tables.
