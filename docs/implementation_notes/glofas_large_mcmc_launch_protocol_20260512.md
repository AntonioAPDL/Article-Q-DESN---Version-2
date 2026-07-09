# GloFAS Large MCMC Launch Protocol

Date: 2026-05-12

## Purpose

This protocol defines the reproducibility gate for the large Dec. 25, 2022
GloFAS discrepancy Q-DESN fit. It is intentionally separated from the MCMC
launch. The gate verifies the source lineage, materialized inputs, derived
panel, and Q-DESN design before any sampler is started.

## Configuration Boundary

The launch is controlled by tracked configuration rather than by editing R
scripts:

```text
application/config/authoritative_cutoff_sources.csv
application/config/input_bundle_authoritative_dec25.yaml
application/config/glofas_discrepancy_mcmc_large_dec25.yaml
application/config/model_grid_mcmc_large_dec25.csv
application/config/quantile_grid_mcmc_diagnostic.csv
application/config/cutoffs_dec25_authoritative.csv
```

To change the cutoff, edit or add a row in
`authoritative_cutoff_sources.csv` and the cutoff file. To change the reservoir
or prior, edit the YAML and model grid. To change quantile levels, edit the
quantile grid and model grid. The scripts should not be edited for these
scientific choices.

## Large Specification

The current large configuration uses:

```text
D = 2
n = (500, 500)
n_tilde = 500
m = 180
washout = 500
likelihood = AL
coefficient prior = regularized horseshoe
rhs_tau0 = 1e-4
burn_in = 1000
n_iter = 2000
thin = 1
```

The posterior prediction contract is draw-based:

```text
q_y_draw = q_g_draw - d_g_draw
```

Point summaries are derived after draw-level subtraction.

## Input and Design Gate

Run the full pre-MCMC gate with:

```sh
RUN_ID=long_history_dec25_input_design_gate_20260512

Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --cutoff_id dec25_2022 \
  --run_id "$RUN_ID" \
  --design_fit_id qdesn_discrepancy_rhs_al_mcmc_large_p50
```

The `--design_fit_id` option can be omitted to build the design for all enabled
Q-DESN rows. For the current model grid, the design is identical across
quantile levels except for the target level recorded in the summary, so the
median row is a fast launch gate. A final prelaunch check over all rows is also
available when time permits.

The gate runs these stages:

```text
00_materialize_from_source_registry.R
00_audit_authoritative_source_bundle.R
00_register_input_bundle.R
00_audit_glofas_retrospective_history.R
00_check_inputs.R
00_audit_input_bundle.R
01_build_panel.R
03_check_model_design.R
```

## Required Gate Outputs

The run directory must contain:

```text
manifest/authoritative_cutoff_source_selected.csv
tables/authoritative_materialization_summary.csv
tables/authoritative_source_bundle_audit.csv
tables/glofas_retrospective_history_audit.csv
tables/glofas_retrospective_overlap_summary.csv
tables/input_check_status.csv
tables/input_bundle_audit.csv
tables/application_panel_summary.csv
tables/qdesn_discrepancy_design_preflight.csv
tables/qdesn_discrepancy_prediction_design_preflight.csv
```

Expected Dec. 25 checks:

```text
GloFAS retrospective date range: 1987-05-29 to 2022-12-25
GloFAS source id: glofas_hist_v31_lisflood_cons
Issued GloFAS ensemble target range: 2022-12-26 to 2023-01-22
No duplicate retrospective or ensemble rows
No missing reference or GloFAS values in the panel
No horizon calendar violations
Large median design: 1304 base features and 2608 augmented features
Feature contract: 1 intercept, 1000 reservoir features, 180 output lags,
122 precipitation/soil lags, and 1 scaled-horizon feature
```

## MCMC Launch

Do not start MCMC unless the input and design gate has completed. The launch
command is:

```sh
RUN_ID=mcmc_large_dec25_long_history_fit_YYYYMMDD

Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --run_id "$RUN_ID"
```

After fitting, run:

```sh
Rscript application/scripts/04_score_models.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --run_id "$RUN_ID"

Rscript application/scripts/05_make_outputs.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --run_id "$RUN_ID"

Rscript application/scripts/06_preflight_launch.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --run_id "$RUN_ID"
```

This large run is still a scientific pilot until its diagnostics are reviewed.
Do not promote performance claims to the manuscript until the fit manifest,
posterior-draw checks, effective-sample-size summaries, score tables, generated
figures, and provenance tables are inspected.
