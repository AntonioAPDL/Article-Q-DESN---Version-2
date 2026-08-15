repo_root <- normalizePath(file.path(dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase149_case_specific_screening.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R"
)) source(app_path("application/R", path))

scenarios <- c(
  "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
  "regime_shift", "student_t_location_scale"
)
controls <- data.frame(
  case_id = paste0(scenarios, "__joint_exqdesn_rhs_vb"),
  scenario_ids = scenarios,
  model_ids = "joint_exqdesn_rhs_vb",
  candidate_id = paste0("phase150_", scenarios),
  vb_max_iter = 2400L,
  adaptive_vb_max_iter_grid = "2400,2880",
  vb_tol = 1e-4,
  rhs_vb_inner = 14L,
  tau0 = 0.5,
  zeta2 = 16,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = "1",
  alpha_min_spacing = 0,
  gamma_init_policy = "zero",
  review_adjustment_threshold = 1e-3,
  max_dense_dim = 300L,
  selected_forecast_truth_mae = seq(0.10, 0.17, length.out = 8L),
  selected_fit_truth_mae = seq(0.09, 0.16, length.out = 8L),
  stringsAsFactors = FALSE
)
comparison <- data.frame(
  scenario_id = scenarios,
  mcmc_forecast_truth_mae = seq(0.08, 0.15, length.out = 8L),
  mcmc_fit_truth_mae = seq(0.07, 0.14, length.out = 8L),
  article_joint_al_forecast_truth_mae = seq(0.075, 0.145, length.out = 8L),
  article_joint_al_fit_truth_mae = seq(0.07, 0.14, length.out = 8L),
  stringsAsFactors = FALSE
)

registry_a <- app_joint_exqdesn_phase151_build_registry(controls, comparison)
registry_b <- app_joint_exqdesn_phase151_build_registry(controls, comparison)
stopifnot(identical(registry_a, registry_b))
stopifnot(nrow(registry_a) == 36L)
stopifnot(!anyDuplicated(registry_a$candidate_id))
counts <- table(registry_a$scenario_id)
stopifnot(counts[["persistent_heavy_tail"]] == 1L)
stopifnot(all(counts[names(counts) != "persistent_heavy_tail"] == 5L))
stopifnot(all(registry_a$no_global_specification))
stopifnot(all(registry_a$frozen_target_design_contract))
stopifnot(sum(registry_a$design_role == "direct_phase150_parity") == 8L)

novelty <- app_joint_exqdesn_phase151_prior_experiment_audit()
stopifnot(!any(novelty$repeated_in_phase151))
stopifnot(any(novelty$prior_stage == "Phase4n"))
stopifnot(any(grepl("actual reservoir", novelty$phase151_decision, fixed = TRUE)))

scenario_summary <- data.frame(
  scenario_id = scenarios,
  p = c(5L, 5L, 5L, 8L, 5L, 5L, 7L, 5L),
  K = 7L,
  stringsAsFactors = FALSE
)
dense <- app_joint_exqdesn_phase151_validate_dense_dimensions(registry_a, scenario_summary)
stopifnot(nrow(dense) == nrow(registry_a))
stopifnot(all(dense$status == "pass"))
stopifnot(max(dense$dense_dimension) <= 300L)

n <- 1200L
role <- c(rep("desn_washout", 500L), rep("fit", 500L), rep("validation", 200L))
toy_design <- data.frame(
  scenario_id = "normal_bridge",
  full_time_index = seq_len(n),
  effective_index = seq_len(n),
  analysis_window_index = seq_len(n),
  role = role,
  role_index = ave(seq_len(n), role, FUN = seq_along),
  retained_after_desn_index = c(rep(NA_integer_, 500L), seq_len(700L)),
  lag_y = sin(seq_len(n) / 11),
  trend = seq(-1, 1, length.out = n),
  stringsAsFactors = FALSE
)
toy_artifacts <- list(design = toy_design)
direct <- registry_a[
  registry_a$scenario_id == "normal_bridge" &
    registry_a$design_role == "direct_phase150_parity", ,
  drop = FALSE
]
hybrid <- registry_a[
  registry_a$scenario_id == "normal_bridge" &
    registry_a$design_role == "hybrid_balanced", ,
  drop = FALSE
]
reservoir <- registry_a[
  registry_a$scenario_id == "normal_bridge" &
    registry_a$design_role == "reservoir_compact", ,
  drop = FALSE
]
direct_design <- app_joint_exqdesn_phase151_transform_design(toy_artifacts, direct)
stopifnot(identical(direct_design$design, toy_design))
hybrid_a <- app_joint_exqdesn_phase151_transform_design(toy_artifacts, hybrid)
hybrid_b <- app_joint_exqdesn_phase151_transform_design(toy_artifacts, hybrid)
reservoir_design <- app_joint_exqdesn_phase151_transform_design(toy_artifacts, reservoir)
stopifnot(identical(hybrid_a$design, hybrid_b$design))
stopifnot(all(is.finite(as.matrix(hybrid_a$design[, -(1:7), drop = FALSE]))))
stopifnot(hybrid_a$diagnostic$readout_feature_count[[1L]] == 14L)
stopifnot(reservoir_design$diagnostic$readout_feature_count[[1L]] == 12L)
stopifnot(hybrid_a$diagnostic$scaling_reference_rows[[1L]] == 1000L)
stopifnot(hybrid_a$diagnostic$fit_diagnostic_rows[[1L]] == 500L)
stopifnot(all(c(
  "state_live_feature_count", "state_effective_rank", "state_rank_fraction"
) %in% names(hybrid_a$diagnostic)))

toy_preflight_artifacts <- toy_artifacts
toy_preflight_artifacts$scenario_summary <- data.frame(
  scenario_id = "normal_bridge", K = 7L, stringsAsFactors = FALSE
)
preflight <- app_joint_exqdesn_phase151_preflight_designs(
  rbind(direct, hybrid, reservoir), toy_preflight_artifacts
)
stopifnot(nrow(preflight) == 3L)
stopifnot(!any(preflight$preflight_status == "fail"))
stopifnot(all(preflight$dense_dimension <= preflight$max_dense_dim))

toy_changed <- toy_artifacts
toy_changed$design$lag_y[toy_changed$design$role == "validation"] <- 1e6
hybrid_changed <- app_joint_exqdesn_phase151_transform_design(toy_changed, hybrid)
fit_rows <- hybrid_a$design$role == "fit"
stopifnot(isTRUE(all.equal(
  hybrid_a$design[fit_rows, , drop = FALSE],
  hybrid_changed$design[fit_rows, , drop = FALSE],
  tolerance = 0
)))

summary_direct <- data.frame(
  candidate_id = "direct", scenario_id = "normal_bridge",
  scenario_role = "optimization_target", model_id = "joint_exqdesn_rhs_vb",
  source_phase150_candidate_id = "source", design_role = "direct_phase150_parity",
  design_class = "direct", reservoir_width = 0L, reservoir_alpha = NA_real_,
  reservoir_rho = NA_real_, reservoir_pi_w = NA_real_, input_scale = NA_real_,
  reservoir_seed = NA_integer_, tau0 = 0.5, zeta2 = 16,
  alpha_prior_sd = "1", gamma_init_policy = "zero",
  readout_feature_count = 5L, quantile_count = 7L, dense_dimension = 35L,
  gate_status = "pass", implementation_status = "pass",
  vb_converged = TRUE, vb_reached_max_iter = FALSE,
  forecast_truth_mae = 0.10, fit_truth_mae = 0.09,
  forecast_check_loss_mean = 0.20, forecast_raw_crossing_pairs = 0L,
  phase149_vb_forecast_truth_mae = 0.10, phase149_vb_fit_truth_mae = 0.09,
  phase150_mcmc_forecast_truth_mae = 0.095, phase150_mcmc_fit_truth_mae = 0.085,
  article_joint_al_forecast_truth_mae = 0.09, article_joint_al_fit_truth_mae = 0.08,
  stringsAsFactors = FALSE
)
summary_new <- summary_direct
summary_new$candidate_id <- "new"
summary_new$design_role <- "hybrid_balanced"
summary_new$design_class <- "hybrid"
summary_new$reservoir_width <- 12L
summary_new$reservoir_alpha <- 0.86
summary_new$reservoir_rho <- 0.95
summary_new$reservoir_pi_w <- 0.20
summary_new$input_scale <- 0.20
summary_new$reservoir_seed <- 123L
summary_new$forecast_truth_mae <- 0.095
summary_new$fit_truth_mae <- 0.091
summary_new$forecast_check_loss_mean <- 0.201
ranking <- app_joint_exqdesn_phase151_rank_candidates(rbind(summary_direct, summary_new))
stopifnot(ranking$eligible_for_mcmc[ranking$candidate_id == "new"])
selection <- app_joint_exqdesn_phase151_selection(ranking)
stopifnot(nrow(selection$mcmc_plan) == 1L)
stopifnot(selection$mcmc_plan$candidate_id[[1L]] == "new")

tmp <- tempfile("phase151_candidate_")
dir.create(tmp)
checkpoint <- list(
  candidate_summary = summary_direct,
  tau_summary = data.frame(candidate_id = "direct", scenario_id = "normal_bridge", validation_window = "fit", tau = 0.5),
  interval_summary = data.frame(candidate_id = "direct", validation_window = "fit", lower_tau = 0.1, upper_tau = 0.9),
  design_diagnostics = data.frame(candidate_id = "direct", scenario_id = "normal_bridge", finite_design = TRUE),
  vb_diagnostics = data.frame(candidate_id = "direct", scenario_id = "normal_bridge", converged = TRUE)
)
candidate_dir <- app_joint_exqdesn_phase151_write_candidate(checkpoint, tmp, "direct")
stopifnot(app_joint_exqdesn_phase151_verify_candidate_dir(candidate_dir))
manifest <- app_read_csv(file.path(candidate_dir, "artifact_manifest.csv"))
stopifnot(nrow(manifest) == 6L)
stopifnot(all(nzchar(manifest$sha256)))

cat("Joint exQDESN Phase151 feature-design screening tests passed.\n")
