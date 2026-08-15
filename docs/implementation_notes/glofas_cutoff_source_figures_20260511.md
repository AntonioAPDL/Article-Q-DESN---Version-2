# GloFAS Cutoff-Source Figure Workflow

This note records the article-side workflow for producing source diagnostics at
a selected GloFAS forecast origin. The current manuscript-facing example uses
the audited jerez bundle for cutoff `2022-12-25`. A separate legacy diagnostic
path remains available only for local code-path checks.

## Purpose

The figure is an input audit. It shows, on the same transformed scale,
historical reference streamflow through the cutoff, the GloFAS retrospective
path through the cutoff, the GloFAS ensemble issued at the cutoff, and held-out
reference observations after the cutoff. These held-out observations are drawn
only as visual reference and are not predictors for a model fit.

The Dec 25 manuscript-facing materialization is marked
`authoritative_jerez_audited`. The legacy materialization is deliberately
marked `local_legacy_unverified` and should not be used for model fitting,
scoring, or manuscript-facing GloFAS claims.

## Tracked Inputs

- `application/scripts/import_authoritative_jerez_inputs.sh`: imports the
  revised jerez frozen input bundle and audit artifacts into ignored
  article-side directories, including the GEFS/NWM precipitation and
  soil-moisture handoff cache.
- `application/config/authoritative_source_requirements.yaml`: declares the
  source families required before manuscript-facing figures can be generated.
- `application/scripts/00_audit_authoritative_source_bundle.R`: verifies that a
  copied authoritative bundle contains the reference gauge, GloFAS
  retrospective, GloFAS ensemble, GEFS precipitation, GEFS soil-moisture
  forecasts, local soil moisture, blended or weighted forecast input,
  retrospective family, and GloFAS version evidence.
- `application/config/glofas_dec25_source_figures.yaml`: run configuration for
  the local legacy Dec 25 source diagnostic.
- `application/config/glofas_dec25_authoritative_source_figures.yaml`: run
  configuration for the audited jerez Dec 25 source diagnostic.
- `application/config/input_bundle_legacy_dec25.yaml`: local input-bundle
  registration contract.
- `application/config/input_bundle_authoritative_dec25.yaml`: audited jerez
  input-bundle registration contract.
- `application/config/cutoffs_dec25.csv`: cutoff definition and evaluation
  window for the local legacy Dec 25 origin.
- `application/config/cutoffs_dec25_authoritative.csv`: cutoff definition and
  evaluation window for the audited jerez Dec 25 origin.
- `application/config/figure_specs_dec25_source.yaml`: figure specification with
  `cutoff_source_diagnostic` enabled for the local legacy path.
- `application/config/figure_specs_dec25_authoritative.yaml`: figure
  specification with `cutoff_source_diagnostic` enabled for the audited jerez
  path.
- `application/config/model_grid_source_figures.csv`: raw-only placeholder model
  grid used so schema checks can run without requiring a Q-DESN engine.
- `application/scripts/local_prepare_legacy_cutoff_bundle.R`: materializes
  cutoff-specific legacy files into the application input schema.

## Ignored Outputs

The local materialized inputs, cache, manifests, and run outputs are ignored by
git:

- `application/data_local/frozen_inputs/legacy_dec25_2022`
- `application/data_local/frozen_inputs/authoritative_dec25_2022`
- `application/cache/legacy_dec25_2022`
- `application/cache/authoritative_dec25_2022`
- `application/manifests/input_manifest.csv`
- `application/manifests/input_bundle_manifest.csv`
- `application/runs/dec25_source_figures_legacy_20260511`
- `application/runs/dec25_source_figures_authoritative_20260511`

The run directory records the input manifest, panel summary, figure manifest,
cutoff-source summary, git state, and session information.

## Reproducible Command

For manuscript-facing inputs, first import and audit the jerez bundle:

```bash
application/scripts/import_authoritative_jerez_inputs.sh

Rscript application/scripts/00_audit_authoritative_source_bundle.R \
  --bundle_root application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505 \
  --cutoff_date 2022-12-25 \
  --extra_root application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z \
  --run_id authoritative_source_audit_20260511
```

If `muscat` cannot authenticate to `jerez`, perform the same copy from a host
that can read the jerez project tree and place the files under
`application/data_local/upstream_jerez/`. The audit is still the gatekeeper for
any manuscript-facing figures.

Only after that audit passes should the copied bundle be materialized into the
application panel contract and used for figures or fits.

For the audited Dec 25, 2022 cutoff, the article-side materialization and
figure workflow is:

```bash
Rscript application/scripts/materialize_authoritative_cutoff_bundle.R

Rscript application/scripts/00_register_input_bundle.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --bundle_config application/config/input_bundle_authoritative_dec25.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/00_check_inputs.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/00_audit_input_bundle.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/01_build_panel.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/02_make_input_figures.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511

Rscript application/scripts/02_collect_handoff_figures.R \
  --config application/config/glofas_dec25_authoritative_source_figures.yaml \
  --run_id dec25_source_figures_authoritative_20260511 \
  --cutoff_date 2022-12-25
```

For the unverified local legacy diagnostic only:

```bash
Rscript application/scripts/local_prepare_legacy_cutoff_bundle.R \
  --legacy_root /data/jaguir26/muscat_data_backup/jaguir26/project1_ucsc_phd \
  --cutoff_date 2022-12-25 \
  --bundle_root application/data_local/frozen_inputs/legacy_dec25_2022 \
  --allow_unverified_legacy true

RUN_ID=dec25_source_figures_legacy_20260511
CFG=application/config/glofas_dec25_source_figures.yaml
BUNDLE=application/config/input_bundle_legacy_dec25.yaml

Rscript application/scripts/00_register_input_bundle.R \
  --config "$CFG" \
  --bundle_config "$BUNDLE" \
  --run_id "$RUN_ID"
Rscript application/scripts/00_check_inputs.R --config "$CFG" --run_id "$RUN_ID"
Rscript application/scripts/00_audit_input_bundle.R --config "$CFG" --run_id "$RUN_ID"
Rscript application/scripts/01_build_panel.R --config "$CFG" --run_id "$RUN_ID"
Rscript application/scripts/02_make_input_figures.R --config "$CFG" --run_id "$RUN_ID"
```

The audited manuscript-facing cutoff figure is:

```text
application/runs/dec25_source_figures_authoritative_20260511/figures/input_diagnostics/cutoff_source_diagnostic_dec25_2022.pdf
```

The corresponding imported GEFS/NWM precipitation and soil-moisture handoff
figures are collected under:

```text
application/runs/dec25_source_figures_authoritative_20260511/figures/handoff_diagnostics/cutoff_date=2022-12-25/
```

## Validation Checks

The workflow is covered by two application tests:

- `application/tests/test_legacy_source_bundle_prep.R` checks that a toy legacy
  cutoff bundle is materialized with the expected schema, horizons, members,
  and source map.
- `application/tests/test_input_figures.R` checks that the cutoff-centered
  figure type can be generated from a toy panel and that its summary table
  records the selected cutoff, horizon range, and member count.

Run all application tests with:

```bash
Rscript application/tests/run_tests.R
```

On the current server, the discrepancy-fit adapter test is skipped when the
Q-DESN discrepancy engine is not installed, but the source-bundle and
source-figure checks complete.

## Final-Application Caution

The audited Dec 25 workflow verifies that the retrospective GloFAS path is the
post-2021 LISFLOOD source and that the copied GEFS/NWM handoff exposes the
precipitation, soil-moisture, blended-input, and health-check artifacts needed
for the application. The legacy path remains useful for local smoke testing
only. It should not be promoted into model fitting, scoring, or manuscript
outputs.
