repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 123 test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
}

phase122_dir <- tempfile("joint_qdesn_phase122_for_phase123_")
app_ensure_dir(phase122_dir)

cases <- data.frame(
  case_id = c(
    "normal_bridge__joint_qdesn_rhs_vb",
    "normal_bridge__qdesn_rhs_independent_vb",
    "normal_bridge__joint_exqdesn_rhs_vb",
    "normal_bridge__exqdesn_rhs_independent_vb",
    "laplace_bridge__joint_qdesn_rhs_vb"
  ),
  scenario_id = c("normal_bridge", "normal_bridge", "normal_bridge", "normal_bridge", "laplace_bridge"),
  scenario_class = c("bridge", "bridge", "bridge", "bridge", "bridge"),
  distribution_family = c("gaussian", "gaussian", "gaussian", "gaussian", "laplace"),
  dynamics_class = "ar1_seasonal_location_scale",
  source_candidate_id = "phase123_test_candidate",
  source_model_id = c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb",
    "joint_qdesn_rhs_vb"
  ),
  model_id = c(
    "joint_qdesn_rhs_mcmc",
    "qdesn_rhs_independent_mcmc",
    "joint_exqdesn_rhs_mcmc",
    "exqdesn_rhs_independent_mcmc",
    "joint_qdesn_rhs_mcmc"
  ),
  display_label = c(
    "JOINT QDESN RHS MCMC",
    "QDESN RHS MCMC",
    "JOINT exQDESN RHS MCMC",
    "exQDESN RHS MCMC",
    "JOINT QDESN RHS MCMC"
  ),
  likelihood = c("al", "al", "exal", "exal", "al"),
  fit_structure = c("joint", "independent_single_tau", "joint", "independent_single_tau", "joint"),
  inference = "MCMC",
  phase121_candidate_id = "phase123_test_candidate",
  phase121_selection_status = c("pass", "review", "pass", "pass", "pass"),
  n_train = 20L,
  p = 3L,
  K = 7L,
  tau_grid = "0.05,0.10,0.25,0.50,0.75,0.90,0.95",
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
  vb_fit_truth_mae = c(0.10, 0.11, 0.12, 0.13, 0.09),
  mcmc_fit_truth_mae = c(0.09, 0.11, 0.10, 0.12, 0.08),
  vb_forecast_truth_mae = c(0.11, 0.12, 0.13, 0.14, 0.10),
  mcmc_forecast_truth_mae = c(0.10, 0.121, 0.11, 0.13, 0.09),
  vb_fit_check_loss_mean = 0.15,
  mcmc_fit_check_loss_mean = 0.149,
  vb_forecast_check_loss_mean = 0.16,
  mcmc_forecast_check_loss_mean = c(0.15, 0.161, 0.151, 0.152, 0.148),
  vb_fit_raw_crossing_pairs = 0L,
  mcmc_fit_raw_crossing_pairs = c(0L, 1L, 0L, 0L, 0L),
  vb_forecast_raw_crossing_pairs = 0L,
  mcmc_forecast_raw_crossing_pairs = c(0L, 3L, 0L, 0L, 0L),
  vb_fit_contract_crossing_pairs = 0L,
  mcmc_fit_contract_crossing_pairs = 0L,
  vb_forecast_contract_crossing_pairs = 0L,
  mcmc_forecast_contract_crossing_pairs = 0L,
  vb_fit_max_abs_adjustment = 0,
  mcmc_fit_max_abs_adjustment = c(0, 0.02, 0, 0, 0),
  vb_forecast_max_abs_adjustment = 0,
  mcmc_forecast_max_abs_adjustment = c(0, 0.03, 0, 0, 0),
  vb_mcmc_max_normalized_distance = c(0.10, 0.20, 0.30, 0.25, 0.12),
  max_chain_to_pooled_normalized_distance = c(0.05, 0.08, 0.07, 0.06, 0.04),
  vb_elapsed_seconds = 1,
  mcmc_elapsed_seconds = c(2, 3, 4, 5, 2),
  total_elapsed_seconds = c(3, 4, 5, 6, 3),
  stringsAsFactors = FALSE
)

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
  status_reason = ifelse(cases$mcmc_forecast_raw_crossing_pairs > 0, "raw quantiles crossed before monotone contract", "all Phase 122 gates passed"),
  stringsAsFactors = FALSE
)

metric_rows <- do.call(rbind, lapply(seq_len(nrow(cases)), function(ii) {
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
forecast_truth <- metric_rows[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "truth_mae", "truth_rmse", "truth_bias")]
forecast_check <- metric_rows[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "check_loss_mean", "n_scores")]
fit_truth <- forecast_truth
fit_check <- forecast_check
forecast_crps <- unique(metric_rows[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")])
forecast_crps$crps_grid_mean <- 0.2
forecast_crps$n_crps <- 20L
forecast_hit <- forecast_check
forecast_hit$hit_rate <- forecast_hit$tau
forecast_hit$hit_rate_error <- 0
forecast_hit$abs_hit_rate_error <- 0.01
forecast_hit <- forecast_hit[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure", "tau", "hit_rate", "n_scores", "hit_rate_error", "abs_hit_rate_error")]
forecast_interval <- unique(metric_rows[, c("scenario_id", "model_id", "display_label", "likelihood", "fit_structure")])
forecast_interval$lower_tau <- 0.05
forecast_interval$upper_tau <- 0.95
forecast_interval$nominal_coverage <- 0.90
forecast_interval$coverage <- 0.88
forecast_interval$interval_width_mean <- 1.0
forecast_interval$interval_score_mean <- 2.0
forecast_interval$n_intervals <- 20L
forecast_interval$coverage_error <- -0.02
forecast_interval$abs_coverage_error <- 0.02

simple_manifest_rows <- data.frame(
  artifact_label = "source",
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
empty_failures <- data.frame(
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
  ), file.path(phase122_dir, "run_config.csv")),
  phase121_source_manifest_verification = app_joint_qvp_write_csv(simple_manifest_rows, file.path(phase122_dir, "phase121_source_manifest_verification.csv")),
  fixture_source_manifest = app_joint_qvp_write_csv(simple_manifest_rows, file.path(phase122_dir, "fixture_source_manifest.csv")),
  case_winner_controls = app_joint_qvp_write_csv(cases[, c("case_id", "scenario_id", "source_model_id")], file.path(phase122_dir, "case_winner_controls.csv")),
  scenario_worker_failures = app_joint_qvp_write_csv(empty_failures, file.path(phase122_dir, "scenario_worker_failures.csv")),
  mcmc_case_summary = app_joint_qvp_write_csv(cases, file.path(phase122_dir, "mcmc_case_summary.csv")),
  mcmc_case_assessment = app_joint_qvp_write_csv(assessment, file.path(phase122_dir, "mcmc_case_assessment.csv")),
  forecast_truth_distance_summary = app_joint_qvp_write_csv(forecast_truth, file.path(phase122_dir, "forecast_truth_distance_summary.csv")),
  forecast_check_loss_summary = app_joint_qvp_write_csv(forecast_check, file.path(phase122_dir, "forecast_check_loss_summary.csv")),
  forecast_crps_grid_summary = app_joint_qvp_write_csv(forecast_crps, file.path(phase122_dir, "forecast_crps_grid_summary.csv")),
  forecast_hit_rate_summary = app_joint_qvp_write_csv(forecast_hit, file.path(phase122_dir, "forecast_hit_rate_summary.csv")),
  forecast_interval_summary = app_joint_qvp_write_csv(forecast_interval, file.path(phase122_dir, "forecast_interval_summary.csv")),
  fit_truth_distance_summary = app_joint_qvp_write_csv(fit_truth, file.path(phase122_dir, "fit_truth_distance_summary.csv")),
  fit_check_loss_summary = app_joint_qvp_write_csv(fit_check, file.path(phase122_dir, "fit_check_loss_summary.csv")),
  crossing_summary = app_joint_qvp_write_csv(data.frame(n_crossing_pairs = 0L), file.path(phase122_dir, "crossing_summary.csv")),
  raw_crossing_summary = app_joint_qvp_write_csv(data.frame(n_crossing_pairs = 3L), file.path(phase122_dir, "raw_crossing_summary.csv")),
  vb_convergence_audit = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, converged = TRUE, reached_max_iter = FALSE), file.path(phase122_dir, "vb_convergence_audit.csv")),
  objective_diagnostics = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, objective_status = "finite"), file.path(phase122_dir, "objective_diagnostics.csv")),
  mcmc_draw_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, block = "alpha", finite_draws = TRUE), file.path(phase122_dir, "mcmc_draw_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, max_normalized_distance = cases$vb_mcmc_max_normalized_distance), file.path(phase122_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, max_normalized_to_pooled = cases$max_chain_to_pooled_normalized_distance), file.path(phase122_dir, "chain_to_pooled_distance_summary.csv")),
  runtime_summary = app_joint_qvp_write_csv(data.frame(case_id = cases$case_id, elapsed_seconds = cases$total_elapsed_seconds), file.path(phase122_dir, "runtime_summary.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(phase122_dir, "provenance.csv")),
  readme = app_joint_qvp_write_csv(data.frame(note = "phase123 test"), file.path(phase122_dir, "README.md"))
)
invisible(app_joint_qdesn_write_manifest(paths, phase122_dir))
invisible(check_manifest(phase122_dir))

out_dir <- tempfile("joint_qdesn_phase123_")
result <- app_joint_qdesn_run_phase123_mcmc_article_freeze(
  out_dir = out_dir,
  phase122_dir = phase122_dir
)

manifest <- check_manifest(result$out_dir)
expected <- c(
  "run_config",
  "phase122_source_manifest_verification",
  "phase121_source_manifest_verification",
  "fixture_source_manifest",
  "health_check_summary",
  "article_gate_summary",
  "model_confirmation_summary",
  "case_confirmation_summary",
  "article_scope_matrix",
  "article_scope_by_model",
  "article_scope_decision",
  "raw_crossing_diagnostic_summary",
  "vb_mcmc_delta_summary",
  "chain_stability_summary",
  "article_candidate_model_table_csv",
  "article_candidate_case_table_csv",
  "article_candidate_gate_table_csv",
  "article_candidate_model_table_tex",
  "article_candidate_case_table_tex",
  "article_candidate_gate_table_tex",
  "article_promotion_recommendation",
  "article_integration_plan",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected))
gate <- utils::read.csv(file.path(result$out_dir, "article_gate_summary.csv"), stringsAsFactors = FALSE)
scope <- utils::read.csv(file.path(result$out_dir, "article_scope_decision.csv"), stringsAsFactors = FALSE)
rec <- utils::read.csv(file.path(result$out_dir, "article_promotion_recommendation.csv"), stringsAsFactors = FALSE)
raw <- utils::read.csv(file.path(result$out_dir, "raw_crossing_diagnostic_summary.csv"), stringsAsFactors = FALSE)

stopifnot(any(gate$gate == "raw_crossings" & gate$status == "review"))
stopifnot(any(gate$gate == "balanced_article_scope" & gate$status == "review"))
stopifnot(any(scope$audit_item == "balanced_four_model_by_scenario_comparison" & scope$status == "review"))
stopifnot(identical(rec$hard_implementation_gate[[1L]], "pass"))
stopifnot(grepl("needs_phase124", rec$balanced_four_model_table[[1L]], fixed = TRUE))
stopifnot(nrow(raw) == 1L)
stopifnot(file.exists(file.path(result$out_dir, "article_candidate_mcmc_model_table.tex")))
stopifnot(file.exists(file.path(result$out_dir, "article_candidate_mcmc_case_table.tex")))

cat("Joint QDESN Phase 123 MCMC article-candidate freeze test passed.\n")
