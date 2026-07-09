# GloFAS Prelaunch Runbook

Date: 2026-05-11

## Purpose

This runbook defines the last reproducibility gate before the main GloFAS
Q--DESN application launch. The gate is intentionally smaller than the final
application: it verifies the input contract, diagnostic figures, package API,
scoreable discrepancy bridge, provenance files, and launch-readiness checks
without producing manuscript performance claims.

## Required Inputs

The registered input manifest must already exist at:

```text
application/manifests/input_manifest.csv
```

The manifest must point to frozen local inputs under the ignored application
workspace and must pass `application/scripts/00_check_inputs.R`.

## Dry-Run Configuration

Use the prelaunch dry-run configuration:

```text
application/config/glofas_discrepancy_prelaunch_dryrun.yaml
application/config/model_grid_prelaunch_dryrun.csv
```

This configuration fits only:

- the raw GloFAS median baseline;
- one AL-MCMC Q--DESN discrepancy model with the regularized horseshoe prior.

It is a workflow and provenance check. It is not a replacement for the final
exAL or VB--LD application run.

## Command

Run the dry run from the repository root:

```sh
hash -r
which Rscript
Rscript -e 'cat(R.version.string, "\n"); cat("R_HOME=", R.home(), "\n", sep = "")'

RUN_ID=prelaunch_dryrun_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_prelaunch_dryrun.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

Expected runtime on Muscat is `/home/jaguir26/.local/bin/Rscript`, R 4.6.0,
with `R_HOME=/data/jaguir26/local/opt/R/4.6.0/lib64/R`. Do not use legacy
R-4.4 user-library prefixes for this gate.

The `--preflight true` flag appends `06_preflight_launch.R` after the ordinary
staged workflow.

## Required Artifacts

The completed run directory must contain:

- `manifest/input_manifest_used.csv`;
- `manifest/model_grid_used.csv`;
- `manifest/quantile_grid_used.csv`;
- `manifest/run_config.yaml`;
- `manifest/git_state.txt`;
- `manifest/session_info.txt`;
- `manifest/qdesn_engine_contract.csv`;
- `tables/figure_manifest.csv`;
- `tables/fit_status.csv`;
- `tables/prediction_quantiles.csv`;
- `tables/score_summary.csv`;
- `tables/launch_readiness_report.csv`;
- `tables/launch_readiness_summary.txt`;
- input diagnostic PDFs under `figures/input_diagnostics/`.

## Passing Criteria

The dry run is ready for a final launch decision only when:

- all required input files exist and match their hashes;
- every stage from `00_check_inputs` through `05_make_outputs` completed;
- the preflight stage completed;
- all diagnostic figure files exist and contain at least one readable page;
- raw GloFAS and Q--DESN discrepancy prediction rows are present;
- every prediction row records the forecast contract, contract version,
  forecast scope, GloFAS quantile source, discrepancy feature strategy, and
  prediction unit;
- pilot discrepancy prediction rows satisfy `qhat = q_g_hat - d_g_hat`;
- required model fits did not fail;
- the score table is nonempty;
- the article repo and engine repo are clean;
- the engine SHA is recorded;
- the R executable path, R version, `R_HOME`, and library paths are recorded;
- the run is explicitly marked as a pilot or prelaunch dry run.

## Boundary

Passing this gate means the workflow is wired, documented, and reproducible
enough to schedule the main launch. It does not validate final performance and
does not license manuscript claims. The main launch must use a separate run ID,
the final application configuration, and its own preflight report. A final
launch must not use a `pilot_` prediction contract unless the contract has been
renamed and justified as the final scientific prediction rule. For discrepancy
models, the final prediction unit must be posterior draws satisfying
`q_y_draw = q_g_draw - d_g_draw`; point summaries are derived afterward. A
final launch must also record `q_g_source = posterior_model_quantile`, write
`tables/posterior_draw_predictions.csv`, and pass the draw-table validation in
`application/R/forecast_contract.R`.
