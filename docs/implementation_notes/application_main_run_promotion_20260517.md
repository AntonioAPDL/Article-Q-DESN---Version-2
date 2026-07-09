# Article-Q-DESN Application Output Promotion, 2026-05-17

## Run promoted

- Run id: `latent_path_main_al_vb_n1000_m360_20260515_221729`
- Config: `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- Validation worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Validation branch: `validation/shared-fitforecast-v2-1.0.0`
- Validation commit accepted by launch-readiness: `e4e6dc0f7976c1464e91231557f9212914e7438a`
- Required launch-readiness failures after targeted recheck: `0`

The original end-to-end `run_all.R --preflight true` exit-code file remains a
historical record of the stale validation-commit pin that was diagnosed in
`docs/implementation_notes/application_main_run_audit_20260517.md`. The targeted
post-fix readiness report is the active gate for this completed run.

## Promotion command

```sh
Rscript application/scripts/08_promote_application_outputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_al_vb_n1000_m360_20260515_221729 \
  --output_slug latent_path_main_al_vb_n1000_m360_20260515_221729
```

The promotion script copies only storage-light article-facing outputs and writes
a hash manifest. It refuses promotion when any required readiness check failed,
unless `--allow_required_failures true` is supplied for an explicit diagnostic
case.

## Article-facing outputs

Promotion manifest:

```text
tables/glofas_application_promotion_manifest__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
```

Promoted tables:

```text
tables/glofas_application_score_summary__latent_path_main_al_vb_n1000_m360_20260515_221729.tex
tables/glofas_application_score_summary__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_post_fit_metrics_by_model__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_post_fit_metrics_by_horizon__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_forecast_window_band_check__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_post_fit_parameter_summary__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_post_fit_trace_summary__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_launch_readiness_report__latent_path_main_al_vb_n1000_m360_20260515_221729.csv
tables/glofas_application_launch_readiness_summary__latent_path_main_al_vb_n1000_m360_20260515_221729.txt
```

Promoted figures:

```text
figures/glofas_application/
figures/glofas_application/post_fit/
```

Heavy run-local outputs are intentionally not promoted. In particular, the
posterior draw table remains here:

```text
application/runs/latent_path_main_al_vb_n1000_m360_20260515_221729/tables/posterior_draw_predictions.csv
```

## Verification performed

- Promotion manifest rows: `21`
- Manifest storage classes: `9` article tables, `2` article figures,
  `10` post-fit figures
- Manifest engine SHA: `e4e6dc0f7976c1464e91231557f9212914e7438a`
- Engine SHA source: `application/runs/latent_path_main_al_vb_n1000_m360_20260515_221729/tables/post_analysis_manifest.csv`
- All promoted source files existed
- All promoted files existed after copy
- All promoted file hashes matched their source hashes
- Promoted PDF count: `12`
- Promoted PDF structural check: all readable, one page each

## Reproducibility checks

Use these checks before treating the promoted outputs as the manuscript-facing
application artifacts:

```sh
Rscript application/tests/run_tests.R

Rscript -e 'm <- read.csv("tables/glofas_application_promotion_manifest__latent_path_main_al_vb_n1000_m360_20260515_221729.csv", stringsAsFactors = FALSE); stopifnot(nrow(m) == 21L, all(file.exists(m$promoted_path)), all(m$source_sha256 == m$promoted_sha256), identical(unique(m$engine_repo_sha), "e4e6dc0f7976c1464e91231557f9212914e7438a"))'

Rscript application/scripts/06_preflight_launch.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_al_vb_n1000_m360_20260515_221729
```

## New launch under new specs

A new full application launch should be started only after the new specs are
made explicit in a new or updated config. Use the existing main config as the
template, then rerun the design/readiness gates before launching:

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config <new_config.yaml> \
  --run_id <new_run_id>_design_gate

Rscript application/scripts/run_all.R \
  --config <new_config.yaml> \
  --run_id <new_run_id> \
  --preflight true \
  --confirm_final_launch true

Rscript application/scripts/08_promote_application_outputs.R \
  --config <new_config.yaml> \
  --run_id <new_run_id> \
  --output_slug <new_run_id>
```

The launch-readiness gate must still require the shared validation branch,
package version `1.0.0`, and the accepted validation commit for the run. If the
validation worktree advances before the next launch, update the Article config
only after the validation chat confirms the new commit is clean, pushed, and
valid for application consumption.
