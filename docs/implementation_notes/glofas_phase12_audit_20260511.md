# GloFAS Application Phase 1--2 Audit

Date: 2026-05-11

## Scope

This audit checks the article-owned Phase 1 and Phase 2 application workflow:
input-bundle registration, manifest validation, semantic input audits, panel
construction, and pre-model diagnostic figures. It does not audit Q-DESN model
fitting, discrepancy-inference derivations, scoring, or manuscript performance
claims.

The original Phase 1--2 smoke run used a synthetic bundle under
`application/data_local/smoke_bundle/`. That bundle remains useful for
regression tests only. The manuscript-facing source-figure path now uses the
audited jerez Dec 25, 2022 bundle and the copied GEFS/NWM precipitation and
soil-moisture handoff cache. The full application still requires repeating this
source audit across the final cutoff set before model fitting or manuscript
claims.

## Criteria

Phase 1 is considered wired only if:

- required inputs are registered from a local frozen bundle;
- `input_manifest.csv` and `input_bundle_manifest.csv` are generated rather
  than hand-edited;
- required semantic columns match `expected_schema.yaml`;
- SHA-256 hashes match the registered files;
- row counts, column counts, and date ranges in the manifest match the files;
- optional covariates can be absent without masking missing required inputs.

Phase 2 is considered wired only if:

- the application panel is built from the registered manifest;
- retrospective rows and ensemble rows are distinguishable;
- ensemble horizons satisfy `target_date - origin_date = horizon`;
- origin-target-horizon-member keys are unique;
- panel summaries and pre-model diagnostic figures are written to the run
  directory;
- each generated figure has a provenance row with the run ID, input manifest,
  panel hash, config path, and git SHA.

## Smoke Results

The strict smoke run `audit_phase12_strict` completed the Phase 1 and Phase 2
stages:

- `00_register_input_bundle.R`
- `00_check_inputs.R`
- `00_audit_input_bundle.R`
- `01_build_panel.R`
- `02_make_input_figures.R`

The registered smoke manifest contains three required inputs:

- reference gauge streamflow: 20 rows and 3 columns;
- GloFAS retrospective streamflow: 20 rows and 3 columns;
- GloFAS ensemble forecasts: 100 rows and 5 columns.

The optional climate-covariate input is absent and is correctly recorded in the
bundle manifest as optional. The semantic input audit passed the duplicate-key
and horizon-consistency checks. The derived panel has 120 rows: 20
retrospective rows and 100 ensemble rows. Six input-diagnostic PDFs were
generated and listed in `figure_manifest.csv`.

## Verification Commands

```sh
Rscript application/tests/run_tests.R

Rscript application/scripts/00_register_input_bundle.R \
  --bundle_config application/cache/smoke_input_bundle.yaml \
  --run_id audit_phase12_strict
Rscript application/scripts/00_check_inputs.R --run_id audit_phase12_strict
Rscript application/scripts/00_audit_input_bundle.R --run_id audit_phase12_strict
Rscript application/scripts/01_build_panel.R --run_id audit_phase12_strict
Rscript application/scripts/02_make_input_figures.R --run_id audit_phase12_strict
```

## Authoritative Dec 25 Source Check

The audited Dec 25 source workflow now completes the article-side input stages
against the revised jerez lineage:

- `00_audit_authoritative_source_bundle.R`;
- `materialize_authoritative_cutoff_bundle.R`;
- `00_register_input_bundle.R`;
- `00_check_inputs.R`;
- `00_audit_input_bundle.R`;
- `01_build_panel.R`;
- `02_make_input_figures.R`;
- `02_collect_handoff_figures.R`.

The source audit verifies the reference gauge, GloFAS retrospective path,
issued GloFAS ensemble, GEFS precipitation, GEFS soil-moisture forecasts, local
soil-moisture input, blended or weighted forecast input, retrospective source
family, and the expected post-2021 LISFLOOD GloFAS source for `2022-12-25`.
The materialized bundle is local and ignored by git, but its manifest, source
map, panel summary, figure manifest, git state, and session information are
written into the run directory.

## Authoritative All-Cutoff Source Check

The same source-diagnostic workflow was then run for all copied authoritative
cutoffs with:

```sh
Rscript application/scripts/02_run_authoritative_source_diagnostics.R \
  --run_id authoritative_source_cutoffs_20260512
```

The run completed for five cutoffs: `2021-01-23`, `2021-11-12`,
`2021-12-21`, `2022-05-11`, and `2022-12-25`. The cutoff-aware GloFAS
retrospective rule selected `glofas_hist_v21_htessel_cons` for `2021-01-23`
and `glofas_hist_v31_lisflood_cons` for the four later cutoffs. Each cutoff
produced an audited local bundle, input manifest, panel summary, source
diagnostic figures, and collected GEFS/NWM handoff figures. The combined
summary is written to:

```text
application/runs/authoritative_source_cutoffs_20260512/tables/
```

The run directories and materialized bundles remain ignored by git. This gate
checks the source contract and figures only; it does not fit Q--DESN models or
support manuscript performance claims.

## Remaining Data Work

Before Phase 3 or manuscript-facing application claims, the package-backed dry
run must be completed against the audited input contract. The real application
bundle should include:

- the reference gauge series for the application site;
- the GloFAS retrospective series aligned to the site and calendar;
- issued GloFAS ensemble forecasts by origin, horizon, and member;
- optional climate or hydrologic covariates, if they are used in the final
  application;
- populated forecast-origin cutoffs for evaluation and scoring.

After those inputs are copied locally, rerun the registration, check, audit,
panel, and input-figure stages for each cutoff or for the final combined input
bundle. Only audited run directories should be used to decide whether the real
data match the documentation.
