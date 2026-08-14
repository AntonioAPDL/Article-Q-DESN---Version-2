# GloFAS Long-History Retrospective Gate

Date: 2026-05-12

## Purpose

The Dec. 25, 2022 application bundle must use the audited long-history GloFAS
retrospective, not the short selected-run retrospective that begins in 2020.
The long-history source is needed because the Q-DESN readout should be trained
on the full available retrospective support, after the configured washout, while
the issued GloFAS ensemble is used only for the forecast window after the
cutoff.

## Authoritative Source

The source used for GloFAS is the jerez histfix stable-input bundle:

```text
/data/muscat_data/jaguir26/project1_ucsc_phd_runtime/
  multimodel_v8_histfix_20260407/stable_inputs/
  site=11160500/cutoff_date=2022-12-25/
  run_id=20260407_long_history_r01
```

The article-side copy lives under ignored local data:

```text
application/data_local/upstream_jerez/histfix_stable_inputs/
  site=11160500/cutoff_date=2022-12-25/
  run_id=20260407_long_history_r01
```

The bundle metadata records `bundle_kind: multimodel_v8_histfix_long_history`,
`data_start: 1987-05-29`, and
`histfix.glofas_source_id: glofas_hist_v31_lisflood_cons`.

The tracked source-registry row is:

```text
application/config/authoritative_cutoff_sources.csv
```

That row is the article-side contract for the base frozen-input root, the
GloFAS histfix stable-input root, the materialized bundle root, the expected
retrospective support, and the overlap comparison path.

## Scale Decision

The histfix `inputs/retros_daily.csv` file is stored on the `log1p_cms` support
scale. The article input schema stores streamflow in cubic meters per second
and applies the configured `log1p` transformation when building the application
panel. The materializer therefore converts the histfix GloFAS retrospective
with `expm1()` before writing `glofas/glofas_retrospective.csv`. This prevents
the retrospective from being transformed twice.

## Materialization Contract

The materializer now separates the base source root from the GloFAS source
root. The base source root supplies USGS observations, climate covariates, and
other copied frozen-input lineage. The GloFAS source root supplies
`inputs/retros_daily.csv` and `inputs/glofas_members.csv` from the histfix
stable-input bundle.

The preferred command is registry-driven:

```sh
Rscript application/scripts/00_materialize_from_source_registry.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --cutoff_id dec25_2022
```

The materialized article bundle is:

```text
application/data_local/frozen_inputs/authoritative_cutoffs/cutoff_date=2022-12-25
```

The retrospective is clipped at the cutoff:

```text
1987-05-29 through 2022-12-25
```

The issued GloFAS ensemble covers:

```text
2022-12-26 through 2023-01-22
```

## Validation

The long-history audit is reproducible with:

```sh
Rscript application/scripts/00_audit_glofas_retrospective_history.R \
  --output_dir application/runs/long_history_dec25_input_gate_20260512/tables
```

The validated local gate produced:

```text
retrospective rows: 12995
retrospective date range: 1987-05-29 to 2022-12-25
GloFAS source id: glofas_hist_v31_lisflood_cons
overlap rows with previous short source: 1081
overlap date range: 2020-01-10 to 2022-12-25
maximum absolute overlap difference: 1e-08
```

The rebuilt panel from the large-spec configuration produced:

```text
panel rows: 14423
retrospective rows: 12995
ensemble rows: 1428
panel date range: 1987-05-29 to 2023-01-22
missing reference rows: 0
missing GloFAS rows: 0
```

The sampler-free large-spec design preflight for the median fit produced:

```text
D = 2
n = (500, 500)
n_tilde = 500
m = 180
washout = 500
base feature rows: 12495
base features: 1304
augmented features: 2608
stacked likelihood rows: 26418
prediction rows: 28
```

The base feature count reflects one readout intercept, 1000 reservoir-state
features, 180 direct transformed-streamflow lags, 122 precipitation and soil
lags, and one scaled-horizon feature. This gate verifies that the requested
large DESN specification can be built from the long-history panel before
launching MCMC.
