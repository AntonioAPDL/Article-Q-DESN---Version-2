# Article-Q-DESN 1.0.0 Sync Execution Report

Date: 2026-05-15

Core Article sync commit:

- Commit: `c4e1cffbb2f55a8d5c01446cb551e871bcba3ace`
- Branch: `application-ensemble-likelihood-redesign`
- Remote: `origin/application-ensemble-likelihood-redesign`
- Push status after this pass: local branch synchronized with upstream

## Validation Logic Pin

Article-Q-DESN is synced to the shared validation logic worktree:

- Worktree: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- Commit: `e4e6dc0f7976c1464e91231557f9212914e7438a`
- Package version: `1.0.0`
- Upstream state observed during sync: clean and synchronized with
  `origin/validation/shared-fitforecast-v2-1.0.0`

The previous handoff commit `5de7a28f1f93d884917e26bcbb7aef5676f76cb0` was
superseded by validation-side commit `bd3b7324...` while this sync was in
progress. Article configs now pin the current shared branch HEAD.

Validation later completed and pushed the smoke hardening commit
`e4e6dc0f7976c1464e91231557f9212914e7438a`; Article configs and guards were
updated to this final clean validation HEAD.

## Article Changes

- Updated all active application configs from the old 0.5.0 validation branch
  to the shared 1.0.0 validation logic branch and exact commit.
- Added `application/R/validation_interface_contract.R` and wired it into
  `application/tests/run_tests.R`.
- Added `application/tests/test_validation_interface_contract.R`.
- Added `application/config/figure_specs_dec25_latent_smoke.yaml` so the
  reduced two-horizon smoke config uses its own cutoff id instead of the
  full Dec. 25 authoritative cutoff id.
- Added the seven-horizon micro-pilot gate:
  `application/config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml`,
  `application/config/cutoffs_dec25_latent_micro_pilot.csv`,
  `application/config/model_grid_latent_path_al_vb_dec25_micro_pilot.csv`, and
  `application/config/figure_specs_dec25_latent_micro_pilot.yaml`.
- Updated documentation in `README.md`, `application/README.md`,
  `application/config/README.md`, `application/R/README.md`, and
  `application/scripts/README.md`.
- Updated `scripts/build_qdesn_simulation_tables.R` so the default remains the
  documented historical fit-only table source and any attempted
  `shared_fitforecast` table mode fails closed until validation closeout/export
  is complete.

## Shared Interface Guard

The Article guard matches the validation-side schema file:

`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/schema/shared_fitforecast_interface_schema.csv`

Required fields now include:

- source-registry hash fields
- model family and model variant fields
- fit-window and forecast-origin/window fields
- H=100 and H=1000 forecast metrics
- fit recovery metrics
- runtime/status/failure fields
- package/branch/commit/run provenance
- storage-light artifact paths

The row manifest remains an optional extra provenance cross-check. Article
tables must not be rebuilt from preparation manifests or aborted validation run
scaffolding.

## Verification Run Results

Passed:

```sh
Rscript application/tests/run_tests.R
```

Passed:

```sh
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root(getwd()); source(app_path("application/R/input_contract.R")); source(app_path("application/R/validation_interface_contract.R")); schema <- read.csv("/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/validation/fitforecast_v2/schema/shared_fitforecast_interface_schema.csv", check.names=FALSE); required <- schema$column[schema$required == "true"]; miss <- setdiff(required, app_required_shared_fitforecast_interface_columns()); extra <- setdiff(app_required_shared_fitforecast_interface_columns(), schema$column); if (length(miss) || length(extra)) stop(sprintf("schema mismatch; missing=%s extra=%s", paste(miss, collapse=","), paste(extra, collapse=","))); cat("shared interface schema compatible\n")'
```

Passed for latent-path smoke, pilot, full, and main configs:

```sh
Rscript -e 'source("application/R/00_packages.R"); app_set_repo_root(getwd()); source(app_path("application/R/input_contract.R")); source(app_path("application/R/model_contract.R")); source(app_path("application/R/engine_contract.R")); cfgs <- c("application/config/glofas_latent_path_al_vb_dec25_smoke.yaml", "application/config/glofas_latent_path_al_vb_dec25_pilot.yaml", "application/config/glofas_latent_path_al_vb_dec25_full.yaml", "application/config/glofas_latent_path_al_vb_dec25_main.yaml"); for (p in cfgs) { cfg <- app_read_config(app_path(p)); mg <- tryCatch(app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema")), error=function(e) NULL); res <- app_check_qdesn_engine_api(cfg, require_discrepancy=app_qdesn_engine_requires_discrepancy_export(cfg, mg), stop_on_failure=FALSE); cat(p, "ok=", res$ok, "source_policy_ok=", res$source_policy_ok, "version=", res$version, "branch=", res$repo_branch, "sha=", res$repo_git_sha, "message=", res$message, "\n") }'
```

Correctly failed closed:

```sh
QDESN_SIMULATION_TABLE_SOURCE_MODE=shared_fitforecast Rscript scripts/build_qdesn_simulation_tables.R
```

Smoke design gate passed:

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --cutoff_id dec25_2022 \
  --run_id latent_path_smoke_1p0p0_design_gate_20260515_194250 \
  --design_fit_id qdesn_latent_path_rhs_al_vb_smoke_p50
```

Functional smoke workflow completed input checks, panel, figures, fitting,
scoring, and output generation:

```sh
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --run_id latent_path_smoke_1p0p0_fit_20260515_194520 \
  --preflight true
```

The smoke run failed only at `06_preflight_launch.R` because
`article_git_clean` is required and the sync edits were intentionally still
uncommitted. Functional smoke outputs were written under:

`application/runs/latent_path_smoke_1p0p0_fit_20260515_194520`

Smoke fit summary:

- raw GloFAS smoke row completed in `0.262` seconds
- Q-DESN latent-path AL-VB smoke row completed in `5.845` seconds
- Q-DESN wrote `16` posterior-draw rows and `2` summary prediction rows

## 2026-05-15 Follow-Up Gate Results

The shared-table dry check still fails closed, as intended:

```sh
QDESN_SIMULATION_TABLE_SOURCE_MODE=shared_fitforecast Rscript scripts/build_qdesn_simulation_tables.R
```

Fresh smoke design gate passed:

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --cutoff_id dec25_2022 \
  --run_id latent_path_smoke_1p0p0_design_gate_20260515_203324 \
  --design_fit_id qdesn_latent_path_rhs_al_vb_smoke_p50
```

Micro-pilot design gate passed:

```sh
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml \
  --cutoff_id dec25_2022 \
  --run_id latent_path_micro_pilot_1p0p0_design_gate_20260515_203324 \
  --design_fit_id qdesn_latent_path_rhs_al_vb_micro_pilot_p50
```

Fresh smoke workflow completed every functional stage:

```sh
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --run_id latent_path_smoke_1p0p0_fit_20260515_203324 \
  --preflight true
```

Fresh smoke outputs before committing the Article sync:

- Q-DESN latent-path AL-VB smoke row completed.
- `16` posterior-draw prediction rows satisfied
  `q_y_draw = q_g_draw - d_g_draw`.
- `30` finite prediction rows were written.
- The run failed only at launch-readiness code cleanliness gates:
  `article_git_clean` and `engine_git_clean`.

Micro-pilot workflow completed every functional stage:

```sh
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml \
  --run_id latent_path_micro_pilot_1p0p0_fit_20260515_203324 \
  --preflight true
```

Micro-pilot outputs before committing the Article sync:

- raw GloFAS micro-pilot row completed in `0.241` seconds.
- Q-DESN latent-path AL-VB micro-pilot row completed in `8.136` seconds.
- Q-DESN wrote `224` posterior-draw rows and `7` summary prediction rows.
- `35` finite prediction rows were written.
- All figure, scoring, required-fit, and posterior-draw contract checks passed.
- The run failed only at launch-readiness code cleanliness gates:
  `article_git_clean` and `engine_git_clean`.

After committing and pushing the Article sync, both completed runs were audited
again with `06_preflight_launch.R`. Article-side cleanliness and upstream-sync
checks passed. The only remaining required launch-readiness failure in both
runs is `engine_git_clean`, because the shared validation worktree is dirty.

## Pilot Attempt

Pilot input checks, panel, and figures completed:

```sh
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_pilot.yaml \
  --run_id latent_path_pilot_1p0p0_fit_20260515_194520 \
  --preflight true
```

The pilot was stopped after more than 23 minutes of CPU-active fitting without
fit-stage outputs. This suggests the current median-only pilot is too large to
serve as a quick sync gate. Treat it as a sizing/runtime blocker before any
full launch.

## Remaining Blockers

- Article changes are committed and pushed at `c4e1cff...`; `article_git_clean`
  and `article_git_upstream_synced` pass.
- The shared validation engine worktree is currently dirty even though its
  upstream branch is synchronized at `bd3b7324...`. Article launch-readiness
  correctly refuses to bless a dirty engine source until the validation chat
  either commits those changes on the validation branch or reverts them.
- Validation-side article-facing fit+forecast result interfaces are still not
  cleared as table inputs until validation closeout/export confirms completed
  Q-DESN and exDQLM/DQLM outputs.
- The large median-only pilot is still a runtime-sizing concern: it was stopped
  after more than 23 minutes of CPU-active fitting without fit-stage outputs.
  The new seven-horizon micro-pilot is the practical launch gate before that
  larger pilot is revisited.
- Main/full application launch remains blocked until the engine worktree is
  clean, the validation chat confirms final shared interface exports, and the
  main launch command is deliberately run with
  `--confirm_final_launch true`.

## Next Safe Commands

Review the sync diff:

```sh
git diff --stat
git diff -- README.md application docs scripts
```

Rerun the Article test suite:

```sh
Rscript application/tests/run_tests.R
```

Rerun the smoke workflow after committing the sync if a clean preflight is
needed:

```sh
RUN_ID=latent_path_smoke_1p0p0_fit_$(date +%Y%m%d_%H%M%S)
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_smoke.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

Run the micro-pilot gate:

```sh
RUN_ID=latent_path_micro_pilot_1p0p0_$(date +%Y%m%d_%H%M%S)
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml \
  --cutoff_id dec25_2022 \
  --run_id "${RUN_ID}_design_gate" \
  --design_fit_id qdesn_latent_path_rhs_al_vb_micro_pilot_p50

Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

Do not launch the main run yet.
