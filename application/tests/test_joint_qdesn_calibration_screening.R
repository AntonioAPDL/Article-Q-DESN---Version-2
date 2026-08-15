repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN calibration-screening test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))

stopifnot(identical(app_joint_qdesn_parse_numeric_vector("1,0.5,Inf"), c(1, 0.5, Inf)))
controls <- app_joint_qdesn_simulation_controls(
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = 1L,
  alpha_prior_sd = "1,0.5,1",
  gamma_init_policy = "zero"
)
stopifnot(identical(controls$alpha_prior_sd, c(1, 0.5, 1)))
stopifnot(all(app_joint_qdesn_gamma_init_for_policy(c(0.1, 0.5, 0.9), controls) == 0))
stopifnot(identical(app_joint_qdesn_alpha_prior_sd_for_tau(controls$alpha_prior_sd, 2L, 3L), 0.5))

write_manifest_checked <- function(paths, dir) {
  info <- app_joint_qdesn_write_manifest(paths, dir)
  manifest <- utils::read.csv(info$manifest_path, stringsAsFactors = FALSE)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  info
}

make_screening_dir <- function(dir) {
  app_ensure_dir(dir)
  cand_id <- "rhs_tau0_0p5_alpha0p5"
  forecast_dir <- file.path(dir, "candidate_forecast")
  fit_dir <- file.path(dir, "candidate_fit")
  app_ensure_dir(forecast_dir)
  app_ensure_dir(fit_dir)
  registry <- data.frame(
    candidate_id = cand_id,
    candidate_label = "Selected",
    use_existing_artifacts = FALSE,
    fit_dir = fit_dir,
    forecast_dir = forecast_dir,
    vb_max_iter = 480L,
    adaptive_vb_max_iter_grid = "480,960",
    vb_tol = 1.0e-4,
    rhs_vb_inner = 7L,
    tau0 = 0.5,
    zeta2 = Inf,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = "0.5",
    alpha_min_spacing = 0,
    gamma_init_policy = "default",
    review_adjustment_threshold = 1.0e-3,
    max_dense_dim = 300L,
    n_cores = 1L,
    candidate_role = "full_screening_candidate",
    notes = "tiny fixture",
    stringsAsFactors = FALSE
  )
  app_joint_qdesn_validate_screening_registry(registry)
  dirs <- data.frame(
    candidate_id = cand_id,
    candidate_label = "Selected",
    use_existing_artifacts = FALSE,
    fit_dir = fit_dir,
    forecast_dir = forecast_dir,
    stringsAsFactors = FALSE
  )
  models <- data.frame(
    model_id = c("joint_qdesn_rhs_vb", "joint_exqdesn_rhs_vb", "qdesn_rhs_independent_vb", "exqdesn_rhs_independent_vb"),
    display_label = c("JOINT QDESN RHS", "JOINT exQDESN RHS", "QDESN RHS", "exQDESN RHS"),
    likelihood = c("al", "exal", "al", "exal"),
    fit_structure = c("joint", "joint", "independent_single_tau", "independent_single_tau"),
    stringsAsFactors = FALSE
  )
  model_metric <- cbind(
    registry[rep(1L, 4L), c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy", "vb_max_iter", "adaptive_vb_max_iter_grid", "rhs_vb_inner")],
    data.frame(
      stage = "forecast",
      models,
      truth_mae = c(0.10, 0.16, 0.11, 0.15),
      truth_sq_error = c(0.02, 0.04, 0.03, 0.035),
      truth_rmse = c(0.14, 0.20, 0.17, 0.19),
      check_loss_mean = c(0.16, 0.17, 0.16, 0.17),
      crps_grid_mean = c(0.36, 0.38, 0.37, 0.38),
      abs_hit_rate_error = c(0.02, 0.04, 0.02, 0.04),
      abs_coverage_error = c(0.02, 0.08, 0.03, 0.08),
      interval_width_mean = c(2.1, 1.7, 2.1, 1.7),
      interval_score_mean = c(3.0, 3.4, 3.1, 3.3),
      raw_crossing_pairs = c(2L, 0L, 20L, 30L),
      contract_crossing_pairs = 0L,
      reached_max_iter = c(0L, 1L, 1L, 1L),
      elapsed_seconds = c(1, 1, 1, 1),
      max_abs_adjustment = c(1.0e-4, 0, 1.0e-3, 1.0e-3),
      adjustment_rate = c(0.001, 0, 0.01, 0.01),
      finite_quantiles = TRUE,
      finite_scores = TRUE,
      gate_status = c("review", "review", "review", "review"),
      stringsAsFactors = FALSE
    )
  )
  fit_model <- model_metric
  fit_model$stage <- "fit"
  scenario_metric <- do.call(rbind, lapply(c("normal_bridge", "nonlinear_reservoir_friendly"), function(sid) {
    out <- model_metric[, c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy", "stage", "model_id", "display_label", "likelihood", "fit_structure", "truth_mae", "truth_sq_error", "truth_rmse", "check_loss_mean", "gate_status", "raw_crossing_pairs", "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate", "reached_max_iter"), drop = FALSE]
    out$scenario_id <- sid
    out[, c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy", "stage", "scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "truth_mae", "truth_sq_error", "truth_rmse", "check_loss_mean", "gate_status", "raw_crossing_pairs", "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate", "reached_max_iter"), drop = FALSE]
  }))
  scenario_metric$status_reason <- "tiny"
  tau_metric <- do.call(rbind, lapply(c(0.05, 0.10, 0.50, 0.90, 0.95), function(tt) {
    out <- model_metric[, c("candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "gamma_init_policy", "stage", "model_id", "display_label", "likelihood", "fit_structure", "truth_mae", "truth_sq_error", "truth_rmse", "check_loss_mean"), drop = FALSE]
    out$tau <- tt
    out$truth_mae <- out$truth_mae + ifelse(tt >= 0.90 & out$model_id == "joint_exqdesn_rhs_vb", 0.08, 0)
    out
  }))
  scorecard <- data.frame(
    candidate_id = cand_id,
    candidate_label = "Selected",
    gate_status = "review",
    screening_score = 0.7,
    mean_fit_truth_mae = 0.11,
    mean_forecast_truth_mae = 0.12,
    joint_qdesn_forecast_truth_mae = 0.10,
    independent_exqdesn_forecast_truth_mae = 0.15,
    max_scenario_forecast_truth_mae = 0.21,
    forecast_raw_crossings = 52L,
    max_forecast_adjustment = 0.01,
    elapsed_minutes = 2,
    recommendation_class = "usable_with_review",
    rank = 1L,
    stringsAsFactors = FALSE
  )
  health <- data.frame(
    candidate_id = cand_id,
    candidate_label = "Selected",
    gate_status = "review",
    forecast_raw_crossings = 52L,
    contract_crossings = 0L,
    max_forecast_truth_mae = 0.21,
    max_forecast_adjustment = 0.01,
    fit_reached_max_iter = 1L,
    forecast_reached_max_iter = 1L,
    elapsed_seconds = 120,
    stringsAsFactors = FALSE
  )
  selected <- cbind(scorecard, data.frame(selected = TRUE, next_action = "review", stringsAsFactors = FALSE))
  interval <- data.frame(
    scenario_id = rep("normal_bridge", 8L),
    model_id = rep(models$model_id, each = 2L),
    display_label = rep(models$display_label, each = 2L),
    likelihood = rep(models$likelihood, each = 2L),
    fit_structure = rep(models$fit_structure, each = 2L),
    lower_tau = rep(c(0.05, 0.10), 4L),
    upper_tau = rep(c(0.95, 0.90), 4L),
    nominal_coverage = rep(c(0.90, 0.80), 4L),
    coverage = c(0.88, 0.78, 0.81, 0.72, 0.87, 0.78, 0.80, 0.72),
    interval_width_mean = c(2.1, 1.6, 1.7, 1.3, 2.1, 1.6, 1.7, 1.3),
    interval_score_mean = c(3, 2.7, 3.5, 3.1, 3.1, 2.8, 3.4, 3.0),
    n_intervals = 10L,
    coverage_error = 0,
    abs_coverage_error = 0.02,
    stringsAsFactors = FALSE
  )
  utils::write.csv(interval, file.path(forecast_dir, "interval_summary.csv"), row.names = FALSE)
  candidate_registry_path <- app_joint_qdesn_screening_write_csv(registry, file.path(dir, "candidate_registry.csv"))
  nested <- data.frame(
    candidate_id = cand_id,
    stage = "screening",
    label = "candidate_registry",
    relative_path = "candidate_registry.csv",
    path = normalizePath(candidate_registry_path, mustWork = TRUE),
    exists = TRUE,
    declared_sha256 = app_sha256_file(candidate_registry_path),
    actual_sha256 = app_sha256_file(candidate_registry_path),
    declared_size_bytes = as.numeric(file.info(candidate_registry_path)$size),
    actual_size_bytes = as.numeric(file.info(candidate_registry_path)$size),
    status = "pass",
    stringsAsFactors = FALSE
  )
  paths <- c(
    candidate_registry = candidate_registry_path,
    candidate_artifact_dirs = app_joint_qdesn_screening_write_csv(dirs, file.path(dir, "candidate_artifact_dirs.csv")),
    candidate_manifest_verification = app_joint_qdesn_screening_write_csv(nested, file.path(dir, "candidate_manifest_verification.csv")),
    candidate_scorecard = app_joint_qdesn_screening_write_csv(scorecard, file.path(dir, "candidate_scorecard.csv")),
    fit_model_metric_summary = app_joint_qdesn_screening_write_csv(fit_model, file.path(dir, "fit_model_metric_summary.csv")),
    forecast_model_metric_summary = app_joint_qdesn_screening_write_csv(model_metric, file.path(dir, "forecast_model_metric_summary.csv")),
    fit_scenario_metric_summary = app_joint_qdesn_screening_write_csv(scenario_metric, file.path(dir, "fit_scenario_metric_summary.csv")),
    forecast_scenario_metric_summary = app_joint_qdesn_screening_write_csv(scenario_metric, file.path(dir, "forecast_scenario_metric_summary.csv")),
    forecast_tau_metric_summary = app_joint_qdesn_screening_write_csv(tau_metric, file.path(dir, "forecast_tau_metric_summary.csv")),
    screening_health_summary = app_joint_qdesn_screening_write_csv(health, file.path(dir, "screening_health_summary.csv")),
    selected_spec_recommendation = app_joint_qdesn_screening_write_csv(selected, file.path(dir, "selected_spec_recommendation.csv")),
    provenance = app_joint_qdesn_screening_write_csv(app_joint_qvp_provenance_rows(), file.path(dir, "provenance.csv"))
  )
  write_manifest_checked(paths, dir)
  normalizePath(dir, mustWork = TRUE)
}

phase106 <- make_screening_dir(tempfile("joint_qdesn_phase106_"))
phase107 <- make_screening_dir(tempfile("joint_qdesn_phase107_"))
out_dir <- tempfile("joint_qdesn_phase111_")
screening_out <- tempfile("joint_qdesn_phase112_")

result <- app_joint_qdesn_run_calibration_screening_readiness(
  out_dir = out_dir,
  phase106_dir = phase106,
  phase107_dir = phase107,
  screening_output_dir = screening_out,
  n_cores = 1L
)

stopifnot(file.exists(file.path(result$out_dir, "artifact_manifest.csv")))
stopifnot(file.exists(file.path(result$out_dir, "recommended_screening_registry.csv")))
stopifnot(file.exists(file.path(result$out_dir, "implementation_plan.csv")))
stopifnot(file.exists(file.path(result$out_dir, "phase112_launch_command.csv")))
stopifnot(nrow(result$model_diagnosis) == 8L)
stopifnot(nrow(result$scenario_diagnosis) == 2L)
stopifnot(any(result$recommended_registry$gamma_init_policy == "zero"))
stopifnot(!any(grepl(",", result$recommended_registry$alpha_prior_sd, fixed = TRUE)))
app_joint_qdesn_validate_screening_registry(result$recommended_registry, allow_alpha_prior_vectors = FALSE)
bad_registry <- result$recommended_registry
bad_registry$alpha_prior_sd[[2L]] <- "1,0.5,1"
stopifnot(inherits(
  try(app_joint_qdesn_validate_screening_registry(bad_registry, allow_alpha_prior_vectors = FALSE), silent = TRUE),
  "try-error"
))
stopifnot(inherits(
  try(
    app_joint_qdesn_run_vb_spec_screening(
      out_dir = tempfile("joint_qdesn_bad_vector_runner_"),
      candidate_registry = bad_registry,
      n_cores = 1L,
      reuse_completed = TRUE,
      audit_only = TRUE
    ),
    silent = TRUE
  ),
  "try-error"
))

toy <- app_joint_qdesn_vb_readiness_fixture(
  Tn = 24L,
  washout_length = 5L,
  tau = c(0.1, 0.5, 0.9),
  seed = 2026070701L
)
tiny_controls <- app_joint_qdesn_simulation_controls(
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = 1L,
  rhs_vb_inner = 1L,
  tau0 = 0.5,
  alpha_prior_sd = "1,0.5,1",
  gamma_init_policy = "zero"
)
independent_exal <- app_joint_qdesn_fit_independent_readiness(toy, tiny_controls, likelihood = "exal")
stopifnot(length(independent_exal$fits) == 3L)
stopifnot(all(is.finite(independent_exal$alpha_mean)))

manifest <- utils::read.csv(file.path(result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(manifest$sha256) == 64L))
for (ii in seq_len(nrow(manifest))) {
  path <- file.path(result$out_dir, manifest$relative_path[[ii]])
  stopifnot(file.exists(path))
  stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
}

phase113_out <- tempfile("joint_qdesn_phase113_")
phase113_screening_out <- tempfile("joint_qdesn_phase113_screening_")
phase113 <- app_joint_qdesn_run_phase113_top_candidate_readiness(
  out_dir = phase113_out,
  phase112_dir = phase107,
  screening_output_dir = phase113_screening_out,
  n_cores = 1L
)
stopifnot(file.exists(file.path(phase113$out_dir, "artifact_manifest.csv")))
stopifnot(file.exists(file.path(phase113$out_dir, "phase113_recommended_registry.csv")))
stopifnot(file.exists(file.path(phase113$out_dir, "phase113_implementation_plan.csv")))
stopifnot(file.exists(file.path(phase113$out_dir, "phase113_launch_command.csv")))
stopifnot(any(phase113$recommended_registry$candidate_role == "phase113_hybrid_verification"))
stopifnot(any(phase113$recommended_registry$candidate_id == "zeta2_16_inner10_iter1440_alpha0p5_tau0_0p5"))
stopifnot(any(phase113$recommended_registry$use_existing_artifacts))
stopifnot(!any(duplicated(phase113$recommended_registry$candidate_id)))
app_joint_qdesn_validate_screening_registry(phase113$recommended_registry, allow_alpha_prior_vectors = FALSE)
stopifnot(grepl("106_run_joint_qdesn_vb_spec_screening.R", phase113$launch_command$command[[1L]], fixed = TRUE))
stopifnot(grepl("phase113_recommended_registry.csv", phase113$launch_command$command[[1L]], fixed = TRUE))
phase113_manifest <- utils::read.csv(file.path(phase113$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(phase113_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase113_manifest))) {
  path <- file.path(phase113$out_dir, phase113_manifest$relative_path[[ii]])
  stopifnot(file.exists(path))
  stopifnot(identical(app_sha256_file(path), phase113_manifest$sha256[[ii]]))
}

phase114_out <- tempfile("joint_qdesn_phase114_")
phase114 <- app_joint_qdesn_run_phase114_vb_article_candidate_freeze(
  freeze_dir = phase114_out,
  phase113_dir = phase107,
  fixture_dir = phase106,
  mcmc_out_dir = tempfile("joint_qdesn_phase114_mcmc_"),
  article_assets_out_dir = tempfile("joint_qdesn_phase115_assets_"),
  n_cores = 1L,
  n_chains = 2L,
  mcmc_n_iter = 12L,
  mcmc_burn = 6L,
  mcmc_thin = 3L
)
stopifnot(file.exists(file.path(phase114$freeze_dir, "artifact_manifest.csv")))
stopifnot(file.exists(file.path(phase114$freeze_dir, "freeze_decision_summary.csv")))
stopifnot(file.exists(file.path(phase114$freeze_dir, "selected_vb_model_summary.csv")))
stopifnot(file.exists(file.path(phase114$freeze_dir, "phase114_launch_plan.csv")))
stopifnot(phase114$freeze_decision$decision[[1L]] == "freeze_selected_vb_candidate_and_launch_vb_initialized_mcmc_article_candidate")
stopifnot(any(phase114$gate_audit$gate == "candidate_manifest" & phase114$gate_audit$status == "pass"))
stopifnot(any(phase114$selected_model_summary$model_id == "joint_qdesn_rhs_vb"))
stopifnot(grepl("108_run_joint_qdesn_mcmc_readiness.R", phase114$launch_plan$command[[1L]], fixed = TRUE))
stopifnot(grepl("110_build_joint_qdesn_article_validation_assets.R", phase114$launch_plan$command[[2L]], fixed = TRUE))
phase114_manifest <- utils::read.csv(file.path(phase114$freeze_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(phase114_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase114_manifest))) {
  path <- file.path(phase114$freeze_dir, phase114_manifest$relative_path[[ii]])
  stopifnot(file.exists(path))
  stopifnot(identical(app_sha256_file(path), phase114_manifest$sha256[[ii]]))
}
