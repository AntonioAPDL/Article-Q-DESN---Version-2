repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase125 test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase125_balanced_mcmc_audit.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  invisible(manifest)
}

make_case_rows <- function(scenario_id, source_model_id, raw = 0L, gate = "pass") {
  model_id <- sub("_vb$", "_mcmc", source_model_id)
  label <- switch(
    source_model_id,
    joint_qdesn_rhs_vb = "JOINT QDESN RHS MCMC",
    qdesn_rhs_independent_vb = "QDESN RHS MCMC",
    joint_exqdesn_rhs_vb = "JOINT exQDESN RHS MCMC",
    exqdesn_rhs_independent_vb = "exQDESN RHS MCMC"
  )
  data.frame(
    case_id = paste(scenario_id, source_model_id, sep = "__"),
    scenario_id = scenario_id,
    scenario_class = "test",
    distribution_family = "synthetic",
    dynamics_class = "test_dynamic",
    source_candidate_id = "phase125_test_candidate",
    source_model_id = source_model_id,
    model_id = model_id,
    display_label = label,
    likelihood = ifelse(grepl("exqdesn", source_model_id), "exal", "al"),
    fit_structure = ifelse(grepl("independent", source_model_id), "independent_single_tau", "joint"),
    inference = "MCMC",
    phase121_candidate_id = "phase125_test_candidate",
    phase121_selection_status = gate,
    n_train = 20L,
    p = 3L,
    K = 3L,
    tau_grid = "0.05,0.50,0.95",
    vb_converged = TRUE,
    vb_reached_max_iter = FALSE,
    vb_adaptive_attempts = "20",
    mcmc_n_chains = 2L,
    mcmc_n_iter = 20L,
    mcmc_burn = 10L,
    mcmc_thin = 2L,
    mcmc_n_keep_total = 10L,
    mcmc_init_source = "provided",
    all_chain_init_source_provided = TRUE,
    mcmc_draws_all_finite = TRUE,
    sigma_lower_bound = 1.0e-8,
    sigma_upper_bound = 10,
    max_sigma_lower_bound_hit_fraction = 0,
    max_sigma_upper_bound_hit_fraction = 0,
    vb_fit_truth_mae = 0.11,
    mcmc_fit_truth_mae = 0.10 + 0.001 * raw,
    vb_forecast_truth_mae = 0.12,
    mcmc_forecast_truth_mae = 0.11 + 0.001 * raw,
    vb_fit_check_loss_mean = 0.15,
    mcmc_fit_check_loss_mean = 0.149,
    vb_forecast_check_loss_mean = 0.16,
    mcmc_forecast_check_loss_mean = 0.151 + 0.001 * raw,
    vb_fit_raw_crossing_pairs = 0L,
    mcmc_fit_raw_crossing_pairs = 0L,
    vb_forecast_raw_crossing_pairs = 0L,
    mcmc_forecast_raw_crossing_pairs = raw,
    vb_fit_contract_crossing_pairs = 0L,
    mcmc_fit_contract_crossing_pairs = 0L,
    vb_forecast_contract_crossing_pairs = 0L,
    mcmc_forecast_contract_crossing_pairs = 0L,
    vb_fit_max_abs_adjustment = 0,
    mcmc_fit_max_abs_adjustment = 0,
    vb_forecast_max_abs_adjustment = 0,
    mcmc_forecast_max_abs_adjustment = ifelse(raw > 0, 0.01, 0),
    vb_mcmc_max_normalized_distance = 0.2,
    max_chain_to_pooled_normalized_distance = 0.1,
    vb_elapsed_seconds = 1,
    mcmc_elapsed_seconds = 2,
    total_elapsed_seconds = 3,
    stringsAsFactors = FALSE
  )
}

write_mcmc_block <- function(dir, cases) {
  app_ensure_dir(dir)
  assessment <- data.frame(
    case_id = cases$case_id,
    scenario_id = cases$scenario_id,
    scenario_class = cases$scenario_class,
    distribution_family = cases$distribution_family,
    dynamics_class = cases$dynamics_class,
    source_model_id = cases$source_model_id,
    model_id = cases$model_id,
    display_label = cases$display_label,
    likelihood = cases$likelihood,
    fit_structure = cases$fit_structure,
    implementation_status = "pass",
    distance_status = "pass",
    chain_status = "pass",
    raw_crossing_status = ifelse(cases$mcmc_forecast_raw_crossing_pairs > 0, "review", "pass"),
    gate_status = ifelse(cases$mcmc_forecast_raw_crossing_pairs > 0, "review", "pass"),
    contract_crossing_pairs = 0L,
    raw_crossing_pairs = cases$mcmc_forecast_raw_crossing_pairs,
    max_abs_adjustment = cases$mcmc_forecast_max_abs_adjustment,
    status_reason = ifelse(cases$mcmc_forecast_raw_crossing_pairs > 0, "raw quantiles crossed before monotone contract", "all gates passed"),
    stringsAsFactors = FALSE
  )
  metric <- do.call(rbind, lapply(seq_len(nrow(cases)), function(ii) {
    data.frame(
      scenario_id = cases$scenario_id[[ii]],
      model_id = cases$model_id[[ii]],
      display_label = cases$display_label[[ii]],
      likelihood = cases$likelihood[[ii]],
      fit_structure = cases$fit_structure[[ii]],
      tau = c(0.05, 0.50, 0.95),
      truth_mae = cases$mcmc_forecast_truth_mae[[ii]],
      truth_rmse = cases$mcmc_forecast_truth_mae[[ii]] + 0.01,
      truth_bias = 0,
      check_loss_mean = cases$mcmc_forecast_check_loss_mean[[ii]],
      n_scores = 20L,
      stringsAsFactors = FALSE
    )
  }))
  truth <- metric[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "truth_mae", "truth_rmse", "truth_bias")]
  check <- metric[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "check_loss_mean", "n_scores")]
  crps <- unique(metric[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")])
  crps$crps_grid_mean <- 0.2
  crps$n_crps <- 20L
  hit <- check
  hit$hit_rate <- hit$tau
  hit$hit_rate_error <- 0
  hit$abs_hit_rate_error <- 0.01
  hit <- hit[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "hit_rate", "n_scores", "hit_rate_error", "abs_hit_rate_error")]
  interval <- unique(metric[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")])
  interval$lower_tau <- 0.05
  interval$upper_tau <- 0.95
  interval$nominal_coverage <- 0.90
  interval$coverage <- 0.88
  interval$interval_width_mean <- 1
  interval$interval_score_mean <- 2
  interval$n_intervals <- 20L
  interval$coverage_error <- -0.02
  interval$abs_coverage_error <- 0.02
  manifest_rows <- data.frame(
    source_label = "test",
    label = "dummy",
    relative_path = "dummy.csv",
    path = "dummy.csv",
    exists = TRUE,
    declared_size_bytes = 1,
    actual_size_bytes = 1,
    declared_sha256 = paste(rep("a", 64), collapse = ""),
    actual_sha256 = paste(rep("a", 64), collapse = ""),
    status = "pass",
    stringsAsFactors = FALSE
  )
  failures <- data.frame(
    validation_label = character(),
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      n_cases = nrow(cases),
      validation_contract = "quantile_grid_readout_fit_and_no_refit_forecast",
      scalar_predictive_density_claim = FALSE,
      stringsAsFactors = FALSE
    ), file.path(dir, "run_config.csv")),
    phase121_source_manifest_verification = app_joint_qvp_write_csv(manifest_rows, file.path(dir, "phase121_source_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(manifest_rows, file.path(dir, "fixture_source_manifest.csv")),
    case_winner_controls = app_joint_qvp_write_csv(cases[, c("case_id", "scenario_id", "source_model_id")], file.path(dir, "case_winner_controls.csv")),
    scenario_worker_failures = app_joint_qvp_write_csv(failures, file.path(dir, "scenario_worker_failures.csv")),
    mcmc_case_summary = app_joint_qvp_write_csv(cases, file.path(dir, "mcmc_case_summary.csv")),
    mcmc_case_assessment = app_joint_qvp_write_csv(assessment, file.path(dir, "mcmc_case_assessment.csv")),
    forecast_truth_distance_summary = app_joint_qvp_write_csv(truth, file.path(dir, "forecast_truth_distance_summary.csv")),
    forecast_check_loss_summary = app_joint_qvp_write_csv(check, file.path(dir, "forecast_check_loss_summary.csv")),
    forecast_crps_grid_summary = app_joint_qvp_write_csv(crps, file.path(dir, "forecast_crps_grid_summary.csv")),
    forecast_hit_rate_summary = app_joint_qvp_write_csv(hit, file.path(dir, "forecast_hit_rate_summary.csv")),
    forecast_interval_summary = app_joint_qvp_write_csv(interval, file.path(dir, "forecast_interval_summary.csv")),
    fit_truth_distance_summary = app_joint_qvp_write_csv(truth, file.path(dir, "fit_truth_distance_summary.csv")),
    fit_check_loss_summary = app_joint_qvp_write_csv(check, file.path(dir, "fit_check_loss_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(data.frame(n_crossing_pairs = 0L), file.path(dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(data.frame(n_crossing_pairs = sum(cases$mcmc_forecast_raw_crossing_pairs)), file.path(dir, "raw_crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, converged = TRUE, reached_max_iter = FALSE), file.path(dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, objective_status = "finite"), file.path(dir, "objective_diagnostics.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, block = "alpha", finite_draws = TRUE), file.path(dir, "mcmc_draw_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, max_normalized_distance = cases$vb_mcmc_max_normalized_distance), file.path(dir, "vb_mcmc_distance_summary.csv")),
    chain_to_pooled_distance_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, max_normalized_to_pooled = cases$max_chain_to_pooled_normalized_distance), file.path(dir, "chain_to_pooled_distance_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, elapsed_seconds = cases$total_elapsed_seconds), file.path(dir, "runtime_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(dir, "provenance.csv")),
    readme = app_joint_qvp_write_csv(data.frame(note = "phase125 test"), file.path(dir, "README.md"))
  )
  invisible(app_joint_qdesn_write_manifest(paths, dir))
}

tmp_root <- tempfile("joint_qdesn_phase125_")
block_a <- file.path(tmp_root, "block_a")
block_b <- file.path(tmp_root, "block_b")
out_dir <- file.path(tmp_root, "phase125")

cases_a <- rbind(
  make_case_rows("normal_bridge", "joint_qdesn_rhs_vb"),
  make_case_rows("normal_bridge", "qdesn_rhs_independent_vb", raw = 1L)
)
cases_b <- rbind(
  make_case_rows("laplace_bridge", "joint_qdesn_rhs_vb"),
  make_case_rows("laplace_bridge", "qdesn_rhs_independent_vb")
)
write_mcmc_block(block_a, cases_a)
write_mcmc_block(block_b, cases_b)

blocks <- data.frame(
  source_block_id = c("test_existing", "test_missing"),
  source_role = c("existing", "missing"),
  source_dir = c(block_a, block_b),
  stringsAsFactors = FALSE
)

result <- app_joint_qdesn_run_phase125_balanced_mcmc_audit(
  out_dir = out_dir,
  source_blocks = blocks,
  expected_scenarios = c("normal_bridge", "laplace_bridge"),
  expected_models = c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb")
)

stopifnot(file.exists(file.path(out_dir, "artifact_manifest.csv")))
check_manifest(out_dir)
stopifnot(nrow(result$case_summary) == 4L)
stopifnot(nrow(result$model_summary) == 2L)
stopifnot(all(result$scope$matrix$present_in_balanced_mcmc))
stopifnot(sum(result$scope$matrix$n_matching_rows) == 4L)
stopifnot(result$recommendation$hard_implementation_gate[[1L]] == "pass")
stopifnot(result$recommendation$balanced_mcmc_grid[[1L]] == "complete")
stopifnot(sum(result$case_summary$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE) == 0L)
stopifnot(sum(result$case_summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE) == 1L)
stopifnot(nrow(utils::read.csv(file.path(out_dir, "source_block_summary.csv"), stringsAsFactors = FALSE)) == 2L)
stopifnot(nrow(utils::read.csv(file.path(out_dir, "scenario_winner_summary.csv"), stringsAsFactors = FALSE)) == 8L)
stopifnot(all(utils::read.csv(file.path(out_dir, "source_artifact_manifest_verification.csv"), stringsAsFactors = FALSE)$status == "pass"))

cat("joint_qdesn_phase125_balanced_mcmc_audit tests passed\n")
