# GloFAS Q-DESN Application

This directory will contain the reproducible workflow for the GloFAS
streamflow forecast-calibration application described in Section 9 of the
article.

The application is article-owned. The Q-DESN computational engine may be
installed from a pinned `exdqlm` commit or vendored later as a small audited
module, but the data contract, forecast-origin protocol, model grid, scoring,
and manuscript outputs live here.

The current application work distinguishes the frozen origin-state bridge from
the target latent-path ensemble-likelihood model. The model-family separation
is documented in
`docs/implementation_notes/glofas_application_model_families_20260513.md`.
The original bridge contract remains documented in
`docs/implementation_notes/glofas_model_contract_20260511.md`, and the
code-facing object and API mapping is documented in
`docs/implementation_notes/glofas_implementation_spec_20260511.md`. The
required Q-DESN application fits use the regularized horseshoe prior; ridge
fits are retained as dense baselines.

The forward launch gates are documented in
`docs/implementation_notes/glofas_application_forward_plan_20260511.md`. That
note is the current checkpoint for moving from audited source figures to the
package-backed dry run and final application launch.

The first executable latent-path smoke profile is
`config/glofas_latent_path_al_vb_dec25_smoke.yaml`, with model rows in
`config/model_grid_latent_path_al_vb_dec25_smoke.csv`. It uses the audited
Dec. 25, 2022 input bundle, a deliberately small history and horizon window,
the AL working likelihood, the regularized horseshoe prior, and an
article-side VB approximation. This profile is a wiring and reproducibility
check for recursive future-state construction and posterior-draw output. It is
not an application-scale fit and should not be used for manuscript performance
claims.

The next launch gate is
`config/glofas_latent_path_al_vb_dec25_micro_pilot.yaml`, with model rows in
`config/model_grid_latent_path_al_vb_dec25_micro_pilot.csv`. It uses the same
real Dec. 25 source bundle and recursive posterior-draw contract, but extends
the smoke to seven forecast horizons with a modest reservoir and draw count.
This profile is the reproducible end-to-end pilot gate before spending compute
on the larger median-only pilot.

The covariate-aware latent-path full profile is documented in
`docs/implementation_notes/glofas_latent_path_vb_structure_profile_20260514.md`.
That note records the current VB structure decision: dense future-row moments
are retained only as a debug reference, while the executable full profile uses
keyed future-builder output, streamed grouped moments, a linearized Delta
future-path update, and first-order Delta posterior-draw prediction. The full
covariate-aware AL-VB readiness profile remains disabled. The safe full-specification
pilot is `config/glofas_latent_path_al_vb_dec25_pilot.yaml`, with model rows in
`config/model_grid_latent_path_al_vb_dec25_pilot.csv`. It mirrors the current
large DESN and covariate-aware reservoir input contract but limits VB to a
short diagnostic run. The historical completed pilot
`latent_path_fullspec_pilot_fit_20260514_214438` verified the latent-path code
path, posterior-draw prediction contract, post-fit uncertainty-band checks, and
diagnostic plot generation under the previous launch size; it is not a
manuscript-scale fit.

The main Dec. 25 latent-path AL-VB launch is configured separately in
`config/glofas_latent_path_al_vb_dec25_main.yaml`, with model rows in
`config/model_grid_latent_path_al_vb_dec25_main.csv`. This main configuration
uses `D = 2`, `n = (1000, 1000)`, `n_tilde = 500`, `m = 360`,
`washout = 500`, `rhs_tau0 = 1e-6`, and
`rhs_freeze_tau_warmup_iters = 50`. It caps VB at 200 iterations, keeps
2,000 posterior-draw summaries, and sets
`execution.final_launch.enabled: true`. Article-side VB launch configurations
are guarded by a 500-iteration hard cap to avoid accidentally running obsolete
1,500-iteration profiles.

Because the main configuration is marked as a final launch, it cannot reach
`scripts/03_fit_models.R` unless the command includes
`--confirm_final_launch true`. The wrapper option `--preflight true` is not a
dry run; it appends `scripts/06_preflight_launch.R` after the ordinary workflow
stages. Safe launch preparation should use the tests,
`scripts/run_input_design_gate.R`, `scripts/03_check_model_design.R`, and
`scripts/03_profile_latent_path_al_vb.R`. The cancelled run id
`latent_path_main_al_vb_n1000_m360_20260515_024133` is permanently blocked.

## Runtime Contract

Application and validation-facing commands should use the local R 4.6.0
runtime:

```sh
hash -r
which R
R --version
Rscript -e 'cat(R.version.string, "\n"); cat("R_HOME=", R.home(), "\n", sep = "")'
```

Expected values on Muscat are:

```text
R=/home/jaguir26/.local/bin/R
Rscript=/home/jaguir26/.local/bin/Rscript
R version 4.6.0 (2026-04-24)
R_HOME=/data/jaguir26/local/opt/R/4.6.0/lib64/R
```

The system `/usr/bin/R` may still be R 4.5.3. Do not set an old
`R_LIBS_USER` path or silently fall back to `/usr/bin/R`; if a shell has cached
the old executable, run `hash -r` before launching tests or application stages.

## Directory Contract

Tracked source and documentation:

- `config/`: human-readable configuration files for cutoffs, quantile grids,
  model grids, input-bundle registration, figure specifications, and execution
  profiles.
- `manifests/`: schema files and manifest templates for audited inputs and
  derived panels.
- `R/`: application-specific R functions.
- `scripts/`: executable workflow stages.
- `tests/`: reproducibility and leakage checks.

Ignored local artifacts:

- `data_local/`: frozen GloFAS, gauge, and covariate handoffs.
- `cache/`: derived panels and intermediate objects.
- `runs/`: complete local run archives, including manifests, stage logs,
  run-private tables, fitted objects, input figures, and post-fit diagnostics.
- `logs/`: launcher/session logs outside the per-run stage logs.
- `outputs/`: storage-light generated-output staging before manuscript
  promotion.

## PriceFM Data-Layer Pilot

The PriceFM data pipeline is staged under `scripts/pricefm/` with configuration
in `config/pricefm_data_pipeline.yaml`. It is a data-layer pilot only:
download, audit, split, scale, and window construction for the Hugging Face
`RunyaoYu/PriceFM` `FINAL.csv` artifact. Generated data stay ignored under
`data_local/pricefm/`, with logs under `logs/pricefm/`.

The first operational target is deliberately narrow: DE_LU, fold 1, L96/H96
rolling windows, train-only robust scaling, and explicit `market_time =
time_utc + 1 hour` manifests. These artifacts are not Q-DESN model inputs until
a later modeling adapter is explicitly specified and tested.

The current median PriceFM modeling workflow uses tracked experiment-grid
configs under `application/config/` and ignored run/output roots under
`application/data_local/pricefm/`. The fold 2/3 follow-up seed/refinement grid
is prepared by
`scripts/pricefm/28_prepare_median_folds23_followup_grid.py` and tracked as
`config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml`.
The stage note
`docs/implementation_notes/pricefm_de_lu_folds23_followup_seed_refine_20260605.md`
records the exact scope, validation-only selection rule, launch command, and
post-launch summary command. The completed follow-up registry is archived
locally under
`data_local/pricefm/authoritative/pricefm_median_de_lu_folds23_followup_registry_20260605/`,
with compact tracked snapshots in `docs/implementation_notes/`. The promoted
fold-2/fold-3 paper-quantile grid generated from that registry is tracked as
`config/pricefm_desn_experiment_grid_de_lu_folds23_followup_promoted_quantiles_20260605.yaml`.

## Application Artifact Lifecycle

Application outputs move through three layers:

```text
application/runs/<run_id>              complete local run archive
        -> scripts/05_make_outputs.R
application/outputs/generated/<run_id> generated-output staging
        -> scripts/08_promote_application_outputs.R
tables/ and figures/                   tracked article-facing outputs
        -> scripts/09_select_application_outputs.R
tables/glofas_application_current_*     current manuscript-facing aliases
```

`application/runs/<run_id>/` is the authoritative local archive for a run. It
contains the config snapshot, input/model/quantile manifests, fit status,
prediction tables, posterior-draw tables, fitted objects, and diagnostic
figures. Most post-fit figures live under
`application/runs/<run_id>/figures/post_fit_analysis/`.

`application/outputs/generated/<run_id>/` is not the final article interface.
It contains only lightweight generated-output candidates from
`05_make_outputs.R`, such as the score-summary TeX file and compact
manuscript-style PDFs.

The tracked article interface is the repository-level `tables/` and
`figures/` directories. Files should reach those directories only through
`08_promote_application_outputs.R`, after required launch-readiness checks
pass. Final application promotion must use a tracked config under
`application/config/` or promote an explicit run-config snapshot; final
manuscript provenance should not depend only on ignored local runtime configs.

The manuscript should not hard-code long run-specific promoted file names.
After promotion, `09_select_application_outputs.R` selects one promoted run as
the current manuscript-facing application set and writes stable
`tables/glofas_application_current_*` aliases, a compact score table, and a
selection manifest with hashes. Future model replacements should update this
current-output registry instead of editing application figure and table paths by
hand.

The shared simulation validation tables follow the same principle. The final
TT500 fit-and-forecast handoff is pinned by
`application/config/shared_validation_tt500_final_fitforecast.yaml` and rebuilt
with `application/scripts/31_build_shared_validation_tt500_final_tables.R`.
That builder reads hash-pinned Q--DESN and exDQLM/DQLM shared-interface CSV
files, checks the source registry, rolling-origin grid, TT500 windows,
package/branch/commit provenance, and Q--DESN scale-repaired forecast paths,
then writes the article-facing `tables/qdesn_validation_tt500_final_*` files.
TT5000 MCMC remains outside manuscript claims until a separate final handoff is
declared and guarded.

For GloFAS synthesis runs that use optional no-refit spread calibration, the
calibration must be declared in the synthesis config and promoted through
`tables/glofas_application_spread_calibration_manifest__*.csv`. The current
registry exposes the selected calibration factor, additive width, center
quantile, and calibration identifier as LaTeX aliases; the manuscript should
describe these as synthesis-time adjustments, not as refitted Q-DESN models.

### Current GloFAS Manuscript Candidate

As of 2026-06-21, the current manuscript-facing GloFAS candidate is:

```text
glofas_cal07_scorebalanced_spread140_add050_synthesis_final
```

This candidate is selected through
`tables/glofas_application_current_selection_manifest.csv`; manuscript text
should continue to use the stable aliases in
`tables/glofas_application_current_outputs.tex`. The tracked run snapshot is
`tables/glofas_application_run_config__glofas_cal07_scorebalanced_spread140_add050_20260621.yaml`.

The reference-case scores on the transformed streamflow scale are:

| Model | Check | Interval | CRPS | Coverage |
|---|---:|---:|---:|---:|
| Q-DESN calibration | 0.3818 | 4.1930 | 0.7915 | 0.583 |
| Raw GloFAS | 0.7639 | 13.0538 | 1.4424 | 0.000 |

The selected spread calibration is
`scorebalanced_spread_x1p400_plus0p500`, centered at quantile 0.50. It is a
post-fit synthesis adjustment only; it does not change the fitted reservoirs,
likelihood, priors, or readout coefficients.

Future GloFAS replacements should be promoted by rerunning
`scripts/08_promote_application_outputs.R` and then
`scripts/09_select_application_outputs.R` with an explicit promotion manifest.
Do not hand-edit the current manuscript aliases.

## Required Workflow

The intended workflow is staged so that each step has a clear input and output
contract.

1. `scripts/00_register_input_bundle.R`
   registers a local frozen input bundle from `config/input_bundle.yaml`,
   computes file hashes, row counts, column counts, and date ranges, and writes
   `manifests/input_manifest.csv`.
2. `scripts/00_check_inputs.R`
   validates registered frozen inputs against `manifests/input_manifest.csv`
   and `manifests/expected_schema.yaml`, including the declared hashes, file
   profiles, and the Q-DESN engine API contract required by the enabled model
   grid.
3. `scripts/00_audit_input_bundle.R`
   writes semantic input-audit tables for row counts, columns, duplicate keys,
   and forecast-horizon consistency.
4. `scripts/01_build_panel.R`
   builds the forecast-origin application panel and writes a panel summary.
5. `scripts/02_make_input_figures.R`
   produces pre-model diagnostic figures from the audited panel and records a
   figure manifest.
6. `scripts/03_fit_models.R`
   fits the reference-only and discrepancy-calibration Q-DESN models over the
   configured quantile grid.
7. `scripts/04_score_models.R`
   scores raw GloFAS, Q-DESN, and baseline forecasts under a shared
   forecast-origin protocol.
8. `scripts/05_make_outputs.R`
   creates storage-light generated-output candidates and provenance records in
   `application/outputs/generated/<run_id>/`.
9. `scripts/06_preflight_launch.R`
   audits a completed pilot or dry-run directory before any final application
   launch.
10. `scripts/07_post_analysis.R`
   reads completed fit artifacts and writes post-fit summaries and diagnostic
   figures under the run archive.
11. `scripts/08_promote_application_outputs.R`
   copies selected storage-light tables, figures, and provenance snapshots
   into tracked article-facing paths.
12. `scripts/09_select_application_outputs.R`
    selects one promoted run as the current manuscript-facing application run
    and regenerates stable aliases consumed by `main.tex`.
13. `scripts/run_all.R`
   executes the checked, audited, panel, diagnostic-figure, fitting, scoring,
   output, optional post-analysis, and optionally preflight stages after the
   input manifest has been registered.

The cutoff file may remain empty while only Phase 1 and Phase 2 are being
exercised. Forecast-origin evaluation and model scoring require populated
cutoffs before manuscript claims can be made.

## Cutoff-Centered Source Figures

### Authoritative Jerez Import

Manuscript-facing GloFAS figures and fits must be generated from the revised
jerez input lineage, not from the local legacy Dec 25 files. The import script
copies the frozen shared inputs, the Dec. 25 long-history histfix stable-input
bundle, run manifest, setup audits, provenance-only climate/GDPC audit
artifacts, deterministic precipitation and soil handoff, GEFS audit notes,
GloFAS harmonization notes,
weighted/blended forecast forensics, and the GEFS/NWM precipitation and
soil-moisture handoff cache into ignored article-side directories:

```bash
application/scripts/import_authoritative_jerez_inputs.sh
```

The script uses non-interactive SSH and fails before copying if `muscat` cannot
authenticate to `jerez`. In that case, copy the same paths into
`application/data_local/upstream_jerez/` from a host that can read the jerez
project tree, then run the audit below.

After the copy succeeds, audit a selected cutoff before any plotting or model
fit:

```bash
Rscript application/scripts/00_audit_authoritative_source_bundle.R \
  --bundle_root application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505 \
  --cutoff_date 2022-12-25 \
  --extra_root application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z,application/data_local/upstream_jerez/histfix_stable_inputs/site=11160500/cutoff_date=2022-12-25/run_id=20260407_long_history_r01 \
  --run_id authoritative_source_audit_20260511
```

The audit checks that the copied lineage exposes the reference gauge,
GloFAS retrospective path, issued GloFAS ensemble, GEFS precipitation,
GEFS soil-moisture forecasts, local soil-moisture input, blended or weighted
forecast input, retrospective source family, and the expected GloFAS
hydrological-model version for the cutoff. For `2022-12-25`, the audit expects
`lisflood` evidence. If this audit fails, do not generate or promote
application figures.

### Forecast Covariate Source Policy

The application covariate builder now requires an explicit future-covariate
contract when precipitation and soil inputs extend beyond the cutoff. The
supported `covariates.future_policy` values are:

- `gefs_only`: use reduced GEFS precipitation and soil forecasts only. This is
  the deployable forecast setting and fails if any realized-future correction,
  including dry-day zero-stay logic, is enabled.
- `gefs_realized_blend`: reproduce the historical blended GEFS plus realized
  future diagnostic setting. This must set `covariates.allow_realized_future:
  yes` because it is not a deployable forecast covariate.
- `oracle_realized`: use realized future precipitation and soil covariates.
  This is an oracle diagnostic for model-capacity checks and does not require
  GEFS handoff files.
- `external_table`: use a user-supplied future-covariate table with either
  `date,ppt,soil` columns or `date,variable,value` rows.

Legacy configs with
`source_policy: realized_history_and_blended_gefs_forecast` are mapped to
`gefs_realized_blend`, and the legacy `noisy_blend` and `observed_blend`
fields remain accepted as aliases for `forecast_noise` and
`realized_future_correction`. Fit and design summaries record the future policy,
source provider, realized-future flag, and source-manifest hash so promoted
outputs can be audited without reopening serialized fit objects.

After the audit passes, materialize the cutoff into the article input schema
and regenerate the diagnostic figures. For Dec. 25, 2022, the materializer uses
the frozen shared-input root for USGS and realized precipitation and soil
covariates and the histfix
stable-input root for GloFAS retrospective and member forecasts. The histfix
retrospective is documented as `log1p_cms`, so it is converted back to raw
streamflow during materialization before the application panel applies its
configured transform. The preferred materialization command reads the tracked
source registry:

```bash
Rscript application/scripts/00_materialize_from_source_registry.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --cutoff_id dec25_2022
```

For source-diagnostic figures, continue with:

```bash

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

The long-history retrospective gate is documented in
`docs/implementation_notes/glofas_long_history_retrospective_20260512.md`. The
reproducible audit command is:

```bash
Rscript application/scripts/00_audit_glofas_retrospective_history.R \
  --output_dir application/runs/long_history_dec25_input_gate_20260512/tables
```

The expected Dec. 25 materialized retrospective support is 1987-05-29 through
2022-12-25. The issued GloFAS ensemble support is 2022-12-26 through
2023-01-22.

To repeat the audited source-diagnostic workflow over every copied jerez cutoff,
run:

```bash
Rscript application/scripts/02_run_authoritative_source_diagnostics.R \
  --run_id authoritative_source_cutoffs_20260512
```

This command audits each cutoff, materializes a local schema-compatible bundle,
registers and checks the manifest, builds the panel, makes the cutoff-centered
source diagnostics, collects the GEFS/NWM handoff figures when available, and
writes a combined summary table under
`application/runs/authoritative_source_cutoffs_20260512/tables/`.

### Local Legacy Diagnostic

The local Dec 25, 2022 diagnostic workflow reproduces the source-level figure
checks used before model fitting: historical USGS reference values, the GloFAS
retrospective path through the cutoff, the GloFAS ensemble issued at the
cutoff, and held-out USGS values after the cutoff for visual reference. This is
an input-audit workflow, not a model-performance run.
The implementation note
`docs/implementation_notes/glofas_cutoff_source_figures_20260511.md` records
the file contract, commands, and validation checks.

The tracked configuration is generic enough to repeat the workflow for another
cutoff once the corresponding local files are available. For the Dec 25 legacy
inputs, run:

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

The main cutoff figure is written to:

```text
application/runs/dec25_source_figures_legacy_20260511/figures/input_diagnostics/cutoff_source_diagnostic_dec25_2022.pdf
```

The run directory also records the registered input manifest, panel summary,
figure manifest, cutoff-source summary table, git state, and session
information. The materialized bundle, cache, manifests, and generated run
outputs are intentionally ignored by git. The Dec 25 files are local legacy
diagnostics and are explicitly unverified. Final manuscript figures should be
regenerated from the authoritative frozen GloFAS input bundle after it is copied
into this application contract. In particular, do not use the local legacy
retrospective series for model fitting, scoring, or manuscript-facing claims
unless its product version has been verified against the revised data-lineage
audit.

## Current Engine Gate

The current application configurations use the shared 1.0.0 local `exdqlm`
validation-logic worktree at
`/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`. The active
latent-path ensemble-likelihood workflow uses that source for Q--DESN feature
construction and readout APIs, while the latent-path AL-VB fitter remains
article-side. For simulation results, the article consumes only the finalized
TT500 shared fit+forecast handoff pinned in
`application/config/shared_validation_tt500_final_fitforecast.yaml`; unfinished
or provisional shared-validation artifacts remain non-consumable.

The application configs set `qdesn_engine_load_mode: local_source`, so the
article workflow loads the checked-out branch named by
`qdesn_engine_repo_hint`; it does not install `exdqlm` from CRAN. The local
source loader requires `Rcpp`, because the branch's compiled sampler is called
through `RcppExports.R`. The engine contract records the load mode, package
version from `DESCRIPTION`, engine branch, engine commit SHA, source-policy
status, required exports, missing exports, and API status in each run
directory. Launch readiness fails if an old 0.4.0-era or origin-state-only
worktree, the old 0.5.0 fitforecast validation worktree, or a stale
`/home/jaguir26/local/src` path is active.

The legacy pilot prediction adapter uses an origin-state discrepancy
correction: it subtracts the fitted discrepancy readout at the forecast origin
from the raw GloFAS ensemble quantile. This remains useful as a historical API
gate, but it is not the current target application model. The target
latent-path workflow uses posterior-draw predictions and the recursive
future-state contract described in the implementation notes. In model notation,
the legacy adapter is a point bridge for the posterior-draw identity
`q_Y_draw(s, T, h, p0) = q_G_draw(s, T, h, p0) - d_G_draw(s, T, h, p0)`.
The final Bayesian application should construct matched posterior draws for
`q_G`, `d_G`, and `q_Y`, record
`q_g_source = ensemble_bayesian_bootstrap_quantile`, and then compute summaries
only after draw-level subtraction. In this contract, the issued GloFAS ensemble
supplies `q_G` draws and the fitted Q-DESN supplies posterior discrepancy
draws. This pilot is not the final posterior-draw prediction contract.
Forecasts beyond the issued GloFAS horizon would require recursive prediction
of both the GloFAS quantile path and the discrepancy path.

The first executable posterior-draw gate is
`config/glofas_discrepancy_posterior_draw_dryrun.yaml`. It fits the
retrospective source-indexed likelihood through the cutoff and evaluates
prediction rows with `discrepancy_feature_strategy = horizon_indexed_origin_state`.
Issued GloFAS ensembles enter the prediction contract, not the default
likelihood rows. The dry run is intentionally small; it verifies the
posterior-draw contract and reproducibility wiring before any tuned
manuscript-scale run.

The next tracked configuration is
`config/glofas_discrepancy_mcmc_diagnostic_dec25.yaml`. It keeps the same
posterior-draw contract but fits levels 0.10, 0.50, and 0.90 with a moderate
two-layer DESN and longer AL-MCMC chains. This run is the first model-behavior
diagnostic pilot: it should be inspected through the fit-diagnostic tables,
draw-check table, score summaries, and generated model figures before expanding
to all cutoffs or the full quantile grid.

The long-history large-specification configuration is
`config/glofas_discrepancy_mcmc_large_dec25.yaml`. It uses
`D = 2`, `n = (500, 500)`, `n_tilde = 500`, `m = 180`, `washout = 500`,
`burn_in = 1000`, `n_iter = 2000`, and `rhs_tau0 = 1e-4`. Before running the
sampler, use the input/design gate:

```bash
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --cutoff_id dec25_2022 \
  --run_id long_history_dec25_input_design_gate_20260512 \
  --design_fit_id qdesn_discrepancy_rhs_al_mcmc_large_p50
```

This gate materializes the registry row, audits the source lineage, registers
the bundle, checks the long-history retrospective, rebuilds the panel, and
checks the reservoir feature matrix, augmented discrepancy design, and
posterior-draw prediction design. Omit `--design_fit_id` to check every enabled
Q-DESN row.

The companion VB preparation profile is
`config/glofas_discrepancy_vb_large_dec25.yaml`, with model rows in
`config/model_grid_vb_large_dec25.csv`. It uses the same source registry,
large DESN specification, posterior-draw prediction contract, and
regularized-horseshoe prior as the MCMC profile. It is intended to pass the
same input/design gate before sampler development is complete. The fit stage
must remain blocked until the configured engine passes the 1.0.0 source-policy
and Q--DESN feature API checks and the article-side latent-path fitter supports
the requested `AL + VB` rows. For AL rows, the `vb_ld` label denotes the
variational route through the article interface; the Laplace-Delta
scale-asymmetry block is only active for exAL rows.

The prediction contract is now encoded in the configuration and recorded in
every prediction row. The current pilot writes `q_g_hat`, `d_g_hat`, `qhat`,
`prediction_contract`, `contract_version`, `forecast_scope`, `q_g_source`,
`discrepancy_feature_strategy`, `prediction_unit`, `posterior_draw_contract`,
and `beyond_issued_horizon`. The scoring and preflight stages verify the
identity `qhat = q_g_hat - d_g_hat` for pilot discrepancy rows. A final launch
is not allowed to use a contract whose name begins with `pilot_`, and
discrepancy predictions must use `prediction_unit: posterior_draw` with a
validated `tables/posterior_draw_predictions.csv` file.

The launch-readiness dry run is exercised through
`config/glofas_discrepancy_prelaunch_dryrun.yaml` and
`config/model_grid_prelaunch_dryrun.csv`. It runs the same small AL-MCMC
discrepancy bridge, then executes `scripts/06_preflight_launch.R` to verify the
input manifest, run manifests, input figures, prediction table, score table,
engine contract, git state, and dry-run boundary. Passing this dry run means
the workflow is ready for a final launch decision; it does not constitute the
final application run.

No manuscript performance claim should be made from this application unless
the run directory contains the input manifest, configuration files, session
information, git state, fit status table, scoring table, and provenance table
for every promoted output.

## Naming Rules

Use explicit, stable names:

- `glofas_discrepancy_application.yaml` for the main application config.
- `cutoffs.csv` for forecast origins or cutoff dates.
- `quantile_grid.csv` for target quantile levels.
- `model_grid.csv` for candidate model definitions.
- `input_bundle.yaml` for the local frozen-input bundle contract.
- `figure_specs.yaml` for pre-model input diagnostic figures.
- `fit_id` for a single model--quantile fit and `model_id` for the grouped
  multi-quantile forecast to be synthesized and scored.
- `application_panel.rds` for the derived modeling panel.
- `score_summary.csv` for final evaluation summaries.
- `figure_manifest.csv` for generated figure provenance.
- `manuscript_output_provenance.csv` for table and figure lineage.

Run identifiers should use:

```text
glofas_qdesn_YYYYMMDD_HHMMSS__git-<shortsha>__cfg-<hash>
```

This keeps generated artifacts sortable, traceable, and easy to connect back
to the manuscript.
