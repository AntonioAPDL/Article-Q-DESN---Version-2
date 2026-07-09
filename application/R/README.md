# Application R Helpers

This directory will contain application-specific R helpers for the GloFAS
workflow. Keep these files focused on data ingestion, panel construction,
Q-DESN application wrappers, scoring, and manuscript-output generation.

General Q-DESN fitting code should remain in the pinned computational package
or in a clearly documented vendored module if vendoring becomes necessary.

Tracked helper files:

- `00_packages.R`
- `launch_control.R`: explicit launch guards for expensive workflows. It blocks
  retired run identifiers, requires `--confirm_final_launch true` before any
  final-launch configuration reaches `03_fit_models.R`, and refuses to reuse
  nonempty run directories unless an intentional resume is requested.
- `artifact_hygiene.R`: report-only inventory helpers for generated `.rds`,
  `.rda`, `.RData`, and large local artifacts under ignored application output
  roots. These helpers never delete files. They include both file-level
  inventories and run-level summaries for deciding which unselected run
  objects can be cleaned after promotion.
- `input_contract.R`
- `engine_contract.R`
  plus the inference-support gate for package-backed discrepancy fits. The
  current local-source contract records the pinned exDQLM/Q-DESN source path,
  branch, commit, and package version. The shared 1.0.0 source supplies the
  package Q-DESN feature and readout APIs used by the article-side latent-path
  fitter; the older package-side `qdesn_fit_discrepancy()` export is required
  only for the legacy origin-state bridge.
- `validation_interface_contract.R`: guards for shared validation interface
  tables. The generic guard requires source-registry hashes,
  package/branch/commit provenance, forecast-origin/window metadata, H=100 and
  H=1000 forecast metrics, fit metrics, runtime/status fields, and
  storage-light artifact paths. The final TT500 guard additionally pins exact
  Q--DESN and exDQLM/DQLM interface SHA-256 hashes, checks the TT500 source
  window, rolling-origin `H_{\max}=30` lead grid, source-registry hash,
  package version `1.0.0`, validation branch, artifact commits, and Q--DESN
  scale-repaired forecast paths before the article table builder can consume
  rows. The guards fail loudly on old 0.5.0 validation paths or stale
  `/home/jaguir26/local/src` paths.
- `model_contract.R`: application-model contract helpers. These distinguish
  the frozen `origin_state_bridge` workflow from the target
  `latent_path_ensemble_likelihood` workflow and record source-parameter
  ownership for GloFAS likelihood rows.
- `feature_contract.R`: normalized readout-feature contract for the GloFAS
  discrepancy model. It parses output and covariate lag specifications,
  separates the reservoir's internal input bias from the readout intercept, and
  validates that fitted and prediction matrices use compatible columns. The
  current large Dec. 25 launch profiles keep the direct input block and horizon
  column disabled, so those parsed lag specifications are inactive unless a
  later config explicitly enables them.
- `register_input_bundle.R`
- `audit_input_bundle.R`
- `build_application_panel.R`
- `covariate_design.R`: model-facing precipitation and soil-moisture covariate
  timeline construction. It excludes GDPC and climate-index columns, tags
  retrospective-realized versus forecast-blended rows, standardizes covariates
  on the retrospective training period, and builds lagged readout blocks when
  the readout contract requests direct covariate lags.
- `build_qdesn_features.R`
- `latent_path_design.R`: latent-path future-state continuation helpers. These
  recompute only the issued-horizon reservoir states given a candidate future
  USGS path and enforce no-leakage checks for post-cutoff USGS inputs. The
  current continuation core supports response-lag reservoir inputs and
  deterministic ppt and soil lagged covariates inside the reservoir recursion.
- `simulate_latent_path.R`: synthetic AL generator for the target latent-path
  ensemble-likelihood model. It produces known-truth panels with output lags,
  precipitation and soil-moisture covariates, retrospective GloFAS rows, and
  issued GloFAS ensemble rows for sampler validation.
- `discrepancy_design.R`
  builds the source-indexed discrepancy design. Version 0.2 uses one feature
  block for the shared quantile and discrepancy readouts. Version 0.3 supports
  separate reference and discrepancy feature blocks, producing stacked designs
  of the form `[X_Y, 0]` for reference rows and `[X_Y, X_D]` for retrospective
  GloFAS rows.
- `forecast_contract.R`: prediction-contract validation and row builders for
  issued-horizon GloFAS quantile correction. This file owns the recorded
  pilot relationship `qhat = q_g_hat - d_g_hat` and the final draw-level
  contract `q_y_draw = q_g_draw - d_g_draw`. The default posterior-draw
  contract uses Bayesian-bootstrap quantile draws from the issued GloFAS
  ensemble and posterior draws of the discrepancy readout.
- `fit_qdesn_reference.R`
- `fit_qdesn_discrepancy.R`: legacy origin-state bridge adapter to a
  package-side `qdesn_fit_discrepancy()` API when that export is available.
  The target latent-path ensemble-likelihood workflow does not use this
  adapter for fitting.
- `fit_qdesn_latent_path.R`: data-contract adapter and fail-closed fitter
  for the target latent-path ensemble-likelihood model. It
  separates historical USGS rows, retrospective GloFAS rows, issued ensemble
  rows, and held-out future USGS oracle values before any sampler is enabled.
  In `latent_path_v0.3` it builds separate reference and discrepancy DESN
  feature blocks, with forecast-window discrepancy states driven by the keyed
  GloFAS empirical quantile path minus the latent reference path. It also
  records requested versus effective issued horizons, keyed future GloFAS
  design metadata, and first-order Delta prediction metadata for posterior-draw
  quantiles.
- `latent_path_vb_al.R`: article-side AL-VB implementation for the
  latent-path ensemble-likelihood model. It keeps a dense debug path for small
  equivalence tests, uses streamed grouped future moments for the production
  path, updates the future USGS latent path with a linearized Delta Gaussian
  step, applies independent regularized-horseshoe states to the beta and alpha
  coefficient blocks, and stores the final future-state linearization for
  draw-level prediction.
- `figure_provenance.R`
- `plot_input_diagnostics.R`
- `synthesize_quantiles.R`: monotone quantile-grid synthesis and crossing
  diagnostics for independently fitted quantile models.
- `hybrid_quantile_synthesis.R`: no-refit raw/Q-DESN hybrid-candidate
  builders for completed multi-quantile GloFAS synthesis runs. These helpers
  are diagnostic and do not promote article-facing outputs by themselves.
- `score_forecasts.R`: check loss, interval score, and quantile-grid CRPS
  helpers. Multi-quantile workflows can report both independent and monotone
  check loss so synthesis corrections remain explicit.
- `reservoir_screening.R`: sampler-free D-ESN reservoir diagnostics and
  early-rejection helpers. These inspect recurrent-layer stability, leaky
  effective radii, state degeneracy, saturation, correlation redundancy,
  effective rank, conditioning, optional cheap validation, and seed-level
  aggregation. The helpers are advisory by default and do not launch VB or
  MCMC; `application/scripts/03_screen_reservoir_design.R` is the standalone
  pre-stage that writes screening tables for a fresh run id.
- `make_manuscript_outputs.R`
- `promote_application_outputs.R`: promotion guards and provenance-map helpers
  used by `scripts/08_promote_application_outputs.R`. Final-launch promotion
  refuses ignored local configs by default and can promote storage-light run
  provenance snapshots with the article-facing outputs.
- `application_output_registry.R`: current-output selection helpers for the
  manuscript-facing GloFAS application. These read a promotion manifest and
  write stable TeX aliases, a compact score table, and a hash-checked
  selection manifest so future promoted runs can replace the current reference
  run without hard-coded manuscript paths.
- `post_fit_analysis.R`: post-fit posterior-draw summaries, method-aware
  diagnostics, figures, and descriptive/proper forecast metrics for completed
  GloFAS discrepancy Q-DESN runs. This helper treats the saved fit and design
  objects as authoritative and does not refit the model.
- `launch_readiness.R`: preflight checks for completed pilot or dry-run
  directories before any final application launch.
