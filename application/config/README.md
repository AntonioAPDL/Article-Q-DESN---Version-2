# Application Configuration

This directory stores tracked configuration files for the GloFAS application.
Configuration should be declarative: scripts read these files and should not
hard-code forecast origins, quantile levels, model grids, or output paths.

Final manuscript-facing promotions should use tracked configs from this
directory. Local runtime variants under `local_trackers/runtime_configs/` are
useful for sweeps and overnight launches, but they are ignored operational
state. If one of those variants becomes the article-facing candidate, copy it
here under a descriptive name before running
`application/scripts/08_promote_application_outputs.R`.

Planned files:

- `glofas_discrepancy_application.yaml`: main workflow configuration.
  It names the planned exAL and VB-LD rows and permits input and design gates
  before every requested inference route is available; model fitting remains
  fail-closed for unsupported required rows.
- `glofas_discrepancy_prelaunch_dryrun.yaml`: small launch-readiness workflow
  that must pass before the final application configuration is run.
- `input_bundle.yaml`: local frozen-input registration contract. It names the
  expected files but does not store the untracked data themselves.
- `input_bundle_authoritative_dec25.yaml`: Dec. 25 source registration
  contract. It registers `ppt_soil_covariates` as the model-facing
  precipitation and soil table when present; the legacy `climate_covariates`
  file remains diagnostic/provenance-only.
- `authoritative_cutoff_sources.csv`: source registry for cutoff-specific
  upstream roots, GloFAS histfix roots, materialized bundle roots, expected
  GloFAS source IDs, retrospective support, and overlap checks.
- `cutoffs.csv`: forecast origins, target windows, and train/evaluation flags.
- `quantile_grid.csv`: fitted quantile levels.
- `model_grid.csv`: model--quantile fit rows. The `fit_id` column is unique
  per row, while `model_id` groups the quantile levels that form one forecast
  model for synthesis and scoring.
- `model_grid_prelaunch_dryrun.csv`: raw GloFAS and one AL-MCMC discrepancy
  median fit for the prelaunch dry run.
- `glofas_discrepancy_posterior_draw_dryrun.yaml`: small posterior-draw
  contract gate using horizon-indexed origin-state discrepancy features.
- `model_grid_posterior_draw_dryrun.csv`: raw GloFAS and one AL-MCMC
  discrepancy median fit for the posterior-draw dry run.
- `glofas_discrepancy_vb_posterior_draw_dryrun.yaml`: small AL-VB
  posterior-draw contract gate using the same horizon-indexed origin-state
  discrepancy features.
- `model_grid_vb_posterior_draw_dryrun.csv`: raw GloFAS and one AL-VB
  discrepancy median fit for the VB posterior-draw dry run.
- `glofas_discrepancy_mcmc_diagnostic_dec25.yaml`: one-cutoff diagnostic
  scientific pilot with three quantile levels and a moderate DESN.
- `model_grid_mcmc_diagnostic_dec25.csv`: raw GloFAS and Q-DESN discrepancy
  rows for the Dec. 25 diagnostic pilot.
- `glofas_discrepancy_mcmc_large_dec25.yaml`: long-history Dec. 25
  large-specification configuration using `D = 2`, `n = (500, 500)`,
  `n_tilde = 500`, `m = 180`, `washout = 500`, `burn_in = 1000`,
  `n_iter = 2000`, and `rhs_tau0 = 1e-4`. It is ready for a main launch only
  after the long-history input and design gates pass.
- `model_grid_mcmc_large_dec25.csv`: raw GloFAS and Q-DESN discrepancy rows
  for the long-history large-specification Dec. 25 configuration.
- `glofas_discrepancy_vb_large_dec25.yaml`: companion VB profile
  for the same Dec. 25 source registry, posterior-draw contract, DESN
  specification, and RHS prior. It is allowed to pass input and design gates.
  The fit stage must still confirm that the configured engine passes the
  1.0.0 source-policy and Q--DESN feature API checks and that the article-side
  latent-path fitter supports `AL + VB` before posterior computation starts.
- `model_grid_vb_large_dec25.csv`: raw GloFAS and Q-DESN discrepancy rows for
  the VB preparation profile. The requested method is `vb_ld`; for AL rows the
  Laplace-Delta scale-asymmetry block is inactive.
- `glofas_discrepancy_vb_large_dec25_p50_pilot.yaml`: median-only large-spec
  VB pilot using the same Dec. 25 source registry, DESN specification, RHS
  prior, and posterior-draw contract as the full large VB profile.
- `model_grid_vb_large_dec25_p50_pilot.csv`: raw GloFAS median and one
  required Q-DESN discrepancy median row for the large VB pilot.
- `glofas_latent_path_al_vb_dec25_full.yaml`: latent-path full-specification
  readiness profile for the current application model. It mirrors the main
  reservoir, covariate, likelihood, and prior specification but keeps
  `execution.final_launch.enabled: false`.
- `glofas_latent_path_al_vb_dec25_pilot.yaml`: short full-specification
  latent-path pilot. It uses the main design but limits VB to five iterations
  and 200 posterior draws.
- `glofas_latent_path_al_vb_dec25_micro_pilot.yaml`: right-sized intermediate
  latent-path launch gate. It uses real Dec. 25 inputs, seven forecast
  horizons, a modest reservoir, and posterior-draw prediction output so the
  full workflow can be tested repeatedly before the large pilot.
- `glofas_latent_path_al_vb_dec25_main.yaml`: main Dec. 25 latent-path AL-VB
  launch configuration. It uses `D = 2`, `n = (1000, 1000)`,
  `n_tilde = 500`, `m = 360`, `washout = 500`, an AL working likelihood, the
  RHS prior with `rhs_tau0 = 1e-6`, `rhs_freeze_tau_warmup_iters = 50`, and
  `max_iter = 200`. Article-side VB launch
  configurations should stay at or below the 500-iteration hard cap unless the
  launch policy is deliberately revised. Because this configuration has
  `execution.final_launch.enabled: true`, any command that reaches
  `03_fit_models.R` must pass `--confirm_final_launch true`.
- `model_grid_latent_path_al_vb_dec25_main.csv`: raw GloFAS median and one
  required latent-path Q-DESN median row for the main AL-VB launch.
- `glofas_latent_path_al_vb_dec25_d1n300_tau3em3_main1000.yaml`: tracked
  storage-light provenance config for the completed D=1, n=300, m=100,
  `alpha=0.92`, `rho=0.97`, tau0=0.003 AL-VB main1000 sensitivity run. It
  records the selected tau0 candidate before article-facing promotion and uses
  the same focused D1 model grid and Dec. 25 authoritative input bundle.
- `glofas_application_candidate_batch_20260524.csv`: focused post-promotion
  candidate batch for selecting among nearby D=1, n=300 reservoir settings
  while holding `tau0=0.003`, `rhs_slab_s2=1.0`, AL-VB, and the Dec. 25
  forecast-origin contract fixed.
- `reservoir_candidate_grid_latent_path_d1n300_candidate_batch_20260524.csv`:
  matching reservoir-validity grid for the focused candidate batch. Run it
  with `03_screen_reservoir_candidate_grid.R --diagnostic_target both` before
  launching a candidate so the reference/shared-quantile and discrepancy DESN
  feature maps are both screened.
- `glofas_latent_path_al_vb_dec25_d1n300_m*_tau3em3_main1000.yaml` and
  `model_grid_latent_path_al_vb_dec25_d1n300_m*_tau3em3_main1000.csv`:
  tracked configs/model grids for the 2026-05-24 focused reservoir-candidate
  launch batch. These are launch candidates, not promoted manuscript outputs.
- `glofas_capacity1000_candidate_batch_20260524.csv`: capacity-controlled
  depth/width candidate table with total reservoir units fixed at 1000 while
  holding the selected run's prior, inference, memory, sparsity, and input
  scaling settings fixed.
- `reservoir_candidate_grid_latent_path_capacity1000_20260524.csv`: matching
  reservoir-validity grid for the capacity-1000 batch. Run it with
  `03_screen_reservoir_candidate_grid.R --diagnostic_target both` before any
  launch so both application DESN feature maps are screened.
- `glofas_latent_path_al_vb_dec25_cap1000_*_tau3em3_main1000.yaml` and
  `model_grid_latent_path_al_vb_dec25_cap1000_*_tau3em3_main1000.csv`:
  tracked configs/model grids for the capacity-controlled candidate batch.
  For `D > 1`, each `n_tilde[d-1]` equals the previous layer width, which
  makes the inter-layer state map an identity/no-reduction pass-through in the
  article reservoir generator.
- `glofas_overnight_ladder_screen_20260525.csv`: compact family summary for
  the broad screening-only reservoir ladder prepared after the capacity-1000
  repair screens. It includes the D1 n300 positive-control neighborhood,
  shallow capacity ladders, D2/D3 no-reduction ladders, and a focused deep
  stress block.
- `reservoir_candidate_grid_latent_path_overnight_ladder_20260525.csv`:
  matching broad reservoir-screening grid. It is intended for
  `03_screen_reservoir_candidate_grid.R --diagnostic_target both` and must not
  be interpreted as permission to launch a fit. Candidates from this grid are
  reviewed through `03_rank_reservoir_screening_for_pilots.R` before any
  micro-pilot is considered.
- `glofas_shortlist_multiseed_screen_20260525.csv`: compact summary of the
  multiseed shortlist selected from the completed broad overnight ladder
  screen. The shortlist keeps the current D1 n300 reference-control candidate,
  D1 n300 refinements, shallow D1 capacity candidates, and D2 no-reduction
  candidates.
- `reservoir_candidate_grid_latent_path_shortlist_multiseed_20260525.csv`:
  matching shortlist grid for `03_screen_reservoir_candidate_grid.R` with
  seeds `20260512:20260518` and `--diagnostic_target both`. Passing this gate
  identifies candidates for possible tiny pilots only; it is not a main-launch
  approval.
- `glofas_diverse_reservoir_pilot_batch_20260525.csv`: launch-preparation
  table for the eight diverse screened candidates selected after the broad
  ladder and multiseed shortlist screens. It intentionally includes D1
  capacity candidates and two D2 no-reduction candidates rather than only D1
  n300 refinements.
- `reservoir_candidate_grid_latent_path_diverse_pilot_batch_20260525.csv`:
  exact reservoir-screening grid for the eight diverse candidates. It is wired
  for `03_screen_reservoir_candidate_grid.R --diagnostic_target both` and
  records the matching launch config/model-grid paths.
- `glofas_diverse_reservoir_pilot_batch_20260525_readiness.csv`: compact
  readiness table combining multiseed evidence, exact launch-seed reservoir
  screening, and sampler-free design validation. Rows marked
  `ready_for_explicit_launch_decision` still require explicit approval before
  any fit is launched.
- `glofas_latent_path_al_vb_dec25_diverse8_*_tau3em3_main1000.yaml` and
  `model_grid_latent_path_al_vb_dec25_diverse8_*_tau3em3_main1000.csv`:
  tracked config/model-grid pairs for the eight diverse screened candidates.
  These configs have `execution.final_launch.enabled: true`, so `run_all.R`
  or `03_fit_models.R` cannot enter fitting without
  `--confirm_final_launch true`.
- `glofas_latent_path_al_vb_dec25_d3n1000_m180_tau1em5_slab1_parallel.yaml`:
  parallel Dec. 25 latent-path AL-VB launch configuration with
  `D = 3`, `n = (1000, 1000, 1000)`, identity-width reducers
  `n_tilde = (1000, 1000)`, `m = 180`, `alpha = (0.10, 0.10, 0.10)`,
  `rho = (0.95, 0.95, 0.95)`, `pi_w = (0.10, 0.10, 0.10)`,
  `pi_in = (1.00, 1.00, 1.00)`, seed `20260512`, AL-VB inference, and the
  RHS prior with `rhs_tau0 = 1e-5` and `rhs_slab_s2 = 1.0`.
- `model_grid_latent_path_al_vb_dec25_d3n1000_m180_tau1em5_slab1_parallel.csv`:
  raw GloFAS median and one required latent-path Q-DESN median row for the
  D=3 n=1000 m=180 tau0=1e-5 parallel launch.
- Posterior-draw MCMC and VB configs may include a `post_analysis` block. When
  `run_after_outputs: true`, `run_all.R` appends `07_post_analysis.R` after the
  manuscript-output stage. The post-analysis stage reads completed fit
  artifacts, does not refit, and writes `post_fit_*` tables plus figures under
  `figures/post_fit_analysis/`. By default, the fitted-discrepancy diagnostics
  include both the full historical path and a focused
  `discrepancy_history_since_2020` path controlled by
  `post_analysis.discrepancy_history_since`. The `run_all.R --preflight`
  option is not a dry run: it appends `06_preflight_launch.R` after the
  ordinary workflow stages. For safe launch preparation, use the input/design
  gate, design checker, profiler, and test suite instead.
- `quantile_grid_mcmc_diagnostic.csv`: the three-level grid used by the
  diagnostic pilot.
- `figure_specs.yaml`: input-diagnostic figures generated after panel
  construction and before model fitting.
- `shared_validation_tt500_provisional_progress.yaml`: tracked pointer to the
  current shared-validation Q-DESN TT500 provisional progress snapshot. This is
  an operational audit and explicitly labeled status-display input only, not a
  scientific result-table source. It records external paths, hashes, expected
  counts, and the refresh command consumed by
  `application/scripts/29_audit_shared_validation_tt500_provisional_progress.R`
  and `application/scripts/30_build_shared_validation_tt500_provisional_table.R`.
- `shared_validation_tt500_final_fitforecast.yaml`: final article-facing TT500
  fit-and-forecast handoff for the shared Q--DESN + exDQLM/DQLM validation
  study. It pins the validation worktree, branch, current sync commit, package
  version, source-registry hash, TT500 train/forecast windows, rolling-origin
  lead/stride policy, exact shared-interface paths, and SHA-256 hashes consumed
  by `application/scripts/31_build_shared_validation_tt500_final_tables.R`.
  This config is TT500-only; TT5000 MCMC must not be inferred from it.

Generated outputs follow the application artifact lifecycle:

```text
application/runs/<run_id>              complete local run archive
application/outputs/generated/<run_id> generated-output staging
tables/ and figures/                   tracked article-facing outputs
tables/glofas_application_current_*     selected manuscript-facing aliases
```

Configs control the first two application paths through `paths.runs` and
`paths.generated_outputs`. The final article paths are controlled by
`paths.promoted_tables` and `paths.promoted_figures`, which should remain the
repository-level `tables/` and `figures/` directories unless a deliberate
manuscript-output migration is made.
After promotion, `application/scripts/09_select_application_outputs.R` selects
one promoted run as the current manuscript-facing application run and writes
the stable `tables/glofas_application_current_*` aliases consumed by
`main.tex`.

Prediction-contract convention:

- Each application config should include a `prediction` block. The current
  issued-horizon contract uses `target:
  reference_quantile_from_glofas_discrepancy`, `q_g_source:
  ensemble_empirical_quantile`, `discrepancy_feature_strategy:
  origin_state_pilot`, `prediction_unit: point_bridge`, and
  `beyond_issued_horizon: disabled`.
- The final Bayesian prediction contract is draw-based:
  `q_y_draw = q_g_draw - d_g_draw`. The default application contract records
  `q_g_source: ensemble_bayesian_bootstrap_quantile`, uses
  `discrepancy_feature_strategy: horizon_indexed_origin_state`, and writes
  `tables/posterior_draw_predictions.csv`.
  Here `q_g_draw` is an issued-GloFAS ensemble quantile draw and `d_g_draw`
  is a posterior discrepancy draw. Point prediction tables are pilot bridges or
  summaries derived after draw-level subtraction, not the primary prediction
  object.
- The current pilot workflow writes `q_g_hat`, `d_g_hat`, and `qhat` to every
  prediction table. For discrepancy rows, launch readiness checks
  `qhat = q_g_hat - d_g_hat`.
- The latent-path main launch requests horizons 1--30, but the executable
  design uses the maximum available issued GloFAS horizon for the cutoff. The
  design summaries record both `requested_horizon_max` and the effective
  `horizon_max`; a shorter effective horizon is expected when the archived
  issued ensemble does not contain all requested lead times.
- Final manuscript launches are not allowed to use a prediction contract whose
  name begins with `pilot_`, and discrepancy rows must use `prediction_unit:
  posterior_draw`.

The posterior-draw dry-run configuration keeps the DESN small and the MCMC
chain short so that the workflow can verify the draw contract quickly. It is a
reproducibility gate, not a tuned application fit.

The MCMC diagnostic configuration is the next step after the dry-run gate. It
uses a moderate two-layer DESN, three quantile levels, and longer AL-MCMC
chains so that posterior draws, discrepancy behavior, scoring, and generated
figures can be inspected before any manuscript-scale campaign.

The large Dec. 25 configuration should be prepared through the source registry
and the input/design gate before MCMC is launched. The source registry is the
only tracked place where the Dec. 25 histfix stable-input root is named. The
large config then controls the reservoir, prior, likelihood, and MCMC settings.
The current large Dec. 25 profiles enable only precipitation and soil-moisture
covariates in the input-preparation layer. They build GEFS q85 blended
forecast covariates for future target dates so the covariate timeline can be
audited and plotted. In the origin-state bridge profiles, the readout contract
does not append direct streamflow-lag, precipitation-lag, soil-moisture-lag, or
horizon columns. In the latent-path profiles, `ppt` and `soil` can enter the
recursive reservoir input through `feature_contract.reservoir_input.covariates`;
the fitted readout still uses an explicit intercept and the fixed reservoir
state. GDPC, PCA, and climate indices are intentionally excluded from the model
design.

The large VB profile mirrors the large MCMC profile. The input/design gate
writes the support report to the run manifest; `03_fit_models.R` refuses
unsupported required VB rows before starting posterior computation. A real
large VB launch should follow synthetic engine checks and a small article-side
VB dry run in the current checkout.

Engine-loading convention:

- Pilot and prelaunch configurations use `qdesn_engine_load_mode:
  local_source`. The article workflow loads the checked-out branch specified by
  `qdesn_engine_repo_hint`, records its git SHA, and does not install `exdqlm`
  from CRAN.
- Current main, exact-chunked smoke, and tiny pilot configurations pin the
  local source to
  `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0` on branch
  `validation/shared-fitforecast-v2-1.0.0` at commit
  `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`. This package checkpoint adds
  the comparison harness on top of the approximate stochastic AL support for
  package static/readout and univariate Q-DESN AL paths while preserving
  unchunked and exact-chunked defaults. The engine gate records the path,
  branch, commit, and package version and fails if a known old 0.4.0-era
  worktree, old 0.5.0 fitforecast worktree, or stale `/home/jaguir26/local`
  path is active.
- `glofas_latent_path_al_vb_dec25_exact_chunked_smoke.yaml` is the controlled
  exact-chunking activation profile. It mirrors the selected D=1, n=300 smoke
  setup and enables `inference.vb_ld.chunking` with `mode: exact` and
  `chunk_size: 512`; manuscript-scale configs remain unchunked unless the
  paired smoke and launch gates support promotion.
- `glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml` and
  `glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml` are paired
  manuscript-scale pilot configs for separate-process runtime and memory
  measurement. The unchunked pilot completed, but the exact-chunked pilot did
  not write a fitted state in the 2026-05-27 run recorded in
  `docs/implementation_notes/qdesn_exact_chunked_vb_fullspec_pilot_20260527.md`,
  so the main Dec. 25 config remains unchunked.
- `glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml` and
  `glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml` are cheap
  real-data twins for repeated exact-chunking checks. They use the
  authoritative Dec. 25 GloFAS/USGS input bundle, but cap the historical panel,
  horizons, ensemble members, lag windows, posterior draws, and reservoir to a
  D=1, n=5 design. These twins are pinned to package commit
  `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`, which adds the package
  comparison harness on top of package-level stochastic AL VB while preserving
  exact chunking. The 2026-05-27 and 2026-05-28 runs are
  recorded in
  `docs/implementation_notes/qdesn_exact_chunked_vb_tiny_d1n5_pilot_20260527.md`.
- `QDESN_ENGINE_REPO_HINT` may override `qdesn_engine_repo_hint` for local
  development. The same source-policy checks still apply, so an override must
  point to the pinned shared 1.0.0 source unless the config is deliberately
  revised.
- The local-source engine path requires the R package `Rcpp`, because the
  branch calls its compiled sampler through `RcppExports.R`.
- Run these configurations under the local R 4.6.0 runtime:
  `/home/jaguir26/.local/bin/Rscript`, with
  `R_HOME=/data/jaguir26/local/opt/R/4.6.0/lib64/R`. Do not set legacy
  R-4.4 user-library paths or rely on `/usr/bin/R`, which may resolve to the
  older system R.

Recommended defaults after the discrepancy VB fitter is implemented and
validated:

- Forecast system: GloFAS only.
- Model family: reference-only Q-DESN and GloFAS discrepancy Q-DESN.
- Inference: VB-LD for the full grid, with MCMC retained for selected
  diagnostic fits.
- Coefficient prior: regularized horseshoe as the default application prior;
  ridge as the dense baseline.
- Quantile grid: `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.
- Scores: check loss, interval coverage, interval score, CRPS from the
  synthesized quantile grid, runtime, and fit status.
