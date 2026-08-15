# GloFAS Latent-Path Relaunch Preparation

Date: 2026-05-15

## Scope

This note documents the relaunch-preparation layer for the Dec. 25, 2022
latent-path ensemble-likelihood Q--DESN application model. It is a
source/API/wiring/documentation checkpoint. It is not a validation relaunch and
not the main application fit.

The current launch target is:

- config: `application/config/glofas_latent_path_al_vb_dec25_main.yaml`
- model grid: `application/config/model_grid_latent_path_al_vb_dec25_main.csv`
- fit id: `qdesn_latent_path_rhs_al_vb_main_p50`
- contract: `latent_path_ensemble_likelihood`
- likelihood and inference route: AL working likelihood with article-side VB
- readout prior: regularized horseshoe with `rhs_tau0 = 1e-6`
- reservoir: `D = 2`, `n = (1000, 1000)`, `n_tilde = 500`, `m = 360`,
  `washout = 500`
- VB cap: 200 iterations

## Source State

The article repository is expected to be on branch
`application-ensemble-likelihood-redesign`. The relaunch preparation follows
the 0.5.0-compatible Q--DESN/exDQLM engine sync.

Pinned engine source:

- path: `/data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0`
- branch: `feature/qdesn-fitforecast-validation-0p5p0`
- commit: `1417a825d24a6ac805b3b4af8033bb8e14a29187`
- minimum package version: `0.5.0`
- load mode: `local_source`

The current latent-path workflow does not require the legacy
`qdesn_fit_discrepancy()` export. That export remains part of the older
origin-state bridge only.

## Cancelled Run

The run id
`latent_path_main_al_vb_n1000_m360_20260515_024133` was intentionally
cancelled during the fit stage and must not be reused. Launch-control helpers
block this id before any new workflow begins.

## Relaunch Guards

The relaunch-preparation pass adds an explicit launch-control contract:

- `run_all.R --preflight true` is not a dry run. It executes the ordinary
  workflow stages and appends `06_preflight_launch.R`.
- Any configuration with `execution.final_launch.enabled: true` must pass
  `--confirm_final_launch true` before `run_all.R` or `03_fit_models.R` can
  enter the fit stage.
- `run_all.R` refuses to reuse a nonempty run directory unless
  `--allow_existing_run_dir true` is supplied for an intentional resume.
- The fit manifest records the Q--DESN source path, branch, commit, load mode,
  version, required exports, missing exports, and source-policy result.
- Generated-artifact cleanup is report-only. The artifact audit inventories
  generated or heavy local outputs and does not delete files.

## Safe Gates

Use these checks before any relaunch:

```sh
Rscript -e 'cat(R.version.string, "\n"); stopifnot(getRversion() >= "4.6.0")'
Rscript application/tests/run_tests.R
```

```sh
Rscript application/scripts/00_audit_generated_artifacts.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --output application/runs/local_audits/generated_artifact_inventory_YYYYMMDD.csv
```

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --cutoff_id dec25_2022 \
  --run_id latent_path_main_0p5p0_input_design_gate_YYYYMMDD_HHMMSS \
  --design_fit_id qdesn_latent_path_rhs_al_vb_main_p50
```

```sh
Rscript application/scripts/03_check_model_design.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_0p5p0_design_recheck_YYYYMMDD_HHMMSS \
  --fit_id qdesn_latent_path_rhs_al_vb_main_p50
```

```sh
Rscript application/scripts/03_profile_latent_path_al_vb.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_0p5p0_profile_YYYYMMDD_HHMMSS \
  --fit_id qdesn_latent_path_rhs_al_vb_main_p50 \
  --future_laplace false \
  --save_design false
```

These commands verify runtime, input lineage, model-grid support, DESN design
construction, effective issued horizon, and VB structure without launching the
main fit.

## Real Launch Command

Do not run this command until the safe gates have passed and the launch is
explicitly approved:

```sh
RUN_ID=latent_path_main_al_vb_n1000_m360_YYYYMMDD_HHMMSS
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id "$RUN_ID" \
  --preflight true \
  --confirm_final_launch true
```

This command starts the real application fit.

## Completion Criteria

The relaunch preparation is complete when:

- the test suite passes under R 4.6.0;
- stale 0.4.0 engine paths fail source-policy checks;
- the main final-launch config cannot reach `03_fit_models.R` without explicit
  confirmation;
- the cancelled run id is blocked;
- documentation no longer describes `run_all.R --preflight` as a safe dry run;
- main config descriptions match the actual `rhs_tau0 = 1e-6` setting;
- design summaries record requested and effective issued horizons; and
- no heavy generated artifacts are staged.

## Verification Results

The relaunch-preparation implementation was checked without launching the main
fit.

Runtime:

- `Rscript -e 'cat(R.version.string, "\n"); stopifnot(getRversion() >= "4.6.0")'`
  reported R 4.6.0.

Test suite:

- `Rscript application/tests/run_tests.R` completed successfully.
- The test suite intentionally skipped the legacy discrepancy-fit adapter when
  the 0.5.0-compatible engine did not expose `qdesn_fit_discrepancy()`. This is
  expected for the latent-path workflow.

Launch-control smoke checks:

- `run_all.R` refused the main final-launch config without
  `--confirm_final_launch true`.
- Direct `03_fit_models.R` refused the same config without
  `--confirm_final_launch true`.

Design check:

- run id: `latent_path_main_0p5p0_design_recheck_20260515_relaunchprep_v2`
- design hash: `8c8c9b2dff606dc2baa67641770548c0935e72a038821f02ee60aa183daf45bb`
- fixed rows: 24,990
- stacked rows: 26,446
- base features: 1,501
- augmented features: 3,002
- reservoir input output-lag features: 360
- reservoir input covariate-lag features: 122
- requested horizon max: 30
- effective horizon max: 28
- horizon scope: `available_issued_ensemble_horizon`
- feature strategy: `recursive_latent_path`

Profiler:

- run id: `latent_path_main_0p5p0_profile_20260515_relaunchprep`
- total profile time: about 686 seconds
- design build: about 125 seconds
- initial row moments: about 277 seconds
- one theta update: about 266 seconds
- peak observed RSS during profiled steps: about 1.6 GB
- strategy: `streamed_grouped` moments with `linearized_delta` future update

Input/design gate:

- run id: `latent_path_main_0p5p0_input_design_gate_20260515_relaunchprep`
- input manifest, quantile grid, model grid, cutoff file, engine contract, and
  inference-support checks passed.
- The retrospective audit confirmed the long-history start date, cutoff
  clipping, GloFAS source id `glofas_hist_v31_lisflood_cons`, and overlap with
  the previous short source at tolerance `1e-8`.
- The design hash matched the standalone design check.

No `03_fit_models.R` main launch was run during these checks.

Artifact audit:

- `00_audit_generated_artifacts.R` is available as a report-only inventory
  before disk cleanup. No generated outputs were deleted as part of this
  relaunch-preparation pass.
- The local inventory was written to
  `application/runs/local_audits/generated_artifact_inventory_20260515_relaunchprep.csv`.
