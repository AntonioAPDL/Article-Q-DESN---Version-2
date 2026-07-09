# Application Scripts

This directory will contain executable stages for the GloFAS application.
Scripts should be thin: parse configuration, call functions from
`application/R/`, write run artifacts, and fail with clear messages when an
input contract is violated.

Runtime contract:

```sh
hash -r
which Rscript
Rscript -e 'cat(R.version.string, "\n"); cat("R_HOME=", R.home(), "\n", sep = "")'
```

Expected on Muscat:

```text
Rscript=/home/jaguir26/.local/bin/Rscript
R version 4.6.0 (2026-04-24)
R_HOME=/data/jaguir26/local/opt/R/4.6.0/lib64/R
```

Do not prefix launch commands with legacy R-4.4 `R_LIBS_USER` paths. If a
shell resolves `Rscript` to `/usr/bin/Rscript`, run `hash -r` and verify the
local 4.6.0 runtime before launching any gate or fit stage.

Launch-safety contract:

- `run_all.R --preflight true` is not a dry run. It runs the ordinary workflow
  stages and appends `06_preflight_launch.R` at the end.
- Safe preparation commands are `run_input_design_gate.R`,
  `03_check_model_design.R`, `03_profile_latent_path_al_vb.R`,
  `03_screen_reservoir_design.R`,
  `03_screen_reservoir_candidate_grid.R`, and the test suite. These commands
  must not call `03_fit_models.R`.
- `03_screen_reservoir_candidate_grid.R` accepts scalar `n` for equal-width
  candidates and `n_vector` plus `n_tilde` for vector-width candidates. For
  no-reduction DESN candidates, set `n_tilde[d-1]` equal to the previous layer
  width so the article reservoir generator uses an identity inter-layer state
  map.
- `03_collect_reservoir_screening_shards.R` merges parallel
  `03_screen_reservoir_candidate_grid.R` shard outputs and writes ranked local
  summaries for selecting candidates after a background screening campaign.
- `03_prepare_diverse_reservoir_pilot_batch_20260525.R`,
  `03_validate_diverse_reservoir_pilot_batch_20260525.R`, and
  `03_summarize_diverse_reservoir_pilot_readiness_20260525.R` prepare and
  validate the current eight-candidate diverse reservoir batch without
  entering `03_fit_models.R`. They are configuration and design gates only.
- Any configuration with `execution.final_launch.enabled: true` must pass
  `--confirm_final_launch true` before `run_all.R` or `03_fit_models.R` can
  enter the fit stage.
- Multi-quantile application synthesis is prepared in two steps. First,
  `10_prepare_glofas_multiquantile_launch.R` writes ignored per-quantile
  runtime configs and manifests under `local_trackers/runtime_configs/`;
  it does not launch fits. Second,
  `10_synthesize_glofas_quantile_runs.R` consumes completed per-quantile
  runs, combines their prediction tables by shared `model_id`, applies
  monotone quantile synthesis, scores check loss, interval score, and
  quantile-grid CRPS, and writes manuscript-facing figures and provenance.
  This keeps expensive fitting separate from article-facing synthesis.
- `11_evaluate_glofas_hybrid_synthesis.R` is a no-refit diagnostic layer for
  completed multi-quantile synthesis runs. It builds predeclared raw/Q-DESN
  hybrid candidates, reapplies monotone synthesis, reports both independent
  and monotone check loss, writes crossing and isotonic-adjustment diagnostics,
  and creates comparison figures. Its outputs are decision evidence only until
  an explicit promotion step is approved.
- `12_make_glofas_multiquantile_diagnostic_figures.R` is a no-refit plotting
  pass for completed multi-quantile application runs. It reads the saved
  per-quantile VB fit objects and completed synthesis tables, then writes ELBO
  traces, parameter-change traces, convergence/runtime summaries, and
  side-by-side raw/all-Q-DESN/hybrid quantile-path diagnostics.
- `13_make_glofas_pre_cutoff_quantile_history.R` is a no-refit retrospective
  diagnostic. It reads the saved per-quantile VB fit and design objects,
  computes fitted Q-DESN quantile paths for the last pre-cutoff history window,
  and plots those dynamics against the USGS reference path.
- `14_debug_glofas_forecast_quantile_collapse.R` is a no-refit forecast
  debugging bundle for completed multi-quantile application runs. It compares
  fitted-history and forecast linearization designs, checks the posterior-draw
  identity `q_y_draw = q_g_draw - d_g_draw`, summarizes component paths,
  diagnoses cross-quantile crossings and spread collapse, and writes a compact
  readiness report plus diagnostic figures. It is designed for debugging
  forecast construction, not for selecting a final promoted result by itself.
- `15_audit_glofas_forecast_contract.R` is the deeper no-refit forecast
  contract audit. It maps the latent-path forecast contract, verifies
  date/horizon and two-block beta/alpha alignment, compares saved
  first-order future designs with exact no-Jacobian feature rebuilds,
  decomposes component-level crossings, audits reservoir-state shift, and
  writes candidate-fix readiness evidence. Exact draw-subset rebuilds are
  intentionally configurable because they are substantially more expensive
  than ordinary plotting diagnostics.
- `16_audit_glofas_synthesis_and_readout_blocks.R` is a no-refit synthesis
  and readout-block audit. It decomposes forecast-window feature shift by
  beta and alpha readout block, scores diagnostic block-zeroing ablations, and
  stress-tests draw-index-aligned post-hoc monotone synthesis. It does not
  alter independently fitted quantile models.
- `17_prepare_glofas_readout_refinement_gate.R` prepares ignored local
  p05/p50/p95 readout-refinement gate configs and a tmux launcher. It does
  not launch fits; review the generated candidate and launch manifests before
  any explicit launch.
- `18_make_glofas_readout_gate_diagnostic_figures.R` is a no-refit plotting
  pass for completed readout-refinement gates. It writes ELBO traces,
  parameter-change traces, convergence summaries, and independent/monotone
  synthesized quantile-path figures around the cutoff for every candidate.
- `19_prepare_glofas_reservoir_only_full7_launch.R` prepares ignored local
  seven-quantile runtime configs for the selected `reservoir_only_m360`
  GloFAS specification. It preserves the gate-winning reservoir-only readout
  contract, writes launch and synthesis manifests, and emits tmux/synthesis
  shell scripts for explicit execution.
- `20_make_glofas_reservoir_only_full7_diagnostic_figures.R` is a no-refit
  plotting and audit pass for the selected reservoir-only full-seven GloFAS
  run. It consumes the completed per-quantile fits plus synthesis tables and
  writes VB traces, score comparisons, interval diagnostics, synthesized
  quantile paths, component-path figures, and crossing-adjustment diagnostics.
- The cancelled run id
  `latent_path_main_al_vb_n1000_m360_20260515_024133` is blocked and should
  never be reused.
- `run_all.R` refuses to reuse a nonempty run directory unless
  `--allow_existing_run_dir true` is supplied for an intentional resume.

The current package-backed fitting gate is the AL-MCMC pilot:

```sh
Rscript application/scripts/03_fit_models.R \
  --config application/config/glofas_discrepancy_al_mcmc_pilot.yaml
```

This pilot writes the discrepancy design, fitted object, fit manifest, and fit
status for one median GloFAS discrepancy model. It should pass before the
article workflow treats larger exAL or VB-LD rows as launchable; unsupported
rows still fail closed at the fit stage.
Prediction rows are written under an explicit forecast contract. For the
current pilot, `prediction_quantiles.csv` records
`pilot_origin_state_glofas_quantile_minus_discrepancy`, together with
`q_g_hat`, `d_g_hat`, `qhat`, the contract version, and the discrepancy feature
strategy. The scoring stage verifies the identity `qhat = q_g_hat - d_g_hat`
for discrepancy rows before computing check loss. This is a point bridge. The
final Bayesian prediction contract must write matched posterior draws satisfying
`q_y_draw = q_g_draw - d_g_draw` in
`tables/posterior_draw_predictions.csv`, with any point summaries computed
afterward.

The posterior-draw dry run is available through:

```sh
RUN_ID=posterior_draw_dryrun_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_posterior_draw_dryrun.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

This is a real small fit, not a sampler-free dry run.

This run writes matched posterior draws for `q_g_draw`, `d_g_draw`, and
`q_y_draw` using `q_g_source = ensemble_bayesian_bootstrap_quantile` and
`discrepancy_feature_strategy = horizon_indexed_origin_state`. The usual
`prediction_quantiles.csv` table is then a posterior-mean summary derived from
the draw table so that the scoring scripts can run without changing their
interface.

The companion AL-VB posterior-draw dry run uses the same contract and a small
DESN:

```sh
RUN_ID=vb_posterior_draw_dryrun_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_vb_posterior_draw_dryrun.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

This is a real small fit, not a sampler-free dry run.

This run is the article-side gate for the approximate posterior draws returned
by the AL-VB discrepancy fitter. It should pass before the larger Dec. 25 VB
profile is used for real-data analysis.

The first diagnostic scientific pilot uses:

```sh
RUN_ID=mcmc_diagnostic_dec25_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_mcmc_diagnostic_dec25.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

This is a real diagnostic fit, not a sampler-free dry run.

This pilot fits raw GloFAS and Q-DESN discrepancy rows at levels 0.10, 0.50,
and 0.90. It writes fit diagnostics, posterior-draw checks, score tables, and
model diagnostic figures. It is intended for inspection before a full
application campaign, not as the final manuscript run.

The Dec. 25 long-history large-specification gate uses:

```sh
RUN_ID=long_history_dec25_input_gate_YYYYMMDD
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_discrepancy_mcmc_large_dec25.yaml \
  --cutoff_id dec25_2022 \
  --run_id "$RUN_ID" \
  --design_fit_id qdesn_discrepancy_rhs_al_mcmc_large_p50
```

This sequence verifies the long-history GloFAS retrospective, registers the
materialized bundle, rebuilds the panel, and checks the large reservoir design
without launching MCMC. Omit `--design_fit_id` to build designs for every
enabled Q-DESN row.
For the current large Dec. 25 profiles, the panel stage also materializes the
model covariate timeline. It uses only `ppt` and `soil`, tags retrospective
realized and forecast-blended rows, and stores the timeline as an attribute on
`application_panel.rds`. The origin-state bridge profiles keep direct
covariate-lag and direct streamflow-lag blocks disabled in the readout. The
latent-path profiles use the same timeline inside the recursive reservoir
input, with future response lags supplied by the latent USGS path and future
`ppt` and `soil` lags supplied by the deterministic blended-forecast covariate
timeline.

The companion VB profile uses the same gate:

```sh
RUN_ID=vb_large_dec25_input_gate_YYYYMMDD
Rscript application/scripts/run_input_design_gate.R \
  --config application/config/glofas_discrepancy_vb_large_dec25.yaml \
  --cutoff_id dec25_2022 \
  --run_id "$RUN_ID" \
  --design_fit_id qdesn_discrepancy_rhs_al_vb_large_p50
```

This gate checks the same source lineage and design matrix as the MCMC profile
and records the engine inference-support report. The fit stage is stricter:
`03_fit_models.R` must see the pinned shared 1.0.0 engine source and the
article-side latent-path `AL + VB` support before launching required VB rows.
Use a small article-side VB dry run before any large real-data launch.

For the latent-path ensemble-likelihood profile, run the structure profiler
before any manuscript-scale VB launch:

```sh
RUN_ID=latent_path_covaware_full_vb_safe_profile_YYYYMMDD
Rscript application/scripts/03_profile_latent_path_al_vb.R \
  --config application/config/glofas_latent_path_al_vb_dec25_full.yaml \
  --run_id "$RUN_ID" \
  --future_laplace true \
  --save_design false
```

The profiler writes dense-covariance memory estimates and skips heavy dense
future-row moment updates by default when the estimated storage exceeds the
configured limit. The current Dec. 25 covariate-aware profile is held until the
future-row moment update is streamed or otherwise structured.

The right-sized latent-path micro-pilot is the end-to-end gate between the
two-horizon smoke and the large median-only pilot:

```sh
RUN_ID=latent_path_micro_pilot_1p0p0_YYYYMMDD_HHMMSS
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

This run uses real Dec. 25 inputs, seven forecast horizons, posterior-draw
prediction output, and the shared 1.0.0 engine source. It should pass cleanly
before the large latent-path pilot or main launch is attempted.

After the large VB design gate and synthetic VB checks pass, the median-only
large VB pilot can be run with:

```sh
RUN_ID=vb_large_dec25_p50_pilot_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

This pilot fits only `p0 = 0.50` with the large DESN and RHS prior. It is the
first serious VB application fit, not a full three-quantile launch.

The main Dec. 25 latent-path AL-VB application launch is intentionally guarded.
Do not use this command for testing:

```sh
RUN_ID=latent_path_main_al_vb_n1000_m360_YYYYMMDD_HHMMSS
Rscript application/scripts/run_all.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id "$RUN_ID" \
  --preflight true \
  --confirm_final_launch true
```

The command above starts the real fit. Run the safe input/design gate, design
checker, profiler, and test suite first.

Completed posterior-draw runs can be post-processed without refitting:

```sh
Rscript application/scripts/07_post_analysis.R \
  --config application/config/glofas_discrepancy_vb_large_dec25_p50_pilot.yaml \
  --run_id vb_large_dec25_p50_pilot_20260512_142839
```

The post-analysis stage writes posterior summaries for the fitted USGS
quantile path, the GloFAS discrepancy path, source-specific scale parameters,
method-aware diagnostics, coefficient forest plots, and forecast-window
metrics. It uses the posterior-draw identity
`q_y_draw = q_g_draw - d_g_draw`; retrospective discrepancy diagnostics use
`GloFAS - USGS` to match that sign convention. When
`post_analysis.run_after_outputs: true` is set, `run_all.R` executes this stage
after `05_make_outputs.R`.

Workflow stages:

- `00_register_input_bundle.R`
- `00_materialize_from_source_registry.R`
- `00_audit_glofas_retrospective_history.R`
- `00_audit_generated_artifacts.R`
- `00_check_inputs.R`
- `00_audit_input_bundle.R`
- `01_build_panel.R`
- `02_make_input_figures.R`
- `03_check_model_design.R`
- `03_fit_models.R`
- `04_score_models.R`
- `05_make_outputs.R`
- `06_preflight_launch.R`
- `07_post_analysis.R`
- `08_promote_application_outputs.R`
- `10_prepare_glofas_multiquantile_launch.R`
- `10_synthesize_glofas_quantile_runs.R`
- `11_evaluate_glofas_hybrid_synthesis.R`
- `12_make_glofas_multiquantile_diagnostic_figures.R`
- `13_make_glofas_pre_cutoff_quantile_history.R`
- `14_debug_glofas_forecast_quantile_collapse.R`
- `15_audit_glofas_forecast_contract.R`
- `run_input_design_gate.R`
- `run_all.R`

Each script should write its stage status into the current run directory.
The registration stage is usually run when a new local input bundle is placed
under `application/data_local/`; `run_all.R` assumes that registration has
already produced `application/manifests/input_manifest.csv`.

## Artifact Lifecycle

The application has a three-layer artifact contract:

```text
application/runs/<run_id>              complete local run archive
application/outputs/generated/<run_id> generated-output staging
tables/ and figures/                   tracked article-facing outputs
```

Scripts through `04_score_models.R` write run-private artifacts under
`application/runs/<run_id>/`. `05_make_outputs.R` writes only storage-light
generated-output candidates under `application/outputs/generated/<run_id>/`.
Most post-fit diagnostic figures are not in that staging directory; they are
written by `07_post_analysis.R` under
`application/runs/<run_id>/figures/post_fit_analysis/`.

Only `08_promote_application_outputs.R` should copy application outputs into
tracked article paths. For final manuscript promotion, the script refuses a
final-launch config that is ignored by git unless
`--allow_ignored_config true` is supplied. The preferred route is to copy the
selected final config into `application/config/` before promotion.

Generated-artifact cleanup is report-only unless a deletion step is explicitly
approved:

```sh
Rscript application/scripts/00_audit_generated_artifacts.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --output application/runs/local_audits/generated_artifact_inventory_YYYYMMDD.csv
```

This inventory reports generated `.rds`, `.rda`, `.RData`, and large local
artifacts under ignored application output roots. It does not remove files.
For cleanup planning across runs, use the run-level inventory:

```sh
Rscript application/scripts/00_audit_generated_artifacts.R \
  --config application/config/glofas_latent_path_al_vb_dec25_d1n300_tau3em3_main1000.yaml \
  --inventory_level run \
  --output application/runs/local_audits/generated_run_artifact_inventory_YYYYMMDD.csv
```

The run-level inventory reports run size, heavy-object size, readiness status,
generated-output staging status, and whether a run has promoted outputs.

The prelaunch dry run should be executed before the final application launch:

```sh
RUN_ID=prelaunch_dryrun_YYYYMMDD
Rscript application/scripts/run_all.R \
  --config application/config/glofas_discrepancy_prelaunch_dryrun.yaml \
  --run_id "$RUN_ID" \
  --preflight true
```

The resulting `launch_readiness_report.csv` is a gate, not a manuscript result.
This prelaunch command still fits the configured small dry-run rows; it is not
a sampler-free check.

After a completed application run has passed required launch-readiness checks,
promote only storage-light article-facing outputs into the repository-level
`tables/` and `figures/` directories:

```sh
Rscript application/scripts/08_promote_application_outputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_main.yaml \
  --run_id latent_path_main_al_vb_n1000_m360_20260515_221729 \
  --output_slug latent_path_main_al_vb_n1000_m360_20260515_221729
```

The promotion script refuses runs with required readiness failures by default,
copies generated manuscript tables and PDFs, copies post-fit diagnostic tables
and figures, promotes storage-light provenance snapshots, and writes
`tables/glofas_application_promotion_manifest__*.csv` with source paths,
promoted paths, hashes, run id, config path, Article git SHA, and Q-DESN engine
SHA provenance. Heavy posterior draw tables stay in
`application/runs/<run_id>/tables/`.

After promotion, select exactly one promoted run as the current manuscript-facing
application output set:

```sh
Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__latent_path_d1n300_m100a092r097_tau3em3_main1000_20260523_160355.csv
```

This writes `tables/glofas_application_current_outputs.tex`,
`tables/glofas_application_current_score_summary.tex`,
`tables/glofas_application_current_score_summary.csv`, and
`tables/glofas_application_current_selection_manifest.csv`. The manuscript
uses these current-output aliases instead of hard-coding run-specific promoted
file names. To replace the application run later, promote the new run and
regenerate the current-output registry from its promotion manifest.
